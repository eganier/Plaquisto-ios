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
    var length: Double = 5
    var width: Double = 4
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

enum WorkType: String, Codable, CaseIterable, Identifiable {
    case ceilingOnFurring = "plafond-fourrures"

    var id: String { rawValue }
    var title: String { "Plafond sur fourrures" }
}

struct WorkItem: Identifiable, Codable, Equatable {
    let id: UUID
    let projectID: UUID
    var name: String
    var type: WorkType
    var configuration: CeilingConfiguration
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
