// Les alertes arrivent au cycliste par une notification Android (relayée
// sur le compteur par l'app du compteur ou Gadgetbridge) et, si la voix
// est activée, lues à voix haute dans les écouteurs.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

import 'diagnostic.dart';

class Annonces {
  final FlutterLocalNotificationsPlugin _notifs =
      FlutterLocalNotificationsPlugin();
  final FlutterTts _tts = FlutterTts();
  bool _pret = false;
  bool _voix = true;
  int _numero = 100;

  static const _canal = AndroidNotificationDetails(
    'alertes_coach',
    'Alertes du coach',
    channelDescription: 'Manger, boire, puissance en montée',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  /// Prépare les notifications et la voix. Ne bloque jamais la sortie :
  /// ce qui ne démarre pas est noté dans le diagnostic de l'accueil.
  Future<void> preparer({required bool voix}) async {
    _voix = voix;
    if (_pret) return;
    try {
      await _notifs.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _notifs
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e, p) {
      Diagnostic.instance.noter('Notifications indisponibles : $e', p);
    }
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.5);
    } catch (e, p) {
      _voix = false;
      Diagnostic.instance.noter('Voix indisponible : $e', p);
    }
    _pret = true;
  }

  Future<void> annoncer(Alerte a) async {
    try {
      // Un numéro différent à chaque alerte : le compteur les reçoit comme
      // des messages distincts.
      await _notifs.show(
        id: _numero++,
        title: 'Coach',
        body: a.texte,
        notificationDetails: const NotificationDetails(android: _canal),
      );
      if (_voix) await _tts.speak(a.texteVocal);
    } catch (e, p) {
      Diagnostic.instance.noter('Annonce impossible : $e', p);
    }
  }
}
