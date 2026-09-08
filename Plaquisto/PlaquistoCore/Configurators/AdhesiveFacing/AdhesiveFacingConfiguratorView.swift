import SwiftUI

struct AdhesiveFacingQuantity: Identifiable, Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var id: String { "\(name)|\(unit)" }
}

struct AdhesiveFacingConfiguration: Codable, Equatable {
    var geometryMode = "length"
    var height = 0.0
    var enteredLength = 0.0
    var enteredSurface = 0.0
    var facingFamily = "BA13"
    var facingFunctionID = ""
    var formatID = "1200x2500"
    var jointTreatment = true
    var quantities: [AdhesiveFacingQuantity] = []

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }
}

struct AdhesiveFacingConfiguratorView: View {
    private enum GeometryMode: String, CaseIterable, Identifiable {
        case length = "Longueur"
        case surface = "Surface totale"
        var id: Self { self }
    }

    @EnvironmentObject private var references: AdhesiveFacingReferenceStore
    let onSave: ((AdhesiveFacingConfiguration) -> Void)?
    let onClose: () -> Void
    let showsCloseButton: Bool
    @State private var step: Int
    @State private var geometryMode: GeometryMode
    @State private var height: Double
    @State private var enteredLength: Double
    @State private var enteredSurface: Double
    @State private var selectedFamily: String
    @State private var selectedFunctionID: String
    @State private var selectedFormatID: String
    @State private var jointTreatment: Bool
    @State private var showPanelHeightWarning = false

    private let green = Color(red: 0.12, green: 0.38, blue: 0.29)
    private let stepNames = ["Dimensions", "Parement", "Format", "Bandes à joint", "Résultat"]

    init(
        initialConfiguration: AdhesiveFacingConfiguration? = nil,
        startsAtResult: Bool = false,
        onSave: ((AdhesiveFacingConfiguration) -> Void)? = nil,
        onClose: @escaping () -> Void = {},
        showsCloseButton: Bool = false
    ) {
        let value = initialConfiguration ?? AdhesiveFacingConfiguration()
        _step = State(initialValue: startsAtResult ? 5 : 1)
        _geometryMode = State(initialValue: value.geometryMode == "surface" ? .surface : .length)
        _height = State(initialValue: value.height)
        _enteredLength = State(initialValue: value.enteredLength)
        _enteredSurface = State(initialValue: value.enteredSurface)
        _selectedFamily = State(initialValue: value.facingFamily)
        _selectedFunctionID = State(initialValue: value.facingFunctionID)
        _selectedFormatID = State(initialValue: value.formatID)
        _jointTreatment = State(initialValue: value.jointTreatment)
        self.onSave = onSave
        self.onClose = onClose
        self.showsCloseButton = showsCloseButton
    }

    private var actualLength: Double { geometryMode == .length ? enteredLength : (height > 0 ? enteredSurface / height : 0) }
    private var actualArea: Double { geometryMode == .surface ? enteredSurface : enteredLength * height }
    private var functions: [AdhesiveFacingOption] { references.functions(for: selectedFamily) }
    private var selectedFunction: AdhesiveFacingOption? { functions.first { $0.id == selectedFunctionID } ?? functions.first }
    private var selectedFormat: AdhesiveFacingFormat { references.formats.first { $0.id == selectedFormatID } ?? references.formats[1] }
    private var panelIsShort: Bool { Double(selectedFormat.heightMM) / 1000 < height }
    private var canContinue: Bool {
        switch step {
        case 1: height > 0 && (geometryMode == .length ? enteredLength > 0 : enteredSurface > 0)
        case 2: references.families.contains(selectedFamily) && selectedFunction != nil
        case 3: references.formats.contains(selectedFormat)
        default: true
        }
    }

    var body: some View {
        Group {
            if references.isLoading {
                ProgressView("Synchronisation avec Plaquisto Admin…")
            } else if let error = references.error {
                ContentUnavailableView {
                    Label("Données indisponibles", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Réessayer") { Task { await references.load() } }
                }
            } else {
                wizard
            }
        }
        .tint(green)
        .onChange(of: references.options) { _, _ in normalizeSelections() }
        .onChange(of: selectedFamily) { _, _ in normalizeFunction() }
        .onChange(of: height) { _, _ in normalizeFormatForHeight() }
        .alert("Hauteur de plaque insuffisante", isPresented: $showPanelHeightWarning) {
            Button("Modifier le format", role: .cancel) {}
            Button("Continuer malgré tout") { step += 1 }
        } message: {
            Text("La plaque sélectionnée mesure \(format(Double(selectedFormat.heightMM) / 1000, "m")) de haut, pour une hauteur sous plafond de \(format(height, "m")). Des raccords seront nécessaires. Confirmez-vous ce choix ?")
        }
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 1: dimensionsStep
                    case 2: facingStep
                    case 3: formatStep
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
            if showsCloseButton { Button("Fermer", action: onClose).buttonStyle(.bordered) }
            Text("OUVRAGE").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Doublage périphérique en parement collé").font(.title2.bold())
            Label("Données synchronisées avec Plaquisto Admin", systemImage: "icloud.and.arrow.down")
                .font(.caption).foregroundStyle(.green)
            ProgressView(value: Double(step), total: 5)
            Text("Étape \(step) sur 5 · \(stepNames[step - 1])").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
    }

    private var footer: some View {
        HStack {
            if step > 1 {
                Button("Retour") { step -= 1 }
                    .buttonStyle(.borderedProminent).tint(green.opacity(0.18)).foregroundStyle(green)
            }
            Spacer()
            if step < 5 {
                Button("Continuer") { continueForm() }.buttonStyle(.borderedProminent).disabled(!canContinue)
            } else {
                Button(onSave == nil ? "Terminer" : "Enregistrer") {
                    if let onSave { onSave(configuration) } else { step = 1 }
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20).background(.background)
    }

    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Dimensions de l’ouvrage")
            card {
                AdhesiveDecimalRow("Hauteur sous plafond", value: $height, unit: "m")
                Divider()
                Picker("Mode de saisie", selection: $geometryMode) {
                    ForEach(GeometryMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Divider()
                if geometryMode == .length {
                    AdhesiveDecimalRow("Longueur du doublage (périmètre)", value: $enteredLength, unit: "m")
                } else {
                    AdhesiveDecimalRow("Surface totale", value: $enteredSurface, unit: "m²")
                }
            }
            card {
                LabeledContent(geometryMode == .length ? "Surface calculée" : "Longueur calculée", value: format(geometryMode == .length ? actualArea : actualLength, geometryMode == .length ? "m²" : "m"))
            }
            Text("La hauteur sous plafond est obligatoire. Renseignez ensuite soit la longueur du doublage, soit sa surface totale.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var facingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Parement")
            card {
                LabeledContent("Type de plaque") {
                    Picker("Type de plaque", selection: $selectedFamily) {
                        ForEach(references.families, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden()
                }
                Divider()
                LabeledContent("Fonction") {
                    Picker("Fonction", selection: $selectedFunctionID) {
                        ForEach(functions) { Text($0.functionTitle).tag($0.id) }
                    }.labelsHidden()
                }
            }
            if selectedFamily == "BA6" {
                Text("Le BA6 est autorisé seul pour cet ouvrage.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var formatStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Dimension du parement")
            card {
                LabeledContent("Format") {
                    Picker("Format", selection: $selectedFormatID) {
                        ForEach(references.formats) { Text($0.title).tag($0.id) }
                    }.labelsHidden()
                }
            }
            Text("Ces dimensions génériques sont proposées quel que soit le type de parement. La disponibilité exacte sera à confirmer auprès du fournisseur.")
                .font(.footnote).foregroundStyle(.secondary)
            if panelIsShort {
                warning("La hauteur sélectionnée est inférieure à la hauteur sous plafond de \(format(height, "m")).")
            }
        }
    }

    private var jointsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Bandes à joint")
            card {
                Toggle("Prévoir le traitement des bandes à joint", isOn: $jointTreatment)
                if jointTreatment { Divider(); LabeledContent("Enduit", value: "Enduit en poudre") }
            }
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Configuration retenue")
            card {
                LabeledContent("Dimensions", value: "\(format(actualLength, "m")) × \(format(height, "m"))")
                Divider(); LabeledContent("Surface", value: format(actualArea, "m²"))
                Divider(); LabeledContent("Parement", value: "\(selectedFamily) · \(selectedFunction?.functionTitle ?? "Standard")")
                Divider(); LabeledContent("Format", value: selectedFormat.title)
            }
            sectionTitle("Quantitatif indicatif")
            card {
                ForEach(Array(quantityRows.enumerated()), id: \.offset) { index, row in
                    LabeledContent(row.name, value: format(row.quantity, row.unit))
                    if index < quantityRows.count - 1 { Divider() }
                }
            }
        }
    }

    private var quantityRows: [(name: String, quantity: Double, unit: String)] {
        var result = [("Plaque de plâtre \(selectedFamily)", actualArea * references.quantities.plate, "m²"),
                      (references.quantities.names["adhesive"] ?? "Mortier adhésif", actualArea * references.quantities.adhesive, "kg")]
        if jointTreatment {
            result.append((references.quantities.names["band"] ?? "Bande à joint", actualArea * references.quantities.band, "ml"))
            result.append((references.quantities.names["powder"] ?? "Enduit en poudre", actualArea * references.quantities.powder, "kg"))
        }
        return result
    }

    private var configuration: AdhesiveFacingConfiguration {
        AdhesiveFacingConfiguration(
            geometryMode: geometryMode == .surface ? "surface" : "length",
            height: height,
            enteredLength: enteredLength,
            enteredSurface: enteredSurface,
            facingFamily: selectedFamily,
            facingFunctionID: selectedFunction?.id ?? "",
            formatID: selectedFormat.id,
            jointTreatment: jointTreatment,
            quantities: quantityRows.map { AdhesiveFacingQuantity(name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        )
    }

    private func normalizeSelections() {
        if !references.families.contains(selectedFamily) { selectedFamily = references.families.first ?? "BA13" }
        normalizeFunction()
    }

    private func normalizeFunction() {
        if !functions.contains(where: { $0.id == selectedFunctionID }) { selectedFunctionID = functions.first?.id ?? "" }
    }

    private func normalizeFormatForHeight() {
        guard panelIsShort, let next = references.formats.first(where: { Double($0.heightMM) / 1000 >= height }) else { return }
        selectedFormatID = next.id
    }

    private func continueForm() {
        if step == 3 && panelIsShort { showPanelHeightWarning = true }
        else { step += 1 }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.bold()).foregroundStyle(.secondary).padding(.horizontal, 12)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text)
        }
        .font(.footnote).padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
    }

    private func format(_ value: Double, _ unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }
}

private struct AdhesiveDecimalRow: View {
    let title: String
    @Binding var value: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, unit: String) {
        self.title = title
        _value = value
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 58, maxWidth: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
