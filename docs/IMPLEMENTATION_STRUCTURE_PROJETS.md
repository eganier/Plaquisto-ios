# Structure des projets — premier lot implémenté

Date : 18 septembre 2026. Branche : `codex/tools-lab-improvements`.

Ce document décrit le code de ce lot, pas l'ensemble de l'architecture cible.
L'intégration complète au scan 3D et aux médias reste à réaliser.

## Données persistées

`ProjectItem.rooms` contient des `ProjectRoomRecord` identifiés par UUID.
Le nom est un libellé modifiable, jamais une clé de rattachement. La surface au
sol, facultative et exprimée en m², sert à proposer la pièce propriétaire d'une
cloison. On ne déduit pas cette surface des surfaces de parements.

`ProjectItem.works` reste le registre unique des ouvrages du projet. `roomID`
désigne la pièce propriétaire ; `linkedRoomIDs` donne accès aux cloisons depuis
les pièces voisines sans les compter une deuxième fois. Les ouvrages sans pièce
restent visibles dans le projet et peuvent être rattachés explicitement.

`WorkItem.components` contient les composants physiques : Mur A, Mur B, etc.
Un ouvrage ne possédant qu'un quantitatif global peut avoir zéro composant.
Un composant créé sans contour porte `surface = nil` : aucun rectangle n'est
fabriqué à partir de la surface totale de l'ouvrage.

Chaque composant conserve un seul `Surface2D` (millimètres), avec les ouvertures
géométriques canoniques et une révision. Ses `ComponentLayoutPlan` portent les
couches de plaques et les points électriques propres à chaque côté.
L'ossature est conservée une seule fois dans le composant, puis injectée dans le
document remis à l'éditeur.

`WorkItem.layoutDocument` n'est plus persisté en parallèle : c'est une façade
calculée pour les anciens parcours à un seul composant et un seul plan. Elle
renvoie nil pour un ouvrage multi-composant ; le premier mur ne peut donc pas
remplacer accidentellement les dimensions de tout le doublage.

## Cloisons et côtés

### Ne pas confondre support partagé et supports adjacents

**Décision utilisateur complémentaire :** déplacer un bord de plafond ne doit
jamais modifier automatiquement la longueur du mur adjacent. Ce sont deux
composants distincts, contrairement aux deux vues d'une même ossature de cloison.

Lors de l'implémentation des relations scan/plafond/mur, présenter la ou les
dimensions concernées avec ancienne valeur et nouvelle valeur proposée, puis
attendre une confirmation explicite avant de les appliquer aux autres composants.
Un refus conserve leurs dimensions et laisse un écart à vérifier ; il ne doit ni
annuler la correction locale demandée, ni masquer cet écart. L'acceptation doit
être une transaction validée et invalider seulement les plans dépendants.

Ce lot ne propage aucune modification entre composants distincts. Le dialogue de
propagation sera ajouté avec les relations d'adjacence du scan, pas simulé sans
relation géométrique connue.

### Un seul composant de cloison, deux points de vue

- Toute la cloison est comptée dans sa pièce propriétaire, y compris les deux
  parements. La pièce voisine expose seulement un lien de consultation.
- Lors de la première association, la plus petite pièce est proposée si les deux
  surfaces au sol sont connues. Une propriété existante n'est pas recalculée
  silencieusement lorsque les surfaces changent ; l'utilisateur peut la modifier.
- `referenceSideRoomID` conserve le repère physique indépendamment du propriétaire.
- Le plan du côté opposé est projeté en miroir autour de l'origine locale fixe.
  Les identifiants des ouvertures et les indices des arêtes restent les mêmes.
- Les points électriques et les couches de plaques restent propres au côté.
- Une modification du contour **ou de l'ossature commune** augmente la révision
  du support ; les plans de l'autre côté sont signalés à vérifier.
- L'éditeur explique que +5 cm vers la droite côté A donne −5 cm côté B. Une
  modification d'ossature demande confirmation « Appliquer aux deux côtés » à
  l'enregistrement. Les positions des montants ne sont jamais propres à un côté.
- Un éditeur ouvert sur une révision de contour périmée ne peut pas écraser le
  nouveau contour ou rétablir une ancienne ossature : il demande de rouvrir le composant.

## Sauvegarde et copies

Le nouveau stockage est `Application Support/Plaquisto/projects-v2.json`, enveloppe
`schemaVersion: 2`. Le fichier historique `projects.json` n'est pas importé.
Il reste intact sur disque ; le démarrage vierge n'est pas une suppression des
photos ou des bibliothèques autonomes.

Écritures atomiques ; publication de l'état seulement après réussite. Une archive
illisible ou de version inconnue bloque les écritures. Les identifiants et les
références de pièces/composants/plans sont validés au chargement et à l'écriture.

La copie d'un projet réattribue les UUID des pièces, ouvrages, composants, plans,
supports, couches et ouvertures géométriques. Les liens internes sont réaffectés.
La copie d'un ouvrage garde ses pièces dans le même projet mais reçoit des
composants/plans distincts. Les ouvertures auxiliaires gardent un lien vers leur
ouvrage porteur ; si celui-ci est supprimé, ce lien est détaché explicitement.

L'éditeur de calepinage embarqué ne lit ni n'écrit le brouillon ou la bibliothèque
autonome des outils. Son bouton Enregistrer écrit dans le composant et retourne
à la page appelante ; une erreur est affichée et ne ferme pas le plan.

## Parcours livrés

- Projet → organisation des pièces → création / renommage / rattachement.
- Création d'un ouvrage → choix d'une pièce existante ou saisie d'une nouvelle
  pièce ; création de la pièce et de l'ouvrage dans la même transaction.
- Pièce → ouvrages propriétaires / cloisons liées → composants → plan de calepinage.
- Projet ou pièce → quantitatif → configuration de l'ouvrage contributeur.
- Export d'un calepinage autonome → projet / pièce → ouvrage et composant.

Les quantitatifs restent ceux des calculateurs métier existants. L'agrégateur
déduplique les ouvrages par UUID. Il ne répartit pas arbitrairement les fournitures
entre composants et n'additionne pas un métrage de plan à l'estimation métier.

## Limites et prochain lot

1. Relier les pièces et composants aux observations du scan par UUID ; permettre
   la sélection d'un composant depuis la scène 3D, avec projection dans son plan réel.
2. Relier les ouvertures de scan, de calepinage et des formulaires métier par une
   identité canonique. Les ouvertures géométriques et les anciens ouvrages
   auxiliaires de fournitures restent deux modèles distincts à ce stade.
3. Remonter les métrés multi-composants vers les calculateurs métier sans remplacer
   leurs prescriptions ni double compter les ossatures de cloisons. Pour ce lot,
   le quantitatif global est toujours configuré dans le formulaire de l'ouvrage.
4. Détailler la provenance de chaque ligne de fourniture, les révisions de calcul
   et les snapshots. Le lien vers l'ouvrage source existe, pas encore une ventilation
   poste par poste par composant.
5. Ajouter les médias et observations vocales ciblées ; aucun enregistrement audio,
   analyse de photo ou import de scan n'est activé par ce lot.
6. Enrichir les opérations de suppression/réaffectation des pièces et composants
   avec leurs confirmations. Aucune cascade implicite sur les pièces n'est exposée.

Ne pas annoncer la navigation complète scan → calepinage → quantitatif comme
terminée avant ces étapes et leurs tests de bout en bout.

## Validation du premier lot

Le 18 septembre 2026 : 143 tests réussis, zéro échec ; compilation iOS et Lab
réussie sur simulateur. Les tests couvrent notamment les copies indépendantes,
les liens de pièces, le non-double-comptage, le refus d'écriture sur une archive
incompatible, l'isolation des plans embarqués et les positions physiques de
l'ossature communes aux deux côtés avec décalage miroir et protection de révision.

Contrôle UI sur iPhone 17 Pro simulé : création de Bureau (9 m²) et Salon (30 m²),
cloison propriétaire Bureau, composant Mur A, édition/enregistrement des deux
côtés, confirmation d'ossature commune, puis affichage du lien dans Salon.
Le projet de contrôle « Test organisation » est conservé. Aucune installation
sur iPhone physique n'a été effectuée pour cette validation.
