/// One `live_data` packet from the LIVE DATA characteristic.
///
/// Fields match apis.txt exactly:
/// timestamp, voltage_v, current_a, power_w, charging, path_enabled,
/// charging_limit, ina219_available, session_energy_wh, total_energy_wh.
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

  /// Actual charging state derived from INA219 current measurement.
  final bool charging;

  /// Physical relay / charging-path state. NOT the same as [charging].
  final bool pathEnabled;

  final int chargingLimit;
  final bool ina219Available;
  final double sessionEnergyWh;
  final double totalEnergyWh;

  /// Local device clock at the moment this sample was parsed, used for
  /// x-axis positioning in the rolling graphs (the ESP32 timestamp is not
  /// wall-clock time).
  final DateTime receivedAt;

  /// Parses a `live_data` packet, returning null on any malformed/missing
  /// field rather than throwing — BLE data from an external device must
  /// never crash the app.
  static LiveDataSample? tryParse(Map<String, dynamic> json) {
    try {
      final data = json['data'];
      if (json['type'] != 'live_data' || data is! Map) return null;
      final d = Map<String, dynamic>.from(data);

      num req(String key) {
        final v = d[key];
        if (v is num) return v;
        throw FormatException('missing/invalid field: $key');
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
        sessionEnergyWh: (d['session_energy_wh'] as num?)?.toDouble() ?? 0,
        totalEnergyWh: (d['total_energy_wh'] as num?)?.toDouble() ?? 0,
        receivedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
