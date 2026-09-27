# Décision actuelle — capture native simple (26 septembre 2026)

## Plafonds et conservation des murs — décision la plus récente

Pas de proposition jaune/verte, ni de recherche de plafond pendant ou à la fin
de la capture. RoomPlan configure sa session sans surcouche de reconstruction
Plaquisto. L’utilisateur crée ensuite son plafond dans **Modifier le plan →
Plafond**, avec choix de forme, hauteurs explicites et aperçu. Les valeurs
préremplies sont des estimations à vérifier, non des observations du plafond.

Le contour natif `polygonCorners` des murs est conservé dans un repère local
portable (`localOutline`, mètres, X le long du mur, Y vertical). Un plafond ne
modifie jamais ce contour. Surfaces, rendu 3D et calepinage emploient le même
profil. Un ancien scan sans ce champ ne peut retrouver ses sommets perdus depuis
le seul rectangle sauvegardé : il faut une nouvelle acquisition ou réimporter
explicitement ses données brutes, ce dernier parcours n’étant pas ajouté ici.

Dans l’éditeur, les ouvertures peuvent être corrigées ou supprimées et les murs
contigus compatibles fusionnés, après confirmation. Une fusion ne doit ni
combler un vide, ni rectifier automatiquement un angle, ni aplatir un rampant.
Le document conserve le scan initial séparément des modifications enregistrées.

## Acquisition

Cette section prévaut sur les itérations historiques ci-dessous. À la demande de
l’utilisateur, la capture multi-pièces personnalisée est retirée. On utilise une
`RoomCaptureView` neuve par relevé, sa maquette native et son guidage. L’app appelle
`run` une fois, puis `stop(pauseARSession: true)` quand l’utilisateur termine.
Elle ne détecte plus les passages pour redémarrer RoomPlan, ne remplace pas le
suivi ARKit et ne dessine plus sa propre miniature cumulative.

Le résultat passe par `RoomBuilder` puis par l’adaptateur portable existant et ouvre
le même espace de travail 3D/2D. Restent inchangés : édition des murs, cloisons,
portes 73/83/93 cm, plafonds, sélection multiple et attribution aux ouvrages/projets.
Les sauvegardes précédentes restent lisibles. Seuls leurs champs d’assemblage
restent dans le format de sauvegarde ; les calculs de raccord, de recalage des
plafonds et de détection des chevauchements sont retirés du code.

Le scan simple ne garantit ni une maison entière en une seule acquisition ni son
découpage automatique en pièces. Ces capacités ne doivent pas être annoncées dans
l’interface. Une future reprise du multi-pièces nécessitera un parcours Apple
explicite et des essais matériels, pas une réactivation implicite des heuristiques.

Contrôles matériels à faire : rotation de la miniature native, absence de relance
Plaquisto à une porte, fin de scan vers l’éditeur, nouveau relevé indépendant du
précédent. Les tests sur simulateur ne valident pas le suivi LiDAR réel.

---

# Plaquisto — relevé LiDAR multi-pièces, cadrage V1

> Décision du 24 septembre 2026, issue de l’audit du dépôt, de six avis consultatifs
> et d’un arbitrage final par un gardien du MVP.

## Correction des repères et de l’aperçu — 26 septembre 2026

### Rotation et interruptions — après analyse du scan réel de 7 h 50

Le relevé `BBCED9D8-2D26-4657-A18D-3D543742508E` conserve deux acquisitions
(salon/salle à manger et cuisine), mais `continuityReliable=false` a empêché
StructureBuilder de s’exécuter. Aucun journal persistant ne permet de distinguer
l’interruption système d’une relocalisation dans cette ancienne sauvegarde.
Les fichiers originaux de l’iPhone n’ont pas été modifiés.

- La caméra de la miniature suit désormais l’azimut de l’iPhone, lissé par le
  chemin angulaire court, avec élévation conservée et zoom indépendant de la
  rotation. Les murs ne bougent pas dans leur repère. Regard quasi vertical :
  dernière orientation conservée pour éviter une rotation indéterminée.
- Une interruption ou un tracking limité fige les mises à jour, conserve la
  miniature et affiche une aide pour retrouver la zone scannée. La relocalisation
  est autorisée, avec les callbacks du delegate natif toujours transmis.
- Après fin d’interruption, des images fraîches avec tracking normal pendant
  une seconde sont nécessaires. Une nouvelle sous-acquisition attend ce retour ;
  pas de reset ARSession et pas de franchissement déduit à travers l’interruption.
- Terminer reste possible pendant l’attente : les acquisitions sont sauvegardées
  séparément sans prétendre au raccord. Les erreurs AR fatales restent terminales.
- `captureEvents`, optionnel et limité aux 500 derniers événements, persiste dans
  le relevé les états tracking, interruptions, reprises, débuts/fins de captures et
  décisions d’assemblage. Pas d’images caméra ni de trajectoire continue enregistrées.
- Les labels sémantiques ne déclenchent pas les transitions. Le détecteur de porte
  reste un découpage technique RoomPlan, et non une validation définitive des pièces.
  La maquette cumulative est indépendante de ce découpage. Passer à une unique
  acquisition sans limites pour toute une maison n’est pas annoncé comme garanti.

### État actif : maquette paramétrique cumulative après le retour sur 3084

- Le rendu natif plaît mais sa miniature se réinitialise à chaque `run`. Elle est
  remplacée par une scène persistante de murs blancs pleins avec ouvertures et
  sols, sur fond transparent. Aucun maillage ARKit n’est utilisé pour son rendu.
- `ScanWorldPreview` ne reçoit que les snapshots **en direct** du delegate,
  dans le repère de l’ARSession continue. Chaque transition conserve le dernier
  snapshot de la pièce sortante et commence une entrée distincte ; un callback
  tardif de l’ancienne acquisition est ignoré. Seul un nouveau relevé vide la scène.
- Les résultats post-traités par RoomBuilder, potentiellement recentrés, ne
  remplacent **jamais** ces snapshots. `liveOverview` reste le registre séparé
  de récupération/revue. StructureBuilder reste l’autorité du modèle final ;
  on ne lui soumet pas de snapshots live non post-traités pour un assemblage.
- Le cadrage englobe progressivement le relevé, sans se rabattre sur la pièce
  entrante. Actualisation limitée à 2,5 Hz et seuls les nœuds modifiés sont reconstruits.
- La perte avérée du suivi interrompt toujours le relevé : ne pas inventer un
  raccord entre deux repères. Le raccord réel et le rendu sur caméra restent à
  tester en marchant entre plusieurs pièces sur iPhone. Les tests synthétiques
  prouvent la rétention de la scène, pas la précision du tracking matériel.

Les décisions suivantes sont conservées comme historique et sont remplacées,
pour la miniature pendant le scan, par l’état actif ci-dessus.

### Décision prioritaire après le test de 07 h 10 (installation 3076)

L’aperçu du maillage ARKit est **rejeté par l’utilisateur** : triangles troués,
aspect bruité, contrairement à la maquette nette de RoomPlan demandée. Il est
retiré, avec ses traitements de rendu, et la miniature native RoomPlan réactivée.
Le maillage conserve son rôle technique pour la reconnaissance des plafonds.
Les écrans 3D/2D après capture, l’édition et l’attribution ne sont pas annulés.

Ce rétablissement concerne le rendu de la **pièce courante**. La maquette propre
de toute la maison, cumulée pendant l’acquisition, reste un besoin non résolu.
Ne pas remplacer ce besoin par un maillage brut ni réintroduire la superposition
de coordonnées RoomBuilder non assemblées. Le paragraphe suivant sur l’aperçu
continu décrit une tentative abandonnée, pas la solution active.

### Évolution suivante : espace de travail et aperçu continu

La demande suivant l’installation 2988 remplace **uniquement la présentation
native par pièce** décrite ci-dessous. Les règles d’assemblage restent impératives.

- La caméra occupe une zone bornée sur fond noir. Une maquette claire, plus
  centrale, utilise les triangles murs/sols du maillage ARKit dans son repère
  mondial. Elle n’est pas recréée lors d’un nouveau `RoomCaptureSession.run`.
  La préparation des triangles et normales se fait hors du fil principal.
  Ce contexte visuel n’est ni une mesure certifiée, ni la géométrie des ouvrages.
- Le modèle métier final reste celui de **StructureBuilder**, avec le contrôle
  des repères et la conservation des caches déjà implémentés. Pas de mélange
  entre maillages AR et coordonnées brutes des résultats RoomBuilder.
- Terminer ouvre directement l’espace de travail : 3D par défaut, Plan 2D coté,
  sélection multiple Murs/Plafonds, bouton Créer un ouvrage inactif sans sélection.
  Les zones non raccordées restent présentées séparément et explicitement signalées.
- Le choix du projet intervient après la sélection : projet existant ou formulaire
  nouveau projet (nom, client, adresse, notes), puis catégories et type d’ouvrage,
  nom facultatif et configurateur prérempli. Contrôle explicite des mesures avant
  attribution ; les doublons et les modifications de source restent refusés.
- L’éditeur 2D travaille sur une copie : déplacement d’un mur scanné et de ses
  extrémités raccordées, longueur/hauteur, création d’une cloison à deux points,
  porte 73/83/93 cm avec hauteur modifiable et déplacement le long du mur.
  Pas de sens d’ouverture. Refus des portes hors limites, des chevauchements et
  des croisements de murs nouvellement introduits. Enregistrer ou Abandonner.
- Le bouton Plafond reprend les quatre familles estimées existantes si aucun
  plafond observé ne doit être écrasé. Les cloisons ajoutées ne servent pas à
  reconstruire le contour extérieur. Un déplacement de mur ne redimensionne pas
  automatiquement les plafonds. Le document initial du scan demeure inchangé.
- Une cloison conçue dans l’éditeur est une seule surface physique sélectionnable
  des deux côtés. L’ouvrage cloison reçoit cette surface une fois ; son configurateur
  gère les parements. Les meubles restent hors périmètre.
- Le parcours après capture et le visualiseur sont partagés iOS/Lab, sans dépendance
  RoomPlan dans les écrans d’exploitation. Le scan continu lui-même exige encore
  une validation sur iPhone : le simulateur ne peut prouver la persistance des
  ancres, la justesse du raccord réel, ni la performance dans une maison entière.

Cette section remplace les décisions antérieures d’afficher tous les résultats
bruts dans une maquette persistante pendant la capture.

- La capture montre la petite maquette progressive **native de la pièce courante**.
  Un accès compact donne les zones conservées en 2D/3D séparément ; une transition
  ne supprime pas les acquisitions précédentes. L’assemblage complet est présenté
  après Terminer, pas en superposant les coordonnées brutes des sous-scans.
- Les résultats de RoomBuilder peuvent être rebases par rapport aux autres
  résultats. Conserver la même ARSession est nécessaire, mais le code doit
  réellement exploiter les `rooms` renvoyées par StructureBuilder. Ne pas utiliser
  l’assemblage comme une simple validation en conservant les anciennes positions.
- L’application du résultat est atomique, garde les IDs métier, les noms et les
  décisions utilisateur. Les murs, sols et ouvertures viennent de l’assemblage ;
  les plafonds supplémentaires changent de repère via les correspondances de murs,
  sans recalage arbitraire ni mise à l’échelle. Les caches RoomPlan bruts subsistent.
- `assemblyVerified` est requis pour afficher/importer plusieurs chunks comme
  géométrie déjà raccordée. Les brouillons historiques sans ce statut ne sont
  pas supposés assemblés. Une perte de suivi/erreur garde les zones séparées.
- Aucun contour de checkpoint post-traité ne doit être projeté dans la caméra
  AR sans conversion de repère vérifiée. Les callbacks du delegate ARKit natif
  doivent être préservés ; nos diagnostics ne doivent pas le remplacer.
- Validation matérielle à faire après installation : scanner deux pièces
  communicantes, franchir la porte, terminer, comparer le raccord en 2D et en 3D,
  puis rouvrir le relevé. Les tests simulateur ne prouvent pas ce parcours matériel.

## Plafonds reconnus et estimés — décision du 25 septembre 2026

- Une reconstruction appuyée sur les observations du plafond est acceptée
  automatiquement, avec « Plafond reconnu ». Pas de plafond jaune/vert superposé
  à la capture, ni de bouton de validation de plafond pendant le scan.
- Sans plafond observé, le résultat final essaie une estimation depuis les murs.
  Il faut un contour fermé unique, non auto-intersectant et un niveau de sol
  cohérent. Les raccords bornés du solveur existant sont réutilisés ; aucun
  rectangle ni enveloppe convexe ne remplace un contour incomplet ou concave.
  Si le contour n’est pas exploitable, aucun plafond n’est inventé.
- Hauteurs uniformes : plat. Deux murs parallèles opposés, suffisamment séparés,
  présentant plus de 10 cm d’écart de hauteur : un pan reliant leurs niveaux.
  Ce seuil filtre le bruit ; il ne constitue ni une règle métier ni une garantie
  de mesure. Les pieds des murs doivent rester dans une plage de 20 cm.
- Le message est alors « Plafond estimé à partir des murs ». La provenance
  `estimated` persiste dans le JSON : une estimation automatiquement acceptée
  n’est jamais marquée comme une observation LiDAR ou une validation manuelle.
- Dans l’éditeur 3D : « Modifier la forme et les hauteurs du plafond » donne
  **Plat, Un pan, Deux pans, Quatre pans**, avec hauteur(s), orientation et
  position du faîtage pour les formes concernées. Les quatre pans utilisent
  des croupes rejoignant un faîtage, ou un sommet quand les dimensions le donnent.
  Les modèles sont recoupés par le contour réel, même concave ; ce ne sont pas
  des toitures complexes détectées automatiquement. Leurs ouvertures non
  relevées ne sont pas déduites.
- L’aperçu distingue les arêtes des pans, propose Perspective/Dessus/Recentrer
  et calcule la surface développée, pas la projection au sol. Enregistrer
  applique une modification explicite ; Annuler laisse la géométrie inchangée.
- La création automatique n’écrase aucun plafond existant. Le réglage des
  modèles ne remplace pas un plafond réellement observé. Le document initial
  reste intact. Les dimensions/quantités des murs ne sont pas modifiées par un
  plafond estimé ; les ouvrages déjà attribués gardent le mécanisme de revue
  après modification du relevé.
- Les anciens documents sans plafond sont complétés à leur ouverture dans
  l’éditeur, si leur contour le permet ; une erreur de sauvegarde n’est pas
  présentée comme un succès. Les paramètres du modèle survivent à la relecture
  et à la duplication d’un projet.
- Cette acceptation automatique concerne **le plafond**, pas la validation
  métier du relevé complet avant attribution aux ouvrages. Les contrôles des
  brouillons, ouvertures, unités et liens spatiaux restent actifs.
- Preuve visuelle indépendante :
  `bash Tests/run-room-model-proof.sh <simulateur> --ceiling-estimate`.
  Elle ouvre l’éditeur de production sur une pièce synthétique sans plafond,
  dans un stockage de test séparé. Elle ne simule pas une acquisition LiDAR.

## Audit initial de l’existant (avant ces incréments)

Le scanner actuel est un socle à conserver :

- `PlaquistoRoomModel` est portable, en mètres, dans un repère droit avec Y vertical ;
- les UUID métier sont distincts des identifiants RoomPlan ;
- une correction manuelle reste prioritaire sur une nouvelle mesure de scan ;
- `RoomPlanAdapter` convertit murs, sols et ouvertures sans imposer RoomPlan au domaine ;
- RoomPlan et le maillage ARKit classifié utilisent déjà la même `ARSession` ;
- la reconstruction des plafonds, ses propositions, ses limites virtuelles et ses
  diagnostics représentent un travail métier spécifique à préserver ;
- la scène 3D permet déjà de contrôler et sélectionner murs et plafonds sans session AR ;
- le moteur de calepinage sait projeter une surface 3D dans son plan local ;
- les ouvrages et leurs composants/plans de calepinage, les liens historiques
  aux pièces, les cloisons partagées et les liens plafond–mur sont déjà persistés
  et validés. Ces liens aux pièces ne constituent pas un classement obligatoire.

Les manques structurants sont les suivants :

- le fichier `scanner-room-v1.json` ne conserve qu’une pièce et reste séparé du Projet ;
- le scanner visible est encore un écran de diagnostic ;
- `startCapture()` réinitialise actuellement le suivi et les ancres ;
- `complete()` met la session AR en pause ;
- aucune transaction ne rattache encore plusieurs pièces scannées à un même relevé ;
- aucune attribution de surfaces scannées aux composants d’ouvrage n’existe encore.

## Retours des sous-agents

Les profils artisan expérimenté, artisan débutant, métreur, UX 3D mobile,
ingénieur RoomPlan/ARKit et critique chantier convergent sur ces besoins :

1. conserver le scanner et le modèle portable existants ;
2. sauvegarder chaque pièce terminée avant de poursuivre ;
3. ne jamais forcer une fusion de pièces ;
4. distinguer les surfaces observées, corrigées, ajoutées et à vérifier ;
5. séparer les modes Explorer et Sélectionner ;
6. associer une vue 3D de compréhension à un plan 2D de correction ;
7. attribuer plusieurs surfaces homogènes dans une transaction unique ;
8. préremplir uniquement la géométrie fiable ;
9. empêcher double attribution, double comptage de cloison et double déduction d’ouverture ;
10. limiter la V1 à un niveau et à des corrections guidées.

Le désaccord principal concernait le degré d’automatisation de l’assemblage. L’arbitrage
retenu est : tentative avec les API Apple uniquement lorsque les espaces monde sont
compatibles ; sinon les pièces restent séparées, utilisables et marquées « à relier ».

## Synthèse et arbitrages

La chaîne de valeur prioritaire est :

```text
Scanner plusieurs pièces
→ contrôler le relevé
→ enregistrer dans un Projet
→ sélectionner plusieurs surfaces
→ attribuer à un Ouvrage
→ ouvrir le formulaire avec la géométrie fiable
```

La V1 n’est pas un clone de Polycam ou de SketchUp. La 3D sert à comprendre,
contrôler et sélectionner. Les corrections sont guidées dans le plan 2D. Une cloison
ajoutée est une géométrie Plaquisto de provenance manuelle, jamais une observation LiDAR.

## Architecture de données retenue

Le modèle existant reste la source de vérité. Il est complété par une enveloppe de relevé :

```text
Projet
└── Relevé 3D (un niveau)
    ├── Checkpoint de pièce 1
    │   ├── Pièce métier du Projet
    │   ├── PlaquistoRoomDocument initial + corrigé
    │   ├── transformation vers le repère du relevé
    │   └── état de liaison spatiale
    └── Checkpoint de pièce 2
```

Règles :

- `ProjectSurveyRecord` et ses checkpoints ne contiennent aucun type Apple ;
- `PlaquistoRoomDocument` reste la géométrie portable d’une pièce ;
- la transformation 4×4 est persistée sous forme de seize `Double` documentés ;
- les artefacts `CapturedRoom`, `CapturedStructure` et `ARWorldMap` sont des caches iOS ;
- la pièce métier et la pièce scannée ont des identités distinctes et liées explicitement ;
- les futures attributions relieront un identifiant de surface du relevé à un
  `WorkComponentRecord`, sans recopier silencieusement la géométrie ;
- la copie et la suppression d’un Projet doivent inclure tout son relevé ;
- l’écriture d’une pièce, de sa pièce métier et de son relevé est atomique.

## Parcours UX retenu

Décision utilisateur révisée : **un seul Démarrer et un seul Terminer pour toute
la maison, sur un niveau**, sans action « pièce suivante ».

1. Démarrer le relevé, parcourir les pièces en balayant murs, passages et plafonds.
2. Au franchissement d’une porte/ouverture stable, terminer un sous-scan interne
   sans arrêter ARKit, puis redémarrer immédiatement RoomPlan dans le même repère.
3. Traiter le résultat précédent avec un contexte figé pendant la suite du scan.
4. Proposer les noms depuis les catégories RoomPlan (salon, cuisine, chambre,
   salle de bains, salle à manger), ou « Pièce à identifier ». Une zone ouverte
   peut avoir plusieurs usages : un nom n’invente jamais une frontière.
5. Terminer le relevé et contrôler les pièces ; noms modifiables, plafonds ajoutés
   automatiquement avec une origine reconnue ou estimée (voir ci-dessous), sans
   validation colorée pendant la capture. Une revisite potentielle est conservée, jamais effacée
   automatiquement : l’utilisateur décide de l’inclure ou de l’écarter.
6. Enregistrer toutes les pièces retenues dans un Projet, en une transaction.
7. Sélectionner plusieurs surfaces dans la scène globale ou la liste du relevé.
8. Créer un doublage rails/montants, un doublage lisses/fourrures, un plafond sur
   fourrures ou un ouvrage **Peinture (bêta)**. Formulaires existants préremplis ;
   peinture provisoire limitée à la surface nette, sans consommables inventés.
9. Chaque surface garde son contour, ses ouvertures et sa provenance dans un
   composant. Un ouvrage peut couvrir plusieurs pièces et est nommé librement.

**Les pièces ne sont pas un classement des ouvrages** : elles servent au repérage
dans le relevé. Le nouveau parcours ne demande aucun rattachement à une pièce.
Les ouvrages appartiennent directement au Projet ; leur nom et leur regroupement
de surfaces sont choisis par l’utilisateur. La provenance pièce/surface est gardée
dans les composants pour retrouver la géométrie, sans créer de dossier de pièce
ni imposer de nom d’ouvrage.

L’anti-doublon est défini par **surface + famille de travaux**, et non surface
seule : doublage puis peinture sur une même surface est légitime. Pour la future
construction d’une cloison ajoutée dans l’app, sélectionner un côté sélectionne
le support entier : ossature une fois, plaques sur les deux côtés selon les couches.
Pour peindre une cloison existante, seuls les côtés explicitement sélectionnés
sont comptés, sans ossature ni parement nouveaux.

## Risques techniques

### Garde-fous et sélection après audit (25 septembre)

- La récupération des brouillons isole chaque fichier illisible, sans le supprimer
  ni masquer les autres. La fin de capture n'est présentée comme sauvegardée
  qu'après une écriture atomique réussie ; sinon les données en mémoire restent
  disponibles avec une action de nouvelle tentative.
- Après « Terminer », le raffinement est borné à 90 secondes. Au-delà, les
  checkpoints déjà acquis sont conservés pour contrôle. Les résultats asynchrones
  tardifs ne doivent pas réécrire une capture annulée ou échouée. Cela ne garantit
  pas l'arrêt immédiat d'un calcul interne au SDK Apple.
- Les nouvelles captures enregistrées dans un Projet ont un statut métier
  explicite : provisoire, à valider ou validé. Une validation utilisateur du
  document courant est nécessaire avant l'attribution aux ouvrages. Un brouillon
  récupéré peut être contrôlé et validé sans devoir reprendre RoomBuilder.
  Un ancien checkpoint dépourvu de statut n'est pas présumé validé : il demande
  le même contrôle avant toute nouvelle attribution, sans modifier ses ouvrages.
- Une modification géométrique du relevé marque les ouvrages concernés à
  contrôler. Elle ne remplace ni leurs composants ni leurs quantités. L'utilisateur
  peut confirmer explicitement qu'il conserve les dimensions de l'ouvrage après
  comparaison avec le relevé. Un simple renommage n'est pas une correction de
  géométrie. Cette alerte reste visible dans les quantitatifs regroupés.
- Les revisites partielles sont des suspicions, pas des décisions : comparaison
  des captures, puis conserver ou écarter explicitement. Pas de fusion automatique.
- La sélection conserve un état distinct pour chaque couple famille/traitement.
  Le plan 2D, la maquette 3D et la liste partagent les mêmes identifiants de
  surfaces. Le résumé distingue surface brute, ouvertures et surface nette.

Ces protections logicielles ne remplacent pas les essais de capture réels :
parcours A → B → A, pièce partiellement observée, interruption, traitement lent,
faible stockage et grand logement restent des scénarios de contrôle sur iPhone.

### Plan 2D complémentaire (25 septembre)

`ScanFloorPlan` projette les mêmes murs corrigés, ouvertures et sols dans le plan
horizontal. Il n’enregistre pas de copie indépendante de la géométrie. Le choix
Maquette 3D / Plan 2D est disponible pendant la capture et lors du contrôle ; le
relevé sauvegardé du Projet propose « Voir le plan 2D ». Zoom, déplacement,
recentrage et longueurs de murs optionnelles sont des états d’affichage uniquement.
Les transformations validées des checkpoints sont appliquées à cette projection.
Les pièces non raccordées sont présentées séparément. Fenêtres en bleu,
portes/passages en pointillés : aucun débattement de porte n’est inventé.

### Retour terrain : l’aperçu ne doit jamais repartir à zéro (25 septembre)

Le premier incrément continu conservait une ARSession commune mais affichait le
modèle de `RoomCaptureView`, limité à l’acquisition courante. Sa remise à zéro à
chaque passage était visible : ce parcours ne satisfaisait pas le besoin utilisateur.

Le correctif utilise une scène globale Plaquisto indépendante (`ScanLiveOverview`
et `ScannerSurveyOverview`) et désactive seulement le modèle intégré Apple avec
`isModelEnabled = false`. La caméra RoomPlan, le suivi partagé et le moteur de
plafonds restent en place. Les checkpoints internes sont conservés, mais leur
transition n’efface plus la scène globale ni les murs déjà acquis. Le cadrage
s’élargit avec le bâtiment, sans recentrer sur la seule pièce courante.

La géométrie portable est maintenant sauvegardée avant toute transition et toutes
les cinq secondes durant l’acquisition. Le raffinement asynchrone remplace le même
checkpoint. En cas d’échec, sa géométrie provisoire reste accessible et marquée à
contrôler. Ceci ne permet pas de reprendre une session AR après relance : la
récupération concerne le relevé sauvegardé, pas le suivi du téléphone.

Référence Apple : [Scanning the rooms of a single structure](https://developer.apple.com/documentation/roomplan/scanning-the-rooms-of-a-single-structure)
décrit le regroupement de captures dans une ARSession continue avec
`stop(pauseARSession: false)`. Le correctif ne remplace pas ce mécanisme par une
acquisition de taille illimitée. Une vérification réelle en marchant entre deux
pièces reste nécessaire, y compris aller-retour et fermeture juste après un passage.

- Le multi-pièces exige une `ARSession` continue et `stop(pauseARSession: false)` entre
  les pièces. Les options `.resetTracking` et `.removeExistingAnchors` ne sont autorisées
  qu’au début d’un nouveau relevé.
- `StructureBuilder` refuse des pièces dont les espaces monde sont incompatibles. Cet
  échec ne doit jamais invalider les checkpoints individuels.
- Une reprise immersive via `ARWorldMap` dépend de la relocalisation et ne peut pas être
  promise en V1.
- Les identifiants Apple servent seulement à la corrélation. Les identifiants Plaquisto
  doivent survivre aux sauvegardes, copies et renommages.
- Les conversions mètres/millimètres restent aux frontières explicites avec le calepinage.
- Aucun calcul métier ne doit être relancé pendant un geste 3D.

## Découpage en MVP

### Incrément 1 — persistance du relevé dans le Projet

- modèle portable de relevé et de checkpoints ;
- transaction d’enregistrement d’une pièce contrôlée ;
- rattachement à une pièce métier existante ou nouvelle ;
- ajout à un relevé existant ou nouveau ;
- copie, suppression, rechargement et validations ;
- accès depuis le scanner actuel, sans supprimer son mode diagnostic.
- accès depuis une pièce déjà sauvegardée ou importée, avec ses corrections ;
- liste des relevés dans le Projet et réouverture de chaque pièce dans l’éditeur
  existant (perspective et vue de dessus) ;
- confirmation avant remplacement d’une capture, protection contre une correction
  provenant d’un éditeur périmé ;
- les captures indépendantes sont par défaut « à relier », jamais présentées comme
  automatiquement assemblées.

### Incrément 2 — coordinateur de capture multi-pièces

- même `ARSession` entre les pièces ;
- checkpoint après chaque traitement ;
- tentative `StructureBuilder` ;
- état « à relier » en cas d’échec ;
- liste des pièces et contrôle global.

Implémentation du parcours continu : `SurveyCapture.swift` contient les types
portables et la détection de franchissement ; `ScannerDebugModel` conserve une
seule session AR, reprend la capture avant RoomBuilder et traite séquentiellement
des contextes de sous-scan figés. Chaque pièce brute portable est écrite avant
la reconstruction de plafond, puis enrichie ; caches RoomPlan et assemblage
sont stockés séparément. Le maillage final est limité au contour du sol et à la
hauteur de la pièce ; les traitements géométriques finaux sont hors thread UI.

Limites à tester sur iPhone : portes non détectées, passages très rapides,
suivi perdu, pièces vides et cuisines ouvertes. Une capture non découpée reste
une zone à contrôler ; aucun algorithme de découpage manuel complet après scan
n’est annoncé ici. Une reprise de brouillon ouvre les données sauvegardées,
mais ne reprend pas une session AR sans relocalisation. Android reste hors scope.

### Incrément 3 — attribution métier

- modes Explorer/Sélectionner ;
- sélection homogène et résumé brut/ouvertures/net ;
- transaction vers un ouvrage et ses composants ;
- préremplissage du formulaire et prévention des doublons.

### Incrément 4 — correction guidée

- plan 2D ;
- cloison droite ;
- porte rectangulaire ;
- annuler/rétablir et confirmation des impacts liés.

Sont reportés : reprise immersive garantie, multi-niveaux dans un même relevé,
raccordement manuel avancé, géométries courbes, édition 3D libre, médias et notes vocales.

## Fichiers concernés

- `PlaquistoRoomModel.swift` : enveloppe portable de relevé ;
- `ProjectStore.swift` : transaction, validations, copie et suppression ;
- `ScannerDebugView.swift` : premier point d’entrée d’enregistrement ;
- `ProjectSurveyViews.swift` : enregistrement, liste des pièces et réouverture ;
- `ProjectsView.swift` : accès aux relevés du projet ;
- `PlaquistoRoomEditor.swift` : réutilisation de l’éditeur et destination d’enregistrement
  injectée, sans dépendance à RoomPlan ;
- `RoomPlanScanner.swift` : coordinateur multi-pièces lors de l’incrément suivant ;
- `ProjectStoreTests.swift` : persistance et intégrité ;
- `PROJECT_STATE.md` : état réel livré.

## Plan de tests

- enregistrer une pièce dans un nouveau Projet en une transaction ;
- ajouter une seconde pièce au même relevé ;
- conserver les UUID après rechargement ;
- refuser un relevé, une pièce ou un checkpoint incohérent ;
- copier un Projet en réaffectant Projet, pièces, relevés et géométries ;
- supprimer un Projet et ses relevés ;
- abandonner l’écran avant validation sans donnée fantôme ;
- vérifier la lecture des archives antérieures sans clé `surveys` ;
- compiler l’application et contrôler le parcours sur simulateur hors capture.

## Références Apple vérifiées

- `StructureBuilder.capturedStructure(from:)` combine des `CapturedRoom` situés dans
  un espace monde compatible ;
- la compatibilité est obtenue par une `ARSession` continue ou une relocalisation ;
- `RoomCaptureSession.stop(pauseARSession: false)` permet de conserver la session ;
- ces API sont disponibles à partir d’iOS 17, qui est la cible minimale de Plaquisto.

Sources : [StructureBuilder](https://developer.apple.com/documentation/roomplan/structurebuilder),
[capturedStructure(from:)](https://developer.apple.com/documentation/roomplan/structurebuilder/capturedstructure%28from%3A%29),
[RoomCaptureSession](https://developer.apple.com/documentation/roomplan/roomcapturesession).

## Validation de l’incrément 1 — 24 septembre 2026

- Suite iOS : 191 tests réussis, zéro échec. Résultat :
  `/tmp/plaquisto-lidar-survey/Logs/Test/Test-Plaquisto-2026.09.24_22-28-38-+0200.xcresult`.
- Preuve d’indépendance existante `Tests/run-room-model-proof.sh` réussie : deux
  processus distincts, sauvegarde/relecture, UUID, corrections manuelles prioritaires,
  rectangle, porte, fenêtre, surfaces nettes, rampant et pignon.
- Contrôle visuel sur simulateur : pièce synthétique de quatre murs et deux ouvertures,
  enregistrement dans « Test relevé LiDAR », accès Projet → Relevé → Pièce, scène 3D
  conservée ; correction de longueur 4,31 → 4,40 m enregistrée dans le relevé, valeur
  initiale 4,28 m inchangée dans l’archive.
- Les transactions couvrent aussi ancienne archive sans relevés, abandon/échec
  d’écriture sans projet fantôme, copie/suppression, remplacement explicite,
  éditeur périmé, et refus des transformations qui changeraient l’échelle.
- Arrêt complet et relance sur simulateur : même relevé retrouvé, même identifiant
  de mur, correction à 4,40 m persistée.
- Compilations finales iOS et Lab réussies (arm64 et x86_64 simulateur) ; seuls les
  modèles et écrans portables du relevé sont partagés avec Lab, sans capture RoomPlan.
- Tests historiques `ScannerCeilingReconstructionChecks` réussis, notamment la
  régression cuisine, les rampants opposés, contours concaves et murs fragmentés.

Ce premier incrément n’active pas encore la capture continue multi-pièces, la fusion
`StructureBuilder`, l’attribution aux ouvrages ou l’ajout guidé de cloison/porte.
Le prochain incrément réutilisera `ScannerDebugModel`, sa session AR commune,
`RoomPlanAdapter` et la reconstruction de plafond existante. Aucune validation de
capture réelle sur iPhone n’a été effectuée à ce stade.
