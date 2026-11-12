// Captures d'écran (PNG) pour regarder le rendu, avec les vraies polices.
// Ne tourne que sur demande :
//   CAPTURES=1 flutter test test/captures_test.dart --update-goldens
// Les images vont dans test/captures/ (non versionné).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velo_coach/annonces.dart';
import 'package:velo_coach/capteurs.dart';
import 'package:velo_coach/charte.dart';
import 'package:velo_coach/ecran_nutrition.dart';
import 'package:velo_coach/main.dart';
import 'package:velo_coach/reglages.dart';
import 'package:velo_coach/sortie.dart';
import 'package:velo_coach/suivi.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

final _parcours = Parcours.depuisProfil(const [
  Troncon(9000, 0.4),
  Troncon(6000, 6.5),
  Troncon(5000, -5),
  Troncon(8000, 0.5),
  Troncon(3000, 7.5),
  Troncon(9000, -2),
]);

Future<Sortie> _sortie() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return Sortie(
    reglages: Reglages(prefs),
    capteurs: Capteurs(prefs),
    suivi: Suivi(prefs),
    annonces: Annonces(),
  )..choisirParcours(_parcours, 'Col du Granier.gpx');
}

/// Fait rouler le coach jusqu'au milieu du premier col.
void _rouler(Sortie s) {
  final cfg = s.reglages.config();
  final coach = Coach(cfg, parcours: _parcours);
  final cond = ConditionsRoulage.depuis(cfg, coach.meteo);
  final col = _parcours.montees.first;
  var d = 0.0;
  var t = 0.0;
  while (d < col.debutM + 0.55 * col.longueurM) {
    final cible = coach.etat.puissanceCibleW;
    final p = cible != null && col.contient(d) ? cible + 12 : 175.0;
    for (final a in coach.tick(
      Echantillon(t: t, puissanceW: p, distanceParcoursM: d),
    )) {
      s.derniereAlerte = a;
      s.alertes.add(a);
    }
    d += vitessePourPuissance(p, _parcours.segmentA(d), cond);
    t += 1;
  }
  s
    ..coach = coach
    ..debut = DateTime.now().subtract(Duration(seconds: t.round()))
    ..distanceM = d
    ..positionSimuleeM = d
    ..puissance3sW = coach.etat.puissanceCibleW! + 12
    ..active = true;
}

void main() {
  final actif = Platform.environment['CAPTURES'] == '1';

  void telephone(WidgetTester t, {double hauteur = 2400}) {
    t.view.physicalSize = Size(1080, hauteur);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
  }

  testWidgets('accueil', skip: !actif, (t) async {
    telephone(t, hauteur: 5200);
    final s = await _sortie();
    await t.pumpWidget(
      AppliCoach(sortie: s, prefs: await SharedPreferences.getInstance()),
    );
    await t.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(AppliCoach),
      matchesGoldenFile('captures/accueil.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sortie en cours', skip: !actif, (t) async {
    telephone(t, hauteur: 3300);
    final s = await _sortie();
    _rouler(s);
    await t.pumpWidget(
      AppliCoach(sortie: s, prefs: await SharedPreferences.getInstance()),
    );
    await t.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(AppliCoach),
      matchesGoldenFile('captures/sortie.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nutrition', skip: !actif, (t) async {
    telephone(t, hauteur: 3600);
    final s = await _sortie();
    await t.pumpWidget(
      MaterialApp(
        theme: themeGoatout(),
        home: EcranNutrition(reglages: s.reglages),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(EcranNutrition),
      matchesGoldenFile('captures/nutrition.png'),
    );
  });
}
