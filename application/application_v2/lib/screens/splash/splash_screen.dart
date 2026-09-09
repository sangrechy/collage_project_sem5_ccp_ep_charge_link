import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../app/app_theme.dart';
import '../connection/connection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Checking Bluetooth support…';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final supported = await FlutterBluePlus.isSupported;
      setState(() => _status = supported
          ? 'Bluetooth supported'
          : 'This device does not support Bluetooth LE');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (_) {
      // Continue regardless — the connection screen handles adapter state.
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt_rounded, size: 56, color: AppColors.copper),
            const SizedBox(height: 16),
            Text(
              'CHARGE LINK',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(letterSpacing: 4),
            ),
            const SizedBox(height: 6),
            Text('Smart Charging Controller', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 40),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.copper),
            ),
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
