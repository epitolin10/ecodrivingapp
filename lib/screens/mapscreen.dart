import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
  List<Polyline> _routes = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isCalculatingRoute = false;
  RouteResult? _routeResult;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final granted = await GpsService.checkAndRequestPermission();
    if (!granted) return;
    GpsService.getPositionStream().listen((Position position) {
      if (!mounted) return;
      final pos = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = pos;
        _markers = [
          ..._markers.where((m) => m.key != const ValueKey('current')),
          Marker(
            key: const ValueKey('current'),
            point: pos,
            width: 48,
            height: 48,
            child: const Icon(Icons.my_location, color: Colors.blue, size: 36),
          ),
        ];
      });
      // Recentre uniquement si pas de route active
      if (_routeResult == null) {
        _mapController.move(pos, 15.0);
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
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
      _routeResult = null;
      _routes = [];
    });

    final result = await GpsService.getRoute(_currentPosition, dest);
    if (!mounted) return;

    if (result == null) {
      setState(() => _isCalculatingRoute = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de calculer l\'itinéraire.')),
      );
      return;
    }

    setState(() {
      _routeResult = result;
      _isCalculatingRoute = false;
      _routes = [
        Polyline(
          points: result.points,
          color: Colors.blue,
          strokeWidth: 5.0,
        ),
      ];
    });

    // Ajuste la vue pour montrer tout le trajet
    final bounds = LatLngBounds.fromPoints(result.points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(40, 100, 40, 200),
      ),
    );
  }

  void _clearRoute() {
    setState(() {
      _routeResult = null;
      _routes = [];
      _markers = _markers.where((m) => m.key != const ValueKey('search')).toList();
    });
    _mapController.move(_currentPosition, 15.0);
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

  List<Widget> _buildFuelEstimate(double distanceKm) {
    final profile = widget.vehicleProfile!;
    final liters = profile.estimateFuelLiters(distanceKm);
    return [
      const SizedBox(height: 4),
      Row(
        children: [
          const Icon(Icons.local_gas_station, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            '~${liters.toStringAsFixed(1)} L  (${profile.fuelLabel})',
            style: const TextStyle(fontSize: 13, color: Colors.green),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = _routeResult != null || _isCalculatingRoute ? 160.0 : 24.0;

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
              onTap: (tp, ll) => setState(() => _searchResults = []),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.ecodrivingapp',
              ),
              PolylineLayer(polylines: _routes),
              MarkerLayer(markers: _markers),
            ],
          ),

          // Barre de recherche en haut
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher une destination...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchResults = []);
                                  },
                                )
                              : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onSubmitted: _search,
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final place = _searchResults[i];
                        return ListTile(
                          leading: const Icon(Icons.place),
                          title: Text(
                            place['display_name'] as String? ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectPlace(place),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Bouton recentrer
          Positioned(
            bottom: bottomPadding,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'recenter',
              mini: true,
              onPressed: () => _mapController.move(_currentPosition, 15.0),
              child: const Icon(Icons.my_location),
            ),
          ),

          // Panneau d'itinéraire en bas
          if (_isCalculatingRoute)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _routePanel(
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Calcul de l\'itinéraire...', style: TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            )
          else if (_routeResult != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _routePanel(
                child: Row(
                  children: [
                    const Icon(Icons.directions_car, color: Colors.blue, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDuration(_routeResult!.durationMin),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatDistance(_routeResult!.distanceKm),
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                          if (widget.vehicleProfile != null) ...
                            _buildFuelEstimate(_routeResult!.distanceKm),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _clearRoute,
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text('Annuler', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _routePanel({required Widget child}) {
    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: child,
    );
  }
}
