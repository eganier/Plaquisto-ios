import SwiftUI

struct BondedLiningConfiguratorView: View {
    private enum GeometryMode: String, CaseIterable, Identifiable { case length = "Longueur", surface = "Surface totale"; var id: Self { self } }
    private enum RevealMode: String, CaseIterable, Identifiable { case none = "Aucune tapée", required = "Tapée à respecter"; var id: Self { self } }

    @EnvironmentObject private var references: BondedLiningReferenceStore
    let onSave: (BondedLiningConfiguration) -> Void
    let onClose: () -> Void
    let showsCloseButton: Bool

    @State private var step: Int
    @State private var geometryMode: GeometryMode
    @State private var height: Double
    @State private var enteredLength: Double
    @State private var enteredSurface: Double
    @State private var allocations: [BondedFacingAllocation]
    @State private var selectedLambda: Double
    @State private var revealMode: RevealMode
    @State private var selectedRevealMM: Int
    @State private var selectedThicknessMM: Int
    @State private var selectedWidthMM: Int
    @State private var selectedHeightMM: Int
    @State private var jointTreatment: Bool
    @State private var showPanelHeightWarning = false

    private let green = Color(red: 0.12, green: 0.38, blue: 0.29)
    private let stepNames = ["Dimensions", "Parement", "Isolation et tapée", "Format", "Bandes à joint", "Résultat"]

    init(
        initialConfiguration: BondedLiningConfiguration? = nil,
        startsAtResult: Bool = false,
        onSave: @escaping (BondedLiningConfiguration) -> Void,
        onClose: @escaping () -> Void,
        showsCloseButton: Bool = true
    ) {
        let value = initialConfiguration ?? BondedLiningConfiguration()
        _step = State(initialValue: startsAtResult ? 6 : 1)
        _geometryMode = State(initialValue: value.geometryMode == "surface" ? .surface : .length)
        _height = State(initialValue: value.height)
        _enteredLength = State(initialValue: value.enteredLength)
        _enteredSurface = State(initialValue: value.enteredSurface)
        _allocations = State(initialValue: value.allocations.isEmpty ? [BondedFacingAllocation()] : value.allocations)
        _selectedLambda = State(initialValue: value.lambda)
        _revealMode = State(initialValue: value.hasReveal ? .required : .none)
        _selectedRevealMM = State(initialValue: value.revealMM)
        _selectedThicknessMM = State(initialValue: value.insulationThicknessMM)
        _selectedWidthMM = State(initialValue: value.widthMM)
        _selectedHeightMM = State(initialValue: value.panelHeightMM)
        _jointTreatment = State(initialValue: value.jointTreatment)
        self.onSave = onSave
        self.onClose = onClose
        self.showsCloseButton = showsCloseButton
    }

    private var actualLength: Double { geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0) }
    private var actualArea: Double { geometryMode == .surface ? enteredSurface : enteredLength * height }
    private var selectedFacings: Set<BondedFacingKind> { Set(allocations.map(\.facing)) }
    private var allocatedArea: Double { allocations.reduce(0) { $0 + $1.surface } }
    private var remainingArea: Double { max(0, actualArea - allocatedArea) }
    private var availableLambdas: [Double] { references.commonLambdas(for: selectedFacings) }
    private var availableThicknesses: [Int] { references.commonThicknesses(for: selectedFacings, lambda: selectedLambda) }
    private var availableWidths: [Int] { references.commonWidths(for: selectedFacings, lambda: selectedLambda, thickness: selectedThicknessMM) }
    private var availableHeights: [Int] { references.commonHeights(for: selectedFacings, lambda: selectedLambda, thickness: selectedThicknessMM, width: selectedWidthMM) }
    private var thermalResistance: Double { references.resistance(lambda: selectedLambda, thickness: selectedThicknessMM) ?? 0 }
    private var recommendedThicknessMM: Int { max(0, selectedRevealMM - references.revealOffsetMM) }
    private var panelIsShort: Bool { Double(selectedHeightMM) / 1000 < height }
    private var canContinue: Bool {
        switch step {
        case 1: height > 0 && (geometryMode == .length ? enteredLength > 0 : enteredSurface > 0)
        case 2: !allocations.isEmpty && allocations.allSatisfy { $0.surface > 0 } && abs(allocatedArea - actualArea) < 0.01 && !availableLambdas.isEmpty
        case 3: availableThicknesses.contains(selectedThicknessMM) && !availableWidths.isEmpty
        case 4: availableWidths.contains(selectedWidthMM) && availableHeights.contains(selectedHeightMM)
        default: true
        }
    }

    var body: some View {
        Group {
            if references.isLoading { ProgressView("Synchronisation avec Plaquisto Admin…") }
            else if let error = references.error {
                ContentUnavailableView {
                    Label("Données indisponibles", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: { Button("Réessayer") { Task { await references.load() } } }
            } else { wizard }
        }
        .tint(green)
        .onChange(of: references.references) { _, _ in normalizeAll() }
        .onChange(of: height) { _, _ in normalizeHeightForWork() }
        .onChange(of: allocations) { _, _ in normalizeAll() }
        .onChange(of: selectedLambda) { _, _ in normalizeThickness() }
        .onChange(of: selectedThicknessMM) { _, _ in normalizeFormat() }
        .onChange(of: selectedWidthMM) { _, _ in normalizeHeight() }
        .onChange(of: revealMode) { _, value in
            if value == .required {
                if !references.revealDepthsMM.contains(selectedRevealMM), let first = references.revealDepthsMM.first { selectedRevealMM = first }
                applyRecommendedThickness()
            }
        }
        .onChange(of: selectedRevealMM) { _, _ in applyRecommendedThickness() }
        .alert("Hauteur de panneau insuffisante", isPresented: $showPanelHeightWarning) {
            Button("Revenir au choix", role: .cancel) {}
            Button("Continuer malgré tout") { step += 1 }
        } message: {
            Text("La hauteur du panneau est inférieure à la hauteur sous plafond de \(format(height, "m")). Des raccords seront nécessaires. Confirmez-vous ce choix ?")
        }
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 1: dimensionsStep
                    case 2: facingStep
                    case 3: thermalStep
                    case 4: formatStep
                    case 5: jointsStep
                    default: resultStep
                    }
                }.padding(.horizontal, 20).padding(.vertical, 18)
            }
            footer
        }.background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsCloseButton { Button("Fermer", action: onClose).buttonStyle(.bordered) }
            Text("OUVRAGE").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Doublage périphérique en complexe collé").font(.title2.bold())
            Label("Données synchronisées avec Plaquisto Admin", systemImage: "icloud.and.arrow.down").font(.caption).foregroundStyle(.green)
            ProgressView(value: Double(step), total: 6)
            Text("Étape \(step) sur 6 · \(stepNames[step - 1])").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading).background(.background)
    }

    private var footer: some View {
        HStack {
            if step > 1 { Button("Retour") { step -= 1 }.buttonStyle(.borderedProminent).tint(green.opacity(0.18)).foregroundStyle(green) }
            Spacer()
            if step < 6 { Button("Continuer") { continueForm() }.buttonStyle(.borderedProminent).disabled(!canContinue) }
            else { Button("Enregistrer") { onSave(configuration) }.buttonStyle(.borderedProminent) }
        }.padding(20).background(.background)
    }

    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Dimensions de l’ouvrage")
            card {
                BondedDecimalRow("Hauteur sous plafond", value: $height, unit: "m")
                Divider()
                Picker("Mode de saisie", selection: $geometryMode) { ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Divider()
                if geometryMode == .length { BondedDecimalRow("Longueur du doublage (périmètre)", value: $enteredLength, unit: "m") }
                else { BondedDecimalRow("Surface totale", value: $enteredSurface, unit: "m²") }
            }
            card { LabeledContent(geometryMode == .length ? "Surface calculée" : "Longueur calculée", value: format(geometryMode == .length ? actualArea : actualLength, geometryMode == .length ? "m²" : "m")) }
            Text("La hauteur sous plafond est obligatoire. Renseignez ensuite soit la longueur du doublage, soit sa surface totale.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var facingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Parement")
            Text("Répartissez la surface entre les complexes nécessaires.").font(.footnote).foregroundStyle(.secondary)
            ForEach($allocations) { $allocation in
                card {
                    LabeledContent("Type de parement") {
                        Picker("Type", selection: $allocation.facing) { ForEach(availableFacings(for: allocation.id)) { Text($0.title).tag($0) } }.labelsHidden()
                    }
                    Divider(); BondedDecimalRow("Surface attribuée", value: $allocation.surface, unit: "m²")
                    if allocations.count > 1 { Divider(); Button("Supprimer ce parement", role: .destructive) { allocations.removeAll { $0.id == allocation.id } } }
                }
            }
            if allocations.count < references.facingKinds.count { Button("Ajouter un autre type de parement") { addFacing() }.foregroundStyle(.green) }
            Text(allocationStatus).font(.footnote).foregroundStyle(abs(allocatedArea - actualArea) < 0.01 ? .green : .orange)
        }
    }

    private var thermalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Performance thermique")
            card { LabeledContent("Lambda") { Picker("Lambda", selection: $selectedLambda) { ForEach(availableLambdas, id: \.self) { Text("λ \($0.formatted(.number.precision(.fractionLength(3)))) W/(m·K)").tag($0) } }.labelsHidden() } }
            sectionTitle("Tapée de menuiserie")
            card {
                Picker("Tapée", selection: $revealMode) { ForEach(RevealMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if revealMode == .required { Divider(); LabeledContent("Profondeur de la tapée") { Picker("Profondeur", selection: $selectedRevealMM) { ForEach(references.revealDepthsMM, id: \.self) { Text("\($0) mm").tag($0) } }.labelsHidden() } }
            }
            if revealMode == .required { Text("Pour une tapée de \(selectedRevealMM) mm, l’épaisseur conseillée de PSE est de \(recommendedThicknessMM) mm.").font(.footnote).foregroundStyle(.secondary) }
            sectionTitle("Épaisseur du complexe")
            card {
                LabeledContent("Épaisseur du PSE") { Picker("Épaisseur", selection: $selectedThicknessMM) { ForEach(availableThicknesses, id: \.self) { Text(thicknessLabel($0)).tag($0) } }.labelsHidden() }
                Divider(); LabeledContent("Épaisseur totale", value: "\(selectedThicknessMM + 13) mm")
                Divider(); LabeledContent("Résistance thermique", value: "R = \(thermalResistance.formatted(.number.precision(.fractionLength(2)))) m²·K/W")
            }
            if revealMode == .none { Text("Sans tapée à respecter, choisissez librement l’épaisseur parmi les complexes disponibles.").font(.footnote).foregroundStyle(.secondary) }
            if revealMode == .required && selectedThicknessMM != recommendedThicknessMM { warning("Cette épaisseur ne correspond pas exactement à la tapée de \(selectedRevealMM) mm. L’épaisseur conseillée de PSE est de \(recommendedThicknessMM) mm.") }
        }
    }

    private var formatStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Format du panneau")
            card {
                LabeledContent("Largeur") { Picker("Largeur", selection: $selectedWidthMM) { ForEach(availableWidths, id: \.self) { Text("\($0) mm").tag($0) } }.labelsHidden() }
                Divider(); LabeledContent("Hauteur") { Picker("Hauteur", selection: $selectedHeightMM) { ForEach(availableHeights, id: \.self) { Text("\($0) mm").tag($0) } }.labelsHidden() }
            }
            if selectedWidthMM == 600 { Text("Le format de 600 mm reste limité aux dimensions réellement disponibles dans le catalogue.").font(.footnote).foregroundStyle(.secondary) }
            if panelIsShort { warning("La hauteur sélectionnée est inférieure à la hauteur sous plafond de \(format(height, "m")).") }
        }
    }

    private var jointsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Bandes à joint")
            card { Toggle("Prévoir le traitement des bandes à joint", isOn: $jointTreatment); if jointTreatment { Divider(); LabeledContent("Enduit", value: "Enduit en poudre") } }
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Configuration retenue")
            card {
                LabeledContent("Dimensions", value: "\(format(actualLength, "m")) × \(format(height, "m"))"); Divider()
                LabeledContent("Surface", value: format(actualArea, "m²")); Divider()
                LabeledContent("Lambda", value: "λ \(selectedLambda.formatted(.number.precision(.fractionLength(3)))) W/(m·K)"); Divider()
                LabeledContent("Complexe", value: "13+\(selectedThicknessMM)"); Divider()
                LabeledContent("Résistance thermique", value: "R = \(thermalResistance.formatted(.number.precision(.fractionLength(2)))) m²·K/W"); Divider()
                LabeledContent("Tapée", value: revealMode == .none ? "Aucune tapée à respecter" : "\(selectedRevealMM) mm"); Divider()
                LabeledContent("Format", value: "\(selectedWidthMM) × \(selectedHeightMM) mm")
            }
            sectionTitle("Quantitatif indicatif")
            card { ForEach(configuration.quantities) { item in LabeledContent(item.name, value: format(item.quantity, item.unit)); if item.id != configuration.quantities.last?.id { Divider() } } }
        }
    }

    private var configuration: BondedLiningConfiguration {
        var rows = allocations.map { BondedLiningQuantity(name: references.supplyName(for: $0.facing), quantity: $0.surface * references.quantities.complex, unit: "m²") }
        rows.append(.init(name: references.quantities.names["adhesive"] ?? "Mortier adhésif", quantity: actualArea * references.quantities.adhesive, unit: "kg"))
        if jointTreatment {
            rows.append(.init(name: references.quantities.names["band"] ?? "Bande à joint", quantity: actualArea * references.quantities.band, unit: "ml"))
            rows.append(.init(name: references.quantities.names["powder"] ?? "Enduit en poudre", quantity: actualArea * references.quantities.powder, unit: "kg"))
        }
        return BondedLiningConfiguration(geometryMode: geometryMode == .surface ? "surface" : "length", height: height, enteredLength: enteredLength, enteredSurface: enteredSurface, allocations: allocations, lambda: selectedLambda, hasReveal: revealMode == .required, revealMM: selectedRevealMM, insulationThicknessMM: selectedThicknessMM, widthMM: selectedWidthMM, panelHeightMM: selectedHeightMM, jointTreatment: jointTreatment, quantities: rows)
    }

    private var allocationStatus: String {
        let delta = actualArea - allocatedArea
        if abs(delta) < 0.01 { return "Répartition complète : \(format(actualArea, "m²"))." }
        return delta > 0 ? "Il reste \(format(delta, "m²")) à répartir." : "La surface attribuée dépasse celle de l’ouvrage de \(format(-delta, "m²"))."
    }
    private func availableFacings(for id: UUID) -> [BondedFacingKind] {
        let used = Set(allocations.filter { $0.id != id }.map(\.facing)); return references.facingKinds.filter { !used.contains($0) }
    }
    private func addFacing() {
        let used = Set(allocations.map(\.facing)); guard let next = references.facingKinds.first(where: { !used.contains($0) }) else { return }
        allocations.append(.init(facing: next, surface: remainingArea))
    }
    private func normalizeAll() {
        guard !references.references.isEmpty else { return }
        for index in allocations.indices where !references.facingKinds.contains(allocations[index].facing) { allocations[index].facing = references.facingKinds[0] }
        if let first = availableLambdas.first, !availableLambdas.contains(where: { abs($0 - selectedLambda) < 0.0001 }) { selectedLambda = first }
        if revealMode == .required, let first = references.revealDepthsMM.first, !references.revealDepthsMM.contains(selectedRevealMM) { selectedRevealMM = first }
        normalizeThickness()
    }
    private func normalizeThickness() {
        guard !availableThicknesses.isEmpty else { return }
        if !availableThicknesses.contains(selectedThicknessMM) { selectedThicknessMM = availableThicknesses.min { abs($0 - selectedThicknessMM) < abs($1 - selectedThicknessMM) }! }
        normalizeFormat()
    }
    private func applyRecommendedThickness() {
        guard revealMode == .required, !availableThicknesses.isEmpty else { return }
        selectedThicknessMM = availableThicknesses.contains(recommendedThicknessMM) ? recommendedThicknessMM : availableThicknesses.min { abs($0 - recommendedThicknessMM) < abs($1 - recommendedThicknessMM) }!
    }
    private func normalizeFormat() {
        guard !availableWidths.isEmpty else { return }
        if !availableWidths.contains(selectedWidthMM) { selectedWidthMM = availableWidths[0] }
        normalizeHeight()
    }
    private func normalizeHeight() {
        guard !availableHeights.isEmpty else { return }
        if !availableHeights.contains(selectedHeightMM) { selectedHeightMM = availableHeights.first(where: { Double($0) / 1000 >= height }) ?? availableHeights.last! }
    }
    private func normalizeHeightForWork() {
        guard !availableHeights.isEmpty, Double(selectedHeightMM) / 1000 < height else { return }
        selectedHeightMM = availableHeights.first(where: { Double($0) / 1000 >= height }) ?? availableHeights.last!
    }
    private func continueForm() {
        if step == 1, allocations.count == 1, allocations[0].surface == 0 { allocations[0].surface = actualArea }
        if step == 4 && panelIsShort { showPanelHeightWarning = true } else { step += 1 }
    }
    private func thicknessLabel(_ value: Int) -> String { "\(value) mm — R = \((references.resistance(lambda: selectedLambda, thickness: value) ?? 0).formatted(.number.precision(.fractionLength(2))))" }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.title3.bold()).foregroundStyle(.secondary).padding(.horizontal, 12) }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 14, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 22)) }
    private func warning(_ text: String) -> some View { HStack(alignment: .top, spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(text) }.font(.footnote).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18)) }
    private func format(_ value: Double, _ unit: String) -> String { "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)" }
}

private struct BondedDecimalRow: View {
    let title: String; @Binding var value: Double; let unit: String
    init(_ title: String, value: Binding<Double>, unit: String) { self.title = title; _value = value; self.unit = unit }
    var body: some View { HStack { Text(title); Spacer(); TextField("0", value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 58, maxWidth: 100); Text(unit).foregroundStyle(.secondary) } }
}
