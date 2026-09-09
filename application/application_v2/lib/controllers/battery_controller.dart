import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/phone/phone_battery_service.dart';

class BatteryController extends ChangeNotifier {
  BatteryController(this._battery) {
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  final PhoneBatteryService _battery;
  late final Timer _timer;

  int? percentage;
  bool? isCharging;

  Future<void> _refresh() async {
    percentage = await _battery.getBatteryPercentage();
    isCharging = await _battery.getChargingState();
    notifyListeners();
  }

  Future<void> refreshNow() => _refresh();

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
