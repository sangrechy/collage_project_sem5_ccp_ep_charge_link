import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DiscoveredBleDevice {
  const DiscoveredBleDevice({
    required this.device,
    required this.id,
    required this.name,
    required this.rssi,
    required this.isChargeLink,
    required this.serviceUuids,
  });

  final BluetoothDevice device;
  final String id;
  final String name;
  final int rssi;
  final bool isChargeLink;
  final List<String> serviceUuids;

  factory DiscoveredBleDevice.fromScanResult(ScanResult r, {String? targetServiceUuid}) {
    final advName = r.advertisementData.advName.trim();
    final platName = r.device.platformName.trim();
    final name = advName.isNotEmpty
        ? advName
        : platName.isNotEmpty
            ? platName
            : 'Unknown Device';

    final serviceUuids = r.advertisementData.serviceUuids
        .map((g) => g.str.toLowerCase())
        .toList();

    final targetUuid = targetServiceUuid?.toLowerCase();
    final hasMatchingUuid = targetUuid != null && serviceUuids.contains(targetUuid);

    final cleanLowerName = name.toLowerCase();
    final matchesName = cleanLowerName.contains('charge') ||
        cleanLowerName.contains('link') ||
        cleanLowerName.contains('cl-scb');

    final isChargeLink = hasMatchingUuid || matchesName;

    return DiscoveredBleDevice(
      device: r.device,
      id: r.device.remoteId.str,
      name: name,
      rssi: r.rssi,
      isChargeLink: isChargeLink,
      serviceUuids: serviceUuids,
    );
  }

  factory DiscoveredBleDevice.fromBluetoothDevice(
    BluetoothDevice d, {
    int rssi = -60,
    String? targetServiceUuid,
  }) {
    final platName = d.platformName.trim();
    final name = platName.isNotEmpty
        ? platName
        : 'Bluetooth Device (${d.remoteId.str.length > 5 ? d.remoteId.str.substring(d.remoteId.str.length - 5) : d.remoteId.str})';

    final cleanLowerName = name.toLowerCase();
    final isChargeLink = cleanLowerName.contains('charge') ||
        cleanLowerName.contains('link') ||
        cleanLowerName.contains('cl-scb');

    return DiscoveredBleDevice(
      device: d,
      id: d.remoteId.str,
      name: name,
      rssi: rssi,
      isChargeLink: isChargeLink,
      serviceUuids: const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredBleDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
