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


// ============================================================
// DEVICE INFORMATION
// ============================================================

#define DEVICE_NAME          "Charge Link"
#define MODEL_NAME           "CL-SCB-01"
#define HARDWARE_VERSION     "1.0"
#define FIRMWARE_VERSION     "1.0.0"
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
// AUDIO FILTER STATE
// ============================================================

float dcFilter = 0.0f;

float bassFilter = 0.0f;

float trebleFilter = 0.0f;

float previousOutput = 0.0f;

bool audioPlaying = false;


// ============================================================
// AUDIO EQ
// ============================================================

const float DC_ALPHA =
  0.995f;

const float BASS_ALPHA =
  0.045f;

const float TREBLE_ALPHA =
  0.35f;

const float BASS_GAIN =
  1.08f;

const float VOICE_GAIN =
  1.10f;

const float CLARITY_GAIN =
  1.12f;

const float OUTPUT_GAIN =
  0.88f;


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
// AUDIO SOFT LIMITER
// ============================================================

float softLimit(float x) {

  if (x > 1.0f) {

    x =
      1.0f -
      (
        1.0f /
        (x + 1.0f)
      );
  }


  if (x < -1.0f) {

    x =
      -1.0f +
      (
        1.0f /
        (-x + 1.0f)
      );
  }


  return x;
}


// ============================================================
// AUDIO PROCESSING
// ============================================================

float processAudioSample(float input) {

  dcFilter =
    DC_ALPHA * dcFilter +
    (1.0f - DC_ALPHA) * input;


  float clean =
    input -
    dcFilter;


  bassFilter =
    bassFilter +
    BASS_ALPHA *
    (
      clean -
      bassFilter
    );


  float bass =
    bassFilter;


  trebleFilter =
    trebleFilter +
    TREBLE_ALPHA *
    (
      clean -
      trebleFilter
    );


  float treble =
    clean -
    trebleFilter;


  float voice =
    clean -
    bass -
    treble;


  float processed =
      (bass   * BASS_GAIN)
    + (voice  * VOICE_GAIN)
    + (treble * CLARITY_GAIN);


  processed *=
    OUTPUT_GAIN;


  processed =
      previousOutput * 0.10f
    + processed * 0.90f;


  previousOutput =
    processed;


  processed =
    softLimit(
      processed
    );


  return processed;
}


// ============================================================
// PLAY PCM AUDIO
// ============================================================
//
// 16-bit signed PCM
// Little endian
// 16 kHz
// Mono
//
// Blocking for the current prototype.
//

void playAudio(
  const unsigned char *audio,
  unsigned int length
) {

  if (
    audioPlaying ||
    audio == nullptr ||
    length < 2
  ) {

    return;
  }


  audioPlaying =
    true;


  Serial.println();

  Serial.println(
    "======================================"
  );

  Serial.println(
    "PLAYING VOICE"
  );

  Serial.println(
    "GPIO26 / DAC2"
  );

  Serial.println(
    "16-bit PCM / 16 kHz / MONO"
  );

  Serial.println(
    "======================================"
  );


  dcFilter = 0.0f;

  bassFilter = 0.0f;

  trebleFilter = 0.0f;

  previousOutput = 0.0f;


  unsigned int samples =
    length / 2;


  unsigned long nextSample =
    micros();


  bool extraMicrosecond =
    false;


  for (
    unsigned int i = 0;
    i < samples;
    i++
  ) {

    uint16_t low =
      audio[
        i * 2
      ];


    uint16_t high =
      audio[
        i * 2 + 1
      ];


    int16_t rawSample =
      (int16_t)(
        (high << 8) |
        low
      );


    float input =
      (float)rawSample /
      32768.0f;


    float processed =
      processAudioSample(
        input
      );


    int dacValue =
      (int)(
        processed * 127.0f +
        128.0f
      );


    if (dacValue < 0) {

      dacValue = 0;
    }


    if (dacValue > 255) {

      dacValue = 255;
    }


    dacWrite(
      AUDIO_PIN,
      (uint8_t)dacValue
    );


    nextSample += 62;

    extraMicrosecond =
      !extraMicrosecond;


    if (extraMicrosecond) {

      nextSample += 1;
    }


    while (
      (long)(
        micros() -
        nextSample
      ) < 0
    ) {

      yield();
    }
  }


  dacWrite(
    AUDIO_PIN,
    128
  );


  audioPlaying =
    false;


  Serial.println(
    "Voice finished."
  );
}


// ============================================================
// RELAY CONTROL
// ============================================================

void relayChargingOn() {

  digitalWrite(
    RELAY_PIN,
    HIGH
  );


  relayPathEnabled =
    true;
}


void relayChargingOff() {

  digitalWrite(
    RELAY_PIN,
    LOW
  );


  relayPathEnabled =
    false;
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
  bool playVoice
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
      charging_stopped,
      charging_stopped_len
    );
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

    if (
      currentA <=
      CHARGING_STOP_THRESHOLD_A
    ) {

      charging =
        false;


      stopChargingSession(
        true
      );
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

void commandStartCharging(
  int id
) {

  relayChargingOn();


  String data;


  data =
    "{\"command_accepted\":true";


  data +=
    ",\"path_enabled\":true";


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
}


// ============================================================
// STOP CHARGING
// ============================================================

void commandStopCharging(
  int id
) {

  relayChargingOff();


  String data;


  data =
    "{\"command_accepted\":true";


  data +=
    ",\"path_enabled\":false";


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
    "BLE COMMAND: "
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

    return;
  }


  String command =
    extractCommand(
      json
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

    commandStopCharging(
      id
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
      BLECharacteristic::PROPERTY_WRITE
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


  advertising->setScanResponse(
    true
  );


  advertising->start();


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
    "        ESP32 FIRMWARE v1.0.0"
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
    "Initializing audio DAC..."
  );


  pinMode(
    AUDIO_PIN,
    OUTPUT
  );


  dacWrite(
    AUDIO_PIN,
    128
  );


  Serial.println(
    "DAC: OK"
  );

  Serial.println(
    "GPIO26 / DAC2"
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


    printSerialStatus();
  }


  // ========================================================
  // YIELD
  // ========================================================

  delay(5);
}