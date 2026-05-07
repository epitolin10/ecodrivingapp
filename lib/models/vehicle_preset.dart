import 'package:flutter/material.dart';

class VehiclePreset {
  final String label;
  final IconData icon;
  final double cx;
  final double frontalAreaM2;
  final double defaultMassKg;
  final double defaultPowerKw;

  const VehiclePreset({
    required this.label,
    required this.icon,
    required this.cx,
    required this.frontalAreaM2,
    required this.defaultMassKg,
    required this.defaultPowerKw,
  });
}

const vehiclePresets = [
  VehiclePreset(
    label: 'Citadine',
    icon: Icons.directions_car_outlined,
    cx: 0.32,
    frontalAreaM2: 2.0,
    defaultMassKg: 1100,
    defaultPowerKw: 55,
  ),
  VehiclePreset(
    label: 'Berline',
    icon: Icons.directions_car,
    cx: 0.28,
    frontalAreaM2: 2.2,
    defaultMassKg: 1400,
    defaultPowerKw: 85,
  ),
  VehiclePreset(
    label: 'SUV',
    icon: Icons.airport_shuttle_outlined,
    cx: 0.35,
    frontalAreaM2: 2.6,
    defaultMassKg: 1700,
    defaultPowerKw: 110,
  ),
  VehiclePreset(
    label: 'Utilitaire',
    icon: Icons.local_shipping_outlined,
    cx: 0.38,
    frontalAreaM2: 3.2,
    defaultMassKg: 2000,
    defaultPowerKw: 90,
  ),
];
