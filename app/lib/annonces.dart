// Les alertes arrivent au cycliste par une notification Android (relayée
// sur le compteur par l'app du compteur ou Gadgetbridge) et, si la voix
// est activée, lues à voix haute dans les écouteurs.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

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

  Future<void> preparer({required bool voix}) async {
    _voix = voix;
    if (_pret) return;
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
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
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
    } catch (e) {
      debugPrint('Annonce impossible : $e');
    }
  }
}
