class PowerData {
  const PowerData({
    required this.voltage,
    required this.current,
    required this.power,
    required this.energyWh,
  });

  final double voltage;
  final double current;
  final double power;
  final double energyWh;

  factory PowerData.zero() =>
      const PowerData(voltage: 0, current: 0, power: 0, energyWh: 0);

  factory PowerData.fromJson(Map<String, dynamic> json) {
    return PowerData(
      voltage: (json['voltage_v'] as num?)?.toDouble() ?? 0,
      current: (json['current_a'] as num?)?.toDouble() ?? 0,
      power: (json['power_w'] as num?)?.toDouble() ?? 0,
      energyWh: (json['session_energy_wh'] as num?)?.toDouble() ?? 0,
    );
  }
}
