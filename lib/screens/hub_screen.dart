import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/trip_storage.dart';
import '../models/vehicle_profile.dart';
import '../services/data_export_service.dart';
import '../services/fuel_price_service.dart';
import 'stats_screen.dart';

class HubScreen extends StatefulWidget {
  final VehicleProfile? vehicleProfile;

  const HubScreen({super.key, this.vehicleProfile});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  List<StoredTrip> _trips = [];
  bool _loading = true;
  FuelPrices? _fuelPrices;
  bool _loadingPrices = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _loadFuelPrices();
  }

  Future<void> _loadTrips() async {
    final trips = await TripStorage.loadAll();
    if (mounted) {
      setState(() {
        _trips = trips;
        _loading = false;
      });
    }
  }

  Future<void> _loadFuelPrices() async {
    final prices = await FuelPriceService.fetchLatest();
    if (mounted) {
      setState(() {
        _fuelPrices = prices;
        _loadingPrices = false;
      });
    }
  }

  // ── Métriques calculées depuis les vrais trajets ──────────────────────────

  double get _totalKmWeek {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return _trips
        .where((t) => t.date.isAfter(weekAgo))
        .fold(0.0, (s, t) => s + t.realDistanceKm);
  }

  double get _avgKmDay {
    final kmDay = TripStorage.kmPerDay(_trips, 7);
    final days = kmDay.values.where((v) => v > 0);
    if (days.isEmpty) return 0;
    return days.reduce((a, b) => a + b) / days.length;
  }

  double get _maxKmDay {
    final kmDay = TripStorage.kmPerDay(_trips, 7);
    if (kmDay.isEmpty) return 0;
    return kmDay.values.reduce(math.max);
  }

  double get _totalCo2Week {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return _trips
        .where((t) => t.date.isAfter(weekAgo))
        .fold(0.0, (s, t) => s + t.co2Grams);
  }

  double get _avgEcoScore {
    if (_trips.isEmpty) return 0;
    final recent = _trips.take(10).toList();
    return recent.fold(0.0, (s, t) => s + t.ecoScore) / recent.length;
  }

  // ── Données graphe 7 jours ────────────────────────────────────────────────

  List<_DayBar> get _weekBars {
    final kmDay = TripStorage.kmPerDay(_trips, 7);
    final sorted = kmDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return sorted.map((e) {
      final label = days[e.key.weekday - 1];
      return _DayBar(label: label, km: e.value, date: e.key);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildAppBar(),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildWeeklySummary(),
                      const SizedBox(height: 16),
                      _buildWeekChart(),
                      const SizedBox(height: 16),
                      _buildEcoScoreCard(),
                      const SizedBox(height: 16),
                      _buildFuelPricesCard(),
                      const SizedBox(height: 16),
                      _buildQuickActions(),
                      const SizedBox(height: 16),
                      _buildDataManagementCard(),
                      const SizedBox(height: 20),
                      _buildTripHistory(),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 130,
      pinned: true,
      backgroundColor: const Color(0xFF1B5E20),
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  const Text(
                    'Tableau de bord',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_trips.length} trajet${_trips.length > 1 ? 's' : ''} enregistré${_trips.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Résumé semaine (3 tuiles) ─────────────────────────────────────────────

  Widget _buildWeeklySummary() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: _SummaryTile(
              icon: Icons.route_rounded,
              label: 'Total semaine',
              value: '${_totalKmWeek.toStringAsFixed(0)} km',
              color: const Color(0xFF1A73E8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryTile(
              icon: Icons.today_rounded,
              label: 'Moyenne / jour',
              value: '${_avgKmDay.toStringAsFixed(1)} km',
              color: const Color(0xFF00897B),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryTile(
              icon: Icons.cloud_outlined,
              label: 'CO₂ semaine',
              value: _totalCo2Week >= 1000
                  ? '${(_totalCo2Week / 1000).toStringAsFixed(1)} kg'
                  : '${_totalCo2Week.round()} g',
              color: const Color(0xFF78909C),
            ),
          ),
        ],
      ),
    );
  }

  // ── Graphe 7 jours ────────────────────────────────────────────────────────

  Widget _buildWeekChart() {
    final bars = _weekBars;
    final maxKm = bars.isEmpty
        ? 1.0
        : bars.map((b) => b.km).reduce(math.max).clamp(1.0, double.infinity);
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Kilomètres — 7 derniers jours',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StatsScreen(trips: _trips)),
                ),
                child: const Text(
                  'Tout voir →',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (bars.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun trajet cette semaine.\nLancez votre première navigation !',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: bars.map((bar) {
                  final isToday = bar.date == todayDay;
                  final ratio = bar.km / maxKm;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (bar.km > 0)
                            Text(
                              '${bar.km.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 9,
                                color: isToday
                                    ? const Color(0xFF2E7D32)
                                    : Colors.grey.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 3),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            height: math.max(4, ratio * 100),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? const Color(0xFF2E7D32)
                                  : bar.km > 0
                                  ? const Color(0xFF81C784)
                                  : Colors.grey.shade200,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            bar.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isToday
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Score éco moyen ───────────────────────────────────────────────────────

  Widget _buildEcoScoreCard() {
    final score = _avgEcoScore.round();
    final color = score >= 80
        ? const Color(0xFF2E7D32)
        : score >= 60
        ? const Color(0xFF689F38)
        : score >= 40
        ? const Color(0xFFF9A825)
        : const Color(0xFFD32F2F);
    final label = score >= 80
        ? 'Excellent conducteur'
        : score >= 60
        ? 'Bonne conduite'
        : score >= 40
        ? 'Conduite à améliorer'
        : 'Conduite peu éco';

    return _Card(
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(
              painter: _MiniGaugePainter(
                progress: score / 100,
                color: color,
                score: score,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Score éco moyen',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _trips.isEmpty
                      ? 'Faites un trajet pour obtenir votre score'
                      : 'Basé sur vos ${math.min(10, _trips.length)} derniers trajets',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Prix carburants ───────────────────────────────────────────────────────

  Widget _buildFuelPricesCard() {
    final fuelType = widget.vehicleProfile?.fuelType;

    Widget priceChip({
      required String label,
      required double? price,
      required Color color,
      required bool highlighted,
    }) {
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: highlighted ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted ? color.withValues(alpha: 0.4) : Colors.grey.shade200,
              width: highlighted ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: highlighted ? color : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              _loadingPrices
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color.withValues(alpha: 0.5),
                      ),
                    )
                  : Text(
                      price != null
                          ? '${price.toStringAsFixed(3)} €'
                          : '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: highlighted ? color : Colors.grey.shade700,
                      ),
                    ),
            ],
          ),
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_gas_station_rounded,
                size: 16,
                color: Color(0xFFFF6F00),
              ),
              const SizedBox(width: 6),
              const Text(
                'Prix carburants — semaine en cours',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Moyenne nationale hebdomadaire',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              priceChip(
                label: 'Gazole',
                price: _fuelPrices?.gazole,
                color: const Color(0xFF1565C0),
                highlighted: fuelType == FuelType.diesel,
              ),
              const SizedBox(width: 8),
              priceChip(
                label: 'SP95',
                price: _fuelPrices?.sp95,
                color: const Color(0xFF2E7D32),
                highlighted: fuelType == FuelType.essence,
              ),
              const SizedBox(width: 8),
              priceChip(
                label: 'SP98',
                price: _fuelPrices?.sp98,
                color: const Color(0xFFE65100),
                highlighted: fuelType == FuelType.essence,
              ),
            ],
          ),
          if (!_loadingPrices && _fuelPrices == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Données indisponibles — vérifiez votre connexion',
                style: TextStyle(fontSize: 11, color: Colors.red.shade300),
              ),
            ),
        ],
      ),
    );
  }

  // ── Actions rapides ───────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.map_rounded,
            label: 'Navigation',
            subtitle: 'Retour à la carte',
            color: const Color(0xFF1A73E8),
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.bar_chart_rounded,
            label: 'Statistiques',
            subtitle: 'Calendrier & détails',
            color: const Color(0xFF2E7D32),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StatsScreen(trips: _trips)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Export / Import ──────────────────────────────────────────────────────

  Future<void> _exportData() async {
    try {
      await DataExportService.exportData(
        trips: _trips,
        vehicleProfile: widget.vehicleProfile,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erreur lors de l'export.")),
      );
    }
  }

  Future<void> _importData() async {
    final result = await DataExportService.importData();
    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier invalide ou import annulé.')),
      );
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importer les données'),
        content: Text(
          '${result.trips.length} trajet(s) trouvé(s).\n\n'
          'Voulez-vous remplacer vos données actuelles ou les fusionner ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('Fusionner'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'replace') {
      await TripStorage.clearAll();
    }

    for (final trip in result.trips) {
      await TripStorage.save(trip);
    }

    if (result.vehicleProfile != null) {
      await result.vehicleProfile!.save();
    }

    await _loadTrips();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.trips.length} trajet(s) importé(s) avec succès.',
        ),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }

  Widget _buildDataManagementCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sync_alt_rounded, size: 16, color: Color(0xFF455A64)),
              SizedBox(width: 6),
              Text(
                'Mes données',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sauvegardez ou restaurez votre historique de trajets',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _trips.isEmpty ? null : _exportData,
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: const Text('Exporter'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importData,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Importer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A73E8),
                    side: const BorderSide(color: Color(0xFF1A73E8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Historique des trajets ────────────────────────────────────────────────

  Widget _buildTripHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historique des trajets',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_trips.isEmpty)
          _Card(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.directions_car_outlined,
                      size: 40,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Aucun trajet enregistré',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Lancez une navigation pour commencer.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...(_trips.take(15).toList().asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TripCard(
                trip: entry.value,
                onDelete: () async {
                  await TripStorage.deleteAt(entry.key);
                  await _loadTrips();
                },
              ),
            );
          })),
        if (_trips.length > 15)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StatsScreen(trips: _trips)),
                ),
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text('Voir les ${_trips.length - 15} trajets suivants'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte d'un trajet individuel
// ─────────────────────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  final StoredTrip trip;
  final VoidCallback onDelete;

  const _TripCard({required this.trip, required this.onDelete});

  Color get _scoreColor {
    final s = trip.ecoScore;
    if (s >= 80) return const Color(0xFF2E7D32);
    if (s >= 60) return const Color(0xFF689F38);
    if (s >= 40) return const Color(0xFFF9A825);
    return const Color(0xFFD32F2F);
  }

  String _fmtDate() {
    final now = DateTime.now();
    final diff = now.difference(trip.date);
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} jours';
    return '${trip.date.day.toString().padLeft(2, '0')}/'
        '${trip.date.month.toString().padLeft(2, '0')}/'
        '${trip.date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(trip.date.toIso8601String()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer ce trajet ?'),
            content: const Text('Cette action est irréversible.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _TripDetailScreen(trip: trip)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Score badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _scoreColor.withOpacity(0.1),
                  border: Border.all(
                    color: _scoreColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${trip.ecoScore}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _scoreColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Infos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.distanceLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${trip.durationLabel} · ${trip.avgSpeedKmh.round()} km/h moy.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // Date + conso
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtDate(),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trip.realConsumptionL100.toStringAsFixed(1)} L/100',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Détail d'un trajet (graphe + toutes métriques)
// ─────────────────────────────────────────────────────────────────────────────

class _TripDetailScreen extends StatefulWidget {
  final StoredTrip trip;
  const _TripDetailScreen({required this.trip});

  @override
  State<_TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<_TripDetailScreen> {
  int _chartTab = 0;

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final scoreColor = t.ecoScore >= 80
        ? const Color(0xFF2E7D32)
        : t.ecoScore >= 60
        ? const Color(0xFF689F38)
        : t.ecoScore >= 40
        ? const Color(0xFFF9A825)
        : const Color(0xFFD32F2F);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.distanceLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${t.date.day.toString().padLeft(2, '0')}/'
              '${t.date.month.toString().padLeft(2, '0')}/'
              '${t.date.year} à '
              '${t.date.hour.toString().padLeft(2, '0')}h'
              '${t.date.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Score
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scoreColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CustomPaint(
                      painter: _MiniGaugePainter(
                        progress: t.ecoScore / 100,
                        color: scoreColor,
                        score: t.ecoScore,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Score éco-conduite',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      Text(
                        t.ecoScoreLabel,
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (t.hardAccelerationCount > 0 || t.hardBrakingCount > 0)
                        Text(
                          '${t.hardAccelerationCount} accél. · '
                          '${t.hardBrakingCount} freinages brusques',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Stats grille
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.2,
              children: [
                _DetailTile(
                  'Vitesse moy.',
                  '${t.avgSpeedKmh.round()} km/h',
                  Icons.speed_rounded,
                  const Color(0xFF1A73E8),
                ),
                _DetailTile(
                  'Vitesse max',
                  '${t.maxSpeedKmh.round()} km/h',
                  Icons.rocket_launch_rounded,
                  const Color(0xFFE91E63),
                ),
                _DetailTile(
                  'Consommation',
                  '${t.realConsumptionL100.toStringAsFixed(1)} L/100',
                  Icons.local_gas_station_rounded,
                  const Color(0xFFFF6F00),
                ),
                _DetailTile(
                  'Carburant',
                  '${t.totalFuelLiters.toStringAsFixed(2)} L',
                  Icons.water_drop_rounded,
                  const Color(0xFF00897B),
                ),
                _DetailTile(
                  'CO₂ émis',
                  t.co2Grams >= 1000
                      ? '${(t.co2Grams / 1000).toStringAsFixed(2)} kg'
                      : '${t.co2Grams.round()} g',
                  Icons.cloud_outlined,
                  const Color(0xFF78909C),
                ),
                if (t.fuelCostEur != null)
                  _DetailTile(
                    'Coût',
                    '${t.fuelCostEur!.toStringAsFixed(2)} €',
                    Icons.euro_rounded,
                    const Color(0xFFFFAB00),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Graphe
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _tabBtn(0, 'Vitesse'),
                      const SizedBox(width: 8),
                      _tabBtn(1, 'Conso.'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(height: 140, child: _buildMiniChart()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(int i, String label) {
    final sel = _chartTab == i;
    return GestureDetector(
      onTap: () => setState(() => _chartTab = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? Colors.white.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? Colors.white.withOpacity(0.2) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : Colors.white38,
            fontSize: 12,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChart() {
    final values = _chartTab == 0
        ? widget.trip.speedSamples
        : widget.trip.consumptionSamples;
    if (values.length < 2) {
      return Center(
        child: Text('Pas de données', style: TextStyle(color: Colors.white38)),
      );
    }
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final color = _chartTab == 0
        ? const Color(0xFF1A73E8)
        : const Color(0xFFFF6F00);

    return SizedBox.expand(
      child: CustomPaint(
        painter: _SimpleLinePainter(
          values: values,
          minVal: minV,
          maxVal: maxV,
          color: color,
        ),
      ),
    );
  }
}

Widget _DetailTile(String label, String value, IconData icon, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF1A2332),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets réutilisables
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainters
// ─────────────────────────────────────────────────────────────────────────────

class _MiniGaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final int score;
  final double fontSize;

  const _MiniGaugePainter({
    required this.progress,
    required this.color,
    required this.score,
    this.fontSize = 18,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const startAngle = -math.pi * 0.75;
    const sweepTotal = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = color.withOpacity(0.12)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * progress,
        false,
        Paint()
          ..color = color
          ..strokeWidth = 7
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    final tp = TextPainter(
      text: TextSpan(
        text: '$score',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_MiniGaugePainter old) =>
      old.progress != progress || old.score != score;
}

class _SimpleLinePainter extends CustomPainter {
  final List<double> values;
  final double minVal;
  final double maxVal;
  final Color color;

  const _SimpleLinePainter({
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final range = (maxVal - minVal).clamp(1.0, double.infinity);
    const padTop = 8.0;
    const padBottom = 8.0;
    final chartH = size.height - padTop - padBottom;

    final pts = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = padTop + chartH * (1 - (values[i] - minVal) / range);
      pts.add(Offset(x, y));
    }

    // Fill
    final fill = Path()..moveTo(pts.first.dx, size.height - padBottom);
    for (final p in pts) fill.lineTo(p.dx, p.dy);
    fill.lineTo(pts.last.dx, size.height - padBottom);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, padTop, size.width, chartH)),
    );

    // Line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final cp = (pts[i - 1].dx + pts[i].dx) / 2;
      line.cubicTo(cp, pts[i - 1].dy, cp, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SimpleLinePainter old) => old.values != values;
}

class _DayBar {
  final String label;
  final double km;
  final DateTime date;
  const _DayBar({required this.label, required this.km, required this.date});
}
