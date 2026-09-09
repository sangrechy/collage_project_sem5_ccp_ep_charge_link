import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
import '../../controllers/history_controller.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryController>().load(limit: 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<HistoryController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Charging History')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: AppColors.surfaceRaised,
            child: Text(
              'History is stored in RAM on the ESP32 — a sample is captured '
              'every ~10 seconds, up to the most recent 300 samples, and is '
              'lost if the device reboots.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(child: _body(h)),
        ],
      ),
    );
  }

  Widget _body(HistoryController h) {
    switch (h.status) {
      case HistoryStatus.idle:
      case HistoryStatus.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.copper),
        );
      case HistoryStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              h.error ?? 'Could not load history.',
              style: const TextStyle(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ),
        );
      case HistoryStatus.loaded:
        if (h.samples.isEmpty) {
          return const Center(
            child: Text('No history samples yet.', style: TextStyle(color: AppColors.textMuted)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: h.samples.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = h.samples[i];
            return ListTile(
              dense: true,
              title: Text(
                '${s.voltageV.toStringAsFixed(2)} V · ${s.currentA.toStringAsFixed(2)} A · ${s.powerW.toStringAsFixed(1)} W',
                style: AppTheme.telemetry(size: 14),
              ),
              subtitle: Text(
                '${s.time.toLocal()}'.split('.').first,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: Icon(
                s.charging ? Icons.bolt : Icons.bolt_outlined,
                color: s.charging ? AppColors.copper : AppColors.textMuted,
                size: 18,
              ),
            );
          },
        );
    }
  }
}
