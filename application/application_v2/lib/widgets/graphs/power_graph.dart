import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/telemetry_controller.dart';
import 'live_line_graph.dart';

class PowerGraph extends StatelessWidget {
  const PowerGraph({super.key});

  @override
  Widget build(BuildContext context) {
    final points = context.watch<TelemetryController>().powerPoints;
    return LiveLineGraph(
      title: 'Power',
      unit: 'W',
      points: points,
      color: Colors.deepOrangeAccent,
    );
  }
}
