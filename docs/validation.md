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
- [ ] Gain de latence et lisibilité du mode fluide confirmés en usage tactile sur le Bike.
- [ ] Reconnexion après veille et après interruption d’ADB.

## Dictée et focus

- [x] Autorisations Microphone et Accessibilité reconnues par le compagnon installé.
  Après recompilation, l’ancien bouton Accessibilité était activé mais l’API refusait
  l’app ; supprimer puis réajouter l’app installée a rétabli l’autorisation.
- [ ] Dictée dans un champ de test vide, avec le micro utilisé près du vélo.
- [ ] Paroles françaises et anglaises correctement transcrites pendant le pédalage.
- [ ] Changer de champ pendant une transcription empêche l’insertion automatique.
- [ ] Insertion manuelle de la dictée en attente dans le champ choisi.
- [ ] Arrêt de l’écoute et absence d’insertion après arrêt, sortie de l’app ou déconnexion.
- [ ] Essai dans les applications d’IA réellement utilisées ; aucun envoi automatique.

## Métriques et session

- [ ] Cadence, résistance et vitesse estimée évoluent en pédalant et en tournant la molette.
- [ ] Durée : démarrage, pause, reprise et remise à zéro.
- [ ] Les métriques continuent pendant le bureau distant et la dictée.
- [ ] La barre laisse accessibles les zones de travail utiles.

Le critère final est une session de travail réelle : lire, changer de fenêtre,
dicter un prompt et l’envoyer en pédalant, avec les métriques visibles.
