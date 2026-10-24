import 'config.dart';
import 'messages.dart';

/// Types d'alerte, rangés par priorité [CDC] : montée > manger > boire.
enum TypeAlerte { montee, manger, boire }

/// Une alerte envoyée au cycliste.
class Alerte {
  const Alerte({
    required this.t,
    required this.type,
    required this.code,
    required this.texte,
    required this.texteVocal,
  });

  /// Instant (s depuis le départ).
  final double t;
  final TypeAlerte type;

  /// Code stable pour le journal (ex. « manger_avant_col »).
  final String code;

  /// Texte court (notification, BiNavi).
  final String texte;

  /// Texte à lire à voix haute.
  final String texteVocal;

  @override
  String toString() => '${t.toStringAsFixed(0)} s [$code] $texte';
}

/// Alerte possible à cet instant, avant arbitrage.
class CandidatAlerte {
  const CandidatAlerte({
    required this.type,
    required this.code,
    required this.message,
    required this.siEmise,
    this.sousPriorite = 0,
  });

  final TypeAlerte type;
  final String code;
  final Message message;

  /// Appelé seulement si l'alerte est réellement envoyée.
  final void Function() siEmise;

  /// À type égal, la plus grande passe en premier.
  final int sousPriorite;
}

/// Choisit au plus une alerte par minute, la plus prioritaire.
///
/// Les alertes non choisies ne sont pas perdues : chaque fonction les
/// repropose tant que la situation le justifie (ex. retard de boisson).
class Arbitre {
  Arbitre(this.cfg);

  final ConfigAlertes cfg;
  double? derniereEmissionT;

  Alerte? choisir(double t, List<CandidatAlerte> candidats) {
    if (candidats.isEmpty) return null;
    final derniere = derniereEmissionT;
    if (derniere != null && t - derniere < cfg.intervalleMinS) return null;
    final tries = [...candidats]
      ..sort((a, b) {
        final c = a.type.index.compareTo(b.type.index);
        return c != 0 ? c : b.sousPriorite.compareTo(a.sousPriorite);
      });
    final choisi = tries.first;
    choisi.siEmise();
    derniereEmissionT = t;
    var court = choisi.message.court;
    if (cfg.sansAccents) court = sansAccents(court);
    if (court.length > cfg.longueurMaxTexte) {
      court = '${court.substring(0, cfg.longueurMaxTexte - 1)}…';
    }
    return Alerte(
      t: t,
      type: choisi.type,
      code: choisi.code,
      texte: court,
      texteVocal: choisi.message.vocal,
    );
  }
}
