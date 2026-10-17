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

Le menu vérifie les droits réels et devient **Dictée autorisée ✓**, grisé, lorsque
micro et accessibilité sont accordés. Cela n’active pas le micro : seule la commande
**Dictée** sur le Bike ou **Démarrer la dictée** dans la fenêtre Mac démarre l’écoute. Si un droit manque, le menu l’indique.

Le bureau utilise par défaut le mode **fluide**. Le Mac compare les pixels avec
l’image précédente et transmet seulement les zones modifiées. Les petites zones
restent sans perte ; les grandes images peuvent utiliser JPEG. Le défilement
réutilise les pixels déjà présents lorsque macOS envoie une commande CopyRect.
Pour conserver tous les pixels : **Image exacte** dans `···`, puis reconnecter.
En mode fluide, le client demande la prochaine image pendant la réception de
l’image courante, avec au plus une demande anticipée hors redimensionnement.
Les zones unies utilisent une couleur RGB et les petits rectangles sont regroupés
dans les messages réseau. Le client attend le rendu précédent avant de poursuivre.

La dictée montre un **aperçu provisoire pendant la parole**, rafraîchi environ
toutes les secondes avec Parakeet V3, toutes les deux secondes avec Whisper si le moteur suit.
Une pause de 900 ms termine la phrase. La destination est le champ actif à cette
pause : vous pouvez changer d’application sans arrêter l’écoute.
Les rires et interjections isolées connus (« ha ha », « euh », « okay ») sont
filtrés avant collage et envoi. Les commandes courtes, oui/non et les phrases
comme « OK, corrige ce bug » restent intactes. Ce filtre local n’analyse pas
l’intention générale d’une phrase. Sur le Bike, les notifications répétitives de
dictée sont supprimées ; l’aperçu et les erreurs utiles restent visibles.
Le texte final est collé avec ⌘V si la cible n’a pas changé pendant le traitement ; le
presse-papiers précédent est ensuite restauré, sauf si vous avez copié autre chose.
En mode collage seul, les éditeurs qui n’exposent pas un champ texte classique
utilisent le focus clavier de l’application active. Son identifiant de champ est comparé s’il est disponible ;
sinon, seul le maintien de l’application et de sa fenêtre peut être vérifié.
La transcription reste récupérable si le collage est annulé.

L’option **Envoyer avec Entrée après chaque phrase**, dans la fenêtre Mac ou les
réglages du Bike, colle puis appuie sur Entrée après une pause. Elle est désactivée
par défaut, sauf préférence locale explicite. Les phrases longues sont assemblées
avant ce collage unique ; la cible est revérifiée avant Entrée. Si aucun champ
éditable n’est confirmé, ou si la fenêtre de dictée est active, le texte reste dans
la fenêtre de dictée pour copie, sans envoi automatique.
Décocher cette option pour relire le prompt avant de l’envoyer.

Le menu **Icône vélo → Tester la dictée sur le Mac…** ouvre une fenêtre flottante
avec niveau du micro, aperçu, phrases reconnues et bouton Copier. Elle fonctionne
sans le Bike : démarrer, sélectionner son prompt, puis parler. **Terminer** garde
la dernière phrase ; **Annuler**, fermer la fenêtre ou perdre la connexion annule
le travail restant. Le micro est toujours celui du **Mac**.

## État vérifié le 17 octobre 2026

- APK compilé, signé et installé sur un Bike PLTN-RB1VQ, Android 11 / API 30.
- Compagnon installé dans `/Applications/Peloton Desk Mac.app` et serveur actif.
- Icône vélo dans la barre des menus ; démarrage avec le Mac activé et confirmé par macOS.
- Sunshine retiré du Mac et Moonlight désinstallé du Bike.
- Interface affichée sur le Bike et bureau Mac en miroir, confirmés par l’utilisateur.
- Lecture réelle des capteurs : cadence 0, résistance 34 au premier échantillon.
- Parakeet V3 sélectionné et testé hors ligne sur des fichiers français et anglais ;
  modèles existants du cache FluidAudio réutilisés. Whisper `base` reste disponible.
- Audio du micro Mac transcrit lors d’un essai manuel avec Whisper ; autorisations
  Microphone et Accessibilité reconnues après installation de Parakeet.
- Dictée Parakeet dans le champ actif de Codex : collage puis Entrée confirmés
  par l’utilisateur, avec l’option d’envoi automatique activée.
- Passage fenêtre de dictée → Codex sans arrêter l’écoute : première phrase
  conservée, seconde collée et envoyée, vérifié dans la même session.
- Dictée envoyée depuis le Bike pendant le pédalage, confirmée par réception des
  messages et journaux de collage/Entrée. Filtrage des interjections ajouté ensuite.
- Tests des outils, du tunnel, des protections HTTP, du chronomètre et de la segmentation réussis.
- Optimisation VNC vérifiée sur un flux réel de 3024 × 1964 : première image
  de 422 584 octets, puis mises à jour de 16 782, 3 776 et 4 octets lorsque
  peu de pixels changent. Ce n’est pas une mesure de latence tactile.

**À valider en usage réel :** précision du toucher, métriques pendant le pédalage,
insertion et qualité de Parakeet dans les applications d’IA, dernière optimisation
VNC sur le Bike et comportement lors des déconnexions.
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
make license-check
make app-doctor
```

Le SDK est attendu dans `.local/android-sdk`, ou à l’emplacement `ANDROID_SDK_ROOT`.
Le compagnon installé référence ce dépôt et son environnement `.venv` : ne pas
déplacer le dépôt après installation sans reconstruire le bundle Mac.

Pour choisir un autre modèle ou binaire Whisper, créer `.local/voice.json` :

```json
{"whisper":"/opt/homebrew/bin/whisper-cli","model":"/chemin/vers/ggml-base.bin"}
```

Pour le moteur **Parakeet V3** (Swift 6.2+), compiler `make asr-build`, puis suivre
[la configuration des modèles](docs/setup.md#modèles). Le compagnon reste indépendant
de VoiceInk. Whisper reste disponible comme moteur alternatif.

Les builds Mac utilisent une identité locale stable dans `.local/signing/`, ou
`PELOTON_DESK_SIGN_IDENTITY` si une identité existante est configurée. La clé privée
ne quitte pas le Mac et ne doit pas être publiée. Une première autorisation macOS
reste nécessaire lors du passage depuis l’ancienne signature ad hoc.

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
du pédalage reste à tester. L’audio est traité par segments d’au plus 20 secondes,
sans envoyer Entrée avant la pause, avec au plus
trois transcriptions finales en cours ou en attente. Une seule prévisualisation peut être en cours. Les extraits audio sont temporaires et
supprimés après traitement ou arrêt normal. Les vingt dernières transcriptions restent accessibles dix minutes en mémoire,
sans fichier d’historique. La qualité et le focus doivent être
vérifiés avec le micro et les applications réellement utilisés.
