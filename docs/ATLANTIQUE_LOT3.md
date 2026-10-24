# Plaquisto Lab — lot 3

Référence : book iOS lot 3 Atlantique v4. Intégration opt-in du thème dans Lab,
sans migration des projets ou des tarifs et sans changement du thème de production.

## Parcours intégrés

- Modéliser : entrée scanner/dessin, création du sol, hauteurs communes ou différentes,
  réglage par sommet/segment et enregistrement dans un projet. Une hauteur différente
  masque le champ de hauteur commune sans perdre sa valeur.
- Outils : liste complète, recherche visible, catégories, icônes harmonisées et
  navigation dans les outils existants sous Avenir Next / Atlantique / Orange.
- Calculs thermiques, TVA et angles : conservation des calculs ; résultats d’angle verts.
- Gabarit d’arche : hauteur et ampleur réglables, tracé centré à échelle uniforme,
  points symétriques et tableau mesuré depuis le centre jusqu’à la demi-largeur.
- Hauteur de cloison/doublage : cartes de configuration, résultat métier et remise
  à zéro ; plafond autoportant en recherche avec filtres parement/peaux/montants.
- Photo avant/après : présentation commune, menu Séparation et curseur du séparateur,
  tout en conservant la capture, l’alignement et l’export existants.
- Réglages : graphisme 3D réel, catalogue avec actualisation réelle, état du cache,
  date du dernier succès réseau, erreurs explicites, version et fonctionnement local.

## Limites explicites

Les écrans de compte, connexion, mot de passe, abonnement et textes contractuels du
book sont des parcours futurs : aucun backend d’identité ou de facturation n’existe
dans cette version. Ils ne sont pas simulés avec des boutons sans effet. Aucun compte
ni synchronisation cloud n’est annoncé comme opérationnel. Les réglages exposés sont
ceux qui fonctionnent réellement dans l’app locale.

Le LiDAR, la caméra et les gestes sur iPhone réel nécessitent une recette appareil ;
la compilation et le simulateur ne permettent pas de valider ces capteurs.

## Tests

Après les 388 tests ciblés du lot 2, la suite complète du 21 octobre 2026 réussit :
659 tests, zéro échec, sur iPhone 17 Pro simulé (iOS 26.5). Elle couvre notamment
géométrie, relevés, calepinages, quantitatifs, stock, calculateurs et photos.
Les tests d’arche ajoutés vérifient symétrie, demi-largeur, forme et entrées invalides.

Résultat : Test-Plaquisto-2026.10.21_22-50-18-+0200.xcresult (Passed).
La compilation finale PlaquistoLab réussit également.

La recette visuelle du lot 2 a été effectuée sur le stock et le parcours plafond avec
le projet de démonstration. Elle a conduit à corriger le contraste des actions,
les cartes Ossature et les titres de section. La dernière passe visuelle du lot 3
est INCOMPLÈTE : le Mac s’est verrouillé et l’automatisation d’interface ne pouvait
plus accéder au simulateur. La compilation et les tests ne remplacent pas cette passe.
Aucune écriture dans les projets réels. Aucun déploiement iPhone ni push GitHub.

## Reprise de recette et corrections — 22 octobre 2026

La passe interrompue ci-dessus a été reprise sur le simulateur iPhone 17 Pro,
avec les projets de démonstration. Corrections d’affichage uniquement :

- boutons de barre « Fermer », « Annuler » et « Utiliser » non comprimés ;
- sélecteurs orange communs dans les outils techniques, le stock et le contour,
  avec conservation du sélecteur natif hors thème Atlantique ;
- titre Plénum et actions rapides du stock plus lisibles ;
- champs Largeur / Pas depuis le centre sur deux lignes et libellé de
  conditionnement raccourci ; raccourci du formulaire renommé « Ossature ».

Contrôle visuel du binaire Lab corrigé : Ossature et Fixations, changements
Simples/Doublés et 40/60 cm dans Hauteur de cloison, champs du gabarit d’arche,
famille Vis et fixations et saisie du conditionnement, éditeur de sol et bascule
Cotes/Angles. Les essais de stock et de dessin ont été quittés sans enregistrement.
Les matériaux de verre/transparence existants sont conservés sans nouvelle retouche.

Suite complète : **661 tests réussis, aucun échec ni test ignoré**, dont deux
nouveaux tests de rendu (largeur des actions et sélecteurs sur petits écrans /
texte agrandi). Résultat : `Test-Plaquisto-2026.10.21_23-59-35-+0200.xcresult`.
Compilation finale PlaquistoLab réussie ; binaire installé sur le simulateur
uniquement. La recette capteurs et gestes sur iPhone réel reste à effectuer.
