import Foundation

// Portable schema: metres, right-handed coordinates, Y up. No scan SDK types.
struct RoomPoint: Codable, Equatable {
    var x: Double; var y: Double; var z: Double
    static let zero = RoomPoint(x: 0, y: 0, z: 0)
    static func + (a: Self, b: Self) -> Self { .init(x: a.x+b.x, y: a.y+b.y, z: a.z+b.z) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x-b.x, y: a.y-b.y, z: a.z-b.z) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x*b, y: a.y*b, z: a.z*b) }
    var length: Double { sqrt(x*x+y*y+z*z) }
    var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
enum GeometrySource: String, Codable {
    case roomPlan, arCore, lidar, manual, imported
    var title: String {
        switch self {
        case .roomPlan: return "RoomPlan"
        case .arCore: return "ARCore"
        case .lidar: return "LiDAR"
        case .manual: return "Manuelle"
        case .imported: return "Import"
        }
    }
}
struct GeometryProvenance: Codable, Equatable {
    var source: GeometrySource
    var sourceIdentifier: String? = nil // Correlation only, never the domain ID.
    var confidenceLabel: String? = nil
    var confidence: Double? = nil // Only when supplied; no invented probability.
}
struct RoomMeasurement: Codable, Equatable {
    var rawValue: Double
    var provenance: GeometryProvenance
    var manualValue: Double? = nil
    var manuallyValidated = false
    var effectiveValue: Double { manualValue ?? rawValue }
    var effectiveSource: GeometrySource { manualValue == nil ? provenance.source : .manual }
    // Used by acquisition adapters too: a scan update never clears a manual choice.
    func preservingCorrection(from previous: Self?) -> Self {
        guard let previous else { return self }
        var value = self
        value.manualValue = previous.manualValue
        value.manuallyValidated = previous.manuallyValidated
        return value
    }
    mutating func correct(_ value: Double) throws {
        guard value.isFinite, value > 0, value <= 1000 else { throw RoomModelError.invalidGeometry }
        manualValue = value; manuallyValidated = true
    }
    mutating func updateScan(_ value: Double, provenance: GeometryProvenance) {
        rawValue = value; self.provenance = provenance
    }
}
struct PlaquistoWall: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: RoomPoint
    var end: RoomPoint
    var length: RoomMeasurement
    var height: RoomMeasurement
    var thickness: RoomMeasurement? = nil
    var openingIDs: [UUID] = []
    var provenance: GeometryProvenance
    var direction: RoomPoint {
        let v = RoomPoint(x: end.x-start.x, y: 0, z: end.z-start.z)
        return v.length > 1e-9 ? v * (1/v.length) : .zero
    }
    var orientationRadians: Double { atan2(direction.z, direction.x) }
    var effectiveEnd: RoomPoint { start + direction * length.effectiveValue }
}
enum RoomOpeningKind: String, Codable, CaseIterable {
    case door, window, glazedBay, frenchDoor, passage, other
    var title: String {
        switch self { case .door: return "Porte"; case .window: return "Fenêtre"
        case .glazedBay: return "Baie vitrée"; case .frenchDoor: return "Porte-fenêtre"
        case .passage: return "Ouverture libre"; case .other: return "Autre ouverture" }
    }
}
struct PlaquistoOpening: Codable, Equatable, Identifiable {
    var id = UUID()
    var wallID: UUID? // Uncertain assignments stay unattached.
    var kind: RoomOpeningKind
    var center: RoomPoint
    var width: RoomMeasurement
    var height: RoomMeasurement
    var sillHeight: RoomMeasurement
    var positionOnWall: RoomMeasurement // Distance to left edge along wall.
    var provenance: GeometryProvenance
}
struct RoomPlane: Codable, Equatable {
    // Parametric plane y = a*x + b*z + c; a boundary is separate from the plane.
    var a: Double; var b: Double; var c: Double
    func height(x: Double, z: Double) -> Double { a*x+b*z+c }
    var slopeDegrees: Double { atan(hypot(a,b))*180 / .pi }
}
struct PlaquistoSlope: Codable, Equatable, Identifiable {
    var id = UUID()
    var plane: RoomPlane
    var boundaries: [[RoomPoint]]
    var provenance: GeometryProvenance
    var accepted = false
    var manuallyValidated = false
}
struct PlaquistoCeiling: Codable, Equatable, Identifiable {
    var id = UUID()
    var slopeIDs: [UUID]
    var provenance: GeometryProvenance
}
struct PlaquistoFloor: Codable, Equatable, Identifiable {
    var id = UUID()
    var boundaries: [[RoomPoint]]
    var referenceElevation: Double? = nil
    var provenance: GeometryProvenance
}
struct RoomMetadata: Codable, Equatable {
    var coordinateSystem = "rightHandedYUp"
    var lengthUnit = "meters"
    var createdAt = Date()
    var source: GeometrySource
    var sourceObjectCount = 0
}
struct PlaquistoRoomModel: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String? = nil
    var walls: [PlaquistoWall] = []
    var openings: [PlaquistoOpening] = []
    var ceilings: [PlaquistoCeiling] = []
    var floors: [PlaquistoFloor] = []
    var slopes: [PlaquistoSlope] = []
    var metadata: RoomMetadata
}
enum RoomModelError: Error, LocalizedError {
    case unsupportedSchema, invalidGeometry
    var errorDescription: String? {
        self == .unsupportedSchema ? "Version du fichier Plaquisto non prise en charge." : "Dimensions ou géométrie invalides."
    }
}
// Future explicit business choice. Separate from wall geometry; no Work is created.
// Intentionally no UI or quantity integration at this stage.
struct WallWorkIntent: Codable, Equatable {
    enum Use: String, Codable { case lining, partition, existingWall, untreated }
    var wallID: UUID
    var use: Use
}
struct PlaquistoRoomDocument: Codable, Equatable {
    var schemaVersion = 1
    let initialRoom: PlaquistoRoomModel
    var room: PlaquistoRoomModel // Working model: manual edits take priority.
    var wallWorkIntents: [WallWorkIntent]? = nil // Optional: existing v1 files remain readable.
    init(room: PlaquistoRoomModel) { initialRoom = room; self.room = room }
    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    static func decode(_ data: Data) throws -> Self {
        let header = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard header?["schemaVersion"] as? Int == 1 else { throw RoomModelError.unsupportedSchema }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Self.self, from: data)
        try document.validate(); return document
    }
    func validate() throws {
        guard schemaVersion == 1 else { throw RoomModelError.unsupportedSchema }
        let intents = wallWorkIntents ?? []
        guard room.id == initialRoom.id,
              Set(intents.map(\.wallID)).count == intents.count,
              intents.allSatisfy({ intent in room.walls.contains { $0.id == intent.wallID } }) else { throw RoomModelError.invalidGeometry }
        for model in [initialRoom, room] {
            guard model.metadata.lengthUnit == "meters", model.metadata.coordinateSystem == "rightHandedYUp",
                  model.walls.count <= 1000, model.openings.count <= 5000, model.slopes.count <= 100 else { throw RoomModelError.invalidGeometry }
            let ids = model.walls.map(\.id) + model.openings.map(\.id) + model.slopes.map(\.id) + model.ceilings.map(\.id) + model.floors.map(\.id)
            guard Set(ids).count == ids.count else { throw RoomModelError.invalidGeometry }
            func measurement(_ m: RoomMeasurement, zero: Bool = false) -> Bool {
                [m.rawValue, m.effectiveValue].allSatisfy { $0.isFinite && (zero ? $0 >= 0 : $0 > 0) && $0 <= 1000 }
            }
            for w in model.walls {
                guard w.start.finite, w.end.finite, w.direction.length > 0,
                      measurement(w.length), measurement(w.height), w.thickness.map({ measurement($0, zero: true) }) ?? true,
                      w.openingIDs.allSatisfy({ id in model.openings.contains { $0.id == id && $0.wallID == w.id } }) else { throw RoomModelError.invalidGeometry }
            }
            for o in model.openings {
                guard o.center.finite, measurement(o.width), measurement(o.height), measurement(o.sillHeight, zero: true),
                      o.positionOnWall.rawValue.isFinite, o.positionOnWall.effectiveValue.isFinite,
                      o.wallID.map({ id in model.walls.contains { $0.id == id && $0.openingIDs.contains(o.id) } }) ?? true else { throw RoomModelError.invalidGeometry }
            }
            for pan in model.slopes {
                guard [pan.plane.a,pan.plane.b,pan.plane.c].allSatisfy(\.isFinite), !pan.boundaries.isEmpty,
                      pan.boundaries.allSatisfy({ $0.count >= 3 && $0.count <= 10000 && $0.allSatisfy(\.finite) }) else { throw RoomModelError.invalidGeometry }
            }
            guard model.ceilings.allSatisfy({ c in c.slopeIDs.allSatisfy { id in model.slopes.contains { $0.id == id } } }),
                  model.floors.allSatisfy({ ($0.referenceElevation?.isFinite ?? true) && $0.boundaries.allSatisfy { $0.count >= 3 && $0.allSatisfy(\.finite) } }) else { throw RoomModelError.invalidGeometry }
        }
    }
}
enum PlaquistoRoomStore {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plaquisto/scanner-room-v1.json")
    }
    static func save(_ document: PlaquistoRoomDocument, to url: URL = defaultURL) throws {
        let data = try document.encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    static func load(from url: URL = defaultURL) throws -> PlaquistoRoomDocument {
        try .decode(Data(contentsOf: url))
    }
}
