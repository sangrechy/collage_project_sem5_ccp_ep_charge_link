import 'charging_sample.dart';
import 'device_status.dart';
import 'energy_data.dart';
import 'power_data.dart';
import 'temperature_data.dart';

class AppSnapshot {
  const AppSnapshot({
    required this.deviceStatus,
    required this.powerData,
    required this.charging,
    required this.chargingLimit,
    required this.energyData,
    required this.temperatureData,
    required this.chargingSample,
    this.phoneBatteryPercentage,
    this.phoneCharging,
    this.phoneBatteryTemperature,
    this.phoneBatteryHealth,
  });

  final DeviceStatus deviceStatus;
  final PowerData powerData;
  final bool charging;
  final int chargingLimit;
  final EnergyData energyData;
  final TemperatureData temperatureData;
  final ChargingSample chargingSample;

  final int? phoneBatteryPercentage;
  final bool? phoneCharging;
  final double? phoneBatteryTemperature;
  final double? phoneBatteryHealth;
}