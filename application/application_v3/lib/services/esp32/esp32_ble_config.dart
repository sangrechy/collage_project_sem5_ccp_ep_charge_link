class Esp32BleConfig {
  const Esp32BleConfig._();

  static const String deviceName = 'Charge Link';
  static const String deviceAddress = '70:4b:ca:46:d3:ba';

  static const String serviceUuid = '7f4a0001-6d3b-4a91-9c21-123456789001';
  static const String commandCharacteristicUuid = '7f4a0002-6d3b-4a91-9c21-123456789001';
  static const String responseCharacteristicUuid = '7f4a0003-6d3b-4a91-9c21-123456789001';
  static const String liveDataCharacteristicUuid = '7f4a0004-6d3b-4a91-9c21-123456789001';
  static const String historyCharacteristicUuid = '7f4a0005-6d3b-4a91-9c21-123456789001';

  static const Duration commandTimeout = Duration(seconds: 6);
  static const Duration connectTimeout = Duration(seconds: 12);
}
