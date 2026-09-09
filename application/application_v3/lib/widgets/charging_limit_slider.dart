import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/charging_controller.dart';
import '../theme/app_theme.dart';

class ChargingLimitSlider extends StatelessWidget {
  const ChargingLimitSlider({super.key});

  @override
  Widget build(BuildContext context) {
    final charging = context.watch<ChargingController>();
    final limit = charging.chargingLimit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, size: 20, color: AppColors.amber),
                    const SizedBox(width: 8),
                    const Text(
                      'CHARGING LIMIT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$limit%',
                  style: AppTheme.mono(size: 20, weight: FontWeight.w800, color: AppColors.amber),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.amber,
                inactiveTrackColor: AppColors.surfaceRaised,
                thumbColor: AppColors.amber,
                overlayColor: AppColors.amber.withValues(alpha: 0.2),
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: limit.toDouble().clamp(50.0, 100.0),
                min: 50,
                max: 100,
                divisions: 10,
                onChanged: (val) {
                  charging.setLimit(val.round());
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('50% (Storage)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('80% (Recommended)', style: TextStyle(fontSize: 11, color: AppColors.amber)),
                Text('100% (Full)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
