import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/trip_storage.dart';

class StatsScreen extends StatefulWidget {
  final List<StoredTrip> trips;

  const StatsScreen({super.key, required this.trips});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  /// Retourne la liste des trajets pour un jour donné
  List<StoredTrip> _getTripsForDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return widget.trips
        .where((t) => t.date.isAfter(dayStart) && t.date.isBefore(dayEnd))
        .toList();
  }

  /// Retourne les km totals pour un jour
  double _getKmForDay(DateTime day) {
    return _getTripsForDay(day).fold(0.0, (sum, t) => sum + t.realDistanceKm);
  }

  /// Statistiques annuelles
  Map<String, dynamic> _getYearStats(int year) {
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year + 1, 1, 1);
    final yearTrips = widget.trips
        .where((t) => t.date.isAfter(yearStart) && t.date.isBefore(yearEnd))
        .toList();

    double totalKm = 0;
    double totalCo2 = 0;
    double totalCost = 0;
    double avgScore = 0;
    int totalTrips = yearTrips.length;

    for (final t in yearTrips) {
      totalKm += t.realDistanceKm;
      totalCo2 += t.co2Grams;
      if (t.fuelCostEur != null) totalCost += t.fuelCostEur!;
      avgScore += t.ecoScore;
    }

    if (totalTrips > 0) avgScore /= totalTrips;

    return {
      'totalKm': totalKm,
      'totalCo2': totalCo2,
      'totalCost': totalCost,
      'avgScore': avgScore.round(),
      'totalTrips': totalTrips,
      'avgKmPerTrip': totalTrips > 0 ? totalKm / totalTrips : 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yearStats = _getYearStats(now.year);
    final selectedDayTrips = _getTripsForDay(_selectedDay);
    final selectedDayKm = _getKmForDay(_selectedDay);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        title: const Text(
          'Statistiques détaillées',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // ─ Résumé annuel ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _buildYearSummary(yearStats),
            ),
          ),

          // ─ Calendrier ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCalendar(),
            ),
          ),

          // ─ Détails jour sélectionné ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildDayDetails(
                _selectedDay,
                selectedDayKm,
                selectedDayTrips,
                yearStats,
              ),
            ),
          ),

          // ─ Graphique mensuel ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: _buildMonthlyChart(),
            ),
          ),

          // ─ Liste des trajets du jour ─────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: _buildDayTripsList(_selectedDay, selectedDayTrips),
          ),
        ],
      ),
    );
  }

  // ── Résumé annuel ─────────────────────────────────────────────────

  Widget _buildYearSummary(Map<String, dynamic> stats) {
    final totalKm = (stats['totalKm'] as num).toDouble();
    final totalCo2 = (stats['totalCo2'] as num).toDouble();
    final avgKmPerTrip = (stats['avgKmPerTrip'] as num).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Année ${DateTime.now().year}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: [
              _StatTile(
                label: 'Total km',
                value: '${totalKm.toStringAsFixed(0)} km',
                icon: Icons.route_rounded,
                color: const Color(0xFF1A73E8),
              ),
              _StatTile(
                label: 'Trajets',
                value: '${stats['totalTrips']}',
                icon: Icons.directions_car_rounded,
                color: const Color(0xFF2E7D32),
              ),
              _StatTile(
                label: 'CO₂ annuel',
                value: totalCo2 >= 1000
                    ? '${(totalCo2 / 1000).toStringAsFixed(1)} kg'
                    : '${totalCo2.round()} g',
                icon: Icons.cloud_outlined,
                color: const Color(0xFF78909C),
              ),
              _StatTile(
                label: 'Moy. km/trajet',
                value: '${avgKmPerTrip.toStringAsFixed(1)} km',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFFFF6F00),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Calendrier ────────────────────────────────────────────────────

  Widget _buildCalendar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TableCalendar(
        firstDay: DateTime(2020),
        lastDay: DateTime(2100),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        onPageChanged: (focusedDay) {
          _focusedDay = focusedDay;
        },
        calendarStyle: CalendarStyle(
          cellMargin: const EdgeInsets.all(4),
          cellPadding: const EdgeInsets.all(6),
          defaultDecoration: BoxDecoration(
            color: const Color(0xFFF4F6F9),
            borderRadius: BorderRadius.circular(10),
          ),
          weekendDecoration: BoxDecoration(
            color: const Color(0xFFF4F6F9),
            borderRadius: BorderRadius.circular(10),
          ),
          selectedDecoration: BoxDecoration(
            color: const Color(0xFF2E7D32),
            borderRadius: BorderRadius.circular(10),
          ),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          todayDecoration: BoxDecoration(
            color: const Color(0xFF81C784),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2E7D32), width: 2),
          ),
          todayTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          defaultTextStyle: const TextStyle(fontSize: 13),
          weekendTextStyle: const TextStyle(fontSize: 13),
          outsideTextStyle: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade400,
          ),
          markerDecoration: BoxDecoration(
            color: const Color(0xFF1A73E8),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E7D32),
          ),
        ),
        eventLoader: (day) {
          final km = _getKmForDay(day);
          return km > 0 ? ['event'] : [];
        },
      ),
    );
  }

  // ── Détails du jour sélectionné ───────────────────────────────────

  Widget _buildDayDetails(
    DateTime day,
    double km,
    List<StoredTrip> trips,
    Map<String, dynamic> yearStats,
  ) {
    final isToday = isSameDay(day, DateTime.now());
    final dayName = isToday ? 'Aujourd\'hui' : _formatDate(day);

    final totalCo2 = trips.fold(0.0, (sum, t) => sum + t.co2Grams);
    final avgScore = trips.isEmpty
        ? 0
        : (trips.fold(0.0, (sum, t) => sum + t.ecoScore) / trips.length)
              .round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dayName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          if (trips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucun trajet ce jour.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: [
                _StatTile(
                  label: 'Distance',
                  value: '${km.toStringAsFixed(1)} km',
                  icon: Icons.route_rounded,
                  color: const Color(0xFF1A73E8),
                ),
                _StatTile(
                  label: 'Trajets',
                  value: '${trips.length}',
                  icon: Icons.directions_car_rounded,
                  color: const Color(0xFF2E7D32),
                ),
                _StatTile(
                  label: 'CO₂',
                  value: totalCo2 >= 1000
                      ? '${(totalCo2 / 1000).toStringAsFixed(2)} kg'
                      : '${totalCo2.round()} g',
                  icon: Icons.cloud_outlined,
                  color: const Color(0xFF78909C),
                ),
                _StatTile(
                  label: 'Score moyen',
                  value: '$avgScore',
                  icon: Icons.grade_rounded,
                  color: _scoreColor(avgScore),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Graphique mensuel ─────────────────────────────────────────────

  Widget _buildMonthlyChart() {
    final month = _focusedDay;
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = month.month == 12
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    // Calculer km par jour du mois
    final daysInMonth = monthEnd.difference(monthStart).inDays;
    final kmPerDay = <double>[];
    for (int i = 0; i < daysInMonth; i++) {
      final day = monthStart.add(Duration(days: i));
      kmPerDay.add(_getKmForDay(day));
    }

    final maxKm = kmPerDay.isEmpty
        ? 1.0
        : kmPerDay.reduce(math.max).clamp(1.0, double.infinity);
    final totalKm = kmPerDay.fold(0.0, (sum, v) => sum + v);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mois ${_formatMonthYear(month)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${totalKm.toStringAsFixed(0)} km',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(daysInMonth, (i) {
                final day = monthStart.add(Duration(days: i));
                final km = kmPerDay[i];
                final ratio = km / maxKm;
                final isToday = isSameDay(day, DateTime.now());

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (km > 0)
                          Text(
                            '${km.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 8,
                              color: isToday
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          height: math.max(2, ratio * 100),
                          decoration: BoxDecoration(
                            color: isToday
                                ? const Color(0xFF2E7D32)
                                : km > 0
                                ? const Color(0xFF81C784)
                                : Colors.grey.shade200,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 8,
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
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Liste des trajets du jour ─────────────────────────────────────

  Widget _buildDayTripsList(DateTime day, List<StoredTrip> trips) {
    if (trips.isEmpty) {
      return SliverToBoxAdapter(child: const SizedBox.shrink());
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Trajets du jour',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ...trips.map((trip) {
          final scoreColor = trip.ecoScore >= 80
              ? const Color(0xFF2E7D32)
              : trip.ecoScore >= 60
              ? const Color(0xFF689F38)
              : trip.ecoScore >= 40
              ? const Color(0xFFF9A825)
              : const Color(0xFFD32F2F);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scoreColor.withOpacity(0.1),
                      border: Border.all(
                        color: scoreColor.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${trip.ecoScore}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.distanceLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${trip.durationLabel} · ${trip.avgSpeedKmh.round()} km/h moy.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${trip.date.hour.toString().padLeft(2, '0')}h${trip.date.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${trip.realConsumptionL100.toStringAsFixed(1)} L/100',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ]),
    );
  }

  // ── Utilitaires ───────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF2E7D32);
    if (score >= 60) return const Color(0xFF689F38);
    if (score >= 40) return const Color(0xFFF9A825);
    return const Color(0xFFD32F2F);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets réutilisables
// ─────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
