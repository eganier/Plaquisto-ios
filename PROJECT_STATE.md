# Plaquisto — état du développement

Mise à jour : 19 septembre 2026. Branche de travail : `codex/tools-lab-improvements`.

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
