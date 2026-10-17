# Peloton Desk

Une app sur le Peloton Bike pour travailler sur son Mac en pédalant : bureau
tactile, résistance, cadence, vitesse estimée, durée et dictée locale.

Le compagnon **Peloton Desk Mac** se trouve dans la barre des menus (icône de vélo).
L’app Android utilise le partage d’écran intégré au Mac, avec noVNC embarqué.
Moonlight, Sunshine, Grupetto et VoiceInk ne sont pas nécessaires à ce parcours.

## Usage quotidien

Sur le Mac, cliquer **Icône vélo → Ouvrir le bureau sur le Bike**. Le compagnon rétablit
le tunnel, retrouve le Bike appairé si son adresse Wi-Fi a changé, et affiche
le bureau. Une connexion déjà active est conservée ; sinon le mot de passe VNC
est demandé sur le Bike. Aucun Terminal n’est nécessaire.

Cocher **Icône vélo → Démarrer avec le Mac** pour retrouver ce menu après ouverture de
session macOS. Cette option est désactivée tant que vous ne la cochez pas.
Le Bike doit être allumé, sur le même réseau, avec Wireless debugging actif.
Si le Bike est éteint au démarrage du Mac, le compagnon reste disponible : utiliser
le bouton après avoir allumé le vélo.

## Premier lancement

1. Garder le Bike connecté par ADB sans fil et ouvrir **Peloton Desk Mac**.
2. Sur le Mac, activer **Réglages Système → Général → Partage → Partage d’écran**,
   puis l’accès VNC avec un mot de passe dédié, choisi directement dans macOS.
3. Sur le Bike, toucher **Afficher mon bureau** et saisir ce mot de passe.
4. Pour la dictée : menu **Icône vélo → Autorisations de dictée…**, puis autoriser le micro
   et l’accessibilité pour **Peloton Desk Mac**.
5. Depuis le Bike, sélectionner un champ texte, activer **Dictée**, puis parler.

Les pauses terminent chaque phrase. L’insertion automatique vérifie que le champ
sélectionné n’a pas changé ; sinon la transcription reste disponible dans `···`.
L’envoi du texte reste manuel. Le micro utilisé est l’entrée audio du **Mac** :
brancher le micro placé près du vélo au Mac, pas à la tablette Peloton.

## État vérifié le 16 octobre 2026

- APK compilé, signé et installé sur un Bike PLTN-RB1VQ, Android 11 / API 30.
- Compagnon installé dans `/Applications/Peloton Desk Mac.app` et serveur actif.
- Icône vélo dans la barre des menus ; démarrage avec le Mac activé et confirmé par macOS.
- Sunshine retiré du Mac et Moonlight désinstallé du Bike.
- Interface affichée sur le Bike et bureau Mac en miroir, confirmés par l’utilisateur.
- Lecture réelle des capteurs : cadence 0, résistance 34 au premier échantillon.
- Modèle Whisper `base` multilingue vérifié par SHA-256 et testé sur un audio public.
- Tests des outils, du tunnel, des protections HTTP, du chronomètre et de la segmentation réussis.

**À valider en usage réel :** précision du toucher, métriques pendant le pédalage,
micro, insertion dans les applications d’IA et comportement lors des déconnexions.
La vitesse est estimée depuis la puissance, pas mesurée indépendamment.

## Développement

Prérequis : macOS avec Swift et les outils Xcode, Node/npm, Python 3.10+, ADB,
Java et Android Platform 35 / Build Tools 35.0.1. Le SDK Android requiert l’acceptation
de la licence Google. Les dépendances et artefacts locaux restent hors de Git.

```sh
npm ci
uv venv
uv pip install -r requirements.txt
make app-build
adb devices -l
make app-install SERIAL=IDENTIFIANT_DU_BIKE
make app-test
make app-doctor
```

Le SDK est attendu dans `.local/android-sdk`, ou à l’emplacement `ANDROID_SDK_ROOT`.
Le compagnon installé référence ce dépôt et son environnement `.venv` : ne pas
déplacer le dépôt après installation sans reconstruire le bundle Mac.

Pour choisir un autre modèle ou binaire Whisper, créer `.local/voice.json` :

```json
{"whisper":"/opt/homebrew/bin/whisper-cli","model":"/chemin/vers/ggml-base.bin"}
```

Consulter [la configuration](docs/setup.md), [les essais matériels](docs/validation.md)
et [les dépendances tierces](THIRD_PARTY.md).
Les anciens lanceurs `tools/desk.py` et [le guide Sunshine/Moonlight](docs/legacy-streaming.md)
restent disponibles pour référence.

## Limites du prototype

Le transport dépend de la connexion ADB appairée. Le compagnon HTTP écoute
uniquement sur `127.0.0.1:8765` ; le partage d’écran macOS est un service séparé,
accessible sur le réseau selon les réglages du Mac. Le mot de passe VNC n’est pas
conservé par l’app. Garder le Mac éveillé et sa session ouverte.

La dictée utilise un seuil d’énergie sonore simple. Son comportement face au bruit
du pédalage reste à tester. Les phrases sont limitées à 20 secondes, avec au plus
deux transcriptions en cours ou en attente. Les extraits audio sont temporaires et
supprimés après traitement ou arrêt normal. La qualité et le focus doivent être
vérifiés avec le micro et les applications réellement utilisés.
