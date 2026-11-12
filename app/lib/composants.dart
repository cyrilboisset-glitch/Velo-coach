// Éléments visuels communs aux écrans, dans la charte GOATout.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:velo_coach_moteur/velo_coach_moteur.dart';

import 'charte.dart';

/// Nom de l'appli en deux couleurs, comme « GOATout » (crème + or).
class Logo extends StatelessWidget {
  const Logo({super.key, this.taille = 34});
  final double taille;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: 'Vélo', style: Polices.titreStyle(taille)),
        TextSpan(
          text: 'Coach',
          style: Polices.titreStyle(taille, couleur: Couleurs.or),
        ),
      ],
    ),
    semanticsLabel: 'Vélo Coach',
  );
}

/// Phrase d'accroche en cuivre (Space Grotesk 500), comme GOATout.
class Accroche extends StatelessWidget {
  const Accroche(this.texte, {super.key});
  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: Polices.titreStyle(15, poids: 500, couleur: Couleurs.cuivre),
  );
}

/// Carte sombre avec ombre ; [lueur] l'entoure d'un liseré coloré.
class Carte extends StatelessWidget {
  const Carte({
    super.key,
    required this.child,
    this.lueur,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final Color? lueur;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = lueur;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF221F1B), Couleurs.surface],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: l == null ? Couleurs.ligne : l.withValues(alpha: 0.75),
          width: l == null ? 1 : 1.4,
        ),
        boxShadow: [
          ...ombreCarte,
          if (l != null)
            BoxShadow(color: l.withValues(alpha: 0.18), blurRadius: 22),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Petit titre de section en majuscules espacées.
class Rubrique extends StatelessWidget {
  const Rubrique(this.texte, {super.key, this.icone});
  final String texte;
  final IconData? icone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        if (icone != null) ...[
          Icon(icone, size: 18, color: Couleurs.or),
          const SizedBox(width: 8),
        ],
        Text(
          texte.toUpperCase(),
          style: Polices.titreStyle(
            13,
            poids: 600,
            couleur: Couleurs.texte3,
          ).copyWith(letterSpacing: 1.4),
        ),
      ],
    ),
  );
}

/// Pastille d'état : point coloré + texte. [vivante] : le point pulse.
class Pastille extends StatelessWidget {
  const Pastille(this.texte, this.couleur, {super.key, this.vivante = false});
  final String texte;
  final Color couleur;
  final bool vivante;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: couleur.withValues(alpha: 0.55)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        vivante
            ? PointVivant(couleur: couleur, taille: 8)
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: couleur,
                  shape: BoxShape.circle,
                ),
              ),
        const SizedBox(width: 6),
        Text(
          texte,
          style: TextStyle(
            color: couleur,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Point qui pulse (onde qui s'élargit), pour « en direct ». Immobile si
/// le téléphone demande moins d'animations.
class PointVivant extends StatefulWidget {
  const PointVivant({super.key, required this.couleur, this.taille = 10});
  final Color couleur;
  final double taille;

  @override
  State<PointVivant> createState() => _PointVivantState();
}

class _PointVivantState extends State<PointVivant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.taille;
    return SizedBox(
      width: t,
      height: t,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) =>
            CustomPaint(painter: _OndePeintre(widget.couleur, _c.value)),
      ),
    );
  }
}

class _OndePeintre extends CustomPainter {
  _OndePeintre(this.couleur, this.t);
  final Color couleur;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r * (1 + 1.6 * t),
      Paint()..color = couleur.withValues(alpha: 0.45 * (1 - t)),
    );
    canvas.drawCircle(c, r, Paint()..color = couleur);
  }

  @override
  bool shouldRepaint(_OndePeintre old) => old.t != t || old.couleur != couleur;
}

/// Anneau de progression (comme les objectifs de GOATout) : l'arc se
/// remplit en douceur quand la valeur change.
class Anneau extends StatelessWidget {
  const Anneau({
    super.key,
    required this.fraction,
    required this.couleur,
    required this.centre,
    required this.libelle,
    this.taille = 104,
  });

  /// 0 à 1.
  final double fraction;
  final Color couleur;
  final Widget centre;
  final String libelle;
  final double taille;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: taille,
        height: taille,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, f, enfant) => CustomPaint(
            painter: _AnneauPeintre(f, couleur),
            child: Center(child: enfant),
          ),
          child: centre,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        libelle,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Couleurs.texte2, fontSize: 13),
      ),
    ],
  );
}

class _AnneauPeintre extends CustomPainter {
  _AnneauPeintre(this.f, this.couleur);
  final double f;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    const epaisseur = 9.0;
    final rect = Offset.zero & size;
    final cercle = rect.deflate(epaisseur / 2 + 2);
    canvas.drawArc(
      cercle,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = epaisseur
        ..color = Couleurs.surface2,
    );
    if (f <= 0) return;
    // Lueur sous l'arc
    canvas.drawArc(
      cercle,
      -math.pi / 2,
      2 * math.pi * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = epaisseur + 6
        ..strokeCap = StrokeCap.round
        ..color = couleur.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(
      cercle,
      -math.pi / 2,
      2 * math.pi * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = epaisseur
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          transform: const GradientRotation(-math.pi / 2),
          colors: [couleur.withValues(alpha: 0.65), couleur],
        ).createShader(cercle),
    );
  }

  @override
  bool shouldRepaint(_AnneauPeintre old) =>
      old.f != f || old.couleur != couleur;
}

/// Profil du parcours (altitude selon la distance) : montées en or,
/// position actuelle en point lumineux.
class ProfilParcours extends StatelessWidget {
  const ProfilParcours({
    super.key,
    required this.parcours,
    this.positionM,
    this.hauteur = 92,
  });

  final Parcours parcours;
  final double? positionM;
  final double hauteur;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: hauteur,
    width: double.infinity,
    child: CustomPaint(painter: _ProfilPeintre(parcours, positionM)),
  );
}

class _ProfilPeintre extends CustomPainter {
  _ProfilPeintre(this.p, this.positionM);
  final Parcours p;
  final double? positionM;

  @override
  void paint(Canvas canvas, Size size) {
    final segs = p.segments;
    if (segs.isEmpty || size.width <= 0) return;
    final longueur = p.longueurM;
    // Une altitude par pixel (au plus), début de chaque colonne.
    final n = math.max(2, size.width.floor());
    final alts = List<double>.generate(n, (i) {
      final s = p.segmentA(longueur * i / (n - 1));
      final d = longueur * i / (n - 1) - s.debutM;
      return s.altitudeM + s.pente * d.clamp(0, s.longueurM);
    });
    var mini = alts.reduce(math.min);
    var maxi = alts.reduce(math.max);
    if (maxi - mini < 30) maxi = mini + 30;
    const haut = 6.0;
    final bas = size.height - 2;
    double x(double d) => size.width * d / longueur;
    double y(double a) => bas - (a - mini) / (maxi - mini) * (bas - haut);

    final contour = Path()..moveTo(0, y(alts.first));
    for (var i = 1; i < n; i++) {
      contour.lineTo(size.width * i / (n - 1), y(alts[i]));
    }
    final aire = Path.from(contour)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      aire,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Couleurs.or.withValues(alpha: 0.22),
            Couleurs.or.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      contour,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Couleurs.texte3,
    );
    // Montées : trait or épais par-dessus.
    for (final m in p.montees) {
      final debut = (m.debutM / longueur * (n - 1)).floor().clamp(0, n - 1);
      final fin = (m.finM / longueur * (n - 1)).ceil().clamp(0, n - 1);
      final chemin = Path()
        ..moveTo(size.width * debut / (n - 1), y(alts[debut]));
      for (var i = debut + 1; i <= fin; i++) {
        chemin.lineTo(size.width * i / (n - 1), y(alts[i]));
      }
      canvas.drawPath(
        chemin,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..color = Couleurs.or,
      );
    }
    // Position actuelle.
    final pos = positionM;
    if (pos != null && pos >= 0 && pos <= longueur) {
      final i = (pos / longueur * (n - 1)).round().clamp(0, n - 1);
      final px = x(pos);
      final py = y(alts[i]);
      canvas.drawLine(
        Offset(px, py),
        Offset(px, size.height),
        Paint()
          ..color = Couleurs.cuivre.withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(
        Offset(px, py),
        11,
        Paint()..color = Couleurs.cuivre.withValues(alpha: 0.25),
      );
      canvas.drawCircle(Offset(px, py), 5.5, Paint()..color = Couleurs.cuivre);
      canvas.drawCircle(
        Offset(px, py),
        5.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Couleurs.fond,
      );
    }
  }

  @override
  bool shouldRepaint(_ProfilPeintre old) =>
      old.p != p || old.positionM != positionM;
}

/// Grand bouton doré, avec un léger reflet.
class BoutonOr extends StatelessWidget {
  const BoutonOr({
    super.key,
    required this.texte,
    required this.onPressed,
    this.icone,
    this.hauteur = 70,
  });

  final String texte;
  final VoidCallback? onPressed;
  final IconData? icone;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final actif = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: actif ? 1 : 0.55,
      child: Container(
        height: hauteur,
        decoration: BoxDecoration(
          gradient: degradeOr,
          borderRadius: BorderRadius.circular(hauteur / 2),
          boxShadow: [
            BoxShadow(
              color: Couleurs.or.withValues(alpha: 0.35),
              blurRadius: 26,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(hauteur / 2),
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icone != null) ...[
                    Icon(icone, color: Couleurs.surOr, size: 30),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    texte,
                    style: Polices.titreStyle(21, couleur: Couleurs.surOr),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton qu'il faut maintenir appuyé (1,2 s) : se remplit de rouge, puis
/// déclenche [onValide]. Évite d'arrêter une sortie par erreur.
class BoutonMaintenir extends StatefulWidget {
  const BoutonMaintenir({
    super.key,
    required this.texte,
    required this.onValide,
  });

  final String texte;
  final VoidCallback onValide;

  @override
  State<BoutonMaintenir> createState() => _BoutonMaintenirState();
}

class _BoutonMaintenirState extends State<BoutonMaintenir>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          widget.onValide();
          _c.value = 0;
        }
      });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.texte,
    onTap: widget.onValide,
    child: GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          height: 60,
          decoration: BoxDecoration(
            color: Couleurs.surface2,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Couleurs.rouge.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: _c.value,
                child: Container(color: Couleurs.rouge.withValues(alpha: 0.85)),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stop_rounded, color: Couleurs.texte),
                    const SizedBox(width: 8),
                    Text(widget.texte, style: Polices.titreStyle(17)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Nombre qui « roule » quand il change (glissement vertical + fondu).
class ChiffreAnime extends StatelessWidget {
  const ChiffreAnime(this.texte, {super.key, required this.style});
  final String texte;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 260),
    transitionBuilder: (enfant, anim) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(anim),
        child: enfant,
      ),
    ),
    child: Text(texte, key: ValueKey(texte), style: style),
  );
}
