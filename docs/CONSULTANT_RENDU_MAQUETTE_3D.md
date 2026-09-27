# Plaquisto — audit du rendu de maquette après scan

26 septembre 2026 — consultant senior AR / tech lead iOS, audit en lecture seule.
Cette note propose des pistes ; elle ne décrit pas des améliorations déjà livrées.

## Décision de cadrage

Le code actuel utilise **SceneKit**, pas RealityKit : `RoomDomainScene` dans
`PlaquistoRoomEditor.swift` et `SurveySceneRenderer` / `SurveySurfaceScene` dans
`SurveyWorkViews.swift`. Une migration n’est pas nécessaire pour obtenir une
maquette lumineuse, moderne et stylisée. Garder une présentation indépendante du
modèle métier permet de préparer une évolution sans réécrire la capture.

Ne pas modifier RoomPlan, ajouter une passe de correction géométrique ou démarrer
une session AR pour améliorer l’éclairage d’une maquette après scan.

## Constats vérifiés dans le dépôt

- `RoomDomainScene` utilise déjà le PBR, rugosité 0,85. Il reconstruit cependant
  les nœuds, géométries, matériaux et lumières à chaque sélection. Ses surfaces
  n’ont pas d’UV et sa directionnelle n’active pas `light.castsShadow`.
- `SurveySceneRenderer` est plus avancé : rugosité 0,9, métal nul, parquet
  procédural, ombres, SSAO et caméra orthographique. Mutualiser le style visuel
  plutôt que de créer un troisième moteur.
- Les UV du sol sont actuellement basées sur X/Z après transformation dans le
  relevé. Une réorientation de pièce peut donc déplacer/orienter le parquet.
- La sélection mute `firstMaterial.diffuse.contents`. Partager ces matériaux
  sans revoir cette mutation ferait recolorer plusieurs murs simultanément.
- Les identifiants Plaquisto sont stables dans le document ; les UUID RoomPlan
  sont des corrélations de provenance, jamais les clés principales de sauvegarde.

## V1 recommandée, par ordre de priorité

1. Partager palette et studio : murs ivoire, plafond neutre, sol minéral clair ou
   chêne blond désaturé, fond lin, ombres de contact légères. Réserver le bleu à
   la sélection/lecture technique. Pas de bloom, profondeur de champ ou reflets
   contrastés.
2. Conserver nœuds et maillages lors d’une sélection. Invalider la géométrie
   uniquement si sa révision change ; échanger des variantes de matériaux
   immuables pour les états normal/sélectionné/attribué.
3. Ajouter des UV métriques sur les triangles réels : contours concaves, rampants
   et ouvertures conservés. Un plan rectangulaire ne remplace jamais ces contours.
4. Centraliser textures/matériaux ; mesurer RAM, énergie et fluidité sur le plus
   ancien appareil LiDAR supporté. Prévoir un profil économique si nécessaire.
5. Ajouter un manifeste de finitions optionnel si la personnalisation fait partie
   de la V1. Ne pas lancer cette fonctionnalité uniquement pour améliorer le
   rendu par défaut.

## Matériaux légers

Points de départ visuels : enduit `roughness` 0,85–0,95 ; bois mat 0,70–0,85 ;
`metalness = 0`. Un micrograin de normale très faible est facultatif et peut être
retiré à distance. Les ombres/modelés sont prioritaires sur les textures.

```swift
@MainActor
func plaster(color: UIColor, grain: UIImage? = nil) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = color
    material.metalness.contents = 0.0
    material.roughness.contents = 0.88
    if let grain {
        material.normal.contents = grain
        material.normal.intensity = 0.08
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.mipFilter = .linear
    }
    return material
}
```

En PBR SceneKit, `specular`, `reflective` et `shininess` ne contrôlent pas ce
modèle : agir sur rugosité, métal, normale et lumière. `PhysicallyBasedMaterial`
et `SimpleMaterial` sont des équivalents RealityKit, non des matériaux utilisables
directement dans `SCNGeometry`.

## UV métriques sans déformation

Pour chaque sommet `p`, dans un repère orthonormé stable :

```swift
func uv(_ p: SIMD3<Double>, origin: SIMD3<Double>,
        axisU: SIMD3<Double>, axisV: SIMD3<Double>,
        periodU: Double, periodV: Double) -> CGPoint {
    // Valider periodU et periodV : positifs et finis.
    let d = p - origin
    return CGPoint(x: CGFloat(simd_dot(d, axisU) / periodU),
                   y: CGFloat(simd_dot(d, axisV) / periodV))
}
```

- Mur : origine `wall.start`, U = `wall.direction`, V vertical.
- Sol : repère local X/Z avant `transformToSurvey`.
- Rampant : axes normalisés du `Surface2D.localFrame` existant ; pas une simple
  projection horizontale, qui comprimerait le motif.
- Chants et tableaux d’ouverture : matériau uni pour commencer.

Ajouter `SCNGeometrySource(textureCoordinates:)` aux maillages existants, utiliser
`.repeat` et des périodes en mètres. Une texture de période 2 m se répète deux
fois sur 4 m. Les décalages/rotations propres à une surface doivent vivre dans les
UV ou une variante dédiée, sans mutation d’un matériau partagé.

## Cache et budgets

Un petit catalogue `@MainActor` peut partager les variantes immuables de matériaux
par `(styleID, état, mode opaque/translucide)`. `NSCache<NSString, UIImage>` est
utile pour un catalogue dynamique ; trois textures embarquées peuvent rester
dans un dictionnaire chargé à la demande. Une clé inclut version et résolution.

512² pour le micrograin, 512² ou 1K² pour un sol discret sont des budgets de départ,
pas des garanties de 60 FPS. RGBA8 : environ 1 Mio pour 512², 4 Mio pour 1K², plus
environ un tiers pour les mipmaps. Compter séparément ombres, SSAO, MSAA et copies.

HEIC/PNG sont des formats de fichier ; SVG/PDF doivent être rasterisés pour une
texture. Leur poids disque ne prédit pas le poids GPU. ASTC est une compression
GPU, à envisager seulement avec une chaîne de chargement vérifiée.

`floorTexture` utilise un `UIGraphicsImageRenderer` de 256 points sans échelle
explicite : fixer `format.scale = 1` et contrôler les pixels réels. Conserver le
rendu à la demande (`rendersContinuously = false`) ; une préférence de 60 FPS
n’est pas une garantie. Le profil économique peut réduire SSAO, ombres 2048→1024
et cadence, sur mesures et non sur promesse.

## Persistance indépendante du moteur

```swift
struct FinishManifest: Codable, Equatable {
    var version = 1
    var styleID = "scandi.light.v1"
    var assignments: [FinishAssignment] = []
}
struct FinishAssignment: Codable, Equatable {
    enum Kind: String, Codable { case wall, floor, slope }
    var elementID: UUID // Identifiant Plaquisto, pas RoomPlan.
    var kind: Kind
    var materialID: String
    var periodU: Double
    var periodV: Double
    var rotationRadians: Double
}
```

Champ optionnel pour les archives existantes. Les noms affichés sont localisés
dans le catalogue ; les clés persistées restent versionnées. Ne pas enregistrer
de `UIColor`, `SCNMaterial` ni de nom temporaire de nœud.

Étendre les remappings existants lors de la duplication. Une fusion conserve le
style commun ; les styles contradictoires nécessitent une règle explicite. Une
division hérite du style et de son repère. Éviter `boundaryIndex` comme identité
durable : l’ordre des boucles peut changer.

## Lumière après scan versus lumière AR

La maquette non-AR a besoin d’un studio fixe reproductible : une principale
oblique, un remplissage doux, des ombres peu denses. L’estimation lumineuse ARKit
et les `AREnvironmentProbeAnchor` servent à intégrer des objets à une vraie image
caméra ; ils ne sont pas nécessaires à cette vue. Ne pas reconfigurer RoomPlan
pour ce seul bénéfice esthétique.

## Vigilance géométrique pour une passe séparée

`RoomDomainScene` triangule séparément les boucles de sol/plafond ; la vue relevé
sait distinguer contour et trous. Une trémie peut donc être remplie différemment
dans ces deux vues. Harmoniser à terme sur les triangles validés existants, dans
une passe testée dédiée, sans mélanger cette correction avec le texturage.

## Références Apple vérifiées par le consultant

- [PBR SceneKit](https://developer.apple.com/documentation/scenekit/scnmaterial/lightingmodel-swift.struct/physicallybased)
- [Matériaux RealityKit](https://developer.apple.com/documentation/realitykit/material)
- [Coordonnées de textures SceneKit](https://developer.apple.com/documentation/scenekit/scnmaterialproperty/contentstransform)
- [NSCache et limite de coût indicative](https://developer.apple.com/documentation/foundation/nscache/totalcostlimit)
- [Réduire la mémoire Metal](https://developer.apple.com/documentation/metal/reducing-the-memory-footprint-of-metal-apps)
- [Rendu à la demande SceneKit](https://developer.apple.com/documentation/scenekit/scnview/renderscontinuously)
- [Estimation lumineuse ARKit](https://developer.apple.com/documentation/arkit/arconfiguration/islightestimationenabled)
- [Environnement ARKit](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/environmenttexturing-swift.property)
- [Transition SceneKit / RealityKit](https://developer.apple.com/documentation/RealityKit/bringing-your-scenekit-projects-to-realitykit)
