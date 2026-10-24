/// =====================================================================
///  CONFIGURATION UNIQUE DU MOTEUR DE COACHING VÉLO
/// =====================================================================
///
/// Tous les coefficients du moteur sont ici, et nulle part ailleurs.
/// Pour changer une valeur : la modifier ici, ou la passer au
/// constructeur, par exemple `Config(cycliste: ConfigCycliste(ftpW: 270))`.
///
/// Origine de chaque valeur par défaut :
///   [CDC]    cahier des charges (ta demande).
///   [LITT]   littérature scientifique (référence indiquée).
///   [CHOIX]  mon choix de départ : raisonnable mais pas validé.
///            À ajuster avec le mode simulation, puis sur le vélo.
///   [PERSO]  valeur personnelle à remplacer par la tienne.
///
/// ⚠ HYPOTHÈSE : hypothèse non validée scientifiquement. La liste
///   complète, avec l'effet de chaque hypothèse, est dans HYPOTHESES.md.
///
/// Unités : W, J, kJ, s, m, kg, g, L, ml, °C. Dans ce fichier, les
/// pentes et les intensités sont en % (6 = 6 %).
library;

/// Modèle de calcul de la réserve anaérobie W'bal.
enum ModeleWbal {
  /// Forme « différentielle » : Skiba et al., 2015, European Journal of
  /// Applied Physiology. Se calcule seconde par seconde, adaptée au direct.
  differentiel,

  /// Forme « intégrale » d'origine : Skiba et al., 2012, Medicine &
  /// Science in Sports & Exercise. Récupération plus lente, constante de
  /// temps tau = 546 × e^(-0,01 × D_CP) + 316 s.
  integral,
}

/// Une ligne de la table « part des glucides selon l'intensité ».
class PalierGlucides {
  const PalierGlucides(this.jusquAPctFtp, this.part);

  /// Borne haute du palier en % de FTP (exclue).
  final double jusquAPctFtp;

  /// Part de l'énergie fournie par les glucides (0 à 1).
  final double part;
}

/// Un aliment préréglé pour le bouton « j'ai mangé ».
class Aliment {
  const Aliment(this.nom, this.glucidesG);
  final String nom;
  final double glucidesG;
}

/// Une quantité préréglée pour le bouton « j'ai bu ».
class Boisson {
  const Boisson(this.nom, this.ml);
  final String nom;
  final double ml;
}

// ---------------------------------------------------------------------
// Réglages personnels
// ---------------------------------------------------------------------

/// Réglages saisis une fois.
class ConfigCycliste {
  const ConfigCycliste({
    this.poidsCyclisteKg = 75,
    this.poidsVeloKg = 9,
    this.ftpW = 250,
  });

  /// [PERSO] Poids du cycliste habillé (kg).
  final double poidsCyclisteKg;

  /// [PERSO] Poids du vélo prêt à rouler : bidons pleins, compteur,
  /// sacoche (kg).
  final double poidsVeloKg;

  /// [PERSO] FTP : puissance tenue environ une heure (W).
  final double ftpW;

  double get masseTotaleKg => poidsCyclisteKg + poidsVeloKg;
}

// ---------------------------------------------------------------------
// Fonction 1 : quand manger
// ---------------------------------------------------------------------

class ConfigManger {
  const ConfigManger({
    this.rendementBrut = 0.24,
    this.kcalParGramme = 4,
    this.paliers = const [
      PalierGlucides(55, 0.50),
      PalierGlucides(75, 0.65),
      PalierGlucides(90, 0.80),
      PalierGlucides(double.infinity, 0.95),
    ],
    this.lissageIntensiteS = 120,
    this.toleranceMaxGh = 75,
    this.fenetreDebitS = 600,
    this.seuilAlerteG = 25,
    this.aliments = const [
      Aliment('Gel', 25),
      Aliment('Barre', 40),
      Aliment('Banane', 25),
    ],
    this.glucidesParLitreBoisson = 0,
    this.anticipationDureeMonteeMinS = 600,
    this.anticipationDansMinS = 600,
    this.anticipationDansMaxS = 900,
    this.anticipationSiRetardProjete = true,
    this.reporterPendantMontee = true,
  });

  /// [CDC] Rendement brut : part de l'énergie dépensée par le corps qui
  /// arrive aux pédales. À 24 %, 1 kJ mesuré par le capteur ≈ 1 kcal
  /// dépensée (1 / (0,24 × 4,184) = 0,996).
  /// [LITT] 18 à 24 % chez les cyclistes entraînés (Ettema et Lorås,
  /// 2009, Eur J Appl Physiol ; Jeukendrup et al., 2000, J Sci Med Sport).
  /// ⚠ HYPOTHÈSE : varie d'une personne à l'autre. À 20 %, la dépense
  /// réelle (et donc les glucides brûlés) est 20 % plus élevée.
  final double rendementBrut;

  /// [LITT] Énergie d'un gramme de glucides : 4 kcal (facteur d'Atwater).
  final double kcalParGramme;

  /// [CDC] Part des glucides dans l'énergie dépensée, selon l'intensité
  /// en % de FTP.
  /// [LITT] Ordre de grandeur cohérent avec Romijn et al., 1993 (Am J
  /// Physiol) et van Loon et al., 2001 (J Physiol), mais ces études
  /// expriment l'intensité en % de VO2max ou de puissance maximale, pas
  /// en % de FTP.
  /// ⚠ HYPOTHÈSE : la part réelle dépend beaucoup de l'entraînement, du
  /// repas d'avant et du stock de glycogène. Seule une mesure en
  /// laboratoire (calorimétrie) la donnerait pour toi.
  final List<PalierGlucides> paliers;

  /// [CHOIX] L'intensité qui choisit le palier est une moyenne glissante
  /// de la puissance sur environ 2 minutes, pour qu'une relance de
  /// 5 secondes ne fasse pas sauter de palier.
  /// ⚠ HYPOTHÈSE : durée de lissage non validée.
  final double lissageIntensiteS;

  /// [CDC] Quantité maximale de glucides que l'intestin absorbe (g/h).
  /// [LITT] Jusqu'à environ 60 g/h avec du glucose seul, jusqu'à environ
  /// 90 g/h avec un mélange glucose + fructose (Jeukendrup, 2014, Sports
  /// Medicine). Se travaille à l'entraînement.
  final double toleranceMaxGh;

  /// [CHOIX] Le plafond de tolérance s'applique au débit moyen sur
  /// environ 10 minutes, pas seconde par seconde : un sprint de
  /// 10 secondes n'est pas « plafonné ».
  /// ⚠ HYPOTHÈSE : durée non validée.
  final double fenetreDebitS;

  /// [CDC] Alerte quand le retard sur l'objectif atteint ce seuil (g),
  /// puis à chaque nouveau multiple (25, 50, 75 g...) si tu n'as pas
  /// mangé. [CHOIX] pour la répétition par multiples.
  final double seuilAlerteG;

  /// [CDC] gel 25 g et barre 40 g. [CHOIX] banane moyenne ≈ 25 g.
  /// Mets les valeurs lues sur tes emballages.
  final List<Aliment> aliments;

  /// [CHOIX] Glucides par litre de ce que tu bois (g/L). 0 = eau plate.
  /// Avec une boisson énergétique, mets la valeur de l'étiquette
  /// (souvent 40 à 80 g/L) : chaque « j'ai bu » comptera aussi comme
  /// « j'ai mangé ».
  final double glucidesParLitreBoisson;

  /// [CDC] « Mange avant le col » seulement pour une montée estimée à
  /// plus de 10 minutes.
  final double anticipationDureeMonteeMinS;

  /// [CDC] Fenêtre de l'alerte « mange avant le col » : la montée doit
  /// commencer dans 10 à 15 minutes.
  final double anticipationDansMinS;
  final double anticipationDansMaxS;

  /// [CHOIX] N'alerter « mange avant le col » que si, sans manger, tu
  /// serais en retard d'au moins [seuilAlerteG] en haut du col. Évite de
  /// te dire de manger alors que tu viens de prendre une barre.
  final bool anticipationSiRetardProjete;

  /// [CHOIX] D'après ta remarque « on mange mal en montée » : pendant une
  /// montée, l'alerte « mange » normale attend le sommet.
  final bool reporterPendantMontee;

  /// Part des glucides pour une intensité donnée (% de FTP).
  double partGlucides(double pctFtp) {
    for (final p in paliers) {
      if (pctFtp < p.jusquAPctFtp) return p.part;
    }
    return paliers.last.part;
  }
}

// ---------------------------------------------------------------------
// Fonction 2 : quand boire
// ---------------------------------------------------------------------
//
// Sudation (L/h) = taux de base × facteur température × facteur humidité
//                  × facteur intensité.
// Chaque facteur vaut 1 dans les conditions de référence (20 °C, 50 %
// d'humidité, 65 % de FTP) : le taux de base est donc ta sudation dans
// ces conditions. Le mode calibration recalcule ce taux de base.

class ConfigBoire {
  const ConfigBoire({
    this.tauxBaseLh = 0.8,
    this.temperatureRefC = 20,
    this.humiditeRefPct = 50,
    this.intensiteRefPctFtp = 65,
    this.coefTemperatureParDegre = 0.04,
    this.facteurTemperatureMin = 0.5,
    this.facteurTemperatureMax = 2.0,
    this.coefHumiditeParPct = 0.005,
    this.facteurHumiditeMin = 0.8,
    this.facteurHumiditeMax = 1.3,
    this.partFixeIntensite = 0.4,
    this.facteurIntensiteMin = 0.3,
    this.lissageIntensiteS = 300,
    this.ratioRemplacement = 1.0,
    this.plafondBoireLh = 1.0,
    this.seuilAlerteMl = 150,
    this.boissons = const [
      Boisson('Gorgée', 40),
      Boisson('Demi-bidon', 250),
      Boisson('Bidon', 500),
    ],
  });

  /// [CDC] Sudation dans les conditions de référence (L/h).
  /// [LITT] Le plus souvent entre 0,5 et 2 L/h selon la personne,
  /// l'effort et la chaleur (ACSM, Sawka et al., 2007, Med Sci Sports
  /// Exerc). Le mode calibration donne ta vraie valeur.
  final double tauxBaseLh;

  /// [CHOIX] Conditions de référence où tous les facteurs valent 1.
  final double temperatureRefC;
  final double humiditeRefPct;
  final double intensiteRefPctFtp;

  /// [CHOIX] +4 % de sudation par degré au-dessus de 20 °C, −4 % par
  /// degré en dessous. Exemple : 30 °C → × 1,4 ; 10 °C → × 0,6.
  /// ⚠ HYPOTHÈSE : approximation linéaire. Les modèles validés (Gonzalez
  /// et al., 2009, J Appl Physiol) calculent la charge de chaleur à
  /// évacuer, avec beaucoup plus de paramètres.
  final double coefTemperatureParDegre;
  final double facteurTemperatureMin;
  final double facteurTemperatureMax;

  /// [CHOIX] +0,5 % par point d'humidité au-dessus de 50 % : en air
  /// humide, la sueur s'évapore mal, on en produit plus pour se
  /// refroidir. Exemple : 90 % → × 1,2.
  /// ⚠ HYPOTHÈSE : coefficient non validé.
  final double coefHumiditeParPct;
  final double facteurHumiditeMin;
  final double facteurHumiditeMax;

  /// [CHOIX] Facteur intensité = 0,4 + 0,6 × (puissance / puissance de
  /// référence). La chaleur produite par les muscles est
  /// proportionnelle à la puissance, mais une partie de la sueur dépend
  /// du soleil et de l'air (d'où la part fixe de 0,4).
  /// Exemple : 100 % de FTP → × 1,32 ; à l'arrêt → × 0,4.
  /// ⚠ HYPOTHÈSE : répartition 0,4 / 0,6 non validée.
  final double partFixeIntensite;
  final double facteurIntensiteMin;

  /// [CHOIX] La sudation suit la puissance avec retard : moyenne
  /// glissante sur environ 5 minutes.
  final double lissageIntensiteS;

  /// [CHOIX] Part de la sueur à compenser en buvant (1 = tout).
  final double ratioRemplacement;

  /// [CHOIX] Objectif de boisson plafonné à 1 L/h : au-delà, l'estomac
  /// suit mal et boire trop d'eau sans sel expose à l'hyponatrémie.
  /// ⚠ HYPOTHÈSE : ordre de grandeur, à ajuster après calibration.
  final double plafondBoireLh;

  /// [CDC] Alerte tous les 150 ml de retard (150, 300, 450 ml...).
  final double seuilAlerteMl;

  /// [CHOIX] Quantités du bouton « j'ai bu ». Mets la contenance de ton
  /// bidon (souvent 500 à 750 ml).
  final List<Boisson> boissons;
}

// ---------------------------------------------------------------------
// Fonction 3 : réserve anaérobie (W'bal) et fatigue de fond
// ---------------------------------------------------------------------

class ConfigWbal {
  const ConfigWbal({
    this.wPrimeJ = 18000,
    this.cpSurFtp = 1.0,
    this.modele = ModeleWbal.differentiel,
    this.fatigueSeuilKj = 1500,
    this.fatigueTrancheKj = 500,
    this.fatiguePctParTranche = 1.0,
    this.fatigueEnEscalier = false,
    this.fatigueReductionMaxPct = 20,
    this.fatigueAppliqueeAuWbal = true,
  });

  /// [CDC] W' : réserve d'énergie disponible au-dessus de la puissance
  /// critique (J). [LITT] Souvent 10 à 25 kJ chez les cyclistes
  /// entraînés (Jones et al., 2010 ; Poole et al., 2016, Med Sci Sports
  /// Exerc). Un test de puissance critique donnerait ta valeur.
  final double wPrimeJ;

  /// [CDC] Puissance critique CP = FTP × ce coefficient.
  /// ⚠ HYPOTHÈSE : CP et FTP sont proches en moyenne, mais l'écart
  /// varie beaucoup d'une personne à l'autre (Karsten et al., 2021,
  /// Frontiers in Physiology).
  final double cpSurFtp;

  /// [CHOIX] Forme différentielle par défaut : faite pour le calcul en
  /// direct. [LITT] Les deux formes sont de Skiba et al. (2012, 2015).
  final ModeleWbal modele;

  /// [CDC] Fatigue de fond : CP effective réduite de 1 % par tranche de
  /// 500 kJ de travail au-delà de 1500 kJ.
  /// [LITT] La baisse de la courbe de puissance après 1500 à 3000 kJ
  /// est bien décrite (notion de « durabilité », Maunder et al., 2021,
  /// Sports Medicine), mais elle varie beaucoup selon les personnes.
  /// ⚠ HYPOTHÈSE : les valeurs 1500 kJ et 1 % sont des points de départ.
  final double fatigueSeuilKj;
  final double fatigueTrancheKj;
  final double fatiguePctParTranche;

  /// [CHOIX] false = baisse continue (1 % à 2000 kJ, 1,5 % à 2250 kJ),
  /// pour éviter que la puissance cible saute d'un coup. true = baisse
  /// par marches entières de 500 kJ.
  final bool fatigueEnEscalier;

  /// [CHOIX] Baisse maximale de la CP (%), garde-fou.
  final double fatigueReductionMaxPct;

  /// [CHOIX] Le W'bal se calcule avec la CP effective (réduite par la
  /// fatigue) : fatigué, rouler à ton ancienne CP entame ta réserve.
  /// ⚠ HYPOTHÈSE : en réalité W' baisse aussi avec la fatigue ; ce n'est
  /// pas modélisé.
  final bool fatigueAppliqueeAuWbal;
}

// ---------------------------------------------------------------------
// Modèle physique (vitesse selon la puissance)
// ---------------------------------------------------------------------
//
// Puissance aux pédales × rendement de transmission =
//   vitesse × [ masse × g × (Crr × cos θ + sin θ)
//               + ½ × densité de l'air × CdA × (vitesse + vent de face)² ]
// Modèle validé sur route par Martin et al., 1998, Journal of Applied
// Biomechanics (écart moyen de l'ordre de 1 à 3 % sur la puissance).
// Ne tient pas compte des accélérations, des virages, des freinages, ni
// de l'abri d'un groupe.

class ConfigPhysique {
  const ConfigPhysique({
    this.cda = 0.32,
    this.crr = 0.005,
    this.rendementTransmission = 0.976,
    this.facteurVentHauteur = 0.6,
    this.vitesseMaxKmh = 60,
    this.vitesseMinKmh = 4,
    this.temperatureDefautC = 15,
    this.humiditeDefautPct = 50,
  });

  /// [CDC] Surface frontale × coefficient de traînée (m²).
  /// [LITT] Vélo de route, mains aux cocottes : environ 0,30 à 0,40 m²
  /// (revue de Debraux et al., 2011, Sports Biomechanics).
  final double cda;

  /// [CDC] Coefficient de résistance au roulement. Ordre de grandeur
  /// habituel 0,003 à 0,006 selon pneus, pression et revêtement.
  final double crr;

  /// [LITT] Rendement de la chaîne et des roulements ≈ 97,6 % (valeur
  /// utilisée par Martin et al., 1998).
  final double rendementTransmission;

  /// [LITT] La météo donne le vent à 10 m de haut. Au niveau du
  /// cycliste (≈ 1,2 m), le profil logarithmique du vent en campagne le
  /// réduit à environ 55 à 65 %.
  /// ⚠ HYPOTHÈSE : haies, arbres, vallées et relief changent beaucoup
  /// le vent réellement subi.
  final double facteurVentHauteur;

  /// [CHOIX] En descente, on freine : vitesse plafonnée à 60 km/h.
  final double vitesseMaxKmh;

  /// [CHOIX] Vitesse minimale retenue (vélo poussé), pour ne jamais
  /// diviser par zéro.
  final double vitesseMinKmh;

  /// [LITT] Atmosphère standard (15 °C) et humidité moyenne, utilisées
  /// tant que la météo n'est pas connue.
  final double temperatureDefautC;
  final double humiditeDefautPct;
}

// ---------------------------------------------------------------------
// Détection des montées dans le parcours GPX
// ---------------------------------------------------------------------

class ConfigMontees {
  const ConfigMontees({
    this.pasM = 25,
    this.lissageAltitudeM = 200,
    this.penteDebutPct = 2,
    this.penteMoyenneMinPct = 3,
    this.longueurMinM = 1000,
    this.deniveleMinM = 30,
    this.replatMaxM = 300,
    this.perteMaxM = 15,
  });

  /// [CHOIX] Le parcours est rééchantillonné tous les 25 m.
  final double pasM;

  /// [CHOIX] L'altitude d'un GPX est bruitée : moyenne glissante sur
  /// 200 m avant de calculer les pentes.
  final double lissageAltitudeM;

  /// [CHOIX] Une montée commence quand la pente dépasse 2 %, et
  /// continue tant qu'on gagne au moins 2 % en moyenne.
  final double penteDebutPct;

  /// [CHOIX] Une montée retenue fait au moins 3 % de moyenne, 1 km et
  /// 30 m de dénivelé.
  final double penteMoyenneMinPct;
  final double longueurMinM;
  final double deniveleMinM;

  /// [CHOIX] Un replat de moins de 300 m, ou une descente de moins de
  /// 15 m, ne coupe pas la montée.
  final double replatMaxM;
  final double perteMaxM;
}

// ---------------------------------------------------------------------
// Pacing en montée
// ---------------------------------------------------------------------
//
// Puissance cible P telle que P = CP_eff + W'bal disponible / durée(P),
// la durée venant du modèle physique. Résolu par dichotomie.

class ConfigPacing {
  const ConfigPacing({
    this.recalculS = 30,
    this.puissanceMaxPctFtp = 130,
    this.puissanceMinPctFtp = 50,
    this.reserveFinMonteePct = 0,
    this.declinLongueDureeParLn = 0,
    this.dureeRefDeclinS = 3600,
    this.lissageApprocheS = 600,
    this.puissanceApprocheMinPctFtp = 40,
    this.preAnnonceS = 90,
    this.rappelS = 300,
    this.ecartAnnonceW = 10,
    this.margeSurregimePct = 5,
    this.lissageComparaisonS = 30,
  });

  /// [CDC] Recalcul de la cible toutes les 30 s.
  final double recalculS;

  /// [CHOIX] Bornes de la puissance cible. Sur une montée courte (moins
  /// de 3 minutes environ), la formule donne des valeurs énormes :
  /// le modèle CP/W' n'est fiable qu'entre environ 2 et 30 minutes
  /// d'effort (Poole et al., 2016). La cible est alors plafonnée à 130 %
  /// de FTP et marquée « plafonnée ».
  final double puissanceMaxPctFtp;
  final double puissanceMinPctFtp;

  /// [CDC] La formule vide toute la réserve (0 % au sommet).
  /// [CHOIX] possible : garder 10 à 20 % pour la suite.
  final double reserveFinMonteePct;

  /// [CDC] 0 = formule pure P = CP_eff + W'bal / durée.
  /// ⚠ HYPOTHÈSE : pour une montée de plus d'une heure, la formule pure
  /// donne presque la FTP, ce qui est trop dur. Avec une valeur A > 0,
  /// la CP retenue baisse de A × ln(durée / 1 h) au-delà d'une heure
  /// (forme du modèle « omni-domaine » de Puchowicz et al., 2020,
  /// J Sports Sci). Exemple A = 0,12 : 2 h → −8 % ; 1 h 30 → −5 %.
  final double declinLongueDureeParLn;
  final double dureeRefDeclinS;

  /// [CHOIX] Pour estimer dans combien de temps commence la montée, on
  /// suppose que tu continues à ta puissance moyenne des 10 dernières
  /// minutes (au moins 40 % de FTP).
  final double lissageApprocheS;
  final double puissanceApprocheMinPctFtp;

  /// [CHOIX] Annonce de la puissance cible 90 s avant le pied du col.
  final double preAnnonceS;

  /// [CHOIX] Pendant la montée : nouvelle annonce si la cible bouge
  /// d'au moins 10 W, sinon un rappel toutes les 5 minutes (avec 2 min,
  /// un col de 45 min donnait plus de 20 notifications).
  final double rappelS;
  final double ecartAnnonceW;

  /// [CHOIX] « Lève le pied » si ta puissance moyenne sur 30 s dépasse
  /// la cible de plus de 5 %.
  final double margeSurregimePct;
  final double lissageComparaisonS;
}

// ---------------------------------------------------------------------
// Alertes
// ---------------------------------------------------------------------

class ConfigAlertes {
  const ConfigAlertes({
    this.intervalleMinS = 60,
    this.longueurMaxTexte = 40,
    this.sansAccents = false,
  });

  /// [CDC] Pas plus d'une alerte par minute.
  /// Priorité [CDC] : montée > manger > boire (voir TypeAlerte).
  final double intervalleMinS;

  /// [CDC] Texte court pour l'affichage sur le BiNavi.
  final int longueurMaxTexte;

  /// [CHOIX] À passer à true si le BiNavi affiche mal les accents.
  /// ⚠ À TESTER sur le compteur.
  final bool sansAccents;
}

// ---------------------------------------------------------------------
// Configuration complète
// ---------------------------------------------------------------------

class Config {
  const Config({
    this.cycliste = const ConfigCycliste(),
    this.manger = const ConfigManger(),
    this.boire = const ConfigBoire(),
    this.wbal = const ConfigWbal(),
    this.physique = const ConfigPhysique(),
    this.montees = const ConfigMontees(),
    this.pacing = const ConfigPacing(),
    this.alertes = const ConfigAlertes(),
    this.ecartMaxEchantillonsS = 10,
  });

  final ConfigCycliste cycliste;
  final ConfigManger manger;
  final ConfigBoire boire;
  final ConfigWbal wbal;
  final ConfigPhysique physique;
  final ConfigMontees montees;
  final ConfigPacing pacing;
  final ConfigAlertes alertes;

  /// [CHOIX] Au-delà de 10 s sans donnée (pause, capteur perdu), la
  /// puissance de l'intervalle est comptée à 0 W.
  final double ecartMaxEchantillonsS;
}
