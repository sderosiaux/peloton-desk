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
- [ ] Paroles françaises et anglaises correctement transcrites pendant le pédalage.
- [ ] Changer de champ pendant une transcription empêche l’insertion automatique.
- [ ] Insertion manuelle de la dictée en attente dans le champ choisi.
- [ ] Terminer finit la dernière phrase ; Annuler, fermeture et déconnexion arrêtent
  l’écoute sans nouvelle insertion. Validation matérielle encore nécessaire.
- [ ] Essai dans les autres applications d’IA utilisées, avec et sans l’option Entrée.

## Métriques et session

- [ ] Cadence, résistance et vitesse estimée évoluent en pédalant et en tournant la molette.
- [ ] Durée : démarrage, pause, reprise et remise à zéro.
- [ ] Les métriques continuent pendant le bureau distant et la dictée.
- [ ] La barre laisse accessibles les zones de travail utiles.

Le critère final est une session de travail réelle : lire, changer de fenêtre,
dicter un prompt et l’envoyer en pédalant, avec les métriques visibles.
