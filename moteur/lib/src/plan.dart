import 'dart:math' as math;

import 'config.dart';
import 'hydratation.dart';
import 'parcours.dart';
import 'physique.dart';

/// Repère de glucides (g/h) selon la durée de la sortie.
///
/// [LITT] Jeukendrup (2014, Sports Medicine) : 30 à 75 min, rien ou
/// rinçage de bouche ; 1 à 2 h, 30 g/h ; 2 à 3 h, 60 g/h ; plus de
/// 2 h 30, jusqu'à 90 g/h (avec un mélange glucose + fructose). Repères
/// pour sportifs entraînés, à adapter : ce n'est pas l'objectif choisi
/// par l'utilisateur, seulement une référence à lui montrer.
double repereGlucidesGh(double dureeS) {
  if (dureeS < 4500) return 0;
  if (dureeS < 7200) return 30;
  if (dureeS < 9000) return 60;
  return 90;
}

/// Durée estimée (s) pour parcourir [parcours] à [pctFtp] % de FTP.
///
/// [CHOIX] 65 % de FTP : allure d'endurance, proche de ce que roule
/// Cyril en sortie (136 W de moyenne pour une FTP de 203 W, soit 67 %).
/// ⚠ HYPOTHÈSE : modèle physique en vitesse stable, sans arrêts ni
/// groupe ; la durée réelle est en général plus longue (arrêts).
double estimerDureeParcoursS(
  Parcours parcours,
  Config cfg,
  Meteo meteo, {
  double pctFtp = 65,
}) => dureeSegments(
  parcours.segments,
  pctFtp / 100 * cfg.cycliste.ftpW,
  ConditionsRoulage.depuis(cfg, meteo),
);

/// Ce qu'il faut prévoir avant le départ.
class PlanSortie {
  const PlanSortie({
    required this.dureeS,
    required this.glucidesNecessaires,
    required this.glucidesTotalG,
    required this.portions,
    required this.repereGh,
    required this.eauSueurL,
    required this.eauABoireL,
    required this.perteSansBoirePct,
    required this.perteAvecPlanPct,
    required this.eauAvantDepartMlMin,
    required this.eauAvantDepartMlMax,
    this.sodiumMgH,
  });

  final double dureeS;

  /// Faux pour une sortie de moins de 1 h 15 : de l'eau seulement.
  final bool glucidesNecessaires;
  final double glucidesTotalG;

  /// Portions à emporter, marge comprise.
  final int portions;

  /// Repère de la littérature pour cette durée (g/h), à titre indicatif.
  final double repereGh;

  /// Sueur estimée sur toute la sortie (L).
  final double eauSueurL;

  /// Eau à boire pendant la sortie (L) pour rester sous la perte tolérée.
  final double eauABoireL;

  /// Perte de poids estimée si on ne boit pas / si on suit le plan (%).
  final double perteSansBoirePct;
  final double perteAvecPlanPct;

  /// Eau à boire dans les 4 h avant le départ : 5 à 10 ml par kg.
  final double eauAvantDepartMlMin;
  final double eauAvantDepartMlMax;

  /// Sodium apporté par la boisson (mg/h), si la boisson en contient.
  final double? sodiumMgH;

  /// Eau qu'il manque (L) si on emporte [emporteeL] litres. 0 si assez.
  double eauManquanteL(double emporteeL) =>
      math.max(0.0, eauABoireL - emporteeL);
}

/// Prépare la sortie : durée, glucides à emporter, eau à boire.
///
/// - Glucides : objectif (g/h) × durée, moins les 40 premières minutes ;
///   aucun sous 1 h 15. Portions arrondies au-dessus, plus la marge.
/// - Eau : plan des 2 % (voir [Hydratation.ratioPlan]) avec la sueur
///   prévue pour la météo donnée, à [pctFtp] % de FTP.
/// - Avant le départ : 5 à 10 ml/kg d'eau dans les 4 h précédentes
///   (Thomas et al., 2016, Med Sci Sports Exerc).
PlanSortie planifierSortie({
  required Config cfg,
  required double dureeS,
  required Meteo meteo,
  required double portionG,
  double pctFtp = 65,
  double sodiumMgParL = 0,
  int margePortions = 1,
}) {
  final cm = cfg.manger;
  final cb = cfg.boire;
  final poids = cfg.cycliste.poidsCyclisteKg;
  final h = dureeS / 3600;

  // Glucides
  final necessaires = dureeS >= cm.dureeMinGlucidesS;
  final totalG = necessaires
      ? cm.toleranceMaxGh * math.max(0.0, dureeS - cm.premierePriseS) / 3600
      : 0.0;
  final portions = totalG <= 0 || portionG <= 0
      ? 0
      : (totalG / portionG).ceil() + margePortions;

  // Eau
  final hydratation = Hydratation(
    cb,
    cfg.cycliste.ftpW,
    poidsKg: poids,
    dureePrevueS: dureeS,
  );
  final tauxLh = hydratation.tauxSudationLh(
    meteo.temperatureC,
    meteo.humiditePct,
    pctFtp / 100 * cfg.cycliste.ftpW,
  );
  final sueurL = tauxLh * h;
  final toleree = cb.perteMaxPctPoids <= 0
      ? 0.0
      : cb.perteMaxPctPoids / 100 * poids;
  final ratio = sueurL <= 0
      ? 0.0
      : ((sueurL - toleree) / sueurL).clamp(
          cb.ratioRemplacementMin,
          cb.ratioRemplacement,
        );
  final aBoireL = math.min(sueurL * ratio, cb.plafondBoireLh * h);

  return PlanSortie(
    dureeS: dureeS,
    glucidesNecessaires: necessaires,
    glucidesTotalG: totalG,
    portions: portions,
    repereGh: repereGlucidesGh(dureeS),
    eauSueurL: sueurL,
    eauABoireL: aBoireL,
    perteSansBoirePct: poids <= 0 ? 0 : 100 * sueurL / poids,
    perteAvecPlanPct: poids <= 0 ? 0 : 100 * (sueurL - aBoireL) / poids,
    eauAvantDepartMlMin: 5 * poids,
    eauAvantDepartMlMax: 10 * poids,
    sodiumMgH: sodiumMgParL > 0 && h > 0 ? aBoireL / h * sodiumMgParL : null,
  );
}
