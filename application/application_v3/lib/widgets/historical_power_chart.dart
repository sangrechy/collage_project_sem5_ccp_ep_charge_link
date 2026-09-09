import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../controllers/history_controller.dart';
import '../services/storage/history_storage_service.dart';
import '../theme/app_theme.dart';

class HistoricalPowerChart extends StatelessWidget {
  const HistoricalPowerChart({
    super.key,
    required this.points,
    required this.range,
    required this.anchorDate,
    required this.totalBoxWh,
    required this.totalPhoneWh,
    required this.avgEfficiency,
  });

  final List<HistoricalDataPoint> points;
  final HistoryViewRange range;
  final DateTime anchorDate;
  final double totalBoxWh;
  final double totalPhoneWh;
  final double avgEfficiency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.bolt_rounded, size: 20, color: AppColors.cyan),
                const SizedBox(width: 8),
                const Text(
                  'HISTORICAL POWER COMPARISON',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Dual Series Legend & Energy Totals
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Text('Box Output: ', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text('${totalBoxWh.toStringAsFixed(1)} Wh', style: AppTheme.mono(size: 11, color: AppColors.cyan, weight: FontWeight.w700)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Text('Phone Absorbed: ', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text('${totalPhoneWh.toStringAsFixed(1)} Wh', style: AppTheme.mono(size: 11, color: AppColors.amber, weight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Average Transmission Efficiency: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      Text('${avgEfficiency.toStringAsFixed(1)}%', style: AppTheme.mono(size: 11, color: AppColors.green, weight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Chart Canvas
            SizedBox(
              height: 160,
              child: points.isEmpty
                  ? const Center(
                      child: Text(
                        'No power records for this period.',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: range == HistoryViewRange.day ? 24.0 : 6.0,
                        minY: 0,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 5.0,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: AppColors.border.withValues(alpha: 0.35),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: 5.0,
                              getTitlesWidget: (val, meta) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '${val.toInt()}W',
                                  textAlign: TextAlign.right,
                                  style: AppTheme.mono(size: 9, color: AppColors.textMuted),
                                ),
                              ),
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              interval: range == HistoryViewRange.day ? 6.0 : 1.0,
                              getTitlesWidget: (val, meta) => _bottomTitleWidget(val),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          // 1. Smart Box Power (Cyan)
                          LineChartBarData(
                            spots: _generateSpots(true),
                            isCurved: true,
                            curveSmoothness: 0.15,
                            color: AppColors.cyan,
                            barWidth: 2.2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.cyan.withValues(alpha: 0.08),
                            ),
                          ),
                          // 2. Phone Intake Power (Amber)
                          LineChartBarData(
                            spots: _generateSpots(false),
                            isCurved: true,
                            curveSmoothness: 0.15,
                            color: AppColors.amber,
                            barWidth: 2.0,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.amber.withValues(alpha: 0.06),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _generateSpots(bool isBox) {
    if (points.isEmpty) return [];

    if (range == HistoryViewRange.day) {
      return points.map((p) {
        final hourVal = p.time.hour + (p.time.minute / 60.0);
        final val = isBox ? p.boxPower : p.phonePower;
        return FlSpot(hourVal, val);
      }).toList();
    } else {
      final weekStart = DateTime(anchorDate.year, anchorDate.month, anchorDate.day).subtract(const Duration(days: 6));
      return points.map((p) {
        final diffDays = p.time.difference(weekStart).inMilliseconds / (86400.0 * 1000.0);
        final val = isBox ? p.boxPower : p.phonePower;
        return FlSpot(diffDays.clamp(0.0, 6.0), val);
      }).toList();
    }
  }

  Widget _bottomTitleWidget(double val) {
    if (range == HistoryViewRange.day) {
      final hour = val.toInt();
      if (hour % 6 == 0 && hour <= 24) {
        return Text(
          '${hour.toString().padLeft(2, '0')}:00',
          style: AppTheme.mono(size: 9, color: AppColors.textMuted),
        );
      }
      return const SizedBox.shrink();
    } else {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final weekStart = anchorDate.subtract(const Duration(days: 6));
      final dayIndex = val.toInt();
      if (dayIndex >= 0 && dayIndex <= 6) {
        final dt = weekStart.add(Duration(days: dayIndex));
        final label = days[dt.weekday - 1];
        return Text(
          label,
          style: AppTheme.mono(size: 10, color: AppColors.textMuted),
        );
      }
      return const SizedBox.shrink();
    }
  }
}
