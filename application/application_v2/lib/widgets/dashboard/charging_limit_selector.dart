import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/charging_controller.dart';
import '../common/section_card.dart';

class ChargingLimitSelector extends StatelessWidget {
  const ChargingLimitSelector({super.key});

  static const _presets = [50, 60, 70, 80, 85, 90, 95, 100];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChargingController>();

    return SectionCard(
      title: 'Charging limit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${c.chargingLimit}', style: AppTheme.telemetry(size: 32, color: AppColors.copper)),
              Text('%', style: AppTheme.telemetry(size: 18, color: AppColors.copper)),
            ],
          ),
          Slider(
            value: c.chargingLimit.toDouble(),
            min: 50,
            max: 100,
            divisions: 10,
            activeColor: AppColors.copper,
            inactiveColor: AppColors.hairline,
            label: '${c.chargingLimit}%',
            onChanged: (v) => c.setLimit(v.round()),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((p) {
              final selected = p == c.chargingLimit;
              return ChoiceChip(
                label: Text('$p%'),
                selected: selected,
                onSelected: (_) => c.setLimit(p),
                selectedColor: AppColors.copper.withOpacity(0.2),
                backgroundColor: AppColors.surfaceRaised,
                side: BorderSide(
                  color: selected ? AppColors.copper : AppColors.hairline,
                ),
                labelStyle: TextStyle(
                  color: selected ? AppColors.copper : AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
