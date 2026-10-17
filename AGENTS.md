# Peloton Desk

- Objectif confirmé : une seule app Android, bureau Mac tactile, métriques intégrées,
  dictée locale contrôlable sans raccourci clavier maintenu.
- Architecture actuelle : WebView Android + noVNC, partage d’écran macOS, passerelle
  aiohttp sur loopback via ADB reverse, compagnon Swift et whisper.cpp local.
- Les anciens scripts Sunshine/Moonlight sont conservés comme parcours historique.
- Exécuter `make app-test` et le diagnostic pertinent après modification. Recompiler
  avant installation ; ne pas modifier Swift pendant sa compilation.
- Toute ouverture ou installation Android exige un identifiant ADB explicite.
- Conserver appareils, jetons, modèles, captures et journaux dans `.local/`, ignoré.
  Ne jamais afficher les jetons ni les inclure dans les exceptions ou journaux.
- Ne pas enregistrer de micro ni injecter du texte pour un test sans déclenchement
  explicite de l’utilisateur. Vérifier le focus avant insertion et ne pas envoyer le texte.
- Documenter séparément ce qui passe en test et ce qui a été vérifié sur matériel.
- Sur ce Mac, préserver le serveur ADB démarré depuis le Terminal autorisé au réseau local.
