import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../controllers/history_controller.dart';
import '../services/storage/history_storage_service.dart';
import '../theme/app_theme.dart';

class HistoricalTemperatureChart extends StatelessWidget {
  const HistoricalTemperatureChart({
    super.key,
    required this.points,
    required this.range,
    required this.anchorDate,
  });

  final List<HistoricalDataPoint> points;
  final HistoryViewRange range;
  final DateTime anchorDate;

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
                const Icon(Icons.thermostat_rounded, size: 20, color: Color(0xFFFF7043)),
                const SizedBox(width: 8),
                const Text(
                  'PHONE TEMPERATURE PROFILE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                if (points.isNotEmpty)
                  Text(
                    '${points.last.temperatureC.toStringAsFixed(1)}°C',
                    style: AppTheme.mono(size: 14, weight: FontWeight.w700, color: const Color(0xFFFF7043)),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Stat Summary Chips
            if (points.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatBadge(
                    label: 'MIN',
                    value: '${points.map((p) => p.temperatureC).reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}°C',
                    color: AppColors.cyan,
                  ),
                  _StatBadge(
                    label: 'MAX',
                    value: '${points.map((p) => p.temperatureC).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}°C',
                    color: AppColors.amber,
                  ),
                  _StatBadge(
                    label: 'WARM LIMIT',
                    value: '40.0°C',
                    color: const Color(0xFFFF7043),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Chart Canvas
            SizedBox(
              height: 160,
              child: points.isEmpty
                  ? const Center(
                      child: Text(
                        'No temperature records for this period.',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: range == HistoryViewRange.day ? 24.0 : 6.0,
                        minY: 20,
                        maxY: 50,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 10,
                          getDrawingHorizontalLine: (val) => FlLine(
                            color: val == 40
                                ? const Color(0xFFFF7043).withValues(alpha: 0.35)
                                : AppColors.border.withValues(alpha: 0.35),
                            strokeWidth: val == 40 ? 1.5 : 1,
                            dashArray: val == 40 ? [4, 4] : null,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              interval: 10,
                              getTitlesWidget: (val, meta) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '${val.toInt()}°C',
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
                          LineChartBarData(
                            spots: _generateSpots(),
                            isCurved: true,
                            curveSmoothness: 0.15,
                            color: const Color(0xFFFF7043),
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: const Color(0xFFFF7043).withValues(alpha: 0.12),
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

  List<FlSpot> _generateSpots() {
    if (points.isEmpty) return [];

    if (range == HistoryViewRange.day) {
      return points.map((p) {
        final hourVal = p.time.hour + (p.time.minute / 60.0);
        return FlSpot(hourVal, p.temperatureC);
      }).toList();
    } else {
      final weekStart = DateTime(anchorDate.year, anchorDate.month, anchorDate.day).subtract(const Duration(days: 6));
      return points.map((p) {
        final diffDays = p.time.difference(weekStart).inMilliseconds / (86400.0 * 1000.0);
        return FlSpot(diffDays.clamp(0.0, 6.0), p.temperatureC);
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

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: AppTheme.mono(size: 11, color: color, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
