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

## Décisions de réglage (validées par Cyril)

- Rappel en montée toutes les 5 min (plus une annonce si la cible bouge
  de 10 W, et « lève le pied » en cas de surrégime).
- Correction des cols de plus d'une heure activée (A = 0,12).
- Réserve au sommet : « avec le GPX, c'est à toi » → gérée par le moteur
  (cols enchaînés à moins de 10 min gérés ensemble, voir pacing.dart).
- Étape 2 : rejouer une sortie Strava (via le connecteur Strava). Ne pas
  mettre ses traces GPS dans le dépôt (données personnelles).

## Appli `app/` (fusion avec Suivi direct, 6 nov. 2026)

- Appli Flutter `app/`, dépend du moteur par chemin (`../moteur`).
  Reprend le suivi en direct du dépôt **Suivi-direct** (Firebase REST,
  lien permanent, page de suivi qui reste sur GitHub Pages de
  Suivi-direct, règles de la base dans ce dépôt-là).
- **Identifiant Android `fr.cyril.suivi_direct` et clé de signature de
  Suivi direct** (`app/ci/debug.keystore`) : l'appli s'installe par-dessus
  Suivi direct et garde ses réglages (même lien de suivi). Le `+N` de
  `version:` doit toujours augmenter.
- Compilation par GitHub Actions (`.github/workflows/apk.yml`) :
  `flutter create`, `app/ci/preparer_android.py` (autorisations, nom,
  identifiant, desugaring), analyse, tests, APK publié en *Release*.
- Fichiers : `sortie.dart` (GPS 1 s avec service de premier plan,
  coach 1 fois/s, météo Open-Meteo 10 min, journal CSV), `capteurs.dart`
  (Bluetooth puissance + cadence 0x2A63, cardio 0x2A37),
  `annonces.dart` (notifications + voix), `suivi.dart` (Firebase, une
  position / 10 s), `reglages.dart`, `main.dart` (écrans).
- Flutter est installable dans l'environnement de Claude
  (storage.googleapis.com) : `flutter analyze` et `flutter test` dans
  `app/` avant d'envoyer. Pas de SDK Android : l'APK se compile sur GitHub.

## Décisions de Cyril (oct.–nov. 2026), pas toutes codées

Codé dans l'appli v0.2 :
- Compteur : alertes en notification Android (BiNavi via app iGPSPORT ou
  Gadgetbridge ; Magene via OnelapFit, à tester).
- Glucides (v0.3, usage généraliste) : écran « Ma nutrition » ; chaque
  utilisateur saisit ses produits (glucides par portion, ou pour 100 g
  × poids de la portion), choisit celui de la sortie, l'objectif en g/h
  et les glucides de sa boisson (g/L). Défauts : mini-sachet Haribo
  (7,5 g), 20 g/h, eau. Alerte « Mange 1 <produit> ».
- Aucune validation pendant la sortie : une alerte = faite (sachet
  mangé, 150 ml bus).
- Capteurs : pédales Magene P715 (puissance + cadence en Bluetooth).
- Réglages par défaut : 90 kg, vélo 9 kg, FTP 203 W (Strava).

À coder dans le moteur :
- Moins de 1 h 15 : pas de glucides. Au-delà de 3 h : toujours 20 g/h,
  et pause repas proposée si l'écart brûlés − mangés dépasse 200 g
  (arrêt de plus de 10 min = pause faite).
- Manger : jamais en montée (sauf replat), jamais en descente, jamais
  au-dessus de 30 km/h ; plutôt 10 à 15 min avant une montée ; premier
  sachet après 30 à 45 min ; rien dans les 20 dernières minutes ;
  avant la sortie : nombre de sachets à prendre (+ marge).
- Boire : sans restriction ; 2 bidons de 1 L suivis ; recharge
  conseillée, comptée faite après un arrêt de plus de 2 min.
- Braquet saisi (montages standards) ; plancher de puissance : cadence
  mini 50 tr/min dans le plus petit braquet ; vitesse engagée déduite
  de vitesse/cadence (Wheeltop lisible seulement si Bluetooth).
- Mode « endurance » par défaut (cible plafonnée à 90 % FTP, plat
  115–150 W, cadence plat 80–90, montée 65–80) et mode « à fond » en
  option. Question encore ouverte : mode endurance par défaut ?
- Correction après la sortie (écran bilan).

## Questions ouvertes (voir HYPOTHESES.md)

- Le BiNavi affiche-t-il les notifications d'une appli tierce ? Les
  accents ?
