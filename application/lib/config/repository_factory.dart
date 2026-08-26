import '../repositories/charge_link_repository.dart';
import '../services/esp32/esp32_service.dart';
import '../services/phone/phone_battery_service.dart';
import 'service_factory.dart';

class RepositoryFactory {
  const RepositoryFactory._();

  static ChargeLinkRepository create({
    Esp32Service? esp32Service,
    PhoneBatteryService? phoneBatteryService,
  }) {
    return ChargeLinkRepository(
      esp32Service:
      esp32Service ?? ServiceFactory.createEsp32Service(),
      phoneBatteryService:
      phoneBatteryService ??
          BatteryPlusPhoneBatteryService(),
    );
  }
}