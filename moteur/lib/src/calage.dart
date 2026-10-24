import 'dart:math' as math;

import 'parcours.dart';

/// Calage des positions GPS sur le parcours : transforme (latitude,
/// longitude) en distance depuis le départ du GPX.
///
/// On cherche le point du parcours le plus proche, d'abord un peu en
/// arrière et devant la dernière position connue (pour ne pas sauter sur
/// l'autre côté d'un aller-retour ou d'une boucle), puis sur tout le
/// parcours si on ne trouve rien (retour après un détour).
class Calage {
  Calage(
    this.parcours, {
    this.toleranceM = 60,
    this.fenetreArriereM = 150,
    this.fenetreAvantM = 2000,
  });

  final Parcours parcours;

  /// Au-delà de cette distance au tracé, on est « hors parcours ».
  final double toleranceM;
  final double fenetreArriereM;
  final double fenetreAvantM;

  double? _derniereM;

  /// Dernière distance calée (m), ou null.
  double? get derniereM => _derniereM;

  /// Distance sur le parcours (m), ou null si hors parcours.
  double? caler(double lat, double lon) {
    final segs = parcours.segments;
    if (segs.isEmpty || parcours.latitudes.length != segs.length + 1) {
      return null;
    }
    final derniere = _derniereM;
    _Projection? p;
    if (derniere != null) {
      p = _chercher(
        lat,
        lon,
        derniere - fenetreArriereM,
        derniere + fenetreAvantM,
      );
    }
    if (p == null || p.ecartM > toleranceM) {
      final partout = _chercher(lat, lon, 0, double.infinity);
      if (p == null || (partout != null && partout.ecartM < p.ecartM)) {
        p = partout;
      }
    }
    if (p == null || p.ecartM > toleranceM) return null;
    _derniereM = p.distanceM;
    return p.distanceM;
  }

  _Projection? _chercher(double lat, double lon, double d0, double d1) {
    final segs = parcours.segments;
    final lats = parcours.latitudes;
    final lons = parcours.longitudes;
    // Projection plane locale (mètres) autour du point.
    const rad = math.pi / 180;
    final kx = rayonTerreM * rad * math.cos(lat * rad);
    const ky = rayonTerreM * rad;
    _Projection? meilleur;
    for (
      var i = d0 > 0 ? parcours.indexSegmentA(d0) : 0;
      i < segs.length;
      i++
    ) {
      final s = segs[i];
      if (s.debutM > d1) break;
      final ax = (lons[i] - lon) * kx;
      final ay = (lats[i] - lat) * ky;
      final bx = (lons[i + 1] - lon) * kx;
      final by = (lats[i + 1] - lat) * ky;
      final dx = bx - ax;
      final dy = by - ay;
      final l2 = dx * dx + dy * dy;
      final f = l2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / l2).clamp(0.0, 1.0);
      final px = ax + f * dx;
      final py = ay + f * dy;
      final ecart = math.sqrt(px * px + py * py);
      if (meilleur == null || ecart < meilleur.ecartM) {
        meilleur = _Projection(s.debutM + f * s.longueurM, ecart);
      }
    }
    return meilleur;
  }
}

class _Projection {
  const _Projection(this.distanceM, this.ecartM);
  final double distanceM;
  final double ecartM;
}
