# Architecture de Plaquisto

## Applications

- `Plaquisto` est l'application principale. Elle contient les chantiers, les ouvrages validés et les quantitatifs.
- `PlaquistoLab` est un atelier indépendant. Son contenu peut être remplacé pour développer un nouveau configurateur sans modifier l'application principale.

Les deux applications sont des cibles Xcode indépendantes. Plaquisto ne dépend d'aucun fichier ni d'aucune cible de Plaquisto Lab.

## Code de l'application principale

Le dossier `PlaquistoCore` contient le métier de Plaquisto :

- `Models` : catégories, types d'ouvrages et configurations enregistrées ;
- `References` : lecture des données publiées par Plaquisto Admin ;
- `Configurators/Ceiling` : plafond sur fourrures ;
- `Configurators/Doublage` : doublage périphérique sur rails et montants.

Le dossier `Plaquisto` contient l'application, les chantiers, la navigation et les quantitatifs regroupés.

## Familles d'ouvrages prévues

- Les plafonds
- Les cloisons
- L'isolation des murs
- Ouvrages spécifiques

Chaque nouveau type d'ouvrage doit appartenir à une de ces familles et posséder sa propre configuration enregistrable.

## Cycle d'un nouveau configurateur

1. Développer et tester le formulaire dans `PlaquistoLab`.
2. Valider son parcours, ses règles et ses quantitatifs.
3. Déplacer le formulaire validé dans `PlaquistoCore/Configurators`.
4. Ajouter son type et sa configuration aux modèles de Plaquisto.
5. Ajouter les tests de sauvegarde, migration, duplication et quantitatifs.
