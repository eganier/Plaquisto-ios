# Plaquisto — passation du développement du scanner LiDAR

Dernière mise à jour : 11 septembre 2026, après validation sur iPhone d’un plafond rampant à deux pans.

> Mise à jour du 12 septembre : lire en priorité [SCANNER_ARCHITECTURE_2026-09-12.md](SCANNER_ARCHITECTURE_2026-09-12.md). Le modèle neutre, l’adaptateur, la sauvegarde JSON et le prototype murs sont maintenant implémentés. Les sections ci-dessous décrivent l’état historique avant ce refactor ; les validations terrain du 11 septembre restent distinctes des tests du nouveau code.

## Consigne pour le prochain assistant

Ce document décrit l’état réel du prototype. Commencer par inspecter le dépôt et lire les fichiers cités avant de modifier le code. Préserver les changements existants : le worktree est volontairement non propre et plusieurs fichiers du scanner sont encore non suivis par Git. Ne pas réécrire les formulaires métier ni les calculs de fournitures sans demande explicite.

Le prochain objectif envisagé avec l’utilisateur est le prototype de mesure et de validation des murs. Ne pas le considérer comme déjà développé.

## Dépôt et cible

- Dépôt : `/Users/edouard/Documents/GitHub/Plaquisto-ios`
- Projet : `Plaquisto/Plaquisto.xcodeproj`
- Scheme : `Plaquisto`
- Application : iOS 17+, SwiftUI, RoomPlan, ARKit et SceneKit
- Bundle ID : `fr.plaquisto.app`
- iPhone de test : iPhone 16 Pro (`iPhone17,1`), CoreDevice ID `6A65A405-C70C-5FEF-88B6-B110C4E648B8`, UDID Xcode `00008140-000875360A60801C`
- Équipe de signature : `U6X2KSN84X`

## Fichiers actuellement concernés

- `Plaquisto/Plaquisto/ScannerDebugView.swift` : capture, modèle de debug, interface live, diagnostic et aperçu 3D.
- `Plaquisto/Plaquisto/ScannerCeilingReconstruction.swift` : géométrie pure des contours et des plafonds.
- `Tests/ScannerCeilingReconstructionChecks.swift` : contrôles Swift autonomes.
- `Tests/Fixtures/kitchen-open-corridor-20260911.json` : régression d’une cuisine ouverte sur un couloir.
- `Tests/Fixtures/sloped-room-branches-20260911.json` : régression d’une pièce avec ramifications RoomPlan.
- `SCANNER_IMPLEMENTATION_PLAN.md` : plan d’intégration et journal détaillé des itérations. Certaines sections anciennes y décrivent des limitations ensuite corrigées ; le présent fichier fait foi pour l’état courant.
- `Plaquisto/Plaquisto/PlaquistoApp.swift` : branchement de l’onglet Scanner.
- `Plaquisto/Plaquisto.xcodeproj/project.pbxproj` : déclaration des sources et autorisation caméra.

État Git observé lors de cette passation : `project.pbxproj` et `PlaquistoApp.swift` modifiés ; les fichiers du scanner, le plan et `Tests/` sont non suivis. Ne supprimer, restaurer ou écraser aucun de ces changements.

## Ce qui fonctionne et a été validé sur l’iPhone

### Capture RoomPlan et maillage ARKit

- Une `ARSession` commune est fournie à `RoomCaptureView`.
- La reconstruction de scène demande `.meshWithClassification` lorsque l’appareil le permet.
- Les murs, sols, portes, fenêtres, ouvertures et objets RoomPlan sont comptés.
- Les ancres, faces et classifications du maillage ARKit sont conservées dans le même repère monde.
- Le snapshot final du mesh est copié avant l’arrêt de RoomPlan.
- Les copies périodiques du maillage sont faites hors du thread principal, avec une seule copie en vol.

### Fluidité et expérience de scan

- L’overlay SceneKit suit la caméra via `CADisplayLink`, jusqu’à 60 Hz.
- L’utilisateur a confirmé que l’image caméra est devenue nettement plus fluide.
- Les petits triangles verts ne sont plus affichés pendant la recherche.
- Une proposition incertaine apparaît en jaune ; elle devient verte et se fige après validation.
- Une surface validée ne se recalcule plus à partir des points acquis ensuite.
- La mise en veille de l’iPhone est désactivée pendant la capture et son état précédent est restauré à la fin.

### Contours de pièces

- Rectangles et formes concaves en L pris en charge sans enveloppe convexe.
- Nettoyage des fragments et doublons de murs RoomPlan.
- Petits écarts aux angles raccordés avec des limites prudentes.
- Cuisine ouverte sur couloir : détection d’un passage et proposition d’une fermeture locale, à valider.
- Si le graphe contient un contour principal et des branches annexes, la face fermée contenant la caméra peut être proposée au lieu d’exiger une boucle globale unique.
- Le plafond problématique ayant motivé ces correctifs a ensuite fonctionné trois fois de suite selon l’utilisateur.

### Plafonds et rampants

- Plafond horizontal continu reconstruit à partir du contour des murs et des portions planes du mesh.
- Les trous de mesh dus aux luminaires sont comblés par la surface estimée.
- Rampant à un pan validé sur un vrai scan.
- Rampant à deux pans validé sur un vrai scan le 11 septembre : les deux pans et leur faîtage étaient correctement visibles dans l’aperçu, pour une surface affichée de `13,28 m²`.
- Le modèle `Surface` contient désormais une liste de `Pan`. Chaque pan possède ses triangles, sa surface réelle, sa pente, son support observé et son erreur d’ajustement.
- Les deux pans doivent avoir des pentes opposées d’au moins 5°, représenter chacun au moins 20 % des observations et couvrir ensemble au moins 85 % de la surface observée.
- Les deux pans sont découpés au contour de la pièce et proposés ensemble en jaune avant validation.

## Diagnostic actuel

L’écran affiche le dernier motif précis de refus :

- contour inexploitable ;
- échantillons insuffisants ;
- support insuffisant d’un plan ;
- plan principal inférieur à 70 % ;
- ajustement dégénéré ;
- résidu supérieur à 4 cm ;
- pente supérieure à 65° ;
- succès à un ou deux pans.

Le partage « Diagnostic complet » exporte en JSON : murs bruts et normalisés, contour, position relative de la caméra, 120 dernières tentatives live, nombre de murs et de faces, pas d’échantillonnage, seuil de hauteur, propositions de zones et fermetures, résultats des ajustements, actions de validation/refus et chemin de reconstruction final. L’export ne contient ni photo ni maillage brut ; il ne permet donc pas de rejouer exactement l’ajustement des plans hors appareil.

## Limites connues

- Trois et quatre pans ne sont pas encore détectés. La structure `Surface.pans` est prête à être étendue, mais seuls un et deux pans sont implémentés.
- Les tests trois/quatre pans pourront être synthétiques dans un premier temps, car l’utilisateur ne dispose pas d’une pièce réelle adaptée. Cela ne remplacera pas une validation LiDAR sur chantier.
- Les fenêtres de toit ne sont pas reconnues comme ouvertures déductibles. Sur le scan à deux pans, la fenêtre apparaissait en orange : notre filtre géométrique la voyait, mais Apple ne la classait pas comme plafond. La surface reconstituée la rebouche actuellement.
- Poutres, coffrages et gaines ne sont pas identifiés. ARKit n’a pas de classe sémantique « poutre » ; une future détection devrait chercher un volume allongé en relief par rapport au plan et demander confirmation.
- Aucune surface du scanner n’alimente encore les ouvrages ou les quantitatifs.
- Aucune persistance durable des scans ou du mesh n’est implémentée.
- Les ouvertures/trémies ne sont jamais déduites automatiquement.
- L’overlay live ne réalise pas d’occlusion par les objets réels.
- La précision absolue des dimensions et surfaces reste à comparer à davantage de mesures manuelles.

## Décisions fonctionnelles déjà prises

- Les murs donnent le contour ; les portions de plafond donnent hauteur et orientation.
- Les surfaces proposées automatiquement mais incertaines sont jaunes et doivent être validées.
- Après validation, la surface devient verte et reste figée.
- Un trou dans le maillage ne doit pas être interprété automatiquement comme une trémie.
- Pour une surface irrégulière future : zone rectangulaire calculée en métrique, reste évalué avec un coefficient. Les consommables surfaciques utiliseront la surface réelle totale ; l’ossature rectangulaire utilisera le métrique et l’ossature résiduelle sera présentée comme estimation.
- Il faudra à terme des ouvrages de plafond rampant à 1, 2, 3 et 4 pans.
- Le scanner doit toujours permettre une vérification/correction humaine avant de créer ou préremplir un ouvrage.

## Tests disponibles

Les contrôles couvrent notamment :

- rectangle `0,99 × 1,50 m` avec trou central ;
- plafond horizontal et pente simple ;
- deux pans symétriques et dissymétriques ;
- trou de maillage sur un deux-pans ;
- inversion de l’ordre des murs et des normales ;
- translation du repère monde ;
- contour concave à un ou deux pans ;
- échantillonnage live ;
- rejet d’un troisième plan substantiel ;
- L, fragments, doublons, petits écarts aux angles et branche ambiguë ;
- cuisine ouverte sur couloir ;
- contour principal avec ramifications ;
- refus d’une ouverture arbitraire, d’un mesh absent et de plusieurs niveaux incohérents.

Commande :

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swiftc \
  Plaquisto/Plaquisto/ScannerCeilingReconstruction.swift \
  Tests/ScannerCeilingReconstructionChecks.swift \
  -o /tmp/plaquisto-ceiling-reconstruction-checks \
&& /tmp/plaquisto-ceiling-reconstruction-checks
```

Cette commande doit être lancée depuis la racine du dépôt, car les fixtures utilisent des chemins relatifs.

## Compiler et installer

Compilation iPhone :

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project Plaquisto/Plaquisto.xcodeproj \
  -scheme Plaquisto \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PlaquistoScannerDevice \
  DEVELOPMENT_TEAM=U6X2KSN84X build
```

La signature peut attendre une autorisation du trousseau macOS. L’utilisateur doit la valider lui-même.

Compilation simulateur :

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project Plaquisto/Plaquisto.xcodeproj \
  -scheme Plaquisto \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

Installation sur l’iPhone :

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun devicectl device install app \
  --device 6A65A405-C70C-5FEF-88B6-B110C4E648B8 \
  /tmp/PlaquistoScannerDevice/Build/Products/Debug-iphoneos/Plaquisto.app
```

Lancement :

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun devicectl device process launch \
  --device 6A65A405-C70C-5FEF-88B6-B110C4E648B8 \
  --terminate-existing fr.plaquisto.app
```

## Suite recommandée : prototype des murs

RoomPlan fournit déjà les murs et leurs ouvertures. La prochaine étape discutée est un prototype de contrôle, sans brancher encore les calculs métier :

1. sélectionner un mur dans la vue 3D ;
2. afficher sa longueur, sa hauteur et sa surface brute ;
3. afficher les portes, fenêtres et ouvertures qui lui appartiennent ;
4. présenter séparément surface brute et surface nette ;
5. permettre de corriger et valider les dimensions ;
6. découper le haut des murs selon les pans validés, afin de représenter correctement les pignons et murs sous rampants.

Avant de coder cette étape, vérifier les modèles d’ouvrage déjà présents dans le dépôt et décider explicitement quelles ouvertures doivent être déduites selon l’usage métier. Ne pas déduire automatiquement une ouverture ou transformer un mur RoomPlan en ouvrage sans validation utilisateur.

## Critères de prudence pour la suite

- Ne pas baisser globalement les seuils pour faire passer un cas : diagnostiquer puis ajouter une règle géométrique ciblée et testée.
- Ne jamais utiliser une enveloppe convexe qui supprimerait les formes en L ou engloberait un couloir.
- Une inférence doit être proposée en jaune, pas validée silencieusement.
- Conserver toutes les coordonnées dans le repère spatial partagé RoomPlan/ARKit.
- Ajouter une fixture de régression lorsqu’un diagnostic réel révèle un nouvel échec.
- Vérifier les tests géométriques, la compilation simulateur et la compilation iPhone après chaque modification importante.
- Distinguer clairement « testé synthétiquement », « compilé » et « validé sur iPhone ».
