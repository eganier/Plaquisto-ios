# Éditeur de dessin partagé

Branche : `codex/editeur-dessin`, après fusion de l'audit dans `main`.

## Parcours

- Même éditeur pour le sol de la modélisation manuelle, le support du calepinage rapide et la modification d'un contour existant.
- Trois outils bas : Sélection, Segment, Rectangle. Rectangle propose aussi Carré, avec les dimensions réelles en cm.
- Segment : toucher pour placer chaque point, aperçu pendant le geste, aimantation horizontale/verticale et parallèle/perpendiculaire au segment précédent. Fermer par le bouton ou en touchant le point initial après trois points. Le contour n'est pas fermé au simple passage du doigt.
- Sélection : toucher un côté pour sa longueur et Ajouter un point ; toucher un sommet pour son angle et Supprimer le point. Un point doit être sélectionné avant déplacement. Les modifications numériques sont prévisualisées et appliquées explicitement.
- Zoom par pincement centré sur les doigts ; déplacement de la vue par glissement sur le fond en Sélection ; recentrage séparé. Une grille légère facilite le repérage.
- Échelle : commande distincte du zoom, accessible pour le sol comme pour les supports et les rectangles. Pourcentage exact ou curseur ; longueurs, ouvertures et positions électriques redimensionnées, dimensions physiques des plaques/profils et diamètre des spots inchangés.
- Annuler la dernière modification reste sur le dessin. Recommencer nécessite confirmation. Le brouillon n'est transmis au parent qu'à Utiliser / Continuer.

## Compatibilité

- L'ancien éditeur est conservé (`LayoutLegacyManualContourEditor`) ; son accès depuis le nouveau menu est restreint aux décalages de pose et ne peut plus effectuer une mise à l'échelle cachée.
- Les angles et longueurs déjà contraints restent gérés par le solveur existant. Une contrainte incompatible n'est pas libérée silencieusement.
- Ajout/suppression de sommets : identité topologique modifiée, références de côtés des plaques et de l'ossature invalidées même si le nombre final de sommets est inchangé.
- Modélisation : une mise à l'échelle ou le déplacement d'un sommet conserve son attribution de hauteur. Changer la topologie demande confirmation avant de remettre les hauteurs particulières à zéro ; la hauteur commune reste disponible.
- Les transformations d'échelle successives conservent chacune leur origine pour transformer correctement les points électriques, même après d'autres modifications du contour.

## Recette

Tester rectangle/carré, contour concave en L, fermeture invalide, cote décimale, angle rentrant, ajout/suppression et annulation, échelle puis annulation, zoom sans modification des dimensions, contour avec ouvertures/électricité, sauvegarde/réouverture et sol à hauteurs différentes. Les gestes tactiles simultanés restent à confirmer sur iPhone après la recette simulateur.

### Résultats du 25 octobre 2026

- Suite ciblée `SheetLayoutEngineTests` + `SurveyCaptureTests` : 386 tests réussis, zéro échec. Elle comprend huit nouveaux cas sur les formes, les croisements, l'échelle et les références topologiques ; elle couvre également les contraintes, l'aimantation et la persistance existantes.
- Recette initiale iPhone 17 Pro simulé : carré 250 × 250 cm, échelle 120 % donnant 300 × 300 cm puis annulation ; ajout/suppression d'un sommet ; création d'un sol en L avec angle rentrant 270° ; passage aux hauteurs et sauvegarde d'un volume 3D dans un projet de test.
- Recette finale iPhone SE simulé : boutons et formulaires lisibles, rectangle 400 × 300 cm, déplacement du sommet C jusqu'au point de relâchement, angle modifié de 113,1° à 90°, puis annulations ramenant le rectangle à 12 m². Dernière correction des cotes orientées le long des côtés et des lettres de sommets vérifiée visuellement après recompilation.
- Compilations Lab réussies : `/tmp/plaquisto-drawing-lab-final.log`, puis `/tmp/plaquisto-drawing-lab-labels.log`. La dernière différence après les 386 tests ne concerne que le placement visuel des libellés.
- La saisie décimale au clavier via le pilotage natif n'a pas pu être confirmée : le processus Simulator a disparu pendant l'action à deux reprises. Ce cas n'est pas compté dans la recette UI ; les dimensions décimales sont couvertes au niveau des opérations géométriques. Aucune perte d'un projet utilisateur : ces dessins étaient des brouillons de recette.
- Aucun déploiement sur l'iPhone physique dans cette intervention. Le comportement au doigt, notamment le pincement simultané, reste à confirmer sur appareil.
