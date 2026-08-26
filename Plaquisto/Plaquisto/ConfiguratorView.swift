import SwiftUI

struct Supply: Identifiable {
    let id: String
    let name: String
    let quantity: Double
    let unit: String
}

private struct InsulationPoint: Identifiable {
    let thickness: Double
    let maxWeight: Double
    var id: Double { thickness }
}

private struct FixingComponent: Identifiable {
    let name: String
    let quantity: Double
    let unit: String
    let calculation: String
    var id: String { "\(name)-\(unit)-\(calculation)" }
}

private struct VaporBarrierComponent: Identifiable {
    let name: String
    let quantity: Double
    let unit: String
    let calculation: String
    let excludeWhenSystemHandlesVaporBarrier: Bool
    var id: String { "\(name)-\(unit)-\(calculation)" }
}

private struct FacingDimension: Identifiable, Hashable {
    let width: Double
    let length: Double
    var id: String { "\(Int(width))x\(Int(length))" }
    var label: String { "\(Int(width)) × \(Int(length)) mm" }
    var area: Double { width * length / 1_000_000 }
}

private typealias FacingAllocation = FacingSelection

struct ConfiguratorView: View {
    @StateObject private var store = ReferenceStore()
    @State private var step: Int
    @State private var length: Double
    @State private var width: Double
    @State private var enteredArea: Double
    @State private var support: String
    @State private var plenum: Double
    @State private var vaporBarrier: Bool
    @State private var insulationID: String
    @State private var insulationThickness: Double
    @State private var selectedSpacing: Double
    @State private var showSpacingWarning = false
    @State private var showDimensionsWarning = false
    @State private var fixingSystemID: String
    @State private var layers: Int
    @State private var firstSkin: [FacingAllocation]
    @State private var secondSkin: [FacingAllocation]
    @State private var jointTreatment: Bool
    @State private var compoundChoice: String
    @State private var showingSavedResult: Bool
    private let onSave: (CeilingConfiguration) -> Void

    private let stepNames = ["Dimensions", "Support", "Isolation et entraxe", "Fixation", "Parements", "Bandes à joint", "Résultat"]
    private let spacingChoices = [0.4, 0.5, 0.6]

    init(
        initialConfiguration: CeilingConfiguration = CeilingConfiguration(),
        startsAtResult: Bool = false,
        onSave: @escaping (CeilingConfiguration) -> Void = { _ in }
    ) {
        _step = State(initialValue: startsAtResult ? 6 : 0)
        _length = State(initialValue: initialConfiguration.length)
        _width = State(initialValue: initialConfiguration.width)
        _enteredArea = State(initialValue: initialConfiguration.length * initialConfiguration.width)
        _support = State(initialValue: initialConfiguration.support)
        _plenum = State(initialValue: initialConfiguration.plenum)
        _vaporBarrier = State(initialValue: initialConfiguration.vaporBarrier)
        _insulationID = State(initialValue: initialConfiguration.insulationID)
        _insulationThickness = State(initialValue: initialConfiguration.insulationThickness)
        _selectedSpacing = State(initialValue: initialConfiguration.selectedSpacing)
        _fixingSystemID = State(initialValue: initialConfiguration.fixingSystemID)
        _layers = State(initialValue: initialConfiguration.layers)
        _firstSkin = State(initialValue: initialConfiguration.firstSkin)
        _secondSkin = State(initialValue: initialConfiguration.secondSkin)
        _jointTreatment = State(initialValue: initialConfiguration.jointTreatment)
        _compoundChoice = State(initialValue: initialConfiguration.compoundChoice)
        _showingSavedResult = State(initialValue: startsAtResult)
        self.onSave = onSave
    }

    private var catalogue: CataloguePayload? { store.catalogue }
    private var workTitle: String { catalogue?.ouvrage?.title ?? "Plafond sur fourrures horizontal" }
    private var insulationSeries: [ReferenceRecord] { catalogue?.isolation ?? [] }
    private var fixingSystems: [ReferenceRecord] { catalogue?.systemesFixation ?? [] }
    private var facings: [ReferenceRecord] { catalogue?.parements ?? [] }
    private var quantityItems: [ReferenceRecord] { catalogue?.quantitatifs ?? [] }
    private var vaporBarrierRecords: [ReferenceRecord] { catalogue?.pareVapeur ?? [] }
    private var supports: [String] {
        Array(Set(fixingSystems.compactMap { $0.data["support"]?.string })).sorted()
    }
    private var selectedInsulation: ReferenceRecord? { insulationSeries.first { $0.id == insulationID } }
    private var insulationPoints: [InsulationPoint] {
        selectedInsulation?.data["values"]?.array?.compactMap { value in
            guard let object = value.object,
                  let thickness = object["thickness_mm"]?.number,
                  let weight = object["max_weight_kg_m2"]?.number else { return nil }
            return InsulationPoint(thickness: thickness, maxWeight: weight)
        }.sorted { $0.thickness < $1.thickness } ?? []
    }
    private var selectedInsulationPoint: InsulationPoint? {
        insulationPoints.first { abs($0.thickness - insulationThickness) < 0.01 }
    }
    private var insulationWeight: Double { selectedInsulationPoint?.maxWeight ?? 0 }
    private var maximumSpacing: Double? {
        guard insulationWeight <= 15 else { return nil }
        if insulationWeight >= 10 { return 0.4 }
        if insulationWeight >= 6 { return 0.5 }
        return 0.6
    }
    private var spacingIsAboveRecommendation: Bool {
        guard let maximumSpacing else { return false }
        return selectedSpacing > maximumSpacing
    }
    private var compatibleSystems: [ReferenceRecord] {
        let plenumMM = plenum * 10
        return fixingSystems.filter { system in
            guard system.data["support"]?.string == support,
                  let minimum = system.data["plenum_min_mm"]?.number,
                  let maximum = system.data["plenum_max_mm"]?.number,
                  plenumMM >= minimum, plenumMM <= maximum else { return false }
            return true
        }
    }
    private var selectedFixingSystem: ReferenceRecord? {
        compatibleSystems.first { $0.id == fixingSystemID }
    }
    private var selectedComponents: [FixingComponent] { components(for: selectedFixingSystem) }
    private var area: Double { enteredArea }
    private var quantityConfigurationKey: String {
        let prefix = layers == 1 ? "simple" : "double"
        return "\(prefix)_0\(Int((selectedSpacing * 100).rounded()))"
    }
    private var fixingSystemCount: Double {
        guard let row = quantityItems.first(where: { $0.id == "QTY-FIXATION" }),
              let ratio = row.data["values"]?.object?[quantityConfigurationKey]?.number else { return 0 }
        return ratio * area
    }
    private var otherSupplies: [Supply] {
        var result: [Supply] = []

        for item in quantityItems where !["QTY-FIXATION", "QTY-PLAQUE"].contains(item.id) {
            if !jointTreatment && ["QTY-BANDE", "QTY-ENDUIT-POUDRE", "QTY-ENDUIT-PATE"].contains(item.id) { continue }
            if jointTreatment && compoundChoice == "poudre" && item.id == "QTY-ENDUIT-PATE" { continue }
            if jointTreatment && compoundChoice == "pate" && item.id == "QTY-ENDUIT-POUDRE" { continue }
            guard let ratio = item.data["values"]?.object?[quantityConfigurationKey]?.number,
                  ratio > 0,
                  let unit = item.data["unit"]?.string else { continue }
            result.append(Supply(id: item.id, name: item.title, quantity: ratio * area, unit: unit))
        }

        for (index, component) in selectedComponents.enumerated() {
            var quantity = fixingSystemCount * component.quantity
            if component.calculation == "plenum_m" { quantity *= plenum / 100 }
            result.append(Supply(id: "FIX-\(index)-\(component.name)", name: component.name, quantity: quantity, unit: component.unit))
        }
        return result
    }
    private var facingSupplies: [Supply] {
        suppliesForSkin(firstSkin, name: "Première peau") + (layers == 2 ? suppliesForSkin(secondSkin, name: "Deuxième peau") : [])
    }
    private var vaporBarrierSupplies: [Supply] {
        guard vaporBarrier else { return [] }
        let systemHandlesVaporBarrier = selectedFixingSystem?.data["pare_vapeur_compatible"]?.bool == true
        let fourrureRatio = quantityItems.first(where: { $0.id == "QTY-FOURRURE" })?.data["values"]?.object?[quantityConfigurationKey]?.number ?? 0

        return vaporBarrierRecords.flatMap { record in
            vaporBarrierComponents(for: record).compactMap { component in
                if component.excludeWhenSystemHandlesVaporBarrier && systemHandlesVaporBarrier { return nil }
                let quantity = component.calculation == "fourrure_ml"
                    ? component.quantity * fourrureRatio * area
                    : component.quantity * area
                guard quantity > 0 else { return nil }
                return Supply(id: "\(record.id)-\(component.id)", name: component.name, quantity: quantity, unit: component.unit)
            }
        }
    }

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("Synchronisation avec Plaquisto Admin…")
            } else if let error = store.error {
                ContentUnavailableView("Référentiel indisponible", systemImage: "wifi.exclamationmark", description: Text(error))
                    .overlay(alignment: .bottom) {
                        Button("Réessayer") { Task { await store.load() } }
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom, 80)
                    }
            } else {
                configurator
            }
        }
        .task { if store.catalogue == nil { await store.load() } }
        .tint(Color(red: 0.12, green: 0.38, blue: 0.29))
    }

    private var configurator: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("OUVRAGE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(workTitle).font(.title2.bold())
                if store.isUsingOfflineData {
                    Label("Mode hors connexion · dernières données synchronisées", systemImage: "icloud.slash")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Label("Données synchronisées avec Plaquisto Admin", systemImage: "checkmark.icloud")
                        .font(.caption).foregroundStyle(.green)
                }
                ProgressView(value: Double(step + 1), total: Double(stepNames.count))
                Text("Étape \(step + 1) sur \(stepNames.count) · \(stepNames[step])")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()

            Divider()
            Form { stepContent }

            HStack {
                if step > 0 { Button("Retour") { withAnimation { step -= 1 } }.buttonStyle(.bordered) }
                Spacer()
                if step < stepNames.count - 1 {
                    Button("Continuer") { advance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canContinue)
                } else {
                    if showingSavedResult {
                        Button("Modifier l’ouvrage") {
                            showingSavedResult = false
                            withAnimation { step = 0 }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Enregistrer l’ouvrage") {
                            onSave(configuration)
                            showingSavedResult = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Entraxe supérieur à la valeur recommandée", isPresented: $showSpacingWarning) {
            Button("Modifier l’entraxe", role: .cancel) {}
            Button("Poursuivre malgré l’avertissement") { completeAdvance() }
        } message: {
            Text("L’entraxe choisi de \(Int(selectedSpacing * 100)) cm dépasse la valeur maximale recommandée de \(Int((maximumSpacing ?? 0) * 100)) cm pour le poids d’isolant retenu. Cette configuration peut ne pas respecter les règles techniques applicables. Souhaitez-vous néanmoins poursuivre ?")
        }
        .alert("Dimensions non renseignées", isPresented: $showDimensionsWarning) {
            Button("Renseigner les dimensions", role: .cancel) {}
            Button("Continuer avec une estimation") {
                let side = sqrt(enteredArea)
                length = side
                width = side
                completeAdvance()
            }
        } message: {
            Text("Les calculs seront plus précis si la longueur et la largeur de l’ouvrage sont renseignées. Souhaitez-vous vraiment continuer ? Plaquisto estimera les dimensions en considérant une forme carrée.")
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            Section("Dimensions de l’ouvrage") {
                MeasureField(label: "Surface", value: $enteredArea, unit: "m²")
                    .onChange(of: enteredArea) { oldValue, newValue in
                        guard abs(newValue - oldValue) > 0.0001, length > 0, width > 0, abs(newValue - length * width) > 0.01 else { return }
                        length = 0
                        width = 0
                    }
            }
            Section {
                MeasureField(label: "Longueur", value: $length, unit: "m")
                    .onChange(of: length) { _, _ in updateAreaFromDimensions() }
                MeasureField(label: "Largeur", value: $width, unit: "m")
                    .onChange(of: width) { _, _ in updateAreaFromDimensions() }
            } footer: {
                Text("La longueur et la largeur améliorent la précision des calculs. Si elles sont toutes les deux renseignées, la surface est calculée automatiquement.")
            }

        case 1:
            Section("Support du plafond") {
                Picker("Type de support", selection: $support) {
                    Text("Sélectionner").tag("")
                    ForEach(supports, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: support) { _, _ in fixingSystemID = "" }
                MeasureField(label: "Hauteur du plénum", value: $plenum, unit: "cm")
                    .onChange(of: plenum) { _, _ in fixingSystemID = "" }
                Toggle("Prévoir la pose d’un pare-vapeur", isOn: $vaporBarrier)
            }
            Section {
                Label("Le plénum correspond à l’espace vide situé entre le faux plafond, ou plafond suspendu, et la dalle du plancher.", systemImage: "info.circle")
                if vaporBarrier {
                    Text("Les fournitures nécessaires au pare-vapeur seront ajoutées au quantitatif.")
                        .foregroundStyle(.secondary)
                }
            }

        case 2:
            Section {
                Picker("Type d’isolant", selection: $insulationID) {
                    Text("Sans isolant").tag("")
                    ForEach(insulationSeries) { Text($0.title).tag($0.id) }
                }
                .onChange(of: insulationID) { _, _ in
                    insulationThickness = insulationPoints.first?.thickness ?? 0
                    selectedSpacing = maximumSpacing ?? 0.4
                    fixingSystemID = ""
                }
                if !insulationID.isEmpty {
                    Picker("Épaisseur", selection: $insulationThickness) {
                        ForEach(insulationPoints) { point in Text("\(Int(point.thickness)) mm").tag(point.thickness) }
                    }
                    .onChange(of: insulationThickness) { _, _ in
                        selectedSpacing = maximumSpacing ?? 0.4
                        fixingSystemID = ""
                    }
                    LabeledContent("Poids maximal retenu", value: "\(format(insulationWeight)) kg/m²")
                }
            } header: {
                Text("Isolation")
            } footer: {
                Text("Pour une plage de poids, Plaquisto retient toujours la valeur la plus élevée.")
            }
            Section("Entraxe des fourrures") {
                Picker("Entraxe", selection: $selectedSpacing) {
                    ForEach(spacingChoices, id: \.self) { spacing in Text("\(Int(spacing * 100)) cm").tag(spacing) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Maximum recommandé", value: maximumSpacing.map { "\(Int($0 * 100)) cm" } ?? "Non couvert")
            }
            if spacingIsAboveRecommendation {
                Section {
                    Label("L’entraxe choisi dépasse la valeur maximale recommandée pour cette configuration.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

        case 3:
            Section("Système de fixation") {
                if compatibleSystems.isEmpty {
                    Label("Aucun système publié n’est compatible avec cette configuration.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Picker("Système", selection: $fixingSystemID) {
                        Text("Sélectionner").tag("")
                        ForEach(compatibleSystems) { Text($0.title).tag($0.id) }
                    }
                }
            }
            if let system = selectedFixingSystem {
                Section {
                    ForEach(selectedComponents) { component in
                        LabeledContent(component.name, value: componentDescription(component))
                    }
                } header: {
                    Text("Fournitures composant le système de fixation")
                } footer: {
                    Text(system.summary)
                }
            }

        case 4:
            Section("Nombre de peaux") {
                Picker("Parement", selection: $layers) {
                    Text("Simple peau").tag(1)
                    Text("Double peau").tag(2)
                }
                .pickerStyle(.segmented)
                .onChange(of: layers) { _, _ in ensureFacingAllocations() }
            }
            allocationSection(title: "Première peau", allocations: $firstSkin)
            if layers == 2 { allocationSection(title: "Deuxième peau", allocations: $secondSkin) }

        case 5:
            Section("Traitement des bandes à joint") {
                Toggle("Prévoir le traitement des bandes", isOn: $jointTreatment)
                if jointTreatment {
                    Picker("Type d’enduit", selection: $compoundChoice) {
                        Text("Enduit en poudre").tag("poudre")
                        Text("Enduit en pâte").tag("pate")
                    }
                }
            }
            Section {
                if jointTreatment {
                    Label("La bande à joint et l’enduit choisi seront ajoutés au quantitatif.", systemImage: "checkmark.circle")
                } else {
                    Text("Aucune bande à joint ni aucun enduit ne sera ajouté au quantitatif.")
                        .foregroundStyle(.secondary)
                }
            }

        default:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Quantitatif calculé", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text("\(format(area)) m² · \(layers == 1 ? "simple" : "double") peau · entraxe \(Int(selectedSpacing * 100)) cm")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }
            Section("Système de fixation") {
                LabeledContent("Solution", value: selectedFixingSystem?.title ?? "—")
                LabeledContent("Nombre de systèmes", value: String(Int(ceil(fixingSystemCount))))
            }
            Section("Pare-vapeur") {
                LabeledContent("Pose prévue", value: vaporBarrier ? "Oui" : "Non")
                if vaporBarrier {
                    ForEach(vaporBarrierSupplies) { supply in
                        LabeledContent(supply.name, value: "\(formattedQuantity(supply.quantity, unit: supply.unit)) \(supply.unit)")
                    }
                }
            }
            Section("Parements utilisés") {
                ForEach(facingSupplies) { supply in
                    LabeledContent(supply.name, value: "\(Int(supply.quantity)) \(supply.unit)")
                }
            }
            Section("Traitement des joints") {
                LabeledContent("Bandes à joint", value: jointTreatment ? "Oui" : "Non")
                if jointTreatment { LabeledContent("Enduit retenu", value: compoundChoice == "poudre" ? "Enduit en poudre" : "Enduit en pâte") }
            }
            Section("Autres fournitures indicatives") {
                ForEach(otherSupplies) { supply in
                    LabeledContent(supply.name, value: "\(formattedQuantity(supply.quantity, unit: supply.unit)) \(supply.unit)")
                }
            }
            Section {
                Text("Les quantités sont indicatives et proviennent des tableaux publiés dans Plaquisto Admin.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func allocationSection(title: String, allocations: Binding<[FacingAllocation]>) -> some View {
        Section {
            ForEach(allocations) { $allocation in
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Type de parement", selection: $allocation.facingID) {
                        ForEach(facings) { Text($0.title).tag($0.id) }
                    }
                    .onChange(of: allocation.facingID) { _, _ in
                        allocation.dimensionID = dimensions(for: allocation.facingID).first?.id ?? ""
                    }
                    Picker("Dimension", selection: $allocation.dimensionID) {
                        ForEach(dimensions(for: allocation.facingID)) { dimension in Text(dimension.label).tag(dimension.id) }
                    }
                    MeasureField(label: "Surface attribuée", value: $allocation.area, unit: "m²")
                    if allocations.wrappedValue.count > 1 {
                        Button("Retirer ce parement", role: .destructive) {
                            allocations.wrappedValue.removeAll { $0.id == allocation.id }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Button("Ajouter un autre type de parement") {
                allocations.wrappedValue.append(defaultAllocation(area: 0))
            }
        } header: {
            Text(title)
        } footer: {
            let total = allocations.wrappedValue.reduce(0) { $0 + $1.area }
            let difference = area - total
            Text(abs(difference) < 0.01 ? "Répartition complète : \(format(total)) m²." : difference > 0 ? "Il reste \(format(difference)) m² à répartir." : "La répartition dépasse la surface de \(format(-difference)) m².")
                .foregroundStyle(abs(difference) < 0.01 ? .green : .orange)
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: return enteredArea > 0
        case 1: return !support.isEmpty && plenum > 0
        case 2: return maximumSpacing != nil && (insulationID.isEmpty || selectedInsulationPoint != nil) && spacingChoices.contains(selectedSpacing)
        case 3: return selectedFixingSystem != nil
        case 4: return allocationsAreValid(firstSkin) && (layers == 1 || allocationsAreValid(secondSkin))
        case 5: return !jointTreatment || ["poudre", "pate"].contains(compoundChoice)
        default: return true
        }
    }

    private func advance() {
        if step == 0 && (length <= 0 || width <= 0) { showDimensionsWarning = true }
        else if step == 2 && spacingIsAboveRecommendation { showSpacingWarning = true }
        else { completeAdvance() }
    }

    private func updateAreaFromDimensions() {
        if length > 0 && width > 0 { enteredArea = length * width }
    }

    private func completeAdvance() {
        prepareDefaults()
        withAnimation { step += 1 }
    }

    private func prepareDefaults() {
        if step == 0 && support.isEmpty { support = supports.first ?? "" }
        if step == 2 && fixingSystemID.isEmpty { fixingSystemID = compatibleSystems.first?.id ?? "" }
        if step == 3 { ensureFacingAllocations() }
    }

    private func ensureFacingAllocations() {
        if firstSkin.isEmpty { firstSkin = [defaultAllocation(area: area)] }
        if layers == 2 && secondSkin.isEmpty { secondSkin = [defaultAllocation(area: area)] }
    }

    private func defaultAllocation(area allocationArea: Double) -> FacingAllocation {
        let facingID = facings.first?.id ?? ""
        return FacingAllocation(facingID: facingID, dimensionID: dimensions(for: facingID).first?.id ?? "", area: allocationArea)
    }

    private var configuration: CeilingConfiguration {
        CeilingConfiguration(
            length: length,
            width: width,
            support: support,
            plenum: plenum,
            vaporBarrier: vaporBarrier,
            insulationID: insulationID,
            insulationThickness: insulationThickness,
            selectedSpacing: selectedSpacing,
            fixingSystemID: fixingSystemID,
            layers: layers,
            firstSkin: firstSkin,
            secondSkin: secondSkin,
            jointTreatment: jointTreatment,
            compoundChoice: compoundChoice
        )
    }

    private func allocationsAreValid(_ allocations: [FacingAllocation]) -> Bool {
        !allocations.isEmpty && abs(allocations.reduce(0) { $0 + $1.area } - area) < 0.01 && allocations.allSatisfy { !$0.facingID.isEmpty && !$0.dimensionID.isEmpty && $0.area > 0 }
    }

    private func dimensions(for facingID: String) -> [FacingDimension] {
        facings.first(where: { $0.id == facingID })?.data["dimensions"]?.array?.compactMap { value in
            guard let object = value.object,
                  let width = object["width_mm"]?.number,
                  let length = object["length_mm"]?.number else { return nil }
            return FacingDimension(width: width, length: length)
        } ?? []
    }

    private func suppliesForSkin(_ allocations: [FacingAllocation], name skinName: String) -> [Supply] {
        allocations.compactMap { allocation in
            guard let facing = facings.first(where: { $0.id == allocation.facingID }),
                  let dimension = dimensions(for: allocation.facingID).first(where: { $0.id == allocation.dimensionID }),
                  dimension.area > 0 else { return nil }
            let boardCount = ceil(allocation.area * 1.05 / dimension.area)
            return Supply(
                id: "\(skinName)-\(allocation.id)",
                name: "\(skinName) · \(facing.title) · \(dimension.label) · \(format(allocation.area)) m² posés",
                quantity: boardCount,
                unit: "plaque(s)"
            )
        }
    }

    private func components(for system: ReferenceRecord?) -> [FixingComponent] {
        system?.data["components"]?.array?.compactMap { value in
            guard let object = value.object,
                  let name = object["name"]?.string,
                  let quantity = object["quantity"]?.number,
                  let unit = object["unit"]?.string,
                  let calculation = object["calculation"]?.string else { return nil }
            return FixingComponent(name: name, quantity: quantity, unit: unit, calculation: calculation)
        } ?? []
    }

    private func vaporBarrierComponents(for record: ReferenceRecord) -> [VaporBarrierComponent] {
        record.data["components"]?.array?.compactMap { value in
            guard let object = value.object,
                  let name = object["name"]?.string,
                  let quantity = object["quantity"]?.number,
                  let unit = object["unit"]?.string,
                  let calculation = object["calculation"]?.string else { return nil }
            return VaporBarrierComponent(
                name: name,
                quantity: quantity,
                unit: unit,
                calculation: calculation,
                excludeWhenSystemHandlesVaporBarrier: object["exclude_when_system_handles_vapor_barrier"]?.bool == true
            )
        } ?? []
    }

    private func componentDescription(_ component: FixingComponent) -> String {
        component.calculation == "plenum_m" ? "selon le plénum · ml" : "\(format(component.quantity)) \(component.unit) par système"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func formattedQuantity(_ value: Double, unit: String) -> String {
        unit == "unité" ? String(Int(ceil(value))) : format(value)
    }
}

private struct MeasureField: View {
    let label: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
