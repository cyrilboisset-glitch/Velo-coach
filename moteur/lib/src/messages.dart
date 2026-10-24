/// Textes des alertes : une version courte (notification, BiNavi,
/// 40 caractères au plus) et une version à lire à voix haute.
class Message {
  const Message(this.court, this.vocal);
  final String court;
  final String vocal;
}

String _dec1(double x) => x.toStringAsFixed(1).replaceAll('.', ',');
String _km(double m) => _dec1(m / 1000);
String _ent(double x) => x.round().toString();

abstract final class Messages {
  /// [reserveSommetPct] : réserve prévue au sommet ; citée à la voix si
  /// un col suivant oblige à en garder (5 % ou plus).
  static Message annonceMontee({
    required double longueurM,
    required double penteMoyenne,
    required double puissanceW,
    double reserveSommetPct = 0,
  }) {
    final km = _km(longueurM);
    final pct = _dec1(100 * penteMoyenne);
    final w = _ent(puissanceW);
    final garde = reserveSommetPct >= 5
        ? ' Garde ${_ent(reserveSommetPct)} pour cent pour le col suivant.'
        : '';
    return Message(
      'Montée $km km à $pct % : tiens $w W',
      'Montée de $km kilomètres à $pct pour cent. Tiens $w watts.$garde',
    );
  }

  static Message tiens({required double puissanceW, required double resteM}) {
    final w = _ent(puissanceW);
    final km = _km(resteM);
    return Message(
      'Tiens $w W, reste $km km',
      'Tiens $w watts. Encore $km kilomètres.',
    );
  }

  static Message leveLePied({
    required double puissanceW,
    required double reservePct,
  }) {
    final w = _ent(puissanceW);
    final r = _ent(reservePct.clamp(0, 100).toDouble());
    return Message(
      'Lève le pied : $w W, réserve $r %',
      'Lève le pied. Vise $w watts. Réserve à $r pour cent.',
    );
  }

  static Message mangeAvantCol({required double dansS}) {
    final min = _ent(dansS / 60);
    return Message(
      'Mange avant le col (dans $min min)',
      'Mange maintenant. La montée commence dans $min minutes.',
    );
  }

  static Message mange({required double retardG}) {
    final g = _ent(retardG);
    return Message(
      'Mange : retard $g g de glucides',
      'Pense à manger. Retard de $g grammes de glucides.',
    );
  }

  static Message bois({required double retardMl}) {
    final ml = _ent(retardMl);
    return Message(
      'Bois : retard $ml ml',
      'Pense à boire. Retard de $ml millilitres.',
    );
  }
}

/// Retire les accents (pour un écran qui les affiche mal).
String sansAccents(String s) {
  const de = 'àâäáãéèêëíìîïóòôöõúùûüçÀÂÄÁÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÇ’';
  const vers = "aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'";
  final b = StringBuffer();
  for (final c in s.split('')) {
    final i = de.indexOf(c);
    b.write(i < 0 ? c : vers[i]);
  }
  return b.toString().replaceAll('œ', 'oe').replaceAll('Œ', 'OE');
}
