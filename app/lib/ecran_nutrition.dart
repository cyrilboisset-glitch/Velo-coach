// Écran « Ma nutrition » : les produits que l'on emporte (valeurs de
// l'étiquette), celui qu'on mange pendant la sortie, l'objectif en g/h et
// la boisson.
import 'package:flutter/material.dart';

import 'charte.dart';
import 'composants.dart';
import 'reglages.dart';

const Color _texte2 = Couleurs.texte2;
const Color _orange = Couleurs.cuivre;

String _dec(double x) {
  final t = x.toStringAsFixed(1);
  return (t.endsWith('.0') ? t.substring(0, t.length - 2) : t).replaceAll(
    '.',
    ',',
  );
}

double? _nombre(String texte) =>
    double.tryParse(texte.trim().replaceAll(',', '.'));

/// Phrase du type « 1 gel toutes les 1 h 15 ».
String rythme(ProduitNutrition p, double objectifGh) {
  if (objectifGh <= 0) return 'aucun glucide prévu';
  final min = (p.glucidesG / objectifGh * 60).round();
  final duree = min < 60
      ? '$min min'
      : '${min ~/ 60} h${min % 60 == 0 ? '' : ' ${(min % 60).toString().padLeft(2, '0')}'}';
  return '1 ${p.nom} toutes les $duree';
}

class EcranNutrition extends StatefulWidget {
  const EcranNutrition({super.key, required this.reglages});

  final Reglages reglages;

  @override
  State<EcranNutrition> createState() => _EcranNutritionState();
}

class _EcranNutritionState extends State<EcranNutrition> {
  late List<ProduitNutrition> _produits = [...widget.reglages.produits];
  late int _choisi = widget.reglages.indexProduit;
  late final _objectif = TextEditingController(
    text: _dec(widget.reglages.objectifGh),
  );
  late final _boisson = TextEditingController(
    text: _dec(widget.reglages.boissonGParL),
  );
  String? _erreur;

  double get _objectifGh => _nombre(_objectif.text) ?? 0;

  Future<void> _modifier(int? index) async {
    final resultat = await showDialog<ProduitNutrition>(
      context: context,
      builder: (_) =>
          _DialogueProduit(produit: index == null ? null : _produits[index]),
    );
    if (resultat == null) return;
    setState(() {
      if (index == null) {
        _produits = [..._produits, resultat];
        _choisi = _produits.length - 1;
      } else {
        _produits[index] = resultat;
      }
    });
  }

  void _supprimer(int index) {
    if (_produits.length <= 1) return;
    setState(() {
      _produits = [..._produits]..removeAt(index);
      if (_choisi >= _produits.length) _choisi = _produits.length - 1;
    });
  }

  Future<void> _enregistrer() async {
    final objectif = _nombre(_objectif.text);
    final boisson = _nombre(_boisson.text);
    if (objectif == null || objectif < 0 || objectif > 120) {
      setState(() => _erreur = 'Objectif : un nombre entre 0 et 120 g/h.');
      return;
    }
    if (boisson == null || boisson < 0 || boisson > 150) {
      setState(
        () => _erreur = 'Boisson : un nombre entre 0 et 150 g par litre.',
      );
      return;
    }
    await widget.reglages.enregistrerNutrition(
      produits: _produits,
      indexProduit: _choisi,
      objectifGh: objectif,
      boissonGParL: boisson,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final choisi = _produits[_choisi];
    return Scaffold(
      appBar: AppBar(title: const Text('Ma nutrition')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Note ici ce que tu emportes pour la sortie, avec les valeurs '
            "écrites sur l'emballage. Pendant la sortie, l'appli te dira "
            'quand en manger.',
            style: TextStyle(color: _texte2),
          ),
          const SizedBox(height: 24),
          const _Titre('1. Combien de glucides par heure ?'),
          TextField(
            controller: _objectif,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Objectif',
              suffixText: 'g par heure',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final v in [20, 30, 45, 60])
                ActionChip(
                  label: Text('$v g/h'),
                  onPressed: () => setState(() => _objectif.text = '$v'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Repères : sortie tranquille 20 à 30 g/h ; longue sortie 40 à '
            '60 g/h ; au-delà de 60 g/h, seulement si ton estomac est '
            'entraîné (avec des produits glucose + fructose). En dessous '
            "d'une heure d'effort, manger n'est pas nécessaire.",
            style: TextStyle(color: _texte2, fontSize: 13),
          ),
          const SizedBox(height: 28),
          const _Titre('2. Mes produits'),
          const Text(
            'Coche celui que tu manges pendant la sortie.',
            style: TextStyle(color: _texte2),
          ),
          RadioGroup<int>(
            groupValue: _choisi,
            onChanged: (v) => setState(() => _choisi = v ?? _choisi),
            child: Column(
              children: [
                for (var i = 0; i < _produits.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Radio<int>(value: i),
                    title: Text(
                      _produits[i].nom,
                      style: Polices.titreStyle(16, poids: 600),
                    ),
                    subtitle: Text(
                      '${_dec(_produits[i].glucidesG)} g de glucides par portion',
                    ),
                    onTap: () => setState(() => _choisi = i),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Modifier',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _modifier(i),
                        ),
                        if (_produits.length > 1)
                          IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _supprimer(i),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _modifier(null),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un produit'),
            ),
          ),
          const SizedBox(height: 12),
          Carte(
            lueur: Couleurs.or,
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: Couleurs.or),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pendant la sortie : ${rythme(choisi, _objectifGh)}.',
                    style: Polices.titreStyle(16, poids: 600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _Titre('3. Ma boisson'),
          TextField(
            controller: _boisson,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Glucides pour 1 litre',
              suffixText: 'g',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "0 si tu bois de l'eau. Boisson énergétique : l'étiquette donne "
            'souvent les glucides « pour 100 ml » : multiplie par 10. Ce que '
            "tu bois compte alors aussi dans tes glucides.",
            style: TextStyle(color: _texte2, fontSize: 13),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, style: const TextStyle(color: _orange)),
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

// ---- Ajouter / modifier un produit -----------------------------------------

class _DialogueProduit extends StatefulWidget {
  const _DialogueProduit({this.produit});

  final ProduitNutrition? produit;

  @override
  State<_DialogueProduit> createState() => _DialogueProduitState();
}

class _DialogueProduitState extends State<_DialogueProduit> {
  late final _nom = TextEditingController(text: widget.produit?.nom ?? '');
  late bool _pour100g = widget.produit?.glucidesPour100G != null;
  late final _parPortion = TextEditingController(
    text: widget.produit == null ? '' : _dec(widget.produit!.glucidesG),
  );
  late final _poids = TextEditingController(
    text: widget.produit?.poidsPortionG == null
        ? ''
        : _dec(widget.produit!.poidsPortionG!),
  );
  late final _pour100 = TextEditingController(
    text: widget.produit?.glucidesPour100G == null
        ? ''
        : _dec(widget.produit!.glucidesPour100G!),
  );
  String? _erreur;

  double? get _glucides {
    if (!_pour100g) return _nombre(_parPortion.text);
    final poids = _nombre(_poids.text);
    final g100 = _nombre(_pour100.text);
    if (poids == null || g100 == null) return null;
    return glucidesPortion(poidsPortionG: poids, glucidesPour100G: g100);
  }

  void _valider() {
    final nom = _nom.text.trim();
    final g = _glucides;
    if (nom.isEmpty) {
      setState(() => _erreur = 'Donne un nom au produit.');
      return;
    }
    if (g == null || g <= 0 || g > 150) {
      setState(
        () => _erreur =
            'Glucides par portion : entre 1 et 150 g. Vérifie '
            'les chiffres.',
      );
      return;
    }
    Navigator.pop(
      context,
      ProduitNutrition(
        nom: nom,
        glucidesG: double.parse(g.toStringAsFixed(1)),
        poidsPortionG: _pour100g ? _nombre(_poids.text) : null,
        glucidesPour100G: _pour100g ? _nombre(_pour100.text) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget champ(TextEditingController c, String libelle, String unite) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: c,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: libelle,
              suffixText: unite,
              border: const OutlineInputBorder(),
            ),
          ),
        );
    final g = _glucides;
    return AlertDialog(
      title: Text(widget.produit == null ? 'Nouveau produit' : 'Modifier'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nom,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: 'Nom (court)',
                hintText: 'ex. gel Maurten, barre Clif',
              ),
            ),
            const Text("Sur l'emballage, je lis les glucides :"),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('par portion')),
                ButtonSegment(value: true, label: Text('pour 100 g')),
              ],
              selected: {_pour100g},
              onSelectionChanged: (s) => setState(() => _pour100g = s.first),
            ),
            if (!_pour100g)
              champ(_parPortion, 'Glucides dans 1 portion', 'g')
            else ...[
              champ(_pour100, 'Glucides pour 100 g', 'g'),
              champ(_poids, "Poids d'une portion (gel, barre, sachet)", 'g'),
            ],
            const SizedBox(height: 10),
            Text(
              g == null
                  ? 'Glucides par portion : –'
                  : 'Glucides par portion : ${_dec(g)} g',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Prends la ligne « Glucides » (et non « dont sucres »).',
              style: TextStyle(color: _texte2, fontSize: 13),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: const TextStyle(color: _orange)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _valider, child: const Text('Valider')),
      ],
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(texte, style: Polices.titreStyle(19, couleur: Couleurs.or)),
  );
}
