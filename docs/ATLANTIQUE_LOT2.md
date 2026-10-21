# Plaquisto Lab — lot 2

Référence : book iOS lot 2 Atlantique v22. Activation par `usesAtlantiqueDesign`.

## Intégration

- Formulaires et feuilles : fond Atlantique, Avenir Next, actions communes, titres
  d’étape, enregistrement disponible dès que toutes les données sont valides.
- Plafond sur fourrures : séparation Ossature / Fixations, choix 40 ou 60 cm pour
  les nouvelles configurations, périphérie et entraxe des suspentes modifiable.
  Une valeur historique de 50 cm reste lisible sans remplacement silencieux.
- Couche d’isolation regroupée ; deuxième couche et deuxième parement ajoutables.
  Pare-vapeur et traitement des joints restent des choix explicites.
- Estimation du plafond fondée sur les vrais tarifs et le même calcul que le
  quantitatif. Les tarifs absents ne deviennent jamais des prix nuls.
- Ouvertures : disposition compacte, choix du mur par flèches, cotes A/B/C/D
  jusqu’au contour réel, y compris dans une pièce en L ou tournée.
- Prise sélectionnée : cotes A/B/C/D, déplacement indépendant des autres prises
  et conservation des rangées. La validation géométrique reste obligatoire.
- Contour : affichage cotes ou angles ; annulation et nouveau dessin distincts.
- Stock : métadonnées sur l’accueil, familles regroupées, recherche dans la famille,
  Entrée verte / Sortie rouge, pourcentage de conditionnement entamé, aperçu après
  mouvement, export texte réel. Pas d’attribution à un chantier dans la saisie Lab.

## Persistance et précautions

`CeilingConfiguration.suspensionSpacingMeters` est optionnel : nil conserve 1,20 m.
Le paramètre alimente l’estimation et les nouveaux plans. Un réglage manuel de plan
reste prioritaire. Aucun catalogue, tarif ou compte Admin n’est modifié.
Les anciennes réservations restent conservées et protégées par le stock ; aucune
migration destructive n’a été introduite pour retirer leur ancien onglet.
Les variantes métier non représentées dans le book conservent leurs champs et
validations existants sous les composants communs.

## Vérification

21 octobre 2026 : 388 tests réussis, zéro échec, zéro ignoré sur iPhone 17 Pro simulé
(iOS 26.5) : SheetLayoutEngineTests, StockTests, ProjectStoreTests, ToolCalculatorTests.
Résultat : Test-Plaquisto-2026.10.21_22-34-37-+0200.xcresult.
Nouveaux contrôles : positions dans un contour concave/tourné, déplacement d’une seule
prise, lecture de l’ancien format sans entraxe des suspentes, conservation du réglage
manuel, conversion des pourcentages de boîtes et refus des valeurs invalides.

La recette visuelle finale et la vérification sur appareil physique sont distinctes
de ces tests. Aucun déploiement iPhone ni envoi GitHub dans cette étape.
