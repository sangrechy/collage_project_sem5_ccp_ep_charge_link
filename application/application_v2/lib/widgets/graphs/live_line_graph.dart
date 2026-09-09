import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../controllers/telemetry_controller.dart';
import '../common/section_card.dart';

/// A single rolling line graph fed by a bounded [GraphPoint] window.
/// Used identically by the voltage, current, and power graphs — only the
/// title, unit, color, and data selector differ.
class LiveLineGraph extends StatelessWidget {
  const LiveLineGraph({
    super.key,
    required this.title,
    required this.unit,
    required this.points,
    required this.color,
  });

  final String title;
  final String unit;
  final List<GraphPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hasData = points.length >= 2;

    return SectionCard(
      title: title,
      trailing: Text(
        unit,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      child: SizedBox(
        height: 160,
        child: hasData ? _chart() : _emptyState(context),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Text(
        'Waiting for live data…',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _chart() {
    final minX = points.first.x;
    final maxX = points.last.x;
    final ys = points.map((p) => p.y);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final niceMaxY = maxY <= 0 ? 1.0 : maxY * 1.25;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 0,
        maxY: niceMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: niceMaxY / 4,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.hairline,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: niceMaxY / 4,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(value < 10 ? 1 : 0),
                style: AppTheme.telemetry(size: 10, color: AppColors.textMuted),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: points.map((p) => FlSpot(p.x, p.y)).toList(),
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
