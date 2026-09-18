# Calepinage 2D — dessin manuel et mesures

État au 17 septembre 2026. Développement sur `codex/tools-lab-improvements`, interface disponible dans Plaquisto Lab.

## Organisation et visibilité — 17 septembre

- Modes communs à tous les murs/plafonds, gabarits et contours libres : **Vue → Plaques → Ossatures → Ouvertures → Électricité**. Vue est le mode initial. Sélection d'une plaque par un toucher en mode Plaques ; le glissement déplace toujours la grille.
- Le menu `…` contient **Modifier le contour et l’échelle**, unique accès aux mesures du contour depuis le plan final.
- Cinq icônes dessinées en Canvas remplacent le menu Affichage : plaque, angle α, fourrure + rail en perspective, fenêtre, prise + spot. Cycle visible → coté → masqué (pointillé atténué), sauf angles : visible/masqué. Libellés et état accessibles VoiceOver.
- Valeurs initiales : plaques/ossatures/ouvertures/électricité visibles sans cotes, angles masqués. Réinitialisées à l'ouverture d'un autre document ; pas de migration des fichiers sauvegardés.
- Les nouveaux supports ont une ossature initiale compatible avec le format de plaque ; les anciens plans sans ossature restent inchangés. Ossatures verticales pour les murs.
- Cotes des plaques en cm, longueurs des ossatures parallèles aux profils ; cotes des ouvertures/points électriques vers les murs. Une ouverture déplacée conserve ses cotes transitoires. Les couches masquées ne réapparaissent pas durant le déplacement et ne peuvent pas être sélectionnées ou déplacées invisiblement. Les trous restent de vrais vides dans les plaques même si leurs annotations sont masquées.
- Calcul des découpes/métrages au relâchement conservé. Les dimensions détaillées ne sont pas recalculées durant le glissement de grille.
- Aperçu du support agrandi selon le nombre de côtés, marges accrues et placement des cotes avec recherche de positions libres autour du contour. Lignes de rappel pour les petits décrochements.

### Mise à niveau d'un nouveau tracé

Dès le relâchement du doigt, après simplification et validation : choix du segment bas orienté vers la droite, rotation rigide autour de son extrémité pour le rendre horizontal. **Plafonds : rotation seule, aucun angle redressé**, y compris désactivation du petit snap d'axes historique. **Murs uniquement :** projection des voisins des deux angles au sol lorsqu'ils sont à **8° ou moins de 90°**. Aucun verrou de mesure n'est créé. Les angles franchement obliques et rentrants sont conservés ; les triangles ne sont pas équarris. Une correction qui invaliderait la topologie est abandonnée au profit de la rotation seule.

Ce traitement concerne uniquement les nouveaux tracés/redessins : jamais les modifications d'un contour déjà mesuré, les sauvegardes ou les imports. Le déplacement d'un sommet reste libre hors contraintes explicitement verrouillées.

Validation : 62 tests `SheetLayoutEngineTests` réussis, aucun échec/ignoré (`Test-Plaquisto-2026.09.17_23-00-18-+0200.xcresult`). Rendu du contour chargé et des icônes inspecté ; parcours du simulateur contrôlé (sélection directe, cotes longitudinales, masquage). Compilations Lab simulateur et iPhone réussies. Lab installé sur l'iPhone le 17 septembre à 23:07, séquence 2248.

## Parcours

### Finition bibliothèque et commandes (17 septembre, deuxième passe)

- Icônes de visibilité : angle, plaque, ossature, fenêtre à double cadre, éclair ; mêmes colonnes et espacements que Vue/Plaques/Ossatures/Ouvertures/Électricité. Cycle des cotes et pointillés conservé, cote des profils éloignée du rail.
- Le cartouche X/Y est remplacé par un bouton de remise à l'horizontale du côté bas. Il agit uniquement sur la caméra et recadre le plan : aucune mesure ni implantation n'est modifiée.
- Un support prédéfini passe obligatoirement par « Modifier le contour et l’échelle » après Suivant, avant de créer le calepinage. Annuler ce contrôle revient aux dimensions du gabarit.
- Retour haut gauche depuis un calepinage local : sauvegarde puis bibliothèque ; depuis la bibliothèque : retour Outils habituel. Le parcours d'un calepinage rattaché à un ouvrage garde son callback de sauvegarde.
- Lignes de bibliothèque : aperçu léger du contour et des plaques, type Mur/Plafond, aire brute et date de création. Les profils/éclairages/annotations ne sont pas rendus en miniature.
- Glissement vers la gauche sans action complète automatique : boutons Renommer et Supprimer. Suppression effective uniquement après bouton rouge ET confirmation. Renommage vide ignoré ; date de création stable après renommage et sauvegarde.
- Compatibilité des JSON anciens : `createdAt` absent reprend `updatedAt`, seule date connue avant cette évolution.

Tests de cette passe : **65 tests réussis**, zéro échec/ignoré, rapport `Test-Plaquisto-2026.09.17_23-36-26-+0200.xcresult`. Ajouts : alignement de caméra non déformant, cycle sauvegarde/renommage/date et décodage ancien, rendu des nouvelles icônes/miniatures. Compilateur Lab simulateur : succès.

Contrôle UI réel : bibliothèque/miniatures, retour depuis le plan, dialogues de renommage/suppression (annulés), gabarit → modification du contour → retour au formulaire. Aucun calepinage supprimé. Compilation Lab iPhone réussie et installation confirmée le 17 septembre à 23:42, séquence 2256.

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
6. Murs uniquement : snap horizontal/vertical limité à trois degrés, accepté seulement si son déplacement reste faible et le contour valide. Pas de snap angulaire pour les plafonds.
7. Validation topologique et orientation cohérente, alignement du bas et éventuel équarrissage des deux angles au sol des murs (voir ci-dessus). Aucune limitation artificielle à douze côtés.

Le snap utilise une fermeture linéaire par moindres carrés avant qu'une mesure terrain existe. La résolution des mesures et des angles utilise ensuite le moteur unique décrit ci-dessous.

## Résolution des contraintes

### Correction du déplacement des sommets (16 septembre, après retour iPhone)

Le déplacement d'un sommet utilisait auparavant une position imposée sur l'ancienne esquisse. Avec un seul sommet fixé, translater tout le polygone satisfaisait cette position en conservant toutes les anciennes longueurs : la surface ne changeait donc pas. Le problème ne venait pas d'une contrainte explicite d'aire.

Le geste passe désormais par `Surface2D.movingVertices(to:)` : la forme déplacée devient la référence, les autres sommets restent à leur place en l'absence de verrous, et seuls les angles/longueurs explicitement verrouillés contraignent la résolution. Les anciennes positions de glissement ne deviennent plus des verrous invisibles. Les relevés originaux sont conservés pour afficher les corrections ; le tracé antérieur est archivé. Le même chemin est utilisé dans le dessin plein écran et dans l'éditeur du calepinage. Le point suit la translation du doigt sans sauter au centre de la prise.

Régression testée : déplacer C d'un rectangle de 400 × 300 cm vers (500, 400) cm fait passer l'aire de 12 à 15,5 m², puis vers (300, 200) cm à 8,5 m² ; les trois autres points restent inchangés. Tests supplémentaires : verrous visibles, rejet d'une auto-intersection, annulation/rétablissement et réouverture après sauvegarde.

Validation : **73 tests réussis**, aucun échec ni test ignoré, dans `SheetLayoutEngineTests` et `ProjectStoreTests`. Rapport : `/tmp/PlaquistoLayoutTestsDerived/Logs/Test/Test-Plaquisto-2026.09.16_23-03-12-+0200.xcresult`.

Compilations Lab iPhone et simulateur réussies ; correction installée sur l'iPhone le 16 septembre à 23:07. L'app de production reste inchangée sur le téléphone.

Le solveur minimise des résidus par Levenberg–Marquardt avec jacobiens analytiques locaux et résolution de Cholesky. Les inconnues sont les coordonnées des sommets. Le dernier côté rejoint toujours le premier sommet : la fermeture est obligatoire par construction, pas une pénalité approximative.

Les longueurs explicitement saisies sont fortes ; les longueurs et directions suggérées par le dessin sont souples. Les angles et positions de sommets explicitement imposés sont prioritaires. Une jauge de translation empêche le déplacement arbitraire de la pièce. Les poids sont centralisés.

L'optimisation répartit les écarts sur les longueurs concernées en minimisant leur somme des carrés pondérée ; aucun côté de fermeture n'absorbe arbitrairement tout l'écart. Exemple testé : deux côtés opposés demandés à 414 et 400 cm, avec quatre angles droits, donnent environ 407 cm chacun et des corrections de −7/+7 cm. Les angles du dessin restent des indications souples tant qu'ils n'ont pas été imposés.

Un jeu de contraintes contradictoire, un contour croisé, des côtés nuls ou une inversion de la pièce sont refusés avec conservation du plan précédent. Une correction rouge sur un contour valide n'empêche pas de valider.

## Conservation des données

`LayoutContourIntent` contient le dessin initial, `userMeasuredLengths`, `userAnglesDegrees` et `userVertexPositions`. Une valeur `nil` signifie « non mesurée/non imposée ». Le solveur ne modifie jamais cette structure.

`Surface2D.contour` contient les positions résolues ; les longueurs résolues en sont déduites. `LayoutDimensionCorrection` conserve la longueur originale, la longueur corrigée, le delta signé et le pourcentage absolu par rapport à l'original. Les sauvegardes, annulations et réouvertures conservent cette séparation.

L'ajout/la suppression d'un sommet archive l'ancienne intention dans `previousContourIntents`. Les contraintes des côtés non touchés sont remappées ; celles des côtés coupés/fusionnés et des angles adjacents sont libérées. Un redessin repart avec des cotes estimées. Les anciens relevés ne sont pas détruits ni attribués au mauvais côté.

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

### Échelle, orientation des plaques et fourrures

Après le dessin, un curseur de ×0,25 à ×5 multiplie proportionnellement les dimensions réelles (ce n'est pas le zoom). Il transforme le contour, les ouvertures, l'esquisse et les positions de sommets imposées ; les angles sont conservés. Une action complète du curseur est annulable. Après une autre modification, la nouvelle forme devient la référence ×1. Le réglage se retrouve aussi depuis le menu « Dessin et échelle » du calepinage.

Le changement global d'échelle est volontairement verrouillé dès qu'une longueur terrain a été saisie : il ne doit jamais réécrire silencieusement une mesure utilisateur. Les cotes approximatives restent ajustables avant ce relevé. Les surfaces issues du scanner ne sont pas redimensionnées par ce contrôle.

Les cotes et les angles peuvent être masqués indépendamment, dans le dessin et dans le calepinage. Ces préférences d'affichage sont conservées localement.

Dans « Plaques et pose », sélectionner un mur A–B, B–C… aligne le repère de pose sur ce côté. Le grand côté des plaques peut être parallèle ou perpendiculaire au mur. Le premier sommet du côté devient l'origine de la grille ; les décalages se font dans ce repère. `LayoutGridFrame` convertit entre plan et grille. Le moteur, les découpes et leurs cotes restent en coordonnées de grille, sans boîte englobante erronée après rotation. L'affichage et le hit-testing réalisent la conversion inverse. Un changement de topologie réinitialise le côté de référence plutôt que de réutiliser un indice pour un autre mur.

Une trame optionnelle de fourrures peut être activée : parallèle/perpendiculaire **au grand côté des plaques**, entraxe 400, 500 ou 600 mm, décalage indépendant. `LayoutFurringEngine` intersecte les lignes avec le contour et les ouvertures, puis conserve uniquement les segments dans le support. Les membres en rive sont inclus s'ils coïncident avec la trame. Le calcul ne prescrit ni entraxe techniquement admissible, ni appuis, ni fixations. La compatibilité géométrique vérifie la divisibilité du format et la phase des joints parallèles aux fourrures, pas un montage réglementaire.

Dans « Affichage », on peut masquer la trame, afficher ses cotes et choisir le mur à coter. Les repères sont les distances **cumulées depuis le premier sommet du mur**, non les espacements successifs. Le détail des repères fournit aussi la liste numérique par mur. Sur les murs obliques, ces distances sont mesurées le long du mur, pas projetées sur X/Y.

Les nouveaux champs `LayoutLayer.referenceEdge` et `LayoutLayer.furring` sont optionnels et sauvegardés avec le document ; les anciens documents sans ces champs restent lisibles.

Les cotes sont horizontales, colorées, avec lignes de rappel et traits de cote. Une recherche de positions limite les collisions avec les sommets, les autres cotes et les angles. La même présentation est utilisée dans l'éditeur de contour et dans le plan de plaques.

Le warning est un bouton distinct de la cote : il ouvre les valeurs relevée/retenue, le delta signé en cm et le pourcentage. Le rouge ajoute une recommandation, pas un blocage. Les angles rentrants sont conservés (par exemple 270° dans un L).

## Vérification

### Extension : plaques, ossature, éclairage et ouvrages

#### Éclairage éditable (itération suivante)

- Dans le panneau Éclairage, glisser sur l'aperçu déplace tout le groupe. La translation conserve les écarts. Un déplacement invalide est annulé au relâchement. Centrer conserve la disposition et translate seulement le groupe.
- Rouvrir ce panneau conserve les positions sauvegardées, y compris après des alignements manuels. Changer uniquement le diamètre ne déplace pas les spots. Le curseur d'écartement effectue une homothétie autour du centre, sans régénérer la disposition. Seul le changement du nombre recrée une répartition régulière.
- Le plan comprend un mode Éclairage au même niveau que Plaques/Ossature. Toucher un spot ajoute/retire la sélection ; toucher le vide la vide. Tout sélectionner permet de déplacer le groupe complet. Glisser un spot sélectionné translate la sélection ; glisser un spot non sélectionné le déplace seul. Glisser le fond déplace la vue.
- Organiser propose alignement horizontal/vertical sur le dernier spot sélectionné (repère bleu), ainsi que répartition des centres en X/Y entre les extrêmes conservés. Les écarts libres sont également uniformes puisque les diamètres sont identiques. Minimum deux spots pour aligner, trois pour répartir. Axes du dessin, non orientation d'un mur.
- L'aimantation, désactivable, détecte un alignement avec les spots non sélectionnés à moins de 8 points d'écran et affiche les repères. En mode Éclairage, la rotation à deux doigts tourne la sélection (ou tous les points si sélection vide) autour de son centre, avec aimantation sur les côtés. Le zoom est réservé aux autres modes pour ne pas déplacer la caméra pendant cette manipulation. Même rotation disponible dans l'aperçu du formulaire.
- Toutes ces modifications sont annulables et sauvegardées avec le calepinage. Les placements hors contour, dans les ouvertures ou se chevauchant (diamètre + 10 mm de dégagement géométrique) sont refusés. Aucune prescription d'installation électrique ni contournement automatique de l'ossature.
- Les quatre boutons de réglages inférieurs ont une largeur flexible identique et une hauteur commune de 64 points.

- Toucher un sommet propose sa suppression après confirmation ; toucher un segment propose un sommet supplémentaire. Les cotes et angles affichent leur cadenas et peuvent être imposés/libérés. Une distance verrouillée doit être respectée à 0,5 mm ; une contradiction est refusée. Les anciennes mesures non verrouillées gardent le comportement souple et leurs corrections.
- La surface est visible en bas à droite du dessin. Les modes du plan sont Sélection, Plaques, Ossature, Éclairage et Vue. Les formulaires du bas sont Plaques, Fourrures, Ouvertures et Éclairage (Ossature/Électricité sur un mur).
- Le pinch zoome hors mode Éclairage. Pendant un déplacement, un rendu de grille léger est découpé visuellement au contour ; le calcul des intersections, plaques et mètres linéaires attend le relâchement. Les totaux restent ceux du dernier calcul terminé.
- Les ouvertures déplacées affichent les projections perpendiculaires de leurs coins vers les murs visibles. Affichage permet de conserver ces cotes, celles des spots et les longueurs individuelles des fourrures.
- Les aperçus de pose utilisent le vrai moteur. Le format 240 × 120 cm est compatible avec 40/60 cm en perpendiculaire ; 250 × 120 cm avec 50 cm. Un format changé peut ajuster l'entraxe avec avertissement ; un entraxe choisi incompatible propose les formats du catalogue. Les boutons Caler synchronisent les phases des deux trames.
- Optimiser effectue une recherche bornée de décalages, sans garantie d'optimum global : minimum de plaques de grille pour Plaques, **mètres linéaires posés** pour Ossature (choix confirmé par l'utilisateur). Le déplacement optimisé coordonne les deux trames. Il ne réemploie pas les chutes entre cases et ne calcule pas les barres commerciales à acheter.
- Éclairage répartit 1 à 64 spots : grille régulière si possible, répartition espacée de secours pour formes concaves. Le curseur règle l'écartement. Les trous évitent le contour et les ouvertures ; un déplacement ultérieur causant un conflit est signalé. Les détails d'une plaque donnent le diamètre et les cotes au centre des trous depuis les bords de la plaque brute. Aucun dimensionnement électrique/photométrique ni évitement automatique des fourrures.
- Exporter vers un ouvrage ouvre le formulaire métier dans un chantier Lab existant ou nouveau. Le calepinage est conservé dans `WorkItem.layoutDocument` ; le lien « Calepinage 2D existant » le rouvre. Une édition le marque à recalculer et remet sa géométrie dans le formulaire. La duplication copie le document indépendamment.
- Les quantités métier restent distinctes du nombre de plaques exact du dessin. L'export transmet les longueurs exactes des côtés pour un plafond rectangulaire sans ouverture (même tourné) ; sinon il transmet la surface nette et les dimensions de l'enveloppe à vérifier. Les portées et hauteurs doivent être vérifiées pour les formes irrégulières. L'entraxe choisi est conservé à l'initialisation du formulaire plafond, tout en gardant ses avertissements techniques. L'export ne transforme pas un croquis de rampant en prescription technique.
- Plaquisto Lab dispose désormais de l'onglet Chantiers Lab pour ce parcours ; son stockage reste séparé de Plaquisto iOS.

Nouveaux fichiers : `LayoutPlanning.swift` (coordination, optimisation, spots et topologie), `LayoutPlanningForms.swift` (aperçus/formulaires), `LayoutExportForm.swift` (passerelle ouvrages).

Contrôles UI de l'extension : création d'un plafond 400 × 250 cm, ajustement automatique à 50 cm pour des plaques de 250 cm, proposition et choix de plaques de 240 cm en sélectionnant 40 cm, aperçu réel des deux trames, ajout de six spots et curseur d'écartement, mode Ossature avec total en ml, optimisation de 28 à 24 ml sur cette fixture. Parcours complet d'export via le formulaire plafond, sauvegarde dans « Contrôle calepinage Lab » du simulateur et réouverture via « Calepinage 2D existant » vérifiés. Aucun chantier de test créé sur le téléphone. Le geste pinch à deux doigts et la fluidité réelle restent à confirmer sur l'iPhone.

Validation finale de l'extension : **70 tests ciblés réussis**, aucun échec ni test ignoré (`SheetLayoutEngineTests` + `ProjectStoreTests`). Résultat : `/tmp/PlaquistoLayoutTestsDerived/Logs/Test/Test-Plaquisto-2026.09.16_22-31-58-+0200.xcresult`. Les deux tests complémentaires couvrent le rectangle tourné à l'export et le conflit d'un spot après déplacement d'une ouverture. Compilations Lab simulateur et iPhone réussies. Dernière version installée sur l'iPhone le 16 septembre à 22:34, lancement confirmé à 22:34:57 ; aucune mise à jour de l'app de production.

La suite `SheetLayoutEngineTests` couvre les rectangles tremblants, L, pentagones/diagonales, bruit et crochet parasite, départ au milieu d'un côté, 16 sommets, fermeture proche, tracés ouverts/croisés/courts/non finis, mesures cohérentes ou ajustées, seuils exacts des warnings, modification longueur/angle/sommet, angles rentrants, contraintes contradictoires, sérialisation et bibliothèque de plusieurs documents. Les tests historiques de découpe et de projection scanner sont conservés.

Première version du 16 septembre 2026 : **25 tests passés, zéro échec** dans `SheetLayoutEngineTests` sur le simulateur iPhone 17 Pro. Compilation Lab simulateur et iPhone réussie. Cette première version a été installée sur les deux appareils ; installation physique confirmée par `devicectl` pour `fr.plaquisto.lab`.

Extension échelle/orientation/fourrures : **31 tests passés, zéro échec**, résultat `Test-Plaquisto-2026.09.16_18-14-24-+0200.xcresult`. Couverture ajoutée : homothétie avec angles et positions imposés, protection des mesures, plaques parallèles à un mur oblique avec conservation des cotes de découpe, repérage inverse, fourrures 40/60 et deux orientations, interruptions aux ouvertures, forme concave, lignes en rive après rotation, rétrocompatibilité et sérialisation des réglages. Compilation Lab simulateur réussie, installation et lancement de `fr.plaquisto.lab` confirmés. Le contrôle visuel de cette extension reste à réaliser : Mac verrouillé. La signature iPhone attend l'autorisation du trousseau macOS ; l'extension n'est pas encore confirmée installée sur l'iPhone. Recompiler la cible iPhone après déverrouillage avant installation pour intégrer les derniers ajustements de rive.

Mise à jour déploiement, 16 septembre à 18 h 38 : recompilation iPhone de la dernière extension réussie après autorisation du trousseau. Installation de `fr.plaquisto.lab` confirmée sur l'iPhone physique par `devicectl`. Le lancement automatique a été refusé parce que l'iPhone était verrouillé ; l'application peut être ouverte manuellement après déverrouillage. Le contrôle visuel des nouveaux réglages reste à effectuer.

Contrôles UI effectués dans le simulateur : réouverture de la bibliothèque avec deux documents, accès à un document, affichage des cotes et angles, saisie remplaçant la valeur existante, modification d'un angle de 90° à 87° avec recalcul, fermeture de la saisie par appui dans le fond, annulation, enregistrement et retour à la liste, accès à l'écran de dessin plein écran. Le geste fermé complet a été vérifié par les séries de points unitaires ; l'ergonomie du tracé au doigt reste à confirmer sur l'iPhone.

Sur ces fixtures synthétiques, le nettoyage et les tests du solveur s'exécutent en quelques millisecondes dans le simulateur. Ce n'est pas un benchmark du téléphone ni une garantie pour des contours de 200 sommets.

## Limites et suite recommandée

### Rotation, harmonisation murs/plafonds et implantation électrique

- Rotation de vue à deux doigts sur les plafonds uniquement, autour de l'origine monde (0,0). Le repère reste fixe : la géométrie et les métrés ne changent pas. Aimantation lorsqu'un côté rejoint un axe : acquisition 2,5°, libération 5°, retour haptique. La cible recadre l'enveloppe tournée, sans remettre l'angle à zéro.
- Les conversions écran/monde et les déplacements tiennent compte de la rotation. Le calage sur un mur des plaques est indépendant de la rotation de la caméra.
- Toutes les formes proposent « Modifier le contour et l'échelle ». Le dessin à main levée est disponible pour murs et plafonds. Les murs sont dessinés de face, sol horizontal en bas, sans rotation de vue. Leur ossature reste verticale et ne suit pas un côté oblique.
- Pinch pour zoomer de 0,4× à 8× pendant le dessin et la retouche. Le zoom ne change aucune mesure. En retouche, glisser le fond déplace la caméra ; la cible recadre le contour. Pendant le tracé brut, un pinch suspend le trait sans le valider ; repartir près de son extrémité le prolonge, repartir ailleurs commence un nouveau tracé.
- Sur un mur tenant dans une seule hauteur de plaque, le décalage vertical est bloqué au sol. Pour plusieurs hauteurs superposées, les deux axes restent disponibles. Ce critère utilise la hauteur de la plaque dans son orientation choisie, pas sa longueur commerciale seule.
- La fiche d'une découpe est un dessin coté avec options de visibilité dessous : côtés, plaque brute, ouvertures, perçages, coordonnées X/Y. Les cotes des centres de perçage sont reportées depuis les deux bords de la plaque brute. Les identifiants des points sont conservés du plan à la fiche.
- Diamètre par défaut des nouveaux spots : 68 mm ; les valeurs sauvegardées restent inchangées. Ajout manuel un à un, suppression de sélection, centrage, rotation, alignement, répartition et agrandissement/réduction d'un groupe sont disponibles. Le centrage d'un groupe irrégulier qui rencontre une ouverture est refusé, jamais ajusté silencieusement.
- « Rapprocher / écarter » dans Organiser agit sur la sélection ou tous les points. Le curseur conserve le centre, les positions relatives et le diamètre ; il ne régénère pas la grille. Les points non sélectionnés restent fixes.
- Pour les murs, le panneau « Prises et lumières » ajoute des rangées successives avec type, quantité et hauteur au centre depuis le sol. Répartition horizontale régulière entre les limites du mur à cette hauteur. Si un point tombe dans une ouverture ou sur un autre point, toute la rangée est refusée avec une indication ; l'ajout manuel reste possible. Le centrage mural est horizontal pour préserver les hauteurs.
- Le champ optionnel `LayoutLighting.kinds` distingue prises/lumières et préserve la lecture des anciens documents. Il s'agit d'un plan d'implantation géométrique, sans validation électrique ou prescriptions de hauteur.

### Outils de mesure d’angle

Harmonisation visuelle du 17 septembre au matin : dessins Canvas en perspective 3D, murs épais en blocs (joints et alvéoles sur le dessus), repères L/L/D uniquement. L'arc extérieur relie les deux faces réelles en passant par le grand tour dans l'espace libre ; le petit arc supérieur de l'image de référence utilisateur n'est pas repris. Résultat principal commun aux deux écrans et aide détaillée repliable. Le moteur de calcul est inchangé. Suivi des vérifications et de l'installation dans `PROJECT_STATE.md`.

Extension du 17 septembre : la rubrique dédiée « Mesure d’angle » remplace l'entrée unique dans Traçage & calepinage. Deux outils « Angle intérieur · 0–180° » et « Angle extérieur · 180–360° » partagent `WallAngleCalculator.calculate` et `WallAngleToolView`, avec deux arcs Canvas distincts. Le résultat extérieur est 360° moins l'intérieur. L'UX reste volontairement différente : repères sur les murs pour l'intérieur ; murs réels pleins et prolongements virtuels pointillés pour l'extérieur, avec A–B entièrement dans la zone libre. Voir `PROJECT_STATE.md` pour les 95 tests réussis, les contrôles visuels clair/sombre et l'installation Lab physique à 00:34. La description ci-dessous conserve l'historique de la première version intérieure.

Intégré à « Traçage & calepinage » dans le catalogue partagé, avec écran `WallAngleToolView` et schéma Canvas (sans dépendance). Saisie L préremplie à 100 cm et D vide. Champs numériques existants à sélection complète, acceptant point/virgule, sans bouton accessoire « Terminé ». Résultat automatique à une décimale : l'angle intérieur entre les deux murs, entre 0° et 180° (extrémités dégénérées rejetées). L'écart à 90° et l'indication d'angle pratiquement droit ne sont plus affichés. Schéma de dessus : deux segments L bleus et liaison D orange.

`WallAngleCalculator` dans `ToolModels.swift` sépare calcul/validation de la vue : `2 asin(D / (2 L))`, conversion en degrés, valeurs strictement positives et finies, ratio strictement inférieur à 1, protection contre dépassements numériques. Les entrées impossibles ne produisent pas de résultat. `ToolCalculatorTests` couvre 60/90/120/150°, valeurs nulles/négatives/non finies, triangle dégénéré, grandes valeurs finies, format français et recherche du catalogue.

Validation du 16 septembre, finalisée le 17 septembre : 92 tests unitaires réussis, aucun échec ni test ignoré, résultat `/tmp/PlaquistoLayoutTestsDerived/Logs/Test/Test-Plaquisto-2026.09.16_23-44-52-+0200.xcresult`. Les derniers ajustements d'interface (zoom du dessin, clavier et résultat simplifié de l'angle) ont ensuite été compilés pour simulateur et iPhone. Plaquisto Lab (`fr.plaquisto.lab`) réinstallé sur l'iPhone à 23:57 le 16 septembre, sans mise à jour de l'application de production. Contrôles visuels simulateur : L=100 et D=141,4 donnent 90,0°, sans écart à 90° ni bouton « Terminé » ; fiche de plaque avec dessin coté, repères de perçages et options de visibilité. Le ressenti des gestes à deux doigts et de l'aimantation reste à valider physiquement sur l'iPhone.


- Les très petits détails du dessin peuvent être absorbés par les tolérances de nettoyage : dessiner plus grand améliore leur conservation.
- L'optimisation est locale ; elle ne garantit pas une solution pour tout ensemble de contraintes contradictoires ou une forme auto-intersectée.
- Sur un téléphone, un contour très dense peut encore présenter des annotations proches malgré le placement anti-collision.
- L'outil fournit une géométrie et des quantités, pas une précision métrologique garantie par un croquis.
- Prochaine étape : tester plusieurs tracés réels au doigt, puis ajuster les seuils et ajouter des identifiants stables de côtés pour conserver davantage de contraintes lors d'un ajout/suppression de sommet.
- Aucun `PROJECT_STATE.md` n'était présent initialement ; il a été créé le 17 septembre pour le suivi de la rubrique Mesure d’angle. L'historique détaillé du calepinage reste ici.
