import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

void main() {
  group('Détection des montées (profil)', () {
    test('un col de 8 km à 6 %, une bosse trop courte ignorée', () {
      final p = Parcours.depuisProfil(const [
        Troncon(5000, 0),
        Troncon(8000, 6),
        Troncon(3000, -5),
        Troncon(600, 5), // 600 m : trop court
        Troncon(2000, 0),
      ]);
      expect(p.longueurM, closeTo(18600, 1e-6));
      expect(p.montees, hasLength(1));
      final m = p.montees.single;
      expect(m.debutM, closeTo(5000, 120));
      expect(m.finM, closeTo(13000, 120));
      expect(m.deniveleM, closeTo(480, 15));
      expect(m.penteMoyenne * 100, closeTo(6, 0.2));
    });

    test('un replat de 200 m ne coupe pas la montée, un de 600 m oui', () {
      final court = Parcours.depuisProfil(const [
        Troncon(2000, 0),
        Troncon(3000, 7),
        Troncon(200, 0),
        Troncon(3000, 7),
        Troncon(2000, 0),
      ]);
      expect(court.montees, hasLength(1));
      expect(court.montees.single.longueurM, closeTo(6200, 150));

      final long = Parcours.depuisProfil(const [
        Troncon(2000, 0),
        Troncon(3000, 7),
        Troncon(600, 0),
        Troncon(3000, 7),
        Troncon(2000, 0),
      ]);
      expect(long.montees, hasLength(2));
    });

    test('une pente moyenne sous 3 % n’est pas une montée', () {
      final p = Parcours.depuisProfil(const [
        Troncon(1000, 0),
        Troncon(5000, 2.5),
        Troncon(1000, 0),
      ]);
      expect(p.montees, isEmpty);
    });

    test('un faux plat long avant le col n’est pas compté dedans', () {
      final p = Parcours.depuisProfil(const [
        Troncon(4000, 1.5),
        Troncon(5000, 7),
        Troncon(1000, 0),
      ]);
      expect(p.montees, hasLength(1));
      expect(p.montees.single.debutM, closeTo(4000, 150));
    });

    test('résiste au bruit d’altitude du GPS (±2 m)', () {
      final alea = math.Random(42);
      // Trace vers le nord, un point tous les 20 m.
      final pts = <PointGps>[];
      for (var d = 0.0; d <= 15000; d += 20) {
        final alt = d < 4000
            ? 300.0
            : d < 10000
            ? 300 + (d - 4000) * 0.065
            : 690.0;
        pts.add(
          PointGps(45.4 + d / 111195, 6.0, alt + (alea.nextDouble() * 4 - 2)),
        );
      }
      final p = Parcours.depuisPoints(pts);
      expect(p.longueurM, closeTo(15000, 15));
      expect(p.montees, hasLength(1));
      expect(p.montees.single.penteMoyenne * 100, closeTo(6.5, 0.4));
      expect(p.segments.first.capDeg, closeTo(0, 0.5));
    });
  });

  group('Outils GPS', () {
    test('1° de latitude ≈ 111,2 km', () {
      expect(distanceGps(45, 6, 46, 6), closeTo(111195, 10));
    });
    test('caps', () {
      expect(capGps(45, 6, 45.01, 6), closeTo(0, 0.01));
      expect(capGps(45, 6, 45, 6.01), closeTo(90, 0.01));
      expect(capGps(45, 6, 44.99, 6), closeTo(180, 0.01));
      expect(capGps(45, 6, 45, 5.99), closeTo(270, 0.01));
    });
  });

  group('Segments', () {
    final p = Parcours.depuisProfil(const [Troncon(3000, 0), Troncon(2000, 5)]);
    test('segmentsEntre coupe aux bornes', () {
      final s = p.segmentsEntre(1010, 4020);
      final total = s.fold(0.0, (a, x) => a + x.longueurM);
      expect(total, closeTo(3010, 1e-6));
      expect(s.first.debutM, 1010);
      expect(s.last.finM, closeTo(4020, 1e-6));
    });
    test('segmentA', () {
      expect(p.segmentA(0).debutM, 0);
      expect(p.segmentA(1012).debutM, 1000);
      expect(p.segmentA(99999).finM, closeTo(5000, 1e-6));
    });
    test('montée en cours et prochaine montée', () {
      final m = p.montees.single;
      expect(p.monteeA(100), isNull);
      expect(p.prochaineMontee(100)?.index, 0);
      expect(p.monteeA(m.debutM + 10)?.index, 0);
      expect(p.prochaineMontee(m.debutM + 10), isNull);
    });
  });
}
