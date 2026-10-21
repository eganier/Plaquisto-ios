# Plaquisto — état du développement

## Modélisation manuelle et sélection 3D — 18 octobre 2026

- Onglet « Modéliser » (icône de pièce ouverte), deux entrées « Scanner ma pièce » / « Dessiner ma pièce », vérification locale de compatibilité RoomPlan. Le parcours de calepinage rapide reste un scanner sans création de projet.
- Dessin manuel : contour de sol via l'éditeur existant (ou rectangle de départ), hauteur commune de 250 cm, option hauteurs différentes. Un angle contraint un sommet ; un segment contraint ses deux extrémités. Deux références distinctes donnent la pente minimale ; trois références non colinéaires définissent un plan unique. Les sommets non contraints suivent le plan ; hauteurs incompatibles refusées sans déformer silencieusement les autres mesures. Plafond horizontal ou un seul rampant à la création, 20–2 000 cm sur tout le contour.
- Conversion mm → mètres, murs trapézoïdaux jusqu'au plafond, sol concave conservé, provenance manuelle. Nom du relevé, projet existant ou nouveau (préselection depuis un projet), aperçu 3D et sauvegarde atomique via ProjectStore. Réutilisation du relevé/éditeur commun, des ouvertures, cloisons, poteaux et ouvrages. Pas de fausse localisation de scan. Les plafonds manuels disposent des paramètres nécessaires à leur reconfiguration et à leur découpe ultérieures.
- Retard de sélection : retrait de `tap.require(toFail: reset)` dans SurveySurfaceScene. Le premier toucher sélectionne immédiatement ; le deuxième recentre et restaure la sélection initiale, sans reconstruire la géométrie. L'état de sélection simple du calepinage rapide est également restauré.
- Vérifications : 179 tests réussis (12 modélisation/sélection + 167 régressions relevé), journal `/tmp/plaquisto-manual-model-roof-tests.log`. Recette UI dans le bundle isolé `fr.plaquisto.lab.manualqa` : rectangle, hauteurs par segments à 250/320 cm, sauvegarde dans un nouveau projet, ouverture 3D, sélection d'un mur et double-tap conservant la sélection. Archive relue : un seul projet/relevé, origine manuelle et hauteurs exactes conservées. Ressenti tactile réel à confirmer sur iPhone.
- Illustration d'accueil définitive en attente du modèle que l'utilisateur dessinera dans l'app ; aucune illustration générée intégrée. Aucune installation sur iPhone ni publication Git dans cette intervention.
- Raccord plafond vérifié visuellement après correction : modèle retrouvé après relance, ouverture de « Configurer les plafonds » sans erreur, commandes hauteur/pente et découpe accessibles. Compilation finale Lab réussie (`/tmp/plaquisto-manual-model-qa-final-build.log`).

## Liste de courses, unités et ouvertures — 17 octobre 2026

- Branche `codex/liste-courses-ouvertures`, créée depuis `main` après la publication précédente. Aucun déploiement Admin ni installation iPhone dans cette intervention.
- Quantitatif Lab : suppression des commandes de réservation dans cette vue. Stock disponible orange et déduction/réintégration par fourniture **uniquement dans la liste à acheter**, sans sortie de stock ni réservation. Modifications persistées par sélection d'ouvrages, séparées du calcul source : renommage, quantité manuelle, produit ajouté, regroupement de références de même unité. Ligne source grisée à zéro et valeur initiale visible. Glissement gauche pour réinitialiser une ligne ; réinitialiser un participant annule tout son regroupement. Export des libellés et quantités modifiés, sans lignes à zéro.
- Correction de la double comptabilisation en unités et mètres linéaires des profils d'ouvertures de toiture ; cornières et fourrures concernées comptées en ml seulement. Normalisation des synonymes d'unités ; aucune conversion inventée d'une unité en longueur.
- Option Trappe pour calepinages muraux et plafonds. Les ouvertures rectangulaires ajoutées/déplacées/retirées d'un calepinage mural lié au relevé sont reportées dans le document 3D dans la même transaction ; conservation des autres ouvertures et de la capture brute, recalcul des ouvrages liés. Les contours libres/obliques non représentables sont refusés plutôt qu'agrandis. La synchronisation vers le relevé concerne actuellement les murs, pas les trappes de plafond.
- Modifier le plan : cadrage calculé sur les dimensions après rotation, adapté à l'expansion initiale de la feuille jusqu'au premier geste, puis stable pendant l'édition.
- Cartes Lab : glissement de tout le bloc, vignette comprise, avec Renommer / Dupliquer / Supprimer empilés verticalement. Reconnaissance directionnelle réservant les gestes verticaux au défilement ; compatibilité avec les gestes de pointeur qui ne transmettent que leurs extrémités.
- Tests automatiques : **603 tests réussis** (`/tmp/plaquisto-shopping-tests-final.log`), couvrant les regroupements, annulations, stock inchangé, persistance/relecture, ouvertures sur mur tourné et seconde face de cloison, unités et trappes. Recette UI dans un bundle distinct `fr.plaquisto.lab.shoppingqa`, avec projets synthétiques uniquement : glissement depuis une vignette, ouverture/annulation du renommage, création d'un ouvrage, modification de 17,3 à 20 ml et réinitialisation à 17,3 ml vérifiés. Défilement tactile continu et cadrage initial sur un scan réel restent à valider sur iPhone.

## Relevé unifié et installation — 16 octobre 2026, 23:08

- Relevé : sélecteur 3D / 2D, bouton ouvrages jaunes avec joints visibles, résumé de l'ouvrage touché, cube murs/plafonds et doublages opaques en mode plafond. Configurer les plafonds remplace Exporter DAE dans le pied ; DAE reste dans le menu. Retrait des commandes de réparation et de sélection devenues inutiles.
- Plan 2D : cadrage suivant un mur adapté au portrait, zoom ancré au pincement, double toucher pour recentrer, cotes toujours présentes. Ces transformations restent des transformations d'affichage.
- Calepinages créés dès l'enregistrement des ouvrages liés au scan, y compris grilles de dalles des plafonds modulaires. Reprise des anciens ouvrages sans écraser les plans existants ; le comptage des plaques inclut les plans conservés et nouveaux. Les systèmes sans format de parement exploitable conservent un avertissement plutôt qu'un plan inventé.
- Recouvrement d'un ouvrage existant : aperçu des surfaces concernées et choix « Exclure de la nouvelle sélection », « Conserver la sélection », « Annuler ». Acceptation explicite persistée et validée lors de la relecture/duplication ; l'ancien ouvrage n'est pas supprimé. Détection à l'échelle des surfaces sources, pas d'une intersection polygonale arbitraire.
- Projets Lab : actions au glissement Renommer / Dupliquer / Supprimer sur projets, relevés et ouvrages ; regroupement des ouvrages sous leur relevé avec triangle animé. Ouvrages sans relevé conservés à part.
- Plafonds : sélection multiple et commandes Fusionner (deux zones contiguës) / Masquer / Réafficher. Réglages de hauteur/pente et découpe restent disponibles ; textes explicatifs encombrants retirés.
- Éditeur du plan : Portes avec galandage sans arc, Verrière (allège par défaut 100 cm), Poteau avec côtés A/B, orientation sur un mur, hauteur issue du plafond ou mur proche. Poteaux persistés et exportés en DAE ; cotes latérales des ouvertures déplacées et zone de sélection des portes élargie au débattement.
- Vérification finale : **594 tests réussis, zéro échec**, compilation Lab simulateur et iPhone réussie, signature vérifiée, diff sans erreurs d'espacement. Logs `/tmp/plaquisto-final-all-tests.log`, `/tmp/plaquisto-final-lab-sim.log`, `/tmp/plaquisto-final-lab-device.log`. Avertissement du collecteur de diagnostics simctl après les tests, sans échec de la suite.
- Recette visuelle simulateur : accueil, page projet, glissement de carte et ouverture/annulation du renommage vérifiés. Les gestes multitouch et l'ensemble du parcours sur un scan réel restent à valider au doigt sur iPhone ; les tests automatiques couvrent la géométrie, les nouvelles entités et la persistance.
- Installation réussie sur l'iPhone connecté à 23:08 : `fr.plaquisto.lab`, séquence **4521**, conteneur `9CA7F8CF-8A90-4018-908D-E936F8AA8418`. Mise à jour sans désinstallation ni effacement. Lancement automatique refusé uniquement parce que l'appareil est verrouillé ; ouverture manuelle nécessaire.
- Cette version et les développements accumulés de la branche `codex/ergonomie-lab-simplifiee` sont préparés pour fusion dans `main` et publication GitHub à la demande explicite de l'utilisateur. Aucune publication Admin dans cette opération.

## Relevé, plafond modulaire, gestes et aperçu des ouvrages — 16 octobre 2026

- Installation finalement réussie le 16 octobre à 21:30 après nouvelle demande utilisateur : bundle `fr.plaquisto.lab`, séquence 4504, conteneur d'application `DA433A18-754C-4A91-B1B8-7EA7E02DC174`. Nouvelle compilation installée par-dessus l'existant, sans désinstallation ni effacement de données. Cette réussite remplace le blocage de transfert décrit plus bas.
- Version précédente réinstallée à la demande sur l'iPhone à 11:49 (séquence 4496), puis corrections suivantes développées dans le même arbre de travail, sans commit/push ni publication Admin.
- Plafond modulaire accessible depuis la sélection des plafonds du relevé et depuis Nouvel ouvrage. Conservation des contours/ouvertures réels dans la configuration, saisie de surface verrouillée, création/persistance/synchronisation avec les composants du scan. Calcul indicatif T24 sur grilles centrées, dalles et profilés découpés sur le contour et ses trous, sans inflation liée à l'orientation du scan. Pas de faux calepinage BA13 généré pour ce système. Une géométrie non calculable bloque l'enregistrement et signale un quantitatif incomplet au lieu de publier un rectangle comme résultat réel.
- Trémies/ouvertures du calepinage plafond : orientation initiale parallèle au mur qui cadre la vue, choix d'un autre mur numéroté avec aperçu. Rotation autour du centre ; dimensions mesurées dans les axes propres de l'ouverture, conservation des contours non rectangulaires et des anciennes ouvertures lors de leur réédition. Transformation d'affichage distincte de la géométrie.
- Maquette 3D : glissement à deux doigts réservé à la translation caméra+cible ; un doigt conserve l'orbite et le pincement reste natif. Pivotement à deux doigts toujours interdit. Translation ne réinitialise pas le cadrage lors d'une sélection ou de l'affichage des ouvrages.
- Tracé de cloison : arbitre UIKit du plan exclusif face aux panoramiques d'un parent ; plus de reconnaissance simultanée du tracé avec un scroll extérieur. Défilement progressif dans les 30 % périphériques du canevas via display-link, vitesse plafonnée 150 points/s. Recalcul du pointeur avec le nouvel offset à chaque frame ; arrêt au relâchement, à l'annulation, au deuxième doigt et à la fermeture du plan. Dernier aperçu conservé à la levée du doigt.
- Vue 3D du relevé : boutons Ouvrages / Joints des plaques pour les ouvrages liés au scan. Surfaces finies bleues, sélection orange, épaisseurs des doublages issues des configurations, plafonds abaissés du plénum connu. Rails/montants autoportants sans hauteur de descente stockée : pas d'abaissement inventé. Joints de la dernière peau du calepinage enregistré, sans optimisation/recalcul des quantités. Le scan et l'export DAE restent inchangés ; simulation graphique uniquement, masquable. Pas de calepinage fictif sur les ouvrages sans plan.
- Diagnostic reçu : `/Users/edouard/Downloads/Plaquisto-diagnostic-289B484D-5A9C-4FAE-879B-B849F10748E6.json`. Capture du 16/10 05:23–05:25 UTC : 10 murs en sortie RoomPlan, 0 fusion et 0 fragment retiré, tableau des murs final strictement identique à la géométrie adaptée avant nettoyage. Deux petits pans de 0,308 et 0,254 m persistent ; aucune représentation volumique complète des poteaux. Seul objet natif : « stairs », confiance faible. Maillage complémentaire désactivé (0 ancre/face) ; 95 images locales avec profondeur indiquées mais absentes de ce JSON. Échec de l'archive brute natif signalé (« format incorrect »), résultat final RoomPlan présent. Reconnaissance complète des poteaux NON corrigée ; ne pas inventer de poteaux depuis ces seuls fragments/photo. Aucune image personnelle téléversée.
- Vérifications : 585 tests après plafond modulaire/ouvertures, puis **588 tests réussis** après gestes/aperçu (`/tmp/plaquisto-scan-gestures-preview-tests.log`). Régressions : contours concaves et trou, invariance au yaw, persistance/sources, ouverture tournée sans déplacement, translation caméra+cible sans rotation, bande périphérique 30 %, épaisseur/abaissement/joints et retour au scan sans mutation ni recadrage. Compilation/signature Lab iPhone réussie (`/tmp/plaquisto-lab-scan-gestures-preview-device.log`). `git diff --check` OK. Recette tactile réelle encore à effectuer sur l'iPhone.
- Déploiement de cette nouvelle compilation : trois tentatives échouées, connexion/tunnel CoreDevice interrompu par le téléphone (« Connection reset by peer », erreurs 4000 / 4). Appareil toujours déclaré paired/available ; lecture des détails réussie entre les deuxième/troisième essais, transport localNetwork, tunnel TCP connected, mais transfert d'app encore interrompu. Demander connexion USB et iPhone déverrouillé. Ne pas annoncer cette compilation installée tant qu'un nouvel `devicectl install app` n'a pas réussi. Artefact prêt : `/tmp/PlaquistoPricesDevice/Build/Products/Debug-iphoneos/Plaquisto Lab.app`. La réinstallation de 11:49 concernait la version précédente.

## Stock rapide, rails et épaisseurs de cloisons — 15 octobre 2026 (soir)

- Version précédente, incluant la duplication des relevés, installée sur l'iPhone d'Edouard à 23:32 (bundle `fr.plaquisto.lab`, séquence 4408), sans désinstallation ni effacement du stock/projets.
- Cloison de distribution : première épaisseur proposée = référence compatible la plus proche de la largeur de l'ossature, et non première épaisseur de la liste. R48 → laine phonique 45 mm, R70 → 70 mm. Respect des limites de dépassement publiées par isolant, jamais une épaisseur inventée ; nouvelle suggestion lors d'un changement d'ossature ou d'isolant. Une sélection manuelle compatible enregistrée n'est pas remplacée à la simple réouverture.
- Stock : accueil présentant toutes les familles, même vides ; filtrage famille/sous-catégorie sur l'ensemble du catalogue, avec quantité zéro pour une référence non encore entrée. Boutons Entrée / Sortie de 48 points dans chaque carte. Chaque nouvelle action globale Entrée repart des familles. Inventaire permet aussi de sélectionner une référence encore absente du stock.
- Aucun rattachement chantier lors d'une entrée ou d'un inventaire, y compris au niveau du journal du moteur. Le choix de chantier reste disponible à la sortie pour consommer sa réservation. Réservation toujours distincte d'une entrée physique.
- Rails manquants : extraction des profils depuis les systèmes publiés dans l'Admin (tableaux frame et studs), en plus des quantity_item. Catalogue courant : R36, R48, R62, R70, R90, R100, R150, avec montants associés. Pas de création de prix ni de pseudo-identifiant tarifaire pour ces références dérivées. Les lignes déjà référencées gardent leur identité tarifaire.
- Bande papier : harmonisation des alias explicites « Bande à joint · papier » / « Bande à joint papier » avec « Bande à joint ». Chargement des anciens stocks remappe réservations et additionne leurs quantités sans écriture immédiate ni perte d'historique. Formats de plaques, fonctions, épaisseurs, lambdas, vis de longueur différente et sections de profils restent distincts.
- Scénario de régression : création et relecture d'un projet temporaire de six ouvrages (cloisons R48/R70, doublage montants, doublage fourrures hydro, plafond rails/montants, parement collé), vérification des sommes et de l'absence de doubles comptes même si un ouvrage est sélectionné deux fois. Aucun projet de test ajouté aux données personnelles du téléphone.
- Vérification finale : **580 tests réussis**, zéro échec (`/tmp/plaquisto-stock-insulation-all-tests.log`), compilation/signature iPhone Lab réussie (`/tmp/plaquisto-lab-stock-quick-device-build-final.log`), `git diff --check` OK. Le premier passage complet a révélé 10 assertions obsolètes dans quatre tests Opening/aliases du fichier PaintingTests ; elles attendaient les anciens renforts d'embrasure. Mises en accord avec la simplification à deux profils latéraux déjà demandée, sans modifier le moteur pour contourner les tests. Tests toiture conservés. Recette tactile du nouveau parcours Stock non effectuée ; tests moteur/persistance et compilation réalisés.
- Version finale installée sur l'iPhone à 23:38, séquence 4416, conteneur `DB93AC3E-DE0C-42A7-826C-8A7E30DD0080`, bundle `fr.plaquisto.lab`. Lancement automatique refusé uniquement parce que l'iPhone était verrouillé ; installation réussie, ouverture manuelle nécessaire. Aucun effacement de données, commit, push ou publication Admin.

## Copies de relevés, portes et partage sélectif — 15 octobre 2026

- Menu ⋯ d'un relevé enregistré : « Dupliquer le relevé » crée et ouvre une copie dans le même projet, nommée « … – copie », puis numérotée si nécessaire. Géométrie, réglages, ouvertures, masquages, transformations et date de capture conservés. Nouveaux identifiants de relevé, checkpoints et éléments géométriques ; aucun ouvrage ni quantitatif dupliqué ou réaffecté. Historique de division remappé pour permettre la réunion des plafonds après suppression d'une cloison dans la copie. Sauvegarde atomique.
- Portes : correction du poussant droit/gauche, côté d'ouverture déterminé par le côté du mur où passe le doigt, avec zone morte et maintien de l'aimantage. Bouton pour inverser le côté après pose. Fin de geste conservant la prévisualisation. Orientation transmise aux ouvertures de calepinage et synchronisée sans changer leur surface.
- Les portes issues du plan apparaissent dans la gestion des ouvertures de l'ouvrage. Elles sont déjà incluses dans sa géométrie nette : aucun ouvrage d'ouverture supplémentaire ni seconde déduction. Tests couvrant deux faces de cloison et isolant après déduction unique.
- Quantitatif : sélection des fournitures, tout sélectionner/désélectionner, puis boutons « Partager la liste » (fichier texte via partage iOS) et « Copier le texte ». Texte limité au projet/client/adresse et aux fournitures sélectionnées en puces, sans prix, stocks, notes privées ni explications. Quantités nulles exclues.
- Lab : disponibilité orange sous chaque fourniture, bouton Réserver/Modifier ciblé sur cette référence. Réservation réussie active l'affichage des quantités à acheter ; pas de sortie physique du stock. Réservations des autres références conservées. Le sélecteur global de déduction reste disponible.
- Vérifications : compilation Lab simulateur réussie (`/tmp/plaquisto-survey-copy-export-lab-build.log`), 476 tests ciblés réussis sans échec (`/tmp/plaquisto-survey-copy-export-tests-final.log`), `git diff --check` OK. Le premier passage avait un échec dans le nouveau test de relecture dû aux fractions de seconde supprimées par l'encodage ISO-8601 existant ; comparaison des documents encodés corrigée, puis suite complète ciblée repassée. Avertissement post-test simctl du collecteur Xcode, TEST SUCCEEDED et sortie 0. Recette tactile et feuille de partage iPhone non effectuées. Aucune installation iPhone, publication Admin ou opération Git effectuée.

## Suppression d'une cloison et réunion des plafonds — 15 octobre 2026

- Chaque division proposée à la fin du tracé mémorise les identifiants des segments de cloison responsables dans `CeilingSplitOrigin.partitionWallIDs`. Découpes manuelles explicitement marquées sans cloison ; anciennes archives compatibles (`nil`).
- Supprimer un segment du séparateur réunit automatiquement les deux zones issues de cette opération. Union réelle des contours, sans rectangle englobant, sans aplatir les rampants et sans supprimer les pans/sources utilisés par les ouvrages et calepinages. Les composants d'ouvrage restent conservés avec leurs plans, au sein d'un seul plafond regroupé.
- Anciennes divisions : rapprochement conservateur par opération et frontière commune entièrement portée par les cloisons dessinées, dont la cloison supprimée. Pas de fusion d'une zone indépendante par simple proximité. Si les deux zones ont été redécoupées depuis, les découpes ultérieures sont conservées : pas de réunion automatique dans ce cas. Message de suppression mis à jour ; annulation de l'éditeur conserve le document antérieur complet.
- Retrait de la demande « Renseigner les doublages avant de tracer ? » : Tracer une cloison démarre directement. Les doublages existants continuent à guider les positions et cotes des faces finies.
- Compilation Lab simulateur réussie (`/tmp/plaquisto-divider-merge-build.log`). 267 tests ciblés réussis (`/tmp/plaquisto-divider-merge-tests.log`), dont suppression/relecture, cas legacy, cloison en L, préservation des découpes manuelles et des calepinages rattachés. Pas de recette tactile ni installation iPhone pour ces deux changements ; pas de commit/push.

## Installation des corrections cloisons — 15 octobre 2026, 19:21

- Compilation iPhone Lab réussie, signature vérifiée (`/tmp/plaquisto-lab-partitions-device-build.log`), équipe U6X2KSN84X.
- Mise à jour `fr.plaquisto.lab` installée sur l'iPhone connecté, séquence 4400, conteneur d'application 59E055A5-6E15-4C5F-9106-F7CF28CC1CB6. Aucun effacement/désinstallation, application standard inchangée.
- Inclut les corrections décrites ci-dessous (cloisons, quantitatif BA13, scan depuis projet, simplification des ossatures d'ouvertures).
- Lancement automatique refusé uniquement parce que l'iPhone était verrouillé (Locked). Ouverture manuelle et recette au doigt restent à effectuer.

## Cloisons, ouvertures et scan depuis un projet — 15 octobre 2026

- Tracé tactile des cloisons : la fin du geste conserve le dernier point prévisualisé, sans recalcul depuis la position de relâchement. Hauteur adaptée aux plafonds acceptés traversés, avec profil rampant ; repli sur la hauteur du mur de départ en l'absence de plafond.
- Jonctions des nouvelles cloisons : découpage des murs supports en surfaces distinctes, filiation explicite et conservation des ouvertures, composants d'ouvrages et calepinages. Un découpage traversant une ouverture existante est rejeté. Les ouvrages existants restent regroupés avec leurs composants, ils ne sont pas dupliqués automatiquement.
- Portes du plan : choix poussant droit/gauche, persistance rétrocompatible et représentation du battant.
- Quantitatif cloisons : correction des surfaces de parement restées à une ancienne dimension, redimensionnement proportionnel des choix mixtes lors d'un changement de surface et garde sur l'enregistrement d'un formulaire incomplet. Le cas synthétique reproduisant 27,9 m² et deux faces restées à 6 m² donne 58,59 m² de BA13, réserve existante de 5 % incluse. Réparation ciblée à la relecture des ouvrages ; autres fournitures inchangées.
- BA13 : harmonisation des libellés « Parement · BA13 Standard » et « BA13 », sans fusion de formats ou variantes techniques distincts. Résolution des tarifs adaptée à cette canonicalisation.
- Lab : bouton Scanner dans ce projet, sauvegarde du relevé dans le projet cible à la fin de la capture, sans choix de rattachement supplémentaire.
- Ouvertures murales : uniquement deux profils latéraux toute hauteur, axes à 5 cm à l'extérieur des bords. Suppression des traverses et petits renforts propres aux ouvertures dans le moteur graphique et le calcul, pour cloisons et doublages fourrures/montants. Minimum d'ossature des anciens calepinages automatiques recalculé, profils latéraux non doublés ; ossature générale et ses règles de réserve conservées.
- Vérification : compilation Lab simulateur réussie (`/tmp/plaquisto-partition-build-final.log`), 447 tests ciblés réussis sans échec (`/tmp/plaquisto-partition-tests-final.log`), `git diff --check` OK. Le journal de test contient un avertissement post-exécution sur `simctl`, puis TEST SUCCEEDED et code de sortie 0. Recette au doigt, capture LiDAR et partage sur téléphone non effectués pour cette version.
- Diagnostic du quantitatif lu depuis une copie temporaire de l'archive iPhone, sans écriture sur l'appareil. Aucun relevé privé ajouté au dépôt. Pas d'installation de ces nouvelles corrections, ni commit/push/publication Admin.
- L'affichage futur des ouvrages en surépaisseur sur la maquette 3D reste une proposition discutée : non implémenté, conformément à la demande.

## Installation Lab — 15 octobre 2026

- Dernières sources compilées pour l'iPhone avec l'équipe U6X2KSN84X ; compilation et signature vérifiées (`/tmp/plaquisto-lab-stock-device-build.log`).
- Mise à jour de `fr.plaquisto.lab` installée sur l'iPhone d'Edouard (6A65A405-C70C-5FEF-88B6-B110C4E648B8), séquence 4392. Inclut le Stock et sa date de dernière mise à jour.
- Installation par-dessus l'existant, sans désinstallation ni effacement de données. Plaquisto standard inchangé.
- Lancement automatique refusé par iOS (Security : signature/droits ou profil non approuvé). Signature locale valide ; nouveau profil créé le 15 octobre, valable jusqu'au 22 octobre. Autorisation du profil sur l'iPhone à vérifier par l'utilisateur ; lancement non confirmé.

## Date de mise à jour du stock — 14 octobre 2026

- Accueil Stock : date et heure françaises de la dernière opération enregistrée, sous le sélecteur Stock / Réservations. Stock vierge : « Aucun mouvement enregistré ». Historique toujours invisible.
- Date issue du dernier événement persistant, conservée après relance ; réservations, annulations et annulation de dernière opération incluses. Une réservation inchangée ou une opération rejetée ne modifie pas cette date. Rafraîchir les tarifs Admin ne la modifie pas.
- Compilation Lab simulateur réussie (`/tmp/plaquisto-stock-date-build.log`) et 19 StockTests réussis (`/tmp/plaquisto-stock-date-tests.log`), dont persistance de la date et opérations sans changement. Pas d'installation iPhone.

## Stock personnel Lab — 14 octobre 2026

- Quatrième onglet Stock à droite de Projets / Scanner / Outils, uniquement dans la navigation Lab. Un seul lieu « Local ». Accueil par familles présentes, recherche transversale, filtres de sous-catégorie, listes par tranches de 30. Actions Entrée / Sortie / Inventaire fixées en bas (64 points), validations de 56 points.
- Références tirées des données Admin publiées (y compris familles imbriquées), complétées par les fournitures des projets. Classement de présentation local par famille/sous-catégorie ; aucune publication ni modification Admin dans cette étape. Produit personnel possible si absent. Appariement strict nom canonique + unité ; aucun rapprochement approximatif de modèles/dimensions/lambdas. Identité tarifaire Admin conservée si non ambiguë.
- Quantités stockées en unités de calcul ; saisie directe ou conditionnement avec contenu renseigné, raccourcis ¼ / ½ / ¾ et nombre libre. Plaques du catalogue : conversion surface déduite des dimensions explicites. Aucun contenu de boîte ni longueur de barre supposé. Affichage du nombre de conditionnements avec l'équivalent de base. Quantités éditables non arrondies en interne.
- Stock physique distinct du disponible. Réservations rattachées au projet depuis le quantitatif, avec aperçu/quantités modifiables ; réitérer remplace les réservations pour ces références, sans accumulation ni suppression des autres références. Onglet Réservations regroupé par chantier, action « Annuler la réservation » confirmée. Sortie affectée au chantier consomme sa réservation ; les autres chantiers sont protégés. Inventaire déficitaire conserve les réservations et affiche une alerte.
- Quantitatif Lab : option Déduire le stock disponible, reste à acheter et besoin total, mention orange du stock. Les réservations propres au projet sont utilisables, celles des autres exclues. Quantitatif/formulaires/calepinages d'origine inchangés. Export demande avec/sans stock puis ouvre le partage iOS ; coût calculé sur les achats restants si déduction active.
- Valeur estimée HT globale / famille / sélection, au tarif validé Admin avec éco-contribution ; stock réservé inclus. Prix manquants, expirés ou ambigus exclus et signalés (estimation partielle), jamais assimilés à zéro.
- Historique persistant enregistré mais **invisible**, sur demande de l'utilisateur. Les événements gardent date, produit, avant/après physique et réservé, chantier éventuel, acteur local « Moi ». Annuler la dernière opération via les trois points ajoute une trace compensatrice. Stock local mono-utilisateur, pas de synchronisation multi-comptes.
- Persistance `Application Support/Plaquisto/stock-v1.json`, isolée par sandbox Lab. Écritures atomiques avant publication UI, archive illisible conservée et écriture bloquée. Réservations multi-lignes validées avant transaction. Aucune désinstallation ni effacement de données.
- 343 tests réussis, dont 18 StockTests (`/tmp/plaquisto-stock-final-tests.log`) : réservation/annulation/idempotence, sorties réservées, inventaire déficitaire, atomicité, sauvegarde/relecture, archive illisible et échec disque, annulation historisée, unités/plaques, tarifs, export avec/sans stock, fractions, précision, cibles tactiles.
- Compilation finale Lab simulateur réussie (`/tmp/plaquisto-stock-final-build.log`), incluant les dernières retouches de titre de valorisation et fermeture du clavier de conditionnement. `git diff --check` OK.
- Recette native simulateur : onglet Stock, familles, entrée d'une demi-boîte de 1 000 vis → 500 unités avec valeur HT, entrée 50 ml de bande à joint, réservation 17,3 ml au projet de test « Vérification bandes », activation de la déduction et coût restant. Données de test uniquement dans le simulateur. Défilements pilotés intermittents ; fin de vérification visuelle/partage interrompue par le verrouillage du Mac. Export texte couvert par tests ; feuille de partage non vérifiée interactivement jusqu'au bout.
- Non installé sur l'iPhone ; aucune publication, aucun commit/push. Modifications précédentes conservées.

## Calepinage Lab — plan agrandi et commandes fixes, 13 octobre 2026, 23:22

- Zone d'informations ramenée de 154 à 64 points (mise à l'échelle avec le texte). Actions dans une bande séparée de 44 points juste au-dessus du sélecteur d'outil : environ 42 points gagnés pour le plan à taille de texte standard. Les deux zones restent réservées pour chaque outil, y compris en plein écran ; informations longues toujours défilables.
- Optimiser / Caler : colonnes fixes 34 % / 66 %, hauteur et position inchangées entre Plaques et Ossature. Boutons légèrement réduits, cibles tactiles de 44 points minimum à taille standard. Alertes dans les informations, sans déplacer les actions.
- Icônes Lab redessinées en contours fins : règle diagonale, plaque simple arrondie, trois traits verticaux, carré dans une plaque, éclair sans remplissage. États gris/bleu et cycle des cotes orange inchangés.
- Outil Plan : accès direct à Modifier le contour et l'échelle, Afficher les numéros de plaques, Afficher les angles. Ces entrées sont retirées des trois points et du menu contextuel des cotes en Lab. Présentation standard, géométrie, calculs et rendu du dessin inchangés.
- Compilation PlaquistoLab simulateur réussie (`/tmp/plaquisto-lab-compact-dock-build.log`). 325 tests réussis, zéro échec (`/tmp/plaquisto-lab-compact-dock-tests.log`), dont deux nouveaux tests de dimensions stables et de rendu des contrôles. Rendu SwiftUI vérifié visuellement (`/tmp/plaquisto-lab-compact-controls.png`). Pas de recette interactive complète au doigt.
- Non installé sur l'iPhone à ce stade. Aucun commit/push ; changements antérieurs conservés.

## Installation Lab — 13 octobre 2026, 23:06

- Compilation iPhone signée réussie (`/tmp/plaquisto-thumb-device-build.log`) et signature vérifiée par `codesign --verify --deep --strict`.
- Mise à jour de `fr.plaquisto.lab` installée sur l'iPhone d'Edouard, séquence 4260, conteneur `6745ED21-A880-4AC0-9412-DF2CF16FE77C`.
- Inclut la nouvelle barre de déplacement du calepinage, les réglages/cotes/zoom décrits ci-dessous et les retours de recette précédents. Installation par-dessus l'existant, sans désinstallation ni effacement des données. App Plaquisto standard inchangée.
- À tester : calepinage → outils du bas ; cotes en masquant une catégorie ; pincement hors centre ; Ossature → réglages des plafonds sur fourrures → enregistrer et vérifier le quantitatif.

## Calepinage Lab — outils de déplacement, 13 octobre 2026

- Intégration de la direction validée « outils sous le pouce » : une seule icône à quatre flèches, puis Plan / Plaques / Ossature / Ouvertures / Électricité. La sélection choisit l'élément déplacé, pas les éléments affichés. Aucun tutoriel ni indication de première utilisation.
- Affichage directement accessible en haut : éléments gris OFF / bleus ON ; bouton Cotes orange, un seul soulignement orange sous la catégorie cotée. Cycle plaques → ossature → ouvertures → électricité → OFF en sautant les catégories masquées. Masquer la catégorie cotée avance à la suivante visible, ou coupe les cotes.
- Rendu « lecture précise » conservé : profils à l'échelle, traits et teintes alternées inchangés ; Plan montre plaques/ossature nettes, transition de netteté de 0,5 s conservée. Ouverture représentée par un carré dans une plaque, électricité par un éclair. Numéros toujours masqués par défaut, accessibles dans les options et le menu contextuel de Cotes.
- Informations/actions au-dessus de la barre de déplacement dans une zone de hauteur réservée indépendante de l'outil, également en plein écran. Le contenu long reste défilable dans cette zone sans déplacer/redimensionner le canevas. Parement sans mention alignée/quinconce ; résumé ossature limité à l'entraxe. Liste des découpes et recentrage retirés du menu supérieur Lab (le recentrage reste accessible par appui long sur le bouton plein écran).
- Zoom ancré au point initial de pincement, en tenant compte du panoramique, de la rotation et de la vue du dessous. La même transformation est conservée au relâchement ; pas de recalage différent à la fin du geste.
- Réglages simplifiés uniquement pour les plafonds sur fourrures Lab : entraxe, cornière périphérique OU fourrures fixes à 10 cm des bords, entraxe des suspentes (120 cm par défaut, réduction par pas de 10 cm jusqu'à 20 cm). Les autres ouvrages gardent leurs réglages existants. Pas de modification des références Admin.
- Les choix de périphérie et d'espacement sont des paramètres persistés du calepinage. Les anciens plans continuent de suivre le formulaire à défaut de choix explicite. La reprise du quantitatif utilise les paramètres de chaque sous-partie, conserve le prorata des parties non dessinées et recalcule tous les composants des ensembles de suspension ; les portées/entraxe des plafonds rails-montants restent issus de leur formulaire.
- 323 tests réussis (118 ProjectStoreTests, 28 PaintingTests, 177 SheetLayoutEngineTests), dont 5 nouveaux tests : 16 combinaisons de visibilité, masquage de la catégorie cotée, ancrage du zoom avec rotation/miroir, persistance/rétrocompatibilité des supports, impact des suspentes sur plusieurs fournitures. Journal `/tmp/plaquisto-thumb-tests.log`.
- Compilation finale PlaquistoLab simulateur réussie : `/tmp/plaquisto-thumb-lab-build-final.log`. Aucun commit, push ou changement de branche dans cette étape ; modifications antérieures conservées.
- Recette native interactive non effectuée : accès au simulateur toujours bloqué par `timeoutReached (-10005)`. À tester au doigt : pincement hors centre, changement d'outil sans saut du dessin, réglages/sauvegarde/réouverture. Non installé sur l'iPhone à ce stade.

## Retours de recette ergonomie — 13 octobre 2026, après installation 4252

- Page ouvrage Lab : configuration affichée directement au-dessus du quantitatif, avec les ouvertures du plan et celles rattachées (type/nom, dimensions). Suppression de « Détails techniques ».
- Affichage des parements dans les quantitatifs et exports partagés : conversion en m² des quantités de plaques dont le libellé fournit le format mm/cm/m ; regroupement avec les lignes m² de même référence. Comptages internes, prix et nombre de plaques en haut du calepinage inchangés. Aucun format inventé pour un ancien libellé sans dimensions.
- Suppression de la pseudo-fourniture « Surface d’isolant à déduire ». Déduction automatique, au prorata et avec la réserve d'origine, sur chaque couche d'isolant du seul ouvrage parent des ouvertures rattachées. Aucune déduction sur un ouvrage sans lien ; exclusion des IDs d'ouvertures déjà représentées par le contour net, et dédoublonnage des sélections/IDs. Ne rapproche pas arbitrairement deux ouvertures distinctes sur la seule base de leurs dimensions.
- 318 tests réussis : ProjectStoreTests, PaintingTests, SheetLayoutEngineTests. Journal `/tmp/plaquisto-feedback-ergonomie-tests.log`. Compilation Lab simulateur réussie (`/tmp/plaquisto-feedback-lab-build.log`). Pas encore installé sur iPhone.
- Calepinage : aucune nouvelle interface imposée. Trois propositions interactives livrées (double barre, palette latérale, outils sous le pouce), avec icônes de visibilité accessibles et représentation nette plaques/ossatures en mode Parcourir. Le choix du design et son intégration native restent à valider. Bouton Annuler natif conservé.

## Installation ergonomie Lab — 13 octobre 2026, 21:28

- Build iPhone signé réussi et signature vérifiée : `/tmp/plaquisto-ergonomie-lab-device.log`.
- Mise à jour installée sur l'iPhone d'Edouard, bundle `fr.plaquisto.lab`, séquence 4252, conteneur d'application `BC42C48C-1A5D-4896-A57D-792AB009E15C`.
- Inclut les quatre simplifications décrites ci-dessous. Installation par-dessus l'existant, sans désinstallation ni effacement des données ; application Plaquisto de production inchangée. Les essais tactiles sont à effectuer par l'utilisateur.
- Lancement automatique refusé uniquement parce que l'iPhone est verrouillé ; ouvrir Plaquisto Lab manuellement après déverrouillage. L'installation est confirmée indépendamment du lancement.

## Première simplification ergonomique Lab — 13 octobre 2026

- Branche `codex/ergonomie-lab-simplifiee`, créée après intégration et publication du socle `41e49e5` sur `main`. Les changements ci-dessous restent sur cette branche, sans modifier les moteurs de calcul ni les données Admin.
- Configuration d'un ouvrage Lab : page de raccourcis vers les rubriques des neuf formulaires guidés (plafonds, doublages, cloisons). Une rubrique ouvre le formulaire existant directement au bon endroit ; son enregistrement revient à la page de configuration. Le formulaire complet reste accessible, notamment pour peinture, bandes et ouvertures. Les étapes de suspension sont masquées pour un plafond autoportant.
- Calepinage Lab : menu « Affichage » regroupant visibilité/cotes des plaques, ossatures, ouvertures et électricité, numéros, angles et recentrage. Les modes Vue/Plaques/Ossatures/Ouvertures/Électricité restent distincts. Présentation standard conservée.
- Bouton Annuler directement sur le dessin Lab, également en plein écran ; désactivé pendant gestes et calculs. Utilise l'historique existant, sans nouvelle logique de géométrie.
- Quantitatif Lab : ouverture directe sur tous les ouvrages visibles du projet. Filtre facultatif avec Tout/Aucun, Appliquer et Annuler ; la liste partagée est recréée lorsque la sélection change.
- Compilation simulateur PlaquistoLab réussie (`/tmp/plaquisto-ergonomie-lab-build.log`). 288 tests réussis, aucun échec : 116 ProjectStoreTests et 172 SheetLayoutEngineTests (`/tmp/plaquisto-ergonomie-lab-tests.log`), dont trois nouveaux tests de raccourcis/navigation optionnelle/absence de réinitialisation au retour. Vérification native interactive indisponible : le contrôle du simulateur retourne `timeoutReached (-10005)`. Non installé sur iPhone.
- Parcours de recette : projet → ouvrage → Modifier la configuration → Isolation → Enregistrer ; projet → Quantitatif → Filtrer → quelques ouvrages → Appliquer (puis vérifier Annuler) ; calepinage → Affichage → cotes/numéros → déplacer une trame → Annuler ; répéter en plein écran sans perdre zoom/rotation.

## Base avant simplification ergonomique — 13 octobre 2026

- État installé du 12 octobre sauvegardé avant la nouvelle passe ergonomique : cotes live, cadrage, rangées électriques, montants fixes, parement collé commun, numéros facultatifs et retrait des fourrures voisines des fenêtres.
- Vérification avant intégration : 285 tests ProjectStoreTests/SheetLayoutEngineTests réussis, aucun échec (`/tmp/plaquisto-pre-ergonomie-merge-tests.log`).
- L’audit des sous-agents du 13 octobre n’a modifié aucun code. Prochaine passe Lab prévue sur une branche distincte : modification ciblée de configuration, distinction affichage/édition, quantitatif direct avec filtre, accès direct à Annuler.

## Installation iPhone — 12 octobre 2026, 23:22

- Dernier état local compilé et signé en PlaquistoLab (`/tmp/plaquisto-window-neighbors-device.log`, BUILD SUCCEEDED), signature vérifiée.
- Installation physique confirmée sur l’iPhone d’Edouard : `fr.plaquisto.lab`, séquence 4204, conteneur `810145A9-3A32-4596-8C21-B46CE8B90D48`. Mise à jour sans désinstallation ni effacement des données ; app de production inchangée. Aucun lancement automatique revendiqué.
- Inclut numéros de plaques masqués par défaut/menu Vue, retrait des fourrures voisines des fenêtres, ainsi que les modifications locales précédentes de cadrage, cotes en mouvement, montants fixes, parements collés et rangées électriques.

## Fourrures voisines des fenêtres — 12 octobre 2026

- Après confirmation du dessin barré : dans les doublages sur fourrures, retire les segments de trame régulière à l’extérieur et à 100 mm au plus des renforts latéraux fixes des fenêtres. Cadre à 50 mm, traverses, petits bouts intérieurs et profils périphériques conservés ; portes et rails/montants inchangés.
- Soustraction limitée à la hauteur réellement couverte par le renfort fixe pour préserver les éventuels prolongements sous rampant. Appliquée dans le moteur commun (affichage, déplacements, calculs), avant décompte des appuis ; contacts des lignes retirées filtrés. Les quantitatifs calculés à partir du calepinage utilisent ces lignes corrigées, sans prétendre réécrire les anciennes estimations enregistrées.
- 172 tests SheetLayoutEngineTests réussis dont trois nouveaux cas (deux voisins extérieurs et longueurs/appuis, limites et hauteur non couverte, portes/montants inchangés). Journal `/tmp/plaquisto-window-neighbors-tests.log`. Compilation simulateur réussie ; pas encore installé sur iPhone.

## Numéros de plaques facultatifs — 12 octobre 2026

- Menu Vue du calepinage : « Afficher les numéros de plaques », désactivé par défaut à l’ouverture d’une surface. Réglage d’affichage commun aux murs/plafonds, conservé lors des changements de mode et du passage en plein écran ; aucune modification de la géométrie ni des quantitatifs.
- Masque les numéros intérieurs et les repères déportés des petites découpes, indépendamment des cotes et des angles. La liste des découpes conserve ses identifiants.
- Compilation simulateur et deux tests ciblés de visibilité réussis (`/tmp/plaquisto-sheet-number-visibility-tests.log`). Non installé sur iPhone à ce stade.

## Cadrage haut, parement collé et édition électrique — 12 octobre 2026

- Calepinages murs/plafonds : cadrage initial dans la partie haute du canvas avec une zone de fit dimensionnée pour l'édition. Échelle de fit conservée au changement de mode et compensation du centre quand les commandes réduisent le canvas. Le recadrage explicite applique la même présentation ; zoom, rotation et déplacements manuels ne sont pas réinitialisés au changement d'onglet.
- Parement collé : le catalogue Admin publié fournit déjà les références communes (schéma 2), mais le client limitait encore les familles à BA6/BA13 et lisait les anciens formats génériques. Le formulaire utilise maintenant les familles compatibles et les dimensions de chaque produit, conserve l'identifiant et le libellé complet fonction/format dans le quantitatif. Les formats historiques restent accessibles uniquement pour leur ouvrage enregistré. Aucun changement de coefficient, aucune publication Admin nécessaire.
- Électricité sur murs : rangées de hauteur indépendantes des points, ajout individuel au curseur déporté de 64 points, aimantage aux rangées et cotes live ; toucher un point ouvre la saisie précise depuis la gauche/droite. Enregistrement des rangées et compatibilité des anciens plans vérifiés par tests.
- Textes de consigne sous le dessin retirés dans les cinq modes, confirmations ordinaires d'optimisation masquées (erreurs conservées). Boutons Optimiser/Caler agrandis, hauteur minimale 52 points.
- Diagnostic distinct : les formulaires de plafonds issus du scan conservent la surface nette et les contours dans les composants, mais les dimensions de formulaire sont synthétisées par racine carrée de la surface. Cette partie n'a pas été modifiée dans ce lot.
- Build iPhone signé réussi : `/tmp/plaquisto-upper-framing-catalogue-device.log`. 281/281 tests réussis (SheetLayoutEngineTests et ProjectStoreTests), résultat confirmé par xcresult : `/tmp/plaquisto-upper-framing-catalogue-tests.log`. Nouveaux cas cadrage haut/rotation/paysage/stabilité entre modes, catalogue commun/formats spécifiques/compatibilité/anciens formats, en plus des rangées et montants fixes. Contrôle gestuel natif non réalisé : le contrôle du simulateur ne répond pas. Pas encore installé ni poussé.

## Cotes pendant les glissements et montants fixes des doublages — 12 octobre 2026

- Les cotes de plaques utilisent les contours réellement découpés pendant le geste, sans lancer l'optimiseur ni le placement des chutes. Le calcul léger partage la même intersection que le calcul définitif, avec ouvertures et contours de pose. L'aperçu reste actif après le relâchement jusqu'au résultat à jour : pas de retour temporaire aux anciennes cotes.
- Un glissement de caméra ou d'ossature ne masque plus les plaques/cotes existantes ; les longueurs d'ossatures continuent à provenir de leur géométrie courante.
- Doublages rails-montants : montants fixes à 100 mm de chaque extrémité (correction demandée par l'utilisateur ; fourrures conservées à 120 mm), suivant pente et ouvertures, fusion géométrique des superpositions avec la trame et les renforts. Les retours de moins de 200 mm reçoivent un seul montant centré. Réglage optionnel persistant, appliqué également à l'ouverture des anciens plans liés à un doublage. Cloisons et plafonds exclus.
- 160/160 tests SheetLayoutEngineTests réussis, y compris les nouveaux cas découpe live/définitive, ouverture, rampant, superposition, retrait fixe, compatibilité et non-régression cloisons. Journal final : `/tmp/plaquisto-live-dimensions-tests-final.log`.
- Compilation iPhone signée Plaquisto Lab réussie : `/tmp/plaquisto-live-dimensions-device.log` ; application dans `/tmp/PlaquistoPricesDevice/Build/Products/Debug-iphoneos/Plaquisto Lab.app`.
- Changements locaux sur `codex/calepinage-lecture-precise`, pas encore installés sur iPhone ni poussés.

## Calepinage « Lecture précise » — 12 octobre 2026

- Avant modification : état existant sauvegardé au commit `cecdcab` et poussé sur `origin/codex/survey-layout-refinements`. Nouvelle branche `codex/calepinage-lecture-precise` créée ensuite ; aucun merge sur main.
- Rendu partagé du calepinage mur/plafond (donc cloisons et doublages inclus) : profils rectangulaires de 50 mm à l’échelle, traverses horizontales de fixation derrière les verticales, teintes grises alternées, même couleur/épaisseur de trait pour joints et contour. Repères, cotes et ouvertures restent nets. Géométrie et quantitatifs non modifiés.
- Transition explicite Canvas via un scalaire animatable : flou léger vers netteté en mode Ossatures sur 0,5 s, sans animation des données ou du zoom ; respect de Réduire les animations. Même style pendant le déplacement et dans les aperçus des réglages d’ossature.
- Icônes : menu Vue (angles/recentrage conservés), ossature III sans cadre, ouverture carré dans carré, électricité inchangée.
- Les quatre raccourcis inférieurs sont remplacés par un résumé du mode actif, touchable pour ouvrir les réglages existants : parement/format/bords/pose, entraxe/longueur, ouvertures/dimensions et menu d’édition, éclairage/prises/diamètre/orientation. Pas de carte supplémentaire en mode Vue ; actions d’optimisation toujours présentes en plein écran.
- Contrôle natif dans le simulateur : rendu plafond, changement des quatre modes, affichage des résumés et accès aux réglages d’ossature vérifiés, sans enregistrer de modification sur le plan de test.
- Régression : deux passes de 156 tests SheetLayoutEngineTests réussies, dont 3 nouveaux tests largeur physique, ordre des profils et interpolation. Build simulateur et build iPhone signé réussis. Journaux `/tmp/plaquisto-lecture-precise-{build,device,tests}.log` et `/tmp/plaquisto-lecture-precise-tests-final.log`. Contrôle des quatre résumés et ouverture des réglages réalisé dans le simulateur.
- Non installé sur iPhone à ce stade ; seuls les simulateurs ont été utilisés pour la vérification.

## Coupe stable, nettoyage maillage plafond/DAE et propositions graphiques — 12 octobre 2026

- Coupe plafond : panneau de confirmation réservé dès l’entrée dans le mode découpe, transparent/inactif avant l’aperçu. Instructions stables. Cela évite la réduction du canvas et le recentrage à la levée du doigt ; validation de la dernière ligne affichée, sans recalcul depuis la position de relâchement.
- `SurveyCeilingCutConfirmation` testé en largeurs 240/390/750 et grandes tailles de texte ; 3 tests coupe/layout réussis (`/tmp/plaquisto-ceiling-cut-stability-tests.log`). Pas encore de vérification gestuelle sur iPhone.
- Raccords artificiels de triangles coplanaires : résolution optionnelle des jonctions A–C / A–B–C avant extraction des contours, activée pour génération et coupe des plafonds. Déduplication des faces identiques, refus de contours ambigus/non-manifold, aucun moyennage de hauteur/pente. Trous et îlots restent distincts. N’aplatit pas les vrais pans estimés ou dessinés ; pas de migration destructrice des anciens relevés.
- DAE : positions identiques partagées par index au sein de chaque maillage, normales conservées par face pour les vraies arêtes. Aucun soudage entre objets distincts ou à travers un écart réel. Les triangles restent nécessaires au format, mais leurs sommets ne sont plus systématiquement isolés.
- Designer mandaté : trois pistes comparables, sources et PNG dans `/Users/edouard/Documents/ChatGPT/Plaquisto/outputs/calepinage-design-2026-10-12/`. Préférence proposée « Lecture précise », alternatives « Plan de chantier » et « Calques doux ». Joints fins, fourrures lisibles, appui horizontal distinct, sélection orange. Aucun redesign iOS appliqué avant choix utilisateur.
- Validation finale : 154/154 tests réussis (SurveyCaptureTests, CeilingMeshCleanupTests, ScanWallSimplificationTests), confirmé par xcresult ; journal `/tmp/plaquisto-scan-cleanup-regressions-v2.log`. Build signé PlaquistoLab réussi `/tmp/plaquisto-ceiling-cleanup-device.log`. Ces changements du 12 octobre ne sont pas encore installés sur téléphone.

## Redressement/fusion des fragments de murs — 11 octobre 2026

- Ajout `ScanWallSimplification`, uniquement sur la géométrie finale des nouveaux scans RoomPlan, avant génération des plafonds. `initialRoom` et cache natif restent inchangés ; aucun retraitement automatique des anciens ouvrages.
- Tolérances doublées à la demande utilisateur : distance à la droite commune 4 cm, orientation 6°, distance des extrémités 5 cm, désaccord de hauteur au raccord 4 cm. La droite passe par les deux extrémités extérieures, pas de moyenne itérative qui dérive.
- Fusion uniquement de chaînes adjacentes : refus des branches/jonctions en T, vrais angles, marches, faces parallèles séparées et modifications manuelles. Conservation des profils verticaux/rampants et identités/dimensions des ouvertures ; repérage des ouvertures transféré au mur fusionné. Limite supplémentaire de variation de surface 1 %, raccordement du contour du sol et validation géométrique avant application.
- Validation : 9 tests `ScanWallSimplificationTests` + régression fusion manuelle sous rampant réussis (10/10), journal `/tmp/plaquisto-wall-simplification-tests-v2.log`. Première exécution corrigée uniquement côté assertions : epsilon flottant et date fixture ISO-8601 sans fractions. Build iPhone signé réussi `/tmp/plaquisto-wall-simplification-device.log`.
- 11 octobre 2026 à 23:42 : mise à jour `fr.plaquisto.lab` installée sur l’iPhone 16 Pro `6A65A405-C70C-5FEF-88B6-B110C4E648B8`, sans désinstallation. Un nouveau scan réel reste à réaliser pour apprécier les seuils et le rendu sur place.
- Lancement automatique refusé car iPhone verrouillé (`FBSOpenApplicationErrorDomain Locked`) ; ouvrir Plaquisto Lab manuellement après déverrouillage.
- Diagnostic Safari demandé : produit KNAUF 3525447, « boîte de 50 », 25,24 € HT. Référence 300 mm correctement cochée, conversion vide donc bouton désactivé. `core.js` ne reconnaît le nombre qu’avec suffixe pièces/pcs/unités. Vérification locale : diviseur 50 => 0,45432 €/unité après -10 %. Aucun rattachement/prix modifié pendant ce diagnostic.

## Installation iPhone — 11 octobre 2026, 23:07

- Dernières sources compilées en Debug signé pour `PlaquistoLab` (équipe U6X2KSN84X), build réussi `/tmp/plaquisto-appuis-device-build.log`, produit `/tmp/PlaquistoPricesDevice/Build/Products/Debug-iphoneos/Plaquisto Lab.app`.
- Mise à jour `fr.plaquisto.lab` installée puis lancée avec succès sur l’iPhone 16 Pro d’Edouard (`6A65A405-C70C-5FEF-88B6-B110C4E648B8`). Pas de désinstallation ni suppression de données.
- Inclut les appuis intermédiaires par modèle, les suspentes galvanisées/composites, les changements isolation/plénum et la correction d’identités stables à l’enregistrement des ouvrages issus du relevé. Les parcours tactiles restent à valider sur téléphone.

## Appuis intermédiaires par modèle, 11 octobre 2026

- Dernière décision utilisateur : sélection uniquement selon l’épaisseur d’isolant (aucune priorité à la tapée, même explicite). Tableau conservé dans Admin avec tapées descriptives. Sept références `QTY-APPUI-FOURRURE-{15-45,75,100,120,140,75-160,200}`, prix unitaires laissés à renseigner.
- Étape 3 doublage fourrures : option remplacée par « Fixation directe des appuis dans la maçonnerie », désactivée par défaut. Liaison inverse à `includesHorizontalSupportFurring` pour conserver les anciens choix et le comportement calepinage/quantitatif. Fixation directe : modèles 15-45 (0–60 mm) ou 75-160 (75–160 mm). Sur fourrure horizontale : 75/100/120/140/200 avec bornes du tableau, modèle supérieur aux limites communes (120 mm → 140). Aucun modèle deviné dans les trous/hors plages : quantité conservée, « modèle à préciser », sans prix attribué.
- API `doublageFourrures.appuis` alimente la sélection iOS, sans table métier codée en dur dans l’app. Identité/libellé du modèle mémorisés avec configuration ; utilisés dans quantitatifs, minimum automatique du calepinage et appuis des ouvertures rattachées. Recalcul géométrique reconnaît aussi les libellés spécifiques. Les modèles restent séparés au regroupement des fournitures.
- Admin commit `c31693f` poussé main, déploiement Vercel réussi, insertion des sept fiches via Admin authentifié. Tableau Fournitures > Systèmes vérifié et API publique contrôlée pour les sept plages exactes. Édition dédiée isolant/tapée indicative/fixation, contrôle des chevauchements hors limites communes. Aucun prix existant modifié.
- Extension reconstruite/signée et mise à jour dans `/Users/edouard/Applications/Point P vers Plaquisto.app`. Sept références visibles/exportables indépendamment (542 références, 385 cibles Admin), ancien rattachement générique conservé. Vérification Safari : 3 118 produits et 60 associations conservés, recherche « Appuis intermédiaires » laissée ouverte.
- Vérifications : 36 tests Admin + build Next/TypeScript ; 31 tests extension + build macOS ; 11 tests iOS (3 appuis + 3 composite + 5 galvanisé) réussis, journal `/tmp/plaquisto-appuis-ios-tests.log`. Aucun déploiement iPhone effectué.

## Suspentes composites par modèle, 11 octobre 2026

- Cinq références Admin `QTY-SUSPENTE-COMPOSITE-{FERMETTE,12-16,16-20,20-24,24-28}` : plages de plénum inclusives 20–80 / 81–160 / 161–200 / 201–240 / 241–280 mm. Pas de longueur physique inventée (colonne fournie vide), prix à l’unité distincts et laissés à renseigner. Support bois pour plafonds horizontaux/rampants ; aucune compatibilité hourdis inventée.
- Système `FIX-BOIS-PARE-VAPEUR` migré par marqueur de sélection, vis/coefficients/limites conservés. iOS utilise les plages publiées pour choisir un seul modèle entier-mm, affiché au choix système et dans les quantitatifs formulaire/projet ; aucun prix deviné en cas de référence absente, plage ambiguë ou hors tableau. Préférence composite si pare-vapeur prévue conservée. Les anciens relevés/formulaires ne sont pas réécrits.
- Admin commit `8235157` poussé main, Vercel réussi. Ouverture authentifiée Admin pour persister les cinq nouvelles fiches et migrer le système ; UI et API publique `/api/ios/catalogue` vérifiées avec toutes les plages exactes. Édition dédiée modèle/minimum/maximum dans Fournitures > Systèmes de fixation.
- Extension reconstruite/signée et mise à jour dans `/Users/edouard/Applications/Point P vers Plaquisto.app` : cinq nouvelles références exportables visibles, ancienne référence générique locale conservée pour ne pas casser d’associations. 3 118 produits et 60 associations toujours présents ; aucun prix copié ni publié.
- Vérifications : 31 tests Admin, build Next/TypeScript, 30 tests extension et build macOS réussis. 8 tests Swift composite/galvanisé réussis, y compris tous les mm de chaque plage, frontières, cas invalides, composants préservés et préférence de fixation. Résultat `build/Logs/Test/Test-Plaquisto-2026.10.11_21-57-40-+0200.xcresult`, journal `/tmp/plaquisto-composite-tests.log`. Aucune installation iPhone effectuée.

## Plénum, suspentes par longueur et isolation, 11 octobre 2026

- Formulaire plafond fourrures horizontal/rampant sur bois : diagramme SwiftUI Canvas flat (solive orange, suspente et fourrure bleu-gris, placo clair), cote dynamique en cm, trait interrompu autour du chiffre. Texte de plénum remplacé selon demande. Première couche proposée entre solives/chevrons, deuxième dessous ; emplacement avant type ; première épaisseur 60 mm si publiée pour l’isolant choisi. Les configurations enregistrées conservent leurs choix à l’ouverture.
- Saisie du supplément de plénum en millimètres entiers. Sept références `QTY-SUSPENTE-GALVA-{80,180,240,300,400,500,600}` ; sélection unique depuis les plages Admin, sans table métier dupliquée en production iOS. Quantitatifs formulaire/projet utilisent le libellé de longueur pour le rattachement tarifaire ; accessoires hourdis/vis et coefficients conservés.
- Bois : 20–60 / 61–150 / 151–210 / 211–270 / 271–370 / 371–470 / 471–570 mm. Hourdis : 20–70 / 71–170 / 171–230 / 231–290 / 291–390 / 391–490 / 491–590 mm. Minimum propre au système hourdis à serrer conservé à 60 mm. Plages entières et non chevauchantes contrôlées dans Admin ; un ancien projet hors plage n’est pas associé arbitrairement à un prix.
- Préférence de fixation : galvanisé bois/hourdis, composite bois si pare-vapeur prévu, uniquement parmi les systèmes compatibles (forme/support/plénum). Un choix manuel compatible reste conservé ; changer le choix pare-vapeur réapplique la préférence.
- Admin `d764f59` poussé sur main, Vercel réussi. Session Admin authentifiée ouverte pour persister les nouvelles références et migrer les trois systèmes sans réinitialiser la base. Les sept références et les deux tableaux ont été vérifiés dans l’UI Fournitures puis via `/api/ios/catalogue` en production. Aucun tarif créé ou modifié.
- Extension Point P vers Plaquisto reconstruite/signée et mise à jour dans `/Users/edouard/Applications` : sept longueurs visibles et exportables, 3 118 produits et 60 associations existantes vérifiés conservés dans Safari. Nouveaux prix laissés à renseigner. 29 tests Node au total (28 existants + couverture sept tailles), build extension réussi.
- Admin : 28 tests métier réussis, TypeScript et build Next réussis. Exécution iOS finale : **7 tests diagramme/sélection/isolation/préférence galvanisé-composite réussis**, zéro échec (`/tmp/plaquisto-hangers-defaults-tests.log`, résultat `build/Logs/Test/Test-Plaquisto-2026.10.11_21-46-28-+0200.xcresult`). Aucune installation iPhone dans ce lot.

## Vérification du refus d’enregistrement sur fourrures, 11 octobre 2026

- Capture `IMG_7151.PNG` : refus à l’étape Résultat du doublage sur lisses et fourrures. Le contrôle incriminé compare notamment les surfaces du calepinage préparé hors du store avec celles reconstruites à l’enregistrement. Des UUID recréés aléatoirement suffisaient à faire échouer cette égalité sans changement de dimensions ; la correction d’identités stables du 9 octobre est déjà présente dans les sources.
- Le dernier binaire iPhone documenté, `/tmp/PlaquistoPricesDevice/Build/Products/Debug-iphoneos/Plaquisto Lab.app/Plaquisto Lab`, a été construit le 9 octobre à 23 h 12. Il contient le calepinage automatique mais pas la chaîne `plaquisto-survey-projection/v1/` du correctif ; le binaire simulateur actuel la contient. Les tests de cette correction datent de 23 h 31–23 h 32, après ce build iPhone. Cela explique probablement la récurrence sur le téléphone ; l’archive exacte du relevé de la capture n’a pas été fournie.
- Couverture ajoutée dans `ProjectStoreTests` : préparation externe puis sauvegarde/relecture d’un doublage fourrures à trois murs tournés, hauteurs non arrondies, porte et fenêtres qui se chevauchent ; conservation des contours, ouvertures, surfaces nettes et plans. Les mesures réellement arrondies/modifiées, runs absents et nombre de murs incorrect restent rejetés atomiquement. Aucun assouplissement des contrôles métier ni nouveau changement de géométrie.
- Validation : compilation simulateur réussie et **6 tests ciblés réussis**, zéro échec, dont les deux nouvelles régressions fourrures, partition avec/sans porte, plafond multi-frontières avec trémie, rejet de géométrie/configuration altérées et champs SwiftUI désactivés conservant leur précision. Journal `/tmp/plaquisto-survey-furring-save-tests.log`, résultat `build/Logs/Test/Test-Plaquisto-2026.10.11_21-41-06-+0200.xcresult`. Aucun commit, push ni installation iPhone dans cette vérification.

## Quantitatifs actualisés sans seconde validation, 9 octobre 2026

- Sauvegarder un calepinage de plafond sur fourrures ou rails/montants actualise son quantitatif dans la transaction du plan ; le dialogue de confirmation et le message orange d’attente d’accord sont supprimés.
- Les sous-parties non calepinées conservent leur estimation au prorata. Les détails inutilisables ne réutilisent jamais un ancien quantitatif : estimation du formulaire et indication explicite dans la vue des quantités.
- Les anciennes quantités périmées sont recalculées et persistées au chargement. Les changements du relevé réactualisent également le calcul sans approbation supplémentaire. Les identifiants de formats sont conservés pour retrouver les libellés des parements.
- Une modification de contour scanné applique immédiatement la nouvelle surface au formulaire lié. L’estimation automatique initiale d’un plafond ne bloque plus les quantités d’un plan ensuite modifié.
- Vérifié : compilation simulateur et **403 tests réussis** (`ProjectStoreTests`, `SheetLayoutEngineTests`, `SurveyCaptureTests`), journal `/tmp/plaquisto-auto-quantity-tests-verified.log`. Test ajouté : sauvegarde et modification d’une sous-partie, prorata 50 %, rechargement et migration d’une ancienne quantité en attente. Aucun commit, push ni installation dans cette intervention.

## Correction enregistrement ouvrage depuis relevé, 9 octobre 2026

- La projection relevé → surfaces 2D produit désormais des identités stables par
  relevé/checkpoint/mur ou pan/frontière, y compris pour les trous des plafonds.
  La préparation asynchrone du calepinage ne déclenche plus un faux changement
  de dimensions lorsque le store reconstruit les mêmes surfaces à la sauvegarde.
- Comparaison stricte des contours, ouvertures, repères et configuration conservée ;
  aucun contournement du contrôle de source périmée. Identités des surfaces déjà
  sauvegardées conservées par la synchronisation existante.
- Régressions reproduisant le chemin formulaire réel (préparation externe) :
  cloison avec/sans porte, doublage, plafond à frontières distinctes avec trémie,
  rejet de changements réels. 402 tests ProjectStore/SurveyCapture/SheetLayoutEngine
  réussis ; compilation simulateur réussie. Pas encore installé sur iPhone.

## Calepinages automatiques et estimation tarifaire, 9 octobre 2026

- Création d’un ouvrage depuis un relevé : préparation hors thread UI des plans
  sur les contours réels, avec formats/parements/entraxes du formulaire. Systèmes
  actuellement attribuables depuis le relevé : plafonds fourrures ou rails/montants,
  doublages fourrures ou montants, cloisons créées dans le plan. Peinture exclue.
  Aucune géométrie inventée depuis une simple surface ; plans existants préservés.
- Optimisation : pénalise prioritairement les petites pièces indépendantes de
  moins de 300 mm (dimensions, aire et bandes obliques), sans pénaliser une petite
  pointe attachée à une grande pièce. Recherche bornée, pas une garantie de
  solution sur tout contour : avertissement si des découpes contraintes subsistent.
  Ossature calée sur les joints quand compatible avec l’entraxe choisi, sans
  modifier ce dernier. Toutes les peaux et faces utilisent l’ossature commune.
- Cloisons : deux identités A/B indépendantes des pièces propriétaires, miroir de
  géométrie/ossature, plaques propres à chaque face, ossature comptée une fois.
  Copie remappe ces identités. Anciennes données sans ce champ restent compatibles.
- Snapshot des besoins automatiques : maximum par fourniture entre formulaire et
  plan, sans réduction automatique ni double marge. Config modifiée invalide le
  snapshot ; impossibilité de rapprochement conservée comme avertissement.
- Tarifs : nouveau `SupplyPrices.swift`, lecture séparée `/api/ios/prices`.
  Estimation HT proportionnelle, REP comprise, fourchette -5/+5 %, aucun arrondi
  au conditionnement. Raccordement exact produit/format/unité pour les parements
  et référence quantitative/unité/variante standard (papier pour bande). Le pont
  depuis les anciens libellés est volontairement strict : pas d’équivalence floue.
  Autres variantes/familles non résolues restent non chiffrées. API absente, prix
  proposé, ambigu ou expiré : jamais zéro implicite. Cache hors ligne avec date
  de validité contrôlée, Europe/Paris comme Admin.
- Vue quantitatif ouvrage/projet et partage texte : fourchette, état partiel et
  liste des fournitures non chiffrées ; référence de révision dans le partage.
  Pas de devis contractuel ni prix figé dans le projet : affichage recalculé avec
  les tarifs validés disponibles ; le fichier partagé conserve son état exporté.
- Admin (autre dépôt) : tableau `/tarifs`, API protégée d’édition, API publique
  filtrée, huit propositions extraites du devis. Prix et provenance séparés des
  coefficients techniques ; source/fournisseur non exposés publiquement.
  Admin publié sur main (`f0bee65`), déploiement Vercel réussi. Exemples réels
  retirés du dépôt public et des bundles ; import JSON local de brouillons.
  Migration SQL appliquée en production après confirmation de publication.
  Huit prix importés en base privée : six validés (trois formats BA13, vis25/35,
  bande papier), deux proposés (poudre lente/rapide, choix standard à confirmer).
  API production HTTP200 : six lignes, aucune provenance fournisseur exposée.
  Page Admin /tarifs vérifiée en session authentifiée : huit lignes enregistrées.
  Lab signé installé et lancé sur l’iPhone d’Edouard (fr.plaquisto.lab), sans
  désinstallation ni effacement. Journal `/tmp/plaquisto-prices-device-build.log`.
  Aucun commit/push iOS dans ce lot.
- Vérifications : 258 tests iOS réussis, dont copie des deux faces des cloisons,
  sauvegarde/relecture des plans automatiques et estimation tarifaire. Journal
  final `/tmp/plaquisto-prices-layout-final-tests.log`. Build Lab réussi
  `/tmp/plaquisto-prices-lab-build.log`. Admin : 32 tests, typecheck/lint/build OK.
  Parcours Lab vérifié au simulateur : création d’un ouvrage Bandes à joint 10 m²,
  sauvegarde, sélection et quantitatif projet. Bloc tarifs indisponibles affiché
  sans montant zéro, quantités 17,3 ml et 3,3 kg consultables. Pas de test connecté
  iPhone du parcours complet avec prix publiés ; API production et tableau Admin
  vérifiés séparément. Le reste du devis/catalogue demeure à rapprocher et chiffrer.

## Bandes à joint et ouvertures rattachées, 9 octobre 2026

- Nouveau type/payload Codable `jointTreatment`, catégorie « Bandes à joint ».
  Formulaire surface totale des faces, murs/plafonds, poudre/pâte, résultat.
  Ratios chargés depuis les enregistrements Admin existants : doublage rails/
  montants pour les murs, QTY-BANDE/ENDUIT pour les plafonds. Snapshot enregistré,
  sans coefficients de production dupliqués ni nouvelle publication Admin.
- Avertissement et liste des ouvrages dont le traitement des joints est activé :
  surface déduite du nouvel ouvrage, murs/plafonds séparés, deux faces pour les
  cloisons, minimum zéro. Quantitatifs des autres ouvrages inchangés. Le contexte
  du projet entier est utilisé même pour consulter le seul ouvrage Bandes.
  Rappel des bandes armées pour angles saillants dans le résultat et le partage.
- Les points des appuis intermédiaires ne sont plus dessinés dans les doublages
  sur fourrures ; leurs positions et quantités restent calculées.
- Ouvertures retirées du choix de nouvelle catégorie. Action sous « Modifier la
  configuration » dans les ouvrages compatibles, iOS et Lab. Stockage historique
  des enregistrements liés conservé, masqué de la liste principale et inclus une
  seule fois dans le quantitatif du parent. Anciens enregistrements sans parent
  accessible toujours visibles. Copie d’un ouvrage copie ses ouvertures liées.
- Vérifications : 249 tests réussis (99 ProjectStoreTests, 150 SheetLayoutEngineTests)
  dans `/tmp/plaquisto-joints-tests.log`. Parcours création et formulaire vérifiés
  dans le simulateur ; saisie UI complète non validée, session Simulator instable
  lors de la saisie automatisée. Calculs et persistance vérifiés par tests.
  Aucune installation sur iPhone ni publication Admin dans ce lot.
- Demande suivante, au stade avis : création automatique des calepinages,
  optimisation des coupes vers 30 × 30 cm, ossatures sur jonctions et ajustement
  à la hausse des fournitures. Non implémentée dans ce lot ; ne pas inventer de
  contour depuis une simple surface ni garantir 30 cm aux découpes contraintes.

## Doublages : traverses, rives fixes et éclisses, 9 octobre 2026

- Formulaire lisses/fourrures : snapshot optionnel des distances d’appuis Admin
  dans la configuration. Le calepinage récupère aussi le choix avec/sans fourrure
  horizontale. Sous rampant, les traverses restent horizontales ; une ligne
  supplémentaire commence seulement où la hauteur locale la nécessite. Les
  ouvertures coupent les traverses ; les appuis sont alignés sur leurs lignes.
  Anciens ouvrages sans snapshot : répartition indicative depuis le nombre de
  lignes, message invitant à réenregistrer le formulaire pour récupérer la règle.
- Doublage fourrures : profil vertical fixe à 120 mm de chaque bord (axe),
  fourrure à gauche et cornière à droite, tronqués au contour et aux ouvertures.
  Ne suivent pas le décalage de trame ; superposition avec une fourrure mobile
  soustraite pour ne pas dessiner deux fois le même segment.
- Éclisses : `ceil(longueur / 3000) - 1` par ligne continue, tolérance numérique,
  réunion des subdivisions jointives et exclusion des cornières. Affichage dans
  les réglages d’ossature ; reprise des plafonds fourrures dans le quantitatif
  approuvé au prorata des surfaces calepinées. Reliquat du formulaire conservé,
  anciens quantitatifs approuvés sans comptage d’éclisses compatibles. Rails/
  montants exclus du nouvel affichage et de cette reprise.
- Commandes inversées en vue normale et plein écran : onglet Ossatures déplace
  les plaques (« Caler les plaques sur l’ossature »), onglet Plaques déplace
  la trame mobile (« Caler les ossatures sur les plaques »). Profils fixes exclus
  du calage des plaques comme les renforts d’ouvertures.
- Tests : cas limites 3/6/9 m, interruption par ouverture, rampant, traverses
  désactivées, rives fixes lors du déplacement/calage, sérialisation et
  remplacement partiel de l’estimation d’éclisses. Journaux :
  **244 tests réussis** (150 SheetLayoutEngineTests + 94 ProjectStoreTests),
  `/tmp/plaquisto-wall-furring-tests-verified.log`. Correction d’une régression
  de métadonnée par défaut qui modifiait inutilement les plans manuels.
  Build Lab : `/tmp/plaquisto-wall-furring-lab-verified.log`.
  Aucune publication Admin ni installation iPhone demandée dans cette étape.

## Rendu Élevé par défaut, 9 octobre 2026

- Préférence persistante `maquette.rendering` dans les réglages iOS et Lab :
  Élevé par défaut (y compris en l’absence de préférence), Standard disponible.
- Élevé : murs bleu clair mats, sol gris clair uni, contours encre, sélection
  orange et plafonds sélectionnés à 80 % d’opacité. Appliqué à la maquette,
  aux éditeurs et aux miniatures ; cache des miniatures distinct par rendu.
- Géométrie métier, scans, UUID, quantitatifs et exports inchangés. Changement
  de rendu sans reconstruire le scan ni réinitialiser la caméra. Arêtes de
  présentation regroupées par surface ; diagonales coplanaires exclues.
  Traits fins géométriques pour éviter le scintillement des lignes coplanaires.
- Pas de texture de sol, SSAO ni ombres portées en Élevé : éclairage diffus
  simple. Budget thermique/batterie indépendant, FPS et anticrénelage inchangés.
  RAM/FPS sur appareil réel non mesurés : ne pas prétendre à un gain chiffré.
- Tests : 235 réussis (141 SurveyCaptureTests + 94 ProjectStoreTests), journal
  `/tmp/plaquisto-elevated-tests-verified.log`. Images SceneKit produites et inspectées
  dans `/tmp/plaquisto-elevated-verified-attachments/`. Choix Élevé par défaut et
  bascule Standard puis Élevé vérifiés dans le simulateur Lab. Build Lab réussi
  (`/tmp/plaquisto-elevated-build-final.log`). Pas d’installation iPhone.

## Coupe de plafond par glissement, 9 octobre 2026

- Sélecteur de plafonds : « Découper », « Fusionner » (voisins partageant un
  bord, confirmation) et « Masquer / Afficher ». Fusion par raccord de segments,
  sans enveloppe convexe : aucun remplissage de trou ni fusion de zones disjointes.
  Les pans et leurs UUID restent identiques, ainsi que les calepinages associés.
- `PlaquistoCeiling.isHidden` optionnel et persistant : affichage et sélection de
  nouveaux ouvrages seulement. Géométrie canonique, ouvrages existants,
  quantitatifs et export complet conservés. La création d’ouvrage revérifie que
  les sources ne sont pas masquées. Le sélecteur conserve toutes les zones pour
  pouvoir les réafficher. Une édition explicite montre temporairement sa cible.
- Hauteurs minimale/maximale réglables par curseurs (pas 1 cm), aperçu fixé
  au-dessus du formulaire ; saisie numérique dans « Saisie précise des hauteurs ».
  Orientation/faîtage conservent leurs curseurs. La caméra et les maillages du
  sol/des murs sont réutilisés pendant les changements de hauteur des plafonds.
- Régression : **233 tests réussis** (139 SurveyCaptureTests + 94 ProjectStoreTests),
  `/tmp/plaquisto-ceiling-contact-tests.log` (dernier passage, recognizer inclus),
  build Lab simulateur réussi `/tmp/plaquisto-ceiling-contact-sim.log`.
  Tests de conservation des pans,
  identité des plans, quantités après fusion/masquage, sérialisation et caméra.
- UI simulateur : ouverture du sélecteur, Masquer/Afficher et présence du curseur
  avec aperçu fixe vérifiées. Le pilote `cua.drag` ne déplace pas non plus le
  curseur natif dans cette session : glissement réel de coupe/hauteur non validé
  par cette automatisation. Vérifier au doigt sur iPhone avant de prétendre à une
  validation tactile. Relevé synthétique temporaire supprimé ; aucun projet réel
  modifié. Le recognizer conserve le point physique de contact initial pour les
  gestes dont la reconnaissance arrive après le premier déplacement.
- Historique de la direction graphique (désormais implémentée ci-dessus) : propositions d’un sous-agent dans
  `/Users/edouard/Documents/ChatGPT/Plaquisto/design-maquette/`. L’utilisateur veut
  une nouvelle direction « Lecture précise », plus moderne et **contrastée**,
  puis finalement **moins réaliste / plus flat**. Nouvelle planche
  `plaquisto-trois-pistes-flat-2026-10-09.png` : Blanc & ardoise, Encre & minéral,
  Graphite & crème. Choix utilisateur : **Encre & minéral avec sol gris clair
  neutre et discret**, sans texture ni reflet. Visuel livré :
  `plaquisto-encre-mineral-sol-gris-clair-2026-10-09.png` dans le même dossier ;
  base du rendu Élevé implémenté ensuite.
  Précision suivante : plafond sélectionné en orange franc à **80 % d’opacité**
  (20 % transparent), contour orange soutenu ; pas seulement une teinte pâle.
  Préférence Standard (rendu d’origine) / Élevé, uniquement visuelle.

- `SurveyPlanEditor` : pose du doigt = départ, déplacement maintenu = arrivée
  mobile ; trait orange pointillé, repères d’extrémité et petits ciseaux.
  Le relâchement calcule un aperçu séparé du document de travail, avec les deux
  moitiés orange/bleue et les actions persistantes « Valider » / « Refaire la coupe ».
- `SurveyCeilingCut` isole le brouillon : seule la validation appelle
  `commitDocument` et ajoute une étape d’annulation. Refaire/annuler ne change
  ni le document ni les ouvrages. La sauvegarde habituelle du relevé reste requise.
- Deux doigts annulent un trait en cours pour naviguer, mais conservent un aperçu
  déjà calculé. Un appui sans glissement, une coupe trop courte ou extérieure est
  refusée sans créer de plafond. Les commandes concurrentes d’édition/sauvegarde
  sont désactivées pendant la découpe. Les pentes et la surface totale sont conservées.
- Aucun changement du post-traitement LiDAR : la simplification des murs par
  ajustement robuste de segments quasi alignés est seulement discutée, pas codée.
  Ne pas confondre les deux extrémités d’un axe en plan avec le contour en hauteur
  d’un mur sous rampant, qui peut légitimement avoir plusieurs sommets.
- À la demande suivante : retrait du bouton « Modifier le contour » du
  configurateur de plafond du relevé 3D. L’éditeur de contour du calepinage
  et le bouton « Modifier le plan » du relevé ne sont pas retirés.
- Logs de vérification : `/tmp/plaquisto-ceiling-cut-tests.log`,
  `/tmp/plaquisto-ceiling-cut-sim.log`, `/tmp/plaquisto-ceiling-cut-device.log`.
  Pas d’installation iPhone demandée pour cette modification.

## Prototype d’observations visuelles du scan — Lab uniquement, 8 octobre 2026

- `ScanVisualEvidence.swift` : échantillonnage local des images ARKit, pose de
  caméra, calibration et profondeur/confiance **si la session native les fournit**.
  Activé exclusivement pour `fr.plaquisto.lab`, indépendamment du thème graphique.
  Aucun remplacement de délégué, redémarrage, changement de configuration ou de
  repère de la session RoomPlan. Aucun serveur ni reconnaissance visuelle distante.
- Une seule image en cours d’encodage, traitement CI et fichiers hors main thread,
  JPEG 960 px maximum, profondeur réduite à 96 colonnes, confiance haute uniquement.
  Au maximum 120 images / 24 Mo par relevé, 72 Mo de cache au total ; arrêt des
  seules images si quota/erreur, pas du scan. Échantillons retenus lors d’un déplacement,
  changement de direction ou après 8 secondes ; pas d’enregistrement vidéo.
- **Demande utilisateur : aucun compteur, animation ou indication photo pendant
  le scan.** L’interface de capture reste inchangée. Pas d’écriture dans Photos.
  Les limites/erreurs sont diagnostiquées après capture, sans exposer les images.
- Cache privé protégé, exclu des projets, DAE et diagnostics partagés. Expiration
  de lecture à 24 h, purge au lancement Lab/démarrage/lecture, et suppression manuelle
  depuis la réparation. Annuler la capture efface ses observations. Le scan durable
  reste indépendant ; perdre le cache ne bloque ni édition ni sauvegarde.
- Dans `Réparer le relevé`, comparaison de la zone choisie avec les photos et
  projection orange, choix de photo et de zone. La calibration reste dans les axes
  capteur ; une orientation JPEG séparée affiche correctement les photos portrait.
- Analyse géométrique prudente des fermetures déjà proposées : profondeur au
  niveau du mur, derrière la zone, contradictoire ou insuffisante. Au moins deux
  positions espacées de 20 cm avec couverture suffisante ; les mesures devant
  le mur (occlusion), manquantes ou peu fiables ne prouvent pas un mur.
  Rien n’est sélectionné/appliqué automatiquement et `initialRoom` reste intact.
- **Limite du prototype** : ce n’est pas une reconstruction photogrammétrique,
  une segmentation RGB ni un recalage global des murs. Sans `sceneDepth`, seules
  les photos sont disponibles pour le contrôle humain. La présence réelle de
  profondeur avec RoomPlan, les performances/batterie et l’efficacité sur le cas
  cuisine/salon nécessitent un NOUVEAU scan iPhone ; aucune amélioration terrain
  du modèle n’est revendiquée sur la base des tests simulateur.
- Vérification visuelle simulateur : état sans images et scénario synthétique
  de passage avec deux points de vue, projection orange cohérente, aucune fermeture
  appliquée. Tests de projection, rotation photo, confiance, occlusion, vues répétées,
  cache/expiration/suppression et quota ajoutés à `SurveyCaptureTests`.
  **132 tests réussis**, build iPhone Lab signé réussi, `git diff --check` propre.
  Les données synthétiques de contrôle ont été retirées du simulateur après vérification.
  Logs : `/tmp/plaquisto-evidence-tests.log`, `/tmp/plaquisto-evidence-device.log`,
  `/tmp/plaquisto-evidence-sim.log`.
- Installation demandée ensuite : build revérifié puis mise à jour sur l’iPhone
  16 Pro d’Edouard le 8 octobre vers 23 h 59 (`fr.plaquisto.lab` uniquement,
  sans désinstallation). Log build `/tmp/plaquisto-evidence-install-build.log`.
  La suggestion ultérieure d’un message demandant de stabiliser la prise de vue
  n’est pas encore implémentée dans cette version.

## Correction des gestes 3D après retour iPhone, 8 octobre 2026

- Le test utilisateur a révélé que `rotationSensitivity = 0` bloque l’orbite
  à un doigt sans supprimer le roulis à deux doigts. Ce réglage a été retiré.
- `UprightSurveySceneView` refuse l’ajout des `UIRotationGestureRecognizer`
  natifs, dans le relevé et l’éditeur/réparation. Les pan/pinch natifs restent.
  Désactiver le recognizer juste après son ajout ne suffisait pas : SceneKit
  le réactivait ensuite (échec reproduit par test, puis correction vérifiée).
- Tests vérifient un témoin SCNView avec geste de rotation présent, son absence
  dans la vue corrigée, les pan/pinch actifs après réactivation des contrôles,
  ainsi que l’orbite horizontale/verticale avec la sensibilité réelle de la vue.
  122 tests réussis, compilation iPhone Lab signée réussie ; logs
  `/tmp/plaquisto-gesture-roll-verified-tests.log` et
  `/tmp/plaquisto-gesture-roll-verified-device.log`. Pas encore réinstallé.
- Retour terrain sur beautifyObjects : pas d’amélioration visible du scan
  signalée par l’utilisateur. Ne pas présenter cette option comme une réparation
  démontrée des murs. Le prototype RGB/profondeur ajouté ensuite est décrit ci-dessus.

## Finalisation native Apple, 8 octobre 2026

- `RoomBuilder` utilise maintenant `[.beautifyObjects]`, au lieu de `[]`.
  La capture continue unique, le repère ARKit et les contours `polygonCorners`
  restent inchangés. Pas de nouvel alignement/fusion/bouchage maison des murs.
- `StructureBuilder` n’est pas invoqué artificiellement pour cette capture
  unique : son rôle documenté est l’assemblage de plusieurs CapturedRoom dans
  des espaces compatibles. Coaching natif déjà actif, maintenu.
- En cas d’échec de la finalisation améliorée, une tentative standard native
  est effectuée ; repli signalé dans le relevé et le diagnostic. Annulation
  propagée sans second traitement. Si les deux échouent, brouillon conservé.
- Entrée Codable `CapturedRoomData` archivée hors thread UI avant traitement,
  dans `<chunkID>.roomplan-capture`, séparée du résultat `<chunkID>.roomplan`.
  L’échec d’archivage est journalisé sans perdre le scan. Aucun ancien relevé
  ni ouvrage existant n’est retraité ou modifié par cette évolution.
- Diagnostic `nativePostProcessing` : options, état, raison du repli, présence
  d’archive brute, dernière géométrie live, résultat Apple complet avant
  conversion et géométrie convertie avant création des plafonds. Noms saisis
  masqués dans les instantanés portables ; pas de coordonnées GPS ajoutées.
- Tests : 216 réussis sur SurveyCaptureTests et ProjectStoreTests. Compilation
  iPhone Lab signée réussie. Logs `/tmp/plaquisto-native-processing-tests.log`
  et `/tmp/plaquisto-native-processing-device.log`.
- Limite : l’efficacité réelle sur les murs de la maison exige un nouveau scan
  LiDAR sur iPhone. Apple décrit notamment l’embellissement du mobilier ; cette
  option ne constitue pas une garantie de correction des murs ou des trous.
  Le diagnostic reçu était daté du 26 septembre, sans CapturedRoomData brut.
  Installation demandée puis réussie le 8 octobre à 23:15 sur l’iPhone
  `6A65A405-C70C-5FEF-88B6-B110C4E648B8`, bundle `fr.plaquisto.lab`, sans
  désinstallation ni remplacement des données des projets.

## Réparation élargie et pivotement 3D, 8 octobre 2026, après installation

- Confirmation utilisateur : bloquer seulement le pivotement à deux doigts,
  conserver orbite à un doigt et pincement. `rotationSensitivity = 0` dans le
  style SceneKit commun ; sensibilité du pan et du déplacement inchangée.
- Réparation : toutes les catégories d’ouvertures attachées à un mur deviennent
  proposées, y compris portes, fenêtres, passages au sol, créations manuelles et
  dimensions validées. Type, largeur et numéro de mur affichés pour les repérer.
- Raccords : extrémités libres à partir de 5 mm, suppression de la limite de 3 m
  et de la restriction colinéaire ; côtés manquants proposés sans prolongement
  en arrière dans les murs existants, ni croisement/chevauchement. Les ouvertures
  non attachées entièrement comprises dans le raccord sont retirées avec lui.
  Contours/rampants existants et original du scan conservés. Aperçu puis choix
  et application explicites ; aucun bouchage automatique pendant le scan.
- Limite : pas de remplissage universel d’un maillage brut ou de trous absents
  des ouvertures/extrémités du modèle. Ces cas restent éditables via le contour.
- Vérification : 212 tests réussis, zéro échec (SurveyCaptureTests et
  ProjectStoreTests), compilation iPhone Lab signée réussie. Journaux :
  `/tmp/plaquisto-repair-expanded-tests.log`,
  `/tmp/plaquisto-repair-expanded-device.log`.
  Pas de nouvelle installation ni de validation tactile sur iPhone à ce stade.

## Lab — ergonomie et réparation assistée, 8 octobre 2026

- Adresses : menu Plans/Google Maps/Waze, partage/copie, et suggestions MapKit
  dans le formulaire projet (temporisation, annulation des requêtes obsolètes,
  saisie libre toujours disponible). Pas de permission GPS supplémentaire.
- Réglages via engrenage ; quantitatifs via une icône de liste. Cotes répétées
  regroupées par longueur/direction visible pour plaques et ossatures, sans
  changer les calculs ni masquer les distances au mur servant au réglage.
- Ouvertures : grandes ossatures toujours à 5 cm du bord, petits renforts à
  10 cm vers l’intérieur depuis leur axe ; verticales d’ouverture en pointillés.
- Orbite SceneKit limitée à l’hémisphère supérieur, butée 89,5° pour éviter
  la singularité du pôle ; vue de dessus dédiée en déplacement panoramique.
- Contour de plafond éditable avec l’éditeur 2D partagé, hauteur/pente séparées.
  Rejet des chevauchements avec un autre plafond ; murs scannés conservés.
  Loupe déportée à gauche pendant le déplacement d’un sommet.
- « Réparer le relevé » remplace l’entrée de contrôle manuel : surbrillance orange,
  comparaison avant/après, choix explicite des fermetures et application atomique.
  Propositions conservatrices : ouvertures non identifiées non validées,
  ouvertures génériques entièrement surélevées/encadrées, interruptions de murs
  colinéaires de 10 cm à 3 m. Portes/fenêtres identifiées, passages au niveau du
  sol et coins manquants ne sont pas fermés automatiquement. Une zone sans
  proposition reste corrigeable via Modifier le plan.
- Les réparations ne modifient jamais `initialRoom`. Les nouveaux raccords
  conservent les hauteurs aux extrémités (rampants), sont des murs existants
  manuellement ajoutés, et ne sont pas arbitrairement attribués à un ouvrage.
  Les modifications des surfaces déjà liées passent par `updateSurveyRoom`.
- Recette simulateur : suggestions d’adresse/menu GPS, absence de suggestion
  sur une pièce intacte, aperçu orange/avant-après d’un trou synthétique,
  validation puis vérification de la sauvegarde (autre pièce intacte), ouverture
  du contour 2D depuis le configurateur de plafond. Aucune donnée réelle copiée
  ni modifiée pendant ces tests.
- Installation demandée puis réussie le 8 octobre à 22:38 sur l’iPhone 16 Pro
  `6A65A405-C70C-5FEF-88B6-B110C4E648B8`, bundle `fr.plaquisto.lab`, sans recopie
  ni remplacement de l’archive des projets. Lancement automatique refusé car
  l’iPhone était verrouillé ; ouverture manuelle possible après déverrouillage.
- Validation finale : 353 tests réussis, zéro échec (ProjectStoreTests,
  SheetLayoutEngineTests, SurveyCaptureTests). Compilation iPhone Lab signée
  réussie. Journaux : `/tmp/plaquisto-repairs-verified-tests.log` et
  `/tmp/plaquisto-repairs-final-device.log`. Les tests d’orbite simulent les gestes
  SceneKit et vérifient les deux butées, pas seulement les valeurs des propriétés.

## Lab Contraste — première tranche, 8 octobre 2026

- Reprise du target `PlaquistoLab` (`fr.plaquisto.lab`) pour tester une présentation
  épurée sans remplacer Plaquisto (`fr.plaquisto.app`). Même `ProjectStore`, mêmes
  modèles, références et calculateurs, mais sandbox distinct : aucune synchronisation
  implicite, aucun App Group, aucune modification des données de production.
- Présentation activée explicitement par l’environnement `interfacePresentation`.
  La valeur par défaut reste `.standard`. Première tranche : galerie des projets,
  page projet, fiche ouvrage, présentation du relevé et quantitatif.
- Vignettes réelles mises en cache via le moteur existant ; la vignette d’un ouvrage
  sélectionne seulement ses surfaces liées. Les ouvrages sans scan sont présentés
  honnêtement avec une icône, pas une fausse maquette.
- Actions secondaires dans les menus ; informations complémentaires repliables.
  Alertes de données, de géométrie et de quantitatif conservées. Formulaires et
  éditeurs métier réutilisés sans nouveau moteur de calcul.
- Réglages du Lab : accès à l’interface actuelle sur les données du Lab pour
  comparer. Le faux onglet Stock n’est pas affiché dans la nouvelle navigation.
- Parcours de recette : projet → relevé 3D/2D → sélection de surfaces → création
  d’ouvrage → retour projet → fiche ouvrage → calepinage/configuration/quantitatif ;
  puis quantitatif global, tout/aucun, sélection partielle et feuille de partage.
  Vérifier aussi recherche par lieu/date, retour arrière et menus secondaires.
- Validation : 201 tests ciblés réussis (ProjectStoreTests + SurveyCaptureTests),
  incluant présentation opt-in et correspondance des surfaces des vignettes.
  Résultat : `/tmp/PlaquistoContrastRegression/Logs/Test/Test-Plaquisto-2026.10.08_18-09-49-+0200.xcresult`.
  Compilation simulateur réussie, installation et lancement `fr.plaquisto.lab`
  sur `A734A080-B465-4BE5-B4E1-984AAD24696A`, avec copie du relevé synthétique de
  test du second simulateur (pas de projets réels dans le simulateur).
- Compilation iPhone signée et installation réussies le 8 octobre à 18:28,
  bundle `fr.plaquisto.lab`, après rétablissement du tunnel. Le Lab ne contenait
  aucune archive `projects-v2.json` (inventaire contrôlé) : copie des 7 projets,
  15 ouvrages et 9 relevés de Plaquisto dans le sandbox Lab, relue et comparée
  au fichier source avant lancement. Les anciens comparatifs photo du Lab sont
  conservés ; aucun écrasement de données préexistantes ni de données de production.
- Contrôle visuel interactif non réalisé : Mac verrouillé, l’outil UI demande un
  déverrouillage manuel. Ne pas présenter cette tranche comme validée visuellement.
  Lancement iPhone refusé par iOS car verrouillé (installation réussie) ; ouvrir
  manuellement Plaquisto Lab après déverrouillage. Démarrage simulateur confirmé.
  Pas de commit, push ni remplacement de l’app de production.

## Parement collé et synchronisation du relevé — 8 octobre 2026

- Crash iPhone confirmé dans `Plaquisto-2026-10-07-235906.ips` :
  `AdhesiveFacingConfiguratorView.selectedFormat`, appelé par le message d’alerte
  avant chargement du catalogue, accédait à `formats[1]` sur une liste vide.
  Format désormais optionnel, aucun format fictif ni enregistrement sans catalogue ;
  sélections normalisées à la réception des formats. Tests création/édition pendant
  chargement et catalogue vide/à un format.
- À la demande utilisateur, modifier un relevé ne réclame plus un contrôle manuel.
  Géométrie valide utilisable directement ; l’éditeur enregistre et synchronise les
  composants liés dans une seule transaction, avec leurs ouvertures. Les choix de
  matériaux, identités et placements des plans sont conservés. Les suppressions de
  surfaces retirent leurs composants liés ; les divisions explicites de plafonds
  conservent le mécanisme d’héritage de grille existant.
- Surfaces de formulaire et répartitions de parements actualisées. Estimations
  enregistrées ajustées selon les surfaces nettes, longueurs périphériques et axes
  d’ossature, en conservant les produits et coefficients existants (pas un nouveau
  calcul mécanique complet depuis Admin). Quantitatif de plan déjà adopté recalculé
  si exploitable, sinon retour à l’estimation du formulaire. Les autres ouvrages ne
  sont pas modifiés. Contrôles de géométrie et d’éditeur périmé conservés.
- Migration des anciens drapeaux de contrôle vers la géométrie liée actuelle lors
  du chargement. Une source introuvable dans une ancienne sauvegarde n’entraîne
  pas la suppression de son composant pendant cette migration.
- 415 tests Swift réussis : `/tmp/plaquisto-survey-sync-verified-tests.log`, plus
  un test additionnel réussi de recalcul automatique d’un quantitatif de plafond
  déjà adopté (`/tmp/plaquisto-survey-sync-takeoff-tests.log`).
  Compilation iPhone signée réussie :
  `/tmp/plaquisto-oct8-adhesive-survey-device-build.log`.
  Pas encore d’installation de cette correction, ni commit/push.
- Book graphique demandé à l’agent existant `redesign_clair` : livrables PNG,
  comparaison de l’existant et de propositions plus neutres/minimalistes, sans
  modification de l’interface de production. Second simulateur et jeu de données
  synthétiques, pas de scans privés.
  Livrables dans `/Users/edouard/Downloads/Plaquisto-Book-Refonte-2026-10-08` :
  couverture et 13 planches (8 parcours, familles couvrant les 11 outils),
  planche-contact, captures réelles et reconstitutions explicitement distinguées.
  Direction précisée par l’utilisateur : harmoniser légèrement l’existant, surtout
  simplifier sa lecture. Contrôle visuel des planches ; corrections des contours,
  chevauchements, dates, références de fournitures et actions essentielles.

## Publication et installation — 7 octobre 2026, 23:47

- Admin : commit `0b39959` poussé sur main, déploiement Vercel réussi. API publique
  vérifiée : Appuis intermédiaires pour fourrures et deux composants distincts
  Cheville crampon 8 mm / Piton de suspension 8 mm, coefficients inchangés.
- Persistance des fiches en base encore en attente d’authentification Admin :
  Safari était déconnecté ; lien envoyé à l’utilisateur, connexion demandée.
  Ne pas confondre publication API effective et migration en base effective.
- Dernier code iOS compilé signé (équipe U6X2KSN84X), installé sur l’iPhone 16 Pro
  `6A65A405-C70C-5FEF-88B6-B110C4E648B8`, bundle `fr.plaquisto.app`, séquence 3856.
  Installation réussie ; lancement automatique refusé car iPhone verrouillé.
- 410 tests Swift et 15 tests Admin réussis avant publication ; build Admin
  webpack et build iPhone réussis. Aucun projet utilisateur supprimé.

## Cheville et piton séparés — 7 octobre 2026

- Accord utilisateur : décomposer le lot « Cheville et piton » des plafonds
  rails/montants en une Cheville crampon 8 mm + un Piton de suspension 8 mm,
  chacun compté en unités et regroupé avec les fournitures des plafonds fourrures.
- Nouveaux résultats et fournitures par suspente séparés ; compatibilité des
  anciennes quantités conservée dans le regroupement et l’export. Les calculs
  issus du calepinage conservent leur couverture sans double comptage du lot.
- Admin : composants explicites ajoutés au support béton, avec migration ciblée
  seulement si la liste n’existait pas (configurations personnalisées préservées).
  iOS lit cette liste et possède la compatibilité de l’ancien libellé hors ligne.
- 410 tests Swift et 15 tests Admin réussis ; lint Admin et diff-check réussis.
  Non publié sur Admin et non installé sur l’iPhone.

## Regroupement des isolants — 7 octobre 2026

- Accord utilisateur : regrouper les m² d’un même isolant, épaisseur et lambda
  identiques, indépendamment de la couche ou de l’ouvrage. Les configurations
  et les coefficients de chaque ouvrage restent inchangés.
- Normalisation conservatrice des formats de libellés connus (ordre épaisseur /
  lambda, virgule décimale, première/deuxième couche, R dérivé). La désignation
  complète du produit est conservée, dont les mentions kraft et les références
  commerciales. Les anciennes lignes sans lambda exploitable restent distinctes.
- Plafonds et cloisons génèrent désormais un libellé explicite avec lambda ; les
  plafonds rails/montants conservent le titre catalogue complet plutôt que le seul
  matériau. Aucun changement de bases de calcul Admin requis pour cette étape.
- 408 tests Swift réussis, dont regroupement doublage double couche + plafond,
  idempotence, différences de produit / épaisseur / lambda et conservation des
  configurations. Non installé sur l’iPhone.

## Appuis intermédiaires pour fourrures — 7 octobre 2026

- Nom validé : Appuis intermédiaires pour fourrures. Les anciens libellés
  « pour doublage sur fourrure », verticaux, horizontaux et embrasure sont
  regroupés avec addition des quantités, sans modifier les calculs.
- Canonicalisation des sauvegardes, résultat du calculateur d’ouvertures et
  libellé du formulaire doublage mis à jour. Les appuis pour montants restent distincts.
- Données initiales et migration ciblée préparées dans Plaquisto Admin.
  110 tests Swift ciblés et 14 tests Admin réussis ; lint Admin et diff-check réussis.
  Ces changements ne sont pas encore publiés sur Admin ni installés sur iPhone.

## Montants d’embrasure, rails et vis — 7 octobre 2026

- Précision utilisateur : chaque montant latéral d’embrasure prend la hauteur
  sol-plafond ; chaque transversal prend la largeur de l’ouverture. Les règles
  existantes de nombre de pièces sont conservées, mais les montants sont désormais
  fournis uniquement en mètres linéaires, sous le profil exact de l’ouvrage.
- Le profil est transmis et sauvegardé dans le contexte des ouvertures (champ
  optionnel pour les anciennes sauvegardes). Les profils M48/35 et M48/50 restent
  distincts. À défaut de profil connu, la référence est explicitement à préciser.
- Rails Rxx au pluriel ; anciennes quantités génériques de doublage/cloison
  résolues avec leur configuration. Les rails alvéolaires restent séparés.
- Plafond rails/montants : libellés de vis parement/première peau remplacés par
  Vis TTPC 25, deuxième peau par Vis TTPC 35, avec compatibilité des anciens noms.
  Les autres références explicites, dont TTPC 45, ne sont pas fusionnées.
- Vérification : 404 tests Swift réussis, dont conversion géométrique, conservation
  des profils, anciennes sauvegardes et consolidation ouvrage + ouvertures.
  git diff --check réussi. Changements iOS uniquement, non installés sur l’iPhone.

## Fourrures d’ouverture regroupées — 7 octobre 2026, 22:54

- Accord utilisateur : fourrures de renfort, latérales, transversales et
  d’embrasure regroupées sous Fourrures F45/F47. Calculs géométriques inchangés ;
  pièces et mètres linéaires conservés séparément. Les montants restent distincts.
- Canonicalisation des anciennes sauvegardes et regroupement dès le résultat du
  calculateur d’ouvertures. Tests des renforts de fenêtre et fenêtre de toit,
  des totaux et des unités ; 104 tests Swift ciblés réussis.
- Ces appellations proviennent du moteur iOS, pas de fiches Admin distinctes :
  aucune nouvelle publication Admin nécessaire. Non installé sur l’iPhone.

## Hourdis simples et cornières — 7 octobre 2026, 22:49

- Nouvelle précision utilisateur, qui remplace la distinction précédente :
  Suspente hourdis à griffe et Suspente hourdis regroupées sous Suspentes hourdis
  simples. Suspente hourdis à serrer reste un produit distinct.
- Cornière d’angle plafond et Cornière d’ouverture regroupées sous Cornière,
  y compris les cornières périphériques issues du calepinage. Mètres linéaires
  et unités conservés séparément ; cornières de rive du plafond modulaire non
  assimilées. Coefficients et règles de fixation inchangés.
- Admin commit `cb8bc57`, publication Vercel réussie et valeurs vérifiées sur
  l’API publique. Code iOS mis à jour pour les anciens noms et les nouveaux
  quantitatifs ; 102 tests Swift ciblés et 13 tests Admin réussis, lint et build
  Admin réussis. Pas de nouvelle installation iPhone.

## Suspentes hourdis distinctes — 7 octobre 2026, 22:42

- L’utilisateur confirme deux produits différents : ancien libellé Suspente
  hourdis à griffe à serrer renommé Suspente hourdis à serrer ; Suspente hourdis
  à griffe conservée séparément, ainsi que Suspente hourdis simple.
- Admin : composants et titres des deux systèmes fourrures concernés renommés,
  identifiants et calculs conservés ; migration ciblée des anciens libellés.
  Commit `d105c3d` poussé sur main, Vercel réussi et trois produits distincts
  contrôlés sur l’API publique. Pas de fusion avec la fixation rails/montants.
- iOS : ancien libellé reconnu à la consolidation ; 17 tests Swift ciblés et
  11 tests Admin réussis, lint et build Admin réussis. Non réinstallé sur iPhone.

## Regroupement Demi-collier validé — 7 octobre 2026, 22:37

- Accord utilisateur : Demi collier / Demi-collier regroupés sous Demi-collier.
  Quantités et règles de fixation inchangées ; anciens noms consolidés côté
  iOS et présentation du formulaire rails/montants harmonisée, même en cache.
- Admin commit `a506c38` poussé sur main, déploiement Vercel réussi ; fixation
  bois des plafonds rails/montants et composant des plafonds fourrures vérifiés
  dans le catalogue public. Migration ciblée des supports de la règle existante.
- 16 tests Swift ciblés et 10 tests Admin réussis ; lint ciblé et build Admin
  réussis. Pas de nouvelle installation iPhone.

## Regroupement TRPF 13 validé — 7 octobre 2026, 22:34

- Accord utilisateur : Vis TRPF 13, variante solidarisation des montants et
  variante fixation des suspentes regroupées sous Vis TRPF 13. Calculs par
  usage conservés et quantités additionnées ; TRPF 25 distinctes.
- Admin commit `7aef862` sur main, déploiement Vercel réussi ; libellés des deux
  composants vérifiés sur le catalogue public. Renommage ciblé des anciennes
  fiches via le mécanisme de publication commun, sans changement de coefficient.
- iOS : consolidation des anciennes sauvegardes et noms du formulaire plafond
  rails/montants harmonisés. 15 tests Swift ciblés et 9 tests Admin réussis,
  compilation Admin réussie. Pas de nouvelle installation iPhone.

## Regroupements validés — 7 octobre 2026, 22:29

- Accord utilisateur : Bande PP grand rouleau → Bande à joint ; Vis TTPC 35 mm
  (2e parement) → Vis TTPC 35. Coefficients inchangés ; consolidation iOS des
  anciennes et nouvelles appellations sans perte de quantité. Les vis 25/45/70
  restent distinctes. Libellé de repli de la cloison alvéolaire harmonisé.
- Admin : commits `930d76a` et `ee63020` poussés sur main, déploiements Vercel
  réussis. Deux appellations contrôlées sur le catalogue public de production.
- Vérification : 14 tests Swift ciblés et 8 tests Admin réussis, build Admin
  réussi. Code iOS non réinstallé depuis ces regroupements ; aucune autre
  famille fusionnée sans validation.

## Publication Admin — 7 octobre 2026, après installation

- Admin main : commit `8b59f5c`, déploiement Vercel réussi. Catalogue public
  contrôlé : peinture révision `2026-10-07.2`, réserve 10 %, Airless 0 %,
  épaisseurs rebouchage 10–50 mm, garnissant 1–5 mm, finition 0,5–1 mm.
- Libellés F45/F47, TTPC 25 et enduits à joints vérifiés en production.
  Transformation ciblée des anciennes fiches à la lecture publique, sans
  écraser les coefficients personnalisés ; persistance prévue à l’ouverture
  authentifiée d’Admin (non déclenchée pendant cette publication).
- Six tests Admin réussis, lint ciblé et build webpack réussis.
- Audit de doublons demandé : aucun nouveau regroupement sans validation.
  Premier candidat : Bande PP grand rouleau (plafond fourrures et cloison
  alvéolaire) / Bande à joint. Autres candidats à examiner : TTPC 35,
  TRPF 13 selon usage, Demi collier / Demi-collier, suspentes hourdis à griffe,
  cornières (dimensions et unités à vérifier avant tout regroupement).

## Installation iPhone — 7 octobre 2026, 22:11

- Dernière série peinture progressive, renforts d’ouvertures et quantitatif
  compilée en Debug signé (équipe U6X2KSN84X) et installée sur l’iPhone 16 Pro
  d’Edouard, bundle `fr.plaquisto.app`, séquence **3848**.
- Journal : `/tmp/plaquisto-oct7-latest-install-build.log` (BUILD SUCCEEDED).
- Lancement automatique refusé car l’iPhone est verrouillé ; installation
  confirmée, ouverture manuelle possible après déverrouillage.
- Installation uniquement : changements non poussés et nouvelles bases Admin
  toujours non publiées. Les vérifications de la série sont détaillées ci-dessous.

## Peinture progressive, ouvertures et quantitatif projet — 7 octobre 2026, soir

- Formulaire peinture : choix indépendants ratissage / impression / finition en
  première étape ; seules les étapes retenues sont présentées. Trois vignettes
  rouge/verte/bleue pour les enduits ; ajout et suppression de passes dans une
  même étape, chacune avec son pourcentage et sa présentation poudre/pâte.
  Rebouchage 1–5 cm par cm, garnissant 1–5 mm par mm, finition 0,5 ou 1 mm.
  Rendements peinture par pas de 1 m²/L. Airless retiré des nouvelles saisies ;
  réserve générale 10 % conservée. Les snapshots historiques conservent leurs
  calculs jusqu’à une édition explicite (nouvelle saisie sans Airless).
- Depuis Ajouter un ouvrage, un projet contenant un relevé propose d’y choisir
  les surfaces ou de saisir les dimensions. Le type et le nom choisis sont
  conservés, avec choix du relevé si plusieurs sont disponibles.
- Tapée non demandée dans les formulaires : estimation isolant + parements
  (+15 mm pour lisses/fourrures), épaisseur de parement enregistrée depuis les
  choix catalogue. Les anciennes profondeurs mesurées explicitement priment.
  Estimation accessible à SurveyPlanFinishes et contrôles de menuiserie liés.
- Calepinage des doublages liés à un ouvrage : renforts fixes à 50 mm à l’axe
  autour des ouvertures, montants/rails ou fourrures/cornières selon système.
  Fourrures courtes alignées aux bords des fenêtres en lisses/fourrures ; pas de
  traverse ni de tronçon bas pour les portes. Profils découpés au contour réel.
  Appuis représentés selon le nombre de lignes d’appuis du formulaire ; les
  renforts ne suivent pas la translation de la trame. Aimantation de celle-ci
  aux renforts latéraux, soustraction des profils superposés pour les fusionner.
  Les plaques se calent sur la trame régulière la plus proche, pas les renforts.
- Quantitatif projet : Tout sélectionner / Tout désélectionner et partage natif
  d’un fichier texte consolidé, avec ouvrages inclus et avertissements source.
  Aliases F45/F45-F47 et TTPC 25/25-ou-35 homogénéisés, sans fusion des vraies
  vis TTPC 35. Enduit à joints en poudre/pâte renommé avec accord utilisateur.
  Regroupement des plaques 260/270 abandonné à sa demande.
- Autres doublons proposés, NON fusionnés : Bande PP grand rouleau / Bande à
  joint ; Vis TTPC 35 mm (2e parement) / Vis TTPC 35 ; libellés TRPF 13 par usage.
- Vérification : **391 tests Swift réussis**, **3 tests Admin réussis** ; build
  iOS appareil non signé réussi et build Next.js webpack réussi. Simulateur :
  choix du relevé/type plafond conservé, formulaire et ajout de passe contrôlés,
  sélection des trois ouvrages en un clic, noms consolidés, feuille de partage
  avec Enregistrer dans Fichiers. Aucune sauvegarde de formulaire test créée.
- Journaux : `/tmp/plaquisto-oct7-changes-tests-final.log`,
  `/tmp/plaquisto-oct7-changes-device-build.log`,
  `/tmp/plaquisto-admin-oct7-changes-build.log`.
- **Non installé sur l’iPhone, non commité/poussé, Admin non redéployé** pour
  cette nouvelle série. Dernière installation physique ci-dessous inchangée.

## Installation iPhone peinture + DAE — 7 octobre 2026, 08:10

- Compilation Debug signée réussie, installation confirmée sur l’iPhone 16 Pro
  d’Edouard, bundle `fr.plaquisto.app`, séquence d’installation **3840**.
- Inclut Peinture et ratissages (bases Admin 5.1 publiées), réserve 10 % et
  Airless 5 %, ainsi que le correctif DAE et son bouton visible sous la maquette.
- Dernière suite : 383 tests Swift réussis. Journal de compilation :
  `/tmp/plaquisto-painting-dae-install-build.log`.

## Publication Admin peinture — 7 octobre 2026

- À la demande de l’utilisateur, changements Admin commités et poussés sur
  `Plaquisto-admin/main` : `d7ed23a`. Déploiement Vercel de production réussi.
- Catalogue public `https://plaquisto-admin.vercel.app/api/ios/catalogue`
  vérifié en version **5.1** : six enduits conformes, rendement 8–12 m²/L,
  réserve 10 %, Airless 5 %. Les rubriques existantes restent présentes.
- Les coefficients sont désormais disponibles à iOS. La présence des deux
  nouvelles fiches physiques dans Supabase n’a pas été vérifiée : le catalogue
  possède le repli publié prévu, et l’ouverture authentifiée d’Admin insère les
  fiches manquantes selon son workflow existant. Aucun accès administrateur à
  la base n’a été utilisé pour cette publication.
- Application iPhone non installée pendant cette publication.

## Peinture et ratissages + correctif DAE — 7 octobre 2026

- Nouveau formulaire en trois étapes : ratissage, peinture, quantitatif. Jusqu’à
  trois passes indépendantes : type d’enduit poudre/pâte, épaisseur au curseur,
  traitement intégral ou pourcentage de surface propre à chaque passe.
- Impression facultative, finition 1–3 couches, rendement en **m²/L** (8–12
  dans les bases initiales), nom et teinte facultatifs. Ratissage sans peinture
  possible. Catalogue personnel de noms/rendements conservé sur l’appareil.
- Réserve générale **+10 %** pour tous les consommables ; Airless **+5 %**
  uniquement sur les peintures, avant réserve : **×1,155** au total.
- Moteur de calcul partagé formulaire/quantitatif projet. Chaque ouvrage garde
  les règles Admin utilisées, ses choix par passe et ses teintes. Un recalcul
  de surface issue d’un relevé conserve ces choix et déduit les ouvertures.
- Identifiant historique `peinture-beta` maintenu pour les sauvegardes ; tous
  les libellés d’ouvrage deviennent « Peinture et ratissages ». Une ancienne
  sauvegarde de surface seule reste lisible, sans inventer de consommables.
- Plaquisto Admin : nouvelle famille, fiche de coefficients éditable, contrat
  `peintureRatissages.regles.data`, validation de PATCH/PUT, tests de contrat.
  Aucun coefficient de production codé en secours dans iOS : téléchargement,
  cache validé et copie dans l’ouvrage. Sans base disponible, message Réessayer.
- Contrôle visuel au simulateur des trois étapes avec fixture Admin locale,
  trois passes et Airless ; aucun ouvrage de test sauvegardé. Fixture temporaire
  retirée après contrôle. Arrondi supérieur corrigé pour ne pas afficher 23,2 L
  au lieu de 23,1 L à cause des erreurs binaires flottantes.
- Export DAE : triangles d’aire nulle aux pointes des sols/plafonds retirés avant
  génération des normales, sans retirer de surface. Les vraies erreurs restent
  bloquantes avec identification de la surface ; pas d’export partiel silencieux.
  Bouton « Exporter DAE » directement visible sous la maquette, partage iOS vérifié.
  Sous-agent : 8/8 relevés iPhone raccordés exportés, ancien relevé non raccordé
  toujours bloqué explicitement. Diagnostics privés non ajoutés au dépôt.
- Vérifications : **383 tests Swift réussis**, **2 tests de contrat Admin réussis**, lint ciblé, compilation
  iPhone non signée et compilation Admin Webpack (Turbopack échoue sur le lancement
  du processus Node dans cet environnement). Logs `/tmp/plaquisto-painting-*.log`.
- **Non publié / non installé** : les modifications Admin doivent être déployées
  pour rendre la nouvelle rubrique disponible sur un iPhone sans cache. Pas de
  déploiement, commit, push ou installation physique pendant cette tâche.

## Accueil en vignettes, recherche et export DAE — 6 octobre 2026

- Accueil Projets en cartes adaptatives : miniature 3D du dernier scan, sinon
  résumé des surfaces par famille d’ouvrage (pas de double comptage des peaux).
  Nom, adresse et date du scan/de création affichés ; duplication et suppression
  confirmée accessibles dans le menu de chaque carte.
- Recherche locale par nom, client, adresse, ville, code postal, nom du relevé et
  dates françaises/ISO ; indépendante de la casse et des accents. Les adresses
  issues des positions de capture sont résolues séquentiellement puis conservées
  dans `captureAddress`, sans écraser l’adresse du projet. Hors réseau, les
  adresses déjà enregistrées restent recherchables. Aucun GPS courant utilisé.
- Date de capture conservée explicitement (`capturedAt`) pour les nouveaux
  relevés. Anciens relevés : position GPS, métadonnées originales, puis date de
  création en repli ; une date sentinelle Unix zéro n’est pas affichée comme scan.
- Export depuis le menu du relevé : « Exporter le relevé en DAE », puis feuille
  de partage iOS directe. COLLADA 1.4.1 autonome, mètres/Y vertical, matériaux
  simples, normales, murs et ouvertures, sols et plafonds existants/édités.
  Aucun plafond inventé ; aucune caméra, sélection ou texture externe exportée.
  Épaisseur des murs exportée seulement si connue, contrairement à l’épaisseur
  illustrative du visualiseur. Les zones non raccordées sont explicitement
  refusées, sans appliquer la séparation artificielle de l’aperçu.
- Sérialisation sur tâche de fond, instantané immuable, fichier temporaire unique
  conservé pour la feuille de partage. Aucun envoi automatique ni modification du
  relevé. SceneKit ne fournit pas l’écriture DAE sur iOS : exporteur XML portable.
- Miniatures statiques 576 × 432, cache plafonné à 12 Mio, pas de scène animée par
  carte. Compatibilité Codable conservée pour les anciennes sauvegardes.
- Validation : **373 tests réussis**, compilation simulateur et compilation iOS
  réussies. Logs `/tmp/plaquisto-gallery-dae-verified-tests.log` et
  `/tmp/plaquisto-gallery-dae-device-build.log`. Exemple DAE validé contre le XSD
  COLLADA officiel Khronos, puis réimporté par SceneKit macOS (5 maillages).
  Pas de vérification dans SketchUp ni d’envoi Mail réel revendiqués.
- Contrôles simulateur : cartes avec/sans scan, recherche nom/date, feuille de
  partage présentant le fichier comme ressource 3D. Partage fermé sans envoi.
  GPS/adresses couverts par les tests de recherche ; aucun nouveau scan réel ni
  géocodage terrain effectué pendant cette vérification.
- **Installé sur l’iPhone 16 Pro le 6 octobre 2026 à 23:17**, bundle
  `fr.plaquisto.app`, séquence CoreDevice `3784`. Compilation signée réussie
  (`/tmp/plaquisto-gallery-dae-install-build.log`). Lancement automatique refusé
  parce que l’iPhone était verrouillé (`Locked`). Aucun commit/push pour ce lot.

## Plan plein écran et aperçu permanent des spots — 6 octobre 2026

- Éditeur de plan : rotation de la vue au mur suivant en haut à gauche en mode
  Vue ; plein écran en haut à droite, recentrage dans son menu contextuel.
  Zoom conservé, transformation inverse appliquée aux gestes d’édition ; aucun
  changement de géométrie par la rotation. Cadrage initial différé jusqu’à une
  taille de fenêtre valide pour éviter un plan minuscule à l’ouverture.
- Électricité des plafonds : seule la répartition automatique reste dans les
  commandes, retrait des organisateurs avancés et de l’ajout manuel. Les commandes
  des équipements muraux restent inchangées.
- Répartition automatique : aperçu fixe au-dessus du formulaire défilant,
  déplacements du groupe sur cet aperçu, choix du nombre et des variantes,
  deux curseurs et rotation 90° conservés. Pas de bouton « Centrer tous les spots ».
- Vérification simulateur : rotation successive et plein écran, aperçu toujours
  visible après défilement, 6/12 spots, variante 4 × 3 et rotation 90°. Les poses
  hors support ne peuvent pas être appliquées. Changements de test non enregistrés.
  Les glissements physiques via le pilotage du simulateur restent intermittents ;
  le défilement a aussi été contrôlé via son action d’accessibilité.

## Lisibilité et suppression dans l’éditeur de plan — 6 octobre 2026

- Curseur de tracé/pose de porte déporté de 64 points vers la gauche et 18 vers
  le haut (au lieu de 38 horizontalement), borné au cadre et indépendant du zoom.
- Présentation rapprochée du calepinage : onglets en capsule, plan arrondi avec
  marges, commandes rondes de 44 points sur fond translucide autour du dessin
  (aimantation, recentrage, annulation, dimensions et suppression contextuelles).
- Sélection d’une porte sur toute sa réservation, pas seulement son centre.
  Corbeille directe avec confirmation ; suppression de cloison limitée aux
  cloisons conçues dans l’app, avec retrait de leurs ouvertures et liens locaux.
  Scan original et plafonds conservés ; aucune fusion implicite de plafonds.
  L’annulation restaure le document complet avant suppression.
- En mode Ouvertures, aucune suppression de cloison proposée à la place de la
  porte après son retrait : la sélection est explicitement effacée.
- Contrôle simulateur : tracé temporaire, curseur déporté, suppression/restauration
  de cloison et de porte vérifiés, changements de test abandonnés sans sauvegarde.
  Deux tests de régression ajoutés ; **365 tests réussis**, revalidation finale
  et compilation simulateur réussies : `/tmp/plaquisto-editor-polish-final-tests.log`.
- Ajustements **installés le 6 octobre 2026 à 22:25** sur l’iPhone 16 Pro,
  séquence CoreDevice `3776`. Compilation signée réussie
  (`/tmp/plaquisto-editor-polish-device.log`). Lancement automatique refusé
  uniquement parce que l’iPhone est verrouillé (`Locked`). Aucun commit/push.

## Éditeur de plan et spots simplifiés — 6 octobre 2026

- Éditeur : modes Vue / Cotes / Cloisons / Ouvertures, navigation à un doigt en
  Vue, déplacement à deux doigts et pincement dans les modes d’édition. Tracé de
  cloison par points avec confirmation, continuation et annulation du tracé ;
  épaisseur 72 mm par défaut, préréglages et saisie libre. Réservations de portes
  73/83/93 cm ou saisie libre, cotes latérales tenant compte des épaisseurs.
- Tapées de doublage jusqu’au parement fini renseignables dans les formulaires ;
  représentation sur le plan et parcours vers la création/modification du doublage
  avant reprise du tracé. Zones fermées avec surface ; proposition de division du
  plafond existant conservant ses plans via la filiation des composants.
- Correction ou redessin du contour d’une pièce via l’éditeur partagé, sans
  décalage de bords de plaque ; confirmation des conséquences sur les ouvertures.
  Données du scan original conservées, refus des cas de contours partagés ambigus.
- Spots automatiques : 1/2/3/4/6/8/9/10/12, 2 et 3 sur une rangée ; 9 en 3×3,
  10 en 5×2, 12 en 6×2 / 4×3 / 3×4. Deux écartements indépendants, rotation
  de 90° par rapport aux fourrures, conservation des ajustements manuels et des
  anciennes sauvegardes (y compris groupes manuels de 5/11 et diamètres existants).
- Validation intégrée : **363 tests réussis, aucun échec**, compilation simulateur
  réussie ; journal `/tmp/plaquisto-spots-integrated-tests.log`.
- Pilotage du simulateur : l’erreur `noWindowsAvailable` sur les actions par
  coordonnées a disparu après déplacement de sa fenêtre sur l’écran intégré du Mac.
  Cinq glissements consécutifs du plan vérifiés visuellement. Ce contrôle ne remplace
  pas une validation tactile sur iPhone des gestes à plusieurs doigts.
- Lot complet **installé le 6 octobre 2026 à 22:04** sur l’iPhone 16 Pro,
  bundle `fr.plaquisto.app`, séquence CoreDevice `3768`. Lancement confirmé à
  22:05. Compilation iPhone signée réussie ; journal
  `/tmp/plaquisto-install-oct6-complete.log`. Aucun commit ni push pour ce lot.

## Calepinage rapide depuis un scan et division des plafonds — 2 octobre 2026

- L’outil autonome s’appelle « Calepinage 2D rapide ». Les calepinages liés aux
  ouvrages gardent leur titre. Les arcs et pointillés des icônes d’angle emploient
  désormais la couleur d’accent commune aux outils.
- Depuis l’accueil du calepinage autonome : « Scanner un mur ou un plafond »
  réutilise la capture RoomPlan existante, puis la maquette et son éditeur de
  plafonds. Sélection d’une seule surface et ouverture directe du calepinage,
  sans création de projet ni d’ouvrage. Contour développé et ouvertures conservés ;
  sauvegarde dans la bibliothèque autonome, rafraîchie au retour du scanner.
  Le scan reste récupérable dans les relevés non classés.
- Une division explicite de plafond dans le relevé met à jour les composants
  d’ouvrage liés : chaque partie hérite des plans enregistrés, dans le repère local
  du parent, avec orientation/décalage/quinconce des plaques et phase des fourrures
  conservés. Les plans sont découpés, pas réinitialisés. Spots répartis sans doublon
  sur la séparation. Le périmètre physique d’origine est gardé pour les fourrures
  fixes à 10 cm, sans en inventer sur la séparation artificielle.
- L’historique de filiation couvre plusieurs divisions avant un même enregistrement
  ainsi que les divisions après réouverture. La transaction est refusée si le
  calepinage a un contour modifié manuellement incompatible ou une révision périmée.
  Ce mécanisme ne s’applique pas automatiquement aux rescans ni aux changements
  de hauteur/inclinaison. Les liens plafond–mur du composant divisé sont invalidés
  car ils ne désignent plus nécessairement un bord complet. Les quantités approuvées
  ne sont pas remplacées sans la confirmation habituelle de l’utilisateur.
- Validation : **350 tests réussis**, incluant plafonds plats/rampants, grille
  décalée en quinconce, repère d’ossature indépendant, conservation du métrage,
  divisions répétées et sauvegarde/rechargement. Compilation simulateur et iPhone
  signée réussie. Journaux : `/tmp/plaquisto-split-quick-tests.log` et
  `/tmp/plaquisto-split-quick-device.log`.
- Contrôle visuel : lancement du simulateur en thème clair vérifié. Suite de
  navigation interrompue par une erreur de contrôle du simulateur ; capture LiDAR
  réelle non testable sur simulateur. À vérifier sur l’iPhone.
- Installation : première tentative du 2 octobre bloquée par la déconnexion.
  **Installé le 6 octobre 2026 à 21:02** sur l’iPhone 16 Pro, bundle
  `fr.plaquisto.app`, séquence CoreDevice `3744`. Reconstruction signée réussie
  après renouvellement automatique du profil (expiration : 13 octobre 2026).
  Journal : `/tmp/plaquisto-install-oct6-build.log`. Signature vérifiée valide
  sur disque. Lancement refusé par iOS (signature/entitlements/confiance du profil) ;
  validation du développeur sur l’iPhone à vérifier. Aucun commit ni push.
- Les quatre propositions de refonte claire ont été livrées séparément dans la
  conversation. Elles ne sont pas intégrées dans ce lot iOS. Deux profils artisan
  simulés ont parcouru l’app en lecture seule : recommandations principales,
  miniatures de scans, recherche projet/ville, date explicite du scan et reprise
  des relevés non classés. Aucune modification de l’accueil n’a été faite pour elles.

## Orientation de la vue plafond et thème clair — 1er octobre 2026

- Bouton circulaire en haut à gauche, uniquement en mode Vue d’un plafond
  (plein écran compris) : parcourt les bords et les aligne successivement sur
  l’horizontale. Rotation de caméra uniquement ; ni géométrie ni référence de
  pose des plaques/fourrures modifiée. Zoom conservé, déplacement limité par le
  cadre de visibilité existant. Aucun bord surligné en mode Vue.
- À l’ouverture d’un plafond, orientation paysage du dessin : référence des
  plaques privilégiée si elle donne un contour plus large que haut ; sinon
  choix d’un bord offrant une présentation plus horizontale. Après cette
  initialisation, orientation libre via le bouton, indépendante de la référence
  de pose. Changer de mode ne réinitialise ni rotation ni zoom.
- Thème clair imposé à la racine de l’app iOS, y compris les présentations.
  Suppression de l’exception de thème sombre du mode photo ; son fond caméra
  noir et ses commandes blanches restent intentionnels, indépendants du thème.
- Vérifications de régression : cycle des bords, vues dessus/dessous, zoom et
  précision des coordonnées, bord nul, référence courte et ouverture paysage.
  **348 tests réussis**, compilation iPhone signée réussie. Journaux du lot : `/tmp/plaquisto-view-day-tests.log` et
  `/tmp/plaquisto-view-day-device.log`.
- Ce lot est inclus dans l’installation du 6 octobre 2026 décrite ci-dessus.
  Aucun commit ni push.

## Calepinage, implantation et correctifs rails/montants — 1er octobre 2026

- Sélection des sous-parties par grille de vignettes : maquette du relevé avec
  surface concernée sélectionnée, aperçu 2D de secours pour les composants manuels.
- Interface iOS verrouillée en portrait, sans modifier les poses AR du scanner.
- Plafonds sur fourrures sans cornière : supports fixes à 100 mm des bords
  parallèles (tolérance angulaire 15°), découpés aux ouvertures et conservés lors
  du déplacement de la trame. Métrage et suspentes inclus dans la reprise du
  quantitatif, avec la même règle d’espacement que les autres fourrures.
- Aimantation de la trame aux joints de plaques ; longueurs calculées pendant
  le glissement. Distances mur/fourrure de jonction déportées hors contour et
  éditables numériquement : déplacement de toute la trame, pas des supports fixes.
  Affichage des cotes au maximum à une décimale, précision interne conservée.
- Spots : dispositions 1/2/3/4/5/6/8, axes liés aux fourrures, bascule 90°,
  sélection par rectangle et commandes d’alignement/distribution/centrage/entraxe.
- Les ouvertures scannées étaient déjà conservées et déduites par union de leur
  surface. Le formulaire des doublages affiche désormais leur nombre et la
  surface déjà déduite, sans une seconde déduction ni changement de RoomPlan.
- Correction isolants rails/montants : le catalogue publié fournit `conductivity`
  (ex. « λ ≈ 0,035 »), pas systématiquement `lambda_w_mk`. Le décodeur partage
  désormais la lecture du lambda du formulaire fourrures. Ajout/modification
  de l’isolation accessible au récapitulatif même si aucun isolant n’était prévu.
- Premier calepinage d’un ouvrage plafond dimensionné : longueur et largeur
  du formulaire reprises en mm. Pas de rectangle inventé depuis la surface
  seule ; pas de remplacement des composants scannés/plans enregistrés, ni de
  duplication des dimensions globales dans chaque nouvelle sous-partie.
- Validation : **346 tests réussis**, dont décodage du catalogue réel (lambda
  textuel), reprise des dimensions, supports périphériques fixes, saisie des
  distances, aimantation, dispositions des spots et déduction des ouvertures.
  Compilation iPhone signée réussie avec équipe `U6X2KSN84X`.
  Journaux : `/tmp/plaquisto-refinements-tests.log` et
  `/tmp/plaquisto-refinements-device.log`. Vérification visuelle du sélecteur
  de sous-parties, des cotes et du formulaire rails/montants dans le simulateur :
  isolant laine de verre, lambda, épaisseur et résistance disponibles, passage
  à l’étape suivante débloqué. Gestes réels, grandes scènes
  scannées et performances à confirmer sur l’iPhone.
- Lot installé sur l’iPhone d’Edouard le 1er octobre à 23 h 17 :
  `fr.plaquisto.app`, séquence d’installation **3504**, confirmation `devicectl`.
  Aucun commit ni push effectué.

## Plafonds automatiques après scan — 1er octobre 2026

- Après le traitement final RoomPlan, création directe d’un plafond par contour
  fermé disponible, avec les mêmes réglages et géométries que le configurateur.
  Aucun écran de proposition ni validation jaune/verte pendant l’acquisition.
- Sélection horizontal / rampant / deux pans d’après les profils supérieurs
  natifs des murs. Une pente automatique exige une couverture suffisante, une
  variation d’au moins 20 cm, un bon accord avec les profils et une amélioration
  significative par rapport à une forme plus simple. Deux pans nécessitent des
  observations sur les deux pentes ; les hauteurs maximales des murs seules ne
  permettent pas d’inventer un faîtage. Bruit ou ambiguïté : horizontal par défaut.
- Réutilisation de `CeilingAutoFit` et `WallCeilingEstimate.applying` : réglages
  sauvegardés, chaque plafond reste éditable séparément. Provenance estimée
  conservée dans les données, sans le présenter comme une mesure LiDAR directe.
- Murs, ouvertures, repère AR et `initialRoom` inchangés. Aucun plafond existant
  n’est remplacé. Les contours ouverts/inexploitables restent à traiter dans
  l’éditeur. Pas de régénération rétroactive des anciens relevés sauvegardés.
- Ajustement hors du thread principal, après arrêt de l’acquisition. Annulation,
  changement de capture et expiration du délai empêchent un résultat tardif de
  remplacer le relevé courant. Les checkpoints natifs restent récupérables.
- Vérification : **336 tests réussis**, dont 10 nouveaux tests (formes, rotation,
  faîtage décentré, bruit/pic isolé, plusieurs pièces, préservation, édition,
  sauvegarde/relecture et annulation). Compilation iPhone signée réussie.
  Journaux : `/tmp/plaquisto-auto-ceilings-all-tests.log` et
  `/tmp/plaquisto-auto-ceilings-device.log`.
- Installation iPhone confirmée le 1er octobre à 21 h 27 : `fr.plaquisto.app`,
  séquence **3496**. L’ouverture automatique a été refusée car l’iPhone s’est
  reverrouillé ; lancer l’app manuellement. À tester sur un nouveau scan réel.
  Aucun commit ni push effectué.

## Installation iPhone — 28 septembre 2026, 22 h 46

- Lot calepinage et quantitatif affiné installé sur l’iPhone d’Edouard après
  déverrouillage : `fr.plaquisto.app`, séquence d’installation **3300**.
- Compilation signée actualisée réussie (`/tmp/plaquisto-layout-install-build.log`).
  Installation et lancement confirmés par `devicectl`. Aucun commit ni push effectué.
- Les mentions « non installé » des sections antérieures décrivent leur état
  avant cette installation ; les gestes restent à essayer sur l’iPhone réel.

## Calepinage, commandes et quantitatif affiné — 28 septembre 2026

- Miniatures des ouvrages issus d’un relevé : surfaces concernées mises en
  évidence, cache distinct par sélection et thème. Acquisition du scan inchangée.
- Parements du plan : sélection par famille, fonction et formats du référentiel,
  avec 4BA déduit du produit ; plus de choix manuel des bords, de sens de pose ni
  de coordination dans le formulaire « Plaques et pose ».
- Commandes du plan : parallèle/perpendiculaire et changement de mur de référence
  pour plaques et ossature indépendamment ; icône quinconce dessinée. Rotation
  tactile du support retirée dans tous les modes. Vue plafond dessous/dessus par
  miroir de caméra uniquement, dessous par défaut, géométrie conservée.
- Glisser depuis l’extérieur du support déplace la vue en modes plaques/ossature ;
  glisser depuis l’intérieur déplace la grille concernée. Plaques grises avec
  contours renforcés. Fourrures de jonction en trait continu renforcé, distances
  aux murs visibles avec les cotes d’ossature. Optimisation des fourrures sans
  déplacement des plaques et sans perdre une phase déjà calée sur les joints.
- Modifier le contour : sommets par défaut, bouton dédié au décalage des bords,
  conservation des décalages en revenant aux sommets, cible supprimée.
- Le formulaire plafond sur fourrures demande « Fixer une cornière en périphérie »
  à l’étape de l’entraxe. Sans cornière, estimation des suspentes supplémentaires
  aux extrémités dans le formulaire, remplacée par les segments réels du plan
  lorsqu’un quantitatif affiné est accepté.
- À l’enregistrement d’un plan lié à un plafond, proposition explicite de reprise
  des quantités : plaques achetées après réemploi +10 % (arrondi par format),
  profilés posés +10 %, périmètre cornières/rails +10 %. Suspentes tous les 1,20 m
  pour fourrures ; distances sauvegardées du configurateur pour rails/montants.
  Les extrémités sur une périphérie porteuse ne rajoutent pas de suspentes ; les
  extrémités libres et celles des ouvertures en prévoient. Portée autoportante
  contrôlée ; montants doubles comptés deux fois en longueur, pas en suspentes.
- **Correction demandée : aucun besoin d’avoir tous les plans.** La fraction de
  surface calepinée remplace sa part de l’estimation du formulaire ; la surface
  restante conserve cette estimation. La surface totale de l’ouvrage ne diminue
  pas. Prise en compte par peau pour fourrures ; pour rails/montants, les plaques
  d’une sous-partie restent estimées si ses deux peaux ne sont pas calepinées,
  mais son ossature peut être affinée. Les fournitures non concernées conservent
  le calcul du formulaire. Les choix techniques du formulaire ne sont pas réécrits.
- Les quantités approuvées sont sauvegardées séparément. Refuser leur actualisation
  conserve le dernier quantitatif approuvé avec un avertissement si le plan a changé.
  Modifier la configuration technique invalide cet instantané et rétablit le calcul
  du formulaire. Recalcul déterministe, pas d’accumulation à chaque sauvegarde.
- Limites : reprise automatique limitée aux deux familles de plafonds ; ne constitue
  pas une validation de dimensionnement. Ancien formulaire rails/montants à réenregistrer
  pour récupérer ses distances et composants de suspension. Pas d’installation,
  de commit ou de push de ce lot pour l’instant.
- Vérification : 326 tests réussis, compilation iPhone signée réussie.
  Journaux `/tmp/plaquisto-layout-quantity-verified-tests.log` et
  `/tmp/plaquisto-layout-quantity-verified-device.log`. Contrôle visuel simulateur :
  miniature sélectionnée, commandes plaques grises/dessous, famille/fonction 4BA
  et dimensions, cornière visible à l’étape 4 « Entraxe et plénum ».
  Gestes tactiles réels (dont multipoint) restant à contrôler sur iPhone.

## Correctifs parement d’ouvrage et plein écran — 28 septembre 2026

- Le calepinage créé depuis un ouvrage conserve maintenant la référence exacte
  du parement (produit + dimensions), et pas uniquement son format et un booléen
  4BA. Identifiant partagé avec le parseur du catalogue ; libellé « Type de parement ».
- Résolution lors de l’ouverture, de la création du support et du chargement du
  catalogue. Reprise des anciens plans liés dont la référence manque, sans modifier
  leur géométrie, leur grille ni leur ossature. Le choix explicite « Saisie manuelle »
  est mémorisé et ne sera pas remplacé par celui de l’ouvrage. Un autre parement
  choisi dans le calepinage reste prioritaire. La propriété 4BA est sauvegardée et
  utilisable hors connexion une fois connue ; aucune déduction par la taille seule.
- Plein écran : actions Optimiser/Caler visibles en modes Plaques et Ossatures ;
  Répartition automatique/Ajouter à la main visibles en Électricité, même après
  ajout de points. Les commandes d’organisation existantes restent accessibles.
- Pincement rétabli en Électricité pour le zoom uniquement, sans rotation des
  spots (demande utilisateur explicite). Rotation tactile des spots retirée du
  plan principal ; moteur de rotation conservé pour un futur travail d’ergonomie.
  Le calcul de la limite de déplacement après pincement conserve l’échelle de référence.
- Vérifications : 317 tests réussis (5 régressions supplémentaires), compilation
  iPhone signée réussie. Journaux `/tmp/plaquisto-facing-fullscreen-final-tests.log`
  et `/tmp/plaquisto-facing-fullscreen-final-device.log`. Contrôle simulateur des
  trois modes plein écran, actions après ajout d’un spot, et libellé Type de parement.
  Le geste multipoint reste à essayer sur iPhone réel. Correctifs non installés,
  non commités et non poussés ; dernière installation : lot précédent, séquence 3260.

## Parcours relevé, bords 4BA et navigation du calepinage — 27 septembre 2026

- Travail isolé sur `codex/survey-layout-refinements`, depuis `main` (`d789837`).
  Acquisition RoomPlan, données des relevés et plafonds existants inchangés.
- Entrée plafonds : sélecteur « Choisir un plafond » directement, sans afficher
  l’éditeur de cloisons en arrière-plan. Création/modification de plusieurs zones,
  séparation et enregistrement explicite conservés. Le bouton de configuration
  est superposé dans la maquette ; suppression des deux bandeaux demandés.
- Création depuis des plafonds sélectionnés : fourrures OU rails/montants,
  surface nette exacte verrouillée, contours et ouvertures conservés. Les
  métrés sur rails/montants restent estimatifs avec une surface seule ; le
  formulaire l’explique. Vérifications de géométrie et non-double-attribution
  conservées, case de confirmation manuelle retirée. Après création d’un ouvrage,
  fermeture du parcours et navigation vers son projet via un événement transitoire.
- Calepinage : Vue permet de toucher une plaque pour ouvrir ses cotes/découpes.
  Bouton rond de quinconce en haut à gauche et changement de mur de référence
  uniquement en mode Plaques. Rotation du sens/référence suivie d’une optimisation
  asynchrone ; une modification rapide pendant le calcul relance sur le dernier état.
- Réemploi automatique sans interrupteur ni texte sur les 20 cm. Règles
  d’appui et seuil de 200 mm conservés dans le moteur. Règle utilisateur 4BA :
  chaque jonction doit rester sur un bord d’usine de la plaque brute ; les
  découpes restent possibles en périphérie et autour des ouvertures. Cette règle
  supplémentaire n’est pas appliquée aux plaques 2BA. Placement des chutes dans
  les quatre coins possibles des espaces libres, sans rotation, sans chevauchement.
  Métadonnée 4BA conservée dans les configurations et plans ; reprise du catalogue
  par identifiant produit pour les anciens ouvrages, choix explicite en format manuel.
- Repères numérotés le long du grand côté, puis bande suivante. Les petites
  pièces reçoivent un numéro déporté avec trait de rappel et évitement des autres
  numéros quand l’espace le permet. Les coordonnées de découpe restent inchangées.
- Navigation 2D du relevé : cache des tracés/étiquettes hors des mouvements.
  Éditeur de cloisons : glissement direct, séparation du tap et du drag, absence
  d’animation implicite ; validations métier toujours au relâchement.
- Échelle d’affichage indépendante de la hauteur disponible : changer de mode
  ne dézoome plus. Plein écran depuis le bouton remplaçant la cible : barres de
  navigation/onglets et réglages inférieurs masqués, modes et visibilité conservés.
  Sortie par le même bouton. Recentrage dans le menu et par appui long sur ce bouton.
- Vérifications : 312 tests réussis (9 nouveaux), comprenant bords d’usine avec
  quinconce/ouvertures/référence tournée, découpe réalisable et réemploi en périphérie,
  choix rapides d’orientation, numéros déportés, zoom stable, rails/montants depuis
  relevé et routage projet. Journaux `/tmp/plaquisto-survey-refinements-verified.log`
  et `/tmp/plaquisto-survey-refinements-device.log` (compilation iPhone signée).
  Contrôle simulateur : Vue ouvre une plaque, commandes limitées à Plaques,
  quinconce/optimisation, plein écran et sélecteur direct cuisine/salon.
  Preuve autonome : `/tmp/plaquisto-survey-refinements-proof.log`.
  Fluidité tactile réelle et pincement à revalider sur iPhone ; aucun scan réel
  ni essai terrain ajouté. Application installée et lancée sur l’iPhone d’Édouard
  le 27 septembre à 23 h 56, sans effacement des données (séquence 3260).
  Reçus : `/tmp/plaquisto-survey-refinements-install.json` et
  `/tmp/plaquisto-survey-refinements-launch.json`. Ce lot reste non commité/non poussé.

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
