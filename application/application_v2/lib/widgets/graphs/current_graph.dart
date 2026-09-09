import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/telemetry_controller.dart';
import 'live_line_graph.dart';

class CurrentGraph extends StatelessWidget {
  const CurrentGraph({super.key});

  @override
  Widget build(BuildContext context) {
    final points = context.watch<TelemetryController>().currentPoints;
    return LiveLineGraph(
      title: 'Current',
      unit: 'A',
      points: points,
      color: AppColors.copper,
    );
  }
}
