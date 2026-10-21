# Plaquisto Lab — intégration du lot 1

Référence : `plaquisto-ios-lot1-atlantique-v12.pdf`, validé avant intégration.
Branche : `codex/refonte-atlantique`.

## Périmètre

- Accueil projets : cartes de même structure avec/sans relevé, recherche claire, actions
  Renommer / Dupliquer / Supprimer empilées, glissement depuis toute la vignette.
- Projet : relevés dépliables avec triangle à gauche, liaison verticale aux ouvrages,
  séparation des groupes et informations du projet dans le menu.
- Ouvrage : configuration et ouvertures au-dessus du quantitatif ; réglages en feuille.
- Relevé : sélecteur 3D/2D, résumé de sélection à emplacement fixe, dessin de même taille
  dans les deux modes, création pleine largeur, export DAE conservé dans le menu.
- Zone déjà occupée : aperçu et choix Exclure / Conserver / Annuler, sans suppression.
- Plan : outils regroupés en bas ; espace réservé aux commandes pour stabiliser le dessin.
- Plafonds : aperçu commun, sélection multiple, ciseaux par plafond, Fusionner / Masquer
  et commande Type de plafond et hauteur. Pour plusieurs plafonds, le menu permet de
  choisir celui dont on règle la hauteur : aucune affectation groupée implicite.
- Calepinage : habillage Atlantique, cinq outils + déplacement détaché, dessin et règles
  de calcul conservés. La barre principale disparaît en plein écran.
- Quantitatif : sélection de fournitures directement sur la liste existante, partage et
  copie du texte. Édition, regroupement, réinitialisation et déduction du stock conservés.

## Garanties

Le drapeau `usesAtlantiqueDesign` reste désactivé par défaut. L'activation se fait dans
le parcours Projets et Modéliser du Lab ; l'app principale ne bascule pas vers la refonte.
Les formulaires détaillés, Outils, Stock et Compte seront migrés dans les lots suivants.
Aucune modification des catalogues, tarifs Admin, moteurs géométriques ou modèles persistés.
La déduction du stock reste une modification de liste d'achat, jamais une sortie réelle.
Le texte exporté contient les informations projet et les fournitures choisies, sans prix ni stock.

La sélection d'export est indexée par l'identifiant de la ligne source, et non son nom édité.
Les valeurs sont relues lors du partage ; lignes remplacées à zéro et valeurs invalides exclues.
Les menus de suppression et leurs confirmations existantes sont conservés.

## Recette isolée

Argument simulateur Lab : `-atlantique-lot1-fixture`.
Archive dédiée : dossier temporaire `AtlantiqueLot1QA-v2/projects.json` dans le sandbox Lab.
Cette option n'est pas compilée sur appareil physique. Elle n'écrit jamais dans l'archive
normale : deux projets fictifs, deux relevés et deux ouvrages permettent les contrôles.
Sans cet argument, le Lab retrouve son stockage habituel.

À contrôler avant installation sur téléphone : vignette/glissement, repli/dépli,
3D/2D et sélection, plafonds, calepinage/plein écran, quantitatif/filtre/sélection/partage.
Les contrôles sur appareil LiDAR réel et l'audit VoiceOver complet restent distincts de
la compilation et des tests simulateur.

## Validation du 21 octobre 2026

- Compilation Debug simulateur de Plaquisto Lab réussie sur le code final.
- Compilation de l'app principale et suites `ToolCalculatorTests`, `StockTests`,
  `ProjectStoreTests` : **187 tests réussis, aucun échec ni test ignoré**.
- Nouveau test de sélection d'export : identité stable après renommage, quantité
  éditée avec déduction du stock, exclusion des sources fusionnées à zéro et des IDs périmés.
- Recette visuelle sur iPhone 17 Pro simulé : cartes uniformes, glissement depuis la
  vignette, hiérarchie, configuration/ouvertures, résumé de sélection 3D/2D, bouton de
  création, choix des plafonds, calepinage et disparition de la navigation en plein écran.
- Dernière version vérifiée : retour unique du calepinage, Enregistrer lisible, sélection
  d'export individuelle/globale, actions désactivées à zéro sélection, Annuler restitue
  les lignes éditables. Aucun partage externe n'a été envoyé pendant la recette.
- Aucune installation sur téléphone physique, aucune fusion vers la branche principale.
