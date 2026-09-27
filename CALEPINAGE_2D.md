# Calepinage polygonal — première version

Développement sur `codex/polygonal-layout`, depuis `codex/tools-lab`.

## Parcours

Outils → Calepinage 2D → Saisir manuellement. Création d’un mur ou plafond rectangulaire, en L, sous rampant ou en pignon. Toutes les formes deviennent un contour polygonal éditable.

- **Sélection** : toucher une plaque pour ses cotes ; toucher une ouverture pour la modifier ; déplacer une ouverture par glissement.
- **Contour** : déplacer un sommet ; toucher un sommet pour saisir ses coordonnées, modifier la longueur du côté suivant, ajouter un sommet au milieu du côté ou supprimer le sommet.
- **Grille** : déplacer la pose avec le doigt. Les deux décalages sont aussi saisissables dans **Plaques**.
- **Vue** : déplacement du plan. Zoom par pincement et bouton de recentrage.
- **Plaques** : formats issus du catalogue Plaquisto Admin, saisie manuelle, orientation et décalages.
- **Ouverture** : porte, fenêtre, baie, passage, trémie ou fenêtre de toit suivant le support.
- **Découpes** : liste de toutes les plaques brutes et de leurs morceaux, surfaces nettes et chutes théoriques.

Les dimensions des formulaires sont en centimètres ; les points de traçage sont en millimètres. Le repère des découpes est le coin inférieur gauche de la plaque brute. Le rectangle brut apparaît en pointillés sur la fiche.

## Architecture et fichiers

| Fichier dans `Plaquisto/PlaquistoCore/Tools/` | Rôle |
| --- | --- |
| `LayoutGeometry.swift` | Calcul géométrique, validation et opérations sur les contours |
| `SheetLayoutEngine.swift` | Surface2D, couches, formats, placements, morceaux, joints et adaptateur d’import |
| `LayoutEditorModel.swift` | État de l’éditeur, calcul hors du fil d’interface, historique et brouillon |
| `SheetLayoutView.swift` | Plan tactile, sélection, zoom, déplacement et navigation |
| `LayoutForms.swift` | Création, ouvertures, sommets, réglages des plaques et cotes de découpe |

L’entrée est activée dans `ToolModels.swift` et `ToolsHomeView.swift`. `ToolTechnicalStore.swift` lit les formats `parements[].data.dimensions` du catalogue existant. Le projet Xcode inclut ces fichiers dans Plaquisto et Plaquisto Lab. Les tests se trouvent dans `Plaquisto/PlaquistoTests/SheetLayoutEngineTests.swift`.

Les modèles et le moteur ne dépendent ni de SwiftUI ni de RoomPlan. Les calculs utilisent des millimètres et un axe Y vers le haut. `LayoutDocument.layers` prévoit plusieurs couches ; l’éditeur V1 travaille sur la première.

## Calcul des intersections

Pour chaque case de la grille :

1. Les côtés du support, des ouvertures et de la plaque sont découpés à leurs intersections, y compris leurs recouvrements colinéaires.
2. Pour chaque segment obtenu, le moteur détermine si ses deux côtés séparent une zone à poser d’une zone vide : **dans la plaque ET dans le support ET hors de toutes les ouvertures**.
3. Les segments de frontière conservés sont assemblés en boucles orientées. Les boucles positives sont les morceaux extérieurs ; les boucles négatives sont les trous.
4. Les morceaux disjoints restent séparés dans la même plaque brute. Les ouvertures qui se chevauchent ne sont retirées qu’une seule fois. Les tangences ponctuelles sont séparées en boucles simples.

Les rampants conservent leurs côtés obliques et leurs sommets exacts. La fiche affiche les dimensions principales, les hauteurs latérales lorsqu’elles correspondent à des côtés verticaux, la longueur de chaque côté et les coordonnées de tous les sommets depuis la plaque brute.

Tolérance numérique : `0,00001 mm`, seuil de suppression d’artefacts : `0,0001 mm²`. Les contours croisés et les côtés nuls sont refusés. Un déplacement tactile invalide revient à la dernière géométrie valide. Les calculs sont déterministes, avec des offsets normalisés modulo les dimensions de plaque.

## Historique, performances et sauvegarde

Annuler/rétablir conserve jusqu’à 100 états durant la session. Un glissement crée une seule opération d’historique. Le dernier brouillon est conservé dans les préférences locales sous `plaquisto.tools.layout.draft.v1`, indépendamment des ouvrages du chantier.

Les calculs s’exécutent hors du fil principal. Pendant les gestes, les requêtes sont temporisées de 40 ms ; les calculs dépassés sont annulés et ne peuvent pas remplacer un résultat plus récent.

Limites explicites : 2 000 cases de grille, 200 sommets par contour et 100 ouvertures. Ce sont des limites de traitement de la V1, pas des règles de pose.

## Import du scanner

L’architecture existante du scanner expose déjà un modèle portable en mètres, avec points, murs, plans et provenance. Son triangulateur de rendu et sa tolérance de capture ne sont pas utilisés comme moteur de découpe.

`Surface2DAdapter.projected` reçoit un contour 3D en mètres, ses ouvertures, un identifiant source et un repère orthonormal local. Il projette les positions dans le plan réel du support et les convertit en millimètres. Un rampant conserve donc ses longueurs inclinées. Le modèle conserve le repère et l’identifiant de provenance.

Le bouton d’import reste explicitement indisponible : la sélection d’une surface du scanner et sa transmission à cet adaptateur seront connectées ultérieurement. Aucun scan n’est simulé.

## Tests

Tests sur : rectangle exactement divisible, plaque de fin partielle, poses verticale et horizontale, offsets positifs et négatifs, périodicité/déterminisme, fenêtre dans une plaque, porte au sol, ouvertures chevauchantes et traversant une ligne de grille, plafond en L avec trémie, mur sous rampant et cotes diagonales, pignon, polygone irrégulier dans les deux sens de parcours, morceaux disjoints, cellule entièrement vide, ouvertures tangentes, ouverture débordante, forme en U, petites découpes réelles, conservation des aires sur vingt offsets, rejet de géométries et formats invalides, projection d’un rampant, sérialisation, historique et sauvegarde du brouillon.

## Limites fonctionnelles

- Une couche affichée à la fois ; aucune prescription de joints décalés ni optimisation des chutes entre plaques ou supports.
- Ouvertures rectangulaires dans le formulaire ; le modèle et le moteur acceptent aussi des contours polygonaux.
- Un seul brouillon local, sans bibliothèque multi-plans ni rattachement à un ouvrage pour cette version.
- Les chutes sont une différence de surface brute/nette, pas un plan optimisé de réutilisation.
- Pas encore d’export de plan imprimable ni de liaison au visualiseur scanner.
- Les cotes calculées conservent la géométrie saisie ; leur précision physique dépend du relevé initial.
