import 'dart:math' as math;

import 'config.dart';

/// Rayon moyen de la Terre (m).
const double rayonTerreM = 6371000;

/// Un point de trace GPX.
class PointGps {
  const PointGps(this.lat, this.lon, this.altitudeM);
  final double lat;
  final double lon;
  final double altitudeM;
}

/// Un tronçon de profil, pour décrire un parcours sans GPS (tests,
/// simulation).
class Troncon {
  const Troncon(this.longueurM, this.pentePct);
  final double longueurM;
  final double pentePct;
}

/// Morceau de parcours à pente constante.
class Segment {
  const Segment({
    required this.debutM,
    required this.longueurM,
    required this.pente,
    required this.altitudeM,
    this.capDeg,
  });

  /// Distance depuis le départ du parcours (m).
  final double debutM;
  final double longueurM;

  /// Pente en fraction (0,06 = 6 %).
  final double pente;

  /// Altitude au début du segment (m).
  final double altitudeM;

  /// Direction suivie (degrés, 0 = nord), ou null si inconnue.
  final double? capDeg;

  double get finM => debutM + longueurM;
}

/// Une montée détectée dans le parcours.
class Montee {
  const Montee({
    required this.index,
    required this.debutM,
    required this.finM,
    required this.altitudeDebutM,
    required this.altitudeFinM,
  });

  /// Numéro de la montée dans le parcours (0, 1, 2...).
  final int index;
  final double debutM;
  final double finM;
  final double altitudeDebutM;
  final double altitudeFinM;

  double get longueurM => finM - debutM;
  double get deniveleM => altitudeFinM - altitudeDebutM;

  /// Pente moyenne en fraction.
  double get penteMoyenne => deniveleM / longueurM;

  bool contient(double distanceM) => distanceM >= debutM && distanceM < finM;
}

/// Distance entre deux points GPS (m), formule de haversine.
double distanceGps(double lat1, double lon1, double lat2, double lon2) {
  const rad = math.pi / 180;
  final dLat = (lat2 - lat1) * rad;
  final dLon = (lon2 - lon1) * rad;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * rad) *
          math.cos(lat2 * rad) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * rayonTerreM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Cap pour aller du point 1 au point 2 (degrés, 0 = nord, 90 = est).
double capGps(double lat1, double lon1, double lat2, double lon2) {
  const rad = math.pi / 180;
  final p1 = lat1 * rad;
  final p2 = lat2 * rad;
  final dl = (lon2 - lon1) * rad;
  final y = math.sin(dl) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (math.atan2(y, x) / rad + 360) % 360;
}

/// Parcours rééchantillonné à pas régulier, altitude lissée, montées
/// détectées.
class Parcours {
  Parcours._(
    this.segments,
    this.montees, [
    this.latitudes = const [],
    this.longitudes = const [],
  ]);

  /// Parcours tiré d'une trace GPS (fichier GPX).
  factory Parcours.depuisPoints(
    List<PointGps> points, {
    ConfigMontees cfg = const ConfigMontees(),
  }) {
    if (points.length < 2) return Parcours._(const [], const []);
    final dist = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      dist.add(dist.last + distanceGps(a.lat, a.lon, b.lat, b.lon));
    }
    return _construire(
      dist,
      [for (final p in points) p.altitudeM],
      [for (final p in points) p.lat],
      [for (final p in points) p.lon],
      null,
      cfg,
    );
  }

  /// Parcours décrit par tronçons de pente constante, au cap [capDeg]
  /// (null = cap inconnu, le vent est alors ignoré).
  factory Parcours.depuisProfil(
    List<Troncon> troncons, {
    double altitudeDepartM = 300,
    double? capDeg = 0,
    ConfigMontees cfg = const ConfigMontees(),
  }) {
    final dist = <double>[0];
    final alt = <double>[altitudeDepartM];
    for (final t in troncons) {
      dist.add(dist.last + t.longueurM);
      alt.add(alt.last + t.longueurM * t.pentePct / 100);
    }
    return _construire(dist, alt, null, null, capDeg, cfg);
  }

  final List<Segment> segments;
  final List<Montee> montees;

  /// Coordonnées des points de la grille (un de plus que de segments),
  /// vides pour un parcours décrit par profil. Servent au calage GPS.
  final List<double> latitudes;
  final List<double> longitudes;

  double get longueurM => segments.isEmpty ? 0 : segments.last.finM;

  static Parcours _construire(
    List<double> dist,
    List<double> alt,
    List<double>? lat,
    List<double>? lon,
    double? capFixe,
    ConfigMontees cfg,
  ) {
    final total = dist.last;
    if (total <= 0) return Parcours._(const [], const []);

    // 1. Rééchantillonnage tous les cfg.pasM mètres.
    final gd = <double>[];
    final ga = <double>[];
    final glat = <double>[];
    final glon = <double>[];
    var j = 0;
    void ajouter(double d) {
      while (j < dist.length - 2 && dist[j + 1] <= d) {
        j++;
      }
      final d0 = dist[j];
      final d1 = dist[j + 1];
      final f = d1 > d0 ? ((d - d0) / (d1 - d0)).clamp(0.0, 1.0) : 1.0;
      gd.add(d);
      ga.add(alt[j] + f * (alt[j + 1] - alt[j]));
      if (lat != null && lon != null) {
        glat.add(lat[j] + f * (lat[j + 1] - lat[j]));
        glon.add(lon[j] + f * (lon[j + 1] - lon[j]));
      }
    }

    final n = (total / cfg.pasM).floor();
    for (var k = 0; k <= n; k++) {
      ajouter(k * cfg.pasM);
    }
    if (total - gd.last > 0.5) ajouter(total);
    if (gd.length < 2) return Parcours._(const [], const []);

    // 2. Lissage de l'altitude.
    final lisse = _lisser(ga, (cfg.lissageAltitudeM / 2 / cfg.pasM).round());

    // 3. Segments.
    final segments = <Segment>[];
    for (var i = 0; i < gd.length - 1; i++) {
      final l = gd[i + 1] - gd[i];
      segments.add(
        Segment(
          debutM: gd[i],
          longueurM: l,
          pente: (lisse[i + 1] - lisse[i]) / l,
          altitudeM: lisse[i],
          capDeg:
              capFixe ??
              (glat.isEmpty
                  ? null
                  : capGps(glat[i], glon[i], glat[i + 1], glon[i + 1])),
        ),
      );
    }

    return Parcours._(segments, _detecterMontees(gd, lisse, cfg), glat, glon);
  }

  /// Moyenne glissante centrée sur ±[demi] points. La fenêtre se
  /// rétrécit aux deux bouts pour garder les altitudes de départ et
  /// d'arrivée exactes.
  static List<double> _lisser(List<double> v, int demi) {
    if (demi <= 0) return [...v];
    final cumul = <double>[0];
    for (final x in v) {
      cumul.add(cumul.last + x);
    }
    final n = v.length;
    return [
      for (var i = 0; i < n; i++)
        () {
          final h = math.min(demi, math.min(i, n - 1 - i));
          return (cumul[i + h + 1] - cumul[i - h]) / (2 * h + 1);
        }(),
    ];
  }

  /// Détection des montées.
  ///
  /// Une montée part d'un point où la pente dépasse penteDebut. Elle
  /// avance son « point haut » tant qu'on gagne au moins penteDebut en
  /// moyenne depuis le dernier point haut. Elle s'arrête après un replat
  /// trop long ou une descente trop forte. On la garde si elle est assez
  /// longue, assez haute et assez raide.
  static List<Montee> _detecterMontees(
    List<double> d,
    List<double> alt,
    ConfigMontees cfg,
  ) {
    final res = <Montee>[];
    final penteDebut = cfg.penteDebutPct / 100;
    final n = d.length;
    var i = 0;
    while (i < n - 1) {
      final pente = (alt[i + 1] - alt[i]) / (d[i + 1] - d[i]);
      if (pente < penteDebut) {
        i++;
        continue;
      }
      var haut = i;
      for (var j = i + 1; j < n; j++) {
        final ecart = d[j] - d[haut];
        if (alt[j] - alt[haut] >= penteDebut * ecart) {
          haut = j;
        } else if (alt[haut] - alt[j] > cfg.perteMaxM ||
            ecart > cfg.replatMaxM) {
          break;
        }
      }
      final longueur = d[haut] - d[i];
      final denivele = alt[haut] - alt[i];
      if (longueur >= cfg.longueurMinM &&
          denivele >= cfg.deniveleMinM &&
          denivele / longueur >= cfg.penteMoyenneMinPct / 100) {
        res.add(
          Montee(
            index: res.length,
            debutM: d[i],
            finM: d[haut],
            altitudeDebutM: alt[i],
            altitudeFinM: alt[haut],
          ),
        );
        i = haut;
      } else {
        i++;
      }
    }
    return res;
  }

  /// Index du segment où se trouve la distance [d].
  int indexSegmentA(double d) => _indexA(d);

  int _indexA(double d) {
    var bas = 0;
    var haut = segments.length - 1;
    while (bas < haut) {
      final m = (bas + haut + 1) ~/ 2;
      if (segments[m].debutM <= d) {
        bas = m;
      } else {
        haut = m - 1;
      }
    }
    return bas;
  }

  /// Segment où se trouve la distance [d].
  Segment segmentA(double d) => segments[_indexA(d)];

  /// Segments entre [d0] et [d1], coupés aux bornes.
  List<Segment> segmentsEntre(double d0, double d1) {
    final res = <Segment>[];
    if (segments.isEmpty || d1 <= d0) return res;
    for (var i = _indexA(d0); i < segments.length; i++) {
      final s = segments[i];
      if (s.debutM >= d1) break;
      final a = math.max(s.debutM, d0);
      final b = math.min(s.finM, d1);
      if (b - a <= 1e-9) continue;
      res.add(
        Segment(
          debutM: a,
          longueurM: b - a,
          pente: s.pente,
          altitudeM: s.altitudeM + s.pente * (a - s.debutM),
          capDeg: s.capDeg,
        ),
      );
    }
    return res;
  }

  /// Montée en cours à la distance [d], ou null.
  Montee? monteeA(double d) {
    for (final m in montees) {
      if (m.contient(d)) return m;
    }
    return null;
  }

  /// Prochaine montée qui commence après [d], ou null.
  Montee? prochaineMontee(double d) {
    for (final m in montees) {
      if (m.debutM > d) return m;
    }
    return null;
  }
}
