import '../models/app_snapshot.dart';
import '../models/charging_sample.dart';
import '../models/device_status.dart';
import '../models/energy_data.dart';
import '../models/power_data.dart';
import '../models/temperature_data.dart';
import '../services/esp32/esp32_service.dart';
import '../services/phone/phone_battery_service.dart';

class ChargeLinkRepository {
  const ChargeLinkRepository({
    required this.esp32Service,
    required this.phoneBatteryService,
  });

  final Esp32Service esp32Service;
  final PhoneBatteryService phoneBatteryService;

  // ============================================================
  // ESP32 CONNECTION
  // ============================================================

  Stream<bool> get connectionState {
    return esp32Service.connectionState;
  }

  Future<void> connect() {
    return esp32Service.connect();
  }

  Future<void> disconnect() {
    return esp32Service.disconnect();
  }

  // ============================================================
  // ESP32 DEVICE
  // ============================================================

  Future<DeviceStatus> getDeviceStatus() {
    return esp32Service.getDeviceStatus();
  }

  // ============================================================
  // POWER
  // ============================================================

  Future<PowerData> getPowerData() {
    return esp32Service.getPowerData();
  }

  // ============================================================
  // CHARGING
  // ============================================================

  Future<bool> getChargingState() {
    return esp32Service.getChargingState();
  }

  Future<void> startCharging() {
    return esp32Service.startCharging();
  }

  Future<void> stopCharging() {
    return esp32Service.stopCharging();
  }

  // ============================================================
  // CHARGING LIMIT
  // ============================================================

  Future<int> getChargingLimit() {
    return esp32Service.getChargingLimit();
  }

  Future<void> setChargingLimit(int percentage) {
    if (percentage < 0 || percentage > 100) {
      throw ArgumentError(
        'Charging limit must be between 0 and 100.',
      );
    }

    return esp32Service.setChargingLimit(percentage);
  }

  // ============================================================
  // CHARGING DATA
  // ============================================================

  Future<ChargingSample> getChargingSample() {
    return esp32Service.getChargingSample();
  }

  Future<TemperatureData> getTemperature() {
    return esp32Service.getTemperature();
  }

  Future<EnergyData> getEnergyData() {
    return esp32Service.getEnergyData();
  }

  // ============================================================
  // PHONE BATTERY
  // ============================================================

  Future<int?> getPhoneBatteryPercentage() {
    return phoneBatteryService.getBatteryPercentage();
  }

  Future<bool?> getPhoneChargingState() {
    return phoneBatteryService.getChargingState();
  }

  Future<double?> getPhoneBatteryVoltage() {
    return phoneBatteryService.getBatteryVoltage();
  }

  Future<double?> getPhoneBatteryCurrent() {
    return phoneBatteryService.getBatteryCurrent();
  }

  Future<double?> getPhoneBatteryTemperature() {
    return phoneBatteryService.getBatteryTemperature();
  }

  Future<double?> getPhoneBatteryHealth() {
    return phoneBatteryService.getBatteryHealth();
  }

  Future<String?> getPhoneBatteryModel() {
    return phoneBatteryService.getBatteryModel();
  }

  Future<String?> getPhoneManufacturer() {
    return phoneBatteryService.getManufacturer();
  }

  // ============================================================
  // COMPLETE APPLICATION SNAPSHOT
  // ============================================================

  Future<AppSnapshot> getAppSnapshot() async {
    final deviceStatus = await getDeviceStatus();
    final powerData = await getPowerData();
    final charging = await getChargingState();
    final chargingLimit = await getChargingLimit();
    final energyData = await getEnergyData();
    final temperatureData = await getTemperature();
    final chargingSample = await getChargingSample();

    final phoneBatteryPercentage =
    await getPhoneBatteryPercentage();

    final phoneCharging =
    await getPhoneChargingState();

    final phoneBatteryTemperature =
    await getPhoneBatteryTemperature();

    final phoneBatteryHealth =
    await getPhoneBatteryHealth();

    return AppSnapshot(
      deviceStatus: deviceStatus,
      powerData: powerData,
      charging: charging,
      chargingLimit: chargingLimit,
      energyData: energyData,
      temperatureData: temperatureData,
      chargingSample: chargingSample,
      phoneBatteryPercentage:
      phoneBatteryPercentage,
      phoneCharging: phoneCharging,
      phoneBatteryTemperature:
      phoneBatteryTemperature,
      phoneBatteryHealth:
      phoneBatteryHealth,
    );
  }
}