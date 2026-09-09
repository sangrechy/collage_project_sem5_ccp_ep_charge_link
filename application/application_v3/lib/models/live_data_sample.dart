class LiveDataSample {
  const LiveDataSample({
    required this.timestamp,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.charging,
    required this.pathEnabled,
    required this.chargingLimit,
    required this.ina219Available,
    required this.sessionEnergyWh,
    required this.totalEnergyWh,
    required this.receivedAt,
  });

  final int timestamp;
  final double voltageV;
  final double currentA;
  final double powerW;
  final bool charging;
  final bool pathEnabled;
  final int chargingLimit;
  final bool ina219Available;
  final double sessionEnergyWh;
  final double totalEnergyWh;
  final DateTime receivedAt;

  static LiveDataSample? tryParse(Map<String, dynamic> json) {
    try {
      final data = json['data'];
      if (json['type'] != 'live_data' || data is! Map) return null;
      final d = Map<String, dynamic>.from(data);

      num req(String key) {
        final v = d[key];
        if (v is num) return v;
        throw FormatException('missing field $key');
      }

      return LiveDataSample(
        timestamp: req('timestamp').toInt(),
        voltageV: req('voltage_v').toDouble(),
        currentA: req('current_a').toDouble(),
        powerW: req('power_w').toDouble(),
        charging: d['charging'] as bool? ?? false,
        pathEnabled: d['path_enabled'] as bool? ?? false,
        chargingLimit: (d['charging_limit'] as num?)?.toInt() ?? 100,
        ina219Available: d['ina219_available'] as bool? ?? false,
        sessionEnergyWh: (d['session_energy_wh'] as num?)?.toDouble() ?? 0.0,
        totalEnergyWh: (d['total_energy_wh'] as num?)?.toDouble() ?? 0.0,
        receivedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
