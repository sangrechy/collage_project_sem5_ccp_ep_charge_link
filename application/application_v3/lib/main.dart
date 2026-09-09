import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/battery_controller.dart';
import 'controllers/charging_controller.dart';
import 'controllers/connection_controller.dart';
import 'controllers/history_controller.dart';
import 'controllers/settings_controller.dart';
import 'controllers/telemetry_controller.dart';
import 'screens/main_navigation_screen.dart';
import 'services/esp32/esp32_ble_service.dart';
import 'services/esp32/esp32_service.dart';
import 'services/esp32/mock_esp32_service.dart';
import 'services/phone/phone_battery_service.dart';
import 'services/storage/history_storage_service.dart';
import 'theme/app_theme.dart';

/// Production default is strictly FALSE (real ESP32 BLE hardware and real phone battery).
/// Set to true only in automated test harness via `--dart-define=USE_MOCK=true`.
const bool kUseMockEsp32 = bool.fromEnvironment('USE_MOCK', defaultValue: false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChargeLinkApp());
}

class ChargeLinkApp extends StatefulWidget {
  const ChargeLinkApp({super.key, this.useMock = kUseMockEsp32});

  final bool useMock;

  @override
  State<ChargeLinkApp> createState() => _ChargeLinkAppState();
}

class _ChargeLinkAppState extends State<ChargeLinkApp> {
  late final Esp32Service _esp32;
  late final PhoneBatteryService _phoneBattery;
  late final HistoryStorageService _storage;

  @override
  void initState() {
    super.initState();
    _esp32 = widget.useMock ? MockEsp32Service() : Esp32BleService();
    _phoneBattery = widget.useMock
        ? MockPhoneBatteryService()
        : BatteryPlusPhoneBatteryService();
    _storage = HistoryStorageService();
  }

  @override
  void dispose() {
    _esp32.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Esp32Service>.value(value: _esp32),
        Provider<PhoneBatteryService>.value(value: _phoneBattery),
        Provider<HistoryStorageService>.value(value: _storage),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(create: (_) => ConnectionController(_esp32)),
        ChangeNotifierProvider(create: (_) => ChargingController(_esp32)),
        ChangeNotifierProvider(
          create: (_) => TelemetryController(
            _esp32,
            _phoneBattery,
            storageService: _storage,
          ),
        ),
        ChangeNotifierProvider(create: (_) => BatteryController(_phoneBattery)),
        ChangeNotifierProvider(create: (_) => HistoryController(_esp32, _storage)),
      ],
      child: MaterialApp(
        title: 'CHARGE LINK',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainNavigationScreen(),
      ),
    );
  }
}
