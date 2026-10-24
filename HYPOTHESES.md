# Hypothèses non validées

Ce fichier liste tout ce qui, dans le moteur, **n'est pas prouvé
scientifiquement** ou n'est qu'un **choix de départ**. Pour chaque point :
ce que ça change, et comment le vérifier.

Toutes les valeurs sont dans `moteur/lib/src/config.dart`, avec leur
origine : `[CDC]` cahier des charges, `[LITT]` littérature, `[CHOIX]` mon
choix, `[PERSO]` ta valeur personnelle.

## À retenir d'abord

- **Manger** : au-dessus d'environ 55 % de FTP (≈ 138 W pour une FTP de
  250 W), tu brûles plus de glucides que ta tolérance. L'objectif vaut
  alors simplement **75 g/h**, et les incertitudes sur le rendement et
  la table des glucides ne changent rien. Elles ne comptent que pour les
  sorties très tranquilles.
- **Boire** : la formule de sudation est la partie la plus fragile. La
  **calibration** (pesée avant/après) corrige le taux de base. Il faudra
  la faire sur plusieurs sorties, par temps différents.
- **Montée** : CP = FTP et W' = 18 kJ sont des estimations. Un test de
  puissance critique (par exemple 3 min et 12 min à fond) donnerait tes
  vraies valeurs. Le mode simulation (étape 2) permettra de comparer la
  cible proposée à ce que tu as vraiment tenu.

## Fonction 1 : quand manger

| # | Hypothèse | Effet | Vérification |
|---|---|---|---|
| 1 | Rendement brut 24 % [CDC] | À 20 %, la dépense réelle est 20 % plus élevée | Labo seulement. Sans effet au-dessus de 55 % de FTP (plafond 75 g/h) |
| 2 | Part des glucides selon le % de FTP [CDC] | Les études donnent l'intensité en % de VO2max, pas de FTP | Labo (calorimétrie). Même remarque que le 1 |
| 3 | Intensité lissée sur 2 min, plafond appliqué au débit moyen sur 10 min [CHOIX] | Change peu le total ; évite les sauts | Mode simulation |
| 4 | Alerte répétée à chaque multiple de 25 g de retard [CHOIX] | Une alerte « mange » toutes les 20 min environ si tu ne manges pas | Sur le vélo |
| 5 | « Mange avant le col » seulement si tu serais en retard en haut [CHOIX] | Pas d'alerte inutile juste après une barre | Mode simulation |
| 6 | Pas d'alerte « mange » normale pendant une montée [CHOIX] | Elle sort au sommet | Sur le vélo |

## Fonction 2 : quand boire

| # | Hypothèse | Effet | Vérification |
|---|---|---|---|
| 7 | Sudation = base × température × humidité × intensité, en lignes droites [CHOIX] | +4 %/°C, +0,5 %/point d'humidité, part fixe 0,4 pour l'intensité | Calibration sur plusieurs sorties à des températures différentes |
| 8 | Objectif plafonné à 1 L/h [CHOIX] | Par forte chaleur, tu bois moins que ce que tu perds (volontaire) | À ajuster après calibration |
| 9 | Calibration : on néglige l'eau perdue en respirant, la masse des glucides brûlés et celle de ce que tu as mangé | Erreur de l'ordre de 5 à 10 % | Toujours se peser dans les mêmes conditions |

## Fonction 3 : puissance en montée

| # | Hypothèse | Effet | Vérification |
|---|---|---|---|
| 10 | CP = FTP [CDC] | Proches en moyenne, mais l'écart varie selon les personnes | Test de puissance critique |
| 11 | W' = 18 kJ [CDC] | +5 kJ = environ +3 W de cible sur un col de 30 min | Test de puissance critique |
| 12 | Fatigue : −1 % de CP par 500 kJ au-delà de 1500 kJ, en continu, plafonnée à −20 % [CDC + CHOIX] | En réalité W' baisse aussi : non modélisé | Comparer tes cols en début et en fin de longue sortie (étape 2) |
| 13 | Cols enchaînés (moins de 10 min entre le sommet et le pied suivant) : une seule puissance pour tous, réserve au sommet calculée pour arriver vide en haut du dernier, récupération entre les deux estimée à 60 % de FTP [CHOIX] | Simplification : pas une vraie optimisation. Au-delà de 10 min, chaque col vide sa réserve | Mode simulation sur tes parcours à bosses |
| 14 | Col de plus d'une heure : CP retenue baissée de 0,12 × ln(durée / 1 h) [CHOIX validé] | −5 % à 1 h 30, −8 % à 2 h. Valeur estimée | Mode simulation sur tes longs cols |
| 15 | Montée de moins de 3 min : le modèle CP/W' ne s'applique plus | Cible plafonnée à 130 % de FTP | Normal |
| 16 | Modèle physique en vitesse stable : pas d'accélérations, pas d'abri d'un groupe, vent ramené à 60 % de sa valeur à 10 m, descente plafonnée à 60 km/h | Durées de montée un peu fausses par vent tournant ou en groupe | Mode simulation : temps estimé contre temps réel |
| 17 | Heure d'arrivée au pied du col : à ta puissance moyenne des 10 dernières minutes | Alerte « mange avant le col » un peu tôt ou tard | Mode simulation |

## Alertes

| # | Hypothèse | Vérification |
|---|---|---|
| 18 | L'app iGPSPORT transfère les notifications de n'importe quelle appli vers le BiNavi | **À tester dès le premier APK** |
| 19 | Le BiNavi affiche les accents (sinon option `sansAccents`) | À tester |
| 20 | En montée, un rappel toutes les 5 min suffit (plus une annonce si la cible bouge de 10 W) [CHOIX] | Sur le vélo |
