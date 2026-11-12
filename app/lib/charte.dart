// Charte graphique, reprise de GOATout (dépôt New-strava, v0.39) pour que
// les deux applis de Cyril se ressemblent : noir chaud, or et cuivre,
// texte crème ; titres en Space Grotesk, chiffres en Barlow Condensed.
import 'package:flutter/material.dart';

abstract final class Couleurs {
  static const fond = Color(0xFF0F0E0D);
  static const surface = Color(0xFF1C1A17);
  static const surface2 = Color(0xFF27241F);
  static const ligne = Color(0xFF3A342C);
  static const texte = Color(0xFFF4EFE6);
  static const texte2 = Color(0xFFCFC8BA);
  static const texte3 = Color(0xFF978E7F);

  /// Or : l'accent (boutons, chiffres importants).
  static const or = Color(0xFFF0CF73);

  /// Or foncé : dégradés, traits.
  static const orFonce = Color(0xFFC99A34);

  /// Texte posé sur l'or.
  static const surOr = Color(0xFF1A1405);

  /// Cuivre : accroches, glucides.
  static const cuivre = Color(0xFFE9A178);

  static const bleu = Color(0xFF4D8EF7); // eau
  static const vert = Color(0xFF37C27B); // en avance, connecté
  static const rouge = Color(0xFFFF5C5C); // arrêter, en retard
  static const violet = Color(0xFFA995FF); // puissance (comme GOATout)
  static const cardio = Color(0xFFFF6B7A);
}

/// Zones de puissance de Coggan (en % de FTP), avec une couleur chacune.
class ZonePuissance {
  const ZonePuissance(this.numero, this.nom, this.couleur);
  final int numero;
  final String nom;
  final Color couleur;
}

ZonePuissance zonePuissance(double puissanceW, double ftpW) {
  final pct = ftpW <= 0 ? 0 : 100 * puissanceW / ftpW;
  if (pct < 55) return const ZonePuissance(1, 'Récup', Color(0xFF8B93A1));
  if (pct < 75) return const ZonePuissance(2, 'Endurance', Couleurs.bleu);
  if (pct < 90) return const ZonePuissance(3, 'Tempo', Couleurs.vert);
  if (pct < 105) return const ZonePuissance(4, 'Seuil', Couleurs.or);
  if (pct < 120) return const ZonePuissance(5, 'VO2max', Couleurs.cuivre);
  return const ZonePuissance(6, 'Anaérobie', Couleurs.rouge);
}

abstract final class Polices {
  static const titre = 'Space Grotesk';
  static const chiffres = 'Barlow Condensed';

  /// Space Grotesk est une police « variable » : on règle l'épaisseur.
  static TextStyle titreStyle(
    double taille, {
    int poids = 700,
    Color? couleur,
  }) => TextStyle(
    fontFamily: titre,
    fontSize: taille,
    fontWeight: poids >= 600 ? FontWeight.w700 : FontWeight.w500,
    fontVariations: [FontVariation('wght', poids.toDouble())],
    color: couleur ?? Couleurs.texte,
    height: 1.1,
    letterSpacing: -0.2,
  );

  static TextStyle chiffresStyle(
    double taille, {
    FontWeight poids = FontWeight.w700,
    Color? couleur,
  }) => TextStyle(
    fontFamily: chiffres,
    fontSize: taille,
    fontWeight: poids,
    color: couleur ?? Couleurs.texte,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Ombre des cartes (comme GOATout en thème sombre).
const List<BoxShadow> ombreCarte = [
  BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x73000000), blurRadius: 26, offset: Offset(0, 12)),
];

/// Dégradé or des grands boutons.
const LinearGradient degradeOr = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF6DE97), Couleurs.or, Couleurs.orFonce],
);

ThemeData themeGoatout() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: null,
  );
  final schema = const ColorScheme.dark(
    primary: Couleurs.or,
    onPrimary: Couleurs.surOr,
    secondary: Couleurs.cuivre,
    onSecondary: Couleurs.surOr,
    surface: Couleurs.surface,
    onSurface: Couleurs.texte,
    surfaceContainerHighest: Couleurs.surface2,
    outline: Couleurs.ligne,
    error: Couleurs.rouge,
  );
  return base.copyWith(
    colorScheme: schema,
    scaffoldBackgroundColor: Couleurs.fond,
    canvasColor: Couleurs.fond,
    dividerColor: Couleurs.ligne,
    dividerTheme: const DividerThemeData(color: Couleurs.ligne, thickness: 1),
    textTheme: base.textTheme.apply(
      bodyColor: Couleurs.texte,
      displayColor: Couleurs.texte,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Couleurs.fond,
      foregroundColor: Couleurs.texte,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Polices.titreStyle(22),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Couleurs.or,
        foregroundColor: Couleurs.surOr,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: Polices.titreStyle(17, couleur: Couleurs.surOr),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Couleurs.texte,
        side: const BorderSide(color: Couleurs.ligne),
        minimumSize: const Size(48, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: Couleurs.surface2,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Couleurs.or),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Couleurs.surface2,
      labelStyle: const TextStyle(color: Couleurs.texte2),
      suffixStyle: const TextStyle(color: Couleurs.texte3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Couleurs.ligne),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Couleurs.ligne),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Couleurs.or, width: 1.6),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Couleurs.surOr : Couleurs.texte3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Couleurs.or : Couleurs.surface2,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Couleurs.ligne),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Couleurs.or : Couleurs.texte3,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Couleurs.surface2,
      side: const BorderSide(color: Couleurs.ligne),
      labelStyle: Polices.chiffresStyle(17, poids: FontWeight.w600),
      shape: const StadiumBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Couleurs.or
              : Couleurs.surface2,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Couleurs.surOr
              : Couleurs.texte,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: Couleurs.ligne)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Couleurs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Couleurs.ligne),
      ),
      titleTextStyle: Polices.titreStyle(21),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Couleurs.surface2,
      contentTextStyle: const TextStyle(color: Couleurs.texte),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Couleurs.ligne),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Couleurs.or,
      textColor: Couleurs.texte,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}
