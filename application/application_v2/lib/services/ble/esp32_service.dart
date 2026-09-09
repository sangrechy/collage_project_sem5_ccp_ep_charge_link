import '../../models/charging_sample.dart';
import '../../models/device_status.dart';
import '../../models/energy_data.dart';
import '../../models/history_sample.dart';
import '../../models/live_data_sample.dart';
import '../../models/power_data.dart';
import '../../models/temperature_data.dart';

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

/// Contract that any ESP32 transport (BLE, mock, Wi-Fi, ...) must satisfy.
///
/// This is the interface only — no implementation lives here. See
/// `esp32_ble_service.dart` for the real BLE implementation.
abstract class Esp32Service {
  Stream<BleConnectionState> get connectionState;

  /// Emits every parsed `live_data` packet as it arrives (~1/sec).
  Stream<LiveDataSample> get liveDataStream;

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect();

  Future<void> disconnect();

  Future<DeviceStatus> getDeviceStatus();

  Future<PowerData> getPowerData();

  Future<bool> getChargingState();

  Future<int> getChargingLimit();

  Future<void> setChargingLimit(int percentage);

  Future<void> startCharging();

  Future<void> stopCharging();

  Future<ChargingSample> getChargingSample();

  Future<TemperatureData> getTemperature();

  Future<EnergyData> getEnergyData();

  /// Requests up to [limit] history samples and returns them fully
  /// reassembled from whatever number of chunks the firmware sends.
  Future<List<HistorySample>> getHistory({int limit = 100});

  Future<void> dispose();
}
