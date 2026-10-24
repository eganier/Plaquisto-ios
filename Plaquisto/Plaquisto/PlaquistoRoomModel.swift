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
    /// Missing on older scans. Scanned walls are never reshaped by a ceiling;
    /// newly drawn partitions may explicitly adopt its upper profile.
    var localOutline: [RoomPoint]? = nil
    /// Explicit junction cuts only; keeps existing ouvrages linked to all pieces.
    var splitAncestorIDs: [UUID]? = nil
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
enum DoorPlanGeometry {
    static func hitDistance(point: RoomPoint, opening: PlaquistoOpening, wall: PlaquistoWall, tolerance: Double) -> Double? {
        let start = wall.start + wall.direction * opening.positionOnWall.effectiveValue
        let delta = point-start, width = opening.width.effectiveValue
        let along = min(width, max(0, delta.x*wall.direction.x+delta.z*wall.direction.z))
        let gap = (point-start-wall.direction*along).horizontalLength
        if gap < tolerance { return gap }
        guard opening.kind == .door, opening.isPocketDoor != true else { return nil }
        let side = opening.doorOpeningSide ?? .positive
        let atStart = hingeAtStart(handing: opening.doorHanding ?? .right, side: side)
        let rel = point - (start+wall.direction*(atStart ? 0 : width))
        let inward = (-rel.x*wall.direction.z+rel.z*wall.direction.x)*(side == .positive ? 1 : -1)
        let sweep = (rel.x*wall.direction.x+rel.z*wall.direction.z)*(atStart ? 1 : -1)
        return inward >= -tolerance && sweep >= -tolerance && rel.horizontalLength <= width+tolerance ? gap : nil
    }
    /// Handing is read from the side where the user pushes, not the receiving room.
    static func hingeAtStart(handing:DoorHanding,side:DoorOpeningSide) -> Bool {
        (handing == .right) == (side == .positive)
    }
    static func openingSide(point:RoomPoint,wall:PlaquistoWall,previous:DoorOpeningSide,
                            deadZone:Double) -> DoorOpeningSide {
        let delta=point-wall.start
        let distance = -delta.x*wall.direction.z+delta.z*wall.direction.x
        if distance>deadZone { return .positive }
        if distance < -deadZone { return .negative }
        return previous
    }
    struct Placement {
        var wallID:UUID
        var position:Double
        var center:RoomPoint
        var side:DoorOpeningSide
    }
    static func placement(point:RoomPoint,walls:[PlaquistoWall],width:Double,latchedWallID:UUID?,
                          previous:DoorOpeningSide,captureDistance:Double) -> Placement? {
        guard point.finite,width.isFinite,width>0,captureDistance>0 else { return nil }
        let eligible=walls.filter { $0.length.effectiveValue>=width }
        func distance(_ wall:PlaquistoWall) -> Double {
            let delta=point-wall.start
            let along=min(wall.length.effectiveValue,max(0,delta.x*wall.direction.x+delta.z*wall.direction.z))
            return (point-(wall.start+wall.direction*along)).horizontalLength
        }
        // Hysteresis: once attached, a sideways move changes the receiving room
        // instead of dropping the door or jumping to a nearby partition.
        let latched=eligible.first { $0.id==latchedWallID && distance($0)<max(0.6,captureDistance*4) }
        guard let wall=latched ?? eligible.filter({distance($0)<captureDistance}).min(by:{distance($0)<distance($1)}) else { return nil }
        let delta=point-wall.start
        let position=min(wall.length.effectiveValue-width,max(0,delta.x*wall.direction.x+delta.z*wall.direction.z-width/2))
        return .init(wallID:wall.id,position:position,center:wall.start+wall.direction*(position+width/2),
            side:openingSide(point:point,wall:wall,previous:previous,deadZone:min(0.04,captureDistance/4)))
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
    var doorHanding: DoorHanding? = nil
    var doorOpeningSide: DoorOpeningSide? = nil
    /// A pocket door remains a door for openings/quantities, without a swing arc.
    var isPocketDoor: Bool? = nil
    /// Preserve a calepinage-specific type (notably an access hatch) on round-trip.
    var layoutKind: LayoutOpeningKind? = nil
}
struct RoomPlane: Codable, Equatable {
    // Parametric plane y = a*x + b*z + c; a boundary is separate from the plane.
    var a: Double; var b: Double; var c: Double
    func height(x: Double, z: Double) -> Double { a*x+b*z+c }
    var slopeDegrees: Double { atan(hypot(a,b))*180 / .pi }
}
struct CeilingSplitOrigin: Codable, Equatable {
    var operationID: UUID
    var sourceSlopeID: UUID
    var ancestorSlopeIDs: [UUID]? = nil
    /// nil: legacy split without attribution; []: explicit manual cut or consumed divider.
    var partitionWallIDs: [UUID]? = nil
}
struct PlaquistoSlope: Codable, Equatable, Identifiable {
    var id = UUID()
    var plane: RoomPlane
    var boundaries: [[RoomPoint]]
    var provenance: GeometryProvenance
    var accepted = false
    var manuallyValidated = false
    var splitOrigin: CeilingSplitOrigin? = nil
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
    /// Presentation only. Geometry and existing work quantities remain intact.
    var isHidden: Bool? = nil
    var canConfigureShape: Bool { provenance.source == .estimated || provenance.source == .manual }
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
    /// Optional for older files. True means the walls could not determine the pitch/ridge height.
    var riseIsEstimated: Bool? = nil
    /// Explicit ceiling edit: extend the derived wall envelope, never overwrite scan measurements.
    var extendsWalls: Bool? = nil
    mutating func setSliderHeight(_ value: Double, isMinimum: Bool) {
        guard value.isFinite, value > 0 else { return }
        if shape == .flat {
            lowHeight = value; highHeight = value
        } else if isMinimum {
            lowHeight = value; highHeight = max(highHeight,value)
        } else {
            // The maximum stops at the minimum; it must never push it down.
            highHeight = max(lowHeight,value)
        }
    }
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
struct PlaquistoColumn: Codable, Equatable, Identifiable {
    var id = UUID()
    var center: RoomPoint
    var sideA: Double
    var sideB: Double
    var angle: Double
    var height: Double
    var isValid: Bool { center.finite && [sideA, sideB, height].allSatisfy { $0.isFinite && $0 > 0 && $0 <= 100 } && angle.isFinite }
    var axisA: RoomPoint { .init(x: cos(angle), y: 0, z: sin(angle)) }
    var axisB: RoomPoint { .init(x: -sin(angle), y: 0, z: cos(angle)) }
    var corners: [RoomPoint] {
        [center-axisA*(sideA/2)-axisB*(sideB/2), center+axisA*(sideA/2)-axisB*(sideB/2),
         center+axisA*(sideA/2)+axisB*(sideB/2), center-axisA*(sideA/2)+axisB*(sideB/2)]
    }
    var triangles: [RoomPoint] {
        let p = corners, up = RoomPoint(x: 0, y: height, z: 0)
        var result = [p[0], p[2], p[1], p[0], p[3], p[2], p[0]+up, p[1]+up, p[2]+up, p[0]+up, p[2]+up, p[3]+up]
        for i in 0..<4 { let a = p[i], b = p[(i+1)%4]; result += [a,b,b+up,a,b+up,a+up] }
        return result
    }
    func contains(_ point: RoomPoint, tolerance: Double = 0) -> Bool {
        let d = point-center
        return abs(d.x*axisA.x+d.z*axisA.z) <= sideA/2+tolerance && abs(d.x*axisB.x+d.z*axisB.z) <= sideB/2+tolerance
    }
    func clearances(walls: [PlaquistoWall]) -> [(start: RoomPoint, end: RoomPoint, distance: Double)] {
        [(axisA, sideA/2), (axisA * -1, sideA/2), (axisB, sideB/2), (axisB * -1, sideB/2)].compactMap { axis, half in
            let start = center + axis * half
            let distances = walls.compactMap { wall -> Double? in
                let edge = wall.effectiveEnd-wall.start, d = wall.start-start
                let det = axis.x*edge.z-axis.z*edge.x
                guard abs(det) > 1e-8 else { return nil }
                let t = (d.x*edge.z-d.z*edge.x)/det
                let u = (d.x*axis.z-d.z*axis.x)/det
                return t >= 0 && u >= 0 && u <= 1 ? t : nil
            }
            guard let distance = distances.min() else { return nil }
            return (start, start+axis*distance, distance)
        }
    }
}

struct PlaquistoRoomModel: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String? = nil
    var walls: [PlaquistoWall] = []
    var openings: [PlaquistoOpening] = []
    var ceilings: [PlaquistoCeiling] = []
    var floors: [PlaquistoFloor] = []
    var slopes: [PlaquistoSlope] = []
    var columns: [PlaquistoColumn]? = nil
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
            let ids = model.walls.map(\.id) + model.openings.map(\.id) + model.slopes.map(\.id) + model.ceilings.map(\.id) + model.floors.map(\.id) + (model.columns ?? []).map(\.id)
            guard Set(ids).count == ids.count else { throw RoomModelError.invalidGeometry }
            guard (model.columns ?? []).count <= 1000, (model.columns ?? []).allSatisfy(\.isValid) else { throw RoomModelError.invalidGeometry }
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
    /// Availability depends on valid geometry, not a second manual approval.
    var isUsableForWork: Bool { (try? document.validate()) != nil }
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
    var capturedAt: Date? = nil
    /// Address resolved from the capture location, independent of the project's address.
    var captureAddress: String? = nil
    var ceilingPlanNumbers: [String:Int]? = nil
    var scanDate: Date {
        capturedAt ?? captureLocation?.capturedAt
            ?? checkpoints.map { $0.document.initialRoom.metadata.createdAt }.filter { $0.timeIntervalSince1970 > 0 }.min()
            ?? createdAt
    }
}

extension PlaquistoRoomDocument {
    /// Deep identity copy used when duplicating a Project. Observation source IDs
    /// remain correlation metadata, while every Plaquisto domain ID is renewed.
    func remappingDomainIDs(preservingSplitHistory: Bool = false) -> Self {
        let models = [initialRoom, room]
        let roomIDs = Dictionary(uniqueKeysWithValues: Set(models.map(\.id)).map { ($0, UUID()) })
        let walls = models.flatMap(\.walls)
        let origins = models.flatMap(\.slopes).compactMap(\.splitOrigin)
        let historicalWalls = walls.flatMap { $0.splitAncestorIDs ?? [] } + origins.flatMap { $0.partitionWallIDs ?? [] }
        let wallIDs = Dictionary(uniqueKeysWithValues: Set(walls.map(\.id) + historicalWalls).map { ($0, UUID()) })
        let openingIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.openings).map(\.id)).map { ($0, UUID()) })
        let historicalSlopes = origins.map(\.sourceSlopeID) + origins.flatMap { $0.ancestorSlopeIDs ?? [] }
        let slopeIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.slopes).map(\.id) + historicalSlopes).map { ($0, UUID()) })
        let operationIDs = Dictionary(uniqueKeysWithValues: Set(origins.map(\.operationID)).map { ($0, UUID()) })
        let ceilingIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.ceilings).map(\.id)).map { ($0, UUID()) })
        let floorIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap(\.floors).map(\.id)).map { ($0, UUID()) })
        let columnIDs = Dictionary(uniqueKeysWithValues: Set(models.flatMap { $0.columns ?? [] }.map(\.id)).map { ($0, UUID()) })

        func copy(_ source: PlaquistoRoomModel) -> PlaquistoRoomModel {
            var result = source
            result.id = roomIDs[source.id]!
            result.walls = source.walls.map { wall in
                var value = wall
                value.id = wallIDs[wall.id]!
                value.openingIDs = wall.openingIDs.compactMap { openingIDs[$0] }
                value.splitAncestorIDs = wall.splitAncestorIDs?.compactMap { wallIDs[$0] }
                return value
            }
            result.openings = source.openings.map { opening in
                var value = opening
                value.id = openingIDs[opening.id]!
                value.wallID = opening.wallID.flatMap { wallIDs[$0] }
                return value
            }
            result.slopes = source.slopes.map { slope in
                var value = slope; value.id = slopeIDs[slope.id]!
                value.splitOrigin = nil
                if preservingSplitHistory, let origin = slope.splitOrigin {
                    value.splitOrigin = CeilingSplitOrigin(operationID: operationIDs[origin.operationID]!,
                        sourceSlopeID: slopeIDs[origin.sourceSlopeID]!,
                        ancestorSlopeIDs: origin.ancestorSlopeIDs?.compactMap { slopeIDs[$0] },
                        partitionWallIDs: origin.partitionWallIDs?.compactMap { wallIDs[$0] })
                }
                return value
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
            result.columns = source.columns?.map { column in var value = column; value.id = columnIDs[column.id]!; return value }
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
