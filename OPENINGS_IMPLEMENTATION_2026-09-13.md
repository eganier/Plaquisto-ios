# Plaquisto Lab — implémentation des ouvertures

Date : 13 septembre 2026.

Référence métier lue intégralement : `PLAQUISTO_REGLES_METIER_COMPLETES_OUVERTURES_CODEX.md`.

## Périmètre livré dans le Lab

- fenêtre classique ;
- porte-fenêtre / baie ;
- porte intérieure de cloison ;
- galandage R70/M70 ;
- fenêtre de toit sur plafond en fourrures ;
- fenêtre de toit sur plafond rails/montants ;
- embrasures et appuis intermédiaires pour doublage sur fourrure ;
- niche présente dans le modèle mais volontairement désactivée, conformément à la spécification.

Le scanner et l’application Plaquisto principale ne sont pas modifiés par cette étape. Plaquisto Lab ne démarre plus sur l’ancien configurateur de plafond rail/montant : sa cible ne compile que l’écran du Lab des ouvertures et son moteur métier autonome.

## Architecture

```text
OpeningInput + OpeningContext
          ↓
OpeningQuantityCalculator
          ↓
OpeningQuantityResult par ouverture
          ↓
Totaux du Lab
```

Le calculateur importe uniquement Foundation. L’interface SwiftUI ne contient aucune formule de quantitatif.

Le contexte de l’ouvrage (système, HSP, entraxe, montants doublés, tapée et longueur dans le sens des montants) est saisi une seule fois. Dans Plaquisto Lab, la HSP est obligatoire et n’a aucune valeur préremplie ; l’ajout d’une ouverture murale reste bloqué tant qu’elle n’est pas renseignée. Dans l’application principale, elle pourra être reprise automatiquement de l’ouvrage lorsqu’elle est déjà connue. Chaque sous-formulaire demande ensuite uniquement le type, la largeur, la hauteur et le nombre d’ouvertures identiques. Une quantité supérieure à un crée autant d’ouvertures individuelles, numérotées et modifiables séparément. Une saisie peut aussi être dupliquée avec l’action de glissement. Les types proposés sont filtrés selon l’ouvrage.

Les plaques ne sont jamais déduites. La surface des ouvertures est déduite uniquement de l’isolant. Chaque ouverture est calculée séparément avant addition des résultats ; les renforts de plusieurs ouvertures ne sont donc jamais fusionnés.

Le détail affiche les nombres de profils et leurs longueurs totales séparément. Pour les embrasures, l’interprétation géométrique retenue est : deux profils latéraux continus, puis un profil transversal par zone et par tranche de largeur de 60 cm ; une fenêtre possède une zone inférieure et une zone supérieure, une baie uniquement la zone supérieure. Le nombre d’appuis d’embrasure suit directement la formule explicite du document. La tapée est conservée comme profondeur d’embrasure et signalée lorsqu’elle manque.

La spécification métier source ne distingue pas encore deux modes de pose « sur tapée de menuiserie » et « en embrasure ». Elle décrit la tapée comme profondeur d’embrasure et applique ensuite une seule famille de renforts d’embrasure. Aucun calcul distinct ne doit donc être activé tant que les fournitures et formules propres à chaque montage ne sont pas précisées.

Le formulaire prépare néanmoins cette distinction : « Sur tapée de menuiserie » est sélectionné par défaut, et « En embrasure » est visible mais désactivé avec la mention « Fonctionnalité à venir ». Le mode choisi est conservé dans le modèle de l’ouverture, sans modifier les formules actuelles.

Dans une cloison de distribution, le type `window` est présenté à l’utilisateur sous le nom « Verrière » et le type « Porte-fenêtre / baie » n’est pas proposé. Pour un plafond rails/montants, la longueur dans le sens des montants est affichée comme une donnée obligatoire et l’ajout reste bloqué tant qu’elle n’est pas renseignée.

Les champs numériques obligatoires sont vides lorsque leur valeur métier vaut zéro afin que la saisie ne conserve jamais un zéro parasite. Les dimensions des ouvertures sont saisies et affichées en centimètres dans l’interface, puis converties en mètres avant leur transmission au calculateur.

## Intégration Plaquisto iOS

L’intégration à l’application principale est développée sur la branche `codex/integrate-openings-ios`. La catégorie auparavant affichée « Ouvrages spécifiques » est renommée « Ouvertures » et contient un type d’ouvrage « Ouvertures ». Une configuration sauvegarde le contexte commun et la liste des ouvertures individuelles. Elle peut être rouverte, modifiée, dupliquée et incluse dans le quantitatif global du chantier.

## Vérifications

`Tests/OpeningQuantityCalculatorChecks.swift` contrôle :

- les seuils stricts 60/61 cm et 120/121 cm ;
- les ossatures lisses/fourrures et rails/montants simples ou doublés ;
- fenêtre, baie, porte intérieure, galandage et fenêtre de toit ;
- l’absence d’appuis intermédiaires en rails/montants ;
- la niche non finalisée ;
- l’addition de deux ouvertures après leur calcul indépendant.

Rejouer depuis la racine du dépôt :

```sh
bash Tests/run-opening-checks.sh
```

La cible PlaquistoLab compile pour simulateur. Une archive de développement signée pour iPhone a également été générée ; l’installation attend que l’iPhone redevienne disponible pour le Mac.
