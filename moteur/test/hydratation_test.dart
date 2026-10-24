import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

Hydratation rouler(
  double heures,
  double puissanceW,
  double tempC,
  double hum, {
  ConfigBoire cfg = const ConfigBoire(),
}) {
  final h = Hydratation(cfg, 250);
  for (var i = 0; i < heures * 3600; i++) {
    h.maj(puissanceW, 1, tempC, hum);
  }
  return h;
}

void main() {
  group('Facteurs', () {
    final h = Hydratation(const ConfigBoire(), 250);
    test('tous à 1 dans les conditions de référence', () {
      expect(h.facteurTemperature(20), 1);
      expect(h.facteurHumidite(50), 1);
      expect(h.facteurIntensite(162.5), closeTo(1, 1e-12));
    });
    test('température : +4 % par degré, bornée', () {
      expect(h.facteurTemperature(30), closeTo(1.4, 1e-12));
      expect(h.facteurTemperature(10), closeTo(0.6, 1e-12));
      expect(h.facteurTemperature(-10), 0.5);
      expect(h.facteurTemperature(60), 2.0);
    });
    test('humidité : +0,5 % par point, bornée', () {
      expect(h.facteurHumidite(90), closeTo(1.2, 1e-12));
      expect(h.facteurHumidite(100), closeTo(1.25, 1e-12));
      expect(h.facteurHumidite(0), 0.8);
    });
    test('intensité : 0,4 à l’arrêt, 1,32 à FTP', () {
      expect(h.facteurIntensite(0), closeTo(0.4, 1e-12));
      expect(h.facteurIntensite(250), closeTo(0.4 + 0.6 * 250 / 162.5, 1e-12));
    });
  });

  group('Perte et objectif', () {
    test('1 h en conditions de référence : 0,8 L', () {
      final h = rouler(1, 162.5, 20, 50);
      expect(h.perteL, closeTo(0.8, 1e-6));
      expect(h.objectifL, closeTo(0.8, 1e-6));
      expect(h.heuresEquivalentes, closeTo(1, 1e-6));
    });
    test('1 h à 30 °C : 1,12 L perdus', () {
      final h = rouler(1, 162.5, 30, 50);
      expect(h.perteL, closeTo(1.12, 1e-6));
    });
    test('l’objectif de boisson est plafonné à 1 L/h', () {
      final h = rouler(1, 250, 35, 80);
      expect(h.perteL, greaterThan(1.5));
      expect(h.objectifL, closeTo(1.0, 1e-6));
    });
  });

  group('Alertes « bois »', () {
    test('tous les 150 ml de retard, remis à zéro quand on boit', () {
      final h = Hydratation(const ConfigBoire(), 250);
      var t = 0;
      while (!h.alerteDue) {
        h.maj(162.5, 1, 20, 50);
        t++;
      }
      // 150 ml à 0,8 L/h : 675 s.
      expect(t, closeTo(675, 2));
      h.alerteEmise();
      while (!h.alerteDue) {
        h.maj(162.5, 1, 20, 50);
      }
      expect(h.retardMl, closeTo(300, 1));
      h.boit(250);
      expect(h.retardMl, closeTo(50, 1));
      expect(h.alerteDue, isFalse);
      while (!h.alerteDue) {
        h.maj(162.5, 1, 20, 50);
      }
      expect(h.retardMl, closeTo(150, 1));
    });
  });

  group('Calibration', () {
    test('poids perdu + bu = sueur', () {
      final r = calibrerSudation(
        poidsAvantKg: 75,
        poidsApresKg: 74,
        buL: 0.6,
        dureeH: 2,
      );
      expect(r.perteL, closeTo(1.6, 1e-9));
      expect(r.tauxMoyenLh, closeTo(0.8, 1e-9));
      expect(r.nouveauTauxBaseLh, closeTo(0.8, 1e-9));
      expect(r.pertePoidsPct, closeTo(1.333, 0.001));
    });
    test('ramené aux conditions de référence', () {
      // Sortie chaude : le modèle compte 2,5 « heures de référence » en 2 h.
      final r = calibrerSudation(
        poidsAvantKg: 75,
        poidsApresKg: 74,
        buL: 0.6,
        dureeH: 2,
        heuresEquivalentes: 2.5,
      );
      expect(r.nouveauTauxBaseLh, closeTo(0.64, 1e-9));
    });
    test('boucle complète : la calibration retrouve le vrai taux', () {
      // Sortie de 3 h à 28 °C simulée avec un taux de base de 0,8 ;
      // le vrai taux du cycliste est 1,0 L/h en référence.
      final h = rouler(3, 180, 28, 65);
      final vraiePerte = h.perteL * 1.0 / 0.8;
      final r = calibrerSudation(
        poidsAvantKg: 75,
        poidsApresKg: 75 - (vraiePerte - 1.2),
        buL: 1.2,
        dureeH: 3,
        heuresEquivalentes: h.heuresEquivalentes,
      );
      expect(r.nouveauTauxBaseLh, closeTo(1.0, 1e-9));
    });
  });
}
