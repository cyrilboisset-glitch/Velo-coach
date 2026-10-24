import 'dart:math' as math;

import 'config.dart';
import 'lissage.dart';

/// Joules par kilocalorie.
const double jParKcal = 4184;

/// Fonction 1 : glucides brûlés, objectif d'apport, retard, alertes.
///
/// - Énergie dépensée = travail mécanique / rendement brut.
/// - Glucides brûlés = énergie × part des glucides (selon l'intensité)
///   / 4 kcal par gramme.
/// - Objectif d'apport : on suit les glucides brûlés, mais jamais plus
///   vite que la tolérance (75 g/h). Le plafond s'applique au débit moyen
///   des dernières minutes.
class Ravitaillement {
  Ravitaillement(this.cfg, this.ftpW)
    : _intensite = MoyenneExpo(cfg.lissageIntensiteS),
      _debit = MoyenneExpo(cfg.fenetreDebitS),
      _prochainSeuilG = cfg.seuilAlerteG;

  final ConfigManger cfg;
  final double ftpW;
  final MoyenneExpo _intensite;
  final MoyenneExpo _debit;
  double _prochainSeuilG;

  /// Glucides brûlés depuis le départ (g).
  double brulesG = 0;

  /// Glucides qu'il aurait fallu manger depuis le départ (g).
  double objectifG = 0;

  /// Glucides mangés (et bus) depuis le départ (g).
  double mangesG = 0;

  /// Retard sur l'objectif (g). Négatif = en avance.
  double get retardG => objectifG - mangesG;

  /// Débit de glucides brûlés, moyenne des dernières minutes (g/h).
  double get debitBrulageGh => _debit.valeur();

  /// Débit de l'objectif d'apport, plafonné par la tolérance (g/h).
  double get debitObjectifGh => math.min(debitBrulageGh, cfg.toleranceMaxGh);

  /// Débit de glucides brûlés (g/h) si on tient [puissanceW] longtemps.
  double debitPourPuissanceGh(double puissanceW) =>
      _gParS(puissanceW, cfg.partGlucides(100 * puissanceW / ftpW)) * 3600;

  double _gParS(double puissanceW, double part) => puissanceW <= 0
      ? 0
      : puissanceW / cfg.rendementBrut / jParKcal * part / cfg.kcalParGramme;

  /// Ajoute [dt] secondes passées à [puissanceW].
  void maj(double puissanceW, double dt) {
    if (dt <= 0) return;
    final p = math.max(0.0, puissanceW);
    _intensite.ajouter(p, dt);
    final part = cfg.partGlucides(100 * _intensite.valeur() / ftpW);
    final gParS = _gParS(p, part);
    brulesG += gParS * dt;
    _debit.ajouter(gParS * 3600, dt);
    final debit = _debit.valeur();
    final ratio = debit > cfg.toleranceMaxGh ? cfg.toleranceMaxGh / debit : 1.0;
    objectifG += gParS * dt * ratio;
  }

  /// Vrai quand le retard a franchi le prochain seuil d'alerte.
  bool get alerteDue => retardG >= _prochainSeuilG;

  /// À appeler quand l'alerte « mange » vient d'être envoyée : la
  /// suivante attend le multiple de seuil suivant.
  void alerteEmise() =>
      _prochainSeuilG = prochainMultiple(retardG, cfg.seuilAlerteG);

  /// Bouton « j'ai mangé ».
  void mange(double glucidesG) {
    mangesG += glucidesG;
    _prochainSeuilG = prochainMultiple(retardG, cfg.seuilAlerteG);
  }
}
