import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velo_coach/ecran_radar.dart';

void main() {
  group('Paquets radar V1 (format Garmin, non vérifié sur le L508)', () {
    test('un battement de cœur n’est pas un paquet de véhicules', () {
      expect(lireMenacesV1([0x32]), isNull);
    });

    test('un véhicule : identifiant, distance, indicateur', () {
      final v = lireMenacesV1([0x42, 0x83, 45, 0x01])!;
      expect(v, hasLength(1));
      expect(v.single.id, 3);
      expect(v.single.distanceM, 45);
      expect(v.single.indicateur, 1);
    });

    test('deux véhicules, un emplacement vide ignoré', () {
      final v = lireMenacesV1([0x12, 0x81, 80, 0, 0x82, 30, 1, 0x00, 0xFF, 0])!;
      expect(v.map((x) => x.distanceM), [80, 30]);
    });

    test('un paquet de 6 octets (amplitude) est ignoré', () {
      expect(lireMenacesV1([0x06, 1, 5, 0, 0, 9]), isNull);
    });
  });

  testWidgets('l’écran Test radar s’affiche', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: EcranRadar()));
    expect(find.text('Chercher les appareils'), findsOneWidget);
  });
}
