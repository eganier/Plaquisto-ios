# Guide de contours local

Détecteur [TEED](https://github.com/xavysp/TEED), commit
`40fa4b1391dc6424f88989d0ca75d5b592c8681d`, licence MIT, Copyright (c) 2022 Xavier Soria Poma.
Le code et la licence sont conservés dans `vendor/`. Les opérations Smish sont intégrées
depuis le même dépôt ; PixelShuffle(1) est remplacé par son équivalent identité pour CoreML.

Poids officiels BIPED/7 : SHA-256
`d0109e7f40e7d9f1f495d34947eb08167e8fbb0a13b4e6ab3121261fb8d5a416`.
La conversion télécharge uniquement ces poids et vérifie leur empreinte. Aucune photo
n'est transmise. Le modèle est embarqué dans l'app, sans téléchargement à l'exécution.

## Reproduction sur macOS

Dans un environnement Python isolé, installer `torch==2.8.0`, `coremltools==8.3.0`,
`numpy==1.26.4`, `onnx==1.19.1`, `onnxruntime==1.19.2`, puis lancer depuis le dépôt :

```sh
python scripts/structural_guide/convert.py
```

Coremltools avertit que Torch 2.8 dépasse sa version testée. La conversion a néanmoins
réussi et la comparaison numérique CoreML/ONNX incluse dans le script a passé :
écart absolu maximal 0,0137912 sur l'entrée pseudo-aléatoire de contrôle (seuil 0,025).
Ce contrôle n'est pas une validation d'une application Android.

Artefacts actuels dans `Plaquisto/PlaquistoCore/Tools/GuideModels` :

- `StructuralContours.mlmodel` : `918a3710bc894f366927d81dd653078d844b354df43ca5d3d7ef89ece056213e`
- `StructuralContours.onnx` : `cdf8ba5429a2ff4b63e1565f5e6be55b3d00a054dc1cc77127f3fe4a67c72cde`

La licence est embarquée avec le modèle iOS ; le fichier ONNX reste dans le dépôt,
sans alourdir le bundle iOS.

## Contrat portable / Android

1. Image orientée, pixels RGB, rapport d'aspect préservé, centrée sur un carré 512 × 512,
   fond gris 0,5. Arrondis et offsets : `BeforeAfterGuideFit`.
2. Entrée `rgb`, Float32 NCHW `[1,3,512,512]`, valeurs 0…1.
   La conversion RGB→BGR, multiplication par 255 et soustraction de la moyenne
   `[104.007,116.669,122.679]` sont déjà incluses dans les deux modèles.
3. Sortie `edges`, probabilités `[1,1,512,512]`. Retirer les marges de cadrage.
4. `BeforeAfterGuideTracing` : seuil 0,80, suppression des zones denses et de leur bord,
   squelettisation, suppression des fragments courts, simplification en polylignes.
5. Polylignes normalisées, origine en haut à gauche, puis traits blancs sur alpha transparent.

Le protocole `BeforeAfterGuideExtracting` ne contient aucun type Apple. L'adaptateur iOS
emploie CoreML ; Android pourra employer ONNX Runtime et reprendre le pré/post-traitement.
Le détecteur repère des arêtes, pas une segmentation sémantique parfaite des meubles :
des joints peuvent subsister et certains contours rester interrompus.

## Aperçu de contrôle avec le code de production

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun coremlcompiler compile Plaquisto/PlaquistoCore/Tools/GuideModels/StructuralContours.mlmodel /tmp/plaquisto-guide-model
xcrun swiftc -O Plaquisto/PlaquistoCore/Tools/BeforeAfterModels.swift Plaquisto/PlaquistoCore/Tools/BeforeAfterStructuralGuide.swift Plaquisto/PlaquistoCore/Tools/BeforeAfterGuideApple.swift scripts/structural_guide/Preview.swift -o /tmp/plaquisto-guide-preview
/tmp/plaquisto-guide-preview /chemin/photo.jpg /tmp/plaquisto-guide-model/StructuralContours.mlmodelc /tmp/guide
```

Le script produit un PNG transparent, une version sur noir et une superposition de diagnostic.
Cette dernière n'est PAS le calque caméra : l'app n'affiche que les traits sur le flux live.
Aucune photo utilisateur n'est incluse dans le dépôt.
