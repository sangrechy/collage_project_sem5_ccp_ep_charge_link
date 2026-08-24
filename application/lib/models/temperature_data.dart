class TemperatureData {
  const TemperatureData({
    required this.temperatureCelsius,
    required this.timestamp,
  });

  final double? temperatureCelsius;
  final DateTime timestamp;
}