"""Complète le projet Android généré par `flutter create` (dans la CI).

Repris de Suivi direct, avec en plus :
- identifiant Android `fr.cyril.suivi_direct` (celui de Suivi direct) :
  Vélo Coach s'installe PAR-DESSUS Suivi direct et garde ses réglages,
  donc le même lien de suivi ;
- autorisations Bluetooth (capteurs de puissance et de cardio) ;
- « desugaring », exigé par flutter_local_notifications ;
- nom affiché « Vélo Coach ».
"""
from pathlib import Path
import re
import sys

APP = Path(__file__).resolve().parent.parent / 'android/app'
MANIFESTE = APP / 'src/main/AndroidManifest.xml'
GRADLE = APP / 'build.gradle.kts'

AUTORISATIONS = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_LOCATION',
    'android.permission.WAKE_LOCK',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.BLUETOOTH_SCAN',
    'android.permission.BLUETOOTH_CONNECT',
]
# Anciens Android (11 et avant) seulement
AUTORISATIONS_ANCIENNES = [
    'android.permission.BLUETOOTH',
    'android.permission.BLUETOOTH_ADMIN',
]


def remplacer(texte, motif, remplacement, quoi):
    nouveau, n = re.subn(motif, remplacement, texte, count=1)
    if n != 1:
        sys.exit(f'{quoi} introuvable')
    return nouveau


# ---- Manifeste ---------------------------------------------------------------
texte = MANIFESTE.read_text(encoding='utf-8')
ajout = ''.join(
    f'    <uses-permission android:name="{a}"/>\n'
    for a in AUTORISATIONS
    if f'android:name="{a}"' not in texte
) + ''.join(
    f'    <uses-permission android:name="{a}" android:maxSdkVersion="30"/>\n'
    for a in AUTORISATIONS_ANCIENNES
    if f'android:name="{a}"' not in texte
)
texte = remplacer(texte, r'(<manifest\b[^>]*>\s*\n)', lambda m: m.group(1) + ajout,
                  'Balise <manifest>')
texte = remplacer(texte, r'android:label="[^"]*"', 'android:label="Vélo Coach"',
                  'android:label')
MANIFESTE.write_text(texte, encoding='utf-8')

# ---- Gradle ------------------------------------------------------------------
g = GRADLE.read_text(encoding='utf-8')
g = remplacer(g, r'applicationId\s*=\s*"[^"]*"', 'applicationId = "fr.cyril.suivi_direct"',
              'applicationId')
if 'isCoreLibraryDesugaringEnabled' not in g:
    g = remplacer(g, r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true',
                  'compileOptions')
# Signature avec la clé fixe du dépôt (ci/debug.keystore). Sans ça,
# Gradle crée une clé de « debug » au hasard à chaque compilation sur
# GitHub, et Android refuse d'installer une version par-dessus l'autre.
if 'create("fixe")' not in g:
    g = remplacer(g, r'(\n\s*buildTypes\s*\{)', lambda m: '''
    signingConfigs {
        create("fixe") {
            storeFile = file("../../ci/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }''' + m.group(1), 'buildTypes')
    g = remplacer(g, r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                  'signingConfig = signingConfigs.getByName("fixe")', 'signingConfig release')
if 'desugar_jdk_libs' not in g:
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
GRADLE.write_text(g, encoding='utf-8')

print(texte)
print(g)
