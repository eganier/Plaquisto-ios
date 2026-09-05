import SwiftUI

struct CloisonDistributionConfiguratorView: View {
    enum GeometryMode: String, CaseIterable, Identifiable {
        case length = "Longueur"
        case surface = "Surface totale"
        var id: Self { self }
    }

    enum SkinCount: String, CaseIterable, Identifiable {
        case single = "Simple peau"
        case double = "Double peau"
        var id: Self { self }
    }

    enum StudMounting: String, CaseIterable, Identifiable {
        case simple = "Montants simples"
        case double = "Montants doubles"
        var id: Self { self }
    }

    enum Compound: String, CaseIterable, Identifiable {
        case powder = "Enduit en poudre"
        case paste = "Enduit en pâte"
        var id: Self { self }
    }

    typealias FacingAllocation = CloisonFacingSelection

    @EnvironmentObject private var references: CloisonDistributionReferenceStore
    private let onSave: ((CloisonDistributionConfiguration) -> Void)?
    private let onClose: (() -> Void)?
    private let showsCloseButton: Bool
    @State private var step = 1
    @State private var geometryMode = GeometryMode.length
    @State private var height = 0.0
    @State private var enteredLength = 0.0
    @State private var enteredSurface = 0.0
    @State private var skinCount = SkinCount.single
    @State private var faceAFirst = [FacingAllocation()]
    @State private var faceASecond = [FacingAllocation()]
    @State private var faceBFirst = [FacingAllocation()]
    @State private var faceBSecond = [FacingAllocation()]
    @State private var mounting = StudMounting.simple
    @State private var selectedFrame = "R48 + M48/35"
    @State private var spacing = 0.60
    @State private var systemID = ""
    @State private var insulationEnabled = true
    @State private var insulationID = ""
    @State private var insulationThicknessMM = 0
    @State private var jointTreatment = true
    @State private var compound = Compound.powder
    @State private var showPlateHeightWarning = false

    init(
        initialConfiguration: CloisonDistributionConfiguration? = nil,
        startsAtResult: Bool = false,
        onSave: ((CloisonDistributionConfiguration) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        showsCloseButton: Bool = true
    ) {
        let configuration = initialConfiguration ?? CloisonDistributionConfiguration()
        self.onSave = onSave
        self.onClose = onClose
        self.showsCloseButton = showsCloseButton
        _step = State(initialValue: startsAtResult ? 7 : 1)
        _geometryMode = State(initialValue: configuration.geometryMode == "surface" ? .surface : .length)
        _height = State(initialValue: configuration.height)
        _enteredLength = State(initialValue: configuration.enteredLength)
        _enteredSurface = State(initialValue: configuration.enteredSurface)
        _skinCount = State(initialValue: configuration.layers == 2 ? .double : .single)
        _faceAFirst = State(initialValue: configuration.faceAFirst.isEmpty ? [FacingAllocation()] : configuration.faceAFirst)
        _faceASecond = State(initialValue: configuration.faceASecond.isEmpty ? [FacingAllocation()] : configuration.faceASecond)
        _faceBFirst = State(initialValue: configuration.faceBFirst.isEmpty ? [FacingAllocation()] : configuration.faceBFirst)
        _faceBSecond = State(initialValue: configuration.faceBSecond.isEmpty ? [FacingAllocation()] : configuration.faceBSecond)
        _mounting = State(initialValue: configuration.doubledStuds ? .double : .simple)
        _selectedFrame = State(initialValue: configuration.frame)
        _spacing = State(initialValue: configuration.spacing)
        _insulationEnabled = State(initialValue: configuration.insulationEnabled)
        _insulationID = State(initialValue: configuration.insulationID)
        _insulationThicknessMM = State(initialValue: configuration.insulationThicknessMM)
        _jointTreatment = State(initialValue: configuration.jointTreatment)
        _compound = State(initialValue: configuration.compoundChoice == "pate" ? .paste : .powder)
    }

    private let stepNames = ["Dimensions", "Ossature", "Parements", "Vérification", "Isolation", "Bandes à joint", "Résultat"]
    private let green = Color(red: 0.12, green: 0.38, blue: 0.29)

    private var actualLength: Double {
        geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0)
    }

    private var actualArea: Double {
        geometryMode == .surface ? enteredSurface : enteredLength * height
    }

    private var selectedSystem: CloisonSystem? {
        compatibleSystems.first(where: { $0.id == systemID })
    }

    private var selectedInsulation: CloisonInsulation? {
        references.insulations.first(where: { $0.id == insulationID })
    }

    private var compatibleSystems: [CloisonSystem] {
        let layers = skinCount == .double ? 2 : 1
        return references.systems.filter {
            $0.frame == selectedFrame &&
            $0.layersPerFace == layers &&
            compatibleFacingFamilies.contains($0.facingFamily)
        }
    }

    private var compatibleFacingFamilies: Set<String> {
        return [governingFamily]
    }

    private var governingFamily: String {
        if skinCount == .double { return "BA13" }
        let families = (faceAFirst + faceBFirst).compactMap { facing($0)?.family }
        if families.contains("BA18") { return "BA18" }
        if families.contains("BA15") { return "BA15" }
        return "BA13"
    }

    private var maximumHeight: Double {
        guard let selectedSystem else { return 0 }
        return selectedSystem.heights[heightKey] ?? 0
    }

    private var heightKey: String {
        "\(mounting == .simple ? "simple" : "double")_\(spacing < 0.5 ? "040" : "060")"
    }

    private var selectedFrameWidthMM: Int {
        references.systems.first(where: { $0.frame == selectedFrame })?.frameWidthMM ?? 48
    }

    private var availableFrames: [String] {
        Array(Set(references.systems.map(\.frame))).sorted { lhs, rhs in
            let left = references.systems.first(where: { system in system.frame == lhs })?.frameWidthMM ?? 0
            let right = references.systems.first(where: { system in system.frame == rhs })?.frameWidthMM ?? 0
            return left == right ? lhs < rhs : left < right
        }
    }

    private var preliminaryHeightRange: ClosedRange<Double>? {
        let values = references.systems
            .filter { $0.frame == selectedFrame }
            .compactMap { $0.heights[heightKey] }
            .filter { $0 > 0 }
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        return minimum...maximum
    }

    private var compatibleInsulationThicknesses: [Int] {
        guard let selectedInsulation, selectedFrameWidthMM > 0 else { return [] }
        return selectedInsulation.thicknessesMM.filter { $0 <= selectedFrameWidthMM + selectedInsulation.maxOverFrameMM }
    }

    private var thermalResistance: Double {
        guard let selectedInsulation, selectedInsulation.lambda > 0, insulationThicknessMM > 0 else { return 0 }
        return (Double(insulationThicknessMM) / 1000) / selectedInsulation.lambda
    }

    private var canContinue: Bool {
        switch step {
        case 1:
            return height > 0 && (geometryMode == .length ? enteredLength > 0 : enteredSurface > 0)
        case 2:
            return availableFrames.contains(selectedFrame)
        case 3:
            return allRequiredLayersAreComplete
        case 4:
            return selectedSystem != nil && maximumHeight >= height
        case 5:
            return !insulationEnabled || (selectedInsulation != nil && compatibleInsulationThicknesses.contains(insulationThicknessMM))
        default:
            return true
        }
    }

    var body: some View {
        Group {
            if references.isLoading {
                ProgressView("Chargement depuis Plaquisto Admin…")
            } else if let error = references.error {
                ContentUnavailableView(
                    "Données indisponibles",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
            } else {
                wizard
            }
        }
        .tint(green)
        .onChange(of: references.facings.count, initial: true) { _, _ in initializeSelections() }
        .onChange(of: references.systems.count, initial: true) { _, _ in normalizeSystem() }
        .onChange(of: references.insulations.count, initial: true) { _, _ in normalizeInsulation() }
        .onChange(of: skinCount) { _, _ in resetParementsForSkinCount(); normalizeSystem() }
        .onChange(of: governingFamily) { _, _ in normalizeSystem() }
        .onChange(of: selectedFrame) { _, _ in normalizeSystem() }
        .onChange(of: mounting) { _, _ in normalizeSystem() }
        .onChange(of: spacing) { _, _ in normalizeSystem() }
        .onChange(of: systemID) { _, _ in normalizeInsulation() }
        .onChange(of: insulationID) { _, _ in normalizeInsulationThickness() }
        .alert("Hauteur de plaque insuffisante", isPresented: $showPlateHeightWarning) {
            Button("Revenir au choix", role: .cancel) {}
            Button("Continuer malgré tout") { step += 1 }
        } message: {
            Text("Au moins une plaque choisie est moins haute que la hauteur sous plafond de \(format(height, "m")). Des raccords seront nécessaires. Confirmez-vous cette configuration ?")
        }
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 1: dimensionsStep
                    case 2: framingStep
                    case 3: facingsStep
                    case 4: verificationStep
                    case 5: insulationStep
                    case 6: jointsStep
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
            if showsCloseButton {
                Button("Fermer") {
                    if let onClose { onClose() } else { reset() }
                }
                .buttonStyle(.bordered)
            }
            Text("OUVRAGE").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Cloison de distribution").font(.title2.bold())
            Label("Données synchronisées avec Plaquisto Admin", systemImage: "checkmark.icloud")
            .font(.caption)
            .foregroundStyle(.green)
            ProgressView(value: Double(step), total: 7)
            Text("Étape \(step) sur 7 · \(stepNames[step - 1])")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.background)
    }

    private var footer: some View {
        HStack {
            if step > 1 {
                Button("Retour") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step < 7 {
                Button("Continuer") { advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
            } else if let onSave {
                Button("Enregistrer") { onSave(configurationSnapshot()) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Recommencer") { reset() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.background)
    }

    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Dimensions de l’ouvrage")
            card {
                LabDecimalRow("Hauteur sous plafond", value: $height, unit: "m")
                Divider()
                Picker("Deuxième mesure", selection: $geometryMode) {
                    ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Divider()
                if geometryMode == .length {
                    LabDecimalRow("Longueur de la cloison", value: $enteredLength, unit: "m")
                } else {
                    LabDecimalRow("Surface totale", value: $enteredSurface, unit: "m²")
                }
            }
            card {
                LabeledContent(
                    geometryMode == .length ? "Surface calculée" : "Longueur calculée",
                    value: format(geometryMode == .length ? actualArea : actualLength, geometryMode == .length ? "m²" : "m")
                )
            }
            Text("La hauteur sous plafond est obligatoire. Renseignez ensuite soit la longueur de la cloison, soit sa surface totale.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
    }

    private var facingsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Nombre de peaux par face")
            card {
                Picker("Nombre de peaux", selection: $skinCount) {
                    ForEach(SkinCount.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            faceSection(title: "Face A", first: $faceAFirst, second: $faceASecond)
            faceSection(title: "Face B", first: $faceBFirst, second: $faceBSecond)

            if skinCount == .double {
                Text("Le nombre de peaux est identique sur les deux faces. Les fonctions des plaques peuvent être différentes entre les faces A et B.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

        }
    }

    private var verificationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Vérification du montage")
            card {
                LabeledContent("Type de cloison", value: selectedSystem?.type ?? "Non défini")
                Divider()
                LabeledContent("Ossature retenue", value: selectedSystem?.frame ?? selectedFrame)
                Divider()
                LabeledContent("Entraxe", value: "\(Int(spacing * 100)) cm")
                Divider()
                LabeledContent("Montage", value: mounting.rawValue)
                Divider()
                LabeledContent("Épaisseur totale de la cloison", value: selectedSystem.map { "\($0.totalThicknessMM) mm" } ?? "—")
                Divider()
                LabeledContent("Hauteur maximale", value: selectedSystem == nil ? "—" : format(maximumHeight, "m"))
            }

            card {
                verificationRow("Face A", value: faceSummary(first: faceAFirst, second: faceASecond))
                Divider()
                verificationRow("Face B", value: faceSummary(first: faceBFirst, second: faceBSecond))
            }

            if selectedSystem == nil {
                warning("Les parements choisis ne correspondent à aucune configuration du tableau pour l’ossature sélectionnée. Modifiez le nombre de peaux, le type de plaque ou l’ossature.")
            } else if maximumHeight <= 0 {
                warning("Cette configuration n’est pas prévue avec un entraxe de \(Int(spacing * 100)) cm. Choisissez l’autre entraxe ou modifiez l’ossature.")
            } else if maximumHeight < height {
                warning("Cette configuration n’est pas compatible avec la hauteur sous plafond renseignée de \(format(height, "m")). Sa hauteur maximale est de \(format(maximumHeight, "m")). Choisissez un entraxe plus faible, des montants doubles ou une ossature plus large.")
            } else {
                info("Configuration compatible : hauteur maximale \(format(maximumHeight, "m")) pour une hauteur sous plafond de \(format(height, "m")).", icon: "checkmark.circle", color: .green)
            }

        }
    }

    @ViewBuilder
    private func faceSection(title: String, first: Binding<[FacingAllocation]>, second: Binding<[FacingAllocation]>) -> some View {
        sectionTitle(title)
        Text(skinCount == .single ? "Parement" : "Première peau")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        allocationList(first)
        if skinCount == .double {
            Text("Deuxième peau")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            allocationList(second)
        }
    }

    @ViewBuilder
    private func allocationList(_ allocations: Binding<[FacingAllocation]>) -> some View {
        ForEach(allocations.wrappedValue.indices, id: \.self) { index in
            allocationCard(allocation: allocations[index], canDelete: allocations.wrappedValue.count > 1) {
                allocations.wrappedValue.remove(at: index)
            }
        }
        Button("Ajouter un autre type de parement") {
            addAllocation(to: allocations)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        allocationStatus(allocations.wrappedValue)
    }

    private func allocationCard(allocation: Binding<FacingAllocation>, canDelete: Bool, onDelete: @escaping () -> Void) -> some View {
        card {
            LabeledContent("Type de plaque") {
                Picker("Type de plaque", selection: familyBinding(allocation)) {
                    ForEach(allowedFamilies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: 28)
            Divider()
            LabeledContent("Fonction") {
                Picker("Fonction", selection: facingBinding(allocation)) {
                    ForEach(functionChoices(for: allocation.wrappedValue)) { choice in
                        Text(choice.functionTitle).tag(choice.id)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: 28)
            Divider()
            LabeledContent("Dimension") {
                Picker("Dimension", selection: allocation.formatID) {
                    ForEach(formatChoices(for: allocation.wrappedValue)) { plateFormat in
                        Text(plateFormat.title).tag(plateFormat.id)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: 28)
            Divider()
            LabDecimalRow("Surface attribuée", value: allocation.surface, unit: "m²")
            if let plateFormat = selectedFormat(allocation.wrappedValue), Double(plateFormat.lengthMM) / 1000 < height {
                Label("Cette plaque est moins haute que la hauteur sous plafond de \(format(height, "m")).", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if canDelete {
                Divider()
                Button("Supprimer ce type", role: .destructive, action: onDelete)
            }
        }
    }

    private func allocationStatus(_ allocations: [FacingAllocation]) -> some View {
        let remaining = actualArea - allocations.reduce(0) { $0 + $1.surface }
        return Group {
            if abs(remaining) < 0.01 {
                Text("Répartition complète : \(format(actualArea, "m²")).").foregroundStyle(.green)
            } else if remaining > 0 {
                Text("Il reste \(format(remaining, "m²")) à répartir.").foregroundStyle(.orange)
            } else {
                Text("La surface attribuée dépasse de \(format(abs(remaining), "m²")).").foregroundStyle(.red)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 12)
    }

    private var framingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Ossature métallique")
            card {
                Picker("Largeur du montant", selection: $selectedFrame) {
                    ForEach(availableFrames, id: \.self) { frame in
                        Text(frameLabel(frame)).tag(frame)
                    }
                }
                Divider()
                Picker("Entraxe des montants", selection: $spacing) {
                    Text("40 cm").tag(0.40)
                    Text("60 cm").tag(0.60)
                }
                Divider()
                Picker("Montage des montants", selection: $mounting) {
                    ForEach(StudMounting.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            if let range = preliminaryHeightRange {
                card {
                    LabeledContent(
                        "Hauteur maximale",
                        value: "\(format(range.lowerBound, "m")) – \(format(range.upperBound, "m"))"
                    )
                }
                Text("Cette plage dépend de la configuration des parements. Leur choix permettra ensuite de vérifier précisément la hauteur maximale.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var insulationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Isolation de la cloison")
            card {
                Toggle("Prévoir une isolation", isOn: $insulationEnabled)
            }
            if insulationEnabled {
                card {
                    LabeledContent("Type d’isolant") {
                        Picker("Type d’isolant", selection: $insulationID) {
                            ForEach(references.insulations) { insulation in
                                Text(insulation.title).tag(insulation.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    Divider()
                    if let selectedInsulation {
                        LabeledContent("Lambda", value: "λ \(selectedInsulation.lambda.formatted(.number.precision(.fractionLength(3)))) W/(m·K)")
                        Divider()
                        LabeledContent("Épaisseur") {
                            Picker("Épaisseur", selection: $insulationThicknessMM) {
                                ForEach(compatibleInsulationThicknesses, id: \.self) { thickness in
                                    let resistance = (Double(thickness) / 1000) / selectedInsulation.lambda
                                    Text("\(thickness) mm — R = \(resistance.formatted(.number.precision(.fractionLength(2))))").tag(thickness)
                                }
                            }
                            .labelsHidden()
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                if compatibleInsulationThicknesses.isEmpty {
                    warning("Aucune épaisseur de cet isolant n’est compatible avec l’ossature \(selectedSystem?.frame ?? "sélectionnée"). Choisissez un autre isolant ou une ossature plus large.")
                } else {
                    card {
                        LabeledContent("Résistance thermique", value: "R = \(thermalResistance.formatted(.number.precision(.fractionLength(2)))) m²·K/W")
                    }
                }
                Text("L’épaisseur peut dépasser la largeur du rail de 10 mm, sauf pour la laine de bois qui ne doit pas dépasser la largeur du rail.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var jointsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Traitement des bandes à joint")
            card {
                Toggle("Prévoir le traitement des bandes à joint", isOn: $jointTreatment)
                if jointTreatment {
                    Divider()
                    Picker("Type d’enduit", selection: $compound) {
                        ForEach(Compound.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Configuration retenue")
            card {
                LabeledContent("Dimensions", value: "\(format(actualLength, "m")) × \(format(height, "m"))")
                Divider()
                LabeledContent("Surface", value: format(actualArea, "m²"))
                Divider()
                LabeledContent("Parements", value: skinCount.rawValue)
                Divider()
                LabeledContent("Ossature", value: selectedSystem?.frame ?? "Largeur \(selectedFrameWidthMM) mm")
                Divider()
                LabeledContent("Épaisseur totale de la cloison", value: selectedSystem.map { "\($0.totalThicknessMM) mm" } ?? "—")
                Divider()
                LabeledContent("Montants", value: mounting.rawValue)
                Divider()
                LabeledContent("Entraxe", value: "\(Int(spacing * 100)) cm")
                Divider()
                LabeledContent("Isolation", value: insulationEnabled ? insulationSummary : "Non")
            }

            sectionTitle("Quantitatif indicatif")
            card {
                ForEach(Array(resultRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    LabeledContent(row.0, value: row.1)
                }
            }
            Text("Les quantités sont indicatives. Elles devront être adaptées aux ouvertures, aux découpes et aux conditions réelles du chantier.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
    }

    private var insulationSummary: String {
        guard let selectedInsulation else { return "—" }
        return "\(selectedInsulation.title) · \(insulationThicknessMM) mm · R \(thermalResistance.formatted(.number.precision(.fractionLength(2))))"
    }

    private var resultRows: [(String, String)] {
        guard actualArea > 0 else { return [] }
        let table = references.quantities
        let plateFactor = table.coefficients["parement_per_face_and_layer_m2_m2"] ?? 1.05
        var rows: [(String, String)] = []

        var allFacings = faceAFirst + faceBFirst
        if skinCount == .double {
            allFacings += faceASecond + faceBSecond
        }
        appendCombinedFacingRows(allFacings, factor: plateFactor, to: &rows)

        let layerKey = skinCount == .single ? "simple" : "double"
        let mountingKey = mounting == .simple ? "simple" : "double"
        let spacingKey = spacing < 0.5 ? "0.40" : "0.60"
        let detailKey = "\(layerKey)_\(spacingKey)_\(mountingKey)"
        let studKey = "\(spacingKey)_\(mountingKey)"
        let railFactor = table.coefficients[skinCount == .single ? "rail_simple_skin_ml_m2" : "rail_double_skin_ml_m2"] ?? 0

        rows.append(("Rails R\(selectedFrameWidthMM)", format(actualArea * railFactor, "ml")))
        rows.append(("Montants \(selectedStudName)", format(actualArea * (table.studs[studKey] ?? 0), "ml")))
        rows.append(("Vis TTPC 25 ou 35", format(actualArea * (table.firstLayerScrews[detailKey] ?? 0), "unités", rounded: true)))
        if skinCount == .double {
            rows.append(("Vis TTPC 45", format(actualArea * (table.secondLayerScrews[detailKey] ?? 0), "unités", rounded: true)))
        }
        rows.append(("Vis TRPF 13", format(actualArea * (table.frameScrews[detailKey] ?? 0), "unités", rounded: true)))

        if insulationEnabled {
            rows.append(("Isolation · \(insulationSummary)", format(actualArea * (table.coefficients["insulation_m2_m2"] ?? 1.10), "m²")))
        }
        if jointTreatment {
            let bandKey = skinCount == .single ? "band_simple_skin_ml_m2" : "band_double_skin_ml_m2"
            let compoundKey = compound == .powder ? "enduit_poudre_kg_m2" : "enduit_pate_kg_m2"
            rows.append(("Bande à joint", format(actualArea * (table.coefficients[bandKey] ?? 0), "ml")))
            rows.append((compound.rawValue, format(actualArea * (table.coefficients[compoundKey] ?? 0), "kg")))
        }
        return rows
    }

    private func appendCombinedFacingRows(
        _ allocations: [FacingAllocation],
        factor: Double,
        to rows: inout [(String, String)]
    ) {
        typealias Group = (facing: CloisonFacingChoice, plateFormat: CloisonFacingFormat, surface: Double)
        var groups: [String: Group] = [:]

        for allocation in allocations {
            guard let facing = facing(allocation), let plateFormat = selectedFormat(allocation) else { continue }
            let key = "\(facing.id)|\(plateFormat.id)"
            if var group = groups[key] {
                group.surface += allocation.surface
                groups[key] = group
            } else {
                groups[key] = (facing, plateFormat, allocation.surface)
            }
        }

        for group in groups.values.sorted(by: { lhs, rhs in
            let left = "\(lhs.facing.family)|\(lhs.facing.functionTitle)|\(lhs.plateFormat.id)"
            let right = "\(rhs.facing.family)|\(rhs.facing.functionTitle)|\(rhs.plateFormat.id)"
            return left < right
        }) {
            rows.append((
                "Parement · \(group.facing.family) \(group.facing.functionTitle) · \(group.plateFormat.title)",
                format(group.surface * factor, "m²")
            ))
        }
    }

    private var allowedFamilies: [String] {
        skinCount == .double ? ["BA13"] : ["BA13", "BA15", "BA18"]
    }

    private func facing(_ allocation: FacingAllocation) -> CloisonFacingChoice? {
        references.facings.first(where: { $0.id == allocation.facingID })
    }

    private func selectedFormat(_ allocation: FacingAllocation) -> CloisonFacingFormat? {
        facing(allocation)?.formats.first(where: { $0.id == allocation.formatID })
    }

    private func functionChoices(for allocation: FacingAllocation) -> [CloisonFacingChoice] {
        let family = facing(allocation)?.family ?? allowedFamilies.first ?? "BA13"
        return references.facings.filter { $0.family == family }
            .sorted { lhs, rhs in
                if lhs.function == "standard" { return true }
                if rhs.function == "standard" { return false }
                return lhs.functionTitle < rhs.functionTitle
            }
    }

    private func formatChoices(for allocation: FacingAllocation) -> [CloisonFacingFormat] {
        facing(allocation)?.formats ?? []
    }

    private func familyBinding(_ allocation: Binding<FacingAllocation>) -> Binding<String> {
        Binding(
            get: { facing(allocation.wrappedValue)?.family ?? allowedFamilies.first ?? "BA13" },
            set: { family in
                guard let choice = references.facings.first(where: { $0.family == family && $0.function == "standard" }) ?? references.facings.first(where: { $0.family == family }) else { return }
                var next = allocation.wrappedValue
                next.facingID = choice.id
                next.formatID = preferredFormat(choice.formats)?.id ?? choice.formats.first?.id ?? ""
                allocation.wrappedValue = next
            }
        )
    }

    private func facingBinding(_ allocation: Binding<FacingAllocation>) -> Binding<String> {
        Binding(
            get: { allocation.wrappedValue.facingID },
            set: { facingID in
                guard let choice = references.facings.first(where: { $0.id == facingID }) else { return }
                var next = allocation.wrappedValue
                next.facingID = facingID
                next.formatID = preferredFormat(choice.formats)?.id ?? choice.formats.first?.id ?? ""
                allocation.wrappedValue = next
            }
        )
    }

    private func preferredFormat(_ formats: [CloisonFacingFormat]) -> CloisonFacingFormat? {
        formats.filter { Double($0.lengthMM) / 1000 >= height }.min(by: { $0.lengthMM < $1.lengthMM }) ?? formats.max(by: { $0.lengthMM < $1.lengthMM })
    }

    private func addAllocation(to allocations: Binding<[FacingAllocation]>) {
        let used = Set(allocations.wrappedValue.map(\.facingID))
        guard let choice = references.facings.first(where: { allowedFamilies.contains($0.family) && !used.contains($0.id) }) else { return }
        allocations.wrappedValue.append(FacingAllocation(facingID: choice.id, formatID: preferredFormat(choice.formats)?.id ?? "", surface: 0))
    }

    private func allocationIsComplete(_ allocations: [FacingAllocation]) -> Bool {
        !allocations.isEmpty &&
        allocations.allSatisfy { $0.surface > 0 && facing($0) != nil && selectedFormat($0) != nil } &&
        abs(allocations.reduce(0) { $0 + $1.surface } - actualArea) < 0.01
    }

    private var allRequiredLayersAreComplete: Bool {
        allocationIsComplete(faceAFirst) &&
        allocationIsComplete(faceBFirst) &&
        (skinCount == .single || (allocationIsComplete(faceASecond) && allocationIsComplete(faceBSecond)))
    }

    private var hasShortPlate: Bool {
        let required = skinCount == .single
            ? faceAFirst + faceBFirst
            : faceAFirst + faceASecond + faceBFirst + faceBSecond
        return required.contains { allocation in
            guard let plateFormat = selectedFormat(allocation) else { return false }
            return Double(plateFormat.lengthMM) / 1000 < height
        }
    }

    private func maximumHeight(for system: CloisonSystem) -> Double {
        system.heights[heightKey] ?? 0
    }

    private var selectedStudName: String {
        guard let frame = selectedSystem?.frame,
              let stud = frame.split(separator: "+").last else {
            return "M\(selectedFrameWidthMM)"
        }
        return stud.trimmingCharacters(in: .whitespaces)
    }

    private func frameLabel(_ frame: String) -> String {
        if frame.contains("M48/35") { return "48 mm (standard : 48/35)" }
        if frame.contains("M48/50") { return "48 mm (ailes élargies : 48/50)" }
        let width = references.systems.first(where: { $0.frame == frame })?.frameWidthMM ?? 0
        return "\(width) mm"
    }

    private func verificationRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func faceSummary(first: [FacingAllocation], second: [FacingAllocation]) -> String {
        let firstDescription = allocationsSummary(first)
        guard skinCount == .double else { return firstDescription }
        return "Première peau : \(firstDescription)\nDeuxième peau : \(allocationsSummary(second))"
    }

    private func allocationsSummary(_ allocations: [FacingAllocation]) -> String {
        allocations.compactMap { allocation in
            guard let facing = facing(allocation), let plateFormat = selectedFormat(allocation) else { return nil }
            return "\(facing.family) \(facing.functionTitle.lowercased()) · \(plateFormat.title) · \(format(allocation.surface, "m²"))"
        }.joined(separator: " + ")
    }

    private func initializeSelections() {
        guard let defaultFacing = references.facings.first(where: { $0.family == "BA13" && $0.function == "standard" }) ?? references.facings.first else { return }
        func normalized(_ allocations: [FacingAllocation]) -> [FacingAllocation] {
            if let first = allocations.first, facing(first) != nil { return allocations }
            return [FacingAllocation(facingID: defaultFacing.id, formatID: preferredFormat(defaultFacing.formats)?.id ?? "", surface: actualArea)]
        }
        faceAFirst = normalized(faceAFirst)
        faceASecond = normalized(faceASecond)
        faceBFirst = normalized(faceBFirst)
        faceBSecond = normalized(faceBSecond)
    }

    private func resetParementsForSkinCount() {
        initializeSelections()
        if skinCount == .double {
            forceBA13(&faceAFirst)
            forceBA13(&faceASecond)
            forceBA13(&faceBFirst)
            forceBA13(&faceBSecond)
        }
    }

    private func forceBA13(_ allocations: inout [FacingAllocation]) {
        guard let choice = references.facings.first(where: { $0.family == "BA13" && $0.function == "standard" }) else { return }
        for index in allocations.indices where facing(allocations[index])?.family != "BA13" {
            allocations[index].facingID = choice.id
            allocations[index].formatID = preferredFormat(choice.formats)?.id ?? ""
        }
    }

    private func normalizeSystem() {
        let current = compatibleSystems.first(where: { $0.id == systemID })
        let fittingSystem = compatibleSystems.first(where: { maximumHeight(for: $0) >= height })
        if current == nil || (current.map { maximumHeight(for: $0) < height } == true && fittingSystem != nil) {
            systemID = fittingSystem?.id ?? compatibleSystems.first?.id ?? ""
        }
        normalizeInsulation()
    }

    private func normalizeInsulation() {
        if !references.insulations.contains(where: { $0.id == insulationID }) {
            insulationID = references.insulations.first?.id ?? ""
        }
        normalizeInsulationThickness()
    }

    private func normalizeInsulationThickness() {
        if !compatibleInsulationThicknesses.contains(insulationThicknessMM) {
            insulationThicknessMM = compatibleInsulationThicknesses.first ?? 0
        }
    }

    private func populateSurfacesIfNeeded() {
        func populated(_ allocations: inout [FacingAllocation]) {
            if allocations.count == 1 && allocations[0].surface == 0 { allocations[0].surface = actualArea }
            for index in allocations.indices {
                if let choice = facing(allocations[index]) {
                    allocations[index].formatID = preferredFormat(choice.formats)?.id ?? allocations[index].formatID
                }
            }
        }
        populated(&faceAFirst)
        populated(&faceBFirst)
        populated(&faceASecond)
        populated(&faceBSecond)
    }

    private func advance() {
        guard canContinue else { return }
        if step == 1 { populateSurfacesIfNeeded(); normalizeSystem() }
        if step == 3 && hasShortPlate { showPlateHeightWarning = true }
        else { step += 1 }
    }

    private func configurationSnapshot() -> CloisonDistributionConfiguration {
        CloisonDistributionConfiguration(
            geometryMode: geometryMode == .surface ? "surface" : "length",
            height: height,
            enteredLength: enteredLength,
            enteredSurface: enteredSurface,
            layers: skinCount == .double ? 2 : 1,
            faceAFirst: faceAFirst,
            faceASecond: skinCount == .double ? faceASecond : [],
            faceBFirst: faceBFirst,
            faceBSecond: skinCount == .double ? faceBSecond : [],
            frame: selectedFrame,
            doubledStuds: mounting == .double,
            spacing: spacing,
            insulationEnabled: insulationEnabled,
            insulationID: insulationID,
            insulationThicknessMM: insulationThicknessMM,
            jointTreatment: jointTreatment,
            compoundChoice: compound == .paste ? "pate" : "poudre",
            quantities: resultRows.compactMap { quantity(from: $0) }
        )
    }

    private func quantity(from row: (String, String)) -> CloisonQuantity? {
        let scanner = Scanner(string: row.1.replacingOccurrences(of: ",", with: "."))
        guard let value = scanner.scanDouble() else { return nil }
        let unit = String(row.1[scanner.currentIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty else { return nil }
        return CloisonQuantity(name: row.0, quantity: value, unit: unit)
    }

    private func reset() {
        step = 1
        geometryMode = .length
        height = 0
        enteredLength = 0
        enteredSurface = 0
        skinCount = .single
        faceAFirst = [FacingAllocation()]
        faceASecond = [FacingAllocation()]
        faceBFirst = [FacingAllocation()]
        faceBSecond = [FacingAllocation()]
        mounting = .simple
        selectedFrame = "R48 + M48/35"
        spacing = 0.60
        systemID = ""
        insulationEnabled = true
        insulationID = ""
        insulationThicknessMM = 0
        jointTreatment = true
        compound = .powder
        initializeSelections()
        normalizeSystem()
    }

    private func format(_ value: Double, _ unit: String, rounded: Bool = false) -> String {
        let number = rounded ? ceil(value) : value
        return number.formatted(.number.precision(.fractionLength(rounded ? 0 : 2))) + " " + unit
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(.secondary).padding(.horizontal, 12)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func warning(_ text: String) -> some View {
        info(text, icon: "exclamationmark.triangle.fill", color: .orange)
    }

    private func info(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct LabDecimalRow: View {
    let title: String
    @Binding var value: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, unit: String) {
        self.title = title
        _value = value
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 86)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
