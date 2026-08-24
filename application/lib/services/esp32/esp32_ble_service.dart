import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../config/esp32_ble_config.dart';
import '../../models/charging_sample.dart';
import '../../models/device_status.dart';
import '../../models/energy_data.dart';
import '../../models/power_data.dart';
import '../../models/temperature_data.dart';
import 'esp32_service.dart';

class Esp32BleService implements Esp32Service {
  Esp32BleService();

  BluetoothDevice? _device;

  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _telemetryCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;

  StreamSubscription<BluetoothConnectionState>?
  _connectionSubscription;

  final StreamController<bool> _connectionController =
  StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectionState =>
      _connectionController.stream;

  // ============================================================
  // CONNECTION
  // ============================================================

  @override
  Future<void> connect() async {
    await FlutterBluePlus.stopScan();

    BluetoothDevice? foundDevice;

    final scanSubscription =
    FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final device = result.device;

        final platformName = device.platformName;
        final advertisedName = result.advertisementData.advName;

        if (platformName == Esp32BleConfig.deviceName ||
            advertisedName == Esp32BleConfig.deviceName) {
          foundDevice = device;
          break;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
      );

      await Future<void>.delayed(
        const Duration(seconds: 10),
      );
    } finally {
      await scanSubscription.cancel();
      await FlutterBluePlus.stopScan();
    }

    if (foundDevice == null) {
      throw StateError(
        'CHARGE LINK ESP32 was not found during BLE scan.',
      );
    }

    _device = foundDevice;

    await _device!.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
    );

    await _connectionSubscription?.cancel();

    _connectionSubscription =
        _device!.connectionState.listen((state) {
          final connected =
              state == BluetoothConnectionState.connected;

          _connectionController.add(connected);

          if (!connected) {
            _clearCharacteristics();
          }
        });

    _connectionController.add(true);

    await _discoverServices();
  }

  @override
  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    final device = _device;

    if (device == null) {
      _connectionController.add(false);
      return;
    }

    try {
      await device.disconnect();
    } finally {
      _connectionController.add(false);
      _clearCharacteristics();
      _device = null;
    }
  }

  // ============================================================
  // SERVICE DISCOVERY
  // ============================================================

  Future<void> _discoverServices() async {
    final device = _device;

    if (device == null) {
      throw StateError('ESP32 is not connected.');
    }

    final services = await device.discoverServices();

    BluetoothService? targetService;

    for (final service in services) {
      if (service.uuid.str.toLowerCase() ==
          Esp32BleConfig.serviceUuid.toLowerCase()) {
        targetService = service;
        break;
      }
    }

    if (targetService == null) {
      throw StateError(
        'CHARGE LINK BLE service was not found.',
      );
    }

    for (final characteristic
    in targetService.characteristics) {
      final uuid =
      characteristic.uuid.str.toLowerCase();

      if (uuid ==
          Esp32BleConfig.commandCharacteristicUuid
              .toLowerCase()) {
        _commandCharacteristic = characteristic;
      }

      if (uuid ==
          Esp32BleConfig.telemetryCharacteristicUuid
              .toLowerCase()) {
        _telemetryCharacteristic = characteristic;
      }

      if (uuid ==
          Esp32BleConfig.statusCharacteristicUuid
              .toLowerCase()) {
        _statusCharacteristic = characteristic;
      }
    }
  }

  void _clearCharacteristics() {
    _commandCharacteristic = null;
    _telemetryCharacteristic = null;
    _statusCharacteristic = null;
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  void _ensureConnected() {
    if (_device == null) {
      throw StateError('ESP32 is not connected.');
    }
  }

  BluetoothCharacteristic _requireCommandCharacteristic() {
    final characteristic = _commandCharacteristic;

    if (characteristic == null) {
      throw StateError(
        'BLE command characteristic is not configured.',
      );
    }

    return characteristic;
  }

  BluetoothCharacteristic _requireTelemetryCharacteristic() {
    final characteristic = _telemetryCharacteristic;

    if (characteristic == null) {
      throw StateError(
        'BLE telemetry characteristic is not configured.',
      );
    }

    return characteristic;
  }

  BluetoothCharacteristic _requireStatusCharacteristic() {
    final characteristic = _statusCharacteristic;

    if (characteristic == null) {
      throw StateError(
        'BLE status characteristic is not configured.',
      );
    }

    return characteristic;
  }

  // ============================================================
  // LOW-LEVEL BLE OPERATIONS
  // ============================================================

  Future<void> _sendCommand(String command) async {
    _ensureConnected();

    final characteristic =
    _requireCommandCharacteristic();

    final bytes = utf8.encode(command);

    await characteristic.write(
      bytes,
      withoutResponse:
      characteristic.properties.writeWithoutResponse,
    );
  }

  Future<String> _readStatus() async {
    _ensureConnected();

    final characteristic =
    _requireStatusCharacteristic();

    final bytes = await characteristic.read();

    return utf8.decode(bytes);
  }

  Future<String> _readTelemetry() async {
    _ensureConnected();

    final characteristic =
    _requireTelemetryCharacteristic();

    final bytes = await characteristic.read();

    return utf8.decode(bytes);
  }

  // ============================================================
  // DEVICE STATUS
  // ============================================================

  @override
  Future<DeviceStatus> getDeviceStatus() async {
    final raw = await _readStatus();

    final data =
    jsonDecode(raw) as Map<String, dynamic>;

    return DeviceStatus(
      connected: data['connected'] as bool,
      charging: data['charging'] as bool,
      relayState: data['relayState'] as bool,
      deviceName: data['deviceName'] as String,
    );
  }

  // ============================================================
  // POWER
  // ============================================================

  @override
  Future<PowerData> getPowerData() async {
    final raw = await _readTelemetry();

    final data =
    jsonDecode(raw) as Map<String, dynamic>;

    return PowerData(
      voltage: (data['voltage'] as num).toDouble(),
      current: (data['current'] as num).toDouble(),
      power: (data['power'] as num).toDouble(),
      energyWh:
      (data['energyWh'] as num).toDouble(),
    );
  }

  // ============================================================
  // CHARGING
  // ============================================================

  @override
  Future<bool> getChargingState() async {
    final status = await getDeviceStatus();

    return status.charging;
  }

  @override
  Future<int> getChargingLimit() async {
    final raw = await _readStatus();

    final data =
    jsonDecode(raw) as Map<String, dynamic>;

    return (data['chargingLimit'] as num).toInt();
  }

  @override
  Future<void> setChargingLimit(
      int percentage,
      ) async {
    if (percentage < 0 || percentage > 100) {
      throw ArgumentError(
        'Charging limit must be between 0 and 100.',
      );
    }

    await _sendCommand(
      jsonEncode({
        'command': 'setChargingLimit',
        'percentage': percentage,
      }),
    );
  }

  @override
  Future<void> startCharging() async {
    await _sendCommand(
      jsonEncode({
        'command': 'startCharging',
      }),
    );
  }

  @override
  Future<void> stopCharging() async {
    await _sendCommand(
      jsonEncode({
        'command': 'stopCharging',
      }),
    );
  }

  // ============================================================
  // CHARGING SAMPLE
  // ============================================================

  @override
  Future<ChargingSample> getChargingSample() async {
    final raw = await _readTelemetry();

    final data =
    jsonDecode(raw) as Map<String, dynamic>;

    return ChargingSample(
      timestamp:
      DateTime.parse(data['timestamp'] as String),
      sessionId:
      data['sessionId'] as String,
      voltage:
      (data['voltage'] as num).toDouble(),
      current:
      (data['current'] as num).toDouble(),
      power:
      (data['power'] as num).toDouble(),
      energyWh:
      (data['energyWh'] as num).toDouble(),
      charging:
      data['charging'] as bool,
      batteryPercent:
      (data['batteryPercent'] as num?)?.toInt(),
      batteryTemperature:
      (data['batteryTemperature'] as num?)
          ?.toDouble(),
      batteryVoltage:
      (data['batteryVoltage'] as num?)
          ?.toDouble(),
      batteryCurrent:
      (data['batteryCurrent'] as num?)
          ?.toDouble(),
      batteryHealth:
      (data['batteryHealth'] as num?)
          ?.toDouble(),
    );
  }

  // ============================================================
  // TEMPERATURE
  // ============================================================

  @override
  Future<TemperatureData> getTemperature() async {
    final raw = await _readTelemetry();

    final data =
    jsonDecode(raw) as Map<String, dynamic>;

    return TemperatureData(
      temperatureCelsius:
      (data['temperatureCelsius'] as num?)
          ?.toDouble(),
      timestamp:
      DateTime.parse(data['timestamp'] as String),
    );
  }

  // ============================================================
  // ENERGY
  // ============================================================

  @override
  Future<EnergyData> getEnergyData() async {
    final raw = await _readTelemetry();

    final data =
    jsonDecode(raw) as Map<String, dynamic>;

    return EnergyData(
      sessionEnergyWh:
      (data['sessionEnergyWh'] as num)
          .toDouble(),
      totalEnergyWh:
      (data['totalEnergyWh'] as num)
          .toDouble(),
    );
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  Future<void> dispose() async {
    await disconnect();
    await _connectionController.close();
  }
}