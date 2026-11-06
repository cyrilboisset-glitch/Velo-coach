// Capteurs Bluetooth : puissance + cadence (Cycling Power Service, par
// exemple les pédales Magene P715) et fréquence cardiaque (Heart Rate
// Service). Les capteurs choisis sont gardés et reconnectés tout seuls.
//
// Format des mesures : spécifications Bluetooth SIG « Cycling Power
// Service » (caractéristique 0x2A63) et « Heart Rate Service » (0x2A37).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Guid _servicePuissance = Guid('1818');
final Guid _mesurePuissance = Guid('2a63');
final Guid _serviceCardio = Guid('180d');
final Guid _mesureCardio = Guid('2a37');

enum TypeCapteur { puissance, cardio }

/// Un capteur trouvé pendant la recherche.
class CapteurTrouve {
  const CapteurTrouve(this.id, this.nom, this.type);
  final String id;
  final String nom;
  final TypeCapteur type;
}

/// Lecture d'une mesure de puissance (0x2A63). Renvoie la puissance (W)
/// et, si le capteur l'envoie, le compteur de tours de pédalier et
/// l'instant du dernier tour (1/1024 s).
({int puissanceW, int? tours, int? instant}) lireMesurePuissance(List<int> o) {
  final d = ByteData.sublistView(Uint8List.fromList(o));
  final drapeaux = d.getUint16(0, Endian.little);
  final puissance = d.getInt16(2, Endian.little);
  var i = 4;
  if (drapeaux & 0x01 != 0) i += 1; // équilibre gauche/droite
  if (drapeaux & 0x04 != 0) i += 2; // couple cumulé
  if (drapeaux & 0x10 != 0) i += 6; // tours de roue
  if (drapeaux & 0x20 != 0 && o.length >= i + 4) {
    return (
      puissanceW: puissance,
      tours: d.getUint16(i, Endian.little),
      instant: d.getUint16(i + 2, Endian.little),
    );
  }
  return (puissanceW: puissance, tours: null, instant: null);
}

/// Lecture d'une mesure de fréquence cardiaque (0x2A37).
int lireMesureCardio(List<int> o) {
  if (o[0] & 0x01 == 0) return o[1];
  return o[1] | (o[2] << 8);
}

/// Cadence (tr/min) entre deux mesures successives du compteur de tours.
/// Les compteurs repartent à zéro après 65 535 : on calcule modulo 2^16.
double? cadenceEntre(int tours0, int instant0, int tours1, int instant1) {
  final dTours = (tours1 - tours0) & 0xFFFF;
  final dInstant = (instant1 - instant0) & 0xFFFF;
  if (dInstant == 0) return null;
  return dTours * 60 * 1024 / dInstant;
}

class Capteurs extends ChangeNotifier {
  Capteurs(this._prefs);

  final SharedPreferences _prefs;

  String? get idPuissance => _prefs.getString('capteurPuissance');
  String? get nomPuissance => _prefs.getString('capteurPuissanceNom');
  String? get idCardio => _prefs.getString('capteurCardio');
  String? get nomCardio => _prefs.getString('capteurCardioNom');

  bool connectePuissance = false;
  bool connecteCardio = false;
  bool recherche = false;
  String? erreur;
  final List<CapteurTrouve> trouves = [];

  int? _puissance;
  DateTime? _tPuissance;
  double? _cadence;
  DateTime? _tCadence;
  int? _fc;
  DateTime? _tFc;
  int? _tours;
  int? _instant;
  DateTime? _tDernierTour;

  final List<StreamSubscription<Object?>> _abonnements = [];

  // ---- Valeurs (null si trop vieilles) ------------------------------------

  double? puissanceW(Duration ageMax) =>
      _frais(_tPuissance, ageMax) ? _puissance?.toDouble() : null;
  double? cadenceRpm(Duration ageMax) =>
      _frais(_tCadence, ageMax) ? _cadence : null;
  double? fcBpm(Duration ageMax) =>
      _frais(_tFc, ageMax) ? _fc?.toDouble() : null;

  bool _frais(DateTime? t, Duration ageMax) =>
      t != null && DateTime.now().difference(t) <= ageMax;

  // ---- Recherche ------------------------------------------------------------

  Future<void> chercher() async {
    erreur = null;
    trouves.clear();
    recherche = true;
    notifyListeners();
    try {
      if (await FlutterBluePlus.isSupported == false) {
        throw StateError('Bluetooth absent');
      }
      final sub = FlutterBluePlus.onScanResults.listen((resultats) {
        for (final r in resultats) {
          final services = r.advertisementData.serviceUuids
              .map((g) => g.str128)
              .toSet();
          final type = services.contains(_servicePuissance.str128)
              ? TypeCapteur.puissance
              : services.contains(_serviceCardio.str128)
              ? TypeCapteur.cardio
              : null;
          if (type == null) continue;
          final id = r.device.remoteId.str;
          if (trouves.any((c) => c.id == id)) continue;
          final nom = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : (r.advertisementData.advName.isNotEmpty
                    ? r.advertisementData.advName
                    : id);
          trouves.add(CapteurTrouve(id, nom, type));
          notifyListeners();
        }
      });
      _abonnements.add(sub);
      await FlutterBluePlus.startScan(
        withServices: [_servicePuissance, _serviceCardio],
        timeout: const Duration(seconds: 15),
      );
      await FlutterBluePlus.isScanning.where((s) => !s).first;
      await sub.cancel();
      _abonnements.remove(sub);
    } catch (e) {
      erreur =
          'Recherche impossible : active le Bluetooth et autorise '
          "« Appareils à proximité » pour l'appli. ($e)";
    }
    recherche = false;
    notifyListeners();
  }

  Future<void> choisir(CapteurTrouve c) async {
    if (c.type == TypeCapteur.puissance) {
      await _prefs.setString('capteurPuissance', c.id);
      await _prefs.setString('capteurPuissanceNom', c.nom);
    } else {
      await _prefs.setString('capteurCardio', c.id);
      await _prefs.setString('capteurCardioNom', c.nom);
    }
    notifyListeners();
    await connecter();
  }

  Future<void> oublier(TypeCapteur type) async {
    if (type == TypeCapteur.puissance) {
      await _prefs.remove('capteurPuissance');
      await _prefs.remove('capteurPuissanceNom');
    } else {
      await _prefs.remove('capteurCardio');
      await _prefs.remove('capteurCardioNom');
    }
    await connecter();
  }

  // ---- Connexion ---------------------------------------------------------

  /// Connecte les capteurs choisis. La reconnexion est automatique s'ils
  /// s'éloignent ou s'éteignent (autoConnect).
  Future<void> connecter() async {
    for (final s in _abonnements) {
      await s.cancel();
    }
    _abonnements.clear();
    connectePuissance = false;
    connecteCardio = false;
    notifyListeners();
    final p = idPuissance;
    final c = idCardio;
    if (p != null) await _brancher(p, TypeCapteur.puissance);
    if (c != null) await _brancher(c, TypeCapteur.cardio);
  }

  Future<void> _brancher(String id, TypeCapteur type) async {
    final appareil = BluetoothDevice.fromId(id);
    _abonnements.add(
      appareil.connectionState.listen((etat) async {
        final ok = etat == BluetoothConnectionState.connected;
        if (type == TypeCapteur.puissance) {
          connectePuissance = ok;
        } else {
          connecteCardio = ok;
        }
        notifyListeners();
        if (ok) await _abonner(appareil, type);
      }),
    );
    try {
      await appareil.connect(
        license: License.nonprofit, // usage personnel
        autoConnect: true,
        mtu: null,
      );
    } catch (e) {
      erreur = 'Connexion au capteur impossible : $e';
      notifyListeners();
    }
  }

  Future<void> _abonner(BluetoothDevice appareil, TypeCapteur type) async {
    try {
      final services = await appareil.discoverServices();
      final cible = type == TypeCapteur.puissance
          ? _mesurePuissance.str128
          : _mesureCardio.str128;
      for (final s in services) {
        for (final ch in s.characteristics) {
          if (ch.uuid.str128 != cible) continue;
          final sub = ch.onValueReceived.listen((o) => _mesure(o, type));
          appareil.cancelWhenDisconnected(sub);
          await ch.setNotifyValue(true);
        }
      }
    } catch (e) {
      erreur = 'Lecture du capteur impossible : $e';
      notifyListeners();
    }
  }

  void _mesure(List<int> o, TypeCapteur type) {
    if (o.length < 2) return;
    final maintenant = DateTime.now();
    if (type == TypeCapteur.cardio) {
      _fc = lireMesureCardio(o);
      _tFc = maintenant;
      return;
    }
    if (o.length < 4) return;
    final m = lireMesurePuissance(o);
    _puissance = m.puissanceW;
    _tPuissance = maintenant;
    final tours = m.tours;
    final instant = m.instant;
    if (tours == null || instant == null) return;
    final t0 = _tours;
    final i0 = _instant;
    if (t0 != null && i0 != null && tours != t0) {
      final cad = cadenceEntre(t0, i0, tours, instant);
      if (cad != null && cad < 250) {
        _cadence = cad;
        _tCadence = maintenant;
      }
      _tDernierTour = maintenant;
    } else if (_tDernierTour != null &&
        maintenant.difference(_tDernierTour!) > const Duration(seconds: 3)) {
      // Plus de tour de pédalier depuis 3 s : roue libre.
      _cadence = 0;
      _tCadence = maintenant;
    }
    _tours = tours;
    _instant = instant;
  }

  @override
  void dispose() {
    for (final s in _abonnements) {
      s.cancel();
    }
    super.dispose();
  }
}
