// Météo du moment par Open-Meteo (gratuit, sans clé).
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

import 'config_appli.dart';

/// Température, humidité et vent à la position donnée, ou null si le
/// réseau ne répond pas (le coach garde alors la dernière météo connue).
Future<Meteo?> lireMeteo(double lat, double lon) async {
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': lat.toStringAsFixed(4),
    'longitude': lon.toStringAsFixed(4),
    'current':
        'temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m',
    'wind_speed_unit': 'ms',
  });
  try {
    final rep = await http.get(uri).timeout(delaiReseau);
    if (rep.statusCode != 200) return null;
    final c =
        (jsonDecode(rep.body) as Map<String, dynamic>)['current']
            as Map<String, dynamic>;
    return Meteo(
      temperatureC: (c['temperature_2m'] as num).toDouble(),
      humiditePct: (c['relative_humidity_2m'] as num).toDouble(),
      ventMs: (c['wind_speed_10m'] as num).toDouble(),
      ventVientDeDeg: (c['wind_direction_10m'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}
