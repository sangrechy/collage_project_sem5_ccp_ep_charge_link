import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/battery_controller.dart';
import '../../controllers/charging_controller.dart';
import '../common/section_card.dart';

class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final battery = context.watch<BatteryController>();
    final charging = context.watch<ChargingController>();

    return SectionCard(
      title: 'Phone battery',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Percentage', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  battery.percentage == null ? 'Not available' : '${battery.percentage}%',
                  style: AppTheme.telemetry(size: 22),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Charging status', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                _StatePill(
                  label: battery.isCharging == null
                      ? 'Not available'
                      : (battery.isCharging! ? 'Charging' : 'Not charging'),
                  color: battery.isCharging == true ? AppColors.copper : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Charging path + actual-charging state — kept as a distinct card because
/// these two states are genuinely different things (see apis.txt) and
/// collapsing them into one label would hide that.
class ChargingStateCard extends StatelessWidget {
  const ChargingStateCard({super.key});

  @override
  Widget build(BuildContext context) {
    final charging = context.watch<ChargingController>();

    return SectionCard(
      title: 'Device state',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Charging path', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                _StatePill(
                  label: charging.pathEnabled ? 'Enabled' : 'Disabled',
                  color: charging.pathEnabled ? AppColors.teal : AppColors.textMuted,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Actual charging', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                _StatePill(
                  label: charging.charging ? 'Charging' : 'Not charging',
                  color: charging.charging ? AppColors.copper : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}
