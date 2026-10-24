import 'dart:math' as math;

import 'config.dart';
import 'lissage.dart';

/// Fonction 2 : sueur perdue, objectif de boisson, retard, alertes.
///
/// Sudation (L/h) = taux de base × f(température) × f(humidité)
///                  × f(intensité). Voir ConfigBoire.
class Hydratation {
  Hydratation(this.cfg, this.ftpW)
    : _intensite = MoyenneExpo(cfg.lissageIntensiteS),
      _prochainSeuilMl = cfg.seuilAlerteMl;

  final ConfigBoire cfg;
  final double ftpW;
  final MoyenneExpo _intensite;
  double _prochainSeuilMl;

  /// Sueur perdue estimée depuis le départ (L).
  double perteL = 0;

  /// Ce qu'il aurait fallu boire depuis le départ (L).
  double objectifL = 0;

  /// Ce que tu as bu (L).
  double buL = 0;

  /// Dernier taux de sudation calculé (L/h).
  double sudationLh = 0;

  /// Somme des facteurs × durée (h). Sert à la calibration : la perte
  /// réelle divisée par ce nombre donne ton vrai taux de base.
  double heuresEquivalentes = 0;

  /// Retard sur l'objectif (ml). Négatif = en avance.
  double get retardMl => (objectifL - buL) * 1000;

  double facteurTemperature(double temperatureC) =>
      (1 + cfg.coefTemperatureParDegre * (temperatureC - cfg.temperatureRefC))
          .clamp(cfg.facteurTemperatureMin, cfg.facteurTemperatureMax);

  double facteurHumidite(double humiditePct) =>
      (1 + cfg.coefHumiditeParPct * (humiditePct - cfg.humiditeRefPct)).clamp(
        cfg.facteurHumiditeMin,
        cfg.facteurHumiditeMax,
      );

  double facteurIntensite(double puissanceW) {
    final ref = cfg.intensiteRefPctFtp / 100 * ftpW;
    final f =
        cfg.partFixeIntensite +
        (1 - cfg.partFixeIntensite) * math.max(0.0, puissanceW) / ref;
    return math.max(cfg.facteurIntensiteMin, f);
  }

  /// Taux de sudation (L/h) pour des conditions données.
  double tauxSudationLh(
    double temperatureC,
    double humiditePct,
    double puissanceW,
  ) =>
      cfg.tauxBaseLh *
      facteurTemperature(temperatureC) *
      facteurHumidite(humiditePct) *
      facteurIntensite(puissanceW);

  /// Ajoute [dt] secondes passées à [puissanceW] dans la météo donnée.
  void maj(
    double puissanceW,
    double dt,
    double temperatureC,
    double humiditePct,
  ) {
    if (dt <= 0) return;
    _intensite.ajouter(math.max(0.0, puissanceW), dt);
    final f =
        facteurTemperature(temperatureC) *
        facteurHumidite(humiditePct) *
        facteurIntensite(_intensite.valeur());
    sudationLh = cfg.tauxBaseLh * f;
    final h = dt / 3600;
    perteL += sudationLh * h;
    heuresEquivalentes += f * h;
    objectifL +=
        math.min(sudationLh * cfg.ratioRemplacement, cfg.plafondBoireLh) * h;
  }

  /// Vrai quand le retard a franchi le prochain seuil d'alerte.
  bool get alerteDue => retardMl >= _prochainSeuilMl;

  /// À appeler quand l'alerte « bois » vient d'être envoyée.
  void alerteEmise() =>
      _prochainSeuilMl = prochainMultiple(retardMl, cfg.seuilAlerteMl);

  /// Bouton « j'ai bu ».
  void boit(double ml) {
    buL += ml / 1000;
    _prochainSeuilMl = prochainMultiple(retardMl, cfg.seuilAlerteMl);
  }
}

/// Résultat du mode calibration de la sudation.
class ResultatCalibration {
  const ResultatCalibration({
    required this.perteL,
    required this.tauxMoyenLh,
    required this.nouveauTauxBaseLh,
    required this.pertePoidsPct,
  });

  /// Sueur perdue pendant la sortie (L).
  final double perteL;

  /// Sudation moyenne réelle sur la sortie (L/h).
  final double tauxMoyenLh;

  /// Nouveau taux de base à mettre dans ConfigBoire.tauxBaseLh (L/h),
  /// ramené aux conditions de référence.
  final double nouveauTauxBaseLh;

  /// Poids perdu en % du poids de départ. [LITT] Au-delà de 2 %, la
  /// performance baisse (ACSM, Sawka et al., 2007).
  final double pertePoidsPct;
}

/// Mode calibration : poids avant et après la sortie + ce que tu as bu.
///
/// Sueur perdue = poids perdu + boisson − urine (1 kg ≈ 1 L).
/// Si [heuresEquivalentes] (donné par [Hydratation] pendant la sortie)
/// est fourni, le taux de base est ramené aux conditions de référence.
/// Sinon, on suppose que la sortie s'est faite dans ces conditions.
///
/// ⚠ HYPOTHÈSE : on néglige l'eau perdue en respirant et la masse des
/// glucides et graisses brûlés, ce qui surestime un peu la sueur (de
/// l'ordre de 5 à 10 %). On néglige aussi le poids de ce que tu as
/// mangé, ce qui la sous-estime un peu. Pèse-toi nu, vessie vide, avant
/// et après.
ResultatCalibration calibrerSudation({
  required double poidsAvantKg,
  required double poidsApresKg,
  required double buL,
  double urineL = 0,
  required double dureeH,
  double? heuresEquivalentes,
}) {
  final perte = (poidsAvantKg - poidsApresKg) + buL - urineL;
  final taux = perte / dureeH;
  final base = heuresEquivalentes != null && heuresEquivalentes > 0
      ? perte / heuresEquivalentes
      : taux;
  return ResultatCalibration(
    perteL: perte,
    tauxMoyenLh: taux,
    nouveauTauxBaseLh: base,
    pertePoidsPct: 100 * (poidsAvantKg - poidsApresKg) / poidsAvantKg,
  );
}
