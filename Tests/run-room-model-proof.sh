#!/bin/bash
# Run from repository root. Optional first argument: already booted simulator UUID.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
proof_dir=$(mktemp -d /tmp/plaquisto-room-proof.XXXXXX)
xcrun swiftc Plaquisto/Plaquisto/PlaquistoRoomModel.swift Plaquisto/Plaquisto/PlaquistoWallGeometry.swift Tests/RoomModelIndependenceChecks.swift -o "$proof_dir/checks"
"$proof_dir/checks" write "$proof_dir/room.json"
"$proof_dir/checks" read "$proof_dir/room.json"
if [ "$#" -gt 0 ]; then
    app_dir="$proof_dir/RoomModelViewer.app"
    mkdir "$app_dir"
    cp Tests/RoomModelViewer-Info.plist "$app_dir/Info.plist"
    cp "$proof_dir/room.json" "$app_dir/room.json"
    proof_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
    xcrun --sdk iphonesimulator swiftc -parse-as-library -sdk "$proof_sdk" -target arm64-apple-ios17.0-simulator Plaquisto/Plaquisto/PlaquistoRoomModel.swift Plaquisto/Plaquisto/PlaquistoWallGeometry.swift Plaquisto/Plaquisto/SurveyCapture.swift Plaquisto/Plaquisto/ScannerCeilingReconstruction.swift Plaquisto/Plaquisto/ScannerRoomBridge.swift Plaquisto/Plaquisto/CeilingAutoFit.swift Plaquisto/Plaquisto/MaquetteStyle.swift Plaquisto/Plaquisto/PlaquistoRoomEditor.swift Plaquisto/PlaquistoCore/Configurators/PlaquistoNumericField.swift Plaquisto/PlaquistoCore/Configurators/ZeroEmptyDecimalTextField.swift Tests/RoomModelViewerSmoke.swift -o "$app_dir/RoomModelViewer"
    xcrun simctl install "$1" "$app_dir"
    xcrun simctl launch --terminate-running-process "$1" fr.plaquisto.roommodelproof "${2:-}"
fi
printf 'Proof artifacts: %s\n' "$proof_dir"
