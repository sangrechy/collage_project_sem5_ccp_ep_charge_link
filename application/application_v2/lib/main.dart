import 'package:flutter/material.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // FINAL DEFAULT MODE = REAL ESP32 BLE. Flip to `useMock: true` only for
  // local development without a physical CHARGE LINK device on hand.
  runApp(const ChargeLinkApp(useMock: false));
}
