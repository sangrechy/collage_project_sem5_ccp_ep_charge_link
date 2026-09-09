class EnergyData {
  const EnergyData({
    required this.sessionEnergyWh,
    required this.totalEnergyWh,
  });

  final double sessionEnergyWh;
  final double totalEnergyWh;

  factory EnergyData.zero() =>
      const EnergyData(sessionEnergyWh: 0, totalEnergyWh: 0);

  factory EnergyData.fromJson(Map<String, dynamic> json) {
    return EnergyData(
      sessionEnergyWh: (json['session_energy_wh'] as num?)?.toDouble() ?? 0,
      totalEnergyWh: (json['total_energy_wh'] as num?)?.toDouble() ?? 0,
    );
  }
}
