/// BLE identity constants for the CHARGE LINK ESP32 device.
///
/// This file stores only BLE constants — no logic, no implementation.
/// Copied unmodified from the v1 reference (CHARGE_LINK_REFERENCE/esp32_ble_config.dart).
class Esp32BleConfig {
  const Esp32BleConfig._();

  static const String deviceName = 'Charge Link';

  static const String deviceAddress = '70:4b:ca:46:d3:ba';

  static const String serviceUuid = '7f4a0001-6d3b-4a91-9c21-123456789001';

  static const String commandCharacteristicUuid =
      '7f4a0002-6d3b-4a91-9c21-123456789001';

  static const String responseCharacteristicUuid =
      '7f4a0003-6d3b-4a91-9c21-123456789001';

  static const String liveDataCharacteristicUuid =
      '7f4a0004-6d3b-4a91-9c21-123456789001';

  static const String historyCharacteristicUuid =
      '7f4a0005-6d3b-4a91-9c21-123456789001';

  /// Firmware sends live data roughly once per second.
  static const Duration liveDataInterval = Duration(seconds: 1);

  /// Firmware stores a history sample roughly every 10 seconds.
  static const Duration historySampleInterval = Duration(seconds: 10);

  /// Firmware keeps at most this many history samples, in RAM only.
  static const int maxHistorySamples = 300;

  /// How long to wait for a command response before treating it as failed.
  static const Duration commandTimeout = Duration(seconds: 6);

  /// How long to wait for a BLE connection attempt before giving up.
  static const Duration connectTimeout = Duration(seconds: 12);
}
