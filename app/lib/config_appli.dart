// Réglages techniques de l'appli (le moteur a les siens dans
// moteur/lib/src/config.dart). Les identifiants Firebase ne sont pas
// secrets : la protection vient des règles de la base (dépôt Suivi-direct).

const String cleApiFirebase = 'AIzaSyAPDgdivR6nvrRCnaRWiLNGF3pj4IMrPSA';
const String urlBase =
    'https://suivi-direct-default-rtdb.europe-west1.firebasedatabase.app';
const String urlPageSuivi =
    'https://cyrilboisset-glitch.github.io/Suivi-direct/';

/// Une position GPS par seconde pour le coach (calage sur le parcours).
const Duration intervalleGps = Duration(seconds: 1);

/// Une position envoyée au suivi en direct toutes les 10 s. [CHOIX]
const Duration intervalleSuivi = Duration(seconds: 10);

/// Arrêt automatique si on oublie d'arrêter la sortie. [CHOIX]
const Duration dureeMaxSuivi = Duration(hours: 16);

/// Positions moins précises que ça : ignorées. [CHOIX]
const double precisionMaxM = 50;

/// Délai maximum d'une requête réseau.
const Duration delaiReseau = Duration(seconds: 20);

/// Météo (Open-Meteo, sans clé) toutes les 10 min. [CDC]
const Duration intervalleMeteo = Duration(minutes: 10);

/// Une puissance plus vieille que ça (capteur perdu) compte pour 0 W. [CHOIX]
const Duration ageMaxCapteur = Duration(seconds: 3);
