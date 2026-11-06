// Réglages personnels, saisis une fois et gardés sur le téléphone.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

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

  /// Configuration du moteur pour la sortie.
  ///
  /// Décisions de Cyril appliquées ici en attendant l'adaptation du
  /// moteur : 20 g/h de glucides (un mini-sachet Haribo de 7,5 g toutes
  /// les 20 à 25 min), rappel d'eau tous les 150 ml.
  Config config() => Config(
    cycliste: ConfigCycliste(
      poidsCyclisteKg: poidsKg,
      poidsVeloKg: veloKg,
      ftpW: ftpW,
    ),
    wbal: ConfigWbal(wPrimeJ: wPrimeKj * 1000),
    manger: const ConfigManger(
      toleranceMaxGh: 20,
      seuilAlerteG: sachetG,
      aliments: [Aliment('Sachet', sachetG)],
    ),
    boire: const ConfigBoire(
      seuilAlerteMl: gorgeesMl,
      boissons: [Boisson('Gorgées', gorgeesMl)],
    ),
  );

  /// Mini-sachet Haribo Goldbären : 9,8 g, dont 7,5 g de glucides.
  static const double sachetG = 7.5;

  /// Quantité bue à chaque rappel « bois ».
  static const double gorgeesMl = 150;
}
