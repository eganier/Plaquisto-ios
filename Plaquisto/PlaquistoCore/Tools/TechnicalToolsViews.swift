import SwiftUI

private enum TechnicalSearchMode: String, CaseIterable, Identifiable {
    case verify = "Vérifier"
    case find = "Trouver"
    var id: String { rawValue }
}

struct CeilingSpanToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var mode = TechnicalSearchMode.verify
    @State private var requestedSpan = 0.0
    @State private var loadBand = 0
    @State private var selectedID = ""

    private var options: [CeilingSpanOption] { store.ceilingSpans }
    private var selected: CeilingSpanOption? { options.first { $0.id == selectedID } ?? options.first }
    private func span(_ option: CeilingSpanOption) -> Double { option.spans.indices.contains(loadBand) ? option.spans[loadBand] : 0 }
    private var compatible: [CeilingSpanOption] { options.filter { span($0) >= requestedSpan }.sorted { span($0) - requestedSpan < span($1) - requestedSpan } }

    var body: some View {
        TechnicalToolForm(title: "Plafond autoportant", store: store) {
            Section { Picker("Mode", selection: $mode) { ForEach(TechnicalSearchMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
            Section("Portée") { ToolNumberField(title: "Portée à franchir", unit: "m", value: $requestedSpan) }
            Section("Charge d’isolant") {
                Picker("Bande", selection: $loadBand) {
                    Text("< 6 kg/m²").tag(0); Text("6 à < 10 kg/m²").tag(1); Text("10 à 15 kg/m²").tag(2)
                }
            }
            if mode == .verify {
                Section("Configuration") {
                    Picker("Montage", selection: $selectedID) { ForEach(options) { Text($0.title).tag($0.id) } }
                }
                if let selected { compatibility(maximum: span(selected), requested: requestedSpan) }
            } else {
                Section("Configurations compatibles") {
                    if requestedSpan <= 0 { Text("Renseignez la portée à franchir.").foregroundStyle(.secondary) }
                    else if compatible.isEmpty { Text("Aucune configuration publiée ne couvre cette portée.").foregroundStyle(.orange) }
                    else { ForEach(compatible) { option in resultRow(option.title, maximum: span(option), requested: requestedSpan) } }
                }
            }
        }
        .onAppear { selectFirstOptionIfNeeded() }
        .onChange(of: options) { _, value in if selectedID.isEmpty { selectedID = value.first?.id ?? "" } }
    }

    private func selectFirstOptionIfNeeded() {
        if selectedID.isEmpty { selectedID = options.first?.id ?? "" }
    }
}

struct PartitionHeightToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var mode = TechnicalSearchMode.verify
    @State private var height = 0.0
    @State private var spacing = 0.60
    @State private var doubled = false
    @State private var selectedID = ""

    private var key: String { "\(doubled ? "double" : "simple")_\(spacing < 0.5 ? "040" : "060")" }
    private var options: [PartitionHeightOption] { store.partitionHeights }
    private var selected: PartitionHeightOption? { options.first { $0.id == selectedID } ?? options.first }
    private func maximum(_ option: PartitionHeightOption) -> Double { option.heights[key] ?? 0 }
    private var compatible: [PartitionHeightOption] { options.filter { maximum($0) >= height }.sorted { maximum($0) - height < maximum($1) - height } }

    var body: some View {
        TechnicalToolForm(title: "Hauteur de cloison", store: store) {
            Section { Picker("Mode", selection: $mode) { ForEach(TechnicalSearchMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
            Section("Besoin") {
                ToolNumberField(title: "Hauteur sous plafond", unit: "m", value: $height)
                Picker("Entraxe", selection: $spacing) { Text("40 cm").tag(0.40); Text("60 cm").tag(0.60) }.pickerStyle(.segmented)
                Toggle("Montants doublés", isOn: $doubled)
            }
            if mode == .verify {
                Section("Configuration") { Picker("Système", selection: $selectedID) { ForEach(options) { Text($0.title).tag($0.id) } } }
                if let selected { compatibility(maximum: maximum(selected), requested: height) }
            } else {
                Section("Configurations compatibles") {
                    if height <= 0 { Text("Renseignez la hauteur sous plafond.").foregroundStyle(.secondary) }
                    else if compatible.isEmpty { Text("Aucune configuration publiée n’est compatible.").foregroundStyle(.orange) }
                    else { ForEach(compatible.prefix(20)) { option in resultRow(option.title, maximum: maximum(option), requested: height) } }
                }
            }
        }
        .onAppear { selectFirstOptionIfNeeded() }
        .onChange(of: options) { _, value in if selectedID.isEmpty { selectedID = value.first?.id ?? "" } }
    }

    private func selectFirstOptionIfNeeded() {
        if selectedID.isEmpty { selectedID = options.first?.id ?? "" }
    }
}

struct LiningHeightToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var mode = TechnicalSearchMode.verify
    @State private var system = 0
    @State private var height = 0.0
    @State private var selectedLiningID = ""
    @State private var selectedFurringID = ""

    private var selectedLining: LiningHeightOption? { store.liningHeights.first { $0.id == selectedLiningID } ?? store.liningHeights.first }
    private var selectedFurring: FurringSupportOption? { store.furringSupports.first { $0.id == selectedFurringID } ?? store.furringSupports.first }

    var body: some View {
        TechnicalToolForm(title: "Hauteur de doublage", store: store) {
            Section { Picker("Mode", selection: $mode) { ForEach(TechnicalSearchMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
            Section("Système") {
                Picker("Ossature", selection: $system) { Text("Lisses / fourrures").tag(0); Text("Rails / montants").tag(1) }.pickerStyle(.segmented)
                ToolNumberField(title: "Hauteur sous plafond", unit: "m", value: $height)
            }
            if system == 0 { furringContent } else { liningContent }
        }
        .onAppear { selectFirstOptionsIfNeeded() }
        .onChange(of: store.liningHeights) { _, value in if selectedLiningID.isEmpty { selectedLiningID = value.first?.id ?? "" } }
        .onChange(of: store.furringSupports) { _, value in if selectedFurringID.isEmpty { selectedFurringID = value.first?.id ?? "" } }
    }

    private func selectFirstOptionsIfNeeded() {
        if selectedLiningID.isEmpty { selectedLiningID = store.liningHeights.first?.id ?? "" }
        if selectedFurringID.isEmpty { selectedFurringID = store.furringSupports.first?.id ?? "" }
    }

    @ViewBuilder private var furringContent: some View {
        if mode == .verify {
            Section("Parement") { Picker("Montage", selection: $selectedFurringID) { ForEach(store.furringSupports) { Text($0.title).tag($0.id) } } }
            if let rule = selectedFurring {
                compatibility(maximum: rule.maximumHeight, requested: height)
                Section("Lignes d’appuis") {
                    let count = height > 0 ? max(1, Int(ceil(height / rule.maximumSupportSpacing)) - 1) : 0
                    LabeledContent("Nombre recommandé", value: "\(count)")
                    LabeledContent("Écart maximal", value: meters(rule.maximumSupportSpacing))
                    if count > 0 { Text("Première ligne à 0,60 m du sol, puis répartition régulière dans la limite publiée.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        } else {
            Section("Configurations compatibles") {
                let values = store.furringSupports.filter { $0.maximumHeight >= height }.sorted { $0.maximumHeight < $1.maximumHeight }
                if height <= 0 { Text("Renseignez la hauteur sous plafond.").foregroundStyle(.secondary) }
                else if values.isEmpty { Text("Aucun montage sur fourrures publié n’est compatible.").foregroundStyle(.orange) }
                else { ForEach(values) { rule in resultRow(rule.title, maximum: rule.maximumHeight, requested: height) } }
            }
        }
    }

    @ViewBuilder private var liningContent: some View {
        if mode == .verify {
            Section("Configuration") { Picker("Montage", selection: $selectedLiningID) { ForEach(store.liningHeights) { Text("\($0.label) · \($0.title)").tag($0.id) } } }
            if let selectedLining { compatibility(maximum: selectedLining.maximumHeight, requested: height) }
        } else {
            Section("Configurations compatibles") {
                let values = store.liningHeights.filter { $0.maximumHeight >= height }.sorted { $0.maximumHeight < $1.maximumHeight }
                if height <= 0 { Text("Renseignez la hauteur sous plafond.").foregroundStyle(.secondary) }
                else if values.isEmpty { Text("Aucun montage rails / montants publié n’est compatible.").foregroundStyle(.orange) }
                else { ForEach(values.prefix(20)) { option in resultRow("\(option.label) · \(option.title)", maximum: option.maximumHeight, requested: height) } }
            }
        }
    }
}

struct FurringSpacingToolView: View {
    @EnvironmentObject private var store: ToolTechnicalStore
    @State private var selectedID = ""

    private var selected: InsulationMassOption? { store.insulationMasses.first { $0.id == selectedID } ?? store.insulationMasses.first }
    private var band: InsulationSpacingBand? { selected.flatMap { item in store.insulationSpacingBands.first { $0.contains(item.surfaceMass) } } }

    var body: some View {
        TechnicalToolForm(title: "Entraxe selon l’isolant", store: store) {
            Section("Isolant") {
                Picker("Type, lambda et épaisseur", selection: $selectedID) {
                    ForEach(store.insulationMasses) { item in
                        Text("\(item.title) · \(item.thicknessMM) mm").tag(item.id)
                    }
                }
            }
            if let selected {
                Section("Données Plaquisto Admin") {
                    LabeledContent("Lambda", value: selected.lambda > 0 ? selected.lambda.formatted(.number.precision(.fractionLength(3))) + " W/(m·K)" : "Non renseigné")
                    LabeledContent("Épaisseur", value: "\(selected.thicknessMM) mm")
                    LabeledContent("Masse surfacique maximale", value: selected.surfaceMass.formatted(.number.precision(.fractionLength(0...2))) + " kg/m²")
                }
                Section("Résultat") {
                    if let band {
                        LabeledContent("Entraxe maximal admissible", value: "\(Int(band.spacing * 100)) cm").font(.headline)
                        Text("La valeur maximale publiée pour la plage de poids est retenue.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Label("Aucun entraxe admissible n’est défini pour cette masse dans le référentiel actuel.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
        .onAppear { selectFirstOptionIfNeeded() }
        .onChange(of: store.insulationMasses) { _, value in if selectedID.isEmpty { selectedID = value.first?.id ?? "" } }
    }

    private func selectFirstOptionIfNeeded() {
        if selectedID.isEmpty { selectedID = store.insulationMasses.first?.id ?? "" }
    }
}

private struct TechnicalToolForm<Content: View>: View {
    let title: String
    @ObservedObject var store: ToolTechnicalStore
    let content: Content

    init(title: String, store: ToolTechnicalStore, @ViewBuilder content: () -> Content) {
        self.title = title
        self.store = store
        self.content = content()
    }

    var body: some View {
        Form {
            if store.isLoading { Section { HStack { ProgressView(); Text("Chargement du référentiel…") } } }
            if let error = store.error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
            if store.isOffline { Section { Label("Référentiel local hors connexion", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary) } }
            content
        }
        .navigationTitle(title)
    }
}

@ViewBuilder private func compatibility(maximum: Double, requested: Double) -> some View {
    Section("Résultat") {
        if requested <= 0 { Text("Renseignez la dimension à vérifier.").foregroundStyle(.secondary) }
        else if maximum <= 0 { Label("Aucune valeur publiée pour cette configuration.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        else {
            Label(maximum >= requested ? "Configuration compatible" : "Configuration incompatible", systemImage: maximum >= requested ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(maximum >= requested ? .green : .red).font(.headline)
            LabeledContent("Valeur maximale", value: meters(maximum))
            LabeledContent("Marge", value: signedMeters(maximum - requested))
        }
    }
}

@ViewBuilder private func resultRow(_ title: String, maximum: Double, requested: Double) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.subheadline.bold())
        Text("Maximum \(meters(maximum)) · marge \(signedMeters(maximum - requested))").font(.caption).foregroundStyle(.secondary)
    }
}

private func meters(_ value: Double) -> String { value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(2))) + " m" }
private func signedMeters(_ value: Double) -> String { (value >= 0 ? "+" : "") + meters(value) }
