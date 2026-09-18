# Audit préalable de la migration Projet → Pièce → Ouvrage → Composant

Date : 18 septembre 2026. Dépôt : `Plaquisto-ios`, branche `codex/tools-lab-improvements`.

## Changement de périmètre validé après l'audit

L'utilisateur autorise à supprimer les anciennes sauvegardes de test. La migration patrimoniale décrite dans cet audit est donc abandonnée : pas d'inférence des pièces historiques, pas de reconstitution des composants depuis une surface totale, pas de maintien obligatoire des anciens champs pour ces sauvegardes. La nouvelle architecture peut démarrer sur un stockage vierge, versionné et validé. Le code et les référentiels restent conservés. Les règles de copie des identifiants, d'intégrité et d'imputation comptable restent applicables aux nouveaux projets.

Le doublage total reste l'ouvrage ; chacun de ses murs est un composant d'ouvrage. Pour une cloison, toutes les fournitures sont imputées à la pièce propriétaire ; l'autre pièce fournit un lien de consultation.

Document de décision complémentaire à `ARCHITECTURE_DONNEES_PROJETS_SCAN_CALEPINAGE_QUANTITATIFS.md`. L'audit porte sur le code de travail, comprenant des modifications non commitées. Aucun état sauvegardé sur téléphone n'a été migré lors de cet audit.

## 1. Inventaire vérifié et conflits de termes

| Existant / fichier | Cible | Action retenue |
|---|---|---|
| `ProjectItem`, `WorkModels.swift` | Projet métier | Conserver le type et ses UUID ; ajouter progressivement des collections typées et une version persistée. |
| `ProjectStore`, `ProjectStore.swift` | Point d'entrée des écritures du projet | Conserver les formulaires et les méthodes existants ; ajouter des transactions de migration et de résolution par UUID. |
| `PlaquistoRoomModel`, `PlaquistoRoomModel.swift` | Observation géométrique d'une pièce | Conserver le document de scan ; créer une pièce métier `RoomRecord` distincte. |
| `WorkItem.inferredRoomName` | Indice de migration | Ne plus l'utiliser comme identité de pièce après attribution explicite de `roomID`. |
| `WorkItem` | Ouvrage | Conserver `payload`, les calculateurs et les clés historiques. |
| `FixingComponent`, `VaporBarrierComponent` | Éléments locaux de configuration | Aucun renommage nécessaire ; nouveau type métier `WorkComponentRecord`. |
| `Surface2D` | Projection géométrique d'un composant | Réutiliser le moteur ; marquer les projections par leur révision source. |
| `LayoutDocument`, `SavedLayoutDocument` | Contenu du plan / entrée de bibliothèque | Introduire `LayoutPlanRecord`, avec lien explicite vers le composant ; une bibliothèque autonome reste possible. |
| `PlaquistoOpening`, `LayoutOpening`, `OpeningInput` | Observation / projection / paramètres de calcul | Relier à une identité d'ouverture canonique ; ne pas fusionner sur les seules dimensions. |
| `WorkType.openings`, `sourceWorkID` | Ouvrage auxiliaire de fournitures d'ouvertures | Conserver dans la première migration, avec références aux ouvertures canoniques. |
| `faceAFirst`, `faceBFirst`, etc. | Paramètres des deux côtés d'une cloison | Conserver les clés Codable ; créer des contextes `Côté Bureau`, `Côté Salon` pour les plans. |
| `BeforeAfterProject`, `BeforeAfterModels.swift` | Montage photo autonome | Ne pas confondre avec le Projet métier : le montage est une ressource éventuellement attachée au Projet, pas son parent. |
| `Chantier` dans les écrans | Projet | Remplacer les libellés du dossier ; garder « sur chantier » dans les conseils pratiques. |

Fichiers d'intégration principaux : `ProjectsView.swift`, `CombinedQuantityView.swift`, `LayoutExportForm.swift`, `LayoutEditorModel.swift`, `SheetLayoutEngine.swift`, `RoomPlanAdapter.swift`, `PlaquistoRoomEditor.swift`, `OpeningModels.swift`, `ProjectStoreTests.swift`.

## 2. Constats qui modifient les exemples de la spécification

### Une surface totale ne définit pas quatre murs

Les configurations actuelles peuvent ne contenir que `enteredSurface`, une hauteur et éventuellement `wallCount`. Elles ne fournissent pas nécessairement les longueurs individuelles, les angles ou les positions d'ouvertures.

La migration doit donc autoriser un ouvrage **à détailler**, sans composant géométrique inventé. Un composant peut être créé avec une géométrie inconnue explicitement représentée, mais ne doit pas s'appeler « Mur A » avec un rectangle fictif. Le quantitatif historique de l'ouvrage reste disponible. Ses contributions ne sont pas réparties arbitrairement entre composants.

### Une surface détectée n'est pas automatiquement un ouvrage à construire

`WallWorkIntent` distingue déjà doublage, cloison, mur existant et surface non traitée. Une capture peut créer une pièce et des observations ; l'affectation métier doit utiliser cette intention. Un mur existant ne doit pas devenir automatiquement une cloison neuve à quantifier.

### Noms de pièces ambigus

`inferredRoomName` renvoie le nom entier lorsqu'il ne trouve pas ` - `. Un ancien ouvrage appelé « Plafond séjour » n'est donc pas une preuve d'existence d'une pièce appelée « Plafond séjour ».

Migration proposée : extraire seulement un préfixe reconnu devant un suffixe de type d'ouvrage connu ; présenter les candidats et conserver les cas incertains « À rattacher à une pièce ». Deux pièces homonymes restent possibles et possèdent des UUID distincts.

### Double comptage des cloisons

La spécification prévoit à la fois l'agrégation des ouvrages propriétaires et l'affichage des contributions d'un côté dans la pièce liée. Additionner ces deux vues compterait certains parements deux fois. Il faut une règle unique d'imputation, distincte de la visibilité : chaque contribution appartient à exactement une pièce comptable, même lorsqu'elle apparaît en information dans plusieurs pièces.

**Décision métier confirmée par l'utilisateur le 18 septembre : tout imputer à la pièce propriétaire.** Bureau porte donc toutes les fournitures de la cloison, y compris les parements des deux côtés. Salon affiche un lien informatif ; aucune contribution de cette cloison n'entre dans son total. L'appartenance physique d'un côté et son imputation comptable sont distinctes.

### Corrections locales du contour

La proposition « appliquer uniquement à ce plan » exige une variante géométrique identifiée. Elle ne doit pas créer silencieusement un contour contradictoire avec le composant. Première version recommandée : une modification validée de géométrie met à jour le composant et invalide ses plans dépendants ; les variantes indépendantes attendent un modèle explicite de variantes.

### Quantitatif exact : attention au sens du mot

Un plan fournit des métrés géométriques calculés, pas une certification complète de tous les besoins de fournitures. Le nombre de plaques et les mètres posés ne remplacent pas automatiquement pertes, conditionnement, fixations ou prescriptions métier. L'agrégateur conserve la provenance et choisit une seule contribution active pour un même poste.

## 3. Réponses techniques aux sept points de décision

| Point | Choix retenu pour la première migration | Compatibilité / risque | Vérification prévue |
|---|---|---|---|
| Racine | Conserver `ProjectItem`, enrichi de collections normalisées ; enveloppe de stockage versionnée autour de la liste des projets. | Évite de changer tous les formulaires ; lecture du tableau JSON historique maintenue. | Fixtures tableau ancien et enveloppe nouvelle, égalité des UUID et payloads. |
| Composant | `WorkComponentRecord` | Aucun symbole concurrent repéré dans le code inspecté ; geometry optionnelle/état inconnu nécessaire pour les anciens agrégats. | Références vers ouvrage/projet et géométrie inconnue. |
| Côtés de cloison | `ComponentTreatmentContext`, avec pièce visible et orientation locale | Les clés `faceA...` restent lues ; l'UI utilise « Côté <Pièce> ». Une inversion de repère ne doit pas déplacer les prises physiquement. | Projection aller-retour, ouverture traversante unique et équipements propres à chaque côté. |
| Ouvrages ouvertures | Conserver l'ouvrage auxiliaire et ses formules | La fusion comptable dans l'ouvrage porteur sera une évolution métier séparée. Les liens canoniques empêchent les doubles déductions. | Calcul historique inchangé, liens vers porteur/copieur, déduction unique. |
| Médias | Fichiers relatifs dans le stockage applicatif, métadonnées dans le projet | Réutiliser les mécanismes locaux du montage photo si pertinents ; aucune dépendance à une URL absolue iOS. | Export/import, ressource absente, fichier partagé entre références. |
| Valeur quantitative retenue | Métier par défaut ; métrés du calepinage consultables séparément et remplaçables poste par poste explicitement | Les devis/snapshots restent immuables ; le géométrique ne s'ajoute pas à son estimation. | Un poste actif, révisions, unités, changement de catalogue. |
| Scan v1 | Importer un instantané portable identifié dans les ressources du projet, garder le fichier initial | Réimport du même document reconnu par identifiant ; rescan distinct n'écrase pas les corrections manuelles. | Import répété, nouvelles captures, conservation des valeurs manuelles. |

Ces choix n'exigent aucun changement des formules métier. Le stockage et les types proposés restent des décisions de conception ; ils ne sont pas encore déployés au moment de l'audit.

## 4. Graphe retenu et cardinalités

```text
Projet (ProjectItem)
 ├─ Pièces (RoomRecord)
 ├─ Ouvrages (WorkItem, ownerRoomID ; linkedRoomIDs en consultation)
 │   └─ Composants (WorkComponentRecord, workID)
 │       ├─ Géométrie effective + révision (ou état inconnu)
 │       ├─ Caractéristiques canoniques : ouvertures, électricité
 │       └─ Contextes de traitement
 │           └─ Plan courant + révisions (LayoutPlanRecord)
 ├─ Documents de scan → liaisons vers pièce/composant
 ├─ Médias et observations → cible par UUID
 └─ Contributions quantitatives → source + pièce d'imputation unique
```

- Une pièce appartient à un projet ; un ouvrage à une pièce propriétaire (rattachement temporairement absent si ancien cas ambigu).
- Un composant appartient à un ouvrage. Il peut être décrit par plusieurs observations de scan.
- Une observation peut contribuer à plusieurs composants si l'utilisateur découpe sa géométrie : la liaison doit alors porter la région concernée.
- Chaque contexte a au plus un plan courant ; l'ossature commune d'une cloison ne doit pas être dupliquée par les deux plans.
- Une ouverture traversante peut être projetée des deux côtés avec un seul UUID. Une prise a un contexte/côté pour ne pas apparaître de l'autre côté.
- Plusieurs composants peuvent partager une même configuration d'ouvrage. Une configuration différente doit être explicitement traitée par un autre ouvrage ou une surcharge typée, jamais recopiée silencieusement.

## 5. Unités et conventions à conserver

Le scan actuel utilise des mètres et Y vertical. `Surface2DAdapter` convertit en millimètres ; les coordonnées 2D sont en millimètres et les surfaces moteur en mm². L'affichage des cotes utilise des centimètres. Plusieurs paramètres des formulaires sont en mètres, certains en mm ou cm (par exemple le plénum).

Chaque adaptateur doit convertir à sa frontière, avec noms et tests explicites. Ne pas interpréter tous les `Double` comme des mètres. Les rampants se développent dans leur plan réel, pas dans leur projection sur le sol. La surface au sol de la pièce, la surface développée des ouvrages et les surfaces de parements sont des mesures différentes.

## 6. Persistance, copie et retour arrière

Avant activation d'une nouvelle version de schéma :

1. Lire et conserver les octets du fichier historique.
2. Décoder dans un modèle de compatibilité ; produire candidats et problèmes sans réécrire le fichier.
3. Construire le graphe en mémoire, avec identifiants stables conservés ou attribués une fois.
4. Valider unicité et références, encoder, redécoder et comparer.
5. Sauvegarder le fichier historique avec nom versionné non écrasable.
6. Publier atomiquement le nouveau fichier ; seulement ensuite publier le nouvel état aux vues.

Après une erreur de chargement, interdire toute écriture qui remplacerait les données illisibles par une liste vide. Le `ProjectStore` actuel expose l'erreur mais ne verrouille pas cette situation : ce point doit être traité avec la migration.

Une copie de projet doit construire une table `ancien UUID → nouvel UUID` pour ouvrages, pièces, composants, plans et caractéristiques. **Constat dans `duplicateProject` :** les ouvrages reçoivent actuellement de nouveaux UUID, mais leur `payload` est copié tel quel, y compris le `sourceWorkID` des ouvertures. Ajouter un test couvrant une copie comprenant doublage et ouvertures avant de faire évoluer cette fonction.

Retour arrière : restaurer une sauvegarde vers un fichier distinct après validation, puis basculer explicitement vers ce fichier. Ne jamais relancer une ancienne application sur le nouveau schéma en espérant qu'elle le réécrive correctement. Les données ajoutées après migration doivent être conservées dans le fichier nouveau pour récupération.

## 7. Quantitatifs : conservation des formules et provenance

`CombinedQuantityCalculator` utilise à la fois des snapshots de certaines configurations et des calculs avec le catalogue courant pour d'autres. Une provenance doit indiquer le mode et, si connu, la version catalogue. Ne pas présenter un snapshot ancien comme un calcul fraîchement validé.

Les quantités regroupées actuelles ne permettent pas toujours d'identifier le côté ou le composant. Ne pas distribuer proportionnellement les rails, fixations ou pertes : les règles dépendent notamment des extrémités et des arrondis. Garder la contribution au niveau ouvrage tant que le calculateur n'a pas émis une vraie ventilation.

Prévoir un identifiant de contribution stable par source/poste/contexte/règle, une clé produit comprenant le format et les caractéristiques utiles, une unité et une pièce d'imputation. Le résultat d'une union de périmètres doit dédupliquer les contributions, et non additionner leurs totaux préagrégés.

## 8. Ordre d'intégration et critères de passage

1. Libellés Projet et documentation de décision : compilation iOS + Lab.
2. Persistance versionnée et sauvegardes : lecture historique, idempotence, échec d'écriture et refus de version future.
3. Pièces et rattachement explicite : création, renommage, réaffectation et cas ambigus. Les noms ne servent plus de clé.
4. Composants et plans : déplacer le calepinage historique sans perdre sa bibliothèque ; lecture seule de l'ancien champ puis adaptateur calculé.
5. Scans : import répétable, association, ouverture du plan depuis sélection 3D ; vérifier le repère de chaque côté et rampant.
6. Caractéristiques et quantités : identité partagée, invalidation par dépendance, rattachement comptable validé, détails des sources.
7. Navigation complète et médias : routes par UUID, sauvegarde unique, retour au bon contexte, captures et observations ciblées.

Le schéma complet ne doit pas être publié avant que les parcours de création, modification, duplication et suppression sachent conserver toutes ses relations. L'existence des structs seules ne valide pas la migration.

## 9. État de cette livraison d'audit

- Audit source et propositions techniques : rédigés.
- Répartition des quantitatifs de cloisons : confirmée, entièrement dans la pièce propriétaire.
- Libellés Projet : modification indépendante prévue dans cette phase.
- Migration persistée, composants, scans reliés et nouvelles vues : à implémenter dans les phases suivantes ; aucune disponibilité n'est annoncée à ce stade.
- Les fichiers existants et modifications non commitées sont conservés.
