import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/vehicle_profile.dart';
import '../services/gpsservice.dart';

class MapScreen extends StatefulWidget {
  final VehicleProfile? vehicleProfile;

  const MapScreen({super.key, this.vehicleProfile});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
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

  // Index de l'étape de navigation en cours (0 = depart, 1 = premier manœuvre)
  int _navStepIndex = 1;

  // Cap de déplacement (en degrés, nord = 0)
  double _bearing = 0.0;

  // Vrai si la carte suit automatiquement le GPS pendant la navigation
  bool _isFollowing = false;

  // Drapeau pour autoriser le recentrage automatique
  bool _shouldAutoFollow = false;

  // Dernière position utilisée pour recentrer (évite les micro-mouvements)
  LatLng? _lastFollowedPosition;
  double _speedKmh = 0.0;

  // Synthèse vocale
  final FlutterTts _tts = FlutterTts();
  bool _announced300 = false;
  bool _announced100 = false;

  // Prix du carburant en €/L (chargé depuis l'API nationale)
  double? _fuelPricePerLiter;

  // Hit testing polyline (tap sur le tracé de la carte)
  final LayerHitNotifier<int> _polylineHitNotifier = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
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
    _tts.stop();
    _searchController.dispose();
    _polylineHitNotifier.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final granted = await GpsService.checkAndRequestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permission de localisation refusée. L\'application ne peut pas fonctionner sans elle.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    GpsService.getPositionStream().listen((Position position) {
      if (!mounted) return;
      final pos = LatLng(position.latitude, position.longitude);
      final bearing = position.heading;
      final speedKmh = (position.speed * 3.6).clamp(0.0, 300.0);
      setState(() {
        _currentPosition = pos;
        _bearing = bearing;
        _speedKmh = speedKmh;
        _markers = [
          ..._markers.where((m) => m.key != const ValueKey('current')),
          Marker(
            key: const ValueKey('current'),
            point: pos,
            width: 60,
            height: 60,
            child: _routeValidated
                ? _buildArrowMarker(bearing)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      // Halo de précision (cercle externe semi-transparent)
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue.withOpacity(0.15),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.25),
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
      // Recentre : uniquement si le suivi automatique est activé pendant la navigation
      // Seuil de 10 m pour éviter les micro-mouvements GPS
      final double _movedDist = _lastFollowedPosition == null
          ? double.infinity
          : Geolocator.distanceBetween(
              _lastFollowedPosition!.latitude,
              _lastFollowedPosition!.longitude,
              pos.latitude,
              pos.longitude,
            );
      if (_shouldAutoFollow && _movedDist >= 10.0) {
        if (_routeValidated && _isFollowing) {
          _mapController.move(pos, 17.0);
          _lastFollowedPosition = pos;
        }
      }

      // Avancement automatique des étapes de navigation + annonces vocales
      if (_routeValidated && _routeAlternatives.isNotEmpty) {
        final steps = _routeAlternatives[_selectedRouteIndex].steps;

        // ── NOUVEAU : recalage sur l'étape la plus proche ──────────────
        // Cherche parmi les étapes restantes celle dont le point
        // est le plus proche de la position actuelle
        if (steps.length > 2) {
          int bestIdx = _navStepIndex;
          double bestDist = double.infinity;

          // On cherche dans une fenêtre : étape actuelle ± 5
          final searchFrom = (_navStepIndex - 1).clamp(1, steps.length - 1);
          final searchTo = (_navStepIndex + 5).clamp(1, steps.length - 1);

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

          // Si on a trouvé une étape plus pertinente (et qu'on ne recule pas
          // de plus d'une étape pour éviter les faux positifs)
          if (bestIdx != _navStepIndex && bestIdx >= _navStepIndex - 1) {
            setState(() {
              _navStepIndex = bestIdx;
              _announced300 = false;
              _announced100 = false;
            });
            _speak(_stepInstructionShort(steps[bestIdx]));
          }
        }
        // ── FIN recalage ───────────────────────────────────────────────

        if (_navStepIndex < steps.length - 1) {
          final target = steps[_navStepIndex].location;
          final dist = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            target.latitude,
            target.longitude,
          );

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
            setState(() {
              _navStepIndex = nextIdx;
              _announced300 = false;
              _announced100 = false;
            });
            if (nextIdx < steps.length) {
              _speak(_stepInstructionShort(steps[nextIdx]));
            }
          }
        }
      }
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

  void _clearRoute() {
    _tts.stop();
    setState(() {
      _routeAlternatives = [];
      _selectedRouteIndex = 0;
      _routeValidated = false;
      _isFollowing = false;
      _shouldAutoFollow = false;
      _navStepIndex = 1;
      _announced300 = false;
      _announced100 = false;
      // Recréer le marqueur GPS normal
      _markers = [
        ..._markers.where((m) => m.key != const ValueKey('search')),
        Marker(
          key: const ValueKey('current'),
          point: _currentPosition,
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Halo de précision (cercle externe semi-transparent)
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(0.15),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.25),
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
    _mapController.move(_currentPosition, 15.0);
  }

  void _validateRoute() {
    final steps = _routeAlternatives[_selectedRouteIndex].steps;
    setState(() {
      _routeValidated = true;
      _isFollowing = true;
      _shouldAutoFollow = true;
      _navStepIndex = steps.length > 1 ? 1 : 0;
      _announced300 = false;
      _announced100 = false;
      // Rebuild le marqueur en flèche immédiatement
      _markers = [
        ..._markers.where((m) => m.key != const ValueKey('current')),
        Marker(
          key: const ValueKey('current'),
          point: _currentPosition,
          width: 60,
          height: 60,
          child: _buildArrowMarker(_bearing),
        ),
      ];
    });
    _mapController.move(_currentPosition, 17.0);
    // Annonce vocale de la première instruction
    final startIdx = steps.length > 1 ? 1 : 0;
    if (steps.isNotEmpty) {
      _speak(_stepInstructionShort(steps[startIdx]));
    }
  }

  void _focusOnLocation() {
    setState(() {
      _isFollowing = true;
      _shouldAutoFollow = true;
    });
    _mapController.move(_currentPosition, _routeValidated ? 17.0 : 15.0);
    _lastFollowedPosition = _currentPosition;
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

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
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
    final bottomPadding = _routeValidated
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
                if (hasGesture && _routeValidated && _isFollowing) {
                  setState(() {
                    _isFollowing = false;
                    _shouldAutoFollow = false;
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
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.93),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
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
                                    _search(value);
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
                            color: Colors.black.withOpacity(0.1),
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
                                  ).withOpacity(0.1),
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
                        color: Colors.black.withOpacity(0.15),
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

          // Bouton recentrer pendant la navigation
          if (_routeValidated && _routeAlternatives.isNotEmpty && !_isFollowing)
            Positioned(
              bottom: 110,
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
                        color: Colors.black.withOpacity(0.15),
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
              bottom: 0,
              left: 0,
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
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildSelectionPanel(),
            )
          else if (hasRoutes && _routeValidated)
            Positioned(
              bottom: 0,
              left: 0,
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

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: speedColor, width: 3),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$speed',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: speedColor,
              height: 1.0,
            ),
          ),
          Text(
            'km/h',
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
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
              separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                _formatDuration(route.durationMin),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A73E8),
                ),
              ),
              Text(
                _formatDistance(route.distanceKm),
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
                color: const Color(0xFF1A73E8).withOpacity(0.1),
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
    final steps = _routeAlternatives[_selectedRouteIndex].steps;
    if (steps.isEmpty) {
      return Positioned(top: 0, child: const SizedBox.shrink());
    }
    final idx = _navStepIndex.clamp(0, steps.length - 1);
    final current = steps[idx];
    final hasNext = idx + 1 < steps.length;
    final next = hasNext ? steps[idx + 1] : null;

    final distM = Geolocator.distanceBetween(
      _currentPosition.latitude,
      _currentPosition.longitude,
      current.location.latitude,
      current.location.longitude,
    );

    final isArrived = current.maneuverType == 'arrive';
    final bannerColor = isArrived
        ? const Color(0xFF0F9D58)
        : const Color.fromARGB(255, 10, 10, 10);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
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
                      color: Colors.white.withOpacity(0.2),
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
                            _formatDistance(distM / 1000),
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

  String _ordinalFr(int n) => n == 1 ? '1ère' : '${n}ème';

  Widget _buildBottomSheet({required Widget child}) {
    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
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
          child,
        ],
      ),
    );
  }
}
