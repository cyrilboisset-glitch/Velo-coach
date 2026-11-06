// Accès à Firebase par son interface web (REST), sans les bibliothèques
// Firebase : connexion anonyme + écriture dans la base temps réel.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config_appli.dart';

class ErreurSuivi implements Exception {
  const ErreurSuivi(this.message, {this.code});
  final String message;
  final int? code;

  @override
  String toString() => message;
}

class FirebaseRest {
  FirebaseRest(this._prefs);

  final SharedPreferences _prefs;
  final http.Client _client = http.Client();

  String? _jeton;
  DateTime _expiration = DateTime.fromMillisecondsSinceEpoch(0);

  /// Identifiant anonyme du téléphone (propriétaire du suivi).
  String? get uid => _prefs.getString('uid');

  /// Jeton d'accès valide (connexion anonyme la première fois, puis
  /// renouvellement : le téléphone garde toujours le même identifiant).
  Future<String> jeton() async {
    final actuel = _jeton;
    if (actuel != null && DateTime.now().isBefore(_expiration)) return actuel;
    final renouvellement = _prefs.getString('refreshToken');
    if (renouvellement == null) {
      await _inscrireAnonyme();
    } else {
      await _renouveler(renouvellement);
    }
    return _jeton!;
  }

  Future<void> _inscrireAnonyme() async {
    final rep = await _client
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$cleApiFirebase',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'returnSecureToken': true}),
        )
        .timeout(delaiReseau);
    if (rep.statusCode != 200) {
      throw ErreurSuivi(
        'Connexion à Firebase refusée (${rep.statusCode}). La connexion anonyme est-elle activée ?',
        code: rep.statusCode,
      );
    }
    final j = jsonDecode(rep.body) as Map<String, dynamic>;
    await _prefs.setString('uid', j['localId'] as String);
    await _prefs.setString('refreshToken', j['refreshToken'] as String);
    _memoriser(j['idToken'] as String, j['expiresIn']);
  }

  Future<void> _renouveler(String renouvellement) async {
    final rep = await _client
        .post(
          Uri.parse(
            'https://securetoken.googleapis.com/v1/token?key=$cleApiFirebase',
          ),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': renouvellement,
          },
        )
        .timeout(delaiReseau);
    if (rep.statusCode != 200) {
      throw ErreurSuivi(
        'Renouvellement de la connexion refusé (${rep.statusCode}).',
        code: rep.statusCode,
      );
    }
    final j = jsonDecode(rep.body) as Map<String, dynamic>;
    await _prefs.setString('refreshToken', j['refresh_token'] as String);
    await _prefs.setString('uid', j['user_id'] as String);
    _memoriser(j['id_token'] as String, j['expires_in']);
  }

  void _memoriser(String jeton, Object? expireDansS) {
    final secondes = int.tryParse('$expireDansS') ?? 3600;
    _jeton = jeton;
    // Marge de 5 min pour ne jamais envoyer un jeton tout juste expiré
    _expiration = DateTime.now().add(Duration(seconds: secondes - 300));
  }

  /// Requête sur la base : `methode` = PUT, PATCH ou DELETE ;
  /// `chemin` sans « .json », par exemple « suivis/abc ».
  Future<void> envoyer(String methode, String chemin, Object? corps) async {
    for (var essai = 0; essai < 2; essai++) {
      final uri = Uri.parse('$urlBase/$chemin.json?auth=${await jeton()}');
      final requete = http.Request(methode, uri);
      if (corps != null) {
        requete.headers['Content-Type'] = 'application/json';
        requete.body = jsonEncode(corps);
      }
      final flux = await _client.send(requete).timeout(delaiReseau);
      final rep = await http.Response.fromStream(flux).timeout(delaiReseau);
      if (rep.statusCode == 200 || rep.statusCode == 204) return;
      if (rep.statusCode == 401 && essai == 0) {
        _jeton = null; // jeton peut-être expiré : on renouvelle et on réessaie
        continue;
      }
      throw ErreurSuivi(
        'Envoi refusé par Firebase (${rep.statusCode}).',
        code: rep.statusCode,
      );
    }
  }
}
