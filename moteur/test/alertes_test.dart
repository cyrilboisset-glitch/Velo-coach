import 'package:test/test.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

CandidatAlerte _cand(
  TypeAlerte type,
  String code,
  List<String> emis, {
  int sousPriorite = 0,
}) => CandidatAlerte(
  type: type,
  code: code,
  sousPriorite: sousPriorite,
  message: Message('Texte $code', 'Voix $code'),
  siEmise: () => emis.add(code),
);

void main() {
  group('Arbitre', () {
    test('priorité montée > manger > boire, une alerte par minute', () {
      final arbitre = Arbitre(const ConfigAlertes());
      final emis = <String>[];
      final enAttente = {'montee', 'manger', 'boire'};
      final types = {
        'montee': TypeAlerte.montee,
        'manger': TypeAlerte.manger,
        'boire': TypeAlerte.boire,
      };
      final instants = <double>[];
      for (var t = 0.0; t < 300; t += 1) {
        // Les alertes non envoyées restent proposées, comme dans le coach.
        final c = [
          for (final code in enAttente) _cand(types[code]!, code, emis),
        ];
        final a = arbitre.choisir(t, c);
        if (a != null) {
          enAttente.remove(a.code);
          instants.add(t);
        }
      }
      expect(emis, ['montee', 'manger', 'boire']);
      expect(instants, [0, 60, 120]);
    });

    test('à type égal, la sous-priorité départage', () {
      final arbitre = Arbitre(const ConfigAlertes());
      final emis = <String>[];
      final a = arbitre.choisir(0, [
        _cand(TypeAlerte.manger, 'manger', emis),
        _cand(TypeAlerte.manger, 'manger_avant_col', emis, sousPriorite: 1),
      ]);
      expect(a?.code, 'manger_avant_col');
      expect(emis, ['manger_avant_col']);
    });

    test('les alertes non choisies ne déclenchent pas leur action', () {
      final arbitre = Arbitre(const ConfigAlertes());
      final emis = <String>[];
      arbitre.choisir(0, [
        _cand(TypeAlerte.boire, 'boire', emis),
        _cand(TypeAlerte.montee, 'montee', emis),
      ]);
      expect(emis, ['montee']);
    });

    test('option sans accents', () {
      final arbitre = Arbitre(const ConfigAlertes(sansAccents: true));
      final a = arbitre.choisir(0, [
        CandidatAlerte(
          type: TypeAlerte.montee,
          code: 'x',
          message: Messages.leveLePied(puissanceW: 240, reservePct: 20),
          siEmise: () {},
        ),
      ]);
      expect(a?.texte, 'Leve le pied : 240 W, reserve 20 %');
      // La voix garde les accents (meilleure prononciation).
      expect(a?.texteVocal, contains('Lève'));
    });
  });

  group('Messages', () {
    test(
      'textes courts : 40 caractères au plus, même avec des valeurs extrêmes',
      () {
        final textes = [
          Messages.annonceMontee(
            longueurM: 112400,
            penteMoyenne: 0.125,
            puissanceW: 1265,
          ),
          Messages.annonceMontee(
            longueurM: 8200,
            penteMoyenne: 0.061,
            puissanceW: 265,
          ),
          Messages.tiens(puissanceW: 1265, resteM: 112400),
          Messages.leveLePied(puissanceW: 1265, reservePct: -40),
          Messages.leveLePied(puissanceW: 240, reservePct: 100),
          Messages.mangeAvantCol(dansS: 900),
          Messages.mange(retardG: 1250),
          Messages.bois(retardMl: 12500),
        ];
        for (final m in textes) {
          expect(m.court.length, lessThanOrEqualTo(40), reason: m.court);
          expect(m.vocal, isNotEmpty);
        }
      },
    );

    test('format français', () {
      expect(
        Messages.annonceMontee(
          longueurM: 8200,
          penteMoyenne: 0.061,
          puissanceW: 264.6,
        ).court,
        'Montée 8,2 km à 6,1 % : tiens 265 W',
      );
      expect(
        Messages.tiens(puissanceW: 265, resteM: 3100).court,
        'Tiens 265 W, reste 3,1 km',
      );
      expect(
        Messages.leveLePied(puissanceW: 240, reservePct: 19.6).court,
        'Lève le pied : 240 W, réserve 20 %',
      );
      expect(
        Messages.mangeAvantCol(dansS: 720).court,
        'Mange avant le col (dans 12 min)',
      );
      expect(
        Messages.mange(retardG: 32.4).court,
        'Mange : retard 32 g de glucides',
      );
      expect(Messages.bois(retardMl: 160).court, 'Bois : retard 160 ml');
    });

    test('sansAccents', () {
      expect(
        sansAccents('Élève à l’été, ça côtoie l’œuf'),
        "Eleve a l'ete, ca cotoie l'oeuf",
      );
    });
  });
}
