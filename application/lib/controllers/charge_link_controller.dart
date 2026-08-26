import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/repository_factory.dart';
import '../models/app_snapshot.dart';
import '../repositories/charge_link_repository.dart';

class ChargeLinkController extends ChangeNotifier {
  ChargeLinkController({
    ChargeLinkRepository? repository,
  }) : _repository =
      repository ?? RepositoryFactory.create();

  final ChargeLinkRepository _repository;

  AppSnapshot? _snapshot;
  bool _loading = false;
  bool _connected = false;
  String? _errorMessage;

  Timer? _refreshTimer;
  StreamSubscription<bool>? _connectionSubscription;

  AppSnapshot? get snapshot => _snapshot;

  bool get loading => _loading;

  bool get connected => _connected;

  String? get errorMessage => _errorMessage;

  bool get charging => _snapshot?.charging ?? false;

  int get chargingLimit =>
      _snapshot?.chargingLimit ?? 80;

  int? get batteryPercentage =>
      _snapshot?.phoneBatteryPercentage;

  bool? get phoneCharging =>
      _snapshot?.phoneCharging;

  double? get voltage =>
      _snapshot?.powerData.voltage;

  double? get current =>
      _snapshot?.powerData.current;

  double? get power =>
      _snapshot?.powerData.power;

  double? get temperature =>
      _snapshot?.temperatureData.temperatureCelsius;

  double get sessionEnergyWh =>
      _snapshot?.energyData.sessionEnergyWh ?? 0.0;

  double get totalEnergyWh =>
      _snapshot?.energyData.totalEnergyWh ?? 0.0;

  double? get batteryHealth =>
      _snapshot?.phoneBatteryHealth;

  Future<void> initialize() async {
    _errorMessage = null;
    notifyListeners();

    _listenToConnection();

    try {
      await _repository.connect();

      _connected = true;

      await refresh();

      _startAutoRefresh();
    } catch (error) {
      _connected = false;
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  void _listenToConnection() {
    _connectionSubscription?.cancel();

    _connectionSubscription =
        _repository.connectionState.listen(
              (connected) {
            _connected = connected;

            if (!connected) {
              _snapshot = null;
            }

            notifyListeners();
          },
          onError: (Object error) {
            _errorMessage = error.toString();
            notifyListeners();
          },
        );
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
          (_) {
        refresh();
      },
    );
  }

  Future<void> refresh() async {
    if (!_connected || _loading) {
      return;
    }

    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final snapshot =
      await _repository.getAppSnapshot();

      _snapshot = snapshot;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> startCharging() async {
    if (!_connected) {
      return;
    }

    try {
      await _repository.startCharging();
      await refresh();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> stopCharging() async {
    if (!_connected) {
      return;
    }

    try {
      await _repository.stopCharging();
      await refresh();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> setChargingLimit(
      int percentage,
      ) async {
    if (!_connected) {
      return;
    }

    if (percentage < 0 || percentage > 100) {
      _errorMessage =
      'Charging limit must be between 0 and 100.';
      notifyListeners();
      return;
    }

    try {
      await _repository.setChargingLimit(
        percentage,
      );

      await refresh();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> connect() async {
    try {
      _errorMessage = null;
      notifyListeners();

      await _repository.connect();

      _connected = true;

      await refresh();

      _startAutoRefresh();
    } catch (error) {
      _connected = false;
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _refreshTimer?.cancel();

    try {
      await _repository.disconnect();
    } catch (error) {
      _errorMessage = error.toString();
    }

    _connected = false;
    _snapshot = null;

    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _connectionSubscription?.cancel();

    super.dispose();
  }
}