import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

class NoInternetScreen extends StatefulWidget {
  /// Appelé quand la connexion est rétablie. Permet au parent de reprendre.
  final VoidCallback onRetry;

  const NoInternetScreen({super.key, required this.onRetry});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen>
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

  Future<bool> _checkConnectivity() => ConnectivityService.hasInternet();

  Future<void> _retry() async {
    setState(() => _checking = true);
    final connected = await _checkConnectivity();
    if (!mounted) return;
    setState(() => _checking = false);
    if (connected) {
      widget.onRetry();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toujours pas de connexion. Vérifiez votre réseau.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                      color: const Color(0xFFE53935).withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 56,
                    color: Color(0xFFE53935),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // Titre
              const Text(
                'Pas de connexion',
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
                'EcoDriving a besoin d\'internet pour charger les cartes et calculer les itinéraires.',
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
                icon: Icons.wifi_rounded,
                text: 'Activez le Wi-Fi ou les données mobiles',
              ),
              const SizedBox(height: 12),
              _HintRow(
                icon: Icons.airplanemode_active_rounded,
                text: 'Désactivez le mode avion si activé',
              ),
              const Spacer(flex: 3),
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
