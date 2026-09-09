import 'dart:async';
import 'dart:math';

import '../../models/charging_sample.dart';
import '../../models/device_status.dart';
import '../../models/energy_data.dart';
import '../../models/history_sample.dart';
import '../../models/live_data_sample.dart';
import '../../models/power_data.dart';
import '../../models/temperature_data.dart';
import 'esp32_service.dart';

/// Development/testing double for [Esp32Service]. NEVER used as the
/// default in production — see `charge_link_repository.dart`, which wires
/// up [Esp32BleService] by default and only swaps this in when explicitly
/// constructed with `useMock: true`.
class MockEsp32Service implements Esp32Service {
  MockEsp32Service();

  bool _connected = false;
  bool _charging = false;
  bool _relayState = false;
  int _chargingLimit = 80;
  double _sessionEnergyWh = 0;
  double _totalEnergyWh = 12.4;
  final _rand = Random();
  Timer? _liveTimer;

  final StreamController<BleConnectionState> _stateController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<LiveDataSample> _liveDataController =
      StreamController<LiveDataSample>.broadcast();

  @override
  Stream<BleConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<LiveDataSample> get liveDataStream => _liveDataController.stream;

  @override
  Future<void> startScan() async {
    _stateController.add(BleConnectionState.scanning);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _stateController.add(BleConnectionState.deviceFound);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect() async {
    _stateController.add(BleConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _connected = true;
    _stateController.add(BleConnectionState.connected);

    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final voltage = _charging ? 9.0 + _rand.nextDouble() * 0.3 : 0.0;
      final current = _charging ? 1.6 + _rand.nextDouble() * 0.5 : 0.0;
      final power = voltage * current;
      if (_charging) _sessionEnergyWh += power / 3600;

      _liveDataController.add(
        LiveDataSample(
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          voltageV: voltage,
          currentA: current,
          powerW: power,
          charging: _charging && current > 0.05,
          pathEnabled: _relayState,
          chargingLimit: _chargingLimit,
          ina219Available: true,
          sessionEnergyWh: _sessionEnergyWh,
          totalEnergyWh: _totalEnergyWh + _sessionEnergyWh,
          receivedAt: DateTime.now(),
        ),
      );
    });
  }

  @override
  Future<void> disconnect() async {
    _liveTimer?.cancel();
    _connected = false;
    _charging = false;
    _relayState = false;
    _stateController.add(BleConnectionState.disconnected);
  }

  void _ensureConnected() {
    if (!_connected) throw StateError('ESP32 is not connected.');
  }

  @override
  Future<DeviceStatus> getDeviceStatus() async {
    _ensureConnected();
    return DeviceStatus(
      connected: _connected,
      charging: _charging,
      relayState: _relayState,
      deviceName: 'CHARGE LINK',
      chargingLimit: _chargingLimit,
      ina219Available: true,
    );
  }

  @override
  Future<PowerData> getPowerData() async {
    _ensureConnected();
    final voltage = _charging ? 9.0 : 0.0;
    final current = _charging ? 2.0 : 0.0;
    return PowerData(
      voltage: voltage,
      current: current,
      power: voltage * current,
      energyWh: _sessionEnergyWh,
    );
  }

  @override
  Future<bool> getChargingState() async {
    _ensureConnected();
    return _charging;
  }

  @override
  Future<int> getChargingLimit() async {
    _ensureConnected();
    return _chargingLimit;
  }

  @override
  Future<void> setChargingLimit(int percentage) async {
    _ensureConnected();
    if (percentage < 0 || percentage > 100) {
      throw ArgumentError('Charging limit must be between 0 and 100.');
    }
    _chargingLimit = percentage;
  }

  @override
  Future<void> startCharging() async {
    _ensureConnected();
    _relayState = true;
    _charging = true;
  }

  @override
  Future<void> stopCharging() async {
    _ensureConnected();
    _relayState = false;
    _charging = false;
  }

  @override
  Future<ChargingSample> getChargingSample() async {
    _ensureConnected();
    final voltage = _charging ? 9.0 : 0.0;
    final current = _charging ? 2.0 : 0.0;
    return ChargingSample(
      timestamp: DateTime.now(),
      sessionId: 'MOCK-SESSION',
      voltage: voltage,
      current: current,
      power: voltage * current,
      energyWh: _sessionEnergyWh,
      charging: _charging,
    );
  }

  @override
  Future<TemperatureData> getTemperature() async {
    _ensureConnected();
    return TemperatureData(
      temperatureCelsius: _charging ? 32.5 : null,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<EnergyData> getEnergyData() async {
    _ensureConnected();
    return EnergyData(
      sessionEnergyWh: _sessionEnergyWh,
      totalEnergyWh: _totalEnergyWh + _sessionEnergyWh,
    );
  }

  @override
  Future<List<HistorySample>> getHistory({int limit = 100}) async {
    _ensureConnected();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return List.generate(min(limit, 30), (i) {
      final t = now - (30 - i) * 10;
      return HistorySample(
        timestamp: t,
        sessionId: 'MOCK-SESSION',
        voltageV: 9.0,
        currentA: 1.8,
        powerW: 16.2,
        sessionEnergyWh: i * 0.05,
        charging: true,
        pathEnabled: true,
      );
    });
  }

  @override
  Future<void> dispose() async {
    _liveTimer?.cancel();
    await _stateController.close();
    await _liveDataController.close();
  }
}
