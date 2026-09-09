import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/telemetry_controller.dart';
import '../common/section_card.dart';

class EnergyCard extends StatelessWidget {
  const EnergyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sample = context.watch<TelemetryController>().latest;

    return SectionCard(
      title: 'Energy',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  sample == null ? '—' : '${sample.sessionEnergyWh.toStringAsFixed(2)} Wh',
                  style: AppTheme.telemetry(size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  sample == null ? '—' : '${sample.totalEnergyWh.toStringAsFixed(2)} Wh',
                  style: AppTheme.telemetry(size: 20, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
