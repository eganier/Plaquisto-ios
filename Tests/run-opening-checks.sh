#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
proof_dir=$(mktemp -d /tmp/plaquisto-openings.XXXXXX)
xcrun swiftc \
    Plaquisto/PlaquistoCore/Configurators/Openings/OpeningModels.swift \
    Plaquisto/PlaquistoCore/Configurators/Openings/OpeningQuantityCalculator.swift \
    Tests/OpeningQuantityCalculatorChecks.swift \
    -o "$proof_dir/opening-checks"
"$proof_dir/opening-checks"
printf 'Preuve des ouvertures : %s\n' "$proof_dir"

