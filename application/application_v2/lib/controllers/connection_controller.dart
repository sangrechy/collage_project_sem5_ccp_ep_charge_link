import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/permissions/ble_permissions.dart';
import '../services/ble/esp32_service.dart';

class ConnectionController extends ChangeNotifier {
  ConnectionController(this._esp32) {
    _sub = _esp32.connectionState.listen((s) {
      _state = s;
      notifyListeners();
    });
  }

  final Esp32Service _esp32;
  late final StreamSubscription<BleConnectionState> _sub;

  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get state => _state;

  bool get isConnected => _state == BleConnectionState.connected;

  String? lastError;

  Future<void> beginConnection() async {
    lastError = null;

    final granted = await BlePermissions.hasAll() || await BlePermissions.requestAll();
    if (!granted) {
      _state = BleConnectionState.permissionsRequired;
      notifyListeners();
      return;
    }

    try {
      await _esp32.startScan();
      // Give the scan a moment; the service itself emits deviceFound.
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_state == BleConnectionState.deviceFound) {
        await _esp32.connect();
      }
    } catch (e) {
      lastError = e.toString();
      _state = BleConnectionState.connectionFailed;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _esp32.disconnect();
  }

  Future<void> retry() => beginConnection();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
