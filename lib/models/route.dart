import 'package:latlong2/latlong.dart';

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
