// Exemple : une sortie inventée de 95 km avec deux cols, rejouée
// seconde par seconde. Affiche les alertes que tu aurais reçues.
//
// Lancer : dart run example/sortie_exemple.dart
//
// Le cycliste virtuel roule à 190 W sur le plat, suit la cible en montée,
// mange quand on le lui dit (gel, ou barre avant un col) et boit un
// demi-bidon à chaque alerte « bois ».

import 'package:velo_coach_moteur/velo_coach_moteur.dart';

void main() {
  const cfg = Config(
    cycliste: ConfigCycliste(poidsCyclisteKg: 75, poidsVeloKg: 9, ftpW: 250),
  );
  final parcours = Parcours.depuisProfil(const [
    Troncon(30000, 0.3),
    Troncon(11000, 6.5), // col 1 : 11 km à 6,5 %
    Troncon(14000, -5),
    Troncon(12000, 0),
    Troncon(4000, 8), // col 2 : 4 km à 8 %
    Troncon(6000, -5),
    Troncon(18000, 0),
  ], capDeg: 0);
  const meteo = Meteo(
    temperatureC: 26,
    humiditePct: 60,
    ventMs: 3,
    ventVientDeDeg: 0,
  );
  final coach = Coach(cfg, parcours: parcours, meteo: meteo);
  final cond = ConditionsRoulage.depuis(cfg, meteo);

  print('Montées détectées :');
  for (final m in parcours.montees) {
    print(
      '  col ${m.index + 1} : km ${km(m.debutM)} → ${km(m.finM)}, '
      '${km(m.longueurM)} km à ${(100 * m.penteMoyenne).toStringAsFixed(1).replaceAll('.', ',')} %, '
      '+${m.deniveleM.round()} m',
    );
  }
  print('');
  print('Heure  | km    | Alerte');
  print('-------+-------+------------------------------------------');

  var d = 0.0;
  var t = 0.0;
  while (d < parcours.longueurM && t < 6 * 3600) {
    final m = parcours.monteeA(d);
    final cible = coach.etat.puissanceCibleW;
    final enDescente = parcours.segmentA(d).pente < -0.02;
    final p = m != null && cible != null
        ? cible
        : enDescente
        ? 60.0
        : 190.0;
    for (final a in coach.tick(
      Echantillon(t: t, puissanceW: p, distanceParcoursM: d),
    )) {
      print('${hm(t)}  | ${km(d).padLeft(5)} | ${a.texte}');
      switch (a.code) {
        case 'manger':
          coach.mangeAliment(cfg.manger.aliments[0]); // gel
        case 'manger_avant_col':
          coach.mangeAliment(cfg.manger.aliments[1]); // barre
        case 'boire':
          coach.boitBoisson(cfg.boire.boissons[1]); // demi-bidon
      }
    }
    d += vitessePourPuissance(p, parcours.segmentA(d), cond);
    t += 1;
  }

  final e = coach.etat;
  print('');
  print('Bilan après ${hm(t)} et ${km(d)} km :');
  print(
    '  travail        ${e.travailKj.round()} kJ, '
    'CP effective ${e.cpEffW.round()} W, réserve ${e.wbalPct.round()} %',
  );
  print(
    '  glucides       brûlés ${e.glucidesBrulesG.round()} g, '
    'objectif ${e.glucidesObjectifG.round()} g, '
    'mangés ${e.glucidesMangesG.round()} g',
  );
  print(
    '  eau            sueur ${l(e.eauPerdueL)} L, '
    'objectif ${l(e.eauObjectifL)} L, '
    'bue ${l(e.eauBueL)} L',
  );
}

String l(double x) => x.toStringAsFixed(2).replaceAll('.', ',');

String km(double m) => (m / 1000).toStringAsFixed(1).replaceAll('.', ',');

String hm(double s) {
  final h = s ~/ 3600;
  final min = (s % 3600) ~/ 60;
  return '${h}h${min.toString().padLeft(2, '0')}';
}
