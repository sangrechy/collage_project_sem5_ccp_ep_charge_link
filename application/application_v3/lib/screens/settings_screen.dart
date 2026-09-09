import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/connection_controller.dart';
import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final conn = context.watch<ConnectionController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS'),
        actions: const [
          StatusBadge(),
          SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Smart Charging Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SMART CHARGING',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatic charging control', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Enable phone-guided automation logic', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    value: settings.autoControl,
                    activeThumbColor: AppColors.cyan,
                    onChanged: (val) => settings.setAutoControl(val),
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stop at selected battery limit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Cut relay power when phone reaches target %', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    value: settings.stopAtLimit,
                    activeThumbColor: AppColors.cyan,
                    onChanged: (val) => settings.setStopAtLimit(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Device Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DEVICE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto reconnect', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Scan and pair automatically upon launch', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    value: settings.autoReconnect,
                    activeThumbColor: AppColors.cyan,
                    onChanged: (val) => settings.setAutoReconnect(val),
                  ),
                  const Divider(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disconnect device', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.red)),
                    subtitle: const Text('Terminate active BLE connection', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    trailing: const Icon(Icons.bluetooth_disabled, color: AppColors.red, size: 20),
                    onTap: () {
                      conn.disconnect();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Disconnected from CHARGE LINK')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Application Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'APPLICATION',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('About CHARGE LINK', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      Text('Smart Charging Controller', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Version', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      Text('3.0.0 (Build 1)', style: AppTheme.mono(size: 13, color: AppColors.cyan)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Protocol Spec', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      Text('BLE v1.0.1 (apis.txt)', style: AppTheme.mono(size: 13, color: AppColors.amber)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
