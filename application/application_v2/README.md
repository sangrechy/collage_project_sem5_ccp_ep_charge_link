# CHARGE LINK — application_v2

Production V2 rebuild of the CHARGE LINK smart-charging-controller app,
built against the protocol documented in `apis.txt`.

## ⚠️ About the reference files

Several files you listed weren't actually available when this was built —
the upload didn't go through for:

- `main_ui.txt`
- `AndroidManifest.xml`
- `esp32_ble_service.dart` (the real v1 BLE implementation)
- `SmartChargeBox.ino`
- `charging_started.h` / `charging_stopped.h` / `power_limit.h`

Everything else you uploaded (`apis.txt`, the v1 models, `esp32_service.dart`,
`mock_esp32_service.dart`, `phone_battery_service.dart`, `esp32_ble_config.dart`,
`build.gradle.kts`) was used directly or as the basis for these files.

Because the real BLE implementation wasn't available, `esp32_ble_service.dart`
here is a **fresh implementation written directly from `apis.txt`'s documented
request/response format** — the final-prompt document you provided says to
build V2 fresh rather than copy v1 anyway, so this matches that intent. It's
untested against real hardware; double-check it against your actual firmware
behavior (especially write-with-response vs write-without-response on the
COMMAND characteristic, and whatever chunk-framing your firmware actually
uses for `get_history` — I inferred `request_id` / `total_chunks` / an
optional `chunk_index` from apis.txt, but if your firmware sends something
different, adjust `_onHistory` in `esp32_ble_service.dart`).

`AndroidManifest.xml` is similarly a best-effort reconstruction covering
exactly what BLE scanning/connecting + `battery_plus` need on modern
Android. If you have an existing manifest with other entries, merge rather
than replace.

## Architecture

```
lib/
├── main.dart
├── app/                  MaterialApp + top-level Provider wiring, theme
├── config/               BLE UUIDs (unchanged from your reference)
├── models/               Data classes, incl. new LiveDataSample / HistorySample
├── services/
│   ├── ble/              Esp32Service contract, real BLE impl, mock impl
│   └── phone/            PhoneBatteryService (battery_plus)
├── repositories/         Composes the two services for injection
├── controllers/          ChangeNotifiers: connection, charging, telemetry,
│                         battery, history — including the automatic
│                         battery-limit stop guard
├── core/permissions/     Runtime BLE permission handling
├── screens/              splash → connection → home (dashboard) → history
└── widgets/              dashboard cards, the 3 live graphs, connection UI
```

State management: **Provider / ChangeNotifier**, wired once in `app/app.dart`.

## Key protocol details respected

- `path_enabled` (relay) and `charging` (INA219-derived) are tracked and
  displayed as two distinct states everywhere, never collapsed into one.
- The three live graphs subscribe once to `liveDataStream` — they do not
  each poll a separate API.
- The ESP32 never sees phone battery %; the app owns the automatic
  charging-limit stop logic (`ChargingController.evaluateAutoStop`), guarded
  so it fires `stop_charging` exactly once per session.
- `battery_plus`-unavailable fields (voltage, current, temperature, health,
  model, manufacturer) return `null` and render "Not available" — nothing is
  fabricated.
- History reassembly is chunk-aware and sorts samples chronologically before
  display, since RAM-only storage on the firmware gives no ordering guarantee.
- Mock mode (`ChargeLinkApp(useMock: true)`) exists for development only;
  the shipped default in `main.dart` is the real BLE service.

## Before you build

```bash
flutter pub get
flutter analyze
flutter run
```

Since this was generated without a live Flutter toolchain in this
environment, `flutter analyze` hasn't actually been run against it — read
through `esp32_ble_service.dart` particularly closely against your real
firmware before flashing/testing on the physical device.
