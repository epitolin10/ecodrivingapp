import 'package:shared_preferences/shared_preferences.dart';

enum FuelType { diesel, essence }

class VehicleProfile {
  final FuelType fuelType;
  final double consumptionL100; // Consommation constructeur (référence)
  final double massKg; // Masse à vide + conducteur (~75 kg)
  final double powerKw; // Puissance réelle moteur
  final double cx; // Coefficient aérodynamique
  final double frontalAreaM2; // Surface frontale

  const VehicleProfile({
    required this.fuelType,
    required this.consumptionL100,
    this.massKg = 1400, // Valeur par défaut raisonnable
    this.powerKw = 80,
    this.cx = 0.30,
    this.frontalAreaM2 = 2.2,
  });

  static const _keyFuelType = 'vehicle_fuel_type';
  static const _keyConsumption = 'vehicle_consumption';
  static const _keyMass = 'vehicle_mass';
  static const _keyPower = 'vehicle_power';
  static const _keyCx = 'vehicle_cx';
  static const _keyFrontalArea = 'vehicle_frontal_area';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFuelType, fuelType.name);
    await prefs.setDouble(_keyConsumption, consumptionL100);
    await prefs.setDouble(_keyMass, massKg);
    await prefs.setDouble(_keyPower, powerKw);
    await prefs.setDouble(_keyCx, cx);
    await prefs.setDouble(_keyFrontalArea, frontalAreaM2);
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
    return VehicleProfile(
      fuelType: fuelType,
      consumptionL100: consumption,
      massKg: prefs.getDouble(_keyMass) ?? 1400,
      powerKw: prefs.getDouble(_keyPower) ?? 80,
      cx: prefs.getDouble(_keyCx) ?? 0.30,
      frontalAreaM2: prefs.getDouble(_keyFrontalArea) ?? 2.2,
    );
  }

  double estimateFuelLiters(double distanceKm) {
    return (distanceKm * consumptionL100) / 100.0;
  }

  /// Calcule la consommation instantanée en L/h à partir des données GPS
  /// [speedMs]       : vitesse actuelle en m/s
  /// [accelerationMs2] : accélération en m/s² (peut être négative)
  /// [altitudeDeltaM]  : différence d'altitude sur le dernier intervalle (m)
  /// [distanceDeltaM]  : distance parcourue sur ce même intervalle (m)
  double estimateInstantConsumptionLph({
    required double speedMs,
    required double accelerationMs2,
    double altitudeDeltaM = 0,
    double distanceDeltaM = 1,
  }) {
    const double rhoAir = 1.225; // densité air kg/m³
    const double g = 9.81; // gravité m/s²
    const double Cr = 0.012; // coefficient roulement typique
    final double eta = fuelType == FuelType.diesel ? 0.42 : 0.35;
    final double pciKWhPerL = fuelType == FuelType.diesel ? 9.8 : 8.9;

    // Angle de pente (rad) depuis la variation d'altitude
    final double sinTheta = distanceDeltaM > 0
        ? (altitudeDeltaM / distanceDeltaM).clamp(-0.3, 0.3)
        : 0.0;

    // Puissances (W)
    final double pAero =
        0.5 * rhoAir * cx * frontalAreaM2 * speedMs * speedMs * speedMs;
    final double pRolling = massKg * g * Cr * speedMs;
    final double pGrade = massKg * g * sinTheta * speedMs;
    final double pInertia = massKg * accelerationMs2 * speedMs;

    // Puissance totale demandée, plafonnée à la puissance moteur
    final double pTotal = (pAero + pRolling + pGrade + pInertia).clamp(
      0.0,
      powerKw * 1000,
    );

    // Conversion en L/h
    // P (W) → P (kW) / (eta × PCI) × 1h
    final double lph = (pTotal / 1000.0) / (eta * pciKWhPerL);

    // Ralenti : consommation minimale même à l'arrêt (~0.5 L/h)
    return lph < 0.5 ? 0.5 : lph;
  }

  String get fuelLabel => fuelType == FuelType.diesel ? 'Diesel' : 'Essence';
}
