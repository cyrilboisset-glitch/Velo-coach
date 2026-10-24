import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

import 'outils.dart';

const _cfg = Config();
final _cond = ConditionsRoulage.depuis(
  _cfg,
  const Meteo(temperatureC: 15, humiditePct: 50),
);

/// Col de 6 km à 7 % entre deux plats de 2 km.
final _col = Parcours.depuisProfil(const [
  Troncon(2000, 0),
  Troncon(6000, 7),
  Troncon(2000, 0),
]);

ResultatPacing _pacing(
  List<Segment> segs, {
  double cp = 250,
  double wbal = 18000,
  ConfigPacing cfg = const ConfigPacing(),
  ConditionsRoulage? cond,
}) => calculerPacing(
  segments: segs,
  cpEffW: cp,
  wbalJ: wbal,
  wPrimeJ: 18000,
  ftpW: 250,
  cfg: cfg,
  conditions: cond ?? _cond,
);

List<Segment> _montee(Parcours p) =>
    p.segmentsEntre(p.montees.first.debutM, p.montees.first.finM);

void main() {
  group('Puissance cible P = CP_eff + W\'bal / durée', () {
    test('réserve vide : la cible est la CP', () {
      final r = _pacing(_montee(_col), wbal: 0);
      expect(r.puissanceW, closeTo(250, 0.2));
    });

    test('réserve pleine : la formule est respectée', () {
      final r = _pacing(_montee(_col));
      expect(r.dureeS, inInclusiveRange(20 * 60, 35 * 60));
      expect(r.puissanceW, closeTo(250 + 18000 / r.dureeS, 0.2));
      expect(r.plafonnee, isFalse);
    });

    test('fatigue : CP effective plus basse, cible plus basse', () {
      final frais = _pacing(_montee(_col));
      final fatigue = _pacing(
        _montee(_col),
        cp: cpEffective(cpW: 250, travailKj: 3000, cfg: const ConfigWbal()),
      );
      expect(frais.puissanceW - fatigue.puissanceW, closeTo(7.5, 0.5));
    });

    test('vent de face : montée plus longue, cible plus proche de la CP', () {
      final calme = _pacing(_montee(_col));
      final vent = _pacing(
        _montee(_col),
        cond: ConditionsRoulage.depuis(
          _cfg,
          const Meteo(temperatureC: 15, humiditePct: 50, ventMs: 8),
        ),
      );
      expect(vent.dureeS, greaterThan(calme.dureeS));
      expect(vent.puissanceW, lessThan(calme.puissanceW));
      expect(vent.puissanceW, greaterThan(250));
    });

    test('garder 20 % de réserve baisse la cible', () {
      final r0 = _pacing(_montee(_col));
      final r20 = _pacing(
        _montee(_col),
        cfg: const ConfigPacing(reserveFinMonteePct: 20),
      );
      expect(r20.puissanceW, lessThan(r0.puissanceW));
      expect(r20.puissanceW, closeTo(250 + 0.8 * 18000 / r20.dureeS, 0.2));
    });

    test('montée courte : cible plafonnée à 130 % de FTP', () {
      final bosse = Parcours.depuisProfil(const [
        Troncon(1000, 0),
        Troncon(1000, 8),
        Troncon(1000, 0),
      ]);
      final r = _pacing(_montee(bosse));
      expect(r.puissanceW, 325);
      expect(r.plafonnee, isTrue);
    });

    test('réserve très négative : cible au plancher (50 % de FTP)', () {
      // −200 kJ donne encore 165 W ; il faut −1000 kJ pour toucher 125 W.
      final r = _pacing(_montee(_col), wbal: -1000000);
      expect(r.puissanceW, 125);
      expect(r.plancher, isTrue);
    });

    test('col de plus d’une heure : le déclin optionnel baisse la cible', () {
      final long = Parcours.depuisProfil(const [
        Troncon(1000, 0),
        Troncon(25000, 7),
        Troncon(1000, 0),
      ]);
      final pur = _pacing(
        _montee(long),
        cfg: const ConfigPacing(declinLongueDureeParLn: 0),
      );
      expect(pur.dureeS, greaterThan(1.5 * 3600));
      // Formule pure : quasiment la FTP pendant plus d'une heure et demie.
      expect(pur.puissanceW, closeTo(250 + 18000 / pur.dureeS, 0.2));
      // Réglage par défaut : correction activée (A = 0,12).
      final declin = _pacing(_montee(long));
      final t = declin.dureeS;
      expect(
        declin.puissanceW,
        closeTo(250 * (1 - 0.12 * math.log(t / 3600)) + 18000 / t, 0.2),
      );
      expect(declin.puissanceW, lessThan(pur.puissanceW - 10));
    });
  });

  group('En suivant la cible, la réserve arrive vide au sommet', () {
    for (final modele in ModeleWbal.values) {
      test('modèle ${modele.name}', () {
        final cfg = Config(wbal: ConfigWbal(modele: modele));
        final coach = Coach(cfg, parcours: _col);
        final m = _col.montees.single;
        final cibles = <double>[];
        double? wbalSommet;
        simuler(
          coach,
          dureeMaxS: 3 * 3600,
          puissance: (c, t, d) {
            final cible = c.etat.puissanceCibleW;
            return m.contient(d) && cible != null ? cible : 180;
          },
          chaqueSeconde: (c, t, d, a) {
            final cible = c.etat.puissanceCibleW;
            if (cible != null) cibles.add(cible);
            if (d >= m.finM && wbalSommet == null) wbalSommet = c.wbal.wbalJ;
          },
        );
        expect(cibles, isNotEmpty);
        if (modele == ModeleWbal.differentiel) {
          // Modèle différentiel : vidange linéaire, la prévision est exacte.
          expect(wbalSommet, closeTo(0, 400));
          // La cible reste stable du pied au sommet.
          final ecart =
              cibles.reduce((a, b) => a > b ? a : b) -
              cibles.reduce((a, b) => a < b ? a : b);
          expect(ecart, lessThan(3));
        } else {
          // Modèle intégral : il récupère pendant l'effort, la réserve
          // n'est pas vide au sommet, mais elle a bien servi.
          expect(wbalSommet, lessThan(0.5 * 18000));
        }
      });
    }
  });

  group('Cols enchaînés : réserve au sommet décidée par le parcours', () {
    // Deux cols de 3 km à 7 %, séparés par 800 m de plat.
    final deux = Parcours.depuisProfil(const [
      Troncon(2000, 0),
      Troncon(3000, 7),
      Troncon(800, 0),
      Troncon(3000, 7),
      Troncon(2000, 0),
    ]);

    test('gérés ensemble : cible plus basse, réserve gardée au sommet', () {
      expect(deux.montees, hasLength(2));
      final m0 = deux.montees[0];
      final m1 = deux.montees[1];
      final seul = _pacing(deux.segmentsEntre(m0.debutM, m0.finM));
      final ensemble = calculerPacing(
        segments: deux.segmentsEntre(m0.debutM, m0.finM),
        enchainement: [
          ColEnchaine(
            intervalle: deux.segmentsEntre(m0.finM, m1.debutM),
            montee: deux.segmentsEntre(m1.debutM, m1.finM),
          ),
        ],
        cpEffW: 250,
        wbalJ: 18000,
        wPrimeJ: 18000,
        ftpW: 250,
        cfg: const ConfigPacing(),
        conditions: _cond,
      );
      expect(seul.reserveSommetJ, closeTo(0, 50));
      expect(ensemble.colsEnchaines, 1);
      expect(ensemble.puissanceW, lessThan(seul.puissanceW - 5));
      expect(ensemble.puissanceW, greaterThan(250));
      expect(ensemble.reserveSommetJ, greaterThan(0.25 * 18000));
    });

    test(
      'en suivant la cible : réserve gardée en haut du 1er, vide en haut du 2e',
      () {
        final coach = Coach(const Config(), parcours: deux);
        final m0 = deux.montees[0];
        final m1 = deux.montees[1];
        final cibles0 = <double>[];
        final cibles1 = <double>[];
        double? prevue;
        double? auSommet0;
        double? auSommet1;
        simuler(
          coach,
          dureeMaxS: 3 * 3600,
          puissance: (c, t, d) {
            final cible = c.etat.puissanceCibleW;
            return c.parcours!.monteeA(d) != null && cible != null
                ? cible
                : 150;
          },
          chaqueSeconde: (c, t, d, a) {
            final e = c.etat;
            if (e.puissanceCibleW != null && m0.contient(d)) {
              cibles0.add(e.puissanceCibleW!);
              prevue ??= e.reserveSommetPct;
            }
            if (e.puissanceCibleW != null && m1.contient(d)) {
              cibles1.add(e.puissanceCibleW!);
            }
            if (d >= m0.finM && auSommet0 == null) {
              auSommet0 = c.wbal.pourcentage;
            }
            if (d >= m1.finM && auSommet1 == null) {
              auSommet1 = c.wbal.pourcentage;
            }
          },
        );
        expect(prevue, greaterThan(25));
        expect(auSommet0, closeTo(prevue!, 3));
        expect(auSommet1, closeTo(0, 3));
        // Une seule puissance pour les deux cols.
        expect(cibles1.first, closeTo(cibles0.first, 4));
      },
    );

    test('col suivant après une longue descente : chacun vide sa réserve', () {
      final loin = Parcours.depuisProfil(const [
        Troncon(2000, 0),
        Troncon(3000, 7),
        Troncon(15000, -5),
        Troncon(3000, 7),
        Troncon(2000, 0),
      ]);
      final coach = Coach(const Config(), parcours: loin);
      final m0 = loin.montees.first;
      EtatCoach? dansLeCol;
      simuler(
        coach,
        dureeMaxS: 3 * 3600,
        puissance: (c, t, d) => c.etat.puissanceCibleW ?? 150,
        chaqueSeconde: (c, t, d, a) {
          if (m0.contient(d) && c.etat.puissanceCibleW != null) {
            dansLeCol ??= c.etat;
          }
        },
      );
      expect(dansLeCol!.colsEnchaines, 0);
      expect(dansLeCol!.reserveSommetPct, closeTo(0, 1));
    });
  });
}
