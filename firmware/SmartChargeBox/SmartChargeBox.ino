#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#include "charging_started.h"
#include "charging_stopped.h"
#include "power_limit.h"

// =====================================================
// PIN DEFINITIONS
// =====================================================

#define INA_SDA       21
#define INA_SCL       22

#define OLED_SDA      18
#define OLED_SCL      19

#define RELAY_PIN     25
#define AUDIO_PIN     27

// =====================================================
// AUDIO
// =====================================================

#define SAMPLE_RATE   16000
#define PWM_FREQ      78125
#define PWM_BITS      8

// =====================================================
// OLED
// =====================================================

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64

TwoWire INA_WIRE  = TwoWire(0);
TwoWire OLED_WIRE = TwoWire(1);

Adafruit_INA219 ina219;

Adafruit_SSD1306 display(
  SCREEN_WIDTH,
  SCREEN_HEIGHT,
  &OLED_WIRE,
  -1
);

// =====================================================
// PLAY AUDIO
// =====================================================

void playAudio(const unsigned char *audio, unsigned int length) {

  Serial.println("Playing audio...");

  // 16-bit PCM = 2 bytes per sample
  unsigned int samples = length / 2;

  // 16 kHz sample period
  const unsigned long samplePeriod = 1000000UL / SAMPLE_RATE;

  unsigned long nextSample = micros();

  for (unsigned int i = 0; i < samples; i++) {

    // -------------------------------------------------
    // Read 16-bit little-endian PCM
    // -------------------------------------------------

    int16_t sample =
      (int16_t)(
        ((uint16_t)audio[i * 2 + 1] << 8) |
        audio[i * 2]
      );

    // -------------------------------------------------
    // Convert signed 16-bit to unsigned 8-bit
    // -------------------------------------------------

    uint8_t output =
      (uint8_t)(((int32_t)sample + 32768) >> 8);

    // Send sample to PWM
    ledcWrite(AUDIO_PIN, output);

    // -------------------------------------------------
    // Maintain 16 kHz timing
    // -------------------------------------------------

    nextSample += samplePeriod;

    while ((long)(micros() - nextSample) < 0) {
      // wait
    }
  }

  // Silence
  ledcWrite(AUDIO_PIN, 128);

  Serial.println("Audio finished.");
}

// =====================================================
// SETUP
// =====================================================

void setup() {

  Serial.begin(115200);

  delay(1000);

  Serial.println();
  Serial.println("======================================");
  Serial.println("        SMART CHARGE BOX");
  Serial.println("======================================");

  // ===================================================
  // RELAY
  // ===================================================

  pinMode(RELAY_PIN, OUTPUT);

  // Relay coil OFF initially
  // Active LOW relay:
  // HIGH = coil OFF
  // LOW  = coil ON

  digitalWrite(RELAY_PIN, HIGH);

  Serial.println("Relay initialized.");
  Serial.println("NC path = CHARGING ON");

  // ===================================================
  // AUDIO PWM
  // ===================================================

  Serial.println("Starting audio PWM...");

  if (ledcAttach(
        AUDIO_PIN,
        PWM_FREQ,
        PWM_BITS
      )) {

    Serial.println("Audio PWM: OK");

  } else {

    Serial.println("Audio PWM: ERROR");
  }

  // Center value = silence
  ledcWrite(AUDIO_PIN, 128);

  // ===================================================
  // INA219
  // ===================================================

  INA_WIRE.begin(
    INA_SDA,
    INA_SCL
  );

  Serial.println("Checking INA219...");

  if (ina219.begin(&INA_WIRE)) {

    Serial.println("INA219: OK");

    ina219.setCalibration_32V_2A();

  } else {

    Serial.println("INA219: NOT FOUND!");
  }

  // ===================================================
  // OLED
  // ===================================================

  OLED_WIRE.begin(
    OLED_SDA,
    OLED_SCL
  );

  Serial.println("Checking OLED...");

  if (display.begin(
        SSD1306_SWITCHCAPVCC,
        0x3C
      )) {

    Serial.println("OLED: OK");

    display.clearDisplay();

    display.setTextColor(SSD1306_WHITE);

    display.setTextSize(2);

    display.setCursor(0, 0);
    display.println("SMART");

    display.setCursor(0, 25);
    display.println("CHARGE BOX");

    display.setTextSize(1);

    display.setCursor(0, 52);
    display.println("VOICE TEST");

    display.display();

  } else {

    Serial.println("OLED: NOT FOUND!");
  }

  delay(1500);

  Serial.println();
  Serial.println("======================================");
  Serial.println("SYSTEM READY");
  Serial.println("Relay changes every 7 seconds");
  Serial.println("NC = charging path");
  Serial.println("======================================");
}

// =====================================================
// LOOP
// =====================================================

void loop() {

  // ===================================================
  // INA219 READINGS
  // ===================================================

  float voltage = ina219.getBusVoltage_V();
  float current = ina219.getCurrent_mA();
  float power   = ina219.getPower_mW();

  // ===================================================
  // SERIAL MONITOR
  // ===================================================

  Serial.println("--------------------------------------");

  Serial.print("Voltage : ");
  Serial.print(voltage, 2);
  Serial.println(" V");

  Serial.print("Current : ");
  Serial.print(current / 1000.0, 3);
  Serial.println(" A");

  Serial.print("Power   : ");
  Serial.print(power / 1000.0, 2);
  Serial.println(" W");

  // ===================================================
  // OLED
  // ===================================================

  display.clearDisplay();

  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);

  display.setCursor(0, 0);
  display.println("SMART CHARGE BOX");

  display.setCursor(0, 15);
  display.print("Voltage : ");
  display.print(voltage, 2);
  display.println(" V");

  display.setCursor(0, 28);
  display.print("Current : ");
  display.print(current / 1000.0, 2);
  display.println(" A");

  display.setCursor(0, 41);
  display.print("Power   : ");
  display.print(power / 1000.0, 2);
  display.println(" W");

  display.setCursor(0, 55);

  if (current > 50) {
    display.print("CHARGING");
  } else {
    display.print("STANDBY");
  }

  display.display();

  // ===================================================
  // RELAY + VOICE
  // ===================================================

  static unsigned long lastChange = 0;

  // false = relay coil OFF
  // true  = relay coil ON

  static bool relayState = false;

  if (millis() - lastChange >= 7000) {

    lastChange = millis();

    // Toggle relay coil state
    relayState = !relayState;

    // =================================================
    // CHARGING ON
    //
    // Relay coil OFF
    // NC CLOSED
    // =================================================

    if (!relayState) {

      digitalWrite(
        RELAY_PIN,
        HIGH
      );

      Serial.println();
      Serial.println("======================================");
      Serial.println("RELAY COIL : OFF");
      Serial.println("NC         : CLOSED");
      Serial.println("CHARGING   : ON");
      Serial.println("VOICE      : Charging started");
      Serial.println("======================================");

      playAudio(
        charging_started,
        charging_started_len
      );
    }

    // =================================================
    // CHARGING OFF
    //
    // Relay coil ON
    // NC OPEN
    // =================================================

    else {

      digitalWrite(
        RELAY_PIN,
        LOW
      );

      Serial.println();
      Serial.println("======================================");
      Serial.println("RELAY COIL : ON");
      Serial.println("NC         : OPEN");
      Serial.println("CHARGING   : OFF");
      Serial.println("VOICE      : Charging stopped");
      Serial.println("======================================");

      playAudio(
        charging_stopped,
        charging_stopped_len
      );
    }
  }

  delay(50);
}