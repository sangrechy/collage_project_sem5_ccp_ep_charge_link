import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/telemetry_controller.dart';
import '../theme/app_theme.dart';

class LivePowerCard extends StatelessWidget {
  const LivePowerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<TelemetryController>();
    final sample = telemetry.latest;

    final voltageStr = sample != null ? sample.voltageV.toStringAsFixed(2) : '0.00';
    final currentStr = sample != null ? sample.currentA.toStringAsFixed(2) : '0.00';
    final powerStr = sample != null ? sample.powerW.toStringAsFixed(2) : '0.00';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, size: 20, color: AppColors.amber),
                const SizedBox(width: 8),
                Text(
                  'LIVE READINGS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ReadingColumn(
                  label: 'VOLTAGE',
                  value: voltageStr,
                  unit: 'V',
                  color: AppColors.cyan,
                ),
                Container(width: 1, height: 40, color: AppColors.border),
                _ReadingColumn(
                  label: 'CURRENT',
                  value: currentStr,
                  unit: 'A',
                  color: AppColors.amber,
                ),
                Container(width: 1, height: 40, color: AppColors.border),
                _ReadingColumn(
                  label: 'POWER',
                  value: powerStr,
                  unit: 'W',
                  color: AppColors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingColumn extends StatelessWidget {
  const _ReadingColumn({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: AppTheme.mono(size: 22, weight: FontWeight.w800, color: color),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ],
    );
  }
}
