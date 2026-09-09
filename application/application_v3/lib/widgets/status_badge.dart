import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/connection_controller.dart';
import '../services/esp32/esp32_service.dart';
import '../theme/app_theme.dart';

import 'device_scan_sheet.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();

    Color dotColor;
    String text;

    switch (conn.state) {
      case BleConnectionState.connected:
        dotColor = AppColors.green;
        text = 'ONLINE';
        break;
      case BleConnectionState.scanning:
        dotColor = AppColors.cyan;
        text = 'SCANNING';
        break;
      case BleConnectionState.connecting:
      case BleConnectionState.deviceFound:
        dotColor = AppColors.amber;
        text = 'CONNECTING';
        break;
      case BleConnectionState.bluetoothOff:
        dotColor = AppColors.red;
        text = 'BT OFF';
        break;
      case BleConnectionState.permissionsRequired:
        dotColor = AppColors.red;
        text = 'PERMISSIONS';
        break;
      case BleConnectionState.connectionFailed:
        dotColor = AppColors.red;
        text = 'FAILED';
        break;
      case BleConnectionState.disconnected:
        dotColor = AppColors.textMuted;
        text = 'OFFLINE';
        break;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => DeviceScanSheet.show(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: dotColor.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: dotColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
