# ChargeLink - Smart Charging Controller & Telemetry System

A college engineering project delivering an intelligent charging management and telemetry system combining custom ESP32 hardware and a cross-platform Flutter mobile application.

## ⚡ Overview

ChargeLink bridges physical charging hardware with an intuitive mobile dashboard over Bluetooth Low Energy (BLE):
- **ESP32 Smart Box**: Monitors input/output voltage, current, and wattage in real time via an INA219 sensor, controls charging relay paths, and provides voice alerts.
- **Flutter Mobile App (pplication_v3)**: Displays real-time live telemetry comparing charger output vs. phone intake, computes cable transmission loss and efficiency, tracks battery % and phone temperature history (Day/Week views), and persists historical telemetry for 30–60 days via SQLite.
- **Hardware-Aware Battery Telemetry**: Includes dual-cell battery compensation (e.g. OnePlus / Oppo dual-cell architecture) and active display/system load compensation for accurate power readings.

---

## 📁 Repository Structure

`
charge_link/
├── application/
│   ├── application_v3/      # Current Flutter mobile application (v3.0.0)
│   └── application_v2/      # Previous iteration (v2.0.0)
├── doc/
│   ├── esp32_api.md         # ESP32 BLE protocol & GATT specification
│   ├── 1 review.pdf         # Project review presentation
│   ├── flow charts.pdf      # Architectural flow charts
│   └── demo_sim.mp4         # Demonstration video
└── firmware/
    ├── SmartChargeBox/      # ESP32 Arduino firmware (v1.0.1)
    │   ├── SmartChargeBox.ino
    │   ├── charging_started.h
    │   ├── charging_stopped.h
    │   └── power_limit.h
    └── audio_tools/         # Voice alert audio assets & wav-to-header conversion
        ├── wav_to_h.py
        └── *.wav
`

---

## 🚀 Getting Started

### Flutter App (pplication_v3)

1. **Navigate to the application folder**:
   `ash
   cd application/application_v3
   `

2. **Install dependencies**:
   `ash
   flutter pub get
   `

3. **Run on a connected Android / iOS device**:
   `ash
   flutter run
   `

### ESP32 Firmware

1. Open irmware/SmartChargeBox/SmartChargeBox.ino in Arduino IDE or PlatformIO.
2. Select your ESP32 board and configure serial baud rate to 115200.
3. Required libraries: Adafruit_INA219, ESP32 BLE Arduino.
4. Compile and flash to the Smart Charge Box.

---

## 📜 License & Acknowledgments

Developed as a college engineering project (Semester 5).
