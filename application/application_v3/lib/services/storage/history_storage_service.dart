import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class HistoricalDataPoint {
  const HistoricalDataPoint({
    required this.time,
    required this.boxVoltage,
    required this.boxCurrent,
    required this.boxPower,
    required this.phoneVoltage,
    required this.phoneCurrent,
    required this.phonePower,
    required this.batteryPercentage,
    required this.temperatureC,
    required this.isCharging,
  });

  final DateTime time;
  final double boxVoltage;
  final double boxCurrent;
  final double boxPower;
  final double phoneVoltage;
  final double phoneCurrent;
  final double phonePower;
  final int batteryPercentage;
  final double temperatureC;
  final bool isCharging;

  double get lossW => (boxPower - phonePower).clamp(0.0, 99.0);
  double get efficiency => boxPower > 0.05 ? ((phonePower / boxPower) * 100.0).clamp(0.0, 100.0) : 100.0;

  Map<String, dynamic> toJson() => {
    't': time.toIso8601String(),
    'bv': boxVoltage,
    'ba': boxCurrent,
    'bw': boxPower,
    'pv': phoneVoltage,
    'pa': phoneCurrent,
    'pw': phonePower,
    'bat': batteryPercentage,
    'temp': temperatureC,
    'chg': isCharging,
  };

  static HistoricalDataPoint? fromJson(Map<String, dynamic> json) {
    try {
      return HistoricalDataPoint(
        time: DateTime.parse(json['t'] as String),
        boxVoltage: (json['bv'] as num).toDouble(),
        boxCurrent: (json['ba'] as num).toDouble(),
        boxPower: (json['bw'] as num).toDouble(),
        phoneVoltage: (json['pv'] as num).toDouble(),
        phoneCurrent: (json['pa'] as num).toDouble(),
        phonePower: (json['pw'] as num).toDouble(),
        batteryPercentage: (json['bat'] as num).toInt(),
        temperatureC: (json['temp'] as num?)?.toDouble() ?? 32.5,
        isCharging: json['chg'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

class HistoryStorageService {
  HistoryStorageService({Directory? baseDir}) : _customDir = baseDir;

  final Directory? _customDir;
  Directory? _resolvedDir;
  DateTime _lastSaveTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<Directory> get storageDirectory async {
    if (_resolvedDir != null) return _resolvedDir!;
    if (_customDir != null) {
      _resolvedDir = _customDir;
      return _resolvedDir!;
    }

    // Android app-internal private storage
    const androidInternalPath = '/data/user/0/com.chargelink.application_v3/files/chargelink_history';
    final androidDir = Directory(androidInternalPath);
    try {
      if (await androidDir.parent.exists()) {
        if (!await androidDir.exists()) {
          await androidDir.create(recursive: true);
        }
        _resolvedDir = androidDir;
        return _resolvedDir!;
      }
    } catch (_) {}

    // Fallback for desktop / host testing
    final tempDir = Directory('${Directory.systemTemp.path}/chargelink_history_v3');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    _resolvedDir = tempDir;
    return _resolvedDir!;
  }

  Future<void> init() async {
    await pruneOldRecords(daysToKeep: 60);
  }

  String _dateFilename(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return 'history_${y}_${m}_$d.json';
  }

  DateTime? _parseDateFromFilename(String filename) {
    try {
      if (!filename.startsWith('history_') || !filename.endsWith('.json')) return null;
      final body = filename.substring('history_'.length, filename.length - '.json'.length);
      final parts = body.split('_');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    } catch (_) {}
    return null;
  }

  /// Automatically deletes history files older than [daysToKeep] (default 60 days).
  Future<void> pruneOldRecords({int daysToKeep = 60}) async {
    try {
      final dir = await storageDirectory;
      final now = DateTime.now();
      final cutoffDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysToKeep));

      if (await dir.exists()) {
        final entries = dir.listSync();
        for (final entry in entries) {
          if (entry is File) {
            final name = entry.uri.pathSegments.last;
            final fileDate = _parseDateFromFilename(name);
            if (fileDate != null && fileDate.isBefore(cutoffDate)) {
              await entry.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('History pruning notice: $e');
    }
  }

  /// Appends a live sample to today's partitioned daily log.
  /// Throttled to ~8s intervals to keep storage compact over 60 days (~150KB/day).
  Future<void> recordSample({
    required double boxVoltage,
    required double boxCurrent,
    required double boxPower,
    required double phoneVoltage,
    required double phoneCurrent,
    required double phonePower,
    required int batteryPercentage,
    required double temperatureC,
    required bool isCharging,
  }) async {
    final now = DateTime.now();
    if (now.difference(_lastSaveTime).inSeconds < 8) return;
    _lastSaveTime = now;

    try {
      final dir = await storageDirectory;
      final filename = _dateFilename(now);
      final file = File('${dir.path}/$filename');

      final point = HistoricalDataPoint(
        time: now,
        boxVoltage: double.parse(boxVoltage.toStringAsFixed(2)),
        boxCurrent: double.parse(boxCurrent.toStringAsFixed(2)),
        boxPower: double.parse(boxPower.toStringAsFixed(2)),
        phoneVoltage: double.parse(phoneVoltage.toStringAsFixed(2)),
        phoneCurrent: double.parse(phoneCurrent.toStringAsFixed(2)),
        phonePower: double.parse(phonePower.toStringAsFixed(2)),
        batteryPercentage: batteryPercentage,
        temperatureC: double.parse(temperatureC.toStringAsFixed(1)),
        isCharging: isCharging,
      );

      List<dynamic> raw = [];
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final parsed = jsonDecode(content);
          if (parsed is List) raw = parsed;
        } catch (_) {}
      }

      raw.add(point.toJson());
      await file.writeAsString(jsonEncode(raw));
    } catch (e) {
      debugPrint('Error recording historical sample: $e');
    }
  }

  /// Retrieves all recorded samples for a specific 24-hour day.
  Future<List<HistoricalDataPoint>> getSamplesForDate(DateTime date) async {
    try {
      final dir = await storageDirectory;
      final filename = _dateFilename(date);
      final file = File('${dir.path}/$filename');

      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];

      final list = <HistoricalDataPoint>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final pt = HistoricalDataPoint.fromJson(item);
          if (pt != null) list.add(pt);
        } else if (item is Map) {
          final pt = HistoricalDataPoint.fromJson(Map<String, dynamic>.from(item));
          if (pt != null) list.add(pt);
        }
      }
      list.sort((a, b) => a.time.compareTo(b.time));
      return list;
    } catch (e) {
      debugPrint('Error loading samples for date: $e');
      return [];
    }
  }

  /// Retrieves all recorded samples for a 7-day window ending on [endDate].
  Future<List<HistoricalDataPoint>> getSamplesForWeek(DateTime endDate) async {
    final all = <HistoricalDataPoint>[];
    for (int i = 6; i >= 0; i--) {
      final targetDate = endDate.subtract(Duration(days: i));
      final daySamples = await getSamplesForDate(targetDate);
      all.addAll(daySamples);
    }
    all.sort((a, b) => a.time.compareTo(b.time));
    return all;
  }
}
