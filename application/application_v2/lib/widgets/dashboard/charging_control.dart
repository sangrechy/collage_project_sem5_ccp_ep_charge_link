import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/charging_controller.dart';

class ChargingControl extends StatelessWidget {
  const ChargingControl({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChargingController>();
    final isSending = c.status == CommandStatus.sending;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: c.pathEnabled
              ? OutlinedButton(
                  onPressed: isSending ? null : () => c.stop(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    foregroundColor: AppColors.danger,
                  ),
                  child: isSending
                      ? const _Spinner(color: AppColors.danger)
                      : const Text('STOP CHARGING'),
                )
              : ElevatedButton(
                  onPressed: isSending ? null : () => c.start(),
                  child: isSending
                      ? const _Spinner(color: Color(0xFF1A1204))
                      : const Text('START CHARGING'),
                ),
        ),
        if (c.lastError != null) ...[
          const SizedBox(height: 10),
          Text(
            c.lastError!,
            style: const TextStyle(color: AppColors.danger, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
        if (c.statusMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.teal, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.statusMessage!,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                  onPressed: c.clearStatusMessage,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
    );
  }
}
