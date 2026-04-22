import 'package:flutter/material.dart';
import 'models/vehicle_profile.dart';
import 'screens/mapscreen.dart';
import 'screens/vehicle_setup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/hub_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
      routes: {
        '/map': (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments as VehicleProfile?;
          return MapScreen(vehicleProfile: args!);
        },
        '/setup': (context) => const VehicleSetupScreen(),
        '/hub': (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments as VehicleProfile?;
          return HubScreen(vehicleProfile: args);
        },
      },
    );
  }
}
