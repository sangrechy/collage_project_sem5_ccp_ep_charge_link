import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/battery_controller.dart';
import '../controllers/charging_controller.dart';
import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';

class SmartAutomationCard extends StatelessWidget {
  const SmartAutomationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final charging = context.watch<ChargingController>();
    final battery = context.watch<BatteryController>();
    final settings = context.watch<SettingsController>();

    final target = charging.chargingLimit;
    final current = battery.percentage ?? 0;
    final isCompleted = charging.autoStopCompleted;

    if (isCompleted) {
      return Card(
        color: AppColors.green.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.green, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.green, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'CHARGING COMPLETE',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.green,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    onPressed: charging.dismissAutoStopAlert,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Battery reached the $target% limit.',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Charging was stopped automatically to protect battery health.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy, size: 20, color: AppColors.cyan),
                const SizedBox(width: 8),
                const Text(
                  'SMART CHARGING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  settings.stopAtLimit ? 'ACTIVE' : 'OFF',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: settings.stopAtLimit ? AppColors.cyan : AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Target Limit', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                Text('$target%', style: AppTheme.mono(size: 14, weight: FontWeight.w700, color: AppColors.cyan)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Current Battery', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                Text('$current%', style: AppTheme.mono(size: 14, weight: FontWeight.w700, color: AppColors.amber)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      settings.stopAtLimit
                          ? 'Charging will stop automatically when battery reaches $target%.'
                          : 'Automatic stop is disabled in settings.',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
