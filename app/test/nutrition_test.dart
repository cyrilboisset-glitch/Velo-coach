import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velo_coach/ecran_nutrition.dart';
import 'package:velo_coach/reglages.dart';

void main() {
  test('glucides d’une portion depuis l’étiquette « pour 100 g »', () {
    // Mini-sachet Haribo : 9,8 g à 77 g de glucides pour 100 g.
    expect(
      glucidesPortion(poidsPortionG: 9.8, glucidesPour100G: 77),
      closeTo(7.546, 1e-9),
    );
  });

  test('rythme affiché', () {
    const gel = ProduitNutrition(nom: 'gel', glucidesG: 25);
    expect(rythme(gel, 20), '1 gel toutes les 1 h 15');
    expect(rythme(gel, 60), '1 gel toutes les 25 min');
    expect(rythme(gel, 25), '1 gel toutes les 1 h');
    expect(rythme(gel, 0), 'aucun glucide prévu');
  });

  test('réglages par défaut, puis produits personnels gardés', () async {
    SharedPreferences.setMockInitialValues({});
    final r = Reglages(await SharedPreferences.getInstance());
    expect(r.produitChoisi.nom, 'mini-sachet Haribo');
    expect(r.objectifGh, 20);
    expect(r.config().manger.toleranceMaxGh, 20);
    expect(r.config().manger.seuilAlerteG, 7.5);

    await r.enregistrerNutrition(
      produits: const [
        ProduitNutrition(nom: 'gel', glucidesG: 25),
        ProduitNutrition(nom: 'barre', glucidesG: 40),
      ],
      indexProduit: 1,
      objectifGh: 45,
      boissonGParL: 60,
    );
    final r2 = Reglages(await SharedPreferences.getInstance());
    expect(r2.produits, hasLength(2));
    expect(r2.produitChoisi.nom, 'barre');
    final m = r2.config().manger;
    expect(m.toleranceMaxGh, 45);
    expect(m.seuilAlerteG, 40);
    expect(m.aliments.single.nom, 'barre');
    expect(m.glucidesParLitreBoisson, 60);
  });
}
