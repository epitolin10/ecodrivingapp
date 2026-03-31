import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;

  RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
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
        distanceFilter: 10,
      ),
    );
  }

  /// Recherche un lieu via Nominatim (OpenStreetMap).
  static Future<List<Map<String, dynamic>>> searchPlace(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&limit=5',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'EcoDrivingApp/1.0 (contact@example.com)',
      });
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  /// Calcule un itinéraire routier via OSRM.
  /// Retourne null en cas d'erreur.
  static Future<RouteResult?> getRoute(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List);
      final points = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      final distanceKm = (route['distance'] as num) / 1000;
      final durationMin = ((route['duration'] as num) / 60).round();
      return RouteResult(
        points: points,
        distanceKm: distanceKm,
        durationMin: durationMin,
      );
    } catch (_) {
      return null;
    }
  }
}