import 'package:flutter/foundation.dart';

class SettingsController extends ChangeNotifier {
  SettingsController();

  bool _autoControl = true;
  bool _stopAtLimit = true;
  bool _autoReconnect = true;

  bool get autoControl => _autoControl;
  bool get stopAtLimit => _stopAtLimit;
  bool get autoReconnect => _autoReconnect;

  void setAutoControl(bool value) {
    if (_autoControl != value) {
      _autoControl = value;
      notifyListeners();
    }
  }

  void setStopAtLimit(bool value) {
    if (_stopAtLimit != value) {
      _stopAtLimit = value;
      notifyListeners();
    }
  }

  void setAutoReconnect(bool value) {
    if (_autoReconnect != value) {
      _autoReconnect = value;
      notifyListeners();
    }
  }
}

