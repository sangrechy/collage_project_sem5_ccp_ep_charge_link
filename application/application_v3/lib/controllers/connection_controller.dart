import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/ble_permissions.dart';
import '../models/discovered_ble_device.dart';
import '../services/esp32/esp32_service.dart';

class ConnectionController extends ChangeNotifier {
  ConnectionController(this._esp32) {
    _sub = _esp32.connectionState.listen(_onStateChanged);
    _devicesSub = _esp32.discoveredDevicesStream.listen((devices) {
      _discoveredDevices = devices;
      notifyListeners();
    });
  }

  final Esp32Service _esp32;
  late final StreamSubscription<BleConnectionState> _sub;
  StreamSubscription<List<DiscoveredBleDevice>>? _devicesSub;

  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get state => _state;

  List<DiscoveredBleDevice> _discoveredDevices = [];
  List<DiscoveredBleDevice> get discoveredDevices =>
      _discoveredDevices.isNotEmpty ? _discoveredDevices : _esp32.discoveredDevices;

  DiscoveredBleDevice? _connectingDevice;
  DiscoveredBleDevice? get connectingDevice => _connectingDevice;

  String? get connectedDeviceName => _esp32.connectedDeviceName;
  String? get connectedDeviceId => _esp32.connectedDeviceId;

  bool get isConnected => _state == BleConnectionState.connected;
  bool get isScanning => _state == BleConnectionState.scanning;
  bool get isConnecting =>
      _state == BleConnectionState.scanning ||
      _state == BleConnectionState.deviceFound ||
      _state == BleConnectionState.connecting;

  String? lastError;

  void _onStateChanged(BleConnectionState s) {
    _state = s;
    if (s == BleConnectionState.connected || s == BleConnectionState.disconnected) {
      _connectingDevice = null;
    }
    notifyListeners();

    // Auto-connect if auto-detected during initial background scan
    if (s == BleConnectionState.deviceFound && _connectingDevice == null) {
      _connectAfterFound();
    }
  }

  Future<void> _connectAfterFound() async {
    try {
      await _esp32.connect();
    } catch (e) {
      lastError = e.toString();
      _state = BleConnectionState.connectionFailed;
      notifyListeners();
    }
  }

  Future<void> beginConnection() async {
    await scanForDevices();
  }

  Future<void> scanForDevices() async {
    lastError = null;

    final granted = await BlePermissions.hasAll() || await BlePermissions.requestAll();
    if (!granted) {
      _state = BleConnectionState.permissionsRequired;
      notifyListeners();
      return;
    }

    try {
      await _esp32.startScan();
    } catch (e) {
      lastError = e.toString();
      _state = BleConnectionState.connectionFailed;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _esp32.stopScan();
  }

  Future<void> connectToDevice(DiscoveredBleDevice device) async {
    lastError = null;
    _connectingDevice = device;
    notifyListeners();

    try {
      await _esp32.connectToDevice(device);
    } catch (e) {
      lastError = e.toString();
      _state = BleConnectionState.connectionFailed;
      _connectingDevice = null;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _connectingDevice = null;
    await _esp32.disconnect();
  }

  Future<void> retry() => scanForDevices();

  Future<void> openSettings() => BlePermissions.openSettings();

  Future<void> requestPermissionsOrOpenSettings() async {
    final permanentlyDenied = await BlePermissions.isPermanentlyDenied();
    if (permanentlyDenied) {
      await BlePermissions.openSettings();
    } else {
      await scanForDevices();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _devicesSub?.cancel();
    super.dispose();
  }
}
