import Foundation

/// Metres, acquisition-neutral. All edits return a validated copy and preserve
/// the original scan. The caller owns Save/Cancel and downstream review warnings.
enum SurveyPlanEditing {
    enum Failure: Error, LocalizedError {
        case missingWall, invalidSize, openingOutside, overlappingOpening, crossingWalls, incompatibleMerge
        var errorDescription: String? {
            switch self {
            case .missingWall: "Sélectionnez un mur ou une cloison."
            case .invalidSize: "Renseignez des dimensions positives et un segment d’au moins 10 cm."
            case .openingOutside: "Une ouverture dépasserait du mur. Corrigez sa position ou ses dimensions."
            case .overlappingOpening: "Cette porte chevauche une autre ouverture."
            case .crossingWalls: "Cette modification ferait se croiser des murs. Déplacez leur extrémité jusqu’à la jonction souhaitée."
            case .incompatibleMerge: "Seuls deux murs contigus, dans le même alignement et partageant le même bord peuvent être fusionnés sans déformer le scan."
            }
        }
    }
    static let doorWidths: [Double] = [0.73, 0.83, 0.93]

    static func changingWall(_ document: PlaquistoRoomDocument, id: UUID,
                             start: RoomPoint, end: RoomPoint, height: Double) throws -> PlaquistoRoomDocument {
        guard let old = document.room.walls.first(where: { $0.id == id }) else { throw Failure.missingWall }
        guard start.finite, end.finite, height.isFinite, height > 0, height <= 100,
              hypot(end.x-start.x, end.z-start.z) >= 0.1 else { throw Failure.invalidSize }
        var result = document
        let a = RoomPoint(x: start.x, y: old.start.y, z: start.z)
        let b = RoomPoint(x: end.x, y: old.end.y, z: end.z)
        func moved(_ p: RoomPoint) -> RoomPoint {
            if (p-old.start).length < 0.03 { return a }
            if (p-old.effectiveEnd).length < 0.03 { return b }
            return p
        }
        var affected = Set<UUID>()
        for i in result.room.walls.indices {
            let wall = result.room.walls[i]
            let nextA = wall.id == id ? a : moved(wall.start)
            let nextB = wall.id == id ? b : moved(wall.effectiveEnd)
            if wall.id == id || nextA != wall.start || nextB != wall.effectiveEnd {
                guard hypot(nextB.x-nextA.x, nextB.z-nextA.z) >= 0.1 else { throw Failure.invalidSize }
                result.room.walls[i].start = nextA; result.room.walls[i].end = nextB
                try result.room.walls[i].length.correct(hypot(nextB.x-nextA.x, nextB.z-nextA.z))
                affected.insert(wall.id)
            }
            if wall.id == id, abs(height-wall.height.effectiveValue)>1e-8 { try result.room.walls[i].height.correct(height) }
        }
        for i in result.room.floors.indices {
            result.room.floors[i].boundaries = result.room.floors[i].boundaries.map { $0.map(moved) }
        }
        for i in result.room.openings.indices {
            guard let wallID = result.room.openings[i].wallID, affected.contains(wallID),
                  let wall = result.room.walls.first(where: { $0.id == wallID }) else { continue }
            try validateOpening(result.room.openings[i], wall: wall)
            result.room.openings[i].center = openingCenter(result.room.openings[i], wall: wall)
        }
        // Refuse newly introduced crossings, while leaving pre-existing scan
        // imperfections editable. T-junctions at segment endpoints are allowed.
        for i in result.room.walls.indices {
            for j in result.room.walls.indices where j > i {
                if crosses(result.room.walls[i], result.room.walls[j]),
                   !crosses(document.room.walls[i], document.room.walls[j]) { throw Failure.crossingWalls }
            }
        }
        // Ceiling resizing is deliberately not implicit: the editor exposes an
        // explicit ceiling action, and the caller warns that it needs review.
        try result.validate(); return result
    }

    static func addingPartition(_ document: PlaquistoRoomDocument, start: RoomPoint,
                                end: RoomPoint, height: Double) throws -> PlaquistoRoomDocument {
        guard start.finite, end.finite, height.isFinite, height > 0, height <= 100,
              hypot(end.x-start.x, end.z-start.z) >= 0.1 else { throw Failure.invalidSize }
        var result = document
        let source = GeometryProvenance(source: .manual)
        let wall = PlaquistoWall(start: start, end: .init(x: end.x, y: start.y, z: end.z),
            length: .init(rawValue: hypot(end.x-start.x, end.z-start.z), provenance: source, manuallyValidated: true),
            height: .init(rawValue: height, provenance: source, manuallyValidated: true), provenance: source)
        result.room.walls.append(wall)
        result.wallWorkIntents = (result.wallWorkIntents ?? []) + [.init(wallID: wall.id, use: .partition)]
        try result.validate(); return result
    }

    static func addingDoor(_ document: PlaquistoRoomDocument, wallID: UUID,
                           width: Double, height: Double, position: Double) throws -> PlaquistoRoomDocument {
        guard doorWidths.contains(where: { abs($0-width) < 1e-6 }) else { throw Failure.invalidSize }
        guard let wall = document.room.walls.first(where: { $0.id == wallID }) else { throw Failure.missingWall }
        let source = GeometryProvenance(source: .manual)
        var opening = PlaquistoOpening(wallID: wallID, kind: .door, center: .zero,
            width: .init(rawValue: width, provenance: source, manuallyValidated: true),
            height: .init(rawValue: height, provenance: source, manuallyValidated: true),
            sillHeight: .init(rawValue: 0, provenance: source, manuallyValidated: true),
            positionOnWall: .init(rawValue: position, provenance: source, manuallyValidated: true), provenance: source)
        try validateOpening(opening, wall: wall)
        try checkOverlap(opening, in: document)
        opening.center = openingCenter(opening, wall: wall)
        var result = document
        result.room.openings.append(opening)
        let index = result.room.walls.firstIndex { $0.id == wallID }!
        result.room.walls[index].openingIDs.append(opening.id)
        try result.validate(); return result
    }

    static func movingDoor(_ document: PlaquistoRoomDocument, id: UUID, position: Double) throws -> PlaquistoRoomDocument {
        var result = document
        guard let i = result.room.openings.firstIndex(where: { $0.id == id }),
              let wall = result.room.walls.first(where: { $0.id == result.room.openings[i].wallID }) else { throw Failure.missingWall }
        result.room.openings[i].positionOnWall.manualValue = position
        result.room.openings[i].positionOnWall.manuallyValidated = true
        try validateOpening(result.room.openings[i], wall: wall)
        try checkOverlap(result.room.openings[i], in: result)
        result.room.openings[i].center = openingCenter(result.room.openings[i], wall: wall)
        try result.validate(); return result
    }

    static func changingOpening(_ document: PlaquistoRoomDocument, id: UUID,
                                width: Double, height: Double, sill: Double, position: Double) throws -> PlaquistoRoomDocument {
        var result=document
        guard let i=result.room.openings.firstIndex(where: { $0.id==id }),
              let wall=result.room.walls.first(where: { $0.id==result.room.openings[i].wallID }) else { throw Failure.missingWall }
        try result.room.openings[i].width.correct(width)
        try result.room.openings[i].height.correct(height)
        result.room.openings[i].sillHeight.manualValue=sill
        result.room.openings[i].sillHeight.manuallyValidated=true
        result.room.openings[i].positionOnWall.manualValue=position
        result.room.openings[i].positionOnWall.manuallyValidated=true
        try validateOpening(result.room.openings[i],wall:wall)
        try checkOverlap(result.room.openings[i],in:result)
        result.room.openings[i].center=openingCenter(result.room.openings[i],wall:wall)
        try result.validate(); return result
    }

    static func removingOpening(_ document: PlaquistoRoomDocument, id: UUID) throws -> PlaquistoRoomDocument {
        var result=document
        result.room.openings.removeAll { $0.id==id }
        for i in result.room.walls.indices { result.room.walls[i].openingIDs.removeAll { $0==id } }
        try result.validate(); return result
    }

    /// Explicit, conservative union: never bridge a gap or flatten a rampant.
    /// The original scan remains in initialRoom. The first wall keeps its ID.
    static func mergingWalls(_ document: PlaquistoRoomDocument, first: UUID, second: UUID) throws -> PlaquistoRoomDocument {
        guard first != second, let a=document.room.walls.first(where: { $0.id==first }),
              let b=document.room.walls.first(where: { $0.id==second }) else { throw Failure.missingWall }
        let useA=document.wallWorkIntents?.first { $0.wallID==first }?.use
        let useB=document.wallWorkIntents?.first { $0.wallID==second }?.use
        guard useA==useB else { throw Failure.incompatibleMerge }
        if let ta=a.thickness?.effectiveValue, let tb=b.thickness?.effectiveValue,
           abs(ta-tb)>0.005 { throw Failure.incompatibleMerge }
        func local(_ p:RoomPoint) -> RoomPoint {
            let v=p-a.start
            return .init(x:v.x*a.direction.x+v.z*a.direction.z,y:v.y,z:0)
        }
        let delta=b.start-a.start
        guard abs(a.direction.x*b.direction.z-a.direction.z*b.direction.x)<0.001,
              abs(delta.x*a.direction.z-delta.z*a.direction.x)<0.005 else { throw Failure.incompatibleMerge }
        let pa=a.effectiveOutline
        let pb=b.effectiveOutline.map { local(b.start+b.direction*$0.x+RoomPoint(x:0,y:$0.y,z:0)) }
        func oriented(_ points:[RoomPoint]) -> [RoomPoint] {
            let area=points.indices.reduce(0.0) { sum,i in
                let p=points[i],q=points[(i+1)%points.count]; return sum+p.x*q.y-q.x*p.y
            }
            return area<0 ? points.reversed() : points
        }
        let p=oriented(pa), q=oriented(pb)
        func close(_ x:RoomPoint,_ y:RoomPoint) -> Bool { (x-y).length<0.005 }
        var seam:(Int,Int)?
        for i in p.indices where abs(p[i].x-p[(i+1)%p.count].x)<1e-6 {
            for j in q.indices where close(p[i],q[(j+1)%q.count]) && close(p[(i+1)%p.count],q[j]) { seam=(i,j) }
        }
        guard let (i,j)=seam else { throw Failure.incompatibleMerge }
        var outline=(1...p.count).map { p[(i+$0)%p.count] }
        outline += (2..<q.count).map { q[(j+$0)%q.count] }
        let minX=outline.map(\.x).min()!, maxX=outline.map(\.x).max()!
        let minY=outline.map(\.y).min()!, maxY=outline.map(\.y).max()!
        guard maxX-minX>0.1, maxY-minY>0 else { throw Failure.incompatibleMerge }
        let source=GeometryProvenance(source:.manual)
        let origin=a.start+a.direction*minX+RoomPoint(x:0,y:minY,z:0)
        var merged=PlaquistoWall(id:first,start:origin,end:origin+a.direction*(maxX-minX),
            length:.init(rawValue:maxX-minX,provenance:source,manuallyValidated:true),
            height:.init(rawValue:maxY-minY,provenance:source,manuallyValidated:true),thickness:a.thickness ?? b.thickness,provenance:source,
            localOutline:outline.map { .init(x:$0.x-minX,y:$0.y-minY,z:0) })
        var result=document
        for k in result.room.openings.indices {
            let opening=result.room.openings[k]
            guard opening.wallID==first || opening.wallID==second else { continue }
            let old=opening.wallID==first ? a : b
            let left=old.start+old.direction*opening.positionOnWall.effectiveValue
            let right=left+old.direction*opening.width.effectiveValue
            result.room.openings[k].wallID=first
            result.room.openings[k].positionOnWall.manualValue=min(local(left).x,local(right).x)-minX
            result.room.openings[k].positionOnWall.manuallyValidated=true
            result.room.openings[k].sillHeight.manualValue=old.start.y+opening.sillHeight.effectiveValue-origin.y
            result.room.openings[k].sillHeight.manuallyValidated=true
            result.room.openings[k].center=openingCenter(result.room.openings[k],wall:merged)
            try validateOpening(result.room.openings[k],wall:merged)
        }
        merged.openingIDs=result.room.openings.filter { $0.wallID==first }.map(\.id)
        result.room.walls.removeAll { $0.id==second }
        result.room.walls[result.room.walls.firstIndex { $0.id==first }!]=merged
        result.wallWorkIntents?.removeAll { $0.wallID==second }
        for opening in result.room.openings where opening.wallID==first { try checkOverlap(opening,in:result) }
        try result.validate(); return result
    }

    static func suggestedHeight(in room: PlaquistoRoomModel, at point: RoomPoint) -> Double {
        if let slope = room.slopes.first(where: { $0.accepted && $0.boundaries.first.map { PlaquistoWallGeometry.contains(point, polygon: $0) } == true }) {
            return max(0.1, slope.plane.height(x: point.x, z: point.z)-point.y)
        }
        return room.walls.map { $0.height.effectiveValue }.sorted().dropFirst(room.walls.count/2).first ?? 2.5
    }
    private static func validateOpening(_ opening: PlaquistoOpening, wall: PlaquistoWall) throws {
        let x = opening.positionOnWall.effectiveValue, w = opening.width.effectiveValue
        let h = opening.height.effectiveValue, sill = opening.sillHeight.effectiveValue
        guard [x,w,h,sill].allSatisfy(\.isFinite), x >= 0, w > 0, h > 0, sill >= 0,
              x+w <= wall.length.effectiveValue+1e-6, sill+h <= wall.height.effectiveValue+1e-6 else { throw Failure.openingOutside }
        // Test the actual wall outline (including ramps), not its bounding box.
        let empty=PlaquistoRoomModel(metadata:.init(source:.manual))
        let strips=PlaquistoWallGeometry.analyze(wall:wall,room:empty).strips
        var covered=0.0
        for s in strips {
            let lo=max(x,s.x0), hi=min(x+w,s.x1)
            guard hi>lo else { continue }
            func interpolate(_ a:Double,_ b:Double,_ t:Double) -> Double { a+(b-a)*(t-s.x0)/(s.x1-s.x0) }
            if [lo,hi].allSatisfy({ t in
                sill>=interpolate(s.b0,s.b1,t)-1e-6 && sill+h<=interpolate(s.h0,s.h1,t)+1e-6
            }) { covered += hi-lo }
        }
        guard covered>=w-1e-6 else { throw Failure.openingOutside }
    }
    private static func openingCenter(_ opening: PlaquistoOpening, wall: PlaquistoWall) -> RoomPoint {
        wall.start + wall.direction * (opening.positionOnWall.effectiveValue+opening.width.effectiveValue/2)
            + RoomPoint(x: 0, y: opening.sillHeight.effectiveValue+opening.height.effectiveValue/2, z: 0)
    }
    private static func checkOverlap(_ opening: PlaquistoOpening, in document: PlaquistoRoomDocument) throws {
        let x = opening.positionOnWall.effectiveValue, w = opening.width.effectiveValue
        guard !document.room.openings.contains(where: { old in
            old.id != opening.id && old.wallID == opening.wallID &&
            min(x+w, old.positionOnWall.effectiveValue+old.width.effectiveValue) > max(x, old.positionOnWall.effectiveValue)+1e-6 &&
            min(opening.sillHeight.effectiveValue+opening.height.effectiveValue, old.sillHeight.effectiveValue+old.height.effectiveValue)
                > max(opening.sillHeight.effectiveValue, old.sillHeight.effectiveValue)
        }) else { throw Failure.overlappingOpening }
    }
    private static func crosses(_ a: PlaquistoWall, _ b: PlaquistoWall) -> Bool {
        func side(_ p: RoomPoint, _ q: RoomPoint, _ r: RoomPoint) -> Double {
            (q.x-p.x)*(r.z-p.z)-(q.z-p.z)*(r.x-p.x)
        }
        return side(a.start,a.effectiveEnd,b.start)*side(a.start,a.effectiveEnd,b.effectiveEnd) < -1e-10 &&
            side(b.start,b.effectiveEnd,a.start)*side(b.start,b.effectiveEnd,a.effectiveEnd) < -1e-10
    }
}

/// Acquisition-neutral proposals, not a claim that a semantic zone has walls.
enum ScanRoomUsage: String, Codable, CaseIterable {
    case livingRoom, bedroom, bathroom, kitchen, diningRoom, unidentified
    var title: String {
        switch self {
        case .livingRoom: "Salon"
        case .bedroom: "Chambre"
        case .bathroom: "Salle de bains"
        case .kitchen: "Cuisine"
        case .diningRoom: "Salle à manger"
        case .unidentified: "Pièce à identifier"
        }
    }
    static func proposedName(_ usages: [Self]) -> String {
        let known = Self.allCases.filter { $0 != .unidentified && usages.contains($0) }
        return known.isEmpty ? Self.unidentified.title : known.map(\.title).joined(separator: " / ")
    }
}

struct ScanRoomChunk: Codable, Equatable, Identifiable {
    var id = UUID()
    var referenceGroupID: UUID
    var name: String
    var usages: [ScanRoomUsage]
    var document: PlaquistoRoomDocument
    var needsReview = true
    var capturedAt = Date()
    var possibleDuplicateOf: UUID? = nil
    /// Nil for an unresolved revisit; never silently throw away an acquisition.
    var keepAfterReview: Bool? = nil
    /// Live checkpoint saved before RoomBuilder. Nil decodes older, processed drafts.
    var processingPending: Bool? = nil
}

/// Durable checkpoints survive cancellation, processing errors and app relaunch.
/// A recovered draft can be reviewed, NOT resumed in AR without relocalization.
struct ScanCampaignDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var chunks: [ScanRoomChunk] = []
    var continuityReliable = true
    var isComplete = false
    var assemblyMessage: String?
    /// Raw RoomBuilder outputs are NOT an assembled building. Older drafts must
    /// also be reviewed separately until an actual StructureBuilder result is applied.
    var assemblyVerified: Bool? = nil
    /// Optional for old saves. Events explain tracking/transition decisions,
    /// without recording camera images or a continuous user trajectory.
    var captureEvents: [ScanCaptureEvent]? = nil
    /// Bounded capture diagnostics, persisted independently of the scanner screen.
    var captureDiagnostic: String? = nil
    var captureLocation: ScanLocationFix? = nil
    var ceilingPlanNumbers: [String:Int]? = nil

    var sharesWorldSpace: Bool {
        continuityReliable && Set(chunks.map(\.referenceGroupID)).count == 1
            && (chunks.count == 1 || assemblyVerified == true)
    }
    var includedChunks: [ScanRoomChunk] { chunks.filter { $0.keepAfterReview != false } }
    var hasUnreviewedDuplicates: Bool { chunks.contains { $0.possibleDuplicateOf != nil && $0.keepAfterReview == nil } }

    mutating func append(_ chunk: ScanRoomChunk) {
        assemblyVerified = false
        var chunk = chunk
        let base = chunk.name
        var suffix = 2
        while chunks.contains(where: { $0.name == chunk.name }) {
            chunk.name = "\(base) \(suffix)"; suffix += 1
        }
        chunk.document.room.name = chunk.name
        chunks.append(chunk)
    }

    /// Processing enriches the same checkpoint; it must not append a second room
    /// or erase the user's review decisions/name when the async result arrives.
    mutating func upsert(_ chunk: ScanRoomChunk, preserveName: Bool = true) {
        assemblyVerified = false
        guard let index = chunks.firstIndex(where: { $0.id == chunk.id }) else {
            append(chunk); return
        }
        var replacement = chunk
        if preserveName || chunk.usages.filter({ $0 != .unidentified }).isEmpty {
            replacement.name = chunks[index].name
        } else {
            let base = chunk.name
            var suffix = 2
            while chunks.contains(where: { $0.id != chunk.id && $0.name == replacement.name }) {
                replacement.name = "\(base) \(suffix)"; suffix += 1
            }
        }
        replacement.document.room.name = replacement.name
        replacement.keepAfterReview = chunks[index].keepAfterReview
        replacement.possibleDuplicateOf = replacement.possibleDuplicateOf ?? chunks[index].possibleDuplicateOf
        chunks[index] = replacement
    }

    func validate() throws {
        guard Set(chunks.map(\.id)).count == chunks.count,
              Set(chunks.map { $0.document.room.id }).count == chunks.count else { throw RoomModelError.invalidGeometry }
        for chunk in chunks {
            guard !chunk.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RoomModelError.invalidGeometry }
            try chunk.document.validate()
        }
    }

}

/// Export only technical scan data. No photos, raw mesh, client or address.
struct ScanDiagnosticExport: Identifiable {
    let id = UUID()
    let url: URL
    let limited: Bool

    static func data(draft: ScanCampaignDraft, survey: ProjectSurveyRecord?) throws -> (Data, Bool) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let diagnostic = survey?.captureDiagnostic ?? draft.captureDiagnostic
        let capture = diagnostic.flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let rooms = survey?.checkpoints.map(\.document.room) ?? draft.chunks.map(\.document.room)
        // Names are user-entered and unnecessary for reconstruction diagnostics.
        let geometry = try rooms.map { room -> Any in
            var anonymous = room; anonymous.name = nil
            return try JSONSerialization.jsonObject(with: encoder.encode(anonymous))
        }
        let report: [String: Any] = [
            "format": "plaquisto-diagnostic-export-v1",
            "scanID": draft.id.uuidString,
            "availability": capture == nil ? "partial" : "capture_recorded",
            "notice": capture == nil
                ? "Diagnostic partiel : les tentatives de détection et compteurs LiDAR n’ont pas été conservés pour ce scan. Leur absence ne signifie pas zéro observation."
                : "Diagnostic enregistré pendant la capture. Les tentatives sont limitées aux 120 dernières ; la géométrie actuelle peut avoir été modifiée ensuite.",
            "capture": capture as Any? ?? NSNull(),
            "captureEvents": try JSONSerialization.jsonObject(with: encoder.encode(draft.captureEvents ?? [])),
            "currentGeometry": geometry
        ]
        return (try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), capture == nil)
    }

    static func prepare(draft: ScanCampaignDraft, survey: ProjectSurveyRecord?) throws -> Self {
        // A project opens with an ID-only draft; recover its original capture if available.
        var source = draft
        if survey?.captureDiagnostic == nil, draft.captureDiagnostic == nil,
           let saved = try ScanCampaignStore.load(id: draft.id) { source = saved }
        let (data, limited) = try data(draft: source, survey: survey)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Plaquisto-diagnostic-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return .init(url: url, limited: limited)
    }
}

struct ScanCaptureEvent: Codable, Equatable {
    var date = Date()
    let roomID: UUID
    let name: String
    let detail: String
}

struct ScanLiveOverview: Equatable {
    struct Entry: Equatable, Identifiable {
        let id: UUID
        var room: PlaquistoRoomModel
        var isProcessing: Bool
        var revision = UUID()
    }
    private(set) var entries: [Entry] = []
    var wallCount: Int { entries.reduce(0) { $0 + $1.room.walls.count } }

    mutating func update(id: UUID, room: PlaquistoRoomModel, isProcessing: Bool = false) {
        guard !room.walls.isEmpty || !room.floors.isEmpty else { return }
        let entry = Entry(id: id, room: room, isProcessing: isProcessing)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            if entries[index].room != room || entries[index].isProcessing != isProcessing { entries[index] = entry }
        } else { entries.append(entry) }
    }

    init() {}
    init(draft: ScanCampaignDraft) {
        for chunk in draft.includedChunks {
            update(id: chunk.id, room: chunk.document.room, isProcessing: chunk.processingPending == true)
        }
    }
}

enum ScanCampaignStore {
    struct RecoveryResult {
        var drafts: [ScanCampaignDraft] = []
        var unreadableFiles: [String] = []
    }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plaquisto/ScanDrafts", isDirectory: true)
    }
    static func save(_ draft: ScanCampaignDraft, directory: URL = directory) throws {
        try draft.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(draft).write(to: directory.appendingPathComponent(draft.id.uuidString + ".json"), options: .atomic)
    }
    static func loadAll(directory: URL = directory) throws -> [ScanCampaignDraft] {
        try recover(directory: directory).drafts
    }

    static func load(id: UUID, directory: URL = directory) throws -> ScanCampaignDraft? {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanCampaignDraft.self, from: Data(contentsOf: url))
    }

    /// One damaged file must not hide the other recoverable surveys. Never delete it.
    static func recover(directory: URL = directory) throws -> RecoveryResult {
        guard FileManager.default.fileExists(atPath: directory.path) else { return RecoveryResult() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var result = RecoveryResult()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) {
            do {
                let draft = try decoder.decode(ScanCampaignDraft.self, from: Data(contentsOf: url))
                try draft.validate(); result.drafts.append(draft)
            } catch { result.unreadableFiles.append(url.lastPathComponent) }
        }
        result.drafts.sort { $0.createdAt > $1.createdAt }
        return result
    }

    static func completing(_ draft: ScanCampaignDraft, directory: URL = directory) throws -> ScanCampaignDraft {
        var completed = draft
        completed.isComplete = true
        try save(completed, directory: directory)
        return completed
    }
}

/// Horizontal projection of the SAME corrected geometry used by the 3D survey.
/// No invented wall closure, door swing or duplicate geometry archive.
struct ScanFloorPlan {
    struct Segment {
        var a: RoomPoint; var b: RoomPoint
        var opening: RoomOpeningKind? = nil
    }
    struct Dimension { var a: RoomPoint; var b: RoomPoint; var meters: Double }
    struct Region { var name: String; var rings: [[RoomPoint]] }
    var segments: [Segment] = []
    var dimensions: [Dimension] = []
    var regions: [Region] = []
    var points: [RoomPoint] {
        segments.flatMap { [$0.a, $0.b] } + regions.flatMap(\.rings).flatMap { $0 }
    }

    init(overview: ScanLiveOverview, transforms: [UUID: SurveyTransform3D] = [:]) {
        for entry in overview.entries {
            let t = (transforms[entry.id] ?? .identity).values
            func project(_ p: RoomPoint) -> RoomPoint {
                .init(x: t[0]*p.x + t[4]*p.y + t[8]*p.z + t[12], y: 0,
                      z: t[2]*p.x + t[6]*p.y + t[10]*p.z + t[14])
            }
            let room = entry.room
            regions.append(.init(name: room.name ?? "", rings: room.floors.flatMap(\.boundaries).map { $0.map(project) }))
            for wall in room.walls {
                let length = wall.length.effectiveValue
                guard length.isFinite, length > 0 else { continue }
                func at(_ x: Double) -> RoomPoint { project(wall.start + wall.direction * x) }
                dimensions.append(.init(a: at(0), b: at(length), meters: length))
                let openings = room.openings.filter { $0.wallID == wall.id }
                var cuts = [0.0, length]
                for opening in openings {
                    cuts += [max(0, min(length, opening.positionOnWall.effectiveValue)),
                             max(0, min(length, opening.positionOnWall.effectiveValue + opening.width.effectiveValue))]
                }
                cuts = Array(Set(cuts)).sorted()
                for i in 1..<cuts.count where cuts[i] - cuts[i-1] > 1e-6 {
                    let midpoint = (cuts[i] + cuts[i-1]) / 2
                    let opening = openings.first { midpoint >= $0.positionOnWall.effectiveValue &&
                        midpoint <= $0.positionOnWall.effectiveValue + $0.width.effectiveValue }
                    segments.append(.init(a: at(cuts[i-1]), b: at(cuts[i]), opening: opening?.kind))
                }
            }
        }
    }
}

enum ScanFloorContainment {
    /// Tests against an observed floor contour; never invents a room boundary.
    static func contains(_ point: RoomPoint, in room: PlaquistoRoomModel) -> Bool {
        room.floors.contains { floor in
            guard let ring = floor.boundaries.first, ring.count >= 3 else { return false }
            let elevation = floor.referenceElevation ?? ring[0].y
            guard point.y-elevation > 0.25, point.y-elevation < 2.6 else { return false }
            func inside(_ polygon: [RoomPoint]) -> Bool {
                var result = false
                for i in polygon.indices {
                    let a = polygon[i], b = polygon[(i+1)%polygon.count]
                    if (a.z > point.z) != (b.z > point.z),
                       point.x < (b.x-a.x)*(point.z-a.z)/(b.z-a.z)+a.x { result.toggle() }
                }
                return result
            }
            return inside(ring) && !floor.boundaries.dropFirst().contains(where: inside)
        }
    }
}
