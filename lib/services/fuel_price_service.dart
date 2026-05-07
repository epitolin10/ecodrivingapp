import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/fuel_prices.dart';

export '../models/fuel_prices.dart';

class FuelPriceService {
  static const _url =
      'https://api-carburant.onrender.com/api/prix/hebdomadaires/derniere';

  static FuelPrices? _cache;
  static DateTime? _cacheTime;

  static Future<FuelPrices?> fetchLatest() async {
    // Cache uniquement si les données sont réelles (au moins un prix non-null)
    if (_cache != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!).inHours < 1 &&
        (_cache!.gazole != null || _cache!.sp95 != null || _cache!.sp98 != null)) {
      return _cache;
    }

    try {
      final response = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final prices = _extract(data);
      _cache = prices;
      _cacheTime = DateTime.now();
      return prices;
    } catch (_) {
      return null;
    }
  }

  static FuelPrices _extract(dynamic data) {
    double? gazole;
    double? sp95;
    double? sp98;

    // Format principal : { "data": [ { "carburant": "Gazole", "prix_moyen": 2.33 }, ... ] }
    final list = data is Map ? data['data'] : (data is List ? data : null);
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final carburant = item['carburant']?.toString().toUpperCase() ?? '';
        final prix = item['prix_moyen'] ?? item['prix'] ?? item['moyenne'];
        if (prix is! num) continue;
        if (carburant == 'GAZOLE' || carburant == 'DIESEL') {
          gazole ??= prix.toDouble();
        } else if (carburant.startsWith('SP95') || carburant == 'E10') {
          sp95 ??= prix.toDouble();
        } else if (carburant.startsWith('SP98')) {
          sp98 ??= prix.toDouble();
        }
      }
    }

    return FuelPrices(
      gazole: gazole,
      sp95: sp95,
      sp98: sp98,
      fetchedAt: DateTime.now(),
    );
  }
}
