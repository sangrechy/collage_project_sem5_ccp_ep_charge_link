import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/charging_controller.dart';
import '../theme/app_theme.dart';

class ChargingControlCard extends StatelessWidget {
  const ChargingControlCard({super.key});

  @override
  Widget build(BuildContext context) {
    final charging = context.watch<ChargingController>();
    final isSending = charging.status == CommandStatus.sending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.power_settings_new, size: 20, color: AppColors.cyan),
                const SizedBox(width: 8),
                const Text(
                  'CHARGING STATUS & CONTROL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                if (isSending)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Status row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: charging.charging ? AppColors.green : AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        charging.charging ? 'Charging Active' : 'Charging Idle',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: charging.charging ? AppColors.green : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'Path: ',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      Text(
                        charging.pathEnabled ? 'ENABLED' : 'DISABLED',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: charging.pathEnabled ? AppColors.cyan : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isSending || charging.pathEnabled ? null : charging.start,
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: const Text('START'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppColors.surfaceRaised,
                      disabledForegroundColor: AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isSending || !charging.pathEnabled ? null : charging.stop,
                    icon: const Icon(Icons.stop, size: 20),
                    label: const Text('STOP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceRaised,
                      disabledForegroundColor: AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ),
            if (charging.lastError != null) ...[
              const SizedBox(height: 10),
              Text(
                charging.lastError!,
                style: const TextStyle(fontSize: 12, color: AppColors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
