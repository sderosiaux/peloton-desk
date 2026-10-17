# Configuration de l’app unique

## Connexion du Bike

Le Bike et le Mac doivent conserver leur connexion ADB appairée. Vérifier avec
`adb devices -l`, puis utiliser exactement cet identifiant pour l’installation.
Le [guide de connexion ADB](legacy-streaming.md#1-identifier-lécran-et-préparer-la-liaison)
décrit l’appairage Wi-Fi et le problème de permissions réseau rencontré sur ce Mac.
Un câble n’est pas nécessaire lorsque l’appairage sans fil fonctionne.

Ouvrir **Peloton Desk Mac** dans Applications. Le menu **Icône vélo → Ouvrir le bureau
sur le Bike** rétablit le tunnel ADB et ouvre l’app en demandant directement la
connexion au bureau. Si une session existe encore, elle est conservée. Le compagnon
reste ouvert même si le Bike est éteint. Un nouvel essai se fait depuis ce menu.

Le lanceur peut retrouver une annonce ADB TLS du même Bike après changement
d’adresse. Il vérifie son numéro matériel avant d’ouvrir l’app ; il ne choisit pas
un autre appareil disponible et ne bascule pas sur l’ancien port ADB sans TLS.

L’option **Icône vélo → Démarrer avec le Mac** ajoute ou retire le compagnon des éléments
d’ouverture de session macOS. Elle reste décochée par défaut. Si macOS demande
une confirmation, la terminer dans Ouverture et extensions.

Pour une installation automatisée, le bundle installé accepte `--enable-login`
et `--login-status`. Ces commandes utilisent ServiceManagement et n’ouvrent pas
le micro ni le bureau. L’état `Login item enabled` confirme l’inscription ; une
demande d’approbation reste à terminer dans les réglages macOS.

Garder le dépôt à son emplacement d’installation : le bundle utilise `.venv`
et les fichiers compilés. Le même lanceur est disponible en ligne de commande :
`python3 tools/app.py open --serial IDENTIFIANT_DU_BIKE`.

## Bureau et toucher

Sur le Mac : **Réglages Système → Général → Partage → Partage d’écran → ⓘ**.
Activer le partage et l’option permettant aux visualiseurs VNC de contrôler l’écran
avec un mot de passe. Choisir ce mot de passe directement dans macOS.
Voir [les instructions Apple](https://support.apple.com/en-by/guide/mac-help/mh11848/mac).

Sur le Bike : **Afficher mon bureau**, puis saisir le mot de passe VNC.
Il reste en mémoire pendant la connexion et n’est pas enregistré par Peloton Desk.
Le bureau est mis à l’échelle pour l’écran ; vérifier la précision du toucher et
la lisibilité avant de commencer une session de travail.

Le mode **Bureau fluide** conserve l’image source en mémoire et compare chaque
mise à jour. Les pixels inchangés ne traversent pas le Wi-Fi. Les changements
éloignés sont séparés par tuiles de 128 pixels, puis regroupés pour réduire le
nombre de dessins. Les petites zones de texte utilisent PNG ou des pixels bruts ;
les grandes images choisissent PNG ou JPEG qualité 70, couleurs 4:4:4.
Les CopyRect de macOS sont conservés et mettent aussi à jour le cache. Un
rafraîchissement complet demandé par le client invalide ce cache ; un changement
de taille le recrée. Les coordonnées et la résolution ne changent pas.
Le contenu reste en mémoire, sans enregistrer les images. Pour revenir au flux
d’origine : `··· → Image exacte → Reconnecter le bureau`.

Si VNC montre seulement le fond d’écran ou un écran de connexion distinct avec
un clavier US, demander à macOS de rejoindre la session physique. Dans un Terminal :

```sh
sudo defaults write /Library/Preferences/com.apple.RemoteManagement VNCAlwaysStartOnConsole -bool true
```

Redémarrer le partage d’écran en le désactivant puis en le réactivant dans macOS,
puis `··· → Reconnecter le bureau` sur le Bike. Le miroir de la session physique
a été confirmé sur le Mac testé après cette opération.
Pour revenir au défaut : `sudo defaults delete /Library/Preferences/com.apple.RemoteManagement VNCAlwaysStartOnConsole`.
Référence : [signalement TigerVNC](https://github.com/TigerVNC/tigervnc/issues/826).
Le client sélectionne explicitement VNCAuth, car le Mac propose d’abord ARD,
qui demande les identifiants du compte macOS et non le mot de passe VNC.

Le partage d’écran macOS écoute aussi sur le réseau local. Le tunnel ADB transporte
notre connexion ; il ne restreint pas les autres accès autorisés par les réglages macOS.
Le compagnon HTTP, lui, n’écoute que sur la boucle locale.

## Dictée locale

Le micro doit être connecté au Mac et sélectionné comme entrée audio dans macOS.
Le bouton **Icône vélo → Autorisations de dictée…** prépare les autorisations Microphone
et Accessibilité pour **Peloton Desk Mac**. L’accessibilité permet d’identifier le
champ sélectionné et d’y insérer la transcription.

Le menu se met à jour à son ouverture et toutes les cinq secondes. **Dictée autorisée ✓**
est grisé quand les deux droits sont reconnus par l’app ; cela signifie que la dictée
est disponible, pas que le micro écoute. Les réglages du Bike affichent le même état.
Les builds utilisent maintenant une identité de signature stable, conservée dans
un trousseau privé sous `.local/signing/`. Ce trousseau entre temporairement dans
la liste de recherche pendant la signature, puis la liste précédente est restaurée
et le trousseau verrouillé. Aucun certificat n’est ajouté aux autorités de confiance.
Il est aussi possible de définir `PELOTON_DESK_SIGN_IDENTITY`.

Lors du passage depuis les anciennes versions signées ad hoc, retirer l’ancienne
entrée Accessibilité avec **−**, puis ajouter avec **+**
`/Applications/Peloton Desk Mac.app`. Les builds suivants conservent cette identité.
La demande de micro passe par le compagnon qui affiche son état, à l’activation
explicite de l’écoute.

Le bouton **Dictée** du Bike active l’écoute jusqu’à son arrêt. L’aperçu provisoire
est calculé environ toutes les secondes avec Parakeet, toutes les deux secondes avec Whisper ; un aperçu encore en cours n’est pas
empilé dans une file d’attente. Une pause de 900 ms termine une phrase. En cas de
parole continue, le moteur traite des segments de 20 secondes. Avec l’envoi
automatique, leurs textes sont assemblés : un seul collage puis Entrée à la pause
ou au bouton Terminer. En mode collage seul, les segments terminés sont collés
au fur et à mesure. Le texte provisoire peut changer.

Un filtre local retire les phrases composées uniquement d’interjections connues
ou de rires (« ha ha », « okay », « euh »), avant tout collage ou Entrée. Une
phrase contenant aussi d’autres mots, une commande courte, oui/non ou un nombre
est conservé. Il ne décide pas si une phrase est une commande pertinente.
Les événements ignorés n’alimentent ni l’historique ni la dictée en attente.
Le Bike conserve l’aperçu provisoire sans les notifications répétitives de parole,
traitement ou collage réussi en haut de l’écran.

La destination est choisie à la fin de la phrase, pas au début de l’écoute : on peut
changer d’application entre deux phrases sans redémarrer. Les activations sont
suivies sur la boucle principale macOS, puis le champ actif est relu à chaque contrôle.
Le collage final vérifie l’application, la fenêtre et l’identifiant du champ (s’il existe) avant
⌘V, avec la disposition de clavier active. Un éditeur web ou terminal peut ne pas
exposer un champ texte classique : en mode collage seul, ⌘V est dirigé vers son
focus système. Avec l’envoi automatique, l’absence de champ éditable confirmé
conserve le texte dans la fenêtre de dictée, sans collage ni Entrée.
Sans identifiant de champ stable, seule l’application et sa fenêtre (si disponible)
peuvent être comparées ; un déplacement de curseur au sein du même éditeur n’est
pas détecté. Les contrôles non textuels reconnus, champs sécurisés et l’app de dictée
elle-même sont exclus.

**Envoyer avec Entrée après chaque phrase** ajoute Entrée 700 ms après le collage,
après un nouveau contrôle du focus et de l’annulation. Cette option est choisie
avant de démarrer l’écoute, dans la fenêtre Mac ou les réglages du Bike.
Elle est désactivée par défaut ; `"sendReturn":true` dans `.local/voice.json` fournit
une préférence initiale explicite, que la case permet de changer.
La transmission d’un raccourci ne prouve pas
que l’application destinataire a effectivement accepté le collage : le texte reste
visible dans la fenêtre Mac. Si la cible est exclue ou a changé, l’audio est tout
de même transcrit et le texte conservé pour copie. Depuis le Bike, utiliser aussi
`··· → Insérer la dictée en attente` après avoir sélectionné le champ voulu.

**Icône vélo → Tester la dictée sur le Mac…** ouvre un panneau flottant avec le
micro utilisé, son niveau, les étapes du traitement, l’aperçu et les résultats.
Démarrer, sélectionner son prompt, puis parler. Le Bike n’est pas nécessaire.
**Terminer la dictée** arrête le micro et termine les phrases capturées ; **Annuler**,
fermer le panneau ou perdre sa connexion annule le traitement restant. Une coupure
brutale du réseau peut retarder la détection par le WebSocket.

### Modèles

**Whisper** utilise `whisper.cpp` et un modèle multilingue, par défaut `base` :

```json
{"engine":"whisper","whisper":"/opt/homebrew/bin/whisper-cli","model":"/chemin/vers/ggml-base.bin"}
```

**Parakeet V3** utilise FluidAudio, chargé une fois par session d’écoute. Compiler
le moteur séparé avec `make asr-build`, puis préparer un dossier de modèles :

```sh
.local/bin/PelotonDeskASR --prepare /chemin/vers/modeles/parakeet-tdt-0.6b-v3
```

Un dossier V3 déjà présent dans le cache FluidAudio de VoiceInk peut aussi être
utilisé directement. Le mode de transcription du moteur interdit les téléchargements ;
seule la commande explicite `--prepare` peut récupérer les poids. Configuration
`.local/voice.json` :

```json
{"engine":"parakeet","worker":"/chemin/du/depot/.local/bin/PelotonDeskASR","model":"/chemin/vers/modeles/parakeet-tdt-0.6b-v3"}
```

Ces fichiers et chemins personnels restent hors de Git. Les deux moteurs restent
locaux et ne dépendent pas de VoiceInk pour fonctionner.

## Capteurs et durée

La barre lit le service local `AffernetService` du Bike V1, sans modifier la résistance.
Les données vieilles de plus de cinq secondes sont remplacées par des tirets.
La vitesse est une approximation calculée à partir de la puissance.

Le bouton ▶ démarre la durée ; Ⅱ la met en pause. Le compteur reprend sa valeur
après réouverture. Le premier échantillon de cadence positive démarre aussi le
chronomètre automatiquement. Une pause manuelle reste respectée, même en pédalant
ou après réouverture ; ▶ permet de reprendre. S’arrêter de pédaler ne met pas
automatiquement la séance en pause. `···` remet le compteur à zéro et réarme le
démarrage au pédalage. Le temps pédalé avant l’ouverture de l’app n’est pas reconstruit.
La barre affiche aussi la puissance instantanée en watts fournie par le Bike.

Au démarrage du compagnon, une réponse HTTP non JSON, tronquée ou une coupure
réseau affiche un état d’attente et relance l’initialisation. Les erreurs de syntaxe
JSON internes ne sont plus affichées sur l’écran du Bike. Les refus d’authentification
restent explicites et ne déclenchent pas une boucle infinie de réessais.

## Diagnostic

```sh
make app-doctor
make app-test
```

Les journaux du compagnon restent dans `.local/companion.log`. Ils indiquent les
étapes, les durées, le nombre de caractères, la présence d’une cible et le motif
d’un refus de collage (`deliveryReason`), sans
texte dicté ni audio. Les vingt dernières phrases restent en mémoire dix minutes ;
la fenêtre Mac les affiche, et l’API authentifiée `/api/voice/history` permet le
diagnostic. Les fichiers audio temporaires sont supprimés après traitement ou arrêt
normal. Un arrêt brutal du système peut laisser un répertoire temporaire à nettoyer. Les jetons et le
numéro d’appareil ne doivent pas être copiés dans un rapport public.
Si le Bike affiche la page d’attente, vérifier ADB puis rouvrir le compagnon Mac.
Si le bouton bureau reste absent, vérifier le partage d’écran et son port local 5900.

Les sources restent dans `android/`, `web/`, `macos/` et `tools/`. Après modification :
`make app-build`, puis `make app-install SERIAL=IDENTIFIANT_DU_BIKE`.
Quitter le compagnon avant de remplacer son bundle. Après une nouvelle signature
de développement, macOS peut demander à nouveau certaines autorisations.
