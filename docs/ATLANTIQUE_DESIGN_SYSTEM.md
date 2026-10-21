# Plaquisto · Socle Atlantique

Branche : `codex/refonte-atlantique`.
Sauvegarde avant refonte : `fb51e9c` sur `origin/codex/liste-courses-ouvertures`.
Le socle ne modifie aucun catalogue, prix, calcul ou modèle de données.

## Références validées

- iOS lot 1 : `plaquisto-ios-lot1-atlantique-v12.pdf`
- iOS lot 2 : `plaquisto-ios-lot2-atlantique-v22.pdf`
- iOS lot 3 : `plaquisto-ios-lot3-atlantique-v4.pdf`
- Atlantique `#285982`, orange de sélection `#FF8A1F`, texte `#17324A`.
- Orange de lecture sur fond clair `#AD5100` ; éviter du petit texte orange vif sur blanc.
- Avenir Next Regular / Medium / DemiBold / Bold, tailles relatives Dynamic Type.
- Cartes 17 pt, commandes 12–14 pt, cibles tactiles au moins 48 pt.
- Verre et ombre discrets sur les surfaces seulement ; jamais de flou sur texte ou cotes.

## Intégration progressive

`AtlantiqueDesignSystem.swift` est compilé dans Plaquisto et Plaquisto Lab.
L'activation est locale : `.atlantiqueDesign()` sur la racine d'un écran migré.
Pas de remplacement global de `UIAppearance`, ni de changement implicite des écrans existants.
Ne pas activer ce modificateur sur toute l'app avant migration des couleurs et fonds de chaque écran.

Composants disponibles : `AtlantiqueCard`, `AtlantiqueSurface`, `AtlantiqueButtonStyle`,
`AtlantiqueSymbol`, `AtlantiqueIconButton`, `AtlantiqueOptionsMenu`, `AtlantiqueChoice`,
`AtlantiqueSearchField`, `AtlantiqueNumberRow`.

Les actions, valeurs, validations et conditions d'enregistrement restent définies par l'écran métier.
Un bouton Enregistrer incomplet doit utiliser `.disabled(true)` : le style gère son apparence.
Les boutons Entrée/Sortie utilisent les variantes `.entry`/`.exit`, avec flèches haut/bas.
Les menus restent des menus natifs, avec les rôles destructifs déclarés par l'appelant.

## Clavier R50

Réutilisation de `PlaquistoNumericField`, sans nouveau moteur de saisie.
Disposition : 7–8–9 / 4–5–6 / 1–2–3 / 0–virgule–effacer, Valider en colonne à droite.
Le drapeau visuel est transmis explicitement au `UIHostingController` de l'inputView,
qui n'hérite pas de l'environnement SwiftUI du formulaire.
Les entiers, signes, copier-coller, suppression, focus et fermeture gardent leur logique existante.
La valeur métier n'est pas arrondie lors de l'affichage.

## Vérification dans le Lab

Réglages → Comparer → Composants Atlantique.
La galerie est interactive et ne touche pas aux données de l'utilisateur.
Arguments de lancement simulateur : `-atlantique-gallery`, éventuellement `-atlantique-keyboard`.
La galerie sert à vérifier les composants isolément. La migration des écrans métier se fait par lot.
Le premier lot intégré dans le Lab est décrit dans [ATLANTIQUE_LOT1.md](ATLANTIQUE_LOT1.md).

Contrôler : petit écran, Dynamic Type, Réduire la transparence, Réduire les animations,
contraste augmenté, état désactivé, menus VoiceOver et clavier natif dans un formulaire.

## Vérifications du socle réalisées le 21 octobre 2026 (avant intégration du lot 1)

- Compilation Debug simulateur de Plaquisto Lab et de Plaquisto réussie.
- Suite `PlaquistoTests/ToolCalculatorTests` : 28 tests réussis, dont 6 ajoutés au socle.
- Vérifications automatisées : palette, disponibilité des quatre graisses Avenir Next,
  activation locale, disposition R50, précision des valeurs et rendu avec texte agrandi.
- Vérification manuelle sur simulateur iPhone 17 Pro : galerie, menu, sélecteur 40/60,
  interrupteur, ouverture du clavier natif, saisie « 2,5 », validation et fermeture.
- Aucune installation sur iPhone physique et aucune migration complète des écrans à ce stade.
- Les réglages système de transparence, animations et contraste sont pris en compte par
  les composants ; leur vérification sur appareil et l'audit VoiceOver complet restent à faire.
