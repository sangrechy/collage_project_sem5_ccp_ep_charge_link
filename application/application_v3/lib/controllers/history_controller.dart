import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/esp32/esp32_service.dart';
import '../services/storage/history_storage_service.dart';

enum HistoryViewRange { day, week }

class HistoryController extends ChangeNotifier {
  HistoryController(this._esp32, this._storage) {
    _init();
  }

  final Esp32Service _esp32;
  final HistoryStorageService _storage;

  Esp32Service get esp32 => _esp32;

  HistoryViewRange _range = HistoryViewRange.day;
  HistoryViewRange get range => _range;

  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<HistoricalDataPoint> _points = [];
  List<HistoricalDataPoint> get points => _points;

  Future<void> _init() async {
    await _storage.init();
    await loadData();
  }

  bool get canGoNext {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cur = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return cur.isBefore(today);
  }

  String get dateRangeLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    if (_range == HistoryViewRange.day) {
      if (target == today) return 'Today, ${_formatDate(_selectedDate)}';
      if (target == today.subtract(const Duration(days: 1))) return 'Yesterday, ${_formatDate(_selectedDate)}';
      return _formatDate(_selectedDate);
    } else {
      final start = _selectedDate.subtract(const Duration(days: 6));
      return '${_formatShortDate(start)} – ${_formatDate(_selectedDate)}';
    }
  }

  static String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _formatShortDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  void setRange(HistoryViewRange r) {
    if (_range != r) {
      _range = r;
      loadData();
    }
  }

  void previous() {
    if (_range == HistoryViewRange.day) {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    } else {
      _selectedDate = _selectedDate.subtract(const Duration(days: 7));
    }
    loadData();
  }

  void next() {
    if (!canGoNext) return;

    if (_range == HistoryViewRange.day) {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    } else {
      _selectedDate = _selectedDate.add(const Duration(days: 7));
    }

    final now = DateTime.now();
    if (_selectedDate.isAfter(now)) {
      _selectedDate = now;
    }
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_range == HistoryViewRange.day) {
        _points = await _storage.getSamplesForDate(_selectedDate);
      } else {
        _points = await _storage.getSamplesForWeek(_selectedDate);
      }
    } catch (_) {
      _points = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // Summary Metrics: Battery
  int get minBattery => _points.isEmpty ? 0 : _points.map((p) => p.batteryPercentage).reduce((a, b) => a < b ? a : b);
  int get maxBattery => _points.isEmpty ? 0 : _points.map((p) => p.batteryPercentage).reduce((a, b) => a > b ? a : b);
  int get latestBattery => _points.isEmpty ? 0 : _points.last.batteryPercentage;

  // Summary Metrics: Temperature
  double get minTemperature => _points.isEmpty ? 0.0 : _points.map((p) => p.temperatureC).reduce((a, b) => a < b ? a : b);
  double get maxTemperature => _points.isEmpty ? 0.0 : _points.map((p) => p.temperatureC).reduce((a, b) => a > b ? a : b);
  double get latestTemperature => _points.isEmpty ? 0.0 : _points.last.temperatureC;

  // Summary Metrics: Energy & Efficiency
  double get totalBoxEnergyWh {
    if (_points.length < 2) return 0.0;
    double sum = 0.0;
    for (int i = 1; i < _points.length; i++) {
      final hours = _points[i].time.difference(_points[i - 1].time).inSeconds / 3600.0;
      if (hours > 0 && hours < 0.25) {
        sum += _points[i].boxPower * hours;
      }
    }
    return double.parse(sum.toStringAsFixed(2));
  }

  double get totalPhoneEnergyWh {
    if (_points.length < 2) return 0.0;
    double sum = 0.0;
    for (int i = 1; i < _points.length; i++) {
      final hours = _points[i].time.difference(_points[i - 1].time).inSeconds / 3600.0;
      if (hours > 0 && hours < 0.25) {
        sum += _points[i].phonePower * hours;
      }
    }
    return double.parse(sum.toStringAsFixed(2));
  }

  double get avgEfficiency {
    final bW = totalBoxEnergyWh;
    final pW = totalPhoneEnergyWh;
    if (bW <= 0.01) return 100.0;
    return ((pW / bW) * 100.0).clamp(0.0, 100.0);
  }
}
