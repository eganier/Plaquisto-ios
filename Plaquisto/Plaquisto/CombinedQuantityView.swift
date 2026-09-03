import SwiftUI

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
    let works: [WorkItem]
    let title: String

    private var summary: CombinedQuantitySummary? {
        store.catalogue.map { CombinedQuantityCalculator.calculate(works: works, catalogue: $0) }
    }

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("Calcul du quantitatif…")
            } else if let error = store.error {
                ContentUnavailableView("Référentiel indisponible", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if let summary {
                List {
                    Section("Ouvrages inclus") {
                        ForEach(works) { work in LabeledContent(work.name, value: format(work.area) + " m²") }
                        LabeledContent("Surface totale", value: format(summary.totalArea) + " m²").fontWeight(.semibold)
                    }
                    Section("Fournitures totales indicatives") {
                        ForEach(summary.supplies) { supply in
                            LabeledContent(supply.name, value: displayQuantity(supply.quantity, unit: supply.unit) + " " + supply.unit)
                        }
                    }
                    Section {
                        Text("Les quantités identiques ont été additionnées. Elles restent indicatives et proviennent des tableaux publiés dans Plaquisto Admin.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.catalogue == nil { await store.load() } }
    }

    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func displayQuantity(_ value: Double, unit: String) -> String {
        unit == "unité" || unit.contains("plaque") ? String(Int(ceil(value))) : format(value)
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
            let key = "\(name)|\(unit)"
            let previous = totals[key]?.quantity ?? 0
            totals[key] = CombinedSupply(name: name, quantity: previous + quantity, unit: unit)
        }

        for work in works {
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
            guard let configuration = work.ceilingConfiguration else { continue }
            let area = configuration.length * configuration.width
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

            addParements(configuration.firstSkin, catalogue: catalogue, add: add)
            if configuration.layers == 2 { addParements(configuration.secondSkin, catalogue: catalogue, add: add) }
        }

        return CombinedQuantitySummary(totalArea: totalArea, supplies: totals.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private static func addParements(_ selections: [FacingSelection], catalogue: CeilingCataloguePayload, add: (String, Double, String) -> Void) {
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
            let quantity = ceil(selection.area * 1.05 / boardArea)
            add("\(facing.title) · \(Int(width)) × \(Int(length)) mm", quantity, "plaque(s)")
        }
    }
}

private extension WorkItem {
    var area: Double {
        switch type {
        case .ceilingOnFurring:
            guard let configuration = ceilingConfiguration else { return 0 }
            return configuration.length * configuration.width
        case .peripheralLiningStuds: return doublageConfiguration?.area ?? 0
        case .distributionPartition: return cloisonDistributionConfiguration?.area ?? 0
        }
    }
}
