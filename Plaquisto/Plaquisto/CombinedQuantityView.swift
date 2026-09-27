import SwiftUI

struct ProjectWorkQuantitySelectionView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    @State private var selected: Set<UUID> = []
    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                let chosen = project.works.filter { selected.contains($0.id) }
                List {
                    if project.works.isEmpty {
                        ContentUnavailableView("Aucun ouvrage", systemImage: "sum", description: Text("Ajoutez un ouvrage au projet pour préparer son quantitatif."))
                    } else {
                        Section("Ouvrages à inclure") {
                            ForEach(project.works) { work in
                                Button {
                                    if selected.contains(work.id) { selected.remove(work.id) } else { selected.insert(work.id) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(work.name).foregroundStyle(.primary)
                                            if work.surveySourceNeedsReview {
                                                Label("Relevé modifié — à contrôler", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.caption).foregroundStyle(.orange)
                                            }
                                            Text([project.rooms.first { $0.id == work.roomID }?.name, work.level, work.zone].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(work.id) ? "checkmark.circle.fill" : "circle")
                                    }
                                }.accessibilityAddTraits(selected.contains(work.id) ? .isSelected : [])
                            }
                        }
                        Section {
                            Text("\(chosen.count) ouvrage(s) sélectionné(s)")
                                .font(.caption).foregroundStyle(.secondary)
                            NavigationLink {
                                CombinedQuantityView(works: chosen, title: chosen.count == project.works.count ? "Quantitatif du projet" : "Quantitatif sélectionné")
                            } label: { Label("Afficher le quantitatif", systemImage: "sum") }
                            .disabled(chosen.isEmpty)
                        } footer: { Text("Chaque ouvrage est compté une seule fois.") }
                    }
                }
            }
        }.navigationTitle("Voir les quantitatifs").navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkSelectionView: View {
    let works: [WorkItem]
    @State private var selectedIDs: Set<UUID>

    init(works: [WorkItem]) {
        self.works = works
        _selectedIDs = State(initialValue: Set(works.map(\.id)))
    }

    private var selectedWorks: [WorkItem] { works.filter { selectedIDs.contains($0.id) } }

    var body: some View {
        List {
            Section {
                ForEach(works) { work in
                    Button {
                        if selectedIDs.contains(work.id) { selectedIDs.remove(work.id) }
                        else { selectedIDs.insert(work.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(work.name).foregroundStyle(.primary)
                                Text(work.type.title).font(.caption).foregroundStyle(.secondary)
                                if work.surveySourceNeedsReview {
                                    Label("Relevé modifié — à contrôler", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Image(systemName: selectedIDs.contains(work.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(work.id) ? Color.accentColor : Color.secondary)
                        }
                    }
                }
            } header: {
                Text("Ouvrages à inclure")
            } footer: {
                Text("Les quantités identiques seront additionnées dans un seul récapitulatif.")
            }

            Section {
                NavigationLink {
                    CombinedQuantityView(works: selectedWorks, title: "Quantitatif sélectionné")
                } label: {
                    Label("Afficher le quantitatif de \(selectedWorks.count) ouvrage(s)", systemImage: "sum")
                }
                .disabled(selectedWorks.isEmpty)
            }
        }
        .navigationTitle("Sélection des ouvrages")
        .toolbar {
            Button(selectedIDs.count == works.count ? "Tout désélectionner" : "Tout sélectionner") {
                selectedIDs = selectedIDs.count == works.count ? [] : Set(works.map(\.id))
            }
        }
    }
}

struct CombinedQuantityView: View {
    @StateObject private var store = CeilingReferenceStore()
    @EnvironmentObject private var projectStore: ProjectStore
    let works: [WorkItem]
    let title: String

    private var currentWorks: [WorkItem] {
        works.map { work in projectStore.project(id: work.projectID)?.works.first { $0.id == work.id } ?? work }
    }

    private var summary: CombinedQuantitySummary? {
        store.catalogue.map { CombinedQuantityCalculator.calculate(works: currentWorks, catalogue: $0) }
    }

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView("Aucun ouvrage à quantifier", systemImage: "sum",
                    description: Text("Cette sélection ne contient aucun ouvrage. Le quantitatif est nul."))
            } else if store.isLoading {
                ProgressView("Calcul du quantitatif…")
            } else if let error = store.error {
                ContentUnavailableView("Référentiel indisponible", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if let summary {
                List {
                    let toReview = currentWorks.filter(\.surveySourceNeedsReview)
                    if !toReview.isEmpty {
                        Section("Quantités à contrôler") {
                            ForEach(toReview) { work in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(work.name).font(.headline)
                                    SurveySourceReviewNotice(work: work)
                                }
                            }
                        }
                    }
                    Section("Ouvrages inclus") {
                        ForEach(currentWorks) { work in
                            NavigationLink { SavedWorkView(work: work) } label: {
                            if work.type == .openings {
                                LabeledContent(work.name, value: "\(work.openingConfiguration?.openings.count ?? 0) ouverture(s)")
                            } else {
                                LabeledContent(work.name, value: format(work.area) + " m²")
                            }
                            }
                        }
                        LabeledContent("Surface totale", value: format(summary.totalArea) + " m²").fontWeight(.semibold)
                    }
                    Section("Fournitures totales indicatives") {
                        ForEach(supplyRows(summary.supplies)) { row in
                            LabeledContent(row.name, value: row.value)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !works.isEmpty && store.catalogue == nil { await store.load() } }
    }

    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func supplyRows(_ supplies: [CombinedSupply]) -> [SupplyListingRow] {
        SupplyListingConsolidator.rows(supplies.map {
            .init(name: $0.name, quantity: $0.quantity, unit: $0.unit)
        })
    }
}

struct CombinedSupply: Identifiable {
    let name: String
    let quantity: Double
    let unit: String
    var id: String { "\(name)|\(unit)" }
}

struct CombinedQuantitySummary {
    let totalArea: Double
    let supplies: [CombinedSupply]
}

enum CombinedQuantityCalculator {
    static func calculate(works: [WorkItem], catalogue: CeilingCataloguePayload) -> CombinedQuantitySummary {
        var totals: [String: CombinedSupply] = [:]
        var totalArea = 0.0

        func add(name: String, quantity: Double, unit: String) {
            guard quantity > 0 else { return }
            let name = SupplyListingConsolidator.canonicalName(name)
            let unit = SupplyListingConsolidator.canonicalUnit(unit)
            let key = "\(name)|\(unit)"
            let previous = totals[key]?.quantity ?? 0
            totals[key] = CombinedSupply(name: name, quantity: previous + quantity, unit: unit)
        }

        var includedWorkIDs = Set<UUID>()
        for work in works where includedWorkIDs.insert(work.id).inserted {
            if case .paintingBeta(let configuration) = work.payload {
                totalArea += configuration.area
                add(name: "Surface à peindre (bêta)", quantity: configuration.area, unit: "m²")
                continue
            }
            if work.type == .openings, let configuration = work.openingConfiguration {
                let results = configuration.openings.map {
                    OpeningQuantityCalculator.calculate($0, context: configuration.context)
                }
                for item in OpeningQuantityCalculator.totals(results) {
                    add(name: item.name, quantity: item.quantity, unit: item.unit.rawValue)
                }
                continue
            }
            if work.type == .ceilingOnRailsAndStuds, let ceiling = work.railStudCeilingConfiguration {
                totalArea += ceiling.effectiveArea
                for item in ceiling.quantities { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                continue
            }
            if work.type == .modularCeiling, let ceiling = work.modularCeilingConfiguration {
                let quantities = ModularCeilingCalculator.calculate(ceiling)
                totalArea += quantities.area
                add(name: "Dalles modulaires \(ceiling.tileFormat.title)", quantity: Double(quantities.orderedTiles), unit: "unité(s)")
                add(name: "Profilés porteurs T24 · 3,60 m", quantity: Double(quantities.mainRunnerBars), unit: "unité(s)")
                add(name: "Entretoises T24 · 1,20 m", quantity: Double(quantities.crossTees1200Ordered), unit: "unité(s)")
                add(name: "Entretoises T24 · 0,60 m", quantity: Double(quantities.crossTees600Ordered), unit: "unité(s)")
                add(name: "Cornières de rive · 3,00 m", quantity: Double(quantities.perimeterAngleBars), unit: "unité(s)")
                add(name: "Suspentes + fixations", quantity: Double(quantities.hangers), unit: "unité(s)")
                continue
            }
            if work.type == .peripheralLiningStuds, let doublage = work.doublageConfiguration {
                totalArea += doublage.area
                for item in doublage.quantities {
                    add(name: item.name, quantity: item.quantity, unit: item.unit)
                }
                continue
            }
            if work.type == .distributionPartition, let partition = work.cloisonDistributionConfiguration {
                totalArea += partition.area
                for item in partition.quantities {
                    add(name: item.name, quantity: item.quantity, unit: item.unit)
                }
                continue
            }
            if work.type == .alveolarPartition, let partition = work.alveolarPartitionConfiguration {
                totalArea += partition.area
                for item in partition.quantities {
                    add(name: item.name, quantity: item.quantity, unit: item.unit)
                }
                continue
            }
            if work.type == .peripheralLiningBonded, let lining = work.bondedLiningConfiguration {
                totalArea += lining.area
                for item in lining.quantities { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                continue
            }
            if work.type == .peripheralLiningFurrings, let lining = work.furringLiningConfiguration {
                totalArea += lining.area
                for item in lining.quantities { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                continue
            }
            if work.type == .peripheralLiningAdhesiveFacing, let lining = work.adhesiveFacingConfiguration {
                totalArea += lining.area
                for item in lining.quantities { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                continue
            }
            guard let configuration = work.ceilingConfiguration else { continue }
            let area = configuration.enteredArea ?? configuration.length * configuration.width
            totalArea += area
            let prefix = configuration.layers == 1 ? "simple" : "double"
            let key = "\(prefix)_0\(Int((configuration.selectedSpacing * 100).rounded()))"
            let fixingRatio = catalogue.quantitatifs.first(where: { $0.id == "QTY-FIXATION" })?.data["values"]?.object?[key]?.number ?? 0
            let fixingCount = fixingRatio * area

            for item in catalogue.quantitatifs where !["QTY-FIXATION", "QTY-PLAQUE"].contains(item.id) {
                if !configuration.jointTreatment && ["QTY-BANDE", "QTY-ENDUIT-POUDRE", "QTY-ENDUIT-PATE"].contains(item.id) { continue }
                if configuration.jointTreatment && configuration.compoundChoice == "poudre" && item.id == "QTY-ENDUIT-PATE" { continue }
                if configuration.jointTreatment && configuration.compoundChoice == "pate" && item.id == "QTY-ENDUIT-POUDRE" { continue }
                guard let ratio = item.data["values"]?.object?[key]?.number,
                      let unit = item.data["unit"]?.string else { continue }
                add(name: item.title, quantity: ratio * area, unit: unit)
            }

            if let system = catalogue.systemesFixation.first(where: { $0.id == configuration.fixingSystemID }) {
                for component in system.data["components"]?.array ?? [] {
                    guard let object = component.object,
                          let name = object["name"]?.string,
                          let ratio = object["quantity"]?.number,
                          let unit = object["unit"]?.string,
                          let calculation = object["calculation"]?.string else { continue }
                    var quantity = fixingCount * ratio
                    if calculation == "plenum_m" { quantity *= configuration.plenum / 100 }
                    add(name: name, quantity: quantity, unit: unit)
                }
            }

            if configuration.vaporBarrier {
                let systemHandlesVaporBarrier = catalogue.systemesFixation.first(where: { $0.id == configuration.fixingSystemID })?.data["pare_vapeur_compatible"]?.bool == true
                let fourrureRatio = catalogue.quantitatifs.first(where: { $0.id == "QTY-FOURRURE" })?.data["values"]?.object?[key]?.number ?? 0
                for record in catalogue.pareVapeur ?? [] {
                    for component in record.data["components"]?.array ?? [] {
                        guard let object = component.object,
                              let name = object["name"]?.string,
                              let ratio = object["quantity"]?.number,
                              let unit = object["unit"]?.string,
                              let calculation = object["calculation"]?.string else { continue }
                        if object["exclude_when_system_handles_vapor_barrier"]?.bool == true && systemHandlesVaporBarrier { continue }
                        let quantity = calculation == "fourrure_ml" ? ratio * fourrureRatio * area : ratio * area
                        add(name: name, quantity: quantity, unit: unit)
                    }
                }
            }

            let coveringRatio = LayoutWorkGeometry.coveringAreaRatio(work.layoutDocument)
            for item in LayoutWorkGeometry.ceilingInsulation(configuration, catalogue: catalogue, coveringRatio: coveringRatio) {
                add(name: item.name, quantity: item.quantity, unit: "m²")
            }
            addParements(configuration.firstSkin, catalogue: catalogue, coveringRatio: coveringRatio, add: add)
            if configuration.layers == 2 { addParements(configuration.secondSkin, catalogue: catalogue, coveringRatio: coveringRatio, add: add) }
        }

        return CombinedQuantitySummary(totalArea: totalArea, supplies: totals.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private static func addParements(_ selections: [FacingSelection], catalogue: CeilingCataloguePayload, coveringRatio: Double, add: (String, Double, String) -> Void) {
        for selection in selections {
            guard let facing = catalogue.parements.first(where: { $0.id == selection.facingID }),
                  let dimension = facing.data["dimensions"]?.array?.compactMap({ $0.object }).first(where: {
                      guard let width = $0["width_mm"]?.number, let length = $0["length_mm"]?.number else { return false }
                      return "\(Int(width))x\(Int(length))" == selection.dimensionID
                  }),
                  let width = dimension["width_mm"]?.number,
                  let length = dimension["length_mm"]?.number else { continue }
            let boardArea = width * length / 1_000_000
            guard boardArea > 0 else { continue }
            let quantity = ceil(selection.area * coveringRatio * 1.05 / boardArea)
            add("\(facing.title) · \(Int(width)) × \(Int(length)) mm", quantity, "plaque(s)")
        }
    }
}

extension WorkItem {
    var area: Double {
        switch type {
        case .ceilingOnFurring:
            guard let configuration = ceilingConfiguration else { return 0 }
            return configuration.enteredArea ?? configuration.length * configuration.width
        case .ceilingOnRailsAndStuds: return railStudCeilingConfiguration?.effectiveArea ?? 0
        case .modularCeiling: return modularCeilingConfiguration?.area ?? 0
        case .peripheralLiningStuds: return doublageConfiguration?.area ?? 0
        case .distributionPartition: return cloisonDistributionConfiguration?.area ?? 0
        case .alveolarPartition: return alveolarPartitionConfiguration?.area ?? 0
        case .peripheralLiningBonded: return bondedLiningConfiguration?.area ?? 0
        case .peripheralLiningFurrings: return furringLiningConfiguration?.area ?? 0
        case .peripheralLiningAdhesiveFacing: return adhesiveFacingConfiguration?.area ?? 0
        case .openings: return 0
        case .paintingBeta:
            guard case .paintingBeta(let configuration) = payload else { return 0 }
            return configuration.area
        }
    }
}

enum WorkTechnicalSummary {
    static func text(for work: WorkItem, catalogue: WorkSummaryCatalogue) -> String {
        var parts = [work.type.title]
        var facingIDs: [String] = []
        func number(_ value: Double, decimals: Int = 2) -> String {
            value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...decimals)))
        }
        func insulation(_ id: String, _ thickness: Double, lambda: Double? = nil) {
            guard !id.isEmpty else { return }
            let record = catalogue.records[id]
            let name = record?.data["material"]?.string ?? catalogue.name(id)
            var detail = name ?? ""
            if thickness.isFinite && thickness > 0 {
                detail += (detail.isEmpty ? "Isolant " : " ") + number(thickness) + " mm"
                if let lambda = lambda ?? ThermalCalculator.catalogueLambda(
                    conductivity: record?.data["conductivity"]?.string, lambda: record?.data["lambda_w_mk"]?.number),
                   let resistance = ThermalCalculator.resistance(thicknessMM: thickness, lambda: lambda) {
                    detail += " (R \(number(resistance)))"
                }
            }
            if !detail.isEmpty { parts.append(detail) }
        }
        switch work.payload {
        case .ceiling(let c):
            insulation(c.insulationID, c.insulationThickness)
            if c.insulationLayers == 2 { insulation(c.secondInsulationID ?? "", c.secondInsulationThickness ?? 0) }
            facingIDs = (c.firstSkin + (c.layers > 1 ? c.secondSkin : [])).map(\.facingID)
        case .railStudCeiling(let c):
            parts.append("R\(c.studWidth) + M\(c.studWidth)")
            if c.insulationEnabled {
                insulation(c.firstInsulation.seriesID, Double(c.firstInsulation.thickness))
                if c.insulationLayers == 2 { insulation(c.secondInsulation.seriesID, Double(c.secondInsulation.thickness)) }
            }
            facingIDs = (c.firstSkin + (c.facingLayers > 1 ? c.secondSkin : [])).map(\.productID)
        case .modularCeiling(let c): parts.append("Dalles \(c.tileFormat.title)")
        case .peripheralLining(let c):
            parts.append(c.frame)
            if c.insulationEnabled {
                insulation(c.firstInsulation.familyID, Double(c.firstInsulation.thicknessMM), lambda: c.firstInsulation.lambda)
                if c.insulationLayers == 2 { insulation(c.secondInsulation.familyID, Double(c.secondInsulation.thicknessMM), lambda: c.secondInsulation.lambda) }
            }
            facingIDs = (c.firstSkin + (c.layers > 1 ? c.secondSkin : [])).map(\.facingID)
        case .furringLining(let c):
            if c.insulationEnabled { insulation(c.firstInsulation.familyID, Double(c.firstInsulation.thicknessMM), lambda: c.firstInsulation.lambda) }
            facingIDs = (c.firstSkin + (c.layers > 1 ? c.secondSkin : []) + (c.layers > 2 ? c.thirdSkin : [])).map(\.facingID)
        case .distributionPartition(let c):
            parts.append(c.frame)
            if c.insulationEnabled { insulation(c.insulationID, Double(c.insulationThicknessMM)) }
            facingIDs = (c.faceAFirst + c.faceBFirst + (c.layers > 1 ? c.faceASecond + c.faceBSecond : [])).map(\.facingID)
        case .alveolarPartition(let c): facingIDs = c.panels.map(\.panelID)
        case .bondedLining(let c):
            // This product uses published complex R values, not an approximation e/lambda.
            if c.insulationThicknessMM > 0 {
                var detail = "Isolant \(c.insulationThicknessMM) mm"
                let complexes = catalogue.records.values.flatMap { $0.data["complexes"]?.array ?? [] }
                let resistance = complexes.compactMap(\.object).first {
                    $0["insulation_thickness_mm"]?.number == Double(c.insulationThicknessMM)
                    && abs(($0["lambda_w_mk"]?.number ?? 0) - c.lambda) < 0.0001
                }?["thermal_resistance_m2_kw"]?.number
                if let resistance, resistance.isFinite { detail += " (R \(number(resistance)))" }
                parts.append(detail)
            }
            parts += c.allocations.map { $0.facing.title }
        case .adhesiveFacing(let c): parts.append(c.facingFamily)
        case .openings: break
        case .paintingBeta: parts.append("Surface uniquement · consommables à venir")
        }
        var seen = Set<String>()
        parts += facingIDs.compactMap { catalogue.name($0) }.filter { seen.insert($0).inserted }
        if work.area.isFinite && work.area > 0 { parts.append("\(number(work.area)) m²") }
        return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " • ")
    }
}
