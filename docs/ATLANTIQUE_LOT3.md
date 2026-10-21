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
