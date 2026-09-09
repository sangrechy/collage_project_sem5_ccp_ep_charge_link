import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/charging_controller.dart';
import '../controllers/connection_controller.dart';
import '../models/device_status.dart';
import '../services/esp32/esp32_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  DeviceStatus? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchDeviceStatus();
  }

  Future<void> _fetchDeviceStatus() async {
    setState(() => _loading = true);
    try {
      final esp32 = context.read<Esp32Service>();
      final s = await esp32.getDeviceStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      if (mounted) setState(() => _status = DeviceStatus.disconnected());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final charging = context.watch<ChargingController>();
    final s = _status ?? DeviceStatus.disconnected();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DEVICE'),
        actions: [
          const StatusBadge(),
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                  )
                : const Icon(Icons.refresh, size: 20),
            onPressed: _loading ? null : _fetchDeviceStatus,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDeviceStatus,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Top Hero / Scanner Card
            if (!conn.isConnected) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.bluetooth_searching, color: AppColors.cyan, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CONNECT SMART BOX',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Scan nearby BLE hardware to connect',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Permissions / BT off alerts
                      if (conn.state == BleConnectionState.permissionsRequired)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ElevatedButton.icon(
                            onPressed: () => conn.requestPermissionsOrOpenSettings(),
                            icon: const Icon(Icons.security, size: 18),
                            label: const Text('GRANT BLUETOOTH PERMISSIONS'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
                          ),
                        ),

                      if (conn.state == BleConnectionState.bluetoothOff)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Bluetooth is OFF. Please enable Bluetooth on your phone.',
                            style: TextStyle(fontSize: 12, color: AppColors.amber, fontWeight: FontWeight.w600),
                          ),
                        ),

                      // Scan button
                      ElevatedButton.icon(
                        onPressed: conn.isScanning ? null : () => conn.scanForDevices(),
                        icon: conn.isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.search, size: 18),
                        label: Text(
                          conn.isScanning ? 'SCANNING NEARBY...' : 'SCAN FOR SMART BOX',
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      // Discovered devices in Device screen
                      if (conn.discoveredDevices.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'DETECTED PERIPHERALS (${conn.discoveredDevices.length})',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                            ),
                            if (conn.isScanning)
                              const Text('Scanning...', style: TextStyle(fontSize: 11, color: AppColors.cyan)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...conn.discoveredDevices.map((dev) {
                          final isConnectingThis = conn.connectingDevice?.id == dev.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: dev.isChargeLink
                                    ? AppColors.cyan.withValues(alpha: 0.7)
                                    : AppColors.border.withValues(alpha: 0.4),
                                width: dev.isChargeLink ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  dev.isChargeLink ? Icons.electric_bolt : Icons.bluetooth,
                                  color: dev.isChargeLink ? AppColors.cyan : AppColors.textMuted,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              dev.name,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: dev.isChargeLink ? AppColors.cyan : AppColors.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (dev.isChargeLink) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: AppColors.cyan.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('MATCH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.cyan)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${dev.id}  •  ${dev.rssi} dBm',
                                        style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: isConnectingThis ? null : () => conn.connectToDevice(dev),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: dev.isChargeLink ? AppColors.cyan : AppColors.surfaceRaised,
                                    foregroundColor: dev.isChargeLink ? Colors.black : AppColors.textPrimary,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: isConnectingThis
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Text('CONNECT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              // Connected Hero Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.developer_board, size: 30, color: AppColors.green),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        conn.connectedDeviceName ?? s.deviceName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
                      if (conn.connectedDeviceId != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          conn.connectedDeviceId!,
                          style: AppTheme.mono(size: 12, color: AppColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Connected to Hardware',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => conn.disconnect(),
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('DISCONNECT DEVICE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Device Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DEVICE INFORMATION',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(label: 'Model', value: s.modelName),
                    const Divider(height: 16),
                    _InfoRow(label: 'Hardware', value: s.hardwareVersion),
                    const Divider(height: 16),
                    _InfoRow(label: 'Firmware', value: s.firmwareVersion),
                    const Divider(height: 16),
                    _InfoRow(label: 'Protocol', value: s.protocolVersion),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Sensor Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SENSOR STATUS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StatusRow(
                      label: 'INA219 Power Monitor',
                      status: s.ina219Available ? 'Available' : 'Error',
                      active: s.ina219Available,
                    ),
                    const Divider(height: 16),
                    _StatusRow(
                      label: 'BLE Wireless Stack',
                      status: conn.isConnected ? 'Connected' : 'Disconnected',
                      active: conn.isConnected,
                    ),
                    const Divider(height: 16),
                    _StatusRow(
                      label: 'Relay Charging Path',
                      status: charging.pathEnabled ? 'Enabled' : 'Disabled',
                      active: charging.pathEnabled,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Clear session button
            OutlinedButton.icon(
              onPressed: () async {
                final esp32 = context.read<Esp32Service>();
                await esp32.clearSession();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Session reset on ESP32')),
                  );
                }
              },
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('RESET ACTIVE SESSION'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        Text(value, style: AppTheme.mono(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.status, required this.active});
  final String label;
  final String status;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.green : AppColors.red;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ],
    );
  }
}
