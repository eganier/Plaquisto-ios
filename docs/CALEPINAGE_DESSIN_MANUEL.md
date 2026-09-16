# Calepinage 2D — dessin manuel et mesures

État au 16 septembre 2026. Développement sur `codex/tools-lab-improvements`, interface disponible dans Plaquisto Lab.

## Parcours

Outils → Calepinage 2D ouvre la bibliothèque locale. `Enregistrer` met à jour le document courant (ou en crée un), puis revient à la liste. Le brouillon de l'ancienne version est migré. Revenir depuis Outils affiche cette liste, pas automatiquement le dernier plan.

Nouveau calepinage → Plafond → forme libre → Dessiner le contour ouvre un écran de dessin en grand. Un geste produit une forme rectiligne, sans reconnaissance de rectangle, triangle ou autre gabarit. Le tracé suivant repart de zéro. Un tracé ouvert ou croisé affiche un message et peut être redessiné.

Les cotes issues uniquement du dessin sont précédées de `≈`. Toucher une cote saisit une mesure terrain. Toucher un angle permet de l'imposer ou de le libérer. Glisser un sommet déplace ses deux côtés en direct, puis résout les contraintes au relâchement. Les champs sélectionnent leur valeur à la prise de focus ; toucher hors du champ, glisser le formulaire ou utiliser `Terminé` ferme le clavier.

## Architecture et fichiers

### Fichiers créés

- `Plaquisto/PlaquistoCore/Tools/LayoutPolygonSolver.swift` : configurations, nettoyage du tracé, intention utilisateur et solveur indépendant de SwiftUI.
- `Plaquisto/PlaquistoCore/Tools/LayoutPolygonEditor.swift` : écran de dessin, disposition des cotes/angles, édition numérique et déplacement des sommets.
- Ce document.

### Fichiers modifiés

- `LayoutGeometry.swift` : l'ancien point d'entrée de fermeture de mesures délègue au solveur commun.
- `SheetLayoutEngine.swift` : `Surface2D` conserve son contour résolu, l'intention utilisateur et les intentions archivées lors d'un changement de topologie. Décodage compatible avec les anciennes sauvegardes.
- `LayoutForms.swift` : capture du geste, intégration de l'écran de dessin, détails des corrections et clavier.
- `LayoutEditorModel.swift` : bibliothèque, sélection du texte, fermeture du clavier et résolution des modifications des sommets.
- `SheetLayoutView.swift` : bibliothèque et annotations interactives dans le calepinage final.
- `SheetLayoutEngineTests.swift` : tests géométriques et persistance.
- `Plaquisto.xcodeproj/project.pbxproj` : ajout des deux fichiers Swift aux cibles Lab et iOS.

`Surface2D` reste l'unique surface exploitable par le moteur de plaques. Son contour utilise `LayoutPoint` en millimètres dans un repère local. Le contrat `Surface2DAdapter.projected` existant convertit déjà les surfaces scanner en ce même modèle en préservant leur plan incliné, leur provenance et leur repère 3D. Aucun modèle de pièce concurrent n'est introduit.

## Nettoyage du dessin

1. Échantillonnage spatial, limite du nombre de points et vérification de la proximité début/fin.
2. Lissage cyclique pondéré sur cinq points.
3. Découpe du cycle en deux arcs éloignés, puis Ramer–Douglas–Peucker itératif sur chaque arc.
4. Suppression des micro-segments et fusion des directions presque colinéaires.
5. Intersection locale des deux côtés entourant un minuscule raccord arrondi.
6. Snap horizontal/vertical limité à trois degrés, accepté seulement si son déplacement reste faible et le contour valide.
7. Validation topologique et orientation cohérente. Aucune limitation artificielle à douze côtés.

Le snap utilise une fermeture linéaire par moindres carrés avant qu'une mesure terrain existe. La résolution des mesures et des angles utilise ensuite le moteur unique décrit ci-dessous.

## Résolution des contraintes

Le solveur minimise des résidus par Levenberg–Marquardt avec jacobiens analytiques locaux et résolution de Cholesky. Les inconnues sont les coordonnées des sommets. Le dernier côté rejoint toujours le premier sommet : la fermeture est obligatoire par construction, pas une pénalité approximative.

Les longueurs explicitement saisies sont fortes ; les longueurs et directions suggérées par le dessin sont souples. Les angles et positions de sommets explicitement imposés sont prioritaires. Une jauge de translation empêche le déplacement arbitraire de la pièce. Les poids sont centralisés.

L'optimisation répartit les écarts sur les longueurs concernées en minimisant leur somme des carrés pondérée ; aucun côté de fermeture n'absorbe arbitrairement tout l'écart. Exemple testé : deux côtés opposés demandés à 414 et 400 cm, avec quatre angles droits, donnent environ 407 cm chacun et des corrections de −7/+7 cm. Les angles du dessin restent des indications souples tant qu'ils n'ont pas été imposés.

Un jeu de contraintes contradictoire, un contour croisé, des côtés nuls ou une inversion de la pièce sont refusés avec conservation du plan précédent. Une correction rouge sur un contour valide n'empêche pas de valider.

## Conservation des données

`LayoutContourIntent` contient le dessin initial, `userMeasuredLengths`, `userAnglesDegrees` et `userVertexPositions`. Une valeur `nil` signifie « non mesurée/non imposée ». Le solveur ne modifie jamais cette structure.

`Surface2D.contour` contient les positions résolues ; les longueurs résolues en sont déduites. `LayoutDimensionCorrection` conserve la longueur originale, la longueur corrigée, le delta signé et le pourcentage absolu par rapport à l'original. Les sauvegardes, annulations et réouvertures conservent cette séparation.

L'ajout/la suppression d'un sommet change l'identité des côtés : l'ancienne intention est alors archivée dans `previousContourIntents`, et le nouveau contour repart avec des cotes estimées. Les anciens relevés ne sont pas détruits ni attribués au mauvais côté. Même principe lors d'un redessin.

## Seuils par défaut

| Paramètre | Valeur |
|---|---|
| Échantillonnage | 2,5 points d'écran |
| Nombre maximal de points bruts | 2 048 |
| Fermeture initiale | max(28 points, 14 % de la taille du dessin) |
| Tolérance RDP | 10 points d'écran |
| Micro-segment | 12 points |
| Petit raccord d'angle | 32 points maximum |
| Quasi-colinéarité | 10° |
| Snap horizontal/vertical | 3° maximum |
| Côté résolu minimal | 10 mm |
| Nombre maximal de sommets | 200, limite géométrique préexistante |
| Itérations du solveur | 60 maximum |
| Correction non significative | ≤ 0,1 mm |
| Jaune | correction significative et < 2 cm |
| Orange | 2 à 5 cm inclus |
| Rouge | > 5 cm ; recommandation de refaire la mesure |
| Résidu maximal d'un angle imposé | 0,25° |
| Résidu maximal d'un sommet imposé | 0,5 mm |

## Affichage

Les cotes sont horizontales, colorées, avec lignes de rappel et traits de cote. Une recherche de positions limite les collisions avec les sommets, les autres cotes et les angles. La même présentation est utilisée dans l'éditeur de contour et dans le plan de plaques.

Le warning est un bouton distinct de la cote : il ouvre les valeurs relevée/retenue, le delta signé en cm et le pourcentage. Le rouge ajoute une recommandation, pas un blocage. Les angles rentrants sont conservés (par exemple 270° dans un L).

## Vérification

La suite `SheetLayoutEngineTests` couvre les rectangles tremblants, L, pentagones/diagonales, bruit et crochet parasite, départ au milieu d'un côté, 16 sommets, fermeture proche, tracés ouverts/croisés/courts/non finis, mesures cohérentes ou ajustées, seuils exacts des warnings, modification longueur/angle/sommet, angles rentrants, contraintes contradictoires, sérialisation et bibliothèque de plusieurs documents. Les tests historiques de découpe et de projection scanner sont conservés.

Résultat du 16 septembre 2026 : **25 tests passés, zéro échec** dans `SheetLayoutEngineTests` sur le simulateur iPhone 17 Pro. Compilation Lab simulateur et iPhone réussie. Version installée sur les deux appareils ; installation physique confirmée par `devicectl` pour `fr.plaquisto.lab`.

Contrôles UI effectués dans le simulateur : réouverture de la bibliothèque avec deux documents, accès à un document, affichage des cotes et angles, saisie remplaçant la valeur existante, modification d'un angle de 90° à 87° avec recalcul, fermeture de la saisie par appui dans le fond, annulation, enregistrement et retour à la liste, accès à l'écran de dessin plein écran. Le geste fermé complet a été vérifié par les séries de points unitaires ; l'ergonomie du tracé au doigt reste à confirmer sur l'iPhone.

Sur ces fixtures synthétiques, le nettoyage et les tests du solveur s'exécutent en quelques millisecondes dans le simulateur. Ce n'est pas un benchmark du téléphone ni une garantie pour des contours de 200 sommets.

## Limites et suite recommandée

- Les très petits détails du dessin peuvent être absorbés par les tolérances de nettoyage : dessiner plus grand améliore leur conservation.
- L'optimisation est locale ; elle ne garantit pas une solution pour tout ensemble de contraintes contradictoires ou une forme auto-intersectée.
- Sur un téléphone, un contour très dense peut encore présenter des annotations proches malgré le placement anti-collision.
- L'outil fournit une géométrie et des quantités, pas une précision métrologique garantie par un croquis.
- Prochaine étape : tester plusieurs tracés réels au doigt, puis ajuster les seuils et ajouter des identifiants stables de côtés pour conserver davantage de contraintes lors d'un ajout/suppression de sommet.
- Aucun `PROJECT_STATE.md` n'était présent dans ce dépôt ; cet état est documenté ici.
