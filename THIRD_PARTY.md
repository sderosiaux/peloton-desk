# Dépendances, licences et références

## Audit du 17 octobre 2026

Le contrôle couvre le verrou npm (28 entrées, dont 27 outils esbuild), les 10
paquets Python installés, la révision Swift verrouillée, les notices du code
embarqué et des bibliothèques natives, ainsi que les poids Parakeet utilisés.
Aucune dépendance imposant GPL/AGPL n’a été identifiée dans ce périmètre.
**noVNC est toutefois sous MPL-2.0** ; les poids **Parakeet sont sous CC-BY-4.0**.

`make license-check` compare les versions et licences aux
[métadonnées examinées](docs/license-inventory.json). Il échoue en cas de changement
ou de licence inconnue. Ce contrôle ne remplace pas l’examen du code embarqué,
des options de compilation ou de nouveaux modèles. `--write` sert à enregistrer
un nouvel inventaire après cet examen, pas à approuver automatiquement une mise à jour.

L’audit porte sur cette installation macOS arm64 et les sources verrouillées,
pas sur tous les binaires possibles d’autres plateformes. Les outils propriétaires
Apple/Google et leurs SDK restent installés séparément. Les poids, clés et artefacts
de compilation ne sont pas publiés dans Git. Le dépôt n’a pas encore de licence
pour son propre code : sa visibilité publique ne constitue pas une licence OSS.

## JavaScript

- **noVNC 1.7.0 — MPL-2.0** : [source officielle](https://github.com/novnc/noVNC/tree/v1.7.0),
  importée sans modification et compilée avec esbuild. La MPL applique le copyleft
  aux fichiers couverts ; elle ne force pas les fichiers séparés de l’application
  à adopter la MPL. Le JavaScript minifié est une forme exécutable : fournir les
  sources correspondantes et indiquer où les obtenir reste nécessaire lors d’une
  redistribution ([FAQ Mozilla, Q11 et Q16](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)).
  Le build ajoute cette indication dans `app.js`, conserve les notices dans
  `.local/web/licenses/` et fournit les sources non modifiées dans
  `.local/web/sources/noVNC-1.7.0.tar.gz`. Ces fichiers accompagnent le bundle web.
- Composants inclus par noVNC : **pako — MIT/zlib**, et code DES avec avis permissifs
  de Widget Workshop, AT&T et Jef Poskanzer. Le commentaire DES complet est conservé
  séparément, même si le minificateur le retire. Les polices Orbitron (OFL-1.1),
  images (CC-BY-SA-3.0) et pages de démonstration de noVNC ne sont pas utilisées.
- **esbuild 0.28.2 — MIT** : [source](https://github.com/evanw/esbuild).
  Dépendance de compilation, avec 26 paquets de plateforme optionnels dans le verrou.

## Python et bibliothèques natives

| Paquet installé | Version | Licence |
| --- | --- | --- |
| aiohttp | 3.14.5 | Apache-2.0 AND MIT |
| aiohappyeyeballs | 2.7.1 | PSF-2.0 |
| aiosignal | 1.4.0 | Apache-2.0 |
| attrs | 26.1.0 | MIT |
| frozenlist | 1.8.0 | Apache-2.0 |
| idna | 3.20 | BSD-3-Clause |
| multidict | 7.1.0 | Apache-2.0 |
| Pillow | 13.0.0 | MIT-CMU |
| propcache | 0.5.4 | Apache-2.0 |
| yarl | 1.25.1 | Apache-2.0 |

Les métadonnées et fichiers de licence des distributions installées ont été lus.
[aiohttp](https://github.com/aio-libs/aiohttp) fournit la passerelle ;
[Pillow](https://github.com/python-pillow/Pillow) convertit les pixels VNC en mémoire.
La licence de Pillow 13 est MIT-CMU, et non l’ancien libellé HPND.

La roue Pillow embarque aussi des bibliothèques d’image/compression/polices :
libavif, Brotli, FreeType, HarfBuzz, libjpeg, Little CMS, liblzma, OpenJPEG, libpng,
libtiff, libwebp/libsharpyuv, libXau, libxcb et zlib-ng. Le fichier
`pillow-13.0.0.dist-info/licenses/LICENSE` contient leurs avis, ainsi que ceux de
composants statiques ou d’autres configurations. Il doit accompagner toute copie
redistribuée de la roue et de ses bibliothèques.

FreeType offre **FTL OU GPL-2.0** : nous retenons la licence permissive FTL et son
obligation d’attribution ([conditions FreeType](https://freetype.org/license.html)).
Ce logiciel utilise FreeType, © The FreeType Project (www.freetype.org) ; tous
droits réservés. Les mentions GPL/LGPL des outils et scripts XZ ne rendent pas
`liblzma` GPL : la notice de cette roue identifie la bibliothèque comme domaine
public. Aucun `libfribidi` n’est embarqué dans cette roue examinée.

## Moteurs natifs et modèles

- **FluidAudio 0.17.7 — Apache-2.0** :
  [source](https://github.com/FluidInference/FluidAudio/tree/v0.17.7), révision
  `503b4bd1bbf7220882de39fe8ae6716aae4132da` ;
  [licence](licenses/FluidAudio-Apache-2.0.txt).
  Le worker utilise l’ASR Core ML. Le wrapper **fastcluster — BSD-2-Clause** a son
  [avis propre](licenses/fastcluster-BSD-2-Clause.txt).
  `make asr-build` copie aussi la licence et les `ThirdPartyLicenses` amont dans
  `.local/bin/licenses/FluidAudio/`, à conserver avec le worker et ses ressources.
- Le trait **NemoTextProcessing est désactivé** (`traits: []`). SwiftPM peut en
  télécharger l’archive, mais les symboles de normalisation ne sont pas présents
  dans le worker examiné. Aucun lien vers eSpeak n’a été trouvé. Les notices TTS
  de FluidAudio ont également été lues : Apache/MIT, BSD pour fastcluster et
  option BSD de la triple licence BSD/GPL/LGPL du dictionnaire UniDic. La dictée
  ne lance pas les moteurs TTS. Les notices amont sont conservées sans les tronquer.
- **Parakeet TDT 0.6B V3 — CC-BY-4.0** : poids créés par **NVIDIA**
  ([modèle original](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)), convertis
  au format Core ML par **FluidInference**
  ([conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)).
  Peloton Desk ne modifie pas les poids. Leur redistribution doit conserver cette
  attribution, le lien [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/)
  et l’indication des conversions/modifications. La fiche de conversion présente
  une incohérence entre son en-tête CC-BY-4.0 et son pied de page Apache-2.0 :
  nous retenons la licence CC-BY-4.0 du modèle NVIDIA, distincte de celle du moteur.
- **whisper.cpp 1.9.5 — MIT** :
  [source](https://github.com/ggml-org/whisper.cpp), licence du paquet Homebrew
  installé vérifiée. Le binaire est installé séparément ; le modèle de repli
  `ggml-base.bin` provient du [dépôt de modèles](https://huggingface.co/ggerganov/whisper.cpp).
  Les moteurs de transcription restent hors ligne pendant la dictée.

## Références et outils externes

- **OpenWhispr — MIT** : la résolution du raccourci de collage selon la disposition
  clavier s’inspire de son [helper macOS](https://github.com/OpenWhispr/openwhispr/blob/main/resources/macos-fast-paste.swift).
  [Avis de licence](licenses/OpenWhispr-MIT.txt).
- **VoiceInk — GPL-3.0** : [référence de comportement](https://github.com/Beingpax/VoiceInk)
  pour le presse-papiers et l’aperçu. Aucun code VoiceInk n’est copié ou lié ;
  lire un cache de modèles existant ne lie pas son application à Peloton Desk.
- Le client des capteurs est une implémentation Java du protocole Binder observé
  dans les interfaces V1 décrites par [Grupetto](https://github.com/doudar/grupetto).
  Aucun fichier source Grupetto n’est intégré. La formule de vitesse vient des
  mesures publiées dans [Pelomon](https://ihaque.org/posts/2020/12/25/pelomon-part-ib-computing-speed/).
- Le partage d’écran utilise le service VNC de macOS. Sunshine/Moonlight ne font
  plus partie du parcours actif ; les anciens scripts restent des références historiques.
- **Android SDK** : outils Google soumis à leur
  [licence](https://developer.android.com/studio/terms), non redistribués dans Git.
