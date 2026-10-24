import 'dart:math' as math;

import 'alertes.dart';
import 'config.dart';
import 'hydratation.dart';
import 'lissage.dart';
import 'messages.dart';
import 'pacing.dart';
import 'parcours.dart';
import 'physique.dart';
import 'ravitaillement.dart';
import 'wbal.dart';

/// Une mesure reçue (en général une par seconde).
class Echantillon {
  const Echantillon({
    required this.t,
    this.puissanceW,
    this.fcBpm,
    this.cadenceRpm,
    this.vitesseMs,
    this.distanceParcoursM,
  });

  /// Instant (s depuis le départ).
  final double t;
  final double? puissanceW;
  final double? fcBpm;
  final double? cadenceRpm;
  final double? vitesseMs;

  /// Position sur le parcours (m depuis le départ du GPX), ou null.
  final double? distanceParcoursM;
}

enum TypeEvenement { alerte, mange, boit }

/// Ligne du journal de sortie.
class Evenement {
  const Evenement(this.t, this.type, this.texte, {this.valeur, this.code});
  final double t;
  final TypeEvenement type;
  final String texte;

  /// Grammes de glucides (mange) ou millilitres (boit).
  final double? valeur;

  /// Code de l'alerte.
  final String? code;
}

/// Ce que l'écran affiche à un instant donné.
class EtatCoach {
  const EtatCoach({
    required this.t,
    required this.travailKj,
    required this.cpEffW,
    required this.wbalJ,
    required this.wbalPct,
    required this.glucidesBrulesG,
    required this.glucidesObjectifG,
    required this.glucidesMangesG,
    required this.glucidesRetardG,
    required this.sudationLh,
    required this.eauPerdueL,
    required this.eauObjectifL,
    required this.eauBueL,
    required this.eauRetardMl,
    this.monteeCourante,
    this.puissanceCibleW,
    this.tempsRestantMonteeS,
    this.ciblePlafonnee = false,
    this.reserveSommetPct,
    this.colsEnchaines = 0,
    this.prochaineMontee,
    this.distanceProchaineM,
    this.etaProchaineS,
    this.puissanceProchaineW,
    this.reserveSommetProchainePct,
    this.dureeProchaineS,
  });

  final double t;
  final double travailKj;
  final double cpEffW;
  final double wbalJ;
  final double wbalPct;

  final double glucidesBrulesG;
  final double glucidesObjectifG;
  final double glucidesMangesG;
  final double glucidesRetardG;

  final double sudationLh;
  final double eauPerdueL;
  final double eauObjectifL;
  final double eauBueL;
  final double eauRetardMl;

  /// Montée en cours et puissance à tenir jusqu'au sommet.
  final Montee? monteeCourante;
  final double? puissanceCibleW;
  final double? tempsRestantMonteeS;
  final bool ciblePlafonnee;

  /// Réserve prévue au sommet (% de W'), et nombre de cols suivants
  /// gérés avec celui-ci (enchaînement).
  final double? reserveSommetPct;
  final int colsEnchaines;

  /// Prochaine montée. L'heure d'arrivée et la puissance prévue ne sont
  /// calculées que dans les 15 dernières minutes environ.
  final Montee? prochaineMontee;
  final double? distanceProchaineM;
  final double? etaProchaineS;
  final double? puissanceProchaineW;
  final double? reserveSommetProchainePct;
  final double? dureeProchaineS;
}

class _SuiviMontee {
  bool anticipationFaite = false;
  bool annonceFaite = false;
  double derniereAnnonceT = double.negativeInfinity;
  double derniereAnnonceW = 0;
}

/// Le coach : reçoit les mesures, tient les comptes, décide des alertes.
///
/// Utilisation : appeler [tick] à chaque mesure, [mange] et [boit] à
/// chaque appui sur les boutons, mettre à jour [meteo] toutes les 10 min.
class Coach {
  Coach(this.cfg, {this.parcours, Meteo? meteo})
    : meteo =
          meteo ??
          Meteo(
            temperatureC: cfg.physique.temperatureDefautC,
            humiditePct: cfg.physique.humiditeDefautPct,
          ),
      manger = Ravitaillement(cfg.manger, cfg.cycliste.ftpW),
      boire = Hydratation(cfg.boire, cfg.cycliste.ftpW),
      wbal = ReserveAnaerobie(
        wPrimeJ: cfg.wbal.wPrimeJ,
        modele: cfg.wbal.modele,
      ),
      _arbitre = Arbitre(cfg.alertes),
      _pComparaison = MoyenneExpo(cfg.pacing.lissageComparaisonS),
      _pApproche = MoyenneExpo(cfg.pacing.lissageApprocheS);

  final Config cfg;
  final Parcours? parcours;

  /// Dernière météo connue.
  Meteo meteo;

  final Ravitaillement manger;
  final Hydratation boire;
  final ReserveAnaerobie wbal;

  /// Toutes les alertes et prises, dans l'ordre.
  final List<Evenement> journal = [];

  final Arbitre _arbitre;
  final MoyenneExpo _pComparaison;
  final MoyenneExpo _pApproche;
  final Map<int, _SuiviMontee> _suivis = {};

  double? _tPrecedent;
  double _t = 0;
  double _travailJ = 0;
  double? _distanceM;
  Montee? _montee;
  Montee? _prochaine;
  double _prochainCalculT = double.negativeInfinity;
  double _tCalcul = 0;
  ResultatPacing? _cible;
  ResultatPacing? _pacingProchaine;
  double? _etaCalculS;

  double get ftpW => cfg.cycliste.ftpW;
  double get cpW => ftpW * cfg.wbal.cpSurFtp;
  double get travailKj => _travailJ / 1000;
  double get cpEffW =>
      cpEffective(cpW: cpW, travailKj: travailKj, cfg: cfg.wbal);

  /// Temps avant le pied de la prochaine montée (s), ou null si elle est
  /// à plus de 15 minutes environ.
  double? get etaProchaineS {
    final e = _etaCalculS;
    return e == null ? null : math.max(0.0, e - (_t - _tCalcul));
  }

  /// Traite une mesure. Renvoie l'alerte à envoyer maintenant (au plus
  /// une), ou une liste vide.
  List<Alerte> tick(Echantillon e) {
    final tPrec = _tPrecedent;
    final dt = tPrec == null ? 0.0 : math.max(0.0, e.t - tPrec);
    _tPrecedent = e.t;
    _t = e.t;
    final p = dt > cfg.ecartMaxEchantillonsS
        ? 0.0
        : math.max(0.0, e.puissanceW ?? 0.0);

    wbal.maj(p, cfg.wbal.fatigueAppliqueeAuWbal ? cpEffW : cpW, dt);
    _travailJ += p * dt;
    manger.maj(p, dt);
    boire.maj(p, dt, meteo.temperatureC, meteo.humiditePct);
    _pComparaison.ajouter(p, dt);
    _pApproche.ajouter(p, dt);
    if (e.distanceParcoursM != null) _distanceM = e.distanceParcoursM;

    _suivreMontees();
    final candidats = <CandidatAlerte>[];
    _candidatsMontee(candidats);
    _candidatsManger(candidats);
    _candidatsBoire(candidats);

    final a = _arbitre.choisir(_t, candidats);
    if (a == null) return const [];
    journal.add(Evenement(_t, TypeEvenement.alerte, a.texte, code: a.code));
    return [a];
  }

  /// Bouton « j'ai mangé ».
  void mange(double glucidesG, {String nom = 'Aliment'}) {
    manger.mange(glucidesG);
    journal.add(Evenement(_t, TypeEvenement.mange, nom, valeur: glucidesG));
  }

  void mangeAliment(Aliment a) => mange(a.glucidesG, nom: a.nom);

  /// Bouton « j'ai bu ». Compte aussi les glucides de la boisson.
  void boit(double ml, {String nom = 'Boisson'}) {
    boire.boit(ml);
    final g = ml / 1000 * cfg.manger.glucidesParLitreBoisson;
    if (g > 0) manger.mange(g);
    journal.add(Evenement(_t, TypeEvenement.boit, nom, valeur: ml));
  }

  void boitBoisson(Boisson b) => boit(b.ml, nom: b.nom);

  EtatCoach get etat {
    final d = _distanceM;
    final cible = _cible;
    final pr = _prochaine;
    final pp = _pacingProchaine;
    return EtatCoach(
      t: _t,
      travailKj: travailKj,
      cpEffW: cpEffW,
      wbalJ: wbal.wbalJ,
      wbalPct: wbal.pourcentage,
      glucidesBrulesG: manger.brulesG,
      glucidesObjectifG: manger.objectifG,
      glucidesMangesG: manger.mangesG,
      glucidesRetardG: manger.retardG,
      sudationLh: boire.sudationLh,
      eauPerdueL: boire.perteL,
      eauObjectifL: boire.objectifL,
      eauBueL: boire.buL,
      eauRetardMl: boire.retardMl,
      monteeCourante: _montee,
      puissanceCibleW: cible?.puissanceW,
      tempsRestantMonteeS: cible == null
          ? null
          : math.max(0.0, cible.dureeS - (_t - _tCalcul)),
      ciblePlafonnee: cible?.plafonnee ?? false,
      reserveSommetPct: cible == null ? null : _pct(cible.reserveSommetJ),
      colsEnchaines: cible?.colsEnchaines ?? 0,
      prochaineMontee: pr,
      distanceProchaineM: pr == null || d == null ? null : pr.debutM - d,
      etaProchaineS: etaProchaineS,
      puissanceProchaineW: pp?.puissanceW,
      reserveSommetProchainePct: pp == null ? null : _pct(pp.reserveSommetJ),
      dureeProchaineS: pp?.dureeS,
    );
  }

  // -------------------------------------------------------------------

  _SuiviMontee _suivi(Montee m) =>
      _suivis.putIfAbsent(m.index, _SuiviMontee.new);

  double _pct(double j) => 100 * j / cfg.wbal.wPrimeJ;

  /// Pacing de la montée [m] depuis [depuisM], avec les cols qui la
  /// suivent de près.
  ResultatPacing _pacing(
    Parcours parc,
    Montee m,
    double depuisM,
    ConditionsRoulage c,
  ) => calculerPacing(
    segments: parc.segmentsEntre(depuisM, m.finM),
    enchainement: _enchainement(parc, m, c),
    cpEffW: cpEffW,
    wbalJ: wbal.wbalJ,
    wPrimeJ: cfg.wbal.wPrimeJ,
    ftpW: ftpW,
    cfg: cfg.pacing,
    conditions: c,
    modele: cfg.wbal.modele,
  );

  /// Cols qui commencent moins de [ConfigPacing.enchainementMaxS] après
  /// le sommet du précédent.
  List<ColEnchaine> _enchainement(
    Parcours parc,
    Montee m,
    ConditionsRoulage c,
  ) {
    final cp = cfg.pacing;
    final pRecup = cp.puissanceEntreColsPctFtp / 100 * ftpW;
    final res = <ColEnchaine>[];
    var precedent = m;
    for (
      var i = m.index + 1;
      i < parc.montees.length && res.length < cp.enchainementMaxCols;
      i++
    ) {
      final suivant = parc.montees[i];
      final intervalle = parc.segmentsEntre(precedent.finM, suivant.debutM);
      final t = dureeSegments(
        intervalle,
        pRecup,
        c,
        limiteS: cp.enchainementMaxS,
      );
      if (t >= cp.enchainementMaxS) break;
      res.add(
        ColEnchaine(
          intervalle: intervalle,
          montee: parc.segmentsEntre(suivant.debutM, suivant.finM),
        ),
      );
      precedent = suivant;
    }
    return res;
  }

  /// Repère la montée en cours et la suivante ; recalcule cibles et
  /// heure d'arrivée toutes les 30 s (et dès qu'on change de montée).
  void _suivreMontees() {
    final parc = parcours;
    final d = _distanceM;
    if (parc == null || d == null) {
      _montee = _prochaine = null;
      _cible = _pacingProchaine = null;
      _etaCalculS = null;
      return;
    }
    final m = parc.monteeA(d);
    final pr = parc.prochaineMontee(d);
    if (m?.index != _montee?.index || pr?.index != _prochaine?.index) {
      _prochainCalculT = _t;
    }
    _montee = m;
    _prochaine = pr;
    if (_t < _prochainCalculT) return;

    _prochainCalculT = _t + cfg.pacing.recalculS;
    _tCalcul = _t;
    final cond = ConditionsRoulage.depuis(cfg, meteo);
    _cible = m == null ? null : _pacing(parc, m, d, cond);

    if (pr == null) {
      _etaCalculS = null;
      _pacingProchaine = null;
      return;
    }
    final pApproche = math.max(
      _pApproche.valeur(),
      cfg.pacing.puissanceApprocheMinPctFtp / 100 * ftpW,
    );
    final horizon = cfg.manger.anticipationDansMaxS + 2 * cfg.pacing.recalculS;
    final eta = dureeSegments(
      parc.segmentsEntre(d, pr.debutM),
      pApproche,
      cond,
      limiteS: horizon,
    );
    if (eta < horizon) {
      _etaCalculS = eta;
      // Col suivant déjà géré avec la montée en cours (enchaînement) :
      // pas d'annonce séparée, il sera annoncé à son pied avec la
      // réserve réelle.
      final enchaine =
          m != null &&
          pr.index == m.index + 1 &&
          (_cible?.colsEnchaines ?? 0) > 0;
      _pacingProchaine = enchaine ? null : _pacing(parc, pr, pr.debutM, cond);
    } else {
      _etaCalculS = null;
      _pacingProchaine = null;
    }
  }

  void _candidatsMontee(List<CandidatAlerte> c) {
    final m = _montee;
    final cible = _cible;
    final d = _distanceM;
    if (m != null && cible != null && d != null) {
      final s = _suivi(m);
      final p = cible.puissanceW;
      void noter() {
        s.annonceFaite = true;
        s.derniereAnnonceT = _t;
        s.derniereAnnonceW = p;
      }

      if (!s.annonceFaite) {
        c.add(
          CandidatAlerte(
            type: TypeAlerte.montee,
            sousPriorite: 1,
            code: 'montee_debut',
            message: Messages.annonceMontee(
              longueurM: m.longueurM,
              penteMoyenne: m.penteMoyenne,
              puissanceW: p,
              reserveSommetPct: _pct(cible.reserveSommetJ),
            ),
            siEmise: noter,
          ),
        );
      } else if (_pComparaison.valeur() >
              p * (1 + cfg.pacing.margeSurregimePct / 100) &&
          _t - s.derniereAnnonceT >= cfg.alertes.intervalleMinS) {
        c.add(
          CandidatAlerte(
            type: TypeAlerte.montee,
            sousPriorite: 1,
            code: 'montee_surregime',
            message: Messages.leveLePied(
              puissanceW: p,
              reservePct: wbal.pourcentage,
            ),
            siEmise: noter,
          ),
        );
      } else if ((p - s.derniereAnnonceW).abs() >= cfg.pacing.ecartAnnonceW ||
          _t - s.derniereAnnonceT >= cfg.pacing.rappelS) {
        c.add(
          CandidatAlerte(
            type: TypeAlerte.montee,
            sousPriorite: 1,
            code: 'montee_cible',
            message: Messages.tiens(puissanceW: p, resteM: m.finM - d),
            siEmise: noter,
          ),
        );
      }
    }

    final pr = _prochaine;
    final eta = etaProchaineS;
    final pp = _pacingProchaine;
    if (pr != null &&
        eta != null &&
        pp != null &&
        eta <= cfg.pacing.preAnnonceS) {
      final s = _suivi(pr);
      if (!s.annonceFaite) {
        c.add(
          CandidatAlerte(
            type: TypeAlerte.montee,
            code: 'montee_annonce',
            message: Messages.annonceMontee(
              longueurM: pr.longueurM,
              penteMoyenne: pr.penteMoyenne,
              puissanceW: pp.puissanceW,
              reserveSommetPct: _pct(pp.reserveSommetJ),
            ),
            siEmise: () {
              s.annonceFaite = true;
              s.derniereAnnonceT = _t;
              s.derniereAnnonceW = pp.puissanceW;
            },
          ),
        );
      }
    }
  }

  void _candidatsManger(List<CandidatAlerte> c) {
    final cm = cfg.manger;
    final pr = _prochaine;
    final eta = etaProchaineS;
    final pp = _pacingProchaine;
    if (pr != null &&
        eta != null &&
        pp != null &&
        eta >= cm.anticipationDansMinS &&
        eta <= cm.anticipationDansMaxS &&
        pp.dureeS >= cm.anticipationDureeMonteeMinS) {
      final s = _suivi(pr);
      if (!s.anticipationFaite) {
        // Retard prévu en haut du col si tu ne manges pas d'ici là.
        final projete =
            manger.retardG +
            manger.debitObjectifGh * eta / 3600 +
            math.min(
                  manger.debitPourPuissanceGh(pp.puissanceW),
                  cm.toleranceMaxGh,
                ) *
                pp.dureeS /
                3600;
        if (!cm.anticipationSiRetardProjete || projete >= cm.seuilAlerteG) {
          c.add(
            CandidatAlerte(
              type: TypeAlerte.manger,
              sousPriorite: 1,
              code: 'manger_avant_col',
              message: Messages.mangeAvantCol(dansS: eta),
              siEmise: () {
                s.anticipationFaite = true;
                manger.alerteEmise();
              },
            ),
          );
        }
      }
    }

    final enMontee = _montee != null;
    if (manger.alerteDue && !(enMontee && cm.reporterPendantMontee)) {
      c.add(
        CandidatAlerte(
          type: TypeAlerte.manger,
          code: 'manger',
          message: Messages.mange(retardG: manger.retardG),
          siEmise: manger.alerteEmise,
        ),
      );
    }
  }

  void _candidatsBoire(List<CandidatAlerte> c) {
    if (boire.alerteDue) {
      c.add(
        CandidatAlerte(
          type: TypeAlerte.boire,
          code: 'boire',
          message: Messages.bois(retardMl: boire.retardMl),
          siEmise: boire.alerteEmise,
        ),
      );
    }
  }
}
