import 'package:velo_coach_moteur/velo_coach_moteur.dart';

/// Simule une sortie seconde par seconde sur le parcours du coach.
///
/// La vitesse vient du modèle physique du moteur, la puissance de
/// [puissance] (qui peut lire l'état du coach, par exemple pour suivre la
/// cible en montée). [chaqueSeconde] est appelé après chaque mesure.
/// Renvoie toutes les alertes émises.
List<Alerte> simuler(
  Coach coach, {
  required double dureeMaxS,
  required double Function(Coach c, double t, double d) puissance,
  void Function(Coach c, double t, double d, List<Alerte> a)? chaqueSeconde,
}) {
  final parcours = coach.parcours!;
  final cond = ConditionsRoulage.depuis(coach.cfg, coach.meteo);
  final alertes = <Alerte>[];
  var d = 0.0;
  for (var t = 0.0; t <= dureeMaxS && d < parcours.longueurM; t += 1) {
    final p = puissance(coach, t, d);
    final a = coach.tick(
      Echantillon(t: t, puissanceW: p, distanceParcoursM: d),
    );
    alertes.addAll(a);
    chaqueSeconde?.call(coach, t, d, a);
    d += vitessePourPuissance(p, parcours.segmentA(d), cond);
  }
  return alertes;
}

/// Rouler [dureeS] secondes à puissance constante, sans parcours.
void rouler(Coach coach, double depuisS, double dureeS, double puissanceW) {
  for (var t = depuisS; t < depuisS + dureeS; t += 1) {
    coach.tick(Echantillon(t: t, puissanceW: puissanceW));
  }
}
