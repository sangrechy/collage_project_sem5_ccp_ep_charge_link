abstract class PhoneBatteryService {
  Future<int?> getBatteryPercentage();

  Future<bool?> getChargingState();

  Future<double?> getBatteryVoltage();

  Future<double?> getBatteryCurrent();

  Future<double?> getBatteryTemperature();

  Future<double?> getBatteryHealth();

  Future<String?> getBatteryModel();

  Future<String?> getManufacturer();
}