import 'package:battery_plus/battery_plus.dart';

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

class BatteryPlusPhoneBatteryService implements PhoneBatteryService {
  BatteryPlusPhoneBatteryService({
    Battery? battery,
  }) : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<int?> getBatteryPercentage() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool?> getChargingState() async {
    try {
      final state = await _battery.batteryState;

      return state == BatteryState.charging ||
          state == BatteryState.full;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<double?> getBatteryVoltage() async {
    // Not exposed by battery_plus.
    return null;
  }

  @override
  Future<double?> getBatteryCurrent() async {
    // Not exposed by battery_plus.
    return null;
  }

  @override
  Future<double?> getBatteryTemperature() async {
    // Not exposed by battery_plus.
    return null;
  }

  @override
  Future<double?> getBatteryHealth() async {
    // Not exposed by battery_plus.
    return null;
  }

  @override
  Future<String?> getBatteryModel() async {
    // Not exposed by battery_plus.
    return null;
  }

  @override
  Future<String?> getManufacturer() async {
    // Not exposed by battery_plus.
    return null;
  }
}