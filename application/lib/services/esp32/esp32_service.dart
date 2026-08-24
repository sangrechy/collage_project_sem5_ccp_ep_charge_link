import '../../models/charging_sample.dart';
import '../../models/device_status.dart';
import '../../models/energy_data.dart';
import '../../models/power_data.dart';
import '../../models/temperature_data.dart';

abstract class Esp32Service {
  Future<void> connect();

  Future<void> disconnect();

  Stream<bool> get connectionState;

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
}