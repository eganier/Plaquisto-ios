import SwiftUI

private enum TechnicalSearchMode: String, CaseIterable, Identifiable {
    case verify = "Vérifier"
    case find = "Trouver"
    var id: String { rawValue }
}

struct CeilingSpanToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var mode = TechnicalSearchMode.verify
    @State private var requestedSpan = 0.0
    @State private var material = ""
    @State private var lambda = 0.0
    @State private var thicknessMM = 0
    @State private var stud = 48
    @State private var doubled = false
    @State private var layers = 1
    @State private var facing = "ba13"
    @State private var findAssembly = PartitionAssemblyFilter.all

    private var options: [CeilingSpanOption] { store.ceilingSpans }
    private var materials: [String] { insulationMaterials(store.insulationMasses) }
    private var lambdas: [Double] { insulationLambdas(store.insulationMasses, material: material) }
    private var thicknesses: [Int] { insulationThicknesses(store.insulationMasses, material: material, lambda: lambda) }
    private var insulation: InsulationMassOption? {
        store.insulationMasses.first { $0.material == material && abs($0.lambda - lambda) < 0.000_1 && $0.thicknessMM == thicknessMM }
    }
    private var loadBand: Int? {
        guard let mass = insulation?.surfaceMass else { return nil }
        if mass < 6 { return 0 }
        if mass < 10 { return 1 }
        if mass <= 15 { return 2 }
        return nil
    }
    private var studs: [Int] { unique(options.map(\.stud)).sorted() }
    private var availableLayers: [Int] { unique(options.map { ceilingLayerCount($0.facing) }).sorted() }
    private var availableFacings: [String] {
        unique(options.filter { ceilingLayerCount($0.facing) == layers }.map(\.facing)).sorted(by: facingOrder)
    }
    private var selected: CeilingSpanOption? {
        options.first { $0.stud == stud && $0.assembly == (doubled ? "double" : "single") && $0.facing == facing }
    }
    private func span(_ option: CeilingSpanOption) -> Double {
        guard let loadBand, option.spans.indices.contains(loadBand) else { return 0 }
        return option.spans[loadBand]
    }
    private var compatible: [CeilingSpanOption] {
        options.filter { option in
            span(option) >= requestedSpan
                && (findAssembly.doubled == nil || findAssembly.doubled == (option.assembly == "double"))
        }
        .sorted { lhs, rhs in
            if lhs.stud != rhs.stud { return lhs.stud < rhs.stud }
            if lhs.assembly != rhs.assembly { return lhs.assembly == "single" }
            return span(lhs) < span(rhs)
        }
    }

    var body: some View {
        TechnicalToolForm(title: "Plafond autoportant", store: store) {
            Section { Picker("Mode", selection: $mode) { ForEach(TechnicalSearchMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
            Section("Portée") { ToolNumberField(title: "Portée à franchir", unit: "m", value: $requestedSpan) }
            Section("Isolant") {
                Picker("Type d’isolant", selection: $material) {
                    ForEach(materials, id: \.self) { Text($0).tag($0) }
                }
                Picker("Lambda", selection: $lambda) {
                    ForEach(lambdas, id: \.self) { value in
                        Text("λ \(value.formatted(.number.precision(.fractionLength(3)))) W/(m·K)").tag(value)
                    }
                }
                Picker("Épaisseur", selection: $thicknessMM) {
                    ForEach(thicknesses, id: \.self) { Text("\($0) mm").tag($0) }
                }
            }
            if mode == .verify {
                Section("Configuration") {
                    Picker("Système rail / montant", selection: $stud) {
                        ForEach(studs, id: \.self) { value in
                            compatibilityPickerLabel("R\(value) + M\(value)", compatible: ceilingCompatible(stud: value))
                                .tag(value)
                        }
                    }
                    selectorTitle("Configuration des montants") {
                        Picker("Configuration des montants", selection: $doubled) {
                            Text("Simples").tag(false)
                            Text("Doublés").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    Picker("Parements", selection: $layers) {
                        ForEach(availableLayers, id: \.self) { value in
                            compatibilityPickerLabel(liningLayerTitle(value), compatible: ceilingLayerCompatible(value))
                                .tag(value)
                        }
                    }
                    Picker("Type de parement", selection: $facing) {
                        ForEach(availableFacings, id: \.self) { code in
                            compatibilityPickerLabel(ceilingFacingLabel(code, options: options), compatible: ceilingCompatible(facing: code))
                                .tag(code)
                        }
                    }
                }
                if let selected, loadBand != nil {
                    compatibility(maximum: span(selected), requested: requestedSpan)
                } else if insulation != nil {
                    Section("Résultat") {
                        Label("Aucune portée n’est publiée pour cette configuration.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Section {
                    selectorTitle("Configuration des montants") {
                        Picker("Configuration des montants", selection: $findAssembly) {
                            ForEach(PartitionAssemblyFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
                Section("Configurations compatibles") {
                    if requestedSpan <= 0 { Text("Renseignez la portée à franchir.").foregroundStyle(.secondary) }
                    else if loadBand == nil { Text("Sélectionnez un isolant compatible avec les données publiées.").foregroundStyle(.orange) }
                    else if compatible.isEmpty { Text("Aucune configuration publiée ne couvre cette portée.").foregroundStyle(.orange) }
                    else { ForEach(compatible) { option in resultRow(option.title, maximum: span(option), requested: requestedSpan) } }
                }
            }
        }
        .onAppear { normalizeSelections() }
        .onChange(of: options) { _, _ in normalizeSelections() }
        .onChange(of: store.insulationMasses) { _, _ in normalizeInsulationSelection() }
        .onChange(of: material) { _, _ in selectPreferredLambdaAndThickness() }
        .onChange(of: lambda) { _, _ in normalizeThickness() }
        .onChange(of: layers) { _, _ in normalizeFacing() }
    }

    private func normalizeSelections() {
        if !studs.contains(stud) { stud = studs.first ?? 48 }
        if !availableLayers.contains(layers) { layers = availableLayers.first ?? 1 }
        normalizeFacing()
        normalizeInsulationSelection()
    }

    private func normalizeFacing() {
        if !availableFacings.contains(facing) { facing = availableFacings.first ?? "" }
    }

    private func normalizeInsulationSelection() {
        if !materials.contains(material) { material = materials.first ?? "" }
        selectPreferredLambdaAndThickness()
    }

    private func selectPreferredLambdaAndThickness() {
        let target = material.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("bois") ? 0.036 : 0.035
        if !lambdas.contains(where: { abs($0 - lambda) < 0.000_1 }) {
            lambda = lambdas.first(where: { abs($0 - target) < 0.000_1 }) ?? lambdas.first ?? 0
        }
        normalizeThickness()
    }

    private func normalizeThickness() {
        if !thicknesses.contains(thicknessMM) { thicknessMM = thicknesses.first ?? 0 }
    }

    private func ceilingCompatible(stud candidateStud: Int? = nil, facing candidateFacing: String? = nil) -> Bool? {
        guard requestedSpan > 0, loadBand != nil else { return nil }
        let resolvedStud = candidateStud ?? stud
        let resolvedFacing = candidateFacing ?? facing
        return options.contains {
            $0.stud == resolvedStud
                && $0.assembly == (doubled ? "double" : "single")
                && $0.facing == resolvedFacing
                && span($0) >= requestedSpan
        }
    }

    private func ceilingLayerCompatible(_ candidateLayers: Int) -> Bool? {
        guard requestedSpan > 0, loadBand != nil else { return nil }
        return options.contains {
            $0.stud == stud
                && $0.assembly == (doubled ? "double" : "single")
                && ceilingLayerCount($0.facing) == candidateLayers
                && span($0) >= requestedSpan
        }
    }
}

struct PartitionHeightToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var mode = TechnicalSearchMode.verify
    @State private var height = 0.0
    @State private var spacing = 0.40
    @State private var doubled = false
    @State private var selectedFrame = ""
    @State private var layers = 1
    @State private var facing = ""
    @State private var findSpacing = PartitionSpacingFilter.all
    @State private var findAssembly = PartitionAssemblyFilter.all

    private var options: [PartitionHeightOption] {
        store.partitionHeights.sorted(by: partitionOptionOrder)
    }
    private var frames: [String] {
        unique(options.map(\.frame)).sorted { lhs, rhs in
            let left = options.first { $0.frame == lhs }?.frameWidthMM ?? .max
            let right = options.first { $0.frame == rhs }?.frameWidthMM ?? .max
            return left == right ? lhs.localizedStandardCompare(rhs) == .orderedAscending : left < right
        }
    }
    private var verifyLayers: [Int] {
        unique(options.filter { $0.frame == selectedFrame }.map(\.layers)).sorted()
    }
    private var verifyFacings: [String] {
        unique(options.filter { $0.frame == selectedFrame && $0.layers == layers }.map(\.facing)).sorted(by: facingOrder)
    }
    private var findLayers: [Int] { unique(options.map(\.layers)).sorted() }
    private var findFacings: [String] {
        unique(options.filter { $0.layers == layers }.map(\.facing)).sorted(by: facingOrder)
    }
    private var selected: PartitionHeightOption? {
        options.first { $0.frame == selectedFrame && $0.layers == layers && $0.facing == facing }
    }
    private var selectedMaximum: Double { selected?.heights[heightKey(spacing: spacing, doubled: doubled)] ?? 0 }
    private var compatible: [PartitionHeightCandidate] {
        guard height > 0 else { return [] }
        var result: [PartitionHeightCandidate] = []
        for option in options where option.layers == layers && option.facing == facing {
            for candidateDoubled in [false, true] {
                if let filter = findAssembly.doubled, filter != candidateDoubled { continue }
                for candidateSpacing in [0.60, 0.40] {
                    if let filter = findSpacing.value, abs(filter - candidateSpacing) >= 0.001 { continue }
                    let maximum = option.heights[heightKey(spacing: candidateSpacing, doubled: candidateDoubled)] ?? 0
                    if maximum >= height {
                        result.append(.init(option: option, spacing: candidateSpacing, doubled: candidateDoubled, maximum: maximum))
                    }
                }
            }
        }
        return result.sorted(by: candidateOrder)
    }

    var body: some View {
        TechnicalToolForm(title: "Hauteur de cloison", store: store) {
            Section { Picker("Mode", selection: $mode) { ForEach(TechnicalSearchMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
            if mode == .verify {
                verifyContent
            } else {
                findContent
            }
        }
        .onAppear { normalizeSelections() }
        .onChange(of: store.partitionHeights) { _, _ in normalizeSelections() }
        .onChange(of: mode) { _, _ in normalizeSelections() }
        .onChange(of: selectedFrame) { _, _ in normalizeVerifySelections() }
        .onChange(of: layers) { _, _ in normalizeFacing() }
    }

    private var verifyContent: some View {
        Group {
            Section("Configuration") {
                Picker("Système rail / montant", selection: $selectedFrame) {
                    ForEach(frames, id: \.self) { value in
                        compatibilityPickerLabel(value, compatible: partitionCompatible(frame: value))
                            .tag(value)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entraxe des montants").font(.subheadline.weight(.semibold))
                    Picker("Entraxe des montants", selection: $spacing) {
                        Text("40 cm").tag(0.40)
                        Text("60 cm").tag(0.60)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configuration des montants").font(.subheadline.weight(.semibold))
                    Picker("Configuration des montants", selection: $doubled) {
                        Text("Simples").tag(false)
                        Text("Doublés").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                Picker("Parements", selection: $layers) {
                    ForEach(verifyLayers, id: \.self) { value in
                        compatibilityPickerLabel(layerTitle(value), compatible: partitionLayerCompatible(value))
                            .tag(value)
                    }
                }
                Picker("Type de parement", selection: $facing) {
                    ForEach(verifyFacings, id: \.self) { value in
                        compatibilityPickerLabel(value, compatible: partitionCompatible(facing: value))
                            .tag(value)
                    }
                }
            }
            compatibility(maximum: selectedMaximum, requested: height)
        }
    }

    private var findContent: some View {
        Group {
            Section("Besoin") {
                ToolNumberField(title: "Hauteur sous plafond", unit: "m", value: $height)
                Picker("Parements", selection: $layers) {
                    ForEach(findLayers, id: \.self) { Text(layerTitle($0)).tag($0) }
                }
                Picker("Type de parement", selection: $facing) {
                    ForEach(findFacings, id: \.self) { Text($0).tag($0) }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entraxe des montants").font(.subheadline.weight(.semibold))
                    Picker("Entraxe des montants", selection: $findSpacing) {
                        ForEach(PartitionSpacingFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configuration des montants").font(.subheadline.weight(.semibold))
                    Picker("Configuration des montants", selection: $findAssembly) {
                        ForEach(PartitionAssemblyFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            Section("Configurations compatibles") {
                if height <= 0 {
                    Text("Renseignez la hauteur sous plafond.").foregroundStyle(.secondary)
                } else if compatible.isEmpty {
                    Text("Aucune configuration publiée n’est compatible avec ces critères.").foregroundStyle(.orange)
                } else {
                    ForEach(compatible.prefix(30)) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.option.frame).font(.subheadline.bold())
                            Text("\(candidate.doubled ? "Montants doublés" : "Montants simples") · entraxe \(Int(candidate.spacing * 100)) cm · maximum \(meters(candidate.maximum))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func normalizeSelections() {
        if !frames.contains(selectedFrame) { selectedFrame = frames.first ?? "" }
        if !findLayers.contains(layers) { layers = findLayers.first ?? 1 }
        normalizeVerifySelections()
        normalizeFacing()
    }

    private func normalizeVerifySelections() {
        if !verifyLayers.contains(layers) { layers = verifyLayers.first ?? findLayers.first ?? 1 }
        normalizeFacing()
    }

    private func normalizeFacing() {
        let values = mode == .verify ? verifyFacings : findFacings
        if !values.contains(facing) { facing = values.first ?? "" }
    }

    private func partitionCompatible(frame candidateFrame: String? = nil, facing candidateFacing: String? = nil) -> Bool? {
        guard height > 0 else { return nil }
        let resolvedFrame = candidateFrame ?? selectedFrame
        let resolvedFacing = candidateFacing ?? facing
        let maximum = options.first {
            $0.frame == resolvedFrame && $0.layers == layers && $0.facing == resolvedFacing
        }?.heights[heightKey(spacing: spacing, doubled: doubled)] ?? 0
        return maximum >= height
    }

    private func partitionLayerCompatible(_ candidateLayers: Int) -> Bool? {
        guard height > 0 else { return nil }
        return options.contains { option in
            option.frame == selectedFrame
                && option.layers == candidateLayers
                && (option.heights[heightKey(spacing: spacing, doubled: doubled)] ?? 0) >= height
        }
    }
}

private enum PartitionSpacingFilter: String, CaseIterable, Identifiable {
    case all = "Tous", forty = "40 cm", sixty = "60 cm"
    var id: Self { self }
    var value: Double? {
        switch self { case .all: nil; case .forty: 0.40; case .sixty: 0.60 }
    }
}

private enum PartitionAssemblyFilter: String, CaseIterable, Identifiable {
    case all = "Tous", single = "Simples", double = "Doublés"
    var id: Self { self }
    var doubled: Bool? {
        switch self { case .all: nil; case .single: false; case .double: true }
    }
}

private struct PartitionHeightCandidate: Identifiable {
    let option: PartitionHeightOption
    let spacing: Double
    let doubled: Bool
    let maximum: Double
    var id: String { "\(option.id)-\(doubled)-\(spacing)" }
}

private func heightKey(spacing: Double, doubled: Bool) -> String {
    "\(doubled ? "double" : "simple")_\(spacing < 0.5 ? "040" : "060")"
}

private func layerTitle(_ layers: Int) -> String {
    layers == 1 ? "1 couche par face" : "\(layers) couches par face"
}

private func liningLayerTitle(_ layers: Int) -> String {
    layers == 1 ? "1 couche" : "\(layers) couches"
}

private func ceilingLayerCount(_ facing: String) -> Int {
    facing.contains("double") ? 2 : 1
}

private func ceilingFacingLabel(_ facing: String, options: [CeilingSpanOption]) -> String {
    options.first { $0.facing == facing }?.facingLabel ?? facing
}

private func insulationMaterials(_ options: [InsulationMassOption]) -> [String] {
    unique(options.map(\.material)).sorted { lhs, rhs in
        let leftGlass = lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("verre")
        let rightGlass = rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("verre")
        return leftGlass == rightGlass ? lhs.localizedStandardCompare(rhs) == .orderedAscending : leftGlass
    }
}

private func insulationLambdas(_ options: [InsulationMassOption], material: String) -> [Double] {
    unique(options.filter { $0.material == material }.map(\.lambda)).filter { $0 > 0 }.sorted()
}

private func insulationThicknesses(_ options: [InsulationMassOption], material: String, lambda: Double) -> [Int] {
    unique(options.filter { $0.material == material && abs($0.lambda - lambda) < 0.000_1 }.map(\.thicknessMM)).sorted()
}

@ViewBuilder private func selectorTitle<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.subheadline.weight(.semibold))
        content()
    }
}

private func frameOrder(_ lhs: String, _ rhs: String) -> Bool {
    let width: (String) -> Int = { value in
        let digits = value.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return Int(digits) ?? .max
    }
    return width(lhs) == width(rhs) ? lhs.localizedStandardCompare(rhs) == .orderedAscending : width(lhs) < width(rhs)
}

private func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
    var seen = Set<Value>()
    return values.filter { seen.insert($0).inserted }
}

private func facingOrder(_ lhs: String, _ rhs: String) -> Bool {
    let number: (String) -> Int = { Int($0.filter(\.isNumber)) ?? .max }
    return number(lhs) == number(rhs) ? lhs < rhs : number(lhs) < number(rhs)
}

private func partitionOptionOrder(_ lhs: PartitionHeightOption, _ rhs: PartitionHeightOption) -> Bool {
    if lhs.frameWidthMM != rhs.frameWidthMM { return lhs.frameWidthMM < rhs.frameWidthMM }
    if lhs.frame != rhs.frame { return lhs.frame.localizedStandardCompare(rhs.frame) == .orderedAscending }
    if lhs.layers != rhs.layers { return lhs.layers < rhs.layers }
    return facingOrder(lhs.facing, rhs.facing)
}

private func candidateOrder(_ lhs: PartitionHeightCandidate, _ rhs: PartitionHeightCandidate) -> Bool {
    if lhs.option.frameWidthMM != rhs.option.frameWidthMM { return lhs.option.frameWidthMM < rhs.option.frameWidthMM }
    if lhs.option.frame != rhs.option.frame { return lhs.option.frame.localizedStandardCompare(rhs.option.frame) == .orderedAscending }
    if lhs.doubled != rhs.doubled { return !lhs.doubled }
    if lhs.spacing != rhs.spacing { return lhs.spacing > rhs.spacing }
    return lhs.maximum < rhs.maximum
}

struct LiningHeightToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var mode = TechnicalSearchMode.verify
    @State private var system = 0
    @State private var height = 0.0
    @State private var selectedFurringID = ""
    @State private var layers = 1
    @State private var facing = "BA13"
    @State private var liningFrame = ""
    @State private var liningSpacing = 0.45
    @State private var liningDoubled = false
    @State private var findLiningSpacing = LiningSpacingFilter.all
    @State private var findLiningAssembly = PartitionAssemblyFilter.all

    private let availableLayers = [1, 2, 3]
    private let availableFacings = ["BA13", "BA15", "BA18"]
    private var filteredLining: [LiningHeightOption] {
        store.liningHeights.filter { $0.layers == layers && $0.supportedFacings.contains(facing) }
    }
    private var filteredFurring: [FurringSupportOption] {
        store.furringSupports.filter { $0.layers == layers && $0.supportedFacings.contains(facing) }
    }
    private var liningFrames: [String] {
        unique(filteredLining.map(\.frame)).sorted(by: frameOrder)
    }
    private var liningSpacings: [Double] {
        unique(filteredLining.filter { $0.frame == liningFrame && $0.assembly == liningAssembly }.map(\.spacing)).sorted()
    }
    private var liningAssembly: String { liningDoubled ? "Montants doublés" : "Montants simples" }
    private var selectedLining: LiningHeightOption? {
        filteredLining.first {
            $0.frame == liningFrame
                && $0.assembly == liningAssembly
                && abs($0.spacing - liningSpacing) < 0.001
        }
    }
    private var selectedFurring: FurringSupportOption? { filteredFurring.first { $0.id == selectedFurringID } ?? filteredFurring.first }
    private var compatibleLining: [LiningHeightOption] {
        filteredLining.filter { option in
            option.maximumHeight >= height
                && (findLiningSpacing.value == nil || abs(option.spacing - (findLiningSpacing.value ?? 0)) < 0.001)
                && (findLiningAssembly.doubled == nil || findLiningAssembly.doubled == (option.assembly == "Montants doublés"))
        }
        .sorted { lhs, rhs in
            if frameOrder(lhs.frame, rhs.frame) { return true }
            if frameOrder(rhs.frame, lhs.frame) { return false }
            if lhs.assembly != rhs.assembly { return lhs.assembly == "Montants simples" }
            return lhs.spacing > rhs.spacing
        }
    }

    var body: some View {
        TechnicalToolForm(title: "Hauteur de doublage", store: store) {
            Section { Picker("Mode", selection: $mode) { ForEach(TechnicalSearchMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
            Section("Système") {
                Picker("Ossature", selection: $system) { Text("Lisses / fourrures").tag(0); Text("Rails / montants").tag(1) }.pickerStyle(.segmented)
                ToolNumberField(title: "Hauteur sous plafond", unit: "m", value: $height)
            }
            Section("Parement") {
                Picker("Nombre de couches", selection: $layers) {
                    ForEach(availableLayers, id: \.self) { value in
                        compatibilityPickerLabel(
                            liningLayerTitle(value),
                            compatible: mode == .verify ? liningLayerCompatible(value) : nil
                        )
                        .tag(value)
                    }
                }
                Picker("Type de parement", selection: $facing) {
                    ForEach(availableFacings, id: \.self) { value in
                        compatibilityPickerLabel(
                            value,
                            compatible: mode == .verify ? liningFacingCompatible(value) : nil
                        )
                        .tag(value)
                    }
                }
            }
            if system == 0 { furringContent } else { liningContent }
        }
        .onAppear { selectFirstOptionsIfNeeded() }
        .onChange(of: store.liningHeights) { _, _ in normalizeFacingSelection() }
        .onChange(of: store.furringSupports) { _, value in
            if selectedFurringID.isEmpty { selectedFurringID = value.first?.id ?? "" }
            normalizeFacingSelection()
        }
        .onChange(of: system) { _, _ in normalizeFacingSelection() }
        .onChange(of: layers) { _, _ in normalizeFacingSelection() }
        .onChange(of: facing) { _, _ in normalizeFacingSelection() }
        .onChange(of: liningFrame) { _, _ in normalizeLiningConfiguration() }
        .onChange(of: liningDoubled) { _, _ in normalizeLiningConfiguration() }
    }

    private func selectFirstOptionsIfNeeded() {
        if selectedFurringID.isEmpty { selectedFurringID = store.furringSupports.first?.id ?? "" }
        normalizeFacingSelection()
    }

    private func normalizeFacingSelection() {
        if !availableLayers.contains(layers) { layers = availableLayers.first ?? 1 }
        if !availableFacings.contains(facing) { facing = availableFacings.first ?? "" }
        if let first = filteredFurring.first, !filteredFurring.contains(where: { $0.id == selectedFurringID }) { selectedFurringID = first.id }
        normalizeLiningConfiguration()
    }

    private func normalizeLiningConfiguration() {
        if !liningFrames.contains(liningFrame) { liningFrame = liningFrames.first ?? "" }
        if !liningSpacings.contains(where: { abs($0 - liningSpacing) < 0.001 }) {
            liningSpacing = liningSpacings.first ?? 0.45
        }
    }

    @ViewBuilder private var furringContent: some View {
        if mode == .verify {
            if let rule = selectedFurring {
                compatibility(maximum: rule.maximumHeight, requested: height)
                Section("Lignes d’appuis") {
                    let count = height > 0 ? max(1, Int(ceil(height / rule.maximumSupportSpacing)) - 1) : 0
                    LabeledContent("Nombre recommandé", value: "\(count)")
                    LabeledContent("Écart maximal", value: meters(rule.maximumSupportSpacing))
                    if count > 0 { Text("Première ligne à 0,60 m du sol, puis répartition régulière dans la limite publiée.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        } else {
            Section("Configurations compatibles") {
                let values = filteredFurring.filter { $0.maximumHeight >= height }.sorted { $0.maximumHeight < $1.maximumHeight }
                if height <= 0 { Text("Renseignez la hauteur sous plafond.").foregroundStyle(.secondary) }
                else if values.isEmpty { Text("Aucun montage sur fourrures publié n’est compatible.").foregroundStyle(.orange) }
                else { ForEach(values) { rule in resultRow(rule.title, maximum: rule.maximumHeight, requested: height) } }
            }
        }
    }

    @ViewBuilder private var liningContent: some View {
        if mode == .verify {
            Section("Configuration de l’ossature") {
                Picker("Système rail / montant", selection: $liningFrame) {
                    ForEach(liningFrames, id: \.self) { value in
                        compatibilityPickerLabel(value, compatible: liningFrameCompatible(value))
                            .tag(value)
                    }
                }
                selectorTitle("Entraxe des montants") {
                    Picker("Entraxe des montants", selection: $liningSpacing) {
                        ForEach(liningSpacings, id: \.self) { value in
                            Text("\(Int(value * 100)) cm").tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                selectorTitle("Configuration des montants") {
                    Picker("Configuration des montants", selection: $liningDoubled) {
                        Text("Simples").tag(false)
                        Text("Doublés").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            if let selectedLining {
                compatibility(maximum: selectedLining.maximumHeight, requested: height)
            } else {
                Section("Résultat") {
                    Label("Aucune hauteur n’est publiée pour cette configuration.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Section {
                selectorTitle("Entraxe des montants") {
                    Picker("Entraxe des montants", selection: $findLiningSpacing) {
                        ForEach(LiningSpacingFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                selectorTitle("Configuration des montants") {
                    Picker("Configuration des montants", selection: $findLiningAssembly) {
                        ForEach(PartitionAssemblyFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            Section("Configurations compatibles") {
                if height <= 0 { Text("Renseignez la hauteur sous plafond.").foregroundStyle(.secondary) }
                else if compatibleLining.isEmpty { Text("Aucun montage rails / montants publié n’est compatible.").foregroundStyle(.orange) }
                else { ForEach(compatibleLining.prefix(20)) { option in resultRow(option.title, maximum: option.maximumHeight, requested: height) } }
            }
        }
    }

    private func liningLayerCompatible(_ candidateLayers: Int) -> Bool? {
        guard height > 0 else { return nil }
        if system == 0 {
            return store.furringSupports.contains {
                $0.layers == candidateLayers && $0.maximumHeight >= height
            }
        }
        return store.liningHeights.contains {
            $0.layers == candidateLayers && $0.maximumHeight >= height
        }
    }

    private func liningFacingCompatible(_ candidateFacing: String) -> Bool? {
        guard height > 0 else { return nil }
        if system == 0 {
            return store.furringSupports.contains {
                $0.layers == layers
                    && $0.supportedFacings.contains(candidateFacing)
                    && $0.maximumHeight >= height
            }
        }
        return store.liningHeights.contains {
            $0.layers == layers
                && $0.supportedFacings.contains(candidateFacing)
                && $0.maximumHeight >= height
        }
    }

    private func liningFrameCompatible(_ candidateFrame: String) -> Bool? {
        guard height > 0 else { return nil }
        return filteredLining.contains {
            $0.frame == candidateFrame
                && $0.assembly == liningAssembly
                && abs($0.spacing - liningSpacing) < 0.001
                && $0.maximumHeight >= height
        }
    }
}

private enum LiningSpacingFilter: String, CaseIterable, Identifiable {
    case all = "Tous", fortyFive = "45 cm", ninety = "90 cm"
    var id: Self { self }
    var value: Double? {
        switch self { case .all: nil; case .fortyFive: 0.45; case .ninety: 0.90 }
    }
}

struct FurringSpacingToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var material = ""
    @State private var lambda = 0.0
    @State private var thicknessMM = 0
    @State private var sheetDirection = SheetDirection.perpendicular

    private var materials: [String] {
        unique(store.insulationMasses.map(\.material)).sorted { lhs, rhs in
            let leftGlass = lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("verre")
            let rightGlass = rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("verre")
            return leftGlass == rightGlass ? lhs.localizedStandardCompare(rhs) == .orderedAscending : leftGlass
        }
    }
    private var lambdas: [Double] {
        unique(store.insulationMasses.filter { $0.material == material }.map(\.lambda)).filter { $0 > 0 }.sorted()
    }
    private var thicknesses: [Int] {
        unique(store.insulationMasses.filter { $0.material == material && abs($0.lambda - lambda) < 0.000_1 }.map(\.thicknessMM)).sorted()
    }
    private var selected: InsulationMassOption? {
        store.insulationMasses.first { $0.material == material && abs($0.lambda - lambda) < 0.000_1 && $0.thicknessMM == thicknessMM }
    }
    private var band: InsulationSpacingBand? { selected.flatMap { item in store.insulationSpacingBands.first { $0.contains(item.surfaceMass) } } }
    private var recommendedSpacing: Double? {
        sheetDirection == .parallel ? 0.40 : band?.spacing
    }

    var body: some View {
        TechnicalToolForm(title: "Entraxe des fourrures", store: store) {
            Section("Isolant") {
                Picker("Type d’isolant", selection: $material) {
                    ForEach(materials, id: \.self) { Text($0).tag($0) }
                }
                Picker("Lambda", selection: $lambda) {
                    ForEach(lambdas, id: \.self) { value in
                        Text("λ \(value.formatted(.number.precision(.fractionLength(3)))) W/(m·K)").tag(value)
                    }
                }
                Picker("Épaisseur", selection: $thicknessMM) {
                    ForEach(thicknesses, id: \.self) { Text("\($0) mm").tag($0) }
                }
            }
            Section("Sens de pose des plaques") {
                HStack(spacing: 3) {
                    ForEach(SheetDirection.allCases) { direction in
                        Button {
                            sheetDirection = direction
                        } label: {
                            Text(direction.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(sheetDirection == direction ? Color(.systemBackground) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            Section("Résultat") {
                if let recommendedSpacing {
                    LabeledContent("Entraxe recommandé", value: "\(Int(recommendedSpacing * 100)) cm")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if sheetDirection == .parallel {
                        Text("La pose parallèle aux fourrures impose un entraxe de 40 cm.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if selected != nil {
                    Label("Aucun entraxe admissible n’est défini pour cet isolant.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("Sélectionnez le type d’isolant, son lambda et son épaisseur.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { normalizeInsulationSelection() }
        .onChange(of: store.insulationMasses) { _, _ in normalizeInsulationSelection() }
        .onChange(of: material) { _, _ in selectPreferredLambdaAndThickness() }
        .onChange(of: lambda) { _, _ in normalizeThickness() }
    }

    private func normalizeInsulationSelection() {
        if !materials.contains(material) { material = materials.first ?? "" }
        selectPreferredLambdaAndThickness()
    }

    private func selectPreferredLambdaAndThickness() {
        let target = material.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("bois") ? 0.036 : 0.035
        if !lambdas.contains(where: { abs($0 - lambda) < 0.000_1 }) {
            lambda = lambdas.first(where: { abs($0 - target) < 0.000_1 }) ?? lambdas.first ?? 0
        }
        normalizeThickness()
    }

    private func normalizeThickness() {
        if !thicknesses.contains(thicknessMM) { thicknessMM = thicknesses.first ?? 0 }
    }
}

private enum SheetDirection: String, CaseIterable, Identifiable {
    case perpendicular = "Perpendiculaire aux fourrures"
    case parallel = "Parallèle aux fourrures"
    var id: Self { self }
    var displayTitle: String {
        switch self {
        case .perpendicular: "Perpendiculaire\naux fourrures"
        case .parallel: "Parallèle\naux fourrures"
        }
    }
}

private struct TechnicalToolForm<Content: View>: View {
    let title: String
    @ObservedObject var store: ToolTechnicalStore
    let content: Content

    init(title: String, store: ToolTechnicalStore, @ViewBuilder content: () -> Content) {
        self.title = title
        self.store = store
        self.content = content()
    }

    var body: some View {
        Form {
            if store.isLoading { Section { HStack { ProgressView(); Text("Chargement du référentiel…") } } }
            if let error = store.error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
            if store.isOffline { Section { Label("Référentiel local hors connexion", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary) } }
            content
        }
        .navigationTitle(title)
    }
}

@ViewBuilder private func compatibility(maximum: Double, requested: Double) -> some View {
    Section("Résultat") {
        if requested <= 0 { Text("Renseignez la dimension à vérifier.").foregroundStyle(.secondary) }
        else if maximum <= 0 { Label("Aucune valeur publiée pour cette configuration.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        else {
            Label(maximum >= requested ? "Configuration compatible" : "Configuration incompatible", systemImage: maximum >= requested ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(maximum >= requested ? .green : .red).font(.headline)
            LabeledContent("Valeur maximale", value: meters(maximum))
        }
    }
}

@ViewBuilder private func compatibilityPickerLabel(_ title: String, compatible: Bool?) -> some View {
    if compatible == false {
        Label {
            Text(title)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    } else {
        Text(title)
    }
}

@ViewBuilder private func resultRow(_ title: String, maximum: Double, requested: Double) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.subheadline.bold())
        Text("Maximum \(meters(maximum))").font(.caption).foregroundStyle(.secondary)
    }
}

private func meters(_ value: Double) -> String { value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(2))) + " m" }
