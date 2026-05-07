import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationDisabledScreen extends StatefulWidget {
  /// Appelé quand la localisation est activée et la permission accordée.
  final VoidCallback onRetry;

  const LocationDisabledScreen({super.key, required this.onRetry});

  @override
  State<LocationDisabledScreen> createState() => _LocationDisabledScreenState();
}

class _LocationDisabledScreenState extends State<LocationDisabledScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _retry() async {
    setState(() => _checking = true);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La localisation est toujours désactivée. '
            'Activez-la dans les paramètres.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;
    setState(() => _checking = false);

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permission de localisation refusée. '
            'Autorisez-la dans les paramètres de l\'application.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
      return;
    }

    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // Icône animée
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A2332),
                    border: Border.all(
                      color: const Color(0xFFF9A825).withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.location_off_rounded,
                    size: 56,
                    color: Color(0xFFF9A825),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // Titre
              const Text(
                'Localisation désactivée',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              // Description
              Text(
                'EcoDriving a besoin de votre position GPS pour suivre vos trajets et calculer votre score éco.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 15,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // Conseils
              _HintRow(
                icon: Icons.gps_fixed_rounded,
                text: 'Activez le GPS dans les paramètres du téléphone',
              ),
              const SizedBox(height: 12),
              _HintRow(
                icon: Icons.security_rounded,
                text:
                    'Autorisez l\'accès à la localisation pour EcoDriving',
              ),
              const Spacer(flex: 3),
              // Bouton paramètres
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openLocationSettings,
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('Ouvrir les paramètres'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF9A825),
                    side: const BorderSide(
                      color: Color(0xFFF9A825),
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Bouton réessayer
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _checking ? null : _retry,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_checking ? 'Vérification…' : 'Réessayer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HintRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white54, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
