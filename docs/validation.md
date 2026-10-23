# Validation sur le matériel

Les tests automatisés ne prouvent pas que le bureau et la dictée fonctionnent ensemble.
Conserver les résultats personnels dans `.local/validation.md`.

## Résultats acquis

- [x] Compilation et vérification de la signature APK.
- [x] Installation Android et Mac, démarrage du compagnon sur loopback.
- [x] Interface Peloton Desk visible sur le Bike, confirmée par l’utilisateur.
- [x] Inscription au service de capteurs et premier échantillon réel reçu.
- [x] Inférence Whisper sur un audio public, sans utiliser le micro.
- [x] Tests des outils, tunnel binaire, origine/authentification HTTP, chronomètre et segmentation.
- [x] Raccourci de lancement installé : la commande utilisée par le menu vélo ouvre le Bike réel.
- [x] Tests de reconnexion TLS, identité du Bike, erreur Android et absence de fuite du jeton.
- [x] Icône vélo installée ; inscription au démarrage confirmée par ServiceManagement (`Login item enabled`).
- [ ] Clic manuel sur le menu vélo et ouverture automatique à la prochaine session Mac.

## Bureau et tactile

### Ultra focus RPM — 19 octobre 2026

- [x] `make app-test` : 74 tests Python/JavaScript et auto-tests Swift réussis.
  Le moteur musical reconnaît les impulsions générées à 90/120/168 BPM,
  reste utilisable à faible volume et retire la confiance après silence ;
  un son continu ne crée pas de tempo. Aucun micro ni son joué pour ces tests.
- [x] Tests du flux musical : authentification et origine, une seule capture
  partagée, arrêt au dernier départ, reprise après échec, file de sortie bornée.
- [x] Tests du rendu : signal périmé/invalide, absence de repère en cas de doute,
  adaptation à l’énergie et aux basses à tempo identique, suspension/reprise
  des demandes d’images du bureau fluide.
- [x] Interface intégrée vérifiée dans Chrome, avec signaux fictifs, en plein écran
  et à 560 px : entrée/sortie Focus, cadence centrale, chiffres de la barre sombre,
  contrôles dans une seule rangée et retour des commandes du bureau.
- [x] Compagnon Mac compilé et installé en conservant l’identité de signature.
  Dictée inactive vérifiée avant redémarrage ; droits existants toujours reconnus.
- [x] Capture réelle de Spotify sur ce Mac : des centaines de mesures reçues
  à environ 20 Hz, énergie/basses/attaques variables et tempo estimé disponible.
  Test de la version finale après calibration des faibles volumes. Aucun fichier
  audio conservé ; seuls les résumés numériques sont dans `.local/`.
- [x] Diagnostic matériel : six vérifications réussies, interface Bike rechargée
  avec identifiant ADB explicite, serveur ADB conservé. Mesures de la barre fraîches
  après rechargement (âge observé inférieur à 200 ms).
- [x] Correction des textes instables : `make app-test` (79 tests Python/JavaScript
  et auto-tests Swift) et compilation web réussis. Tests temporels des creux audio,
  variations de confiance, scores d’ambiance concurrents, tempo double/moitié,
  changement soutenu de tempo, silence, perte du flux et choix de subdivision.
  Les ambiances exigent 3 s de confirmation et restent affichées au moins 8 s ;
  le tempo affiché change au maximum toutes les 5 s. Les creux brefs sont tolérés,
  les pulsations restent sur le chemin audio rapide.
- [x] Version corrigée servie par le Mac : contenu HTML/JS identique au build.
  Diagnostic suivant la correction : cinq vérifications réussies, Bike hors ligne ;
  aucun redémarrage du serveur ADB ni de la dictée.
- [ ] Stabilité des textes confirmée sur le Bike après rechargement de l’interface.
- [ ] Fluidité du paysage et confort visuel confirmés sur le Bike en pédalant.
- [ ] Alignement perceptif des pulsations avec le son entendu, notamment sur la
  sortie audio utilisée ; stabilité du tempo sur différents morceaux et breaks.
- [ ] Retour au bureau après une longue immersion et changement de sortie audio
  ou redémarrage de Spotify confirmés en usage réel.

Le tempo est une estimation locale : les subdivisions et les rythmes complexes
peuvent donner un tempo double ou moitié. Le repère RPM disparaît quand la confiance
ou la présence du rythme restent insuffisantes pendant plus de deux secondes ;
une perte du flux retire immédiatement le repère. Il ne mesure pas la phase du pédalage.

### Bureau et métriques intégrées

- [x] 18 octobre : `make app-test` (67 tests Python/JS et auto-test Swift),
  compilation web et `make app-doctor` réussis après ajout des boutons d’onglets
  et des courbes en fond des indicateurs.
- [x] Aperçu Chrome avec données fictives : chiffres lisibles, dimensions des
  indicateurs identiques avec/sans courbes, boutons de 64 px, rendu compact à
  560 px. Navigation simulée, masquage des boutons, déconnexion et remise à zéro
  vérifiés ; aucune touche envoyée à Ghostty et aucun micro utilisé pour ces tests.
- [x] Tests d’historique : fenêtre de 15 minutes, stockage borné, restauration,
  valeurs nulles/zéro, interruption des mesures et correction de l’horloge.
- [x] Correction du 18 octobre : courbes limitées à vitesse/résistance/cadence,
  puissance retirée de la barre, durée et kcal numériques. Compilation web,
  `make app-test` et diagnostic réussis ; interface servie contrôlée et app Bike
  relancée avec son identifiant explicite. Rendu matériel de cette correction
  encore à confirmer.
- [x] Flèches d’onglets intégrées à droite dans la barre et dictée réduite à son
  icône : compilation web et `make app-test` réussis. Aperçu Chrome vérifié en
  plein écran, 900 et 560 px ; une seule rangée, hauteur de 84 px sur grand écran,
  sans boutons en dehors de la barre. États de dictée et raccourcis simulés,
  sans micro ni saisie réelle. Confort sur le Bike encore à confirmer.
- [ ] Navigation réelle entre onglets Ghostty et confort des boutons sur le Bike.
- [ ] Évolution des courbes en pédalant pendant plusieurs minutes sur le Bike.
- [x] Authentification VNC : acceptée après correction du choix VNCAuth/ARD.
- [x] Miroir de la session physique confirmé après réglage console et redémarrage du partage.
- [ ] Toucher précis dans les quatre coins, changement de fenêtre, sélection d’un champ.
- [ ] Défilement et déplacement d’une fenêtre, texte lisible en pédalant.
- [x] Mode fluide : négociation VNC réelle et décodage de deux images complètes
  de 3024 × 1964 ; environ 511 puis 503 ko transmis après conversion côté Mac.
- [x] Tests de flux fragmenté, authentification refusée, curseur, couleurs,
  continuité zlib et bornes de taille ; retour au mode exact conservé.
- [x] Premier gain de fluidité signalé par l’utilisateur ; encore insuffisant pour son usage.
- [x] Optimisation par différences : flux réel 3024 × 1964, première image 422 584 octets,
  mises à jour incrémentales 16 782, 3 776 et 4 octets ; rafraîchissement complet
  explicite 427 060 octets. Mesures côté Mac, sans mesure de latence tactile.
- [x] Tests : zones éloignées, texte sans perte, images identiques, CopyRect avec
  chevauchement, pixels inconnus, redimensionnement et demandes de rafraîchissement.
- [ ] Fluidité et lisibilité de cette dernière optimisation confirmées sur le Bike.
- [x] Mesures avant anticipation : mises à jour locales 17–26 ms ; aller-retour
  ADB médian 54 ms, transfert Mac → Bike environ 14 Mbit/s sur le réseau conservé.
  Mesures de transport, pas de latence visuelle après toucher.
- [x] Tests d’anticipation d’une demande d’image : fragments, attente du rendu,
  réponse vide sans blocage, redimensionnement et autres messages VNC.
- [x] Zones unies transmises sans perte en 16 octets par rectangle via Tight Fill ;
  tests des couleurs, de la continuité zlib et du flux avec curseur. Paquet généré
  par Python également décodé par le véritable décodeur noVNC 1.7.0, avec entrée fragmentée.
- [ ] Gain de fluidité de l’anticipation confirmé sur le Bike après mise à jour.
- [ ] Reconnexion après veille et après interruption d’ADB.

## Dictée et focus

- [x] Autorisations Microphone et Accessibilité reconnues par le compagnon installé.
  Après recompilation, l’ancien bouton Accessibilité était activé mais l’API refusait
  l’app ; supprimer puis réajouter l’app installée a rétabli l’autorisation.
- [x] Audio du micro Mac réellement transcrit dans la fenêtre de test, après
  déclenchement manuel de l’utilisateur ; premier essai sans insertion (AX refusé).
- [x] Identité de signature stable vérifiée sur plusieurs compilations ; autorisation
  Accessibilité renouvelée par l’utilisateur et reconnue par l’app.
- [x] Transcription d’un fichier public sans cible : texte conservé, aucun événement clavier.
- [x] Parakeet V3 chargé hors ligne depuis les modèles FluidAudio existants ; fichiers
  français synthétiques et anglais publics transcrits en 50–81 ms une fois chargé.
  Première préparation Core ML : 17,1 s ; test natif complet à chaud : 380 ms.
  Une erreur de vocabulaire observée sur l’échantillon français : ces mesures ne
  prouvent pas la qualité sur la voix de l’utilisateur.
- [x] Bundle Parakeet installé avec la même identité de signature ; fenêtre Mac
  affichant le modèle, autorisations Microphone et Accessibilité reconnues,
  inscription au démarrage toujours active.
- [x] Tests : arrêt avec fin de phrase, annulation pendant la demande de permission,
  conservation temporaire du texte et absence de transcript dans les journaux.
- [ ] Dictée insérée dans un champ de test vide, après renouvellement de l’autorisation.
- [x] Essai manuel Parakeet sur le micro Mac : plusieurs phrases transcrites en
  70–94 ms ; aucun collage car l’ancienne détection rejetait la cible.
- [x] Nouvelle détection du focus système : réponse dictée dans le champ actif de
  Codex, collée puis envoyée avec Entrée. Réception et envoi confirmés par
  l’utilisateur le 17 octobre 2026 ; journal `inserted:true`, `enterPosted:true`,
  aucun motif de refus, traitement final de 906 ms incluant l’attente du collage.
  Le premier essai avait reconnu la cible mais refusé le collage ; la comparaison
  d’identité des objets AX a été remplacée par leur identifiant stable.
- [x] Tests sans clavier réel : collage avant Entrée, absence d’Entrée sans option
  explicite, après échec de collage, annulation ou changement de focus ; une phrase
  continue de plus de 20 secondes reste ouverte jusqu’à une pause.
- [x] Option Entrée : envoi dans Codex confirmé par l’utilisateur (app inaccessible
  à l’outil de contrôle ; le test a été déclenché par l’utilisateur).
- [x] Changement d’application pendant la même écoute : phrase dans la fenêtre
  de dictée conservée avec `companion_focused`, puis phrase dans Codex collée et
  envoyée (`targetMode:field`, `inserted:true`, `enterPosted:true`, 909 ms).
  Réponse reçue le 17 octobre 2026 après correction du suivi des activations sur
  la boucle principale macOS ; aucun redémarrage de l’écoute entre les phrases.
- [x] Assemblage des segments longs avant collage/envoi : tests sans saisie réelle,
  y compris une fin de phrase exactement à la limite d’un segment de 20 secondes.
- [ ] Aperçu Parakeet pendant une phrase longue et qualité sur le micro réel.
- [x] Messages dictés depuis le Bike pendant le pédalage reçus dans Codex ; quatre
  collages suivis d’Entrée dans les journaux (839–913 ms pour le traitement final).
- [x] Tests sans micro : rires et interjections isolées filtrés ; commandes courtes,
  réponses oui/non, nombres et phrases contenant « OK » conservés. Événements
  ignorés exclus de l’historique et de la dictée en attente.
- [ ] Filtre des interjections et absence de notifications répétitives confirmés sur le Bike.
- [ ] Paroles françaises et anglaises correctement transcrites pendant le pédalage.
- [ ] Changer de champ pendant une transcription empêche l’insertion automatique.
- [ ] Insertion manuelle de la dictée en attente dans le champ choisi.
- [ ] Terminer finit la dernière phrase ; Annuler, fermeture et déconnexion arrêtent
  l’écoute sans nouvelle insertion. Validation matérielle encore nécessaire.
- [ ] Essai dans les autres applications d’IA utilisées, avec et sans l’option Entrée.

## Métriques et session

- [ ] Cadence, résistance et vitesse estimée évoluent en pédalant et en tournant la molette.
- [ ] Durée : démarrage, pause, reprise et remise à zéro.
- [x] Tests : démarrage au pédalage, absence de double démarrage et respect d’une pause manuelle.
- [ ] Durée démarrant au pédalage confirmée sur le Bike.
- [ ] Les métriques continuent pendant le bureau distant et la dictée.
- [ ] La barre laisse accessibles les zones de travail utiles.

Le critère final est une session de travail réelle : lire, changer de fenêtre,
dicter un prompt et l’envoyer en pédalant, avec les métriques visibles.

## Démarrage

- [x] Tests des réponses HTML, JSON tronqué, coupure réseau puis reprise et refus
  d’authentification. Aucun détail brut du serveur n’est exposé dans l’erreur affichée.
- [ ] Démarrage à froid sur le Bike sans message « Unexpected token » confirmé.
