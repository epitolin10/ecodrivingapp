import 'package:flutter/material.dart';
import 'models/vehicle_profile.dart';
import 'screens/mapscreen.dart';
import 'screens/vehicle_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = await VehicleProfile.load();
  runApp(MainApp(vehicleProfile: profile));
}

class MainApp extends StatelessWidget {
  final VehicleProfile? vehicleProfile;

  const MainApp({super.key, this.vehicleProfile});

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
      home: vehicleProfile != null
          ? MapScreen(vehicleProfile: vehicleProfile!)
          : const VehicleSetupScreen(),
    );
  }
}
