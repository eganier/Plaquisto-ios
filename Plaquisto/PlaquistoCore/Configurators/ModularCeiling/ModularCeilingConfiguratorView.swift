import SwiftUI

enum ModularCeilingTileFormat: String, Codable, CaseIterable, Identifiable {
    case square600 = "600x600"
    case rectangle600x1200 = "600x1200"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square600: "600 × 600 mm"
        case .rectangle600x1200: "600 × 1200 mm"
        }
    }

    var tileArea: Double {
        switch self {
        case .square600: 0.36
        case .rectangle600x1200: 0.72
        }
    }

    /// Dimension du module dans le sens perpendiculaire aux porteurs.
    var transverseModule: Double {
        switch self {
        case .square600: 0.6
        case .rectangle600x1200: 1.2
        }
    }
}

struct ModularCeilingConfiguration: Codable, Equatable {
    var length: Double = 0
    var width: Double = 0
    var tileFormat: ModularCeilingTileFormat = .square600
    var tileThicknessMM: Double = 20
    var plenumCM: Double = 0
    var wastePercent: Double = 5
    var replacedSquareModules: Int = 0

    var area: Double { length * width }
}

struct ModularCeilingQuantities: Equatable {
    let area: Double
    let perimeter: Double
    let installedTiles: Int
    let fullTiles: Int
    let cutTiles: Int
    let orderedTiles: Int
    let mainRunnerLines: Int
    let mainRunnerLength: Double
    let mainRunnerBars: Int
    let crossTees1200Useful: Int
    let crossTees1200Ordered: Int
    let crossTees600Useful: Int
    let crossTees600Ordered: Int
    let perimeterAngleBars: Int
    let hangers: Int
}

enum ModularCeilingCalculator {
    static func calculate(_ configuration: ModularCeilingConfiguration) -> ModularCeilingQuantities {
        let longSide = max(0, max(configuration.length, configuration.width))
        let shortSide = max(0, min(configuration.length, configuration.width))
        let wasteFactor = 1 + max(0, configuration.wastePercent) / 100

        let along = centeredModuleCount(dimension: longSide, module: 0.6)
        let across = centeredModuleCount(dimension: shortSide, module: configuration.tileFormat.transverseModule)
        let fullAlong = centeredFullModuleCount(dimension: longSide, module: 0.6)
        let fullAcross = centeredFullModuleCount(dimension: shortSide, module: configuration.tileFormat.transverseModule)
        let installedTiles = along * across
        let fullTiles = fullAlong * fullAcross
        let cutTiles = max(0, installedTiles - fullTiles)
        let replacedModules = configuration.tileFormat == .square600
            ? min(max(0, configuration.replacedSquareModules), installedTiles)
            : 0

        // Trame T24 de base : porteurs espacés de 1,20 m et entretoises de
        // 1,20 m tous les 0,60 m. Les entretoises 0,60 m ne ferment que la
        // maille carrée 600 x 600.
        let mainRunnerLines = shortSide > 0 ? max(1, Int(floor(shortSide / 1.2 + 0.000_001))) : 0
        let crossRows = longSide > 0 ? Int(floor(longSide / 0.6 + 0.000_001)) : 0
        let crossTees1200Useful = crossRows * (mainRunnerLines + 1)
        let crossTees600Useful = configuration.tileFormat == .square600 ? along * mainRunnerLines : 0
        let mainRunnerLength = Double(mainRunnerLines) * longSide
        let hangersPerRunner = longSide > 0
            ? max(1, Int(ceil(max(0, longSide - 0.9) / 1.2)) + 1)
            : 0

        return ModularCeilingQuantities(
            area: longSide * shortSide,
            perimeter: 2 * (longSide + shortSide),
            installedTiles: installedTiles,
            fullTiles: fullTiles,
            cutTiles: cutTiles,
            orderedTiles: Int(ceil(Double(max(0, installedTiles - replacedModules)) * wasteFactor)),
            mainRunnerLines: mainRunnerLines,
            mainRunnerLength: mainRunnerLength,
            mainRunnerBars: mainRunnerLength > 0 ? Int(ceil(mainRunnerLength * wasteFactor / 3.6)) : 0,
            crossTees1200Useful: crossTees1200Useful,
            crossTees1200Ordered: Int(ceil(Double(crossTees1200Useful) * wasteFactor)),
            crossTees600Useful: crossTees600Useful,
            crossTees600Ordered: Int(ceil(Double(crossTees600Useful) * wasteFactor)),
            perimeterAngleBars: longSide > 0 && shortSide > 0
                ? Int(ceil((2 * (longSide + shortSide)) * wasteFactor / 3))
                : 0,
            hangers: mainRunnerLines * hangersPerRunner
        )
    }

    private static func centeredModuleCount(dimension: Double, module: Double) -> Int {
        guard dimension > 0, module > 0 else { return 0 }
        return max(1, Int(ceil(dimension / module - 0.000_001)))
    }

    private static func centeredFullModuleCount(dimension: Double, module: Double) -> Int {
        let count = centeredModuleCount(dimension: dimension, module: module)
        guard count > 0 else { return 0 }
        let ratio = dimension / module
        if abs(ratio.rounded() - ratio) < 0.000_001 { return count }
        return max(0, count - 2)
    }
}

struct ModularCeilingConfiguratorView: View {
    @State private var configuration: ModularCeilingConfiguration
    @State private var step: Int
    @State private var showsConfiguration = false
    @State private var showsPlenumConfirmation = false
    private let isEditing: Bool
    private let onSave: (ModularCeilingConfiguration) -> Void

    init(
        initialConfiguration: ModularCeilingConfiguration? = nil,
        startsAtResult: Bool = false,
        onSave: @escaping (ModularCeilingConfiguration) -> Void = { _ in }
    ) {
        _configuration = State(initialValue: initialConfiguration ?? ModularCeilingConfiguration())
        _step = State(initialValue: startsAtResult ? 3 : 0)
        isEditing = initialConfiguration != nil
        self.onSave = onSave
    }

    private var quantities: ModularCeilingQuantities {
        ModularCeilingCalculator.calculate(configuration)
    }

    private var minimumPlenumCM: Double {
        configuration.tileThicknessMM <= 20 ? 15 : 20
    }

    private var hasEnoughPlenum: Bool {
        configuration.plenumCM + 0.000_1 >= minimumPlenumCM
    }

    private var canSave: Bool {
        configuration.length > 0 &&
        configuration.width > 0 &&
        configuration.tileThicknessMM > 0 &&
        configuration.plenumCM > 0
    }

    private var canContinue: Bool {
        switch step {
        case 0: configuration.length > 0 && configuration.width > 0
        case 1: configuration.tileThicknessMM > 0
        case 2: configuration.plenumCM > 0
        default: canSave
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Étape \(step + 1) sur 4")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(stepTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(step + 1), total: 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Form { currentStepContent }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button("Précédent") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(step == 3 ? "Enregistrer l’ouvrage" : "Suivant") {
                    if step == 3 { attemptSave() }
                    else { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .navigationTitle("Plafond modulaire (bêta)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", action: attemptSave)
                    .disabled(!canSave)
                }
            }
        }
        .alert("Plénum à confirmer", isPresented: $showsPlenumConfirmation) {
            Button("Revoir le plénum", role: .cancel) {}
            Button("Enregistrer quand même") { onSave(configuration) }
        } message: {
            Text("Le plénum renseigné est inférieur au repère prudent de \(format(minimumPlenumCM)) cm. Vérifiez la profondeur minimale de pose et de démontage indiquée par le fabricant des dalles.")
        }
        .onChange(of: configuration.tileFormat) { _, format in
            if format == .rectangle600x1200 {
                configuration.replacedSquareModules = 0
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: "Dimensions"
        case 1: "Dalles et trame"
        case 2: "Plénum"
        default: "Quantitatif"
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch step {
        case 0:
            dimensionsSection
        case 1:
            tilesSection
        case 2:
            plenumSection
        default:
            configurationSummarySection
            quantitySection
        }
    }

    private var dimensionsSection: some View {
        Section {
            metricRow("Longueur", value: $configuration.length, unit: "m")
            metricRow("Largeur", value: $configuration.width, unit: "m")
        } header: {
            Text("Dimensions de la pièce")
        } footer: {
            Text("Première version limitée aux pièces rectangulaires. Les porteurs sont calculés dans le sens de la plus grande longueur.")
        }
    }

    private var tilesSection: some View {
        Section {
            Picker("Format des dalles", selection: $configuration.tileFormat) {
                ForEach(ModularCeilingTileFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)

            metricRow("Épaisseur des dalles", value: $configuration.tileThicknessMM, unit: "mm")

            Stepper(value: $configuration.wastePercent, in: 0...20, step: 1) {
                LabeledContent("Marge de chutes", value: "\(Int(configuration.wastePercent)) %")
            }

            if configuration.tileFormat == .square600 {
                Stepper(value: $configuration.replacedSquareModules, in: 0...999) {
                    LabeledContent(
                        "Modules remplacés par un équipement",
                        value: "\(configuration.replacedSquareModules)"
                    )
                }
            }
        } header: {
            Text("Dalles et trame T24")
        } footer: {
            Text(configuration.tileFormat == .square600
                 ? "Un luminaire 600 × 600 occupant une maille complète peut être déduit ici."
                 : "Le format 600 × 1200 n’utilise pas d’entretoises de 600 mm. Les équipements intégrés ne sont pas déduits dans cette version simple.")
        }
    }

    private var plenumSection: some View {
        Section {
            metricRow("Plénum disponible", value: $configuration.plenumCM, unit: "cm")

            if configuration.plenumCM <= 0 {
                Label("Renseignez le plénum avant d’enregistrer.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if hasEnoughPlenum {
                Label("Plénum cohérent avec le repère de base.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(
                    "Repère prudent : au moins \(format(minimumPlenumCM)) cm pour cette épaisseur.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Passage et démontage des dalles")
        } footer: {
            Text("Le besoin réel dépend de la dalle, de son bord et du système. Plaquisto utilise ici un repère prudent : 15 cm jusqu’à 20 mm d’épaisseur, 20 cm au-delà. La fiche fabricant reste prioritaire.")
        }
    }

    private var quantitySection: some View {
        Section {
            LabeledContent("Surface", value: "\(format(quantities.area)) m²")
            LabeledContent(
                "Dalles à commander",
                value: "\(quantities.orderedTiles) u"
            )
            LabeledContent(
                "Calepinage",
                value: "\(quantities.installedTiles) modules · \(quantities.fullTiles) entiers · \(quantities.cutTiles) coupés"
            )
            LabeledContent(
                "Porteurs T24 de 3,60 m",
                value: "\(quantities.mainRunnerBars) u · \(quantities.mainRunnerLines) lignes · \(format(quantities.mainRunnerLength)) ml"
            )
            LabeledContent(
                "Entretoises T24 de 1,20 m",
                value: "\(quantities.crossTees1200Ordered) u · \(quantities.crossTees1200Useful) utiles"
            )
            if configuration.tileFormat == .square600 {
                LabeledContent(
                    "Entretoises T24 de 0,60 m",
                    value: "\(quantities.crossTees600Ordered) u · \(quantities.crossTees600Useful) utiles"
                )
            }
            LabeledContent(
                "Cornières de rive de 3,00 m",
                value: "\(quantities.perimeterAngleBars) u · \(format(quantities.perimeter)) ml"
            )
            LabeledContent("Suspentes + fixations", value: "\(quantities.hangers) u")
        } header: {
            Text("Quantitatif")
        } footer: {
            Text("Quantités calculées sur une trame T24 standard centrée. Les dalles et profils sont arrondis à l’unité supérieure avec la marge choisie.")
        }
    }

    private var configurationSummarySection: some View {
        Section {
            DisclosureGroup("Configuration retenue", isExpanded: $showsConfiguration) {
                LabeledContent("Dimensions", value: "\(format(configuration.length)) × \(format(configuration.width)) m")
                LabeledContent("Format", value: configuration.tileFormat.title)
                LabeledContent("Épaisseur", value: "\(format(configuration.tileThicknessMM)) mm")
                LabeledContent("Plénum", value: "\(format(configuration.plenumCM)) cm")
                LabeledContent("Marge", value: "\(Int(configuration.wastePercent)) %")
            }
        }
    }

    private func metricRow(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            ZeroEmptyDecimalTextField(value: value, placeholder: "0")
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func attemptSave() {
        guard canSave else { return }
        if hasEnoughPlenum {
            onSave(configuration)
        } else {
            showsPlenumConfirmation = true
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
