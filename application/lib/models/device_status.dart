class DeviceStatus {
  const DeviceStatus({
    required this.connected,
    required this.charging,
    required this.relayState,
    required this.deviceName,
  });

  final bool connected;
  final bool charging;
  final bool relayState;
  final String deviceName;
}