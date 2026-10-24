import 'dart:math' as math;

import 'config.dart';
import 'parcours.dart';
import 'physique.dart';
import 'wbal.dart';

/// Un col qui suit de près la montée en cours.
class ColEnchaine {
  const ColEnchaine({required this.intervalle, required this.montee});

  /// Du sommet précédent au pied de ce col (descente, replat...).
  final List<Segment> intervalle;
  final List<Segment> montee;
}

/// Résultat du calcul de pacing pour une montée (ou ce qu'il en reste).
class ResultatPacing {
  const ResultatPacing({
    required this.puissanceW,
    required this.dureeS,
    required this.reserveSommetJ,
    this.colsEnchaines = 0,
    this.plafonnee = false,
    this.plancher = false,
  });

  /// Puissance à tenir (W).
  final double puissanceW;

  /// Durée estimée jusqu'au sommet à cette puissance (s).
  final double dureeS;

  /// Réserve W'bal prévue au sommet de cette montée (J). Plus de zéro
  /// quand un col suivant arrive vite.
  final double reserveSommetJ;

  /// Nombre de cols suivants gérés avec celui-ci.
  final int colsEnchaines;

  /// Vrai si la cible a été bloquée au maximum (montée trop courte pour
  /// le modèle CP/W').
  final bool plafonnee;

  /// Vrai si la cible a été bloquée au minimum (réserve très négative).
  final bool plancher;
}

/// Puissance cible P en montée.
///
/// Montée seule : P = CP_eff + (W'bal − réserve finale) / durée(P).
///
/// Cols enchaînés : une seule puissance P pour tous. On suit la réserve
/// col après col (elle baisse de (P − CP) × durée dans chaque montée, et
/// remonte entre deux cols selon le modèle de Skiba). P est la plus forte
/// puissance qui laisse la réserve finale en haut du dernier col, sans
/// jamais passer sous zéro en haut d'un col intermédiaire.
///
/// La durée vient du modèle physique (pente, masse, CdA, Crr, vent).
/// On cherche P par dichotomie, à 0,1 W près.
ResultatPacing calculerPacing({
  required List<Segment> segments,
  List<ColEnchaine> enchainement = const [],
  required double cpEffW,
  required double wbalJ,
  required double wPrimeJ,
  required double ftpW,
  required ConfigPacing cfg,
  required ConditionsRoulage conditions,
  ModeleWbal modele = ModeleWbal.differentiel,
}) {
  final pMin = cfg.puissanceMinPctFtp / 100 * ftpW;
  final pMax = cfg.puissanceMaxPctFtp / 100 * ftpW;
  final reserveFinJ = cfg.reserveFinMonteePct / 100 * wPrimeJ;
  final longueur = segments.fold(0.0, (s, x) => s + x.longueurM);
  if (longueur < 1) {
    return ResultatPacing(
      puissanceW: cpEffW.clamp(pMin, pMax),
      dureeS: 0,
      reserveSommetJ: wbalJ,
    );
  }

  final montees = [segments, for (final c in enchainement) c.montee];
  final pRecup = cfg.puissanceEntreColsPctFtp / 100 * ftpW;
  final recupS = [
    for (final c in enchainement)
      dureeSegments(c.intervalle, pRecup, conditions),
  ];

  // CP retenue pour une durée de montée donnée (correction des cols de
  // plus d'une heure).
  double cpPourDuree(double t) =>
      cfg.declinLongueDureeParLn > 0 && t > cfg.dureeRefDeclinS
      ? cpEffW *
            (1 - cfg.declinLongueDureeParLn * math.log(t / cfg.dureeRefDeclinS))
      : cpEffW;

  // Recharge de la réserve entre deux cols (Skiba).
  double recuperer(double w, double dureeS) {
    final dcp = cpEffW - pRecup;
    if (dcp <= 0 || dureeS <= 0) return w;
    final tau = modele == ModeleWbal.differentiel
        ? wPrimeJ / dcp
        : tauSkiba2012(dcp);
    return wPrimeJ - (wPrimeJ - w) * math.exp(-dureeS / tau);
  }

  // Réserve en haut du col [k] si on tient [p] depuis maintenant.
  double reserveAuSommet(double p, int k) {
    var w = wbalJ;
    var tMontee = 0.0;
    for (var i = 0; i <= k; i++) {
      if (i > 0) w = recuperer(w, recupS[i - 1]);
      final t = dureeSegments(montees[i], p, conditions);
      tMontee += t;
      w -= (p - cpPourDuree(tMontee)) * t;
    }
    return w;
  }

  // Plus forte puissance qui laisse [cible] joules en haut du col [k].
  double puissancePour(int k, double cible) {
    if (reserveAuSommet(pMax, k) >= cible) return pMax;
    if (reserveAuSommet(pMin, k) <= cible) return pMin;
    var bas = pMin;
    var haut = pMax;
    while (haut - bas > 0.1) {
      final milieu = 0.5 * (bas + haut);
      if (reserveAuSommet(milieu, k) > cible) {
        bas = milieu;
      } else {
        haut = milieu;
      }
    }
    return 0.5 * (bas + haut);
  }

  final dernier = montees.length - 1;
  var p = puissancePour(dernier, reserveFinJ);
  for (var k = 0; k < dernier; k++) {
    p = math.min(p, puissancePour(k, 0));
  }
  return ResultatPacing(
    puissanceW: p,
    dureeS: dureeSegments(segments, p, conditions),
    reserveSommetJ: reserveAuSommet(p, 0),
    colsEnchaines: enchainement.length,
    plafonnee: p >= pMax,
    plancher: p <= pMin,
  );
}
