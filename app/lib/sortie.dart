// Une sortie : GPS (avec service de premier plan, écran éteint), capteurs,
// coach une fois par seconde, météo toutes les 10 min, suivi en direct,
// alertes, journal.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

import 'annonces.dart';
import 'capteurs.dart';
import 'config_appli.dart';
import 'meteo.dart';
import 'reglages.dart';
import 'suivi.dart';

class ErreurSortie implements Exception {
  const ErreurSortie(this.message);
  final String message;
  @override
  String toString() => message;
}

class Sortie extends ChangeNotifier {
  Sortie({
    required this.reglages,
    required this.capteurs,
    required this.suivi,
    required this.annonces,
  });

  final Reglages reglages;
  final Capteurs capteurs;
  final Suivi suivi;
  final Annonces annonces;

  /// Parcours prévu (GPX importé), ou null.
  Parcours? parcours;
  String? nomParcours;

  bool active = false;
  bool demarrage = false;
  String? erreur;
  DateTime? debut;
  Coach? coach;
  Position? derniere;
  double distanceM = 0;
  Alerte? derniereAlerte;
  final List<Alerte> alertes = [];

  /// Puissance moyenne sur 3 s (affichage).
  double? puissance3sW;

  /// Dernier journal écrit (chemin du fichier), après la sortie.
  String? journal;

  StreamSubscription<Position>? _gps;
  Timer? _seconde;
  Timer? _meteo;
  Timer? _fin;
  Calage? _calage;
  Position? _repereDistance;
  final List<double> _dernieresPuissances = [];
  final StringBuffer _lignes = StringBuffer();

  Duration get duree =>
      debut == null ? Duration.zero : DateTime.now().difference(debut!);

  /// Distance sur le parcours (GPX) si on est calé dessus.
  double? get distanceParcoursM => positionSimuleeM ?? _calage?.derniereM;

  /// Pour les captures d'écran et les tests : position imposée.
  @visibleForTesting
  double? positionSimuleeM;

  double? get resteParcoursM {
    final p = parcours;
    final d = distanceParcoursM;
    return p == null || d == null ? null : p.longueurM - d;
  }

  void choisirParcours(Parcours? p, String? nom) {
    if (active) return;
    parcours = p;
    nomParcours = nom;
    notifyListeners();
  }

  // ---- Démarrer / arrêter -------------------------------------------------

  Future<void> demarrer() async {
    if (active || demarrage) return;
    erreur = null;
    journal = null;
    demarrage = true;
    notifyListeners();
    try {
      await _verifierAutorisations();
      await annonces.preparer(voix: reglages.voix);
      final cfg = reglages.config();
      coach = Coach(cfg, parcours: parcours);
      _calage = parcours == null ? null : Calage(parcours!);
      debut = DateTime.now();
      distanceM = 0;
      derniere = null;
      derniereAlerte = null;
      alertes.clear();
      _repereDistance = null;
      _dernieresPuissances.clear();
      _lignes
        ..clear()
        ..writeln(
          't_s;km_gps;km_parcours;puissance_w;cadence_rpm;fc_bpm;cible_w;'
          'wbal_pct;glucides_retard_g;eau_retard_ml;alerte',
        );
      _gps = Geolocator.getPositionStream(locationSettings: _reglagesGps())
          .listen(
            _surPosition,
            onError: (Object e) {
              erreur = 'GPS : $e';
              notifyListeners();
            },
          );
      _seconde = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _meteo = Timer.periodic(intervalleMeteo, (_) => _majMeteo());
      _fin = Timer(dureeMaxSuivi, arreter);
      active = true;
      if (suivi.partage) unawaited(suivi.demarrer());
    } catch (e) {
      erreur = e is ErreurSortie ? e.message : 'Démarrage impossible : $e';
    }
    demarrage = false;
    notifyListeners();
  }

  Future<void> arreter() async {
    if (!active) return;
    active = false;
    await _gps?.cancel();
    _gps = null;
    _seconde?.cancel();
    _meteo?.cancel();
    _fin?.cancel();
    notifyListeners();
    await _ecrireJournal();
    notifyListeners();
    await suivi.arreter();
  }

  Future<void> _verifierAutorisations() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ErreurSortie(
        'La localisation du téléphone est coupée : active-la puis réessaie.',
      );
    }
    var autorisation = await Geolocator.checkPermission();
    if (autorisation == LocationPermission.denied) {
      autorisation = await Geolocator.requestPermission();
    }
    if (autorisation == LocationPermission.denied ||
        autorisation == LocationPermission.deniedForever) {
      throw const ErreurSortie(
        "L'appli a besoin de la localisation : autorise-la dans les "
        "réglages de l'appli.",
      );
    }
  }

  LocationSettings _reglagesGps() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: intervalleGps,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Vélo Coach : sortie en cours',
          notificationText: "Ouvre l'appli pour voir les chiffres ou arrêter.",
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }

  // ---- GPS ----------------------------------------------------------------

  void _surPosition(Position p) {
    if (p.accuracy > precisionMaxM) return;
    // Distance : on n'avance le repère que si on a vraiment bougé, pour ne
    // pas additionner le bruit du GPS à l'arrêt (repris de Suivi direct)
    final repere = _repereDistance;
    if (repere == null) {
      _repereDistance = p;
      if (derniere == null) unawaited(_majMeteoA(p));
    } else {
      final d = Geolocator.distanceBetween(
        repere.latitude,
        repere.longitude,
        p.latitude,
        p.longitude,
      );
      if (d >= (p.accuracy / 2).clamp(3.0, 25.0)) {
        distanceM += d;
        _repereDistance = p;
      }
    }
    derniere = p;
    _calage?.caler(p.latitude, p.longitude);
    suivi.position(p, distanceM);
  }

  // ---- Coach, une fois par seconde ----------------------------------------

  void _tick() {
    final c = coach;
    if (c == null || !active) return;
    final t = duree.inMilliseconds / 1000;
    final p = capteurs.puissanceW(ageMaxCapteur);
    _dernieresPuissances.add(p ?? 0);
    if (_dernieresPuissances.length > 3) _dernieresPuissances.removeAt(0);
    puissance3sW = p == null
        ? null
        : _dernieresPuissances.reduce((a, b) => a + b) /
              _dernieresPuissances.length;
    final cad = capteurs.cadenceRpm(ageMaxCapteur);
    final fc = capteurs.fcBpm(ageMaxCapteur);
    final nouvelles = c.tick(
      Echantillon(
        t: t,
        puissanceW: p,
        cadenceRpm: cad,
        fcBpm: fc,
        vitesseMs: derniere?.speed,
        distanceParcoursM: _calage?.derniereM,
      ),
    );
    for (final a in nouvelles) {
      // Pas de bouton sur le vélo : une alerte est comptée comme faite.
      switch (a.code) {
        case 'manger':
        case 'manger_avant_col':
          c.mangeAliment(c.cfg.manger.aliments.first);
        case 'boire':
          c.boitBoisson(c.cfg.boire.boissons.first);
      }
      derniereAlerte = a;
      alertes.add(a);
      unawaited(annonces.annoncer(a));
    }
    final e = c.etat;
    String f(double? x, [int dec = 0]) =>
        x == null ? '' : x.toStringAsFixed(dec).replaceAll('.', ',');
    _lignes.writeln(
      [
        f(t),
        f(distanceM / 1000, 3),
        f(_calage?.derniereM == null ? null : _calage!.derniereM! / 1000, 3),
        f(p),
        f(cad),
        f(fc),
        f(e.puissanceCibleW),
        f(e.wbalPct, 1),
        f(e.glucidesRetardG, 1),
        f(e.eauRetardMl),
        nouvelles.isEmpty ? '' : '"${nouvelles.first.texte}"',
      ].join(';'),
    );
    notifyListeners();
  }

  // ---- Météo ---------------------------------------------------------------

  Future<void> _majMeteo() async {
    final p = derniere;
    if (p != null) await _majMeteoA(p);
  }

  Future<void> _majMeteoA(Position p) async {
    final m = await lireMeteo(p.latitude, p.longitude);
    final c = coach;
    if (m != null && c != null) c.meteo = m;
  }

  // ---- Journal -------------------------------------------------------------

  Future<void> _ecrireJournal() async {
    try {
      final dossier = await getApplicationDocumentsDirectory();
      final d = debut ?? DateTime.now();
      String deux(int n) => n.toString().padLeft(2, '0');
      final nom =
          'sortie_${d.year}-${deux(d.month)}-${deux(d.day)}_'
          '${deux(d.hour)}h${deux(d.minute)}.csv';
      final f = File('${dossier.path}/$nom');
      await f.writeAsString(_lignes.toString());
      journal = f.path;
    } catch (e) {
      erreur = "Journal non enregistré : $e";
    }
  }

  @override
  void dispose() {
    _gps?.cancel();
    _seconde?.cancel();
    _meteo?.cancel();
    _fin?.cancel();
    super.dispose();
  }
}
