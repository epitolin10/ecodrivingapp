import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/trip_data.dart';

class TripSummaryScreen extends StatefulWidget {
  final TripSummary summary;
  final VoidCallback onClose;

  const TripSummaryScreen({
    super.key,
    required this.summary,
    required this.onClose,
  });

  @override
  State<TripSummaryScreen> createState() => _TripSummaryScreenState();
}

class _TripSummaryScreenState extends State<TripSummaryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _heroCtrl;
  late final AnimationController _cardsCtrl;
  late final AnimationController _scoreCtrl;
  late final Animation<double> _scoreAnim;

  // Graphe : onglet sélectionné (0 = vitesse, 1 = accélération, 2 = consommation)
  int _chartTab = 0;

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _cardsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scoreCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scoreAnim = CurvedAnimation(
      parent: _scoreCtrl,
      curve: Curves.easeOutCubic,
    );

    // Déclencher les animations en cascade
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _cardsCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _scoreCtrl.forward();
    });
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _cardsCtrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Color get _scoreColor {
    final s = widget.summary.ecoScore;
    if (s >= 80) return const Color(0xFF2E7D32);
    if (s >= 60) return const Color(0xFF689F38);
    if (s >= 40) return const Color(0xFFF9A825);
    return const Color(0xFFD32F2F);
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    if (m > 0) return '${m}min ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  String _fmtDist(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  String _fmtDurationDelta() {
    final real = widget.summary.realDuration.inMinutes;
    final est = widget.summary.estimatedDurationMin;
    final delta = real - est;
    if (delta == 0) return 'Comme prévu';
    if (delta > 0) return '+$delta min vs estimé';
    return '${delta} min vs estimé';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: Stack(
        children: [
          // Fond décoratif
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _scoreColor.withOpacity(0.08),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildScoreHero(),
                        const SizedBox(height: 20),
                        _buildQuickStats(),
                        const SizedBox(height: 20),
                        _buildChartSection(),
                        const SizedBox(height: 20),
                        _buildDrivingBehavior(),
                        const SizedBox(height: 20),
                        _buildEnvironmentCard(),
                        const SizedBox(height: 20),
                        _buildTimeDistanceCard(),
                        const SizedBox(height: 32),
                        _buildCloseButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Barre du haut ─────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: Color(0xFF4CAF50), size: 22),
          const SizedBox(width: 10),
          const Text(
            'Trajet terminé',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Text(
            _fmtDuration(widget.summary.realDuration),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero : score éco ──────────────────────────────────────────────────────

  Widget _buildScoreHero() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: _heroCtrl,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF1A2332), _scoreColor.withOpacity(0.15)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _scoreColor.withOpacity(0.3), width: 1.5),
          ),
          child: Row(
            children: [
              // Jauge circulaire
              SizedBox(
                width: 100,
                height: 100,
                child: AnimatedBuilder(
                  animation: _scoreAnim,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ScoreGaugePainter(
                        progress:
                            _scoreAnim.value * widget.summary.ecoScore / 100,
                        color: _scoreColor,
                        score: (widget.summary.ecoScore * _scoreAnim.value)
                            .round(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Score éco-conduite',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.summary.ecoScoreLabel,
                      style: TextStyle(
                        color: _scoreColor,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildScorePills(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScorePills() {
    final s = widget.summary;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (s.hardAccelerationCount == 0 && s.hardBrakingCount == 0)
          _pill('✓ Conduite douce', const Color(0xFF2E7D32)),
        if (s.hardAccelerationCount > 3)
          _pill(
            '${s.hardAccelerationCount} accél. brusques',
            const Color(0xFFE65100),
          ),
        if (s.hardBrakingCount > 3)
          _pill(
            '${s.hardBrakingCount} freinages brusques',
            const Color(0xFFB71C1C),
          ),
        if (s.speedingCount > 10)
          _pill('Vitesse excessive', const Color(0xFFB71C1C)),
        if (s.realConsumptionL100 < 8)
          _pill('Conso optimale', const Color(0xFF1B5E20)),
      ],
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withOpacity(0.9),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Stats rapides (4 tuiles) ──────────────────────────────────────────────

  Widget _buildQuickStats() {
    final s = widget.summary;
    return _AnimatedSection(
      controller: _cardsCtrl,
      delay: 0.0,
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.speed_rounded,
              label: 'Vitesse moy.',
              value: '${s.avgSpeedKmh.round()}',
              unit: 'km/h',
              color: const Color(0xFF1A73E8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.rocket_launch_rounded,
              label: 'Vitesse max',
              value: '${s.maxSpeedKmh.round()}',
              unit: 'km/h',
              color: const Color(0xFFE91E63),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.local_gas_station_rounded,
              label: 'Consommation',
              value: s.realConsumptionL100.toStringAsFixed(1),
              unit: 'L/100',
              color: const Color(0xFFFF6F00),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.water_drop_rounded,
              label: 'Total carbu.',
              value: s.totalFuelLiters.toStringAsFixed(2),
              unit: 'L',
              color: const Color(0xFF00897B),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section graphe ────────────────────────────────────────────────────────

  Widget _buildChartSection() {
    return _AnimatedSection(
      controller: _cardsCtrl,
      delay: 0.15,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Onglets
            Row(
              children: [
                _chartTabBtn(0, Icons.speed_rounded, 'Vitesse'),
                const SizedBox(width: 8),
                _chartTabBtn(1, Icons.trending_up_rounded, 'Accél.'),
                const SizedBox(width: 8),
                _chartTabBtn(2, Icons.local_gas_station_rounded, 'Conso.'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 160, child: _buildChart()),
            const SizedBox(height: 8),
            // Légende
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(
                  _chartTab == 0
                      ? const Color(0xFF1A73E8)
                      : _chartTab == 1
                      ? const Color(0xFFE91E63)
                      : const Color(0xFFFF6F00),
                ),
                const SizedBox(width: 6),
                Text(
                  _chartTab == 0
                      ? 'Vitesse (km/h) · pics colorés = accélérations'
                      : _chartTab == 1
                      ? 'Accélération (m/s²)'
                      : 'Consommation (L/h)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartTabBtn(int index, IconData icon, String label) {
    final isSelected = _chartTab == index;
    return GestureDetector(
      onTap: () => setState(() => _chartTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.2)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.4),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withOpacity(0.4),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildChart() {
    final points = widget.summary.dataPoints;
    if (points.isEmpty) {
      return Center(
        child: Text(
          'Pas assez de données',
          style: TextStyle(color: Colors.white.withOpacity(0.4)),
        ),
      );
    }

    // Sous-échantillonnage : on garde max 80 points pour la fluidité
    final sampled = _downsample(points, 80);
    final values = _chartTab == 0
        ? sampled.map((p) => p.speedKmh).toList()
        : _chartTab == 1
        ? sampled.map((p) => p.accelerationMs2).toList()
        : sampled.map((p) => p.instantLph).toList();

    final rawMax = values.reduce(math.max);
    final rawMin = values.reduce(math.min);
    final maxAbs = math
        .max(rawMax.abs(), rawMin.abs())
        .clamp(1.0, double.infinity);
    final minVal = _chartTab == 1 ? -maxAbs : rawMin;
    final maxVal = _chartTab == 1 ? maxAbs : rawMax;

    final lineColor = _chartTab == 0
        ? const Color(0xFF1A73E8)
        : _chartTab == 1
        ? const Color(0xFFE91E63)
        : const Color(0xFFFF6F00);

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _LinechartPainter(
            values: values,
            highlightValues: sampled.map((p) => p.accelerationMs2).toList(),
            minVal: minVal,
            maxVal: maxVal,
            lineColor: lineColor,
            baselineAtZero: _chartTab == 1,
            showAccelerationHighlights: _chartTab == 0,
          ),
        );
      },
    );
  }

  List<TripDataPoint> _downsample(List<TripDataPoint> points, int maxCount) {
    if (points.length <= maxCount) return points;
    final step = points.length / maxCount;
    return List.generate(
      maxCount,
      (i) => points[(i * step).round().clamp(0, points.length - 1)],
    );
  }

  // ── Comportement de conduite ──────────────────────────────────────────────

  Widget _buildDrivingBehavior() {
    final s = widget.summary;
    return _AnimatedSection(
      controller: _cardsCtrl,
      delay: 0.25,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Comportement de conduite'),
            const SizedBox(height: 16),
            _behaviorRow(
              icon: Icons.arrow_upward_rounded,
              label: 'Accélérations brusques',
              value: s.hardAccelerationCount,
              goodThreshold: 3,
              unit: 'fois',
              color: const Color(0xFFFF6F00),
            ),
            const SizedBox(height: 12),
            _behaviorRow(
              icon: Icons.arrow_downward_rounded,
              label: 'Freinages brusques',
              value: s.hardBrakingCount,
              goodThreshold: 3,
              unit: 'fois',
              color: const Color(0xFFE91E63),
            ),
            const SizedBox(height: 12),
            _behaviorRow(
              icon: Icons.speed_rounded,
              label: 'Secondes > 130 km/h',
              value: s.speedingCount,
              goodThreshold: 0,
              unit: 's',
              color: const Color(0xFFB71C1C),
            ),
            if (s.altitudeGainM > 10) ...[
              const SizedBox(height: 12),
              _behaviorRow(
                icon: Icons.terrain_rounded,
                label: 'Dénivelé positif',
                value: s.altitudeGainM.round(),
                goodThreshold: 999999,
                unit: 'm',
                color: const Color(0xFF1A73E8),
                isInfo: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _behaviorRow({
    required IconData icon,
    required String label,
    required int value,
    required int goodThreshold,
    required String unit,
    required Color color,
    bool isInfo = false,
  }) {
    final isGood = value <= goodThreshold;
    final displayColor = isInfo
        ? const Color(0xFF1A73E8)
        : isGood
        ? const Color(0xFF2E7D32)
        : color;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: displayColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: displayColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 13,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: displayColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$value $unit',
            style: TextStyle(
              color: displayColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // ── Environnement ─────────────────────────────────────────────────────────

  Widget _buildEnvironmentCard() {
    final s = widget.summary;
    return _AnimatedSection(
      controller: _cardsCtrl,
      delay: 0.35,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Impact environnemental'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _EnvTile(
                    icon: Icons.cloud_outlined,
                    label: 'CO₂ émis',
                    value: s.co2Grams >= 1000
                        ? '${(s.co2Grams / 1000).toStringAsFixed(2)} kg'
                        : '${s.co2Grams.round()} g',
                    color: const Color(0xFF78909C),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EnvTile(
                    icon: Icons.eco_rounded,
                    label: 'CO₂ évité vs agressif',
                    value: s.co2SavedVsAggressive >= 1000
                        ? '${(s.co2SavedVsAggressive / 1000).toStringAsFixed(2)} kg'
                        : '${s.co2SavedVsAggressive.round()} g',
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            if (s.fuelCostEur != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFAB00).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFFAB00).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.euro_rounded,
                      color: Color(0xFFFFAB00),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Coût estimé du trajet',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${s.fuelCostEur!.toStringAsFixed(2)} €',
                      style: const TextStyle(
                        color: Color(0xFFFFAB00),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Temps & Distance ──────────────────────────────────────────────────────

  Widget _buildTimeDistanceCard() {
    final s = widget.summary;
    final timeDelta = s.realDuration.inMinutes - s.estimatedDurationMin;
    final distDelta = s.realDistanceKm - s.estimatedDistanceKm;

    return _AnimatedSection(
      controller: _cardsCtrl,
      delay: 0.45,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Réel vs Estimé'),
            const SizedBox(height: 16),
            _compareRow(
              label: 'Durée',
              real: _fmtDuration(s.realDuration),
              estimated: '${s.estimatedDurationMin} min',
              delta: timeDelta == 0
                  ? 'Parfait ✓'
                  : timeDelta > 0
                  ? '+$timeDelta min'
                  : '${timeDelta} min',
              deltaPositiveIsBad: true,
              deltaValue: timeDelta.toDouble(),
            ),
            const SizedBox(height: 10),
            _compareRow(
              label: 'Distance',
              real: _fmtDist(s.realDistanceKm),
              estimated: _fmtDist(s.estimatedDistanceKm),
              delta: distDelta.abs() < 0.1
                  ? 'Parfait ✓'
                  : distDelta > 0
                  ? '+${distDelta.toStringAsFixed(1)} km'
                  : '${distDelta.toStringAsFixed(1)} km',
              deltaPositiveIsBad: false,
              deltaValue: distDelta,
            ),
          ],
        ),
      ),
    );
  }

  Widget _compareRow({
    required String label,
    required String real,
    required String estimated,
    required String delta,
    required bool deltaPositiveIsBad,
    required double deltaValue,
  }) {
    Color deltaColor;
    if (delta.contains('✓')) {
      deltaColor = const Color(0xFF2E7D32);
    } else if (deltaPositiveIsBad) {
      deltaColor = deltaValue > 0
          ? const Color(0xFFE65100)
          : const Color(0xFF2E7D32);
    } else {
      deltaColor = const Color(0xFF78909C);
    }

    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                real,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Estimé : $estimated',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: deltaColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            delta,
            style: TextStyle(
              color: deltaColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // ── Bouton fermer ─────────────────────────────────────────────────────────

  Widget _buildCloseButton() {
    return ElevatedButton.icon(
      onPressed: widget.onClose,
      icon: const Icon(Icons.map_rounded, size: 18),
      label: const Text('Retour à la carte'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _cardTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget section animée
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedSection extends StatelessWidget {
  final AnimationController controller;
  final double delay; // 0.0 – 1.0
  final Widget child;

  const _AnimatedSection({
    required this.controller,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = delay.clamp(0.0, 0.8);
    final end = (start + 0.4).clamp(0.0, 1.0);

    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat tile
// ─────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Env tile
// ─────────────────────────────────────────────────────────────────────────────

class _EnvTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _EnvTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter : jauge circulaire du score
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreGaugePainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  final Color color;
  final int score;

  _ScoreGaugePainter({
    required this.progress,
    required this.color,
    required this.score,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const startAngle = -math.pi * 0.75;
    const sweepTotal = math.pi * 1.5;

    // Fond gris
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Arc de progression
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * progress,
        false,
        Paint()
          ..color = color
          ..strokeWidth = 10
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Score texte
    final tp = TextPainter(
      text: TextSpan(
        text: '$score',
        style: TextStyle(
          color: color,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2 + 4));

    // Label "/100"
    final tpSub = TextPainter(
      text: TextSpan(
        text: '/100',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpSub.paint(
      canvas,
      center - Offset(tpSub.width / 2, tpSub.height / 2 - 18),
    );
  }

  @override
  bool shouldRepaint(_ScoreGaugePainter old) =>
      old.progress != progress || old.score != score;
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter : graphe linéaire
// ─────────────────────────────────────────────────────────────────────────────

class _LinechartPainter extends CustomPainter {
  final List<double> values;
  final List<double> highlightValues;
  final double minVal;
  final double maxVal;
  final Color lineColor;
  final bool baselineAtZero;
  final bool showAccelerationHighlights;

  _LinechartPainter({
    required this.values,
    required this.highlightValues,
    required this.minVal,
    required this.maxVal,
    required this.lineColor,
    required this.baselineAtZero,
    required this.showAccelerationHighlights,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final visualPadding = ((maxVal - minVal) * 0.12).clamp(0.4, 12.0);
    final chartMin = minVal - visualPadding;
    final chartMax = maxVal + visualPadding;
    final range = (chartMax - chartMin).clamp(1.0, double.infinity);
    final w = size.width;
    final h = size.height;
    final padLeft = 28.0;
    final padRight = 6.0;
    final padTop = 10.0;
    final padBottom = 20.0;
    final chartW = w - padLeft - padRight;
    final chartH = h - padTop - padBottom;

    if (chartW <= 0 || chartH <= 0) return;

    double yFor(double value) {
      return padTop + chartH * (1 - (value - chartMin) / range);
    }

    // Points
    final pts = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = padLeft + (i / (values.length - 1)) * chartW;
      final y = yFor(values[i]);
      pts.add(Offset(x, y));
    }

    // Zones d'accélération importante sur l'axe du temps.
    if (showAccelerationHighlights && highlightValues.length == values.length) {
      final highlightPaint = Paint()
        ..color = const Color(0xFFE91E63).withOpacity(0.16)
        ..strokeWidth = math.max(3, chartW / values.length)
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < highlightValues.length; i++) {
        if (highlightValues[i] < 1.2) continue;
        final x = padLeft + (i / (highlightValues.length - 1)) * chartW;
        canvas.drawLine(
          Offset(x, padTop),
          Offset(x, h - padBottom),
          highlightPaint,
        );
      }
    }

    // Zone de remplissage (gradient)
    final fillPath = Path()..moveTo(pts.first.dx, h - padBottom);
    for (final p in pts) fillPath.lineTo(p.dx, p.dy);
    fillPath
      ..lineTo(pts.last.dx, h - padBottom)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withOpacity(0.25), lineColor.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(padLeft, padTop, chartW, chartH)),
    );

    if (baselineAtZero) {
      final zeroY = yFor(0);
      canvas.drawLine(
        Offset(padLeft, zeroY),
        Offset(w - padRight, zeroY),
        Paint()
          ..color = Colors.white.withOpacity(0.16)
          ..strokeWidth = 1,
      );
    }

    // Ligne
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      // Courbe de Bézier légère pour lisser
      final prev = pts[i - 1];
      final curr = pts[i];
      final cpX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Lignes de grille horizontales
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = padTop + (chartH / 3) * i;
      canvas.drawLine(Offset(padLeft, y), Offset(w - padRight, y), gridPaint);

      // Labels axe Y
      final val = chartMax - (range / 3) * i;
      final tpY = TextPainter(
        text: TextSpan(
          text: val.abs() < 10
              ? val.toStringAsFixed(1)
              : val.round().toString(),
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tpY.paint(canvas, Offset(0, y - tpY.height / 2));
    }
  }

  @override
  bool shouldRepaint(_LinechartPainter old) =>
      old.values != values ||
      old.highlightValues != highlightValues ||
      old.lineColor != lineColor ||
      old.baselineAtZero != baselineAtZero ||
      old.showAccelerationHighlights != showAccelerationHighlights;
}
