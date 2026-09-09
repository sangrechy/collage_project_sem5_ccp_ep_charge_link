import 'dart:async';
import 'dart:math';

import '../../models/device_status.dart';
import '../../models/discovered_ble_device.dart';
import '../../models/history_sample.dart';
import '../../models/live_data_sample.dart';
import '../../models/session_data.dart';
import 'esp32_service.dart';

class MockEsp32Service implements Esp32Service {
  MockEsp32Service({this.autoConnect = true}) {
    if (autoConnect) {
      _initTimer = Timer(const Duration(milliseconds: 500), () {
        _emit(BleConnectionState.connected);
        _startSimulation();
      });
    }
  }

  final bool autoConnect;
  Timer? _initTimer;
  final StreamController<BleConnectionState> _stateController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<LiveDataSample> _liveDataController =
      StreamController<LiveDataSample>.broadcast();

  Timer? _simTimer;
  final Random _rng = Random();

  bool _pathEnabled = true;
  bool _charging = true;
  int _chargingLimit = 80;
  int _uptime = 3600;
  int _sessionId = 12;
  double _sessionEnergy = 12.4;
  double _totalEnergy = 145.8;

  @override
  Stream<BleConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<LiveDataSample> get liveDataStream => _liveDataController.stream;

  void _emit(BleConnectionState s) {
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void _startSimulation() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _uptime++;
      if (_charging && _pathEnabled) {
        _sessionEnergy += 0.004;
        _totalEnergy += 0.004;
      }

      final voltage = _pathEnabled ? (9.10 + (_rng.nextDouble() * 0.08)) : 0.0;
      final current = (_pathEnabled && _charging) ? (1.80 + (_rng.nextDouble() * 0.10)) : 0.0;
      final power = voltage * current;

      if (!_liveDataController.isClosed) {
        _liveDataController.add(
          LiveDataSample(
            timestamp: _uptime,
            voltageV: voltage,
            currentA: current,
            powerW: power,
            charging: _charging && _pathEnabled,
            pathEnabled: _pathEnabled,
            chargingLimit: _chargingLimit,
            ina219Available: true,
            sessionEnergyWh: _sessionEnergy,
            totalEnergyWh: _totalEnergy,
            receivedAt: DateTime.now(),
          ),
        );
      }
    });
  }

  @override
  Stream<List<DiscoveredBleDevice>> get discoveredDevicesStream => const Stream.empty();

  @override
  List<DiscoveredBleDevice> get discoveredDevices => const [];

  @override
  String? get connectedDeviceName => 'Charge Link (Mock)';

  @override
  String? get connectedDeviceId => '70:4B:CA:46:D3:BA';

  @override
  Future<void> startScan() async {
    _emit(BleConnectionState.scanning);
    await Future.delayed(const Duration(milliseconds: 800));
    _emit(BleConnectionState.deviceFound);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect() async {
    _emit(BleConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 600));
    _emit(BleConnectionState.connected);
    _startSimulation();
  }

  @override
  Future<void> connectToDevice(DiscoveredBleDevice device) => connect();

  @override
  Future<void> disconnect() async {
    _simTimer?.cancel();
    _emit(BleConnectionState.disconnected);
  }

  @override
  Future<DeviceStatus> getDeviceStatus() async {
    return DeviceStatus(
      connected: true,
      deviceName: 'Charge Link (Mock)',
      modelName: 'CL-SCB-01',
      hardwareVersion: '1.0',
      firmwareVersion: '1.0.1',
      protocolVersion: '1.0',
      ina219Available: true,
      pathEnabled: _pathEnabled,
      charging: _charging,
      chargingLimit: _chargingLimit,
      uptimeSeconds: _uptime,
    );
  }

  @override
  Future<SessionData> getSession() async {
    return SessionData(
      active: _charging,
      sessionId: _sessionId,
      durationSeconds: 5072, // 01:24:32
      energyWh: _sessionEnergy,
      peakPowerW: 18.6,
      averagePowerW: 16.4,
    );
  }

  @override
  Future<void> clearSession() async {
    _sessionId++;
    _sessionEnergy = 0.0;
  }

  @override
  Future<bool> getChargingState() async => _charging;

  @override
  Future<int> getChargingLimit() async => _chargingLimit;

  @override
  Future<void> setChargingLimit(int percentage) async {
    _chargingLimit = percentage;
  }

  @override
  Future<void> startCharging() async {
    _pathEnabled = true;
    _charging = true;
  }

  @override
  Future<void> stopCharging() async {
    _pathEnabled = false;
    _charging = false;
  }

  @override
  Future<List<HistorySample>> getHistory({int limit = 100}) async {
    final nowUptime = _uptime;
    return List.generate(25, (i) {
      final t = nowUptime - (24 - i) * 10;
      final v = 9.12 + sin(i * 0.3) * 0.05;
      final c = 1.84 + cos(i * 0.3) * 0.08;
      return HistorySample(
        timestamp: t,
        sessionId: '$_sessionId',
        voltageV: v,
        currentA: c,
        powerW: v * c,
        sessionEnergyWh: 10.0 + (i * 0.1),
        charging: true,
        pathEnabled: true,
      );
    });
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    _simTimer?.cancel();
    _stateController.close();
    _liveDataController.close();
  }
}
