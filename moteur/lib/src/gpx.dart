import 'parcours.dart';

/// Lit les points d'un fichier GPX (export Komoot, Strava, Garmin...).
///
/// Prend les points de trace (`trkpt`), ou à défaut les points de route
/// (`rtept`). Un point sans altitude reçoit celle du point précédent (ou
/// du suivant pour les premiers). Lecteur volontairement simple, sans
/// bibliothèque XML : il suffit pour les fichiers de ces applis.
List<PointGps> lireGpx(String texte) {
  var blocs = _blocs(texte, 'trkpt');
  if (blocs.isEmpty) blocs = _blocs(texte, 'rtept');
  final lats = <double>[];
  final lons = <double>[];
  final alts = <double?>[];
  for (final b in blocs) {
    final lat = _attribut(b.ouverture, 'lat');
    final lon = _attribut(b.ouverture, 'lon');
    if (lat == null || lon == null) continue;
    lats.add(lat);
    lons.add(lon);
    final ele = RegExp(r'<ele>\s*([-+0-9.eE]+)\s*</ele>').firstMatch(b.contenu);
    alts.add(ele == null ? null : double.tryParse(ele.group(1)!));
  }
  // Altitudes manquantes.
  double? derniere;
  for (var i = 0; i < alts.length; i++) {
    if (alts[i] != null) {
      derniere = alts[i];
    } else if (derniere != null) {
      alts[i] = derniere;
    }
  }
  final premiere = alts.firstWhere((a) => a != null, orElse: () => 0.0);
  return [
    for (var i = 0; i < lats.length; i++)
      PointGps(lats[i], lons[i], alts[i] ?? premiere!),
  ];
}

/// Écrit une trace GPX minimale.
String ecrireGpx(List<PointGps> points, {String nom = 'Parcours'}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<gpx version="1.1" creator="velo-coach" '
      'xmlns="http://www.topografix.com/GPX/1/1">',
    )
    ..writeln('  <trk><name>${_echapper(nom)}</name><trkseg>');
  for (final p in points) {
    b.writeln(
      '    <trkpt lat="${p.lat.toStringAsFixed(6)}" '
      'lon="${p.lon.toStringAsFixed(6)}">'
      '<ele>${p.altitudeM.toStringAsFixed(1)}</ele></trkpt>',
    );
  }
  b
    ..writeln('  </trkseg></trk>')
    ..writeln('</gpx>');
  return b.toString();
}

class _Bloc {
  const _Bloc(this.ouverture, this.contenu);
  final String ouverture;
  final String contenu;
}

List<_Bloc> _blocs(String texte, String balise) {
  final re = RegExp(
    '<(?:\\w+:)?$balise\\b([^>]*?)(?:/>|>(.*?)</(?:\\w+:)?$balise>)',
    dotAll: true,
  );
  return [
    for (final m in re.allMatches(texte)) _Bloc(m.group(1)!, m.group(2) ?? ''),
  ];
}

double? _attribut(String ouverture, String nom) {
  final m = RegExp(
    '\\b$nom\\s*=\\s*["\']([-+0-9.eE]+)["\']',
  ).firstMatch(ouverture);
  return m == null ? null : double.tryParse(m.group(1)!);
}

String _echapper(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
