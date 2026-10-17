# Dépendances et références

- **noVNC 1.7.0**, MPL-2.0 : [source officielle](https://github.com/novnc/noVNC/tree/v1.7.0).
  Le module est importé sans modification et compilé avec esbuild. Les avis de
  licence de noVNC et de ses composants sont copiés dans `.local/web/licenses/`.
  Les sources correspondantes sont aussi disponibles dans `node_modules/@novnc/novnc`.
- **esbuild 0.28.2**, MIT : [source](https://github.com/evanw/esbuild).
- **aiohttp 3.14.5**, Apache-2.0 : [source](https://github.com/aio-libs/aiohttp).
- **whisper.cpp 1.9.5**, MIT : [source et modèles](https://github.com/ggml-org/whisper.cpp).
  Le binaire est installé séparément ; les poids `ggml-base.bin` proviennent du
  [dépôt de modèles](https://huggingface.co/ggerganov/whisper.cpp).
- **Android SDK** : outils Google soumis à leur
  [licence](https://developer.android.com/studio/terms), non redistribués dans Git.

Le client des capteurs est une implémentation Java du protocole Binder observé
dans les interfaces V1 décrites par [Grupetto](https://github.com/doudar/grupetto).
Aucun fichier source Grupetto n’est intégré au dépôt. La formule de vitesse
provient des mesures publiées dans
[Pelomon : computing speed](https://ihaque.org/posts/2020/12/25/pelomon-part-ib-computing-speed/).

Le partage d’écran utilise le service VNC fourni avec macOS.
