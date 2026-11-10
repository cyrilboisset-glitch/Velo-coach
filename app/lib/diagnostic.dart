// Garde les erreurs rencontrées par l'appli pour les afficher sur l'écran
// d'accueil (bouton « Copier »), au lieu de les perdre : sur le téléphone,
// personne ne voit les journaux techniques.

import 'package:flutter/foundation.dart';

class Diagnostic extends ChangeNotifier {
  Diagnostic._();

  static final Diagnostic instance = Diagnostic._();

  final List<String> _erreurs = [];

  List<String> get erreurs => List.unmodifiable(_erreurs);

  void noter(Object erreur, [StackTrace? pile]) {
    final heure = DateTime.now().toIso8601String().substring(11, 19);
    final lignes = (pile?.toString() ?? '').split('\n').take(4).join('\n');
    _erreurs.add('$heure  $erreur${lignes.isEmpty ? '' : '\n$lignes'}');
    if (_erreurs.length > 20) _erreurs.removeAt(0);
    notifyListeners();
  }

  void effacer() {
    _erreurs.clear();
    notifyListeners();
  }

  String get texte => _erreurs.join('\n\n');

  /// Branche la capture des erreurs Flutter et des erreurs asynchrones.
  void brancher() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      noter(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (erreur, pile) {
      noter(erreur, pile);
      return true;
    };
  }
}
