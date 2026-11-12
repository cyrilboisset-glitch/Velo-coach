// Vélo Coach : coaching en direct (manger, boire, puissance en montée) et
// suivi en direct pour être suivi sur une carte (ancienne appli « Suivi
// direct », fusionnée ici). Charte graphique de GOATout (charte.dart).
//
// Trois écrans : avant la sortie (parcours, capteurs, nutrition, lien de
// suivi), pendant la sortie (gros chiffres, anneaux, profil), réglages.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

import 'annonces.dart';
import 'capteurs.dart';
import 'charte.dart';
import 'composants.dart';
import 'config_appli.dart';
import 'diagnostic.dart';
import 'ecran_nutrition.dart';
import 'reglages.dart';
import 'sortie.dart';
import 'suivi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Diagnostic.instance.brancher();
  try {
    final prefs = await SharedPreferences.getInstance();
    final reglages = Reglages(prefs);
    final capteurs = Capteurs(prefs);
    final suivi = Suivi(prefs);
    final sortie = Sortie(
      reglages: reglages,
      capteurs: capteurs,
      suivi: suivi,
      annonces: Annonces(),
    );
    await _rechargerParcours(prefs, sortie);
    unawaited(
      capteurs.connecter().catchError(
        (Object e, StackTrace p) => Diagnostic.instance.noter(e, p),
      ),
    );
    runApp(AppliCoach(sortie: sortie, prefs: prefs));
  } catch (e, p) {
    // Le démarrage a échoué : on l'affiche au lieu d'un écran noir.
    Diagnostic.instance.noter(e, p);
    runApp(
      MaterialApp(
        theme: themeGoatout(),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                'Vélo Coach $versionAppli : démarrage impossible.\n\n'
                '${Diagnostic.instance.texte}',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Parcours GPX gardé d'une fois sur l'autre ----------------------------

Future<File> _fichierGpx() async =>
    File('${(await getApplicationDocumentsDirectory()).path}/parcours.gpx');

Future<void> _rechargerParcours(SharedPreferences prefs, Sortie s) async {
  try {
    final f = await _fichierGpx();
    if (!await f.exists()) return;
    final p = Parcours.depuisPoints(lireGpx(await f.readAsString()));
    if (p.segments.isNotEmpty) s.choisirParcours(p, prefs.getString('nomGpx'));
  } catch (_) {
    // Fichier abîmé : on repart sans parcours
  }
}

class AppliCoach extends StatelessWidget {
  const AppliCoach({super.key, required this.sortie, required this.prefs});

  final Sortie sortie;
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vélo Coach',
      debugShowCheckedModeBanner: false,
      theme: themeGoatout(),
      home: EcranPrincipal(sortie: sortie, prefs: prefs),
    );
  }
}

class EcranPrincipal extends StatefulWidget {
  const EcranPrincipal({super.key, required this.sortie, required this.prefs});

  final Sortie sortie;
  final SharedPreferences prefs;

  @override
  State<EcranPrincipal> createState() => _EcranPrincipalState();
}

class _EcranPrincipalState extends State<EcranPrincipal> {
  Timer? _horloge;

  Sortie get s => widget.sortie;

  List<Listenable> get _sources => [
    s,
    s.capteurs,
    s.suivi,
    s.reglages,
    Diagnostic.instance,
  ];

  @override
  void initState() {
    super.initState();
    for (final l in _sources) {
      l.addListener(_rafraichir);
    }
    _horloge = Timer.periodic(const Duration(seconds: 1), (_) => _rafraichir());
  }

  @override
  void dispose() {
    for (final l in _sources) {
      l.removeListener(_rafraichir);
    }
    _horloge?.cancel();
    super.dispose();
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  void _message(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  Future<void> _importerGpx() async {
    final fichiers = await FilePicker.pickFiles(type: FileType.any);
    if (fichiers.isEmpty) return;
    final f = fichiers.first;
    try {
      final texte = utf8.decode(await f.readAsBytes(), allowMalformed: true);
      final p = Parcours.depuisPoints(lireGpx(texte));
      if (p.segments.isEmpty) {
        _message("Ce fichier ne contient pas de trace GPX lisible.");
        return;
      }
      await (await _fichierGpx()).writeAsString(texte);
      await widget.prefs.setString('nomGpx', f.name);
      s.choisirParcours(p, f.name);
    } catch (e) {
      _message('Lecture du GPX impossible : $e');
    }
  }

  Future<void> _retirerGpx() async {
    final f = await _fichierGpx();
    if (await f.exists()) await f.delete();
    await widget.prefs.remove('nomGpx');
    s.choisirParcours(null, null);
  }

  void _ouvrir(Widget ecran) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ecran));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (enfant, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(anim),
              child: enfant,
            ),
          ),
          child: s.active
              ? KeyedSubtree(key: const ValueKey('sortie'), child: _enSortie())
              : KeyedSubtree(
                  key: const ValueKey('accueil'),
                  child: _avantSortie(),
                ),
        ),
      ),
    );
  }

  // ======================================================================
  // Pendant la sortie
  // ======================================================================

  Widget _enSortie() {
    final e = s.coach?.etat;
    final ftp = s.reglages.ftpW;
    final cad = s.capteurs.cadenceRpm(const Duration(seconds: 3));
    final p3 = s.puissance3sW;
    final zone = p3 == null ? null : zonePuissance(p3, ftp);
    final cible = e?.puissanceCibleW;
    final reste = s.resteParcoursM;
    final a = s.derniereAlerte;
    final portionG = s.reglages.produitChoisi.glucidesG;
    final parcours = s.parcours;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // ---- Barre du haut : chrono + états
        Row(
          children: [
            Expanded(
              child: Text(
                _duree(s.duree),
                style: Polices.chiffresStyle(38, poids: FontWeight.w600),
              ),
            ),
            Pastille(
              s.capteurs.connectePuissance ? 'Watts' : 'Watts ?',
              s.capteurs.connectePuissance ? Couleurs.vert : Couleurs.cuivre,
            ),
            const SizedBox(width: 6),
            Pastille(
              s.suivi.actif ? 'En direct' : 'Suivi coupé',
              s.suivi.actif ? Couleurs.rouge : Couleurs.texte3,
              vivante: s.suivi.actif,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ---- Puissance (héros)
        Carte(
          lueur: zone?.couleur,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Puissance 3 s',
                          style: TextStyle(
                            color: Couleurs.texte2,
                            fontSize: 14,
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            ChiffreAnime(
                              _w(p3),
                              style: Polices.chiffresStyle(
                                92,
                                couleur: zone?.couleur ?? Couleurs.texte,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'W',
                              style: Polices.chiffresStyle(
                                26,
                                poids: FontWeight.w500,
                                couleur: Couleurs.texte3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Cadence',
                        style: TextStyle(color: Couleurs.texte2, fontSize: 14),
                      ),
                      ChiffreAnime(
                        cad == null ? '–' : '${cad.round()}',
                        style: Polices.chiffresStyle(52),
                      ),
                      const Text(
                        'tr/min',
                        style: TextStyle(color: Couleurs.texte3, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (zone != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: zone.couleur.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Z${zone.numero} · ${zone.nom}',
                    style: TextStyle(
                      color: zone.couleur,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (cible != null) ...[
                const SizedBox(height: 14),
                _BarreCible(puissanceW: p3 ?? 0, cibleW: cible),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---- Anneaux : réserve, glucides, eau
        Carte(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Flexible(
                child: Anneau(
                  fraction: (e?.wbalPct ?? 100) / 100,
                  couleur: Couleurs.or,
                  libelle: 'Réserve',
                  centre: _CentreAnneau(
                    e == null ? '–' : '${e.wbalPct.clamp(0, 100).round()}',
                    '%',
                  ),
                ),
              ),
              Flexible(
                child: Anneau(
                  fraction: e == null ? 0 : e.glucidesRetardG / portionG,
                  couleur: Couleurs.cuivre,
                  libelle: 'Glucides en retard',
                  centre: _CentreAnneau(
                    e == null
                        ? '–'
                        : '${e.glucidesRetardG.clamp(0, 999).round()}',
                    'g',
                  ),
                ),
              ),
              Flexible(
                child: Anneau(
                  fraction: e == null ? 0 : e.eauRetardMl / Reglages.gorgeesMl,
                  couleur: Couleurs.bleu,
                  libelle: 'Eau en retard',
                  centre: _CentreAnneau(
                    e == null ? '–' : '${e.eauRetardMl.clamp(0, 9999).round()}',
                    'ml',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---- Distance et profil
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Mesure(
                      'Parcouru',
                      _km(s.distanceParcoursM ?? s.distanceM),
                      'km',
                    ),
                  ),
                  Expanded(
                    child: _Mesure(
                      'Restant',
                      reste == null ? '–' : _km(reste),
                      'km',
                      aDroite: true,
                    ),
                  ),
                ],
              ),
              if (parcours != null) ...[
                const SizedBox(height: 12),
                ProfilParcours(
                  parcours: parcours,
                  positionM: s.distanceParcoursM,
                ),
              ],
              if (e?.monteeCourante != null) ...[
                const SizedBox(height: 10),
                _Bandeau(
                  icone: Icons.terrain_rounded,
                  couleur: Couleurs.or,
                  texte:
                      'Montée : reste '
                      '${_km(e!.monteeCourante!.finM - (s.distanceParcoursM ?? 0))} km'
                      '${e.tempsRestantMonteeS == null ? '' : ' · environ ${(e.tempsRestantMonteeS! / 60).round()} min'}',
                ),
              ] else if (e?.prochaineMontee != null &&
                  e?.distanceProchaineM != null) ...[
                const SizedBox(height: 10),
                _Bandeau(
                  icone: Icons.trending_up_rounded,
                  couleur: Couleurs.texte2,
                  texte:
                      'Prochaine montée dans ${_km(e!.distanceProchaineM!)} km : '
                      '${_km(e.prochaineMontee!.longueurM)} km à '
                      '${_dec(100 * e.prochaineMontee!.penteMoyenne)} %',
                ),
              ],
            ],
          ),
        ),

        // ---- Dernière alerte
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (enfant, anim) => SizeTransition(
            sizeFactor: anim,
            child: FadeTransition(opacity: anim, child: enfant),
          ),
          child: a == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(a.t),
                  padding: const EdgeInsets.only(top: 14),
                  child: Carte(
                    lueur: _couleurAlerte(a.type),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _couleurAlerte(
                              a.type,
                            ).withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _iconeAlerte(a.type),
                            color: _couleurAlerte(a.type),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dernière alerte',
                                style: TextStyle(
                                  color: Couleurs.texte3,
                                  fontSize: 12.5,
                                ),
                              ),
                              Text(a.texte, style: Polices.titreStyle(19)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        if (s.erreur != null || s.suivi.erreur != null) ...[
          const SizedBox(height: 12),
          Text(
            s.erreur ?? s.suivi.erreur!,
            style: const TextStyle(color: Couleurs.cuivre),
          ),
        ],
        const SizedBox(height: 22),
        BoutonMaintenir(
          texte: 'Maintenir pour arrêter',
          onValide: () => s.arreter(),
        ),
      ],
    );
  }

  // ======================================================================
  // Avant la sortie
  // ======================================================================

  Widget _avantSortie() {
    final p = s.parcours;
    final cap = s.capteurs;
    final suivi = s.suivi;
    final r = s.reglages;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: [
        // ---- En-tête
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Logo(),
                  SizedBox(height: 6),
                  Accroche('Mange, bois, dose ton effort.'),
                ],
              ),
            ),
            _BoutonRond(
              icone: Icons.tune_rounded,
              bulle: 'Réglages',
              onTap: () => _ouvrir(EcranReglages(reglages: r)),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ---- Profil du cycliste
        Row(
          children: [
            Expanded(child: _Puce('FTP', '${r.ftpW.round()}', 'W')),
            const SizedBox(width: 10),
            Expanded(child: _Puce('Poids', _dec(r.poidsKg), 'kg')),
            const SizedBox(width: 10),
            Expanded(child: _Puce('W/kg', _dec2(r.ftpW / r.poidsKg), '')),
          ],
        ),
        const SizedBox(height: 18),

        BoutonOr(
          texte: s.demarrage ? 'Démarrage…' : 'Démarrer la sortie',
          icone: Icons.play_arrow_rounded,
          onPressed: s.demarrage ? null : s.demarrer,
        ),
        if (s.erreur != null) ...[
          const SizedBox(height: 10),
          Text(s.erreur!, style: const TextStyle(color: Couleurs.cuivre)),
        ],

        if (s.journal != null) ...[
          const SizedBox(height: 18),
          Carte(
            lueur: Couleurs.or,
            child: _Bilan(sortie: s),
          ),
        ],

        // ---- Parcours
        const SizedBox(height: 26),
        const Rubrique('Parcours', icone: Icons.route_rounded),
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p == null)
                const Text(
                  'Sans parcours, le coach gère manger et boire, mais pas les '
                  'montées. Importe le GPX de ta sortie (Komoot, Strava, '
                  'GOATout…).',
                  style: TextStyle(color: Couleurs.texte2),
                )
              else ...[
                Text(
                  s.nomParcours ?? 'Parcours',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Polices.titreStyle(18),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    _Mesure('Distance', _km(p.longueurM), 'km'),
                    _Mesure('Dénivelé', '${_deniveleM(p).round()}', 'm'),
                    _Mesure('Montées', '${p.montees.length}', ''),
                  ],
                ),
                const SizedBox(height: 12),
                ProfilParcours(parcours: p),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _importerGpx,
                    icon: const Icon(
                      Icons.upload_file_rounded,
                      color: Couleurs.or,
                    ),
                    label: Text(
                      p == null ? 'Importer un GPX' : 'Changer de GPX',
                    ),
                  ),
                  if (p != null)
                    TextButton(
                      onPressed: _retirerGpx,
                      child: const Text('Retirer'),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ---- Nutrition
        const SizedBox(height: 26),
        const Rubrique('Nutrition', icone: Icons.restaurant_rounded),
        Carte(
          onTap: () => _ouvrir(EcranNutrition(reglages: r)),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Couleurs.cuivre.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cookie_rounded, color: Couleurs.cuivre),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ma nutrition', style: Polices.titreStyle(17)),
                    const SizedBox(height: 4),
                    Text(
                      '${rythme(r.produitChoisi, r.objectifGh)}'
                      ' (${_dec(r.objectifGh)} g/h)',
                      style: const TextStyle(color: Couleurs.texte2),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Couleurs.texte3),
            ],
          ),
        ),

        // ---- Capteurs
        const SizedBox(height: 26),
        const Rubrique('Capteurs', icone: Icons.bluetooth_rounded),
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LigneCapteur(
                icone: Icons.bolt_rounded,
                libelle: 'Puissance',
                nom: cap.nomPuissance,
                connecte: cap.connectePuissance,
                onOublier: () => cap.oublier(TypeCapteur.puissance),
              ),
              const Divider(height: 18),
              _LigneCapteur(
                icone: Icons.favorite_rounded,
                libelle: 'Cardio',
                nom: cap.nomCardio,
                connecte: cap.connecteCardio,
                onOublier: () => cap.oublier(TypeCapteur.cardio),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: cap.recherche ? null : cap.chercher,
                icon: cap.recherche
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Couleurs.or,
                        ),
                      )
                    : const Icon(
                        Icons.bluetooth_searching_rounded,
                        color: Couleurs.or,
                      ),
                label: Text(
                  cap.recherche
                      ? 'Recherche… (pédale un peu)'
                      : 'Chercher les capteurs',
                ),
              ),
              for (final t in cap.trouves)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    t.type == TypeCapteur.puissance
                        ? Icons.bolt_rounded
                        : Icons.favorite_rounded,
                  ),
                  title: Text(t.nom),
                  subtitle: Text(
                    t.type == TypeCapteur.puissance ? 'Puissance' : 'Cardio',
                    style: const TextStyle(color: Couleurs.texte3),
                  ),
                  trailing: FilledButton(
                    onPressed: () => cap.choisir(t),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(60, 40),
                    ),
                    child: const Text('Utiliser'),
                  ),
                ),
              if (cap.erreur != null) ...[
                const SizedBox(height: 8),
                Text(
                  cap.erreur!,
                  style: const TextStyle(color: Couleurs.cuivre),
                ),
              ],
            ],
          ),
        ),

        // ---- Suivi en direct
        const SizedBox(height: 26),
        const Rubrique('Suivi en direct', icone: Icons.share_location_rounded),
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: suivi.partage,
                onChanged: (v) => suivi.partage = v,
                title: const Text('Partager ma position pendant la sortie'),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Couleurs.fond,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Couleurs.ligne),
                ),
                child: SelectableText(
                  suivi.lienPage,
                  style: const TextStyle(color: Couleurs.texte2, fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: suivi.lienPage),
                      );
                      _message('Lien copié : colle-le dans un SMS.');
                    },
                    icon: const Icon(Icons.copy_rounded, color: Couleurs.or),
                    label: const Text('Copier le lien'),
                  ),
                  TextButton(
                    onPressed: () => suivi.changerDeLien(),
                    child: const Text('Changer de lien'),
                  ),
                ],
              ),
              if (suivi.info != null)
                Text(suivi.info!, style: const TextStyle(color: Couleurs.or)),
            ],
          ),
        ),

        // ---- Problèmes rencontrés
        if (Diagnostic.instance.erreurs.isNotEmpty) ...[
          const SizedBox(height: 26),
          const Rubrique(
            'Problèmes rencontrés',
            icone: Icons.report_problem_rounded,
          ),
          Carte(
            lueur: Couleurs.rouge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Diagnostic.instance.texte,
                  style: const TextStyle(color: Couleurs.cuivre, fontSize: 12),
                  maxLines: 12,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: Diagnostic.instance.texte),
                        );
                        _message('Copié : colle-le dans un message.');
                      },
                      child: const Text('Copier'),
                    ),
                    TextButton(
                      onPressed: Diagnostic.instance.effacer,
                      child: const Text('Effacer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // ---- Écran éteint
        const SizedBox(height: 26),
        const Rubrique(
          'Pour que tout tienne écran éteint',
          icone: Icons.battery_saver_rounded,
        ),
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Dans les réglages de l'appli : batterie sur « Aucune restriction », "
                'démarrage automatique activé, notifications autorisées. Ne '
                "ferme pas l'appli depuis les applis récentes pendant une sortie.",
                style: TextStyle(color: Couleurs.texte2),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Geolocator.openAppSettings(),
                icon: const Icon(
                  Icons.settings_applications_rounded,
                  color: Couleurs.or,
                ),
                label: const Text("Ouvrir les réglages de l'appli"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Version $versionAppli',
            style: const TextStyle(color: Couleurs.texte3, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ==========================================================================
// Réglages
// ==========================================================================

class EcranReglages extends StatefulWidget {
  const EcranReglages({super.key, required this.reglages});

  final Reglages reglages;

  @override
  State<EcranReglages> createState() => _EcranReglagesState();
}

class _EcranReglagesState extends State<EcranReglages> {
  late final _poids = TextEditingController(
    text: _dec(widget.reglages.poidsKg),
  );
  late final _velo = TextEditingController(text: _dec(widget.reglages.veloKg));
  late final _ftp = TextEditingController(text: _dec(widget.reglages.ftpW));
  late final _wprime = TextEditingController(
    text: _dec(widget.reglages.wPrimeKj),
  );
  late bool _voix = widget.reglages.voix;
  String? _erreur;

  double? _nombre(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _enregistrer() async {
    final poids = _nombre(_poids);
    final velo = _nombre(_velo);
    final ftp = _nombre(_ftp);
    final wprime = _nombre(_wprime);
    if (poids == null || velo == null || ftp == null || wprime == null) {
      setState(() => _erreur = 'Un nombre est mal écrit.');
      return;
    }
    await widget.reglages.enregistrer(
      poidsKg: poids,
      veloKg: velo,
      ftpW: ftp,
      wPrimeKj: wprime,
      voix: _voix,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    Widget champ(String libelle, TextEditingController c, String unite) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Polices.chiffresStyle(22, poids: FontWeight.w600),
            decoration: InputDecoration(labelText: libelle, suffixText: unite),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Rubrique('Toi et ton vélo', icone: Icons.pedal_bike_rounded),
          Carte(
            child: Column(
              children: [
                champ('Ton poids', _poids, 'kg'),
                champ('Poids du vélo équipé', _velo, 'kg'),
                champ('FTP', _ftp, 'W'),
                champ(
                  "Réserve W′ (laisse 18 si tu ne sais pas)",
                  _wprime,
                  'kJ',
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Rubrique('Annonces', icone: Icons.record_voice_over_rounded),
          Carte(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _voix,
              onChanged: (v) => setState(() => _voix = v),
              title: const Text('Annonces à voix haute'),
              subtitle: const Text(
                'Dans tes écouteurs, en plus des notifications.',
                style: TextStyle(color: Couleurs.texte3),
              ),
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, style: const TextStyle(color: Couleurs.cuivre)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _enregistrer,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

// ==========================================================================
// Petits éléments
// ==========================================================================

String _dec(double x) {
  final t = x.toStringAsFixed(1);
  return (t.endsWith('.0') ? t.substring(0, t.length - 2) : t).replaceAll(
    '.',
    ',',
  );
}

String _dec2(double x) => x.toStringAsFixed(2).replaceAll('.', ',');

String _km(double m) => (m / 1000).toStringAsFixed(1).replaceAll('.', ',');

String _w(double? w) => w == null ? '–' : '${w.round()}';

String _duree(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final sec = d.inSeconds % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

double _deniveleM(Parcours p) {
  var d = 0.0;
  for (final s in p.segments) {
    if (s.pente > 0) d += s.pente * s.longueurM;
  }
  return d;
}

Color _couleurAlerte(TypeAlerte t) => switch (t) {
  TypeAlerte.montee => Couleurs.or,
  TypeAlerte.manger => Couleurs.cuivre,
  TypeAlerte.boire => Couleurs.bleu,
};

IconData _iconeAlerte(TypeAlerte t) => switch (t) {
  TypeAlerte.montee => Icons.terrain_rounded,
  TypeAlerte.manger => Icons.cookie_rounded,
  TypeAlerte.boire => Icons.water_drop_rounded,
};

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({
    required this.icone,
    required this.bulle,
    required this.onTap,
  });
  final IconData icone;
  final String bulle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: bulle,
    child: Material(
      color: Couleurs.surface,
      shape: const CircleBorder(side: BorderSide(color: Couleurs.ligne)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icone, color: Couleurs.texte),
        ),
      ),
    ),
  );
}

/// Petite case chiffrée de l'accueil (FTP, poids, W/kg).
class _Puce extends StatelessWidget {
  const _Puce(this.libelle, this.valeur, this.unite);
  final String libelle;
  final String valeur;
  final String unite;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Couleurs.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Couleurs.ligne),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle,
          style: const TextStyle(color: Couleurs.texte3, fontSize: 12),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: valeur, style: Polices.chiffresStyle(28)),
                if (unite.isNotEmpty)
                  TextSpan(
                    text: ' $unite',
                    style: Polices.chiffresStyle(
                      16,
                      poids: FontWeight.w500,
                      couleur: Couleurs.texte3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Libellé + grand chiffre + unité.
class _Mesure extends StatelessWidget {
  const _Mesure(this.libelle, this.valeur, this.unite, {this.aDroite = false});
  final String libelle;
  final String valeur;
  final String unite;
  final bool aDroite;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: aDroite
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        libelle,
        style: const TextStyle(color: Couleurs.texte3, fontSize: 13),
      ),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: valeur, style: Polices.chiffresStyle(34)),
            if (unite.isNotEmpty)
              TextSpan(
                text: ' $unite',
                style: Polices.chiffresStyle(
                  17,
                  poids: FontWeight.w500,
                  couleur: Couleurs.texte3,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _CentreAnneau extends StatelessWidget {
  const _CentreAnneau(this.valeur, this.unite);
  final String valeur;
  final String unite;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChiffreAnime(valeur, style: Polices.chiffresStyle(32)),
          Text(
            unite,
            style: const TextStyle(color: Couleurs.texte3, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.icone,
    required this.couleur,
    required this.texte,
  });
  final IconData icone;
  final Color couleur;
  final String texte;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icone, color: couleur, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(texte, style: const TextStyle(fontSize: 15))),
      ],
    ),
  );
}

/// Barre « puissance tenue / puissance cible » en montée.
class _BarreCible extends StatelessWidget {
  const _BarreCible({required this.puissanceW, required this.cibleW});
  final double puissanceW;
  final double cibleW;

  @override
  Widget build(BuildContext context) {
    final rapport = cibleW <= 0 ? 0.0 : puissanceW / cibleW;
    final couleur = rapport > 1.05
        ? Couleurs.rouge
        : rapport >= 0.9
        ? Couleurs.vert
        : Couleurs.or;
    final message = rapport > 1.05
        ? 'Lève le pied'
        : rapport >= 0.9
        ? 'Parfait, garde ça'
        : 'Tu peux appuyer';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flag_rounded, color: Couleurs.or, size: 18),
            const SizedBox(width: 6),
            Text('Cible ', style: const TextStyle(color: Couleurs.texte2)),
            Text(
              '${cibleW.round()} W',
              style: Polices.chiffresStyle(22, couleur: Couleurs.or),
            ),
            const Spacer(),
            Text(
              message,
              style: TextStyle(color: couleur, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: (rapport / 1.3).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 500),
            builder: (_, v, _) => Stack(
              children: [
                Container(height: 10, color: Couleurs.surface2),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(height: 10, color: couleur),
                ),
                // Trait de la cible (à 1/1,3 de la largeur)
                Align(
                  alignment: const Alignment(2 / 1.3 - 1, 0),
                  child: Container(width: 3, height: 10, color: Couleurs.texte),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LigneCapteur extends StatelessWidget {
  const _LigneCapteur({
    required this.icone,
    required this.libelle,
    required this.nom,
    required this.connecte,
    required this.onOublier,
  });

  final IconData icone;
  final String libelle;
  final String? nom;
  final bool connecte;
  final VoidCallback onOublier;

  @override
  Widget build(BuildContext context) {
    final couleur = nom == null
        ? Couleurs.texte3
        : (connecte ? Couleurs.vert : Couleurs.cuivre);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icone, color: couleur, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(libelle, style: Polices.titreStyle(16)),
              Text(
                nom == null
                    ? 'Aucun capteur choisi'
                    : '$nom · ${connecte ? 'connecté' : 'en attente'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: couleur, fontSize: 13),
              ),
            ],
          ),
        ),
        if (nom != null)
          TextButton(onPressed: onOublier, child: const Text('Oublier')),
      ],
    );
  }
}

class _Bilan extends StatelessWidget {
  const _Bilan({required this.sortie});
  final Sortie sortie;

  @override
  Widget build(BuildContext context) {
    final e = sortie.coach?.etat;
    if (e == null) return const SizedBox.shrink();
    final produit = sortie.reglages.produitChoisi;
    final portions = (e.glucidesMangesG / produit.glucidesG).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_rounded, color: Couleurs.or),
            const SizedBox(width: 8),
            Text('Dernière sortie', style: Polices.titreStyle(18)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            _Mesure('Distance', _km(sortie.distanceM), 'km'),
            _Mesure('Travail', '${e.travailKj.round()}', 'kJ'),
            _Mesure('Alertes', '${sortie.alertes.length}', ''),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Glucides : $portions × ${produit.nom} conseillé'
          '${portions > 1 ? 's' : ''} (${e.glucidesMangesG.round()} g), '
          '${e.glucidesBrulesG.round()} g brûlés',
          style: const TextStyle(color: Couleurs.texte2),
        ),
        Text(
          'Eau : ${_dec(e.eauBueL)} L conseillés, '
          '${_dec(e.eauPerdueL)} L de sueur estimée',
          style: const TextStyle(color: Couleurs.texte2),
        ),
        const SizedBox(height: 4),
        const Text(
          'Journal enregistré dans le téléphone (fichier CSV).',
          style: TextStyle(color: Couleurs.texte3, fontSize: 12.5),
        ),
      ],
    );
  }
}
