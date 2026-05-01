import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import '../models/trip_storage.dart';
import '../models/trip_data.dart';
import 'trip_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/vehicle_profile.dart';
import '../services/gpsservice.dart';

class MapScreen extends StatefulWidget {
  final VehicleProfile? vehicleProfile;

  const MapScreen({super.key, this.vehicleProfile});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng _currentPosition = const LatLng(48.8566, 2.3522);
  List<Marker> _markers = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isCalculatingRoute = false;

  // Alternatives d'itinéraires
  List<RouteResult> _routeAlternatives = [];
  int _selectedRouteIndex = 0;
  bool _routeValidated = false;
  LatLng? _destination;

  // Index de l'étape de navigation en cours (0 = depart, 1 = premier manœuvre)
  int _navStepIndex = 1;

  // Cap de déplacement (en degrés, nord = 0)
  double _bearing = 0.0;
  static const double _minReliableHeadingSpeedMs = 1.4; // ~5 km/h
  static const double _stationarySpeedMs = 0.8; // ~3 km/h
  static const double _minGpsMoveForHeadingM = 6.0;
  static const double _minTripDistanceDeltaM = 3.0;

  // Vrai si la carte suit automatiquement le GPS pendant la navigation
  bool _isFollowing = false;

  // Drapeau pour autoriser le recentrage automatique
  bool _shouldAutoFollow = false;

  // Drapeau pour autoriser la rotation automatique de la carte
  bool _shouldAutoRotate = false;

  // Ticker 60fps pour un suivi caméra fluide avec dead reckoning
  late final Ticker _cameraTicker;
  double _cameraFollowZoom = 17.0;
  Duration? _prevCameraTickElapsed;

  // Lissage EMA de la position affichée (anti micro-tremblements GPS)
  LatLng? _smoothedPos;
  double _speedKmh = 0.0;
  double _lastSpeedMs = 0.0;
  double _lastAltitude = 0.0;
  double _instantLph = 0.0;
  DateTime? _lastGpsTime;
  LatLng? _lastGpsPos;

  // Synthèse vocale
  final FlutterTts _tts = FlutterTts();
  bool _announced300 = false;
  bool _announced100 = false;

  // Prix du carburant en €/L (chargé depuis l'API nationale)
  double? _fuelPricePerLiter;
  final TripRecorder _tripRecorder = TripRecorder();
  double _tripDistanceKm = 0.0;

  // Hit testing polyline (tap sur le tracé de la carte)
  final LayerHitNotifier<int> _polylineHitNotifier = ValueNotifier(null);

  // Debounce timer pour les recherches
  Timer? _searchDebounceTimer;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _gpsRetryTimer;
  bool _isStartingLocationStream = false;

  // Distance affichée à l'étape actuelle (arrondie aux seuils)
  double _displayedStepDistance = 0.0;

  // Temps et distance restants (mis à jour en temps réel)
  int _remainingDurationMin = 0;
  double _remainingDistanceKm = 0.0;
  bool _isRerouting = false;
  DateTime? _offRouteSince;
  DateTime? _lastRerouteAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraTicker = createTicker(_onCameraFollowTick)..start();
    _setKeepScreenAwake(true);
    _initTts();
    _initLocation();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.52);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setKeepScreenAwake(false);
    _tts.stop();
    _cameraTicker.dispose();
    _positionSubscription?.cancel();
    _gpsRetryTimer?.cancel();
    _searchController.dispose();
    _polylineHitNotifier.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_routeValidated || !_isFollowing) return;
      _mapController.move(
        _predictedFollowTarget(_currentPosition, _bearing, _lastSpeedMs),
        17.0,
      );
      if (_shouldAutoRotate) {
        _rotateMapToBearing(_bearing);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _positionSubscription == null) {
      _initLocation();
    }
  }

  Future<void> _setKeepScreenAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // The app can still navigate if wakelock is unavailable on a platform.
    }
  }

  Future<void> _initLocation() async {
    final granted = await GpsService.checkAndRequestPermission();
    if (!granted) {
      _showLocationUnavailableMessage();
      return;
    }
    _gpsRetryTimer?.cancel();
    if (_isStartingLocationStream) return;
    _isStartingLocationStream = true;

    try {
      await _positionSubscription?.cancel();
      _positionSubscription = GpsService.getPositionStream().listen(
        _handlePosition,
        onError: _handleGpsError,
        cancelOnError: false,
      );
    } catch (_) {
      _handleGpsError('Impossible de demarrer le GPS');
    } finally {
      _isStartingLocationStream = false;
    }
  }

  void _showLocationUnavailableMessage() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Active la localisation et autorise son acces pour utiliser la carte.',
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Reglages',
          textColor: Colors.white,
          onPressed: () => Geolocator.openLocationSettings(),
        ),
      ),
    );
  }

  void _handleGpsError(Object error) {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _initLocation();
    });
  }

  // Ticker 60fps : dead reckoning + lissage exponentiel de la caméra
  void _onCameraFollowTick(Duration elapsed) {
    if (!_shouldAutoFollow || !_isFollowing) {
      _prevCameraTickElapsed = null;
      return;
    }

    final prev = _prevCameraTickElapsed;
    _prevCameraTickElapsed = elapsed;
    if (!mounted || prev == null) return;

    final dt = (elapsed - prev).inMicroseconds / 1000000.0;
    if (dt <= 0 || dt > 0.5) return;

    LatLng target;
    if (_routeValidated) {
      // Dead reckoning : extrapoler la position entre les mises à jour GPS
      LatLng estimated = _currentPosition;
      if (_lastGpsTime != null && _lastSpeedMs >= _stationarySpeedMs) {
        final secSinceGps =
            DateTime.now().difference(_lastGpsTime!).inMilliseconds / 1000.0;
        if (secSinceGps > 0.05 && secSinceGps < 2.0) {
          estimated = _projectPosition(
            _currentPosition,
            _bearing,
            (_lastSpeedMs * secSinceGps).clamp(0.0, 40.0),
          );
        }
      }
      target = _predictedFollowTarget(estimated, _bearing, _lastSpeedMs);
    } else {
      target = _currentPosition;
    }

    // Lissage exponentiel : tau = 0.2s → atteint 98% en 1 seconde
    final alpha = 1.0 - math.exp(-dt / 0.2);
    try {
      final current = _mapController.camera.center;
      final next = _lerpLatLng(current, target, alpha);
      _mapController.move(next, _cameraFollowZoom);
    } catch (_) {}
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  // Projette une position à `distanceM` mètres dans la direction `bearingDeg`
  LatLng _projectPosition(LatLng from, double bearingDeg, double distanceM) {
    if (distanceM < 0.1 || bearingDeg.isNaN || bearingDeg < 0) return from;
    const earthRadiusM = 6378137.0;
    final bearingRad = bearingDeg * math.pi / 180.0;
    final lat1 = from.latitude * math.pi / 180.0;
    final lon1 = from.longitude * math.pi / 180.0;
    final angularDistance = distanceM / earthRadiusM;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearingRad),
    );
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(
      lat2 * 180.0 / math.pi,
      ((lon2 * 180.0 / math.pi + 540.0) % 360.0) - 180.0,
    );
  }

  LatLng _predictedFollowTarget(LatLng pos, double bearingDeg, double speedMs) {
    if (speedMs < 1.4 || bearingDeg.isNaN || bearingDeg < 0) return pos;
    final lookAheadM = (speedMs * 2.2).clamp(18.0, 85.0);
    return _projectPosition(pos, bearingDeg, lookAheadM);
  }

  double _stableBearing(
    Position position,
    LatLng pos,
    double speedMs,
    double gpsDeltaM,
  ) {
    final rawHeading = position.heading;
    final hasReliableHeading = rawHeading.isFinite && rawHeading >= 0;

    if (speedMs >= _minReliableHeadingSpeedMs && hasReliableHeading) {
      return _smoothBearing(_bearing, rawHeading, 0.35);
    }

    if (_lastGpsPos != null && gpsDeltaM >= _minGpsMoveForHeadingM) {
      final gpsBearing = Geolocator.bearingBetween(
        _lastGpsPos!.latitude,
        _lastGpsPos!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (gpsBearing.isFinite) {
        return _smoothBearing(_bearing, gpsBearing, 0.25);
      }
    }

    return _bearing;
  }

  double _smoothBearing(double current, double target, double factor) {
    final delta = ((target - current + 540.0) % 360.0) - 180.0;
    return (current + delta * factor + 360.0) % 360.0;
  }

  double _visibleMarkerBearing(double bearingDeg) {
    return _shouldAutoRotate && _isFollowing ? 0.0 : bearingDeg;
  }

  void _rotateMapToBearing(double bearingDeg) {
    if (!bearingDeg.isFinite || bearingDeg < 0) return;

    try {
      final current = _mapController.camera.rotation;
      final delta = (((bearingDeg - current + 540.0) % 360.0) - 180.0).abs();
      if (delta >= 3.0) {
        _mapController.rotate(bearingDeg);
      }
    } catch (_) {
      _mapController.rotate(bearingDeg);
    }
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    final pos = LatLng(position.latitude, position.longitude);
    final rawSpeedMs = position.speed.clamp(0.0, 83.0);
    final now = DateTime.now();
    final altitude = position.altitude;
    final gpsDeltaM = _lastGpsPos == null
        ? double.infinity
        : Geolocator.distanceBetween(
            _lastGpsPos!.latitude,
            _lastGpsPos!.longitude,
            pos.latitude,
            pos.longitude,
          );
    final isStationaryJitter =
        _lastGpsPos != null &&
        rawSpeedMs < _stationarySpeedMs &&
        gpsDeltaM < _minGpsMoveForHeadingM;
    final speedMs = isStationaryJitter ? 0.0 : rawSpeedMs;
    final speedKmh = (speedMs * 3.6).clamp(0.0, 300.0);

    // Filtre EMA : lisse la position affichée pour éliminer les micro-tremblements
    // alpha bas = plus de lissage (vitesse faible), alpha élevé = suivi fidèle (vitesse élevée)
    if (!isStationaryJitter) {
      final emaAlpha = speedMs < 2.0 ? 0.25 : (speedMs < 6.0 ? 0.5 : 0.85);
      _smoothedPos = _smoothedPos == null
          ? pos
          : _lerpLatLng(_smoothedPos!, pos, emaAlpha);
    }
    final displayPos = isStationaryJitter ? _currentPosition : (_smoothedPos ?? pos);
    final bearing = _stableBearing(position, pos, speedMs, gpsDeltaM);

    double acceleration = 0.0;
    double altitudeDelta = 0.0;
    double distanceDelta = 1.0;

    if (_lastGpsTime != null) {
      final dt = now.difference(_lastGpsTime!).inMilliseconds / 1000.0;
      if (dt > 0.05) {
        acceleration = (speedMs - _lastSpeedMs) / dt;
        altitudeDelta = position.altitude - _lastAltitude;
        distanceDelta = speedMs * dt;
      }
    }

    if (widget.vehicleProfile != null) {
      _instantLph = widget.vehicleProfile!.estimateInstantConsumptionLph(
        speedMs: speedMs,
        accelerationMs2: acceleration,
        altitudeDeltaM: altitudeDelta,
        distanceDeltaM: distanceDelta,
      );
    }

    setState(() {
      _currentPosition = displayPos;
      _bearing = bearing;
      _speedKmh = speedKmh;

      if (_lastGpsTime != null) {
        final dt = now.difference(_lastGpsTime!).inMilliseconds / 1000.0;
        if (dt > 0.05) {
          // Évite la division par zéro
          acceleration = (speedMs - _lastSpeedMs) / dt;
          altitudeDelta = position.altitude - _lastAltitude;
          distanceDelta = speedMs * dt;
        }
      }

      double instantLph = 0.5;
      if (widget.vehicleProfile != null) {
        instantLph = widget.vehicleProfile!.estimateInstantConsumptionLph(
          speedMs: speedMs,
          accelerationMs2: acceleration,
          altitudeDeltaM: altitudeDelta,
          distanceDeltaM: distanceDelta,
        );
      }

      if (_routeValidated && _lastGpsPos != null) {
        if (gpsDeltaM >= _minTripDistanceDeltaM &&
            gpsDeltaM < 200 &&
            speedMs >= _stationarySpeedMs) {
          _tripDistanceKm += gpsDeltaM / 1000.0;
        }
      }

      if (_routeValidated) {
        _tripRecorder.addPoint(
          speedKmh: speedKmh,
          instantLph: instantLph,
          altitude: altitude,
          accelerationMs2: acceleration,
        );
      }
      _instantLph = instantLph;
      _lastSpeedMs = speedMs;
      _lastAltitude = altitude;
      _lastGpsTime = now;
      _lastGpsPos = pos;

      _markers = [
        ..._markers.where((m) => m.key != const ValueKey('current')),
        Marker(
          key: const ValueKey('current'),
          point: displayPos,
          width: 60,
          height: 60,
          rotate: true,
          child: _routeValidated
              ? _buildArrowMarker(_visibleMarkerBearing(bearing))
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    // Halo de précision (cercle externe semi-transparent)
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withValues(alpha: 0.15),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                    ),
                    // Anneau blanc avec ombre
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    // Point bleu central
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1A73E8),
                      ),
                    ),
                  ],
                ),
        ),
      ];
    });
    // La caméra est gérée par le ticker _onCameraFollowTick (dead reckoning 60fps)

    // Rotation automatique de la carte en fonction du cap GPS
    if (_shouldAutoRotate &&
        _isFollowing &&
        speedMs >= _minReliableHeadingSpeedMs) {
      _rotateMapToBearing(bearing);
    }

    // Avancement automatique des étapes de navigation + annonces vocales
    _checkOffRouteAndMaybeReroute(pos, position.accuracy, speedMs);
    if (_isRerouting) {
      _calculateRemaining(pos);
      return;
    }

    if (_routeValidated && _routeAlternatives.isNotEmpty) {
      final steps = _routeAlternatives[_selectedRouteIndex].steps;

      // ── RECALAGE AVEC HYSTÉRÉSIS : évite de changer d'étape à cause des imprécisions GPS ──
      // Ne change d'étape que si on est au moins 50m plus proche
      if (steps.length > 2 && _navStepIndex < steps.length) {
        // Distance à l'étape actuelle
        final currentStepDist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          steps[_navStepIndex].location.latitude,
          steps[_navStepIndex].location.longitude,
        );

        int bestIdx = _navStepIndex;
        double bestDist = currentStepDist;

        // On cherche dans une fenêtre : étape actuelle à +5
        // (on ne cherche pas en arrière pour éviter de reculer)
        final searchFrom = _navStepIndex;
        final searchTo = (_navStepIndex + 5).clamp(
          _navStepIndex,
          steps.length - 1,
        );

        for (int i = searchFrom; i <= searchTo; i++) {
          final d = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            steps[i].location.latitude,
            steps[i].location.longitude,
          );
          if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
          }
        }

        // Ne change d'étape que si on est au moins 50m plus proche
        // (hystérésis : évite les oscillations GPS sur lignes droites)
        if (bestIdx > _navStepIndex && (currentStepDist - bestDist) > 50.0) {
          setState(() {
            _navStepIndex = bestIdx;
            _announced300 = false;
            _announced100 = false;
          });
          _speak(_stepInstructionShort(steps[bestIdx]));
        }
      }
      // ── FIN RECALAGE ───────────────────────────────────────────────

      if (_navStepIndex < steps.length - 1) {
        final target = steps[_navStepIndex].location;
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          target.latitude,
          target.longitude,
        );

        // Arrondir la distance pour l'affichage et mettre à jour si elle a changé
        final roundedDist = _roundDisplayDistance(dist);
        if (roundedDist != _displayedStepDistance) {
          setState(() {
            _displayedStepDistance = roundedDist;
          });
        }

        // Annonce à 300 m
        if (dist <= 300 && !_announced300) {
          _announced300 = true;
          _speak(
            'Dans ${_formatDistance(dist / 1000)}, '
            '${_stepInstructionShort(steps[_navStepIndex])}',
          );
        }
        // Annonce à 100 m
        if (dist <= 100 && !_announced100) {
          _announced100 = true;
          _speak('Bientôt, ${_stepInstructionShort(steps[_navStepIndex])}');
        }
        // Passage à l'étape suivante (seuil abaissé à 20 m pour plus de réactivité)
        if (dist < 20 && mounted) {
          final nextIdx = _navStepIndex + 1;
          if (nextIdx >= steps.length) {
            _speak('Vous êtes arrivé à destination.');
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) _clearRoute(arrived: true);
            });
          } else {
            setState(() {
              _navStepIndex = nextIdx;
              _announced300 = false;
              _announced100 = false;
            });
            if (steps[nextIdx].maneuverType == 'arrive') {
              _speak('Vous êtes arrivé à destination.');
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _clearRoute(arrived: true);
              });
            } else {
              _speak(_stepInstructionShort(steps[nextIdx]));
            }
          }
        }
      }
    }

    // Mettre à jour le temps et la distance restants en continu
    _calculateRemaining(pos);
  }

  void _checkOffRouteAndMaybeReroute(
    LatLng pos,
    double accuracyM,
    double speedMs,
  ) {
    if (!_routeValidated ||
        _routeAlternatives.isEmpty ||
        _destination == null) {
      _offRouteSince = null;
      return;
    }
    if (_isRerouting) return;
    if (speedMs < _minReliableHeadingSpeedMs) {
      _offRouteSince = null;
      return;
    }

    final distanceToDestination = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );
    if (distanceToDestination < 60) {
      _offRouteSince = null;
      return;
    }

    final route = _routeAlternatives[_selectedRouteIndex];
    final distanceToRouteM = _distanceToPolylineM(pos, route.points);
    final thresholdM = math.max(45.0, accuracyM * 2.2);
    if (distanceToRouteM <= thresholdM) {
      _offRouteSince = null;
      return;
    }

    final now = DateTime.now();
    _offRouteSince ??= now;
    final offRouteDuration = now.difference(_offRouteSince!);
    final isCooldownDone =
        _lastRerouteAt == null ||
        now.difference(_lastRerouteAt!) > const Duration(seconds: 18);

    if (offRouteDuration >= const Duration(seconds: 5) && isCooldownDone) {
      _recalculateRouteFromCurrentPosition(pos);
    }
  }

  Future<void> _recalculateRouteFromCurrentPosition(LatLng start) async {
    final destination = _destination;
    if (destination == null || _isRerouting) return;

    _isRerouting = true;
    _lastRerouteAt = DateTime.now();
    _offRouteSince = null;
    if (mounted) {
      setState(() => _isCalculatingRoute = true);
    }

    final alternatives = await GpsService.getRoutes(start, destination);
    if (!mounted) return;
    if (!_routeValidated || _destination != destination) {
      _isRerouting = false;
      return;
    }

    if (alternatives.isEmpty) {
      setState(() {
        _isRerouting = false;
        _isCalculatingRoute = false;
      });
      return;
    }

    final route = alternatives.first;
    final steps = route.steps;
    final startIdx = steps.length > 1 ? 1 : 0;
    final initialStepDistance = steps.isEmpty
        ? 0.0
        : Geolocator.distanceBetween(
            start.latitude,
            start.longitude,
            steps[startIdx].location.latitude,
            steps[startIdx].location.longitude,
          );

    setState(() {
      _routeAlternatives = alternatives;
      _selectedRouteIndex = 0;
      _routeValidated = true;
      _isRerouting = false;
      _isCalculatingRoute = false;
      _navStepIndex = startIdx;
      _announced300 = false;
      _announced100 = false;
      _displayedStepDistance = _roundDisplayDistance(initialStepDistance);
      _remainingDurationMin = route.durationMin;
      _remainingDistanceKm = route.distanceKm;
    });

    if (_isFollowing) {
      _cameraFollowZoom = 17.0;
      _prevCameraTickElapsed = null;
    }

    if (steps.isNotEmpty) {
      _speak('Itineraire recalcule. ${_stepInstructionShort(steps[startIdx])}');
    } else {
      _speak('Itineraire recalcule.');
    }
  }

  double _distanceToPolylineM(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        polyline.first.latitude,
        polyline.first.longitude,
      );
    }

    var minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final distance = _distanceToSegmentM(point, polyline[i], polyline[i + 1]);
      if (distance < minDistance) minDistance = distance;
    }
    return minDistance;
  }

  double _distanceToSegmentM(LatLng point, LatLng a, LatLng b) {
    const metersPerDegreeLat = 111320.0;
    final latRad = point.latitude * math.pi / 180.0;
    final metersPerDegreeLon = metersPerDegreeLat * math.cos(latRad);

    final px = point.longitude * metersPerDegreeLon;
    final py = point.latitude * metersPerDegreeLat;
    final ax = a.longitude * metersPerDegreeLon;
    final ay = a.latitude * metersPerDegreeLat;
    final bx = b.longitude * metersPerDegreeLon;
    final by = b.latitude * metersPerDegreeLat;

    final dx = bx - ax;
    final dy = by - ay;
    if (dx == 0 && dy == 0) {
      return math.sqrt(math.pow(px - ax, 2) + math.pow(py - ay, 2));
    }

    final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(
      0.0,
      1.0,
    );
    final closestX = ax + t * dx;
    final closestY = ay + t * dy;
    return math.sqrt(math.pow(px - closestX, 2) + math.pow(py - closestY, 2));
  }

  /// Lance une recherche avec debounce (attend 600ms après la fin de la frappe).
  /// Cela évite de faire trop de requêtes à l'API Nominatim.
  void _debouncedSearch(String query) {
    _searchDebounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    // Attendre 600ms avant de lancer la requête
    _searchDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await GpsService.searchPlace(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de recherche: ${e.toString()}'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    final lat = double.parse(place['lat'] as String);
    final lon = double.parse(place['lon'] as String);
    final dest = LatLng(lat, lon);

    setState(() {
      _searchResults = [];
      _searchController.clear();
      _markers = [
        ..._markers.where((m) => m.key != const ValueKey('search')),
        Marker(
          key: const ValueKey('search'),
          point: dest,
          width: 48,
          height: 48,
          child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
        ),
      ];
    });

    await _computeRoute(dest);
  }

  Future<void> _computeRoute(LatLng dest) async {
    setState(() {
      _isCalculatingRoute = true;
      _routeAlternatives = [];
      _selectedRouteIndex = 0;
      _routeValidated = false;
      _destination = dest;
      _isRerouting = false;
      _offRouteSince = null;
      _lastRerouteAt = null;
      _displayedStepDistance = 0.0;
    });

    final alternatives = await GpsService.getRoutes(_currentPosition, dest);
    if (!mounted) return;

    if (alternatives.isEmpty) {
      setState(() => _isCalculatingRoute = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de calculer l\'itinéraire.')),
      );
      return;
    }

    setState(() {
      _routeAlternatives = alternatives;
      _selectedRouteIndex = 0;
      _isCalculatingRoute = false;
    });

    final bounds = LatLngBounds.fromPoints(_routeAlternatives[0].points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(40, 100, 40, 260),
      ),
    );
  }

  Future<void> _clearRoute({bool arrived = false}) async {
    _tts.stop();
    if (arrived && _tripRecorder.isRecording) {
      final route = _routeAlternatives[_selectedRouteIndex];
      final summary = _tripRecorder.finish(
        realDistanceKm: _tripDistanceKm,
        estimatedDurationMin: route.durationMin,
        estimatedDistanceKm: route.distanceKm,
        fuelPricePerLiter: _fuelPricePerLiter,
        fuelType: widget.vehicleProfile?.fuelType.name ?? 'essence',
      );

      if (summary != null && mounted) {
        await TripStorage.save(StoredTrip.fromSummary(summary));
        if (mounted) {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, animation, _) => TripSummaryScreen(
                summary: summary,
                onClose: () => Navigator.of(context).pop(),
              ),
              transitionsBuilder: (_, animation, _, child) =>
                  FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      } else {
        _tripRecorder.finish(
          realDistanceKm: _tripDistanceKm,
          estimatedDurationMin: 0,
          estimatedDistanceKm: 0,
        );
      }
    }
    _resetRouteState();
  }

  void _resetRouteState() {
    _prevCameraTickElapsed = null;
    setState(() {
      _routeAlternatives = [];
      _selectedRouteIndex = 0;
      _routeValidated = false;
      _destination = null;
      _isFollowing = false;
      _shouldAutoFollow = false;
      _shouldAutoRotate = false;
      _isRerouting = false;
      _offRouteSince = null;
      _lastRerouteAt = null;
      _navStepIndex = 1;
      _announced300 = false;
      _announced100 = false;
      _displayedStepDistance = 0.0;
      _remainingDurationMin = 0;
      _remainingDistanceKm = 0.0;
      _tripDistanceKm = 0.0;
      _lastGpsPos = null;
      _smoothedPos = null;
      _markers = [
        ..._markers.where(
          (m) =>
              m.key != const ValueKey('search') &&
              m.key != const ValueKey('current'),
        ),
        Marker(
          key: const ValueKey('current'),
          point: _currentPosition,
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.15),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1A73E8),
                ),
              ),
            ],
          ),
        ),
      ];
    });
    _mapController.move(_currentPosition, 15.0);
  }

  void _validateRoute() {
    final steps = _routeAlternatives[_selectedRouteIndex].steps;
    final startIdx = steps.length > 1 ? 1 : 0;
    final initialStepDistance = steps.isEmpty
        ? 0.0
        : Geolocator.distanceBetween(
            _currentPosition.latitude,
            _currentPosition.longitude,
            steps[startIdx].location.latitude,
            steps[startIdx].location.longitude,
          );

    _tripRecorder.start();
    _tripDistanceKm = 0.0;
    _lastGpsTime ??= DateTime.now();

    setState(() {
      _routeValidated = true;
      _isFollowing = true;
      _shouldAutoFollow = true;
      _shouldAutoRotate = true;
      _navStepIndex = startIdx;
      _announced300 = false;
      _announced100 = false;
      _displayedStepDistance = _roundDisplayDistance(initialStepDistance);
      // Initialiser le temps et la distance restants
      final route = _routeAlternatives[_selectedRouteIndex];
      _remainingDurationMin = route.durationMin;
      _remainingDistanceKm = route.distanceKm;
      // Rebuild le marqueur en flèche immédiatement
      _markers = [
        ..._markers.where((m) => m.key != const ValueKey('current')),
        Marker(
          key: const ValueKey('current'),
          point: _currentPosition,
          width: 60,
          height: 60,
          rotate: true,
          child: _buildArrowMarker(_visibleMarkerBearing(_bearing)),
        ),
      ];
    });
    _cameraFollowZoom = 17.0;
    _prevCameraTickElapsed = null;
    if (_lastSpeedMs >= _minReliableHeadingSpeedMs) {
      _rotateMapToBearing(_bearing);
    }
    // Annonce vocale de la première instruction
    if (steps.isNotEmpty) {
      _speak(_stepInstructionShort(steps[startIdx]));
    }
  }

  void _focusOnLocation() {
    setState(() {
      _isFollowing = true;
      _shouldAutoFollow = true;
      _shouldAutoRotate = _routeValidated;
    });
    _cameraFollowZoom = _routeValidated ? 17.0 : 15.0;
    _prevCameraTickElapsed = null;
    if (_routeValidated && _lastSpeedMs >= _minReliableHeadingSpeedMs) {
      _rotateMapToBearing(_bearing);
    }
  }

  Widget _buildArrowMarker(double bearingDeg) {
    final radians = bearingDeg * 3.141592653589793 / 180.0;
    return Transform.rotate(
      angle: radians,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A73E8),
          boxShadow: [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.navigation, color: Colors.white, size: 28),
      ),
    );
  }

  String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  /// Arrondit la distance pour l'affichage :
  /// - Si > 100m : arrondit à 50m (550m -> 550m, 540m -> 550m)
  /// - Si <= 100m : arrondit à 10m (95m -> 100m, 85m -> 90m)
  double _roundDisplayDistance(double distanceM) {
    if (distanceM > 100) {
      // Arrondir à 50m (50, 100, 150, 200, etc.)
      return ((distanceM + 25) ~/ 50) * 50.0;
    } else {
      // Arrondir à 10m (10, 20, 30, etc.)
      return ((distanceM + 5) ~/ 10) * 10.0;
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  /// Calcule le temps et la distance restants à partir de la position actuelle
  /// jusqu'à la destination finale.
  void _calculateRemaining(LatLng currentPos) {
    if (!_routeValidated || _routeAlternatives.isEmpty) {
      return;
    }

    final steps = _routeAlternatives[_selectedRouteIndex].steps;
    if (steps.isEmpty || _navStepIndex >= steps.length) {
      _remainingDurationMin = 0;
      _remainingDistanceKm = 0.0;
      return;
    }

    // Distance de la position actuelle à la fin de l'étape actuelle
    double remainingDistanceM = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      steps[_navStepIndex].location.latitude,
      steps[_navStepIndex].location.longitude,
    );

    // Durée restante pour l'étape actuelle (proportionnelle à la distance)
    double remainingDurationSec = 0;
    if (steps[_navStepIndex].distanceM > 0) {
      final ratio = remainingDistanceM / steps[_navStepIndex].distanceM;
      remainingDurationSec = steps[_navStepIndex].durationSec * ratio;
    }

    // Ajouter le temps et la distance des étapes suivantes
    for (int i = _navStepIndex + 1; i < steps.length; i++) {
      remainingDistanceM += steps[i].distanceM;
      remainingDurationSec += steps[i].durationSec;
    }

    setState(() {
      _remainingDistanceKm = remainingDistanceM / 1000.0;
      _remainingDurationMin = (remainingDurationSec / 60.0).round();
    });
  }

  List<Polyline<int>> get _buildPolylines {
    final result = <Polyline<int>>[];
    // Routes non sélectionnées en dessous (blanc/gris)
    for (int i = 0; i < _routeAlternatives.length; i++) {
      if (i == _selectedRouteIndex) continue;
      result.add(
        Polyline<int>(
          points: _routeAlternatives[i].points,
          color: Colors.grey.shade300,
          strokeWidth: 5.0,
          borderColor: Colors.grey.shade500,
          borderStrokeWidth: 1.5,
          hitValue: i,
        ),
      );
    }
    // Route sélectionnée par-dessus (bleu)
    if (_routeAlternatives.isNotEmpty) {
      result.add(
        Polyline<int>(
          points: _routeAlternatives[_selectedRouteIndex].points,
          color: const Color(0xFF1A73E8),
          strokeWidth: 6.0,
          borderColor: Colors.white,
          borderStrokeWidth: 2.0,
          hitValue: _selectedRouteIndex,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final hasRoutes = _routeAlternatives.isNotEmpty;
    final media = MediaQuery.of(context);
    final isLandscapeLayout =
        media.size.width > media.size.height && media.size.width >= 640;
    final bottomPadding = isLandscapeLayout
        ? 16.0
        : _routeValidated
        ? 90.0
        : (hasRoutes || _isCalculatingRoute ? 220.0 : 24.0);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 13.0,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isFollowing) {
                  setState(() {
                    _isFollowing = false;
                    _shouldAutoFollow = false;
                    _shouldAutoRotate = false;
                  });
                }
              },
              onTap: (tapPosition, latlng) {
                final hit = _polylineHitNotifier.value;
                if (hit != null && hit.hitValues.isNotEmpty) {
                  setState(() => _selectedRouteIndex = hit.hitValues.first);
                } else {
                  setState(() => _searchResults = []);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.ecodrivingapp',
              ),
              PolylineLayer<int>(
                polylines: _buildPolylines,
                hitNotifier: _polylineHitNotifier,
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          // Barre de recherche (masquée pendant la navigation)
          if (!_routeValidated)
            Positioned(
              top: media.padding.top + 8,
              left: 12,
              right: isLandscapeLayout ? null : 12,
              width: isLandscapeLayout ? 420 : null,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.93),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.menu_rounded),
                              color: Colors.grey.shade600,
                              onPressed: () {
                                Navigator.of(context).pushNamed(
                                  '/hub',
                                  arguments: widget.vehicleProfile,
                                );
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Rechercher une destination...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade500,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: Colors.grey.shade600,
                                  ),
                                  suffixIcon: _isSearching
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(
                                            Icons.clear_rounded,
                                            color: Colors.grey.shade600,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchResults = []);
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(28),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 0,
                                  ),
                                ),
                                onChanged: (value) {
                                  if (value.isEmpty) {
                                    setState(() => _searchResults = []);
                                  } else if (value.length > 2) {
                                    _debouncedSearch(value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          separatorBuilder: (ctx, i) =>
                              Divider(height: 1, color: Colors.grey.shade100),
                          itemBuilder: (context, i) {
                            final place = _searchResults[i];
                            return ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1A73E8,
                                  ).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.place_rounded,
                                  color: Color(0xFF1A73E8),
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                place['display_name'] as String? ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              onTap: () => _selectPlace(place),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Bouton recentrer (hors navigation uniquement)
          if (!_routeValidated)
            Positioned(
              bottom: bottomPadding + 8,
              right: 16,
              child: GestureDetector(
                onTap: _focusOnLocation,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: Color(0xFF1A73E8),
                    size: 22,
                  ),
                ),
              ),
            ),

          // Panneau bas : calcul / sélection / validé
          if (_isCalculatingRoute)
            Positioned(
              top: isLandscapeLayout ? media.padding.top + 96 : null,
              bottom: isLandscapeLayout ? null : 0,
              left: isLandscapeLayout ? null : 0,
              right: 0,
              child: _buildBottomSheet(
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Calcul de l\'itinéraire...',
                      style: TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else if (hasRoutes && !_routeValidated)
            Positioned(
              top: isLandscapeLayout ? media.padding.top + 96 : null,
              bottom: 0,
              left: isLandscapeLayout ? null : 0,
              right: 0,
              child: _buildSelectionPanel(),
            )
          else if (hasRoutes && _routeValidated)
            Positioned(
              bottom: 0,
              left: isLandscapeLayout ? null : 0,
              right: 0,
              child: _buildNavBottomBar(),
            ),
          if (_routeValidated && _routeAlternatives.isNotEmpty)
            _buildNavigationBanner(),
          Positioned(
            bottom: bottomPadding + 16,
            left: 16,
            child: _buildSpeedometer(),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedometer() {
    final speed = _speedKmh.round();
    final Color speedColor;
    if (speed < 50) {
      speedColor = const Color(0xFF1A73E8);
    } else if (speed < 90) {
      speedColor = const Color(0xFFF9A825);
    } else {
      speedColor = const Color(0xFFD32F2F);
    }

    final consumptionColor = _instantLph > 12 ? Colors.red : Colors.green[700]!;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Fond dégradé circulaire
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey.shade50],
            ),
            boxShadow: [
              BoxShadow(
                color: speedColor.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: speedColor.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Valeur de vitesse
              Text(
                '$speed',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: speedColor,
                  height: 1.0,
                  letterSpacing: -0.5,
                ),
              ),
              // Unité km/h
              Text(
                'km/h',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        // Badge de consommation (haut droit)
        if (widget.vehicleProfile != null)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: consumptionColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                  ),
                ],
                border: Border.all(color: Colors.transparent, width: 0),
              ),
              child: Text(
                '${_instantLph.toStringAsFixed(1)} L/h',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: consumptionColor,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Panneau de sélection ──────────────────────────────────────────────────

  Widget _buildSelectionPanel() {
    return _buildBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Choisir un itinéraire',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _clearRoute,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _routeAlternatives.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final route = _routeAlternatives[i];
                final isSelected = i == _selectedRouteIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRouteIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 140,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1A73E8)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF1A73E8)
                            : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.directions_car,
                              size: 14,
                              color: isSelected ? Colors.white70 : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              i == 0 ? 'Recommandé' : 'Alternatif $i',
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? Colors.white70
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(route.durationMin),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          _formatDistance(route.distanceKm),
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? Colors.white70
                                : Colors.grey[600],
                          ),
                        ),
                        if (widget.vehicleProfile != null) ...[
                          const SizedBox(height: 2),
                          Builder(
                            builder: (context) {
                              final liters = widget.vehicleProfile!
                                  .estimateFuelLiters(route.distanceKm);
                              final costStr = _fuelPricePerLiter != null
                                  ? ' · ${(liters * _fuelPricePerLiter!).toStringAsFixed(2)} €'
                                  : '';
                              return Text(
                                '~${liters.toStringAsFixed(1)} L$costStr',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.green[600],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _validateRoute,
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Démarrer la navigation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Barre de navigation compacte (bas) ───────────────────────────────────

  Widget _buildNavBottomBar() {
    final route = _routeAlternatives[_selectedRouteIndex];
    return _buildBottomSheet(
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDuration(_remainingDurationMin),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A73E8),
                ),
              ),
              Text(
                _formatDistance(_remainingDistanceKm),
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              if (widget.vehicleProfile != null)
                Row(
                  children: [
                    const Icon(
                      Icons.eco_rounded,
                      size: 13,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 3),
                    Builder(
                      builder: (context) {
                        final liters = widget.vehicleProfile!
                            .estimateFuelLiters(route.distanceKm);
                        final costStr = _fuelPricePerLiter != null
                            ? ' · ${(liters * _fuelPricePerLiter!).toStringAsFixed(2)} €'
                            : '';
                        return Text(
                          '~${liters.toStringAsFixed(1)} L$costStr',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
          const Spacer(),
          // Bouton recentrer (visible seulement si l'utilisateur a pané)
          if (!_isFollowing)
            Container(
              margin: const EdgeInsets.only(right: 8),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Recentrer',
                onPressed: _focusOnLocation,
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: Color(0xFF1A73E8),
                  size: 20,
                ),
              ),
            ),
          GestureDetector(
            onTap: _clearRoute,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.close_rounded,
                    color: Colors.red.shade700,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Arrêter',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bandeau de navigation en haut ─────────────────────────────────────────

  Positioned _buildNavigationBanner() {
    final media = MediaQuery.of(context);
    final isLandscapeLayout =
        media.size.width > media.size.height && media.size.width >= 640;
    final steps = _routeAlternatives[_selectedRouteIndex].steps;
    if (steps.isEmpty) {
      return Positioned(top: 0, child: const SizedBox.shrink());
    }
    final idx = _navStepIndex.clamp(0, steps.length - 1);
    final current = steps[idx];
    final hasNext = idx + 1 < steps.length;
    final next = hasNext ? steps[idx + 1] : null;

    final isArrived = current.maneuverType == 'arrive';
    final bannerColor = isArrived
        ? const Color(0xFF0F9D58)
        : const Color.fromARGB(255, 10, 10, 10);

    return Positioned(
      top: media.padding.top + 8,
      left: 12,
      right: isLandscapeLayout ? null : 12,
      width: isLandscapeLayout ? 430 : null,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(22),
        color: bannerColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _stepIcon(current),
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isArrived)
                          Text(
                            _formatDistance(_displayedStepDistance / 1000),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          _stepInstructionShort(current),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (current.streetName.isNotEmpty)
                          Text(
                            current.streetName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (next != null) ...[
                const Divider(color: Colors.white24, height: 16),
                Row(
                  children: [
                    Icon(_stepIcon(next), color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ensuite : ${_stepInstructionShort(next)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers icônes et textes de navigation ────────────────────────────────

  IconData _stepIcon(RouteStep step) {
    switch (step.maneuverType) {
      case 'depart':
        return Icons.navigation;
      case 'arrive':
        return Icons.flag;
      case 'turn':
        switch (step.modifier) {
          case 'left':
            return Icons.turn_left;
          case 'right':
            return Icons.turn_right;
          case 'slight left':
            return Icons.turn_slight_left;
          case 'slight right':
            return Icons.turn_slight_right;
          case 'sharp left':
            return Icons.turn_sharp_left;
          case 'sharp right':
            return Icons.turn_sharp_right;
          default:
            return Icons.straight;
        }
      case 'fork':
        return step.modifier == 'left' ? Icons.fork_left : Icons.fork_right;
      case 'rotary':
      case 'roundabout':
      case 'roundabout turn':
        return Icons.roundabout_left;
      case 'merge':
        return Icons.merge;
      case 'off ramp':
      case 'on ramp':
        return step.modifier == 'left'
            ? Icons.turn_slight_left
            : Icons.turn_slight_right;
      default:
        return Icons.straight;
    }
  }

  String _stepInstructionShort(RouteStep step) {
    final street = step.streetName.isNotEmpty ? ' sur ${step.streetName}' : '';
    switch (step.maneuverType) {
      case 'depart':
        return 'Partez$street';
      case 'arrive':
        return 'Vous êtes arrivé';
      case 'turn':
        switch (step.modifier) {
          case 'left':
            return 'Tournez à gauche$street';
          case 'right':
            return 'Tournez à droite$street';
          case 'slight left':
            return 'Gardez la gauche$street';
          case 'slight right':
            return 'Gardez la droite$street';
          case 'sharp left':
            return 'Virage serré à gauche$street';
          case 'sharp right':
            return 'Virage serré à droite$street';
          default:
            return 'Continuez tout droit$street';
        }
      case 'fork':
        return step.modifier == 'left'
            ? 'Bifurquez à gauche$street'
            : 'Bifurquez à droite$street';
      case 'rotary':
      case 'roundabout':
      case 'roundabout turn':
        final exit = step.exitNumber;
        if (exit != null) {
          return 'Prenez la ${_ordinalFr(exit)} sortie du rond-point$street';
        }
        return 'Prenez le rond-point$street';
      case 'merge':
        return 'Rejoignez la voie$street';
      case 'off ramp':
        return 'Prenez la bretelle$street';
      case 'on ramp':
        return 'Rejoignez la voie principale$street';
      default:
        return 'Continuez$street';
    }
  }

  String _ordinalFr(int n) => n == 1 ? '1ère' : '$nème';

  Widget _buildBottomSheet({required Widget child}) {
    final media = MediaQuery.of(context);
    final isLandscapeLayout =
        media.size.width > media.size.height && media.size.width >= 640;

    return Container(
      width: isLandscapeLayout ? 360 : null,
      constraints: isLandscapeLayout
          ? BoxConstraints(
              maxHeight: media.size.height - media.padding.top - 24,
            )
          : null,
      margin: isLandscapeLayout
          ? EdgeInsets.only(right: 12, bottom: media.padding.bottom + 12)
          : EdgeInsets.zero,
      padding: EdgeInsets.fromLTRB(
        isLandscapeLayout ? 16 : 20,
        0,
        isLandscapeLayout ? 16 : 20,
        isLandscapeLayout ? 16 : media.padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: isLandscapeLayout
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (isLandscapeLayout)
            Flexible(child: SingleChildScrollView(child: child))
          else
            child,
        ],
      ),
    );
  }
}
