import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

import 'outils.dart';

/// 25 km de plat, col de 8 km à 6 %, 10 km de descente, 10 km de plat.
final _parcours = Parcours.depuisProfil(const [
  Troncon(25000, 0),
  Troncon(8000, 6),
  Troncon(10000, -4),
  Troncon(10000, 0),
]);

/// Le cycliste : 180 W sur le plat, suit la cible en montée (multipliée
/// par [facteurMontee]), 100 W en descente.
double Function(Coach, double, double) _cycliste({double facteurMontee = 1}) {
  final col = _parcours.montees.single;
  return (c, t, d) {
    if (col.contient(d)) {
      final cible = c.etat.puissanceCibleW;
      return cible == null ? 180 : cible * facteurMontee;
    }
    return d >= col.finM && d < col.finM + 10000 ? 100 : 180;
  };
}

class _Trace {
  final alertes = <Alerte>[];
  final distance = <Alerte, double>{};
  final eta = <Alerte, double?>{};
}

_Trace _rouler(Coach coach, {double facteurMontee = 1}) {
  final trace = _Trace();
  simuler(
    coach,
    dureeMaxS: 4 * 3600,
    puissance: _cycliste(facteurMontee: facteurMontee),
    chaqueSeconde: (c, t, d, a) {
      for (final x in a) {
        trace.alertes.add(x);
        trace.distance[x] = d;
        trace.eta[x] = c.etat.etaProchaineS;
      }
    },
  );
  return trace;
}

void main() {
  test('le parcours de test a bien un col', () {
    expect(_parcours.montees, hasLength(1));
  });

  group('Sortie complète sans manger ni boire', () {
    final coach = Coach(const Config(), parcours: _parcours);
    final trace = _rouler(coach);
    final col = _parcours.montees.single;
    List<Alerte> code(String c) =>
        trace.alertes.where((a) => a.code == c).toList();

    test('au plus une alerte par minute', () {
      for (var i = 1; i < trace.alertes.length; i++) {
        expect(
          trace.alertes[i].t - trace.alertes[i - 1].t,
          greaterThanOrEqualTo(60),
        );
      }
    });

    test('textes de 40 caractères au plus', () {
      for (final a in trace.alertes) {
        expect(a.texte.length, lessThanOrEqualTo(40), reason: a.texte);
      }
    });

    test('« mange avant le col » une seule fois, 10 à 15 min avant', () {
      final a = code('manger_avant_col');
      expect(a, hasLength(1));
      expect(trace.eta[a.single], inInclusiveRange(600, 900));
      expect(trace.distance[a.single], lessThan(col.debutM));
    });

    test('annonce de la puissance cible juste avant le pied du col', () {
      final a = code('montee_annonce');
      expect(a, hasLength(1));
      expect(trace.eta[a.single], lessThanOrEqualTo(90));
      expect(trace.distance[a.single], lessThan(col.debutM));
      expect(a.single.texte, startsWith('Montée 8,'));
    });

    test('rappels de puissance pendant la montée', () {
      final a = code('montee_cible');
      expect(a, isNotEmpty);
      for (final x in a) {
        expect(col.contient(trace.distance[x]!), isTrue);
      }
    });

    test('pas d’alerte « mange » normale pendant la montée', () {
      for (final x in code('manger')) {
        expect(col.contient(trace.distance[x]!), isFalse);
      }
      expect(code('manger'), isNotEmpty);
    });

    test('alertes « bois » répétées', () {
      expect(code('boire').length, greaterThanOrEqualTo(3));
    });

    test('le journal contient toutes les alertes', () {
      expect(
        coach.journal.where((e) => e.type == TypeEvenement.alerte),
        hasLength(trace.alertes.length),
      );
    });
  });

  test('pas de « mange avant le col » si on a assez mangé', () {
    final coach = Coach(const Config(), parcours: _parcours);
    coach.mange(100, nom: 'Gros petit-déjeuner de route');
    final trace = _rouler(coach);
    expect(trace.alertes.where((a) => a.code == 'manger_avant_col'), isEmpty);
  });

  test('« lève le pied » si on dépasse la cible de 15 %', () {
    final coach = Coach(const Config(), parcours: _parcours);
    final trace = _rouler(coach, facteurMontee: 1.15);
    final a = trace.alertes.where((a) => a.code == 'montee_surregime');
    expect(a, isNotEmpty);
    expect(a.first.texte, startsWith('Lève le pied : '));
  });

  group('Sans parcours', () {
    test('2 h à 200 W : « bois » vers 12 min, « mange » à 20 min', () {
      final coach = Coach(const Config());
      final alertes = <Alerte>[];
      for (var t = 0.0; t <= 7200; t += 1) {
        alertes.addAll(coach.tick(Echantillon(t: t, puissanceW: 200)));
      }
      // Sudation à 15 °C (météo par défaut) : 0,8 × 0,8 × 1,138
      // = 0,73 L/h → 150 ml en 742 s.
      expect(alertes.first.code, 'boire');
      expect(alertes.first.t, closeTo(742, 5));
      final mange = alertes.firstWhere((a) => a.code == 'manger');
      // Objectif à 75 g/h → 25 g en 1200 s.
      expect(mange.t, closeTo(1200, 5));
      expect(coach.etat.puissanceCibleW, isNull);
    });

    test('une pause de plus de 10 s compte 0 W', () {
      final coach = Coach(const Config());
      rouler(coach, 0, 101, 300);
      final apres100s = coach.travailKj;
      final wbalAvant = coach.wbal.wbalJ;
      coach.tick(const Echantillon(t: 400, puissanceW: 300));
      expect(apres100s, closeTo(30, 1e-9));
      expect(coach.travailKj, closeTo(30, 1e-9));
      expect(coach.wbal.wbalJ, greaterThan(wbalAvant));
    });

    test('une boisson énergétique compte aussi en glucides', () {
      final coach = Coach(
        const Config(manger: ConfigManger(glucidesParLitreBoisson: 60)),
      );
      coach.boitBoisson(const Boisson('Bidon', 500));
      expect(coach.etat.glucidesMangesG, closeTo(30, 1e-9));
      expect(coach.etat.eauBueL, closeTo(0.5, 1e-9));
      expect(coach.journal.single.type, TypeEvenement.boit);
    });

    test('la fatigue de fond baisse la CP effective', () {
      final coach = Coach(const Config());
      rouler(coach, 0, 3 * 3600 + 1, 250); // 2700 kJ
      expect(coach.travailKj, closeTo(2700, 1e-6));
      expect(coach.cpEffW, closeTo(250 * (1 - 0.024), 1e-6));
    });
  });
}
