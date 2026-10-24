import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

void main() {
  group('W\'bal différentiel (Skiba 2015)', () {
    test('2 min à CP + 100 W vident 12 kJ', () {
      final r = ReserveAnaerobie(wPrimeJ: 18000);
      for (var i = 0; i < 120; i++) {
        r.maj(350, 250, 1);
      }
      expect(r.wbalJ, closeTo(6000, 1e-6));
      expect(r.pourcentage, closeTo(33.33, 0.01));
    });

    test('récupération exponentielle sous CP', () {
      final r = ReserveAnaerobie(wPrimeJ: 18000)..wbalJ = 6000;
      for (var i = 0; i < 300; i++) {
        r.maj(0, 250, 1);
      }
      // W' − (W' − 6000) × e^(−250 × 300 / 18000)
      final attendu = 18000 - 12000 * math.exp(-250 * 300 / 18000);
      expect(r.wbalJ, closeTo(attendu, 1e-6));
    });

    test('à CP, la réserve ne bouge pas ; elle ne dépasse jamais W\'', () {
      final r = ReserveAnaerobie(wPrimeJ: 18000);
      for (var i = 0; i < 600; i++) {
        r.maj(250, 250, 1);
      }
      expect(r.wbalJ, 18000);
      for (var i = 0; i < 600; i++) {
        r.maj(100, 250, 1);
      }
      expect(r.wbalJ, lessThanOrEqualTo(18000));
    });

    test('le résultat ne dépend pas du pas de temps', () {
      final a = ReserveAnaerobie(wPrimeJ: 18000)..wbalJ = 5000;
      final b = ReserveAnaerobie(wPrimeJ: 18000)..wbalJ = 5000;
      for (var i = 0; i < 60; i++) {
        a.maj(150, 250, 1);
      }
      b.maj(150, 250, 60);
      expect(a.wbalJ, closeTo(b.wbalJ, 1e-6));
    });
  });

  group('W\'bal intégral (Skiba 2012)', () {
    test('constante de temps tau', () {
      expect(tauSkiba2012(100), closeTo(546 * math.exp(-1) + 316, 1e-9));
      expect(tauSkiba2012(0), 862);
    });

    test('vide moins vite pendant l’effort, puis récupère', () {
      final r = ReserveAnaerobie(wPrimeJ: 18000, modele: ModeleWbal.integral);
      for (var i = 0; i < 120; i++) {
        r.maj(350, 250, 1);
      }
      // Pas encore de puissance sous CP : D_CP = 250, tau ≈ 361 s.
      final tau = tauSkiba2012(250);
      final attendu = 18000 - 100 * tau * (1 - math.exp(-120 / tau));
      expect(r.wbalJ, closeTo(attendu, 60));
      final apresEffort = r.wbalJ;
      for (var i = 0; i < 600; i++) {
        r.maj(100, 250, 1);
      }
      expect(r.wbalJ, greaterThan(apresEffort));
      expect(r.wbalJ, lessThan(18000));
    });
  });

  group('Fatigue de fond', () {
    const cfg = ConfigWbal();
    test('rien jusqu’à 1500 kJ', () {
      expect(cpEffective(cpW: 250, travailKj: 1500, cfg: cfg), 250);
    });
    test('-1 % par tranche de 500 kJ, en continu', () {
      expect(
        cpEffective(cpW: 250, travailKj: 2000, cfg: cfg),
        closeTo(247.5, 1e-9),
      );
      expect(
        cpEffective(cpW: 250, travailKj: 2250, cfg: cfg),
        closeTo(246.25, 1e-9),
      );
      expect(
        cpEffective(cpW: 250, travailKj: 3000, cfg: cfg),
        closeTo(242.5, 1e-9),
      );
    });
    test('en escalier si demandé', () {
      const esc = ConfigWbal(fatigueEnEscalier: true);
      expect(
        cpEffective(cpW: 250, travailKj: 2250, cfg: esc),
        closeTo(247.5, 1e-9),
      );
    });
    test('baisse plafonnée à 20 %', () {
      expect(
        cpEffective(cpW: 250, travailKj: 50000, cfg: cfg),
        closeTo(200, 1e-9),
      );
    });
  });
}
