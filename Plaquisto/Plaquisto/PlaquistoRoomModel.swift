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
    case roomPlan, arCore, lidar, manual, imported, estimated
    var title: String {
        switch self {
        case .roomPlan: return "RoomPlan"
        case .arCore: return "ARCore"
        case .lidar: return "LiDAR"
        case .manual: return "Manuelle"
        case .imported: return "Import"
        case .estimated: return "Estimation à partir des murs"
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
    /// Original polygon in wall-local metres: X along the wall, Y up, Z = 0.
    /// Missing on older scans; never inferred from a ceiling.
    var localOutline: [RoomPoint]? = nil
    var effectiveOutline: [RoomPoint] {
        let outline = localOutline ?? [RoomPoint(x:0,y:0,z:0),
            RoomPoint(x:length.rawValue,y:0,z:0),
            RoomPoint(x:length.rawValue,y:height.rawValue,z:0), RoomPoint(x:0,y:height.rawValue,z:0)]
        let sx = length.rawValue > 0 ? length.effectiveValue / length.rawValue : 1
        let sy = height.rawValue > 0 ? height.effectiveValue / height.rawValue : 1
        return outline.map { .init(x:$0.x*sx,y:$0.y*sy,z:0) }
    }
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
    var estimateSettings: CeilingEstimateSettings? = nil
    /// Editable footprint in the original room frame, not a measured ceiling.
    var footprint: [RoomPoint]? = nil
    var floorElevation: Double? = nil
    var planNumber: Int? = nil
}

enum CeilingPlanNaming {
    static func numbering(_ ceilings:[PlaquistoCeiling], existing:[String:Int]? = nil) -> [String:Int] {
        var result=existing ?? [:]
        var next=max(0,result.values.max() ?? 0)
        for ceiling in ceilings where result[ceiling.id.uuidString] == nil {
            next += 1; result[ceiling.id.uuidString]=next
        }
        return result
    }
    static func numbers(in survey:ProjectSurveyRecord) -> [String:Int] {
        numbering(survey.checkpoints.flatMap { $0.document.room.ceilings },existing:survey.ceilingPlanNumbers)
    }
    static func title(_ ceiling:PlaquistoCeiling,in room:PlaquistoRoomModel,numbers:[String:Int]) -> String {
        let local=numbering(room.ceilings,existing:numbers)
        return "Plafond "+letters(local[ceiling.id.uuidString] ?? 1)
    }
    static func letters(_ number: Int) -> String {
        var n = max(1, number), result = ""
        while n > 0 { n -= 1; result = String(UnicodeScalar(65+n%26)!) + result; n /= 26 }
        return result
    }
    static func title(_ ceiling: PlaquistoCeiling, in room: PlaquistoRoomModel) -> String {
        "Plafond " + letters(ceiling.planNumber ?? ((room.ceilings.firstIndex { $0.id == ceiling.id } ?? 0)+1))
    }
}

/// Portable editing parameters. These describe an assumption, never a LiDAR observation.
struct CeilingEstimateSettings: Codable, Equatable {
    enum Shape: String, Codable, CaseIterable, Identifiable {
        case flat, singleSlope, twoSlopes, fourSlopes
        var id: String { rawValue }
        var title: String {
            switch self {
            case .flat: "Plat"
            case .singleSlope: "Un pan"
            case .twoSlopes: "Deux pans"
            case .fourSlopes: "Quatre pans"
            }
        }
    }
    var shape: Shape = .flat
    var lowHeight: Double
    var highHeight: Double
    var azimuth: Double = 0
    var ridgePosition: Double = 0.5
    var isValid: Bool {
        [lowHeight, highHeight, azimuth, ridgePosition].allSatisfy(\.isFinite)
            && lowHeight > 0 && highHeight >= lowHeight && highHeight <= 1000
            && (0.15...0.85).contains(ridgePosition)
    }
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
                if let outline=w.localOutline {
                    guard outline.count>=3, outline.count<=10000, outline.allSatisfy(\.finite) else { throw RoomModelError.invalidGeometry }
                }
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
            guard model.ceilings.allSatisfy({ c in (c.estimateSettings?.isValid ?? true) && c.slopeIDs.allSatisfy { id in model.slopes.contains { $0.id == id } } }),
                  model.floors.allSatisfy({ ($0.referenceElevation?.isFinite ?? true) && $0.boundaries.allSatisfy { $0.count >= 3 && $0.allSatisfy(\.finite) } }) else { throw RoomModelError.invalidGeometry }
        }
    }
}

/// Portable transform from one room checkpoint into the survey coordinate space.
/// Values are a column-major 4 × 4 matrix, matching the convention used at the
/// acquisition boundaries without persisting a SIMD or Apple framework type.
struct SurveyTransform3D: Codable, Equatable {
    var values: [Double]

    static let identity = SurveyTransform3D(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    ])

    var isValid: Bool {
        guard values.count == 16, values.allSatisfy(\.isFinite) else { return false }
        let epsilon = 1e-6
        guard abs(values[3]) < epsilon, abs(values[7]) < epsilon,
              abs(values[11]) < epsilon, abs(values[15] - 1) < epsilon else { return false }
        // A survey placement is rigid: it must never rescale measured dimensions.
        let axes = (0..<3).map { column in (0..<3).map { values[column * 4 + $0] } }
        for i in 0..<3 {
            for j in i..<3 {
                let dot = (0..<3).reduce(0.0) { $0 + axes[i][$1] * axes[j][$1] }
                guard abs(dot - (i == j ? 1 : 0)) < epsilon else { return false }
            }
        }
        let determinant = axes[0][0] * (axes[1][1] * axes[2][2] - axes[1][2] * axes[2][1])
            - axes[1][0] * (axes[0][1] * axes[2][2] - axes[0][2] * axes[2][1])
            + axes[2][0] * (axes[0][1] * axes[1][2] - axes[0][2] * axes[1][1])
        return abs(determinant - 1) < epsilon
    }
}

enum SurveyLifecycleState: String, Codable, CaseIterable {
    case draft
    case readyForReview
    case validated
}

enum SurveySpatialLinkState: String, Codable, CaseIterable {
    /// The acquisition adapter guarantees that this checkpoint shares the
    /// survey world space (continuous or successfully relocalized session).
    case sharedWorldSpace
    /// The room is deliberately kept usable on its own; no transform is invented.
    case needsLink
    /// A user-approved transform aligns this room with the survey.
    case manuallyAligned
}

/// Controls whether a checkpoint may feed a trade configuration. This is kept
/// separate from `needsReview`: review can also cover naming or spatial linking,
/// while this state specifically prevents provisional geometry becoming a quote.
enum SurveyCheckpointWorkState: String, Codable, CaseIterable {
    /// Portable live checkpoint saved before the acquisition adapter finished
    /// refining the room. It may be recovered and inspected, never silently used.
    case provisional
    /// Processing completed, or the user corrected the geometry. An explicit
    /// confirmation is still required before creating an ouvrage from it.
    case awaitingValidation
    /// The user explicitly accepted this checkpoint as a métier input.
    case validated
}

/// One completed room capture. A checkpoint is portable and remains usable when
/// StructureBuilder cannot assemble the whole property.
struct ProjectRoomScanCheckpoint: Codable, Equatable, Identifiable {
    var id = UUID()
    var roomID: UUID
    var document: PlaquistoRoomDocument
    var transformToSurvey = SurveyTransform3D.identity
    var spatialLinkState: SurveySpatialLinkState
    var needsReview = true
    /// Optional for backward decoding. Historical checkpoints may have lost the
    /// acquisition's provisional flag: require review rather than invent approval.
    var workState: SurveyCheckpointWorkState? = nil
    var createdAt = Date()
    var updatedAt = Date()

    var effectiveWorkState: SurveyCheckpointWorkState { workState ?? .awaitingValidation }
    var isUsableForWork: Bool { effectiveWorkState == .validated }
}

/// A project-bound 3D survey. Apple acquisition artefacts are intentionally absent:
/// Android or an imported geometry adapter can produce the same record.
/// Optional one-shot position captured on site, never inferred at save time.
struct ScanLocationFix: Codable, Equatable {
    var latitude:Double
    var longitude:Double
    var horizontalAccuracy:Double
    var capturedAt:Date
    func isUsable(at date:Date) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
            && (-180...180).contains(longitude) && horizontalAccuracy.isFinite
            && horizontalAccuracy >= 0 && horizontalAccuracy <= 100
            && abs(capturedAt.timeIntervalSince(date)) <= 30
    }
}

struct ProjectSurveyRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var projectID: UUID
    var name: String
    var levelName: String? = nil
    var state: SurveyLifecycleState = .draft
    var checkpoints: [ProjectRoomScanCheckpoint] = []
    var createdAt = Date()
    var updatedAt = Date()
    /// Original capture report; optional for archives created before diagnostics.
    var captureDiagnostic: String? = nil
    var captureLocation: ScanLocationFix? = nil
    var ceilingPlanNumbers: [String:Int]? = nil
}

extension PlaquistoRoomDocument {
    /// Deep identity copy used when duplicating a Project. Observation source IDs
    /// remain correlation metadata, while every Plaquisto domain ID is renewed.
    func remappingDomainIDs() -> Self {
        let models = [initialRoom, room]
        let roomIDs = Dictionary(uniqueKeysWithValues: Set(models.map(\.id)).map { ($0, UUID()) })
        let wallIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.walls).map(\.id)).map { ($0, UUID()) })
        let openingIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.openings).map(\.id)).map { ($0, UUID()) })
        let slopeIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.slopes).map(\.id)).map { ($0, UUID()) })
        let ceilingIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.ceilings).map(\.id)).map { ($0, UUID()) })
        let floorIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.floors).map(\.id)).map { ($0, UUID()) })

        func copy(_ source: PlaquistoRoomModel) -> PlaquistoRoomModel {
            var result = source
            result.id = roomIDs[source.id]!
            result.walls = source.walls.map { wall in
                var value = wall
                value.id = wallIDs[wall.id]!
                value.openingIDs = wall.openingIDs.compactMap { openingIDs[$0] }
                return value
            }
            result.openings = source.openings.map { opening in
                var value = opening
                value.id = openingIDs[opening.id]!
                value.wallID = opening.wallID.flatMap { wallIDs[$0] }
                return value
            }
            result.slopes = source.slopes.map { slope in
                var value = slope; value.id = slopeIDs[slope.id]!; return value
            }
            result.ceilings = source.ceilings.map { ceiling in
                var value = ceiling
                value.id = ceilingIDs[ceiling.id]!
                value.slopeIDs = ceiling.slopeIDs.compactMap { slopeIDs[$0] }
                return value
            }
            result.floors = source.floors.map { floor in
                var value = floor; value.id = floorIDs[floor.id]!; return value
            }
            return result
        }

        let copiedInitial = copy(initialRoom)
        var copied = PlaquistoRoomDocument(room: copiedInitial)
        copied.schemaVersion = schemaVersion
        copied.room = copy(room)
        copied.wallWorkIntents = wallWorkIntents?.compactMap { intent in
            guard let wallID = wallIDs[intent.wallID] else { return nil }
            return WallWorkIntent(wallID: wallID, use: intent.use)
        }
        return copied
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
