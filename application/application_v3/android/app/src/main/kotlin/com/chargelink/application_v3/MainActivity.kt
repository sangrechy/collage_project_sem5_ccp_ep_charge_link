package com.chargelink.application_v3

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.chargelink.application_v3/battery_telemetry"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryTelemetry" -> {
                    try {
                        val telemetry = getNativeBatteryTelemetry()
                        result.success(telemetry)
                    } catch (e: Exception) {
                        result.error("TELEMETRY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getNativeBatteryTelemetry(): Map<String, Any?> {
        val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus: Intent? = registerReceiver(null, ifilter)

        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager

        // Battery percentage
        val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percentage = if (level >= 0 && scale > 0) {
            (level * 100) / scale
        } else {
            bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        }

        // Diagnostic log: Print ALL extras in batteryStatus Intent
        batteryStatus?.extras?.keySet()?.forEach { key ->
            android.util.Log.d("BATTERY_EXTRAS", "KEY: $key -> ${batteryStatus.extras?.get(key)}")
        }

        // Charging state
        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = batteryStatus?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val isPlugged = plugged != 0
        val isCharging = isPlugged && (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL)

        // Real Battery Cell Voltage (millivolts -> volts)
        val voltageMv = batteryStatus?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
        val voltageV = if (voltageMv > 0) voltageMv / 1000.0 else 0.0

        // Real Battery Temperature (tenths of a degree Celsius -> Celsius)
        val tempRaw = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val temperatureC = if (tempRaw > 0) tempRaw / 10.0 else 25.0

        // Detect dual-cell battery architecture (OnePlus / Oppo / Realme 80W SuperVOOC etc.)
        val manufacturer = android.os.Build.MANUFACTURER.lowercase()
        val brand = android.os.Build.BRAND.lowercase()
        val isOplus = manufacturer.contains("oneplus") || manufacturer.contains("oppo") ||
                manufacturer.contains("realme") || brand.contains("oneplus") ||
                brand.contains("oppo") || brand.contains("realme")
        val chargeCounter = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER) ?: 0
        // Dual-cell if known dual-cell OEM or charge counter is ~2000-3000 mAh on a 4500-5400 mAh device
        val isDualCell = isOplus || (chargeCounter in 1800000..3200000)
        val cellMultiplier = if (isDualCell) 2.0 else 1.0

        // Read instantaneous current from Android BatteryManager
        var rawCurrent = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW) ?: 0
        if (rawCurrent == Int.MIN_VALUE || rawCurrent == Int.MAX_VALUE || rawCurrent == 0) {
            val avg = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE) ?: 0
            if (avg != Int.MIN_VALUE && avg != Int.MAX_VALUE && avg != 0) {
                rawCurrent = avg
            }
        }

        val absCurrentRaw = abs(rawCurrent.toLong())
        // Convert to milliamperes (mA):
        // If > 20,000, value is in microamperes (µA) -> divide by 1,000
        // If <= 20,000, value is already in milliamperes (mA)
        val currentMa = when {
            absCurrentRaw > 20000L -> absCurrentRaw / 1000.0
            absCurrentRaw > 0L -> absCurrentRaw.toDouble()
            else -> 0.0
        }

        // Total battery current (accounting for dual-cell splitting)
        val totalBatteryCurrentA = (currentMa * cellMultiplier) / 1000.0

        val currentA: Double
        val powerW: Double
        val dischargePowerW: Double

        if (!isPlugged || !isCharging) {
            // UNPLUGGED: The phone is NOT charging!
            // Charging intake current and power are STRICTLY ZERO.
            currentA = 0.0
            powerW = 0.0
            dischargePowerW = voltageV * totalBatteryCurrentA
        } else {
            // PLUGGED IN & CHARGING:
            // 1. Net chemical power entering the battery pack
            val pBattery = voltageV * totalBatteryCurrentA

            // 2. Active system consumption while screen is on and running app
            // (~1.35W for 120Hz AMOLED display, SoC, 5G modem, Bluetooth)
            val pSystem = 1.35
            val calculatedPowerW = pBattery + pSystem

            // Charging intake power
            powerW = if (calculatedPowerW > 0.1) calculatedPowerW else 0.5

            // Charging intake current at ~5V standard USB input
            currentA = if (powerW > 0.0) powerW / 5.0 else 0.0
            dischargePowerW = 0.0
        }

        return mapOf(
            "percentage" to percentage,
            "isCharging" to isCharging,
            "isPlugged" to isPlugged,
            "voltageV" to voltageV,
            "currentA" to currentA,
            "powerW" to powerW,
            "temperatureC" to temperatureC,
            "dischargePowerW" to dischargePowerW,
            "isDualCell" to isDualCell,
            "cellMultiplier" to cellMultiplier,
            "voltageMv" to voltageMv,
            "currentRaw" to rawCurrent,
            "tempRaw" to tempRaw
        )
    }
}
