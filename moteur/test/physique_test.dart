import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

const _cond = ConditionsRoulage(
  masseKg: 84,
  cda: 0.32,
  crr: 0.005,
  rendementTransmission: 0.976,
  vitesseMinMs: 4 / 3.6,
  vitesseMaxMs: 60 / 3.6,
);

Segment _seg(double pentePct, {double altitude = 0, double? cap = 0}) =>
    Segment(
      debutM: 0,
      longueurM: 1000,
      pente: pentePct / 100,
      altitudeM: altitude,
      capDeg: cap,
    );

ConditionsRoulage _avecVent(double ventMs, double vientDe) => ConditionsRoulage(
  masseKg: 84,
  cda: 0.32,
  crr: 0.005,
  rendementTransmission: 0.976,
  ventMs: ventMs,
  ventVientDeDeg: vientDe,
  vitesseMinMs: 4 / 3.6,
  vitesseMaxMs: 60 / 3.6,
);

void main() {
  group('Densité de l’air', () {
    test('1,225 kg/m³ au niveau de la mer à 15 °C', () {
      expect(densiteAir(altitudeM: 0, temperatureC: 15), closeTo(1.225, 0.001));
    });
    test('plus faible en altitude et au chaud', () {
      expect(
        densiteAir(altitudeM: 1000, temperatureC: 15),
        closeTo(1.087, 0.002),
      );
      expect(densiteAir(altitudeM: 0, temperatureC: 30), lessThan(1.2));
    });
  });

  group('Vent', () {
    test('vent du nord en roulant vers le nord = vent de face', () {
      expect(
        ventDeFace(ventMs: 5, ventVientDeDeg: 0, capDeg: 0),
        closeTo(5, 1e-9),
      );
      expect(
        ventDeFace(ventMs: 5, ventVientDeDeg: 0, capDeg: 180),
        closeTo(-5, 1e-9),
      );
      expect(
        ventDeFace(ventMs: 5, ventVientDeDeg: 0, capDeg: 90),
        closeTo(0, 1e-9),
      );
    });
    test('le vent de face ralentit, le vent de dos accélère', () {
      final calme = vitessePourPuissance(200, _seg(0), _cond);
      final face = vitessePourPuissance(200, _seg(0), _avecVent(4, 0));
      final dos = vitessePourPuissance(200, _seg(0), _avecVent(4, 180));
      expect(face, lessThan(calme));
      expect(dos, greaterThan(calme));
    });
  });

  group('Vitesse selon la puissance', () {
    test('200 W sur le plat : environ 33 km/h', () {
      final v = vitessePourPuissance(200, _seg(0), _cond) * 3.6;
      expect(v, inInclusiveRange(32, 35));
    });
    test('250 W à 8 % : environ 12 km/h', () {
      final v = vitessePourPuissance(250, _seg(8), _cond) * 3.6;
      expect(v, inInclusiveRange(11, 13.5));
    });
    test('calcul inverse cohérent', () {
      for (final pente in [-3.0, 0.0, 4.0, 10.0]) {
        for (final p in [120.0, 200.0, 300.0]) {
          final v = vitessePourPuissance(p, _seg(pente), _cond);
          if (v < _cond.vitesseMaxMs - 1e-6) {
            expect(
              puissancePourVitesse(v, _seg(pente), _cond),
              closeTo(p, 0.01),
            );
          }
        }
      }
    });
    test('descente à 8 % en roue libre : plafonnée à 60 km/h', () {
      expect(vitessePourPuissance(0, _seg(-8), _cond) * 3.6, closeTo(60, 1e-6));
    });
    test('montée à 0 W : vitesse minimale, jamais zéro', () {
      expect(vitessePourPuissance(0, _seg(6), _cond) * 3.6, closeTo(4, 1e-6));
    });
    test('plus la pente est forte, plus on va lentement', () {
      final v3 = vitessePourPuissance(250, _seg(3), _cond);
      final v6 = vitessePourPuissance(250, _seg(6), _cond);
      final v9 = vitessePourPuissance(250, _seg(9), _cond);
      expect(v3, greaterThan(v6));
      expect(v6, greaterThan(v9));
    });
  });

  group('Durée sur des segments', () {
    test('somme des temps, arrêt anticipé à la limite', () {
      final segs = [for (var i = 0; i < 10; i++) _seg(5)];
      final t1 = 1000 / vitessePourPuissance(250, _seg(5), _cond);
      expect(dureeSegments(segs, 250, _cond), closeTo(10 * t1, 1e-6));
      final limite = dureeSegments(segs, 250, _cond, limiteS: 2.5 * t1);
      expect(limite, closeTo(3 * t1, 1e-6));
    });
  });
}
