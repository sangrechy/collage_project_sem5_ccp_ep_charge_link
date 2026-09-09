import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PhoneBatteryTelemetry {
  const PhoneBatteryTelemetry({
    required this.percentage,
    required this.isCharging,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.temperatureC,
    this.isPlugged = false,
    this.dischargePowerW = 0.0,
    this.isDualCell = false,
  });

  final int percentage;
  final bool isCharging;
  final bool isPlugged;
  final double voltageV;
  final double currentA;
  final double powerW;
  final double temperatureC;
  final double dischargePowerW;
  final bool isDualCell;
}

abstract class PhoneBatteryService {
  Future<int?> getBatteryPercentage();
  Future<bool?> getChargingState();
  Future<PhoneBatteryTelemetry> getTelemetry({double? boxVoltage, double? boxCurrent});
}

class BatteryPlusPhoneBatteryService implements PhoneBatteryService {
  BatteryPlusPhoneBatteryService({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;
  static const MethodChannel _channel =
      MethodChannel('com.chargelink.application_v3/battery_telemetry');

  @override
  Future<int?> getBatteryPercentage() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getBatteryTelemetry');
      if (res != null && res['percentage'] != null && (res['percentage'] as num) >= 0) {
        return (res['percentage'] as num).toInt();
      }
      return await _battery.batteryLevel;
    } catch (_) {
      try {
        return await _battery.batteryLevel;
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Future<bool?> getChargingState() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getBatteryTelemetry');
      if (res != null && res['isCharging'] != null) {
        return res['isCharging'] as bool;
      }
      final state = await _battery.batteryState;
      return state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PhoneBatteryTelemetry> getTelemetry({double? boxVoltage, double? boxCurrent}) async {
    // Query physical hardware sensors directly from Android BatteryManager
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getBatteryTelemetry');
      if (res != null) {
        final pct = (res['percentage'] as num?)?.toInt() ?? await getBatteryPercentage() ?? 50;
        final charging = (res['isCharging'] as bool?) ?? false;
        final plugged = (res['isPlugged'] as bool?) ?? false;
        final v = (res['voltageV'] as num?)?.toDouble() ?? 0.0;
        final a = (res['currentA'] as num?)?.toDouble() ?? 0.0;
        final w = (res['powerW'] as num?)?.toDouble() ?? (v * a);
        final temp = (res['temperatureC'] as num?)?.toDouble() ?? 25.0;
        final dischargeW = (res['dischargePowerW'] as num?)?.toDouble() ?? 0.0;
        final dualCell = (res['isDualCell'] as bool?) ?? false;

        debugPrint(
            'NATIVE PHONE BATTERY TELEMETRY: pct=$pct, charging=$charging, plugged=$plugged, V=${v.toStringAsFixed(2)}, A=${a.toStringAsFixed(2)}, W=${w.toStringAsFixed(2)}, temp=${temp.toStringAsFixed(1)}C, dischargeW=${dischargeW.toStringAsFixed(2)}');

        return PhoneBatteryTelemetry(
          percentage: pct,
          isCharging: charging,
          isPlugged: plugged,
          voltageV: double.parse(v.toStringAsFixed(2)),
          currentA: double.parse(a.toStringAsFixed(2)),
          powerW: double.parse(w.toStringAsFixed(2)),
          temperatureC: double.parse(temp.toStringAsFixed(1)),
          dischargePowerW: double.parse(dischargeW.toStringAsFixed(2)),
          isDualCell: dualCell,
        );
      }
    } catch (_) {}

    // Fallback if native channel unavailable
    final level = await getBatteryPercentage() ?? 75;
    final charging = await getChargingState() ?? false;
    final v = 3.85 + (level / 100.0) * 0.45;
    final a = charging ? 0.90 : 0.0;
    final w = charging ? (v * a + 1.3) : 0.0;

    return PhoneBatteryTelemetry(
      percentage: level,
      isCharging: charging,
      voltageV: double.parse(v.toStringAsFixed(2)),
      currentA: double.parse(a.toStringAsFixed(2)),
      powerW: double.parse(w.toStringAsFixed(2)),
      temperatureC: 30.0,
    );
  }
}

class MockPhoneBatteryService implements PhoneBatteryService {
  MockPhoneBatteryService({
    this.mockPercentage = 78,
    this.mockCharging = true,
    this.mockTemperature = 34.8,
  });

  int mockPercentage;
  bool mockCharging;
  double mockTemperature;

  @override
  Future<int?> getBatteryPercentage() async => mockPercentage;

  @override
  Future<bool?> getChargingState() async => mockCharging;

  @override
  Future<PhoneBatteryTelemetry> getTelemetry({double? boxVoltage, double? boxCurrent}) async {
    final bV = boxVoltage ?? 9.16;
    final bA = boxCurrent ?? 1.87;

    double pV;
    double pA;
    double temp;
    if (mockCharging && bA > 0.05) {
      pV = bV * 0.955;
      pA = bA * 0.952;
      // Dynamic simulated temperature warming up during fast charge
      temp = 33.5 + (pA * 1.6);
    } else {
      pV = 4.10;
      pA = 0.0;
      temp = 29.2;
    }
    final pW = pV * pA;
    mockTemperature = double.parse(temp.toStringAsFixed(1));

    return PhoneBatteryTelemetry(
      percentage: mockPercentage,
      isCharging: mockCharging,
      voltageV: double.parse(pV.toStringAsFixed(2)),
      currentA: double.parse(pA.toStringAsFixed(2)),
      powerW: double.parse(pW.toStringAsFixed(2)),
      temperatureC: mockTemperature,
    );
  }
}
