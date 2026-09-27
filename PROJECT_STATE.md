# Plaquisto — état du développement

## Réemploi des chutes et quinconce — 27 septembre 2026

- Lot précédent poussé directement sur `origin/main` à la demande utilisateur :
  `de39748`. Application signée installée sur l’iPhone d’Édouard, séquence 3244
  (`/tmp/plaquisto-usability-install.json`). Lancement automatique refusé car
  téléphone verrouillé ; installation confirmée indépendamment du lancement.
- Nouveau lot isolé sur `codex/offcuts-staggered-layout`, depuis ce commit.
  Réemploi limité au calepinage affiché et au format de la couche active.
  Minimum fixe de 200 mm dans les deux directions, sans réglage utilisateur.
  Un destinataire réutilisé doit toucher deux axes d’ossature distincts, ou une
  périphérie extérieure et un axe distinct. Les ouvertures, contacts ponctuels
  et fragments colinéaires d’une même fourrure ne créent pas d’appui supplémentaire.
- Découpe conservatrice par enveloppes rectangulaires sans rotation : aucune
  matière fictivement récupérée dans les trous, concavités ou coupes diagonales.
  Les pièces disjointes d’une même case gardent leur position relative.
  Comptage distinct des cases, morceaux et plaques à acheter ; repères 2-1/2-2
  pour une même plaque. Fiche de découpe dans les coordonnées de la plaque brute,
  avec les autres morceaux de cette plaque en pointillés et les perçages conservés.
- Option quinconce dans Plaques et pose : bandes alternées décalées dans le sens
  long ; décalages compatibles avec l’entraxe, pas une demi-plaque imposée.
  Aucun joint horizontal ajouté sur un mur couvert en une seule hauteur.
  Grille pendant les gestes et résultat utilisent la même géométrie ; joints
  en T reconnus. Réglages facultatifs Codable pour relire les anciens documents.
- Optimiser compare désormais les plaques réellement nécessaires après réemploi,
  puis cherche un décalage de quinconce compatible parmi des candidats bornés.
  Pas de garantie d’optimum global ni de conformité technique de tous les joints,
  bords amincis ou prescriptions de pose ; limite explicitée dans le formulaire.
- Vérifications terminées : tests de conservation de matière, non-chevauchement
  des découpes, appuis, minimum 20 cm, quinconce/rotations/ouvertures, sauvegarde,
  coordonnées des autres morceaux et optimisation. Suite complète : 303 tests
  réussis, dont 14 nouveaux (`/tmp/plaquisto-offcuts-release-check.log`).
  Compilation iPhone signée réussie (`/tmp/plaquisto-offcuts-device-final.log`).
  Contrôle visuel sur simulateur : plafond 3×3 m, six morceaux issus de quatre
  plaques, bascule quinconce à 120 cm, sélection de 4-2 avec 4-1 en pointillés
  dans la même plaque brute, cotes 120×60 cm, exécution du bouton Optimiser.
  Livraison autorisée puis fusionnée et poussée sur `main` : `fb01f3e`.
  Application signée installée et lancée sur l’iPhone d’Édouard, séquence 3252.
  Confirmations : `/tmp/plaquisto-offcuts-install.json` et
  `/tmp/plaquisto-offcuts-launch.json`.

## Ergonomie relevé, gestes et initialisation du calepinage — 27 septembre 2026

- Branche `codex/survey-layout-usability`, depuis `origin/main` après la PR #2.
  Aucun changement de l’acquisition RoomPlan ou des données du scan initial.
- Onglet Plafonds : état vide explicite et accès direct au choix de zone puis au
  configurateur. L’enregistrement du plan reste explicite. Mode sombre harmonisé
  pour le papier du plan, les murs, les fonds de scène et les miniatures en cache.
- Éditeur 2D : déplacement de vue en direct ; sélection puis translation du
  segment ou redimensionnement par poignées. Nouvelle cloison en deux appuis,
  brouillon ajustable, longueur/hauteur et choix de l’extrémité fixe avant Ajouter.
  Aimants aux extrémités, aux murs, parallèles/perpendiculaires aux directions du
  scan (pas aux axes mondiaux), avec hystérésis, guide et retour haptique.
  Aimantation désactivable et annulation du dernier geste. Les appuis et drags
  sont exclusifs ; un drag très bref est traité même sans callback intermédiaire.
- Une cloison projetée reste indépendante du contour scanné, même si son départ
  touche un angle du relevé. Une correction du mur scanné prévisualise les
  jonctions effectivement déplacées. Refus des nouveaux croisements et
  chevauchements colinéaires ; jonctions en T permises. Les portes suivent une
  translation et gardent leur emplacement lors d’un allongement colinéaire.
  Validation lourde au relâchement ; recherche des fusions hors boucle de drag.
- Recommandations et relecture de l’agent au profil artisan/SketchUp intégrées.
  Il s’agit d’un profil simulé, non d’un essai terrain avec un artisan réel.
- Nouveaux calepinages de plafond : grand côté des plaques perpendiculaire au
  bord le plus long, format 120×240 cm, fourrures visibles à 60 cm. Depuis un
  ouvrage : reprise du format couvrant la plus grande surface cumulée et de
  l’entraxe configuré. Aucun écrasement des calepinages déjà enregistrés.
  Deux boutons ronds font défiler le mur de référence dans les deux sens.
- Formulaire plafond horizontal : entraxe présenté avant le plénum à l’étape 4.
- Vérification : 289 tests réussis, dont 11 nouveaux tests sur orientation,
  import des réglages, conservation des plans, thème et gestes/géométrie.
  Logs : `/tmp/plaquisto-gestures-verified.log` et compilation iPhone signée
  `/tmp/plaquisto-usability-device.log` (réussie). Preuve autonome compilation,
  sauvegarde/relecture : `/tmp/plaquisto-gestures-proof.log`.
- Essais sur simulateur : création provisoire et ajout, translation par corps et
  poignée centrale sans déplacement du contour, allongement, aimantation au mur,
  annulation et désactivation des aimants, plan sombre, accès direct aux plafonds.
  Le pincement multi-touch et les vibrations restent à vérifier sur iPhone.
  Option de preuve : `Tests/run-room-model-proof.sh <simulateur> --configure-ceilings`.
- Livraison ultérieure : commit `de39748`, poussé sur main et installé sur iPhone
  (voir section ci-dessus). Réemploi des chutes/quinconce exclu de ce lot : portée limitée au
  calepinage affiché, minimum fixe de 20 cm (sans réglage utilisateur), appui sur
  deux fourrures ou périphérie + une fourrure, décalage adapté aux fourrures.

## Préréglage des plafonds après scan — 27 septembre 2026

- Expérimentation isolée sur `codex/ceiling-auto-fit`, issue de `origin/main`
  après fusion de la PR #1. Aucun changement du pipeline d’acquisition RoomPlan.
- Nouveaux plafonds : forme plate par défaut, hauteur issue des murs de la zone.
  Au premier choix d’une autre famille, recherche de l’orientation, des hauteurs
  et du faîtage compatibles avec les profils hauts réellement conservés.
  Calcul et génération du maillage partagent les mêmes équations de plans.
- Échantillonnage limité aux bords du plafond choisi, au même niveau ; exclusion
  des murs éloignés et des limites de découpe sans mur. Pondération par longueur,
  ajustement robuste aux petits écarts ; préservation des profils fragmentés.
  Les murs, les plafonds voisins et le relevé initial ne sont jamais modifiés.
- Sans information suffisante sur le faîtage : proposition centrée orientée selon
  la pièce, dénivelé initial de 50 cm ou conservation du dénivelé saisi. L’absence
  de déduction est affichée et conservée dans `riseIsEstimated`, champ facultatif
  pour les anciennes sauvegardes. Le résultat reste une hypothèse à vérifier.
- Éditeur : « Ajuster aux murs », annulation du dernier ajustement utile (une
  répétition identique ne détruit pas ce retour), conservation des corrections
  par famille pendant l’édition, rotation de 90°, écarts >5 cm matérialisés en
  orange dans l’aperçu. Les curseurs restent manuels et l’enregistrement explicite.
- Plafonds multiples : sélecteur avec miniature situant chaque zone dans le plan,
  ajout distinct et modification par identifiant, accès direct à la séparation
  cuisine ouverte/salon. Titre Plafond A/B à la réouverture ; « Appliquer »
  distingue le brouillon du plan de son enregistrement final. Correction d’une
  position de faîtage après découpe qui pouvait sortir de la plage autorisée.
- Tests : 278 tests iOS réussis, dont huit nouveaux scénarios (pignons décentrés,
  rotation/translation, mono-pente, profils subdivisés, absence d’information,
  étages, découpe et cuisine/salon indépendants après sauvegarde/relecture).
  Log : `/tmp/plaquisto-ceiling-fit-full-tests.log`.
- Les deux agents aux profils artisan expérimenté et novice ont relu le parcours.
  Leurs retours sur la conservation des réglages, le faîtage non mesuré,
  l’annulation répétée et la lisibilité de l’enregistrement ont été intégrés.
  Les deux agents ont ensuite manipulé réellement l’éditeur sur simulateur, via
  `Tests/run-room-model-proof.sh <simulateur> --ceiling-zones` : cuisine A plate
  2,50 m / 16 m², salon B deux pans ajusté à 2,50–3,70 m / 18,66 m²,
  réouverture indépendante, deux ajustements puis annulation vers 2,80 m saisis,
  mémoire par forme, annulation de la fiche sans sauvegarde et enregistrement
  final du plan suivi d’une relance conservant A/B et leurs valeurs.
  Accès/annulation de la découpe vérifiés ; découpe effective couverte par tests
  automatisés. Suite à leurs retours, accès direct au sélecteur visuel, titre
  non tronqué, aucun numéro changeant sur les zones à créer, nom et remplissage
  orange du plafond pendant une découpe. Ce sont des profils d’artisans simulés,
  pas une validation de terrain sur un nouveau scan réel.
- Compilation iPhone signée finale réussie :
  `/tmp/plaquisto-ceiling-fit-device-final.log`. Preuve portable sauvegarde/relecture
  et compilation de l’éditeur autonome réussies. Captures d’essai :
  `/tmp/plaquisto-artisan-plan-ab.png`,
  `/tmp/plaquisto-artisan-salon-b-250-370.png`,
  `/tmp/plaquisto-artisan-memory-280.png`.
  Développement sur `codex/ceiling-auto-fit`, commit fonctionnel `cf442bf`.
- Installation demandée ensuite et confirmée sur l’iPhone à 14 h 51 le
  27 septembre, séquence 3228 (`/tmp/plaquisto-ceiling-fit-install.json`).
  Lancement confirmé (`/tmp/plaquisto-ceiling-fit-launch.json`).

## Relevés dans les projets, plafonds multiples et plan d’architecte — 26 septembre 2026

- Relevés du projet : miniature 3D statique 288×216, cache borné à 24 images /
  12 Mo invalidé par la géométrie et les transformations ; pas de scène animée
  dans chaque ligne. Balayage gauche « Supprimer », sans suppression par
  balayage complet, puis confirmation. Les ouvrages dérivés, leurs composants,
  calepinages et quantités sont conservés ; seuls leurs liens vers ce relevé
  sont détachés. Pas de suppression des fichiers bruts de récupération.
- Depuis le résultat du scan : « Enregistrer le relevé dans un projet » fonctionne
  sans sélectionner de surfaces ni créer un ouvrage. Choix d’un projet existant
  ou formulaire nouveau projet, nom de relevé facultativement personnalisé.
- Adresse : position ponctuelle pendant la capture, uniquement après accord
  iOS, précision ≤100 m, fraîcheur ≤30 s, délai maximal 20 s. Coordonnées
  portables dans la sauvegarde ; recherche d’adresse depuis ce point enregistré,
  jamais depuis la position actuelle à la réouverture. Le texte reste modifiable ;
  ni saisie manuelle ni adresse d’un projet existant ne sont écrasées. Ancien
  scan sans position / refus / erreur réseau : saisie manuelle. GPS exclu du
  diagnostic complet et aucun suivi de position en arrière-plan.
- Consultation de l’agent artisan SketchUp : aperçu fixe au-dessus des réglages
  défilants (à gauche en paysage), valeurs près des curseurs, aide détaillée
  repliée, conservation du dernier aperçu valide pendant une saisie invalide.
  Le plafond travaillé est surligné et sa propre surface est affichée.
- Plafonds : ajout indépendant par zone fermée, sans remplacer le voisin ;
  les cloisons dessinées peuvent participer à la délimitation. Menu Plafonds →
  plafond → « Découper en deux zones » : deux points définissent une limite
  droite, opération répétable dans la même pièce. Découpe des plans existants,
  contrôle de conservation d’aire, aucun changement des murs/scan initial.
  Les trous et découpes produisant plusieurs îlots sont refusés explicitement ;
  ce n’est pas un éditeur libre de polygones/trémies de plafond.
- Après découpe : altitude de référence conservée, hauteurs min/max recalculées
  pour chaque moitié, réouverture sans saisie ne régénérant pas sa géométrie.
  Les formes/hauteurs de chaque zone restent modifiables séparément.
- Repères persistants par plafond parent au niveau du relevé : A, B, C…,
  identiques dans les menus et plans ; les pans d’un même plafond sont A · pan 1,
  A · pan 2 pour leur sélection métier. L’ajout dans une zone précédente ne
  renumérote pas les autres. Copie de projet : nouvelle identité, mêmes repères.
- Plan 2D commun : fond papier, murs anthracite, ouvertures en interruption
  avec jambages / double trait pour fenêtres, faîtages fins, cotes en mètres
  à deux décimales déportées et orientées, collisions entre textes évitées,
  étiquettes de plafond à l’intérieur de la surface.
- Capture native RoomPlan / assemblage Apple inchangés, hormis la prise GPS
  ponctuelle indépendante. Aucune reconstruction automatique de plafond ajoutée.
- Vérification finale : **270 tests passent**, zéro échec, après les retouches
  de centrage des cartouches. Test de miniature et
  plan A/B avec pièces jointes, tests découpe 4 familles / hauteurs / persistance /
  ajout sans écrasement / suppression sans perte des ouvrages / GPS facultatif.
  Contrôle interactif sur simulateur : création, curseurs avec aperçu fixe,
  défilement, découpe A/B au toucher. Compilation iPhone signée finale réussie.
  Journaux : `/tmp/plaquisto-survey-ux-final-tests.log`,
  `Test-Plaquisto-2026.09.26_18-37-30-+0200.xcresult`,
  `/tmp/plaquisto-survey-ux-final-device.log`.
  Installation demandée et confirmée sur l’iPhone à 18 h 39, séquence 3188
  (`/tmp/plaquisto-survey-ux-install.json`). Aucun commit ni push.

## Création d’ouvrage depuis le scan : précision des champs — 26 septembre 2026

- Cause du refus « Les dimensions du formulaire ne correspondent plus… » :
  `ZeroEmptyDecimalTextField.synchronizeText()` arrondissait l’affichage à deux
  décimales ; son ancien `onChange(text)` réinjectait ensuite cet arrondi dans
  la mesure métier, même pour les champs désactivés du formulaire issu du scan.
  Cela invalidait `activeMeasuredRuns` puis le contrôle strict à l’enregistrement.
- Correction au niveau du champ partagé : une liaison de saisie dédiée met à
  jour la valeur uniquement lorsque le texte provenant du clavier change.
  La synchronisation d’affichage écrit directement l’état texte. Les échos UIKit
  inchangés à la validation/fermeture ne réécrivent plus les mesures originales.
  Les contrôles du relevé et les tolérances d’enregistrement sont inchangés.
- Régression reproduite avant correction dans un vrai hôte SwiftUI avec les
  champs désactivés : hauteur 2,537842 → 2,54 ; surface 10,960335591604002 → 10,96 ;
  `createSurveyWork` rejette avec `changedDimensions`.
  Log `/tmp/plaquisto-precision-before.log`.
- Tests ajoutés : champs préremplis → création de doublage sur fourrures →
  sauvegarde/relecture sans perte de précision ; focus sans saisie, saisie réelle,
  effacement et rejet de NaN. **262 tests réussis**, zéro échec, dont le test
  rouge avant correction devenu vert :
  `Test-Plaquisto-2026.09.26_17-55-13-+0200.xcresult`,
  `/tmp/plaquisto-precision-tests.log`. Compilation iPhone signée réussie
  (`/tmp/plaquisto-precision-device.log`). Installation confirmée à 17 h 56,
  séquence 3180 (`/tmp/plaquisto-precision-install.json`). Aucun commit ni push.

## Maquette après scan — style partagé et réutilisation du rendu — 26 septembre 2026

- Consultation `docs/CONSULTANT_RENDU_MAQUETTE_3D.md` appliquée au moteur
  **SceneKit existant**, sans migration RealityKit ni changement de capture.
- `MaquetteStyle` mutualise murs ivoire mats, plafonds neutres, parquet clair
  discret (texture procédurale exactement 512 × 512 pixels), sélection ocre,
  éclairage studio et ombres douces. Aucun habillage ne modifie les mesures.
- Matériaux partagés immuables, variantes séparées sélection/affectation et
  transparence ; pas de mutation d’un matériau commun lors d’un clic.
- `RoomDomainScene` conserve ses maillages et sa caméra pour les changements
  de sélection/visibilité. `SurveySurfaceScene` invalide son cache sur les
  données réelles (géométrie, ordre, transformations, état de liaison), pas
  seulement la date du relevé. Les UV sont calculées avant transformation.
- Rendu non continu au repos ; qualité allégée lors d’une actualisation en
  mode économie d’énergie ou état thermique sérieux/critique (30 FPS cible,
  ombres 512, sans occlusion ambiante). Profil normal : 60 FPS cible, ombres
  1024. Ce sont des plafonds de cadence, pas une garantie de performance.
- Aucun changement de géométrie, d’éditeur, de persistance métier ni de
  quantitatifs. Les plafonds restent créés explicitement après le scan.
- Validation : **260 tests réussis**, zéro échec/ignoré, dont matériaux isolés,
  texture 512 pixels, conservation de scène/caméra, invalidation sur édition,
  UV stables après translation et rotation. Rapport
  `Test-Plaquisto-2026.09.26_16-14-23-+0200.xcresult`, log
  `/tmp/plaquisto-style-tests-final.log`. Preuve indépendante sauvegarde/lecture
  réussie ; aperçu architectural et sélection de deux murs contrôlés visuellement
  sur simulateur. Compilation iPhone signée réussie :
  `/tmp/plaquisto-style-device-final.log`.
- Relecture consultant : pas de blocage. Limites : profil économique actualisé
  lors des mises à jour SwiftUI (pas immédiatement pendant l’orbitage seul),
  calcul des surfaces métier encore effectué en amont du cache de scène.
  Énergie, RAM et cadence réelle restent à mesurer sur appareil.
- Installation sur l’iPhone confirmée à 16 h 17 (séquence 3172,
  `/tmp/plaquisto-style-install.json`), lancement confirmé à 16 h 18
  (`/tmp/plaquisto-style-launch.json`). Aucun commit ni push.

## Capture native conservatrice, plafonds après scan — 26 septembre 2026

Cette décision remplace les itérations jaune/vert et de reconstruction automatique
décrites plus bas. Aucun plafond n’est recherché ou validé pendant l’acquisition.

- `RoomPlanScanner` : retrait de l’overlay jaune/vert, de la configuration ARKit
  personnalisée, du polling/copie de mesh et des reconstructions live/finales.
  Une acquisition RoomPlan native, son aperçu natif, ses callbacks transmis et
  les sauvegardes périodiques restent en place. Aucun recalage ni redémarrage à
  un changement de pièce. Les anciens moteurs purs restent testables, mais ne
  sont plus appelés par le scanner.
- Cause des murs sous rampant rectangulaires identifiée dans l’adaptateur :
  `CapturedRoom.Surface.polygonCorners` était ignoré. Import du contour local
  complet, sauvegardé dans `PlaquistoWall.localOutline` (optionnel pour les
  anciennes sauvegardes). Conservation des sommets et concavités, profil haut
  et bas ; les anciens murs sans contour gardent leur rectangle disponible.
- Le rendu, les surfaces brutes/nettes et l’export vers le calepinage utilisent
  ce contour. Aucun plafond, même validé, ne redécoupe implicitement les murs.
  Une correction manuelle de hauteur redimensionne le profil proportionnellement
  plutôt que de supprimer le rampant. `initialRoom` reste inchangé.
- Éditeur après scan : création explicite du plafond (plat, un/deux/quatre pans,
  hauteurs et aperçu, valeurs suggérées signalées comme estimations), correction
  largeur/hauteur/allège/position des ouvertures, suppression avec confirmation.
  Fusion explicite de deux murs contigus coplanaires partageant un bord complet ;
  refus des raccords incompatibles, des épaisseurs divergentes et des ouvertures
  invalides. Le premier ID est conservé, les ouvertures sont réaffectées avec
  leur position, l’original et les plafonds restent intacts. Les ouvrages déjà
  créés restent à vérifier après modification d’un relevé.
- Diagnostic complet toujours partageable et durable ; le rapport annonce
  `ceilingWorkflow: postscan_manual` et `wallGeometry: native_polygon_corners`.
  Zéro tentative de plafond signifie fonctionnalité retirée, pas échec LiDAR.
- Validation : **257 tests iOS réussis**, zéro échec/ignoré. Rapport
  `Test-Plaquisto-2026.09.26_15-47-00-+0200.xcresult`, log
  `/tmp/plaquisto-native-profiles-final-tests.log`. Preuve indépendante de
  sauvegarde/lecture réussie ; contrôle visuel simulateur des champs de fenêtre
  et de l’aperçu 3D de création d’un plafond absent (12,84 m² sur fixture).
  Le contrôle a aussi permis de corriger le message d’erreur d’un ancien plafond
  protégé : ne plus accuser les hauteurs lorsqu’un remplacement est refusé.
- Compilation signée finale réussie (`/tmp/plaquisto-native-profiles-device-ui.log`).
  Installation sur l’iPhone d’Edouard confirmée à 15 h 52, séquence 3164,
  `/tmp/plaquisto-native-profiles-install-final.json`. Ouverture de cette version
  sur l’iPhone confirmée à 15 h 54 (`/tmp/plaquisto-native-profiles-launch-final.json`). La capture réelle
  reste à vérifier sur un nouveau scan ; les anciens contours perdus ne sont pas
  recréés artificiellement. Aucun commit ni push.


## Diagnostic partageable et durable des scans — 26 septembre 2026

- Menu « … » de la maquette 3D / plan 2D : « Partager le diagnostic complet ».
  Ouvre une fiche explicative puis le partage natif d’un fichier JSON. Disponible
  sur les relevés récupérés et depuis les projets, indépendamment du modèle Scanner
  encore présent ou non en mémoire.
- Rapport optionnel sauvegardé dans `ScanCampaignDraft` aux checkpoints et à la
  finalisation, puis copié dans `ProjectSurveyRecord` lors du rattachement au projet.
  Contient état réel de configuration mesh, compteurs, événements, 120 dernières
  tentatives de reconstruction et diagnostic final. Ne modifie pas la détection.
- Anciens scans : export des données encore disponibles, mention explicite
  « diagnostic partiel ». Aucune invention de compteurs ou de motifs de refus.
  Géométrie courante séparée du rapport d’acquisition ; noms des pièces retirés
  de cette géométrie exportée. Ni photos, ni maillage brut, ni coordonnées client.
  Positions relatives et plan peuvent figurer dans le rapport (signalé avant partage).
- Le scan de 13 h 59 a été récupéré pour diagnostic avant cette modification :
  31 murs, un sol, aucun plafond, événement `ceiling_mesh_requested` présent.
  Aucun rapport détaillé n’avait été sauvegardé : il ne peut pas être reconstitué
  rétrospectivement à partir des seuls murs.
- Tests ajoutés : persistance/réouverture/export, lecture d’anciens scans sans
  rapport, transfert au projet et récupération sans fichier de brouillon.
- Validation : **252 tests réussis**, zéro échec/ignoré ; compilation iPhone signée
  réussie, `git diff --check` propre. Traces `/tmp/plaquisto-durable-diagnostics-tests.log`
  et `/tmp/plaquisto-durable-diagnostics-device.log` ; résultat
  `Test-Plaquisto-2026.09.26_14-58-26-+0200.xcresult`.
- Contrôle UI simulateur sur une copie locale du scan de 13 h 59 : ouverture
  du relevé récupéré, menu « … », commande de partage, avertissement partiel,
  puis feuille native présentant le JSON de 57 ko. Aucun fichier envoyé.
  Pas d’installation physique pour cette étape ; aucun commit ni push.

## Reconstruction assistée des plafonds rétablie — 26 septembre 2026

- Retour à la décision du 11 septembre : une portion de plafond réellement
  observée sert à ajuster un plan (ou deux rampants opposés observés), puis à
  reconstruire la surface jusqu’au contour des murs et aux limites proposées.
  Proposition jaune, validation explicite, surface verte et figée ; aucun plafond
  créé automatiquement à partir de la hauteur des murs ou de la projection du sol.
- Cause technique corrigée : l’acquisition précédente attendait passivement des
  ancres mesh sans activer leur production. `RoomCaptureView(frame:arSession:)`
  reçoit maintenant une session commune configurée une seule fois au démarrage
  avec `.meshWithClassification` et la détection de plans. Intégration publique
  Apple (WWDC23, « Explore enhancements to RoomPlan », Custom ARSession).
  Pas de reset de repère, de remplacement du delegate ARKit, de boucle de
  reconfiguration ni de transition artificielle entre pièces. Maquette native,
  édition après scan et création d’ouvrages conservées.
- Les observations classées plafond sous la bande haute des murs ne sont plus
  écartées : elles peuvent décrire le bas d’un rampant. Les faces classées meubles,
  sol ou murs sont exclues du calcul live. Les plafonds restent des estimations
  à contrôler, pas une garantie métrologique.
- Sur un relevé contenant plusieurs contours fermés, recherche du contour local
  autour de l’utilisateur avant tout ajustement global. Les passages ouverts
  conservent les propositions de fermeture historiques ; les limites manuelles
  explicites restent prioritaires. Aucun déplacement des murs du relevé.
- Tests ajoutés : configuration ARKit, reconstruction d’un rampant complet depuis
  moins de 1 m² de points, absence de plafond sans observation, gel après validation,
  sauvegarde et sélection locale dans deux pièces adjacentes. Régressions historiques
  cuisine/couloir, formes en L et deux pans relancées.
- Limite distincte inchangée : import des profils `polygonCorners` des murs rampants
  encore à traiter. Cette modification ne prétend pas corriger les profils de murs.
- Validation : **249 tests réussis**, zéro échec/ignoré, ainsi que les contrôles
  autonomes `ScannerCeilingReconstructionChecks` (dont cuisine réelle du 11 septembre,
  deux pièces fermées et contour en L). Builds iPhone signé et Lab réussis ;
  `git diff --check` propre. Résultat `Test-Plaquisto-2026.09.26_13-38-23-+0200.xcresult`
  dans `/tmp/plaquisto-lidar-survey/Logs/Test/`. Traces :
  `/tmp/plaquisto-assisted-ceiling-{full-tests,device,lab}.log`.
- Installation physique confirmée à 13 h 48, `fr.plaquisto.app`, séquence **3148**,
  sans effacement des données. Lancement automatique refusé car iPhone verrouillé
  (`Locked`, code 7) : ouvrir Plaquisto après déverrouillage.
  Traces `/tmp/plaquisto-assisted-ceiling-{install,launch}.json`.
  Le calque AR, la disponibilité réelle du mesh avec RoomPlan et la continuité
  multi-pièces restent à contrôler sur un nouveau scan physique ; aucun test de
  capture réelle revendiqué. Aucun commit ni push.

## Installation iPhone — validation jaune/vert — 26 septembre 2026, 13 h 07

- Version sans estimation automatique des plafonds installée sur l’iPhone
  d’Edouard, `fr.plaquisto.app`, séquence **3140**, sans effacement des données.
- Lancement automatique refusé car l’iPhone est verrouillé (`Locked`, code 7).
  Ouvrir l’app après déverrouillage ; contrôle du calque en capture réelle à faire.
- Traces : `/tmp/plaquisto-observed-ceiling-install.json` et
  `/tmp/plaquisto-observed-ceiling-launch.json`. Aucun commit ni push.
- Remplace le statut « Non installé » de la section suivante.

## Plafonds : retour à la validation visuelle, sans estimation automatique — 26 septembre 2026

- Décision utilisateur : abandonner la création automatique depuis les hauteurs
  des murs ou la projection du sol. Cette décision remplace les sections précédentes.
  Suppression des appels automatiques après capture, à l’ouverture et à l’import,
  ainsi que de la commande « Estimer les plafonds manquants ».
- Retour du calque AR translucide : jaune pour une proposition issue des observations
  du maillage, vert uniquement après « Valider le plafond ». Refuser, Revoir et
  Autre plafond sont disponibles. Une proposition reste figée jusqu’à décision ;
  les plafonds validés précédemment sont conservés dans le même repère natif.
- `ScannerCeilingReview` refuse les propositions estimées/non-LiDAR. Les plafonds
  confirmés conservent leur provenance et `manuallyValidated`, y compris après
  sauvegarde/finalisation. Une proposition refusée ou non validée n’est pas acceptée
  silencieusement à la fin. Aucun remplacement automatique des relevés existants.
- Capture native et configuration ARKit inchangées : aucun maillage forcé ni
  redémarrage de session. Si Apple ne fournit pas de maillage exploitable, aucune
  proposition jaune n’est fabriquée ; un message propose la création manuelle.
- Création manuelle conservée via Modifier le plan → Plafond : contour fermé,
  choix explicite de la forme et des hauteurs, puis Enregistrer. Les hauteurs
  incohérentes des murs ne bloquent plus l’ouverture du formulaire ; elles ne sont
  jamais corrigées. Le moteur d’estimation historique reste pour compatibilité et
  tests, sans appel automatique dans l’app.
- Diagnostic rampant : copies locales des scans 12 h 28 et 12 h 29, zéro plafond.
  Dans le brut RoomPlan `844C35A6-1B37-4DE6-BFD2-2D049B368156`, trois murs possèdent
  des `polygonCorners` inclinés (4/5 sommets). `RoomPlanAdapter` utilise actuellement
  leurs dimensions rectangulaires et ignore ces profils : perte de géométrie à
  l’import, distincte du contrôle jaune/vert. Correction des profils de murs non
  implémentée ici ; ne pas annoncer le problème des rampants comme résolu.
- Aucun fichier du téléphone modifié pendant le diagnostic. Copies :
  `/tmp/plaquisto-rampant-1228.roomplan` et `/tmp/plaquisto-rampant-*.json`.
- Validation : **246 tests passent**, aucun échec ni test ignoré ; builds iPhone
  signé et Lab réussis, `git diff --check` sans erreur. Tests de refus des hypothèses
  estimées, jaune → validation explicite, conservation de plusieurs plafonds,
  rejet, reprise, sauvegarde et ouverture manuelle malgré les hauteurs incohérentes.
  Rejeu local du scan rampant 12 h 28 : deux contours proposés dans le formulaire
  manuel, sans création automatique ni modification du fichier de l’iPhone.
- Traces : `/tmp/plaquisto-observed-ceiling-tests.log`,
  `/tmp/plaquisto-observed-ceiling-device.log`, `/tmp/plaquisto-observed-ceiling-lab.log`.
  Le calque AR et son alignement doivent encore être contrôlés en capture réelle.
  Non installé (dernière installation : séquence 3132). Aucun commit ni push.

## Correction des plafonds absents sur contours déjà fermés — 26 septembre 2026

- Diagnostic sur copie du scan iPhone de 11 h 26
  (`DD211A30-A6F7-4340-A787-4D3EF257C487`, 20 murs, un sol, aucun plafond).
  Le graphe trouvait des contours fermés, mais le solveur historique tentait ensuite
  de réapparier leurs extrémités avec une tolérance de 20 cm : les petits décrochements
  devenaient des jonctions ambiguës et les deux zones principales étaient refusées.
- Les faces ordonnées du graphe utilisent maintenant directement leurs sommets.
  Continuité, absence de croisement, aire et triangulation restent contrôlées ;
  les points ne sont pas déplacés. Le solveur historique reste disponible pour les
  murs non ordonnés, hors de ce chemin. Capture native inchangée.
- Rejeu de la copie : deux plafonds estimés à 2,534 m, de 44,66 et 29,92 m².
  Une petite troisième zone aux hauteurs incohérentes reste volontairement refusée.
  Aucun fichier utilisateur réécrit. Le scan sauvegardé peut être complété via
  « Estimer les plafonds manquants » ; les nouveaux scans utilisent le calcul corrigé.
- Régressions synthétiques ajoutées : petits décrochements de 10/15 cm, contour
  inversé et tourné, sol avec bord de mur manquant et séparation en deux plafonds,
  préservation des murs/sols/relevé initial, sauvegarde et non-duplication.
- Validation : **242 tests passent**, aucun échec ni test ignoré ; builds iPhone
  signé et Lab réussis, `git diff --check` sans erreur. Traces :
  `/tmp/plaquisto-ceiling-contour-tests.log`, `/tmp/plaquisto-ceiling-contour-device.log`,
  `/tmp/plaquisto-ceiling-contour-lab.log`. Diagnostic local :
  `/tmp/plaquisto-ceiling-diagnostic.swift`, `/tmp/plaquisto-ceiling-scan-1126.json`.
- Installé sur l’iPhone à 11 h 39, séquence **3132**, sans effacement des données.
  Lancement automatique refusé (`Locked`, code 7) : ouvrir l’app après déverrouillage.
  Traces : `/tmp/plaquisto-ceiling-contour-install.json` et
  `/tmp/plaquisto-ceiling-contour-launch.json`. Aucun commit ni push.

## Installation iPhone — maquette et plafonds estimés — 26 septembre 2026, 11 h 22

- Version validée ci-dessous installée sur l’iPhone d’Edouard, `fr.plaquisto.app`,
  séquence **3124**, par-dessus l’app existante sans effacement des données.
- Lancement automatique refusé car l’iPhone est verrouillé (`Locked`, code 7).
  Ouvrir manuellement l’app après déverrouillage ; contrôle du rendu et des plafonds
  sur l’appareil encore à effectuer.
- Traces : `/tmp/plaquisto-polished-scene-install.json` et
  `/tmp/plaquisto-polished-scene-launch.json`. Aucun commit ni push.
- Remplace le statut « Non installé » de la section suivante.

## Maquette après scan et plafonds par espace — 26 septembre 2026

- Capture native inchangée. Le rendu de sélection après scan est désormais une
  maquette claire : murs extrudés (épaisseur de présentation de 8 cm si inconnue),
  ouvertures traversantes et tableaux, éclairage/ombres douces, projection
  orthographique, sols texturés discrètement. Texture décorative, pas un matériau
  reconnu. Aucune géométrie de quantitatif modifiée par le rendu.
- Dans l’espace de travail : recentrage, affichage/masquage des plafonds ; masqués
  par défaut, affichés en mode sélection des plafonds. Les IDs de sélection restent
  ceux des surfaces métier. Rotation/zoom et création d’ouvrages sont conservés.
- Estimation uniquement après capture : graphe planaire des murs, intersections et
  jonctions en T, rapprochement d’extrémités limité à 8 cm, faces fermées bornées.
  Les contours de sols observés peuvent compléter des bords absents ; ni enveloppe
  convexe ni rectangle inventé. Les branches ouvertes ne découpent pas une pièce.
- Un plafond estimé par espace exploitable, selon les hauts de ses murs : plat ou
  un pan si les hauteurs sont cohérentes. Les petits retours bas (< 80 cm) ne font
  pas inventer une pente lorsque les murs longs concordent à plus de 80 %.
  Les trémies/vides et les hauteurs incohérentes ne sont pas comblés arbitrairement.
  Aucun mur ni relevé initial n’est corrigé par cette estimation.
- Ce sont des espaces géométriques, pas une classification certaine salon/cuisine.
  Aucun rangement des ouvrages par pièce n’est ajouté. Les plafonds sont marqués
  « estimés », modifiables séparément ; les autres plafonds ne sont pas remplacés.
- Commande « Estimer les plafonds manquants » pour les relevés antérieurs sans
  plafond. Les plafonds déjà présents ne sont pas automatiquement remplacés.
- Vérification sur copie locale du relevé iPhone `4474ACEA-EF16-46DA-91F0-DF784993A240` :
  16 murs, un contour de sol, aucun plafond enregistré ; le traitement produit deux
  espaces et deux plafonds estimés (74,45 m² cumulés, non vérifiés sur chantier).
  Téléphone lu uniquement ; fichier `/tmp/plaquisto-ceiling-current-scan.json`.
- Validation : **240 tests passent**, aucun échec ; builds iPhone signé et Lab
  réussis, `git diff --check` sans erreur. Le test SceneKit vérifie les identifiants
  de sélection, les normales, le sol, le maintien des quantitatifs et les trous de
  portes après préparation du rendu. Capture de contrôle inspectée : murs blancs,
  tableaux des portes, sol discret, ombres et cadrage orthographique.
- Traces : `/tmp/plaquisto-polished-scene-final-tests.log`,
  `/tmp/plaquisto-polished-scene-device.log`, `/tmp/plaquisto-polished-scene-lab.log`.
  Aperçu synthétique : `/tmp/plaquisto-polished-scene-images-final/A0831ABB-1E9B-4BAE-A745-3F606DD6BD06.png`.
- Non installé ; appareil toujours 3116. Test visuel sur iPhone et contrôle des
  plafonds sur chantier encore nécessaires. Aucun commit ni push.


## Installation iPhone — capture native — 26 septembre 2026, 09 h 42

- Version native RoomPlan installée par-dessus l’app existante sur l’iPhone
  d’Edouard : `fr.plaquisto.app`, séquence d’installation **3116**. Aucune donnée effacée.
- Lancement automatique refusé car l’iPhone est verrouillé (erreur `Locked`, code 7).
  L’installation a réussi ; ouverture manuelle et essai LiDAR restent à faire.
- Traces : `/tmp/plaquisto-native-capture-install.json` et
  `/tmp/plaquisto-native-capture-launch.json`. Aucun commit ni push.

## Retour à la capture native RoomPlan — 26 septembre 2026

- Décision explicite de l’utilisateur : simplifier la capture, conserver intégralement
  les fonctions métier après le scan. Cette décision remplace les essais de capture
  multi-pièces et de maquette cumulative documentés plus bas.
- `RoomCaptureView` recréée pour chaque nouveau relevé, maquette Apple activée,
  guidage natif, un seul `RoomCaptureSession.run` jusqu’à « Terminer le scan ».
  Aucune relance aux portes, aucun déplacement/recentrage de pièce inventé.
- Retirés : détecteur de passage, transitions automatiques, maquette SceneKit de
  capture et sa caméra/point orange, suivi/relocalisation maison, boucle de
  reconfiguration ARKit, assemblage automatique de plusieurs acquisitions à la fin.
  RoomPlan possède désormais son ARSession et sa configuration.
- Conservés : checkpoints récupérables, RoomBuilder, sauvegarde avant affichage du
  résultat, maquette/plan 2D après scan, édition des murs, cloisons et portes,
  plafonds estimés/modifiables, sélection multiple, projets/ouvrages/quantitatifs.
  Le maillage éventuellement fourni par Apple est seulement lu pour enrichissement ;
  aucun maillage n’est forcé dans la configuration native. Sans maillage exploitable,
  l’estimation du plafond par les murs et l’éditeur restent disponibles.
- Les anciennes sauvegardes multi-acquisitions et leurs fonctions de lecture restent
  compatibles ; aucun scan utilisateur effacé. Les tests des mécanismes supprimés
  sont retirés, pas ceux des fonctions métier conservées.
- Limite assumée : acquisition native simple, pas une promesse de scan automatique
  fiable de toute une maison ni de découpage multi-pièces. Texte d’accueil corrigé.
- Validation : **233 tests passent**, aucun échec ni test ignoré, dont le nouveau
  scénario résultat unique → sauvegarde → plafond/cloison/porte → plan 2D/surfaces.
  Les tests d’édition, de copie, de quantitatif et de sauvegardes héritées restent actifs.
- Builds iPhone signé et Lab réussis ; `git diff --check` sans erreur. Traces :
  `/tmp/plaquisto-native-capture-verified-tests.log`,
  `/tmp/plaquisto-native-capture-device.log`, `/tmp/plaquisto-native-capture-lab.log`.
- Installé depuis à 09 h 42 (séquence 3116, voir ci-dessus). Le comportement du scan
  réel reste à tester sur l’appareil. Aucun commit ni push.


## Installation iPhone — verticale de la maquette — 26 septembre 2026, 08 h 43

- Correction installée par-dessus l’app existante et lancement confirmé :
  `fr.plaquisto.app`, séquence **3108**. Aucune donnée effacée.
- Remplace le statut « correction non installée » ci-dessous. Test de rotation
  pendant un scan réel encore à effectuer par l’utilisateur.
- Traces : `/tmp/plaquisto-upright-camera-install.json` et
  `/tmp/plaquisto-upright-camera-launch.json`. Aucun commit ni push.

## Maquette penchée — diagnostic et correction du roulis, 26 septembre 2026

- Retour screenshot 08 h 25 : la maquette est penchée, pas aplatie. Lecture seule
  du checkpoint `3B8ED17B-A4B5-4E74-B9D4-BD819BB16663` (`/tmp/plaquisto-0825-scan.json`) :
  trois murs verticaux de hauteur 2,532 m, une acquisition non terminée, suivi normal
  après initialisation ; aucune transition de pièce dans le journal récupéré.
- Cause reproduite indépendamment dans SceneKit : `look(at:)` réutilise `worldUp`
  déjà tourné. Répété pendant une orbite, il accumule du roulis, jusqu’à retourner
  l’aperçu. Ce bug de caméra ne démontre pas une déformation des murs scannés.
- Correction ciblée : `look(at:up:localFront:)` avec verticale mondiale `(0,1,0)`
  et avant local `(0,0,-1)`. L’azimut suit toujours l’iPhone ; aucune géométrie changée.
- Test de non-régression ajouté : trois tours complets puis sens inverse ; horizontale
  de l’écran perpendiculaire à la gravité, verticale toujours vers le haut.
- Les 42 tests SurveyCaptureTests passent (`/tmp/plaquisto-upright-camera-tests.log`).
  Builds iPhone signé et Lab réussis (`/tmp/plaquisto-upright-camera-device.log`,
  `/tmp/plaquisto-upright-camera-lab.log`), `git diff --check` sans erreur.
- Le point orange représente la position de l’iPhone. Explication donnée à l’utilisateur ;
  aucun retrait demandé, il est conservé.
- Correction non installée, scans de l’utilisateur inchangés.

## Installation iPhone — rotation et reprise LiDAR — 26 septembre 2026, 08 h 14

- Mise à jour installée sur l’iPhone : `fr.plaquisto.app`, séquence **3100**,
  sans désinstallation ni effacement des données. Remplace le statut non installé ci-dessous.
- Lancement automatique refusé car appareil verrouillé (`Locked`, code 7).
  Déverrouiller et ouvrir l’app ; rotation et reprise réelle du suivi restent à tester.
- Traces : `/tmp/plaquisto-tracking-recovery-install.json` et
  `/tmp/plaquisto-tracking-recovery-launch.json`. Aucun commit ni push.

## Rotation et reprise du suivi LiDAR — 26 septembre 2026

- Analyse en lecture seule du scan de 7 h 50 sur l’iPhone : campagne
  `BBCED9D8-2D26-4657-A18D-3D543742508E`, deux acquisitions conservées (8 et 13 murs),
  continuité marquée fausse, assemblage non tenté. Copies de diagnostic locales :
  `/tmp/plaquisto-scan-audit-RboBvm`. Cause exacte de l’interruption non journalisée
  dans cette ancienne version ; ne pas affirmer qu’elle vient du passage de porte.
- Régression de rotation confirmée : caméra fixe et absence de modèle AR branché
  à la vue. Caméra désormais orientée selon l’azimut lissé du téléphone, sans
  rotation des géométries ni variation de zoom liée à la rotation.
- Remplacement de l’arrêt immédiat sur interruption/relocalisation par une attente
  conservant la maquette. Reprise après une seconde de nouvelles images normales,
  interruption terminée et même ARSession ; nouvelle acquisition différée si besoin.
- Fin volontaire pendant l’attente : données conservées, raccord non confirmé.
  Erreur AR fatale : arrêt sûr. Aucun reset automatique ou raccord inventé.
- Journal `captureEvents` compatible avec les anciennes sauvegardes : tracking,
  interruption, reprise, passage/acquisition, décision et résultat d’assemblage.
- 246 tests passés : `/tmp/plaquisto-tracking-recovery-tests.log`. Tests ajoutés
  pour rotation sans déplacement/zoom, regard vertical, reprise stable, anciennes
  images refusées, tracking fluctuant et sérialisation des événements.
- Suite ciblée SurveyCaptureTests relancée avec les dernières protections de
  transition : succès (`/tmp/plaquisto-tracking-recovery-final-tests.log`).
  Builds finaux iPhone signé et Lab réussis (`/tmp/plaquisto-tracking-recovery-device-final.log`
  et `/tmp/plaquisto-tracking-recovery-lab.log`), `git diff --check` sans erreur.
- Les sous-acquisitions techniques RoomPlan restent présentes ; la classification
  salon/cuisine ne les déclenche pas. Aucun changement des scans déjà sauvegardés.
- Correction non installée. Validation réelle rotation et reprise entre pièces
  encore requise sur iPhone ; les tests ne prouvent pas le suivi matériel.

## Installation iPhone — maquette cumulative — 26 septembre 2026, 07 h 40

- Mise à jour installée sur l’iPhone, sans désinstallation ni effacement des données :
  `fr.plaquisto.app`, séquence **3092**. Remplace le statut « pas encore installé » ci-dessous.
- Lancement automatique refusé car iPhone verrouillé (erreur `Locked`, code 7).
  Déverrouiller et ouvrir Plaquisto ; passage réel entre pièces encore à tester.
- Traces : `/tmp/plaquisto-world-preview-install.json` et
  `/tmp/plaquisto-world-preview-launch.json`. Aucun commit ni push.

## Maquette cumulative paramétrique — correction après 3084, 26 septembre 2026

- Retour utilisateur : rendu natif accepté, mais remise à zéro au passage de porte.
  La miniature RoomCaptureView est liée à une acquisition et non à toute la maison.
- Ajout de `ScanWorldPreview`, exclusivement alimenté par les snapshots live dans
  l’ARSession continue. Conservation des pièces sortantes et de leur nœud SceneKit,
  y compris pendant l’entrée vide de la suivante ; callbacks d’ancienne génération
  ignorés. Les résultats RoomBuilder recentrés restent dans un registre distinct.
- Miniature persistante paramétrique blanche, murs épaissis avec ouvertures, sols,
  éclairage, fond transparent. Pas de maillage brut. Mise à jour limitée et cadrage
  englobant ; aucun changement à StructureBuilder, aux données sauvegardées, à
  l’éditeur après scan ou à la création des ouvrages.
- **242 tests passent, zéro échec** : `/tmp/plaquisto-world-preview-tests.log`.
  Test ajouté sur la rétention des pièces, génération tardive et rendu opaque.
- Builds iPhone signé et Lab réussis : `/tmp/plaquisto-world-preview-device.log`
  et `/tmp/plaquisto-world-preview-lab.log`. Pas encore installé, aucun commit/push.
- Contrôle visuel effectué sur un rendu synthétique de deux pièces : murs blancs
  pleins, épaisseur lisible, cadrage global. Test visuel séparé réussi, artefact :
  `/tmp/plaquisto-world-preview-attachments/67588479-3A44-44DA-8BB0-166EC38F8F6A.png`.
- Validation du passage réel entre pièces et du suivi AR toujours à faire sur
  l’iPhone ; les tests simulés ne constituent pas une preuve de raccord matériel.

## Installation iPhone — retour de la maquette RoomPlan — 26 septembre 2026, 07 h 17

- Correction installée par-dessus Plaquisto iOS sur l’iPhone 16 Pro, sans
  désinstallation ni effacement des données : `fr.plaquisto.app`, séquence **3084**.
- Lancement sur l’iPhone confirmé. Cette installation remplace le statut
  « correction non encore installée » de la section suivante.
- Traces : `/tmp/plaquisto-native-preview-install.json` et
  `/tmp/plaquisto-native-preview-launch.json`. Aucun commit ni push.
- Retour au rendu natif de la pièce courante ; la maquette architecturale
  cumulative pendant le scan multi-pièces reste à résoudre et à tester.

## Correction du rendu pendant la capture — 26 septembre 2026, après installation 3076

- Retour utilisateur et capture de 07 h 10 : l’aperçu blanc en triangles était
  un maillage brut bruité, pas la maquette architecturale attendue. Le choix du
  maillage ARKit pour remplacer la miniature propre de RoomPlan était inadapté.
- Rétablissement de `RoomCaptureView.isModelEnabled = true` et suppression de
  `ScannerContinuousPreview`, de sa vue superposée et de la préparation de ses
  géométries/normales. Le maillage LiDAR reste utilisé par la reconstruction des
  plafonds ; seuls son rendu miniature et les calculs propres à ce rendu partent.
- Conservation du cadre caméra, du bouton Terminer, des checkpoints, de
  StructureBuilder, du visualiseur après capture, du plan 2D, de l’éditeur et du
  parcours de création d’ouvrage. Aucun scan ni sauvegarde supprimé.
- **Limite explicite** : l’aperçu natif montre la pièce courante et peut repartir
  au changement de sous-acquisition. Cette correction du rendu ne résout pas la
  demande de maquette architecturale cumulée pendant le scan. Ne pas prétendre
  que le retour au natif règle la continuité de la maison. Toute future solution
  cumulative doit utiliser une géométrie paramétrique propre, pas le maillage brut.
- Compilation iPhone signée réussie : `/tmp/plaquisto-native-preview-build.log`.
  `git diff --check` sans erreur. Correction non encore installée ; validation
  visuelle LiDAR à faire sur iPhone.

## Installation iPhone — espace de travail LiDAR — 26 septembre 2026, 07 h 08

- Compilation Debug signée réussie puis mise à jour de Plaquisto iOS installée
  sur l’iPhone 16 Pro : `fr.plaquisto.app`, séquence d’installation **3076**.
  Installation par-dessus l’existant, sans désinstallation ni effacement des données.
- Le lancement automatique a été refusé par iOS parce que l’iPhone était
  verrouillé (`FBSOpenApplicationErrorDomain`, code 7). L’installation est bien
  confirmée ; il reste à déverrouiller puis ouvrir Plaquisto pour tester le scan.
- Traces : `/tmp/plaquisto-workspace-device-build.log`,
  `/tmp/plaquisto-workspace-device-install.json`,
  `/tmp/plaquisto-workspace-device-launch.json`. Aucun commit ni push.
- Cette installation remplace le statut « pas encore installée » de la section
  suivante. La continuité LiDAR multi-pièces reste à valider en conditions réelles.

## Suite LiDAR — maquette, attribution et édition 2D — 26 septembre 2026

- Nouveau parcours après Terminer : ouverture directe de l’espace de travail
  3D, bascule Plan 2D coté, sélection multiple Murs/Plafonds, bouton Créer un
  ouvrage grisé sans sélection. Le choix du projet précède les catégories et
  le configurateur prérempli. Nom d’ouvrage facultatif ; données client/adresse/
  notes du nouveau projet conservées. Le même visualiseur est partagé avec Lab.
- Pendant la capture : caméra bornée sur fond noir, maquette claire plus centrale
  dans une scène séparée de RoomCaptureView. Elle utilise les murs/sols du maillage
  **ARKit mondial**, préparés hors du fil principal ; pas les coordonnées brutes
  des sous-scans RoomBuilder. Les resets de sous-acquisition ne réinitialisent
  pas cette scène. La géométrie finale reste issue de StructureBuilder avec les
  contrôles de raccord introduits précédemment. Ce changement remplace le retour
  à la miniature native par pièce de l’installation 2988.
- Éditeur 2D : murs scannés déplaçables, extrémités raccordées, longueur/hauteur,
  cloisons en deux points, hauteur suggérée depuis le plafond, portes 73/83/93 cm,
  hauteur de porte et déplacement sur le mur. Proximité des murs aimantée à la
  création. Refus des ouvertures hors limites, chevauchements et nouveaux
  croisements ; scan initial intact. Enregistrer ou Abandonner les modifications.
- Plafond : réutilisation des quatre modèles estimés, sans inclure les cloisons
  ajoutées dans le contour de la pièce. Pas de redimensionnement silencieux du
  plafond après déplacement d’un mur. Les ouvrages déjà attribués sont à revoir
  après une modification géométrique, sans réécriture automatique des quantités.
- Une cloison conçue reçoit une seule surface physique dans l’ouvrage, accessible
  des deux côtés en 3D. Test d’attribution et de doublon ajouté. Meubles hors scope.
- **241 tests iOS réussis, zéro échec**, dont édition, portes, initial inchangé,
  persistence, métadonnées projet, attribution et non-double-comptage. Résultat :
  `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.26_06-37-45-+0200.xcresult`.
- Compilations finales **Plaquisto iOS et PlaquistoLab réussies** après les
  retouches visuelles ; `git diff --check` sans erreur. Journaux :
  `/tmp/plaquisto-workspace-final-build.log` et
  `/tmp/plaquisto-lab-workspace-final-build.log`.
- Contrôle interactif sur simulateur, dans l’app séparée
  `fr.plaquisto.workspaceproof` alimentée exclusivement par un relevé synthétique :
  sélection 3D de deux murs → bouton actif → catégorie doublage → formulaire avec
  **20 m², 8 m, 2 murs** ; affichage 2D coté avec portes ; création d’une cloison,
  porte 83 cm, déplacement de 108 à 200 cm, enregistrement et retour en 3D confirmés.
  Petites retouches de présentation après contrôle : un seul bouton Fermer,
  libellés de dimensions non coupés et cotes parallèles aux murs dans l’éditeur.
- Limite importante : aucune validation matérielle du scan continu multi-pièces
  n’est possible sur simulateur. Il faut encore tester le franchissement des
  portes, la conservation des ancres et la fluidité dans une maison sur iPhone.
  **Cette suite n’est pas encore installée sur l’iPhone. Aucun commit ni push.**

## Installation iPhone — correction des repères LiDAR — 26 septembre 2026, 00 h 20

- Compilation Debug signée réussie, puis installation de Plaquisto iOS sur
  l’iPhone 16 Pro confirmée : bundle `fr.plaquisto.app`, séquence **2988**.
- Mise à jour par-dessus l’existant, sans désinstallation ni effacement des données.
  Cette version comprend le retour de la maquette native et l’utilisation réelle
  de la géométrie assemblée. Le scan de deux pièces reste à retester sur l’appareil.
- Traces : `/tmp/plaquisto-assembly-device-build.log`,
  `/tmp/plaquisto-assembly-device-install.json`. Aucun commit ni push.

## Correction LiDAR — maquette native et repères des pièces — 26 septembre 2026

- Retour utilisateur après l’installation 2980 : aperçu trop encombrant et
  nouvelle pièce superposée à la précédente. Diagnostic sur des copies locales
  en lecture seule des caches sauvegardés sur l’iPhone ; aucun scan effacé.
- Un ancien assemblage Apple conservé permet de comparer les mêmes murs avant
  et après `StructureBuilder` : déplacement maximal **6,485 m** pour une pièce,
  alors que le résidu d’un placement rigide est inférieur à 2 mm. Le code
  sauvegardait cet assemblage mais continuait d’utiliser les coordonnées brutes.
  Le problème de repère est donc confirmé, pas seulement supposé depuis l’image.
- `RoomCaptureView.isModelEnabled = true` : retour de la petite maquette native
  progressive de la pièce en cours. Retrait de la grande carte permanente et
  des contours d’anciennes pièces projetés à tort dans la caméra. Accès compact
  aux zones conservées, avec vues 2D/3D séparées pendant l’acquisition.
- La finalisation applique maintenant **la géométrie assemblée** aux documents
  portables, de façon atomique, avec identité des composants et noms conservés.
  Les plafonds sont transportés par les correspondances de murs observés, sans
  changement d’échelle ; les ambiguïtés/refinements non rigides excessifs refusent
  l’assemblage plutôt que d’inventer un raccord. Les caches bruts restent conservés.
- Nouveau statut `assemblyVerified` : une origine AR commune seule ne suffit
  plus à afficher/importer plusieurs résultats bruts comme un bâtiment assemblé.
  Perte de suivi, résultat incomplet ou échec : conservation séparée et message
  explicite. Les avertissements de recouvrement sont recalculés après assemblage.
- Observation ARKit sans écraser le delegate natif : relais des callbacks vers
  RoomCaptureView/RealityKit, surveillance des interruptions conservée. Les
  passages mémorisés d’une acquisition précédente ne déclenchent plus une
  transition dans la suivante.
- Validation : **234 tests réussis**, dont quatre nouveaux tests d’assemblage,
  transport des plafonds, atomicité/refus et invalidation d’un aperçu assemblé.
  Compilation iOS simulateur et Lab réussies. Logs :
  `/tmp/plaquisto-assembly-correction-tests-final.log`,
  `/tmp/plaquisto-assembly-correction-lab.log`.
- Limite : aucune acquisition matérielle réelle effectuée par l’agent. Le passage
  de porte, la maquette native et le raccord final doivent être retestés sur
  l’iPhone. Le simulateur ne permet pas de valider une acquisition LiDAR ni
  l’exécution matérielle de StructureBuilder. Pas de nouvelle installation,
  commit ou push dans cet incrément.

## Installation iPhone — plafonds automatiques — 25 septembre 2026, 23 h 45

- À la demande de l’utilisateur, compilation Debug signée de Plaquisto iOS
  réussie avec l’équipe de développement habituelle, puis installation sur
  l’iPhone 16 Pro confirmée (bundle `fr.plaquisto.app`, séquence **2980**).
- Lancement de l’application confirmé. Mise à jour par-dessus l’existant,
  sans désinstallation ni effacement des données.
- Cette version inclut les plafonds automatiques reconnus/estimés et les quatre
  formes modifiables. La capture LiDAR réelle reste à tester sur l’appareil.
- Traces : `/tmp/plaquisto-ceiling-device-build.log`,
  `/tmp/plaquisto-ceiling-device-install.json`,
  `/tmp/plaquisto-ceiling-device-launch.json`. Aucun commit ni push.

## LiDAR — plafonds automatiques et quatre formes estimées — 25 septembre 2026

- Les plafonds reconstruits à partir d’observations sont désormais acceptés
  automatiquement. Pendant la capture : message « Plafond reconnu », sans
  surface jaune/verte ni boutons de validation. Une fermeture de pièce ambiguë
  n’est pas automatiquement présentée comme une reconnaissance fiable.
- Sans plafond observé, estimation automatique au traitement final depuis un
  contour fermé de murs : plat, ou un pan si deux murs opposés parallèles ont
  des niveaux supérieurs différents (seuil de bruit 10 cm). Sans contour
  exploitable, pas de remplacement par un rectangle. Les anciens documents
  sans plafond sont complétés à l’ouverture de l’éditeur, avec sauvegarde contrôlée.
- Message/provenance distincts « Plafond estimé à partir des murs ». Modèle
  portable : `GeometrySource.estimated` et paramètres facultatifs dans le plafond.
  Le document initial et les murs restent inchangés ; un plafond estimé ne
  modifie pas silencieusement les quantités des doublages.
- Éditeur commun iOS/Lab : Plat / Un pan / Deux pans / Quatre pans, hauteur(s),
  orientation, position du faîtage. Aperçu Perspective/Dessus/Recentrer, arêtes
  des pans, surface développée. Enregistrer/Annuler pour les modifications ;
  aucune étape obligatoire de confirmation du plafond généré automatiquement.
- Découpage des plans par le contour réel, y compris concave ; contrôle de
  conservation de la surface projetée. Persistance/copie des réglages, IDs
  conservés autant que possible et mécanisme existant de revue des ouvrages.
  La validation métier du relevé complet avant attribution reste indépendante.
- Vérifications : **230 tests réussis**, zéro échec ; compilations iOS et Lab
  simulateur réussies ; tests historiques du moteur de reconstruction et preuve
  de relecture indépendante réussis. Résultat :
  `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.25_08-54-51-+0200.xcresult`.
  Logs : `/tmp/plaquisto-ceiling-tests-final.log`,
  `/tmp/plaquisto-ceiling-lab-build.log`, `/tmp/plaquisto-ceiling-proof.log`.
- Contrôle visuel de l’éditeur de production via le harnais indépendant : plafond
  plat automatiquement ajouté ; quatre familles disponibles ; passage à quatre
  pans, hauteur maximale 3,50 m saisie avec le clavier Plaquisto, surface 15,43 m²,
  sauvegarde puis arrêt/relance : forme et hauteur conservées, murs inchangés.
  Correction d’une feuille vide à la première ouverture via présentation liée
  directement à la proposition. Scénario reproductible :
  `bash Tests/run-room-model-proof.sh <simulateur> --ceiling-estimate`.
- Pas d’installation iPhone ni de commit/push dans cet incrément. La capture
  LiDAR matérielle (en particulier les hauteurs de murs en sous-pente) reste
  à vérifier sur appareil ; aucune acquisition réelle n’est revendiquée.

## LiDAR — fiabilité, validation métier et sélection — 25 septembre 2026

- Suite à l'audit consultatif, récupération indépendante des brouillons illisibles
  (sans suppression), sauvegarde finale contrôlée avec nouvelle tentative et
  interdiction de remplacer un relevé non sauvegardé par une nouvelle capture.
- Finalisation bornée à 90 s après Terminer : les checkpoints restent disponibles
  à contrôler si le raffinement Apple n'aboutit pas. Les retours asynchrones tardifs
  sont ignorés après annulation/échec. Les recouvrements partiels dans un même
  repère sont signalés avec comparaison des plans avant conserver/écarter.
- Démarrer est en tête de l'accueil Scanner ; diagnostics repliés.
- Statut portable de validation métier par checkpoint. Les nouvelles captures,
  provisoires ou traitées, doivent être explicitement validées avant attribution.
  Un brouillon provisoire récupéré reste validable après contrôle manuel.
  Les anciens checkpoints sans statut demandent également ce contrôle avant une
  nouvelle attribution ; leurs ouvrages et quantités existants restent intacts.
- Une correction géométrique du relevé marque les ouvrages concernés « à
  contrôler » sans remplacer leurs composants, calepinages ou quantités. Alerte
  dans le projet, les configurations et les quantitatifs regroupés ; ouverture
  du relevé source et confirmation explicite pour conserver les anciennes cotes.
- Sélections séparées et mémorisées par traitement/famille, plan 2D interactif et
  vue 3D utilisant les mêmes surfaces, compteur/surface/Continuer persistants,
  résumé surface brute − ouvertures = surface nette et raccourcis de contrôle.
- Validation : **223 tests réussis**, zéro échec, compilations iOS et Lab sur
  simulateur réussies ; preuve de sauvegarde/relecture du modèle indépendant
  réussie. Résultat final :
  `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.25_07-42-12-+0200.xcresult`.
  Logs : `/tmp/plaquisto-lidar-audit-verified.log`,
  `/tmp/plaquisto-lidar-audit-lab.log`. Première tentative de tests interrompue
  pendant le démarrage du simulateur dupliqué ; relance sans parallélisation OK.
- Contrôle visuel sur le Projet synthétique existant : ancien relevé bloqué avant
  validation, confirmation et activation des surfaces ; Mur 1 conservé après
  aller-retour Murs/Plafonds et Plan 2D/Vue 3D. Résumé contrôlé : 11,44 m² bruts,
  3,09 m² d'ouvertures, 8,35 m² nets. Accueil Scanner avec Démarrer en tête et
  détails techniques repliés. Aucune capture matérielle simulée ou revendiquée.
- Aucune installation iPhone ni opération Git distante effectuée. La capture
  LiDAR réelle, les transitions entre pièces et les conditions de faible stockage
  restent à tester sur appareil.

## LiDAR — plan 2D en complément de la maquette — 25 septembre 2026

- Projection horizontale des murs corrigés, sols et ouvertures du même relevé :
  aucun second modèle géométrique ni fichier de mesures divergent. Raccords
  `transformToSurvey` appliqués à la projection après sauvegarde dans le Projet.
- Choix Maquette 3D / Plan 2D pendant la capture et dans le contrôle du relevé.
  Accès « Voir le plan 2D » depuis le relevé du Projet, zoom/déplacement/recentrage,
  échelle métrique dynamique et longueurs des murs affichables en option.
- Fenêtres en bleu, portes/passages en pointillés ; pas de sens d’ouverture
  inventé. Noms de pièces placés uniquement dans un contour de sol exploitable.
  Les relevés non raccordés sont affichés en plans séparés, pas en faux assemblage.
- Validation : 217 tests réussis, zéro échec ; compilations simulateur iOS et Lab
  réussies. Résultat `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.25_07-00-35-+0200.xcresult`.
  Contrôle visuel depuis le Projet synthétique : ouverture du plan, fenêtre bleue,
  porte en pointillés, sol, échelle et option des longueurs (4,40 m corrigés, 4,28 m
  côté opposé, 3,00 m latéraux). Les raccords géométriques non corrigés ne sont pas
  fermés artificiellement. Pas de nouvelle installation iPhone ni d’envoi Git.

## LiDAR — continuité visible et checkpoints avant transition — 25 septembre 2026

- Retour réel utilisateur : au passage dans une autre pièce, l’aperçu disparaît
  et donne l’impression de repartir de zéro. Cause identifiée dans le code :
  chaque `RoomCaptureSession.run()` réinitialise le modèle intégré de
  `RoomCaptureView`, même si l’ARSession et les résultats précédents sont conservés.
- Modèle intégré désactivé via l’API publique `isModelEnabled`. Une scène Plaquisto
  persistante affiche tout le relevé pendant la capture, avec position du téléphone,
  repère commun, cadrage qui ne se réduit jamais à la nouvelle pièce et mise à jour
  limitée aux portions modifiées. Les contours déjà acquis restent aussi visibles
  en surimpression AR ; le coaching initial ne redémarre pas dans chaque passage.
- Les sous-acquisitions RoomPlan restent internes : toujours un seul Démarrer /
  Terminer. Il ne s’agit pas d’une session RoomPlan unique illimitée ni d’une
  promesse d’équivalence avec Polycam. Les limites de suivi et de reconnaissance
  des passages restent à tester dans une maison réelle.
- Sauvegarde portable périodique (5 s) et avant l’arrêt interne : les murs ne
  dépendent plus de l’achèvement de RoomBuilder pour survivre à une interruption.
  Le résultat raffiné remplace le même checkpoint, sans créer une seconde pièce.
  Une erreur de raffinement conserve la géométrie provisoire à contrôler.
- « Terminer » reste utilisable pendant la transition. Une dernière acquisition
  vide n’écrase pas les pièces précédentes. Le contrôle après capture propose une
  vue d’ensemble, les snapshots non finalisés sont explicitement signalés.
- Validation : 215 tests réussis, zéro échec. Résultat final
  `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.25_00-04-10-+0200.xcresult`.
  Régressions ajoutées : conservation du premier aperçu quand le suivant est vide,
  remplacement ciblé après raffinement, récupération d’un checkpoint provisoire,
  compatibilité des brouillons antérieurs, reconnaissance tardive d’un nom,
  stabilité du cadrage/nœuds 3D et exclusion explicite après revue.
- Rendu SceneKit de deux pièces synthétiques contrôlé visuellement, cadrage ajusté
  aux coins projetés. Compilation simulateur via les tests, Lab et compilation
  iPhone signée réussies ; diff et projet Xcode validés. Logs
  `/tmp/plaquisto-persistent-scan-tests-verified.log`,
  `/tmp/plaquisto-persistent-scan-lab.log`,
  `/tmp/plaquisto-persistent-scan-device-final.log`.
  Pas de validation LiDAR réelle effectuée par l’agent : test de déplacement entre
  pièces à faire sur l’appareil. Aucun commit ni push effectué.
- Installation tentée ensuite sans lancement de l’app (utilisateur parti dormir),
  mais l’iPhone n’est plus joignable : CoreDevice 4000, connexion interrompue
  (`/tmp/plaquisto-persistent-scan-install.json`). Cette correction n’est donc pas
  installée. Le bundle signé est prêt dans
  `/tmp/PlaquistoDeviceDerived/Build/Products/Debug-iphoneos/Plaquisto.app`.

## LiDAR — parcours continu et surfaces vers ouvrages — 24 septembre 2026

- Décision utilisateur : un Démarrer / Terminer pour tout un niveau. Les pièces
  servent au repérage, pas au classement des ouvrages. Sélection possible dans
  plusieurs pièces ; ouvrage librement nommé, aucun rattachement forcé à une pièce.
- Capture iOS : franchissement de portes/passages observés et stables, hystérésis,
  contrôle du suivi et sous-scans internes sans réinitialiser ARKit. Le prochain
  sous-scan repart avant RoomBuilder ; les calculs de plafond travaillent hors UI
  sur un contexte figé. Callbacks tagués, snapshots et traitement ordonné par chunk.
- Noms proposés depuis les usages RoomPlan (salon/cuisine/chambre/etc.), avec
  « Pièce à identifier » en absence de reconnaissance. Les usages multiples d’un
  espace ouvert n’inventent ni mur ni séparation.
- Brouillons atomiques `Plaquisto/ScanDrafts`, récupération après relance. Modèle
  portable sauvegardé avant reconstruction puis enrichi, caches RoomPlan isolés.
  Une revisite potentielle n’est pas jetée : décision conserver/écarter avant
  transfert au projet. Perte de suivi → arrêt et pièces déjà sauvegardées accessibles.
- Enregistrement de toutes les pièces retenues en une transaction Projet/Relevé.
  Noms corrigibles ; validation des propositions de plafond après le scan (jaune).
- Sélection multiple en scène globale et liste : doublages rails/montants,
  lisses/fourrures et plafonds sur fourrures, formulaires existants préremplis.
  Chaque composant conserve contour, ouvertures, repère local et provenance du
  relevé. Sources corrigées prioritaires, contrôle d’éditeur périmé et doublons
  par famille de travaux. Liens réaffectés lors de la copie d’un Projet.
- Peinture (bêta) demandée ensuite : formulaire provisoire, métrage net uniquement,
  ni consommables, ni plaques, ni ossature. Une surface peut recevoir doublage
  puis peinture ; seuls les côtés sélectionnés comptent pour la peinture. Aucun
  calepinage de plaques proposé pour cet ouvrage bêta.
- Règle future cloisons ajoutées : support entier sélectionné pour construction,
  ossature une fois, parements par côté/couche. Peinture sur existant : côtés
  indépendants explicitement choisis. L’éditeur d’ajout de cloison/porte n’est pas
  inclus dans cet incrément.
- Validation : 208 tests iOS réussis, zéro échec, résultat XCTest
  `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.24_23-36-28-+0200.xcresult`.
  Preuve d’indépendance du modèle et régressions de reconstruction des plafonds
  réussies. Compilation Plaquisto via les tests ; compilation PlaquistoLab réussie.
  `git diff --check` et validation du projet Xcode réussis.
- Parcours simulateur vérifié sur une pièce synthétique : sélection de deux murs,
  nom libre « Test peinture surfaces », formulaire bêta prérempli à 15,85 m² nets,
  sauvegarde, anti-doublon par traitement, quantitatif limité aux m² et absence
  d’action de calepinage de plaques pour la peinture. Ouvrage retrouvé après
  arrêt complet et relance de l’app, sans classement par pièce.
  Aucun nouvel envoi Git dans cet incrément.
- À la demande de l’utilisateur : compilation signée réussie et installation
  sur l’iPhone 16 Pro le 24 septembre à 23 h 48, séquence 2892, bundle
  `fr.plaquisto.app`. Lancement confirmé à 23 h 48. Mise à jour sans
  désinstallation. Logs `/tmp/plaquisto-continuous-device.log`,
  `/tmp/plaquisto-continuous-install.json`, `/tmp/plaquisto-continuous-launch.json`.
  La capture multi-pièces nécessite encore un essai réel sur iPhone : aucune
  garantie de reconnaissance des portes, des pièces ou de précision géométrique
  ne peut être déduite des tests simulateur.

## LiDAR — relevés rattachés aux projets, premier incrément — 24 septembre 2026

- Audit du scanner existant et consultation des six profils puis du gardien MVP
  documentés dans `docs/LIDAR_MULTI_ROOM_V1.md`. Reconstruction des plafonds,
  adaptateur RoomPlan, modèle portable, mesures brutes/corrigées et éditeur 3D conservés.
- `ProjectSurveyRecord` et checkpoints de pièces ajoutés à la même archive que les
  projets. Sauvegarde atomique Projet + Pièce + Relevé, identifiants stables,
  duplication avec réaffectation des liens et suppression avec le projet.
  Anciennes archives v2 sans relevés toujours lisibles. Transformations rigides
  validées : aucune mise à l’échelle implicite des mesures.
- Depuis le scanner ou une pièce sauvegardée/importée : choisir/créer Projet,
  Relevé et Pièce. Depuis le Projet : Relevés 3D → Pièce → éditeur existant.
  Corrections sauvegardées dans le relevé ; édition périmée refusée et confirmation
  avant remplacement d’un scan existant. Aucun ouvrage créé par cette étape.
- Les captures indépendantes restent explicitement « à relier ». Capture continue,
  fusion multi-pièces, attribution métier et cloison/porte guidées sont les incréments
  suivants ; ne pas les présenter comme livrés.
- Validation : 191 tests iOS réussis, zéro échec ; preuve d’indépendance du modèle
  existante réussie (`Tests/run-room-model-proof.sh`). Résultat XCTest :
  `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.24_22-28-38-+0200.xcresult`.
- Parcours testé sur simulateur avec une pièce synthétique : création de
  « Test relevé LiDAR », réouverture par le projet, scène 3D et deux ouvertures
  conservées, correction 4,31 → 4,40 m persistée avec mesure initiale 4,28 m intacte.
  Après arrêt complet et relance, le relevé et la correction 4,40 m sont retrouvés.
- Compilations finales Plaquisto et Plaquisto Lab réussies pour le simulateur,
  architectures arm64 et x86_64. Lab partage les modèles et écrans de relevé
  sans inclure le moteur de capture RoomPlan. `git diff --check` et validation du
  fichier projet Xcode réussis.
- Tests existants `ScannerCeilingReconstructionChecks` réussis : rampants opposés,
  pentes inégales, murs fragmentés, ouvertures, contours concaves, trous de maillage,
  translations, branches ambiguës et régression de la cuisine enregistrée.
- Compilation signée puis installation sur l’iPhone 16 Pro confirmées le
  24 septembre à 22 h 47, séquence 2876, bundle `fr.plaquisto.app` ; lancement
  confirmé à 22 h 48. Mise à jour sans désinstallation, données conservées.
  Comptes rendus `/tmp/plaquisto-lidar-survey-iphone-install.json` et
  `/tmp/plaquisto-lidar-survey-iphone-launch.json`. Aucun commit ni push effectué.

## Correctif navigation des fiches et sélection des quantitatifs — 24 septembre 2026

- Les trois NavigationLink partageant une cellule List activaient plusieurs
  écrans lors d'un appui tactile. Remplacés par des boutons plain indépendants,
  avec une seule destination optionnelle (identifiant ouvrage + action), y compris
  le raccourci isolation. Protection contre un second déclenchement pendant l’ouverture.
  Zones tactiles de 44 points, chevrons explicites ; titre et résumé sans navigation.
- « Voir les quantitatifs » : suppression de la section de filtres et des actions
  associées. Tous les ouvrages apparaissent directement sous « Ouvrages à inclure ».
  Compteur de sélection, absence de double comptage et accès au récapitulatif conservés.
- 57 tests ProjectStore réussis (`/tmp/plaquisto-work-navigation-tests.log`),
  compilation simulateur finale réussie et diff sans erreur. Contrôle par clics
  aux coordonnées sur le simulateur, et non seulement activation AX : nom/résumé
  inertes, chaque action ouvre son seul écran, un retour ramène directement au projet.
  Écran sans filtres et sélection d’un ouvrage contrôlés visuellement.
- Compilation signée et installation iPhone 16 Pro confirmées à 00 h 18,
  séquence 2816, données conservées. Logs `/tmp/plaquisto-work-navigation-device.log`,
  `/tmp/plaquisto-work-navigation-install.json` et `/tmp/plaquisto-work-navigation-launch.json`.
  Lancement automatique refusé car l’iPhone est verrouillé ; installation réussie.

## Fiches ouvrages dans le projet — 24 septembre 2026

- Nom personnalisé conservé en titre, résumé technique secondaire multiligne
  (système, isolant/épaisseur/R, parement et surface selon les données disponibles).
  Les produits sont résolus depuis la même réponse catalogue et son cache ; pas
  d’identifiants bruts, de nom deviné ou de valeur thermique inventée. R via
  ThermalCalculator ; complexes collés via leur résistance publiée au catalogue.
- Actions indépendantes : Quantitatif (CombinedQuantityView limité à cet ouvrage),
  calepinage et Modifier la configuration (formulaire existant à l’étape 1,
  valeurs préchargées, mise à jour du même ouvrage). Renommage/swipe conservé.
  Les types autorisés à créer un calepinage restent inchangés.
- hasSavedLayout est dérivé des composants ayant une surface et un plan non vide,
  sans nouveau drapeau persistant. Les anciens composants vides ne comptent plus.
  La création initiale et les nouvelles sous-parties restent en mémoire jusqu’à
  saveComponentPlan, qui insère et valide le composant dans la même transaction.
  Un abandon ou un échec de sauvegarde ne persiste aucun composant temporaire.
- Validation : 184 tests réussis, zéro échec, dont 57 ProjectStoreTests et six
  nouveaux tests couvrant existence réelle, transaction/rollback, plusieurs ouvrages,
  résumés des dix types, références absentes, R, double isolation, édition sans
  doublon et conservation du plan. Log : `/tmp/plaquisto-work-cards-all-tests.log`.
- Contrôle simulateur : quantitatifs distincts de Bureau - Plafond et Bureau -
  Cloison ; édition de la cloison à l’étape 1 avec 2,5 × 4 m préchargés ; retour
  immédiat et annulation du formulaire sans plan fantôme, fichier persistant vérifié
  (components vide) ; sauvegarde réelle puis réouverture du même plan réussies.
  Édition du plafond de test : largeur 3 → 3,5 m, retour direct au projet, résumé
  12 → 14 m², même identifiant d’ouvrage et composant conservé dans le fichier.
  Ouvrage local de test ajouté dans le simulateur : « Test fiche ouvrage ».
- Compilation finale réussie (`/tmp/plaquisto-work-cards-final-build.log`) et
  `git diff --check` sans erreur.
- Compilation signée réussie, puis installation et lancement sur l’iPhone 16 Pro
  confirmés le 24 septembre à 00 h 08, séquence 2808, bundle `fr.plaquisto.app`.
  Mise à jour sans désinstallation, données conservées. Logs :
  `/tmp/plaquisto-work-cards-device.log`, `/tmp/plaquisto-work-cards-install.json`,
  `/tmp/plaquisto-work-cards-launch.json`. Aucun commit ni push effectué.

## Création directe des ouvrages — 23 septembre 2026

- Parcours confirmé : nom d’ouvrage facultatif, sélection d’une catégorie, puis
  boutons de tous ses types. Un appui ouvre immédiatement le formulaire métier.
  Les catégories restent présentes conformément à la correction de l’utilisateur.
- Suppression du menu de type présélectionné et du bouton Configurer. Ouvertures
  utilisent le même conteneur que les autres types et conservent le nom saisi.
- Aucun champ pièce/niveau/zone dans la création ni lien Organisation dans la liste
  du projet. Les données existantes et leurs références restent sauvegardées.
- Le choix ne crée qu’un brouillon local. Fermer le formulaire revient au choix
  avec le nom conservé ; seul Enregistrer crée l’ouvrage. Nom vide : proposition
  disponible du type ; nom explicite déjà utilisé : avertissement conservé.
- Validation : compilation simulateur réussie et 51 tests ProjectStore réussis
  (`/tmp/plaquisto-direct-work-tests.log`). Contrôle simulateur des quatre catégories
  et des dix boutons, entrée directe dans Plafond modulaire sans nom et Ouvertures
  avec nom, retour avec nom conservé, annulation sans ouvrage créé (deux ouvrages
  existants conservés). Compilation signée réussie et installation sur l’iPhone
  16 Pro confirmée le 23 septembre à 23 h 25, séquence 2792, bundle
  `fr.plaquisto.app`, puis lancement réussi. Mise à jour sans désinstallation.
  Logs : `/tmp/plaquisto-direct-work-device.log`,
  `/tmp/plaquisto-direct-work-install.json`, `/tmp/plaquisto-direct-work-launch.json`.
- Présentation du nom harmonisée avec les formulaires : libellé extérieur « Nom de
  l’ouvrage », badge Facultatif, carte système arrondie, icône crayon, exemple et
  aide sur la proposition automatique. La couleur système évite le rectangle noir
  brut en mode sombre. Compilation simulateur réussie et rendu contrôlé visuellement.
  Build signé, installation et lancement sur l’iPhone confirmés le 23 septembre à
  23 h 32, séquence 2800, données conservées. Logs :
  `/tmp/plaquisto-work-name-style-device.log`,
  `/tmp/plaquisto-work-name-style-install.json`,
  `/tmp/plaquisto-work-name-style-launch.json`.

## Édition du contour : réserve et visibilité — 23 septembre 2026

- Déplacement et zoom du contour utilisent la même limite de caméra que le
  calepinage pour garder le dessin dans la zone visible.
- Icônes Cotes et Angles au-dessus du dessin, états masqués pointillés atténués.
  L'ancien bouton Sommets est retiré ; sa fonction reste accessible dans le menu.
- Réserve expliquée, sélection multiple des bords par appuis successifs,
  désélection au second appui. Curseur désactivé sans sélection, de −5 à +5 cm,
  cran à zéro et retour haptique léger. Les bords sélectionnés seuls deviennent orange.
- Application simultanée aux bords choisis, validation du contour final et annulation
  d'un geste en une opération. Convention du curseur corrigée : −5 cm déplace vers
  l'intérieur et +5 cm vers l'extérieur ; l'avertissement apparaît donc uniquement
  côté positif. Les anciennes valeurs sauvegardées restent lisibles.
- Titre « Décalage des bords de plaque » et aide expliquant l'espace destiné à
  faciliter le passage des gaines entre plaques et murs supports. Validation de la
  convention : 83 tests réussis, zéro échec (`/tmp/plaquisto-offset-direction-tests.log`).
- Correctif compilé, installé et lancé sur l'iPhone 16 Pro le 23 septembre à
  23 h 04, séquence 2784. Données conservées. Logs :
  `/tmp/plaquisto-offset-direction-device.log`,
  `/tmp/plaquisto-offset-direction-install.json` et
  `/tmp/plaquisto-offset-direction-launch.json`.
- Compilation simulateur et 82 tests de calepinage réussis, zéro échec
  (`/tmp/plaquisto-contour-selection-tests.log`). Retour haptique à contrôler sur
  iPhone. Compilation signée réussie et installation physique confirmée le
  23 septembre à 22 h 48, séquence 2776, bundle `fr.plaquisto.app`, puis lancement
  réussi. Mise à jour sans désinstallation. Logs :
  `/tmp/plaquisto-contour-selection-device.log`,
  `/tmp/plaquisto-contour-selection-install.json`,
  `/tmp/plaquisto-contour-selection-launch.json`.

## Installation iPhone — 23 septembre 2026, 21 h 48

- Compilation Debug signée de Plaquisto iOS réussie, puis installation physique
  confirmée sur l’iPhone 16 Pro, bundle `fr.plaquisto.app`, séquence **2768**.
  Installation par-dessus la version existante : données et projets conservés.
- Le lancement automatique a été refusé uniquement parce que l’iPhone était verrouillé ;
  l’application est bien installée. Logs : `/tmp/plaquisto-device-20260923.log`,
  `/tmp/plaquisto-install-20260923.json` et `/tmp/plaquisto-launch-20260923.json`.

## Valeurs initiales du calepinage plafond — 23 septembre 2026

- Tout nouveau calepinage de plafond démarre avec des plaques de 240 × 120 cm
  et un entraxe de fourrures de 60 cm. Les murs conservent leurs valeurs propres.
- La règle s'applique uniquement à la création : aucun calepinage sauvegardé n'est
  réécrit. Validation ciblée : 82 tests réussis, 0 échec
  (`/tmp/plaquisto-default-2400-tests.log`).

## Calage local des plaques sur les fourrures — 23 septembre 2026

- Sur plafond, les deux actions « Caler les plaques sur les fourrures » (éditeur
  et réglages des plaques) conservent le décalage manuel et corrigent uniquement
  sa phase modulo l'entraxe, vers la ligne la plus proche. Déplacement maximal :
  un demi-entraxe ; position latérale, orientation, mur de référence et ossature inchangés.
- Un calepinage aligné reste strictement inchangé. Le calcul utilise les axes
  locaux du mur de référence, y compris pour les plans obliques. Les formats
  incompatibles restent bloqués ; l'action inverse et les murs ne changent pas.
- 167 tests réussis (`/tmp/plaquisto-local-furring-tests.log`), dont plafonds
  8 × 7 m, plans tournés, offsets positifs/négatifs, trois entraxes, deux sens,
  idempotence et conservation du comportement des murs.

Mise à jour : 23 septembre 2026. Branche de travail : `codex/tools-lab-improvements`.

## Contour de pose distinct du contour mesuré — 23 septembre 2026

- `Surface2D` conserve son contour mesuré. `LayoutLayingOffset` stocke l'unité mm,
  le retrait global et les remplacements absolus par identifiant stable de côté.
  Les anciens plans décodent avec zéro retrait. Le contour de pose est dérivé,
  jamais sauvegardé comme une seconde géométrie indépendante.
- Décalage global 0…5 cm et par côté −5…10 cm, pas 1 cm. Les remplacements
  individuels persistent lors d'un nouveau réglage global. Réinitialiser efface tout.
  Orange = pose ; turquoise = mesuré. Taper le contour orange sélectionne le côté,
  taper dans le vide revient au global. « Sommets » conserve les actions topologiques.
- Intersection des droites décalées perpendiculairement : rectangles, polygones
  obliques et concaves, deux sens de parcours. Auto-intersections, arêtes inversées
  et contours effondrés refusés ; dernière valeur valide conservée. Un dépassement
  négatif reste autorisé avec avertissement, visible également dans le calepinage.
- Plaques, coupes et surface utile d'isolant suivent la pose ; les ouvertures gardent
  leurs coordonnées et sont découpées à cette limite. Ossature calculée séparément
  sur le mesuré. Aperçus de déplacement utilisent les deux découpages distincts.
- Export/formulaires : les dimensions et surfaces support restent mesurées pour
  préserver les calculs d'ossature. Le ratio pose nette / mesuré net est dérivé du
  document et injecté dans le contexte SwiftUI, sans stockage redondant. Il ajuste
  uniquement les quantités de plaques (avant arrondi) et d'isolant dans les cinq
  configurateurs exportables. Les affectations de parements restent mesurées.
  Les quantités métriques des formulaires restent distinctes des plaques entières
  dessinées par le moteur, conformément au parcours d'export existant.
- Les quantitatifs métier sauvegardés restent soumis à l'action existante de
  recalcul de l'ouvrage ; la géométrie et le calepinage se recalculent immédiatement.
  Une question utilisateur sur l'automatisation de ces snapshots reste en attente.

## Clavier numérique commun — 20 septembre

- Correctif suivant après retour iPhone : le style `.default` ne suffit pas à retirer
  la plaque de fond d'iOS. La poignée modifie désormais la hauteur réelle du
  `UIInputView` auto-dimensionné, au lieu de déplacer son contenu à hauteur constante.
  Panneau de touches à hauteur fixe, ancré en haut et découpé au bord inférieur ;
  repère du geste global. Le fond système suit ainsi la zone réservée au clavier.
  Retour élastique si geste annulé, fermeture native sinon. 164 tests réussis et
  build iPhone réussi (`/tmp/plaquisto-keyboard-container-tests.log`,
  `/tmp/plaquisto-keyboard-container-device.log`). Contrôle simulateur sur Résistance
  thermique : ouverture, petit geste annulé et fermeture complète. Le maintien lent
  en cours de geste doit être recontrôlé sur l'iPhone, où le défaut a été signalé.
  Installation physique confirmée à 13 h 24, séquence 2656, données conservées
  (`/tmp/plaquisto-keyboard-container-install.json`).

- Correctif du glissement : `UIInputView` de style `.default` transparent (sans
  second fond système), repère nommé fixe autour du panneau mobile et déplacement
  sans animation implicite pendant le geste. Suppression de la pré-animation de
  160 ms avant la fermeture native : retrait du focus immédiat à la fin du geste.
  Petit glissement et fermeture complète vérifiés au simulateur ; 164 tests passent
  (`/tmp/plaquisto-keyboard-drag-tests.log`). Build iPhone réussi et installation
  confirmée, séquence 2648 (`/tmp/plaquisto-keyboard-drag-install.json`).
  Le ressenti d'un glissement très lent reste à confirmer sur l'iPhone physique.

- `PlaquistoNumericField` fournit un `UITextField.inputView` public commun aux
  configurateurs, ouvertures, outils, dimensions du calepinage et surfaces facultatives.
  Sources incluses dans les cibles iOS et Lab ; les champs de texte restent natifs.
- Pavé 7–8–9 / 4–5–6 / 1–2–3 / 0–virgule–effacer, bouton vertical Valider qui
  applique la saisie puis retire le focus. Plus de barre Terminé du calepinage.
  Sélection complète au focus, entier sans virgule, coordonnées signées avec ±.
  Le champ conserve sa politique métier pour les valeurs vides et ses unités.
- Poignée interactive : mouvement descendant, retour élastique sous le seuil,
  fermeture au-delà du seuil ou sur geste rapide. Génération du clavier renouvelée
  après fermeture pour éviter un état bloqué ou un callback visant un autre champ.
- Validation : 164 tests réussis (`/tmp/plaquisto-numeric-tests.log`), compilation iOS
  simulateur et iPhone réussie. Contrôle réel du simulateur en clair et sombre :
  remplacement 100 → 123, effacement puis 12,5, Valider, réouverture, changement de
  champ, petit glissement conservant le clavier et grand glissement le fermant.
  Les tailles alternatives et VoiceOver restent à contrôler sur appareils.
- Plaquisto iOS installé sur l’iPhone le 20 septembre à 11 h 52, séquence 2640,
  puis lancé avec succès à 11 h 53, données conservées ;
  `/tmp/plaquisto-numeric-install.json` et `/tmp/plaquisto-numeric-launch.json`. Inclut les modifications
  précédentes de contrainte du déplacement et d’alignement conservant le zoom.


## Organisation facultative — règle actuelle, 20 septembre

Cette décision remplace les règles historiques de pièce obligatoire et d'attribution
automatique des cloisons à la plus petite pièce décrites plus bas.

- Projet → ouvrages directement. Pièce, niveau et zone sont facultatifs et indépendants.
  L'utilisateur choisit les rattachements ; aucune attribution basée sur la surface.
- Création configurée sans pièce autorisée, nom d'ouvrage facultatif avec proposition
  automatique, rubrique Organisation repliée. Export de calepinage sans pièce autorisé.
  Les ouvertures sans pièce ne sont plus bloquées.
- Action Organisation sur chaque ouvrage : pièce existante/nouvelle/aucune, niveau et
  zone libres, modifiables et effaçables. Aucun calepinage n'est copié ou reconstruit.
- Quantitatifs : sélection explicite d'ouvrages, Tout sélectionner dans le projet,
  sélection des résultats filtrés ; filtres indépendants pièce/niveau/zone. Les éléments
  sélectionnés hors filtre restent comptés et sont indiqués. Chaque ouvrage compte une fois.
- Données : `WorkItem.level` et `zone` optionnels, lecture des archives sans ces champs,
  conservation à la duplication. `roomID` reste optionnel. Les références géométriques
  des côtés et des liens plafond–mur ne dépendent plus du rattachement organisationnel.
  Les confirmations d'impact géométrique restent obligatoires.
- Le nouveau parcours de calepinage cloison à deux faces est **reporté** selon l'utilisateur.
  Les plans de cloison déjà enregistrés restent accessibles et conservés.
- Validation : **156 tests réussis**, `/tmp/plaquisto-flexible-organization-final-tests.log` et
  `/tmp/plaquisto-flexible-organization-lab.log`. Compilations iOS et Lab réussies.
  Contrôle UI simulateur : ouvrages visibles au premier niveau, Configurer sans pièce,
  enregistrement de RDC sur le plafond du projet QA, filtre RDC (un ouvrage),
  Tout sélectionner (deux ouvrages dont un hors filtre). Aucun plan ni ouvrage supprimé.
  Installation physique de Plaquisto iOS confirmée le 20 septembre à 00 h 33,
  séquence 2576, après compilation signée réussie. Données conservées.
  Logs `/tmp/plaquisto-flexible-organization-device.log` et
  `/tmp/plaquisto-flexible-organization-install.json`.

## Calepinage multi-vues par ouvrage — 20 septembre

- L'accès depuis la pièce ouvre directement le calepinage de l'ouvrage. Le sélecteur
  « Sous-parties du calepinage » est dans l'éditeur : choisir un mur/une zone, ajouter,
  renommer. Plus d'étape intermédiaire « Composants d'ouvrage » dans le parcours usuel.
- Un seul conteneur logique par ouvrage (identité WorkItem). Les sous-parties réutilisent
  les composants stables déjà présents dans la sauvegarde du projet, sans fichiers autonomes
  supplémentaires ni conversion destructive. Les composants restent une structure interne
  pour préserver les références scan, les liens plafond–mur et les côtés de cloison.
- Contours, calepinages et électricité indépendants entre sous-parties. Cloisons : côtés
  distincts, support et ossature communs en miroir ; pièce propriétaire inchangée.
- Avant de quitter/changer de sous-partie, si le document métier a changé : Enregistrer
  et continuer / Abandonner / Rester. Déplacement de vue, zoom et visibilité ne demandent
  pas de validation. Une sauvegarde en échec ou une confirmation d'impact refusée ne quitte
  pas le plan. Les confirmations plafond–mur et ossature partagée sont conservées.
- Renommage atomique sans changer les IDs, plans, révisions ou correspondances.
  Pas de nouvelle suppression de sous-partie : le modèle précédent n'en proposait pas.
- « Relations et pièces » conserve la gestion des pièces voisines et des murs reliés,
  sans en faire un passage obligé. Le quantitatif reste celui du formulaire d'ouvrage ;
  l'agrégation automatique des métrés des sous-parties n'est pas ajoutée dans ce lot.
- Validation : **154 tests réussis**, compilations iOS et Lab réussies.
  Logs `/tmp/plaquisto-workbook-final-tests.log`, `/tmp/plaquisto-workbook-lab.log`.
  Contrôle UI : ouverture directe Plafond A depuis Bureau ; visibilité modifiée sans
  confirmation ; ajout de « Zone test multi-vues », contour rectangle 400 × 250 cm ;
  changement vers Plafond A avec confirmation, Enregistrer et continuer, retour au
  contour original 420 × 249,8 cm intact. La nouvelle zone reste dans le projet QA
  du simulateur, aucun ouvrage ni contour existant n'a été supprimé.
  Installation sur iPhone de Plaquisto iOS confirmée le 20 septembre à 00 h 08,
  séquence 2568, après compilation signée réussie. Données conservées.
  Logs `/tmp/plaquisto-workbook-device.log`, `/tmp/plaquisto-workbook-install.json`.
  Cette évolution n'est pas encore poussée sur GitHub.

## Navigation par pièces et quantitatifs — 19 septembre

- Accueil projet centré sur les pièces, sans liste globale des ouvrages ni en-tête gris « Projet ».
  Actions distinctes : Organiser, Ajouter un nouvel ouvrage, Voir les quantitatifs.
- Les ouvrages sont consultables dans leur pièce, avec les actions existantes (renommer,
  dupliquer, suppression confirmée), les alertes tapées, les composants et leurs calepinages.
  Les cloisons liées restent accessibles mais comptées dans leur seule pièce propriétaire.
- Sélection multiple de pièces pour les quantitatifs, Tout sélectionner / Tout désélectionner.
  Réutilisation du calculateur existant, union dédupliquée des ouvrages propriétaires.
  Une pièce vide reste sélectionnable, avec résultat nul explicite et sans chargement réseau inutile.
- Création configurée : pièce obligatoire, champ « Nom de la pièce », choix existant ou
  création atomique. Dans une pièce, le champ est prérempli. Les ouvertures liées héritent
  de la pièce de référence ; les ouvertures manuelles sans pièce demandent ce rattachement
  à l'enregistrement. Une référence ancienne sans pièce doit d'abord être organisée.
- Aucune suppression/migration destructive. Les éventuels anciens ouvrages sans pièce restent
  signalés dans Organiser et sélectionnables comme « Ouvrages à rattacher » dans les quantitatifs.
  Tout sélectionner les inclut pour conserver l'égalité avec le total du projet.
- Ce lot ne modifie ni les formules métier, ni les relations géométriques, ni le scanner.
  **153 tests réussis**, compilations iOS et Lab réussies. Logs :
  `/tmp/plaquisto-room-navigation-final-tests.log`, `/tmp/plaquisto-room-navigation-ui-build.log`,
  `/tmp/plaquisto-room-navigation-lab.log`.
- Contrôle UI simulateur : accueil projet, accès aux ouvrages du Bureau, champ de pièce
  prérempli, sélection Salon seul (nul, cloison exclue), Tout sélectionner (2 ouvrages,
  20 m²), fournitures calculées. Pas de création/suppression de données de test lors de ce contrôle.
- À la demande de l'utilisateur, compilation iPhone réussie et installation physique
  de `fr.plaquisto.app` confirmée le 19 septembre à 23 h 39, séquence **2560**.
  Logs `/tmp/plaquisto-room-navigation-device.log` et `/tmp/plaquisto-room-navigation-install.json`.
  Données conservées. Ce lot reste non commité/non poussé.

## Livraison sur iPhone et GitHub — 19 septembre, 00 h 27

- Code livré : `60860b5`, poussé sur `origin/codex/tools-lab-improvements`.
  Pas de fusion sur `main`.
- Compilation Debug iPhone signée réussie, cible **Plaquisto iOS** (`fr.plaquisto.app`).
  Log : `/tmp/plaquisto-ios-device-20260919.log`.
- Installation physique confirmée à 00 h 26 sur l'iPhone 16 Pro, séquence **2320**.
  Lancement confirmé à 00 h 26 min 56 s. Plaquisto Lab n'a pas été remplacé.
  Résultats : `/tmp/plaquisto-ios-install-20260919.json` et
  `/tmp/plaquisto-ios-launch-20260919.json`.
- Aucun effacement de données réalisé lors de cette installation. Le nouveau
  stockage projets v2 reste distinct des anciennes sauvegardes, comme décrit ci-dessous.
  Les vérifications fonctionnelles de ce lot restent les 150 tests et le contrôle
  UI simulateur ; aucun nouveau scan LiDAR physique n'a été exécuté lors du déploiement.

## Relations plafond–mur et confirmation — 19 septembre

- Relations explicites entre un bord de plafond et la longueur entière d'un
  composant mur, dans une pièce. Identités métier, origine manuelle ou observation
  de scan ; aucune déduction par noms ou égalité des longueurs. API indépendante
  de RoomPlan prête à recevoir les correspondances d'un futur adaptateur LiDAR.
- Parcours composant plafond → **Murs reliés au plafond** : aperçu du bord,
  association explicite et retrait confirmé. La création du lien ne redimensionne rien.
- Enregistrement d'un plafond modifié : écran des anciennes/nouvelles longueurs,
  **Appliquer aux murs et enregistrer**, **Enregistrer le plafond uniquement** ou
  **Revenir au plan**. Refus conservé comme écart visible après rechargement.
  Validation et écritures atomiques ; une confirmation périmée est refusée.
- Ajustement limité aux murs rectangulaires sans contraintes verrouillées, bord
  droit déplacé depuis l'origine canonique gauche. Aucun déplacement des ouvertures,
  points électriques ou ossatures. Une réduction les faisant sortir du support
  impose une correction manuelle. Plans/quantitatifs concernés signalés à vérifier.
- Longueur horizontale calculée depuis le repère 3D lorsqu'il est disponible.
  Changement de topologie ou de pièce : lien à vérifier, pas de report aveugle vers
  un autre bord. Copie de projet : liens réaffectés ; copie d'ouvrage seul : aucun
  lien implicite ; suppression d'ouvrage : seuls ses liens sont retirés.
- **150 tests réussis, zéro échec**, compilations iOS et Lab simulateur réussies.
  Logs `/tmp/plaquisto-adjacency-tests-final.log` et
  `/tmp/plaquisto-adjacency-lab-final.log` ; résultat
  `Test-Plaquisto-2026.09.19_00-09-32-+0200.xcresult`.
- Contrôle UI réel du simulateur : projet local « Test organisation », Bureau -
  Plafond / Plafond A relié à Bureau - Cloison / Mur A, correction A–B de 400 à
  420 cm, confirmation affichée, refus choisi : plafond 420 cm et mur 400 cm,
  avertissement d'écart visible. Projet de contrôle conservé. Pas d'installation iPhone.
- Limite observée hors de la propagation : une seconde correction A–B à 430 cm
  dans ce contour devenu trapézoïdal déclenche une erreur de découpe du moteur
  existant. Aucun enregistrement supplémentaire effectué ; retour au dernier état
  420/400. À reproduire/corriger dans le moteur polygonal séparément. L'acceptation
  transactionnelle est couverte par les tests automatisés, pas validée via ce second
  scénario UI bloqué par la découpe.
- Restent à implémenter : détection des correspondances dans le scan, création des
  ouvrages/composants depuis ses observations et navigation depuis la scène 3D.
  Contrat et limites détaillés dans `docs/IMPLEMENTATION_STRUCTURE_PROJETS.md`.

## Structure des projets — premier lot livré, 18 septembre

- Pièces identifiées, ouvrages propriétaires, composants et plans de calepinage
  persistés. Un ouvrage sans géométrie reste global : aucun mur n'est inventé à
  partir de sa seule surface. Documentation : `docs/IMPLEMENTATION_STRUCTURE_PROJETS.md`.
- Parcours pièce → ouvrage → composants → plans des deux côtés d'une cloison.
  Toute la cloison est comptée dans sa pièce propriétaire ; l'autre pièce affiche
  un lien. Déduplication des ouvrages dans les quantitatifs.
- Contour, ouvertures géométriques et ossature uniques pour une cloison ; plaques
  et électricité propres à chaque côté. Un décalage d'ossature de +5 cm côté A
  apparaît à −5 cm côté B. Confirmation avant application aux deux côtés ; contrôle
  de révision empêchant un ancien éditeur de rétablir une ossature périmée.
- **Plafond et mur adjacent sont des composants distincts** : ne jamais modifier
  automatiquement la longueur du mur lors d'une correction du plafond. Le futur
  raccordement géométrique devra proposer le changement et demander confirmation.
  Ce lien inter-composants n'était pas encore actif dans ce premier lot ; voir
  l'implémentation complémentaire du 19 septembre ci-dessus.
- Nouveau fichier `projects-v2.json`, écrit atomiquement ; l'ancien `projects.json`
  reste intact et n'est pas importé. Aucun fichier utilisateur supprimé.
- Copie des projets/ouvrages avec nouvelles identités et réaffectation des liens.
  Éditeur embarqué isolé de la bibliothèque et du brouillon autonome des outils.
- Correction du lancement du formulaire de création : transmission d'un brouillon
  immuable évitant un nom vide au premier affichage. Vérification réelle dans le
  simulateur : création Bureau/Salon, ouvrage cloison, composant Mur A, deux plans,
  confirmation d'ossature commune et lien depuis Salon sans ouvrage compté deux fois.
  Le projet local « Test organisation » reste disponible pour contrôle.
- Validation finale : **143 tests réussis, zéro échec** ; compilation iOS par la
  session de tests et compilation Lab réussies. Logs :
  `/tmp/plaquisto-structure-verified.log`, `/tmp/plaquisto-structure-lab-verified.log`.
  Résultats : `Test-Plaquisto-2026.09.18_23-45-23-+0200.xcresult`.
  Contrôles sur simulateur uniquement, pas d'installation iPhone pour ce lot.
- À poursuivre : raccordement du scan 3D aux composants, identité commune des
  ouvertures, métrés multi-composants vers les calculateurs, provenance détaillée
  des fournitures, photos et observations vocales. La navigation complète depuis
  le scan n'est donc pas encore livrée.

## Intégration des outils Lab dans Plaquisto iOS — 18 septembre

- Catalogue partagé : Calepinage 2D accessible dans iOS comme dans Lab ; retrait du
  verrou d'accès expérimental et de l'ancien badge « AVEC ASTRA ».
- Les deux cibles compilent le même éditeur de calepinage, les calculateurs et le
  montage avant/après. En Debug iOS, contrôle du filigrane autorisé comme dans Lab ;
  le comportement des droits en Release reste inchangé.
- Dossier métier nommé « Projet » dans les onglets, formulaires et exports. Les
  mentions pédagogiques « sur chantier » restent pertinentes et conservées.
- Duplication de projet : les ouvertures référencent les ouvrages copiés, avec
  vérification après rechargement dans `ProjectStoreTests`.
- Validation automatique finale : **137 tests réussis, zéro échec et zéro ignoré**,
  `Test-Plaquisto-2026.09.18_22-48-13-+0200.xcresult`. Compilations Debug simulateur
  de Plaquisto iOS et Plaquisto Lab réussies. Logs : `/tmp/plaquisto-ios-tools-final.log`
  et `/tmp/plaquisto-lab-tools-final.log`.
- Version iOS installée et lancée dans le simulateur iPhone 17 Pro. Contrôle UI :
  onglet Projets, catalogue commun, accès Calepinage 2D, création mur 400 × 250 cm,
  passage par l'éditeur de contour, cinq modes/icônes, sauvegarde, bibliothèque,
  réouverture (4 plaques, 10 m²), menu et formulaire d'export vers un ouvrage.
  Un plan de test « Mur » de 10 m² reste dans la bibliothèque iOS. Aucun projet
  existant n'a été modifié par ce contrôle. Capture photo réelle et gestes multitouch
  sur appareil physique non revalidés dans cette livraison ; pas d'installation iPhone.

## Décisions d'architecture confirmées — 18 septembre

- Projet → Pièce → Ouvrage → Composant d'ouvrage → Plan de calepinage.
- Le doublage total est l'ouvrage ; chacun de ses murs est un composant.
- Toute la cloison, y compris ses deux côtés, est imputée à la pièce propriétaire
  (plus petite pièce par défaut). L'autre pièce propose un lien, sans double comptage.
- Les anciennes sauvegardes de test peuvent être supprimées : aucune migration
  patrimoniale n'est requise. La remise à zéro sera ciblée, sans toucher aux sources,
  référentiels métier ou photos originales. Aucune suppression effectuée à ce stade.
- Intégrer et vérifier les outils iOS avant de refondre la structure persistée.
- Références : `docs/ARCHITECTURE_DONNEES_PROJETS_SCAN_CALEPINAGE_QUANTITATIFS.md`
  et `docs/AUDIT_MIGRATION_PROJETS_COMPOSANTS.md` (addenda prioritaires).

## Calepinage 2D — organisation et visibilité

### Bibliothèque et finition des commandes — 17 septembre, suite

- Icônes dans les mêmes cinq colonnes que les modes : angle (sous Vue), plaque,
  ossature, fenêtre à double cadre, éclair. Les cotes sont décalées à droite des
  profils ; cycle visible/coté/masqué en pointillés atténués conservé.
- Bouton bas gauche « Aligner le bas sur l’axe horizontal » à la place de X/Y.
  Alignement de caméra uniquement : aucune mesure, contrainte, position de plaque
  ou point électrique n'est modifié, pour les murs comme pour les plafonds.
- Création d'un gabarit : Suivant → **Modifier le contour et l’échelle** → Utiliser
  → calepinage. Annuler revient au formulaire sans créer de document.
- Retour haut gauche et retour du menu enregistrent puis reviennent à la bibliothèque
  locale, pas à Outils. Le parcours embarqué dans un ouvrage conserve son retour propre.
- Bibliothèque : vignette contour + joints des plaques uniquement, type, aire brute
  du support et date de création. Aperçu Canvas léger sans recalcul du quantitatif.
- Glissement : Renommer et Supprimer. `allowsFullSwipe:false`, bouton rouge puis
  confirmation explicite ; pas de suppression par grand glissement. Renommage vide refusé.
- `SavedLayoutDocument.createdAt` persisté et conservé aux modifications/renommages.
  Anciennes sauvegardes : repli sur `updatedAt`, seule date historiquement disponible.

Validation de cette finition : **65 tests réussis**, zéro échec/ignoré,
`Test-Plaquisto-2026.09.17_23-36-26-+0200.xcresult`. Miniatures et icônes inspectées.
Contrôle UI simulateur : ordre/alignement des commandes, bouton d'alignement, retour
en bibliothèque, renommage annulé, confirmation de suppression annulée, passage
gabarit → éditeur de contour → annulation vers le formulaire. Aucun calepinage supprimé.
Compilations Lab simulateur et iPhone réussies. Installation physique Lab confirmée
le 17 septembre à **23:42**, séquence **2256** (`fr.plaquisto.lab`).

### Livraison précédente : organisation et visibilité

- Éditeur partagé murs/plafonds, formes libres et prédéfinies : **Vue, Plaques,
  Ossatures, Ouvertures, Électricité**. Mode Sélection supprimé ; toucher une plaque
  en mode Plaques ouvre son dessin coté. Glissement de la grille conservé.
- Cinq icônes évolutives remplacent Affichage : visible, coté, masqué en pointillés
  atténués ; angles simplement affichés/masqués. Plaques/ossatures/ouvertures/électricité
  visibles sans cotes par défaut ; angles masqués. Cotes en cm, longueurs des profils
  parallèles aux ossatures. Couches cachées non manipulables invisiblement.
- Menu `…` → **Modifier le contour et l’échelle** pour les dimensions du support.
  Aperçu agrandi, annotations éloignées avec évitement des collisions et rappels.
- Après le nouveau tracé : base horizontale par rotation globale. **Plafonds :
  aucun angle redressé. Murs uniquement : deux angles au sol proches de 90°
  (tolérance 8°) équarris**, sous réserve de validité géométrique. Aucun verrou
  ajouté ; contours existants/mesurés et déplacement libre des sommets préservés.
- Nouveaux supports : ossature initiale compatible avec le format des plaques.
  Réouverture des anciens documents inchangée. Ossatures des murs verticales.
- Calculs de découpes/métrages toujours au relâchement, pas pendant les déplacements.

Documentation détaillée : `docs/CALEPINAGE_DESSIN_MANUEL.md`.

Validation : **62 tests `SheetLayoutEngineTests` réussis**, aucun échec/ignoré,
`Test-Plaquisto-2026.09.17_23-00-18-+0200.xcresult`. Couverture ajoutée : base
horizontale, angles des plafonds conservés, équarrissage réservé aux murs,
concavité/triangles, états d'affichage et ossature initiale compatible.
Rendu synthétique d'un contour à dix sommets et des cinq icônes dans leurs trois
états inspecté visuellement : labels séparés, états masqués pointillés et atténués.
Tests de sauvegarde, contraintes, déplacement libre et absence de recalcul pendant
les gestes toujours passants. Compilation Lab simulateur réussie et version installée
dans le simulateur. Contrôle UI réel sur un plafond sauvegardé : ordre des modes,
sélection de la plaque 6, fiche cotée, longueurs des ossatures dans leur sens,
cycles indépendants et masquage effectif vérifiés. Aucun plan de test sauvegardé/modifié.
Compilation/signature Lab iPhone réussies (`/tmp/plaquisto-layout-visibility-device-final.log`).
Installation physique confirmée le 17 septembre à **23:07**, bundle `fr.plaquisto.lab`,
séquence d'installation **2248**. Les gestes multitouch physiques restent à confirmer
à l'usage sur l'iPhone.

## Montage avant / après

### Caméra manuelle et montages mémorisés — version actuelle

- Liste : aperçu du montage complet, reconstruit depuis ses réglages enregistrés (mode,
  position et angle de diagonale, recalage, filigrane et texte), sans recadrer les deux images.
  Les anciens projets avec miniature Avant seule en bénéficient sans migration destructive.
- Réglages sauvegardés après 450 ms d'inactivité, au retour et au passage en arrière-plan.
- Suppression du curseur « Séparateur » externe, du bouton « Réessayer le recalage », et
  du panneau « Photo d’origine et compatibilité ». Ville : « Retrouver la ville via les
  métadonnées de la photo », confirmation du géocodage conservée.
- Diagonale : poignée ronde avec flèches de rotation, pivot au centre du segment visible.
  Géométrie commune masque/trait pour aperçu, miniature et export. `diagonalAngle` optionnel
  en radians (normale en coordonnées normalisées) ; absent sur les anciens JSON = π/4.
- Caméra : capture manuelle uniquement, pas de message de cadrage, menu ni indicateur A.
  À gauche : photo Avant et vue caméra masquables séparément. À droite : curseur vertical
  d'opacité 0–80 %, accessible VoiceOver. Masquer la vue ne coupe pas la session ; le
  déclencheur capture toujours l'image réelle sans calque. Flash de confirmation conservé.

Validation : **32 tests ciblés réussis**, aucun échec/ignoré, résultat
`Test-Plaquisto-2026.09.17_21-27-49-+0200.xcresult`. Tests ajoutés : compatibilité JSON
sans angle, cohérence trait/masque sur tout le tour, sauvegarde automatique et rendu de
miniature identique au moteur d'export. Miniatures synthétiques diagonale et côte à côte
inspectées visuellement (photos unies rouge/bleu, pas des captures réelles). Compilation
Lab iPhone réussie (`/tmp/plaquisto-photo-simplified-device-final.log`). Les gestes physiques
et l'ergonomie du nouveau curseur caméra restent à confirmer sur le téléphone.
Installation physique Lab confirmée le 17 septembre à 21:30, séquence 2240.

### Historique : première interface appareil photo

Retour au calque photo, à la demande de l'utilisateur : suppression des traits et de
leur calcul dans le parcours caméra, sans effacer les sources expérimentales du dépôt.
Viseur sur fond noir, pas de formulaire défilant, déclencheur rond blanc en bas au centre.
À gauche : visibilité du calque et teinte bleue facultative ; à droite : opacité +/-.
Photo en couleurs naturelles par défaut, opacité 20 %, réglable de 5 à 60 %.
Les objectifs restent accessibles au-dessus du déclencheur ; prise automatique et exposition
sont dans le menu supérieur. Le guidage stable et le flash après succès sont conservés ;
le balayage des traits et son délai artificiel sont supprimés. L'analyse du cadrage ne
dépend plus du modèle de contours. Référence et capture gardent le même rapport d'aspect.
Les sections ci-dessous documentent les versions précédentes.

Validation : 29 tests ciblés réussis, dont préparation de référence sans extraction de
contours (`Test-Plaquisto-2026.09.17_18-17-39-+0200.xcresult`). Le fonctionnement caméra
réel et le rendu du nouveau viseur restent à confirmer sur l'iPhone.
Installation de cette interface confirmée le 17 septembre à 18:44 : `fr.plaquisto.lab`,
séquence 2232. La signature initiale avait expiré ; nouvelle compilation et signature
réussies (`/tmp/plaquisto-camera-ui-device-retry.log`). Les 29 tests ciblés restent ceux
de la même version du code ; aucune modification fonctionnelle lors de la reprise.

### Réglages des calques — ajout après le guide structurel

À la demande de l'utilisateur, la photo Avant est désormais affichée avec les traits
par défaut, légèrement teintée en bleu, à 10 % d'opacité (réglable de 5 à 25 %).
Le bouton « Afficher les traits » reste indépendant : photo seule, traits seuls,
les deux ou aucun guide. Les intensités ne modifient ni la capture ni le calcul du
cadrage. Si les traits sont masqués, le balayage lumineux sur les traits l'est aussi ;
le flash de confirmation reste actif. Réglages locaux à l'écran caméra.

Validation : 28 tests ciblés réussis (`Test-Plaquisto-2026.09.17_18-05-47-+0200.xcresult`),
compilation Lab iPhone réussie (`/tmp/plaquisto-blue-overlay-device.log`), installation
physique confirmée à 18:07, séquence 2224. Rendu caméra réel encore à apprécier sur téléphone.

### Version actuelle — guide structurel blanc (17 septembre, 17:55)

L'ancien filtre adaptatif cyan décrit ci-dessous est remplacé par TEED embarqué (MIT),
puis suppression des textures denses, squelettisation et simplification en polylignes.
Seuls les traits blancs transparents et leur léger halo sont superposés au flux caméra :
jamais la photo Avant. Traitement ponctuel sur la photo, hors thread UI, sans envoi réseau.
Les effets de balayage lumineux puis flash, le guidage live et le déclenchement manuel restent présents.
L'auto-capture est suspendue si le guide est absent ou en erreur.

Contrat portable `BeforeAfterGuideExtracting`, adaptateur CoreML séparé, mêmes poids exportés
en ONNX pour Android (pas d'app Android implémentée). Provenance, licence, empreintes,
conversion et contrôle visuel reproductible : `scripts/structural_guide/README.md`.

Validation actuelle : **28 tests ciblés réussis**, aucun échec/ignoré, résultat
`Test-Plaquisto-2026.09.17_17-53-11-+0200.xcresult`. Compilation Lab iPhone réussie
(`/tmp/plaquisto-structural-device-final.log`), `git diff --check` propre.
Calque réellement produit par le code de production inspecté sur la photo utilisateur :
`/tmp/plaquisto-structural-final-black.png`. Pierres largement supprimées ; certains joints
de sol et interruptions de silhouettes subsistent. Pas de prétention à reproduire exactement
le dessin artistique de référence, ni de validation de capture automatique réelle.
**Installation physique de `fr.plaquisto.lab` confirmée à 17:55, séquence 2216.**
Lancement automatique refusé à 17:56 car l'iPhone est verrouillé ; l'utilisateur peut
ouvrir Plaquisto Lab après déverrouillage. L'installation elle-même a réussi.

### Historique des versions précédentes

Correctif contours invisibles : défaut reproduit par test (ancien filtre : 0 pixel visible sur mur pâle). Extraction désormais adaptative à la luminance, traits légèrement épaissis, cyan avec ombre sombre ; fond strictement transparent. Message si préparation impossible ou photo sans contours discernables. Tests faible contraste et orientation ajoutés.

Validation correctif : **24 tests ciblés réussis**, 0 échec, résultat `Test-Plaquisto-2026.09.17_11-15-14-+0200.xcresult`. Guide synthétique pâle inspecté visuellement (PNG attaché au test) ; test de régression reproduit en échec avant correction. Validation sur la photo réelle de l'utilisateur encore nécessaire.

Build iPhone correctif réussi (`/tmp/plaquisto-contours-fixed-device.log`) et installation physique confirmée à 11:18, séquence 2208.

Évolution du 17 septembre : nom et descriptif simplifiés. En caméra, la photo Avant n'est jamais superposée : guide de contours blancs transparents uniquement, intensité réglable, clignotement supprimé. Analyse live bornée (480 px, au plus une analyse toutes les 600 ms, images en retard ignorées), conseils de cadrage indicatifs, validation temporelle conservatrice et déclencheur manuel permanent. Balayage lumineux sur les contours avant la capture, revalidation du cadrage automatique après l'effet ; flash plein écran uniquement après succès. Les directions sont des suggestions fondées sur l'image, pas une mesure 3D de déplacement.

Filigrane Plaquisto répété en diagonale, opacité 23 %, même placement aperçu/export. Désactivation autorisée explicitement dans Lab par injection de capacité, sans simuler un abonnement ; choix conservé dans le projet. Le comportement de production par défaut reste inchangé.

Validation de cette évolution : **22 tests BeforeAfterTests réussis**, dont transparence du guide, prudence du guidage et attente stable, droit de désactivation Lab et export. Résultat `Test-Plaquisto-2026.09.17_11-02-58-+0200.xcresult`. Compilation finale iPhone réussie (`/tmp/plaquisto-guidance-device-final.log`), installation physique de `fr.plaquisto.lab` confirmée à 11:06, séquence 2200. Le guidage en conditions réelles et la perception des animations restent à valider avec l'utilisateur ; aucune prise automatique réelle n'a été effectuée par l'agent.

Nouvel outil ajouté dans « Photos chantier », sans changer les autres calculateurs. Détail technique, format des projets, limites et checklist matérielle : `docs/AVANT_APRES_GUIDE.md`.

- Import Photos sélectif par fichier, lecture EXIF/GPS disponible, copies locales orientées correctement et limitées à 2 400 px. Les originaux de la photothèque restent intacts.
- Caméra AVFoundation sur file dédiée : calque, opacité, clignotement optionnel, objectifs physiques disponibles, permission/refus/interruption. Mode vertical ; pas de prétention à reproduire focale/ouverture. Modèle du téléphone vérifié uniquement à partir d'EXIF réellement capturé, pas d'une table spéculative. Exposition approchable après vérification.
- Recalage homographique iOS via Vision, puis contrôles conservateurs de géométrie et de corrélation de contours, recadrage commun et retour aux photos simples si incertain. Capture durable avant traitement ; reprise d'un recalage interrompu à la réouverture.
- Quatre modes, séparateur déplaçable (image/curseur), habillage entreprise/ville facultatif, JPEG sans GPS, partage iOS. Géocodage de ville uniquement après confirmation explicite ; saisie manuelle disponible.
- Liste locale, ouverture/renommage/suppression confirmée. JSON versionné, dates ISO 8601 et fichiers relatifs ; sauvegarde atomique. Retour avec choix de sauvegarde des réglages.
- À la demande de l'utilisateur : **aucun écran compte/abonnement**. Watermark conservé. Point d'injection de capacités futur, non branché sur un faux abonnement local.
- Android : `BeforeAfterModels.swift` et `BeforeAfterServices.swift` sont indépendants des frameworks Apple d'image/caméra/interface et passent seuls `swiftc -typecheck`. Adaptateurs Apple séparés ; coordonnées de recalage et contrat JSON documentés pour un futur moteur Android. **Aucune app Android implémentée à ce stade.**
- Contrôles simulateur : import réel d'une photo de démonstration, EXIF réellement lu, réouverture après redémarrage, comparaison diagonale, texte, recalage repris, export JPEG inspecté et partage natif annulé sans envoi. Projet de QA avec deux images identiques (pas une capture caméra réelle).
- La caméra et la qualité sur de vraies photos de rénovation restent à tester physiquement sur iPhone. Aucun résultat de caméra réelle n'est revendiqué.
- Vérification finale : **113 tests réussis**, dont **18 nouveaux**, 0 échec/ignoré ; résultat `/tmp/PlaquistoLayoutTestsDerived/Logs/Test/Test-Plaquisto-2026.09.17_10-35-16-+0200.xcresult`. Compilations Lab simulateur et iPhone réussies, JPEG final contrôlé visuellement après correction des textes. Aucun déploiement physique de ce nouvel outil n'est revendiqué.

## Mesure d’angle

- Le catalogue partagé présente une rubrique « Mesure d’angle », avec « Angle intérieur · 0–180° », puis « Angle extérieur · 180–360° ».
- Deux schémas Canvas 3D harmonisés représentent des murs épais en blocs, avec joints et alvéoles sur leur dessus. L'arc intérieur est court ; l'arc extérieur part des faces réelles et fait le grand tour dans l'espace libre, jamais le petit arc supérieur de l'image de référence. Pas de dépendance graphique ajoutée.
- La méthode chantier n'est pas mutualisée à tort : l'angle intérieur place les repères sur les murs ; l'angle extérieur montre les murs réels en traits pleins et leurs alignements prolongés dans le vide en pointillés bleus. L et les points A/B sont sur ces prolongements, et D relie A à B uniquement dans la zone accessible. L'équerre est décrite comme guide d'alignement, jamais comme génératrice d'une perpendiculaire.
- Une seule vue paramétrée par `WallAngleKind` réutilise les champs numériques existants (cm, virgule/point, sélection complète, sans bouton accessoire Terminé). L vaut 100 cm par défaut, D est vide. Recalcul immédiat.
- `WallAngleCalculator.calculate` retourne `WallAngleResult` : un seul calcul trigonométrique, puis extérieur = 360 − intérieur. Validation commune des mesures finies, positives et D < 2L, rejet des cas dégénérés et dépassements numériques. L'entrée historique `angle` délègue au même moteur.
- Les schémas ne gardent que les repères L/L/D et l'arc, sans surcharge numérique. Le résultat principal est présenté de la même façon dans les deux outils ; le résultat secondaire intérieur a été retiré et l'aide détaillée est repliable. Aucun écart à 90°, capteur, export, sauvegarde ou calcul d'onglet.

## Vérifications

- Suite `PlaquistoTests` : **95 tests réussis**, aucun échec ni test ignoré.
- Trois nouveaux tests couvrent les quatre exemples d'angle extérieur, l'invariant intérieur + extérieur = 360° sur une série de mesures, les cas invalides et extrêmes, les deux destinations et la rubrique.
- Résultat : `/tmp/PlaquistoLayoutTestsDerived/Logs/Test/Test-Plaquisto-2026.09.17_00-31-45-+0200.xcresult`.
- Compilations Lab simulateur et iPhone réussies. Installation physique de `fr.plaquisto.lab` confirmée le 17 septembre à 00:34 (séquence 2092). Aucun lancement automatique sur le téléphone n'est revendiqué.
- Contrôles visuels simulateur en clair et sombre : cartes distinctes ; schéma extérieur avec murs pleins, prolongements pointillés et D entièrement dans le vide ; angle extérieur 270,0° pour L=100 / D=141,4 avec résultat secondaire 90,0° ; angle intérieur 60,0° pour L=D=100 ; D=200 pour L=100 refusé. Les résultats sont accessibles par défilement sous les champs.
- Les calculs ont été vérifiés automatiquement, les parcours des deux calculateurs manuellement. Il ne s'agit pas d'une garantie métrologique : la précision dépend des mesures au mètre.

## Harmonisation visuelle du 17 septembre (matin)

- Contrôles simulateur : vues 3D intérieure et extérieure à 90°, résultat extérieur 270,0° pour L=100 et D=141,4 ; vue intérieure à 120,0° pour D=173,205.
- Rayon de l'arc limité à l'espace disponible devant la corde, pour les angles ouverts ; annotations simplifiées pour éviter leur chevauchement.
- Moteur mathématique inchangé. Les 95 tests mentionnés ci-dessus correspondent à l'exécution précédente, pas à une nouvelle exécution pour cette retouche graphique.
- Compilations finales Lab simulateur et iPhone réussies. Version 3D installée physiquement le 17 septembre à 09:42, bundle `fr.plaquisto.lab`, séquence 2184, conteneur `397E6C17-FC57-4ECA-99C7-900CDAD87C1D`. L'application de production n'a pas été remplacée. Schéma extérieur final contrôlé dans le simulateur après réinstallation.

## Fichiers de cette extension

- `Plaquisto/PlaquistoCore/Tools/ToolModels.swift`
- `Plaquisto/PlaquistoCore/Tools/ToolsHomeView.swift`
- `Plaquisto/PlaquistoCore/Tools/CalculatorToolsViews.swift`
- `Plaquisto/PlaquistoTests/ToolCalculatorTests.swift`
- Ce document et `docs/CALEPINAGE_DESSIN_MANUEL.md`.

## Travaux précédents

Le détail du calepinage, de l'implantation électrique et des limites à tester au doigt est conservé dans `docs/CALEPINAGE_DESSIN_MANUEL.md`. Le dépôt contient des modifications non commitées de ces travaux : les préserver. La présente extension est testée dans Plaquisto Lab ; aucune publication ni mise à jour de l'app de production n'est effectuée.
