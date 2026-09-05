import SwiftUI

struct AlveolarPartitionConfiguratorView: View {
    typealias AlveolarPanelAllocation = AlveolarPanelSelection

    private enum GeometryMode: String, CaseIterable, Identifiable {
        case length = "Longueur"
        case surface = "Surface totale"
        var id: Self { self }
    }

    private enum Compound: String, CaseIterable, Identifiable {
        case powder = "Enduit en poudre"
        case paste = "Enduit en pâte"
        var id: Self { self }
    }

    @EnvironmentObject private var references: AlveolarPartitionReferenceStore
    private let onSave: ((AlveolarPartitionConfiguration) -> Void)?
    private let onClose: (() -> Void)?
    private let showsCloseButton: Bool
    @State private var step: Int
    @State private var geometryMode = GeometryMode.length
    @State private var height = 0.0
    @State private var enteredLength = 0.0
    @State private var enteredSurface = 0.0
    @State private var allocations = [AlveolarPanelAllocation()]
    @State private var jointTreatment = true
    @State private var compound = Compound.powder

    private let green = Color(red: 0.12, green: 0.38, blue: 0.29)
    private let stepNames = ["Dimensions", "Panneaux", "Bandes à joint", "Résultat"]

    init(
        initialConfiguration: AlveolarPartitionConfiguration? = nil,
        startsAtResult: Bool = false,
        onSave: ((AlveolarPartitionConfiguration) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        showsCloseButton: Bool = true
    ) {
        let configuration = initialConfiguration ?? AlveolarPartitionConfiguration()
        self.onSave = onSave
        self.onClose = onClose
        self.showsCloseButton = showsCloseButton
        _step = State(initialValue: startsAtResult ? 4 : 1)
        _geometryMode = State(initialValue: configuration.geometryMode == "surface" ? .surface : .length)
        _height = State(initialValue: configuration.height)
        _enteredLength = State(initialValue: configuration.enteredLength)
        _enteredSurface = State(initialValue: configuration.enteredSurface)
        _allocations = State(initialValue: configuration.panels.isEmpty ? [AlveolarPanelAllocation()] : configuration.panels)
        _jointTreatment = State(initialValue: configuration.jointTreatment)
        _compound = State(initialValue: configuration.compoundChoice == "pate" ? .paste : .powder)
    }

    private var actualLength: Double {
        geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0)
    }

    private var actualArea: Double {
        geometryMode == .surface ? enteredSurface : enteredLength * height
    }

    private var allocatedArea: Double {
        allocations.reduce(0) { $0 + $1.surface }
    }

    private var remainingArea: Double {
        max(0, actualArea - allocatedArea)
    }

    private var canContinue: Bool {
        switch step {
        case 1:
            height > 0 && height <= references.maximumHeight &&
            (geometryMode == .length ? enteredLength > 0 : enteredSurface > 0)
        case 2:
            !allocations.isEmpty &&
            allocations.allSatisfy { allocation in
                allocation.surface > 0 && panel(for: allocation) != nil && selectedFormat(for: allocation) != nil
            } && abs(allocatedArea - actualArea) < 0.01
        default:
            true
        }
    }

    var body: some View {
        Group {
            if references.isLoading {
                ProgressView("Chargement depuis Plaquisto Admin…")
            } else if let error = references.error {
                VStack(spacing: 18) {
                    ContentUnavailableView(
                        "Données indisponibles",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                    Button("Réessayer") { Task { await references.load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                wizard
            }
        }
        .tint(green)
        .onChange(of: references.panels.count, initial: true) { _, _ in initializeAllocations() }
        .onChange(of: height) { _, _ in normalizeFormats() }
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 1: dimensionsStep
                    case 2: panelsStep
                    case 3: jointsStep
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
            Text("OUVRAGE")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("Cloison de distribution alvéolaire")
                .font(.title2.bold())
            Label("Données synchronisées avec Plaquisto Admin", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(.green)
            ProgressView(value: Double(step), total: 4)
            Text("Étape \(step) sur 4 · \(stepNames[step - 1])")
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
                    .buttonStyle(.borderedProminent)
                    .tint(green.opacity(0.18))
                    .foregroundStyle(green)
            }
            Spacer()
            if step < 4 {
                Button("Continuer") { continueForm() }
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
        .padding(20)
        .background(.background)
    }

    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Dimensions de l’ouvrage")
            formCard {
                numericRow("Hauteur sous plafond", value: $height, unit: "m")
                Divider()
                Picker("Mode de saisie", selection: $geometryMode) {
                    ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Divider()
                if geometryMode == .length {
                    numericRow("Longueur de la cloison", value: $enteredLength, unit: "m")
                } else {
                    numericRow("Surface totale", value: $enteredSurface, unit: "m²")
                }
            }

            formCard {
                HStack {
                    Text(geometryMode == .length ? "Surface calculée" : "Longueur calculée")
                    Spacer()
                    Text(geometryMode == .length ? format(actualArea, "m²") : format(actualLength, "m"))
                        .foregroundStyle(.secondary)
                }
            }

            if height > references.maximumHeight {
                warningCard(
                    "La hauteur renseignée de \(format(height, "m")) dépasse la hauteur maximale autorisée de \(format(references.maximumHeight, "m")) pour une cloison alvéolaire."
                )
            } else {
                Text("La hauteur maximale autorisée pour cet ouvrage est de \(format(references.maximumHeight, "m")).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var panelsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Panneaux")
            Text("Répartissez la surface entre les panneaux standards et hydrofuges nécessaires à l’ouvrage.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach($allocations) { $allocation in
                panelCard($allocation)
            }

            if canAddPanel {
                Button("Ajouter un autre type de panneau") { addPanel() }
                    .foregroundStyle(.green)
            }

            Text(allocationStatus)
                .font(.footnote)
                .foregroundStyle(abs(allocatedArea - actualArea) < 0.01 ? .green : .orange)
        }
    }

    private var jointsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Bandes à joint")
            formCard {
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
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Synthèse de l’ouvrage")
            formCard {
                summaryRow("Hauteur", format(height, "m"))
                Divider()
                summaryRow("Longueur", format(actualLength, "m"))
                Divider()
                summaryRow("Surface", format(actualArea, "m²"))
                Divider()
                summaryRow("Traitement des joints", jointTreatment ? compound.rawValue : "Non prévu")
            }

            sectionTitle("Quantitatif indicatif")
            formCard {
                ForEach(Array(resultRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    summaryRow(row.0, row.1)
                }
            }
        }
    }

    private func panelCard(_ allocation: Binding<AlveolarPanelAllocation>) -> some View {
        formCard {
            HStack {
                Text("Type de panneau")
                Spacer()
                Picker("Type de panneau", selection: panelBinding(allocation)) {
                    ForEach(references.panels) { panel in
                        Text(panel.functionTitle).tag(panel.id)
                    }
                }
                .labelsHidden()
            }
            Divider()
            HStack {
                Text("Dimension")
                Spacer()
                Picker("Dimension", selection: formatBinding(allocation)) {
                    ForEach(compatibleFormats(for: allocation.wrappedValue)) { panelFormat in
                        Text(panelFormat.title).tag(panelFormat.id)
                    }
                }
                .labelsHidden()
            }
            Divider()
            numericRow("Surface attribuée", value: allocation.surface, unit: "m²")
            if allocations.count > 1 {
                Divider()
                Button("Supprimer ce panneau", role: .destructive) {
                    allocations.removeAll { $0.id == allocation.wrappedValue.id }
                }
            }
        }
    }

    private var resultRows: [(String, String)] {
        guard actualArea > 0 else { return [] }
        var rows: [(String, String)] = []

        for allocation in allocations {
            guard let panel = panel(for: allocation), let panelFormat = selectedFormat(for: allocation),
                  let coefficient = references.quantities.byWidth[panelFormat.widthMM] else { continue }
            rows.append((
                "Panneau · \(panel.functionTitle) · \(panelFormat.title)",
                format(allocation.surface * coefficient.panel, "m²")
            ))
        }

        let totals = weightedTotals
        rows.append((componentName("rail", fallback: "Rail pour cloison alvéolaire"), format(totals.rail, "ml")))
        rows.append((componentName("semelle", fallback: "Semelle pour cloison alvéolaire"), format(totals.semelle, "ml")))
        rows.append((componentName("clavette", fallback: "Clavettes"), format(totals.clavette, "unités", rounded: true)))
        rows.append((componentName("ttpc35", fallback: "Vis TTPC 35"), format(totals.ttpc35, "unités", rounded: true)))
        rows.append((componentName("ttpc70", fallback: "Vis TTPC 70"), format(totals.ttpc70, "unités", rounded: true)))
        if jointTreatment {
            rows.append((componentName("band", fallback: "Bande PP grand rouleau"), format(totals.band, "ml")))
            if compound == .powder {
                rows.append((componentName("powder", fallback: compound.rawValue), format(totals.powder, "kg")))
            } else {
                rows.append((componentName("paste", fallback: compound.rawValue), format(totals.paste, "kg")))
            }
        }
        return rows
    }

    private var weightedTotals: (rail: Double, semelle: Double, clavette: Double, ttpc35: Double, ttpc70: Double, band: Double, powder: Double, paste: Double) {
        allocations.reduce(into: (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)) { result, allocation in
            guard let panelFormat = selectedFormat(for: allocation),
                  let coefficient = references.quantities.byWidth[panelFormat.widthMM] else { return }
            result.0 += allocation.surface * coefficient.rail
            result.1 += allocation.surface * coefficient.semelle
            result.2 += allocation.surface * coefficient.clavette
            result.3 += allocation.surface * coefficient.ttpc35
            result.4 += allocation.surface * coefficient.ttpc70
            result.5 += allocation.surface * coefficient.band
            result.6 += allocation.surface * coefficient.powder
            result.7 += allocation.surface * coefficient.paste
        }
    }

    private var canAddPanel: Bool {
        allocations.count < references.panels.count
    }

    private var allocationStatus: String {
        let difference = actualArea - allocatedArea
        if abs(difference) < 0.01 { return "Répartition complète : \(format(actualArea, "m²"))." }
        if difference > 0 { return "Il reste \(format(difference, "m²")) à répartir." }
        return "La surface attribuée dépasse de \(format(abs(difference), "m²"))."
    }

    private func panel(for allocation: AlveolarPanelAllocation) -> AlveolarPanel? {
        references.panels.first { $0.id == allocation.panelID }
    }

    private func selectedFormat(for allocation: AlveolarPanelAllocation) -> AlveolarPanelFormat? {
        panel(for: allocation)?.formats.first { $0.id == allocation.formatID }
    }

    private func compatibleFormats(for allocation: AlveolarPanelAllocation) -> [AlveolarPanelFormat] {
        guard let panel = panel(for: allocation) else { return [] }
        let minimumHeightMM = Int(ceil(height * 1000))
        return panel.formats.filter { $0.heightMM >= minimumHeightMM }
    }

    private func preferredFormat(for panel: AlveolarPanel) -> AlveolarPanelFormat? {
        let minimumHeightMM = Int(ceil(height * 1000))
        return panel.formats.filter { $0.heightMM >= minimumHeightMM }
            .min { lhs, rhs in
                lhs.heightMM == rhs.heightMM ? lhs.widthMM > rhs.widthMM : lhs.heightMM < rhs.heightMM
            }
    }

    private func panelBinding(_ allocation: Binding<AlveolarPanelAllocation>) -> Binding<String> {
        Binding(
            get: { allocation.wrappedValue.panelID },
            set: { panelID in
                guard let panel = references.panels.first(where: { $0.id == panelID }) else { return }
                var next = allocation.wrappedValue
                next.panelID = panelID
                next.formatID = preferredFormat(for: panel)?.id ?? ""
                allocation.wrappedValue = next
            }
        )
    }

    private func formatBinding(_ allocation: Binding<AlveolarPanelAllocation>) -> Binding<String> {
        Binding(
            get: { allocation.wrappedValue.formatID },
            set: { allocation.wrappedValue.formatID = $0 }
        )
    }

    private func initializeAllocations() {
        guard let first = references.panels.first else { return }
        if allocations.first?.panelID.isEmpty != false {
            allocations = [AlveolarPanelAllocation(panelID: first.id, formatID: preferredFormat(for: first)?.id ?? "", surface: actualArea)]
        }
    }

    private func normalizeFormats() {
        for index in allocations.indices {
            guard let panel = panel(for: allocations[index]) else { continue }
            let compatible = compatibleFormats(for: allocations[index])
            if !compatible.contains(where: { $0.id == allocations[index].formatID }) {
                allocations[index].formatID = preferredFormat(for: panel)?.id ?? ""
            }
        }
    }

    private func addPanel() {
        let used = Set(allocations.map(\.panelID))
        guard let panel = references.panels.first(where: { !used.contains($0.id) }) else { return }
        allocations.append(AlveolarPanelAllocation(
            panelID: panel.id,
            formatID: preferredFormat(for: panel)?.id ?? "",
            surface: remainingArea > 0.009 ? remainingArea : 0
        ))
    }

    private func configurationSnapshot() -> AlveolarPartitionConfiguration {
        AlveolarPartitionConfiguration(
            geometryMode: geometryMode == .surface ? "surface" : "length",
            height: height,
            enteredLength: enteredLength,
            enteredSurface: enteredSurface,
            panels: allocations,
            jointTreatment: jointTreatment,
            compoundChoice: compound == .paste ? "pate" : "poudre",
            quantities: resultRows.compactMap { quantity(from: $0) }
        )
    }

    private func quantity(from row: (String, String)) -> AlveolarQuantity? {
        let scanner = Scanner(string: row.1.replacingOccurrences(of: ",", with: "."))
        guard let value = scanner.scanDouble() else { return nil }
        let unit = String(row.1[scanner.currentIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty else { return nil }
        return AlveolarQuantity(name: row.0, quantity: value, unit: unit)
    }

    private func continueForm() {
        if step == 1 {
            if allocations.count == 1 { allocations[0].surface = actualArea }
            normalizeFormats()
        }
        step += 1
    }

    private func reset() {
        step = 1
        geometryMode = .length
        height = 0
        enteredLength = 0
        enteredSurface = 0
        jointTreatment = true
        compound = .powder
        allocations = [AlveolarPanelAllocation()]
        initializeAllocations()
    }

    private func componentName(_ key: String, fallback: String) -> String {
        references.quantities.names[key] ?? fallback
    }

    private func format(_ value: Double, _ unit: String, rounded: Bool = false) -> String {
        let displayed = rounded ? ceil(value) : value
        let precision = rounded ? 0 : 2
        return "\(displayed.formatted(.number.precision(.fractionLength(0...precision)))) \(unit)"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.secondary)
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func numericRow(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func warningCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }
}
