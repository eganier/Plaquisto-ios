# Scanner Plaquisto — architecture neutre et prototype murs

État du 12 septembre 2026. Complément qui remplace les sections « architecture » et « prochaine étape murs » de la passation du 11 septembre. Les validations terrain antérieures ne valent pas validation terrain de ce refactor.

> Étape suivante réalisée le même jour : voir [SCANNER_MODEL_PROOF_2026-09-12.md](SCANNER_MODEL_PROOF_2026-09-12.md). Lecture/sauvegarde via un écran autonome, fiche mur détaillée, preuve de rechargement dans deux processus et affichage simulateur sans scanner/RoomPlan. Accès actuel : Scanner → Ouvrir la pièce sauvegardée.

## Audit avant modification

- Seul `ScannerDebugView.swift` importait RoomPlan. Il regroupait l’interface, la session de capture, les callbacks, l’analyse et la préparation du rendu.
- `CapturedRoom` était conservé pour le résultat brut et le résultat live, et passé aux callbacks de session, à `complete(with:)` et à `analyzeGeometricCeilings(in:)`.
- Les surfaces étaient lues par leurs collections et propriétés (murs, sols, dimensions, transformations, portes/fenêtres/ouvertures). Aucun modèle métier indépendant de mur ou d’ouverture n’en était extrait.
- Les objets RoomPlan étaient comptés, pas transformés en ouvrages. Aucun usage explicite de `CapturedRoom.Object` dans les formulaires ou calculs métier.
- `ScannerCeilingReconstruction` était déjà indépendant de RoomPlan : Foundation/simd, segments de murs, triangles techniques, pans et surfaces reconstruits.
- L’aperçu SceneKit consommait des triangles et des arêtes déjà préparés, pas directement CapturedRoom. Mais la préparation des murs et des hauteurs était couplée au scanner RoomPlan.
- `ProjectStore`, les modèles d’ouvrages et leurs configurateurs/quantitatifs n’importaient pas RoomPlan. La persistance métier utilisait ses propres structures Codable.
- Le scanner n’avait pas de format de pièce de travail persistant ; son export était un diagnostic technique, non un format métier.

Conclusion : RoomPlan était la représentation de pièce du prototype de scanner, mais n’était pas le modèle principal des ouvrages Plaquisto. Il fallait extraire une représentation géométrique sans réécrire le métier ni le moteur de plafond.

## Frontière après refactor

```text
RoomPlan / ARKit
  ├─ RoomPlanScanner (session, mesh, suivi live, diagnostic)
  └─ RoomPlanAdapter → PlaquistoRoomModel
                        ↑
ScannerCeilingReconstruction → ScannerRoomBridge
                        ↓
              PlaquistoRoomDocument v1
              initialRoom + room de travail
                        ↓
        éditeur de murs / surfaces / JSON / stockage
```

Les seuls imports RoomPlan sont désormais dans `RoomPlanScanner.swift` et `RoomPlanAdapter.swift`. Les types CapturedRoom restent dans ces deux fichiers.

- `RoomPlanScanner.swift` : capture et infrastructure Apple déplacées hors de la vue. Convertit les résultats live/final avant de préparer murs et hauteurs. Le mesh reste une donnée technique de la session.
- `RoomPlanAdapter.swift` : murs, ouvertures, sols, transformations vers le repère commun Y vertical ; dimensions en mètres ; confiance du fournisseur. Chaque élément reçoit un UUID Plaquisto. Les identifiants Apple ne servent qu’à corréler les mises à jour.
- `PlaquistoRoomModel.swift` : Foundation uniquement. Pièce, murs, ouvertures génériques, sols, plafonds, pans paramétriques, provenance, mesures brutes et corrections. Aucune dépendance Apple de scan.
- `ScannerRoomBridge.swift` : extrait les plans et contours des pans reconstruits. Les triangles ne sont pas enregistrés dans la pièce de travail.
- `PlaquistoWallGeometry.swift` : calcul neutre du profil, surface brute, union des ouvertures et surface nette. Produit également la triangulation de rendu à partir de la géométrie paramétrique.
- `PlaquistoRoomEditor.swift` : sélection SceneKit et saisie SwiftUI à partir du modèle Plaquisto seulement.
- `ScannerDebugView.swift` : interface/aperçu de diagnostic conservés ; lien vers l’éditeur neutre.

L’ancien aperçu du mesh reste volontairement un outil technique de diagnostic. Il n’est pas la source des surfaces de l’éditeur. Aucun quantitatif métier actuel n’a été branché ou modifié.

## Modèle et identifiants

- Un mur possède début/fin, longueur, hauteur, épaisseur facultative, orientation calculée et IDs d’ouvertures.
- Types génériques : porte, fenêtre, baie vitrée, porte-fenêtre, passage, autre. L’adaptateur ne prétend pas distinguer baie/porte-fenêtre si la source dit seulement « fenêtre ».
- Rattachement : parent fourni par RoomPlan en priorité, sinon proximité et alignement. Une association ambiguë reste sans mur et n’est pas déduite.
- Un plafond référence plusieurs pans ; chaque pan contient `y = a*x + b*z + c` et ses contours. Le schéma n’impose ni rectangle ni nombre fixe de pans. Le moteur de détection reste limité aux cas précédemment pris en charge.
- Les sols conservent leurs contours et une altitude de référence ; l’adaptateur préserve celle utilisée auparavant par le diagnostic pour ne pas déplacer les seuils.
- Provenance : roomPlan, arCore, lidar, manual, imported. Confiance optionnelle, sans pourcentage inventé.
- Une mesure garde `rawValue`, `manualValue`, provenance et état de validation. La valeur effective est manuelle si elle existe. Une mise à jour brute ne l’efface pas.
- L’adaptateur réutilise les UUID indépendants et les corrections pour les IDs source déjà connus dans une acquisition ou un modèle passé à `preserving:`.
- Une nouvelle acquisition crée une nouvelle pièce. La correspondance entre deux rescans distincts n’est pas implémentée : les IDs RoomPlan pouvant changer, aucune fusion hasardeuse n’est faite.

## Persistance et échanges

`PlaquistoRoomDocument` contient `schemaVersion: 1`, `initialRoom` immuable et `room` de travail.

Sauvegarde atomique locale : `Application Support/Plaquisto/scanner-room-v1.json`, séparée de `projects.json`. Le prototype conserve la dernière pièce, pas encore un historique par chantier. Les corrections sont enregistrées avant confirmation à l’écran ; une erreur de disque est affichée.

JSON import/export depuis l’éditeur, incluant IDs, provenance, corrections et modèle initial. L’import vérifie version, nombres finis, dimensions et relations ; une version inconnue est refusée. Importer remplace la pièce courante du prototype. Il ne s’agit pas du JSON natif RoomPlan.

Les futurs adaptateurs ARCore, saisie manuelle et import de formats externes devront construire les mêmes structures et respecter mètres/repère Y vertical. ARCore, synchronisation serveur, DAE/GLB/DXF et génération de commandes ne sont pas développés ici.

## Prototype murs

Accès : **Scanner → Pièce Plaquisto → Murs et dimensions**, disponible aussi après relancement si une pièce est sauvegardée.

- Toucher un mur dans la 3D, ou utiliser la liste.
- Consulter longueur effective, hauteur min/max du profil, surface brute, ouvertures rattachées, déduction et surface nette géométrique.
- Valider/corriger longueur ou hauteur, avec décimales françaises acceptées.
- Le haut est découpé suivant les contours et plans de plafond acceptés : pignons et murs sous rampants, y compris raccord entre deux pans.
- Les ouvertures sont bornées au profil du mur, avec union pour éviter une double déduction des chevauchements.
- Une hauteur manuelle est explicitement **uniforme** et remplace le profil sous pente pour ce mur. Une action permet de reprendre le profil du plafond.
- Une correction de longueur déplace l’extrémité depuis le point de départ, sans ajuster les murs voisins. Ce n’est pas encore un solveur de contraintes de pièce.
- Les ouvertures sont indiquées en bleu ; elles ne sont pas encore évidées dans le maillage affiché. La déduction métrique est bien effectuée.

La surface nette est une information géométrique, pas une règle commerciale ou de fournitures. Aucun mur ne devient automatiquement doublage/cloison/ouvrage.

## Vérifications

Résultats sur les dernières sources :

- Compilation Debug, destination générique iOS Simulator : réussie, sans signature.
- Compilation Debug, destination générique iOS (arm64) : réussie avec `CODE_SIGNING_ALLOWED=NO`.
- La première tentative de signature était bloquée dans `codesign`. Nouvelle tentative réussie le 12 septembre, puis installation confirmée à 09:50 sur l’iPhone 16 Pro d’Edouard (bundle `fr.plaquisto.app`). Cela ne constitue pas une validation terrain du scan.
- Aucun test tactile/visuel du nouvel éditeur ni capture LiDAR réelle n’a été exécuté pendant ce refactor.

Tests exécutables autonomes :

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc Plaquisto/Plaquisto/ScannerCeilingReconstruction.swift Tests/ScannerCeilingReconstructionChecks.swift -o /tmp/plaquisto-ceiling-reconstruction-checks
/tmp/plaquisto-ceiling-reconstruction-checks

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc Plaquisto/Plaquisto/PlaquistoRoomModel.swift Plaquisto/Plaquisto/PlaquistoWallGeometry.swift Plaquisto/Plaquisto/ScannerRoomBridge.swift Plaquisto/Plaquisto/ScannerCeilingReconstruction.swift Tests/PlaquistoRoomModelChecks.swift -o /tmp/plaquisto-room-checks
/tmp/plaquisto-room-checks
```

Les tests existants passent : contours fragmentés, L, cuisine/couloir enregistré, rampant, deux pans, normales inversées, trous, refus des cas ambigus. Aucun changement au moteur ni baisse globale des seuils.

Les nouveaux tests passent : surface rectangulaire, pignon à deux pans, plafond non accepté ignoré, longueur/hauteur manuelles, priorité sur une nouvelle mesure brute, union des ouvertures, découpe au bord et sous pente, ouverture non rattachée, JSON aller-retour/stockage/IDs, modèle initial préservé, versions inconnues et relations invalides refusées. Le pont de reconstruction est testé sur un L et sur la sortie réelle du moteur alimenté par un mesh synthétique à deux pans.

La compilation ne prouve pas la qualité de capture sur appareil. Restent à valider sur un vrai iPhone après ce refactor :

1. Non-régression des plafonds horizontal, 1 pan, 2 pans, L et cuisine/couloir.
2. Rattachement réel des portes/fenêtres, particulièrement les murs fragmentés.
3. Sélection tactile des murs, lisibilité et navigation 3D.
4. Comparaison des surfaces d’un pignon et d’un mur percé avec des dimensions connues.
5. Correction, fermeture/réouverture de l’app, export/import sur iPhone.
6. Fluidité du scan après ajout de l’adaptation live.

Ni trois/quatre pans, ni poutres, ni fenêtres de toit/trémies déduites ne sont déclarés validés.
