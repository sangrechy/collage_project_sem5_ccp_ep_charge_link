import 'package:flutter/foundation.dart';

import '../services/ble/esp32_service.dart';

enum CommandStatus { idle, sending }

class ChargingController extends ChangeNotifier {
  ChargingController(this._esp32);

  final Esp32Service _esp32;

  /// Physical relay / charging-path state.
  bool pathEnabled = false;

  /// Actual charging state derived from INA219 current — NOT the same as
  /// [pathEnabled]; the path can be enabled while the phone isn't drawing
  /// enough current to count as actively charging.
  bool charging = false;

  int chargingLimit = 80;

  CommandStatus status = CommandStatus.idle;
  String? lastError;
  String? statusMessage;

  // Guards against sending stop_charging repeatedly once the limit is hit.
  bool _autoStopTriggered = false;

  void updateFromLiveSample({
    required bool pathEnabled,
    required bool charging,
    required int chargingLimit,
  }) {
    this.pathEnabled = pathEnabled;
    this.charging = charging;
    this.chargingLimit = chargingLimit;

    // Reset the guard once the path is no longer enabled (e.g. user
    // manually restarted charging after an auto-stop).
    if (!pathEnabled) _autoStopTriggered = false;

    notifyListeners();
  }

  Future<void> refreshFromDevice() async {
    try {
      final s = await _esp32.getDeviceStatus();
      pathEnabled = s.relayState;
      charging = s.charging;
      if (s.chargingLimit != null) chargingLimit = s.chargingLimit!;
      notifyListeners();
    } catch (_) {
      // Best-effort refresh; live stream remains the source of truth.
    }
  }

  Future<void> start() async {
    status = CommandStatus.sending;
    lastError = null;
    notifyListeners();
    try {
      await _esp32.startCharging();
      _autoStopTriggered = false;
      await refreshFromDevice();
    } catch (e) {
      lastError = 'Could not start charging: $e';
    } finally {
      status = CommandStatus.idle;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    status = CommandStatus.sending;
    lastError = null;
    notifyListeners();
    try {
      await _esp32.stopCharging();
      await refreshFromDevice();
    } catch (e) {
      lastError = 'Could not stop charging: $e';
    } finally {
      status = CommandStatus.idle;
      notifyListeners();
    }
  }

  Future<void> setLimit(int percentage) async {
    final previous = chargingLimit;
    chargingLimit = percentage;
    notifyListeners();
    try {
      await _esp32.setChargingLimit(percentage);
    } catch (e) {
      chargingLimit = previous;
      lastError = 'Could not update charging limit: $e';
      notifyListeners();
    }
  }

  /// Called whenever a fresh phone battery percentage is available.
  /// Sends stop_charging exactly once per charging session when the
  /// configured limit is reached — never repeatedly on every update.
  Future<void> evaluateAutoStop(int? batteryPercentage) async {
    if (batteryPercentage == null) return;
    if (!pathEnabled) return;
    if (_autoStopTriggered) return;

    if (batteryPercentage >= chargingLimit) {
      _autoStopTriggered = true;
      statusMessage =
          'Charging stopped — battery reached the selected $chargingLimit% limit.';
      notifyListeners();
      await stop();
    }
  }

  void clearStatusMessage() {
    statusMessage = null;
    notifyListeners();
  }
}
