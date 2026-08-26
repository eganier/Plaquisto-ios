import SwiftUI

struct DoublageConfiguratorView: View {
    enum GeometryMode: String, CaseIterable, Identifiable { case surface = "Surface totale", length = "Longueur"; var id: Self { self } }
    enum StudMounting: String, CaseIterable, Identifiable { case simple = "Montants simples", double = "Montants doubles"; var id: Self { self } }
    enum Compound: String, CaseIterable, Identifiable { case powder = "Enduit en poudre", paste = "Enduit en pâte"; var id: Self { self } }

    @EnvironmentObject private var references: LabReferenceStore
    @State private var mode = GeometryMode.surface
    @State private var surface = 10.0
    @State private var length = 4.0
    @State private var height = 2.5
    @State private var groupID = ""
    @State private var composition = ""
    @State private var plateHeight = 2.5
    @State private var frame = "R48 + M48"
    @State private var mounting = StudMounting.simple
    @State private var spacing = 0.6
    @State private var intermediateSupports = false
    @State private var jointTreatment = true
    @State private var compound = Compound.powder

    private var groups: [LabPerformanceGroup] { references.groups }
    private var group: LabPerformanceGroup? { groups.first(where: { $0.id == groupID }) ?? groups.first }
    private var actualArea: Double { mode == .surface ? surface : length * height }
    private var actualLength: Double { mode == .length ? length : (height > 0 ? surface / height : 0) }
    private var frames: [String] { Array(Set(group?.values.map(\.frame) ?? [])).sorted { frameNumber($0) < frameNumber($1) } }
    private var spacings: [Double] { Array(Set(group?.values.map(\.spacing) ?? [])).sorted() }
    private var maxHeight: Double {
        guard let row = group?.values.first(where: { $0.frame == frame && abs($0.spacing - spacing) < 0.001 }) else { return 0 }
        return mounting == .simple ? row.simple : row.double
    }
    private var isExceeded: Bool { maxHeight > 0 && height > maxHeight }
    private var isUnavailable: Bool { maxHeight == 0 }
    private var layers: Int {
        let text = composition.isEmpty ? (group?.label ?? "") : composition
        if text.contains("+") { return 2 }
        if text.hasPrefix("3 ×") || text.hasPrefix("3 ") { return 3 }
        if text.hasPrefix("2 ×") || text.hasPrefix("2 ") { return 2 }
        return 1
    }

    var body: some View {
        NavigationStack {
            Group {
                if references.isLoading { ProgressView("Chargement depuis Plaquisto Admin…") }
                else if let error = references.error { ContentUnavailableView("Données indisponibles", systemImage: "exclamationmark.icloud", description: Text(error)) }
                else { configurator }
            }
            .navigationTitle("Plaquisto Lab")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await references.load() } } label: { Image(systemName: "arrow.clockwise") } } }
        }
        .onChange(of: groups.count, initial: true) { _, _ in initializeSelections() }
        .onChange(of: groupID) { _, _ in initializeGroupSelections() }
    }

    private var configurator: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Doublage périphérique").font(.title2.bold())
                    Text("Rails et montants").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                if references.isUsingOfflineData { Label("Données enregistrées hors connexion", systemImage: "icloud.slash").foregroundStyle(.orange) }
            }

            Section("1 · Dimensions de l’ouvrage") {
                Picker("Mode de saisie", selection: $mode) { ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if mode == .surface { DecimalField("Surface totale", value: $surface, unit: "m²") }
                else { DecimalField("Longueur du doublage", value: $length, unit: "m") }
                DecimalField("Hauteur sous plafond", value: $height, unit: "m")
                LabeledContent("Surface calculée", value: actualArea.formatted(.number.precision(.fractionLength(2))) + " m²")
                LabeledContent("Longueur calculée", value: actualLength.formatted(.number.precision(.fractionLength(2))) + " m")
            }

            Section("2 · Parement") {
                Picker("Configuration", selection: $groupID) { ForEach(groups) { Text($0.label).tag($0.id) } }
                if let group, group.alternatives.count > 1 {
                    Picker("Nature du parement", selection: $composition) { ForEach(group.alternatives, id: \.self) { Text($0).tag($0) } }
                } else if let group { LabeledContent("Nature", value: group.label) }
                DecimalField("Hauteur des plaques", value: $plateHeight, unit: "m")
                if let group { LabeledContent("Largeur des plaques", value: Int(group.width).formatted() + " mm") }
            }

            Section("3 · Ossature métallique") {
                LabeledContent("Technique", value: "Rails et montants")
                Picker("Rails et montants", selection: $frame) { ForEach(frames, id: \.self) { Text($0).tag($0) } }
                Picker("Montage", selection: $mounting) { ForEach(StudMounting.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Entraxe des montants", selection: $spacing) { ForEach(spacings, id: \.self) { Text(Int($0 * 100).formatted() + " cm").tag($0) } }
                LabeledContent("Hauteur maximale", value: maxHeight > 0 ? maxHeight.formatted(.number.precision(.fractionLength(2))) + " m" : "Configuration indisponible")
            }

            if isExceeded || isUnavailable {
                Section {
                    Label(isUnavailable ? "Cette combinaison n’est pas prévue par le tableau technique." : "La hauteur saisie dépasse la hauteur maximale admise pour cette configuration. Elle ne doit pas être retenue sans adaptation.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    if mounting == .simple { Button("Passer en montants doubles") { mounting = .double } }
                    Text("Vous pouvez également augmenter la largeur des rails et montants.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Ajouter des appuis intermédiaires pour montant sur mur support", isOn: $intermediateSupports)
                } header: { Text("Adaptation nécessaire") }
            }

            Section("4 · Traitement des joints") {
                Toggle("Prévoir le traitement des bandes à joint", isOn: $jointTreatment)
                if jointTreatment { Picker("Type d’enduit", selection: $compound) { ForEach(Compound.allCases) { Text($0.rawValue).tag($0) } } }
            }

            Section("Quantitatif indicatif") {
                ForEach(resultRows, id: \.0) { row in LabeledContent(row.0, value: row.1) }
                if spacing != 0.4 && spacing != 0.6 {
                    Label("La visserie pour les entraxes de 45 et 90 cm reste à compléter dans Plaquisto Admin. Elle n’est pas estimée ici.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
                if layers == 3 { Label("La visserie de la troisième peau reste à compléter dans Plaquisto Admin.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
                Text("Quantités indicatives avec marge issue du tableau fourni. À vérifier selon les conditions réelles du chantier.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var resultRows: [(String, String)] {
        guard actualArea > 0, actualLength > 0, height > 0, let group, let table = references.quantityTable else { return [] }
        let plateArea = (group.width / 1000) * max(plateHeight, 0.01)
        let facingArea = actualArea * 1.05 * Double(layers)
        let plateCount = Int(ceil((actualArea * 1.05 / plateArea))) * layers
        let rails = 2 * actualLength * 1.05
        let bays = ceil(actualLength / spacing)
        let studs = (mounting == .simple ? bays + 1 : 2 * bays) * height * 1.05
        var rows: [(String, String)] = [
            ("Parement · \(composition.isEmpty ? group.label : composition)", format(facingArea, "m²")),
            ("Plaques indicatives · H. \(format(plateHeight, "m"))", "\(plateCount) unités"),
            ("Rails", format(rails, "ml")),
            ("Montants", format(studs, "ml"))
        ]
        let mountingKey = mounting == .simple ? "simple" : "double"
        if spacing == 0.4 || spacing == 0.6 {
            let key = String(format: "%.2f_%@", spacing, mountingKey)
            if let coefficient = table.ttpc25[key] { rows.append(("Vis TTPC 25", format(actualArea * coefficient, "unités", rounded: true))) }
            if layers >= 2, let coefficient = table.ttpc35[key] { rows.append(("Vis TTPC 35", format(actualArea * coefficient, "unités", rounded: true))) }
            if let coefficient = table.trpf13[key] { rows.append(("Vis TRPF 13", format(actualArea * coefficient, "unités", rounded: true))) }
        }
        if intermediateSupports {
            rows.append(("Appuis intermédiaires pour montant sur mur support", "\(Int(ceil((rails / 2) / spacing))) unités"))
        }
        if jointTreatment {
            rows.append(("Bande à joint", format(actualArea * (table.coefficients["band_ml_m2"] ?? 1.73), "ml")))
            let key = compound == .powder ? "enduit_poudre_kg_m2" : "enduit_pate_kg_m2"
            rows.append((compound.rawValue, format(actualArea * (table.coefficients[key] ?? 0), "kg")))
        }
        return rows
    }

    private func initializeSelections() {
        guard groupID.isEmpty, let first = groups.first else { return }
        groupID = first.id
        initializeGroupSelections()
    }

    private func initializeGroupSelections() {
        guard let group else { return }
        composition = group.alternatives.first ?? group.label
        let availableFrames = Array(Set(group.values.map(\.frame))).sorted { frameNumber($0) < frameNumber($1) }
        if !availableFrames.contains(frame) { frame = availableFrames.first ?? frame }
        let availableSpacings = Array(Set(group.values.map(\.spacing))).sorted()
        if !availableSpacings.contains(where: { abs($0 - spacing) < 0.001 }) { spacing = availableSpacings.last ?? spacing }
    }

    private func frameNumber(_ value: String) -> Int { Int(value.dropFirst().prefix { $0.isNumber }) ?? 0 }
    private func format(_ value: Double, _ unit: String, rounded: Bool = false) -> String {
        let number = rounded ? Double(ceil(value)) : value
        return number.formatted(.number.precision(.fractionLength(rounded ? 0 : 2))) + " " + unit
    }
}

private struct DecimalField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, unit: String) { self.title = title; _value = value; self.unit = unit }
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
