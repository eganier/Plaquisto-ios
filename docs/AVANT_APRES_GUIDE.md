# Montage avant / après

## Comportement actuel — caméra manuelle et montages mémorisés

L'entrée « Mes avant / après » montre le montage du dernier enregistrement, avec la
séparation et les deux photos (ou côte à côte), en entier. Le rendu est produit depuis
le JSON sauvegardé, avec le même moteur que l'export ; aucune dépendance à l'ancienne
miniature Avant seule. Réglages enregistrés automatiquement après 450 ms d'inactivité,
au retour et au passage en arrière-plan. Les fichiers des photos originales ne changent pas.

La séparation se déplace sur l'image, sans curseur externe. En mode diagonale, une poignée
ronde à flèches circulaires tourne autour du centre du segment visible ; toucher ailleurs
déplace la séparation. `diagonalAngle` est une nouvelle propriété JSON optionnelle : angle
de la normale en radians, coordonnées normalisées depuis le haut gauche. Valeur absente =
π/4 (ancienne diagonale x+y). Le demi-plan est défini par sa projection minimale +
`divider × amplitude`, assurant encore tout Après à 0 et tout Avant à 1, pour chaque angle.
Cette géométrie est partagée avec l'export, et reste portable sur Android.

Caméra manuelle uniquement : ni guidage visible, ni prise automatique, ni menu supérieur,
ni A. Photo Avant et flux caméra masquables indépendamment à gauche. Curseur vertical
à droite pour opacité 0–80 %. La session reste active si le flux est masqué ; les réglages
de visibilité ne sont jamais imprimés sur la capture. Flash après réussite conservé.
Panneau métadonnées/compatibilité et bouton de relance du recalage retirés. La première
tentative de recalage après capture reste automatique. Le géocodage reste optionnel et
soumis à confirmation sous « Retrouver la ville via les métadonnées de la photo ».

Les sections suivantes constituent l'historique et ne remplacent pas ce comportement.

## Évolution du guide caméra — 17 septembre 2026

### Correctif de visibilité des contours

Le seuil fixe de contraste/luminosité a été reproduit comme cause d'un guide vide sur une scène pâle : rectangle gris 0,72 sur mur gris 0,76, **0 pixel de trait visible** avec l'ancien filtre. Remplacement par un gradient de luminance lissé, normalisé par les intensités de la photo, puis légère dilatation des traits. Les aplats restent transparents ; aucun pixel de la photographie n'est utilisé comme fond du guide. Traits cyan avec ombre sombre et intensité initiale 95 % pour rester discernables sur les murs clairs. État explicite de préparation/échec/absence de contours, plutôt qu'un guide silencieusement absent. Tests supplémentaires de faible contraste et de conservation de l'orientation.

24 tests passent après correction (`Test-Plaquisto-2026.09.17_11-15-14-+0200.xcresult`), après reproduction en échec avec l'ancien filtre. Le guide produit par le cas pâle a été exporté et inspecté visuellement ; la photo réelle de l'utilisateur n'a pas été fournie, donc sa validation matérielle reste nécessaire.

- La photo Avant n'est **jamais** affichée comme calque dans la caméra. Core Image produit des contours blancs sur fond transparent (flou léger, filtre de contours, suppression des faibles niveaux, masque alpha). Intensité réglable ; plus de clignotement.
- Flux vidéo portrait, recadrage central au ratio de la référence ; analyse sur file distincte, résolution de référence 480 px, intervalle minimal 600 ms et rejet des images tardives. Pas d'écriture de chaque frame sur disque.
- Homographie/corrélation fournissent des suggestions : tourner, monter/descendre, avancer/reculer, incliner. Impossible d'inférer une pose 3D unique d'une homographie : conseils explicitement indicatifs, pas de distances ni de promesse sur une scène trop transformée.
- Capture automatique activée par défaut, désactivable : score >= 0,72, coins proches de l'identité, déplacement entre observations < 1,2 % et stabilité continue 1,8 s. Perte de correspondance, résultat périmé, changement d'objectif/exposition ou arrière-plan remettent l'attente à zéro. Manuel toujours disponible.
- Un balayage lumineux masqué par les contours précède le déclenchement (600 ms). En automatique le cadrage est revérifié après cet effet. Flash plein écran bref + retour haptique uniquement après réception réussie du JPEG ; aucun flash de succès sur échec.
- Filigrane diagonal répété semi-transparent (23 %), géométrie partagée aperçu/export. Interrupteur **Filigrane Plaquisto** dans Lab seulement via `allowsLabWatermarkControl` ; choix enregistré dans le JSON existant, respecté à l'export. Pas de compte/abonnement ajouté.
- Politique de guidage, stabilité et style filigrane dans les modèles Foundation : portables/réimplémentables Android, sans objets Vision persistés. Adaptateur caméra/contours/recalage live Apple remplaçable.

Les sections V1 ci-dessous décrivent le socle ; le guide de contours et le filigrane ci-dessus remplacent le calque/clignotement et le badge initial.

Validation de l'évolution : 22 tests ciblés réussis (`/tmp/PlaquistoLayoutTestsDerived/Logs/Test/Test-Plaquisto-2026.09.17_11-02-58-+0200.xcresult`), dont vérification de l'alpha transparent et présence de traits, attentes/rejets du guidage et désactivation Lab. Build iPhone final réussi ; installé physiquement dans Lab le 17 septembre à 11:06 (séquence 2200). Essai caméra réelle/animation à réaliser sur place ; ne pas confondre ces tests unitaires et la validation de la précision du cadrage matériel.

## Périmètre

Outil autonome, catégorie **Photos chantier**, intégré au catalogue partagé (Lab et app iOS), sans modifier les calculateurs existants. Pas de nouveau compte, abonnement, favoris, cloud ou lien chantier. Watermark Plaquisto présent par défaut ; aucun écran commercial. Le contexte de droits reste un point d'injection inactif tant qu'aucun fournisseur de droits vérifiés n'existe.

Parcours : choisir Avant → vérifier les métadonnées disponibles → cadrer avec la caméra et le calque → capturer Après → tentative de recalage → choisir une comparaison → exporter/partager → enregistrer et rouvrir. L'import et la capture sont enregistrés immédiatement ; les réglages se sauvegardent avec Enregistrer ou avant export. Le retour propose de sauvegarder ou d'abandonner uniquement les réglages non enregistrés.

## Découpage

| Fichier | Responsabilité |
| --- | --- |
| `BeforeAfterModels.swift` | Modèles Codable simples, politique de validation géométrique indépendante et position du séparateur. Aucune importation d'API Apple d'imagerie/interface. |
| `BeforeAfterServices.swift` | Contrats remplaçables `BeforeAfterAligning`, `BeforeAfterExporting`, `BeforeAfterReadingMetadata` et orchestration asynchrone, sans dépendance sur les adaptateurs Apple. |
| `BeforeAfterStorage.swift` | Extraction ImageIO, import PhotosPicker par fichier, normalisation orientation/résolution, fichiers et JSON atomiques, géocodage explicite. |
| `BeforeAfterImaging.swift` | Adaptateur Vision/Core Image pour recalage, validation conservatrice, recadrage commun, masques et rendu JPEG. |
| `BeforeAfterCamera.swift` | Adaptateur caméra AVFoundation sérialisé hors UI, calque, clignotement, objectifs physiques, permissions et interruptions. |
| `BeforeAfterViews.swift` | Liste locale, navigation, édition, aperçu, partage natif ; modèles d'édition sans requête Vision dans les vues. |
| `BeforeAfterTests.swift` | Métadonnées, compatibilité, stockage, modes/masques, export, droits, préremplissage, pipeline interchangeable et recalage sur images synthétiques. |

## Portabilité Android — contrat, pas dépendance Apple

Android n'aura **pas besoin de Vision, d'AVFoundation, de Core Image ni d'un service Apple** pour cette fonctionnalité. Les adaptateurs iOS sont une implémentation, pas la définition métier de l'outil. L'interface SwiftUI et les adaptateurs devront évidemment être réimplémentés sur Android ; ce code n'est pas un moteur Kotlin partagé déjà compilable.

Points à remplacer sur Android : import sélecteur de photos, extraction EXIF, caméra/preview/capture, registration d'images, rendu bitmap, stockage local, géocodeur optionnel et partage natif. Un moteur local de correspondances/homographie peut produire le même résultat de recalage. Aucun appel serveur Apple n'est nécessaire au cœur de l'outil. Le géocodeur iOS est optionnel ; saisie de ville manuelle toujours possible.

Contrat du recalage : deux fichiers raster, orientation déjà normalisée. L'image Après est centrée et recadrée au ratio de l'image Avant **sans déformation**, puis mise aux mêmes dimensions de travail. Sortie indépendante :

- `quality` : `excellent`, `correct`, `weak`, `failed` ; estimation visuelle, pas précision métrologique ;
- `corners` : quatre points normalisés **origine en bas à gauche**, dans l'ordre bas-gauche, bas-droite, haut-droite, haut-gauche ; déplacement de l'image **Après vers Avant** ;
- `crop` : rectangle normalisé commun aux deux images, même origine ;
- `score` : corrélation des intensités de contours ; optionnel et non assimilable à une probabilité ;
- `message` : texte explicatif. En cas de qualité faible/échec, pas de transformation appliquée.

Android doit convertir les coordonnées si son moteur utilise une origine en haut à gauche. Aucun `VNObservation`, `CGAffineTransform`, nom d'objectif Apple ou chemin absolu n'est nécessaire à la relecture du résultat. `libraryIdentifier` est une provenance iOS facultative ; les fichiers locaux sont la source utilisée à la réouverture.

## Format local version 1

`Application Support/BeforeAfter/<UUID>/project.json` + `before.jpg`, `after-<UUID>.jpg`, `thumbnail.jpg`.

- UUID en chaîne ; dates création/modification **ISO 8601 UTC** (seconde).
- Noms de fichiers relatifs contrôlés ; pas de chemin absolu persistant.
- `mode` : `sideBySide`, `vertical`, `horizontal`, `diagonal`.
- `divider` : 0...1. Vertical : x ; horizontal : y depuis le haut ; diagonal : demi-plan **x+y ≤ 2×divider**, coordonnées écran normalisées depuis le haut gauche. Position 0 = tout Après, position 1 = tout Avant.
- Texte entreprise/ville et activation ; préférence watermark, soumise au fournisseur de droits au moment du rendu, jamais à la seule valeur du JSON.
- Métadonnées réellement présentes seulement. La date de prise EXIF est gardée telle quelle (fuseau inconnu possible).

Écriture des images avant référencement puis remplacement atomique du JSON ; capture sauvegardée avant le calcul Vision. La suppression d'un projet supprime uniquement son dossier UUID, jamais la photo de la photothèque. Les versions de schéma inconnues ne sont pas écrasées.

## Métadonnées et confidentialité

Lecture ImageIO de marque, modèle, dimensions, orientation, date EXIF, objectif, focale, équivalent 35 mm, ISO, temps d'exposition, ouverture, correction d'exposition et GPS si valides. Données manquantes non inventées. Les métadonnées importées ne sont pas forcément authentiques : la correspondance de modèle n'est pas une preuve du téléphone exact.

Le sélecteur Photos n'exige pas l'accès global à la photothèque. Un transfert iCloud indisponible est signalé, sans créer un faux projet. Les photos de travail sont réencodées **sans EXIF/GPS**, résolution maximale 2 400 px au grand côté. Les métadonnées utiles sont conservées dans le JSON privé. Miniature 320 px ; aperçu environ 1 000 px ; export 2 000 px par photo (jusqu'à 4 000 px de large en côte à côte). L'original de la photothèque reste intact ; le projet ne constitue pas une sauvegarde pleine résolution de celui-ci.

La ville n'est recherchée qu'après confirmation de l'utilisateur : Apple peut recevoir les coordonnées pour son géocodage. Seule la localité est retenue ; aucun nom de rue/adresse précise dans le branding. Aucun GPS n'est ajouté au JPEG exporté. Pas d'envoi des images à une IA ni à un service de retouche.

## Compatibilité caméra honnête

La marque/modèle EXIF de l'Avant est comparée au modèle EXIF **réellement observé lors d'une capture par cet outil** sur ce matériel, mis en cache par identifiant matériel. Au premier lancement, le modèle est inconnu et aucun réglage n'est importé automatiquement. Pas de table spéculative d'identifiants de modèles d'iPhone.

Si le modèle est vérifié et que ISO + durée sont présents, une option permet d'approcher l'exposition, bornée aux capacités de l'objectif actif. Sinon exposition automatique. Focale, ouverture, balance des blancs et distance de mise au point ne sont **pas** prétendues reproduites. Le choix d'objectif est manuel parmi les caméras arrière physiques disponibles. Le résumé indique les valeurs réellement appliquées, et un changement d'objectif remet en automatique.

Caméra conçue pour tenir l'iPhone verticalement ; preview et capture sont orientées pareil puis cadrées au ratio de l'Avant. Les images paysage sont acceptées, mais le cadrage central peut rogner fortement la capture. Le guide est en proportions correctes. Clignotement supprimé ; seuls les traits blancs de l'Avant sont superposés au flux live. Arrêt de session quand on quitte ou passe en arrière-plan.

## Interface caméra actuelle — retour au calque photo

À la demande de l'utilisateur, les traits ont été retirés du parcours caméra, ainsi que
leur extraction. Le modèle reste dans le dépôt pour préserver l'expérimentation, mais
la caméra ne l'exécute plus. L'image Avant est superposée en couleurs naturelles à 20 %
par défaut, opacité 5–60 %, teinte bleue facultative. Aucun calque n'est incorporé au JPEG.

Interface fixe sur fond noir : grand viseur, bouton de capture rond centré en bas,
visibilité et teinte du calque à gauche, opacité +/- à droite. Objectifs au-dessus du
déclencheur. Menu supérieur pour prise automatique et exposition compatible. Le retour
de cadrage reste compact sur le viseur, avec contrôle temporel conservateur ; le flash
confirme une capture réussie. Pas de balayage de traits ni de délai visuel avant capture.
Les proportions Avant/viseur/capture sont conservées ; le mode portrait reste attendu.
Les sections qui suivent sur le guide de dessin sont historiques, pas le comportement actif.

## Historique : guide de dessin simplifié — 17 septembre, 17:55

TEED embarqué sous licence MIT extrait les probabilités de contours. Le post-traitement
portable retire les zones denses et les fragments courts, réduit les contours en lignes
simples et produit des polylignes normalisées. Le rendu est blanc sur fond transparent,
avec un halo léger en caméra. Par défaut la photo Avant est aussi affichée derrière
ces traits, légèrement teintée en bleu. « Afficher la photo d’origine » contrôle ce
calque léger à 10 %, curseur de 5 à 25 %. « Afficher les traits » et leur intensité
restent indépendants. Ces réglages visuels ne sont pas incorporés à la photo capturée,
et ne modifient pas l'analyse de cadrage. Le balayage de traits respecte leur visibilité.
L'extraction se fait une fois, hors thread principal, sans réseau ; l'analyse de cadrage
live existante reste distincte et bornée. Guide absent : message explicite et capture manuelle,
pas de déclenchement automatique. Balayage lumineux avant capture et flash après succès conservés.

Le modèle CoreML iOS et l'export ONNX partagent les mêmes poids et le même prétraitement.
L'interface d'extraction et les polylignes n'exposent aucun type Apple. Conversion, attribution,
hashes et contrat Android : `scripts/structural_guide/README.md`. La future version Android
devra encore implémenter son adaptateur et faire ses propres validations matérielles.

Contrôle avec la photo réelle fournie, sans l'ajouter au dépôt : tracé blanc inspecté,
textures des pierres largement éliminées. Des joints de carrelage restent visibles et des
contours peuvent être interrompus : ce n'est pas une segmentation parfaite des objets.
28 tests ciblés passent (transparence, orientation, faible contraste, textures denses,
modèle embarqué, guidage et capture, stockage/export). Résultat
`Test-Plaquisto-2026.09.17_17-53-11-+0200.xcresult` ; build iPhone réussi.
Installation physique Lab confirmée à 17:55, séquence 2216. Aucune capture réelle ni
mesure de performance sur l'iPhone n'est revendiquée.

## Recalage

L'adaptateur iOS emploie une requête homographique Vision à environ 720 px : cible flottante Après, référence fixe Avant. Transformation appliquée avec Core Image aux coins, sans recalcul au déplacement du séparateur. [Contrat Apple de l'observation homographique](https://developer.apple.com/documentation/vision/vnimagehomographicalignmentobservation).

Validation conservatrice : coins finis et mouvement limité, polygone convexe, intersection commune suffisante ; corrélation des contours suffisante et non dégradée par rapport aux images non recalées. Les images unies ne valident pas un faux recalage. Recadrage identique des deux images pour éviter les bandes transparentes. L'utilisateur peut désactiver un recalage retenu et revenir aux photos non recalées. Échec et qualité faible conservent le comparatif simple.

Limites : changement de point de vue avec parallaxe, murs transformés, scène fortement modifiée, surfaces sans texture et reflets peuvent empêcher un bon recalage. Une homographie n'est pas une reconstruction 3D. Les qualificatifs sont heuristiques ; vérification visuelle toujours demandée.

## Vérifications à effectuer sur iPhone

- Autorisation caméra (accord/refus), retour depuis Réglages, interruption, verrouillage/arrière-plan.
- Import photo locale/iCloud, EXIF absent, portrait/paysage, grand-angle, téléphone différent.
- Reprise de cadrage en chantier, visibilité/opacité des traits blancs et objectifs ; exposition compatible lorsqu'une capture a fourni le modèle exact.
- Alignement avec petits mouvements et scène réellement rénovée ; aucun succès trompeur sur scènes différentes.
- Sauvegarde, arrêt complet, réouverture et réexport ; partager et annuler ; enregistrer via Photos/Fichiers.
- Ces validations matérielles ne sont pas remplacées par la compilation ni par les tests sur images synthétiques.

## Historique des vérifications initiales du 17 septembre 2026 (avant le nouveau guide)

- **113 tests réussis, 0 échec, 0 ignoré**, dont **18 nouveaux tests Avant/Après**. Source du comptage : `xcresulttool get test-results summary` et non décompte du journal entrelacé.
- Résultat : `/tmp/PlaquistoLayoutTestsDerived/Logs/Test/Test-Plaquisto-2026.09.17_10-35-16-+0200.xcresult`.
- Compilations finales Lab simulateur et iPhone réussies : `/tmp/plaquisto-beforeafter-release-build.log` et `/tmp/plaquisto-beforeafter-release-device.log`.
- `swiftc -typecheck` des deux fichiers Models/Services seuls réussi, sans les fichiers d'adaptation Apple.
- Contrôle manuel simulateur : import via le sélecteur Photos d'une photo de démonstration, lecture EXIF (Nikon, focale, ISO, exposition, date, GPS), écran compatible avec métadonnées manquantes pour le modèle du téléphone, projet relu après redémarrage.
- Pour contrôler les écrans de comparaison sans caméra physique, un projet de QA a reçu deux références à la même photo. Il est explicitement marqué comme fixture, pas comme capture réelle. Vérification de reprise du recalage, choix diagonal, branding manuel, export et partage natif ; aucun envoi ni géocodage déclenché.
- Le premier contrôle du JPEG a révélé un placement de texte et un mélange alpha incorrects : corrigés, contrôle visuel du JPEG final effectué, test de non-régression ajouté (texte dans l'image, fond réellement translucide).
- Le séparateur possède un repère visible ; son masque et sa position sont les mêmes dans l'aperçu et le rendu. Le glissement sur la photo est prioritaire au défilement de page.
- Vérification finale du glissement diagonal : position passée de 50 % à 64 %, puis enregistrée et retrouvée dans le JSON (`0.640388573141977`). Version finale installée et relancée dans le simulateur Lab.
- Le seul projet de démonstration créé pour ces contrôles a été retiré de l'application et archivé, récupérable dans `/tmp/plaquisto-beforeafter-qa.D1gDYi/`. Aucun projet utilisateur ni original de la photothèque n'a été supprimé.
- **Pas de validation matérielle de caméra, d'objectif ou d'exposition réelle**, et pas d'installation physique revendiquée pour cette nouvelle fonctionnalité. Test chantier encore nécessaire.

Fichiers intégrés hors module : `ToolsHomeView.swift` (destination), `ToolModels.swift` (rubrique/recherche), `project.pbxproj` (sources + autorisations caméra/enregistrement photo). Les modifications antérieures des autres outils dans le worktree ont été préservées ; elles ne font pas partie de ce nouvel outil.
