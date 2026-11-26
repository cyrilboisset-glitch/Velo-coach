// Règles tirées de la conférence « Nutrition du sport – triathlon » :
// plan d'hydratation des 2 %, glucides selon la durée, fenêtre pour
// manger, pause repas, chaleur, plan de sortie.
import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

/// Config de test : 1 gel de 25 g, 20 g/h (le choix de Cyril).
const _cfg = Config(
  cycliste: ConfigCycliste(poidsCyclisteKg: 78, poidsVeloKg: 9, ftpW: 250),
  manger: ConfigManger(
    toleranceMaxGh: 20,
    seuilAlerteG: 25,
    aliments: [Aliment('gel', 25)],
  ),
);

List<Alerte> _rouler(
  Coach c,
  double dureeS, {
  double puissanceW = 150,
  double? vitesseMs,
  double Function(double t)? vitesse,
  double Function(double t)? puissance,
}) {
  final alertes = <Alerte>[];
  for (var t = 0.0; t <= dureeS; t += 1) {
    alertes.addAll(
      c.tick(
        Echantillon(
          t: t,
          puissanceW: puissance?.call(t) ?? puissanceW,
          vitesseMs: vitesse?.call(t) ?? vitesseMs,
        ),
      ),
    );
  }
  return alertes;
}

void main() {
  group('Plan d’hydratation : rester sous 2 % de perte de poids', () {
    test('l’exemple de la conférence : 78 kg, 4 h, 1,2 L/h → 0,8 L/h', () {
      // Perte tolérée 2 % × 78 = 1,56 L ; (4 × 1,2 − 1,56) / 4 = 0,81.
      final h = Hydratation(
        const ConfigBoire(),
        250,
        poidsKg: 78,
        dureePrevueS: 4 * 3600,
      )..sudationLh = 1.2;
      expect(h.ratioPlan * 1.2, closeTo(0.81, 1e-9));
    });

    test(
      'sans poids : on remplace toute la sueur (comportement d’origine)',
      () {
        final h = Hydratation(const ConfigBoire(), 250)..sudationLh = 1.2;
        expect(h.ratioPlan, 1);
      },
    );

    test('sortie courte : jamais moins de la moitié de la sueur', () {
      // 1 h à 0,7 L/h = 0,7 L, très sous les 1,56 L tolérés.
      final h = Hydratation(
        const ConfigBoire(),
        250,
        poidsKg: 78,
        dureePrevueS: 3600,
      )..sudationLh = 0.7;
      expect(h.ratioPlan, 0.5);
    });

    test('si la sortie dure plus que prévu, on boit davantage', () {
      final h = Hydratation(
        const ConfigBoire(),
        250,
        poidsKg: 78,
        dureePrevueS: 3600,
      );
      for (var i = 0; i < 3 * 3600; i++) {
        h.maj(200, 1, 25, 50);
      }
      // 3 h à environ 1 L/h : bien au-delà de la durée prévue d'1 h, donc
      // plus rien de « restant » : part à boire = (perte − 1,56) / perte.
      expect(h.perteL, greaterThan(2.5));
      expect(h.ratioPlan, closeTo((h.perteL - 1.56) / h.perteL, 1e-9));
      expect(h.ratioPlan, greaterThan(0.5));
    });

    test('suivre le plan garde la perte sous 2 % (3 h à 25 °C)', () {
      final c = Coach(_cfg, dureePrevueS: 3 * 3600);
      c.meteo = const Meteo(temperatureC: 25, humiditePct: 50);
      for (var t = 0.0; t <= 3 * 3600; t += 1) {
        for (final a in c.tick(Echantillon(t: t, puissanceW: 165))) {
          if (a.code == 'boire') c.boit(150);
        }
      }
      final e = c.etat;
      expect(e.eauPerdueL, greaterThan(2.0));
      // Perte de poids = sueur − eau bue, en % de 78 kg.
      expect(e.eauPerteEstimeePct, lessThan(2.3));
      expect(e.eauPerteEstimeePct, greaterThan(1.0));
    });
  });

  group('Glucides : durée, premier apport, pas de rattrapage', () {
    test('sortie prévue de moins de 1 h 15 : aucun rappel de glucides', () {
      final c = Coach(_cfg, dureePrevueS: 3600);
      final alertes = _rouler(c, 3600, puissanceW: 180, vitesseMs: 7);
      expect(alertes.where((a) => a.type == TypeAlerte.manger), isEmpty);
    });

    test('rien avant 40 min, puis un gel quand le retard atteint 25 g', () {
      final c = Coach(_cfg, dureePrevueS: 3 * 3600);
      final alertes = _rouler(c, 3 * 3600, puissanceW: 150, vitesseMs: 7);
      final mange = alertes.where((a) => a.code == 'manger').toList();
      expect(mange, isNotEmpty);
      // 20 g/h à partir de 2 400 s : 25 g après 4 500 s, donc à 6 900 s.
      expect(mange.first.t, closeTo(6900, 10));
      expect(mange.first.texte, 'Mange 1 gel');
    });

    test('le retard ne s’accumule pas avant le premier apport', () {
      final c = Coach(_cfg, dureePrevueS: 3 * 3600);
      _rouler(c, 2300, puissanceW: 150, vitesseMs: 7);
      expect(c.etat.glucidesRetardG, 0);
      expect(c.etat.glucidesBrulesG, greaterThan(40));
    });
  });

  group(
    'Fenêtre pour manger : jamais en descente, en forte montée ni vite',
    () {
      test('au-dessus de 30 km/h, l’alerte attend', () {
        final c = Coach(_cfg, dureePrevueS: 4 * 3600);
        // 31 km/h = 8,6 m/s pendant 3 h, puis 20 km/h.
        final alertes = _rouler(
          c,
          4 * 3600,
          puissanceW: 150,
          vitesse: (t) => t < 3 * 3600 ? 8.6 : 5.5,
        );
        final premiere = alertes.firstWhere((a) => a.code == 'manger');
        expect(premiere.t, greaterThanOrEqualTo(3 * 3600));
        expect(premiere.t, lessThan(3 * 3600 + 120));
      });

      test('en descente, l’alerte attend le replat', () {
        // 15 km plats, 6 km de descente à −6 %, plats ensuite.
        final p = Parcours.depuisProfil(const [
          Troncon(15000, 0),
          Troncon(6000, -6),
          Troncon(20000, 0),
        ]);
        final c = Coach(_cfg, parcours: p, dureePrevueS: 4 * 3600);
        // Roule à 20 km/h : 15 km en 2 700 s (40 min), la descente de
        // 2 700 s à 3 780 s.
        final alertes = <Alerte>[];
        for (var t = 0.0; t <= 4500; t += 1) {
          final d = 5.55 * t;
          alertes.addAll(
            c.tick(
              Echantillon(
                t: t,
                puissanceW: 150,
                vitesseMs: 5.55,
                distanceParcoursM: d.clamp(0, p.longueurM),
              ),
            ),
          );
        }
        for (final a in alertes.where((a) => a.code == 'manger')) {
          final pente = 100 * p.segmentA(5.55 * a.t).pente;
          expect(pente, greaterThanOrEqualTo(-2), reason: a.toString());
        }
      });

      test('l’état dit si on peut manger', () {
        final c = Coach(_cfg);
        c.tick(const Echantillon(t: 0, puissanceW: 150, vitesseMs: 9));
        expect(c.etat.fenetreMangerOuverte, isFalse);
        c.tick(const Echantillon(t: 1, puissanceW: 150, vitesseMs: 6));
        expect(c.etat.fenetreMangerOuverte, isTrue);
      });
    },
  );

  group('Pause repas : écart de 200 g, ou arrêt de plus de 10 min', () {
    test(
      'conseillée quand brûlés − mangés atteint 200 g, puis 200 g plus loin',
      () {
        final c = Coach(_cfg, dureePrevueS: 6 * 3600);
        final alertes = _rouler(c, 5 * 3600, puissanceW: 180, vitesseMs: 6);
        final pauses = alertes.where((a) => a.code == 'pause_repas').toList();
        expect(pauses.length, 2);
        expect(pauses.first.texte, 'Pause repas conseillée');
        // 180 W = 72 % de FTP : 65 % de glucides, soit 105 g/h brûlés ;
        // 200 g en 1 h 54 (6 860 s), puis encore 200 g plus loin.
        expect(pauses.first.t, closeTo(6865, 30));
        expect(pauses[1].t - pauses.first.t, closeTo(6865, 60));
      },
    );

    test('un arrêt de plus de 10 min compte comme pause faite', () {
      final c = Coach(_cfg, dureePrevueS: 6 * 3600);
      // 1 h 30 de route (157 g d'écart), 12 min à l'arrêt sans pédaler,
      // puis on repart.
      bool arret(double t) => t >= 5400 && t < 5400 + 720;
      final alertes = _rouler(
        c,
        4 * 3600,
        vitesse: (t) => arret(t) ? 0 : 6,
        puissance: (t) => arret(t) ? 0 : 180,
      );
      final pauses = alertes.where((a) => a.code == 'pause_repas').toList();
      // Sans l'arrêt, la pause aurait été conseillée vers 6 865 s. Avec
      // la pause faite, le prochain seuil est 200 g plus loin.
      expect(pauses.where((a) => a.t < 10000), isEmpty);
      expect(pauses.first.t, closeTo(5400 + 720 + 6865, 200));
    });
  });

  group('Chaleur', () {
    test('rien sous 30 °C', () {
      final c = Coach(_cfg)
        ..meteo = const Meteo(temperatureC: 29, humiditePct: 50);
      expect(
        _rouler(c, 600).where((a) => a.type == TypeAlerte.chaleur),
        isEmpty,
      );
    });

    test('rappel à 30 °C, puis toutes les 45 min', () {
      final c = Coach(_cfg)
        ..meteo = const Meteo(temperatureC: 31, humiditePct: 40);
      final chaud = _rouler(
        c,
        7200,
        vitesseMs: 6,
      ).where((a) => a.type == TypeAlerte.chaleur).toList();
      expect(chaud.length, 3); // 0, 45 min, 90 min
      expect(chaud.first.code, 'chaleur');
      expect(chaud.first.texte, 'Chaud 31° : bois, arrose ta nuque');
      expect(chaud[1].t - chaud[0].t, closeTo(2700, 60));
    });

    test('très chaud à 35 °C, texte de 40 caractères au plus', () {
      final c = Coach(_cfg)
        ..meteo = const Meteo(temperatureC: 36, humiditePct: 30);
      final a = _rouler(c, 120).firstWhere((a) => a.type == TypeAlerte.chaleur);
      expect(a.code, 'chaleur_forte');
      expect(a.texte, 'Très chaud 36° : ralentis, ombre');
      expect(a.texte.length, lessThanOrEqualTo(40));
      expect(a.texteVocal, contains('arrête-toi'));
    });

    test('la chaleur passe après la montée, manger et boire', () {
      expect(TypeAlerte.chaleur.index, greaterThan(TypeAlerte.boire.index));
    });
  });

  group('Plan de sortie', () {
    const meteo = Meteo(temperatureC: 25, humiditePct: 50);

    test('moins de 1 h 15 : de l’eau, pas de glucides', () {
      final p = planifierSortie(
        cfg: _cfg,
        dureeS: 3600,
        meteo: meteo,
        portionG: 25,
      );
      expect(p.glucidesNecessaires, isFalse);
      expect(p.portions, 0);
      expect(p.repereGh, 0);
    });

    test('3 h à 20 g/h : 40 premières minutes exclues, portions + marge', () {
      final p = planifierSortie(
        cfg: _cfg,
        dureeS: 3 * 3600,
        meteo: meteo,
        portionG: 7.5,
      );
      // 20 g/h × (3 h − 40 min) = 46,7 g → 7 portions + 1 de marge.
      expect(p.glucidesTotalG, closeTo(46.67, 0.01));
      expect(p.portions, 8);
      expect(p.repereGh, 90);
    });

    test('repères de la littérature selon la durée', () {
      expect(repereGlucidesGh(3000), 0);
      expect(repereGlucidesGh(5400), 30);
      expect(repereGlucidesGh(8000), 60);
      expect(repereGlucidesGh(10800), 90);
    });

    test('eau : plan des 2 %, avant-départ 5 à 10 ml/kg', () {
      final p = planifierSortie(
        cfg: _cfg,
        dureeS: 4 * 3600,
        meteo: meteo,
        portionG: 25,
        sodiumMgParL: 600,
      );
      expect(p.eauSueurL, greaterThan(3.0));
      expect(p.perteSansBoirePct, greaterThan(3.5));
      // On boit pour rester autour de 2 %.
      expect(p.perteAvecPlanPct, closeTo(2.0, 0.1));
      expect(p.eauABoireL, closeTo(p.eauSueurL - 1.56, 0.01));
      expect(p.eauAvantDepartMlMin, 390);
      expect(p.eauAvantDepartMlMax, 780);
      expect(p.sodiumMgH, closeTo(p.eauABoireL / 4 * 600, 1e-9));
      expect(p.eauManquanteL(1.0), closeTo(p.eauABoireL - 1.0, 1e-9));
      expect(p.eauManquanteL(10), 0);
    });

    test('durée estimée d’un parcours : plus longue avec du dénivelé', () {
      final plat = Parcours.depuisProfil(const [Troncon(30000, 0)]);
      final vallonne = Parcours.depuisProfil(const [
        Troncon(15000, 3),
        Troncon(15000, -3),
      ]);
      const m = Meteo(temperatureC: 15, humiditePct: 50);
      final tp = estimerDureeParcoursS(plat, _cfg, m);
      final tv = estimerDureeParcoursS(vallonne, _cfg, m);
      expect(tp, inInclusiveRange(3000, 4500)); // environ 31 km/h
      expect(tv, isNot(closeTo(tp, 1)));
    });
  });
}
