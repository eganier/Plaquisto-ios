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

enum WorkType: String, Codable, CaseIterable, Identifiable {
    case ceilingOnFurring = "plafond-fourrures"
    case peripheralLiningStuds = "doublage-peripherique-rails-montants"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ceilingOnFurring: "Plafond sur fourrures"
        case .peripheralLiningStuds: "Doublage périphérique — Rails et montants"
        }
    }
}

struct WorkItem: Identifiable, Codable, Equatable {
    let id: UUID
    let projectID: UUID
    var name: String
    var type: WorkType
    var configuration: CeilingConfiguration
    var doublageConfiguration: DoublageConfiguration? = nil
    let createdAt: Date
    var updatedAt: Date
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
