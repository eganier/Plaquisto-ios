import SwiftUI

struct DoublageConfiguratorView: View {
    enum GeometryMode: String, CaseIterable, Identifiable { case length = "Longueur", surface = "Surface totale"; var id: Self { self } }
    enum SkinCount: String, CaseIterable, Identifiable { case single = "Simple peau", double = "Double peau"; var id: Self { self } }
    enum StudMounting: String, CaseIterable, Identifiable { case simple = "Montants simples", double = "Montants doubles"; var id: Self { self } }
    enum Compound: String, CaseIterable, Identifiable { case powder = "Enduit en poudre", paste = "Enduit en pâte"; var id: Self { self } }

    struct FacingChoice: Identifiable, Hashable {
        let id: String
        let title: String
        let width: Double
    }

    struct FacingAllocation: Identifiable, Hashable {
        let id: UUID
        var facingID: String
        var surface: Double
        var plateHeight: Double

        init(id: UUID = UUID(), facingID: String, surface: Double = 0, plateHeight: Double = 0) {
            self.id = id; self.facingID = facingID; self.surface = surface; self.plateHeight = plateHeight
        }
    }

    private static let facings = [
        FacingChoice(id: "ba13", title: "BA13 standard", width: 1.20),
        FacingChoice(id: "ba13_hydro", title: "BA13 hydrofuge", width: 1.20),
        FacingChoice(id: "ba13_fire", title: "BA13 feu", width: 1.20),
        FacingChoice(id: "ba15", title: "BA15 standard", width: 1.20),
        FacingChoice(id: "ba15_fire", title: "BA15 feu", width: 1.20),
        FacingChoice(id: "ba18", title: "BA18 standard", width: 1.20),
        FacingChoice(id: "ba18s", title: "BA18S standard · largeur 900 mm", width: 0.90),
        FacingChoice(id: "ba25", title: "BA25 standard", width: 0.90),
    ]

    @EnvironmentObject private var references: LabReferenceStore
    @State private var step = 1
    @State private var geometryMode = GeometryMode.length
    @State private var height = 0.0
    @State private var enteredLength = 0.0
    @State private var enteredSurface = 0.0
    @State private var skinCount = SkinCount.single
    @State private var firstSkin = [FacingAllocation(facingID: "ba13")]
    @State private var secondSkin = [FacingAllocation(facingID: "ba13")]
    @State private var technique = "Rails et montants"
    @State private var frame = "R48 + M48"
    @State private var mounting = StudMounting.simple
    @State private var spacing = 0.6
    @State private var intermediateSupports = false
    @State private var jointTreatment = true
    @State private var compound = Compound.powder
    @State private var showPlateHeightWarning = false

    private let stepNames = ["Dimensions", "Parements", "Technique et ossature", "Bandes à joint", "Résultat"]
    private var groups: [LabPerformanceGroup] { references.groups }
    private var actualLength: Double { geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0) }
    private var actualArea: Double { geometryMode == .surface ? enteredSurface : enteredLength * height }
    private var performanceGroupIDs: [String] {
        if skinCount == .single { return Array(Set(firstSkin.compactMap { groupID(first: $0.facingID, second: nil) })) }
        return Array(Set(firstSkin.flatMap { first in secondSkin.compactMap { second in groupID(first: first.facingID, second: second.facingID) } }))
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
        .onChange(of: groups.count, initial: true) { _, _ in normalizeSelections() }
        .onChange(of: skinCount) { _, _ in resetParementsForSkinCount() }
        .onChange(of: firstSkin) { _, _ in normalizeAfterFirstSkinChange() }
        .onChange(of: secondSkin) { _, _ in normalizeSelections() }
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
                    case 4: jointsStep
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
            ProgressView(value: Double(step), total: 5).tint(.green)
            Text("Étape \(step) sur 5 · \(stepNames[step - 1])").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
        .background(.background)
    }

    private var footer: some View {
        HStack {
            if step > 1 { Button("Retour") { step -= 1 }.buttonStyle(.bordered).tint(.green) }
            Spacer()
            if step < 5 { Button("Continuer") { advance() }.buttonStyle(.borderedProminent).tint(.green).disabled(!canContinue) }
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
            Picker("Type de parement", selection: allocation.facingID) {
                ForEach(availableChoices(for: allocation.wrappedValue.id, secondLayer: secondLayer)) { Text($0.title).tag($0.id) }
            }
            Divider()
            DecimalRow("Hauteur des plaques", value: allocation.plateHeight, unit: "m")
            Divider()
            DecimalRow("Surface attribuée", value: allocation.surface, unit: "m²")
            if height > 0 && allocation.wrappedValue.plateHeight > 0 && allocation.wrappedValue.plateHeight < height {
                Label("Cette hauteur est inférieure à la hauteur sous plafond de \(format(height, "m")).", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if canDelete {
                Divider()
                Button("Supprimer ce type", role: .destructive) { removeAllocation(allocation.wrappedValue.id, secondLayer: secondLayer) }
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
            guard let facing = Self.facings.first(where: { $0.id == allocation.facingID }) else { return [] }
            let suppliedArea = allocation.surface * 1.05
            let plateCount = Int(ceil(suppliedArea / (facing.width * max(allocation.plateHeight, 0.01))))
            return [
                ("Parement · \(skinName) · \(facing.title)", format(suppliedArea, "m²")),
                ("Plaques · H. \(format(allocation.plateHeight, "m"))", "\(plateCount) unités"),
            ]
        }
    }

    private func groupID(first: String, second: String?) -> String? {
        if let second {
            let pair = Set([first, second])
            if pair.isSubset(of: Set(["ba13", "ba13_hydro"])) { return "DOUBLE_1200" }
            if pair == Set(["ba13", "ba18"]) || pair == Set(["ba13_hydro", "ba18"]) { return "DOUBLE_1200" }
            if first == "ba13_fire" && second == "ba13_fire" { return "DOUBLE_1200" }
            if first == "ba15_fire" && second == "ba15_fire" { return "DOUBLE_1200" }
            if pair == Set(["ba25", "ba13"]) || pair == Set(["ba25", "ba13_hydro"]) { return "BA25_MIX" }
            if first == "ba18s" && second == "ba18s" { return "DOUBLE_900" }
            if first == "ba25" && second == "ba25" { return "DOUBLE_900" }
            return nil
        }
        if ["ba13", "ba13_hydro", "ba15"].contains(first) { return "BA13_BA15" }
        if first == "ba18" { return "BA18" }
        if first == "ba18s" { return "BA18S" }
        if first == "ba25" { return "BA25_MIX" }
        return nil
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
            !allocations.isEmpty && allocations.allSatisfy { $0.surface > 0 && $0.plateHeight > 0 } && abs(allocations.reduce(0) { $0 + $1.surface } - actualArea) < 0.01
        }
        return complete(firstSkin) && (skinCount == .single || complete(secondSkin))
    }

    private var hasShortPlate: Bool {
        firstSkin.contains(where: { $0.plateHeight < height }) || (skinCount == .double && secondSkin.contains(where: { $0.plateHeight < height }))
    }

    private func configurationGroupIDs(firstIDs: [String], secondIDs: [String]) -> [String]? {
        let ids: [String]
        if skinCount == .single {
            let groups = firstIDs.map { groupID(first: $0, second: nil) }
            guard groups.allSatisfy({ $0 != nil }) else { return nil }
            ids = groups.compactMap { $0 }
        } else {
            let groups = firstIDs.flatMap { first in secondIDs.map { second in groupID(first: first, second: second) } }
            guard !secondIDs.isEmpty, groups.allSatisfy({ $0 != nil }) else { return nil }
            ids = groups.compactMap { $0 }
        }
        let families = Set(ids.map(groupFamily))
        return families.count == 1 ? Array(Set(ids)) : nil
    }

    private func groupFamily(_ id: String) -> String {
        ["BA13_BA15", "BA18", "DOUBLE_1200"].contains(id) ? "1200" : "900"
    }

    private func availableChoices(for allocationID: UUID?, secondLayer: Bool) -> [FacingChoice] {
        let currentLayer = secondLayer ? secondSkin : firstSkin
        let used = Set(currentLayer.filter { $0.id != allocationID }.map(\.facingID))
        return Self.facings.filter { candidate in
            guard !used.contains(candidate.id) else { return false }
            if skinCount == .double && !secondLayer && allocationID != nil && firstSkin.count == 1 && secondSkin.count == 1 {
                return Self.facings.contains { partner in groupID(first: candidate.id, second: partner.id) != nil }
            }
            var firstIDs = firstSkin.map(\.facingID)
            var secondIDs = secondSkin.map(\.facingID)
            if secondLayer {
                if let index = secondSkin.firstIndex(where: { $0.id == allocationID }) { secondIDs[index] = candidate.id }
                else { secondIDs.append(candidate.id) }
            } else {
                if let index = firstSkin.firstIndex(where: { $0.id == allocationID }) { firstIDs[index] = candidate.id }
                else { firstIDs.append(candidate.id) }
            }
            return configurationGroupIDs(firstIDs: firstIDs, secondIDs: secondIDs) != nil
        }
    }

    private func addAllocation(secondLayer: Bool) {
        guard let choice = availableChoices(for: nil, secondLayer: secondLayer).first else { return }
        let allocation = FacingAllocation(facingID: choice.id, plateHeight: height)
        if secondLayer { secondSkin.append(allocation) } else { firstSkin.append(allocation) }
    }

    private func removeAllocation(_ id: UUID, secondLayer: Bool) {
        if secondLayer { secondSkin.removeAll { $0.id == id } } else { firstSkin.removeAll { $0.id == id } }
    }

    private func resetParementsForSkinCount() {
        if firstSkin.isEmpty { firstSkin = [FacingAllocation(facingID: "ba13", surface: actualArea, plateHeight: height)] }
        if skinCount == .double { secondSkin = [FacingAllocation(facingID: "ba13", surface: actualArea, plateHeight: height)] }
        normalizeSelections()
    }

    private func normalizeAfterFirstSkinChange() {
        if skinCount == .double && firstSkin.count == 1 && secondSkin.count == 1 && configurationGroupIDs(firstIDs: firstSkin.map(\.facingID), secondIDs: secondSkin.map(\.facingID)) == nil,
           let partner = Self.facings.first(where: { groupID(first: firstSkin[0].facingID, second: $0.id) != nil }) {
            secondSkin[0].facingID = partner.id
        }
        normalizeSelections()
    }

    private func normalizeSelections() {
        guard let group = performanceGroups.first else { return }
        let choices = Array(Set(group.values.map(\.frame))).sorted { frameNumber($0) < frameNumber($1) }
        if !choices.contains(frame) { frame = choices.first ?? frame }
        let choicesSpacing = Array(Set(group.values.map(\.spacing))).sorted()
        if !choicesSpacing.contains(where: { abs($0 - spacing) < 0.001 }) { spacing = choicesSpacing.last ?? spacing }
    }

    private func reset() {
        step = 1; geometryMode = .length; height = 0; enteredLength = 0; enteredSurface = 0
        skinCount = .single; firstSkin = [FacingAllocation(facingID: "ba13")]; secondSkin = [FacingAllocation(facingID: "ba13")]
        technique = "Rails et montants"; frame = "R48 + M48"; mounting = .simple; spacing = 0.6
        intermediateSupports = false; jointTreatment = true; compound = .powder
        normalizeSelections()
    }

    private func advance() {
        guard canContinue else { return }
        if step == 1 {
            if firstSkin.count == 1 && firstSkin[0].surface == 0 { firstSkin[0].surface = actualArea }
            if firstSkin.count == 1 && firstSkin[0].plateHeight == 0 { firstSkin[0].plateHeight = height }
            if secondSkin.count == 1 && secondSkin[0].surface == 0 { secondSkin[0].surface = actualArea }
            if secondSkin.count == 1 && secondSkin[0].plateHeight == 0 { secondSkin[0].plateHeight = height }
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
