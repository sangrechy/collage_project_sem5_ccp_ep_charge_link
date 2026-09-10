/*
 * ============================================================
 *                       CHARGE LINK
 *                  ESP32 FIRMWARE v1.0.0
 * ============================================================
 *
 * HARDWARE
 * ------------------------------------------------------------
 * ESP32
 * INA219
 * SSD1306 OLED
 * Relay
 * ESP32 DAC2 / GPIO26
 *
 * PIN MAP
 * ------------------------------------------------------------
 * INA219 SDA  -> GPIO21
 * INA219 SCL  -> GPIO22
 *
 * OLED SDA    -> GPIO18
 * OLED SCL    -> GPIO19
 *
 * RELAY       -> GPIO25
 *
 * AUDIO DAC   -> GPIO26 / DAC2
 *
 * ============================================================
 *
 * RELAY LOGIC
 * ------------------------------------------------------------
 *
 * GPIO25 HIGH
 *     -> Relay coil OFF
 *     -> NC CLOSED
 *     -> Charging path ENABLED
 *
 * GPIO25 LOW
 *     -> Relay coil ON
 *     -> NC OPEN
 *     -> Charging path DISABLED
 *
 * ============================================================
 *
 * STATE MODEL
 * ------------------------------------------------------------
 *
 * path_enabled
 *     = commanded physical relay/path state
 *
 * charging
 *     = actual INA219-measured charging state
 *
 * These are intentionally DIFFERENT.
 *
 * Example:
 *
 * path_enabled = true
 * charging     = false
 *
 * means the charging path is available but the phone is not
 * currently drawing enough current to be considered charging.
 *
 * IMPORTANT (v1.0.1 fix):
 * "charging" may ONLY be derived from measured current while
 * "path_enabled" is true. When the path has been commanded
 * OFF, "charging" is always forced to false and is never
 * re-derived from current, even if residual/leaked current is
 * still sensed. This prevents the sensor-polling loop from
 * silently reverting a stop_charging command.
 *
 * ============================================================
 *
 * CHARGING LIMIT
 * ------------------------------------------------------------
 *
 * charging_limit is ONLY a stored user target.
 *
 * ESP32 does NOT know the phone battery percentage.
 *
 * Flutter must read the phone battery percentage and send:
 *
 *     stop_charging
 *
 * when the target is reached.
 *
 * ============================================================
 *
 * BLE
 * ------------------------------------------------------------
 *
 * COMMAND
 *     Flutter -> ESP32
 *
 * RESPONSE
 *     ESP32 -> Flutter
 *
 * LIVE_DATA
 *     ESP32 -> Flutter
 *
 * HISTORY
 *     ESP32 -> Flutter
 *
 * ============================================================
 *
 * TIMESTAMP
 * ------------------------------------------------------------
 *
 * v1.0 uses ESP32 uptime seconds.
 *
 * It is NOT Unix time.
 *
 * ============================================================
 *
 * HISTORY
 * ------------------------------------------------------------
 *
 * 300 samples maximum.
 * One sample every 10 seconds.
 * Stored in RAM only.
 *
 * History is lost after ESP32 reboot.
 *
 * ============================================================
 *
 * NVS PERSISTENCE
 * ------------------------------------------------------------
 *
 * charging limit
 * total energy
 * session ID
 *
 * ============================================================
 */

#include <Arduino.h>
#include <Wire.h>

#include <Adafruit_INA219.h>

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#include <Preferences.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "charging_started.h"
#include "charging_stopped.h"
#include "power_limit.h"
#include "full_charge.h"
#include "no_device.h"
#include "charging_error.h"


// ============================================================
// DEVICE INFORMATION
// ============================================================

#define DEVICE_NAME          "Charge Link"
#define MODEL_NAME           "CL-SCB-01"
#define HARDWARE_VERSION     "1.0"
#define FIRMWARE_VERSION     "1.0.1"
#define PROTOCOL_VERSION     "1.0"


// ============================================================
// PIN DEFINITIONS
// ============================================================

#define INA_SDA       21
#define INA_SCL       22

#define OLED_SDA      18
#define OLED_SCL      19

#define RELAY_PIN     25

#define AUDIO_PIN     26


// ============================================================
// AUDIO
// ============================================================

#define SAMPLE_RATE   16000


// ============================================================
// OLED
// ============================================================

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64


// ============================================================
// I2C
// ============================================================

TwoWire INA_WIRE(0);
TwoWire OLED_WIRE(1);


// ============================================================
// DEVICES
// ============================================================

Adafruit_INA219 ina219;

Adafruit_SSD1306 display(
  SCREEN_WIDTH,
  SCREEN_HEIGHT,
  &OLED_WIRE,
  -1
);

Preferences preferences;


// ============================================================
// BLE UUIDs
// ============================================================

#define SERVICE_UUID \
  "7f4a0001-6d3b-4a91-9c21-123456789001"

#define COMMAND_UUID \
  "7f4a0002-6d3b-4a91-9c21-123456789001"

#define RESPONSE_UUID \
  "7f4a0003-6d3b-4a91-9c21-123456789001"

#define LIVE_DATA_UUID \
  "7f4a0004-6d3b-4a91-9c21-123456789001"

#define HISTORY_UUID \
  "7f4a0005-6d3b-4a91-9c21-123456789001"


// ============================================================
// BLE OBJECTS
// ============================================================

BLEServer *bleServer = nullptr;

BLECharacteristic *commandCharacteristic = nullptr;

BLECharacteristic *responseCharacteristic = nullptr;

BLECharacteristic *liveDataCharacteristic = nullptr;

BLECharacteristic *historyCharacteristic = nullptr;


// ============================================================
// BLE STATE
// ============================================================

volatile bool bleConnected = false;


// ============================================================
// HARDWARE STATE
// ============================================================

bool ina219Available = false;

bool nvsAvailable = false;


// ============================================================
// POWER DATA
// ============================================================

float voltageV = 0.0f;

float currentA = 0.0f;

float powerW = 0.0f;


// ============================================================
// CHARGING DETECTION HYSTERESIS
// ============================================================
//
// Start charging:
//
//     >= 0.08 A
//
// Stop charging:
//
//     <= 0.04 A
//
// This prevents rapid ON/OFF transitions around one threshold.
//

const float CHARGING_START_THRESHOLD_A = 0.08f;

const float CHARGING_STOP_THRESHOLD_A  = 0.04f;


// ============================================================
// RELAY PATH
// ============================================================

bool relayPathEnabled = true;


// ============================================================
// ACTUAL CHARGING STATE
// ============================================================

bool charging = false;


// ============================================================
// CHARGING LIMIT
// ============================================================
//
// USER TARGET ONLY.
//
// ESP32 does not know phone battery percentage.
//

int chargingLimit = 80;


// ============================================================
// ENERGY
// ============================================================

float sessionEnergyWh = 0.0f;

float totalEnergyWh = 0.0f;


// ============================================================
// SESSION
// ============================================================

bool sessionActive = false;

uint32_t sessionId = 0;

unsigned long sessionStartMillis = 0;

unsigned long sessionStartTimestamp = 0;

float sessionPeakPowerW = 0.0f;

float sessionAveragePowerW = 0.0f;

unsigned long sessionSampleCount = 0;


// ============================================================
// HISTORY
// ============================================================

#define HISTORY_SIZE 300

#define HISTORY_SAMPLES_PER_CHUNK 2


struct HistorySample {

  unsigned long timestamp;

  uint32_t sessionId;

  float voltageV;

  float currentA;

  float powerW;

  float sessionEnergyWh;

  bool charging;

  bool pathEnabled;
};


HistorySample history[HISTORY_SIZE];

int historyIndex = 0;

int historyCount = 0;


// ============================================================
// LIVE DATA CACHE
// ============================================================

struct LiveData {

  unsigned long timestamp;

  float voltageV;

  float currentA;

  float powerW;

  float sessionEnergyWh;

  float totalEnergyWh;

  bool charging;

  bool pathEnabled;

  int chargingLimit;

  bool ina219Available;
};


LiveData liveData;


// ============================================================
// SYSTEM TIMERS
// ============================================================

unsigned long deviceStartMillis = 0;

unsigned long lastMeasurementMillis = 0;

unsigned long lastHistoryMillis = 0;

unsigned long lastLiveNotificationMillis = 0;

unsigned long lastOLEDMillis = 0;

unsigned long lastNVSSaveMillis = 0;

unsigned long lastSerialMillis = 0;


// ============================================================
// INTERVALS
// ============================================================

#define MEASUREMENT_INTERVAL_MS       1000UL

#define HISTORY_INTERVAL_MS           10000UL

#define LIVE_NOTIFICATION_MS          1000UL

#define OLED_INTERVAL_MS              1000UL

#define NVS_SAVE_INTERVAL_MS          60000UL

#define SERIAL_INTERVAL_MS            2000UL


// ============================================================
// AUDIO STATE
// ============================================================

bool audioPlaying = false;



// ============================================================
// TIMESTAMP
// ============================================================

unsigned long getTimestamp() {

  return (
    millis() -
    deviceStartMillis
  ) / 1000UL;
}


// ============================================================
// PLAY PCM AUDIO (CLEAN EQUALIZED 3W PLAYBACK)
// ============================================================
//
// 16-bit signed PCM, 16 kHz -> 32 kHz (2x Ultrasonic Interpolation)
// - 32 kHz output moves staircase frequency beyond human hearing (eliminates DAC whine)
// - S-curve raised-cosine bias ramp (zero turn-on pop/click)
// - Low-jitter sample timer (microsecond precision)
// - Zero DC idle coil power
//

void playAudio(
  const unsigned char *audio,
  unsigned int length
) {

  if (
    audioPlaying ||
    audio == nullptr ||
    length < 4
  ) {
    return;
  }

  audioPlaying = true;

  Serial.println();
  Serial.println(
    "======================================"
  );
  Serial.println(
    "PLAYING VOICE (CLEAN 32kHz INTERPOLATED)"
  );
  Serial.println(
    "GPIO26 / DAC2"
  );
  Serial.println(
    "16-bit PCM / 16kHz -> 32kHz / MONO"
  );
  Serial.println(
    "======================================"
  );

  pinMode(
    AUDIO_PIN,
    OUTPUT
  );

  // Smooth S-Curve Anti-Pop Ramp-Up: 0V -> 1.65V (128) over 25ms
  for (int step = 0; step <= 256; step++) {
    float phase = (float)step * 3.14159265f / 256.0f;
    int rampVal = (int)(64.0f * (1.0f - cosf(phase)) + 0.5f);
    if (rampVal < 0) rampVal = 0;
    if (rampVal > 128) rampVal = 128;
    dacWrite(
      AUDIO_PIN,
      (uint8_t)rampVal
    );
    delayMicroseconds(100);
  }

  unsigned int totalSamples = length / 2;
  unsigned long nextTick = micros();
  bool extraMicrosecond = false;

  for (unsigned int i = 0; i < totalSamples; i++) {
    // Current 16-bit sample
    uint16_t low1 = audio[i * 2];
    uint16_t high1 = audio[i * 2 + 1];
    int16_t s1 = (int16_t)((high1 << 8) | low1);

    // Next 16-bit sample (for linear interpolation)
    int16_t s2;
    if (i + 1 < totalSamples) {
      uint16_t low2 = audio[(i + 1) * 2];
      uint16_t high2 = audio[(i + 1) * 2 + 1];
      s2 = (int16_t)((high2 << 8) | low2);
    } else {
      s2 = s1;
    }

    // Midpoint interpolated sample (cuts quantization step in half)
    int16_t sMid = (int16_t)(((int32_t)s1 + (int32_t)s2) / 2);

    // 8-bit DAC values
    int dac1 = (s1 >> 8) + 128;
    if (dac1 < 0) dac1 = 0;
    if (dac1 > 255) dac1 = 255;

    int dac2 = (sMid >> 8) + 128;
    if (dac2 < 0) dac2 = 0;
    if (dac2 > 255) dac2 = 255;

    // --- Sub-sample 1 (at t = 0) ---
    dacWrite(
      AUDIO_PIN,
      (uint8_t)dac1
    );

    nextTick += 31;
    extraMicrosecond = !extraMicrosecond;
    if (extraMicrosecond) {
      nextTick += 1;
    }
    while ((long)(micros() - nextTick) < 0) {
      // tight loop for microsecond timing
    }

    // --- Sub-sample 2 (interpolated at t = 31.25 us) ---
    dacWrite(
      AUDIO_PIN,
      (uint8_t)dac2
    );

    nextTick += 31;
    extraMicrosecond = !extraMicrosecond;
    if (extraMicrosecond) {
      nextTick += 1;
    }
    while ((long)(micros() - nextTick) < 0) {
      // tight loop
    }

    // Feed FreeRTOS watchdog periodically every 128 samples (~8ms)
    if ((i & 0x7F) == 0) {
      yield();
    }
  }

  // Smooth S-Curve Anti-Pop Ramp-Down: 1.65V (128) -> 0V over 25ms
  for (int step = 0; step <= 256; step++) {
    float phase = (float)step * 3.14159265f / 256.0f;
    int rampVal = (int)(64.0f * (1.0f + cosf(phase)) + 0.5f);
    if (rampVal < 0) rampVal = 0;
    if (rampVal > 128) rampVal = 128;
    dacWrite(
      AUDIO_PIN,
      (uint8_t)rampVal
    );
    delayMicroseconds(100);
  }

  // Hold 0V when idle: zero DC coil heating, DAC driver stays active
  dacWrite(
    AUDIO_PIN,
    0
  );

  audioPlaying = false;

  Serial.println(
    "Voice finished (DAC idle at 0V, driver active)."
  );
}



// ============================================================
// RELAY CONTROL
// ============================================================
//
// This remains the ONLY place in the firmware that touches
// RELAY_PIN directly. Every other function (BLE command
// handlers, setup(), etc.) must go through relayChargingOn()
// or relayChargingOff() so the physical pin state and the
// relayPathEnabled flag can never disagree.
//

void relayChargingOn() {

  digitalWrite(
    RELAY_PIN,
    HIGH
  );


  relayPathEnabled =
    true;


  Serial.println(
    "RELAY: GPIO25 HIGH -> PATH ENABLED"
  );
}


void relayChargingOff() {

  digitalWrite(
    RELAY_PIN,
    LOW
  );


  relayPathEnabled =
    false;


  Serial.println(
    "RELAY: GPIO25 LOW -> PATH DISABLED"
  );
}


// ============================================================
// NVS LOAD
// ============================================================

void loadSettings() {

  if (!nvsAvailable) {

    chargingLimit = 80;

    totalEnergyWh = 0.0f;

    sessionId = 0;

    return;
  }


  chargingLimit =
    preferences.getInt(
      "limit",
      80
    );


  totalEnergyWh =
    preferences.getFloat(
      "totalWh",
      0.0f
    );


  sessionId =
    preferences.getULong(
      "sessionId",
      0
    );


  if (
    chargingLimit < 0 ||
    chargingLimit > 100
  ) {

    chargingLimit =
      80;
  }


  if (
    totalEnergyWh < 0.0f
  ) {

    totalEnergyWh =
      0.0f;
  }
}


// ============================================================
// NVS SAVE
// ============================================================

void saveEnergy() {

  if (nvsAvailable) {

    preferences.putFloat(
      "totalWh",
      totalEnergyWh
    );
  }
}


void saveChargingLimit() {

  if (nvsAvailable) {

    preferences.putInt(
      "limit",
      chargingLimit
    );
  }
}


void saveSessionId() {

  if (nvsAvailable) {

    preferences.putULong(
      "sessionId",
      sessionId
    );
  }
}


// ============================================================
// SESSION RESET
// ============================================================

void resetSessionStatistics() {

  sessionEnergyWh =
    0.0f;


  sessionPeakPowerW =
    0.0f;


  sessionAveragePowerW =
    0.0f;


  sessionSampleCount =
    0;
}


// ============================================================
// START SESSION
// ============================================================

void startChargingSession(
  bool playVoice
) {

  if (sessionActive) {

    return;
  }


  sessionId++;

  saveSessionId();


  sessionActive =
    true;


  resetSessionStatistics();


  sessionStartMillis =
    millis();


  sessionStartTimestamp =
    getTimestamp();


  Serial.println();

  Serial.println(
    "======================================"
  );

  Serial.println(
    "CHARGING SESSION STARTED"
  );

  Serial.print(
    "SESSION ID: "
  );

  Serial.println(
    sessionId
  );

  Serial.println(
    "======================================"
  );


  if (playVoice) {

    playAudio(
      charging_started,
      charging_started_len
    );
  }
}


// ============================================================
// STOP SESSION
// ============================================================

void stopChargingSession(
  bool playVoice,
  const char *reason = nullptr
) {

  if (!sessionActive) {

    return;
  }


  sessionActive =
    false;


  saveEnergy();


  Serial.println();

  Serial.println(
    "======================================"
  );

  Serial.println(
    "CHARGING SESSION STOPPED"
  );

  if (reason != nullptr) {
    Serial.print(
      "REASON: "
    );
    Serial.println(
      reason
    );
  }

  Serial.print(
    "SESSION ID: "
  );

  Serial.println(
    sessionId
  );

  Serial.println(
    "======================================"
  );


  if (playVoice) {

    if (
      reason != nullptr &&
      (strcmp(reason, "full_charge") == 0 || strcmp(reason, "battery_full") == 0)
    ) {

      playAudio(
        full_charge,
        full_charge_len
      );

    } else if (
      reason != nullptr &&
      strcmp(reason, "no_device") == 0
    ) {

      playAudio(
        no_device,
        no_device_len
      );

    } else if (
      reason != nullptr &&
      (strcmp(reason, "error") == 0 || strcmp(reason, "charging_error") == 0)
    ) {

      playAudio(
        charging_error,
        charging_error_len
      );

    } else if (
      reason != nullptr &&
      (strcmp(reason, "power_limit") == 0 || strcmp(reason, "limit") == 0)
    ) {

      playAudio(
        power_limit,
        power_limit_len
      );

    } else {

      playAudio(
        charging_stopped,
        charging_stopped_len
      );
    }
  }
}


// ============================================================
// INA219
// ============================================================

void readPower() {

  if (!ina219Available) {

    voltageV = 0.0f;

    currentA = 0.0f;

    powerW = 0.0f;

    return;
  }


  voltageV =
    ina219.getBusVoltage_V();


  currentA =
    ina219.getCurrent_mA()
    /
    1000.0f;


  powerW =
    ina219.getPower_mW()
    /
    1000.0f;


  if (
    currentA < 0.0f
  ) {

    currentA = 0.0f;
  }


  if (
    powerW < 0.0f
  ) {

    powerW = 0.0f;
  }
}


// ============================================================
// CHARGING STATE
// ============================================================
//
// v1.0.1 FIX
// ------------------------------------------------------------
// This function is READ-ONLY with respect to the commanded
// path state (relayPathEnabled). It may only ever set
// "charging" to true while relayPathEnabled is true.
//
// This is the fix for the core bug: previously, this function
// derived "charging" purely from currentA, with no awareness
// of whether the relay path had just been commanded OFF. That
// meant every 1-second measurement tick could silently flip
// "charging" back to true (and even restart a session + replay
// the "charging started" audio) moments after stop_charging
// had already disabled the relay and reported success.
//
// Now, whenever the path is disabled, charging is unconditionally
// forced to false and the current-threshold logic is skipped
// entirely. If current is still detected while the path is
// disabled, that is logged as a hardware warning (possible
// relay polarity/wiring fault) instead of being treated as
// "still charging".
//

void updateChargingStateFromMeasurement() {

  if (!ina219Available) {

    if (charging) {

      charging =
        false;


      stopChargingSession(
        false
      );
    }


    return;
  }


  // ----------------------------------------------------------
  // GATE: sensor readings can never re-enable "charging" while
  // the commanded path state is OFF.
  // ----------------------------------------------------------

  if (!relayPathEnabled) {

    if (charging) {

      charging =
        false;


      stopChargingSession(
        false
      );


      Serial.println(
        "STATE: charging forced OFF (path disabled)"
      );
    }


    if (
      currentA >=
      CHARGING_STOP_THRESHOLD_A
    ) {

      Serial.print(
        "WARNING: current still detected with path disabled: "
      );

      Serial.print(
        currentA,
        3
      );

      Serial.println(
        " A - check relay wiring / polarity"
      );
    }


    return;
  }


  if (!charging) {

    if (
      currentA >=
      CHARGING_START_THRESHOLD_A
    ) {

      charging =
        true;


      startChargingSession(
        true
      );
    }
  }


  else {

    // Overcurrent protection (hardware short-circuit safety)
    if (currentA > 3.0f) {

      Serial.println(
        "SAFETY FAULT: Overcurrent detected (>3.0A)! Disabling path."
      );

      relayChargingOff();

      charging =
        false;

      stopChargingSession(
        false
      );

      playAudio(
        charging_error,
        charging_error_len
      );

      return;
    }


    if (
      currentA <=
      CHARGING_STOP_THRESHOLD_A
    ) {

      charging =
        false;


      // If the session transferred energy or ran for a substantial period,
      // the phone battery has reached full charge.
      // Otherwise, the cable was unplugged early (circuit open / no device).
      if (
        sessionEnergyWh >= 0.10f ||
        sessionSampleCount >= 60
      ) {

        Serial.println(
          "STATUS: Battery fully charged (current dropped after session)"
        );

        stopChargingSession(
          true,
          "full_charge"
        );

      } else {

        Serial.println(
          "STATUS: Circuit open / device disconnected during session"
        );

        stopChargingSession(
          true,
          "no_device"
        );
      }
    }
  }
}


// ============================================================
// ENERGY
// ============================================================

void updateEnergy(
  float elapsedSeconds
) {

  if (
    !charging ||
    elapsedSeconds <= 0.0f ||
    powerW <= 0.0f
  ) {

    return;
  }


  float energyAdded =
    (
      powerW *
      elapsedSeconds
    )
    /
    3600.0f;


  sessionEnergyWh +=
    energyAdded;


  totalEnergyWh +=
    energyAdded;


  if (
    powerW >
    sessionPeakPowerW
  ) {

    sessionPeakPowerW =
      powerW;
  }


  sessionSampleCount++;


  unsigned long durationSeconds =
    (
      millis() -
      sessionStartMillis
    )
    /
    1000UL;


  if (
    durationSeconds > 0
  ) {

    sessionAveragePowerW =
      (
        sessionEnergyWh *
        3600.0f
      )
      /
      durationSeconds;
  }
}


// ============================================================
// LIVE CACHE
// ============================================================

void updateLiveCache() {

  liveData.timestamp =
    getTimestamp();


  liveData.voltageV =
    voltageV;


  liveData.currentA =
    currentA;


  liveData.powerW =
    powerW;


  liveData.sessionEnergyWh =
    sessionEnergyWh;


  liveData.totalEnergyWh =
    totalEnergyWh;


  liveData.charging =
    charging;


  liveData.pathEnabled =
    relayPathEnabled;


  liveData.chargingLimit =
    chargingLimit;


  liveData.ina219Available =
    ina219Available;
}


// ============================================================
// HISTORY
// ============================================================

void addHistorySample() {

  history[
    historyIndex
  ].timestamp =
    getTimestamp();


  history[
    historyIndex
  ].sessionId =
    sessionId;


  history[
    historyIndex
  ].voltageV =
    voltageV;


  history[
    historyIndex
  ].currentA =
    currentA;


  history[
    historyIndex
  ].powerW =
    powerW;


  history[
    historyIndex
  ].sessionEnergyWh =
    sessionEnergyWh;


  history[
    historyIndex
  ].charging =
    charging;


  history[
    historyIndex
  ].pathEnabled =
    relayPathEnabled;


  historyIndex =
    (
      historyIndex +
      1
    )
    %
    HISTORY_SIZE;


  if (
    historyCount <
    HISTORY_SIZE
  ) {

    historyCount++;
  }
}


// ============================================================
// OLED
// ============================================================

void updateOLED() {

  display.clearDisplay();


  display.setTextColor(
    SSD1306_WHITE
  );


  display.setTextSize(
    1
  );


  display.setCursor(
    0,
    0
  );

  display.println(
    "CHARGE LINK"
  );


  display.setCursor(
    0,
    13
  );

  display.print(
    "V: "
  );

  display.print(
    voltageV,
    2
  );

  display.println(
    " V"
  );


  display.setCursor(
    0,
    25
  );

  display.print(
    "I: "
  );

  display.print(
    currentA,
    2
  );

  display.println(
    " A"
  );


  display.setCursor(
    0,
    37
  );

  display.print(
    "P: "
  );

  display.print(
    powerW,
    2
  );

  display.println(
    " W"
  );


  display.setCursor(
    0,
    49
  );

  display.print(
    "E: "
  );

  display.print(
    sessionEnergyWh,
    2
  );

  display.println(
    " Wh"
  );


  display.setCursor(
    82,
    13
  );

  display.println(
    charging
      ? "CHG"
      : "IDLE"
  );


  display.setCursor(
    82,
    25
  );

  display.println(
    relayPathEnabled
      ? "PATH"
      : "OFF"
  );


  display.setCursor(
    82,
    37
  );

  display.print(
    "L:"
  );

  display.print(
    chargingLimit
  );

  display.println(
    "%"
  );


  display.setCursor(
    82,
    49
  );

  display.println(
    ina219Available
      ? "INA"
      : "ERR"
  );


  display.display();
}


// ============================================================
// BLE RESPONSE
// ============================================================

void sendResponse(
  int requestId,
  const String &data
) {

  String response;

  response.reserve(
    700
  );


  response =
    "{\"id\":" +
    String(
      requestId
    );


  response +=
    ",\"success\":true";


  if (
    data.length() > 0
  ) {

    response +=
      ",\"data\":" +
      data;
  }


  response +=
    "}";


  Serial.print(
    "BLE RESPONSE: "
  );

  Serial.println(
    response
  );


  if (
    bleConnected &&
    responseCharacteristic != nullptr
  ) {

    responseCharacteristic->setValue(
      response.c_str()
    );

    responseCharacteristic->notify();
  }
}


// ============================================================
// BLE ERROR
// ============================================================

void sendError(
  int requestId,
  const String &code,
  const String &message
) {

  String response;

  response.reserve(
    350
  );


  response =
    "{\"id\":" +
    String(
      requestId
    );


  response +=
    ",\"success\":false";


  response +=
    ",\"error\":{\"code\":\"" +
    code +
    "\",\"message\":\"" +
    message +
    "\"}}";


  Serial.print(
    "BLE ERROR: "
  );

  Serial.println(
    response
  );


  if (
    bleConnected &&
    responseCharacteristic != nullptr
  ) {

    responseCharacteristic->setValue(
      response.c_str()
    );

    responseCharacteristic->notify();
  }
}


// ============================================================
// GET STATUS
// ============================================================

void commandGetStatus(
  int id
) {

  String data;


  data =
    "{\"device\":{";


  data +=
    "\"name\":\"" +
    String(
      DEVICE_NAME
    );


  data +=
    "\",\"model\":\"" +
    String(
      MODEL_NAME
    );


  data +=
    "\",\"firmware\":\"" +
    String(
      FIRMWARE_VERSION
    );


  data +=
    "\",\"protocol\":\"" +
    String(
      PROTOCOL_VERSION
    );


  data +=
    "\"}";


  data +=
    ",\"connected\":" +
    String(
      bleConnected
        ? "true"
        : "false"
    );


  data +=
    ",\"charging\":" +
    String(
      charging
        ? "true"
        : "false"
    );


  data +=
    ",\"path_enabled\":" +
    String(
      relayPathEnabled
        ? "true"
        : "false"
    );


  data +=
    ",\"charging_limit\":" +
    String(
      chargingLimit
    );


  data +=
    ",\"ina219_available\":" +
    String(
      ina219Available
        ? "true"
        : "false"
    );


  data +=
    ",\"uptime_seconds\":" +
    String(
      getTimestamp()
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// GET POWER
// ============================================================

void commandGetPower(
  int id
) {

  String data;


  data =
    "{\"voltage_v\":" +
    String(
      voltageV,
      3
    );


  data +=
    ",\"current_a\":" +
    String(
      currentA,
      3
    );


  data +=
    ",\"power_w\":" +
    String(
      powerW,
      3
    );


  data +=
    ",\"ina219_available\":" +
    String(
      ina219Available
        ? "true"
        : "false"
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// GET CHARGING STATE
// ============================================================

void commandGetChargingState(
  int id
) {

  String data;


  data =
    "{\"charging\":" +
    String(
      charging
        ? "true"
        : "false"
    );


  data +=
    ",\"path_enabled\":" +
    String(
      relayPathEnabled
        ? "true"
        : "false"
    );


  data +=
    ",\"ina219_available\":" +
    String(
      ina219Available
        ? "true"
        : "false"
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// START CHARGING
// ============================================================
//
// v1.0.1 FIX
// ------------------------------------------------------------
// Only the commanded path state (relayPathEnabled) is set
// directly here. "charging" is left for
// updateChargingStateFromMeasurement() to determine on the
// next measurement tick (<=1s later), based on real current
// draw. This keeps "charging" meaning exactly one thing
// everywhere in the firmware: "current is actually flowing",
// never "the user asked for it to flow".
//
// If a device is already drawing current the moment the path
// is enabled, the very next measurement tick will correctly
// flip charging=true and start a session with voice feedback -
// so there is no meaningful behavior change for the normal
// case, but the state can no longer be forced into an
// inconsistent snapshot.
//

void commandStartCharging(
  int id
) {

  Serial.println(
    "COMMAND: start_charging"
  );


  relayChargingOn();


  // Allow USB-PD / device connection to begin drawing current
  delay(150);

  // Take a fresh reading immediately so telemetry pushed right
  // after this response is as up to date as possible.
  readPower();

  updateChargingStateFromMeasurement();

  updateLiveCache();

  // If path is enabled, but current is below threshold: circuit open / no device connected!
  if (
    ina219Available &&
    currentA < CHARGING_STOP_THRESHOLD_A
  ) {

    Serial.println(
      "CIRCUIT OPEN: No device connected to charging port"
    );

    playAudio(
      no_device,
      no_device_len
    );
  }


  String data;

  data =
    "{\"command_accepted\":true";

  data +=
    ",\"path_enabled\":" +
    String(
      relayPathEnabled
        ? "true"
        : "false"
    );

  data +=
    ",\"charging\":" +
    String(
      charging
        ? "true"
        : "false"
    );

  data +=
    "}";

  sendResponse(
    id,
    data
  );

  // Immediately push new live data state to Flutter
  sendLiveData();
}

// ============================================================
// STOP CHARGING
// ============================================================
//
// v1.0.1 FIX
// ------------------------------------------------------------
// This is the authoritative fix for the reported bug:
//
//   BLE COMMAND SENT: {"command":"stop_charging"}
//   ... followed moments later by ...
//   "charging": true, "path_enabled": true
//
// Previously this handler forced charging=false directly, but
// the very next 1-second measurement tick called
// updateChargingStateFromMeasurement(), which re-derived
// "charging" purely from currentA >= threshold - with no idea
// a stop had just been requested - and flipped it straight
// back to true (and even restarted a session + replayed the
// "charging started" voice clip).
//
// Now:
//   1. The relay is physically disabled FIRST.
//   2. Any active session is explicitly closed out (this was
//      previously skipped entirely, leaving sessionActive
//      stuck true forever after a stop_charging command).
//   3. charging/path_enabled are set to false for immediate
//      reporting.
//   4. Because relayPathEnabled is now false,
//      updateChargingStateFromMeasurement() will GATE OFF any
//      current-based re-activation on every future tick - so
//      this false state is now guaranteed to actually stick,
//      instead of just being a value that gets overwritten
//      one second later.
//

void commandStopCharging(
  int id,
  const String &reason = ""
) {

  Serial.println(
    "COMMAND: stop_charging"
  );

  if (reason.length() > 0) {
    Serial.print(
      "  reason: "
    );
    Serial.println(
      reason
    );
  }


  relayChargingOff();


  if (sessionActive) {

    stopChargingSession(
      true,
      reason.length() > 0
        ? reason.c_str()
        : nullptr
    );

  } else if (reason.length() > 0) {

    if (
      reason == "full_charge" ||
      reason == "battery_full"
    ) {

      playAudio(
        full_charge,
        full_charge_len
      );

    } else if (
      reason == "no_device"
    ) {

      playAudio(
        no_device,
        no_device_len
      );

    } else if (
      reason == "error" ||
      reason == "charging_error"
    ) {

      playAudio(
        charging_error,
        charging_error_len
      );

    } else if (
      reason == "power_limit" ||
      reason == "limit"
    ) {

      playAudio(
        power_limit,
        power_limit_len
      );
    }
  }


  charging =
    false;


  // Verify the physical stop: take an immediate fresh reading
  // so we can warn (via Serial) if current is still flowing
  // through a path that should now be open.
  readPower();

  updateLiveCache();


  if (
    ina219Available &&
    currentA >=
    CHARGING_STOP_THRESHOLD_A
  ) {

    Serial.print(
      "STOP VERIFICATION: current still "
    );

    Serial.print(
      currentA,
      3
    );

    Serial.println(
      " A after relay disable - possible relay/polarity fault"
    );

  }

  else {

    Serial.println(
      "STOP VERIFICATION: current at/near zero - OK"
    );
  }


  String data;

  data =
    "{\"command_accepted\":true";

  data +=
    ",\"path_enabled\":false";

  data +=
    ",\"charging\":false";

  data +=
    "}";

  sendResponse(
    id,
    data
  );

  // Immediately push new live data state to Flutter
  sendLiveData();
}
// ============================================================
// GET CHARGING LIMIT
// ============================================================

void commandGetChargingLimit(
  int id
) {

  String data =
    "{\"percentage\":" +
    String(
      chargingLimit
    ) +
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// SET CHARGING LIMIT
// ============================================================

void commandSetChargingLimit(
  int id,
  int percentage
) {

  if (
    percentage < 0 ||
    percentage > 100
  ) {

    sendError(
      id,
      "INVALID_VALUE",
      "Charging limit must be between 0 and 100"
    );


    return;
  }


  chargingLimit =
    percentage;


  saveChargingLimit();


  // Response FIRST.
  String data =
    "{\"percentage\":" +
    String(
      chargingLimit
    ) +
    "}";


  sendResponse(
    id,
    data
  );


  // Voice AFTER response.
  playAudio(
    power_limit,
    power_limit_len
  );
}


// ============================================================
// GET SAMPLE
// ============================================================

void commandGetSample(
  int id
) {

  String data;


  data =
    "{\"timestamp\":" +
    String(
      getTimestamp()
    );


  data +=
    ",\"timestamp_type\":\"uptime_seconds\"";


  data +=
    ",\"session_id\":" +
    String(
      sessionId
    );


  data +=
    ",\"voltage_v\":" +
    String(
      voltageV,
      3
    );


  data +=
    ",\"current_a\":" +
    String(
      currentA,
      3
    );


  data +=
    ",\"power_w\":" +
    String(
      powerW,
      3
    );


  data +=
    ",\"session_energy_wh\":" +
    String(
      sessionEnergyWh,
      4
    );


  data +=
    ",\"charging\":" +
    String(
      charging
        ? "true"
        : "false"
    );


  data +=
    ",\"path_enabled\":" +
    String(
      relayPathEnabled
        ? "true"
        : "false"
    );


  data +=
    ",\"ina219_available\":" +
    String(
      ina219Available
        ? "true"
        : "false"
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// GET TEMPERATURE
// ============================================================

void commandGetTemperature(
  int id
) {

  sendResponse(
    id,
    "{\"available\":false,\"temperature_c\":null,\"source\":null}"
  );
}


// ============================================================
// GET ENERGY
// ============================================================

void commandGetEnergy(
  int id
) {

  String data;


  data =
    "{\"session_energy_wh\":" +
    String(
      sessionEnergyWh,
      4
    );


  data +=
    ",\"total_energy_wh\":" +
    String(
      totalEnergyWh,
      4
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// GET SESSION
// ============================================================

void commandGetSession(
  int id
) {

  unsigned long durationSeconds =
    0;


  if (
    sessionActive
  ) {

    durationSeconds =
      (
        millis() -
        sessionStartMillis
      )
      /
      1000UL;
  }


  String data;


  data =
    "{\"active\":" +
    String(
      sessionActive
        ? "true"
        : "false"
    );


  data +=
    ",\"session_id\":" +
    String(
      sessionId
    );


  data +=
    ",\"start_uptime_seconds\":" +
    String(
      sessionStartTimestamp
    );


  data +=
    ",\"duration_seconds\":" +
    String(
      durationSeconds
    );


  data +=
    ",\"energy_wh\":" +
    String(
      sessionEnergyWh,
      4
    );


  data +=
    ",\"peak_power_w\":" +
    String(
      sessionPeakPowerW,
      3
    );


  data +=
    ",\"average_power_w\":" +
    String(
      sessionAveragePowerW,
      3
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// GET DEVICE INFO
// ============================================================

void commandGetDeviceInfo(
  int id
) {

  String data;


  data =
    "{\"name\":\"" +
    String(
      DEVICE_NAME
    );


  data +=
    "\",\"model\":\"" +
    String(
      MODEL_NAME
    );


  data +=
    "\",\"hardware_version\":\"" +
    String(
      HARDWARE_VERSION
    );


  data +=
    "\",\"firmware_version\":\"" +
    String(
      FIRMWARE_VERSION
    );


  data +=
    "\",\"protocol_version\":\"" +
    String(
      PROTOCOL_VERSION
    );


  data +=
    "\",\"uptime_seconds\":" +
    String(
      getTimestamp()
    );


  data +=
    ",\"ina219_available\":" +
    String(
      ina219Available
        ? "true"
        : "false"
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// CLEAR SESSION
// ============================================================
//
// History is NOT erased.
// Total energy is NOT erased.
//
// If charging:
//   current session is replaced with a fresh session.
//

void commandClearSession(
  int id
) {

  bool wasCharging =
    charging;


  if (
    wasCharging
  ) {

    sessionActive =
      false;


    resetSessionStatistics();


    sessionId++;

    saveSessionId();


    sessionStartMillis =
      millis();


    sessionStartTimestamp =
      getTimestamp();


    sessionActive =
      true;
  }


  else {

    sessionActive =
      false;


    resetSessionStatistics();


    sessionStartMillis =
      0;


    sessionStartTimestamp =
      0;
  }


  String data;


  data =
    "{\"cleared\":true";


  data +=
    ",\"active\":" +
    String(
      sessionActive
        ? "true"
        : "false"
    );


  data +=
    ",\"session_id\":" +
    String(
      sessionId
    );


  data +=
    "}";


  sendResponse(
    id,
    data
  );
}


// ============================================================
// JSON INTEGER EXTRACTION
// ============================================================

int extractInteger(
  const String &json,
  const String &key
) {

  String searchKey =
    "\"" +
    key +
    "\"";


  int position =
    json.indexOf(
      searchKey
    );


  if (
    position < 0
  ) {

    return -1;
  }


  int colon =
    json.indexOf(
      ':',
      position
    );


  if (
    colon < 0
  ) {

    return -1;
  }


  int comma =
    json.indexOf(
      ',',
      colon
    );


  int brace =
    json.indexOf(
      '}',
      colon
    );


  int closeBrace =
    json.indexOf(
      ']',
      colon
    );


  int end =
    json.length();


  if (
    comma >= 0
  ) {

    end =
      min(
        end,
        comma
      );
  }


  if (
    brace >= 0
  ) {

    end =
      min(
        end,
        brace
      );
  }


  if (
    closeBrace >= 0
  ) {

    end =
      min(
        end,
        closeBrace
      );
  }


  String value =
    json.substring(
      colon + 1,
      end
    );


  value.trim();


  return value.toInt();
}


// ============================================================
// JSON ID
// ============================================================

int extractId(
  const String &json
) {

  return extractInteger(
    json,
    "id"
  );
}


// ============================================================
// JSON COMMAND
// ============================================================

String extractCommand(
  const String &json
) {

  const String key =
    "\"command\"";


  int position =
    json.indexOf(
      key
    );


  if (
    position < 0
  ) {

    return "";
  }


  int colon =
    json.indexOf(
      ':',
      position
    );


  if (
    colon < 0
  ) {

    return "";
  }


  int firstQuote =
    json.indexOf(
      '"',
      colon + 1
    );


  if (
    firstQuote < 0
  ) {

    return "";
  }


  int secondQuote =
    json.indexOf(
      '"',
      firstQuote + 1
    );


  if (
    secondQuote < 0
  ) {

    return "";
  }


  return json.substring(
    firstQuote + 1,
    secondQuote
  );
}


// ============================================================
// JSON STRING EXTRACTOR
// ============================================================

String extractString(
  const String &json,
  const String &fieldName
) {

  String key =
    "\"" + fieldName + "\"";

  int position =
    json.indexOf(
      key
    );

  if (position < 0) {
    return "";
  }

  int colon =
    json.indexOf(
      ':',
      position
    );

  if (colon < 0) {
    return "";
  }

  int firstQuote =
    json.indexOf(
      '"',
      colon + 1
    );

  if (firstQuote < 0) {
    return "";
  }

  int secondQuote =
    json.indexOf(
      '"',
      firstQuote + 1
    );

  if (secondQuote < 0) {
    return "";
  }

  return json.substring(
    firstQuote + 1,
    secondQuote
  );
}


// ============================================================
// HISTORY CHUNK
// ============================================================

void sendHistoryChunk(
  int requestId,
  int chunkNumber,
  int totalChunks,
  int sampleCount,
  int oldestIndex,
  int startOffset
) {

  String packet;

  packet.reserve(
    650
  );


  packet =
    "{\"type\":\"history\"";


  packet +=
    ",\"request_id\":" +
    String(
      requestId
    );


  packet +=
    ",\"chunk\":" +
    String(
      chunkNumber
    );


  packet +=
    ",\"total_chunks\":" +
    String(
      totalChunks
    );


  packet +=
    ",\"samples\":[";


  for (
    int i = 0;
    i < sampleCount;
    i++
  ) {

    if (
      i > 0
    ) {

      packet += ",";
    }


    int relativeIndex =
      startOffset +
      (
        (
          chunkNumber - 1
        )
        *
        HISTORY_SAMPLES_PER_CHUNK
      )
      +
      i;


    int actualIndex =
      (
        oldestIndex +
        relativeIndex
      )
      %
      HISTORY_SIZE;


    HistorySample &sample =
      history[
        actualIndex
      ];


    packet +=
      "{\"timestamp\":" +
      String(
        sample.timestamp
      );


    packet +=
      ",\"timestamp_type\":\"uptime_seconds\"";


    packet +=
      ",\"session_id\":" +
      String(
        sample.sessionId
      );


    packet +=
      ",\"voltage_v\":" +
      String(
        sample.voltageV,
        3
      );


    packet +=
      ",\"current_a\":" +
      String(
        sample.currentA,
        3
      );


    packet +=
      ",\"power_w\":" +
      String(
        sample.powerW,
        3
      );


    packet +=
      ",\"session_energy_wh\":" +
      String(
        sample.sessionEnergyWh,
        4
      );


    packet +=
      ",\"charging\":" +
      String(
        sample.charging
          ? "true"
          : "false"
      );


    packet +=
      ",\"path_enabled\":" +
      String(
        sample.pathEnabled
          ? "true"
          : "false"
      );


    packet +=
      "}";
  }


  packet +=
    "]}";


  if (
    bleConnected &&
    historyCharacteristic != nullptr
  ) {

    historyCharacteristic->setValue(
      packet.c_str()
    );


    historyCharacteristic->notify();
  }
}


// ============================================================
// GET HISTORY
// ============================================================

void commandGetHistory(
  int id,
  int requestedLimit
) {

  if (
    requestedLimit <= 0
  ) {

    requestedLimit =
      100;
  }


  if (
    requestedLimit >
    HISTORY_SIZE
  ) {

    requestedLimit =
      HISTORY_SIZE;
  }


  int sampleCount =
    min(
      requestedLimit,
      historyCount
    );


  int totalChunks =
    (
      sampleCount +
      HISTORY_SAMPLES_PER_CHUNK -
      1
    )
    /
    HISTORY_SAMPLES_PER_CHUNK;


  String metadata;


  metadata =
    "{\"sample_count\":" +
    String(
      sampleCount
    );


  metadata +=
    ",\"total_chunks\":" +
    String(
      totalChunks
    );


  metadata +=
    ",\"ordering\":\"oldest_to_newest\"";


  metadata +=
    ",\"timestamp_type\":\"uptime_seconds\"";


  metadata +=
    "}";


  sendResponse(
    id,
    metadata
  );


  if (
    sampleCount == 0
  ) {

    return;
  }


  int oldestIndex;


  if (
    historyCount <
    HISTORY_SIZE
  ) {

    oldestIndex =
      0;
  }

  else {

    oldestIndex =
      historyIndex;
  }


  // Return newest requested samples in chronological order.

  int startOffset =
    historyCount -
    sampleCount;


  for (
    int chunk = 1;
    chunk <= totalChunks;
    chunk++
  ) {

    int chunkStart =
      (
        chunk - 1
      )
      *
      HISTORY_SAMPLES_PER_CHUNK;


    int remaining =
      sampleCount -
      chunkStart;


    int samplesThisChunk =
      min(
        HISTORY_SAMPLES_PER_CHUNK,
        remaining
      );


    sendHistoryChunk(
      id,
      chunk,
      totalChunks,
      samplesThisChunk,
      oldestIndex,
      startOffset
    );


    delay(20);
  }
}


// ============================================================
// HANDLE COMMAND
// ============================================================

void handleCommand(
  String json
) {

  json.trim();


  if (
    json.length() == 0
  ) {

    return;
  }


  Serial.println();

  Serial.println(
    "--------------------------------------"
  );


  Serial.print(
    "BLE COMMAND RECEIVED (RAW): "
  );

  Serial.println(
    json
  );


  int id =
    extractId(
      json
    );


  if (
    id < 0
  ) {

    id = 0;
  }


  String command =
    extractCommand(
      json
    );


  Serial.print(
    "BLE COMMAND PARSED: "
  );

  Serial.println(
    command
  );


  if (
    command.length() == 0
  ) {

    sendError(
      id,
      "INVALID_COMMAND",
      "Command field missing"
    );


    return;
  }


  if (
    command ==
    "get_status"
  ) {

    commandGetStatus(
      id
    );


  }

  else if (
    command ==
    "get_power"
  ) {

    commandGetPower(
      id
    );


  }

  else if (
    command ==
    "get_charging_state"
  ) {

    commandGetChargingState(
      id
    );


  }

  else if (
    command ==
    "start_charging"
  ) {

    commandStartCharging(
      id
    );


  }

  else if (
    command ==
    "stop_charging"
  ) {

    String reason =
      extractString(
        json,
        "reason"
      );

    commandStopCharging(
      id,
      reason
    );


  }

  else if (
    command ==
    "get_charging_limit"
  ) {

    commandGetChargingLimit(
      id
    );


  }

  else if (
    command ==
    "set_charging_limit"
  ) {

    int percentage =
      extractInteger(
        json,
        "percentage"
      );


    if (
      percentage < 0
    ) {

      sendError(
        id,
        "INVALID_VALUE",
        "Percentage missing"
      );

    }

    else {

      commandSetChargingLimit(
        id,
        percentage
      );
    }


  }

  else if (
    command ==
    "get_sample"
  ) {

    commandGetSample(
      id
    );


  }

  else if (
    command ==
    "get_temperature"
  ) {

    commandGetTemperature(
      id
    );


  }

  else if (
    command ==
    "get_energy"
  ) {

    commandGetEnergy(
      id
    );


  }

  else if (
    command ==
    "get_session"
  ) {

    commandGetSession(
      id
    );


  }

  else if (
    command ==
    "clear_session"
  ) {

    commandClearSession(
      id
    );


  }

  else if (
    command ==
    "get_device_info"
  ) {

    commandGetDeviceInfo(
      id
    );


  }

  else if (
    command ==
    "get_history"
  ) {

    int limit =
      extractInteger(
        json,
        "limit"
      );


    if (
      limit <= 0
    ) {

      limit =
        100;
    }


    commandGetHistory(
      id,
      limit
    );


  }

  else if (
    command ==
    "play_voice"
  ) {

    String voice =
      extractString(
        json,
        "voice"
      );

    if (
      voice == "full_charge" ||
      voice == "battery_full" ||
      voice == "battery_charged"
    ) {

      playAudio(
        full_charge,
        full_charge_len
      );

    } else if (
      voice == "no_device"
    ) {

      playAudio(
        no_device,
        no_device_len
      );

    } else if (
      voice == "error" ||
      voice == "charging_error"
    ) {

      playAudio(
        charging_error,
        charging_error_len
      );

    } else if (
      voice == "started" ||
      voice == "charging_started"
    ) {

      playAudio(
        charging_started,
        charging_started_len
      );

    } else if (
      voice == "stopped" ||
      voice == "charging_stopped"
    ) {

      playAudio(
        charging_stopped,
        charging_stopped_len
      );

    } else if (
      voice == "power_limit" ||
      voice == "limit"
    ) {

      playAudio(
        power_limit,
        power_limit_len
      );
    }

    sendResponse(
      id,
      "{\"command_accepted\":true}"
    );

  }

  else {

    sendError(
      id,
      "UNKNOWN_COMMAND",
      "Unknown command"
    );
  }
}


// ============================================================
// BLE SERVER CALLBACKS
// ============================================================

class ServerCallbacks :
  public BLEServerCallbacks {

  void onConnect(
    BLEServer *server
  ) override {

    bleConnected =
      true;


    Serial.println();

    Serial.println(
      "BLE CLIENT CONNECTED"
    );
  }


  void onDisconnect(
    BLEServer *server
  ) override {

    bleConnected =
      false;


    Serial.println();

    Serial.println(
      "BLE CLIENT DISCONNECTED"
    );


    delay(100);


    BLEDevice::startAdvertising();
  }
};


// ============================================================
// BLE COMMAND CALLBACK
// ============================================================

class CommandCallbacks :
  public BLECharacteristicCallbacks {

  void onWrite(
    BLECharacteristic *characteristic
  ) override {

    String value =
      characteristic->getValue();


    if (
      value.length() == 0
    ) {

      return;
    }


    handleCommand(
      value
    );
  }
};


// ============================================================
// BLE SETUP
// ============================================================

void setupBLE() {

  Serial.println();

  Serial.println(
    "Initializing BLE..."
  );


  BLEDevice::init(
    DEVICE_NAME
  );


  bleServer =
    BLEDevice::createServer();


  bleServer->setCallbacks(
    new ServerCallbacks()
  );


  BLEService *service =
    bleServer->createService(
      SERVICE_UUID
    );


  // ========================================================
  // COMMAND
  // ========================================================

  commandCharacteristic =
    service->createCharacteristic(
      COMMAND_UUID,
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_WRITE_NR
    );


  commandCharacteristic->setCallbacks(
    new CommandCallbacks()
  );


  // ========================================================
  // RESPONSE
  // ========================================================

  responseCharacteristic =
    service->createCharacteristic(
      RESPONSE_UUID,
      BLECharacteristic::PROPERTY_NOTIFY
    );


  responseCharacteristic->addDescriptor(
    new BLE2902()
  );


  // ========================================================
  // LIVE DATA
  // ========================================================

  liveDataCharacteristic =
    service->createCharacteristic(
      LIVE_DATA_UUID,
      BLECharacteristic::PROPERTY_NOTIFY
    );


  liveDataCharacteristic->addDescriptor(
    new BLE2902()
  );


  // ========================================================
  // HISTORY
  // ========================================================

  historyCharacteristic =
    service->createCharacteristic(
      HISTORY_UUID,
      BLECharacteristic::PROPERTY_NOTIFY
    );


  historyCharacteristic->addDescriptor(
    new BLE2902()
  );


  service->start();


BLEAdvertising *advertising =
  BLEDevice::getAdvertising();

advertising->addServiceUUID(
  SERVICE_UUID
);

advertising->setScanResponse(true);

Serial.println("Starting BLE advertising...");

advertising->start();

Serial.println("BLE ADVERTISING STARTED");
Serial.println("ESP32 should now be discoverable");


  Serial.println();

  Serial.println(
    "======================================"
  );

  Serial.println(
    "BLE READY"
  );

  Serial.print(
    "Device: "
  );

  Serial.println(
    DEVICE_NAME
  );
  Serial.print(
    "BLE Address: "
  );

  Serial.println(
    BLEDevice::getAddress().toString().c_str()
  );



  Serial.print(
    "Service UUID: "
  );

  Serial.println(
    SERVICE_UUID
  );

  Serial.println(
    "======================================"
  );
}


// ============================================================
// LIVE DATA NOTIFICATION
// ============================================================

void sendLiveData() {

  if (
    !bleConnected ||
    liveDataCharacteristic == nullptr
  ) {

    return;
  }


  String json;

  json.reserve(
    600
  );


  json =
    "{\"type\":\"live_data\",\"data\":{";


  json +=
    "\"timestamp\":" +
    String(
      liveData.timestamp
    );


  json +=
    ",\"timestamp_type\":\"uptime_seconds\"";


  json +=
    ",\"voltage_v\":" +
    String(
      liveData.voltageV,
      3
    );


  json +=
    ",\"current_a\":" +
    String(
      liveData.currentA,
      3
    );


  json +=
    ",\"power_w\":" +
    String(
      liveData.powerW,
      3
    );


  json +=
    ",\"charging\":" +
    String(
      liveData.charging
        ? "true"
        : "false"
    );


  json +=
    ",\"path_enabled\":" +
    String(
      liveData.pathEnabled
        ? "true"
        : "false"
    );


  json +=
    ",\"charging_limit\":" +
    String(
      liveData.chargingLimit
    );


  json +=
    ",\"ina219_available\":" +
    String(
      liveData.ina219Available
        ? "true"
        : "false"
    );


  json +=
    ",\"session_energy_wh\":" +
    String(
      liveData.sessionEnergyWh,
      4
    );


  json +=
    ",\"total_energy_wh\":" +
    String(
      liveData.totalEnergyWh,
      4
    );


  json +=
    "}}";


  liveDataCharacteristic->setValue(
    json.c_str()
  );


  liveDataCharacteristic->notify();
}


// ============================================================
// SERIAL STATUS
// ============================================================

void printSerialStatus() {

  Serial.println();

  Serial.println(
    "--------------------------------------"
  );


  Serial.print(
    "BLE             : "
  );

  Serial.println(
    bleConnected
      ? "CONNECTED"
      : "DISCONNECTED"
  );


  Serial.print(
    "NVS             : "
  );

  Serial.println(
    nvsAvailable
      ? "AVAILABLE"
      : "UNAVAILABLE"
  );


  Serial.print(
    "INA219          : "
  );

  Serial.println(
    ina219Available
      ? "AVAILABLE"
      : "UNAVAILABLE"
  );


  Serial.print(
    "Path enabled    : "
  );

  Serial.println(
    relayPathEnabled
      ? "YES"
      : "NO"
  );


  Serial.print(
    "Charging        : "
  );

  Serial.println(
    charging
      ? "YES"
      : "NO"
  );


  Serial.print(
    "Voltage         : "
  );

  Serial.print(
    voltageV,
    3
  );

  Serial.println(
    " V"
  );


  Serial.print(
    "Current         : "
  );

  Serial.print(
    currentA,
    3
  );

  Serial.println(
    " A"
  );


  Serial.print(
    "Power           : "
  );

  Serial.print(
    powerW,
    3
  );

  Serial.println(
    " W"
  );


  Serial.print(
    "Charging limit  : "
  );

  Serial.print(
    chargingLimit
  );

  Serial.println(
    "%"
  );


  Serial.print(
    "Session ID      : "
  );

  Serial.println(
    sessionId
  );


  Serial.print(
    "Session energy  : "
  );

  Serial.print(
    sessionEnergyWh,
    4
  );

  Serial.println(
    " Wh"
  );


  Serial.print(
    "Total energy    : "
  );

  Serial.print(
    totalEnergyWh,
    4
  );

  Serial.println(
    " Wh"
  );


  Serial.print(
    "History samples : "
  );

  Serial.println(
    historyCount
  );


  Serial.println(
    "--------------------------------------"
  );
}


// ============================================================
// SETUP
// ============================================================

void setup() {

  Serial.begin(
    115200
  );


  delay(500);


  Serial.println();

  Serial.println(
    "======================================"
  );

  Serial.println(
    "             CHARGE LINK"
  );

  Serial.println(
    "        ESP32 FIRMWARE v1.0.1"
  );

  Serial.println(
    "======================================"
  );


  // ========================================================
  // SYSTEM TIME
  // ========================================================

  deviceStartMillis =
    millis();


  // ========================================================
  // NVS
  // ========================================================

  Serial.println();

  Serial.println(
    "Initializing NVS..."
  );


  nvsAvailable =
    preferences.begin(
      "charge-link",
      false
    );


  if (nvsAvailable) {

    Serial.println(
      "NVS: OK"
    );

  }

  else {

    Serial.println(
      "NVS: ERROR"
    );
  }


  loadSettings();


  Serial.print(
    "Charging limit: "
  );

  Serial.print(
    chargingLimit
  );

  Serial.println(
    "%"
  );


  Serial.print(
    "Total energy: "
  );

  Serial.print(
    totalEnergyWh,
    4
  );

  Serial.println(
    " Wh"
  );


  Serial.print(
    "Next session ID: "
  );

  Serial.println(
    sessionId + 1
  );


  // ========================================================
  // RELAY
  // ========================================================
  //
  // v1.0.1: pinMode() is set explicitly BEFORE any digitalWrite,
  // and the path is forced to a known safe state immediately,
  // before BLE/telemetry start, so no startup glitch can leave
  // the pin floating or in an undefined state.
  //

  Serial.println();

  Serial.println(
    "Initializing relay..."
  );


  pinMode(
    RELAY_PIN,
    OUTPUT
  );


  /*
   * HIGH
   * -> relay coil OFF
   * -> NC CLOSED
   * -> charging path enabled
   */

  relayChargingOn();


  Serial.println(
    "Relay: OK"
  );

  Serial.println(
    "GPIO25 HIGH"
  );

  Serial.println(
    "NC CLOSED / PATH ENABLED"
  );


  // ========================================================
  // AUDIO DAC
  // ========================================================

  Serial.println();

  Serial.println(
    "Initializing audio DAC (0V standby)..."
  );


  pinMode(
    AUDIO_PIN,
    OUTPUT
  );


  dacWrite(
    AUDIO_PIN,
    0
  );


  Serial.println(
    "DAC: Standby OK (GPIO26 / DAC2 ready)"
  );


  // ========================================================
  // INA219
  // ========================================================

  Serial.println();

  Serial.println(
    "Initializing INA219..."
  );


  INA_WIRE.begin(
    INA_SDA,
    INA_SCL
  );


  INA_WIRE.setClock(
    400000
  );


  ina219Available =
    ina219.begin(
      &INA_WIRE
    );


  if (
    ina219Available
  ) {

    Serial.println(
      "INA219: OK"
    );


    ina219.setCalibration_32V_2A();

  }

  else {

    Serial.println(
      "INA219: NOT FOUND"
    );
  }


  // ========================================================
  // OLED
  // ========================================================

  Serial.println();

  Serial.println(
    "Initializing OLED..."
  );


  OLED_WIRE.begin(
    OLED_SDA,
    OLED_SCL
  );


  OLED_WIRE.setClock(
    400000
  );


  bool oledOK =
    display.begin(
      SSD1306_SWITCHCAPVCC,
      0x3C
    );


  if (oledOK) {

    Serial.println(
      "OLED: OK"
    );


    display.clearDisplay();


    display.setTextColor(
      SSD1306_WHITE
    );


    display.setTextSize(
      2
    );


    display.setCursor(
      0,
      0
    );


    display.println(
      "CHARGE"
    );


    display.setCursor(
      0,
      24
    );


    display.println(
      "LINK"
    );


    display.setTextSize(
      1
    );


    display.setCursor(
      0,
      52
    );


    display.println(
      "INITIALIZING..."
    );


    display.display();

  }

  else {

    Serial.println(
      "OLED: NOT FOUND"
    );
  }


  // ========================================================
  // INITIAL INA219 READING
  // ========================================================

  readPower();


  // ========================================================
  // INITIAL CHARGING STATE
  // ========================================================

  if (
    ina219Available &&
    currentA >=
    CHARGING_START_THRESHOLD_A
  ) {

    charging =
      true;


    startChargingSession(
      false
    );

  }

  else {

    charging =
      false;
  }


  // ========================================================
  // INITIAL CACHE
  // ========================================================

  updateLiveCache();


  // ========================================================
  // BLE
  // ========================================================

  setupBLE();


  // ========================================================
  // TIMER INITIALIZATION
  // ========================================================

  unsigned long now =
    millis();


  lastMeasurementMillis =
    now;


  lastHistoryMillis =
    now;


  lastLiveNotificationMillis =
    now;


  lastOLEDMillis =
    now;


  lastNVSSaveMillis =
    now;


  lastSerialMillis =
    now;


  // First history sample intentionally occurs after 10 sec.


  updateOLED();


  // ========================================================
  // READY
  // ========================================================

  Serial.println();

  Serial.println(
    "======================================"
  );

  Serial.println(
    "SYSTEM READY"
  );

  Serial.println(
    "======================================"
  );


  Serial.print(
    "INA219       : "
  );

  Serial.println(
    ina219Available
      ? "OK"
      : "NOT FOUND"
  );


  Serial.print(
    "Relay path   : "
  );

  Serial.println(
    relayPathEnabled
      ? "ENABLED"
      : "DISABLED"
  );


  Serial.print(
    "Charging     : "
  );

  Serial.println(
    charging
      ? "YES"
      : "NO"
  );


  Serial.println(
    "BLE          : READY"
  );


  Serial.println(
    "======================================"
  );


  // Startup Voice Greeting: Test 3W speaker immediately on boot/flash
  Serial.println();
  Serial.println(
    "Playing startup voice greeting..."
  );

  playAudio(
    charging_started,
    charging_started_len
  );
}



// ============================================================
// MAIN LOOP
// ============================================================

void loop() {

  unsigned long now =
    millis();


  // ========================================================
  // MEASUREMENT
  // ========================================================

  if (
    now -
    lastMeasurementMillis
    >=
    MEASUREMENT_INTERVAL_MS
  ) {

    float elapsedSeconds =
      (
        now -
        lastMeasurementMillis
      )
      /
      1000.0f;


    lastMeasurementMillis =
      now;


    // ------------------------------------------------------
    // Read INA219
    // ------------------------------------------------------

    readPower();


    // ------------------------------------------------------
    // Charging state
    // ------------------------------------------------------

    updateChargingStateFromMeasurement();


    // ------------------------------------------------------
    // Energy
    // ------------------------------------------------------

    updateEnergy(
      elapsedSeconds
    );


    // ------------------------------------------------------
    // Cache
    // ------------------------------------------------------

    updateLiveCache();
  }


  // ========================================================
  // HISTORY
  // ========================================================

  if (
    now -
    lastHistoryMillis
    >=
    HISTORY_INTERVAL_MS
  ) {

    lastHistoryMillis =
      now;


    addHistorySample();
  }


  // ========================================================
  // LIVE DATA
  // ========================================================

  if (
    now -
    lastLiveNotificationMillis
    >=
    LIVE_NOTIFICATION_MS
  ) {

    lastLiveNotificationMillis =
      now;


    sendLiveData();
  }


  // ========================================================
  // OLED
  // ========================================================

  if (
    now -
    lastOLEDMillis
    >=
    OLED_INTERVAL_MS
  ) {

    lastOLEDMillis =
      now;


    updateOLED();
  }


  // ========================================================
  // NVS
  // ========================================================

  if (
    now -
    lastNVSSaveMillis
    >=
    NVS_SAVE_INTERVAL_MS
  ) {

    lastNVSSaveMillis =
      now;


    saveEnergy();
  }


  // ========================================================
  // SERIAL
  // ========================================================

  if (
    now -
    lastSerialMillis
    >=
    SERIAL_INTERVAL_MS
  ) {

    lastSerialMillis =
      now;


    // printSerialStatus();  // Disabled: prevents repeated large Serial Monitor status blocks
  }


  // ========================================================
  // YIELD
  // ========================================================

  delay(5);
}


