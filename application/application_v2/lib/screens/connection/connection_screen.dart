import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/connection_controller.dart';
import '../../services/ble/esp32_service.dart';
import '../home/home_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectionController>().beginConnection();
    });
  }

  void _maybeNavigate(BleConnectionState state) {
    if (state == BleConnectionState.connected && !_navigated) {
      _navigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
    if (state != BleConnectionState.connected) {
      _navigated = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectionController>();
    _maybeNavigate(c.state);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bluetooth_searching, size: 48, color: AppColors.teal),
              const SizedBox(height: 20),
              Text('CHARGE LINK', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              _StateLine(state: c.state),
              const SizedBox(height: 32),
              if (c.lastError != null) ...[
                Text(
                  c.lastError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],
              _ActionButton(state: c.state, controller: c),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateLine extends StatelessWidget {
  const _StateLine({required this.state});
  final BleConnectionState state;

  String get _label {
    switch (state) {
      case BleConnectionState.bluetoothOff:
        return 'Bluetooth is off';
      case BleConnectionState.permissionsRequired:
        return 'Bluetooth permissions required';
      case BleConnectionState.disconnected:
        return '● Disconnected';
      case BleConnectionState.scanning:
        return 'Scanning for Charge Link…';
      case BleConnectionState.deviceFound:
        return 'Device found — connecting…';
      case BleConnectionState.connecting:
        return 'Connecting…';
      case BleConnectionState.connected:
        return '● Connected';
      case BleConnectionState.connectionFailed:
        return 'Connection failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = state == BleConnectionState.connected
        ? AppColors.teal
        : (state == BleConnectionState.connectionFailed ? AppColors.danger : AppColors.textMuted);
    return Text(_label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600));
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.state, required this.controller});
  final BleConnectionState state;
  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final busy = state == BleConnectionState.scanning ||
        state == BleConnectionState.connecting ||
        state == BleConnectionState.deviceFound;

    if (busy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.copper),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: controller.retry,
        child: Text(
          state == BleConnectionState.bluetoothOff
              ? 'RETRY (ENABLE BLUETOOTH FIRST)'
              : (state == BleConnectionState.permissionsRequired ? 'GRANT PERMISSIONS' : 'SCAN & CONNECT'),
        ),
      ),
    );
  }
}
