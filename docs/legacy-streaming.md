# Configuration

## 1. Identifier l’écran et préparer la liaison

Relever le modèle d’écran, la version Android et le numéro de build dans les réglages
du Bike. Activer le mode développeur selon le guide OpenPelo correspondant au logiciel
installé. ADB fonctionne en Wi-Fi ou en USB ; les outils du dépôt acceptent les deux.

### Wi-Fi avec code d’appairage

Si **Wireless debugging → Pair device with pairing code** est disponible, aucun
câble n’est nécessaire. Connecter le Mac et le Bike au même réseau Wi-Fi, ouvrir
cette fenêtre et la garder ouverte. Relever son adresse IP et son port d’appairage :

```sh
adb pair IP_DU_BIKE:PORT_APPAIRAGE
```

Saisir le code temporaire demandé dans le terminal. Après appairage, ADB peut se
connecter automatiquement. Sinon, revenir à l’écran principal **Wireless debugging**
et utiliser l’adresse et le port de connexion qui y sont affichés :

```sh
adb connect IP_DU_BIKE:PORT_CONNEXION
adb devices -l
```

Les ports d’appairage et de connexion sont généralement différents. Utiliser ensuite
l’identifiant exact affiché par `adb devices -l` dans `--serial`. Si l’adresse ou le
port change, reprendre ceux affichés sur le Bike. `adb mdns services` permet de
chercher les services annoncés sur le réseau ; une liste vide n’empêche pas de
tenter la connexion manuelle avec les coordonnées de l’écran.

Sources : [Android ADB sans fil](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi),
[appairage OpenPelo](https://github.com/doudar/Openpelo#connect-a-device).

### Si ADB échoue alors que le port répond

Sur ce Mac, `adb pair` renvoyait `protocol fault (couldn't read status message)`.
Le journal du serveur ADB indiquait `No route to host`, alors que `nc -vz IP PORT`
réussissait. L'échec se produisait avant la vérification du code. Un échec Python
ne suffisait donc pas à conclure que le Bike était inaccessible.

La relance du serveur depuis le Terminal du Mac, déjà autorisé à accéder au réseau
local, a permis l'appairage et la connexion automatique :

```sh
adb kill-server
adb start-server
```

Exécuter ces commandes dans ce Terminal, puis reprendre `adb pair` avec les
coordonnées affichées sur le Bike. `kill-server` interrompt les sessions ADB en cours.
Ne pas relancer ensuite le serveur depuis l'environnement qui échouait.
Ce comportement est compatible avec les problèmes d'autorisation réseau des
processus en arrière-plan [décrits par Apple](https://developer.apple.com/forums/thread/778457).

### USB

Si l’appairage sans fil n’est pas disponible, activer **USB debugging**, utiliser
un câble USB de données adapté au port de l’écran et accepter l’autorisation
affichée sur le Bike.

Le guide OpenPelo inclut une réinitialisation du firmware dans son parcours.
Le présent dépôt n’exécute aucune réinitialisation ; commencer par identifier le
matériel et tester l’accès ADB existant.

```sh
adb devices -l
python3 tools/desk.py doctor --serial IDENTIFIANT_DU_BIKE
```

Un appareil `unauthorized` attend la confirmation sur son écran. `offline` indique
une connexion à rétablir. Si plusieurs appareils sont présents, le diagnostic exige
un identifiant explicite. Les lanceurs du Bike l’exigent toujours.

Les versions de Moonlight et Grupetto consultées demandent Android API 21 minimum.
Cette condition ne suffit pas à garantir l’accès aux capteurs ni la fluidité vidéo.
Sources : [Moonlight](https://github.com/moonlight-stream/moonlight-android/blob/master/app/build.gradle),
[Grupetto](https://github.com/doudar/grupetto/blob/develop/app/build.gradle).

## 2. Configurer le Mac

Installer [Sunshine depuis ses versions officielles](https://github.com/LizardByte/Sunshine/releases),
avec le DMG Apple Silicon ou Intel adapté au Mac. Le dépôt attend `Sunshine.app`
dans `/Applications` ou `~/Applications`.

Ouvrir Sunshine et suivre son assistant. Accorder les autorisations demandées pour
la capture d’écran et le contrôle clavier/souris. L’interface locale de configuration
est normalement à `https://localhost:47990`. Configurer ses identifiants dans Sunshine.
Le lancement d’une application ne prouve pas que ses autorisations sont accordées.

Garder le Mac éveillé et sa session ouverte pendant le test. Pour le premier essai,
laisser un écran réel disponible et un MacBook ouvert. Connecter Mac et Bike au même
réseau local. L’entrée `Desktop` de Sunshine diffuse le bureau existant.

Source : [installation Sunshine](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html).

## 3. Installer les applications sur le Bike

Depuis [OpenPelo](https://github.com/doudar/Openpelo), installer un lanceur Android
compatible, Moonlight et Grupetto. Ces applications figurent dans son catalogue.
Le diagnostic vérifie les identifiants officiels `com.limelight` et `com.spop.poverlay` ;
un fork utilisant un autre identifiant ne sera pas reconnu.

Ouvrir Moonlight, sélectionner le Mac et terminer l’appairage par PIN dans Sunshine.
Lancer l’entrée `Desktop`.

Dans les réglages Moonlight, désactiver **Use the touchscreen as a trackpad** :
le doigt désigne alors directement l’endroit où cliquer. Le réglage et les gestes
sont documentés dans le [guide Moonlight](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide).

Point de départ proposé, à ajuster au matériel : flux 1080p, H.264 et 60 images/s,
avec un bureau au même format et des textes agrandis. Vérifier surtout la netteté
des caractères et la précision des clics. Ce profil est une hypothèse de départ,
pas un résultat mesuré sur ce Bike.

## 4. Mettre les métriques au-dessus du bureau

Ouvrir Grupetto, autoriser l’affichage par-dessus les autres applications, puis
vérifier que les valeurs changent réellement en pédalant. Le mode démonstration
doit être désactivé. Démarrer le chronomètre dans la vue étendue, puis réduire et
placer l’overlay à un endroit qui laisse les champs de travail accessibles.
Activer l’option d’affichage du chronomètre dans la vue réduite.

Le Bike original conserve son réglage de résistance à la molette. Grupetto expose
les mesures ; le lanceur de ce dépôt ne commande pas la résistance.
La disposition exacte vitesse/résistance/durée reste à valider dans la version installée.

Source : [fonctionnement de Grupetto](https://github.com/doudar/grupetto#usage).

## 5. Garder la dictée existante

Connecter le micro, ou son récepteur, au Mac. Le poser près du vélo et sélectionner
ce micro dans le logiciel de dictée. VoiceInk a été détecté sur le Mac lors de
l’initialisation ; le choix reste modifiable dans les commandes du dépôt.

Configurer et tester un déclencheur **début/fin d’enregistrement** dans le logiciel
choisi. VoiceInk documente des raccourcis clavier et souris configurables. L’ouverture
de VoiceInk par `make host` ne déclenche pas la dictée.

Pour le premier essai, utiliser un raccourci sur un clavier connecté au Mac. Puis
tester un déclencheur accessible depuis le vélo : bouton Bluetooth configuré comme
raccourci, raccourci transmis par Moonlight, ou commande tactile si le logiciel la
propose. Le comportement de ces options n’est pas encore validé ici.

Il faut sélectionner le **champ de texte**, pas seulement la fenêtre, avant le
déclenchement. Vérifier qu’après transcription le texte est inséré dans ce même
champ. L’envoi du prompt reste une action distincte.

Si un bouton sur le Bike devient nécessaire, il devra envoyer la commande au Mac
sans ouvrir une fenêtre qui vole le focus. Ne pas implémenter ce pont avant d’avoir
vérifié le mécanisme de déclenchement réel de l’application installée.

Source : [VoiceInk](https://github.com/Beingpax/VoiceInk).
