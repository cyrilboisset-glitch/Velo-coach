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
      final pur = _pacing(_montee(long));
      expect(pur.dureeS, greaterThan(1.5 * 3600));
      // Formule pure : quasiment la FTP pendant plus d'une heure et demie.
      expect(pur.puissanceW, closeTo(250 + 18000 / pur.dureeS, 0.2));
      final declin = _pacing(
        _montee(long),
        cfg: const ConfigPacing(declinLongueDureeParLn: 0.12),
      );
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
}
