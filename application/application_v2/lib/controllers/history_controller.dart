import 'package:flutter/foundation.dart';

import '../models/history_sample.dart';
import '../services/ble/esp32_service.dart';

enum HistoryStatus { idle, loading, loaded, error }

class HistoryController extends ChangeNotifier {
  HistoryController(this._esp32);

  final Esp32Service _esp32;

  HistoryStatus status = HistoryStatus.idle;
  List<HistorySample> samples = [];
  String? error;

  Future<void> load({int limit = 100}) async {
    status = HistoryStatus.loading;
    error = null;
    notifyListeners();
    try {
      samples = await _esp32.getHistory(limit: limit);
      // Firmware stores history in RAM only, most-recent-first is not
      // guaranteed — sort by timestamp so the UI reads chronologically.
      samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      status = HistoryStatus.loaded;
    } catch (e) {
      error = 'Could not load history: $e';
      status = HistoryStatus.error;
    }
    notifyListeners();
  }
}
