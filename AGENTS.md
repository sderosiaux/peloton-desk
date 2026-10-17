# Peloton Desk

- Objectif : bureau Mac tactile sur Peloton Bike, métriques locales en superposition,
  dictée avec l’application macOS déjà installée. VoiceInk est le défaut détecté.
- Réutiliser Sunshine, Moonlight, OpenPelo et Grupetto. Le code de ce dépôt orchestre
  ces outils. Documenter ce qui est vérifié sur matériel et ce qui reste une hypothèse.
- Les scripts Python utilisent la bibliothèque standard. Exécuter `make test` et
  le diagnostic pertinent après une modification des outils.
- Toute commande qui ouvre une application Android exige un identifiant ADB explicite.
- Conserver rapports locaux, identifiants d’appareils, captures et journaux dans `.local/`.
- Le prochain point à vérifier sur matériel est le trajet tactile → focus → déclencheur
  de dictée → insertion du texte. Aucun pont de dictée personnalisé n’est implémenté.
