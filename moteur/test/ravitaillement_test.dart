import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

/// Une heure à puissance constante, une mesure par seconde.
Ravitaillement uneHeure(
  double puissanceW, {
  ConfigManger cfg = const ConfigManger(),
}) {
  final r = Ravitaillement(cfg, 250);
  for (var i = 0; i < 3600; i++) {
    r.maj(puissanceW, 1);
  }
  return r;
}

void main() {
  group('Table des glucides', () {
    const cfg = ConfigManger();
    test('paliers du cahier des charges', () {
      expect(cfg.partGlucides(0), 0.50);
      expect(cfg.partGlucides(54.9), 0.50);
      expect(cfg.partGlucides(55), 0.65);
      expect(cfg.partGlucides(74.9), 0.65);
      expect(cfg.partGlucides(75), 0.80);
      expect(cfg.partGlucides(89.9), 0.80);
      expect(cfg.partGlucides(90), 0.95);
      expect(cfg.partGlucides(150), 0.95);
    });
  });

  group('Glucides brûlés et objectif', () {
    test(
      '200 W pendant 1 h (80 % FTP) : 143 g brûlés, objectif plafonné à 75 g',
      () {
        // 200 W × 3600 s = 720 kJ ; / 0,24 / 4,184 = 717 kcal ;
        // × 0,80 = 574 kcal de glucides ; / 4 = 143,4 g.
        final r = uneHeure(200);
        expect(r.brulesG, closeTo(143.4, 0.1));
        expect(r.objectifG, closeTo(75, 0.1));
        expect(r.retardG, closeTo(75, 0.1));
      },
    );

    test('100 W pendant 1 h (40 % FTP) : 44,8 g, sous la tolérance', () {
      final r = uneHeure(100);
      expect(r.brulesG, closeTo(44.8, 0.1));
      expect(r.objectifG, closeTo(r.brulesG, 1e-9));
    });

    test('1 kJ mécanique ≈ 1 kcal avec un rendement de 24 %', () {
      // 1000 J / 0,24 / 4184 = 0,996 kcal.
      expect(1000 / 0.24 / jParKcal, closeTo(1.0, 0.005));
    });

    test('un rendement plus faible augmente les glucides brûlés', () {
      final r24 = uneHeure(150);
      final r20 = uneHeure(150, cfg: const ConfigManger(rendementBrut: 0.20));
      expect(r20.brulesG / r24.brulesG, closeTo(1.2, 1e-6));
    });

    test('roue libre : rien de brûlé', () {
      final r = uneHeure(0);
      expect(r.brulesG, 0);
      expect(r.objectifG, 0);
    });

    test('un sprint court n’est pas plafonné, une heure dure l’est', () {
      final r = Ravitaillement(const ConfigManger(), 250);
      for (var i = 0; i < 1200; i++) {
        r.maj(100, 1);
      }
      final avant = r.objectifG;
      final brulesAvant = r.brulesG;
      for (var i = 0; i < 10; i++) {
        r.maj(800, 1);
      }
      // 10 s à 800 W : le débit moyen reste sous 75 g/h, tout compte.
      expect(r.objectifG - avant, closeTo(r.brulesG - brulesAvant, 1e-6));
    });
  });

  group('Alertes « mange »', () {
    test('première alerte à 25 g de retard, puis à chaque multiple', () {
      final r = Ravitaillement(const ConfigManger(), 250);
      var t = 0;
      while (!r.alerteDue) {
        r.maj(100, 1);
        t++;
      }
      // 25 g à 44,8 g/h : environ 2008 s.
      expect(t, closeTo(2008, 3));
      r.alerteEmise();
      expect(r.alerteDue, isFalse);
      while (!r.alerteDue) {
        r.maj(100, 1);
      }
      expect(r.retardG, closeTo(50, 0.1));
    });

    test('manger remet le compteur : prochaine alerte à 25 g', () {
      final r = Ravitaillement(const ConfigManger(), 250);
      for (var i = 0; i < 2100; i++) {
        r.maj(100, 1);
      }
      expect(r.alerteDue, isTrue);
      r.mange(40);
      expect(r.retardG, lessThan(0));
      expect(r.alerteDue, isFalse);
      while (!r.alerteDue) {
        r.maj(100, 1);
      }
      expect(r.retardG, closeTo(25, 0.1));
    });
  });

  group('Prochain multiple', () {
    test('valeurs', () {
      expect(prochainMultiple(-10, 25), 25);
      expect(prochainMultiple(0, 25), 25);
      expect(prochainMultiple(24.9, 25), 25);
      expect(prochainMultiple(25, 25), 50);
      expect(prochainMultiple(60, 25), 75);
    });
  });
}
