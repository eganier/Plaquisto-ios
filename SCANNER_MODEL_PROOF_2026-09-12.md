# Pièce Plaquisto : preuve d’indépendance et murs

12 septembre 2026 — étape incrémentale après le refactor, pas une nouvelle architecture.

## Mise à jour : sélection du plafond

Le plafond affiché était exclu du hit-test, réservé aux murs. Les pans portent maintenant l’UUID de leur plafond propriétaire : toucher un plafond transparent ou plein sélectionne sa fiche et surligne ses pans. Le menu « Élément » permet aussi de choisir « Plafond 1 ». Masquer le plafond permet de sélectionner les murs situés derrière.

La fiche affiche la surface des pans acceptés suivant leurs pentes, leurs inclinaisons, leur origine et leur validation. Elle rappelle que les ouvertures de toit/trémies ne sont pas déduites. Aucun changement de reconstruction ni de données sauvegardées.

Toucher direct vérifié dans le simulateur avec le JSON réel : « Plafond sélectionné », 14,14 m², un pan. Tests de rendu (dont aire d’un pan concave incliné), compilation simulateur et compilation iPhone signée réussis. Version installée sur l’iPhone le 12 septembre à 21:25 ; confirmation tactile sur appareil attendue.

## Mise à jour : rendu maquette

Après le retour d’Edouard sur les murs pleins et le plafond absent, lecture du JSON de sa pièce sur iPhone : 13 murs, une porte et deux passages rattachés, un pan de plafond accepté et un sol. Ces éléments étaient présents dans le modèle ; l’ancien rendu ne perçait pas les murs et ne montrait le plafond qu’en contours. Cela ne prouve pas que toutes les ouvertures physiques ont été détectées.

Le rendu dérivé du modèle possède maintenant :

- murs évidés suivant leurs ouvertures, y compris sous pente et en cas de chevauchement ;
- épaisseur de présentation (10 cm si absente, bornée pour l’affichage), sans modification de la mesure métier ;
- sol rempli suivant son contour et plafond masqué, transparent ou plein ;
- vues perspective/dessus, recentrage et sélection des murs à travers le plafond transparent ;
- éclairage et couleurs de maquette, sans prétendre restituer textures ou mobilier.

Les surfaces en L sont triangulées suivant leur contour concave, pas une boîte englobante. La reconstruction du plafond, ses seuils, le schéma et les rattachements RoomPlan ne sont pas modifiés. Les trémies/fenêtres de toit ne sont toujours pas automatiquement déduites.

`Tests/PlaquistoRenderingChecks.swift` compare l’aire des triangles de mur évidé à la surface nette : porte, fenêtre, chevauchement, ouverture totale, ouverture coupée par un rampant, contours concaves/inversés/inclinés. Tests réussis aussi sur le JSON réel des 13 murs récupéré pour diagnostic (conservé hors dépôt dans un dossier temporaire). Les anciennes suites restent passantes.

Affichage contrôlé dans l’application autonome du simulateur sur ce JSON réel ; masquage/plafond plein et vue de dessus actionnés et vérifiés visuellement. Compilation simulateur et compilation iPhone signée réussies sur les dernières sources.

Cette section remplace les mentions historiques ci-dessous disant que les ouvertures ne sont pas évidées visuellement.

Version maquette installée sur l’iPhone 16 Pro d’Edouard le 12 septembre à 21:16. Le test utilisateur peut se faire depuis la pièce sauvegardée, sans nouvelle capture.

## Ce qui change

**Scanner → Pièce Plaquisto → Ouvrir la pièce sauvegardée** ouvre désormais un écran autonome, `PlaquistoSavedRoomView`. Il lit le fichier Plaquisto directement ; il n’utilise ni `ScannerDebugModel`, ni un résultat RoomPlan en mémoire. Le bouton **Recharger** relit le disque et recrée l’éditeur. En l’absence de sauvegarde, on peut importer un JSON Plaquisto sans scanner. Les erreurs de chargement ne sont plus silencieusement assimilées à une absence de pièce.

Le scanner ne fait plus que sauvegarder le document à la fin d’une acquisition. La lecture et les corrections ne passent plus par son contrôleur.

La fiche mur affiche maintenant :

- UUID Plaquisto sélectionnable/copiable, indépendant de l’ID fournisseur ;
- longueur effective, hauteur minimale/maximale du profil, surfaces brute/nette et déduction ;
- valeur brute, valeur effective, origine, validation et confiance éventuelle pour longueur/hauteur ;
- origine et validation des portions du profil haut : plafond accepté, mesure de mur ou correction manuelle ;
- ouvertures rattachées, leur type générique, dimensions, origine et état de validation.

Les corrections de longueur et hauteur restent prioritaires et enregistrées avant confirmation. Le traitement de priorité a été centralisé dans `RoomMeasurement.preservingCorrection(from:)`, utilisé effectivement par `RoomPlanAdapter` et couvert par les tests sans SDK. Il s’applique aussi aux dimensions des ouvertures et à l’épaisseur éventuelle. Les mises à jour d’une même acquisition ne suppriment pas une correction. La fusion entre deux rescans distincts reste hors périmètre.

Le découpage sous pans acceptés est conservé : rectangle, rampant, pignon. Aucun changement au moteur de reconstruction des plafonds ni à ses seuils. Une hauteur manuelle reste une **hauteur uniforme** qui remplace le profil, avec avertissement dans l’interface et possibilité de retour au profil.

## Préparation métier minimale

`WallWorkIntent` représente un futur choix explicite (doublage, cloison, mur existant, zone non traitée), rattaché par UUID. Les intentions sont un champ optionnel du document, séparé de la géométrie. Les fichiers v1 précédents restent lisibles.

Aucune interface de création d’intention, aucun ouvrage, aucun quantitatif automatique. Le test vérifie qu’une intention ne modifie pas la géométrie. Le futur parcours devra demander validation humaine puis choix métier avant création d’ouvrage.

## Preuve effectivement exécutée

### Processus indépendants, sans SDK d’acquisition

`Tests/RoomModelIndependenceChecks.swift` compile avec seulement :

- `PlaquistoRoomModel.swift` ;
- `PlaquistoWallGeometry.swift`.

Un premier processus construit une pièce **synthétique**, corrige les dimensions de 4,28 m à 4,31 m et de 2,50 m à 2,60 m, puis sauvegarde le document.

Un second processus relit uniquement le JSON, vérifie les mêmes UUID, les valeurs initiales préservées, les corrections prioritaires et les surfaces calculées. Aucun objet CapturedRoom ni donnée de mesh n’est disponible dans ces exécutables.

Cas vérifiés : rectangle, porte seule, fenêtre seule, types d’ouvertures génériques, surfaces brute/nette, un rampant, pignon à deux pans, nouvelle valeur brute sans perte de correction après rechargement, sérialisation et intention métier isolée.

### Affichage sans RoomPlan

`Tests/RoomModelViewerSmoke.swift` est une petite application de test séparée (bundle `fr.plaquisto.roommodelproof`), compilée avec les deux fichiers précédents et **l’éditeur de production** `PlaquistoRoomEditor.swift`.

Elle ne compile ni scanner, ni adaptateur, ni moteur de plafond. Les bibliothèques directement liées ont été contrôlées : pas de RoomPlan ou ARKit. Elle utilise SceneKit/SwiftUI pour afficher le modèle neutre.

Exécutée sur le simulateur iPhone 17 Pro : pièce affichée, mur sélectionné automatiquement, UUID, longueur 4,31 m, hauteur 2,60 m et origine manuelle visibles. L’application a été terminée puis relancée ; l’affichage est revenu depuis la sauvegarde du conteneur. Le programme indépendant a également relu ce fichier du simulateur et ses assertions passent.

Cette preuve utilise une pièce synthétique, pas un scan LiDAR réel. Les interactions tactiles de correction/sélection restent à valider sur appareil.

### Rejouer

Depuis la racine du dépôt :

```sh
bash Tests/run-room-model-proof.sh
# Pour compiler et afficher aussi l’application autonome, fournir un simulateur déjà démarré :
bash Tests/run-room-model-proof.sh UUID_DU_SIMULATEUR
```

Le script crée un dossier temporaire dédié et affiche son chemin. L’application de preuve conserve sa sauvegarde entre lancements ; une réinstallation ne la remet pas à zéro.

## Autres validations

- Suite existante `ScannerCeilingReconstructionChecks` : réussie.
- Suite `PlaquistoRoomModelChecks` (JSON, pignons, trous/union d’ouvertures, pont L/deux pans) : réussie.
- Compilation de l’application principale pour simulateur : réussie.
- Compilation de l’application principale pour iPhone, avec signature : réussie.
- Mise à jour : nouvelle version installée sur l’iPhone 16 Pro d’Edouard le 12 septembre à 14:10, après compilation signée réussie. Validation terrain encore à faire.

## Limites assumées / prochain test iPhone

Le prototype garde la dernière pièce sauvegardée, pas encore une bibliothèque par chantier. Les ouvertures sont dessinées en contours bleus, pas évidées visuellement ; elles sont déduites du calcul net. La surface nette n’est pas une règle de fournitures. Corriger une longueur n’ajuste pas automatiquement les murs voisins.

Décision confirmée avec Edouard : **un plafond validé par scan pour le moment**, éventuellement composé de plusieurs pans. Plusieurs pans d’un même plafond ne signifient pas plusieurs plafonds/zones simultanés. Le multi-plafonds est différé, de même qu’Android et l’éditeur web.

Test réel restant : scanner une pièce avec porte/fenêtre, ouvrir la sauvegarde, sélectionner un mur, corriger et valider, fermer complètement l’app, rouvrir la pièce **sans lancer un scan**, comparer UUID/dimensions/surfaces ; répéter avec un rampant et un pignon. Les validations terrain antérieures du moteur ne remplacent pas ce contrôle du parcours refactorisé.
