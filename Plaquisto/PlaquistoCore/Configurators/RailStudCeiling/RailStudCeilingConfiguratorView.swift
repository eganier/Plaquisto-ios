import SwiftUI

struct RailStudCeilingInsulationConfiguration: Codable, Equatable {
    var seriesID = ""
    var thickness = 0
    var location = "between"
}

struct RailStudCeilingFacingConfiguration: Identifiable, Codable, Equatable {
    var id = UUID()
    var productID = ""
    var dimensionID = ""
    var area = 0.0
}

struct RailStudCeilingQuantity: Identifiable, Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var id: String { "\(name)|\(unit)" }
}

struct RailStudCeilingConfiguration: Codable, Equatable {
    var shape = "horizontal"
    var area = 0.0
    var dimensionsSpecified = true
    var length = 0.0
    var width = 0.0
    var direction = "width"
    var support = "wood"
    var insulationEnabled = true
    var insulationLayers = 1
    var firstInsulation = RailStudCeilingInsulationConfiguration()
    var secondInsulation = RailStudCeilingInsulationConfiguration()
    var vaporBarrier = false
    var extraPlenumCM = 0.0
    var facingLayers = 1
    var firstSkin: [RailStudCeilingFacingConfiguration] = []
    var secondSkin: [RailStudCeilingFacingConfiguration] = []
    var studWidth = 48
    var assembly = "single"
    var frameMode = "selfSupporting"
    var jointTreatment = true
    var compound = "powder"
    var quantities: [RailStudCeilingQuantity] = []
    var effectiveArea: Double { dimensionsSpecified ? length * width : area }
}

private enum LabCeilingShape: String, CaseIterable, Identifiable {
    case horizontal, sloped
    var id: String { rawValue }
    var title: String { self == .horizontal ? "Horizontal" : "Rampant" }
}

private enum LabCeilingSupport: String, CaseIterable, Identifiable {
    case wood, concrete, concreteHollowBlock, lightHollowBlock, metal, hollowCeiling
    var id: String { rawValue }
    var adminID: String {
        switch self {
        case .concreteHollowBlock: "concrete_hollow_block"
        case .lightHollowBlock: "light_hollow_block"
        case .hollowCeiling: "hollow_ceiling"
        default: rawValue
        }
    }
    var title: String {
        switch self {
        case .wood: "Plancher bois"
        case .concrete: "Dalle béton"
        case .concreteHollowBlock: "Plancher hourdis béton"
        case .lightHollowBlock: "Hourdis léger"
        case .metal: "Charpente métallique"
        case .hollowCeiling: "Plafond creux"
        }
    }
    var suspensionFixing: String {
        switch self {
        case .wood: "Demi collier"
        case .concrete: "Cheville et piton"
        case .concreteHollowBlock: "Suspente hourdis à griffe"
        case .lightHollowBlock: "Système compatible pour hourdis léger"
        case .metal: "Suspente bord de tôle"
        case .hollowCeiling: "Cheville à bascule"
        }
    }
    func isAvailable(for shape: LabCeilingShape) -> Bool { shape == .horizontal || self == .wood || self == .metal }
}

private enum LabStud: Int, CaseIterable, Identifiable, Comparable {
    case m48 = 48, m70 = 70, m90 = 90, m100 = 100, m150 = 150
    var id: Int { rawValue }
    var title: String { "M\(rawValue)" }
    var railTitle: String { "R\(rawValue)" }
    var permitsSuspension: Bool { rawValue <= 90 }
    var railFixingMultiplier: Int { rawValue >= 100 ? 2 : 1 }
    var doubleStudScrewMultiplier: Int { rawValue >= 100 ? 2 : 1 }
    static func < (lhs: LabStud, rhs: LabStud) -> Bool { lhs.rawValue < rhs.rawValue }
}

private enum LabStudAssembly: String, CaseIterable, Identifiable {
    case single, double
    var id: String { rawValue }
    var title: String { self == .single ? "Montants simples" : "Montants doublés" }
    var suspensionSpacing: Double { self == .single ? 1.2 : 2.0 }
    var suspensionCapacity: Int { self == .single ? 100 : 160 }
    var suspensionName: String { self == .single ? "Suspente pour montants simples" : "Suspente pour montants dos à dos" }
}

private enum LabFrameMode: String, Identifiable {
    case selfSupporting, suspended
    var id: String { rawValue }
    var title: String { self == .selfSupporting ? "Autoportant" : "Avec suspentes" }
}

private enum LabMechanicalFacing: Hashable {
    case ba13, ba18, doubleBA13, acousticBA13, doubleAcousticBA13
    var title: String {
        switch self {
        case .ba13: "1 × BA13"
        case .ba18: "1 × BA18"
        case .doubleBA13: "2 × BA13"
        case .acousticBA13: "1 × BA13 phonique / ignifuge"
        case .doubleAcousticBA13: "2 × BA13 phonique / ignifuge"
        }
    }
}

private struct LabInsulationSeries: Identifiable, Hashable {
    let id: String
    let material: String
    let lambda: Double
    let density: Double
    let thicknesses: [Int]
    func weight(for thickness: Int) -> Double { Double(thickness) / 1_000 * density }
    func resistance(for thickness: Int) -> Double { Double(thickness) / 1_000 / lambda }
}

private struct LabInsulationSelection: Hashable {
    var seriesID = ""
    var thickness = 0
    var location = "between"
}

private struct LabFacingDimension: Identifiable, Hashable {
    let width: Int
    let length: Int
    var id: String { "\(width)x\(length)" }
    var title: String { "\(width) × \(length) mm" }
    var area: Double { Double(width * length) / 1_000_000 }
}

private struct LabFacingProduct: Identifiable, Hashable {
    let id: String
    let family: String
    let function: String
    let dimensions: [LabFacingDimension]
    var functionTitle: String {
        switch function {
        case "hydrofuge": "Hydrofuge H1"
        case "phonique": "Phonique"
        case "incendie": "Protection incendie"
        case "quatre_bords_amincis": "Quatre bords amincis"
        default: "Standard"
        }
    }
    var mechanicalIsAcoustic: Bool { function == "phonique" || function == "incendie" }
}

private struct LabFacingAllocation: Identifiable, Hashable {
    var id = UUID()
    var productID = ""
    var dimensionID = ""
    var area = 0.0
}

private struct LabSupply: Identifiable {
    let name: String
    var quantity: Double
    let unit: String
    var id: String { "\(name)|\(unit)" }
}

private struct RailStudCeilingSection: Codable {
    let ouvrage: CeilingReferenceRecord?
    let parements: [CeilingReferenceRecord]
    let isolation: [CeilingReferenceRecord]
    let regles: CeilingReferenceRecord?
    let quantitatif: CeilingReferenceRecord?
}

private struct RailStudCeilingEnvelope: Codable { let plafondRailsMontants: RailStudCeilingSection? }

@MainActor
private final class RailStudCeilingReferenceStore: ObservableObject {
    @Published var section: RailStudCeilingSection?
    @Published var isLoading = true
    @Published var error: String?
    private let endpoint = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!

    func load() async {
        isLoading = true; error = nil
        do {
            var request = URLRequest(url: endpoint); request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(RailStudCeilingEnvelope.self, from: data)
            guard let section = decoded.plafondRailsMontants, section.regles != nil, section.quantitatif != nil,
                  !section.parements.isEmpty, !section.isolation.isEmpty else { throw URLError(.zeroByteResource) }
            self.section = section
        } catch {
            self.error = "Connexion à Plaquisto Admin impossible. Vérifiez votre connexion Internet puis réessayez."
        }
        isLoading = false
    }

    var insulation: [LabInsulationSeries] {
        section?.isolation.compactMap { record in
            guard let lambda = record.data["lambda_w_mk"]?.number,
                  let values = record.data["values"]?.array else { return nil }
            let points = values.compactMap { value -> (Int, Double)? in
                guard let object = value.object, let thickness = object["thickness_mm"]?.number,
                      let weight = object["max_weight_kg_m2"]?.number else { return nil }
                return (Int(thickness), weight)
            }
            guard !points.isEmpty else { return nil }
            let density = points.map { $0.1 / (Double($0.0) / 1_000) }.max() ?? 0
            return .init(id: record.id, material: record.data["material"]?.string ?? record.title, lambda: lambda, density: density, thicknesses: points.map(\.0))
        } ?? []
    }

    var facings: [LabFacingProduct] {
        section?.parements.compactMap { record in
            guard let family = record.data["nominal_family"]?.string, ["BA13", "BA18"].contains(family),
                  let function = record.data["function"]?.string,
                  ["standard", "hydrofuge", "phonique", "incendie", "quatre_bords_amincis"].contains(function) else { return nil }
            let dimensions = record.data["dimensions"]?.array?.compactMap { value -> LabFacingDimension? in
                guard let object = value.object, let width = object["width_mm"]?.number,
                      let length = object["length_mm"]?.number else { return nil }
                return .init(width: Int(width), length: Int(length))
            } ?? []
            guard !dimensions.isEmpty else { return nil }
            return .init(id: record.id, family: family, function: function, dimensions: dimensions)
        } ?? []
    }

    func span(_ facing: LabMechanicalFacing, _ stud: LabStud, _ assembly: LabStudAssembly, _ weight: Double) -> Double? {
        guard weight <= number("maximum_insulation_weight_kg_m2", fallback: 15) else { return nil }
        let facingKey: String = switch facing { case .ba13: "ba13"; case .ba18: "ba18"; case .doubleBA13: "double_ba13"; case .acousticBA13: "acoustic_ba13"; case .doubleAcousticBA13: "double_acoustic_ba13" }
        let rows = section?.regles?.data["spans"]?.array ?? []
        guard let row = rows.compactMap(\.object).first(where: {
            $0["assembly"]?.string == assembly.rawValue && $0["facing"]?.string == facingKey && Int($0["stud"]?.number ?? 0) == stud.rawValue
        }), let values = row["spans_m"]?.array?.compactMap(\.number), values.count == 3 else { return nil }
        return values[weight < 6 ? 0 : (weight < 10 ? 1 : 2)]
    }

    func quantity(_ key: String, fallback: Double) -> Double {
        section?.quantitatif?.data["coefficients"]?.object?[key]?.number ?? fallback
    }
    func number(_ key: String, fallback: Double) -> Double {
        section?.regles?.data[key]?.number
            ?? section?.regles?.data["rules"]?.object?[key]?.number
            ?? fallback
    }
    func studValue(_ stud: LabStud, _ key: String, fallback: Double) -> Double {
        let rows = section?.regles?.data["studs"]?.array?.compactMap(\.object) ?? []
        return rows.first(where: { Int($0["width_mm"]?.number ?? 0) == stud.rawValue })?[key]?.number ?? fallback
    }
    func studFlag(_ stud: LabStud, _ key: String, fallback: Bool) -> Bool {
        let rows = section?.regles?.data["studs"]?.array?.compactMap(\.object) ?? []
        return rows.first(where: { Int($0["width_mm"]?.number ?? 0) == stud.rawValue })?[key]?.bool ?? fallback
    }
    func suspensionValue(_ assembly: LabStudAssembly, _ key: String, fallback: Double) -> Double {
        section?.regles?.data["suspensions"]?.object?[assembly.rawValue]?.object?[key]?.number ?? fallback
    }
    func suspensionName(_ assembly: LabStudAssembly) -> String {
        section?.regles?.data["suspensions"]?.object?[assembly.rawValue]?.object?["name"]?.string ?? assembly.suspensionName
    }
    private func supportData(_ support: LabCeilingSupport) -> [String: CeilingJSONValue]? {
        let rows = section?.regles?.data["supports"]?.array?.compactMap(\.object) ?? []
        return rows.first { $0["id"]?.string == support.adminID }
    }
    func supportTitle(_ support: LabCeilingSupport) -> String {
        supportData(support)?["title"]?.string ?? support.title
    }
    func supportFixing(_ support: LabCeilingSupport) -> String {
        supportData(support)?["fixing"]?.string ?? support.suspensionFixing
    }
    func supportIsAvailable(_ support: LabCeilingSupport, for shape: LabCeilingShape) -> Bool {
        supportData(support)?[shape == .horizontal ? "horizontal" : "sloped"]?.bool ?? support.isAvailable(for: shape)
    }
    var workTitle: String { section?.ouvrage?.title ?? "Plafond sur ossature rails et montants" }
}

struct RailStudCeilingConfiguratorView: View {
    @Environment(\.layoutCoveringAreaRatio) private var coveringAreaRatio
    @StateObject private var references = RailStudCeilingReferenceStore()
    @State private var step = 0
    @State private var shape: LabCeilingShape = .horizontal
    @State private var area = 0.0
    @State private var dimensionsSpecified = true
    @State private var length = 0.0
    @State private var width = 0.0
    @State private var direction = "width"
    @State private var support: LabCeilingSupport = .wood
    @State private var insulationEnabled = true
    @State private var insulationLayers = 1
    @State private var firstInsulation = LabInsulationSelection()
    @State private var secondInsulation = LabInsulationSelection()
    @State private var vaporBarrier = false
    @State private var extraPlenumCM = 0.0
    @State private var facingLayers = 1
    @State private var firstSkin: [LabFacingAllocation] = []
    @State private var secondSkin: [LabFacingAllocation] = []
    @State private var stud: LabStud = .m48
    @State private var assembly: LabStudAssembly = .single
    @State private var frameMode: LabFrameMode = .selfSupporting
    @State private var jointTreatment = true
    @State private var compound = "powder"
    @State private var showDimensionsAlert = false
    @State private var showVaporAlert = false
    @State private var showingResult = false
    @State private var configurationExpanded = false
    private let onSave: ((RailStudCeilingConfiguration) -> Void)?
    private let isEditing: Bool

    private let steps = ["Dimensions","Isolation","Parements","Ossature","Support","Plénum","Suspension","Bandes à joint","Résultat"]

    init(initialConfiguration: RailStudCeilingConfiguration? = nil, startsAtResult: Bool = false, onSave: ((RailStudCeilingConfiguration) -> Void)? = nil) {
        let value = initialConfiguration ?? RailStudCeilingConfiguration()
        _step = State(initialValue: startsAtResult ? 8 : 0)
        _shape = State(initialValue: LabCeilingShape(rawValue: value.shape) ?? .horizontal)
        _area = State(initialValue: value.area)
        _dimensionsSpecified = State(initialValue: value.dimensionsSpecified)
        _length = State(initialValue: value.length)
        _width = State(initialValue: value.width)
        _direction = State(initialValue: value.direction)
        _support = State(initialValue: LabCeilingSupport(rawValue: value.support) ?? .wood)
        _insulationEnabled = State(initialValue: value.insulationEnabled)
        _insulationLayers = State(initialValue: value.insulationLayers)
        _firstInsulation = State(initialValue: .init(seriesID: value.firstInsulation.seriesID, thickness: value.firstInsulation.thickness, location: value.firstInsulation.location))
        _secondInsulation = State(initialValue: .init(seriesID: value.secondInsulation.seriesID, thickness: value.secondInsulation.thickness, location: value.secondInsulation.location))
        _vaporBarrier = State(initialValue: value.vaporBarrier)
        _extraPlenumCM = State(initialValue: value.extraPlenumCM)
        _facingLayers = State(initialValue: value.facingLayers)
        _firstSkin = State(initialValue: value.firstSkin.map { .init(id: $0.id, productID: $0.productID, dimensionID: $0.dimensionID, area: $0.area) })
        _secondSkin = State(initialValue: value.secondSkin.map { .init(id: $0.id, productID: $0.productID, dimensionID: $0.dimensionID, area: $0.area) })
        _stud = State(initialValue: LabStud(rawValue: value.studWidth) ?? .m48)
        _assembly = State(initialValue: LabStudAssembly(rawValue: value.assembly) ?? .single)
        _frameMode = State(initialValue: LabFrameMode(rawValue: value.frameMode) ?? .selfSupporting)
        _jointTreatment = State(initialValue: value.jointTreatment)
        _compound = State(initialValue: value.compound)
        _showingResult = State(initialValue: startsAtResult)
        self.onSave = onSave
        self.isEditing = initialConfiguration != nil
    }
    private var supports: [LabCeilingSupport] { LabCeilingSupport.allCases.filter { references.supportIsAvailable($0, for: shape) } }
    private var insulation: [LabInsulationSeries] { references.insulation.filter { shape == .horizontal || abs($0.lambda - 0.040) > 0.0001 } }
    private var insulationMaterials: [String] {
        Array(Set(insulation.map(\.material))).sorted { lhs, rhs in
            if lhs == "Laine de verre" { return true }
            if rhs == "Laine de verre" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
    private func series(_ id: String) -> LabInsulationSeries? { insulation.first { $0.id == id } }
    private var firstSeries: LabInsulationSeries? { series(firstInsulation.seriesID) }
    private var secondSeries: LabInsulationSeries? { series(secondInsulation.seriesID) }
    private var effectiveArea: Double { dimensionsSpecified ? length * width : area }
    private var span: Double { direction == "length" ? length : width }
    private var distributionLength: Double { direction == "length" ? width : length }
    private var studSpacing: Double { references.number("stud_spacing_m", fallback: 0.60) }
    private var studBays: Int { distributionLength > 0 ? Int(ceil(distributionLength / studSpacing)) : 0 }
    private var studLines: Int { studBays + 1 }
    private var studPieces: Int { assembly == .single ? studLines : studBays * 2 }
    private var frameWasteFactor: Double { references.quantity("frame_waste_factor", fallback: 1.05) }
    private var studLength: Double { Double(studPieces) * span * frameWasteFactor }
    private var railLength: Double { 2 * (length + width) * frameWasteFactor }
    private var insulationWeight: Double {
        guard insulationEnabled else { return 0 }
        return (firstSeries?.weight(for: firstInsulation.thickness) ?? 0) + (insulationLayers == 2 ? secondSeries?.weight(for: secondInsulation.thickness) ?? 0 : 0)
    }
    private var thermalResistance: Double {
        guard insulationEnabled else { return 0 }
        return (firstSeries?.resistance(for: firstInsulation.thickness) ?? 0) + (insulationLayers == 2 ? secondSeries?.resistance(for: secondInsulation.thickness) ?? 0 : 0)
    }
    private var isWoodSupport: Bool { support == .wood }
    private var totalInsulationThicknessMM: Int {
        guard insulationEnabled else { return 0 }
        return firstInsulation.thickness + (insulationLayers == 2 ? secondInsulation.thickness : 0)
    }
    private var minimumPlenumCM: Double {
        guard insulationEnabled else { return 0 }
        if !isWoodSupport { return Double(totalInsulationThicknessMM) / 10 }
        let firstBelow = firstInsulation.location == "below" ? firstInsulation.thickness : 0
        let secondBelow = insulationLayers == 2 && secondInsulation.location == "below" ? secondInsulation.thickness : 0
        return Double(firstBelow + secondBelow) / 10
    }
    private var plenumCM: Double { minimumPlenumCM + extraPlenumCM }
    private var mechanicalFacing: LabMechanicalFacing {
        let products = (firstSkin + (facingLayers == 2 ? secondSkin : [])).compactMap { product($0.productID) }
        if facingLayers == 1 {
            if products.contains(where: { $0.family == "BA18" }) { return .ba18 }
            return products.contains(where: \.mechanicalIsAcoustic) ? .acousticBA13 : .ba13
        }
        return products.contains(where: \.mechanicalIsAcoustic) ? .doubleAcousticBA13 : .doubleBA13
    }
    private var maximumSpan: Double? { references.span(mechanicalFacing, stud, assembly, insulationWeight) }
    private var suspensionAllowed: Bool { shape == .horizontal && references.studFlag(stud, "suspension_allowed", fallback: stud.permitsSuspension) }
    private var suspensionSpacing: Double { references.suspensionValue(assembly, "spacing_m", fallback: assembly.suspensionSpacing) }
    private var suspensionCapacity: Int { Int(references.suspensionValue(assembly, "capacity_kg", fallback: Double(assembly.suspensionCapacity))) }
    private var suspensionName: String { references.suspensionName(assembly) }
    private var frameIsValid: Bool {
        guard maximumSpan != nil, insulationWeight <= 15 else { return false }
        return frameMode == .suspended ? suspensionAllowed : span <= (maximumSpan ?? 0)
    }
    private var suspensionCount: Int {
        guard frameMode == .suspended, suspensionAllowed, span > 0 else { return 0 }
        return studLines * Int(ceil(span / suspensionSpacing))
    }
    private var visibleStepIndices: [Int] {
        frameMode == .selfSupporting ? [0, 1, 2, 3, 7, 8] : Array(0...8)
    }
    private var visibleStepPosition: Int {
        visibleStepIndices.firstIndex(of: step) ?? 0
    }

    var body: some View {
        Group {
            if references.isLoading {
                ProgressView("Chargement depuis Plaquisto Admin…")
            } else if let error = references.error {
                ContentUnavailableView("Données indisponibles", systemImage: "icloud.slash", description: Text(error))
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    Form { stepContent }
                    footer
                }
            }
        }
        .navigationBarBackButtonHidden()
        .tint(Color(red: 0.12, green: 0.38, blue: 0.29))
        .toolbar {
            if isEditing, let onSave {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { onSave(configurationSnapshot()) }
                }
            }
        }
        .alert("Dimensions non renseignées", isPresented: $showDimensionsAlert) {
            Button("Renseigner les dimensions", role: .cancel) { dimensionsSpecified = true }
            Button("Continuer avec une estimation") {
                let side = (sqrt(area) * 100).rounded() / 100
                length = side; width = side; direction = "width"; completeAdvance()
            }
        } message: { Text("Le calcul métrique est plus précis avec la longueur et la largeur. Plaquisto peut estimer un plafond carré à partir de la surface.") }
        .alert("Pare-vapeur fortement recommandé", isPresented: $showVaporAlert) {
            Button("Prévoir un pare-vapeur", role: .cancel) { vaporBarrier = true }
            Button("Continuer sans pare-vapeur") { completeAdvance() }
        } message: { Text("La pose d’un pare-vapeur adapté est fortement recommandée en plafond rampant. Vérifiez les règles applicables avant de poursuivre sans.") }
        .task {
            if references.section == nil { await references.load() }
            normalizeSelections()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OUVRAGE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(shape == .horizontal ? references.workTitle : "Plafond rampant sur ossature rails et montants").font(.title2.bold())
            Label("Données synchronisées avec Plaquisto Admin", systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.green)
            ProgressView(value: Double(visibleStepPosition + 1), total: Double(visibleStepIndices.count))
            Text("Étape \(visibleStepPosition + 1) sur \(visibleStepIndices.count) · \(steps[step])").font(.caption).foregroundStyle(.secondary)
        }.padding()
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button("Retour") { goBack() }.buttonStyle(.bordered) }
            Spacer()
            if step < steps.count - 1 {
                Button("Continuer") { advance() }.buttonStyle(.borderedProminent).disabled(!canContinue)
            } else if let onSave {
                Button("Enregistrer") { onSave(configurationSnapshot()) }.buttonStyle(.borderedProminent)
            } else if showingResult {
                Button("Recommencer") { reset() }.buttonStyle(.borderedProminent)
            } else {
                Button("Valider la configuration") { showingResult = true }.buttonStyle(.borderedProminent)
            }
        }.padding().background(.bar)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: dimensionsStep
        case 1: insulationStep
        case 2: facingsStep
        case 3: frameStep
        case 4: supportStep
        case 5: plenumStep
        case 6: suspensionStep
        case 7: jointsStep
        default: resultStep
        }
    }

    private var dimensionsStep: some View {
        Group {
            Section {
                Picker("Type de plafond", selection: $shape) { ForEach(LabCeilingShape.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of: shape) { _, _ in normalizeSelections() }
            } header: { Text("Type de plafond") }
            Section {
                Toggle("Préciser la longueur et la largeur", isOn: $dimensionsSpecified)
                if dimensionsSpecified {
                    LabMeasureField(label: "Longueur", value: $length, unit: "m").onChange(of: length) { _, _ in updateArea() }
                    LabMeasureField(label: "Largeur", value: $width, unit: "m").onChange(of: width) { _, _ in updateArea() }
                    if length > 0, width > 0 {
                        Picker("Sens des montants", selection: $direction) {
                            Text("Dans la longueur").tag("length"); Text("Dans la largeur").tag("width")
                        }
                    }
                }
            } header: {
                Text("Dimensions de l’ouvrage")
            } footer: {
                Text("Les dimensions calculent précisément les montants et le périmètre des rails.")
            }
            Section("Surface de l’ouvrage") {
                if dimensionsSpecified {
                    LabeledContent("Surface calculée", value: "\(format(area)) m²")
                } else {
                    LabMeasureField(label: "Surface", value: $area, unit: "m²")
                }
            }
        }
    }

    private var supportStep: some View {
        Group {
            Section("Support du plafond") {
                Picker("Type de support", selection: $support) { ForEach(supports) { Text(references.supportTitle($0)).tag($0) } }
                    .onChange(of: support) { _, _ in normalizeInsulationLocations() }
                if isWoodSupport && insulationEnabled {
                    Picker("Emplacement de la première couche", selection: $firstInsulation.location) {
                        Text(shape == .sloped ? "Entre les chevrons" : "Entre les solives").tag("between")
                        Text(shape == .sloped ? "Sous les chevrons" : "Sous les solives").tag("below")
                    }
                    if insulationLayers == 2 {
                        Picker("Emplacement de la deuxième couche", selection: $secondInsulation.location) {
                            Text(shape == .sloped ? "Entre les chevrons" : "Entre les solives").tag("between")
                            Text(shape == .sloped ? "Sous les chevrons" : "Sous les solives").tag("below")
                        }
                    }
                }
            }
            Section { Text(shape == .sloped ? "Le rampant est configuré uniquement en autoportant, sur bois ou charpente métallique." : "Le support détermine la fixation à utiliser si le plafond reçoit des suspentes.").foregroundStyle(.secondary) }
        }
    }

    private var insulationStep: some View {
        Group {
            Section {
                Toggle("Prévoir une isolation", isOn: $insulationEnabled)
                if insulationEnabled {
                    Picker("Nombre de couches", selection: $insulationLayers) { Text("Une couche").tag(1); Text("Deux couches").tag(2) }
                        .pickerStyle(.segmented).onChange(of: insulationLayers) { _, value in if value == 2 { secondInsulation = firstInsulation } }
                    insulationEditor("Première couche", $firstInsulation)
                    if insulationLayers == 2 { insulationEditor("Deuxième couche", $secondInsulation) }
                    LabeledContent("Poids maximal retenu", value: "\(format(insulationWeight)) kg/m²")
                    LabeledContent("Résistance thermique totale", value: "R = \(format(thermalResistance)) m²·K/W")
                    if insulationWeight > 15 { Label("Le poids dépasse les 15 kg/m² couverts par le tableau de portées.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            } header: { Text("Isolation") } footer: { Text(shape == .sloped ? "Le lambda 0,040 est exclu en rampant. La deuxième couche reprend par défaut la première mais reste modifiable." : "La deuxième couche reprend par défaut la première mais reste modifiable.") }
            Section("Pare-vapeur") {
                Toggle("Prévoir la pose d’un pare-vapeur", isOn: $vaporBarrier)
                if shape == .sloped && !vaporBarrier { Label("Pose fortement recommandée en rampant.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
        }
    }

    private func insulationEditor(_ title: String, _ selection: Binding<LabInsulationSelection>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Picker("Type d’isolant", selection: materialBinding(selection)) { ForEach(insulationMaterials, id: \.self) { Text($0).tag($0) } }
            Picker("Lambda", selection: selection.seriesID) {
                ForEach(seriesForMaterial(material(selection.wrappedValue))) { Text("λ \($0.lambda.formatted(.number.precision(.fractionLength(3)))) W/(m·K)").tag($0.id) }
            }.onChange(of: selection.wrappedValue.seriesID) { _, _ in normalizeInsulation(selection) }
            if let chosen = series(selection.wrappedValue.seriesID) {
                Picker("Épaisseur", selection: selection.thickness) {
                    ForEach(chosen.thicknesses, id: \.self) { Text("\($0) mm — R = \(format(chosen.resistance(for: $0)))").tag($0) }
                }
            }
        }
    }

    private var plenumStep: some View {
        Group {
            Section(plenumTitle) {
                LabeledContent("Plénum minimal calculé", value: "\(format(minimumPlenumCM)) cm")
                LabMeasureField(label: "Marge supplémentaire", value: $extraPlenumCM, unit: "cm")
                LabeledContent("Plénum retenu", value: "\(format(plenumCM)) cm")
            }
            Section {
                Label(isWoodSupport
                      ? "Sur un plancher bois, le minimum intègre uniquement l’isolant placé sous les solives ou les chevrons."
                      : "Sur ce support, le minimum intègre toute l’épaisseur d’isolant sélectionnée.",
                      systemImage: "info.circle")
                Text("Vous pouvez ajouter une marge pour les réseaux, gaines, canalisations ou spots.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var facingsStep: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Nombre de peaux")
                card { Picker("Nombre de parements", selection: $facingLayers) { Text("Simple peau").tag(1); Text("Double peau").tag(2) }.pickerStyle(.segmented).onChange(of: facingLayers) { _, _ in normalizeFacings() } }
                skinEditor("Première peau", $firstSkin)
                if facingLayers == 2 { skinEditor("Deuxième peau", $secondSkin) }
            }.padding(.vertical, 6)
        }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
    }

    private func skinEditor(_ title: String, _ allocations: Binding<[LabFacingAllocation]>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
            ForEach(allocations.wrappedValue.indices, id: \.self) { facingCard(allocations[$0], allocations) }
            Button("Ajouter un autre type de parement") { allocations.wrappedValue.append(defaultAllocation(0)) }.buttonStyle(.borderless).tint(.green).padding(.horizontal, 12)
            allocationStatus(allocations.wrappedValue)
        }
    }

    private func facingCard(_ allocation: Binding<LabFacingAllocation>, _ allocations: Binding<[LabFacingAllocation]>) -> some View {
        card {
            Picker("Type de plaque", selection: familyBinding(allocation)) { ForEach(facingFamilies, id: \.self) { Text($0).tag($0) } }
            Divider()
            Picker("Fonction", selection: allocation.productID) { ForEach(products(family(allocation.wrappedValue))) { Text($0.functionTitle).tag($0.id) } }
                .onChange(of: allocation.wrappedValue.productID) { _, _ in allocation.wrappedValue.dimensionID = preferredDimension(product(allocation.wrappedValue.productID))?.id ?? "" }
            Divider()
            Picker("Dimension", selection: allocation.dimensionID) { ForEach(product(allocation.wrappedValue.productID)?.dimensions ?? []) { Text($0.title).tag($0.id) } }
            Divider()
            LabMeasureField(label: "Surface attribuée", value: allocation.area, unit: "m²")
            if allocations.wrappedValue.count > 1 {
                Divider()
                Button("Supprimer ce type", role: .destructive) {
                    let allocationID = allocation.wrappedValue.id
                    allocations.wrappedValue.removeAll { $0.id == allocationID }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var frameStep: some View {
        Group {
            Section {
                Picker("Largeur du montant", selection: $stud) {
                    ForEach(LabStud.allCases) { option in
                        HStack {
                            Text(option.title)
                            if !studIsSufficient(option) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .tag(option)
                    }
                }
                    .onChange(of: stud) { _, _ in if !suspensionAllowed { frameMode = .selfSupporting } }
                Picker("Disposition", selection: $assembly) { ForEach(LabStudAssembly.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Picker("Type de montage", selection: $frameMode) {
                    Text("Autoportant").tag(LabFrameMode.selfSupporting)
                    if suspensionAllowed { Text("Avec suspentes").tag(LabFrameMode.suspended) }
                }.pickerStyle(.segmented)
            } header: { Text("Ossature") }
            Section {
                LabeledContent("Parement retenu", value: mechanicalFacing.title)
                LabeledContent("Poids d’isolant", value: "\(format(insulationWeight)) kg/m²")
                LabeledContent("Portée réelle", value: "\(format(span)) m")
                LabeledContent("Portée maximale", value: maximumSpan.map { "\(format($0)) m" } ?? "Non couverte")
                if frameIsValid { Label(frameMode == .selfSupporting ? "Configuration autoportante compatible" : "Configuration suspendue compatible", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                else { Label(frameWarning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            } header: { Text("Vérification du montage") } footer: { Text("La portée dépend du montant, de sa disposition, du parement et du poids total de l’isolation.") }
        }
    }

    private var suspensionStep: some View {
        Group {
            if frameMode == .suspended {
                Section("Système de suspension") {
                    LabeledContent("Suspente", value: suspensionName)
                    LabeledContent("Fixation au support", value: references.supportFixing(support))
                    LabeledContent("Liaison", value: "Tige filetée Ø 6 mm")
                    LabeledContent("Espacement maximal", value: "\(format(suspensionSpacing)) m")
                    LabeledContent("Charge admissible", value: "\(suspensionCapacity) kg par suspente")
                    LabeledContent("Nombre de suspentes", value: "\(suspensionCount)")
                }
                Section { Text(assembly == .single ? "2 vis TRPF 13 superposées par suspente." : "1 vis TRPF 13 par suspente.").foregroundStyle(.secondary) }
            } else {
                Section("Montage autoportant") { Label("Aucune suspente ni tige filetée n’est nécessaire.", systemImage: "checkmark.circle"); Text("Les montants portent entre les rails périphériques.").foregroundStyle(.secondary) }
            }
        }
    }

    private var jointsStep: some View {
        Group {
            Section("Traitement des bandes à joint") {
                Toggle("Prévoir le traitement des bandes", isOn: $jointTreatment)
                if jointTreatment { Picker("Type d’enduit", selection: $compound) { Text("Enduit en poudre").tag("powder"); Text("Enduit en pâte").tag("paste") } }
            }
            Section { Text(jointTreatment ? "Les bandes et l’enduit seront ajoutés au quantitatif." : "Aucune bande ni aucun enduit ne sera ajouté.").foregroundStyle(.secondary) }
        }
    }

    private var resultStep: some View {
        Group {
            Section { Label("Configuration compatible", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green); Text("\(format(effectiveArea)) m² · \(shape.title.lowercased()) · \(stud.title) · \(assembly.title.lowercased())").foregroundStyle(.secondary) }
            Section("Quantitatif") { ForEach(quantities) { LabeledContent($0.name, value: quantityTitle($0)) } }
            Section {
                DisclosureGroup("Configuration retenue", isExpanded: $configurationExpanded) {
                    editableConfigurationRow("Dimensions", value: "\(format(length)) × \(format(width)) m", targetStep: 0)
                    editableConfigurationRow("Portée", value: "\(format(span)) m", targetStep: 0)
                    editableConfigurationRow("Parement mécanique", value: mechanicalFacing.title, targetStep: 2)
                    editableConfigurationRow("Ossature", value: "\(stud.railTitle) + \(stud.title)", targetStep: 3)
                    editableConfigurationRow("Montage", value: frameMode.title, targetStep: 3)
                    if frameMode == .suspended { editableConfigurationRow("Plénum", value: "\(format(plenumCM)) cm", targetStep: 5) }
                    if insulationEnabled {
                        editableConfigurationRow("Isolation", value: insulationLayers == 1 ? "Une couche" : "Deux couches", targetStep: 1)
                        editableConfigurationRow("R total", value: "\(format(thermalResistance)) m²·K/W", targetStep: 1)
                    }
                    editableConfigurationRow("Pare-vapeur", value: vaporBarrier ? "Oui" : "Non", targetStep: 1)
                }
            }
        }
    }

    private func editableConfigurationRow(_ title: String, value: String, targetStep: Int) -> some View {
        Button {
            withAnimation {
                showingResult = false
                step = targetStep
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canContinue: Bool {
        switch step {
        case 0: return dimensionsSpecified ? length > 0 && width > 0 : area > 0
        case 1:
            guard insulationEnabled else { return true }
            return firstSeries?.thicknesses.contains(firstInsulation.thickness) == true && (insulationLayers == 1 || secondSeries?.thicknesses.contains(secondInsulation.thickness) == true) && insulationWeight <= 15
        case 2: return allocationsValid(firstSkin) && (facingLayers == 1 || allocationsValid(secondSkin))
        case 3: return frameIsValid
        case 4: return frameMode == .selfSupporting || supports.contains(support)
        case 5: return frameMode == .selfSupporting || extraPlenumCM >= 0
        default: return true
        }
    }

    private func advance() {
        if step == 0 && !dimensionsSpecified { showDimensionsAlert = true }
        else if step == 1 && shape == .sloped && !vaporBarrier { showVaporAlert = true }
        else { completeAdvance() }
    }
    private func completeAdvance() {
        if step == 1 { ensureFacings() }
        else if step == 2 { prepareFrameDefault() }
        let next = visibleStepIndices.first(where: { $0 > step }) ?? step
        withAnimation { step = next }
    }
    private func goBack() {
        showingResult = false
        let previous = visibleStepIndices.last(where: { $0 < step }) ?? 0
        withAnimation { step = previous }
    }
    private func normalizeSelections() {
        if !supports.contains(support) { support = supports.first ?? .wood }
        if shape == .sloped {
            if abs((firstSeries?.lambda ?? 0) - 0.040) < 0.0001 { firstInsulation = .init() }
            if abs((secondSeries?.lambda ?? 0) - 0.040) < 0.0001 { secondInsulation = .init() }
            frameMode = .selfSupporting
        }
        if firstSeries == nil, let first = preferredInsulationSeries { firstInsulation = .init(seriesID: first.id, thickness: first.thicknesses.first ?? 0) }
        if insulationLayers == 2, secondSeries == nil { secondInsulation = firstInsulation }
        normalizeInsulationLocations()
    }
    private func normalizeInsulationLocations() {
        guard !isWoodSupport else { return }
        firstInsulation.location = "below"
        secondInsulation.location = "below"
    }
    private func normalizeInsulation(_ selection: Binding<LabInsulationSelection>) {
        guard let chosen = series(selection.wrappedValue.seriesID), !chosen.thicknesses.contains(selection.wrappedValue.thickness) else { return }
        selection.wrappedValue.thickness = chosen.thicknesses.first ?? 0
    }
    private var preferredInsulationSeries: LabInsulationSeries? {
        insulation.first(where: { $0.material == "Laine de verre" && abs($0.lambda - 0.035) < 0.0001 })
            ?? insulation.first(where: { $0.material == "Laine de verre" })
            ?? insulation.first
    }
    private func seriesForMaterial(_ material: String) -> [LabInsulationSeries] { insulation.filter { $0.material == material }.sorted { $0.lambda < $1.lambda } }
    private func material(_ selection: LabInsulationSelection) -> String { series(selection.seriesID)?.material ?? insulationMaterials.first ?? "" }
    private func materialBinding(_ selection: Binding<LabInsulationSelection>) -> Binding<String> {
        Binding(get: { material(selection.wrappedValue) }, set: { value in
            let target = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains("laine de bois") ? 0.036 : 0.035
            let options = seriesForMaterial(value)
            guard let first = options.first(where: { abs($0.lambda - target) < 0.0001 }) ?? options.first else { return }
            selection.wrappedValue.seriesID = first.id; selection.wrappedValue.thickness = first.thicknesses.first ?? 0
        })
    }
    private var plenumTitle: String {
        let structure = support == .metal ? "la structure porteuse" : (shape == .sloped ? "les chevrons" : "les solives")
        return "Plénum (espace entre la partie basse de \(structure) et la partie supérieure du BA13)"
    }
    private func ensureFacings() {
        if firstSkin.isEmpty { firstSkin = [defaultAllocation(effectiveArea)] }
        if facingLayers == 2 && secondSkin.isEmpty { secondSkin = [defaultAllocation(effectiveArea)] }
        normalizeFacings()
    }
    private func normalizeFacings() {
        guard facingLayers == 2 else { return }
        firstSkin = ba13Only(firstSkin); secondSkin = ba13Only(secondSkin.isEmpty ? [defaultAllocation(effectiveArea)] : secondSkin)
    }
    private func ba13Only(_ values: [LabFacingAllocation]) -> [LabFacingAllocation] {
        values.map { value in
            guard product(value.productID)?.family != "BA13" else { return value }
            let selected = products("BA13").first(where: { $0.function == "standard" }) ?? products("BA13").first
            var next = value; next.productID = selected?.id ?? ""; next.dimensionID = preferredDimension(selected)?.id ?? ""; return next
        }
    }
    private func defaultAllocation(_ area: Double) -> LabFacingAllocation {
        let selected = products("BA13").first(where: { $0.function == "standard" }) ?? products("BA13").first
        return .init(productID: selected?.id ?? "", dimensionID: preferredDimension(selected)?.id ?? "", area: area)
    }
    private var facingFamilies: [String] { facingLayers == 2 ? ["BA13"] : ["BA13","BA18"] }
    private func product(_ id: String) -> LabFacingProduct? { references.facings.first { $0.id == id } }
    private func products(_ family: String) -> [LabFacingProduct] { references.facings.filter { $0.family == family } }
    private func family(_ allocation: LabFacingAllocation) -> String { product(allocation.productID)?.family ?? "BA13" }
    private func familyBinding(_ allocation: Binding<LabFacingAllocation>) -> Binding<String> {
        Binding(get: { family(allocation.wrappedValue) }, set: { value in
            guard let next = products(value).first else { return }
            allocation.wrappedValue.productID = next.id; allocation.wrappedValue.dimensionID = preferredDimension(next)?.id ?? ""
        })
    }
    private func preferredDimension(_ product: LabFacingProduct?) -> LabFacingDimension? {
        guard let product else { return nil }
        let spacingMM = studSpacing * 1_000
        return product.dimensions.sorted { lhs, rhs in
            let leftWidthPenalty = abs(Double(lhs.width - 1_200))
            let rightWidthPenalty = abs(Double(rhs.width - 1_200))
            if leftWidthPenalty != rightWidthPenalty { return leftWidthPenalty < rightWidthPenalty }
            let leftMultiple = abs(Double(lhs.length).truncatingRemainder(dividingBy: spacingMM)) < 0.1
            let rightMultiple = abs(Double(rhs.length).truncatingRemainder(dividingBy: spacingMM)) < 0.1
            if leftMultiple != rightMultiple { return leftMultiple }
            return abs(lhs.length - 2_400) < abs(rhs.length - 2_400)
        }.first
    }
    private func allocationsValid(_ values: [LabFacingAllocation]) -> Bool {
        !values.isEmpty && values.allSatisfy { allocation in
            allocation.area > 0 && product(allocation.productID)?.dimensions.contains(where: { $0.id == allocation.dimensionID }) == true
        } && abs(values.reduce(0) { $0 + $1.area } - effectiveArea) < 0.01
    }
    private func prepareFrameDefault() {
        stud = .m48; assembly = .single; frameMode = .selfSupporting
        if frameIsValid { return }; assembly = .double; if frameIsValid { return }
        for candidate in LabStud.allCases.dropFirst() {
            stud = candidate; assembly = .single; if frameIsValid { return }
            assembly = .double; if frameIsValid { return }
        }
        stud = .m48; assembly = .single; if suspensionAllowed { frameMode = .suspended }
    }
    private func studIsSufficient(_ candidate: LabStud) -> Bool {
        guard insulationWeight <= 15,
              let candidateSpan = references.span(mechanicalFacing, candidate, assembly, insulationWeight) else { return false }
        if frameMode == .suspended {
            return shape == .horizontal && candidate.permitsSuspension
        }
        return span <= candidateSpan
    }
    private var frameWarning: String {
        if insulationWeight > 15 { return "Le poids d’isolant dépasse les données couvertes." }
        if frameMode == .suspended && !suspensionAllowed { return "Les suspentes sont réservées aux plafonds horizontaux en M48, M70 ou M90." }
        if assembly == .single, let value = references.span(mechanicalFacing, stud, .double, insulationWeight), span <= value { return "La portée dépasse \(format(maximumSpan ?? 0)) m. Passez en montants doublés." }
        for candidate in LabStud.allCases where candidate > stud {
            if let value = references.span(mechanicalFacing, candidate, assembly, insulationWeight), span <= value { return "La portée dépasse \(format(maximumSpan ?? 0)) m. Passez au minimum en \(candidate.title)." }
        }
        return shape == .horizontal && stud.permitsSuspension ? "La portée autoportante est insuffisante. Utilisez des suspentes." : "Aucune configuration autoportante ne couvre cette portée."
    }

    private var quantities: [LabSupply] {
        var result: [LabSupply] = []
        for allocation in firstSkin + (facingLayers == 2 ? secondSkin : []) {
            guard let facing = product(allocation.productID), let dimension = facing.dimensions.first(where: { $0.id == allocation.dimensionID }) else { continue }
            result.append(.init(name: "\(facing.family) \(facing.functionTitle) · \(dimension.title)", quantity: ceil(allocation.area * coveringAreaRatio * references.quantity("plate_m2_m2", fallback: 1.05) / dimension.area), unit: "plaque(s)"))
        }
        result += [.init(name: "Montant \(stud.title)", quantity: studLength, unit: "ml"), .init(name: "Rail \(stud.railTitle)", quantity: railLength, unit: "ml")]
        let railFixingSpacing = references.quantity("rail_fixing_spacing_m", fallback: 0.60)
        let railFixingMultiplier = references.studValue(stud, "rail_fixing_multiplier", fallback: Double(stud.railFixingMultiplier))
        result.append(.init(name: "Fixations des rails au gros œuvre", quantity: ceil(2 * (length + width) / railFixingSpacing) * railFixingMultiplier, unit: "unité"))
        if railFixingMultiplier > 1 { result.append(.init(name: "Vis TRPF 25 · liaison rail/montant", quantity: Double(studPieces * 2), unit: "unité")) }
        if assembly == .double {
            let screwSpacing = references.quantity("double_stud_screw_spacing_m", fallback: 0.40)
            let multiplier = Int(references.studValue(stud, "double_stud_screw_multiplier", fallback: Double(stud.doubleStudScrewMultiplier)))
            let screws = Double(max(0, studBays - 1) * Int(ceil(span / screwSpacing)) * multiplier)
            result.append(.init(name: "Vis TRPF 13 · solidarisation des montants", quantity: screws, unit: "unité"))
        }
        if frameMode == .suspended {
            let fixingScrews = Int(references.suspensionValue(assembly, "fixing_screws", fallback: assembly == .single ? 2 : 1))
            result += [.init(name: suspensionName, quantity: Double(suspensionCount), unit: "unité"), .init(name: references.supportFixing(support), quantity: Double(suspensionCount), unit: "unité"), .init(name: "Tige filetée Ø 6 mm", quantity: (plenumCM / 100 + references.number("rod_extra_length_m", fallback: 0.05)) * Double(suspensionCount), unit: "ml"), .init(name: "Vis TRPF 13 · fixation des suspentes", quantity: Double(suspensionCount * fixingScrews), unit: "unité")]
        }
        if insulationEnabled {
            let insulationFactor = references.quantity("insulation_m2_m2", fallback: 1.05)
            if let firstSeries { result.append(.init(name: "\(firstSeries.material) · λ \(lambda(firstSeries.lambda)) · \(firstInsulation.thickness) mm", quantity: effectiveArea * coveringAreaRatio * insulationFactor, unit: "m²")) }
            if insulationLayers == 2, let secondSeries { result.append(.init(name: "\(secondSeries.material) · λ \(lambda(secondSeries.lambda)) · \(secondInsulation.thickness) mm", quantity: effectiveArea * coveringAreaRatio * insulationFactor, unit: "m²")) }
        }
        if vaporBarrier { result += [.init(name: "Pare-vapeur", quantity: effectiveArea * references.quantity("vapor_barrier_m2_m2", fallback: 1.2), unit: "m²"), .init(name: "Scotch double-face", quantity: (assembly == .single ? studLength : studLength / 2) * references.quantity("double_sided_tape_factor", fallback: 1.1), unit: "ml")] }
        if facingLayers == 1 { result.append(.init(name: "Vis TTPC · parement", quantity: effectiveArea * references.quantity("ttpc_single_unit_m2", fallback: 15), unit: "unité")) }
        else { result += [.init(name: "Vis TTPC · première peau", quantity: effectiveArea * references.quantity("ttpc_first_double_unit_m2", fallback: 3), unit: "unité"), .init(name: "Vis TTPC · deuxième peau", quantity: effectiveArea * references.quantity("ttpc_second_double_unit_m2", fallback: 15), unit: "unité")] }
        if jointTreatment { result += [.init(name: "Bande à joint", quantity: effectiveArea * references.quantity("band_ml_m2", fallback: 1.58), unit: "ml"), .init(name: compound == "powder" ? "Enduit en poudre" : "Enduit en pâte", quantity: effectiveArea * references.quantity(compound == "powder" ? "powder_kg_m2" : "paste_kg_m2", fallback: compound == "powder" ? 0.37 : 0.53), unit: "kg")] }
        return merge(result)
    }
    private func merge(_ values: [LabSupply]) -> [LabSupply] {
        var order: [String] = []; var merged: [String: LabSupply] = [:]
        for value in values { if merged[value.id] == nil { order.append(value.id); merged[value.id] = value } else { merged[value.id]?.quantity += value.quantity } }
        return order.compactMap { merged[$0] }
    }
    private func allocationStatus(_ values: [LabFacingAllocation]) -> some View {
        let total = values.reduce(0) { $0 + $1.area }; let difference = effectiveArea - total
        return Text(abs(difference) < 0.01 ? "Répartition complète : \(format(total)) m²." : difference > 0 ? "Il reste \(format(difference)) m² à répartir." : "La répartition dépasse de \(format(-difference)) m².").font(.footnote).foregroundStyle(abs(difference) < 0.01 ? .green : .orange).padding(.horizontal, 12)
    }
    private func sectionTitle(_ value: String) -> some View { Text(value).font(.headline).foregroundStyle(.secondary).padding(.horizontal, 12) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 14, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 22)) }
    private func updateArea() { if length > 0 && width > 0 { area = length * width } }
    private func reset() {
        step = 0; shape = .horizontal; area = 0; dimensionsSpecified = true; length = 0; width = 0; direction = "width"; support = .wood
        insulationEnabled = true; insulationLayers = 1; firstInsulation = .init(); secondInsulation = .init(); vaporBarrier = false; extraPlenumCM = 0
        facingLayers = 1; firstSkin = []; secondSkin = []; stud = .m48; assembly = .single; frameMode = .selfSupporting; jointTreatment = true; compound = "powder"; showingResult = false
        normalizeSelections()
    }
    private func configurationSnapshot() -> RailStudCeilingConfiguration {
        RailStudCeilingConfiguration(
            shape: shape.rawValue,
            area: area,
            dimensionsSpecified: dimensionsSpecified,
            length: length,
            width: width,
            direction: direction,
            support: support.rawValue,
            insulationEnabled: insulationEnabled,
            insulationLayers: insulationLayers,
            firstInsulation: .init(seriesID: firstInsulation.seriesID, thickness: firstInsulation.thickness, location: firstInsulation.location),
            secondInsulation: .init(seriesID: secondInsulation.seriesID, thickness: secondInsulation.thickness, location: secondInsulation.location),
            vaporBarrier: vaporBarrier,
            extraPlenumCM: extraPlenumCM,
            facingLayers: facingLayers,
            firstSkin: firstSkin.map { .init(id: $0.id, productID: $0.productID, dimensionID: $0.dimensionID, area: $0.area) },
            secondSkin: secondSkin.map { .init(id: $0.id, productID: $0.productID, dimensionID: $0.dimensionID, area: $0.area) },
            studWidth: stud.rawValue,
            assembly: assembly.rawValue,
            frameMode: frameMode.rawValue,
            jointTreatment: jointTreatment,
            compound: compound,
            quantities: quantities.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        )
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func lambda(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(3))) }
    private func quantityTitle(_ supply: LabSupply) -> String { "\(supply.unit == "unité" || supply.unit == "plaque(s)" ? String(Int(ceil(supply.quantity))) : format(supply.quantity)) \(supply.unit)" }
}

private struct LabMeasureField: View {
    let label: String
    @Binding var value: Double
    let unit: String
    var body: some View {
        HStack { Text(label); Spacer(); ZeroEmptyDecimalTextField(value: $value).multilineTextAlignment(.trailing).frame(width: 90); Text(unit).foregroundStyle(.secondary) }
    }
}
