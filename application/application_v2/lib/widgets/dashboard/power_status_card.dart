import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/telemetry_controller.dart';
import '../common/live_pulse.dart';
import '../common/section_card.dart';

class PowerStatusCard extends StatelessWidget {
  const PowerStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<TelemetryController>();
    final sample = telemetry.latest;

    return SectionCard(
      title: 'Power status',
      trailing: LivePulse(active: sample != null),
      child: Row(
        children: [
          Expanded(
            child: _Reading(
              label: 'Voltage',
              value: sample == null ? '—' : sample.voltageV.toStringAsFixed(2),
              unit: 'V',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Reading(
              label: 'Current',
              value: sample == null ? '—' : sample.currentA.toStringAsFixed(2),
              unit: 'A',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Reading(
              label: 'Power',
              value: sample == null ? '—' : sample.powerW.toStringAsFixed(1),
              unit: 'W',
            ),
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(text: value, style: AppTheme.telemetry(size: 22)),
              TextSpan(
                text: ' $unit',
                style: AppTheme.telemetry(
                  size: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
