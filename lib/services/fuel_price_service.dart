import 'package:http/http.dart' as http;

/// Récupère le prix moyen national TTC d'un carburant via l'API prix-carburants.
/// fuel ID 1 = Gazole, fuel ID 2 = SP95 (Sans Plomb 95)
class FuelPriceService {
  static const int _gazolaFuelId = 1;
  static const int _sp95FuelId = 2;

  /// Retourne le prix en €/L pour le type de carburant du véhicule.
  /// Essaie d'abord l'année courante, puis l'année précédente en fallback
  /// si aucune donnée n'est encore disponible.
  /// Retourne null en cas d'erreur réseau ou de parsing.
  static Future<double?> fetchPricePerLiter({required bool isDiesel}) async {
    final fuelId = isDiesel ? _gazolaFuelId : _sp95FuelId;
    final currentYear = DateTime.now().year;
    for (final year in [currentYear, currentYear - 1]) {
      final uri = Uri.parse(
        'https://api.prix-carburants.2aaz.fr/fuel/$fuelId/price/$year?responseFields=PriceTTC',
      );
      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final price = _parsePrice(response.body);
          if (price != null) return price;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Extrait la valeur numérique du champ <value> dans la réponse XML.
  static double? _parsePrice(String xml) {
    final start = xml.indexOf('<value>');
    final end = xml.indexOf('</value>');
    if (start == -1 || end == -1) return null;
    final valueStr = xml.substring(start + 7, end).trim();
    return double.tryParse(valueStr);
  }
}
