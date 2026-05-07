import 'package:flutter/material.dart';
import '../models/vehicle_profile.dart';
import '../services/connectivity_service.dart';
import 'no_internet_screen.dart';
import 'location_disabled_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  Future<bool> _hasInternet() => ConnectivityService.hasInternet();

  Future<bool> _hasLocation() => ConnectivityService.hasLocation();

  Future<void> _navigateToHome() async {
    final profile = await VehicleProfile.load();

    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final connected = await _hasInternet();
    if (!mounted) return;

    if (!connected) {
      _showNoInternet(profile);
      return;
    }

    final locationOn = await _hasLocation();
    if (!mounted) return;

    if (!locationOn) {
      _showLocationDisabled(profile);
      return;
    }

    _goToApp(profile);
  }

  void _goToApp(VehicleProfile? profile) {
    Navigator.of(context).pushReplacementNamed(
      profile != null ? '/map' : '/setup',
      arguments: profile,
    );
  }

  void _showNoInternet(VehicleProfile? profile) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NoInternetScreen(
          onRetry: () async {
            final locationOn = await _hasLocation();
            if (!mounted) return;
            if (!locationOn) {
              _showLocationDisabled(profile);
            } else {
              _goToApp(profile);
            }
          },
        ),
      ),
    );
  }

  void _showLocationDisabled(VehicleProfile? profile) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LocationDisabledScreen(
          onRetry: () => _goToApp(profile),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Image.asset('lib/logo.png', fit: BoxFit.contain),
              ),
              const SizedBox(height: 40),
              // Titre
              const Text(
                'EcoDriving',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              // Sous-titre
              const Text(
                'Assistant d\'éco conduite',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 60),
              // Indicateur de chargement
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
