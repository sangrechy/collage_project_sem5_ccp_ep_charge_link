import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/battery_controller.dart';
import '../../controllers/charging_controller.dart';
import '../../controllers/connection_controller.dart';
import '../../controllers/telemetry_controller.dart';
import '../../services/ble/esp32_service.dart';
import '../../widgets/connection/connection_status_widget.dart';
import '../../widgets/dashboard/battery_card.dart';
import '../../widgets/dashboard/charging_control.dart';
import '../../widgets/dashboard/charging_limit_selector.dart';
import '../../widgets/dashboard/energy_card.dart';
import '../../widgets/dashboard/power_status_card.dart';
import '../../widgets/graphs/current_graph.dart';
import '../../widgets/graphs/power_graph.dart';
import '../../widgets/graphs/voltage_graph.dart';
import '../connection/connection_screen.dart';
import '../history/history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TelemetryController _telemetry;
  late final BatteryController _battery;
  late final ChargingController _charging;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    _telemetry = context.read<TelemetryController>();
    _battery = context.read<BatteryController>();
    _charging = context.read<ChargingController>();

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
    _charging.evaluateAutoStop(_battery.percentage);
  }

  @override
  void dispose() {
    _telemetry.removeListener(_onTelemetry);
    _battery.removeListener(_onBattery);
    super.dispose();
  }

  void _maybeReturnToConnection(BleConnectionState state) {
    if (state != BleConnectionState.connected && !_navigatedAway) {
      _navigatedAway = true;
      _telemetry.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ConnectionScreen()),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    _maybeReturnToConnection(connection.state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CHARGE LINK'),
        centerTitle: false,
        actions: [
          const ConnectionStatusWidget(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Charging history',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _charging.refreshFromDevice();
          await _battery.refreshNow();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            BatteryCard(),
            SizedBox(height: 12),
            ChargingStateCard(),
            SizedBox(height: 12),
            PowerStatusCard(),
            SizedBox(height: 12),
            EnergyCard(),
            SizedBox(height: 16),
            ChargingControl(),
            SizedBox(height: 16),
            ChargingLimitSelector(),
            SizedBox(height: 16),
            VoltageGraph(),
            SizedBox(height: 12),
            CurrentGraph(),
            SizedBox(height: 12),
            PowerGraph(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
