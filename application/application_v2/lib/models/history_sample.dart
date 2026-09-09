/// One entry inside a `history` packet's `samples` array.
class HistorySample {
  const HistorySample({
    required this.timestamp,
    required this.sessionId,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.sessionEnergyWh,
    required this.charging,
    required this.pathEnabled,
  });

  final int timestamp;
  final String? sessionId;
  final double voltageV;
  final double currentA;
  final double powerW;
  final double sessionEnergyWh;
  final bool charging;
  final bool pathEnabled;

  static HistorySample? tryParse(Map<String, dynamic> json) {
    try {
      return HistorySample(
        timestamp: (json['timestamp'] as num).toInt(),
        sessionId: json['session_id']?.toString(),
        voltageV: (json['voltage_v'] as num?)?.toDouble() ?? 0,
        currentA: (json['current_a'] as num?)?.toDouble() ?? 0,
        powerW: (json['power_w'] as num?)?.toDouble() ?? 0,
        sessionEnergyWh: (json['session_energy_wh'] as num?)?.toDouble() ?? 0,
        charging: json['charging'] as bool? ?? false,
        pathEnabled: json['path_enabled'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime get time =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
}

/// A raw `history` packet: `request_id`, `total_chunks`, `samples`.
/// The HISTORY characteristic may deliver the full sample set split across
/// several BLE notifications sharing the same request_id; the caller is
/// responsible for reassembling chunks (see [Esp32BleService.getHistory]).
class HistoryChunk {
  const HistoryChunk({
    required this.requestId,
    required this.totalChunks,
    required this.chunkIndex,
    required this.samples,
  });

  final int requestId;
  final int totalChunks;
  final int chunkIndex;
  final List<HistorySample> samples;

  static HistoryChunk? tryParse(Map<String, dynamic> json) {
    try {
      if (json['type'] != 'history') return null;
      final rawSamples = json['samples'];
      if (rawSamples is! List) return null;

      final samples = <HistorySample>[];
      for (final s in rawSamples) {
        if (s is Map) {
          final parsed = HistorySample.tryParse(Map<String, dynamic>.from(s));
          if (parsed != null) samples.add(parsed);
        }
      }

      return HistoryChunk(
        requestId: (json['request_id'] as num?)?.toInt() ?? 0,
        totalChunks: (json['total_chunks'] as num?)?.toInt() ?? 1,
        chunkIndex: (json['chunk_index'] as num?)?.toInt() ?? 0,
        samples: samples,
      );
    } catch (_) {
      return null;
    }
  }
}
