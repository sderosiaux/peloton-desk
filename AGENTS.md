# Peloton Desk

- Objectif confirmé : une seule app Android, bureau Mac tactile, métriques intégrées,
  dictée locale contrôlable sans raccourci clavier maintenu.
- Architecture actuelle : WebView Android + noVNC, partage d’écran macOS, passerelle
  aiohttp sur loopback via ADB reverse, compagnon Swift et moteurs locaux whisper.cpp / Parakeet V3 via FluidAudio.
- Les anciens scripts Sunshine/Moonlight sont conservés comme parcours historique.
- Exécuter `make app-test` et le diagnostic pertinent après modification. Recompiler
  avant installation ; ne pas modifier Swift pendant sa compilation.
- Toute ouverture ou installation Android exige un identifiant ADB explicite.
- Conserver appareils, jetons, modèles, captures et journaux dans `.local/`, ignoré.
  Ne jamais afficher les jetons ni les inclure dans les exceptions ou journaux.
- Ne pas enregistrer de micro ni injecter du texte pour un test sans déclenchement
  explicite de l’utilisateur. Vérifier le focus avant insertion. Entrée automatique
  uniquement si l’utilisateur a activé ce mode pour la session ; ce comportement
  a été demandé explicitement pour les prompts d’IA.
- Documenter séparément ce qui passe en test et ce qui a été vérifié sur matériel.
- Sur ce Mac, préserver le serveur ADB démarré depuis le Terminal autorisé au réseau local.

- Conserver l’identité de signature `.local/signing/` entre les builds Mac ; ne jamais
  revenir silencieusement à une signature ad hoc ou publier les clés.
- Parakeet se compile avec `make asr-build`. Le worker reste hors ligne en dictée ;
  ne télécharger des modèles que pendant la préparation explicite.
- Les aperçus sont provisoires. Coller uniquement un résultat final, avec contrôle
  du focus. Terminer transcrit aussi la dernière phrase ; Annuler/déconnexion abandonnent le traitement restant.
