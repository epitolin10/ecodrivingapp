import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

class RouteStep {
  final String maneuverType;
  final String modifier;
  final String streetName;
  final double distanceM;
  final int durationSec;
  final LatLng location;
  final int? exitNumber;

  RouteStep({
    required this.maneuverType,
    required this.modifier,
    required this.streetName,
    required this.distanceM,
    required this.durationSec,
    required this.location,
    this.exitNumber,
  });
}

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
  final List<RouteStep> steps;

  RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    required this.steps,
  });
}

class GpsService {
  /// Vérifie et demande les permissions de localisation.
  /// Retourne true si la permission est accordée.
  static Future<bool> checkAndRequestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Retourne un stream de positions GPS en continu.
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        timeLimit: Duration(seconds: 1),
      ),
    );
  }

  /// Recherche un lieu via Nominatim (OpenStreetMap) avec retry automatique.
  static Future<List<Map<String, dynamic>>> searchPlace(String query) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(query)}&format=json&limit=5&countrycodes=fr',
        );

        final response = await http
            .get(
              url,
              headers: {
                'User-Agent': 'EcoDrivingApp/1.0 (Flutter; Android/iOS)',
                'Accept': 'application/json',
                'Accept-Language': 'fr-FR,fr;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as List<dynamic>;
          if (decoded.isEmpty) {
            throw Exception('Aucun résultat trouvé pour "$query"');
          }
          return decoded.cast<Map<String, dynamic>>();
        } else if (response.statusCode == 429) {
          // Rate limited, attendre avant de réessayer
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          attempt++;
          continue;
        } else {
          throw Exception('Erreur serveur: ${response.statusCode}');
        }
      } on SocketException catch (e) {
        throw Exception('Erreur réseau: ${e.message}');
      } on http.ClientException catch (e) {
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          attempt++;
          continue;
        }
        throw Exception('Erreur réseau: Impossible de se connecter au serveur');
      } on TimeoutException {
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          attempt++;
          continue;
        }
        throw Exception(
          'La requête a dépassé le délai d\'attente. Vérifiez votre connexion Internet.',
        );
      } catch (e) {
        throw Exception(
          'Erreur de recherche: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }

    throw Exception('Impossible de se connecter après plusieurs tentatives');
  }

  /// Calcule plusieurs itinéraires alternatifs via OSRM.
  /// Retourne une liste vide en cas d'erreur.
  static Future<List<RouteResult>> getRoutes(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&alternatives=3&steps=true',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = (data['routes'] as List).cast<Map<String, dynamic>>();
      return routes.map((route) {
        final coords = (route['geometry']['coordinates'] as List);
        final points = coords
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();
        final distanceKm = (route['distance'] as num) / 1000;
        final durationMin = ((route['duration'] as num) / 60).round();
        // Parse les étapes de navigation depuis tous les legs
        final rawSteps = <Map<String, dynamic>>[];
        for (final leg
            in (route['legs'] as List).cast<Map<String, dynamic>>()) {
          rawSteps.addAll((leg['steps'] as List).cast<Map<String, dynamic>>());
        }
        final steps = rawSteps.map((s) {
          final maneuver = s['maneuver'] as Map<String, dynamic>;
          final loc = maneuver['location'] as List;
          return RouteStep(
            maneuverType: maneuver['type'] as String? ?? 'continue',
            modifier: maneuver['modifier'] as String? ?? '',
            streetName: s['name'] as String? ?? '',
            distanceM: (s['distance'] as num).toDouble(),
            durationSec: ((s['duration'] as num).toDouble()).round(),
            location: LatLng(
              (loc[1] as num).toDouble(),
              (loc[0] as num).toDouble(),
            ),
            exitNumber: maneuver['exit'] as int?,
          );
        }).toList();
        return RouteResult(
          points: points,
          distanceKm: distanceKm,
          durationMin: durationMin,
          steps: steps,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
