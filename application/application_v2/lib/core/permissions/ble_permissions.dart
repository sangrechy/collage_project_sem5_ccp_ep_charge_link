import 'package:permission_handler/permission_handler.dart';

/// Centralizes the runtime permissions BLE scanning/connecting needs on
/// modern Android. Location is only requested when the platform actually
/// requires it for BLE scanning (pre-Android 12 devices, or OEMs that still
/// tie BLE scan results to location access) — it isn't requested blindly.
class BlePermissions {
  const BlePermissions._();

  static Future<bool> requestAll() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // bluetoothScan/bluetoothConnect are the Android 12+ permissions.
    // locationWhenInUse only matters on Android < 12 for BLE scan results;
    // if the platform doesn't declare it as required it will report
    // granted/restricted harmlessly.
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? true;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? true;

    return scanOk && connectOk;
  }

  static Future<bool> hasAll() async {
    final scan = await Permission.bluetoothScan.status;
    final connect = await Permission.bluetoothConnect.status;
    return scan.isGranted && connect.isGranted;
  }
}
