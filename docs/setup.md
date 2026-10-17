# Configuration de l’app unique

## Connexion du Bike

Le Bike et le Mac doivent conserver leur connexion ADB appairée. Vérifier avec
`adb devices -l`, puis utiliser exactement cet identifiant pour l’installation.
Le [guide de connexion ADB](legacy-streaming.md#1-identifier-lécran-et-préparer-la-liaison)
décrit l’appairage Wi-Fi et le problème de permissions réseau rencontré sur ce Mac.
Un câble n’est pas nécessaire lorsque l’appairage sans fil fonctionne.

Ouvrir **Peloton Desk Mac** dans Applications. Le menu **PD → Ouvrir le bureau
sur le Bike** rétablit le tunnel ADB et ouvre l’app en demandant directement la
connexion au bureau. Si une session existe encore, elle est conservée. Le compagnon
reste ouvert même si le Bike est éteint. Un nouvel essai se fait depuis ce menu.

Le lanceur peut retrouver une annonce ADB TLS du même Bike après changement
d’adresse. Il vérifie son numéro matériel avant d’ouvrir l’app ; il ne choisit pas
un autre appareil disponible et ne bascule pas sur l’ancien port ADB sans TLS.

L’option **PD → Démarrer avec le Mac** ajoute ou retire le compagnon des éléments
d’ouverture de session macOS. Elle reste décochée par défaut. Si macOS demande
une confirmation, la terminer dans Ouverture et extensions.

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
Le bouton **PD → Autorisations de dictée…** prépare les autorisations Microphone
et Accessibilité pour **Peloton Desk Mac**. L’accessibilité permet d’identifier le
champ sélectionné et d’y insérer la transcription.

Le bouton **Dictée** du Bike active l’écoute jusqu’à son arrêt. Une pause d’environ
900 ms termine une phrase. Le modèle `base` multilingue est exécuté par whisper.cpp.
Changer le moteur ou le modèle via `.local/voice.json` ; aucun service cloud n’est utilisé.

Sélectionner d’abord un champ texte depuis le Bike. Si le focus change pendant la
transcription, l’insertion automatique est refusée. Sélectionner le champ voulu,
puis `··· → Insérer la dictée en attente`. Cette insertion manuelle va au champ
actuellement sélectionné ; l’application n’appuie jamais sur Entrée.

Tester d’abord avec un texte sans importance dans un champ vide. Les éditeurs
qui n’exposent pas un champ texte via l’accessibilité peuvent ne pas fonctionner.
Le bouton Dictée, la mise en arrière-plan de l’app et la fermeture de la connexion
arrêtent l’écoute ; en cas de perte brutale du réseau, le délai de détection du
WebSocket peut retarder cet arrêt.

## Capteurs et durée

La barre lit le service local `AffernetService` du Bike V1, sans modifier la résistance.
Les données vieilles de plus de cinq secondes sont remplacées par des tirets.
La vitesse est une approximation calculée à partir de la puissance.

Le bouton ▶ démarre la durée ; Ⅱ la met en pause. Le compteur reprend sa valeur
après réouverture, en restant en pause. `···` permet de le remettre à zéro.

## Diagnostic

```sh
make app-doctor
make app-test
```

Les journaux du compagnon restent dans `.local/companion.log`. Les jetons et le
numéro d’appareil ne doivent pas être copiés dans un rapport public.
Si le Bike affiche la page d’attente, vérifier ADB puis rouvrir le compagnon Mac.
Si le bouton bureau reste absent, vérifier le partage d’écran et son port local 5900.

Les sources restent dans `android/`, `web/`, `macos/` et `tools/`. Après modification :
`make app-build`, puis `make app-install SERIAL=IDENTIFIANT_DU_BIKE`.
Quitter le compagnon avant de remplacer son bundle. Après une nouvelle signature
de développement, macOS peut demander à nouveau certaines autorisations.
