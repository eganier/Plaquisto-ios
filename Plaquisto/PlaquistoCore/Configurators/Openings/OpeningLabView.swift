import SwiftUI

struct OpeningLabView: View {
    private enum EditorPresentation: Identifiable {
        case create(OpeningKind)
        case edit(OpeningInput)
        case rename(OpeningInput, defaultName: String)

        var id: String {
            switch self {
            case .create(let kind): "create-\(kind.rawValue)"
            case .edit(let opening): "edit-\(opening.id.uuidString)"
            case .rename(let opening, _): "rename-\(opening.id.uuidString)"
            }
        }
    }

    @State private var context = OpeningContext()
    @State private var openings: [OpeningInput] = []
    @State private var editorPresentation: EditorPresentation?
    @State private var selectedHeightSourceID: UUID?
    private let heightOptions: [OpeningWorkSystem: [OpeningHeightSuggestion]]
    private let roomName: String?
    private let onSave: ((OpeningConfiguration) -> Void)?

    private let green = Color(red: 0.05, green: 0.42, blue: 0.31)

    private var results: [OpeningQuantityResult] {
        openings.map { OpeningQuantityCalculator.calculate($0, context: context) }
    }

    private var contextIsReady: Bool {
        switch context.system {
        case .furringLining, .railStudLining, .distributionPartition:
            context.hsp > 0
        case .furringCeiling:
            true
        case .railStudCeiling:
            (context.ceilingLengthInStudDirection ?? 0) > 0
        }
    }

    private var canSave: Bool {
        let roomIsReady = roomName == nil || !(roomName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return roomIsReady && !openings.isEmpty && contextIsReady && results.allSatisfy(\.isComplete)
    }

    init(
        initialConfiguration: OpeningConfiguration? = nil,
        heightOptions: [OpeningWorkSystem: [OpeningHeightSuggestion]] = [:],
        roomName: String? = nil,
        onSave: ((OpeningConfiguration) -> Void)? = nil
    ) {
        var configuration = initialConfiguration ?? OpeningConfiguration()
        var selectedSourceID: UUID?
        if initialConfiguration == nil {
            let preferredSystems: [OpeningWorkSystem] = [.furringLining, .railStudLining, .distributionPartition]
            if let system = preferredSystems.first(where: { !(heightOptions[$0] ?? []).isEmpty }),
               let suggestion = heightOptions[system]?.first {
                configuration.context.system = system
                configuration.context.hsp = suggestion.height
                configuration.context.spacing = suggestion.spacing
                configuration.context.doubledStuds = suggestion.doubledStuds
                selectedSourceID = suggestion.id
            }
        } else {
            selectedSourceID = configuration.sourceWorkID ?? heightOptions[configuration.context.system]?.first(where: {
                abs($0.height - configuration.context.hsp) < 0.001
            })?.id
            if let selectedSourceID,
               let suggestion = heightOptions[configuration.context.system]?.first(where: { $0.id == selectedSourceID }) {
                configuration.context.hsp = suggestion.height
                configuration.context.spacing = suggestion.spacing
                configuration.context.doubledStuds = suggestion.doubledStuds
            }
        }
        _context = State(initialValue: configuration.context)
        _openings = State(initialValue: configuration.openings)
        _selectedHeightSourceID = State(initialValue: selectedSourceID)
        self.heightOptions = heightOptions
        self.roomName = roomName ?? configuration.roomName
        self.onSave = onSave
    }

    var body: some View {
        Form {
            workSection
            typesSection
            openingsSection
            if !openings.isEmpty { totalsSection }
        }
        .blur(radius: editorPresentation == nil ? 0 : 6)
        .overlay {
            if editorPresentation != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { editorPresentation = nil }
            }
        }
        .animation(.easeOut(duration: 0.18), value: editorPresentation == nil)
        .navigationTitle("Ouvertures")
        .tint(green)
        .toolbar {
            if let onSave {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if editorPresentation != nil {
                            editorPresentation = nil
                            return
                        }
                        onSave(.init(
                            context: context,
                            openings: openings,
                            sourceWorkID: selectedHeightSourceID,
                            roomName: roomName?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                    }
                    .blur(radius: editorPresentation == nil ? 0 : 6)
                    .disabled(!canSave && editorPresentation == nil)
                }
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            NavigationStack {
                switch presentation {
                case .create(let kind):
                    OpeningEntryView(
                        kind: kind,
                        system: context.system,
                        minimumJoineryLiningDepth: selectedReference?.minimumJoineryLiningDepth
                    ) { openings.append(contentsOf: $0) }
                case .edit(let opening):
                    OpeningEntryView(
                        opening: opening,
                        system: context.system,
                        minimumJoineryLiningDepth: selectedReference?.minimumJoineryLiningDepth
                    ) { changed in
                        guard let changed = changed.first else { return }
                        guard let index = openings.firstIndex(where: { $0.id == changed.id }) else { return }
                        openings[index] = changed
                    }
                case .rename(let opening, let defaultName):
                    RenameOpeningView(opening: opening, defaultName: defaultName) { newName in
                        guard let index = openings.firstIndex(where: { $0.id == opening.id }) else { return }
                        openings[index].name = newName
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .onChange(of: context.system) { _, system in
            openings.removeAll { !system.availableOpeningKinds.contains($0.kind) }
            if system == .furringCeiling { context.spacing = 0.40 }
            if system == .railStudCeiling { context.spacing = 0.60 }
            if system.isCeiling {
                selectedHeightSourceID = nil
            } else if let suggestion = heightOptions[system]?.first {
                context.hsp = suggestion.height
                context.spacing = suggestion.spacing
                context.doubledStuds = suggestion.doubledStuds
                selectedHeightSourceID = suggestion.id
            } else {
                context.hsp = 0
                selectedHeightSourceID = nil
            }
        }
        .onChange(of: selectedHeightSourceID) { _, sourceID in
            guard let sourceID,
                  let suggestion = heightOptions[context.system]?.first(where: { $0.id == sourceID }) else { return }
            context.hsp = suggestion.height
            context.spacing = suggestion.spacing
            context.doubledStuds = suggestion.doubledStuds
        }
        .onChange(of: context.hsp) { _, newHeight in
            guard let sourceID = selectedHeightSourceID,
                  let source = heightOptions[context.system]?.first(where: { $0.id == sourceID }),
                  abs(source.height - newHeight) >= 0.001 else { return }
            selectedHeightSourceID = nil
        }
    }

    private var selectedReference: OpeningHeightSuggestion? {
        guard let selectedHeightSourceID else { return nil }
        return heightOptions[context.system]?.first { $0.id == selectedHeightSourceID }
    }

    @ViewBuilder
    private var workSection: some View {
        Section("Système accueillant l’ouverture") {
            Picker("Système accueillant l’ouverture", selection: $context.system) {
                ForEach(OpeningWorkSystem.allCases) { Text($0.title).tag($0) }
            }
        }

        if !context.system.isCeiling {
            Section("Hauteur sous plafond") {
                let options = heightOptions[context.system] ?? []
                if !options.isEmpty {
                    Picker("Ouvrage de référence", selection: $selectedHeightSourceID) {
                        ForEach(options) { option in
                            Text("\(option.sourceWorkName) · \(height(option.height))")
                                .tag(Optional(option.id))
                        }
                        Text("Saisie manuelle").tag(UUID?.none)
                    }
                }
                if options.isEmpty || selectedHeightSourceID == nil {
                    DecimalField(title: "Hauteur sous plafond", value: $context.hsp, suffix: "m")
                    if context.hsp <= 0 {
                        Label("Renseignez la hauteur sous plafond avant d’ajouter une ouverture.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }

        Section("Configuration de l’ossature") {
            if selectedHeightSourceID != nil, !context.system.isCeiling {
                LabeledContent("Entraxe", value: "\(Int(context.spacing * 100)) cm")
                if context.system == .railStudLining || context.system == .distributionPartition {
                    LabeledContent("Montants doublés dos à dos", value: context.doubledStuds ? "Oui" : "Non")
                }
                Text("Configuration reprise automatiquement depuis l’ouvrage de référence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if context.system == .furringLining || context.system == .railStudLining || context.system == .furringCeiling {
                Picker("Entraxe", selection: $context.spacing) {
                    Text("40 cm").tag(0.40)
                    Text("60 cm").tag(0.60)
                }
                .pickerStyle(.segmented)
            }

            if selectedHeightSourceID == nil && (context.system == .railStudLining || context.system == .distributionPartition) {
                Toggle("Montants doublés dos à dos", isOn: $context.doubledStuds)
            }

            if context.system == .railStudCeiling {
                OptionalDecimalField(
                    title: "Longueur dans le sens des montants",
                    value: $context.ceilingLengthInStudDirection,
                    suffix: "m",
                    placeholder: "0,00"
                )
                if (context.ceilingLengthInStudDirection ?? 0) <= 0 {
                    Label("Renseignez cette longueur avant d’ajouter une fenêtre de toit.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func height(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " m"
    }

    private var typesSection: some View {
        Section("Type d’ouverture") {
            ForEach(context.system.availableOpeningKinds) { kind in
                Button {
                    editorPresentation = .create(kind)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: kind.symbol)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title(in: context.system))
                            if !kind.isImplemented {
                                Text("Prévue — calcul à venir")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                    }
                }
                .disabled(!kind.isImplemented || !contextIsReady)
            }
        }
    }

    @ViewBuilder
    private var openingsSection: some View {
        if openings.isEmpty {
            Section {
                ContentUnavailableView(
                    "Aucune ouverture",
                    systemImage: "rectangle.dashed",
                    description: Text("Ajoutez une ouverture ci-dessus. La HSP, l’entraxe et l’ossature ne seront pas redemandés.")
                )
            }
        } else {
            Section("Détail par ouverture") {
                ForEach(Array(results.enumerated()), id: \.element.opening.id) { index, result in
                    NavigationLink {
                        OpeningResultView(
                            result: result,
                            system: context.system,
                            title: openingDisplayName(result.opening, index: index),
                            green: green
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(openingDisplayName(result.opening, index: index))
                                .font(.headline)
                            Text("\(centimeters(result.opening.width)) × \(centimeters(result.opening.height)) · \(area(result.opening.area))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Label(result.isComplete ? "Calculé" : "À compléter", systemImage: result.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(result.isComplete ? green : .orange)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { openings.remove(at: index) } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        Button { editorPresentation = .edit(result.opening) } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        .tint(.blue)
                        Button {
                            editorPresentation = .rename(
                                result.opening,
                                defaultName: openingDisplayName(result.opening, index: index)
                            )
                        } label: {
                            Label("Renommer", systemImage: "character.cursor.ibeam")
                        }
                        .tint(.orange)
                        Button { duplicateOpening(at: index) } label: {
                            Label("Dupliquer", systemImage: "plus.square.on.square")
                        }
                        .tint(green)
                    }
                }
            }
        }
    }

    private var totalsSection: some View {
        Section("Total des ouvertures") {
            ForEach(supplyRows(OpeningQuantityCalculator.totals(results))) { row in
                LabeledContent(row.name, value: row.value)
            }
            Text("Les plaques ne sont jamais déduites. Seule la surface d’isolant est retirée. Chaque ouverture est calculée séparément, sans fusion des renforts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func centimeters(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0...1))) + " cm"
    }

    private func area(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + " m²"
    }

    private func duplicateOpening(at index: Int) {
        guard openings.indices.contains(index) else { return }
        var duplicate = openings[index]
        duplicate.id = UUID()
        duplicate.name = nil
        openings.insert(duplicate, at: index + 1)
    }

    private func openingDisplayName(_ opening: OpeningInput, index: Int) -> String {
        let customName = opening.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return customName.isEmpty ? "\(opening.kind.title(in: context.system)) \(index + 1)" : customName
    }

    private func supplyRows(_ quantities: [OpeningQuantity]) -> [SupplyListingRow] {
        SupplyListingConsolidator.rows(quantities.map {
            .init(name: $0.name, quantity: $0.quantity, unit: $0.unit.rawValue)
        })
    }
}

private struct OpeningEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: OpeningKind
    let system: OpeningWorkSystem
    let minimumJoineryLiningDepth: Double?
    let onSave: ([OpeningInput]) -> Void
    @State private var width = 0.0
    @State private var height = 0.0
    @State private var count = 1
    @State private var mountingMode: OpeningMountingMode = .onJoineryLining
    @State private var revealDepth = 0.0
    @State private var showingIncompatibleLiningConfirmation = false
    @State private var openingName = ""
    @State private var isEditingName = false
    @FocusState private var nameFieldIsFocused: Bool

    init(kind: OpeningKind, system: OpeningWorkSystem, minimumJoineryLiningDepth: Double?, onSave: @escaping ([OpeningInput]) -> Void) {
        self.kind = kind
        self.system = system
        self.minimumJoineryLiningDepth = minimumJoineryLiningDepth
        self.onSave = onSave
    }

    init(opening: OpeningInput, system: OpeningWorkSystem, minimumJoineryLiningDepth: Double?, onSave: @escaping ([OpeningInput]) -> Void) {
        self.kind = opening.kind
        self.system = system
        self.minimumJoineryLiningDepth = minimumJoineryLiningDepth
        self.onSave = onSave
        _width = State(initialValue: opening.width)
        _height = State(initialValue: opening.height)
        _mountingMode = State(initialValue: opening.mountingMode)
        _revealDepth = State(initialValue: opening.revealDepth ?? 0)
        _openingName = State(initialValue: opening.name ?? "")
        self.existingID = opening.id
    }

    private var existingID: UUID? = nil

    var body: some View {
        Form {
            Section {
                DecimalField(title: "Largeur", value: centimetersBinding($width), suffix: "cm")
                DecimalField(title: "Hauteur", value: centimetersBinding($height), suffix: "cm")
                if existingID == nil {
                    Stepper("Nombre d’ouvertures identiques : \(count)", value: $count, in: 1...99)
                }
            } header: {
                Text(kind.title(in: system))
            } footer: {
                Text("Saisissez les dimensions finies en centimètres et le nombre d’ouvertures identiques. Exemple : 120 × 105 cm.")
            }

            if kind.usesMountingMode && system.isPeripheralLining {
                Section("Contour de l’ouverture") {
                    Picker("Contour", selection: $mountingMode) {
                        Text("Sur tapée").tag(OpeningMountingMode.onJoineryLining)
                        Text("En embrasure").tag(OpeningMountingMode.inReveal)
                    }
                    .pickerStyle(.segmented)
                    if mountingMode == .onJoineryLining {
                        HStack {
                            Text("Profondeur de la tapée")
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Information importante")
                            Spacer()
                            ZeroEmptyDecimalTextField(value: centimetersBinding($revealDepth), placeholder: "0")
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 70, maxWidth: 110)
                            Text("cm").foregroundStyle(.secondary)
                        }
                        if let minimumJoineryLiningDepth, revealDepth > 0, revealDepth + 0.000_1 < minimumJoineryLiningDepth {
                            Label(incompatibleLiningMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Cette cote est indispensable pour contrôler la compatibilité avec l’isolation et le parement de l’ouvrage de référence.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .principal) {
                if isEditingName {
                    TextField("Nom de l’ouverture", text: $openingName)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nameFieldIsFocused)
                        .onSubmit { isEditingName = false }
                } else {
                    Button {
                        isEditingName = true
                        nameFieldIsFocused = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(editableTitle)
                                .font(.headline)
                            Image(systemName: "pencil")
                                .font(.caption2)
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityHint("Modifier le nom de l’ouverture")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(existingID == nil ? "Ajouter" : "Enregistrer") {
                    if hasIncompatibleJoineryLining {
                        showingIncompatibleLiningConfirmation = true
                    } else {
                        saveAndDismiss()
                    }
                }
                .disabled(width <= 0 || height <= 0 || requiresRevealDepth)
            }
        }
        .alert("Tapée incompatible", isPresented: $showingIncompatibleLiningConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Continuer quand même") { saveAndDismiss() }
        } message: {
            Text("\(incompatibleLiningMessage) Souhaitez-vous quand même continuer ?")
        }
    }

    private var savedRevealDepth: Double? {
        guard system.isPeripheralLining, kind.usesMountingMode,
              mountingMode == .onJoineryLining, revealDepth > 0 else { return nil }
        return revealDepth
    }

    private var requiresRevealDepth: Bool {
        system.isPeripheralLining && kind.usesMountingMode && mountingMode == .onJoineryLining && revealDepth <= 0
    }

    private var hasIncompatibleJoineryLining: Bool {
        guard mountingMode == .onJoineryLining, let minimumJoineryLiningDepth else { return false }
        return revealDepth > 0 && revealDepth + 0.000_1 < minimumJoineryLiningDepth
    }

    private var incompatibleLiningMessage: String {
        let minimum = ((minimumJoineryLiningDepth ?? 0) * 100).formatted(.number.precision(.fractionLength(0...1)))
        return "L’épaisseur d’isolant choisie n’est pas compatible avec cette tapée de menuiserie. La composition de l’ouvrage nécessite au moins \(minimum) cm."
    }

    private var normalizedOpeningName: String? {
        let value = openingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var editableTitle: String {
        normalizedOpeningName ?? (existingID == nil ? "Nouvelle ouverture" : "Modifier l’ouverture")
    }

    private func saveAndDismiss() {
        if let existingID {
            onSave([.init(
                id: existingID,
                kind: kind,
                width: width,
                height: height,
                mountingMode: mountingMode,
                revealDepth: savedRevealDepth,
                name: normalizedOpeningName
            )])
        } else {
            onSave((0..<count).map { index in
                .init(
                    kind: kind,
                    width: width,
                    height: height,
                    mountingMode: mountingMode,
                    revealDepth: savedRevealDepth,
                    name: normalizedOpeningName.map { count == 1 ? $0 : "\($0) \(index + 1)" }
                )
            })
        }
        dismiss()
    }

    private func centimetersBinding(_ meters: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { meters.wrappedValue * 100 },
            set: { meters.wrappedValue = $0 / 100 }
        )
    }
}

private struct RenameOpeningView: View {
    @Environment(\.dismiss) private var dismiss
    let opening: OpeningInput
    let onSave: (String) -> Void
    @State private var name: String

    init(opening: OpeningInput, defaultName: String, onSave: @escaping (String) -> Void) {
        self.opening = opening
        self.onSave = onSave
        let currentName = opening.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _name = State(initialValue: currentName.isEmpty ? defaultName : currentName)
    }

    var body: some View {
        Form {
            Section("Nom de l’ouverture") {
                TextField("Exemple : Fenêtre cuisine", text: $name)
                    .textInputAutocapitalization(.sentences)
            }
        }
        .navigationTitle("Renommer l’ouverture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct OpeningResultView: View {
    let result: OpeningQuantityResult
    let system: OpeningWorkSystem
    let title: String
    let green: Color

    var body: some View {
        List {
            Section {
                LabeledContent("Dimensions", value: dimensions)
                if result.opening.kind.usesMountingMode && system.isPeripheralLining {
                    LabeledContent("Contour", value: result.opening.mountingMode.title)
                    if let depth = result.opening.revealDepth, result.opening.mountingMode == .onJoineryLining {
                        LabeledContent("Profondeur de la tapée", value: format(depth * 100, unit: "cm"))
                    }
                }
                LabeledContent("Surface d’isolant à déduire", value: format(result.insulationAreaDeduction, unit: "m²"))
                LabeledContent("Plaques déduites", value: "Non")
            }

            Section("Renforts et fournitures") {
                if result.quantities.isEmpty {
                    Text("Aucun quantitatif disponible.").foregroundStyle(.secondary)
                } else {
                    ForEach(supplyRows) { row in
                        LabeledContent(row.name, value: row.value)
                    }
                }
            }

            if !result.notes.isEmpty {
                Section("À savoir") {
                    ForEach(result.notes, id: \.self) { Label($0, systemImage: "info.circle") }
                }
            }
        }
        .navigationTitle(title)
        .tint(green)
    }

    private var dimensions: String {
        "\(format(result.opening.width * 100, unit: "cm", whole: true)) × \(format(result.opening.height * 100, unit: "cm", whole: true))"
    }

    private var supplyRows: [SupplyListingRow] {
        SupplyListingConsolidator.rows(result.quantities.map {
            .init(name: $0.name, quantity: $0.quantity, unit: $0.unit.rawValue)
        })
    }

    private func format(_ value: Double, unit: String, whole: Bool = false) -> String {
        value.formatted(.number.precision(.fractionLength(whole ? 0 : 2))) + " " + unit
    }
}

private struct DecimalField: View {
    let title: String
    @Binding var value: Double
    let suffix: String
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0,00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 70, maxWidth: 110)
                .focused($isFocused)
            Text(suffix).foregroundStyle(.secondary)
        }
        .onAppear { synchronizeText() }
        .onChange(of: value) { _, _ in
            if !isFocused { synchronizeText() }
        }
        .onChange(of: text) { _, newText in
            let normalized = newText.replacingOccurrences(of: ",", with: ".")
            if normalized.isEmpty {
                value = 0
            } else if let parsed = Double(normalized) {
                value = parsed
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused, value == 0 {
                text = ""
            } else if !focused {
                synchronizeText()
            }
        }
    }

    private func synchronizeText() {
        text = value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct OptionalDecimalField: View {
    let title: String
    @Binding var value: Double?
    let suffix: String
    var placeholder = "Optionnel"

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 80, maxWidth: 110)
            Text(suffix).foregroundStyle(.secondary)
        }
    }
}
