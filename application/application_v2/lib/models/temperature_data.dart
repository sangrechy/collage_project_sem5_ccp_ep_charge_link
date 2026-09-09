class TemperatureData {
  const TemperatureData({
    required this.temperatureCelsius,
    required this.timestamp,
  });

  final double? temperatureCelsius;
  final DateTime timestamp;

  bool get isAvailable => temperatureCelsius != null;

  factory TemperatureData.unavailable() => TemperatureData(
        temperatureCelsius: null,
        timestamp: DateTime.now(),
      );

  factory TemperatureData.fromJson(Map<String, dynamic> json) {
    return TemperatureData(
      temperatureCelsius: (json['temperature_c'] as num?)?.toDouble(),
      timestamp: DateTime.now(),
    );
  }
}
