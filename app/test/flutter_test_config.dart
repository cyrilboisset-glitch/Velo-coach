// Chargé avant chaque fichier de test : remplace la police de test (des
// carrés très larges) par les vraies polices de l'appli et d'Android
// (Roboto, icônes), pour que les débordements détectés soient réels.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _charger(String famille, List<String> fichiers) async {
  final chargeur = FontLoader(famille);
  var un = false;
  for (final f in fichiers) {
    final fichier = File(f);
    if (!fichier.existsSync()) continue;
    final octets = fichier.readAsBytesSync();
    chargeur.addFont(Future.value(ByteData.sublistView(octets)));
    un = true;
  }
  if (un) await chargeur.load();
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final racine = Platform.environment['FLUTTER_ROOT'] ?? '';
  final materiel = '$racine/bin/cache/artifacts/material_fonts';
  await _charger('Roboto', [
    for (final g in ['Regular', 'Medium', 'Bold']) '$materiel/Roboto-$g.ttf',
  ]);
  await _charger('MaterialIcons', ['$materiel/MaterialIcons-Regular.otf']);
  await _charger('Space Grotesk', ['fonts/SpaceGrotesk.ttf']);
  await _charger('Barlow Condensed', [
    for (final g in ['Medium', 'SemiBold', 'Bold'])
      'fonts/BarlowCondensed-$g.ttf',
  ]);
  await testMain();
}
