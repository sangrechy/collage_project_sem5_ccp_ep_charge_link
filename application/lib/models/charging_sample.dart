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

  // ESP32 / charger-side data
  final double voltage;
  final double current;
  final double power;
  final double energyWh;
  final bool charging;

  // Phone-side data
  final int? batteryPercent;
  final double? batteryTemperature;
  final double? batteryVoltage;
  final double? batteryCurrent;
  final double? batteryHealth;
}