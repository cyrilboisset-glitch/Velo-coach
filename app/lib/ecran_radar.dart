// Test du radar arrière (ex. Magene L508) en Bluetooth.
//
// Pas de coach ici : l'écran cherche les appareils, se connecte à celui
// qu'on touche, liste ses services et caractéristiques, et enregistre les
// données brutes reçues. Le rapport peut être copié pour analyse.
//
// Piste à vérifier : les radars de la famille Garmin Varia utilisent le
// service 6a4e3200-667b-11e3-949a-0800200c9a66 (flux 6a4e3203). Format
// décrit par le dépôt partymola/bike-radar-docs (confirmé sur un seul
// modèle, pas sur le L508) :
//   octet 0 = compteur << 4 | 0x02, puis 3 octets par véhicule :
//   identifiant (bit 7 = présent), distance (m), indicateur (sens inconnu).
// ⚠ HYPOTHÈSE : ce format n'est pas vérifié sur le L508.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'charte.dart';
import 'composants.dart';

/// Un véhicule lu dans un paquet « menace » du flux V1.
class VehiculeRadar {
  const VehiculeRadar(this.id, this.distanceM, this.indicateur);
  final int id;
  final int distanceM;
  final int indicateur;
  @override
  String toString() => '#$id à $distanceM m (ind. $indicateur)';
}

/// Lit un paquet du flux V1 (6a4e3203). `null` si ce n'est pas un paquet
/// de véhicules (battement de cœur d'un octet, autre format).
List<VehiculeRadar>? lireMenacesV1(List<int> o) {
  if (o.length < 4 || (o.length - 1) % 3 != 0) return null;
  if (o[0] & 0x0F != 0x02) return null;
  final liste = <VehiculeRadar>[];
  for (var i = 1; i + 2 < o.length; i += 3) {
    final id = o[i];
    final distance = o[i + 1];
    if (id < 0x80 || id == 0xFD || distance == 0xFF) continue;
    liste.add(VehiculeRadar(id & 0x7F, distance, o[i + 2]));
  }
  return liste;
}

String _hex(List<int> o) =>
    o.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

final _serviceGarmin = '6a4e3200-667b-11e3-949a-0800200c9a66';

class EcranRadar extends StatefulWidget {
  const EcranRadar({super.key});
  @override
  State<EcranRadar> createState() => _EcranRadarState();
}

class _EcranRadarState extends State<EcranRadar> {
  final _trouves = <String, ScanResult>{};
  final _rapport = <String>[];
  final _abonnements = <StreamSubscription<dynamic>>[];
  BluetoothDevice? _appareil;
  bool _recherche = false;
  bool _connecte = false;
  bool _famille = false;
  String? _erreur;
  int _paquets = 0;
  String _dernier = '';

  void _noter(String l) {
    if (_rapport.length > 400) _rapport.removeAt(0);
    _rapport.add(l);
  }

  Future<void> _chercher() async {
    setState(() {
      _erreur = null;
      _trouves.clear();
      _recherche = true;
    });
    try {
      if (await FlutterBluePlus.isSupported == false) {
        throw StateError('Bluetooth absent');
      }
      final sub = FlutterBluePlus.onScanResults.listen((rs) {
        if (!mounted) return;
        setState(() {
          for (final r in rs) {
            _trouves[r.device.remoteId.str] = r;
          }
        });
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
      await sub.cancel();
    } catch (e) {
      _erreur =
          'Recherche impossible : active le Bluetooth et autorise '
          '« Appareils à proximité ». ($e)';
    }
    if (mounted) setState(() => _recherche = false);
  }

  static String _nom(ScanResult r) {
    final n = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : r.advertisementData.advName;
    return n.isEmpty ? '(sans nom)' : n;
  }

  static bool _probable(ScanResult r) {
    final n = _nom(r).toLowerCase();
    return n.contains('l508') ||
        n.contains('magene') ||
        n.contains('radar') ||
        n.contains('varia') ||
        n.contains('rtl') ||
        r.advertisementData.serviceUuids.any(
          (g) => g.str128.startsWith('6a4e'),
        );
  }

  Future<void> _connecter(ScanResult r) async {
    await FlutterBluePlus.stopScan();
    await _deconnecter();
    final a = r.device;
    setState(() {
      _appareil = a;
      _erreur = null;
      _paquets = 0;
      _dernier = '';
      _famille = false;
      _rapport
        ..clear()
        ..add('Appareil : ${_nom(r)} (${a.remoteId.str}), RSSI ${r.rssi}')
        ..add(
          'Publicité : services ${r.advertisementData.serviceUuids.map((g) => g.str).join(', ')}',
        )
        ..add(
          'Données fabricant : ${r.advertisementData.manufacturerData.entries.map((e) => '${e.key.toRadixString(16)}=${_hex(e.value)}').join('; ')}',
        );
    });
    try {
      await a.connect(license: License.nonprofit, autoConnect: false);
      setState(() => _connecte = true);
      final services = await a.discoverServices();
      for (final s in services) {
        _noter('Service ${s.uuid.str128}');
        if (s.uuid.str128 == _serviceGarmin) _famille = true;
        for (final c in s.characteristics) {
          final p = c.properties;
          final props = [
            if (p.read) 'lecture',
            if (p.write) 'écriture',
            if (p.notify) 'notification',
            if (p.indicate) 'indication',
          ].join('+');
          _noter('  Caractéristique ${c.uuid.str128} ($props)');
          if (p.read) {
            try {
              _noter('    valeur : ${_hex(await c.read())}');
            } catch (e) {
              _noter('    lecture refusée : $e');
            }
          }
          if (p.notify) {
            try {
              await c.setNotifyValue(true);
              final id = c.uuid.str128.substring(4, 8);
              _abonnements.add(c.onValueReceived.listen((v) => _recu(id, v)));
              _noter('    abonné aux notifications');
            } catch (e) {
              _noter('    abonnement refusé : $e');
            }
          }
        }
      }
      _noter('--- données reçues ---');
    } catch (e) {
      _erreur = 'Connexion impossible : $e';
    }
    if (mounted) setState(() {});
  }

  void _recu(String id, List<int> v) {
    _paquets++;
    final menaces = lireMenacesV1(v);
    final texte = menaces == null
        ? _hex(v)
        : '${_hex(v)}  →  ${menaces.isEmpty ? 'aucun véhicule' : menaces.join(', ')}';
    _dernier = '$id : $texte';
    // Les battements de cœur (1 octet, 7 par seconde) noient le journal :
    // on n'en garde qu'un sur 50.
    if (v.length > 1 || _paquets % 50 == 0) _noter('[$id] $texte');
    if (mounted) setState(() {});
  }

  Future<void> _deconnecter() async {
    for (final s in _abonnements) {
      await s.cancel();
    }
    _abonnements.clear();
    try {
      await _appareil?.disconnect();
    } catch (_) {}
    _connecte = false;
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _deconnecter();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liste = _trouves.values.toList()
      ..sort((a, b) {
        final pa = _probable(a) ? 0 : 1;
        final pb = _probable(b) ? 0 : 1;
        return pa != pb ? pa - pb : b.rssi.compareTo(a.rssi);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Test radar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Allume le radar, ferme l’appli Magene, puis cherche. Touche le '
            'radar dans la liste : l’écran affiche ce qu’il envoie. Ensuite '
            'copie le rapport et envoie-le moi.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Attention : l’écoute peut laisser le radar en mode simple '
            'jusqu’à ce que tu l’éteignes puis le rallumes.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _recherche ? null : _chercher,
            icon: const Icon(Icons.bluetooth_searching_rounded),
            label: Text(_recherche ? 'Recherche…' : 'Chercher les appareils'),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, style: const TextStyle(color: Couleurs.cuivre)),
          ],
          const SizedBox(height: 12),
          if (_appareil == null)
            for (final r in liste.take(30))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _probable(r) ? Icons.radar_rounded : Icons.bluetooth_rounded,
                  color: _probable(r) ? Couleurs.or : null,
                ),
                title: Text(_nom(r)),
                subtitle: Text('${r.device.remoteId.str}  ·  ${r.rssi} dBm'),
                onTap: () => _connecter(r),
              )
          else ...[
            Carte(
              lueur: _famille ? Couleurs.or : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _connecte
                        ? (_famille
                              ? 'Connecté : service Garmin 6a4e3200 trouvé'
                              : 'Connecté : pas de service 6a4e3200')
                        : 'Connexion…',
                    style: Polices.titreStyle(16, poids: 600),
                  ),
                  const SizedBox(height: 6),
                  Text('Paquets reçus : $_paquets'),
                  if (_dernier.isNotEmpty) Text('Dernier : $_dernier'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: _rapport.join('\n')),
                    ),
                    child: const Text('Copier le rapport'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await _deconnecter();
                      setState(() => _appareil = null);
                    },
                    child: const Text('Autre appareil'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              _rapport.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
