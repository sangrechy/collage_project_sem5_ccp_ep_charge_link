import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/live_data_sample.dart';
import '../services/ble/esp32_service.dart';

/// Point for the rolling live graphs.
class GraphPoint {
  const GraphPoint(this.x, this.y);
  final double x; // seconds since first sample in the window
  final double y;
}

/// Subscribes once to the ESP32's live-data stream and fans it out to the
/// three graphs plus the dashboard telemetry cards — the app never polls
/// get_power/get_sample separately for graph data.
class TelemetryController extends ChangeNotifier {
  TelemetryController(Esp32Service esp32, {this.maxPoints = 90}) {
    _sub = esp32.liveDataStream.listen(_onSample);
  }

  final int maxPoints;
  late final StreamSubscription<LiveDataSample> _sub;

  LiveDataSample? _latest;
  LiveDataSample? get latest => _latest;

  DateTime? _windowStart;

  final Queue<GraphPoint> _voltage = Queue<GraphPoint>();
  final Queue<GraphPoint> _current = Queue<GraphPoint>();
  final Queue<GraphPoint> _power = Queue<GraphPoint>();

  UnmodifiableListView<GraphPoint> get voltagePoints =>
      UnmodifiableListView(_voltage);
  UnmodifiableListView<GraphPoint> get currentPoints =>
      UnmodifiableListView(_current);
  UnmodifiableListView<GraphPoint> get powerPoints =>
      UnmodifiableListView(_power);

  void _onSample(LiveDataSample sample) {
    _latest = sample;
    _windowStart ??= sample.receivedAt;

    final x = sample.receivedAt
        .difference(_windowStart!)
        .inMilliseconds /
        1000.0;

    _pushBounded(_voltage, GraphPoint(x, sample.voltageV));
    _pushBounded(_current, GraphPoint(x, sample.currentA));
    _pushBounded(_power, GraphPoint(x, sample.powerW));

    notifyListeners();
  }

  void _pushBounded(Queue<GraphPoint> q, GraphPoint p) {
    q.addLast(p);
    while (q.length > maxPoints) {
      q.removeFirst();
    }
  }

  void reset() {
    _voltage.clear();
    _current.clear();
    _power.clear();
    _windowStart = null;
    _latest = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
