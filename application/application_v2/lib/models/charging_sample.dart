class ChargingSample {
  const ChargingSample({
    required this.timestamp,
    required this.sessionId,
    required this.voltage,
    required this.current,
    required this.power,
    required this.energyWh,
    required this.charging,
    this.batteryPercent,
    this.batteryTemperature,
    this.batteryVoltage,
    this.batteryCurrent,
    this.batteryHealth,
  });

  final DateTime timestamp;
  final String sessionId;
  final double voltage;
  final double current;
  final double power;
  final double energyWh;
  final bool charging;
  final int? batteryPercent;
  final double? batteryTemperature;
  final double? batteryVoltage;
  final double? batteryCurrent;
  final double? batteryHealth;

  factory ChargingSample.fromJson(Map<String, dynamic> json) {
    return ChargingSample(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((json['timestamp'] as num?)?.toInt() ?? 0) * 1000,
      ),
      sessionId: json['session_id']?.toString() ?? 'UNKNOWN',
      voltage: (json['voltage_v'] as num?)?.toDouble() ?? 0,
      current: (json['current_a'] as num?)?.toDouble() ?? 0,
      power: (json['power_w'] as num?)?.toDouble() ?? 0,
      energyWh: (json['session_energy_wh'] as num?)?.toDouble() ?? 0,
      charging: json['charging'] as bool? ?? false,
    );
  }
}
