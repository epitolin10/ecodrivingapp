import 'package:shared_preferences/shared_preferences.dart';

enum FuelType { diesel, essence }

class VehicleProfile {
  final FuelType fuelType;
  final double consumptionL100;

  const VehicleProfile({
    required this.fuelType,
    required this.consumptionL100,
  });

  static const _keyFuelType = 'vehicle_fuel_type';
  static const _keyConsumption = 'vehicle_consumption';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFuelType, fuelType.name);
    await prefs.setDouble(_keyConsumption, consumptionL100);
  }

  static Future<VehicleProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fuelTypeStr = prefs.getString(_keyFuelType);
    final consumption = prefs.getDouble(_keyConsumption);
    if (fuelTypeStr == null || consumption == null) return null;
    final fuelType = FuelType.values.firstWhere(
      (e) => e.name == fuelTypeStr,
      orElse: () => FuelType.essence,
    );
    return VehicleProfile(fuelType: fuelType, consumptionL100: consumption);
  }

  /// Estime la consommation de carburant pour un trajet donné en km.
  double estimateFuelLiters(double distanceKm) {
    return (distanceKm * consumptionL100) / 100.0;
  }

  String get fuelLabel => fuelType == FuelType.diesel ? 'Diesel' : 'Essence';
}
