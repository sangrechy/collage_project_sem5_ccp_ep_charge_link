import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/battery_controller.dart';
import '../controllers/charging_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/telemetry_controller.dart';
import '../widgets/charging_control_card.dart';
import '../widgets/charging_limit_slider.dart';
import '../widgets/live_performance_chart.dart';
import '../widgets/live_power_card.dart';
import '../widgets/phone_battery_card.dart';
import '../widgets/smart_automation_card.dart';
import '../widgets/status_badge.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final TelemetryController _telemetry;
  late final BatteryController _battery;
  late final ChargingController _charging;
  late final SettingsController _settings;

  @override
  void initState() {
    super.initState();
    _telemetry = context.read<TelemetryController>();
    _battery = context.read<BatteryController>();
    _charging = context.read<ChargingController>();
    _settings = context.read<SettingsController>();

    _charging.refreshFromDevice();
    _telemetry.addListener(_onTelemetry);
    _battery.addListener(_onBattery);
  }

  void _onTelemetry() {
    final sample = _telemetry.latest;
    if (sample == null) return;
    _charging.updateFromLiveSample(
      pathEnabled: sample.pathEnabled,
      charging: sample.charging,
      chargingLimit: sample.chargingLimit,
    );
  }

  void _onBattery() {
    _charging.evaluateAutoStop(
      batteryPercentage: _battery.percentage,
      autoStopEnabled: _settings.stopAtLimit,
    );
  }

  @override
  void dispose() {
    _telemetry.removeListener(_onTelemetry);
    _battery.removeListener(_onBattery);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CHARGE LINK'),
        actions: const [
          StatusBadge(),
          SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _charging.refreshFromDevice();
          await _battery.refreshNow();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: const [
            PhoneBatteryCard(),
            SizedBox(height: 12),
            LivePowerCard(),
            SizedBox(height: 12),
            LivePerformanceChart(),
            SizedBox(height: 12),
            ChargingControlCard(),
            SizedBox(height: 12),
            ChargingLimitSlider(),
            SizedBox(height: 12),
            SmartAutomationCard(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
