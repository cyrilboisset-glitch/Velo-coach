# CLAUDE.md — Vélo Coach

Contexte pour reprendre le projet. Tout le projet est en français.

## Projet

Appli Android de coaching vélo en direct pour Cyril : quand manger,
quand boire, quelle puissance tenir en montée. Compteur iGPSPORT BiNavi
(fermé, pas de SDK). Le capteur de puissance émet en ANT+ vers le BiNavi
et en Bluetooth (BLE) vers le téléphone, qui est dans la poche. Les
alertes passent en notification Android (relayée sur le BiNavi par l'app
iGPSPORT, texte < 40 caractères) et à la voix (TTS français).

Le cahier des charges complet est dans le premier message de la session
d'origine. Ses points clés sont repris dans `moteur/lib/src/config.dart`
(marqués `[CDC]`) et dans le README.

## Décisions prises avec Cyril

- Téléphone **Android**, ordinateur **PC Windows**.
- Stack **Flutter / Dart**. Moteur en Dart pur dans `moteur/`, l'appli
  Flutter viendra dans `app/` et dépendra du moteur.
- Installation prévue : APK compilé par GitHub Actions, téléchargé sur
  le téléphone (pas besoin d'installer Flutter sur le PC).
- Dépôt privé `velo-coach`.

## Méthode de travail (demandée par Cyril)

Avancer **étape par étape** et **montrer chaque étape** avant de passer
à la suivante :

1. Moteur de calcul pur + tests unitaires. **Fait.**
2. Mode simulation : rejouer un FIT d'une ancienne sortie + son GPX,
   voir quelles alertes seraient sorties et quand.
3. Connexion BLE (Cycling Power, Heart Rate, cadence si dispo).
4. GPS, météo Open-Meteo (toutes les 10 min), import GPX, calage sur le
   parcours.
5. Notifications, voix, fonctionnement écran éteint (service de premier
   plan Android).
6. Interface (gros chiffres) et réglages. Journal CSV ou FIT après la
   sortie.

## Règles du code

- **Tous les coefficients** dans `moteur/lib/src/config.dart`, commentés,
  avec l'origine de chaque valeur par défaut : `[CDC]`, `[LITT]` (avec la
  référence), `[CHOIX]`, `[PERSO]`. Marquer `⚠ HYPOTHÈSE` ce qui n'est pas
  validé, et le reporter dans `HYPOTHESES.md`.
- Ne pas inventer de règle sans la signaler. Une valeur choisie par
  Claude est `[CHOIX]`.
- Noms de variables et commentaires en français (identifiants sans
  accents), textes affichés en français correct.
- Unités dans le nom quand c'est utile : `puissanceW`, `dureeS`,
  `retardG`, `retardMl`.
- Textes courts des alertes : 40 caractères au plus (testé).
- Priorité des alertes : montée > manger > boire, une par minute au plus.
- Avant de dire que c'est fait : `dart analyze`, `dart test`, et l'exemple
  `dart run example/sortie_exemple.dart` dans `moteur/`.

## Préférences de Cyril

- Français, explications simples, étape par étape, réponses courtes
  lisibles sur téléphone.
- Aime être questionné par des questions courtes à choix avant de
  construire.
- Quand il dit « dis-moi comment tu verrais la chose », décrire sans
  construire.
- Signaler franchement les limites et les hypothèses.

## Questions ouvertes (voir HYPOTHESES.md)

- Rappel en montée : 5 min par défaut (2 min donnait plus de 20
  notifications sur un col de 45 min).
- Réserve à garder au sommet (0 % par défaut, formule pure).
- Déclin pour les cols de plus d'une heure (désactivé par défaut).
- Le BiNavi affiche-t-il les notifications d'une appli tierce ? Les
  accents ?
