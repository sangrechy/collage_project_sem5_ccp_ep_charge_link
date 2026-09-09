import '../services/ble/esp32_ble_service.dart';
import '../services/ble/esp32_service.dart';
import '../services/ble/mock_esp32_service.dart';
import '../services/phone/phone_battery_service.dart';

/// Single composition point for the two data sources the app needs:
/// the ESP32 (real BLE by default) and the phone's own battery.
///
/// FINAL DEFAULT MODE = REAL ESP32 BLE. Mock mode exists purely for
/// development and must be turned on explicitly — it never silently
/// replaces the real connection.
class ChargeLinkRepository {
  ChargeLinkRepository({bool useMock = false})
      : esp32 = useMock ? MockEsp32Service() : Esp32BleService(),
        phoneBattery = BatteryPlusPhoneBatteryService();

  final Esp32Service esp32;
  final PhoneBatteryService phoneBattery;

  Future<void> dispose() async {
    await esp32.dispose();
  }
}
