import '../../models/device_status.dart';
import '../../models/history_sample.dart';
import '../../models/live_data_sample.dart';
import '../../models/session_data.dart';

import '../../models/discovered_ble_device.dart';

enum BleConnectionState {
  bluetoothOff,
  permissionsRequired,
  disconnected,
  scanning,
  deviceFound,
  connecting,
  connected,
  connectionFailed,
}

abstract class Esp32Service {
  Stream<BleConnectionState> get connectionState;
  Stream<LiveDataSample> get liveDataStream;

  Stream<List<DiscoveredBleDevice>> get discoveredDevicesStream;
  List<DiscoveredBleDevice> get discoveredDevices;

  String? get connectedDeviceName;
  String? get connectedDeviceId;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect();
  Future<void> connectToDevice(DiscoveredBleDevice device);
  Future<void> disconnect();

  Future<DeviceStatus> getDeviceStatus();
  Future<SessionData> getSession();
  Future<void> clearSession();
  Future<bool> getChargingState();
  Future<int> getChargingLimit();
  Future<void> setChargingLimit(int percentage);
  Future<void> startCharging();
  Future<void> stopCharging();
  Future<List<HistorySample>> getHistory({int limit = 100});

  void dispose();
}
