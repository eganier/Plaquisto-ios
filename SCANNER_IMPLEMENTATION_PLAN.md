# Scanner LiDAR — plan d’intégration Plaquisto

## Prototype deux pans — 11 septembre

`Surface` contient désormais une liste de `Pan` (triangles, surface réelle, pente, support observé, erreur d'ajustement). Le rendu conserve les pans dans le même repère et le bilan détaille leurs surfaces/pentes. Cette structure est extensible ; la détection de trois/quatre pans et les formulaires d'ouvrages ne sont pas implémentés.

Premier cas supporté : deux pentes opposées (au moins 5° chacune), chacune représentant au moins 20 % des observations, couvrant ensemble au moins 85 %. Leur jonction coupe le contour triangulé, conservant les retraits concaves sans chevauchement. Les observations doivent soutenir le côté choisi (faîtage, pas une noue). Les deux pans sont proposés en jaune puis figés ensemble à la validation. Les ouvertures restent non déduites. Le seuil de support live est divisé par le pas d'échantillonnage ; surfaces rendues, ratios et seuil final restent inchangés. Cette approximation est renseignée dans le diagnostic.

Tests synthétiques : symétrie, pentes inégales, trou de maillage, normales/ordre inversés, translation monde, contour concave, échantillonnage live et rejet d'un troisième plan substantiel. Les anciens tests rectangle/L/couloir, niveaux multiples et absence de données restent requis. Le JSON utilisateur ne contient pas le maillage : validation réelle à effectuer sur iPhone, sans garantie de reconnaissance automatique de la fenêtre de toit.

## Diagnostic des refus — 11 septembre, après le scan de 19 h 38

Instrumentation sans modification des seuils ni de la sélection des surfaces : chaque calcul du plan expose son étape de sortie (contour, échantillons insuffisants, support insuffisant, ratio inférieur à 70 %, ajustement dégénéré, résidu supérieur à 4 cm, pente supérieure à 65°, succès), les nombres de triangles et surfaces retenues, ratio, résidu et pente lorsqu'ils sont calculés.

L'export du contour conserve ses champs existants et ajoute une version de diagnostic, les 120 dernières tentatives live (avec compteur des tentatives supprimées), position relative caméra, nombre de murs/faces, pas d'échantillonnage, seuil de hauteur, propositions disponibles/écartées et résultats de chaque candidat. Les validations/refus utilisateur et le chemin final (surface validée ou recalcul global) sont distincts. Le dernier motif live est affiché pendant et après le scan. Ces traces restent en mémoire et ne contiennent ni image, ni mesh brut ; elles ne permettent pas une reproduction complète des données LiDAR. Aucun nouveau scan n'est requis tant que la version n'est pas installée.

## Correctif du 11 septembre — contour local avec ramifications

Le diagnostic `texte-D3A16DEE4EF7-1.txt` contient un contour principal et des retours annexes : la reconstruction globale refuse cet ensemble. En cas d'échec du contour, les propositions recherchent maintenant d'abord une face fermée observée contenant la caméra, sur les murs bruts (intersections découpées, branches mortes élaguées). Cette sélection reste jaune et nécessite validation ; le contrôle strict de reconstruction et le verrouillage après validation sont inchangés. Les propositions cuisine/couloir restent prioritaires.

Régression ajoutée dans `Tests/Fixtures/sloped-room-branches-20260911.json` : contour retrouvé pour plusieurs positions dans la pièce et ordre des murs inversé. Un mesh incliné synthétique vérifie la reconstruction ; le diagnostic ne contient pas le mesh réel et ne permet donc pas de valider la capture complète hors appareil. Tests supplémentaires : branche intérieure, L concave avec branche et pièce voisine détachée, caméra hors contour. Aucun changement aux calculs métier ni à la cadence de capture.

Date : 10 septembre 2026. Statut : proposition d’architecture fondée sur l’audit du dépôt, pas une implémentation.

Référence fonctionnelle : `PLAQUISTO_SCANNER_LIDAR_copier collé gptmd.md`, document utilisateur de 3 191 lignes. Ce document exprime la cible produit ; ses propositions techniques ne constituent pas une preuve de faisabilité sur appareil.

## 1. Décision et périmètre

Ajouter un module Scanner isolé, accessible depuis l’onglet existant et depuis un chantier. Il produit un relevé vérifiable et corrigible, puis un **préremplissage géométrique** d’un formulaire existant. Il ne produit pas un nouveau moteur de fournitures.

Conserver les formulaires, leurs validations, les catalogues Admin et leurs calculs. Ne migrer ni les chantiers ni les ouvrages vers SwiftData à cette occasion. Commencer par un prototype de capture sur iPhone avant le développement de l’éditeur complet.

Cette intervention crée uniquement ce plan : aucun modèle, formulaire, stockage, paramétrage Xcode ou comportement de production n’est modifié.

## 2. État réel du projet

Les chemins ci-dessous sont relatifs à la racine du dépôt.

| Sujet | Constat vérifié | Conséquence pour le Scanner |
| --- | --- | --- |
| Plateforme | `Plaquisto/Plaquisto.xcodeproj/project.pbxproj` : iOS 17.0, Swift 5.0, iPhone, cibles `Plaquisto`, `Plaquisto Lab`, `PlaquistoTests`. | Maintenir iOS 17. Tester les API et capacités à l’exécution. |
| SwiftData | Aucun `@Model`, `ModelContainer` ou import SwiftData dans les sources actuelles. | Les « modèles SwiftData existants » mentionnés dans le prompt n’existent pas. |
| Chantiers | `Plaquisto/PlaquistoCore/Models/WorkModels.swift` : `ProjectItem`, structure Codable avec UUID, informations chantier et tableau d’ouvrages. | Référencer le chantier par son UUID, sans relation SwiftData vers `ProjectItem`. |
| Persistance | `Plaquisto/Plaquisto/ProjectStore.swift` : `@MainActor ObservableObject`, fichier Application Support/Plaquisto/projects.json, écritures atomiques, dates ISO8601. | Préserver le fichier et son décodage ; un échec Scanner ne doit pas empêcher l’accès aux chantiers. |
| Ouvrages | `WorkItem`, `WorkType` et `WorkConfiguration` Codable ; huit types ; payload typé ; décodage de formats historiques. | Ne pas changer les identifiants de types ni le format des configurations pour brancher la capture. |
| Navigation | `Plaquisto/Plaquisto/PlaquistoApp.swift` : quatre onglets ; Scanner est un écran d’attente. `ProjectsView.swift` contient les écrans chantier et le routage des huit formulaires. | Remplacer seulement l’écran d’attente ; conserver l’accès au compte et les parcours manuels. |
| Création / réouverture | `NewWorkView` → `WorkConfiguratorContainer` ; `SavedWorkView` réouvre un ouvrage. Les formulaires acceptent déjà `initialConfiguration` et `startsAtResult`. | Ajouter un préremplissage optionnel au parcours de création, avec `startsAtResult: false`. |
| Quantitatifs | `CombinedQuantityView.swift` recalcule le plafond sur fourrures et agrège les quantités sauvegardées des autres ouvrages. Plusieurs calculs résident encore dans les vues configurateurs. | Ne pas injecter directement des quantités ou modifier une configuration sauvegardée sans repasser par son formulaire. |
| Référentiels | Services `PlaquistoCore/References`, plus le store du plafond rails/montants dans son configurateur ; endpoint Admin `/api/ios/catalogue`. | Le Scanner ne copie pas ces catalogues et n’introduit pas d’API Admin. |
| Cache constaté | `CeilingReferenceService.swift` et `DoublageReferenceService.swift` écrivent dans UserDefaults et ont un secours sur cache. | Écart à l’intention « sans stockage local du catalogue », à traiter séparément ; ne pas prétendre que tout est déjà exclusivement réseau. |
| Tests | `PlaquistoTests/ProjectStoreTests.swift` couvre notamment persistance, anciens formats, noms, duplication, agrégation et certains calculs d’ossature. | Conserver ces tests et ajouter des tests Scanner séparés. |
| Organisation | `PlaquistoCore` est un dossier de sources, pas un package Swift autonome ; les appartenances aux cibles sont explicites dans le pbxproj. Le Lab ouvre actuellement le plafond rails/montants. | Ajouter les fichiers progressivement aux bonnes cibles. Aucun nettoyage Lab dans cet audit. |

`README.md` et `Plaquisto/ARCHITECTURE.md` ne décrivent plus tous les ouvrages actuels : le code est la référence de cet audit. Leur actualisation sera distincte de l’intégration Scanner.

## 3. Architecture retenue

```text
Capture RoomPlan + collecte ARKit (session commune à valider)
    → données brutes immuables
    → import / extraction des surfaces
    → géométrie normalisée puis révisions corrigées
    → même document pour 3D, 2D et liste de surfaces
    → sélection et validation des mesures
    → ScanToWorkPrefillAdapter
    → formulaire existant → ProjectStore → quantitatif existant
```

### Frontières

- `PlaquistoScanner` : domaine géométrique, acquisition, stockage et visualisation du relevé. Aucune règle de parements, portée, entraxe, isolant, chute ou fourniture.
- `Plaquisto/ScannerIntegration` : accès aux chantiers, navigation, conversion explicite des mesures vers les configurations actuelles.
- `PlaquistoCore` : moteur et formulaires existants, inchangés dans leurs règles. Seuls les paramètres d’entrée du parcours de création seront raccordés ultérieurement.
- Données en mètres et m² ; valeurs conservées en précision complète ; arrondi uniquement à l’affichage. Le Scanner ne déduit jamais une épaisseur ou une nature de support à partir de l’apparence d’un mur.
- États observables `@MainActor` pour l’interface, services injectables et calculs géométriques purs. Traitements lourds hors thread UI avec copies de données ; ne pas transporter de `ModelContext` ou de buffers ARKit vivants entre acteurs.

### Modèle géométrique unique

Trois niveaux distincts : capture Apple brute, interprétation initiale, géométrie retenue après corrections. Conserver la provenance et les différences ; ne jamais écraser le brut avec une correction.

Chaque surface possède un UUID Plaquisto stable, une catégorie (mur, sol, plafond horizontal, rampant, autre), un repère local plan, un contour polygonal, une transformation vers le repère de la pièce, une normale et un état de validation. Les UUID Apple sont des références de provenance, pas les identités métier durables après fusion ou découpage.

Le repère est en mètres, Y vertical ; préciser pour chaque import le sens des axes et le passage local/monde. Les repères de scans indépendants ne sont pas supposés alignés.

Une ouverture possède un parent, un contour dans le plan de ce parent et une catégorie (porte, fenêtre, passage, fenêtre de toit, trémie…). Les objets restent distincts et ne sont pas soustraits automatiquement des surfaces. Les tableaux de plafonds sont natifs : ne pas réduire tous les plafonds à un seul rectangle.

Calculer séparément surface brute, union des ouvertures découpées au contour, surface nette, périmètre, hauteurs et surface projetée. La surface d’un rampant est celle de son plan incliné, pas sa projection au sol. Une hauteur moyenne ne remplace pas une hauteur maximale pour une vérification mécanique.

Un plafond inféré à partir des murs est marqué « estimé, à vérifier », jamais « mesuré ». Les corrections de dimensions doivent modifier la géométrie retenue et ses mesures dérivées ensemble, pas seulement une étiquette.

## 4. Modèles et fichiers à créer progressivement

Racine proposée : `Plaquisto/PlaquistoScanner/`. Les noms sont des fichiers prévus, pas des fichiers déjà présents.

| Dossier / fichiers | Responsabilité |
| --- | --- |
| `Domain/ScanDocument.swift` | Structures Codable indépendantes d’Apple : pièce, surfaces, ouvertures, objets, provenance, revisionID, version du format. |
| `Domain/ScanGeometry.swift` | Points 2D/3D, transformations sérialisables, contours, repères et mesures. |
| `Domain/GeometrySelection.swift` | IDs sélectionnés, révision source, mesures retenues et instantané immuable destiné au préremplissage. |
| `Domain/ScanValidationIssue.swift` | Erreurs bloquantes, avertissements et états « détecté / estimé / corrigé / validé ». |
| `Geometry/RoomPlanImporter.swift` | Conversion de CapturedRoom ; prise en compte des contours et parents disponibles ; repli rectangle explicitement marqué si nécessaire. |
| `Geometry/CeilingSurfaceExtractor.swift` | Extraction candidate des plafonds depuis le mesh : classement, regroupement, plans, contours, découpe ; aucun résultat présumé certain. |
| `Geometry/ScanGeometryCalculator.swift` | Surfaces, unions d’ouvertures, projection, longueurs ; aucune dépendance SwiftUI ou catalogue. |
| `Geometry/ScanGeometryValidator.swift` | Polygones invalides, auto-intersections, incohérences de parent, trous hors contour, surfaces insuffisamment observées. |
| `Editing/ScanEditCommand.swift` | Commandes de correction avec annuler/rétablir, contrôle de cohérence et création de révisions. |
| `Capture/ScannerCapabilities.swift` | Compatibilité matérielle, autorisation caméra, états indisponibles, simulateur. |
| `Capture/ScanCaptureCoordinator.swift` | Cycle capture/arrêt/traitement/annulation, session AR commune, callbacks RoomPlan, interruptions et erreurs. |
| `Capture/ARMeshCollector.swift` | Copies bornées des sommets/faces/classifications/transforms, mise à jour et suppression des ancres par ID. |
| `Persistence/ScanPersistenceModels.swift` | Modèles SwiftData d’index : `ScanStructureRecord`, `ScanRoomRecord`, `ScanRevisionRecord`, `ScanAssetRecord`, `ScanWorkLinkRecord`. |
| `Persistence/ScanSchema.swift` | VersionedSchema V1 et point d’entrée du futur plan de migration. |
| `Persistence/ScanRepository.swift` | Protocole injectable pour charger, sauvegarder, réviser, lier, détacher et supprimer un relevé. |
| `Persistence/SwiftDataScanRepository.swift` | Implémentation, contexte isolé, erreurs explicites, transactions internes au store Scanner. |
| `Persistence/ScanAssetStore.swift` | Fichiers immuables, staging, manifestes, vérification des fichiers et récupération après échec. |
| `State/ScannerStore.swift` | État du module, chargement et orchestration ; aucune copie des chantiers en source de vérité. |
| `State/ScanEditorState.swift` | Document retenu, sélection commune 2D/3D/liste, `RoomVisibilityState`, masque/isolation/réinitialisation. |
| `Views/ScannerHomeView.swift` | Relevés rattachés à des chantiers et entrée de capture. |
| `Views/ScanCaptureView.swift` | Pont UIViewRepresentable vers RoomCaptureView, guidage et fin/annulation. |
| `Views/ScanReviewView.swift` | Revue des résultats, avertissements, accès aux mesures et validation. |
| `Views/ScanSceneView.swift` | RealityKit, entités générées depuis le document retenu, correspondance entity ↔ surfaceID, sélection par toucher. |
| `Views/ScanPlanView.swift` | SwiftUI Canvas, projection 2D sol/plafond, cotations et sélection du même document. |
| `Views/ScanSurfaceListView.swift` | Liste accessible des surfaces, mesures, visibilité et sélection. |
| `Views/ScanSurfaceEditorView.swift` | Corrections manuelles ; commencer par dimensions puis contours et rampants. |

Les modèles SwiftData restent des index : structure liée à `projectID`, pièce liée à sa structure, révision liée à sa pièce, actifs liés à une révision. `ScanWorkLinkRecord` contient `projectID`, `workID`, révision source, IDs des surfaces, instantané des mesures appliquées et statut du lien. Pas de relation SwiftData vers les structs ProjectItem/WorkItem.

Les surfaces détaillées sont dans le document Codable versionné référencé par la révision, pas dupliquées comme objets SwiftData et JSON modifiables indépendamment. Les index nécessaires peuvent être dénormalisés, mais le document de révision reste la source géométrique.

Fichiers d’intégration, dans `Plaquisto/Plaquisto/ScannerIntegration/` :

- `ScannerFeatureHost.swift` : initialisation récupérable du stockage Scanner, injection et écran d’indisponibilité sans bloquer les autres onglets.
- `ScannerNavigationCoordinator.swift` : routes par UUID chantier/relevé et présentation d’une création d’ouvrage ; pas d’objets ARKit dans les routes.
- `ScanToWorkPrefillAdapter.swift` : résultat typé compatible / à confirmer / non représentable, sans calcul de fournitures.
- `ScanWorkPrefillReviewView.swift` : choix explicite de l’ouvrage et validation des seules mesures applicables.
- `ScanWorkCreationCoordinator.swift` : liaison durable après sauvegarde de l’ouvrage, gestion des échecs et reprise.
- `ScanProjectLifecycleCoordinator.swift` : suppression et duplication cohérentes avec les IDs du ProjectStore.

Tests séparés dans `Plaquisto/PlaquistoTests/` : `ScanGeometryTests.swift`, `ScanImportTests.swift`, `ScanRepositoryTests.swift`, `ScanToWorkPrefillTests.swift`, `ScanProjectLifecycleTests.swift`. Jeux synthétiques anonymes dans `Fixtures/Scanner/`, jamais de relevés privés du domicile dans Git.

## 5. Stockage : ajouter sans migrer l’existant

SwiftData est réservé aux données Scanner, conformément au document de cadrage. Un `ModelContainer` propre au module est proposé, avec stockage local explicite et sans CloudKit. Sa création doit pouvoir échouer sans crash ni effacement automatique ; ne pas utiliser `try!` au démarrage de Plaquisto. Voir la documentation Apple sur [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer).

Organisation proposée sous Application Support/Plaquisto/Scanner :

- `scanner.store` : index SwiftData, accompagné de ses fichiers techniques gérés par le framework.
- `Assets/<roomID>/<revisionID>/` : brut RoomPlan sérialisable, document normalisé/corrigé, mesh copié dans un format versionné, manifestes.
- `Staging/` : écritures incomplètes à reprendre ou nettoyer après vérification.
- Aperçus 2D/3D et USDZ : dérivés régénérables, dans un cache distinct. USDZ n’est pas le modèle éditable.

Conserver les données nécessaires au retraitement, pas un enregistrement vidéo permanent. Fixer un budget mémoire et disque pour le mesh, informer en cas d’espace insuffisant et ne pas supprimer silencieusement un brut utile. Prévoir protection des fichiers, politique de sauvegarde des actifs et suppression explicite. Aucun envoi des pièces, images ou mesh à Plaquisto Admin.

Écriture : créer les actifs en staging, vérifier le manifeste, déplacer vers un dossier final immuable, puis enregistrer la référence SwiftData. Un échec laisse une opération récupérable ; le nettoyage ne doit toucher que des actifs non référencés. Ne pas charger tous les mesh pour lister les relevés.

Il n’existe pas de transaction commune entre projects.json et SwiftData. Lors d’une création depuis un scan, préparer un journal Scanner avec l’UUID prévu de l’ouvrage ; faire accepter cet UUID par une entrée de sauvegarde du ProjectStore conservant ses validations ; sauvegarder l’ouvrage puis finaliser le lien. Une reprise utilise cet UUID et ne recrée pas l’ouvrage. Cette évolution de signature est à réaliser seulement lors du raccordement et à tester sans changer les appels manuels.

Politique proposée pour le cycle de vie :

- Modification du relevé : nouvelle révision, jamais de recalcul automatique d’un ouvrage sauvegardé.
- Mise à jour d’un ouvrage depuis le scan : aperçu des écarts, confirmation, retour dans le formulaire ; conserver l’ancienne référence jusqu’au succès de la sauvegarde.
- Suppression d’un scan : les ouvrages restent utilisables avec leur configuration ; lien détaché et suppression des actifs après confirmation.
- Suppression d’un ouvrage : suppression du lien, conservation du relevé.
- Suppression du chantier : confirmation incluant ses relevés ; opération journalisée, nettoyage Scanner après succès côté ProjectStore. Pas de suppression de scan sur un simple échec de chargement du JSON.
- Duplication d’un ouvrage : conserver l’instantané source avec un nouveau lien vers le nouvel UUID, sans partager un état de configuration mutable.
- Duplication du chantier : conserver le comportement actuel pour les ouvrages ; ne pas copier les relevés lourds par défaut, copies d’ouvrages détachées de la source. Indiquer cette politique à l’utilisateur avant validation ; ajouter une copie explicite des scans plus tard si souhaité.

## 6. Capture : premier verrou technique à lever

Apple documente la possibilité d’utiliser une ARSession personnalisée avec RoomPlan à partir d’iOS 17. Cela rend l’architecture compatible avec la cible actuelle, mais ne valide pas encore notre collecte simultanée sur appareil. Source : [WWDC23 — Explore enhancements to RoomPlan](https://developer.apple.com/videos/play/wwdc2023/10192/).

Prototype préalable, isolé du parcours de production :

1. Vérifier `RoomCaptureSession.isSupported`, le droit caméra et `ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)` ; ne pas déduire la compatibilité uniquement du nom de l’iPhone. [Contrôle de capacité ARKit](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:)).
2. Ajouter `NSCameraUsageDescription` aux seules cibles qui capturent. Aucun besoin de microphone ou photothèque pour la capture de base. L’app reste utilisable sur appareil non LiDAR.
3. Tester RoomPlan seul, puis collecte mesh seule, puis session commune : même origine, ancres reçues et mises à jour, classification exploitable, arrêt fiable. Vérifier la propriété des delegates ; ne pas remplacer un delegate nécessaire à RoomPlan à l’aveugle.
4. Copier et borner les données du mesh ; gérer les ancres supprimées, éviter de compter chaque mise à jour comme un nouveau morceau.
5. Tester permission refusée, interruption, verrouillage/arrière-plan, annulation, sortie de l’écran et plusieurs scans successifs. Une seule session active ; l’annulation ne crée pas un chantier ou ouvrage vide.
6. Examiner un plafond plat puis un rampant réel. La reconnaissance d’un rampant et son contour restent un traitement Plaquisto à valider, pas une garantie de classification Apple.

L’import peut exploiter `polygonCorners` et `parentIdentifier` quand les surfaces les fournissent ; leur présence et leur sens doivent être vérifiés dans les fixtures et l’API utilisée. [CapturedRoom.Surface](https://developer.apple.com/documentation/roomplan/capturedroom/surface).

Si la collecte commune est insuffisante, documenter les résultats et décider d’un passage complémentaire dans le même repère ou d’une saisie manuelle. Ne pas assembler deux scans indépendants comme s’ils étaient alignés. Ne pas engager l’éditeur complet avant ce verdict.

## 7. Intégration avec les formulaires existants

### Entrées UI

Dans `PlaquistoApp.swift`, remplacer le placeholder Scanner par `ScannerFeatureHost`, en conservant les quatre onglets et le bouton Compte. Depuis l’onglet Scanner, sélectionner un chantier existant ou passer par le parcours habituel de création de chantier avant l’enregistrement définitif.

Dans `ProjectsView.swift`, ajouter une section Relevés au détail du chantier. Le lien ouvre le même module avec `projectID`. Ne pas remanier toutes les NavigationStack ; un seul propriétaire présente le formulaire, pour éviter doubles boutons Fermer et empilements de feuilles.

Les vues de création sont actuellement `private` dans ce fichier. Extraire seulement l’hôte de création réutilisable, ou ajouter un point d’entrée interne étroit. Faire accepter à `WorkConfiguratorContainer` une configuration initiale optionnelle de type `WorkConfiguration`, puis la transmettre au bon formulaire/hôte existant. Sans préremplissage, comportement strictement identique aujourd’hui.

### Contrat de préremplissage

L’adaptateur reçoit un instantané validé, un type d’ouvrage et les choix de mesures confirmés. Il ne sauvegarde rien et ne touche ni aux références catalogue, ni aux quantités, ni aux parements. Construire la configuration depuis les valeurs par défaut existantes et n’appliquer que les champs géométriques autorisés.

| Famille / configuration actuelle | Préremplissage possible | Limite à respecter |
| --- | --- | --- |
| Plafond fourrures — `CeilingConfiguration` | `length`, `width`, `dimensionsSpecified`, `enteredArea`, `ceilingShape` si confirmé. | Rectangle dans le plan réel du plafond ; aucune bounding box d’une forme en L présentée comme dimensions exactes. |
| Plafond rails/montants — `RailStudCeilingConfiguration` | `length`, `width`, `dimensionsSpecified`, `area`, `shape`. | La portée dépend des dimensions : pas de conversion silencieuse d’un polygone en carré de même surface. Ne pas changer `direction` automatiquement. |
| Doublage rails/montants — `DoublageConfiguration` | `height`, `enteredLength`, `enteredSurface`, `geometryMode`, `wallCount` si pertinent. | Une seule HSP ; le calcul actuel répartit la longueur également entre les murs. Un total + nombre de murs ne reproduit pas les longueurs individuelles. |
| Doublage lisses/fourrures — `FurringLiningConfiguration` | Même principe : HSP, longueur/surface et nombre de murs. | Vérifier le découpage par mur pour le nombre de fourrures et les lignes d’appuis. |
| Complexe collé / parement collé — `BondedLiningConfiguration`, `AdhesiveFacingConfiguration` | Géométrie longueur/surface et HSP. | Pas de déduction automatique de tapée, de panneau ou d’isolant. |
| Cloison métallique / alvéolaire — `CloisonDistributionConfiguration`, `AlveolarPartitionConfiguration` | Longueur, HSP et surface d’un ouvrage explicitement choisi. | Une paroi scannée n’est pas nécessairement une cloison à créer ; pas de doublement de surface parce qu’il y a deux faces. |

Un mur rectangulaire à HSP constante et un plafond rectangulaire sont les premiers cas raccordables. Pour plusieurs murs de longueurs différentes, proposer un ouvrage par mur ou une estimation globale explicitement acceptée ; ne pas annoncer un métré exact avec la répartition uniforme actuelle.

Les murs sous rampant, formes non rectangulaires, plafonds à plusieurs plans ou sélections mixtes restent visibles et modifiables dans le Scanner. Le transfert exact est bloqué tant qu’ils ne sont pas représentables ; proposer découpage en ouvrages compatibles ou saisie manuelle vérifiée. Ne pas étendre ici les règles métier pour contourner cette limite.

### Ouvertures et surfaces nettes : frontière importante

Le Scanner affiche brut, ouvertures et net. Les formulaires utilisent aujourd’hui une surface qui peut également servir à reconstruire la longueur (`surface / HSP`) et à calculer l’ossature. **Ne pas envoyer le net à la place du brut pour un métré structurel** : cela raccourcirait artificiellement le mur.

Pour la première intégration, transmettre la géométrie brute validée et conserver le détail des ouvertures dans l’instantané du relevé. Une déduction différenciée entre parements, isolant, rails et montants nécessitera une décision métier distincte. Aucun changement implicite des coefficients existants.

Les valeurs préremplies restent modifiables dans le formulaire ; enregistrer dans le lien les valeurs réellement appliquées, pas uniquement celles du scan. Les noms automatiques et la détection des doublons restent ceux de ProjectStore.

## 8. Éditeur et visualisation

Construire la 3D depuis la géométrie retenue, pas depuis un USDZ figé ; la 2D et la liste utilisent les mêmes IDs et le même état de sélection. Masquer/isoler est un état d’affichage, pas une suppression ou une déduction de surface.

Prévoir une vue en plan du sol et une vue de plafond afin de sélectionner les pans qui se superposent en projection. Le mode tactile doit résoudre les surfaces cachées/occluses ; la liste fournit une alternative accessible. Une correction doit être répercutée dans les trois vues.

Commencer par la vérification des cotes et les corrections simples. Ajouter ensuite contours, trous, plafonds multiples et annuler/rétablir avec validation géométrique. Ne pas commencer simultanément une fusion multi-pièces, un éditeur complet de CAO et la génération des ouvrages.

## 9. Ordre de réalisation et critères de sortie

| Lot | Livrable | Validation avant de continuer |
| --- | --- | --- |
| 0 — audit | Ce plan ; aucun code Scanner créé. | Accord sur architecture et frontières. |
| 1 — faisabilité appareil | Petit parcours de capture isolé, résultat RoomPlan + mesh ; logs techniques non sensibles. | Session commune, permission, arrêt et extraction candidate d’un plafond plat vérifiés sur iPhone LiDAR. Compte rendu des rampants. |
| 2 — modèle et persistance | Documents versionnés, import, mesures pures, index SwiftData, actifs, fixtures. | Sauvegarde/relecture, échec disque, reprise et géométrie testés sans catalogue. |
| 3 — revue et correction | Vue 3D, liste, puis plan 2D, visibilité et correction simple. | Mesures et IDs cohérents entre vues ; distinction estimé/validé ; aucune modification d’ouvrage. |
| 4 — premier raccord | Mur rectangulaire vers un doublage existant, plafond rectangle vers un plafond existant. | Même configuration et mêmes quantités que la saisie manuelle ; annulation sans ouvrage parasite. |
| 5 — cycle complet | Liaison/révision, suppression, duplication, reprises ; extension aux autres types compatibles. | Relecture des anciens projets, erreurs partielles et liens testés. |
| 6 — géométries avancées | Rampants, plafonds multiples et contours complexes validés sur terrain. | Mesures comparées au laser ; transfert uniquement des cas représentables. |

Le Lot 1 peut utiliser le Lab comme banc de capture dédié après accord, sans dépendance de production vers le Lab. Le module et ses fixtures seront partagés par appartenance aux cibles, pas par copie de formulaires. L’éditeur et les écrans peuvent être testés au simulateur ; les performances et la capture LiDAR nécessitent l’iPhone.

## 10. Vérification et non-régression

- Avant toute modification exécutable : lancer les tests existants et compiler les deux cibles pour établir un état de référence ; enregistrer les erreurs préexistantes séparément.
- Géométrie : rectangle 4 × 3 = 12 m² ; ouverture 1 × 2 = 2 m² ; net 10 m² ; ouvertures chevauchantes sans double soustraction ; contours concaves ; transformations ; mesures inclinées/projetées distinctes ; NaN, dimensions nulles, polygones invalides.
- Import : contour absent, parent absent, ancres mises à jour/supprimées, surface estimée, identités conservées entre révisions. Un rescan n’est pas présumé conserver les UUID Apple.
- Persistance : aucun scan puis chargement normal de projets.json ; erreur SwiftData sans panne Chantiers ; actif manquant ; écriture interrompue ; révision précédente conservée ; création d’ouvrage interrompue sans doublon.
- Préremplissage : test par configuration ; champs non géométriques inchangés ; pas de net injecté dans la longueur de l’ossature ; surfaces incompatibles refusées ; modifications manuelles conservées.
- Régression : création, sauvegarde, réouverture, modification, suppression et duplication des huit ouvrages ; anciens JSON ; noms automatiques et uniques ; quantitatifs regroupés ; disponibilité/erreur Admin.
- UI : accès depuis Scanner et chantier ; retour/annulation ; un seul bouton Fermer ; formulaire manuel identique sans scan ; suppression du chantier alors qu’un relevé est ouvert.
- Appareil : comparaison au télémètre sur pièce rectangle, ouvertures, angle non droit, plafond plat, un rampant puis deux, zones mal éclairées/masquées. Définir les tolérances produit à partir des essais, sans promettre une précision millimétrique.
- Confidentialité : aucune géométrie privée, image, adresse ou mesh dans Git ou les logs ; aucune synchronisation distante nouvelle sans décision explicite.

## 11. Points à arbitrer au moment utile

Non bloquants pour le prototype : durée de conservation des bruts, export/partage du relevé, copie explicite des scans lors d’une duplication de chantier, tolérances acceptables au regard du télémètre.

Bloquants pour certaines intégrations seulement : traitement métier des ouvertures et surfaces nettes, ouvrages à HSP variable, comptage exact multi-murs avec longueurs individuelles, prise en charge des polygones pour les portées. Ces évolutions doivent être validées séparément ; elles ne sont pas autorisées par le présent travail préparatoire.

Hors périmètre initial : migration globale SwiftData, synchronisation serveur des scans, scan multi-pièces fusionné, dessin de nouvelles cloisons et affichage AR des ossatures. Aucun de ces chantiers n’est un prérequis pour tester un premier scan de pièce.

## 12. État du prototype technique

### Régression sur relevé réel — cuisine du 11 septembre, 15 h 49

Le diagnostic fourni (15 segments bruts) est conservé dans Tests/Fixtures/kitchen-open-corridor-20260911.json. Il ne contient pas le mesh ni la trajectoire caméra : les tests rejouent donc la proposition de contour pour des positions de test dans la cuisine, pas la totalité du scan live.

Quand la recherche topologique locale échoue, une proposition rectangulaire de secours est recherchée sur les lignes de murs observées. Quatre côtés doivent présenter un support mesuré suffisant (au moins 30 % par côté, somme des taux au moins 2,5), et un passage bordé de retours opposés doit être reconnu. Les retours peuvent être décalés longitudinalement de 75 cm par rapport à la coupe, afin de tenir compte d'un côté de couloir prolongé au-delà de son intersection. Aucun rectangle tiré du seul bounding box du mesh. Ces inférences restent jaunes à valider. Le contour fidèle reste prioritaire, notamment pour les pièces en L.

Le fichier réel produit désormais trois propositions pour les positions testées ; la première exclut un point du couloir et donne environ 14,24 m² en projection horizontale. Cette valeur est une estimation, pas une mesure de référence. Tests : exclusion du couloir, inclusion de la position de test, ordre/direction des murs inversés, plus tests géométriques existants. Fluidité, format caméra et règles métier inchangés.

### Fluidité — 11 septembre

Suppression des copies du mesh dans les callbacks didAdd/didUpdate : une lecture périodique de currentFrame alimente désormais une copie en tâche de fond, avec une seule copie périodique en vol. Un snapshot complet remplace le précédent (ancres supprimées incluses). Le nombre de faces plafond est mis en cache lors de la copie. Après verrouillage du plafond, la copie diagnostique est limitée à une fois toutes les 1,2 secondes. À l'arrêt, une dernière copie asynchrone précède l'arrêt RoomPlan ; un identifiant de génération écarte les résultats tardifs après annulation ou nouveau scan.

La surimpression utilise CADisplayLink, jusqu'à 60 Hz, au lieu d'un Timer à 30 Hz ; invalidation au démontage de la vue. Les formats caméra ARWorldTracking disponibles et le temps de copie sont affichés dans le diagnostic du résultat. Aucun changement d'objectif, de résolution ni de règles de reconstruction. Les bénéfices de fluidité restent à mesurer sur l'iPhone ; les tests géométriques ne constituent pas un benchmark.

### Aperçu vert pendant la capture

Recherche locale à l'entrée du couloir : nouvelle priorité aux passages avec deux côtés parallèles et deux retours de murs opposés, caméra du côté de la pièce large. Un graphe planaire découpe les intersections, élimine les branches sans boucle et sélectionne la face contenant la caméra après la coupe. Les autres pièces n'ont plus à former une boucle exploitable. Recherche exécutée même si le contour global est fermé ; la zone proposée reste jaune jusqu'à validation. Essais synthétiques : cuisine 4 × 4 m avec couloir ouvert, pièce voisine détachée, murs inversés et L non découpé. Ces essais ne garantissent pas encore la reconnaissance sur les segments bruités du scan réel.

Propositions automatiques (11 septembre, itération suivante) : après trois tentatives espacées avec contour inexploitable, le prototype recherche une fermeture courte (jusqu'à 3 m) ou une coupe entre extrémités de murs parallèles évoquant un passage. Seuls les contours fermés contenant la position de l'utilisateur sont proposés, sans enveloppe rectangulaire arbitraire. Un plan suffisamment observé est nécessaire. La proposition apparaît en jaune et suspend les réajustements ; « Valider ce plafond » la passe en vert et verrouille ses sommets et son aire, conservés au résultat final. « Autre proposition » relance la recherche ; aucune proposition n'est automatiquement validée. L'interface manuelle à deux points est retirée du parcours principal. Les scènes avec branches complexes, grandes ouvertures ou plusieurs plans peuvent encore rester sans proposition. Tests ajoutés pour passage ouvert, caméra hors contour et grande ouverture refusée. Validation sur appareil requise.

Évolution du 11 septembre après essai utilisateur : les triangles candidats ne sont plus affichés pendant la recherche. Le premier plan complet accepté est affiché en vert et figé ; « Recalculer le plafond » ou une modification des limites le déverrouille. Le résultat final conserve cette surface figée, sans prétendre à une précision supérieure à celle de l'échantillon live. La veille automatique est désactivée pendant la capture et le traitement, puis son état précédent est restauré en fin, annulation ou erreur.

Limites virtuelles manuelles : « Délimiter la pièce » permet de viser deux points avec la caméra, de visualiser la ligne orange, puis de confirmer le côté à conserver en restant dans cette zone. Chaque limite est un plan vertical de découpe, pas un mur métier. Les segments RoomPlan sont tronqués et une fermeture virtuelle est ajoutée si exactement deux raccords distincts sont trouvés. Plusieurs limites peuvent fermer un couloir ; la dernière est annulable. Tests synthétiques : coupe d'un rectangle, sens inversé, deux limites de couloir, pièce ouverte fermée. Une seule zone par scan, pas de proposition automatique ou sauvegarde multi-pièces. Positionnement par raycast estimé : précision et raccords restent à valider sur l'iPhone. Les exports diagnostiques incluent les limites et les segments découpés.

Une surimpression SceneKit transparente utilise les matrices de vue/projection de la caméra AR courante, dans le repère partagé, avec rafraîchissement visuel à 30 Hz. Elle laisse passer les interactions et se masque quand le suivi n'est pas normal. Les événements RoomCaptureSession alimentent le contour en cours via un observateur qui transmet également tous les événements au delegate préexistant.

Au plus une reconstruction en arrière-plan est lancée toutes les 1,5 secondes, sur un échantillon plafonné approximativement à 6 000 faces, tant que le plafond n'est pas figé. Un résultat valide affiche le plan continu vert ; un échec laisse la vidéo sans triangles verts. Un identifiant de génération empêche un calcul terminé tardivement de repeindre après arrêt ou nouveau scan. Le traitement final conserve son snapshot complet pour le diagnostic, mais réutilise la surface figée lorsqu'elle existe. Aucune sauvegarde ou synchronisation ajoutée. L'alignement visuel a fait l'objet d'un premier essai utilisateur positif ; aucune occlusion par les objets réels n'est réalisée dans cette surimpression technique.

### Reconstruction expérimentale d'un plafond continu

Diagnostic exportable : un bouton « Partager le diagnostic des murs » partage un texte JSON en mémoire, contenant les segments bruts et normalisés, les trois extrémités voisines les plus proches avec distances et le contour obtenu (ou null). Il ne contient ni photos ni objets ; aucune écriture automatique sur disque ou synchronisation serveur. Le diagnostic permet de rejouer un échec de contour sans nouvelle acquisition. L'ancien prototype ne permettait pas cet export, et les logs ne conservaient pas tous les segments.

Ajustement du 11 septembre : nettoyage des fragments alignés (écart latéral maximal 4 cm, angle 3°, discontinuité maximale 20 cm), suppression des doublons par fusion, puis raccord des angles à l'intersection des droites supports. Le déplacement de chaque extrémité est plafonné à 30 cm et 25 % de la longueur du segment. Les raccords doivent rester uniques et réciproques. Aucune enveloppe convexe ni fermeture arbitraire d'un couloir n'est ajoutée. Les tests couvrent maintenant aussi les doublons, chevauchements, angles tronqués, une ouverture de 60 cm et une branche ambiguë. Les seuils sont expérimentaux ; le scan réel ayant échoué reste à retester. Pas encore d'éditeur de confirmation manuelle.

`ScannerCeilingReconstruction.swift` reconstruit un seul plan depuis les portions de mesh hautes et non verticales, limité au contour des murs. Les extrémités des murs doivent former une boucle unique (tolérance d'appariement de 20 cm) ; les contours ouverts, ambigus, croisés ou disjoints sont rejetés. Une triangulation par oreilles respecte les concavités, sans enveloppe convexe. Les observations à l'extérieur sont écartées ; des hypothèses de plan pondérées par l'aire sont suivies d'une régression centrée. Au moins 12 triangles et 0,15 m² doivent appuyer le plan dominant, qui doit représenter 70 % de l'aire candidate. L'erreur quadratique tolérée est de 4 cm. Ces seuils de prototype restent à calibrer sur appareils.

Le résultat expose une surface reconstituée et une inclinaison, et s'affiche en violet dans l'aperçu 3D ; un interrupteur permet de revenir aux triangles bruts. Les trous du mesh sont ainsi comblés par le plan, mais aucune trémie n'est automatiquement reconnue ou déduite. Un plafond à plusieurs niveaux/plans n'est pas encore reconstruit. Aucun de ces résultats n'alimente les quantitatifs.

Les contrôles synthétiques de `Tests/ScannerCeilingReconstructionChecks.swift` couvrent le rectangle 99 × 150 cm avec trou central (1,485 m²), la pente, l'ordre inversé des murs, le déplacement du repère, le refus d'un contour ouvert ou de données absentes, deux niveaux distincts, un contour concave et la concordance aire/triangulation. Exécution : compiler ce fichier avec le moteur via `swiftc`, puis exécuter le binaire. La précision réelle doit être comparée au WC mesuré après installation.

L'aperçu « Voir le scan en 3D » compare les triangles du snapshot figé : vert = plafond Apple et filtre, bleu = plafond Apple écarté par le filtre, orange = filtre seul, gris = autres triangles (masqués par défaut). Le classement visuel est calculé dans la même boucle que les compteurs et la surface candidate, afin de comparer exactement les mêmes données. Les murs RoomPlan sont dessinés en contours blancs dans le repère commun. L'utilisateur peut tourner, zoomer, recentrer, passer en vue de dessus ou en perspective et afficher le contexte gris. Aucun trou n'est rempli ; les surfaces candidates restent expérimentales. L'aperçu et le scan sont conservés en mémoire uniquement.

Diagnostic appareil du 10 septembre : RoomPlan détecte 4 murs et 1 sol dans un WC ; le mesh est reçu mais aucun plafond exploitable n'est encore confirmé. Le bilan montre un haut de murs à y = 1,12 m et un mesh maximal à y = 0,40 m. Ces valeurs ne prouvent pas la cause (couverture, cycle de session ou conservation des données). Le mesh est désormais figé avant l'arrêt RoomPlan, et les mises à jour/suppressions tardives sont ignorées pendant le traitement. Une altitude maximale observée pendant la capture permet de comparer la couverture historique au snapshot final. La détection géométrique reste une heuristique de debug, non une mesure validée de plafond ; ses surfaces peuvent inclure d'autres éléments hauts.

Le premier prototype du Lot 1 est maintenant ajouté à l’application principale :

- l’onglet Scanner ouvre `Plaquisto/Plaquisto/ScannerDebugView.swift` ;
- une `ARSession` personnalisée active le mesh classifié et est fournie à `RoomCaptureView` ;
- le prototype conserve en mémoire le `CapturedRoom`, les sommets, faces, classifications et transformations des ancres mesh ;
- les mises à jour et suppressions d’ancres remplacent ou retirent les snapshots par UUID afin d’éviter les doubles comptages ;
- le bilan affiche murs, sols, portes, fenêtres, ouvertures, objets, ancres mesh et faces classées plafond ;
- la console affiche également des coordonnées témoins RoomPlan et ARKit dans le repère monde commun ;
- aucune donnée n’est persistée et aucun chantier, ouvrage ou quantitatif n’est créé ;
- l’autorisation caméra est déclarée pour la cible Plaquisto uniquement.

La compilation iOS et simulateur, le Lab et les tests existants doivent rester verts après chaque ajustement. La faisabilité réelle de la session commune, la réception du mesh et la qualité de classification des plafonds/rampants restent à valider sur l’iPhone LiDAR : c’est précisément l’objet du prochain essai appareil.

Décision géométrique retenue pour un lot ultérieur : pour une surface irrégulière, séparer une zone rectangulaire calculable métriquement et une surface résiduelle calculée par coefficients. Les consommables surfaciques utilisent la surface réelle totale ; l’ossature du rectangle utilise le métrique ; l’ossature résiduelle est affichée comme estimation. Les éléments périphériques doivent utiliser le contour mesuré dès que leur calcul le permet.
