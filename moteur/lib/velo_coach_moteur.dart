/// Moteur de calcul du coaching vélo : ravitaillement, hydratation,
/// réserve anaérobie (W'bal) et pacing en montée.
///
/// Dart pur, sans Flutter : testable sur n'importe quel ordinateur et
/// réutilisé tel quel par le mode simulation et par l'appli Android.
library;

export 'src/alertes.dart';
export 'src/calage.dart';
export 'src/coach.dart';
export 'src/config.dart';
export 'src/enregistrement.dart';
export 'src/gpx.dart';
export 'src/hydratation.dart'
    show Hydratation, ResultatCalibration, calibrerSudation;
export 'src/lissage.dart';
export 'src/messages.dart';
export 'src/pacing.dart';
export 'src/parcours.dart';
export 'src/physique.dart';
export 'src/rapport.dart';
export 'src/ravitaillement.dart';
export 'src/simulateur.dart';
export 'src/wbal.dart';
