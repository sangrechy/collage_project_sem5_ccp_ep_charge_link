import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/telemetry_controller.dart';
import '../theme/app_theme.dart';

class LivePerformanceChart extends StatelessWidget {
  const LivePerformanceChart({super.key});

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<TelemetryController>();
    final metric = telemetry.selectedMetric;
    final boxPoints = telemetry.currentBoxPoints;
    final phonePoints = telemetry.currentPhonePoints;
    final unit = telemetry.metricUnit;

    final boxVal = telemetry.latestBoxValue;
    final phoneVal = telemetry.latestPhoneValue;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title & Segment Switcher
            Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 20, color: AppColors.cyan),
                const SizedBox(width: 8),
                const Text(
                  'LIVE PERFORMANCE COMPARISON',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Segmented Metric Selector
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  _SegmentButton(
                    label: 'Voltage (V)',
                    selected: metric == ChartMetric.voltage,
                    activeColor: AppColors.cyan,
                    onTap: () => telemetry.selectMetric(ChartMetric.voltage),
                  ),
                  _SegmentButton(
                    label: 'Current (A)',
                    selected: metric == ChartMetric.current,
                    activeColor: AppColors.amber,
                    onTap: () => telemetry.selectMetric(ChartMetric.current),
                  ),
                  _SegmentButton(
                    label: 'Power (W)',
                    selected: metric == ChartMetric.power,
                    activeColor: AppColors.green,
                    onTap: () => telemetry.selectMetric(ChartMetric.power),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Dual Readout Legend (Smart Box vs Phone Intake)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Smart Box Legend
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.cyan,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Smart Box: ',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        boxPoints.isNotEmpty ? '${boxVal.toStringAsFixed(2)} $unit' : '-- $unit',
                        style: AppTheme.mono(size: 13, weight: FontWeight.w700, color: AppColors.cyan),
                      ),
                    ],
                  ),
                  // Phone Intake Legend
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Phone Intake: ',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        phonePoints.isNotEmpty
                            ? (metric != ChartMetric.voltage && phoneVal == 0.0
                                ? '0.00 $unit (Unplugged)'
                                : '${phoneVal.toStringAsFixed(2)} $unit')
                            : '-- $unit',
                        style: AppTheme.mono(size: 13, weight: FontWeight.w700, color: AppColors.amber),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Comparative Efficiency / Loss Indicator (only when both are actively charging)
            if (metric == ChartMetric.power && boxVal > 0.2 && phoneVal > 0.2)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'Cable Loss: ',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                    Text(
                      '-${telemetry.powerLoss.toStringAsFixed(2)} W',
                      style: AppTheme.mono(size: 11, weight: FontWeight.w600, color: AppColors.red),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Efficiency: ',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                    Text(
                      '${telemetry.efficiencyPercent.toStringAsFixed(1)}%',
                      style: AppTheme.mono(size: 11, weight: FontWeight.w600, color: AppColors.green),
                    ),
                  ],
                ),
              ),

            // Graph Area with 2 Curves
            SizedBox(
              height: 165,
              child: boxPoints.length < 2
                  ? const Center(
                      child: Text(
                        'Awaiting live BLE telemetry…',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _calcInterval(metric),
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: AppColors.border.withValues(alpha: 0.4),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: const FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          // 1. Smart Box Line (Cyan)
                          LineChartBarData(
                            spots: boxPoints.map((p) => FlSpot(p.x, p.y)).toList(),
                            isCurved: true,
                            curveSmoothness: 0.2,
                            color: AppColors.cyan,
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.cyan.withValues(alpha: 0.08),
                            ),
                          ),
                          // 2. Mobile Phone Line (Amber)
                          LineChartBarData(
                            spots: phonePoints.map((p) => FlSpot(p.x, p.y)).toList(),
                            isCurved: true,
                            curveSmoothness: 0.2,
                            color: AppColors.amber,
                            barWidth: 2.2,
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

  double _calcInterval(ChartMetric metric) {
    switch (metric) {
      case ChartMetric.voltage:
        return 2.0;
      case ChartMetric.current:
        return 0.5;
      case ChartMetric.power:
        return 5.0;
    }
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? activeColor : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
