// Mode simulation : rejoue une sortie enregistrée et affiche les alertes
// que tu aurais reçues, et quand.
//
// Exemples :
//   dart run bin/simuler.dart --strava ../donnees/sortie.json --ftp 203 --poids 90
//   dart run bin/simuler.dart --csv sortie.csv --gpx parcours.gpx --prises aucune
//
// Options :
//   --strava FICHIER   flux Strava (JSON)        --csv FICHIER   sortie en CSV
//   --gpx FICHIER      parcours prévu (sinon la trace de la sortie elle-même)
//   --ftp W  --poids KG  --velo KG  --wprime J   réglages personnels
//   --prises conseils|aucune   le cycliste virtuel mange/boit quand on lui dit
//   --humidite %  --vent KMH  --vent-de DEG     météo (non enregistrée)
//   --journal FICHIER  écrit le journal CSV      --rapport FICHIER  rapport HTML
//   --titre TEXTE      titre du rapport

import 'dart:io';

import 'package:velo_coach_moteur/velo_coach_moteur.dart';

void main(List<String> args) {
  final o = _options(args);
  if (o.containsKey('aide') || (o['strava'] == null && o['csv'] == null)) {
    stdout.writeln(
      'Usage : dart run bin/simuler.dart --strava FICHIER.json '
      '[--gpx PARCOURS.gpx] [--ftp 203] [--poids 90] [--velo 9] '
      '[--prises conseils|aucune] [--journal j.csv] [--rapport r.html]',
    );
    exit(o.containsKey('aide') ? 0 : 64);
  }

  final sortie = o['strava'] != null
      ? Enregistrement.depuisStravaJson(File(o['strava']!).readAsStringSync())
      : Enregistrement.depuisCsv(File(o['csv']!).readAsStringSync());

  const base = Config();
  final cfg = base.copie(
    cycliste: ConfigCycliste(
      poidsCyclisteKg: _nombre(o, 'poids', base.cycliste.poidsCyclisteKg),
      poidsVeloKg: _nombre(o, 'velo', base.cycliste.poidsVeloKg),
      ftpW: _nombre(o, 'ftp', base.cycliste.ftpW),
    ),
    wbal: ConfigWbal(wPrimeJ: _nombre(o, 'wprime', base.wbal.wPrimeJ)),
    // Les flux Strava sont sous-échantillonnés (un point toutes les 1 à
    // 15 s) : ne pas prendre ces écarts pour des pauses.
    ecartMaxEchantillonsS: o['strava'] != null ? 30 : null,
  );

  final points = o['gpx'] != null
      ? lireGpx(File(o['gpx']!).readAsStringSync())
      : sortie.trace;
  final parcours = Parcours.depuisPoints(points, cfg: cfg.montees);
  final res = simulerSortie(
    sortie: sortie,
    parcours: parcours,
    cfg: cfg,
    prises: o['prises'] == 'aucune' ? Prises.aucune : Prises.conseils,
    humiditePct: _nombre(o, 'humidite', 50),
    ventMs: _nombre(o, 'vent', 0) / 3.6,
    ventVientDeDeg: _nombre(o, 'vent-de', 0),
  );

  _afficher(res, cfg, sortie);

  if (o['journal'] != null) {
    File(o['journal']!).writeAsStringSync(res.journalCsv());
    stdout.writeln('\nJournal écrit : ${o['journal']}');
  }
  if (o['rapport'] != null) {
    File(o['rapport']!).writeAsStringSync(
      rapportHtml(res, titre: o['titre'] ?? 'Simulation de sortie'),
    );
    stdout.writeln('Rapport écrit : ${o['rapport']}');
  }
}

void _afficher(ResultatSimulation r, Config cfg, Enregistrement sortie) {
  final c = cfg.cycliste;
  stdout
    ..writeln(
      'Réglages : FTP ${c.ftpW.round()} W, ${c.poidsCyclisteKg} + '
      '${c.poidsVeloKg} kg, W\' ${(cfg.wbal.wPrimeJ / 1000).toStringAsFixed(1)} kJ',
    )
    ..writeln(
      'Sortie : ${sortie.points.length} mesures, ${hm(sortie.dureeS)}, '
      'parcours ${km(r.parcours.longueurM)} km, '
      '${r.pointsHorsParcours} mesures hors parcours',
    )
    ..writeln('')
    ..writeln('Montées détectées :');
  for (final m in r.parcours.montees) {
    stdout.writeln(
      '  ${m.index + 1}. km ${km(m.debutM)} → ${km(m.finM)} : '
      '${km(m.longueurM)} km à ${pct(m.penteMoyenne)} %, '
      '+${m.deniveleM.round()} m',
    );
  }
  stdout
    ..writeln('')
    ..writeln('Heure | km    | Alerte')
    ..writeln('------+-------+---------------------------------------------');
  for (final l in r.lignes) {
    final a = l.alerte;
    if (a == null) continue;
    final prise = l.prise == null ? '' : '   → ${l.prise}';
    final d = l.distanceM == null ? '  -  ' : km(l.distanceM!).padLeft(5);
    stdout.writeln('${hm(l.t)} | $d | ${a.texte}$prise');
  }
  stdout
    ..writeln('')
    ..writeln('Montées : prévu / réel');
  for (final b in r.montees) {
    stdout.writeln(
      '  ${b.montee.index + 1}. cible ${b.cibleAnnonceeW?.round() ?? '-'} W, '
      'tenu ${b.puissanceReelleW.round()} W ; '
      'temps réel ${hm(b.dureeReelleS)}, '
      'prévu à ${b.puissanceReelleW.round()} W : '
      '${hm(b.dureePreditePuissanceReelleS)} ; '
      'réserve au sommet ${b.wbalSommetPct.round()} %',
    );
  }
  final e = r.coach.etat;
  stdout
    ..writeln('')
    ..writeln(
      'Bilan : ${e.travailKj.round()} kJ ; glucides brûlés '
      '${e.glucidesBrulesG.round()} g, objectif ${e.glucidesObjectifG.round()} g, '
      'mangés ${e.glucidesMangesG.round()} g ; sueur '
      '${dec(e.eauPerdueL, 2)} L, objectif ${dec(e.eauObjectifL, 2)} L, '
      'bue ${dec(e.eauBueL, 2)} L',
    );
}

Map<String, String?> _options(List<String> args) {
  final o = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final nom = a.substring(2);
    final suivant = i + 1 < args.length && !args[i + 1].startsWith('--')
        ? args[++i]
        : null;
    o[nom] = suivant;
  }
  return o;
}

double _nombre(Map<String, String?> o, String nom, double defaut) {
  final v = o[nom];
  return v == null ? defaut : double.parse(v.replaceAll(',', '.'));
}

String dec(double x, int n) => x.toStringAsFixed(n).replaceAll('.', ',');
String km(double m) => dec(m / 1000, 1);
String pct(double f) => dec(100 * f, 1);
String hm(double s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).floor();
  return '${h}h${m.toString().padLeft(2, '0')}'
      '${h == 0 ? ':${sec.toString().padLeft(2, '0')}' : ''}';
}
