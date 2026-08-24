import '../services/esp32/esp32_ble_service.dart';
import '../services/esp32/esp32_service.dart';
import '../services/esp32/mock_esp32_service.dart';

class ServiceFactory {
  const ServiceFactory._();

  // Keep true while developing the Flutter UI.
  // Change to false when the real ESP32 BLE firmware is ready.
  static const bool useMockEsp32 = true;

  static Esp32Service createEsp32Service() {
    if (useMockEsp32) {
      return MockEsp32Service();
    }

    return Esp32BleService();
  }
}