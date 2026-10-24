import 'alertes.dart';
import 'calage.dart';
import 'coach.dart';
import 'config.dart';
import 'enregistrement.dart';
import 'parcours.dart';
import 'physique.dart';

/// Ce que fait le cycliste virtuel quand une alerte sort.
enum Prises {
  /// Rien : on voit quand les alertes seraient sorties sans jamais manger
  /// ni boire.
  aucune,

  /// Il obéit : un gel à chaque « mange », une barre avant un col, un
  /// demi-bidon à chaque « bois ».
  conseils,
}

/// Une ligne du journal de simulation (une par mesure).
class LigneJournal {
  const LigneJournal({
    required this.t,
    required this.distanceM,
    required this.altitudeM,
    required this.puissanceW,
    required this.fcBpm,
    required this.etat,
    this.alerte,
    this.prise,
  });

  final double t;
  final double? distanceM;
  final double? altitudeM;
  final double puissanceW;
  final double? fcBpm;
  final EtatCoach etat;
  final Alerte? alerte;

  /// Ce que le cycliste virtuel a mangé ou bu à cet instant.
  final String? prise;
}

/// Comparaison prévu / réel pour une montée de la sortie.
class BilanMontee {
  const BilanMontee({
    required this.montee,
    required this.cibleAnnonceeW,
    required this.puissanceReelleW,
    required this.dureeReelleS,
    required this.dureePreditePuissanceReelleS,
    required this.wbalSommetPct,
  });

  final Montee montee;

  /// Première cible donnée dans la montée (ou à son annonce).
  final double? cibleAnnonceeW;

  /// Puissance moyenne réellement tenue entre le pied et le sommet.
  final double puissanceReelleW;
  final double dureeReelleS;

  /// Durée que le modèle physique prévoit à la puissance réelle : à
  /// comparer à la durée réelle pour vérifier CdA, Crr, poids, vent.
  final double dureePreditePuissanceReelleS;

  /// Réserve W'bal au sommet, telle que calculée pendant le rejeu.
  final double wbalSommetPct;
}

class ResultatSimulation {
  const ResultatSimulation({
    required this.parcours,
    required this.coach,
    required this.lignes,
    required this.montees,
    required this.pointsHorsParcours,
  });

  final Parcours parcours;
  final Coach coach;
  final List<LigneJournal> lignes;
  final List<BilanMontee> montees;

  /// Mesures dont la position n'a pas pu être calée sur le parcours.
  final int pointsHorsParcours;

  List<Alerte> get alertes => [
    for (final l in lignes)
      if (l.alerte != null) l.alerte!,
  ];

  /// Journal CSV (points-virgules, virgule décimale) : une ligne par
  /// mesure, avec l'état du coach, les alertes et les prises.
  String journalCsv() {
    String f(double? x, int dec) =>
        x == null ? '' : x.toStringAsFixed(dec).replaceAll('.', ',');
    String txt(String? s) => s == null ? '' : '"${s.replaceAll('"', "'")}"';
    final b = StringBuffer()
      ..writeln(
        [
          't_s',
          'km',
          'altitude_m',
          'puissance_w',
          'fc_bpm',
          'cible_w',
          'wbal_pct',
          'cp_eff_w',
          'travail_kj',
          'glucides_brules_g',
          'glucides_manges_g',
          'glucides_retard_g',
          'eau_perdue_l',
          'eau_bue_l',
          'eau_retard_ml',
          'alerte_code',
          'alerte_texte',
          'prise',
        ].join(';'),
      );
    for (final l in lignes) {
      final e = l.etat;
      b.writeln(
        [
          f(l.t, 0),
          f(l.distanceM == null ? null : l.distanceM! / 1000, 3),
          f(l.altitudeM, 1),
          f(l.puissanceW, 0),
          f(l.fcBpm, 0),
          f(e.puissanceCibleW, 0),
          f(e.wbalPct, 1),
          f(e.cpEffW, 1),
          f(e.travailKj, 1),
          f(e.glucidesBrulesG, 1),
          f(e.glucidesMangesG, 1),
          f(e.glucidesRetardG, 1),
          f(e.eauPerdueL, 3),
          f(e.eauBueL, 3),
          f(e.eauRetardMl, 0),
          l.alerte?.code ?? '',
          txt(l.alerte?.texte),
          txt(l.prise),
        ].join(';'),
      );
    }
    return b.toString();
  }
}

/// Rejoue une sortie enregistrée dans le moteur, mesure par mesure.
///
/// La position GPS est calée sur [parcours] ; la température vient de la
/// sortie si elle est enregistrée. L'humidité et le vent ne sont pas
/// enregistrés : on prend les valeurs données (par défaut 50 %, pas de
/// vent).
ResultatSimulation simulerSortie({
  required Enregistrement sortie,
  required Parcours parcours,
  required Config cfg,
  Prises prises = Prises.conseils,
  double humiditePct = 50,
  double ventMs = 0,
  double ventVientDeDeg = 0,
}) {
  final coach = Coach(
    cfg,
    parcours: parcours,
    meteo: Meteo(
      temperatureC: cfg.physique.temperatureDefautC,
      humiditePct: humiditePct,
      ventMs: ventMs,
      ventVientDeDeg: ventVientDeDeg,
    ),
  );
  final calage = Calage(parcours);
  final lignes = <LigneJournal>[];
  var horsParcours = 0;
  final t0 = sortie.points.isEmpty ? 0.0 : sortie.points.first.t;

  for (final p in sortie.points) {
    if (p.temperatureC != null && p.temperatureC != coach.meteo.temperatureC) {
      coach.meteo = Meteo(
        temperatureC: p.temperatureC!,
        humiditePct: humiditePct,
        ventMs: ventMs,
        ventVientDeDeg: ventVientDeDeg,
      );
    }
    double? d;
    if (p.lat != null && p.lon != null) {
      d = calage.caler(p.lat!, p.lon!);
      if (d == null) horsParcours++;
    }
    final puissance = p.puissanceW ?? 0;
    final a = coach.tick(
      Echantillon(
        t: p.t - t0,
        puissanceW: puissance,
        fcBpm: p.fcBpm,
        cadenceRpm: p.cadenceRpm,
        distanceParcoursM: d,
      ),
    );
    String? prise;
    if (prises == Prises.conseils) {
      for (final x in a) {
        prise = _obeir(coach, x) ?? prise;
      }
    }
    lignes.add(
      LigneJournal(
        t: p.t - t0,
        distanceM: d,
        altitudeM: p.altitudeM,
        puissanceW: puissance,
        fcBpm: p.fcBpm,
        etat: coach.etat,
        alerte: a.isEmpty ? null : a.first,
        prise: prise,
      ),
    );
  }

  return ResultatSimulation(
    parcours: parcours,
    coach: coach,
    lignes: lignes,
    montees: _bilans(parcours, lignes, cfg),
    pointsHorsParcours: horsParcours,
  );
}

String? _obeir(Coach coach, Alerte a) {
  final aliments = coach.cfg.manger.aliments;
  final boissons = coach.cfg.boire.boissons;
  switch (a.code) {
    case 'manger':
      coach.mangeAliment(aliments.first);
      return aliments.first.nom;
    case 'manger_avant_col':
      final al = aliments.length > 1 ? aliments[1] : aliments.first;
      coach.mangeAliment(al);
      return al.nom;
    case 'boire':
      final b = boissons.length > 1 ? boissons[1] : boissons.first;
      coach.boitBoisson(b);
      return b.nom;
  }
  return null;
}

List<BilanMontee> _bilans(
  Parcours parcours,
  List<LigneJournal> lignes,
  Config cfg,
) {
  final res = <BilanMontee>[];
  for (final m in parcours.montees) {
    // Première mesure au pied, première au sommet.
    final iDebut = lignes.indexWhere(
      (l) => l.distanceM != null && l.distanceM! >= m.debutM,
    );
    if (iDebut < 0) continue;
    final iFin = lignes.indexWhere(
      (l) => l.distanceM != null && l.distanceM! >= m.finM,
      iDebut,
    );
    if (iFin <= iDebut) continue;
    var travail = 0.0;
    for (var i = iDebut + 1; i <= iFin; i++) {
      travail += lignes[i].puissanceW * (lignes[i].t - lignes[i - 1].t);
    }
    final duree = lignes[iFin].t - lignes[iDebut].t;
    final pReelle = duree > 0 ? travail / duree : 0.0;
    // Cible annoncée : à l'annonce avant le pied (jusqu'à 2 min avant),
    // sinon la première cible calculée dans la montée.
    double? cible;
    for (var i = iDebut; i >= 0 && lignes[i].t >= lignes[iDebut].t - 120; i--) {
      if (lignes[i].alerte?.code == 'montee_annonce') {
        cible = lignes[i].etat.puissanceProchaineW;
        break;
      }
    }
    if (cible == null) {
      for (var i = iDebut; i <= iFin && cible == null; i++) {
        cible = lignes[i].etat.puissanceCibleW;
      }
    }
    final meteo = Meteo(
      temperatureC: cfg.physique.temperatureDefautC,
      humiditePct: cfg.physique.humiditeDefautPct,
    );
    res.add(
      BilanMontee(
        montee: m,
        cibleAnnonceeW: cible,
        puissanceReelleW: pReelle,
        dureeReelleS: duree,
        dureePreditePuissanceReelleS: dureeSegments(
          parcours.segmentsEntre(m.debutM, m.finM),
          pReelle,
          ConditionsRoulage.depuis(cfg, meteo),
        ),
        wbalSommetPct: lignes[iFin].etat.wbalPct,
      ),
    );
  }
  return res;
}
