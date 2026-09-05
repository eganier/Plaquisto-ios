import Foundation

struct FacingSelection: Identifiable, Codable, Equatable {
    var id: UUID
    var facingID: String
    var dimensionID: String
    var area: Double

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
    var support: String = ""
    var plenum: Double = 20
    var vaporBarrier = false
    var insulationID: String = ""
    var insulationThickness: Double = 0
    var selectedSpacing: Double = 0.6
    var fixingSystemID: String = ""
    var layers = 1
    var firstSkin: [FacingSelection] = []
    var secondSkin: [FacingSelection] = []
    var jointTreatment = true
    var compoundChoice = "poudre"
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

struct DoublageConfiguration: Codable, Equatable {
    var geometryMode = "length"
    var height: Double = 0
    var enteredLength: Double = 0
    var enteredSurface: Double = 0
    var layers = 1
    var firstSkin: [DoublageFacingSelection] = []
    var secondSkin: [DoublageFacingSelection] = []
    var technique = "Rails et montants"
    var frame = "R48 + M48"
    var doubledStuds = false
    var spacing: Double = 0.6
    var intermediateSupports = false
    var insulationEnabled = true
    var insulationLayers = 1
    var firstInsulation = DoublageInsulationSelection()
    var secondInsulation = DoublageInsulationSelection()
    var vaporBarrier = false
    var jointTreatment = true
    var compoundChoice = "poudre"
    var quantities: [DoublageQuantity] = []

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }
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
    var insulationEnabled = true
    var insulationID = ""
    var insulationThicknessMM = 0
    var jointTreatment = true
    var compoundChoice = "poudre"
    var quantities: [CloisonQuantity] = []

    var area: Double { geometryMode == "surface" ? enteredSurface : enteredLength * height }
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

enum WorkCategory: String, Codable, CaseIterable, Identifiable {
    case ceilings = "plafonds"
    case partitions = "cloisons"
    case wallInsulation = "isolation-murs"
    case specificWorks = "ouvrages-specifiques"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ceilings: "Les plafonds"
        case .partitions: "Les cloisons"
        case .wallInsulation: "L’isolation des murs"
        case .specificWorks: "Ouvrages spécifiques"
        }
    }
}

enum WorkType: String, Codable, CaseIterable, Identifiable {
    case ceilingOnFurring = "plafond-fourrures"
    case peripheralLiningStuds = "doublage-peripherique-rails-montants"
    case distributionPartition = "cloison-de-distribution"
    case alveolarPartition = "cloison-de-distribution-alveolaire"
    case peripheralLiningBonded = "doublage-peripherique-complexe-colle"

    var id: String { rawValue }
    var category: WorkCategory {
        switch self {
        case .ceilingOnFurring: .ceilings
        case .peripheralLiningStuds, .peripheralLiningBonded: .wallInsulation
        case .distributionPartition, .alveolarPartition: .partitions
        }
    }
    var title: String {
        switch self {
        case .ceilingOnFurring: "Plafond sur fourrures"
        case .peripheralLiningStuds: "Doublage périphérique — Rails et montants"
        case .distributionPartition: "Cloison de distribution — Rails et montants"
        case .alveolarPartition: "Cloison de distribution alvéolaire"
        case .peripheralLiningBonded: "Doublage périphérique — Complexe collé"
        }
    }
}

enum WorkConfiguration: Codable, Equatable {
    case ceiling(CeilingConfiguration)
    case peripheralLining(DoublageConfiguration)
    case distributionPartition(CloisonDistributionConfiguration)
    case alveolarPartition(AlveolarPartitionConfiguration)
    case bondedLining(BondedLiningConfiguration)

    private enum CodingKeys: String, CodingKey { case kind, data }
    private enum Kind: String, Codable { case ceiling, peripheralLining, distributionPartition, alveolarPartition, bondedLining }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ceiling:
            self = .ceiling(try container.decode(CeilingConfiguration.self, forKey: .data))
        case .peripheralLining:
            self = .peripheralLining(try container.decode(DoublageConfiguration.self, forKey: .data))
        case .distributionPartition:
            self = .distributionPartition(try container.decode(CloisonDistributionConfiguration.self, forKey: .data))
        case .alveolarPartition:
            self = .alveolarPartition(try container.decode(AlveolarPartitionConfiguration.self, forKey: .data))
        case .bondedLining:
            self = .bondedLining(try container.decode(BondedLiningConfiguration.self, forKey: .data))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ceiling(let configuration):
            try container.encode(Kind.ceiling, forKey: .kind)
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

    var ceilingConfiguration: CeilingConfiguration? {
        guard case .ceiling(let configuration) = payload else { return nil }
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
}

extension WorkItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, projectID, name, type, payload, configuration, doublageConfiguration, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(WorkType.self, forKey: .type)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if let current = try container.decodeIfPresent(WorkConfiguration.self, forKey: .payload) {
            payload = current
        } else if type == .peripheralLiningStuds,
                  let legacy = try container.decodeIfPresent(DoublageConfiguration.self, forKey: .doublageConfiguration) {
            payload = .peripheralLining(legacy)
        } else {
            payload = .ceiling(try container.decode(CeilingConfiguration.self, forKey: .configuration))
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
}
