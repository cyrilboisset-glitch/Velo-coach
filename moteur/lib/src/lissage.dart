import 'dart:math' as math;

/// Moyenne glissante exponentielle de constante de temps [tauS].
///
/// Corrigée au démarrage : tant qu'on a peu de données, c'est presque la
/// moyenne simple des valeurs reçues. Pas de faux départ à zéro.
class MoyenneExpo {
  MoyenneExpo(this.tauS);

  final double tauS;
  double _somme = 0;
  double _poids = 0;

  bool get vide => _poids == 0;

  /// Valeur actuelle, ou [defaut] tant qu'aucune donnée n'est arrivée.
  double valeur([double defaut = 0]) => _poids == 0 ? defaut : _somme / _poids;

  /// Ajoute la valeur [x], tenue pendant [dt] secondes.
  void ajouter(double x, double dt) {
    if (dt <= 0) return;
    final a = math.exp(-dt / tauS);
    _somme = _somme * a + x * (1 - a);
    _poids = _poids * a + (1 - a);
  }
}

/// Plus petit multiple de [pas] strictement supérieur à [x] (au moins
/// [pas]). Sert aux alertes répétées : 25, 50, 75 g...
double prochainMultiple(double x, double pas) =>
    pas * math.max(1, (x / pas).floor() + 1);
