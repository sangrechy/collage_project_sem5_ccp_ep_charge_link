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

  String get uptimeFormatted {
    final hours = (timestamp ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((timestamp % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (timestamp % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static HistorySample? tryParse(Map<String, dynamic> json) {
    try {
      return HistorySample(
        timestamp: (json['timestamp'] as num).toInt(),
        sessionId: json['session_id']?.toString(),
        voltageV: (json['voltage_v'] as num?)?.toDouble() ?? 0.0,
        currentA: (json['current_a'] as num?)?.toDouble() ?? 0.0,
        powerW: (json['power_w'] as num?)?.toDouble() ?? 0.0,
        sessionEnergyWh: (json['session_energy_wh'] as num?)?.toDouble() ?? 0.0,
        charging: json['charging'] as bool? ?? false,
        pathEnabled: json['path_enabled'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
