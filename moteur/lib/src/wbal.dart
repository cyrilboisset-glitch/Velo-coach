import 'dart:math' as math;

import 'config.dart';

/// Réserve anaérobie W'bal (modèle de Skiba).
///
/// Au-dessus de la puissance critique CP, la réserve se vide de
/// (P − CP) joules par seconde. En dessous, elle se recharge.
class ReserveAnaerobie {
  ReserveAnaerobie({
    required this.wPrimeJ,
    this.modele = ModeleWbal.differentiel,
  }) : wbalJ = wPrimeJ;

  final double wPrimeJ;
  final ModeleWbal modele;

  /// Réserve restante (J). Peut devenir négative si CP ou W' sont
  /// surestimés : c'est un signal pour refaire un test.
  double wbalJ;

  /// Réserve restante en % de W'.
  double get pourcentage => 100 * wbalJ / wPrimeJ;

  // Modèle intégral : dépense en cours de récupération et puissance
  // moyenne sous CP.
  double _depenseJ = 0;
  double _sousCpTravailJ = 0;
  double _sousCpDureeS = 0;

  /// Ajoute [dt] secondes passées à [puissanceW] avec une CP de [cpW].
  void maj(double puissanceW, double cpW, double dt) {
    if (dt <= 0) return;
    switch (modele) {
      case ModeleWbal.differentiel:
        // Skiba et al., 2015 :
        //   P ≥ CP : dW'bal/dt = −(P − CP)
        //   P < CP : dW'bal/dt = (W' − W'bal) × (CP − P) / W'
        // Solution exacte pour une puissance constante pendant dt.
        if (puissanceW >= cpW) {
          wbalJ -= (puissanceW - cpW) * dt;
        } else {
          wbalJ =
              wPrimeJ -
              (wPrimeJ - wbalJ) * math.exp(-(cpW - puissanceW) * dt / wPrimeJ);
        }
      case ModeleWbal.integral:
        // Skiba et al., 2012 : chaque joule pris dans W' revient avec
        // une constante de temps tau, qui dépend de la puissance moyenne
        // sous CP (D_CP = CP − moyenne sous CP).
        if (puissanceW < cpW) {
          _sousCpTravailJ += puissanceW * dt;
          _sousCpDureeS += dt;
        }
        final moyenneSousCp = _sousCpDureeS > 0
            ? _sousCpTravailJ / _sousCpDureeS
            : 0.0;
        final tau = tauSkiba2012(cpW - moyenneSousCp);
        _depenseJ =
            _depenseJ * math.exp(-dt / tau) +
            math.max(0.0, puissanceW - cpW) * dt;
        wbalJ = wPrimeJ - _depenseJ;
    }
  }
}

/// Constante de temps de récupération du modèle intégral (s).
/// Skiba et al., 2012 : tau = 546 × e^(−0,01 × D_CP) + 316.
double tauSkiba2012(double dcpW) => 546 * math.exp(-0.01 * dcpW) + 316;

/// CP effective après [travailKj] de travail (fatigue de fond).
double cpEffective({
  required double cpW,
  required double travailKj,
  required ConfigWbal cfg,
}) {
  final excedent = travailKj - cfg.fatigueSeuilKj;
  if (excedent <= 0) return cpW;
  var tranches = excedent / cfg.fatigueTrancheKj;
  if (cfg.fatigueEnEscalier) tranches = tranches.floorToDouble();
  final baissePct = math.min(
    cfg.fatigueReductionMaxPct,
    cfg.fatiguePctParTranche * tranches,
  );
  return cpW * (1 - baissePct / 100);
}
