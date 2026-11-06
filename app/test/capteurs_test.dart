import 'package:flutter_test/flutter_test.dart';
import 'package:velo_coach/capteurs.dart';

void main() {
  group('Mesure de puissance (0x2A63)', () {
    test('puissance seule', () {
      // drapeaux 0x0000, 250 W
      final m = lireMesurePuissance([0x00, 0x00, 0xFA, 0x00]);
      expect(m.puissanceW, 250);
      expect(m.tours, isNull);
    });

    test('équilibre gauche/droite + tours de pédalier', () {
      // drapeaux 0x21 : équilibre (1 octet) + tours de pédalier
      // 180 W, équilibre 100, 1000 tours, instant 2048 (2 s)
      final m = lireMesurePuissance([
        0x21,
        0x00,
        0xB4,
        0x00,
        0x64,
        0xE8,
        0x03,
        0x00,
        0x08,
      ]);
      expect(m.puissanceW, 180);
      expect(m.tours, 1000);
      expect(m.instant, 2048);
    });

    test('tours de roue avant les tours de pédalier', () {
      // drapeaux 0x30 : roue (6 octets) puis pédalier
      final m = lireMesurePuissance([
        0x30,
        0x00,
        0x2C,
        0x01,
        1,
        2,
        3,
        4,
        5,
        6,
        0x0A,
        0x00,
        0x00,
        0x04,
      ]);
      expect(m.puissanceW, 300);
      expect(m.tours, 10);
      expect(m.instant, 1024);
    });
  });

  group('Cadence', () {
    test('2 tours en 1,5 s = 80 tr/min', () {
      expect(cadenceEntre(100, 1024, 102, 1024 + 1536), closeTo(80, 1e-9));
    });
    test('compteurs repassés par zéro', () {
      expect(
        cadenceEntre(65535, 65000, 0, 65000 + 768 - 65536),
        closeTo(80, 1e-9),
      );
    });
    test('même instant : pas de cadence', () {
      expect(cadenceEntre(1, 10, 2, 10), isNull);
    });
  });

  test('fréquence cardiaque 8 et 16 bits', () {
    expect(lireMesureCardio([0x00, 72]), 72);
    expect(lireMesureCardio([0x01, 0x2C, 0x01]), 300);
  });
}
