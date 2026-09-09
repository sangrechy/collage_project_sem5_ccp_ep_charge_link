class SessionData {
  const SessionData({
    required this.active,
    required this.sessionId,
    required this.durationSeconds,
    required this.energyWh,
    required this.peakPowerW,
    required this.averagePowerW,
  });

  final bool active;
  final int sessionId;
  final int durationSeconds;
  final double energyWh;
  final double peakPowerW;
  final double averagePowerW;

  String get durationFormatted {
    final hours = (durationSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((durationSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  factory SessionData.initial() => const SessionData(
        active: false,
        sessionId: 0,
        durationSeconds: 0,
        energyWh: 0.0,
        peakPowerW: 0.0,
        averagePowerW: 0.0,
      );

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      active: json['active'] as bool? ?? false,
      sessionId: (json['session_id'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      energyWh: (json['energy_wh'] as num?)?.toDouble() ??
          (json['session_energy_wh'] as num?)?.toDouble() ??
          0.0,
      peakPowerW: (json['peak_power_w'] as num?)?.toDouble() ?? 0.0,
      averagePowerW: (json['average_power_w'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
