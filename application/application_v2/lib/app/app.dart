import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/battery_controller.dart';
import '../controllers/charging_controller.dart';
import '../controllers/connection_controller.dart';
import '../controllers/history_controller.dart';
import '../controllers/telemetry_controller.dart';
import '../repositories/charge_link_repository.dart';
import '../screens/splash/splash_screen.dart';
import 'app_theme.dart';

/// Root widget. FINAL DEFAULT MODE = REAL ESP32 BLE — pass useMock: true
/// here only for local development against a device that isn't physically
/// present.
class ChargeLinkApp extends StatefulWidget {
  const ChargeLinkApp({super.key, this.useMock = false});

  final bool useMock;

  @override
  State<ChargeLinkApp> createState() => _ChargeLinkAppState();
}

class _ChargeLinkAppState extends State<ChargeLinkApp> {
  late final ChargeLinkRepository _repo =
      ChargeLinkRepository(useMock: widget.useMock);

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _repo.esp32),
        Provider.value(value: _repo.phoneBattery),
        ChangeNotifierProvider(create: (_) => ConnectionController(_repo.esp32)),
        ChangeNotifierProvider(create: (_) => ChargingController(_repo.esp32)),
        ChangeNotifierProvider(create: (_) => TelemetryController(_repo.esp32)),
        ChangeNotifierProvider(create: (_) => BatteryController(_repo.phoneBattery)),
        ChangeNotifierProvider(create: (_) => HistoryController(_repo.esp32)),
      ],
      child: MaterialApp(
        title: 'CHARGE LINK',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const SplashScreen(),
      ),
    );
  }
}
