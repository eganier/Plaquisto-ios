import SwiftUI

struct FurringLiningConfiguratorView: View {
    private enum GeometryMode: String, CaseIterable, Identifiable {
        case length = "Longueur"
        case surface = "Surface totale"
        var id: Self { self }
    }

    private enum SkinCount: Int, CaseIterable, Identifiable {
        case single = 1
        case double = 2
        case triple = 3
        var id: Self { self }
        var title: String {
            switch self {
            case .single: "Simple peau"
            case .double: "Double peau"
            case .triple: "Triple peau"
            }
        }
    }

    private enum VaporBarrierInstallation: String, CaseIterable, Identifiable {
        case throughSupports = "À travers les appuis"
        case tapedOnFurrings = "Scotché sur les fourrures"
        var id: Self { self }
    }

    private enum Compound: String, CaseIterable, Identifiable {
        case powder = "Enduit en poudre"
        case paste = "Enduit en pâte"
        var id: Self { self }
    }

    @EnvironmentObject private var catalogue: FurringLiningReferenceStore
    private let onSave: ((FurringLiningConfiguration) -> Void)?
    private let onClose: (() -> Void)?
    private let showsCloseButton: Bool
    private let green = Color(red: 0.12, green: 0.38, blue: 0.29)

    @State private var step = 1
    @State private var geometryMode = GeometryMode.length
    @State private var height = 0.0
    @State private var enteredLength = 0.0
    @State private var enteredSurface = 0.0
    @State private var specifiesWallCount = true
    @State private var wallCount = 4

    @State private var skinCount = SkinCount.single
    @State private var firstSkin = [FurringFacingSelection()]
    @State private var secondSkin = [FurringFacingSelection()]
    @State private var thirdSkin = [FurringFacingSelection()]
    @State private var tiledArea = false
    @State private var tiledAreaSurface = 0.0

    @State private var selectedSupportLines = 1
    @State private var supportLinesWereEdited = false
    @State private var insulationEnabled = true
    @State private var firstInsulation = FurringInsulationSelection()
    @State private var vaporBarrier = false
    @State private var vaporBarrierInstallation = VaporBarrierInstallation.throughSupports
    @State private var jointTreatment = true
    @State private var compound = Compound.powder
    @State private var showPlateHeightWarning = false
    @State private var showSupportWarning = false

    init(initialConfiguration: FurringLiningConfiguration? = nil, startsAtResult: Bool = false, onSave: ((FurringLiningConfiguration) -> Void)? = nil, onClose: (() -> Void)? = nil, showsCloseButton: Bool = true) {
        let configuration = initialConfiguration ?? FurringLiningConfiguration()
        self.onSave = onSave; self.onClose = onClose; self.showsCloseButton = showsCloseButton
        _step = State(initialValue: startsAtResult ? 6 : 1)
        _geometryMode = State(initialValue: configuration.geometryMode == "surface" ? .surface : .length)
        _height = State(initialValue: configuration.height); _enteredLength = State(initialValue: configuration.enteredLength); _enteredSurface = State(initialValue: configuration.enteredSurface)
        _specifiesWallCount = State(initialValue: initialConfiguration == nil || configuration.wallCount != nil); _wallCount = State(initialValue: max(1, configuration.wallCount ?? 4))
        _skinCount = State(initialValue: SkinCount(rawValue: configuration.layers) ?? .single)
        _firstSkin = State(initialValue: configuration.firstSkin.isEmpty ? [.init()] : configuration.firstSkin)
        _secondSkin = State(initialValue: configuration.secondSkin.isEmpty ? [.init()] : configuration.secondSkin)
        _thirdSkin = State(initialValue: configuration.thirdSkin.isEmpty ? [.init()] : configuration.thirdSkin)
        _tiledArea = State(initialValue: configuration.tiledArea); _tiledAreaSurface = State(initialValue: configuration.tiledAreaSurface)
        _selectedSupportLines = State(initialValue: configuration.selectedSupportLines); _supportLinesWereEdited = State(initialValue: initialConfiguration != nil)
        _insulationEnabled = State(initialValue: configuration.insulationEnabled); _firstInsulation = State(initialValue: configuration.firstInsulation)
        _vaporBarrier = State(initialValue: configuration.vaporBarrier)
        _vaporBarrierInstallation = State(initialValue: configuration.vaporBarrierInstallation == "taped_on_furrings" ? .tapedOnFurrings : .throughSupports)
        _jointTreatment = State(initialValue: configuration.jointTreatment); _compound = State(initialValue: configuration.compoundChoice == "pate" ? .paste : .powder)
    }

    private let stepNames = ["Dimensions", "Parements", "Ossature et appuis", "Isolation", "Bandes à joint", "Résultat"]
    private var facings: [DoublageFacingChoice] { catalogue.facings }
    private var insulationFamilies: [DoublageInsulationFamily] { catalogue.insulationFamilies }
    private var actualLength: Double { geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0) }
    private var actualArea: Double { geometryMode == .surface ? enteredSurface : enteredLength * height }
    private var calculationWallCount: Int { specifiesWallCount ? wallCount : 1 }
    private var effectiveTiledArea: Double { tiledArea ? min(max(tiledAreaSurface, 0), actualArea) : 0 }
    private var nonTiledArea: Double { max(0, actualArea - effectiveTiledArea) }
    private var tiledAreaIsValid: Bool { !tiledArea || (tiledAreaSurface > 0 && tiledAreaSurface <= actualArea + 0.001) }

    private var selectedLayers: [[FurringFacingSelection]] {
        switch skinCount {
        case .single: [firstSkin]
        case .double: [firstSkin, secondSkin]
        case .triple: [firstSkin, secondSkin, thirdSkin]
        }
    }

    private var selectedFormats: [DoublageFacingFormat] {
        selectedLayers.flatMap { $0.compactMap(selectedFormat) }
    }

    private var containsBA18Width900: Bool {
        selectedLayers.flatMap { $0 }.contains { selection in
            facing(for: selection)?.mechanicalFamily == "BA18" && selectedFormat(selection)?.widthMM == 900
        }
    }

    private var standardFurringSpacing: Double { containsBA18Width900 ? catalogue.ba18Width900FurringSpacing : catalogue.normalFurringSpacing }
    private var tiledAreaRequires40CM: Bool {
        guard tiledArea, effectiveTiledArea > 0, skinCount == .single else { return false }
        return firstSkin.contains { selection in
            guard let family = facing(for: selection)?.mechanicalFamily else { return false }
            return catalogue.tiledAreaSingleFacingFamilies.contains(family)
        }
    }

    private var selectedRule: FurringLiningSupportRule? {
        switch skinCount {
        case .single:
            let families = Set(firstSkin.compactMap { facing(for: $0)?.mechanicalFamily })
            if containsBA18Width900 { return catalogue.rule("single-ba18-900") }
            if !families.isEmpty && families.isSubset(of: ["BA13", "BA15"]) { return catalogue.rule("single-ba13-ba15") }
            if families.contains("BA13") || families.contains("BA15") { return catalogue.rule("single-ba13-ba15") }
            if families == ["BA18"] { return catalogue.rule("single-ba18") }
            return nil
        case .double:
            let firstFamilies = Set(firstSkin.compactMap { facing(for: $0)?.mechanicalFamily })
            let secondFamilies = Set(secondSkin.compactMap { facing(for: $0)?.mechanicalFamily })
            guard !firstFamilies.isEmpty, !secondFamilies.isEmpty,
                  firstFamilies.isSubset(of: ["BA13", "BA18"]),
                  secondFamilies.isSubset(of: ["BA13", "BA18"]),
                  !(firstFamilies.contains("BA18") && secondFamilies.contains("BA18")) else { return nil }
            return catalogue.rule("double-skin")
        case .triple:
            let families = selectedLayers.flatMap { $0.compactMap { facing(for: $0)?.mechanicalFamily } }
            guard families.count >= 3, families.allSatisfy({ $0 == "BA13" }) else { return nil }
            return catalogue.rule("triple-ba13")
        }
    }

    private var recommendedSupportLines: Int {
        guard let selectedRule else { return 0 }
        return FurringLiningCalculator.recommendedSupportLines(height: height, maximumSpacing: selectedRule.maximumSupportSpacing)
    }

    private var furringCount: Int {
        let base = FurringLiningCalculator.furringAxes(length: actualLength, spacing: standardFurringSpacing, wallCount: calculationWallCount)
        guard tiledAreaRequires40CM, standardFurringSpacing > catalogue.tiledAreaMaximumSpacing, actualArea > 0 else { return base }
        let tiledLength = actualLength * effectiveTiledArea / actualArea
        let currentBays = Int(ceil(tiledLength / standardFurringSpacing))
        let tiledBays = Int(ceil(tiledLength / catalogue.tiledAreaMaximumSpacing))
        return base + max(0, tiledBays - currentBays)
    }

    private var verticalFurringLength: Double {
        Double(furringCount) * height * catalogue.quantities["furring_waste_factor"]
    }
    private var intermediateHorizontalFurringLength: Double {
        actualLength * Double(selectedSupportLines) * catalogue.quantities["furring_waste_factor"]
    }
    private var totalFurringLength: Double {
        verticalFurringLength + intermediateHorizontalFurringLength
    }
    private var thermalResistanceTotal: Double {
        guard insulationEnabled else { return 0 }
        return thermalResistance(firstInsulation)
    }

    private var canContinue: Bool {
        switch step {
        case 1:
            return height > 0 && (!specifiesWallCount || wallCount > 0) && (geometryMode == .length ? enteredLength > 0 : enteredSurface > 0)
        case 2:
            return allLayersAreComplete && selectedRule != nil && tiledAreaIsValid
        case 3:
            return selectedRule.map { height <= $0.maximumHeight } ?? false
        case 4:
            return !insulationEnabled || insulationIsComplete(firstInsulation)
        default:
            return true
        }
    }

    var body: some View {
        Group {
            if catalogue.isLoading {
                ProgressView("Chargement depuis Plaquisto Admin…")
            } else if let error = catalogue.error {
                ContentUnavailableView("Données indisponibles", systemImage: "exclamationmark.icloud", description: Text(error))
            } else {
                wizard
            }
        }
        .tint(green)
        .onChange(of: facings.count, initial: true) { _, _ in initializeFacingsIfNeeded() }
        .onChange(of: insulationFamilies.count, initial: true) { _, _ in initializeInsulationIfNeeded() }
        .onChange(of: skinCount) { _, _ in normalizeSkinCount() }
        .onChange(of: firstSkin) { _, _ in normalizeSupportLines() }
        .onChange(of: secondSkin) { _, _ in normalizeSupportLines() }
        .onChange(of: thirdSkin) { _, _ in normalizeSupportLines() }
        .onChange(of: height) { _, _ in normalizeSupportLines() }
        .onChange(of: tiledArea) { _, enabled in if !enabled { tiledAreaSurface = 0 } }
        .alert("Hauteur de plaque insuffisante", isPresented: $showPlateHeightWarning) {
            Button("Revenir au choix", role: .cancel) {}
            Button("Continuer malgré tout") { step += 1 }
        } message: {
            Text("Au moins une plaque est plus courte que la hauteur sous plafond de \(format(height, "m")). Des raccords seront nécessaires. Confirmez-vous cette configuration ?")
        }
        .alert("Nombre d’appuis inférieur à la recommandation", isPresented: $showSupportWarning) {
            Button("Revenir au choix", role: .cancel) {}
            Button("Continuer malgré tout") { step += 1 }
        } message: {
            Text(supportWarningText)
        }
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 1: dimensionsStep
                    case 2: facingsStep
                    case 3: framingStep
                    case 4: insulationStep
                    case 5: jointsStep
                    default: resultStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            footer
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsCloseButton { Button("Fermer") { onClose?() }.buttonStyle(.bordered) }
            Text("OUVRAGE").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Doublage périphérique sur lisses et fourrures").font(.title2.bold())
            Label("Données synchronisées avec Plaquisto Admin", systemImage: "checkmark.icloud")
                .font(.caption).foregroundStyle(.green)
            ProgressView(value: Double(step), total: 6)
            Text("Étape \(step) sur 6 · \(stepNames[step - 1])").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14).background(.background)
    }

    private var footer: some View {
        HStack {
            if step > 1 { Button("Retour") { step -= 1 }.buttonStyle(.bordered) }
            Spacer()
            if step < 6 {
                Button("Continuer") { advance() }.buttonStyle(.borderedProminent).disabled(!canContinue)
            } else if let onSave {
                Button("Enregistrer") { onSave(configurationSnapshot()) }.buttonStyle(.borderedProminent)
            } else {
                Button("Recommencer") { reset() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.background)
    }

    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Dimensions de l’ouvrage")
            card {
                FurringDecimalRow("Hauteur sous plafond", value: $height, unit: "m")
                Divider()
                Picker("Deuxième mesure", selection: $geometryMode) { ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Divider()
                if geometryMode == .length {
                    FurringDecimalRow("Longueur du doublage (périmètre)", value: $enteredLength, unit: "m")
                } else {
                    FurringDecimalRow("Surface totale", value: $enteredSurface, unit: "m²")
                }
                Divider()
                Toggle("Préciser le nombre de murs", isOn: $specifiesWallCount)
                if specifiesWallCount {
                    Divider()
                    FurringIntegerRow("Nombre de murs", value: $wallCount)
                }
            }
            card {
                LabeledContent(geometryMode == .length ? "Surface calculée" : "Longueur calculée", value: format(geometryMode == .length ? actualArea : actualLength, geometryMode == .length ? "m²" : "m"))
            }
            Text(specifiesWallCount
                 ? "La hauteur sous plafond est obligatoire. Le nombre de murs est prérempli à 4 afin de tenir compte des fourrures placées aux extrémités de chaque mur."
                 : "Le nombre de murs n’est pas renseigné. Le quantitatif des fourrures sera estimé uniquement à partir de la longueur totale et sera légèrement moins précis.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var facingsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Nombre de peaux")
            card {
                Picker("Nombre de peaux", selection: $skinCount) {
                    ForEach(SkinCount.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Divider()
                Toggle("Une partie de la surface sera carrelée", isOn: $tiledArea)
                if tiledArea {
                    Divider()
                    FurringDecimalRow("Surface carrelée", value: $tiledAreaSurface, unit: "m²")
                }
            }
            if tiledArea {
                infoCard("Avec un parement simple BA13 ou BA15, la surface carrelée sera réalisée avec des fourrures espacées de 40 cm au lieu de 60 cm. Le reste de l’ouvrage conserve son entraxe normal.", icon: "square.grid.3x3.fill", color: .orange)
            }
            if tiledArea && !tiledAreaIsValid {
                Text("La surface carrelée doit être supérieure à 0 m² et ne peut pas dépasser la surface de l’ouvrage.").font(.footnote).foregroundStyle(.red).padding(.horizontal, 12)
            }
            skinSection(title: "Première peau", selections: $firstSkin, layer: 1)
            if skinCount.rawValue >= 2 { skinSection(title: "Deuxième peau", selections: $secondSkin, layer: 2) }
            if skinCount == .triple { skinSection(title: "Troisième peau", selections: $thirdSkin, layer: 3) }
            if skinCount != .single {
                Text("L’ordre des parements n’a aucune incidence.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            if selectedRule == nil && allLayerSurfacesAreComplete {
                warningCard("Cette association de parements n’est pas prévue dans le tableau technique. Les doubles peaux autorisées sont 2 × BA13 ou BA13 + BA18. La triple peau autorisée est 3 × BA13.")
            }
        }
    }

    @ViewBuilder
    private func skinSection(title: String, selections: Binding<[FurringFacingSelection]>, layer: Int) -> some View {
        sectionTitle(title)
        ForEach(selections.wrappedValue.indices, id: \.self) { index in
            facingCard(selection: selections[index], layer: layer, canDelete: selections.wrappedValue.count > 1)
        }
        Button("Ajouter un autre type de parement") { addFacing(to: selections, layer: layer) }
            .buttonStyle(.borderless).padding(.horizontal, 12)
        allocationStatus(selections.wrappedValue)
    }

    private func facingCard(selection: Binding<FurringFacingSelection>, layer: Int, canDelete: Bool) -> some View {
        card {
            LabeledContent("Type de plaque") {
                Picker("Type de plaque", selection: familyBinding(selection)) {
                    ForEach(availableFamilies(layer: layer), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }.frame(height: 28)
            Divider()
            LabeledContent("Fonction") {
                Picker("Fonction", selection: facingBinding(selection)) {
                    ForEach(availableFunctions(for: selection.wrappedValue, layer: layer)) { Text($0.functionTitle).tag($0.id) }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }.frame(height: 28)
            Divider()
            LabeledContent("Dimension") {
                Picker("Dimension", selection: selection.formatID) {
                    ForEach(availableFormats(for: selection.wrappedValue)) { Text($0.title).tag($0.id) }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }.frame(height: 28)
            Divider()
            FurringDecimalRow("Surface attribuée", value: selection.surface, unit: "m²")
            if height > 0, let formatChoice = selectedFormat(selection.wrappedValue), Double(formatChoice.lengthMM) / 1000 < height {
                Label("Cette hauteur est inférieure à la hauteur sous plafond de \(format(height, "m")).", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if canDelete {
                Divider()
                Button("Supprimer ce type", role: .destructive) { removeFacing(selection.wrappedValue.id, layer: layer) }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var framingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Lisses et fourrures")
            card {
                LabeledContent("Technique", value: "Lisses et fourrures")
                Divider(); LabeledContent("Entraxe courant", value: "\(Int(standardFurringSpacing * 100)) cm")
                if tiledAreaRequires40CM {
                    Divider(); LabeledContent("Zone carrelée", value: "\(format(effectiveTiledArea, "m²")) à entraxe 40 cm")
                    Divider(); LabeledContent("Zone non carrelée", value: "\(format(nonTiledArea, "m²")) à entraxe \(Int(standardFurringSpacing * 100)) cm")
                }
                Divider(); LabeledContent("Nombre estimé de fourrures", value: "\(furringCount)")
            }
            if containsBA18Width900 {
                infoCard("Les plaques BA18 de 900 mm de large imposent un entraxe de fourrures de 45 cm.", icon: "ruler", color: .orange)
            }
            sectionTitle("Appuis intermédiaires")
            card {
                if let selectedRule {
                    LabeledContent("Distance maximale", value: format(selectedRule.maximumSupportSpacing, "m"))
                    Divider(); LabeledContent("Nombre recommandé", value: "\(recommendedSupportLines) ligne\(recommendedSupportLines > 1 ? "s" : "")")
                    Divider()
                    Stepper(value: Binding(
                        get: { selectedSupportLines },
                        set: { selectedSupportLines = $0; supportLinesWereEdited = true }
                    ), in: 0...12) {
                        LabeledContent("Nombre choisi", value: "\(selectedSupportLines)")
                    }
                }
            }
            if selectedSupportLines >= 2 {
                infoCard("La première ligne est placée à 60 cm du sol. Implantation indicative : \(supportPositionsText).", icon: "arrow.up.and.down", color: .green)
            } else if selectedSupportLines == 1, let selectedRule {
                infoCard("La ligne d’appuis peut être placée jusqu’à \(format(selectedRule.maximumSupportSpacing, "m")) du sol.", icon: "arrow.up", color: .green)
            }
            if selectedSupportLines > 0 {
                infoCard("Le quantitatif des fourrures inclut aussi \(selectedSupportLines) ligne\(selectedSupportLines > 1 ? "s" : "") horizontale\(selectedSupportLines > 1 ? "s" : ""), soit \(format(actualLength * Double(selectedSupportLines), "ml")) avant marge.", icon: "equal", color: .green)
            }
            if selectedSupportLines < recommendedSupportLines { warningCard(supportWarningText) }
            if let selectedRule, height > selectedRule.maximumHeight {
                warningCard("La hauteur sous plafond de \(format(height, "m")) dépasse la hauteur maximale autorisée de \(format(selectedRule.maximumHeight, "m")) pour ce montage.")
            }
            infoCard("L’aboutage des fourrures est interdit.", icon: "exclamationmark.circle", color: .secondary)
        }
    }

    private var insulationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Isolation du doublage")
            card {
                Toggle("Prévoir une isolation", isOn: $insulationEnabled)
            }
            if insulationEnabled {
                sectionTitle("Isolant")
                insulationCard(selection: $firstInsulation)
                card { LabeledContent("Résistance thermique totale", value: "R = \(thermalResistanceTotal.formatted(.number.precision(.fractionLength(2)))) m²·K/W") }
            }
            sectionTitle("Pare-vapeur")
            card {
                Toggle("Prévoir la pose d’un pare-vapeur", isOn: $vaporBarrier)
                if vaporBarrier {
                    Divider()
                    Picker("Mode de fixation", selection: $vaporBarrierInstallation) {
                        ForEach(VaporBarrierInstallation.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            if vaporBarrier {
                if vaporBarrierInstallation == .throughSupports {
                    infoCard("Le pare-vapeur est maintenu à travers les appuis intermédiaires. Aucun scotch double-face n’est ajouté au quantitatif.", icon: "checkmark.circle", color: .green)
                } else {
                    infoCard("Le pare-vapeur est scotché sur les fourrures verticales. Le quantitatif prévoit une longueur de scotch double-face égale à leur longueur totale.", icon: "info.circle", color: .green)
                }
            }
        }
    }

    private func insulationCard(selection: Binding<FurringInsulationSelection>) -> some View {
        card {
            LabeledContent("Type d’isolant") {
                Picker("Type d’isolant", selection: insulationFamilyBinding(selection)) {
                    ForEach(insulationFamilies) { Text($0.title).tag($0.id) }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
            Divider()
            LabeledContent("Lambda") {
                Picker("Lambda", selection: insulationLambdaBinding(selection)) {
                    ForEach(insulationLambdas(selection.wrappedValue)) { option in
                        Text("λ \(option.value.formatted(.number.precision(.fractionLength(3)))) W/(m·K)").tag(option.value)
                    }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
            Divider()
            LabeledContent("Épaisseur") {
                Picker("Épaisseur", selection: selection.thicknessMM) {
                    ForEach(insulationThicknesses(selection.wrappedValue), id: \.self) { thickness in
                        Text("\(thickness) mm — R = \(thermalResistance(thicknessMM: thickness, lambda: selection.wrappedValue.lambda).formatted(.number.precision(.fractionLength(2))))").tag(thickness)
                    }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var jointsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Traitement des bandes à joint")
            card {
                Toggle("Prévoir le traitement des bandes", isOn: $jointTreatment)
                if jointTreatment {
                    Divider()
                    Picker("Type d’enduit", selection: $compound) { ForEach(Compound.allCases) { Text($0.rawValue).tag($0) } }
                }
            }
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoCard("Quantitatif calculé pour \(format(actualArea, "m²")) de doublage.", icon: "checkmark.seal.fill", color: .green)
            sectionTitle("Configuration retenue")
            card {
                LabeledContent("Dimensions", value: "\(format(actualLength, "m")) × \(format(height, "m"))")
                Divider(); LabeledContent("Nombre de murs", value: specifiesWallCount ? "\(wallCount)" : "Non renseigné")
                Divider(); LabeledContent("Parement", value: selectedRule?.title ?? skinCount.title)
                Divider(); LabeledContent("Entraxe des fourrures", value: tiledAreaRequires40CM ? "\(Int(standardFurringSpacing * 100)) cm + zone carrelée à 40 cm" : "\(Int(standardFurringSpacing * 100)) cm")
                Divider(); LabeledContent("Lignes d’appuis", value: "\(selectedSupportLines)")
                Divider(); LabeledContent("Isolation", value: insulationEnabled ? "Une épaisseur" : "Non")
                if insulationEnabled { Divider(); LabeledContent("Résistance thermique totale", value: "R = \(thermalResistanceTotal.formatted(.number.precision(.fractionLength(2)))) m²·K/W") }
                Divider(); LabeledContent("Pare-vapeur", value: vaporBarrier ? vaporBarrierInstallation.rawValue : "Non")
            }
            sectionTitle("Quantitatif indicatif")
            card {
                ForEach(Array(resultRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    LabeledContent(row.0, value: row.1)
                }
            }
            if skinCount == .triple {
                infoCard("La quantité de vis de troisième peau est estimée avec le ratio d’une peau supplémentaire. La longueur exacte de la vis devra être définie dans Plaquisto Admin.", icon: "info.circle", color: .orange)
            }
        }
    }

    private var resultRows: [(String, String)] {
        guard actualArea > 0 else { return [] }
        var totals: [String: (Double, String)] = [:]
        for layer in selectedLayers {
            for selection in layer {
                guard let facing = facing(for: selection), let plateFormat = selectedFormat(selection) else { continue }
                let name = "\(facing.title) · \(plateFormat.title)"
                let quantity = selection.surface * catalogue.quantities["plate_m2_m2"]
                totals[name, default: (0, "m²")].0 += quantity
            }
        }
        var rows = totals.keys.sorted().map { key in (key, format(totals[key]!.0, totals[key]!.1)) }
        rows.append((catalogue.quantities.name("furring", fallback: "Fourrures F45/F47"), format(totalFurringLength, "ml")))
        rows.append((catalogue.quantities.name("rail", fallback: "Rails pour fourrure ou lisses de doublage"), format(actualLength * 2 * catalogue.quantities["rail_waste_factor"], "ml")))
        rows.append((catalogue.quantities.name("supports", fallback: "Appuis intermédiaires pour doublage sur fourrure"), "\(furringCount * selectedSupportLines) unités"))

        let screwFactor = spacingQuantityFactor
        if skinCount == .single {
            rows.append((catalogue.quantities.name("ttpc_first", fallback: "Vis TTPC 25 ou 35"), format(actualArea * catalogue.quantities["ttpc_first_skin_unit_m2"] * screwFactor, "unités", rounded: true)))
        } else {
            rows.append((catalogue.quantities.name("ttpc_first", fallback: "Vis TTPC 25 ou 35"), format(actualArea * catalogue.quantities["ttpc_first_skin_multiple_unit_m2"] * screwFactor, "unités", rounded: true)))
            rows.append((catalogue.quantities.name("ttpc_additional", fallback: "Vis TTPC 45"), format(actualArea * catalogue.quantities["ttpc_additional_skin_unit_m2"] * screwFactor, "unités", rounded: true)))
            if skinCount == .triple {
                rows.append((catalogue.quantities.name("ttpc_third", fallback: "Vis TTPC adaptée à la troisième peau"), format(actualArea * catalogue.quantities["ttpc_additional_skin_unit_m2"] * screwFactor, "unités", rounded: true)))
            }
        }
        rows.append((catalogue.quantities.name("trpf13", fallback: "Vis TRPF 13"), format(actualArea * catalogue.quantities["trpf13_unit_m2"] * screwFactor, "unités", rounded: true)))

        if insulationEnabled {
            rows.append(("Isolation · \(insulationDescription(firstInsulation))", format(actualArea * catalogue.quantities["insulation_m2_m2"], "m²")))
        }
        if vaporBarrier {
            rows.append((catalogue.quantities.name("vapor_barrier", fallback: "Pare-vapeur"), format(actualArea * catalogue.quantities["vapor_barrier_m2_m2"], "m²")))
            if vaporBarrierInstallation == .tapedOnFurrings {
                rows.append((catalogue.quantities.name("double_sided_tape", fallback: "Scotch double-face"), format(verticalFurringLength, "ml")))
            }
        }
        if jointTreatment {
            rows.append((catalogue.quantities.name("band", fallback: "Bande à joint"), format(actualArea * catalogue.quantities["band_ml_m2"], "ml")))
            let coefficient = compound == .powder ? catalogue.quantities["powder_kg_m2"] : catalogue.quantities["paste_kg_m2"]
            rows.append((compound.rawValue, format(actualArea * coefficient, "kg")))
        }
        return rows
    }

    private var spacingQuantityFactor: Double {
        guard actualArea > 0 else { return 1 }
        let standardPart = nonTiledArea * (catalogue.normalFurringSpacing / standardFurringSpacing)
        let tiledSpacing = tiledAreaRequires40CM ? catalogue.tiledAreaMaximumSpacing : standardFurringSpacing
        let tiledPart = effectiveTiledArea * (catalogue.normalFurringSpacing / tiledSpacing)
        return (standardPart + tiledPart) / actualArea
    }

    private var allLayerSurfacesAreComplete: Bool {
        selectedLayers.allSatisfy { layer in
            !layer.isEmpty && layer.allSatisfy { $0.surface > 0 } && abs(layer.reduce(0) { $0 + $1.surface } - actualArea) < 0.01
        }
    }

    private var allLayersAreComplete: Bool {
        allLayerSurfacesAreComplete && selectedLayers.flatMap { $0 }.allSatisfy { facing(for: $0) != nil && selectedFormat($0) != nil }
    }

    private var platesAreShort: Bool {
        selectedFormats.contains { Double($0.lengthMM) / 1000 < height }
    }

    private var supportWarningText: String {
        guard let selectedRule else { return "Le montage sélectionné ne permet pas de déterminer les appuis." }
        return "Avec une hauteur sous plafond de \(format(height, "m")) et ce parement, \(recommendedSupportLines) ligne\(recommendedSupportLines > 1 ? "s" : "") d’appuis sont recommandées, avec une distance maximale de \(format(selectedRule.maximumSupportSpacing, "m")). Vous en avez choisi \(selectedSupportLines)."
    }

    private var supportPositionsText: String {
        guard let selectedRule, selectedSupportLines > 0 else { return "aucune ligne" }
        if selectedSupportLines == 1 { return format(min(selectedRule.maximumSupportSpacing, max(0, height - 0.10)), "m") }
        let spacing: Double
        if selectedSupportLines > recommendedSupportLines {
            spacing = min(selectedRule.maximumSupportSpacing, max(0, height - catalogue.firstSupportHeightWhenMultiple) / Double(selectedSupportLines))
        } else {
            spacing = selectedRule.maximumSupportSpacing
        }
        return (0..<selectedSupportLines).map { index in
            format(min(height, catalogue.firstSupportHeightWhenMultiple + Double(index) * spacing), "m")
        }.joined(separator: ", ")
    }

    private func skinSelections(_ layer: Int) -> [FurringFacingSelection] {
        switch layer { case 1: firstSkin; case 2: secondSkin; default: thirdSkin }
    }

    private func availableFamilies(layer: Int) -> [String] {
        let all = Set(facings.map(\.mechanicalFamily))
        switch skinCount {
        case .single: return all.filter { ["BA13", "BA15", "BA18"].contains($0) }.sorted(by: familySort)
        case .double: return all.filter { ["BA13", "BA18"].contains($0) }.sorted(by: familySort)
        case .triple: return all.contains("BA13") ? ["BA13"] : []
        }
    }

    private func availableFunctions(for selection: FurringFacingSelection, layer: Int) -> [DoublageFacingChoice] {
        let family = facing(for: selection)?.mechanicalFamily ?? availableFamilies(layer: layer).first ?? ""
        return facings.filter { $0.mechanicalFamily == family }
    }

    private func availableFormats(for selection: FurringFacingSelection) -> [DoublageFacingFormat] {
        facing(for: selection)?.formats ?? []
    }

    private func facing(for selection: FurringFacingSelection) -> DoublageFacingChoice? {
        facings.first { $0.id == selection.facingID }
    }

    private func selectedFormat(_ selection: FurringFacingSelection) -> DoublageFacingFormat? {
        facing(for: selection)?.formats.first { $0.id == selection.formatID }
    }

    private func familyBinding(_ selection: Binding<FurringFacingSelection>) -> Binding<String> {
        Binding(get: { facing(for: selection.wrappedValue)?.mechanicalFamily ?? "" }, set: { family in
            guard let nextFacing = facings.first(where: { $0.mechanicalFamily == family }), let nextFormat = nextFacing.formats.first else { return }
            selection.wrappedValue.facingID = nextFacing.id
            selection.wrappedValue.formatID = nextFormat.id
        })
    }

    private func facingBinding(_ selection: Binding<FurringFacingSelection>) -> Binding<String> {
        Binding(get: { selection.wrappedValue.facingID }, set: { facingID in
            guard let nextFacing = facings.first(where: { $0.id == facingID }) else { return }
            selection.wrappedValue.facingID = facingID
            if !nextFacing.formats.contains(where: { $0.id == selection.wrappedValue.formatID }) {
                selection.wrappedValue.formatID = nextFacing.formats.first?.id ?? ""
            }
        })
    }

    private func addFacing(to selections: Binding<[FurringFacingSelection]>, layer: Int) {
        guard let facing = facings.first(where: { availableFamilies(layer: layer).contains($0.mechanicalFamily) }), let formatChoice = facing.formats.first else { return }
        let allocated = selections.wrappedValue.reduce(0) { $0 + $1.surface }
        selections.wrappedValue.append(.init(facingID: facing.id, formatID: formatChoice.id, surface: max(0, actualArea - allocated)))
    }

    private func removeFacing(_ id: UUID, layer: Int) {
        switch layer {
        case 1: firstSkin.removeAll { $0.id == id }
        case 2: secondSkin.removeAll { $0.id == id }
        default: thirdSkin.removeAll { $0.id == id }
        }
    }

    private func allocationStatus(_ selections: [FurringFacingSelection]) -> some View {
        let remaining = actualArea - selections.reduce(0) { $0 + $1.surface }
        return Group {
            if abs(remaining) < 0.01 { Text("Répartition complète : \(format(actualArea, "m²")).").foregroundStyle(.green) }
            else if remaining > 0 { Text("Il reste \(format(remaining, "m²")) à répartir.").foregroundStyle(.orange) }
            else { Text("La surface attribuée dépasse de \(format(abs(remaining), "m²")).").foregroundStyle(.red) }
        }.font(.footnote).padding(.horizontal, 12)
    }

    private func initializeFacingsIfNeeded() {
        guard let facing = facings.first(where: { $0.mechanicalFamily == "BA13" }), let formatChoice = facing.formats.first else { return }
        func initialized(_ values: [FurringFacingSelection]) -> [FurringFacingSelection] {
            if values.count == 1, values[0].facingID.isEmpty {
                return [.init(id: values[0].id, facingID: facing.id, formatID: formatChoice.id, surface: values[0].surface)]
            }
            return values
        }
        firstSkin = initialized(firstSkin)
        secondSkin = initialized(secondSkin)
        thirdSkin = initialized(thirdSkin)
    }

    private func initializeLayerSurfaces() {
        func filled(_ values: [FurringFacingSelection]) -> [FurringFacingSelection] {
            guard values.count == 1, values[0].surface == 0 else { return values }
            var next = values; next[0].surface = actualArea; return next
        }
        firstSkin = filled(firstSkin)
        secondSkin = filled(secondSkin)
        thirdSkin = filled(thirdSkin)
    }

    private func normalizeSkinCount() {
        initializeFacingsIfNeeded()
        normalizeFacingFamilies()
        initializeLayerSurfaces()
        normalizeSupportLines(force: true)
    }

    private func normalizeFacingFamilies() {
        let activeLayerCount = skinCount.rawValue
        for layer in 1...activeLayerCount {
            let allowed = availableFamilies(layer: layer)
            guard let fallbackFamily = allowed.first,
                  let fallbackFacing = facings.first(where: { $0.mechanicalFamily == fallbackFamily }),
                  let fallbackFormat = fallbackFacing.formats.first else { continue }
            func normalized(_ selections: [FurringFacingSelection]) -> [FurringFacingSelection] {
                selections.map { selection in
                    guard let selectedFacing = facing(for: selection), allowed.contains(selectedFacing.mechanicalFamily) else {
                        return .init(id: selection.id, facingID: fallbackFacing.id, formatID: fallbackFormat.id, surface: selection.surface)
                    }
                    return selection
                }
            }
            switch layer {
            case 1: firstSkin = normalized(firstSkin)
            case 2: secondSkin = normalized(secondSkin)
            default: thirdSkin = normalized(thirdSkin)
            }
        }
    }

    private func normalizeSupportLines(force: Bool = false) {
        guard force || !supportLinesWereEdited else { return }
        selectedSupportLines = max(1, recommendedSupportLines)
    }

    private func familySort(_ lhs: String, _ rhs: String) -> Bool {
        (Int(lhs.dropFirst(2)) ?? 0) < (Int(rhs.dropFirst(2)) ?? 0)
    }

    private func insulationFamily(_ selection: FurringInsulationSelection) -> DoublageInsulationFamily? {
        insulationFamilies.first { $0.id == selection.familyID }
    }

    private func insulationLambdas(_ selection: FurringInsulationSelection) -> [DoublageInsulationLambda] {
        insulationFamily(selection)?.lambdas ?? []
    }

    private func insulationThicknesses(_ selection: FurringInsulationSelection) -> [Int] {
        insulationLambdas(selection).first { abs($0.value - selection.lambda) < 0.000_001 }?.thicknessesMM ?? []
    }

    private func insulationFamilyBinding(_ selection: Binding<FurringInsulationSelection>) -> Binding<String> {
        Binding(get: { selection.wrappedValue.familyID }, set: { familyID in
            guard let family = insulationFamilies.first(where: { $0.id == familyID }), let lambda = family.lambdas.first else { return }
            selection.wrappedValue = .init(familyID: familyID, lambda: lambda.value, thicknessMM: lambda.thicknessesMM.first ?? 0)
        })
    }

    private func insulationLambdaBinding(_ selection: Binding<FurringInsulationSelection>) -> Binding<Double> {
        Binding(get: { selection.wrappedValue.lambda }, set: { lambda in
            var next = selection.wrappedValue
            next.lambda = lambda
            next.thicknessMM = insulationLambdas(next).first(where: { abs($0.value - lambda) < 0.000_001 })?.thicknessesMM.first ?? 0
            selection.wrappedValue = next
        })
    }

    private func initializeInsulationIfNeeded() {
        guard let family = insulationFamilies.first(where: {
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("laine de verre")
        }) ?? insulationFamilies.first,
        let lambda = family.lambdas.first else { return }
        let fallback = FurringInsulationSelection(familyID: family.id, lambda: lambda.value, thicknessMM: lambda.thicknessesMM.first ?? 0)
        if insulationFamily(firstInsulation) == nil { firstInsulation = fallback }
    }

    private func insulationIsComplete(_ selection: FurringInsulationSelection) -> Bool {
        insulationFamily(selection) != nil && insulationThicknesses(selection).contains(selection.thicknessMM)
    }

    private func thermalResistance(_ selection: FurringInsulationSelection) -> Double {
        thermalResistance(thicknessMM: selection.thicknessMM, lambda: selection.lambda)
    }

    private func thermalResistance(thicknessMM: Int, lambda: Double) -> Double {
        guard lambda > 0 else { return 0 }
        return Double(thicknessMM) / 1000 / lambda
    }

    private func insulationDescription(_ selection: FurringInsulationSelection) -> String {
        let family = insulationFamily(selection)?.title ?? "Isolant"
        return "\(family), \(selection.thicknessMM) mm, λ \(selection.lambda.formatted(.number.precision(.fractionLength(3))))"
    }

    private func advance() {
        if step == 1 { initializeLayerSurfaces() }
        if step == 2 && platesAreShort { showPlateHeightWarning = true; return }
        if step == 3 && selectedSupportLines < recommendedSupportLines { showSupportWarning = true; return }
        step += 1
    }

    private func configurationSnapshot() -> FurringLiningConfiguration {
        FurringLiningConfiguration(
            geometryMode: geometryMode == .surface ? "surface" : "length", height: height, enteredLength: enteredLength, enteredSurface: enteredSurface,
            wallCount: specifiesWallCount ? wallCount : nil, layers: skinCount.rawValue, firstSkin: firstSkin, secondSkin: secondSkin, thirdSkin: thirdSkin,
            tiledArea: tiledArea, tiledAreaSurface: tiledAreaSurface, selectedSupportLines: selectedSupportLines, insulationEnabled: insulationEnabled,
            firstInsulation: firstInsulation, vaporBarrier: vaporBarrier,
            vaporBarrierInstallation: vaporBarrierInstallation == .tapedOnFurrings ? "taped_on_furrings" : "through_supports",
            jointTreatment: jointTreatment, compoundChoice: compound == .paste ? "pate" : "poudre", quantities: quantitySnapshot
        )
    }

    private var quantitySnapshot: [DoublageQuantity] {
        resultRows.compactMap { row in
            let normalized = row.1.replacingOccurrences(of: ",", with: ".")
            guard let token = normalized.split(separator: " ").first, let value = Double(token) else { return nil }
            let unit = normalized.contains("m²") ? "m²" : normalized.contains("ml") ? "ml" : normalized.contains("kg") ? "kg" : "unité"
            return DoublageQuantity(name: row.0, quantity: value, unit: unit)
        }
    }

    private func reset() {
        step = 1; geometryMode = .length; height = 0; enteredLength = 0; enteredSurface = 0; specifiesWallCount = true; wallCount = max(1, catalogue.defaultWallCount)
        skinCount = .single; firstSkin = [.init()]; secondSkin = [.init()]; thirdSkin = [.init()]
        tiledArea = false; tiledAreaSurface = 0; selectedSupportLines = 1; supportLinesWereEdited = false
        insulationEnabled = true; firstInsulation = .init()
        vaporBarrier = false; vaporBarrierInstallation = .throughSupports; jointTreatment = true; compound = .powder
        initializeFacingsIfNeeded(); initializeInsulationIfNeeded()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.bold()).foregroundStyle(.secondary).padding(.horizontal, 12)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func warningCard(_ text: String) -> some View {
        infoCard(text, icon: "exclamationmark.triangle.fill", color: .orange)
    }

    private func infoCard(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) { Image(systemName: icon).foregroundStyle(color); Text(text) }
            .font(.footnote).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private func format(_ value: Double, _ unit: String, rounded: Bool = false) -> String {
        let shown = rounded ? Double(Int(ceil(value))) : value
        return "\(shown.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }
}

private struct FurringDecimalRow: View {
    let title: String
    @Binding var value: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, unit: String) {
        self.title = title; _value = value; self.unit = unit
    }

    var body: some View {
        HStack {
            Text(title); Spacer()
            TextField("0", value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 58, maxWidth: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

private struct FurringIntegerRow: View {
    let title: String
    @Binding var value: Int

    init(_ title: String, value: Binding<Int>) {
        self.title = title; _value = value
    }

    var body: some View {
        Stepper(value: $value, in: 1...100) { LabeledContent(title, value: "\(value)") }
    }
}
