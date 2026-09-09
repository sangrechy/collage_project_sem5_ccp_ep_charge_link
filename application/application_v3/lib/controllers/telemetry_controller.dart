import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';

import '../models/live_data_sample.dart';
import '../services/esp32/esp32_service.dart';
import '../services/phone/phone_battery_service.dart';
import '../services/storage/history_storage_service.dart';
import '../theme/app_theme.dart';

enum ChartMetric { voltage, current, power }

class GraphPoint {
  const GraphPoint(this.x, this.y);
  final double x; // seconds elapsed
  final double y;
}

class TelemetryController extends ChangeNotifier {
  TelemetryController(
    this._esp32,
    this._phoneBattery, {
    this.maxPoints = 60,
    HistoryStorageService? storageService,
  }) : _storage = storageService {
    _sub = _esp32.liveDataStream.listen(_onSample);
    _pollPhoneTelemetry();
    _phoneTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollPhoneTelemetry());
  }

  final Esp32Service _esp32;
  final PhoneBatteryService _phoneBattery;
  final HistoryStorageService? _storage;
  final int maxPoints;

  late final StreamSubscription<LiveDataSample> _sub;
  late final Timer _phoneTimer;

  LiveDataSample? _latest;
  LiveDataSample? get latest => _latest;

  PhoneBatteryTelemetry? _latestPhone;
  PhoneBatteryTelemetry? get latestPhone => _latestPhone;

  DateTime? _windowStart;
  ChartMetric _selectedMetric = ChartMetric.voltage;
  ChartMetric get selectedMetric => _selectedMetric;

  // Dual queues for Box vs Phone
  final Queue<GraphPoint> _boxVoltage = Queue<GraphPoint>();
  final Queue<GraphPoint> _phoneVoltage = Queue<GraphPoint>();

  final Queue<GraphPoint> _boxCurrent = Queue<GraphPoint>();
  final Queue<GraphPoint> _phoneCurrent = Queue<GraphPoint>();

  final Queue<GraphPoint> _boxPower = Queue<GraphPoint>();
  final Queue<GraphPoint> _phonePower = Queue<GraphPoint>();

  List<GraphPoint> get currentBoxPoints {
    switch (_selectedMetric) {
      case ChartMetric.voltage:
        return _boxVoltage.toList();
      case ChartMetric.current:
        return _boxCurrent.toList();
      case ChartMetric.power:
        return _boxPower.toList();
    }
  }

  List<GraphPoint> get currentPhonePoints {
    switch (_selectedMetric) {
      case ChartMetric.voltage:
        return _phoneVoltage.toList();
      case ChartMetric.current:
        return _phoneCurrent.toList();
      case ChartMetric.power:
        return _phonePower.toList();
    }
  }

  // Backwards compatibility getter
  List<GraphPoint> get currentPoints => currentBoxPoints;

  double get latestBoxValue {
    if (_latest == null) return 0.0;
    switch (_selectedMetric) {
      case ChartMetric.voltage:
        return _latest!.voltageV;
      case ChartMetric.current:
        return _latest!.currentA;
      case ChartMetric.power:
        return _latest!.powerW;
    }
  }

  double get latestPhoneValue {
    if (_latestPhone == null) return 0.0;
    switch (_selectedMetric) {
      case ChartMetric.voltage:
        return _latestPhone!.voltageV;
      case ChartMetric.current:
        return _latestPhone!.currentA;
      case ChartMetric.power:
        return _latestPhone!.powerW;
    }
  }

  double get powerLoss {
    final bW = _latest?.powerW ?? 0.0;
    final pW = _latestPhone?.powerW ?? 0.0;
    if (bW <= 0.1 || pW <= 0.1) return 0.0;
    return (bW - pW).clamp(0.0, 99.0);
  }

  double get efficiencyPercent {
    final bW = _latest?.powerW ?? 0.0;
    final pW = _latestPhone?.powerW ?? 0.0;
    if (bW <= 0.1 || pW <= 0.1) return 100.0;
    return ((pW / bW) * 100.0).clamp(0.0, 100.0);
  }

  String get metricUnit {
    switch (_selectedMetric) {
      case ChartMetric.voltage:
        return 'V';
      case ChartMetric.current:
        return 'A';
      case ChartMetric.power:
        return 'W';
    }
  }

  Color get metricColor {
    switch (_selectedMetric) {
      case ChartMetric.voltage:
        return AppColors.cyan;
      case ChartMetric.current:
        return AppColors.amber;
      case ChartMetric.power:
        return AppColors.green;
    }
  }

  void selectMetric(ChartMetric metric) {
    if (_selectedMetric != metric) {
      _selectedMetric = metric;
      notifyListeners();
    }
  }

  Future<void> _pollPhoneTelemetry() async {
    final phone = await _phoneBattery.getTelemetry();
    _latestPhone = phone;

    // If Smart Box is disconnected or hasn't started streaming, push phone points
    // so live charts and cards reflect real-time phone state immediately.
    if (_latest == null) {
      _windowStart ??= DateTime.now();
      final x = DateTime.now().difference(_windowStart!).inMilliseconds / 1000.0;
      _pushBounded(_phoneVoltage, GraphPoint(x, phone.voltageV));
      _pushBounded(_phoneCurrent, GraphPoint(x, phone.currentA));
      _pushBounded(_phonePower, GraphPoint(x, phone.powerW));

      _storage?.recordSample(
        boxVoltage: 0.0,
        boxCurrent: 0.0,
        boxPower: 0.0,
        phoneVoltage: phone.voltageV,
        phoneCurrent: phone.currentA,
        phonePower: phone.powerW,
        batteryPercentage: phone.percentage,
        temperatureC: phone.temperatureC,
        isCharging: phone.isCharging,
      );
    }
    notifyListeners();
  }

  Future<void> _onSample(LiveDataSample sample) async {
    _latest = sample;
    _windowStart ??= sample.receivedAt;

    final x = sample.receivedAt.difference(_windowStart!).inMilliseconds / 1000.0;

    // Fetch genuine phone hardware telemetry independently (NO derivation from Smart Box!)
    final phone = await _phoneBattery.getTelemetry();
    _latestPhone = phone;

    // Push Smart Box hardware INA219 points
    _pushBounded(_boxVoltage, GraphPoint(x, sample.voltageV));
    _pushBounded(_boxCurrent, GraphPoint(x, sample.currentA));
    _pushBounded(_boxPower, GraphPoint(x, sample.powerW));

    // Push Real Phone Battery hardware points
    _pushBounded(_phoneVoltage, GraphPoint(x, phone.voltageV));
    _pushBounded(_phoneCurrent, GraphPoint(x, phone.currentA));
    _pushBounded(_phonePower, GraphPoint(x, phone.powerW));

    // Record sample to 60-day storage
    _storage?.recordSample(
      boxVoltage: sample.voltageV,
      boxCurrent: sample.currentA,
      boxPower: sample.powerW,
      phoneVoltage: phone.voltageV,
      phoneCurrent: phone.currentA,
      phonePower: phone.powerW,
      batteryPercentage: phone.percentage,
      temperatureC: phone.temperatureC,
      isCharging: phone.isCharging,
    );

    notifyListeners();
  }

  void _pushBounded(Queue<GraphPoint> q, GraphPoint p) {
    q.addLast(p);
    while (q.length > maxPoints) {
      q.removeFirst();
    }
  }

  void reset() {
    _boxVoltage.clear();
    _boxCurrent.clear();
    _boxPower.clear();
    _phoneVoltage.clear();
    _phoneCurrent.clear();
    _phonePower.clear();
    _windowStart = null;
    _latest = null;
    _latestPhone = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    _phoneTimer.cancel();
    super.dispose();
  }
}
