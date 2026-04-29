import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'trip_data.dart';

/// Résumé allégé d'un trajet pour la persistance (on ne stocke pas les
/// milliers de points GPS, uniquement les métriques calculées).
class StoredTrip {
  final DateTime date;
  final Duration realDuration;
  final double realDistanceKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double totalFuelLiters;
  final double realConsumptionL100;
  final double? fuelCostEur;
  final double co2Grams;
  final int ecoScore;
  final int hardAccelerationCount;
  final int hardBrakingCount;
  final String ecoScoreLabel;
  // Série vitesse sous-échantillonnée (max 60 points) pour le mini-graphe
  final List<double> speedSamples;
  final List<double> consumptionSamples;

  const StoredTrip({
    required this.date,
    required this.realDuration,
    required this.realDistanceKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.totalFuelLiters,
    required this.realConsumptionL100,
    this.fuelCostEur,
    required this.co2Grams,
    required this.ecoScore,
    required this.hardAccelerationCount,
    required this.hardBrakingCount,
    required this.ecoScoreLabel,
    required this.speedSamples,
    required this.consumptionSamples,
  });

  /// Construit un StoredTrip depuis un TripSummary complet.
  factory StoredTrip.fromSummary(TripSummary s) {
    // Sous-échantillonnage à 60 points max pour le stockage
    List<double> _sample(List<double> values) {
      if (values.length <= 60) return values;
      final step = values.length / 60;
      return List.generate(60, (i) {
        final idx = (i * step).round().clamp(0, values.length - 1);
        return values[idx];
      });
    }

    final speeds = s.dataPoints.map((p) => p.speedKmh).toList();
    final consos = s.dataPoints.map((p) => p.instantLph).toList();

    return StoredTrip(
      date: DateTime.now(),
      realDuration: s.realDuration,
      realDistanceKm: s.realDistanceKm,
      avgSpeedKmh: s.avgSpeedKmh,
      maxSpeedKmh: s.maxSpeedKmh,
      totalFuelLiters: s.totalFuelLiters,
      realConsumptionL100: s.realConsumptionL100,
      fuelCostEur: s.fuelCostEur,
      co2Grams: s.co2Grams,
      ecoScore: s.ecoScore,
      hardAccelerationCount: s.hardAccelerationCount,
      hardBrakingCount: s.hardBrakingCount,
      ecoScoreLabel: s.ecoScoreLabel,
      speedSamples: _sample(speeds),
      consumptionSamples: _sample(consos),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'durationSec': realDuration.inSeconds,
    'distanceKm': realDistanceKm,
    'avgSpeedKmh': avgSpeedKmh,
    'maxSpeedKmh': maxSpeedKmh,
    'totalFuelLiters': totalFuelLiters,
    'realConsumptionL100': realConsumptionL100,
    'fuelCostEur': fuelCostEur,
    'co2Grams': co2Grams,
    'ecoScore': ecoScore,
    'hardAcc': hardAccelerationCount,
    'hardBrk': hardBrakingCount,
    'ecoScoreLabel': ecoScoreLabel,
    'speedSamples': speedSamples,
    'consumptionSamples': consumptionSamples,
  };

  factory StoredTrip.fromJson(Map<String, dynamic> j) => StoredTrip(
    date: DateTime.parse(j['date'] as String),
    realDuration: Duration(seconds: (j['durationSec'] as num).toInt()),
    realDistanceKm: (j['distanceKm'] as num).toDouble(),
    avgSpeedKmh: (j['avgSpeedKmh'] as num).toDouble(),
    maxSpeedKmh: (j['maxSpeedKmh'] as num).toDouble(),
    totalFuelLiters: (j['totalFuelLiters'] as num).toDouble(),
    realConsumptionL100: (j['realConsumptionL100'] as num).toDouble(),
    fuelCostEur: j['fuelCostEur'] != null
        ? (j['fuelCostEur'] as num).toDouble()
        : null,
    co2Grams: (j['co2Grams'] as num).toDouble(),
    ecoScore: (j['ecoScore'] as num).toInt(),
    hardAccelerationCount: (j['hardAcc'] as num).toInt(),
    hardBrakingCount: (j['hardBrk'] as num).toInt(),
    ecoScoreLabel: j['ecoScoreLabel'] as String,
    speedSamples: (j['speedSamples'] as List)
        .map((e) => (e as num).toDouble())
        .toList(),
    consumptionSamples: (j['consumptionSamples'] as List)
        .map((e) => (e as num).toDouble())
        .toList(),
  );

  String _fmtDuration() {
    final h = realDuration.inHours;
    final m = realDuration.inMinutes % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    return '${m}min';
  }

  String get durationLabel => _fmtDuration();

  String get distanceLabel => realDistanceKm >= 1
      ? '${realDistanceKm.toStringAsFixed(1)} km'
      : '${(realDistanceKm * 1000).round()} m';
}

/// Service de persistance — charge et sauvegarde la liste des trajets.
class TripStorage {
  static const _key = 'stored_trips_v1';
  static const _maxTrips = 200; // Limite pour éviter de saturer le stockage

  /// Charge tous les trajets triés du plus récent au plus ancien.
  static Future<List<StoredTrip>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final trips = raw
          .map((s) {
            try {
              return StoredTrip.fromJson(jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<StoredTrip>()
          .toList();
      // Tri décroissant par date
      trips.sort((a, b) => b.date.compareTo(a.date));
      return trips;
    } catch (_) {
      return [];
    }
  }

  /// Sauvegarde un nouveau trajet.
  static Future<void> save(StoredTrip trip) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.insert(0, jsonEncode(trip.toJson()));
    // On garde seulement les _maxTrips derniers
    final trimmed = raw.take(_maxTrips).toList();
    await prefs.setStringList(_key, trimmed);
  }

  /// Supprime tous les trajets.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Supprime un trajet spécifique par index.
  static Future<void> deleteAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    if (index >= 0 && index < raw.length) {
      raw.removeAt(index);
      await prefs.setStringList(_key, raw);
    }
  }

  /// Retourne les kilomètres par jour pour les N derniers jours.
  static Map<DateTime, double> kmPerDay(List<StoredTrip> trips, int days) {
    final result = <DateTime, double>{};
    final now = DateTime.now();
    for (int i = 0; i < days; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      result[day] = 0;
    }
    for (final t in trips) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      if (result.containsKey(day)) {
        result[day] = (result[day] ?? 0) + t.realDistanceKm;
      }
    }
    return result;
  }
}
