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

struct ConfiguratorView: View {
    @StateObject private var store = ReferenceStore()
    @State private var step = 0
    @State private var length = 5.0
    @State private var width = 4.0
    @State private var support = ""
    @State private var plenum = 20.0
    @State private var vaporBarrier = false
    @State private var insulationID = ""
    @State private var insulationThickness = 0.0
    @State private var fixingSystemID = ""
    @State private var layers = 1

    private let stepNames = ["Dimensions", "Support", "Isolation", "Fixation", "Parement", "Résultat"]

    private var catalogue: CataloguePayload? { store.catalogue }
    private var workTitle: String { catalogue?.ouvrage?.title ?? "Plafond sur fourrures horizontal" }
    private var insulationSeries: [ReferenceRecord] { catalogue?.isolation ?? [] }
    private var fixingSystems: [ReferenceRecord] { catalogue?.systemesFixation ?? [] }
    private var quantityItems: [ReferenceRecord] { catalogue?.quantitatifs ?? [] }
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
    private var spacing: Double? {
        guard insulationWeight <= 15 else { return nil }
        if insulationWeight >= 10 { return 0.4 }
        if insulationWeight >= 6 { return 0.5 }
        return 0.6
    }
    private var compatibleSystems: [ReferenceRecord] {
        let plenumMM = plenum * 10
        return fixingSystems.filter { system in
            guard system.data["support"]?.string == support,
                  let minimum = system.data["plenum_min_mm"]?.number,
                  let maximum = system.data["plenum_max_mm"]?.number,
                  plenumMM >= minimum, plenumMM <= maximum else { return false }
            let dedicatedToVaporBarrier = system.data["pare_vapeur_compatible"]?.bool == true
            if support == "Plancher bois horizontal" {
                return vaporBarrier ? dedicatedToVaporBarrier : !dedicatedToVaporBarrier
            }
            return true
        }
    }
    private var selectedFixingSystem: ReferenceRecord? {
        compatibleSystems.first { $0.id == fixingSystemID }
    }
    private var selectedComponents: [FixingComponent] {
        components(for: selectedFixingSystem)
    }
    private var area: Double { length * width }
    private var quantityConfigurationKey: String? {
        guard let spacing else { return nil }
        let prefix = layers == 1 ? "simple" : "double"
        return "\(prefix)_0\(Int((spacing * 100).rounded()))"
    }
    private var fixingSystemCount: Double {
        guard let key = quantityConfigurationKey,
              let row = quantityItems.first(where: { $0.id == "QTY-FIXATION" }),
              let ratio = row.data["values"]?.object?[key]?.number else { return 0 }
        return ratio * area
    }
    private var supplies: [Supply] {
        guard let key = quantityConfigurationKey else { return [] }
        var result: [Supply] = []

        for item in quantityItems where item.id != "QTY-FIXATION" {
            guard let ratio = item.data["values"]?.object?[key]?.number,
                  ratio > 0,
                  let unit = item.data["unit"]?.string else { continue }
            result.append(Supply(id: item.id, name: item.title, quantity: ratio * area, unit: unit))
        }

        for (index, component) in selectedComponents.enumerated() {
            var quantity = fixingSystemCount * component.quantity
            if component.calculation == "plenum_m" { quantity *= plenum / 100 }
            result.append(Supply(
                id: "FIX-\(index)-\(component.name)",
                name: component.name,
                quantity: quantity,
                unit: component.unit
            ))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView("Synchronisation avec Plaquisto Admin…")
                } else if let error = store.error {
                    ContentUnavailableView(
                        "Référentiel indisponible",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
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
        }
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
                if step > 0 {
                    Button("Retour") { withAnimation { step -= 1 } }.buttonStyle(.bordered)
                }
                Spacer()
                if step < stepNames.count - 1 {
                    Button("Continuer") {
                        prepareDefaults()
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                } else {
                    Button("Nouvel ouvrage") { reset() }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            Section("Dimensions de la pièce") {
                MeasureField(label: "Longueur", value: $length, unit: "m")
                MeasureField(label: "Largeur", value: $width, unit: "m")
            }
            Section {
                LabeledContent("Surface", value: "\(format(area)) m²")
            } footer: {
                Text("La surface sert de base au calcul de toutes les fournitures.")
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
                    .onChange(of: vaporBarrier) { _, _ in fixingSystemID = "" }
            }
            Section {
                Text("Le support et la hauteur servent à trouver les systèmes de fixation compatibles.")
                    .foregroundStyle(.secondary)
            }

        case 2:
            Section("Isolation") {
                Picker("Type d’isolant", selection: $insulationID) {
                    Text("Sans isolant").tag("")
                    ForEach(insulationSeries) { Text($0.title).tag($0.id) }
                }
                .onChange(of: insulationID) { _, _ in
                    insulationThickness = insulationPoints.first?.thickness ?? 0
                    fixingSystemID = ""
                }
                if !insulationID.isEmpty {
                    Picker("Épaisseur", selection: $insulationThickness) {
                        ForEach(insulationPoints) { point in
                            Text("\(Int(point.thickness)) mm").tag(point.thickness)
                        }
                    }
                    LabeledContent("Poids maximal retenu", value: "\(format(insulationWeight)) kg/m²")
                }
            }
            Section {
                LabeledContent("Entraxe maximal des fourrures", value: spacing.map { "\(Int($0 * 100)) cm" } ?? "Non couvert")
            } footer: {
                Text("Pour une plage de poids, Plaquisto retient toujours la valeur la plus élevée.")
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
                    Text("Fournitures composant le système")
                } footer: {
                    Text(system.summary)
                }
            }

        case 4:
            Section("Parement") {
                Picker("Nombre de plaques", selection: $layers) {
                    Text("Simple peau").tag(1)
                    Text("Double peau").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section("Configuration retenue") {
                LabeledContent("Surface", value: "\(format(area)) m²")
                LabeledContent("Entraxe des fourrures", value: spacing.map { "\(Int($0 * 100)) cm" } ?? "Non couvert")
                LabeledContent("Système de fixation", value: selectedFixingSystem?.title ?? "—")
                LabeledContent("Nombre indicatif de systèmes", value: String(Int(ceil(fixingSystemCount))))
            }

        default:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Quantitatif calculé", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text("\(format(area)) m² · \(layers == 1 ? "simple" : "double") peau · entraxe \(Int((spacing ?? 0) * 100)) cm")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }
            Section("Système de fixation") {
                LabeledContent("Solution", value: selectedFixingSystem?.title ?? "—")
                LabeledContent("Nombre de systèmes", value: String(Int(ceil(fixingSystemCount))))
            }
            Section("Fournitures indicatives") {
                ForEach(supplies) { supply in
                    LabeledContent(supply.name, value: "\(formattedQuantity(supply.quantity, unit: supply.unit)) \(supply.unit)")
                }
            }
            Section {
                Label("Choisir l’enduit en poudre ou l’enduit en pâte : les deux quantités ne doivent pas être additionnées.", systemImage: "info.circle")
                Text("Les quantités sont indicatives et proviennent des tableaux publiés dans Plaquisto Admin.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: return length > 0 && width > 0
        case 1: return !support.isEmpty && plenum > 0
        case 2: return insulationID.isEmpty || selectedInsulationPoint != nil
        case 3: return selectedFixingSystem != nil
        case 4: return spacing != nil
        default: return true
        }
    }

    private func prepareDefaults() {
        if support.isEmpty { support = supports.first ?? "" }
        if fixingSystemID.isEmpty { fixingSystemID = compatibleSystems.first?.id ?? "" }
    }

    private func reset() {
        withAnimation {
            step = 0
            support = ""
            plenum = 20
            vaporBarrier = false
            insulationID = ""
            insulationThickness = 0
            fixingSystemID = ""
            layers = 1
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

    private func componentDescription(_ component: FixingComponent) -> String {
        if component.calculation == "plenum_m" { return "selon le plénum · ml" }
        return "\(format(component.quantity)) \(component.unit) par système"
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
