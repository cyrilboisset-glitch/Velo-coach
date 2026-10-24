# Vélo Coach

Appli Android de coaching en direct à vélo. Le téléphone reste dans la
poche, lit les capteurs en Bluetooth et te prévient :

1. **Quand manger** : glucides brûlés contre glucides mangés, et « mange
   avant le col ».
2. **Quand boire** : sueur estimée selon la chaleur, l'humidité et
   l'effort.
3. **Quelle puissance tenir en montée** : réserve anaérobie W'bal,
   fatigue de fond, durée du col estimée par un modèle physique.

Les alertes sortent en notification (texte court, pour le BiNavi via
l'app iGPSPORT) et à la voix.

## Avancement

| Étape | Contenu | État |
|---|---|---|
| 1 | Moteur de calcul pur + tests | **Fait** (84 tests) |
| 2 | Mode simulation : rejouer un FIT + son GPX | À faire |
| 3 | Connexion Bluetooth aux capteurs | À faire |
| 4 | GPS, météo, import GPX, montées | À faire |
| 5 | Notifications, voix, arrière-plan | À faire |
| 6 | Interface et réglages | À faire |

## Où est quoi

```
moteur/                      Dart pur, sans Flutter
  lib/src/config.dart        TOUS les coefficients, commentés, avec leur origine
  lib/src/ravitaillement.dart   Fonction 1 : manger
  lib/src/hydratation.dart      Fonction 2 : boire + calibration
  lib/src/wbal.dart             Réserve W'bal (Skiba) + fatigue de fond
  lib/src/physique.dart         Vitesse selon puissance, pente, vent
  lib/src/parcours.dart         Parcours, lissage, détection des montées
  lib/src/pacing.dart           Puissance cible en montée
  lib/src/alertes.dart          Priorités, une alerte par minute
  lib/src/messages.dart         Textes des alertes (≤ 40 caractères)
  lib/src/coach.dart            Chef d'orchestre : mesures → alertes
  test/                      Tests unitaires
  example/sortie_exemple.dart   Sortie inventée, affiche les alertes
HYPOTHESES.md                Tout ce qui n'est pas validé scientifiquement
```

## Lancer les tests

GitHub les lance à chaque envoi (onglet **Actions** du dépôt).

Sur un ordinateur avec le SDK Dart (https://dart.dev/get-dart) :

```
cd moteur
dart pub get
dart test
dart run example/sortie_exemple.dart
```
