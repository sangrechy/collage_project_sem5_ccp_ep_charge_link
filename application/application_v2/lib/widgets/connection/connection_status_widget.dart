import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/connection_controller.dart';
import '../../services/ble/esp32_service.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectionController>();
    final connected = c.state == BleConnectionState.connected;
    final color = connected ? AppColors.teal : AppColors.danger;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          connected ? 'Connected' : 'Disconnected',
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: connected ? c.disconnect : c.retry,
          child: Text(connected ? 'Disconnect' : 'Reconnect'),
        ),
      ],
    );
  }
}
