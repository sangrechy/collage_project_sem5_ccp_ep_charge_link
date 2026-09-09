import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/telemetry_controller.dart';
import 'live_line_graph.dart';

class VoltageGraph extends StatelessWidget {
  const VoltageGraph({super.key});

  @override
  Widget build(BuildContext context) {
    final points = context.watch<TelemetryController>().voltagePoints;
    return LiveLineGraph(
      title: 'Voltage',
      unit: 'V',
      points: points,
      color: AppColors.teal,
    );
  }
}
