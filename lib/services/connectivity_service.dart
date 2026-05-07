import 'dart:io';
import 'package:geolocator/geolocator.dart';

class ConnectivityService {
  static Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(
        const Duration(seconds: 5),
      );
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasLocation() async {
    return Geolocator.isLocationServiceEnabled();
  }
}
