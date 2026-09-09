import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/connection_controller.dart';
import '../models/discovered_ble_device.dart';
import '../services/esp32/esp32_service.dart';
import '../theme/app_theme.dart';

class DeviceScanSheet extends StatelessWidget {
  const DeviceScanSheet({super.key});

  static Future<void> show(BuildContext context) {
    // Proactively initiate scanning if not already connected
    final conn = context.read<ConnectionController>();
    if (!conn.isConnected && !conn.isScanning) {
      conn.scanForDevices();
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DeviceScanSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final devices = conn.discoveredDevices;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sheet Handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.bluetooth_searching, color: AppColors.cyan, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'CONNECT DEVICE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (conn.isScanning)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Permissions Alert
            if (conn.state == BleConnectionState.permissionsRequired)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bluetooth & Location Permission Needed',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.red),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Android requires Bluetooth and Location permissions to discover nearby hardware.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => conn.requestPermissionsOrOpenSettings(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('GRANT PERMISSIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),

            // Bluetooth Off Alert
            if (conn.state == BleConnectionState.bluetoothOff)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bluetooth_disabled, color: AppColors.amber, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bluetooth is turned OFF. Please enable Bluetooth on your phone.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.amber),
                      ),
                    ),
                  ],
                ),
              ),

            // Error banner if any
            if (conn.lastError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  conn.lastError!,
                  style: const TextStyle(fontSize: 11, color: AppColors.red),
                ),
              ),

            // Connected Banner
            if (conn.isConnected)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connected to ${conn.connectedDeviceName ?? "Smart Charge Box"}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.green),
                          ),
                          if (conn.connectedDeviceId != null)
                            Text(
                              conn.connectedDeviceId!,
                              style: AppTheme.mono(size: 11, color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => conn.disconnect(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: const BorderSide(color: AppColors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('DISCONNECT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),

            // Devices Section Title
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DISCOVERED DEVICES (${devices.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (conn.isScanning)
                    const Text(
                      'Scanning...',
                      style: TextStyle(fontSize: 11, color: AppColors.cyan),
                    ),
                ],
              ),
            ),

            // Discovered Devices List
            Expanded(
              child: devices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              conn.isScanning ? Icons.radar : Icons.devices_other,
                              size: 44,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              conn.isScanning
                                  ? 'Searching for Charge Link Smart Box...'
                                  : 'No Bluetooth devices detected in range.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Ensure your Smart Charge Box is powered on and advertising.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final dev = devices[index];
                        final isConnectingThis = conn.connectingDevice?.id == dev.id;
                        final isConnectedThis = conn.isConnected && conn.connectedDeviceId == dev.id;

                        return _DeviceItemCard(
                          device: dev,
                          isConnecting: isConnectingThis,
                          isConnected: isConnectedThis,
                          onConnect: () => conn.connectToDevice(dev),
                          onDisconnect: () => conn.disconnect(),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),

            // Rescan Button
            ElevatedButton.icon(
              onPressed: conn.isScanning ? null : () => conn.scanForDevices(),
              icon: conn.isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(
                conn.isScanning ? 'SCANNING NEARBY...' : 'RESCAN FOR DEVICES',
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceItemCard extends StatelessWidget {
  const _DeviceItemCard({
    required this.device,
    required this.isConnecting,
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
  });

  final DiscoveredBleDevice device;
  final bool isConnecting;
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final borderColor = isConnected
        ? AppColors.green
        : device.isChargeLink
            ? AppColors.cyan
            : AppColors.border;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withValues(alpha: device.isChargeLink ? 0.7 : 0.4), width: device.isChargeLink ? 1.5 : 1),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (device.isChargeLink ? AppColors.cyan : AppColors.textMuted).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              device.isChargeLink ? Icons.electric_bolt : Icons.bluetooth,
              color: device.isChargeLink ? AppColors.cyan : AppColors.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Name and MAC
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: device.isChargeLink ? AppColors.cyan : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (device.isChargeLink) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CHARGE LINK',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.cyan),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      device.id,
                      style: AppTheme.mono(size: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${device.rssi} dBm',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Action Button
          if (isConnected)
            OutlinedButton(
              onPressed: onDisconnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.red),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('DISCONNECT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            )
          else
            ElevatedButton(
              onPressed: isConnecting ? null : onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: device.isChargeLink ? AppColors.cyan : AppColors.surfaceRaised,
                foregroundColor: device.isChargeLink ? Colors.black : AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: device.isChargeLink ? AppColors.cyan : AppColors.border),
              ),
              child: isConnecting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('CONNECT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}
