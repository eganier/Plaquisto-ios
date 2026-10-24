import Foundation

struct LayoutQuantityLine: Codable, Equatable {
    var name:String
    var quantity:Double
    var unit:String
    /// Stable catalogue identity for preserving the product label on recalculation.
    var formatID:String? = nil
}
struct LayoutQuantityTakeoff: Codable, Equatable {
    var fingerprint:String
    var area:Double
    var boards:[LayoutQuantityLine]
    var framingMeters:Double
    var perimeterMeters:Double
    var hangers:Int
    /// Exact joints between 3 m furring lengths, before any stock reserve.
    var furringSplices:Int? = nil
    /// Fractions of the whole ouvrage refined by saved plans. The remainder
    /// keeps the configurator estimate, including unconfigured components.
    var coverageFraction:Double? = nil
    var boardCoverageFractions:[Double]? = nil
    var configurationFingerprint:String? = nil
    var framingCoverage:Double { min(1,max(0,coverageFraction ?? 1)) }
    func boardCoverage(_ skin:Int) -> Double {
        guard let values=boardCoverageFractions else { return framingCoverage }
        return values.indices.contains(skin) ? min(1,max(0,values[skin])) : 0
    }
}

struct FacingSelection: Identifiable, Codable, Equatable {
    var id: UUID
    var facingID: String
    var dimensionID: String
    var area: Double
    var fourTaperedEdges: Bool? = nil

    init(id: UUID = UUID(), facingID: String, dimensionID: String, area: Double) {
        self.id = id
        self.facingID = facingID
        self.dimensionID = dimensionID
        self.area = area
    }
}

struct CeilingConfiguration: Codable, Equatable {
    var length: Double = 0
    var width: Double = 0
    // Keeps the exact entered surface when dimensions were estimated and rounded.
    var enteredArea: Double? = nil
    // Optional so ceilings saved before the explicit dimensions choice remain decodable.
    var dimensionsSpecified: Bool? = nil
    var support: String = ""
    var plenum: Double = 0
    var vaporBarrier = false
    var insulationID: String = ""
    var insulationThickness: Double = 0
    var selectedSpacing: Double = 0.6
    var fixingSystemID: String = ""
    // nil keeps the automatic catalogue recommendation for existing archives.
    var hangerModelID: String? = nil
    var layers = 1
    var firstSkin: [FacingSelection] = []
    var secondSkin: [FacingSelection] = []
    var jointTreatment = true
    var compoundChoice = "poudre"
    // Optional fields preserve decoding of ceilings saved before sloped ceilings
    // and double-layer insulation were introduced.
    var ceilingShape: String? = nil
    var insulationLayers: Int? = nil
    var secondInsulationID: String? = nil
    var secondInsulationThickness: Double? = nil
    var firstInsulationLocation: String? = nil
    var secondInsulationLocation: String? = nil
    // Optional so ceilings saved before the direction choice remain decodable.
    var furringDirection: String? = nil
    var perimeterSupport: Bool? = nil
    // Optional to preserve archives created before the suspension-spacing control.
    var suspensionSpacingMeters: Double? = nil
}

struct DoublageFacingSelection: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var facingID: String
    var formatID: String
    var surface: Double

    init(id: UUID = UUID(), facingID: String = "", formatID: String = "", surface: Double = 0) {
        self.id = id
        self.facingID = facingID
        self.formatID = formatID
        self.surface = surface
    }
}

protocol OpeningFacingSelection {
    var openingFacingID: String { get }
}

enum LiningDepthEstimate {
    static func boardThickness(_ text: String) -> Double? {
        let text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard let expression = try? NSRegularExpression(pattern: #"ba\s*([0-9]{2})"#),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
    static func facings<S: OpeningFacingSelection>(_ layers: [[S]], count: Int) -> Double {
        layers.prefix(max(0, count)).reduce(0) { total, layer in
            total + (layer.compactMap { boardThickness($0.openingFacingID) }.max() ?? 13)
        }
    }
    static func millimetres(_ payload: WorkConfiguration) -> Double? {
        switch payload {
        case .peripheralLining(let c):
            guard c.facingDepthMM != nil || !c.firstSkin.isEmpty else { return nil }
            return Double(c.insulationEnabled ? c.firstInsulation.thicknessMM + (c.insulationLayers == 2 ? c.secondInsulation.thicknessMM : 0) : 0)
                + (c.facingDepthMM ?? facings([c.firstSkin, c.secondSkin], count: c.layers))
        case .furringLining(let c):
            guard c.facingDepthMM != nil || !c.firstSkin.isEmpty else { return nil }
            return Double(c.insulationEnabled ? c.firstInsulation.thicknessMM : 0) + 15
                + (c.facingDepthMM ?? facings([c.firstSkin, c.secondSkin, c.thirdSkin], count: c.layers))
        default: return nil
        }
    }
}

extension DoublageFacingSelection: OpeningFacingSelection {
    var openingFacingID: String { facingID }
}

extension FurringFacingSelection: OpeningFacingSelection {
    var openingFacingID: String { facingID }
}

struct DoublageInsulationSelection: Codable, Equatable, Hashable {
    var familyID: String = ""
    var lambda: Double = 0
    var thicknessMM: Int = 0
}

struct DoublageQuantity: Identifiable, Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var id: String { "\(name)|\(unit)" }
}

/// Quantity inputs for separate scanned supports. Their real contours live in
/// WorkComponentRecord; this snapshot prevents deriving rails from net area/HSP.
struct MeasuredWallRun: Codable, Equatable {
    var length: Double
    var height: Double
    var netArea: Double
    var openingCount: Int? = nil
    /// Union of the opening cutouts, already deducted from netArea (square metres).
    var openingArea: Double? = nil
}

struct DoublageConfiguration: Codable, Equatable {
    /// Raw support to finished facing, including boards (millimetres).
    var finishedDepthMM: Double? = nil
    var facingDepthMM: Double? = nil
    var geometryMode = "length"
    var height: Double = 0
    var enteredLength: Double = 0
    var enteredSurface: Double = 0
    var wallCount: Int? = nil
    var layers = 1
    var firstSkin: [DoublageFacingSelection] = []
    var secondSkin: [DoublageFacingSelection] = []
    var technique = "Rails et montants"
    var frame = "R48 + M48"
    var doubledStuds = false
    var spacing: Double = 0.6
    // Optional so projects saved before the tiled-area rule remain decodable.
    var tiledArea: Bool? = nil
    var tiledAreaSurface: Double? = nil
    var intermediateSupports = false
    var insulationEnabled = true
    var insulationLayers = 1
    var firstInsulation = DoublageInsulationSelection()
    var secondInsulation = DoublageInsulationSelection()
    var vaporBarrier = false
    var jointTreatment = true
    var compoundChoice = "poudre"
    var quantities: [DoublageQuantity] = []
    var measuredWallRuns: [MeasuredWallRun]? = nil

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }
}

enum DoublageStudCalculator {
    static func studAxes(length: Double, spacing: Double, wallCount: Int) -> Int {
        guard length > 0, spacing > 0, wallCount > 0 else { return 0 }
        let baysPerWall = Int(ceil((length / Double(wallCount)) / spacing))
        return wallCount * (baysPerWall + 1)
    }

    static func studs(length: Double, spacing: Double, wallCount: Int, doubled: Bool) -> Int {
        guard length > 0, spacing > 0, wallCount > 0 else { return 0 }
        let baysPerWall = Int(ceil((length / Double(wallCount)) / spacing))
        if !doubled { return wallCount * (baysPerWall + 1) }

        // Les deux extrémités de chaque mur restent simples. Seuls les montants intérieurs sont doublés.
        let studsPerWall = 2 + max(0, baysPerWall - 1) * 2
        return wallCount * studsPerWall
    }
}

struct CloisonFacingSelection: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var facingID: String
    var formatID: String
    var surface: Double

    init(id: UUID = UUID(), facingID: String = "", formatID: String = "", surface: Double = 0) {
        self.id = id
        self.facingID = facingID
        self.formatID = formatID
        self.surface = surface
    }
}

struct CloisonQuantity: Identifiable, Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var id: String { "\(name)|\(unit)" }
}

enum PartitionFacingArea {
    /// Every face/layer covers the NET partition area, not half that area.
    /// Preserve mixed product shares when the measured geometry changes.
    static func resized(_ selections:[CloisonFacingSelection],area:Double) -> [CloisonFacingSelection] {
        guard area.isFinite, area>=0, !selections.isEmpty else { return selections }
        let total=selections.reduce(0) { $0+max(0,$1.surface) }
        return selections.enumerated().map { index,selection in
            var result=selection
            result.surface=total>0 ? max(0,selection.surface)*area/total : (index==0 ? area : 0)
            return result
        }
    }
}

struct CloisonDistributionConfiguration: Codable, Equatable {
    var geometryMode = "length"
    var height: Double = 0
    var enteredLength: Double = 0
    var enteredSurface: Double = 0
    var layers = 1
    var faceAFirst: [CloisonFacingSelection] = []
    var faceASecond: [CloisonFacingSelection] = []
    var faceBFirst: [CloisonFacingSelection] = []
    var faceBSecond: [CloisonFacingSelection] = []
    var frame = "R48 + M48/35"
    var doubledStuds = false
    var spacing: Double = 0.60
    // Optional so projects saved before the tiled-area rule remain decodable.
    var tiledArea: Bool? = nil
    var tiledAreaSurface: Double? = nil
    var insulationEnabled = true
    var insulationID = ""
    var insulationThicknessMM = 0
    var jointTreatment = true
    var compoundChoice = "poudre"
    var quantities: [CloisonQuantity] = []

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }

    /// Repair the legacy dimension-edit bug without changing selected products,
    /// the published wastage coefficient or any framing/insulation quantity.
    func repairingStaleFacingAreas() -> Self {
        let groups=layers==2 ? [faceAFirst,faceBFirst,faceASecond,faceBSecond] : [faceAFirst,faceBFirst]
        let totals=groups.map { $0.reduce(0) { $0+$1.surface } }
        guard area>0, let previous=totals.first, previous>0,
              totals.allSatisfy({abs($0-previous)<0.01}), abs(previous-area)>0.01 else { return self }
        var result=self
        result.faceAFirst=PartitionFacingArea.resized(faceAFirst,area:area)
        result.faceBFirst=PartitionFacingArea.resized(faceBFirst,area:area)
        result.faceASecond=PartitionFacingArea.resized(faceASecond,area:area)
        result.faceBSecond=PartitionFacingArea.resized(faceBSecond,area:area)
        result.quantities=quantities.map { row in
            var next=row
            let name=SupplyListingConsolidator.canonicalName(row.name)
            if name.range(of:#"^BA\d+\b"#,options:.regularExpression) != nil,
               SupplyListingConsolidator.canonicalUnit(row.unit)=="m²" { next.quantity *= area/previous }
            return next
        }
        return result
    }
}

struct AlveolarPanelSelection: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var panelID: String
    var formatID: String
    var surface: Double

    init(id: UUID = UUID(), panelID: String = "", formatID: String = "", surface: Double = 0) {
        self.id = id
        self.panelID = panelID
        self.formatID = formatID
        self.surface = surface
    }
}

struct AlveolarQuantity: Identifiable, Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var id: String { "\(name)|\(unit)" }
}

struct AlveolarPartitionConfiguration: Codable, Equatable {
    var geometryMode = "length"
    var height: Double = 0
    var enteredLength: Double = 0
    var enteredSurface: Double = 0
    var panels: [AlveolarPanelSelection] = []
    var jointTreatment = true
    var compoundChoice = "poudre"
    var quantities: [AlveolarQuantity] = []

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }
}

struct BondedFacingAllocation: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var facing: BondedFacingKind
    var surface: Double

    init(id: UUID = UUID(), facing: BondedFacingKind = .standard, surface: Double = 0) {
        self.id = id
        self.facing = facing
        self.surface = surface
    }
}

struct BondedLiningQuantity: Identifiable, Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var id: String { "\(name)|\(unit)" }
}

struct BondedLiningConfiguration: Codable, Equatable {
    var geometryMode = "length"
    var height: Double = 0
    var enteredLength: Double = 0
    var enteredSurface: Double = 0
    var allocations: [BondedFacingAllocation] = []
    var lambda: Double = 0
    var hasReveal = false
    var revealMM = 0
    var insulationThicknessMM = 0
    var widthMM = 0
    var panelHeightMM = 0
    var jointTreatment = true
    var quantities: [BondedLiningQuantity] = []

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }
}

struct FurringLiningConfiguration: Codable, Equatable {
    /// Raw support to finished facing, including boards (millimetres).
    var finishedDepthMM: Double? = nil
    var facingDepthMM: Double? = nil
    var geometryMode = "length"
    var height: Double = 0
    var enteredLength: Double = 0
    var enteredSurface: Double = 0
    var wallCount: Int? = nil
    var layers = 1
    var firstSkin: [FurringFacingSelection] = []
    var secondSkin: [FurringFacingSelection] = []
    var thirdSkin: [FurringFacingSelection] = []
    var tiledArea = false
    var tiledAreaSurface: Double = 0
    var selectedSupportLines = 1
    // Optional so configurations saved before the spacing was persisted remain decodable.
    var furringSpacing: Double? = nil
    // Optional so configurations saved before this choice remain decodable.
    var includesHorizontalSupportFurring: Bool? = nil
    /// Optional snapshots preserve old works and the exact Admin model selected at save time.
    var intermediateSupportReferenceID: String? = nil
    var intermediateSupportTitle: String? = nil
    /// Snapshot of the Admin support rule used by the configurator (metres).
    var maximumSupportSpacing: Double? = nil
    var firstSupportHeightWhenMultiple: Double? = nil
    var insulationEnabled = true
    var firstInsulation = FurringInsulationSelection()
    var vaporBarrier = false
    var vaporBarrierInstallation = "through_supports"
    var jointTreatment = true
    var compoundChoice = "poudre"
    var quantities: [DoublageQuantity] = []
    var measuredWallRuns: [MeasuredWallRun]? = nil

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }
    var supportSupplyName: String { intermediateSupportTitle ?? "Appuis intermédiaires pour fourrures" }
}

struct PaintingBetaConfiguration: Codable, Equatable {
    var area: Double = 0
    // Optional for legacy area-only works. Persist the Admin rules used for this estimate.
    var treatment: PaintingTreatment? = nil
}

enum WorkCategory: String, Codable, CaseIterable, Identifiable {
    case joints = "bandes-a-joint"
    case ceilings = "plafonds"
    case partitions = "cloisons"
    case wallInsulation = "isolation-murs"
    case openings = "ouvertures"
    case painting = "peinture"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .joints: "Bandes à joint"
        case .ceilings: "Les plafonds"
        case .partitions: "Les cloisons"
        case .wallInsulation: "L’isolation des murs"
        case .openings: "Les ouvertures"
        case .painting: "Peinture et ratissages"
        }
    }
}

enum WorkType: String, Codable, CaseIterable, Identifiable {
    case jointTreatment = "bandes-a-joint"
    case ceilingOnFurring = "plafond-fourrures"
    case ceilingOnRailsAndStuds = "plafond-rails-montants"
    case modularCeiling = "plafond-modulaire"
    case frenchCeiling = "plafond-a-la-francaise"
    case peripheralLiningStuds = "doublage-peripherique-rails-montants"
    case distributionPartition = "cloison-de-distribution"
    case alveolarPartition = "cloison-de-distribution-alveolaire"
    case peripheralLiningBonded = "doublage-peripherique-complexe-colle"
    case peripheralLiningFurrings = "doublage-peripherique-lisses-fourrures"
    case peripheralLiningAdhesiveFacing = "doublage-peripherique-parement-colle"
    case openings = "ouvertures"
    case paintingBeta = "peinture-beta"

    var id: String { rawValue }
    var category: WorkCategory {
        switch self {
        case .jointTreatment: .joints
        case .ceilingOnFurring, .ceilingOnRailsAndStuds, .modularCeiling, .frenchCeiling: .ceilings
        case .peripheralLiningStuds, .peripheralLiningBonded, .peripheralLiningFurrings, .peripheralLiningAdhesiveFacing: .wallInsulation
        case .distributionPartition, .alveolarPartition: .partitions
        case .openings: .openings
        case .paintingBeta: .painting
        }
    }
    var title: String {
        switch self {
        case .jointTreatment: "Bandes à joint"
        case .ceilingOnFurring: "Plafond sur fourrures"
        case .ceilingOnRailsAndStuds: "Plafond sur ossature rails et montants"
        case .modularCeiling: "Plafond modulaire en dalles (bêta)"
        case .frenchCeiling: "Plafond à la française (bêta)"
        case .peripheralLiningStuds: "Doublage périphérique — Rails et montants"
        case .distributionPartition: "Cloison de distribution — Rails et montants"
        case .alveolarPartition: "Cloison de distribution alvéolaire"
        case .peripheralLiningBonded: "Doublage périphérique — Complexe collé"
        case .peripheralLiningFurrings: "Doublage périphérique — Lisses et fourrures"
        case .peripheralLiningAdhesiveFacing: "Doublage périphérique — Parement collé"
        case .openings: "Ouvertures"
        case .paintingBeta: "Peinture et ratissages"
        }
    }
    var defaultNameBase: String {
        switch self {
        case .jointTreatment: "Bandes à joint"
        case .ceilingOnFurring: "Plafond sur fourrures"
        case .ceilingOnRailsAndStuds: "Plafond sur ossature rails et montants"
        case .modularCeiling: "Plafond modulaire en dalles"
        case .frenchCeiling: "Plafond à la française"
        case .peripheralLiningStuds: "Doublage périphérique sur rails et montants"
        case .distributionPartition: "Cloison de distribution"
        case .alveolarPartition: "Cloison de distribution alvéolaire"
        case .peripheralLiningBonded: "Doublage périphérique en complexe collé"
        case .peripheralLiningFurrings: "Doublage périphérique sur lisses et fourrures"
        case .peripheralLiningAdhesiveFacing: "Doublage périphérique en parement collé"
        case .openings: "Ouvertures"
        case .paintingBeta: "Peinture et ratissages"
        }
    }

    /// Intitulé volontairement simple utilisé dans le nom visible d'un ouvrage.
    /// Le détail constructif complet reste affiché séparément via `title`.
    var simpleTitle: String {
        switch self {
        case .jointTreatment: "Bandes à joint"
        case .ceilingOnFurring, .ceilingOnRailsAndStuds:
            "Plafond"
        case .modularCeiling:
            "Plafond modulaire"
        case .frenchCeiling:
            "Plafond à la française"
        case .peripheralLiningStuds, .peripheralLiningBonded, .peripheralLiningFurrings, .peripheralLiningAdhesiveFacing:
            "Doublage périphérique"
        case .distributionPartition, .alveolarPartition:
            "Cloison"
        case .openings:
            "Ouvertures"
        case .paintingBeta:
            "Peinture et ratissages"
        }
    }

    func generatedName(roomName: String) -> String {
        let room = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        return room.isEmpty ? simpleTitle : "\(room) - \(simpleTitle)"
    }
}

enum WorkConfiguration: Codable, Equatable {
    case jointTreatment(JointTreatmentConfiguration)
    case ceiling(CeilingConfiguration)
    case railStudCeiling(RailStudCeilingConfiguration)
    case modularCeiling(ModularCeilingConfiguration)
    case peripheralLining(DoublageConfiguration)
    case distributionPartition(CloisonDistributionConfiguration)
    case alveolarPartition(AlveolarPartitionConfiguration)
    case bondedLining(BondedLiningConfiguration)
    case furringLining(FurringLiningConfiguration)
    case adhesiveFacing(AdhesiveFacingConfiguration)
    case openings(OpeningConfiguration)
    case paintingBeta(PaintingBetaConfiguration)

    private enum CodingKeys: String, CodingKey { case kind, data }
    private enum Kind: String, Codable { case ceiling, railStudCeiling, modularCeiling, peripheralLining, distributionPartition, alveolarPartition, bondedLining, furringLining, adhesiveFacing, openings, paintingBeta, jointTreatment }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .jointTreatment:
            self = .jointTreatment(try container.decode(JointTreatmentConfiguration.self, forKey: .data))
        case .ceiling:
            self = .ceiling(try container.decode(CeilingConfiguration.self, forKey: .data))
        case .railStudCeiling:
            self = .railStudCeiling(try container.decode(RailStudCeilingConfiguration.self, forKey: .data))
        case .modularCeiling:
            self = .modularCeiling(try container.decode(ModularCeilingConfiguration.self, forKey: .data))
        case .peripheralLining:
            self = .peripheralLining(try container.decode(DoublageConfiguration.self, forKey: .data))
        case .distributionPartition:
            self = .distributionPartition(try container.decode(CloisonDistributionConfiguration.self, forKey: .data))
        case .alveolarPartition:
            self = .alveolarPartition(try container.decode(AlveolarPartitionConfiguration.self, forKey: .data))
        case .bondedLining:
            self = .bondedLining(try container.decode(BondedLiningConfiguration.self, forKey: .data))
        case .furringLining:
            self = .furringLining(try container.decode(FurringLiningConfiguration.self, forKey: .data))
        case .adhesiveFacing:
            self = .adhesiveFacing(try container.decode(AdhesiveFacingConfiguration.self, forKey: .data))
        case .openings:
            self = .openings(try container.decode(OpeningConfiguration.self, forKey: .data))
        case .paintingBeta:
            self = .paintingBeta(try container.decode(PaintingBetaConfiguration.self, forKey: .data))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jointTreatment(let configuration):
            try container.encode(Kind.jointTreatment, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .ceiling(let configuration):
            try container.encode(Kind.ceiling, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .railStudCeiling(let configuration):
            try container.encode(Kind.railStudCeiling, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .modularCeiling(let configuration):
            try container.encode(Kind.modularCeiling, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .peripheralLining(let configuration):
            try container.encode(Kind.peripheralLining, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .distributionPartition(let configuration):
            try container.encode(Kind.distributionPartition, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .alveolarPartition(let configuration):
            try container.encode(Kind.alveolarPartition, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .bondedLining(let configuration):
            try container.encode(Kind.bondedLining, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .furringLining(let configuration):
            try container.encode(Kind.furringLining, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .adhesiveFacing(let configuration):
            try container.encode(Kind.adhesiveFacing, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .openings(let configuration):
            try container.encode(Kind.openings, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        case .paintingBeta(let configuration):
            try container.encode(Kind.paintingBeta, forKey: .kind)
            try container.encode(configuration, forKey: .data)
        }
    }
}

struct WorkItem: Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    var name: String
    var type: WorkType
    var payload: WorkConfiguration
    let createdAt: Date
    var updatedAt: Date
    /// Compatibility facade for the existing single-support configurators.
    /// The persisted source of truth is always the component, never a second copy.
    var layoutDocument: LayoutDocument? {
        get {
            guard components.count == 1, components[0].plans.count == 1 else { return nil }
            return components[0].document(for: components[0].plans[0])
        }
        set {
            guard let newValue else { return }
            guard components.isEmpty || (components.count == 1 && components[0].plans.count <= 1) else { return }
            var component = components.first ?? WorkComponentRecord(name: newValue.surface.name)
            if component.surface != newValue.surface { component.geometryRevision += 1 }
            component.surface = newValue.surface
            var plan = component.plans.first ?? ComponentLayoutPlan(sideRoomID: isPartition ? roomID : nil)
            component.referenceSideRoomID = component.referenceSideRoomID ?? plan.sideRoomID
            plan.layers = newValue.layers; plan.lighting = newValue.lighting
            component.framing = plan.layers.first?.furring
            for i in plan.layers.indices { plan.layers[i].furring = nil }
            plan.geometryRevision = component.geometryRevision
            component.plans = [plan]
            components = [component]
        }
    }
    var isPartition: Bool { type == .distributionPartition || type == .alveolarPartition }
    /// A named component alone is not a saved layout (including legacy empty components).
    var hasSavedLayout: Bool {
        components.contains { component in
            component.surface != nil && component.plans.contains { !$0.layers.isEmpty }
        }
    }
    var layoutNeedsRecalculation: Bool? = nil
    var layoutQuantityTakeoff: LayoutQuantityTakeoff? = nil
    var automaticLayout: AutomaticLayoutRecord? = nil
    /// Legacy review flag, migrated to automatic synchronization when loading.
    /// Survey edits now update geometry and estimates in the same transaction.
    var surveySourceNeedsReview = false
    /// Optional user-selected organization. Geometric side references are independent.
    var roomID: UUID? = nil
    var level: String? = nil
    var zone: String? = nil
    var linkedRoomIDs: [UUID] = []
    var components: [WorkComponentRecord] = []

    var ceilingConfiguration: CeilingConfiguration? {
        guard case .ceiling(let configuration) = payload else { return nil }
        return configuration
    }

    var paintingBetaConfiguration: PaintingBetaConfiguration? {
        guard case .paintingBeta(let configuration) = payload else { return nil }
        return configuration
    }

    var railStudCeilingConfiguration: RailStudCeilingConfiguration? {
        guard case .railStudCeiling(let configuration) = payload else { return nil }
        return configuration
    }

    var modularCeilingConfiguration: ModularCeilingConfiguration? {
        guard case .modularCeiling(let configuration) = payload else { return nil }
        return configuration
    }

    var doublageConfiguration: DoublageConfiguration? {
        guard case .peripheralLining(let configuration) = payload else { return nil }
        return configuration
    }

    var cloisonDistributionConfiguration: CloisonDistributionConfiguration? {
        guard case .distributionPartition(let configuration) = payload else { return nil }
        return configuration
    }

    var alveolarPartitionConfiguration: AlveolarPartitionConfiguration? {
        guard case .alveolarPartition(let configuration) = payload else { return nil }
        return configuration
    }

    var bondedLiningConfiguration: BondedLiningConfiguration? {
        guard case .bondedLining(let configuration) = payload else { return nil }
        return configuration
    }

    var furringLiningConfiguration: FurringLiningConfiguration? {
        guard case .furringLining(let configuration) = payload else { return nil }
        return configuration
    }

    var adhesiveFacingConfiguration: AdhesiveFacingConfiguration? {
        guard case .adhesiveFacing(let configuration) = payload else { return nil }
        return configuration
    }

    var openingConfiguration: OpeningConfiguration? {
        guard case .openings(let configuration) = payload else { return nil }
        return configuration
    }

    /// Pièce déduite des nouveaux noms `Pièce - Ouvrage`. Pour les données
    /// historiques, le nom complet reste proposé afin qu'il puisse être corrigé.
    var inferredRoomName: String {
        guard let separator = name.range(of: " - ") else { return name }
        return String(name[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, payload: WorkConfiguration, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.type = type
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, configuration: CeilingConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .ceiling(configuration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, railStudCeilingConfiguration: RailStudCeilingConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .railStudCeiling(railStudCeilingConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, modularCeilingConfiguration: ModularCeilingConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .modularCeiling(modularCeilingConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, doublageConfiguration: DoublageConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .peripheralLining(doublageConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, cloisonDistributionConfiguration: CloisonDistributionConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .distributionPartition(cloisonDistributionConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, alveolarPartitionConfiguration: AlveolarPartitionConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .alveolarPartition(alveolarPartitionConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, bondedLiningConfiguration: BondedLiningConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .bondedLining(bondedLiningConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, furringLiningConfiguration: FurringLiningConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .furringLining(furringLiningConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, adhesiveFacingConfiguration: AdhesiveFacingConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .adhesiveFacing(adhesiveFacingConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, projectID: UUID, name: String, type: WorkType, openingConfiguration: OpeningConfiguration, createdAt: Date, updatedAt: Date) {
        self.init(id: id, projectID: projectID, name: name, type: type, payload: .openings(openingConfiguration), createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension WorkItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, projectID, name, type, payload, configuration, doublageConfiguration, createdAt, updatedAt, layoutDocument, layoutNeedsRecalculation, surveySourceNeedsReview, roomID, linkedRoomIDs, components, level, zone, layoutQuantityTakeoff, automaticLayout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(WorkType.self, forKey: .type)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        layoutNeedsRecalculation = try container.decodeIfPresent(Bool.self,forKey:.layoutNeedsRecalculation)
        layoutQuantityTakeoff = try container.decodeIfPresent(LayoutQuantityTakeoff.self,forKey:.layoutQuantityTakeoff)
        automaticLayout = try container.decodeIfPresent(AutomaticLayoutRecord.self, forKey: .automaticLayout)
        surveySourceNeedsReview = try container.decodeIfPresent(Bool.self, forKey: .surveySourceNeedsReview) ?? false
        roomID = try container.decodeIfPresent(UUID.self, forKey: .roomID)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        zone = try container.decodeIfPresent(String.self, forKey: .zone)
        linkedRoomIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedRoomIDs) ?? []
        components = try container.decodeIfPresent([WorkComponentRecord].self, forKey: .components) ?? []

        if let current = try container.decodeIfPresent(WorkConfiguration.self, forKey: .payload) {
            payload = current
        } else if type == .peripheralLiningStuds,
                  let legacy = try container.decodeIfPresent(DoublageConfiguration.self, forKey: .doublageConfiguration) {
            payload = .peripheralLining(legacy)
        } else {
            payload = .ceiling(try container.decode(CeilingConfiguration.self, forKey: .configuration))
        }
        if components.isEmpty, let document = try container.decodeIfPresent(LayoutDocument.self, forKey: .layoutDocument) {
            layoutDocument = document
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(layoutNeedsRecalculation,forKey:.layoutNeedsRecalculation)
        try container.encodeIfPresent(layoutQuantityTakeoff,forKey:.layoutQuantityTakeoff)
        try container.encodeIfPresent(automaticLayout, forKey: .automaticLayout)
        if surveySourceNeedsReview { try container.encode(true, forKey: .surveySourceNeedsReview) }
        try container.encodeIfPresent(roomID, forKey: .roomID)
        try container.encodeIfPresent(level, forKey: .level)
        try container.encodeIfPresent(zone, forKey: .zone)
        try container.encode(linkedRoomIDs, forKey: .linkedRoomIDs)
        try container.encode(components, forKey: .components)
    }
}

struct ProjectItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var client: String
    var address: String
    var notes: String
    var works: [WorkItem]
    let createdAt: Date
    var updatedAt: Date
    var rooms: [ProjectRoomRecord] = []
    // Optional keeps existing v2 archives readable. Relations are explicit, not inferred from lengths.
    var ceilingWallLinks: [CeilingWallLink]? = nil
    /// Shopping adjustments never replace calculated quantities or inventory.
    var shoppingLists: [String: ShoppingListEdits]? = nil

    func ownedWorks(in roomID: UUID) -> [WorkItem] { works.filter { $0.roomID == roomID } }
    func filteredWorks(roomID: UUID? = nil, level: String? = nil, zone: String? = nil) -> [WorkItem] {
        works.filter { work in
            (roomID == nil || work.roomID == roomID) && (level == nil || work.level == level) && (zone == nil || work.zone == zone)
        }
    }
    /// Owner-only union: adjacent room links never add the same partition again.
    func quantityWorks(in roomIDs: Set<UUID>, includeUnassigned: Bool = false) -> [WorkItem] {
        var seen = Set<UUID>()
        return works.filter { work in
            let included = work.roomID.map { roomIDs.contains($0) } ?? includeUnassigned
            return included && seen.insert(work.id).inserted
        }
    }
    func linkedWorks(in roomID: UUID) -> [WorkItem] {
        works.filter { $0.roomID != roomID && $0.linkedRoomIDs.contains(roomID) }
    }
}

struct ShoppingListEdits: Codable, Equatable {
    struct Edit: Codable, Equatable {
        var name: String? = nil
        var quantity: Double? = nil
        var deductStock = false
    }
    struct Product: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var name: String
        var quantity: Double
        var unit: String
    }
    var edits: [String: Edit] = [:]
    var products: [Product] = []
    /// Source -> destination, always a flat group (no chains or cycles).
    var replacements: [String: String] = [:]

    mutating func reset(_ id: String) {
        var group: Set<String> = [id]
        var previous = Set<String>()
        while group != previous {
            previous = group
            for (source, target) in replacements where group.contains(source) || group.contains(target) {
                group.insert(source); group.insert(target)
            }
        }
        replacements = replacements.filter { !group.contains($0.key) && !group.contains($0.value) }
        for key in group { edits.removeValue(forKey: key) }
        products.removeAll { $0.id == id }
    }
    mutating func merge(_ source: String, into target: String) {
        guard source != target, replacements[source] == nil, replacements[target] == nil else { return }
        for key in Array(replacements.keys) where replacements[key] == source { replacements[key] = target }
        replacements[source] = target
    }
}

/// Independent of RoomPlan: this identity survives rescans and room renaming.
struct ProjectRoomRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var floorAreaM2: Double? = nil
}

/// A physical part of an ouvrage, not a second ouvrage or a quantity snapshot.
/// No geometry is invented when only the total work area is known.
struct WorkComponentRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var surface: Surface2D? = nil
    var geometryRevision = 0
    var plans: [ComponentLayoutPlan] = []
    var referenceSideRoomID: UUID? = nil
    /// Stable A/B layout identities for a partition, independent of room ownership.
    var localLayoutSideIDs: [UUID]? = nil
    var framing: LayoutFurringSettings? = nil
    /// Acquisition link, not ownership: edited component geometry remains authoritative.
    var surveySource: SurveySurfaceSource? = nil
    /// Explicitly accepted in the overlap dialog; absent on historical works.
    var allowsExistingSurveyCoverage: Bool? = nil

    func isOppositeSide(_ sideRoomID: UUID?) -> Bool {
        guard let referenceSideRoomID, let sideRoomID else { return false }
        return referenceSideRoomID != sideRoomID
    }

    func document(for plan: ComponentLayoutPlan) -> LayoutDocument? {
        guard let surface else { return nil }
        let opposite = isOppositeSide(plan.sideRoomID)
        var layers = plan.layers
        for i in layers.indices {
            var settings = framing
            if opposite { settings?.offset.negate() }
            layers[i].furring = settings
        }
        return LayoutDocument(surface: opposite ? surface.mirroredComponentSide() : surface, layers: layers, lighting: plan.lighting)
    }

    func initialDocument(sideRoomID: UUID?, configuration: WorkConfiguration?) -> LayoutDocument? {
        if let saved = plans.first(where: { $0.sideRoomID == sideRoomID }) { return document(for: saved) }
        guard let base = document(for: ComponentLayoutPlan(sideRoomID:sideRoomID)) else { return nil }
        guard let configuration else { return base }
        var result = WorkLayoutDefaults.document(surface:base.surface,configuration:configuration)
        let skins = AutomaticSurveyLayout.skins(configuration, opposite: isOppositeSide(sideRoomID))
        if !skins.isEmpty {
            result.layers = skins.map { WorkLayoutDefaults.document(surface: base.surface, configuration: $0).layers[0] }
        }
        for i in result.layers.indices {
            result.layers[i] = WorkLayoutDefaults.resolvingSupport(result.layers[i], configuration: configuration)
            if framing != nil { result.layers[i].furring = base.layers.first?.furring }
        }
        return result
    }
}

struct SurveySurfaceSource: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case wall, ceiling }
    var surveyID: UUID
    var checkpointID: UUID
    var surfaceID: UUID
    var boundaryIndex: Int
    var kind: Kind
    var capturedAt: Date
}

extension Surface2D {
    /// An involution around the component's fixed local origin. IDs and edge indices
    /// stay stable; the same window cannot drift between the two partition sides.
    func mirroredComponentSide() -> Surface2D {
        func mirror(_ point: LayoutPoint) -> LayoutPoint { .init(x: -point.x, y: point.y) }
        func mirroredIntent(_ source: LayoutContourIntent) -> LayoutContourIntent {
            var result = source
            result.sketch = source.sketch.map(mirror)
            result.userVertexPositions = source.userVertexPositions.map { $0.map(mirror) }
            return result
        }
        var result = self
        result.contour = contour.map(mirror)
        result.openings = openings.map { opening in var copy = opening; copy.contour = opening.contour.map(mirror); return copy }
        result.contourIntent = contourIntent.map(mirroredIntent)
        result.previousContourIntents = previousContourIntents.map(mirroredIntent)
        if let frame = localFrame {
            result.localFrame?.axisX = .init(x: -frame.axisX.x, y: -frame.axisX.y, z: -frame.axisX.z)
        }
        return result
    }
}

/// Partition sides have distinct plans but share the component's physical contour.
struct ComponentLayoutPlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var sideRoomID: UUID? = nil
    var layers: [LayoutLayer] = [.init()]
    var lighting: LayoutLighting? = nil
    var geometryRevision = 0
}
