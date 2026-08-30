import SwiftUI

struct DoublageConfiguratorView: View {
    enum GeometryMode: String, CaseIterable, Identifiable { case length = "Longueur", surface = "Surface totale"; var id: Self { self } }
    enum SkinCount: String, CaseIterable, Identifiable { case single = "Simple peau", double = "Double peau"; var id: Self { self } }
    enum StudMounting: String, CaseIterable, Identifiable { case simple = "Montants simples", double = "Montants doubles"; var id: Self { self } }
    enum Compound: String, CaseIterable, Identifiable { case powder = "Enduit en poudre", paste = "Enduit en pâte"; var id: Self { self } }
    enum InsulationLayerCount: String, CaseIterable, Identifiable { case single = "Simple épaisseur", double = "Double épaisseur"; var id: Self { self } }

    struct FacingAllocation: Identifiable, Hashable {
        let id: UUID
        var facingID: String
        var formatID: String
        var surface: Double

        init(id: UUID = UUID(), facingID: String = "", formatID: String = "", surface: Double = 0) {
            self.id = id; self.facingID = facingID; self.formatID = formatID; self.surface = surface
        }
    }

    struct InsulationSelection: Hashable {
        var familyID = ""
        var lambda = 0.0
        var thicknessMM = 0
    }

    @EnvironmentObject private var references: LabReferenceStore
    @State private var step = 1
    @State private var geometryMode = GeometryMode.length
    @State private var height = 0.0
    @State private var enteredLength = 0.0
    @State private var enteredSurface = 0.0
    @State private var skinCount = SkinCount.single
    @State private var firstSkin = [FacingAllocation()]
    @State private var secondSkin = [FacingAllocation()]
    @State private var technique = "Rails et montants"
    @State private var frame = "R48 + M48"
    @State private var mounting = StudMounting.simple
    @State private var spacing = 0.6
    @State private var intermediateSupports = false
    @State private var insulationEnabled = true
    @State private var insulationLayerCount = InsulationLayerCount.single
    @State private var firstInsulation = InsulationSelection()
    @State private var secondInsulation = InsulationSelection()
    @State private var vaporBarrier = false
    @State private var jointTreatment = true
    @State private var compound = Compound.powder
    @State private var showPlateHeightWarning = false

    private let stepNames = ["Dimensions", "Parements", "Technique et ossature", "Isolation", "Bandes à joint", "Résultat"]
    private var groups: [LabPerformanceGroup] { references.groups }
    private var facings: [LabFacingChoice] { references.facings }
    private var compatibility: LabFacingCompatibility? { references.compatibility }
    private var insulationFamilies: [LabInsulationFamily] { references.insulationFamilies }
    private var actualLength: Double { geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0) }
    private var actualArea: Double { geometryMode == .surface ? enteredSurface : enteredLength * height }
    private var performanceGroupIDs: [String] {
        if skinCount == .single { return Array(Set(firstSkin.compactMap { groupID(first: $0, second: nil) })) }
        return Array(Set(firstSkin.flatMap { first in secondSkin.compactMap { second in groupID(first: first, second: second) } }))
    }
    private var performanceGroups: [LabPerformanceGroup] { performanceGroupIDs.compactMap { id in groups.first(where: { $0.id == id }) } }
    private var frames: [String] { Array(Set(performanceGroups.first?.values.map(\.frame) ?? [])).sorted { frameNumber($0) < frameNumber($1) } }
    private var spacings: [Double] { Array(Set(performanceGroups.first?.values.map(\.spacing) ?? [])).sorted() }
    private var maxHeight: Double { maximumHeight(frame: frame) }
    private var isUnavailable: Bool { maxHeight == 0 }
    private var isExceeded: Bool { maxHeight > 0 && height > maxHeight }
    private var frameIsAccepted: Bool { maxHeight >= height || (intermediateSupports && maxHeight > 0) }
    private var canContinue: Bool {
        switch step {
        case 1: return height > 0 && (geometryMode == .length ? enteredLength > 0 : enteredSurface > 0)
        case 2: return allocationsAreComplete && !performanceGroupIDs.isEmpty
        case 3: return frameIsAccepted
        case 4: return !insulationEnabled || insulationSelectionIsComplete(firstInsulation) && (insulationLayerCount == .single || insulationSelectionIsComplete(secondInsulation))
        default: return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if references.isLoading { ProgressView("Chargement depuis Plaquisto Admin…") }
                else if let error = references.error { ContentUnavailableView("Données indisponibles", systemImage: "exclamationmark.icloud", description: Text(error)) }
                else { wizard }
            }
        }
        .onChange(of: groups.count, initial: true) { _, _ in initializeParementsIfNeeded(); normalizeSelections() }
        .onChange(of: facings.count) { _, _ in initializeParementsIfNeeded(); normalizeSelections() }
        .onChange(of: skinCount) { _, _ in resetParementsForSkinCount() }
        .onChange(of: firstSkin) { _, _ in normalizeAfterFirstSkinChange() }
        .onChange(of: secondSkin) { _, _ in normalizeSelections() }
        .onChange(of: insulationFamilies.count, initial: true) { _, _ in initializeInsulationIfNeeded() }
        .alert("Hauteur de plaque insuffisante", isPresented: $showPlateHeightWarning) {
            Button("Revenir au choix", role: .cancel) {}
            Button("Continuer malgré tout") { step += 1 }
        } message: {
            Text("Au moins une hauteur de plaque est inférieure à la hauteur sous plafond de \(format(height, "m")). Des raccords ou des découpes supplémentaires seront nécessaires. Confirmez-vous cette configuration ?")
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
            Button("Fermer") { reset() }.buttonStyle(.bordered).tint(.green)
            Text("OUVRAGE").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Doublage périphérique").font(.title2.bold())
            Label(references.isUsingOfflineData ? "Données enregistrées hors connexion" : "Données synchronisées avec Plaquisto Admin", systemImage: references.isUsingOfflineData ? "icloud.slash" : "checkmark.icloud")
                .font(.caption).foregroundStyle(references.isUsingOfflineData ? .orange : .green)
            ProgressView(value: Double(step), total: 6).tint(.green)
            Text("Étape \(step) sur 6 · \(stepNames[step - 1])").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
        .background(.background)
    }

    private var footer: some View {
        HStack {
            if step > 1 { Button("Retour") { step -= 1 }.buttonStyle(.bordered).tint(.green) }
            Spacer()
            if step < 6 { Button("Continuer") { advance() }.buttonStyle(.borderedProminent).tint(.green).disabled(!canContinue) }
            else { Button("Recommencer") { reset() }.buttonStyle(.borderedProminent).tint(.green) }
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.background)
    }

    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Dimensions de l’ouvrage")
            card {
                DecimalRow("Hauteur sous plafond", value: $height, unit: "m")
                Divider()
                Picker("Deuxième mesure", selection: $geometryMode) { ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Divider()
                if geometryMode == .length { DecimalRow("Longueur du doublage (périmètre)", value: $enteredLength, unit: "m") }
                else { DecimalRow("Surface totale", value: $enteredSurface, unit: "m²") }
            }
            card {
                LabeledContent(geometryMode == .length ? "Surface calculée" : "Longueur calculée", value: format(geometryMode == .length ? actualArea : actualLength, geometryMode == .length ? "m²" : "m"))
            }
            Text("La hauteur sous plafond est obligatoire. Renseignez ensuite soit la longueur du doublage, soit sa surface totale.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var facingsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Nombre de peaux")
            card {
                Picker("Nombre de parements", selection: $skinCount) { ForEach(SkinCount.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            }
            sectionTitle("Première peau")
            ForEach(firstSkin.indices, id: \.self) { index in
                allocationCard(allocation: $firstSkin[index], secondLayer: false, canDelete: firstSkin.count > 1)
            }
            Button("Ajouter un autre type de parement") { addAllocation(secondLayer: false) }
                .buttonStyle(.borderless).tint(.green).padding(.horizontal, 12)
                .disabled(availableChoices(for: nil, secondLayer: false).isEmpty)
            allocationStatus(firstSkin)
            if skinCount == .double {
                sectionTitle("Deuxième peau")
                ForEach(secondSkin.indices, id: \.self) { index in
                    allocationCard(allocation: $secondSkin[index], secondLayer: true, canDelete: secondSkin.count > 1)
                }
                Button("Ajouter un autre type de parement") { addAllocation(secondLayer: true) }
                    .buttonStyle(.borderless).tint(.green).padding(.horizontal, 12)
                    .disabled(availableChoices(for: nil, secondLayer: true).isEmpty)
                allocationStatus(secondSkin)
                Text("L’ordre des deux parements n’a aucune incidence.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
        }
    }

    private func allocationCard(allocation: Binding<FacingAllocation>, secondLayer: Bool, canDelete: Bool) -> some View {
        card {
            LabeledContent("Type de plaque") {
                Picker("Type de plaque", selection: familyBinding(allocation, secondLayer: secondLayer)) {
                    ForEach(availableFamilies(for: allocation.wrappedValue.id, secondLayer: secondLayer), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: 28)
            Divider()
            LabeledContent("Fonction") {
                Picker("Fonction", selection: facingBinding(allocation, secondLayer: secondLayer)) {
                    ForEach(availableFunctions(for: allocation.wrappedValue, secondLayer: secondLayer)) { Text($0.functionTitle).tag($0.id) }
                }
                .labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: 28)
            Divider()
            LabeledContent("Dimension") {
                Picker("Dimension", selection: allocation.formatID) {
                    ForEach(availableFormats(for: allocation.wrappedValue, secondLayer: secondLayer)) { Text($0.title).tag($0.id) }
                }
                .labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: 28)
            Divider()
            DecimalRow("Surface attribuée", value: allocation.surface, unit: "m²")
            if height > 0, let plateFormat = selectedFormat(allocation.wrappedValue), Double(plateFormat.lengthMM) / 1000 < height {
                Label("Cette hauteur est inférieure à la hauteur sous plafond de \(format(height, "m")).", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if canDelete {
                Divider()
                Button("Supprimer ce type", role: .destructive) { removeAllocation(allocation.wrappedValue.id, secondLayer: secondLayer) }
            }
        }.tint(Color(red: 0.12, green: 0.38, blue: 0.29))
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
        }.font(.footnote).padding(.horizontal, 12)
    }

    private var framingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Technique et ossature")
            card {
                Picker("Technique utilisée", selection: $technique) { Text("Rails et montants").tag("Rails et montants") }
                Divider()
                Picker("Type de montage", selection: $mounting) { ForEach(StudMounting.allCases) { Text($0.rawValue).tag($0) } }
                Divider()
                Picker("Rails et montants", selection: $frame) {
                    ForEach(frames, id: \.self) { candidate in
                        HStack {
                            Text(candidate)
                            if frameHasWarning(candidate) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow) }
                        }.tag(candidate)
                    }
                }
                Divider()
                Picker("Entraxe des montants", selection: $spacing) { ForEach(spacings, id: \.self) { Text("\(Int($0 * 100)) cm").tag($0) } }
                Divider()
                Toggle("Ajouter des appuis intermédiaires pour montant sur mur support", isOn: $intermediateSupports)
            }
            if isUnavailable {
                warning("La configuration \(frame) n’est pas prévue par le tableau technique pour les parements sélectionnés. Choisissez une autre ossature.")
            } else if intermediateSupports {
                info("La hauteur maximale de ce montage est de \(format(maxHeight, "m")). Prévoyez une ligne d’appuis intermédiaires tous les \(format(maxHeight, "m")) de hauteur.", icon: "info.circle", color: .green)
            } else if isExceeded {
                warning("La configuration sélectionnée n’est pas compatible avec la hauteur sous plafond renseignée de \(format(height, "m")). Sa hauteur maximale est de \(format(maxHeight, "m")). Choisissez une ossature plus résistante, passez en montants doubles ou ajoutez des appuis intermédiaires.")
            } else {
                info("Configuration compatible : hauteur maximale \(format(maxHeight, "m")) pour une hauteur sous plafond de \(format(height, "m")).", icon: "checkmark.circle", color: .green)
            }
        }
    }

    private var insulationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Isolation du doublage")
            card {
                Toggle("Prévoir une isolation", isOn: $insulationEnabled)
                if insulationEnabled {
                    Divider()
                    Picker("Nombre de couches", selection: $insulationLayerCount) {
                        ForEach(InsulationLayerCount.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
            if insulationEnabled {
                sectionTitle("Première couche")
                insulationCard(selection: $firstInsulation)
                if insulationLayerCount == .double {
                    sectionTitle("Deuxième couche")
                    insulationCard(selection: $secondInsulation)
                }
                card {
                    LabeledContent("Résistance thermique totale", value: "R = \(thermalResistanceTotal.formatted(.number.precision(.fractionLength(2)))) m²·K/W")
                }
            }
            sectionTitle("Pare-vapeur")
            card {
                Toggle("Prévoir la pose d’un pare-vapeur", isOn: $vaporBarrier)
            }
        }
    }

    private func insulationCard(selection: Binding<InsulationSelection>) -> some View {
        card {
            LabeledContent("Type d’isolant") {
                Picker("Type d’isolant", selection: insulationFamilyBinding(selection)) {
                    ForEach(insulationFamilies) { Text($0.title).tag($0.id) }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
            Divider()
            LabeledContent("Lambda") {
                Picker("Lambda", selection: insulationLambdaBinding(selection)) {
                    ForEach(insulationLambdas(for: selection.wrappedValue)) { option in
                        Text("λ \(option.value.formatted(.number.precision(.fractionLength(3)))) W/(m·K)").tag(option.value)
                    }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
            Divider()
            LabeledContent("Épaisseur") {
                Picker("Épaisseur", selection: selection.thicknessMM) {
                    ForEach(insulationThicknesses(for: selection.wrappedValue), id: \.self) { thickness in
                        Text("\(thickness) mm — R = \(thermalResistance(thicknessMM: thickness, lambda: selection.wrappedValue.lambda).formatted(.number.precision(.fractionLength(2))))").tag(thickness)
                    }
                }.labelsHidden().fixedSize(horizontal: true, vertical: false)
            }
        }.tint(Color(red: 0.12, green: 0.38, blue: 0.29))
    }

    private var jointsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Traitement des bandes à joint")
            card {
                Toggle("Prévoir le traitement des bandes", isOn: $jointTreatment)
                if jointTreatment { Divider(); Picker("Type d’enduit", selection: $compound) { ForEach(Compound.allCases) { Text($0.rawValue).tag($0) } } }
            }
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            info("Quantitatif calculé · \(format(actualArea, "m²")) · \(skinCount.rawValue.lowercased()) · entraxe \(Int(spacing * 100)) cm", icon: "checkmark.seal.fill", color: .green)
            sectionTitle("Configuration retenue")
            card {
                LabeledContent("Technique", value: technique)
                Divider(); LabeledContent("Ossature", value: frame)
                Divider(); LabeledContent("Montage", value: mounting.rawValue)
                Divider(); LabeledContent("Appuis intermédiaires", value: intermediateSupports ? "Oui" : "Non")
                Divider(); LabeledContent("Isolation", value: insulationEnabled ? insulationLayerCount.rawValue : "Non")
                if insulationEnabled { Divider(); LabeledContent("Résistance thermique totale", value: "R = \(thermalResistanceTotal.formatted(.number.precision(.fractionLength(2)))) m²·K/W") }
                Divider(); LabeledContent("Pare-vapeur", value: vaporBarrier ? "Oui" : "Non")
            }
            sectionTitle("Quantitatif indicatif")
            card {
                ForEach(Array(resultRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    LabeledContent(row.0, value: row.1)
                }
            }
            if spacing != 0.4 && spacing != 0.6 { info("La visserie pour les entraxes de 45 et 90 cm reste à compléter dans Plaquisto Admin. Elle n’est pas estimée ici.", icon: "info.circle", color: .secondary) }
            Text("Quantités indicatives avec la marge prévue dans votre tableau. Elles restent à vérifier selon les conditions réelles du chantier.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var resultRows: [(String, String)] {
        guard actualArea > 0, actualLength > 0, height > 0, let table = references.quantityTable else { return [] }
        let rails = 2 * actualLength * 1.05
        let bays = ceil(actualLength / spacing)
        let studs = (mounting == .simple ? bays + 1 : 2 * bays) * height * 1.05
        var rows = allocationRows(firstSkin, skinName: "1re peau")
        if skinCount == .double {
            rows += allocationRows(secondSkin, skinName: "2e peau")
        }
        rows += [("Rails", format(rails, "ml")), ("Montants", format(studs, "ml"))]
        if insulationEnabled {
            rows.append(("Isolation · 1re couche · \(insulationDescription(firstInsulation))", format(actualArea * (table.coefficients["insulation_m2_m2"] ?? 1.1), "m²")))
            if insulationLayerCount == .double {
                rows.append(("Isolation · 2e couche · \(insulationDescription(secondInsulation))", format(actualArea * (table.coefficients["insulation_m2_m2"] ?? 1.1), "m²")))
            }
        }
        if vaporBarrier {
            rows.append(("Pare-vapeur", format(actualArea * (table.coefficients["vapor_barrier_m2_m2"] ?? 1.2), "m²")))
            rows.append(("Scotch double-face", format(mounting == .simple ? studs : studs / 2, "ml")))
        }
        let mountingKey = mounting == .simple ? "simple" : "double"
        if spacing == 0.4 || spacing == 0.6 {
            let key = String(format: "%.2f_%@", spacing, mountingKey)
            if let value = table.ttpc25[key] { rows.append(("Vis TTPC 25", format(actualArea * value, "unités", rounded: true))) }
            if skinCount == .double, let value = table.ttpc35[key] { rows.append(("Vis TTPC 35", format(actualArea * value, "unités", rounded: true))) }
            if let value = table.trpf13[key] { rows.append(("Vis TRPF 13", format(actualArea * value, "unités", rounded: true))) }
        }
        if intermediateSupports, maxHeight > 0 {
            let supportsPerLine = Int(ceil((rails / 2) / spacing))
            let lines = max(1, Int(ceil(height / maxHeight)) - 1)
            rows.append(("Appuis intermédiaires pour montant sur mur support", "\(supportsPerLine * lines) unités"))
        }
        if jointTreatment {
            rows.append(("Bande à joint", format(actualArea * (table.coefficients["band_ml_m2"] ?? 1.73), "ml")))
            let key = compound == .powder ? "enduit_poudre_kg_m2" : "enduit_pate_kg_m2"
            rows.append((compound.rawValue, format(actualArea * (table.coefficients[key] ?? 0), "kg")))
        }
        return rows
    }

    private func allocationRows(_ allocations: [FacingAllocation], skinName: String) -> [(String, String)] {
        allocations.flatMap { allocation -> [(String, String)] in
            guard let facing = facing(for: allocation), let plateFormat = selectedFormat(allocation) else { return [] }
            let suppliedArea = allocation.surface * 1.05
            let plateArea = Double(plateFormat.widthMM * plateFormat.lengthMM) / 1_000_000
            let plateCount = Int(ceil(suppliedArea / max(plateArea, 0.01)))
            return [
                ("Parement · \(skinName) · \(facing.title)", format(suppliedArea, "m²")),
                ("Plaques · \(plateFormat.title)", "\(plateCount) unités"),
            ]
        }
    }

    private func facing(for allocation: FacingAllocation) -> LabFacingChoice? {
        facings.first(where: { $0.id == allocation.facingID })
    }

    private func selectedFormat(_ allocation: FacingAllocation) -> LabFacingFormat? {
        facing(for: allocation)?.formats.first(where: { $0.id == allocation.formatID })
    }

    private func groupID(first: FacingAllocation, second: FacingAllocation?) -> String? {
        guard let compatibility, let firstFacing = facing(for: first), let firstFormat = selectedFormat(first) else { return nil }
        if let second {
            guard let secondFacing = facing(for: second), let secondFormat = selectedFormat(second) else { return nil }
            if compatibility.sameWidthRequired && firstFormat.widthMM != secondFormat.widthMM { return nil }
            let width = firstFormat.widthMM
            let rawFamilies = [firstFacing.mechanicalFamily, secondFacing.mechanicalFamily].sorted()
            if let rule = compatibility.exactDouble.first(where: { $0.widthsMM.contains(width) && $0.families.sorted() == rawFamilies }) {
                return rule.performanceGroupID
            }
            let normalized = rawFamilies.map { compatibility.normalizeFamilies[$0] ?? $0 }
            if let rule = compatibility.setDouble.first(where: { $0.widthsMM.contains(width) && normalized.allSatisfy($0.families.contains) }) {
                return rule.performanceGroupID
            }
            return nil
        }
        return compatibility.single.first(where: {
            $0.families.contains(firstFacing.mechanicalFamily) && $0.widthsMM.contains(firstFormat.widthMM)
        })?.performanceGroupID
    }

    private func maximumHeight(frame candidate: String) -> Double {
        guard !performanceGroups.isEmpty else { return 0 }
        let values = performanceGroups.map { group -> Double in
            guard let row = group.values.first(where: { $0.frame == candidate && abs($0.spacing - spacing) < 0.001 }) else { return 0 }
            return mounting == .simple ? row.simple : row.double
        }
        return values.min() ?? 0
    }

    private func frameHasWarning(_ candidate: String) -> Bool { let maximum = maximumHeight(frame: candidate); return maximum == 0 || maximum < height }
    private func frameNumber(_ value: String) -> Int { Int(value.dropFirst().prefix { $0.isNumber }) ?? 0 }

    private var allocationsAreComplete: Bool {
        func complete(_ allocations: [FacingAllocation]) -> Bool {
            !allocations.isEmpty && allocations.allSatisfy { $0.surface > 0 && selectedFormat($0) != nil } && abs(allocations.reduce(0) { $0 + $1.surface } - actualArea) < 0.01
        }
        return complete(firstSkin) && (skinCount == .single || complete(secondSkin))
    }

    private var hasShortPlate: Bool {
        let isShort: (FacingAllocation) -> Bool = { allocation in
            guard let plateFormat = selectedFormat(allocation) else { return false }
            return Double(plateFormat.lengthMM) / 1000 < height
        }
        return firstSkin.contains(where: isShort) || (skinCount == .double && secondSkin.contains(where: isShort))
    }

    private func configurationGroupIDs(firstAllocations: [FacingAllocation], secondAllocations: [FacingAllocation]) -> [String]? {
        let ids: [String]
        if skinCount == .single {
            let groups = firstAllocations.map { groupID(first: $0, second: nil) }
            guard groups.allSatisfy({ $0 != nil }) else { return nil }
            ids = groups.compactMap { $0 }
        } else {
            let groups = firstAllocations.flatMap { first in secondAllocations.map { second in groupID(first: first, second: second) } }
            guard !secondAllocations.isEmpty, groups.allSatisfy({ $0 != nil }) else { return nil }
            ids = groups.compactMap { $0 }
        }
        let families = Set(ids.map(groupFamily))
        return families.count == 1 ? Array(Set(ids)) : nil
    }

    private func groupFamily(_ id: String) -> String {
        ["BA18_900", "BA25_900", "DOUBLE_900"].contains(id) ? "900" : "large"
    }

    private func arraysReplacing(_ candidate: FacingAllocation, allocationID: UUID?, secondLayer: Bool) -> ([FacingAllocation], [FacingAllocation]) {
        var first = firstSkin
        var second = secondSkin
        if secondLayer {
            if let allocationID, let index = second.firstIndex(where: { $0.id == allocationID }) { second[index] = candidate }
            else { second.append(candidate) }
        } else if let allocationID, let index = first.firstIndex(where: { $0.id == allocationID }) {
            first[index] = candidate
        } else {
            first.append(candidate)
        }
        return (first, second)
    }

    private func compatibleFormats(for candidate: LabFacingChoice, allocationID: UUID?, secondLayer: Bool) -> [LabFacingFormat] {
        candidate.formats.filter { plateFormat in
            let allocation = FacingAllocation(id: allocationID ?? UUID(), facingID: candidate.id, formatID: plateFormat.id, surface: 1)
            let arrays = arraysReplacing(allocation, allocationID: allocationID, secondLayer: secondLayer)
            return configurationGroupIDs(firstAllocations: arrays.0, secondAllocations: arrays.1) != nil
        }
    }

    private func availableChoices(for allocationID: UUID?, secondLayer: Bool) -> [LabFacingChoice] {
        let currentLayer = secondLayer ? secondSkin : firstSkin
        let used = Set(currentLayer.filter { $0.id != allocationID }.map(\.facingID))
        return facings.filter { candidate in
            guard !used.contains(candidate.id) else { return false }
            return !compatibleFormats(for: candidate, allocationID: allocationID, secondLayer: secondLayer).isEmpty
        }
    }

    private func availableFamilies(for allocationID: UUID?, secondLayer: Bool) -> [String] {
        Array(Set(availableChoices(for: allocationID, secondLayer: secondLayer).map(\.mechanicalFamily)))
            .sorted { (Int($0.dropFirst(2)) ?? 0) < (Int($1.dropFirst(2)) ?? 0) }
    }

    private func availableFunctions(for allocation: FacingAllocation, secondLayer: Bool) -> [LabFacingChoice] {
        guard let selected = facing(for: allocation) else { return [] }
        return availableChoices(for: allocation.id, secondLayer: secondLayer)
            .filter { $0.mechanicalFamily == selected.mechanicalFamily }
            .sorted { lhs, rhs in
                if lhs.function == "standard" { return true }
                if rhs.function == "standard" { return false }
                return lhs.functionTitle < rhs.functionTitle
            }
    }

    private func availableFormats(for allocation: FacingAllocation, secondLayer: Bool) -> [LabFacingFormat] {
        guard let candidate = facing(for: allocation) else { return [] }
        let compatible = compatibleFormats(for: candidate, allocationID: allocation.id, secondLayer: secondLayer)
        return compatible.isEmpty ? candidate.formats : compatible
    }

    private func preferredFormat(in formats: [LabFacingFormat]) -> LabFacingFormat? {
        let shortest: (LabFacingFormat, LabFacingFormat) -> Bool = { lhs, rhs in
            if lhs.lengthMM != rhs.lengthMM { return lhs.lengthMM < rhs.lengthMM }
            return abs(lhs.widthMM - 1200) < abs(rhs.widthMM - 1200)
        }
        let fitting = formats.filter { Double($0.lengthMM) / 1000 >= height }.sorted(by: shortest)
        if let first = fitting.first { return first }
        return formats.sorted {
            if $0.lengthMM != $1.lengthMM { return $0.lengthMM > $1.lengthMM }
            return abs($0.widthMM - 1200) < abs($1.widthMM - 1200)
        }.first
    }

    private func facingBinding(_ allocation: Binding<FacingAllocation>, secondLayer: Bool) -> Binding<String> {
        Binding(get: { allocation.wrappedValue.facingID }, set: { newID in
            guard let candidate = facings.first(where: { $0.id == newID }) else { return }
            var next = allocation.wrappedValue
            next.facingID = newID
            let formats = compatibleFormats(for: candidate, allocationID: next.id, secondLayer: secondLayer)
            next.formatID = preferredFormat(in: formats.isEmpty ? candidate.formats : formats)?.id ?? ""
            allocation.wrappedValue = next
        })
    }

    private func familyBinding(_ allocation: Binding<FacingAllocation>, secondLayer: Bool) -> Binding<String> {
        Binding(get: { facing(for: allocation.wrappedValue)?.mechanicalFamily ?? "" }, set: { family in
            let choices = availableChoices(for: allocation.wrappedValue.id, secondLayer: secondLayer)
                .filter { $0.mechanicalFamily == family }
            guard let candidate = choices.first(where: { $0.function == "standard" }) ?? choices.first else { return }
            var next = allocation.wrappedValue
            next.facingID = candidate.id
            let formats = compatibleFormats(for: candidate, allocationID: next.id, secondLayer: secondLayer)
            next.formatID = preferredFormat(in: formats.isEmpty ? candidate.formats : formats)?.id ?? ""
            allocation.wrappedValue = next
        })
    }

    private func addAllocation(secondLayer: Bool) {
        guard let choice = availableChoices(for: nil, secondLayer: secondLayer).first else { return }
        let formats = compatibleFormats(for: choice, allocationID: nil, secondLayer: secondLayer)
        let allocation = FacingAllocation(facingID: choice.id, formatID: preferredFormat(in: formats)?.id ?? "")
        if secondLayer { secondSkin.append(allocation) } else { firstSkin.append(allocation) }
    }

    private func removeAllocation(_ id: UUID, secondLayer: Bool) {
        if secondLayer { secondSkin.removeAll { $0.id == id } } else { firstSkin.removeAll { $0.id == id } }
    }

    private func resetParementsForSkinCount() {
        initializeParementsIfNeeded()
        if skinCount == .double, let choice = defaultFacing {
            secondSkin = [FacingAllocation(facingID: choice.id, formatID: preferredFormat(in: choice.formats)?.id ?? "", surface: actualArea)]
        }
        normalizeSelections()
    }

    private func normalizeAfterFirstSkinChange() {
        if skinCount == .double && firstSkin.count == 1 && secondSkin.count == 1 && configurationGroupIDs(firstAllocations: firstSkin, secondAllocations: secondSkin) == nil,
           let partner = availableChoices(for: secondSkin[0].id, secondLayer: true).first {
            secondSkin[0].facingID = partner.id
            secondSkin[0].formatID = preferredFormat(in: compatibleFormats(for: partner, allocationID: secondSkin[0].id, secondLayer: true))?.id ?? ""
        }
        normalizeSelections()
    }

    private var defaultFacing: LabFacingChoice? {
        facings.first(where: { $0.mechanicalFamily == "BA13" && $0.function == "standard" }) ?? facings.first
    }

    private func initializeParementsIfNeeded() {
        guard let choice = defaultFacing else { return }
        let formatID = preferredFormat(in: choice.formats)?.id ?? choice.formats.first?.id ?? ""
        if firstSkin.isEmpty || facing(for: firstSkin[0]) == nil {
            firstSkin = [FacingAllocation(facingID: choice.id, formatID: formatID, surface: actualArea)]
        }
        if secondSkin.isEmpty || facing(for: secondSkin[0]) == nil {
            secondSkin = [FacingAllocation(facingID: choice.id, formatID: formatID, surface: actualArea)]
        }
    }

    private func normalizeSelections() {
        guard let group = performanceGroups.first else { return }
        let choices = Array(Set(group.values.map(\.frame))).sorted { frameNumber($0) < frameNumber($1) }
        if !choices.contains(frame) { frame = choices.first ?? frame }
        let choicesSpacing = Array(Set(group.values.map(\.spacing))).sorted()
        if !choicesSpacing.contains(where: { abs($0 - spacing) < 0.001 }) { spacing = choicesSpacing.last ?? spacing }
    }

    private func insulationFamily(_ selection: InsulationSelection) -> LabInsulationFamily? {
        insulationFamilies.first(where: { $0.id == selection.familyID })
    }

    private func insulationLambdas(for selection: InsulationSelection) -> [LabInsulationLambda] {
        insulationFamily(selection)?.lambdas ?? []
    }

    private func insulationThicknesses(for selection: InsulationSelection) -> [Int] {
        insulationLambdas(for: selection).first(where: { abs($0.value - selection.lambda) < 0.000_001 })?.thicknessesMM ?? []
    }

    private func insulationFamilyBinding(_ selection: Binding<InsulationSelection>) -> Binding<String> {
        Binding(get: { selection.wrappedValue.familyID }, set: { familyID in
            guard let family = insulationFamilies.first(where: { $0.id == familyID }), let lambda = family.lambdas.first else { return }
            selection.wrappedValue = InsulationSelection(familyID: familyID, lambda: lambda.value, thicknessMM: lambda.thicknessesMM.first ?? 0)
        })
    }

    private func insulationLambdaBinding(_ selection: Binding<InsulationSelection>) -> Binding<Double> {
        Binding(get: { selection.wrappedValue.lambda }, set: { lambda in
            var next = selection.wrappedValue
            next.lambda = lambda
            next.thicknessMM = insulationLambdas(for: next).first(where: { abs($0.value - lambda) < 0.000_001 })?.thicknessesMM.first ?? 0
            selection.wrappedValue = next
        })
    }

    private func initializeInsulationIfNeeded() {
        guard let family = insulationFamilies.first, let lambda = family.lambdas.first else { return }
        let fallback = InsulationSelection(familyID: family.id, lambda: lambda.value, thicknessMM: lambda.thicknessesMM.first ?? 0)
        if insulationFamily(firstInsulation) == nil { firstInsulation = fallback }
        if insulationFamily(secondInsulation) == nil { secondInsulation = fallback }
    }

    private func insulationSelectionIsComplete(_ selection: InsulationSelection) -> Bool {
        insulationFamily(selection) != nil && insulationThicknesses(for: selection).contains(selection.thicknessMM)
    }

    private func thermalResistance(thicknessMM: Int, lambda: Double) -> Double {
        guard thicknessMM > 0, lambda > 0 else { return 0 }
        return (Double(thicknessMM) / 1000) / lambda
    }

    private var thermalResistanceTotal: Double {
        let first = thermalResistance(thicknessMM: firstInsulation.thicknessMM, lambda: firstInsulation.lambda)
        let second = insulationLayerCount == .double ? thermalResistance(thicknessMM: secondInsulation.thicknessMM, lambda: secondInsulation.lambda) : 0
        return first + second
    }

    private func insulationDescription(_ selection: InsulationSelection) -> String {
        let name = insulationFamily(selection)?.title ?? "Isolant"
        return "\(name), λ \(selection.lambda.formatted(.number.precision(.fractionLength(3)))), \(selection.thicknessMM) mm, R \(thermalResistance(thicknessMM: selection.thicknessMM, lambda: selection.lambda).formatted(.number.precision(.fractionLength(2))))"
    }

    private func reset() {
        step = 1; geometryMode = .length; height = 0; enteredLength = 0; enteredSurface = 0
        skinCount = .single; firstSkin = [FacingAllocation()]; secondSkin = [FacingAllocation()]
        technique = "Rails et montants"; frame = "R48 + M48"; mounting = .simple; spacing = 0.6
        intermediateSupports = false; insulationEnabled = true; insulationLayerCount = .single
        firstInsulation = InsulationSelection(); secondInsulation = InsulationSelection(); vaporBarrier = false
        jointTreatment = true; compound = .powder
        initializeParementsIfNeeded()
        initializeInsulationIfNeeded()
        normalizeSelections()
    }

    private func advance() {
        guard canContinue else { return }
        if step == 1 {
            if firstSkin.count == 1 && firstSkin[0].surface == 0 { firstSkin[0].surface = actualArea }
            if secondSkin.count == 1 && secondSkin[0].surface == 0 { secondSkin[0].surface = actualArea }
            if let choice = facing(for: firstSkin[0]) { firstSkin[0].formatID = preferredFormat(in: choice.formats)?.id ?? firstSkin[0].formatID }
            if let choice = facing(for: secondSkin[0]) { secondSkin[0].formatID = preferredFormat(in: choice.formats)?.id ?? secondSkin[0].formatID }
        }
        if step == 2 && hasShortPlate { showPlateHeightWarning = true }
        else { step += 1 }
    }

    private func format(_ value: Double, _ unit: String, rounded: Bool = false) -> String {
        let number = rounded ? ceil(value) : value
        return number.formatted(.number.precision(.fractionLength(rounded ? 0 : 2))) + " " + unit
    }

    private func sectionTitle(_ text: String) -> some View { Text(text).font(.headline).foregroundStyle(.secondary).padding(.horizontal, 12) }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 14, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 22)) }
    private func warning(_ text: String) -> some View { info(text, icon: "exclamationmark.triangle.fill", color: .orange) }
    private func info(_ text: String, icon: String, color: Color) -> some View { HStack(alignment: .top, spacing: 14) { Image(systemName: icon).foregroundStyle(color); Text(text).fixedSize(horizontal: false, vertical: true) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 22)) }
}

private struct DecimalRow: View {
    let title: String
    @Binding var value: Double
    let unit: String
    init(_ title: String, value: Binding<Double>, unit: String) { self.title = title; _value = value; self.unit = unit }
    var body: some View {
        HStack {
            Text(title); Spacer()
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 86)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
