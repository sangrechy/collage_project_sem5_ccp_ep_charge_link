class DeviceStatus {
  const DeviceStatus({
    required this.connected,
    required this.charging,
    required this.relayState,
    required this.deviceName,
    this.chargingLimit,
    this.ina219Available,
  });

  final bool connected;

  /// Actual charging state, derived on the ESP32 from INA219 current.
  final bool charging;

  /// Physical relay / charging-path state. NOT the same as [charging] —
  /// the path can be enabled while the phone isn't drawing enough current
  /// to count as actively charging.
  final bool relayState;

  final String deviceName;
  final int? chargingLimit;
  final bool? ina219Available;

  DeviceStatus copyWith({
    bool? connected,
    bool? charging,
    bool? relayState,
    String? deviceName,
    int? chargingLimit,
    bool? ina219Available,
  }) {
    return DeviceStatus(
      connected: connected ?? this.connected,
      charging: charging ?? this.charging,
      relayState: relayState ?? this.relayState,
      deviceName: deviceName ?? this.deviceName,
      chargingLimit: chargingLimit ?? this.chargingLimit,
      ina219Available: ina219Available ?? this.ina219Available,
    );
  }

  factory DeviceStatus.disconnected() => const DeviceStatus(
        connected: false,
        charging: false,
        relayState: false,
        deviceName: 'CHARGE LINK',
      );

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      connected: true,
      charging: json['charging'] as bool? ?? false,
      relayState: json['path_enabled'] as bool? ?? false,
      deviceName: 'CHARGE LINK',
      chargingLimit: (json['charging_limit'] as num?)?.toInt(),
      ina219Available: json['ina219_available'] as bool?,
    );
  }
}
