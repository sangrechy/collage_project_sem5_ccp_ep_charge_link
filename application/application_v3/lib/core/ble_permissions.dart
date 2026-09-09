import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class BlePermissions {
  const BlePermissions._();

  static Future<bool> requestAll() async {
    if (!Platform.isAndroid) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final location = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

    // On Android 12+, scan & connect are essential. On Android 11-, location is essential.
    return (scan && connect) || location;
  }

  static Future<bool> hasAll() async {
    if (!Platform.isAndroid) return true;

    final scan = await Permission.bluetoothScan.status;
    final connect = await Permission.bluetoothConnect.status;
    final location = await Permission.locationWhenInUse.status;

    return (scan.isGranted && connect.isGranted) || location.isGranted;
  }

  static Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    final scan = await Permission.bluetoothScan.isPermanentlyDenied;
    final connect = await Permission.bluetoothConnect.isPermanentlyDenied;
    return scan || connect;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
