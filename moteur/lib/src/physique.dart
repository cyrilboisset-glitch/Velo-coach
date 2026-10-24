import 'dart:math' as math;

import 'config.dart';
import 'parcours.dart';

/// Accélération de la pesanteur (m/s²).
const double gravite = 9.80665;

/// Météo du moment (Open-Meteo, interrogée toutes les 10 min).
class Meteo {
  const Meteo({
    required this.temperatureC,
    required this.humiditePct,
    this.ventMs = 0,
    this.ventVientDeDeg = 0,
  });

  final double temperatureC;
  final double humiditePct;

  /// Vent moyen à 10 m de haut (m/s). Open-Meteo donne des km/h par
  /// défaut : diviser par 3,6.
  final double ventMs;

  /// Direction d'où vient le vent, en degrés (0 = nord, 90 = est),
  /// convention météo.
  final double ventVientDeDeg;
}

/// Densité de l'air (kg/m³) selon l'altitude et la température.
/// Pression de l'atmosphère standard, loi des gaz parfaits (air sec).
double densiteAir({required double altitudeM, required double temperatureC}) {
  final pression =
      101325 * math.pow(1 - 2.25577e-5 * altitudeM, 5.25588).toDouble();
  return pression / (287.05 * (temperatureC + 273.15));
}

/// Composante du vent de face (m/s) pour un cycliste qui roule au cap
/// [capDeg]. Positive = vent de face, négative = vent de dos.
double ventDeFace({
  required double ventMs,
  required double ventVientDeDeg,
  required double capDeg,
}) => ventMs * math.cos((ventVientDeDeg - capDeg) * math.pi / 180);

/// Tout ce qu'il faut au modèle physique, sauf le terrain.
class ConditionsRoulage {
  const ConditionsRoulage({
    required this.masseKg,
    required this.cda,
    required this.crr,
    required this.rendementTransmission,
    this.ventMs = 0,
    this.ventVientDeDeg = 0,
    this.temperatureC = 15,
    required this.vitesseMinMs,
    required this.vitesseMaxMs,
  });

  /// Conditions tirées de la configuration et de la météo. Le vent est
  /// ramené à la hauteur du cycliste.
  factory ConditionsRoulage.depuis(Config cfg, Meteo meteo) =>
      ConditionsRoulage(
        masseKg: cfg.cycliste.masseTotaleKg,
        cda: cfg.physique.cda,
        crr: cfg.physique.crr,
        rendementTransmission: cfg.physique.rendementTransmission,
        ventMs: meteo.ventMs * cfg.physique.facteurVentHauteur,
        ventVientDeDeg: meteo.ventVientDeDeg,
        temperatureC: meteo.temperatureC,
        vitesseMinMs: cfg.physique.vitesseMinKmh / 3.6,
        vitesseMaxMs: cfg.physique.vitesseMaxKmh / 3.6,
      );

  final double masseKg;
  final double cda;
  final double crr;
  final double rendementTransmission;

  /// Vent au niveau du cycliste (m/s).
  final double ventMs;
  final double ventVientDeDeg;
  final double temperatureC;
  final double vitesseMinMs;
  final double vitesseMaxMs;
}

/// Forces sur un segment, calculées une fois pour toutes les vitesses.
class _Forces {
  _Forces(Segment s, ConditionsRoulage c)
    : gravRoul =
          c.masseKg *
          gravite *
          (c.crr * math.cos(math.atan(s.pente)) + math.sin(math.atan(s.pente))),
      demiRhoCda =
          0.5 *
          densiteAir(altitudeM: s.altitudeM, temperatureC: c.temperatureC) *
          c.cda,
      vent = s.capDeg == null
          ? 0
          : ventDeFace(
              ventMs: c.ventMs,
              ventVientDeDeg: c.ventVientDeDeg,
              capDeg: s.capDeg!,
            ),
      rendement = c.rendementTransmission;

  /// Gravité + roulement (N).
  final double gravRoul;
  final double demiRhoCda;

  /// Vent de face (m/s).
  final double vent;
  final double rendement;

  /// Puissance aux pédales (W) pour rouler à [v] m/s.
  double puissance(double v) {
    final vAir = v + vent;
    return (gravRoul + demiRhoCda * vAir * vAir.abs()) * v / rendement;
  }
}

/// Puissance aux pédales (W) nécessaire pour rouler à [vitesseMs] sur le
/// segment [s].
double puissancePourVitesse(double vitesseMs, Segment s, ConditionsRoulage c) =>
    _Forces(s, c).puissance(vitesseMs);

/// Vitesse (m/s) obtenue en tenant [puissanceW] sur le segment [s].
/// Bornée par la vitesse minimale et la vitesse maximale (freinage).
double vitessePourPuissance(double puissanceW, Segment s, ConditionsRoulage c) {
  final f = _Forces(s, c);
  var bas = c.vitesseMinMs;
  var haut = c.vitesseMaxMs;
  if (f.puissance(haut) <= puissanceW) return haut;
  if (f.puissance(bas) >= puissanceW) return bas;
  for (var i = 0; i < 40; i++) {
    final milieu = 0.5 * (bas + haut);
    if (f.puissance(milieu) < puissanceW) {
      bas = milieu;
    } else {
      haut = milieu;
    }
  }
  return 0.5 * (bas + haut);
}

/// Temps (s) pour parcourir [segments] en tenant [puissanceW]. Le calcul
/// s'arrête dès que [limiteS] est dépassé (le résultat est alors
/// supérieur ou égal à [limiteS]).
double dureeSegments(
  Iterable<Segment> segments,
  double puissanceW,
  ConditionsRoulage c, {
  double limiteS = double.infinity,
}) {
  var t = 0.0;
  for (final s in segments) {
    t += s.longueurM / vitessePourPuissance(puissanceW, s, c);
    if (t >= limiteS) return t;
  }
  return t;
}
