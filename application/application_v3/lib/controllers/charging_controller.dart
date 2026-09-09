import 'package:flutter/foundation.dart';
import '../services/esp32/esp32_service.dart';

enum CommandStatus { idle, sending }

class ChargingController extends ChangeNotifier {
  ChargingController(this._esp32);

  final Esp32Service _esp32;

  bool pathEnabled = false;
  bool charging = false;
  int chargingLimit = 80;

  CommandStatus status = CommandStatus.idle;
  String? lastError;

  bool autoStopTriggered = false;
  bool autoStopCompleted = false;

  void updateFromLiveSample({
    required bool pathEnabled,
    required bool charging,
    required int chargingLimit,
  }) {
    this.pathEnabled = pathEnabled;
    this.charging = charging;
    this.chargingLimit = chargingLimit;

    if (!pathEnabled) {
      autoStopTriggered = false;
    }
    notifyListeners();
  }

  Future<void> refreshFromDevice() async {
    try {
      final s = await _esp32.getDeviceStatus();
      pathEnabled = s.pathEnabled;
      charging = s.charging;
      chargingLimit = s.chargingLimit;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> start() async {
    status = CommandStatus.sending;
    lastError = null;
    autoStopCompleted = false;
    notifyListeners();

    try {
      await _esp32.startCharging();
      pathEnabled = true;
      autoStopTriggered = false;
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
      pathEnabled = false;
      charging = false;
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
      lastError = 'Could not set charging limit: $e';
      notifyListeners();
    }
  }

  Future<void> evaluateAutoStop({
    required int? batteryPercentage,
    required bool autoStopEnabled,
  }) async {
    if (!autoStopEnabled) return;
    if (batteryPercentage == null) return;
    if (!pathEnabled) return;
    if (autoStopTriggered) return;

    if (batteryPercentage >= chargingLimit) {
      autoStopTriggered = true;
      autoStopCompleted = true;
      notifyListeners();
      await stop();
    }
  }

  void dismissAutoStopAlert() {
    autoStopCompleted = false;
    notifyListeners();
  }
}
