import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import '../models/trip_storage.dart';
import '../models/vehicle_profile.dart';

class ImportResult {
  final List<StoredTrip> trips;
  final VehicleProfile? vehicleProfile;
  final int version;

  const ImportResult({
    required this.trips,
    required this.vehicleProfile,
    required this.version,
  });
}

class DataExportService {
  static const int _currentVersion = 1;

  /// Exporte tous les trajets et le profil véhicule dans un fichier JSON
  /// partageable. Retourne le chemin du fichier créé.
  static Future<void> exportData({
    required List<StoredTrip> trips,
    required VehicleProfile? vehicleProfile,
  }) async {
    final now = DateTime.now();
    final payload = {
      'version': _currentVersion,
      'exported_at': now.toIso8601String(),
      'vehicle_profile': vehicleProfile?.toJson(),
      'trips': trips.map((t) => t.toJson()).toList(),
    };

    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await getApplicationDocumentsDirectory();
    final filename =
        'ecodriving_export_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(json, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'EcoDriving — sauvegarde du ${now.day}/${now.month}/${now.year}',
    );
  }

  /// Ouvre un sélecteur de fichier, parse le JSON et retourne les données
  /// importées. Retourne null si l'utilisateur annule ou si le fichier est
  /// invalide.
  static Future<ImportResult?> importData() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final bytes = result.files.first.bytes;
    if (bytes == null) return null;

    try {
      final raw = utf8.decode(bytes);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final version = (json['version'] as num?)?.toInt() ?? 1;

      VehicleProfile? vehicleProfile;
      if (json['vehicle_profile'] != null) {
        vehicleProfile = VehicleProfile.fromJson(
          json['vehicle_profile'] as Map<String, dynamic>,
        );
      }

      final tripsRaw = json['trips'] as List? ?? [];
      final trips = tripsRaw
          .map((e) {
            try {
              return StoredTrip.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<StoredTrip>()
          .toList();

      return ImportResult(
        trips: trips,
        vehicleProfile: vehicleProfile,
        version: version,
      );
    } catch (_) {
      return null;
    }
  }
}
