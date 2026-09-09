class DeviceStatus {
  const DeviceStatus({
    required this.connected,
    required this.deviceName,
    required this.modelName,
    required this.hardwareVersion,
    required this.firmwareVersion,
    required this.protocolVersion,
    required this.ina219Available,
    required this.pathEnabled,
    required this.charging,
    required this.chargingLimit,
    required this.uptimeSeconds,
  });

  final bool connected;
  final String deviceName;
  final String modelName;
  final String hardwareVersion;
  final String firmwareVersion;
  final String protocolVersion;
  final bool ina219Available;
  final bool pathEnabled;
  final bool charging;
  final int chargingLimit;
  final int uptimeSeconds;

  factory DeviceStatus.disconnected() => const DeviceStatus(
        connected: false,
        deviceName: 'Charge Link',
        modelName: 'CL-SCB-01',
        hardwareVersion: '1.0',
        firmwareVersion: '1.0.1',
        protocolVersion: '1.0',
        ina219Available: false,
        pathEnabled: false,
        charging: false,
        chargingLimit: 80,
        uptimeSeconds: 0,
      );

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final dev = json['device'] as Map<String, dynamic>? ?? {};
    return DeviceStatus(
      connected: json['connected'] as bool? ?? true,
      deviceName: dev['name']?.toString() ?? json['name']?.toString() ?? 'Charge Link',
      modelName: dev['model']?.toString() ?? json['model']?.toString() ?? 'CL-SCB-01',
      hardwareVersion: dev['hardware']?.toString() ?? json['hardware_version']?.toString() ?? '1.0',
      firmwareVersion: dev['firmware']?.toString() ?? json['firmware_version']?.toString() ?? '1.0.1',
      protocolVersion: dev['protocol']?.toString() ?? json['protocol_version']?.toString() ?? '1.0',
      ina219Available: json['ina219_available'] as bool? ?? true,
      pathEnabled: json['path_enabled'] as bool? ?? false,
      charging: json['charging'] as bool? ?? false,
      chargingLimit: (json['charging_limit'] as num?)?.toInt() ??
          (json['percentage'] as num?)?.toInt() ??
          80,
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
    );
  }
}
