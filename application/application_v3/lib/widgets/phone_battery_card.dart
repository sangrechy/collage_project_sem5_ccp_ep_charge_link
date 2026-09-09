import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/battery_controller.dart';
import '../controllers/telemetry_controller.dart';
import '../theme/app_theme.dart';

class PhoneBatteryCard extends StatelessWidget {
  const PhoneBatteryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final battery = context.watch<BatteryController>();
    final pct = battery.percentage ?? 0;
    final isCharging = battery.isCharging ?? false;

    Color stateColor;
    if (pct <= 20) {
      stateColor = AppColors.red;
    } else if (isCharging) {
      stateColor = AppColors.green;
    } else {
      stateColor = AppColors.cyan;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.battery_charging_full, size: 20, color: AppColors.cyan),
                const SizedBox(width: 8),
                Text(
                  'PHONE BATTERY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                if (isCharging)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt, size: 14, color: AppColors.green),
                        SizedBox(width: 2),
                        Text(
                          'Charging',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                battery.percentage != null ? '$pct%' : '--%',
                style: AppTheme.mono(size: 44, weight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: LinearProgressIndicator(
                  value: pct / 100.0,
                  backgroundColor: AppColors.surfaceRaised,
                  valueColor: AlwaysStoppedAnimation<Color>(stateColor),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Builder(
                builder: (context) {
                  final temp = context.watch<TelemetryController>().latestPhone?.temperatureC;
                  final tempStr = temp != null ? ' • ${temp.toStringAsFixed(1)}°C' : '';
                  return Text(
                    isCharging ? 'Charging$tempStr • Battery Healthy' : 'Discharging$tempStr • Battery Healthy',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ),

          ],
        ),
      ),
    );
  }
}
