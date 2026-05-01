/// Point de données enregistré à chaque tick GPS pendant la navigation.
class TripDataPoint {
  final DateTime timestamp;
  final double speedKmh;
  final double instantLph; // Consommation instantanée L/h
  final double altitude;
  final double accelerationMs2; // Accélération m/s²

  const TripDataPoint({
    required this.timestamp,
    required this.speedKmh,
    required this.instantLph,
    required this.altitude,
    required this.accelerationMs2,
  });
}

/// Résultat calculé d'un trajet terminé.
class TripSummary {
  // ── Métriques de base ───────────────────────────────────────────────────
  final Duration realDuration;
  final int estimatedDurationMin;
  final double realDistanceKm;
  final double estimatedDistanceKm;

  // ── Vitesse ─────────────────────────────────────────────────────────────
  final double avgSpeedKmh;
  final double maxSpeedKmh;

  // ── Consommation ────────────────────────────────────────────────────────
  final double totalFuelLiters;
  final double realConsumptionL100; // Conso réelle calculée
  final double? fuelCostEur; // null si prix non connu

  // ── Environnement ────────────────────────────────────────────────────────
  final double co2Grams; // CO₂ émis en grammes

  // ── Score éco-conduite ────────────────────────────────────────────────
  final int ecoScore; // 0–100
  final int hardAccelerationCount; // Accélérations > 2.5 m/s²
  final int hardBrakingCount; // Décélérations > -3 m/s²
  final int speedingCount; // Secondes > 130 km/h

  // ── Altitude ────────────────────────────────────────────────────────────
  final double altitudeGainM; // Dénivelé positif total

  // ── Série temporelle pour les graphes ────────────────────────────────────
  final List<TripDataPoint> dataPoints;

  const TripSummary({
    required this.realDuration,
    required this.estimatedDurationMin,
    required this.realDistanceKm,
    required this.estimatedDistanceKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.totalFuelLiters,
    required this.realConsumptionL100,
    this.fuelCostEur,
    required this.co2Grams,
    required this.ecoScore,
    required this.hardAccelerationCount,
    required this.hardBrakingCount,
    required this.speedingCount,
    required this.altitudeGainM,
    required this.dataPoints,
  });

  /// Couleur associée au score éco (utilisée dans l'UI).
  String get ecoScoreLabel {
    if (ecoScore >= 80) return 'Excellent';
    if (ecoScore >= 60) return 'Bien';
    if (ecoScore >= 40) return 'Moyen';
    return 'À améliorer';
  }

  /// Économies de CO₂ vs conduite agressive (+30 % de conso).
  double get co2SavedVsAggressive => co2Grams * 0.23;
}

/// Service d'enregistrement du trajet — collecte les points GPS et calcule
/// le [TripSummary] à la fin.
class TripRecorder {
  final List<TripDataPoint> _points = [];
  DateTime? _startTime;

  // Valeurs de la dernière position pour les deltas
  double _lastAltitude = 0.0;
  double _altitudeGain = 0.0;

  bool get isRecording => _startTime != null;

  void start() {
    _points.clear();
    _startTime = DateTime.now();
    _lastAltitude = 0.0;
    _altitudeGain = 0.0;
  }

  /// Ajoute un point GPS. Appelé à chaque tick du stream GPS.
  void addPoint({
    required double speedKmh,
    required double instantLph,
    required double altitude,
    required double accelerationMs2,
  }) {
    if (_startTime == null) return;

    // Cumul du dénivelé positif
    if (_points.isNotEmpty) {
      final delta = altitude - _lastAltitude;
      if (delta > 0) _altitudeGain += delta;
    }
    _lastAltitude = altitude;

    _points.add(
      TripDataPoint(
        timestamp: DateTime.now(),
        speedKmh: speedKmh,
        instantLph: instantLph,
        altitude: altitude,
        accelerationMs2: accelerationMs2,
      ),
    );
  }

  /// Calcule et retourne le résumé du trajet.
  /// [realDistanceKm] : distance GPS réelle parcourue.
  /// [estimatedDurationMin] / [estimatedDistanceKm] : valeurs OSRM initiales.
  /// [fuelPricePerLiter] : prix carburant pour estimer le coût.
  /// [fuelType] : 'diesel' ou 'essence' pour le CO₂.
  TripSummary? finish({
    required double realDistanceKm,
    required int estimatedDurationMin,
    required double estimatedDistanceKm,
    double? fuelPricePerLiter,
    String fuelType = 'essence',
  }) {
    if (_startTime == null || _points.isEmpty) return null;

    final duration = DateTime.now().difference(_startTime!);

    // ── Vitesse ────────────────────────────────────────────────────────────
    double sumSpeed = 0;
    double maxSpeed = 0;
    for (final p in _points) {
      sumSpeed += p.speedKmh;
      if (p.speedKmh > maxSpeed) maxSpeed = p.speedKmh;
    }
    final avgSpeed = sumSpeed / _points.length;

    // ── Consommation ────────────────────────────────────────────────────────
    // Intégration trapézoïdale : L/h × Δt(h) = L
    double totalLiters = 0;
    for (int i = 1; i < _points.length; i++) {
      final dt =
          _points[i].timestamp
              .difference(_points[i - 1].timestamp)
              .inMilliseconds /
          3600000.0; // ms → h
      totalLiters +=
          (_points[i].instantLph + _points[i - 1].instantLph) / 2 * dt;
    }

    final realL100 = realDistanceKm > 0
        ? (totalLiters / realDistanceKm) * 100
        : 0.0;

    // ── CO₂ ────────────────────────────────────────────────────────────────
    // Diesel : 2640 g/L, Essence : 2310 g/L
    final co2PerLiter = fuelType == 'diesel' ? 2640.0 : 2310.0;
    final co2Grams = totalLiters * co2PerLiter;

    // ── Score éco-conduite ──────────────────────────────────────────────────
    int hardAcc = 0;
    int hardBrk = 0;
    int speeding = 0;

    for (final p in _points) {
      if (p.accelerationMs2 > 2.5) hardAcc++;
      if (p.accelerationMs2 < -3.0) hardBrk++;
      if (p.speedKmh > 130) speeding++;
    }

    // Score : pénalités sur 100
    // Chaque événement retire des points, plafonnés
    final penaltyAcc = (hardAcc * 12).clamp(0, 40).toInt();
    final penaltyBrk = (hardBrk * 14).clamp(0, 45).toInt();
    final penaltySpeeding = (speeding * 2).clamp(0, 30).toInt();
    final penaltyConsumption = realL100 <= 8
        ? 0
        : realL100 <= 12
        ? 5
        : 12;

    final ecoScore =
        (100 - penaltyAcc - penaltyBrk - penaltySpeeding - penaltyConsumption)
            .clamp(0, 100)
            .toInt();

    _startTime = null;

    return TripSummary(
      realDuration: duration,
      estimatedDurationMin: estimatedDurationMin,
      realDistanceKm: realDistanceKm,
      estimatedDistanceKm: estimatedDistanceKm,
      avgSpeedKmh: avgSpeed,
      maxSpeedKmh: maxSpeed,
      totalFuelLiters: totalLiters,
      realConsumptionL100: realL100,
      fuelCostEur: fuelPricePerLiter != null
          ? totalLiters * fuelPricePerLiter
          : null,
      co2Grams: co2Grams,
      ecoScore: ecoScore,
      hardAccelerationCount: hardAcc,
      hardBrakingCount: hardBrk,
      speedingCount: speeding,
      altitudeGainM: _altitudeGain,
      dataPoints: List.unmodifiable(_points),
    );
  }
}
