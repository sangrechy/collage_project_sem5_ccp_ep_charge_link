import 'package:battery_plus/battery_plus.dart';

/// Reads what the Android platform actually exposes about the phone's
/// battery. battery_plus only reliably provides percentage + charging
/// state — everything else stays null / "Not available" rather than being
/// faked, per the project's no-fake-data requirement.
abstract class PhoneBatteryService {
  Future<int?> getBatteryPercentage();

  Future<bool?> getChargingState();

  Stream<int> get batteryPercentageStream;

  Future<double?> getBatteryVoltage();
  Future<double?> getBatteryCurrent();
  Future<double?> getBatteryTemperature();
  Future<double?> getBatteryHealth();
  Future<String?> getBatteryModel();
  Future<String?> getManufacturer();
}

class BatteryPlusPhoneBatteryService implements PhoneBatteryService {
  BatteryPlusPhoneBatteryService({Battery? battery})
      : _battery = battery ?? Battery();

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
      return state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<int> get batteryPercentageStream async* {
    // battery_plus doesn't expose a percentage stream directly, so this
    // polls at a modest interval, sufficient for the ~1%-per-update
    // granularity Android reports anyway.
    yield* Stream<void>.periodic(const Duration(seconds: 15))
        .asyncMap((_) => getBatteryPercentage())
        .where((v) => v != null)
        .cast<int>();
  }

  @override
  Future<double?> getBatteryVoltage() async => null;

  @override
  Future<double?> getBatteryCurrent() async => null;

  @override
  Future<double?> getBatteryTemperature() async => null;

  @override
  Future<double?> getBatteryHealth() async => null;

  @override
  Future<String?> getBatteryModel() async => null;

  @override
  Future<String?> getManufacturer() async => null;
}
