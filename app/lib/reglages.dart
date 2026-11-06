// Réglages personnels, saisis une fois et gardés sur le téléphone.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

/// Un produit que l'utilisateur emporte : gel, barre, bonbons…
///
/// [glucidesG] : glucides d'UNE portion (un gel, une barre, un sachet),
/// lus sur l'emballage. Si l'emballage ne donne que les glucides pour
/// 100 g, l'écran les calcule avec le poids de la portion, gardés dans
/// [poidsPortionG] et [glucidesPour100G] pour pouvoir les relire.
class ProduitNutrition {
  const ProduitNutrition({
    required this.nom,
    required this.glucidesG,
    this.poidsPortionG,
    this.glucidesPour100G,
  });

  final String nom;
  final double glucidesG;
  final double? poidsPortionG;
  final double? glucidesPour100G;

  Map<String, Object?> versJson() => {
    'nom': nom,
    'glucidesG': glucidesG,
    'poidsPortionG': poidsPortionG,
    'glucidesPour100G': glucidesPour100G,
  };

  static ProduitNutrition depuisJson(Map<String, dynamic> j) =>
      ProduitNutrition(
        nom: j['nom'] as String,
        glucidesG: (j['glucidesG'] as num).toDouble(),
        poidsPortionG: (j['poidsPortionG'] as num?)?.toDouble(),
        glucidesPour100G: (j['glucidesPour100G'] as num?)?.toDouble(),
      );
}

/// Glucides d'une portion à partir de l'étiquette « pour 100 g ».
double glucidesPortion({
  required double poidsPortionG,
  required double glucidesPour100G,
}) => poidsPortionG * glucidesPour100G / 100;

class Reglages extends ChangeNotifier {
  Reglages(this._prefs);

  final SharedPreferences _prefs;

  // Valeurs par défaut : celles de Cyril (profil Strava, oct. 2026).
  double get poidsKg => _prefs.getDouble('poidsKg') ?? 90;
  double get veloKg => _prefs.getDouble('veloKg') ?? 9;
  double get ftpW => _prefs.getDouble('ftpW') ?? 203;
  double get wPrimeKj => _prefs.getDouble('wPrimeKj') ?? 18;
  bool get voix => _prefs.getBool('voix') ?? true;

  Future<void> enregistrer({
    required double poidsKg,
    required double veloKg,
    required double ftpW,
    required double wPrimeKj,
    required bool voix,
  }) async {
    await _prefs.setDouble('poidsKg', poidsKg);
    await _prefs.setDouble('veloKg', veloKg);
    await _prefs.setDouble('ftpW', ftpW);
    await _prefs.setDouble('wPrimeKj', wPrimeKj);
    await _prefs.setBool('voix', voix);
    notifyListeners();
  }

  // ---- Nutrition ------------------------------------------------------------

  /// Exemples proposés au premier lancement. Les valeurs sont celles
  /// trouvées sur les emballages courants : chacun doit vérifier les
  /// siennes.
  static const List<ProduitNutrition> produitsExemples = [
    ProduitNutrition(
      nom: 'mini-sachet Haribo',
      glucidesG: 7.5,
      poidsPortionG: 9.8,
      glucidesPour100G: 77,
    ),
    ProduitNutrition(nom: 'gel', glucidesG: 25),
    ProduitNutrition(nom: 'barre de céréales', glucidesG: 20),
  ];

  List<ProduitNutrition> get produits {
    final texte = _prefs.getString('produits');
    if (texte == null) return produitsExemples;
    try {
      return [
        for (final j in jsonDecode(texte) as List<dynamic>)
          ProduitNutrition.depuisJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return produitsExemples;
    }
  }

  /// Produit utilisé pendant la sortie (celui des alertes « Mange 1 … »).
  int get indexProduit =>
      (_prefs.getInt('produitChoisi') ?? 0).clamp(0, produits.length - 1);

  ProduitNutrition get produitChoisi => produits[indexProduit];

  /// Glucides à manger par heure. 20 g/h : choix de Cyril (sortie
  /// tranquille, garder des forces sur la longueur).
  double get objectifGh => _prefs.getDouble('objectifGh') ?? 20;

  /// Glucides de la boisson, pour 1 L (0 = eau plate).
  double get boissonGParL => _prefs.getDouble('boissonGParL') ?? 0;

  Future<void> enregistrerNutrition({
    required List<ProduitNutrition> produits,
    required int indexProduit,
    required double objectifGh,
    required double boissonGParL,
  }) async {
    await _prefs.setString(
      'produits',
      jsonEncode([for (final p in produits) p.versJson()]),
    );
    await _prefs.setInt('produitChoisi', indexProduit);
    await _prefs.setDouble('objectifGh', objectifGh);
    await _prefs.setDouble('boissonGParL', boissonGParL);
    notifyListeners();
  }

  /// Configuration du moteur pour la sortie : une alerte « Mange 1 … »
  /// chaque fois que le retard atteint une portion du produit choisi, au
  /// rythme de l'objectif en g/h ; rappel d'eau tous les 150 ml.
  Config config() {
    final p = produitChoisi;
    return Config(
      cycliste: ConfigCycliste(
        poidsCyclisteKg: poidsKg,
        poidsVeloKg: veloKg,
        ftpW: ftpW,
      ),
      wbal: ConfigWbal(wPrimeJ: wPrimeKj * 1000),
      manger: ConfigManger(
        toleranceMaxGh: objectifGh,
        seuilAlerteG: p.glucidesG,
        aliments: [Aliment(p.nom, p.glucidesG)],
        glucidesParLitreBoisson: boissonGParL,
      ),
      boire: const ConfigBoire(
        seuilAlerteMl: gorgeesMl,
        boissons: [Boisson('Gorgées', gorgeesMl)],
      ),
    );
  }

  /// Quantité bue à chaque rappel « bois ».
  static const double gorgeesMl = 150;
}
