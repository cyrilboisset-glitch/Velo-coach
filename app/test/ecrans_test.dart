// Ouvre chaque écran en simulation : une erreur d'affichage (débordement,
// bouton mal construit…) fait échouer le test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velo_coach/annonces.dart';
import 'package:velo_coach/capteurs.dart';
import 'package:velo_coach/ecran_nutrition.dart';
import 'package:velo_coach/main.dart';
import 'package:velo_coach/reglages.dart';
import 'package:velo_coach/sortie.dart';
import 'package:velo_coach/suivi.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

Future<Sortie> _sortie() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return Sortie(
    reglages: Reglages(prefs),
    capteurs: Capteurs(prefs),
    suivi: Suivi(prefs),
    annonces: Annonces(),
  );
}

void main() {
  // Écran de téléphone : 412 x 915 points.
  void telephone(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
  }

  testWidgets('accueil avant la sortie', (t) async {
    telephone(t);
    final s = await _sortie();
    await t.pumpWidget(
      AppliCoach(sortie: s, prefs: await SharedPreferences.getInstance()),
    );
    expect(find.text('Vélo Coach'), findsOneWidget);
    expect(find.text('Démarrer la sortie'), findsOneWidget);
    expect(find.text('Ma nutrition'), findsOneWidget);
    expect(
      find.textContaining('mini-sachet Haribo toutes les'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('accueil avec un parcours importé', (t) async {
    telephone(t);
    final s = await _sortie();
    s.choisirParcours(
      Parcours.depuisProfil(const [
        Troncon(3000, 0),
        Troncon(5000, 7),
        Troncon(2000, -5),
      ]),
      'col.gpx',
    );
    await t.pumpWidget(
      AppliCoach(sortie: s, prefs: await SharedPreferences.getInstance()),
    );
    expect(find.textContaining('col.gpx'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('écran de sortie en cours (gros chiffres)', (t) async {
    telephone(t);
    final s = await _sortie();
    s.coach = Coach(s.reglages.config());
    s.coach!.tick(const Echantillon(t: 0, puissanceW: 150));
    s.coach!.tick(const Echantillon(t: 1, puissanceW: 150));
    s.debut = DateTime.now();
    s.active = true;
    await t.pumpWidget(
      AppliCoach(sortie: s, prefs: await SharedPreferences.getInstance()),
    );
    expect(find.text('Arrêter la sortie'), findsOneWidget);
    expect(find.text('Puissance 3 s'), findsOneWidget);
    expect(find.text('Glucides en retard'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('écran Réglages', (t) async {
    telephone(t);
    final s = await _sortie();
    await t.pumpWidget(MaterialApp(home: EcranReglages(reglages: s.reglages)));
    expect(find.text('Enregistrer'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'écran Ma nutrition : ajouter un produit à partir du « pour 100 g »',
    (t) async {
      telephone(t);
      final s = await _sortie();
      await t.pumpWidget(
        MaterialApp(home: EcranNutrition(reglages: s.reglages)),
      );
      final liste = find.byType(ListView).first;
      expect(find.text('mini-sachet Haribo'), findsOneWidget);

      await t.dragUntilVisible(
        find.text('Ajouter un produit'),
        liste,
        const Offset(0, -200),
      );
      await t.tap(find.text('Ajouter un produit'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await t.enterText(
        find.widgetWithText(TextField, 'Nom (court)'),
        'pâtes de fruits',
      );
      await t.tap(find.text('pour 100 g'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Glucides pour 100 g'),
        '60',
      );
      await t.enterText(
        find.widgetWithText(
          TextField,
          "Poids d'une portion (gel, barre, sachet)",
        ),
        '30',
      );
      await t.pump();
      expect(find.text('Glucides par portion : 18 g'), findsOneWidget);
      await t.tap(find.text('Valider'));
      await t.pumpAndSettle();
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'la fenêtre doit se fermer',
      );
      expect(find.text('pâtes de fruits'), findsOneWidget);

      await t.dragUntilVisible(
        find.text('Enregistrer'),
        liste,
        const Offset(0, -200),
      );
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(s.reglages.produits.last.nom, 'pâtes de fruits');
      expect(s.reglages.produitChoisi.glucidesG, 18);
    },
  );
}
