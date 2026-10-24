import 'dart:math' as math;

import 'config.dart';
import 'parcours.dart';
import 'physique.dart';

/// Résultat du calcul de pacing pour une montée (ou ce qu'il en reste).
class ResultatPacing {
  const ResultatPacing({
    required this.puissanceW,
    required this.dureeS,
    this.plafonnee = false,
    this.plancher = false,
  });

  /// Puissance à tenir (W).
  final double puissanceW;

  /// Durée estimée jusqu'au sommet à cette puissance (s).
  final double dureeS;

  /// Vrai si la cible a été bloquée au maximum (montée trop courte pour
  /// le modèle CP/W').
  final bool plafonnee;

  /// Vrai si la cible a été bloquée au minimum (réserve très négative).
  final bool plancher;
}

/// Puissance cible P telle que P = CP_eff + W'bal disponible / durée(P).
///
/// La durée vient du modèle physique (pente, masse, CdA, Crr, vent).
/// Plus P est grande, plus la montée est courte : on cherche P par
/// dichotomie, à 0,1 W près.
ResultatPacing calculerPacing({
  required List<Segment> segments,
  required double cpEffW,
  required double wbalJ,
  required double wPrimeJ,
  required double ftpW,
  required ConfigPacing cfg,
  required ConditionsRoulage conditions,
}) {
  final pMin = cfg.puissanceMinPctFtp / 100 * ftpW;
  final pMax = cfg.puissanceMaxPctFtp / 100 * ftpW;
  final wDispo = wbalJ - cfg.reserveFinMonteePct / 100 * wPrimeJ;
  final longueur = segments.fold(0.0, (s, x) => s + x.longueurM);
  if (longueur < 1) {
    return ResultatPacing(puissanceW: cpEffW.clamp(pMin, pMax), dureeS: 0);
  }

  double duree(double p) => dureeSegments(segments, p, conditions);

  // CP retenue pour une durée donnée (déclin au-delà d'une heure si
  // activé dans la configuration).
  double cpPourDuree(double t) =>
      cfg.declinLongueDureeParLn > 0 && t > cfg.dureeRefDeclinS
      ? cpEffW *
            (1 - cfg.declinLongueDureeParLn * math.log(t / cfg.dureeRefDeclinS))
      : cpEffW;

  double ecart(double p) {
    final t = duree(p);
    return p - cpPourDuree(t) - wDispo / t;
  }

  if (ecart(pMin) >= 0) {
    return ResultatPacing(
      puissanceW: pMin,
      dureeS: duree(pMin),
      plancher: true,
    );
  }
  if (ecart(pMax) <= 0) {
    return ResultatPacing(
      puissanceW: pMax,
      dureeS: duree(pMax),
      plafonnee: true,
    );
  }
  var bas = pMin;
  var haut = pMax;
  while (haut - bas > 0.1) {
    final milieu = 0.5 * (bas + haut);
    if (ecart(milieu) < 0) {
      bas = milieu;
    } else {
      haut = milieu;
    }
  }
  final p = 0.5 * (bas + haut);
  return ResultatPacing(puissanceW: p, dureeS: duree(p));
}
