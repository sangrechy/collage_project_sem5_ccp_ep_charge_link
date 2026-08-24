import 'dart:async';

import '../../models/charging_sample.dart';
import '../../models/device_status.dart';
import '../../models/energy_data.dart';
import '../../models/power_data.dart';
import '../../models/temperature_data.dart';
import 'esp32_service.dart';

class MockEsp32Service implements Esp32Service {
  MockEsp32Service();

  bool _connected = false;
  bool _charging = false;
  bool _relayState = false;
  int _chargingLimit = 80;

  double _energyWh = 0;

  final StreamController<bool> _connectionController =
  StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectionState =>
      _connectionController.stream;

  @override
  Future<void> connect() async {
    await Future<void>.delayed(
      const Duration(milliseconds: 500),
    );

    _connected = true;
    _connectionController.add(true);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _charging = false;
    _relayState = false;

    _connectionController.add(false);
  }

  void _ensureConnected() {
    if (!_connected) {
      throw StateError('ESP32 is not connected.');
    }
  }

  @override
  Future<DeviceStatus> getDeviceStatus() async {
    _ensureConnected();

    return DeviceStatus(
      connected: _connected,
      charging: _charging,
      relayState: _relayState,
      deviceName: 'CHARGE LINK',
    );
  }

  @override
  Future<PowerData> getPowerData() async {
    _ensureConnected();

    final voltage = _charging ? 9.0 : 0.0;
    final current = _charging ? 2.0 : 0.0;
    final power = voltage * current;

    return PowerData(
      voltage: voltage,
      current: current,
      power: power,
      energyWh: _energyWh,
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
      throw ArgumentError(
        'Charging limit must be between 0 and 100.',
      );
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
    final power = voltage * current;

    if (_charging) {
      _energyWh += power / 3600;
    }

    return ChargingSample(
      timestamp: DateTime.now(),
      sessionId: 'MOCK-SESSION',
      voltage: voltage,
      current: current,
      power: power,
      energyWh: _energyWh,
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
      sessionEnergyWh: _energyWh,
      totalEnergyWh: _energyWh,
    );
  }

  Future<void> dispose() async {
    await _connectionController.close();
  }
}