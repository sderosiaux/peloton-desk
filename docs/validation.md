# Validation sur le matériel

Les tests Python valident les outils. Cette liste valide l’usage réel.
Conserver le résultat et les versions installées dans `.local/validation.md`.

## Bureau et tactile

- [ ] Le bureau du Mac s’affiche dans Moonlight, avec du texte lisible à distance de pédalage.
- [ ] Toucher un élément dans chaque coin clique au bon endroit, sans décalage.
- [ ] Passer entre deux fenêtres, sélectionner un champ, faire défiler et déplacer une fenêtre.
- [ ] Revenir au bureau après une mise en veille du Bike et après un redémarrage.

## Dictée et focus

- [ ] Le logiciel installé fonctionne d’abord directement dans Notes sur le Mac.
- [ ] Sélectionner le champ Notes depuis le Bike ; déclencher, parler et arrêter la dictée.
- [ ] Le texte arrive dans le champ sélectionné et le déclencheur ne change pas son focus.
- [ ] Reproduire le test dans les applications d’IA utilisées au quotidien.
- [ ] Alterner deux champs et vérifier que chaque transcription arrive dans le bon champ.
- [ ] Déclencher et arrêter l’enregistrement depuis la position de pédalage.
- [ ] La dictée comprend les termes techniques et le mélange français/anglais utilisés.

## Métriques

- [ ] Grupetto utilise les capteurs réels ; aucun mode de simulation n’est actif.
- [ ] Vitesse et résistance évoluent pendant le pédalage et l’ajustement de la molette.
- [ ] La durée démarre, se met en pause et se réinitialise correctement.
- [ ] Le chronomètre reste visible dans l’affichage réduit.
- [ ] Les mesures continuent à évoluer pendant le streaming et la dictée.
- [ ] L’overlay laisse accessibles les commandes importantes du bureau.

## Critère de réussite

Effectuer une session de travail représentative : lire une réponse, changer de
fenêtre au toucher, dicter un nouveau prompt et l’envoyer tout en pédalant, sans
perdre les métriques ni devoir se déplacer jusqu’au Mac.

En cas d’échec, préciser la couche concernée : connexion, image, clic, focus,
déclenchement vocal, transcription ou capteurs. Ne développer une interface
personnalisée qu’après identification du blocage.
