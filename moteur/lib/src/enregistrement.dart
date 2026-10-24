import 'dart:convert';

import 'parcours.dart';

/// Une mesure d'une sortie enregistrée.
class PointEnregistre {
  const PointEnregistre({
    required this.t,
    this.puissanceW,
    this.fcBpm,
    this.cadenceRpm,
    this.lat,
    this.lon,
    this.altitudeM,
    this.temperatureC,
  });

  /// Instant (s depuis le départ).
  final double t;
  final double? puissanceW;
  final double? fcBpm;
  final double? cadenceRpm;
  final double? lat;
  final double? lon;
  final double? altitudeM;
  final double? temperatureC;
}

/// Une sortie enregistrée, à rejouer dans le mode simulation.
///
/// Formats lus : flux Strava (JSON tel que renvoyé par le connecteur
/// Strava) et CSV (le format écrit par [versCsv]).
class Enregistrement {
  Enregistrement(this.points);

  /// Flux Strava : objet JSON avec les tableaux `time`, `watts`,
  /// `heart_rate`, `cadence`, `location` (ou `latlng`), `altitude`, `temp`.
  /// Seul `time` est obligatoire.
  factory Enregistrement.depuisStravaJson(String texte) {
    final j = jsonDecode(texte) as Map<String, dynamic>;
    List<dynamic>? serie(String nom) => j[nom] as List<dynamic>?;
    final temps = serie('time');
    if (temps == null) {
      throw const FormatException('Flux Strava sans « time ».');
    }
    final watts = serie('watts');
    final fc = serie('heart_rate');
    final cad = serie('cadence');
    final loc = serie('location') ?? serie('latlng');
    final alt = serie('altitude');
    final temp = serie('temp');
    double? val(List<dynamic>? s, int i) =>
        s == null || i >= s.length ? null : (s[i] as num?)?.toDouble();
    return Enregistrement([
      for (var i = 0; i < temps.length; i++)
        PointEnregistre(
          t: (temps[i] as num).toDouble(),
          puissanceW: val(watts, i),
          fcBpm: val(fc, i),
          cadenceRpm: val(cad, i),
          lat: loc == null || i >= loc.length
              ? null
              : ((loc[i] as List)[0] as num).toDouble(),
          lon: loc == null || i >= loc.length
              ? null
              : ((loc[i] as List)[1] as num).toDouble(),
          altitudeM: val(alt, i),
          temperatureC: val(temp, i),
        ),
    ]);
  }

  /// CSV séparé par des points-virgules, virgule décimale (Excel en
  /// français). Première ligne : en-têtes, voir [enTetesCsv].
  factory Enregistrement.depuisCsv(String texte) {
    final lignes = const LineSplitter()
        .convert(texte)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lignes.isEmpty) return Enregistrement([]);
    final entetes = lignes.first.split(';').map((e) => e.trim()).toList();
    int col(String nom) => entetes.indexOf(nom);
    final iT = col('t_s');
    if (iT < 0) throw const FormatException('CSV sans colonne « t_s ».');
    final iP = col('puissance_w');
    final iFc = col('fc_bpm');
    final iCad = col('cadence_rpm');
    final iLat = col('lat');
    final iLon = col('lon');
    final iAlt = col('altitude_m');
    final iTemp = col('temperature_c');
    final points = <PointEnregistre>[];
    for (final l in lignes.skip(1)) {
      final c = l.split(';');
      double? v(int i) => i < 0 || i >= c.length || c[i].trim().isEmpty
          ? null
          : double.tryParse(c[i].trim().replaceAll(',', '.'));
      final t = v(iT);
      if (t == null) continue;
      points.add(
        PointEnregistre(
          t: t,
          puissanceW: v(iP),
          fcBpm: v(iFc),
          cadenceRpm: v(iCad),
          lat: v(iLat),
          lon: v(iLon),
          altitudeM: v(iAlt),
          temperatureC: v(iTemp),
        ),
      );
    }
    return Enregistrement(points);
  }

  static const enTetesCsv = [
    't_s',
    'puissance_w',
    'fc_bpm',
    'cadence_rpm',
    'lat',
    'lon',
    'altitude_m',
    'temperature_c',
  ];

  final List<PointEnregistre> points;

  double get dureeS => points.isEmpty ? 0 : points.last.t - points.first.t;

  /// Trace GPS de la sortie, utilisable comme parcours.
  List<PointGps> get trace => [
    for (final p in points)
      if (p.lat != null && p.lon != null)
        PointGps(p.lat!, p.lon!, p.altitudeM ?? 0),
  ];

  String versCsv() {
    String f(double? x, int dec) =>
        x == null ? '' : x.toStringAsFixed(dec).replaceAll('.', ',');
    final b = StringBuffer()..writeln(enTetesCsv.join(';'));
    for (final p in points) {
      b.writeln(
        [
          f(p.t, 1),
          f(p.puissanceW, 0),
          f(p.fcBpm, 0),
          f(p.cadenceRpm, 0),
          f(p.lat, 6),
          f(p.lon, 6),
          f(p.altitudeM, 1),
          f(p.temperatureC, 1),
        ].join(';'),
      );
    }
    return b.toString();
  }
}
