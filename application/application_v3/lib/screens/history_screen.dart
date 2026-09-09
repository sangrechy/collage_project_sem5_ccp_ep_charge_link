import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/history_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/historical_battery_chart.dart';
import '../widgets/historical_power_chart.dart';
import '../widgets/historical_temperature_chart.dart';
import '../widgets/status_badge.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryController>();
    final range = history.range;
    final points = history.points;
    final canGoNext = history.canGoNext;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CHARGING HISTORY'),
        actions: const [
          StatusBadge(),
          SizedBox(width: 16),
        ],
      ),
      body: history.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : RefreshIndicator(
              onRefresh: () => history.loadData(),
              color: AppColors.cyan,
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Day / Week Segmented Switcher
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      _RangeButton(
                        label: '1 Day (24h)',
                        selected: range == HistoryViewRange.day,
                        onTap: () => history.setRange(HistoryViewRange.day),
                      ),
                      _RangeButton(
                        label: '1 Week (7d)',
                        selected: range == HistoryViewRange.week,
                        onTap: () => history.setRange(HistoryViewRange.week),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Date Navigation Bar (< Prev Date Next >)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: history.previous,
                        icon: const Icon(Icons.chevron_left_rounded, color: AppColors.cyan, size: 20),
                        label: Text(
                          range == HistoryViewRange.day ? 'Prev Day' : 'Prev Week',
                          style: const TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600),
                        ),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                      Flexible(
                        child: Text(
                          history.dateRangeLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: canGoNext ? history.next : null,
                        label: Text(
                          range == HistoryViewRange.day ? 'Next Day' : 'Next Week',
                          style: TextStyle(
                            fontSize: 12,
                            color: canGoNext ? AppColors.cyan : AppColors.textMuted.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        icon: Icon(
                          Icons.chevron_right_rounded,
                          color: canGoNext ? AppColors.cyan : AppColors.textMuted.withValues(alpha: 0.5),
                          size: 20,
                        ),
                        iconAlignment: IconAlignment.end,
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Historical Battery Profile Chart
                HistoricalBatteryChart(
                  points: points,
                  range: range,
                  anchorDate: history.selectedDate,
                ),
                const SizedBox(height: 14),

                // 4. Historical Phone Temperature Profile Chart
                HistoricalTemperatureChart(
                  points: points,
                  range: range,
                  anchorDate: history.selectedDate,
                ),
                const SizedBox(height: 14),

                // 5. Historical Power Comparison Chart (Smart Box vs Phone Intake)
                HistoricalPowerChart(
                  points: points,
                  range: range,
                  anchorDate: history.selectedDate,
                  totalBoxWh: history.totalBoxEnergyWh,
                  totalPhoneWh: history.totalPhoneEnergyWh,
                  avgEfficiency: history.avgEfficiency,
                ),
                const SizedBox(height: 14),

                // 6. Detailed Records Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'DETAILED LOGS (${points.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'Auto-prunes >60d',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 7. Detailed Sample List
                if (points.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No telemetry logs recorded for this date range.',
                          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  )
                else
                  ...points.reversed.take(40).map((p) {
                    final timeStr = '${p.time.hour.toString().padLeft(2, '0')}:${p.time.minute.toString().padLeft(2, '0')}:${p.time.second.toString().padLeft(2, '0')}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  timeStr,
                                  style: AppTheme.mono(size: 12, color: AppColors.cyan, weight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: p.isCharging ? AppColors.green.withValues(alpha: 0.15) : AppColors.surfaceRaised,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: p.isCharging ? AppColors.green : AppColors.border, width: 0.8),
                                  ),
                                  child: Text(
                                    p.isCharging ? 'CHARGING' : 'IDLE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: p.isCharging ? AppColors.green : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Icon(Icons.thermostat_rounded, size: 14, color: const Color(0xFFFF7043)),
                                const SizedBox(width: 2),
                                Text(
                                  '${p.temperatureC.toStringAsFixed(1)}°C',
                                  style: AppTheme.mono(size: 11, weight: FontWeight.w600, color: const Color(0xFFFF7043)),
                                ),
                                const SizedBox(width: 10),
                                Icon(Icons.battery_std_rounded, size: 14, color: AppColors.green),
                                const SizedBox(width: 2),
                                Text(
                                  '${p.batteryPercentage}%',
                                  style: AppTheme.mono(size: 12, weight: FontWeight.w700, color: AppColors.green),
                                ),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Smart Box Output', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${p.boxVoltage.toStringAsFixed(2)}V · ${p.boxCurrent.toStringAsFixed(2)}A · ${p.boxPower.toStringAsFixed(1)}W',
                                      style: AppTheme.mono(size: 11, color: AppColors.cyan),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('Phone Intake', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${p.phoneVoltage.toStringAsFixed(2)}V · ${p.phoneCurrent.toStringAsFixed(2)}A · ${p.phonePower.toStringAsFixed(1)}W',
                                      style: AppTheme.mono(size: 11, color: AppColors.amber),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 24),
              ],
            ),
          ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.cyan : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
