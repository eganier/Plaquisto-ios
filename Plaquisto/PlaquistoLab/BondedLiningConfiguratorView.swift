import SwiftUI

struct BondedLiningConfiguratorView: View {
    private enum GeometryMode: String, CaseIterable, Identifiable { case length = "Longueur", surface = "Surface totale"; var id: Self { self } }
    private enum RevealMode: String, CaseIterable, Identifiable { case none = "Aucune tapée", required = "Tapée à respecter"; var id: Self { self } }

    @EnvironmentObject private var references: BondedLiningReferenceStore
    @State private var step = 1
    @State private var geometryMode = GeometryMode.length
    @State private var height = 0.0
    @State private var enteredLength = 0.0
    @State private var enteredSurface = 0.0
    @State private var allocations = [BondedFacingAllocation()]
    @State private var selectedLambda = 0.032
    @State private var revealMode = RevealMode.none
    @State private var selectedRevealMM = 120
    @State private var selectedThicknessMM = 100
    @State private var selectedWidthMM = 1200
    @State private var selectedHeightMM = 2500
    @State private var jointTreatment = true
    @State private var showPanelHeightWarning = false

    private let green = Color(red: 0.12, green: 0.38, blue: 0.29)
    private let stepNames = ["Dimensions", "Parement", "Isolation et tapée", "Format", "Bandes à joint", "Résultat"]
    private var actualLength: Double { geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0) }
    private var actualArea: Double { geometryMode == .surface ? enteredSurface : enteredLength * height }
    private var selectedFacings: Set<BondedFacingFunction> { Set(allocations.map(\.facing)) }
    private var allocatedArea: Double { allocations.reduce(0) { $0 + $1.surface } }
    private var remainingArea: Double { max(0, actualArea - allocatedArea) }
    private var availableLambdas: [Double] { references.commonLambdas(for: selectedFacings) }
    private var availableThicknesses: [Int] { references.commonThicknesses(for: selectedFacings, lambda: selectedLambda) }
    private var availableWidths: [Int] { references.commonWidths(for: selectedFacings, lambda: selectedLambda, thickness: selectedThicknessMM) }
    private var availableHeights: [Int] { references.commonHeights(for: selectedFacings, lambda: selectedLambda, thickness: selectedThicknessMM, width: selectedWidthMM) }
    private var thermalResistance: Double { references.resistance(lambda: selectedLambda, thickness: selectedThicknessMM) ?? 0 }
    private var recommendedThicknessMM: Int { max(0, selectedRevealMM - 20) }
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
        NavigationStack { wizard }
            .tint(green)
            .onChange(of: height) { _, _ in normalizeHeightForWork() }
            .onChange(of: allocations) { _, _ in normalizeThermalSelection() }
            .onChange(of: selectedLambda) { _, _ in normalizeThickness() }
            .onChange(of: selectedThicknessMM) { _, _ in normalizeFormat() }
            .onChange(of: selectedWidthMM) { _, _ in normalizeHeight() }
            .onChange(of: revealMode) { _, value in if value == .required { applyRecommendedThickness() } }
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
            Button("Fermer") { reset() }.buttonStyle(.bordered)
            Text("OUVRAGE").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Doublage périphérique en complexe collé").font(.title2.bold())
            Label("Données de travail intégrées à Plaquisto Lab", systemImage: "hammer").font(.caption).foregroundStyle(.orange)
            ProgressView(value: Double(step), total: 6)
            Text("Étape \(step) sur 6 · \(stepNames[step - 1])").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14).background(.background)
    }

    private var footer: some View {
        HStack {
            if step > 1 { Button("Retour") { step -= 1 }.buttonStyle(.borderedProminent).tint(green.opacity(0.18)).foregroundStyle(green) }
            Spacer()
            if step < 6 { Button("Continuer") { continueForm() }.buttonStyle(.borderedProminent).disabled(!canContinue) }
            else { Button("Recommencer") { reset() }.buttonStyle(.borderedProminent) }
        }.padding(20).background(.background)
    }

    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Dimensions de l’ouvrage")
            formCard {
                BondedDecimalRow("Hauteur sous plafond", value: $height, unit: "m")
                Divider()
                Picker("Mode de saisie", selection: $geometryMode) { ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Divider()
                if geometryMode == .length { BondedDecimalRow("Longueur du doublage (périmètre)", value: $enteredLength, unit: "m") }
                else { BondedDecimalRow("Surface totale", value: $enteredSurface, unit: "m²") }
            }
            formCard { LabeledContent(geometryMode == .length ? "Surface calculée" : "Longueur calculée", value: format(geometryMode == .length ? actualArea : actualLength, geometryMode == .length ? "m²" : "m")) }
            Text("La hauteur sous plafond est obligatoire. Renseignez ensuite soit la longueur du doublage, soit sa surface totale.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var facingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Parement")
            Text("Répartissez la surface entre les complexes standards, hydrofuges ou pare-vapeur nécessaires.").font(.footnote).foregroundStyle(.secondary)
            ForEach($allocations) { $allocation in
                formCard {
                    LabeledContent("Type de parement") {
                        Picker("Type", selection: $allocation.facing) { ForEach(availableFacings(for: allocation.id)) { Text($0.rawValue).tag($0) } }.labelsHidden()
                    }
                    Divider()
                    BondedDecimalRow("Surface attribuée", value: $allocation.surface, unit: "m²")
                    if allocations.count > 1 { Divider(); Button("Supprimer ce parement", role: .destructive) { allocations.removeAll { $0.id == allocation.id } } }
                }
            }
            if allocations.count < BondedFacingFunction.allCases.count { Button("Ajouter un autre type de parement") { addFacing() }.foregroundStyle(.green) }
            Text(allocationStatus).font(.footnote).foregroundStyle(abs(allocatedArea - actualArea) < 0.01 ? .green : .orange)
        }
    }

    private var thermalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Performance thermique")
            formCard {
                LabeledContent("Lambda") {
                    Picker("Lambda", selection: $selectedLambda) { ForEach(availableLambdas, id: \.self) { Text("λ \($0.formatted(.number.precision(.fractionLength(3)))) W/(m·K)").tag($0) } }.labelsHidden()
                }
            }
            sectionTitle("Tapée de menuiserie")
            formCard {
                Picker("Tapée", selection: $revealMode) { ForEach(RevealMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if revealMode == .required {
                    Divider()
                    LabeledContent("Profondeur de la tapée") { Picker("Profondeur", selection: $selectedRevealMM) { ForEach(availableRevealDepths, id: \.self) { Text("\($0) mm").tag($0) } }.labelsHidden() }
                }
            }
            if revealMode == .required { Text("Pour une tapée de \(selectedRevealMM) mm, l’épaisseur conseillée de PSE est de \(recommendedThicknessMM) mm.").font(.footnote).foregroundStyle(.secondary) }
            sectionTitle("Épaisseur du complexe")
            formCard {
                LabeledContent("Épaisseur du PSE") { Picker("Épaisseur", selection: $selectedThicknessMM) { ForEach(availableThicknesses, id: \.self) { Text(thicknessLabel($0)).tag($0) } }.labelsHidden() }
                Divider(); LabeledContent("Épaisseur totale", value: "\(selectedThicknessMM + 13) mm")
                Divider(); LabeledContent("Résistance thermique", value: "R = \(thermalResistance.formatted(.number.precision(.fractionLength(2)))) m²·K/W")
            }
            if revealMode == .none { Text("Sans tapée de menuiserie à respecter, choisissez librement l’épaisseur souhaitée parmi les complexes disponibles.").font(.footnote).foregroundStyle(.secondary) }
            if revealMode == .required && selectedThicknessMM != recommendedThicknessMM { warningCard("Cette épaisseur ne correspond pas exactement à la tapée de \(selectedRevealMM) mm. L’épaisseur conseillée de PSE est de \(recommendedThicknessMM) mm.") }
        }
    }

    private var formatStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Format du panneau")
            formCard {
                LabeledContent("Largeur") { Picker("Largeur", selection: $selectedWidthMM) { ForEach(availableWidths, id: \.self) { Text("\($0) mm").tag($0) } }.labelsHidden() }
                Divider()
                LabeledContent("Hauteur") { Picker("Hauteur", selection: $selectedHeightMM) { ForEach(availableHeights, id: \.self) { Text("\($0) mm").tag($0) } }.labelsHidden() }
            }
            if selectedWidthMM == 600 { Text("Le format de 600 mm est destiné notamment aux accès difficiles et reste limité aux dimensions vérifiées.").font(.footnote).foregroundStyle(.secondary) }
            if panelIsShort { warningCard("La hauteur sélectionnée est inférieure à la hauteur sous plafond de \(format(height, "m")).") }
        }
    }

    private var jointsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Bandes à joint")
            formCard { Toggle("Prévoir le traitement des bandes à joint", isOn: $jointTreatment); if jointTreatment { Divider(); LabeledContent("Enduit", value: "Enduit en poudre") } }
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Configuration retenue")
            formCard {
                LabeledContent("Dimensions", value: "\(format(actualLength, "m")) × \(format(height, "m"))"); Divider()
                LabeledContent("Surface", value: format(actualArea, "m²")); Divider()
                LabeledContent("Lambda", value: "λ \(selectedLambda.formatted(.number.precision(.fractionLength(3)))) W/(m·K)"); Divider()
                LabeledContent("Complexe", value: "13+\(selectedThicknessMM)"); Divider()
                LabeledContent("Résistance thermique", value: "R = \(thermalResistance.formatted(.number.precision(.fractionLength(2)))) m²·K/W"); Divider()
                LabeledContent("Tapée", value: revealMode == .none ? "Aucune tapée à respecter" : "\(selectedRevealMM) mm"); Divider()
                LabeledContent("Format", value: "\(selectedWidthMM) × \(selectedHeightMM) mm")
            }
            sectionTitle("Quantitatif indicatif")
            formCard {
                ForEach(Array(allocations.enumerated()), id: \.element.id) { index, allocation in
                    if index > 0 { Divider() }
                    LabeledContent(allocation.facing.supplyName, value: format(allocation.surface * references.quantities.complexM2PerM2, "m²"))
                }
                Divider(); LabeledContent("Mortier adhésif", value: format(actualArea * references.quantities.adhesiveKgPerM2, "kg"))
                if jointTreatment {
                    Divider(); LabeledContent("Bande à joint", value: format(actualArea * references.quantities.bandMLPerM2, "ml"))
                    Divider(); LabeledContent("Enduit en poudre", value: format(actualArea * references.quantities.powderKgPerM2, "kg"))
                }
            }
        }
    }

    private var availableRevealDepths: [Int] { [40, 60, 80, 100, 120, 140, 160, 180, 200] }
    private var allocationStatus: String {
        let delta = actualArea - allocatedArea
        if abs(delta) < 0.01 { return "Répartition complète : \(format(actualArea, "m²"))." }
        if delta > 0 { return "Il reste \(format(delta, "m²")) à répartir." }
        return "La surface attribuée dépasse la surface de l’ouvrage de \(format(-delta, "m²"))."
    }
    private func availableFacings(for id: UUID) -> [BondedFacingFunction] {
        let used = Set(allocations.filter { $0.id != id }.map(\.facing))
        return BondedFacingFunction.allCases.filter { !used.contains($0) }
    }
    private func addFacing() {
        let used = Set(allocations.map(\.facing))
        guard let next = BondedFacingFunction.allCases.first(where: { !used.contains($0) }) else { return }
        allocations.append(.init(facing: next, surface: remainingArea))
    }
    private func initializeFirstSurfaceIfNeeded() { if allocations.count == 1 && allocations[0].surface == 0 && actualArea > 0 { allocations[0].surface = actualArea } }
    private func normalizeThermalSelection() {
        guard !availableLambdas.isEmpty else { return }
        if !availableLambdas.contains(where: { abs($0 - selectedLambda) < 0.0001 }) { selectedLambda = availableLambdas[0] }
        normalizeThickness()
        normalizeReveal()
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
    private func normalizeReveal() {
        guard revealMode == .required, !availableRevealDepths.isEmpty, !availableRevealDepths.contains(selectedRevealMM) else { return }
        selectedRevealMM = availableRevealDepths.min { abs($0 - selectedRevealMM) < abs($1 - selectedRevealMM) }!
    }
    private func continueForm() {
        if step == 1 { initializeFirstSurfaceIfNeeded() }
        if step == 4 && panelIsShort { showPanelHeightWarning = true } else { step += 1 }
    }
    private func thicknessLabel(_ thickness: Int) -> String {
        let resistance = references.resistance(lambda: selectedLambda, thickness: thickness) ?? 0
        return "\(thickness) mm — R = \(resistance.formatted(.number.precision(.fractionLength(2))))"
    }
    private func reset() {
        step = 1; geometryMode = .length; height = 0; enteredLength = 0; enteredSurface = 0
        allocations = [.init()]; selectedLambda = 0.032; revealMode = .none; selectedRevealMM = 120
        selectedThicknessMM = 100; selectedWidthMM = 1200; selectedHeightMM = 2500; jointTreatment = true
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.title3.bold()).foregroundStyle(.secondary).padding(.horizontal, 12) }
    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 14, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 22)) }
    private func warningCard(_ text: String) -> some View { HStack(alignment: .top, spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(text) }.font(.footnote).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18)) }
    private func format(_ value: Double, _ unit: String) -> String { "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)" }
}

private struct BondedDecimalRow: View {
    let title: String; @Binding var value: Double; let unit: String
    init(_ title: String, value: Binding<Double>, unit: String) { self.title = title; _value = value; self.unit = unit }
    var body: some View {
        HStack { Text(title); Spacer(); TextField("0", value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 58, maxWidth: 100); Text(unit).foregroundStyle(.secondary) }
    }
}
