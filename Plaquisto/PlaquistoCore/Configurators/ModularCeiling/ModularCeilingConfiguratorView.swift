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
    var surveyedSurfaces: [Surface2D]? = nil

    var area: Double {
        guard let surfaces = surveyedSurfaces else { return length * width }
        return surfaces.reduce(0) { $0 + ((try? $1.netMeasuredArea()) ?? 0) / 1_000_000 }
    }
    var scanCalculationError: String? {
        guard let surfaces = surveyedSurfaces else { return nil }
        do {
            guard !surfaces.isEmpty else { throw LayoutGeometryError.invalidContour }
            _ = try ModularCeilingCalculator.scanned(self, surfaces: surfaces)
            return nil
        } catch { return "Le plafond modulaire ne peut pas être calculé sur ce contour. Vérifiez le plan avant de commander les fournitures." }
    }
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
    /// The saved tile grid and the indicative T24 calculation share one origin.
    static func layoutLayer(_ configuration: ModularCeilingConfiguration, surface: Surface2D) -> LayoutLayer {
        let angle = LayoutViewport.initialCeilingAlignment(surface.contour, referenceEdge: nil)?.angle ?? 0
        let b = aligned(surface).bounds
        let moduleY = configuration.tileFormat.transverseModule * 1000
        let columns = ceil(b.width / 600 - 0.000_001), rows = ceil(b.height / moduleY - 0.000_001)
        var layer = LayoutLayer()
        layer.sheetWidth = 600; layer.sheetLength = moduleY
        layer.offset = .init(x: b.min.x - (columns * 600 - b.width) / 2, y: b.min.y - (rows * moduleY - b.height) / 2)
        layer.inheritedGridFrame = .init(angle: -angle)
        layer.furring = nil; layer.staggered = false; layer.reuseOffcuts = false
        return layer
    }
    static func calculate(_ configuration: ModularCeilingConfiguration) -> ModularCeilingQuantities {
        if let surfaces = configuration.surveyedSurfaces, !surfaces.isEmpty,
           let measured = try? scanned(configuration, surfaces: surfaces) { return measured }
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

    /// Independent T24 grids in each measured support. Clip tiles and profiles
    /// against the same contour/openings; scan yaw must not inflate quantities.
    static func scanned(_ configuration: ModularCeilingConfiguration, surfaces: [Surface2D]) throws -> ModularCeilingQuantities {
        var area = 0.0, perimeter = 0.0, runnerLength = 0.0
        var tiles = 0, full = 0, runners = 0, tees1200 = 0, tees600 = 0, hangers = 0
        for original in surfaces {
            let surface = aligned(original), b = surface.bounds
            guard b.width.isFinite, b.height.isFinite, b.width > 0, b.height > 0,
                  b.width < 100_000, b.height < 100_000 else { throw LayoutGeometryError.invalidContour }
            area += try surface.netMeasuredArea() / 1_000_000
            let loops = try LayoutGeometry.intersection(outer: surface.contour, holes: surface.openings.map(\.contour), rectangle: b)
            perimeter += loops.reduce(0) { $0 + LayoutGeometry.edges($1).reduce(0) { $0 + ($1.b - $1.a).length } } / 1000
            let moduleY = configuration.tileFormat.transverseModule * 1000
            let layer = layoutLayer(configuration, surface: original)
            let origin = layer.offset
            let columns = ceil(b.width / 600 - 0.000_001)
            let sheets = try LayoutBoardGrid.clippedSheets(surface: surface, layer: layer)
            tiles += sheets.count
            full += sheets.filter { abs($0.area - 600 * moduleY) < 1 }.count
            func clipped(_ a: LayoutPoint, _ z: LayoutPoint) -> [LayoutJoint] {
                LayoutOpeningFraming.clip(.init(start: a, end: z), to: surface)
            }
            let runnerYs = stride(from: origin.y + 1200, to: b.max.y - 0.5, by: 1200).filter { $0 > b.min.y + 0.5 }
            for y in runnerYs {
                let segments = clipped(.init(x: b.min.x, y: y), .init(x: b.max.x, y: y))
                if !segments.isEmpty { runners += 1 }
                for segment in segments {
                    let length = (segment.end - segment.start).length / 1000
                    runnerLength += length
                    hangers += max(1, Int(ceil(max(0, length - 0.9) / 1.2)) + 1)
                }
            }
            let ys = [b.min.y] + runnerYs + [b.max.y]
            for column in 1..<max(1, Int(columns)) {
                let x = origin.x + Double(column) * 600
                for pair in zip(ys, ys.dropFirst()) {
                    tees1200 += clipped(.init(x: x, y: pair.0), .init(x: x, y: pair.1)).count
                }
            }
            if configuration.tileFormat == .square600 {
                // Secondary 600-mm cross tees halfway between main runners.
                let secondaryYs = stride(from: origin.y + 600, to: b.max.y - 0.5, by: 1200).filter { $0 > b.min.y + 0.5 }
                for y in secondaryYs {
                    for column in 0..<max(1, Int(columns)) {
                        let x = origin.x + Double(column) * 600
                        tees600 += clipped(.init(x: x, y: y), .init(x: x + 600, y: y)).count
                    }
                }
            }
        }
        let factor = 1 + max(0, configuration.wastePercent) / 100
        let replaced = configuration.tileFormat == .square600 ? min(tiles, max(0, configuration.replacedSquareModules)) : 0
        return .init(area: area, perimeter: perimeter, installedTiles: tiles, fullTiles: full, cutTiles: tiles - full,
            orderedTiles: Int(ceil(Double(tiles - replaced) * factor)), mainRunnerLines: runners,
            mainRunnerLength: runnerLength, mainRunnerBars: Int(ceil(runnerLength * factor / 3.6)),
            crossTees1200Useful: tees1200, crossTees1200Ordered: Int(ceil(Double(tees1200) * factor)),
            crossTees600Useful: tees600, crossTees600Ordered: Int(ceil(Double(tees600) * factor)),
            perimeterAngleBars: Int(ceil(perimeter * factor / 3)), hangers: hangers)
    }

    static func aligned(_ original: Surface2D) -> Surface2D {
        let angle = LayoutViewport.initialCeilingAlignment(original.contour, referenceEdge: nil)?.angle ?? 0
        var result = original
        result.contour = original.contour.map { LayoutOpeningFrame.rotate($0, by: angle) }
        result.openings = original.openings.map { opening in
            var copy = opening; copy.contour = opening.contour.map { LayoutOpeningFrame.rotate($0, by: angle) }; return copy
        }
        return result
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
    @Environment(\.usesAtlantiqueDesign) private var atlantique
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
        configuration.scanCalculationError == nil && configuration.length > 0 &&
        configuration.width > 0 &&
        configuration.tileThicknessMM > 0 &&
        configuration.plenumCM > 0
    }

    private var canContinue: Bool {
        guard configuration.scanCalculationError == nil else { return false }
        return switch step {
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
                        .foregroundStyle(atlantique ? Color.white : .secondary)
                    Spacer()
                    Text(stepTitle)
                        .font(.caption)
                        .foregroundStyle(atlantique ? Color.white : .secondary)
                }
                ProgressView(value: Double(step + 1), total: 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            AtlantiqueForm(bookLayout: true) { currentStepContent }.id(step)
        }
        .configurationEntry(in:0...2) { step = $0 }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button("Retour") { step -= 1 }
                        .atlantiqueActionStyle(.secondary)
                        .frame(maxWidth: atlantique ? 112 : nil)
                        .formStepMenu(titles: ["Dimensions", "Dalles et trame", "Plénum et suspension", "Résultat"], selection: $step, canShowResult: canSave)
                }
                Spacer()
                Button(step == 3 ? "Enregistrer" : "Continuer") {
                    if step == 3 { attemptSave() }
                    else { step += 1 }
                }
                .atlantiqueActionStyle()
                .disabled(!canContinue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(atlantique ? Atlantique.Palette.blue : Color(.systemBackground))
        }
        .atlantiqueFormPage(atlantique ? stepTitle : "Plafond modulaire (bêta)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing || atlantique {
                ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", action: attemptSave).atlantiqueToolbarAction(primary: true)
                    .disabled(!canSave)
                }.atlantiqueToolbarBackground(atlantique)
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
            if !atlantique || Atlantique.Book.showsAdvancedFormControls { configurationSummarySection }
            quantitySection
        }
    }

    private var dimensionsSection: some View {
        Section {
            if let error = configuration.scanCalculationError { Text(error).foregroundStyle(.orange) }
            if let surfaces = configuration.surveyedSurfaces {
                LabeledContent("Plafonds du relevé", value: "\(surfaces.count)")
                LabeledContent("Surface nette", value: "\(configuration.area.formatted(.number.precision(.fractionLength(2)))) m²")
            } else {
                metricRow("Longueur", value: $configuration.length, unit: "m")
                metricRow("Largeur", value: $configuration.width, unit: "m")
            }
        } header: {
            Text("Dimensions de la pièce").foregroundStyle(atlantique ? Color.white : .secondary)
        } footer: {
            if !atlantique || Atlantique.Book.showsAdvancedFormControls {
            Text(configuration.surveyedSurfaces == nil
                ? "Pièce rectangulaire. Les porteurs sont calculés dans le sens de la plus grande longueur."
                : "Contour et ouvertures repris du relevé. Le quantitatif est recalculé lorsque le plan change.")
            }
        }
    }

    private var tilesSection: some View {
        Section {
            AtlantiqueSegmentedChoice(title: "Format des dalles", options: ModularCeilingTileFormat.allCases.map { ($0, $0.title) }, selection: $configuration.tileFormat)

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
            Text("Dalles et trame T24").foregroundStyle(atlantique ? Color.white : .secondary)
        } footer: {
            Text(configuration.tileFormat == .square600
                 ? "Un luminaire 600 × 600 occupant une maille complète peut être déduit ici."
                 : "Le format 600 × 1200 n’utilise pas d’entretoises de 600 mm. Les équipements intégrés ne sont pas déduits dans cette version simple.")
                .foregroundStyle(atlantique ? Color.white.opacity(0.85) : .secondary)
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
            Text("Passage et démontage des dalles").foregroundStyle(atlantique ? Color.white : .secondary)
        } footer: {
            Text("Le besoin réel dépend de la dalle, de son bord et du système. Plaquisto utilise ici un repère prudent : 15 cm jusqu’à 20 mm d’épaisseur, 20 cm au-delà. La fiche fabricant reste prioritaire.")
                .foregroundStyle(atlantique ? Color.white.opacity(0.85) : .secondary)
        }
    }

    private var quantitySection: some View {
        Section {
            if let error = configuration.scanCalculationError { Text(error).foregroundStyle(.orange) } else {
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
            }
        } header: {
            Text("Quantitatif").foregroundStyle(atlantique ? Color.white : .secondary)
        } footer: {
            Text("Quantités calculées sur une trame T24 standard centrée. Les dalles et profils sont arrondis à l’unité supérieure avec la marge choisie.")
                .foregroundStyle(atlantique ? Color.white.opacity(0.85) : .secondary)
        }
    }

    private var configurationSummarySection: some View {
        Section {
            DisclosureGroup("Configuration retenue", isExpanded: $showsConfiguration) {
                if configuration.surveyedSurfaces == nil {
                    LabeledContent("Dimensions", value: "\(format(configuration.length)) × \(format(configuration.width)) m")
                } else { LabeledContent("Surface du relevé", value: "\(format(configuration.area)) m²") }
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
