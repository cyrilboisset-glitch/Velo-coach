// Vélo Coach : coaching en direct (manger, boire, puissance en montée) et
// suivi en direct pour être suivi sur une carte (ancienne appli « Suivi
// direct », fusionnée ici).
//
// Trois écrans dans un seul : avant la sortie (parcours, capteurs, lien
// de suivi), pendant la sortie (gros chiffres), et les réglages.
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
import 'ecran_nutrition.dart';
import 'capteurs.dart';
import 'config_appli.dart';
import 'diagnostic.dart';
import 'reglages.dart';
import 'sortie.dart';
import 'suivi.dart';

const Color _fond = Color(0xFF0E1014);
const Color _surface = Color(0xFF171A20);
const Color _ligne = Color(0xFF2A2F39);
const Color _accent = Color(0xFFC8F031);
const Color _rouge = Color(0xFFFF6B7A);
const Color _orange = Color(0xFFF0A630);
const Color _bleu = Color(0xFF6CB4FF);
const Color _texte2 = Color(0xFFA7AFBC);

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
        theme: ThemeData(brightness: Brightness.dark),
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _fond,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
          surface: _surface,
        ),
      ),
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

  @override
  void initState() {
    super.initState();
    for (final l in [s, s.capteurs, s.suivi, s.reglages, Diagnostic.instance]) {
      l.addListener(_rafraichir);
    }
    _horloge = Timer.periodic(const Duration(seconds: 1), (_) => _rafraichir());
  }

  @override
  void dispose() {
    for (final l in [s, s.capteurs, s.suivi, s.reglages, Diagnostic.instance]) {
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

  Future<void> _confirmerArret() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter la sortie ?'),
        content: const Text('Le coach et le suivi en direct s’arrêtent.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
    if (ok == true) await s.arreter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: s.active ? _enSortie() : _avantSortie()),
    );
  }

  // ---- Pendant la sortie ---------------------------------------------------

  Widget _enSortie() {
    final c = s.coach;
    final e = c?.etat;
    final cad = s.capteurs.cadenceRpm(const Duration(seconds: 3));
    final cible = e?.puissanceCibleW;
    final reste = s.resteParcoursM;
    final a = s.derniereAlerte;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _duree(s.duree),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Pastille(
              s.capteurs.connectePuissance ? 'Puissance OK' : 'Puissance ?',
              s.capteurs.connectePuissance ? _accent : _orange,
            ),
            const SizedBox(width: 6),
            _Pastille(
              s.suivi.actif ? 'En direct' : 'Suivi coupé',
              s.suivi.actif ? _accent : _texte2,
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // Hauteur fixe : les chiffres ne sont jamais coupés, quelle
            // que soit la taille de l'écran ou de la police.
            mainAxisExtent: 124,
          ),
          children: [
            _Chiffre('Puissance 3 s', _w(s.puissance3sW), 'W'),
            _Chiffre('Cadence', cad == null ? '–' : '${cad.round()}', 'tr/min'),
            _Chiffre(
              cible == null ? 'Cible' : 'Cible montée',
              cible == null ? '–' : '${cible.round()}',
              'W',
              couleur: cible == null ? null : _accent,
            ),
            _Chiffre(
              'Réserve',
              e == null ? '–' : '${e.wbalPct.clamp(0, 100).round()}',
              '%',
            ),
            _Chiffre(
              'Glucides en retard',
              e == null ? '–' : '${e.glucidesRetardG.round()}',
              'g',
              couleur: _orange,
            ),
            _Chiffre(
              'Eau en retard',
              e == null ? '–' : '${e.eauRetardMl.round()}',
              'ml',
              couleur: _bleu,
            ),
            _Chiffre('Parcouru', _km(s.distanceParcoursM ?? s.distanceM), 'km'),
            _Chiffre('Restant', reste == null ? '–' : _km(reste), 'km'),
          ],
        ),
        if (e?.monteeCourante != null) ...[
          const SizedBox(height: 10),
          _Carte(
            child: Text(
              'Montée : reste '
              '${_km(e!.monteeCourante!.finM - (s.distanceParcoursM ?? 0))} km'
              '${e.tempsRestantMonteeS == null ? '' : ', environ ${(e.tempsRestantMonteeS! / 60).round()} min'}',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ] else if (e?.prochaineMontee != null &&
            e?.distanceProchaineM != null) ...[
          const SizedBox(height: 10),
          _Carte(
            child: Text(
              'Prochaine montée dans ${_km(e!.distanceProchaineM!)} km : '
              '${_km(e.prochaineMontee!.longueurM)} km à '
              '${_dec(100 * e.prochaineMontee!.penteMoyenne)} %',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
        if (a != null) ...[
          const SizedBox(height: 10),
          _Carte(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dernière alerte', style: TextStyle(color: _texte2)),
                const SizedBox(height: 4),
                Text(
                  a.texte,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (s.erreur != null || s.suivi.erreur != null) ...[
          const SizedBox(height: 10),
          Text(
            s.erreur ?? s.suivi.erreur!,
            style: const TextStyle(color: _orange),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 64,
          child: FilledButton(
            onPressed: _confirmerArret,
            style: FilledButton.styleFrom(
              backgroundColor: _rouge,
              foregroundColor: _fond,
            ),
            child: const Text(
              'Arrêter la sortie',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Avant la sortie ------------------------------------------------------

  Widget _avantSortie() {
    final p = s.parcours;
    final cap = s.capteurs;
    final suivi = s.suivi;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Vélo Coach',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Réglages',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EcranReglages(reglages: s.reglages),
                ),
              ),
            ),
          ],
        ),
        Text(
          'Version $versionAppli',
          style: const TextStyle(color: _texte2, fontSize: 12),
        ),
        Text(
          'FTP ${s.reglages.ftpW.round()} W · '
          '${_dec(s.reglages.poidsKg)} + ${_dec(s.reglages.veloKg)} kg',
          style: const TextStyle(color: _texte2),
        ),
        const SizedBox(height: 16),
        _Carte(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ma nutrition',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${rythme(s.reglages.produitChoisi, s.reglages.objectifGh)}'
                      ' (${_dec(s.reglages.objectifGh)} g/h)',
                      style: const TextStyle(color: _texte2),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EcranNutrition(reglages: s.reglages),
                  ),
                ),
                child: const Text('Modifier'),
              ),
            ],
          ),
        ),
        if (s.journal != null) ...[
          const SizedBox(height: 16),
          _Carte(child: _Bilan(sortie: s)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 72,
          child: FilledButton(
            onPressed: s.demarrage ? null : s.demarrer,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _fond,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              s.demarrage ? 'Démarrage…' : 'Démarrer la sortie',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (s.erreur != null) ...[
          const SizedBox(height: 10),
          Text(s.erreur!, style: const TextStyle(color: _orange)),
        ],
        const SizedBox(height: 28),
        const _Titre('Parcours'),
        if (p == null)
          const Text(
            'Sans parcours, le coach gère manger et boire, mais pas les '
            'montées. Importe le GPX de ta sortie (Komoot, Strava…).',
            style: TextStyle(color: _texte2),
          )
        else
          Text(
            '${s.nomParcours ?? 'Parcours'} : ${_km(p.longueurM)} km, '
            '${p.montees.length} montée${p.montees.length > 1 ? 's' : ''}'
            '${p.montees.isEmpty ? '' : ' (${p.montees.map((m) => '${_km(m.longueurM)} km à ${_dec(100 * m.penteMoyenne)} %').join(', ')})'}',
            style: const TextStyle(color: _texte2),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _importerGpx,
              icon: const Icon(Icons.route),
              label: Text(p == null ? 'Importer un GPX' : 'Changer de GPX'),
            ),
            if (p != null)
              TextButton(onPressed: _retirerGpx, child: const Text('Retirer')),
          ],
        ),
        const SizedBox(height: 28),
        const _Titre('Capteurs'),
        _LigneCapteur(
          'Puissance',
          cap.nomPuissance,
          cap.connectePuissance,
          onOublier: () => cap.oublier(TypeCapteur.puissance),
        ),
        _LigneCapteur(
          'Cardio',
          cap.nomCardio,
          cap.connecteCardio,
          onOublier: () => cap.oublier(TypeCapteur.cardio),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: cap.recherche ? null : cap.chercher,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(
              cap.recherche
                  ? 'Recherche… (pédale un peu)'
                  : 'Chercher les capteurs',
            ),
          ),
        ),
        for (final t in cap.trouves)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              t.type == TypeCapteur.puissance ? Icons.bolt : Icons.favorite,
            ),
            title: Text(t.nom),
            subtitle: Text(
              t.type == TypeCapteur.puissance ? 'Puissance' : 'Cardio',
            ),
            trailing: TextButton(
              onPressed: () => cap.choisir(t),
              child: const Text('Utiliser'),
            ),
          ),
        if (cap.erreur != null)
          Text(cap.erreur!, style: const TextStyle(color: _orange)),
        const SizedBox(height: 28),
        const _Titre('Suivi en direct'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: suivi.partage,
          onChanged: (v) => suivi.partage = v,
          title: const Text('Partager ma position pendant la sortie'),
        ),
        SelectableText(suivi.lienPage, style: const TextStyle(color: _texte2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: suivi.lienPage));
                _message('Lien copié : colle-le dans un SMS.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copier le lien'),
            ),
            TextButton(
              onPressed: () => suivi.changerDeLien(),
              child: const Text('Changer de lien'),
            ),
          ],
        ),
        if (suivi.info != null)
          Text(suivi.info!, style: const TextStyle(color: _accent)),
        const SizedBox(height: 28),
        if (Diagnostic.instance.erreurs.isNotEmpty) ...[
          const _Titre('Problèmes rencontrés'),
          _Carte(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Diagnostic.instance.texte,
                  style: const TextStyle(color: _orange, fontSize: 12),
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
          const SizedBox(height: 28),
        ],
        const _Titre('Pour que tout tienne écran éteint'),
        const Text(
          "Dans les réglages de l'appli : batterie → Aucune restriction, "
          "démarrage automatique activé, notifications autorisées. Ne ferme "
          "pas l'appli depuis les applis récentes pendant une sortie.",
          style: TextStyle(color: _texte2),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => Geolocator.openAppSettings(),
            icon: const Icon(Icons.settings_applications),
            label: const Text("Ouvrir les réglages de l'appli"),
          ),
        ),
      ],
    );
  }
}

// ---- Réglages -----------------------------------------------------------------

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
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: libelle,
              suffixText: unite,
              border: const OutlineInputBorder(),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          champ('Ton poids', _poids, 'kg'),
          champ('Poids du vélo équipé', _velo, 'kg'),
          champ('FTP', _ftp, 'W'),
          champ("Réserve W′ (laisser 18 si tu ne sais pas)", _wprime, 'kJ'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _voix,
            onChanged: (v) => setState(() => _voix = v),
            title: const Text('Annonces à voix haute'),
          ),
          if (_erreur != null)
            Text(_erreur!, style: const TextStyle(color: _orange)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _enregistrer,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

// ---- Petits éléments ------------------------------------------------------------

String _dec(double x) {
  final t = x.toStringAsFixed(1);
  return (t.endsWith('.0') ? t.substring(0, t.length - 2) : t).replaceAll(
    '.',
    ',',
  );
}

String _km(double m) => (m / 1000).toStringAsFixed(1).replaceAll('.', ',');

String _w(double? w) => w == null ? '–' : '${w.round()}';

String _duree(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final sec = d.inSeconds % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      texte,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );
}

class _Carte extends StatelessWidget {
  const _Carte({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _ligne),
    ),
    child: child,
  );
}

class _Chiffre extends StatelessWidget {
  const _Chiffre(this.libelle, this.valeur, this.unite, {this.couleur});

  final String libelle;
  final String valeur;
  final String unite;
  final Color? couleur;

  @override
  Widget build(BuildContext context) => _Carte(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          libelle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _texte2, fontSize: 14),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: valeur,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: couleur,
                  ),
                ),
                TextSpan(
                  text: ' $unite',
                  style: const TextStyle(fontSize: 16, color: _texte2),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Pastille extends StatelessWidget {
  const _Pastille(this.texte, this.couleur);
  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: couleur),
    ),
    child: Text(texte, style: TextStyle(color: couleur, fontSize: 12)),
  );
}

class _LigneCapteur extends StatelessWidget {
  const _LigneCapteur(
    this.libelle,
    this.nom,
    this.connecte, {
    required this.onOublier,
  });

  final String libelle;
  final String? nom;
  final bool connecte;
  final VoidCallback onOublier;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(
          Icons.circle,
          size: 12,
          color: nom == null ? _texte2 : (connecte ? _accent : _orange),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            nom == null
                ? '$libelle : aucun capteur choisi'
                : '$libelle : $nom (${connecte ? 'connecté' : 'pas encore connecté'})',
          ),
        ),
        if (nom != null)
          TextButton(onPressed: onOublier, child: const Text('Oublier')),
      ],
    ),
  );
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
        const Text(
          'Dernière sortie',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '${_km(sortie.distanceM)} km · ${e.travailKj.round()} kJ · '
          '${sortie.alertes.length} alertes',
        ),
        Text(
          'Glucides : $portions × ${produit.nom} conseillé'
          '${portions > 1 ? 's' : ''} (${e.glucidesMangesG.round()} g), '
          '${e.glucidesBrulesG.round()} g brûlés',
        ),
        Text(
          'Eau : ${_dec(e.eauBueL)} L conseillés, '
          '${_dec(e.eauPerdueL)} L de sueur estimée',
        ),
        const SizedBox(height: 4),
        const Text(
          'Journal enregistré dans le téléphone (fichier CSV).',
          style: TextStyle(color: _texte2),
        ),
      ],
    );
  }
}
