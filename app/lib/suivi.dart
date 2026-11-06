// Suivi en direct (repris de l'appli « Suivi direct ») : envoie la
// position à Firebase pour que la page de suivi l'affiche sur une carte.
// Le GPS est lu par la sortie (sortie.dart) qui transmet ici une position
// toutes les 10 s. Les positions non envoyées (pas de réseau) restent en
// attente et partent toutes ensemble au prochain envoi réussi.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config_appli.dart';
import 'firebase_rest.dart';

class Suivi extends ChangeNotifier {
  Suivi(this._prefs) : _firebase = FirebaseRest(_prefs);

  final SharedPreferences _prefs;
  final FirebaseRest _firebase;

  bool actif = false;
  String? erreur;
  String? info;
  DateTime? dernierEnvoi;

  /// Partager sa position pendant les sorties (réglage gardé).
  bool get partage => _prefs.getBool('partage') ?? true;
  set partage(bool v) {
    _prefs.setBool('partage', v);
    notifyListeners();
  }

  int get pointsEnAttente =>
      _attente.keys.where((k) => k.startsWith('points/')).length;

  final Map<String, Object> _attente = {}; // chemin -> valeur, un seul PATCH
  bool _envoiEnCours = false;
  DateTime? _derniereTransmise;

  // ---- Lien permanent ------------------------------------------------------

  /// Identifiant du suivi : le même à chaque sortie, donc un seul lien à
  /// envoyer. 24 caractères aléatoires : impossible à deviner. Gardé de
  /// l'appli Suivi direct (même identifiant Android, mêmes réglages).
  String get canal {
    var c = _prefs.getString('canal');
    if (c == null) {
      c = _nouveauCanal();
      _prefs.setString('canal', c);
    }
    return c;
  }

  String get lienPage => '$urlPageSuivi?c=$canal';

  static String _nouveauCanal() {
    const alphabet =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(
      24,
      (_) => alphabet[r.nextInt(alphabet.length)],
    ).join();
  }

  /// Nouveau lien ; l'ancien est effacé de la base et ne marche plus.
  Future<void> changerDeLien() async {
    if (actif) return;
    final ancien = _prefs.getString('canal');
    await _prefs.setString('canal', _nouveauCanal());
    info = 'Nouveau lien créé : pense à le renvoyer.';
    notifyListeners();
    if (ancien != null) {
      try {
        await _firebase.envoyer('DELETE', 'suivis/$ancien', null);
      } catch (_) {
        // Pas grave : l'ancien suivi restera simplement figé
      }
    }
  }

  // ---- Démarrer / arrêter -------------------------------------------------

  Future<void> demarrer() async {
    if (actif) return;
    erreur = null;
    info = null;
    final maintenant = DateTime.now();
    try {
      try {
        await _ouvrirSuivi(maintenant);
      } on ErreurSuivi catch (e) {
        // 401 : ce lien appartient à un autre identifiant (appli
        // réinstallée…). On en crée un nouveau.
        if (e.code != 401) rethrow;
        await _prefs.setString('canal', _nouveauCanal());
        await _ouvrirSuivi(maintenant);
        info = 'Le lien a changé : renvoie le nouveau lien.';
      }
      dernierEnvoi = null;
      _derniereTransmise = null;
      _attente.clear();
      actif = true;
    } catch (e) {
      erreur =
          'Suivi en direct indisponible : '
          '${e is ErreurSuivi ? e.message : e}';
    }
    notifyListeners();
  }

  Future<void> _ouvrirSuivi(DateTime maintenant) async {
    await _firebase.jeton();
    // PUT : remplace entièrement le suivi précédent (trace effacée)
    await _firebase.envoyer('PUT', 'suivis/$canal', {
      'proprietaire': _firebase.uid,
      'debut': maintenant.millisecondsSinceEpoch,
      'maj': maintenant.millisecondsSinceEpoch,
      'distanceM': 0,
    });
  }

  Future<void> arreter() async {
    if (!actif) return;
    actif = false;
    final fin = DateTime.now().millisecondsSinceEpoch;
    _attente['fin'] = fin;
    _attente['maj'] = fin;
    notifyListeners();
    // On insiste un peu pour que la fin de sortie parte bien
    for (var essai = 0; essai < 5 && _attente.containsKey('fin'); essai++) {
      if (essai > 0) await Future<void>.delayed(const Duration(seconds: 3));
      await _vider();
    }
    if (_attente.containsKey('fin')) {
      erreur = "La fin de sortie n'a pas pu être envoyée (pas de réseau ?).";
      notifyListeners();
    }
  }

  // ---- Positions ------------------------------------------------------------

  /// Reçoit chaque position GPS de la sortie ; n'en transmet qu'une toutes
  /// les [intervalleSuivi].
  void position(Position p, double distanceM) {
    if (!actif) return;
    final avant = _derniereTransmise;
    if (avant != null && p.timestamp.difference(avant) < intervalleSuivi) {
      return;
    }
    _derniereTransmise = p.timestamp;
    final t = p.timestamp.millisecondsSinceEpoch;
    final la = _arrondi(p.latitude, 6);
    final lo = _arrondi(p.longitude, 6);
    _attente['points/$t'] = {'la': la, 'lo': lo};
    _attente['dernier'] = {
      'la': la,
      'lo': lo,
      't': t,
      'v': _arrondi(p.speed < 0 ? 0 : p.speed, 1),
      'p': p.accuracy.round(),
      'al': p.altitude.round(),
    };
    _attente['distanceM'] = distanceM.round();
    _attente['maj'] = t;
    _vider();
  }

  static double _arrondi(double v, int decimales) {
    final f = pow(10, decimales);
    return (v * f).roundToDouble() / f;
  }

  // ---- Envoi ----------------------------------------------------------------

  Future<void> _vider() async {
    if (_envoiEnCours || _attente.isEmpty) return;
    _envoiEnCours = true;
    final lot = Map<String, Object>.from(_attente);
    var reussi = false;
    try {
      await _firebase.envoyer('PATCH', 'suivis/$canal', lot);
      // On ne retire que ce qui est parti (une valeur plus récente reste)
      lot.forEach((cle, valeur) {
        if (identical(_attente[cle], valeur)) _attente.remove(cle);
      });
      dernierEnvoi = DateTime.now();
      erreur = null;
      reussi = true;
    } catch (e) {
      erreur =
          'Envoi en attente (réseau ?) : '
          '${e is ErreurSuivi ? e.message : e}';
    } finally {
      _envoiEnCours = false;
      notifyListeners();
    }
    // Des positions sont arrivées pendant l'envoi : on les envoie aussi
    if (reussi && _attente.isNotEmpty) unawaited(_vider());
  }
}
