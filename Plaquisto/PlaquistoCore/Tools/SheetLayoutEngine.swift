import Foundation

enum LayoutSupportKind: String, Codable, CaseIterable { case wall = "Mur", ceiling = "Plafond" }
enum LayoutOrientation: String, Codable, CaseIterable { case vertical = "Vertical", horizontal = "Horizontal" }
enum LayoutOpeningKind: String, Codable, CaseIterable {
    case door = "Porte", window = "Fenêtre", bay = "Porte-fenêtre / baie", passage = "Ouverture libre"
    case stairwell = "Trémie", roofWindow = "Fenêtre de toit", other = "Autre ouverture"
    static func available(for kind: LayoutSupportKind) -> [Self] {
        kind == .wall ? [.door, .window, .bay, .passage] : [.stairwell, .roofWindow, .other]
    }
}
struct LayoutOpening: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: LayoutOpeningKind
    var contour: [LayoutPoint]
    var bounds: LayoutBounds { .init(points: contour) }
}
enum LayoutEdgeTone: String, Codable {
    case blue, orange, purple, green, teal, gray
}
struct LayoutDimensionCorrection: Codable, Equatable, Identifiable {
    var edgeIndex: Int
    var original: Double
    var corrected: Double
    var id: Int { edgeIndex }
    var difference: Double { abs(corrected - original) }
    var percentage: Double { original > 0 ? difference / original * 100 : 0 }
    var symbol: String { severity() == .red ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill" }
}
struct Surface2D: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: LayoutSupportKind
    var contour: [LayoutPoint]
    var openings: [LayoutOpening] = []
    var provenance = "manual"
    var sourceIdentifier: String? = nil
    var localFrame: LayoutLocalFrame? = nil
    var edgeTones: [LayoutEdgeTone] = []
    var dimensionCorrections: [LayoutDimensionCorrection] = []
    var contourIntent: LayoutContourIntent? = nil
    // Retain measurements belonging to an earlier topology when adding/removing vertices.
    var previousContourIntents: [LayoutContourIntent] = []
    // Changes whenever vertices are inserted/removed, even if the final count is unchanged.
    var topologyID: UUID? = nil
    var edgeIDs: [String] = []
    var layingOffset = LayoutLayingOffset()
    var bounds: LayoutBounds { .init(points: contour) }
}
extension Surface2D {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, contour, openings, provenance, sourceIdentifier, localFrame, edgeTones, dimensionCorrections, contourIntent, previousContourIntents, topologyID, edgeIDs, layingOffset
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(LayoutSupportKind.self, forKey: .kind)
        contour = try values.decode([LayoutPoint].self, forKey: .contour)
        openings = try values.decodeIfPresent([LayoutOpening].self, forKey: .openings) ?? []
        provenance = try values.decodeIfPresent(String.self, forKey: .provenance) ?? "manual"
        sourceIdentifier = try values.decodeIfPresent(String.self, forKey: .sourceIdentifier)
        localFrame = try values.decodeIfPresent(LayoutLocalFrame.self, forKey: .localFrame)
        edgeTones = try values.decodeIfPresent([LayoutEdgeTone].self, forKey: .edgeTones) ?? []
        dimensionCorrections = try values.decodeIfPresent([LayoutDimensionCorrection].self, forKey: .dimensionCorrections) ?? []
        contourIntent = try values.decodeIfPresent(LayoutContourIntent.self, forKey: .contourIntent)
        previousContourIntents = try values.decodeIfPresent([LayoutContourIntent].self, forKey: .previousContourIntents) ?? []
        topologyID = try values.decodeIfPresent(UUID.self, forKey: .topologyID)
        edgeIDs = try values.decodeIfPresent([String].self, forKey: .edgeIDs) ?? []
        layingOffset = try values.decodeIfPresent(LayoutLayingOffset.self, forKey: .layingOffset) ?? .init()
    }
}
struct LayoutVector3: Codable, Equatable {
    var x: Double; var y: Double; var z: Double
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y + z * b.z }
    var length: Double { sqrt(dot(self)) }
}
struct LayoutLocalFrame: Codable, Equatable {
    var origin: LayoutVector3
    var axisX: LayoutVector3
    var axisY: LayoutVector3
}
// Scanner integration contract. Source positions are metres and axes orthonormal.
// A sloping plane is developed into its own plane, never flattened onto the floor.
enum Surface2DAdapter {
    static func projected(name: String, kind: LayoutSupportKind, contour: [LayoutVector3],
                          openings: [[LayoutVector3]], frame: LayoutLocalFrame, sourceID: String) throws -> Surface2D {
        guard abs(frame.axisX.length - 1) < 1e-6, abs(frame.axisY.length - 1) < 1e-6,
              abs(frame.axisX.dot(frame.axisY)) < 1e-6 else { throw LayoutGeometryError.invalidContour }
        func project(_ p: LayoutVector3) throws -> LayoutPoint {
            let d = p - frame.origin, x = d.dot(frame.axisX), y = d.dot(frame.axisY)
            let residual = max(0, d.dot(d) - x * x - y * y)
            guard residual.isFinite, residual < 0.0001 else { throw LayoutGeometryError.invalidContour }
            return .init(x: x * 1000, y: y * 1000)
        }
        let polygon = try contour.map(project)
        try LayoutGeometry.validate(polygon)
        let holes = try openings.map { vertices -> LayoutOpening in
            let p = try vertices.map(project); try LayoutGeometry.validate(p)
            return .init(kind: .other, contour: p)
        }
        return Surface2D(name: name, kind: kind, contour: polygon, openings: holes,
                         provenance: "scan", sourceIdentifier: sourceID, localFrame: frame)
    }
}
struct LayoutLayer: Codable, Equatable, Identifiable {
    var id = UUID()
    var sheetWidth = 1200.0
    var sheetLength = 2500.0
    var orientation = LayoutOrientation.vertical
    var offset = LayoutPoint.zero
    var catalogFormatID: String? = nil
    // Optional fields keep previously saved documents readable without migration.
    var referenceEdge: Int? = nil
    var furring: LayoutFurringSettings? = nil
    var cellWidth: Double { orientation == .vertical ? min(sheetWidth, sheetLength) : max(sheetWidth, sheetLength) }
    var cellHeight: Double { orientation == .vertical ? max(sheetWidth, sheetLength) : min(sheetWidth, sheetLength) }
    func forSupport(_ kind:LayoutSupportKind) -> Self {
        guard kind == .wall else { return self }
        var copy = self
        copy.referenceEdge = nil
        copy.furring?.orientation = .vertical
        copy.furring?.parallelToBoards = orientation == .vertical
        return copy
    }
    func forSurface(_ surface:Surface2D) -> Self {
        var copy = forSupport(surface.kind)
        if surface.kind == .wall && surface.bounds.height <= cellHeight + 0.001 { copy.offset.y = surface.bounds.min.y }
        return copy
    }
}
struct LayoutFurringSettings: Codable, Equatable {
    // Kept for decoding plans created before furring had its own absolute
    // orientation. New and edited plans persist `orientation` as the source of
    // truth, so rotating boards cannot rotate the frame with them.
    var parallelToBoards = false
    var spacing = 600.0
    var offset = 0.0
    var orientation: LayoutOrientation? = nil

    func resolvedOrientation(boardOrientation: LayoutOrientation) -> LayoutOrientation {
        if let orientation { return orientation }
        if parallelToBoards { return boardOrientation }
        return boardOrientation == .horizontal ? .vertical : .horizontal
    }
}

extension LayoutLayer {
    var resolvedFurringOrientation: LayoutOrientation? {
        furring?.resolvedOrientation(boardOrientation: orientation)
    }

    mutating func materializeFurringOrientation() {
        guard var settings = furring else { return }
        let resolved = settings.resolvedOrientation(boardOrientation: orientation)
        settings.orientation = resolved
        settings.parallelToBoards = resolved == orientation
        furring = settings
    }

    mutating func setFurringOrientation(_ value: LayoutOrientation) {
        guard var settings = furring else { return }
        settings.orientation = value
        settings.parallelToBoards = value == orientation
        furring = settings
    }
}

// Engine and cut sheets stay in grid coordinates. Only the overview is transformed.
// This prevents rotated cuts from being measured using a world-axis bounding box.
struct LayoutGridFrame: Equatable {
    var origin = LayoutPoint.zero
    var angle = 0.0
    func world(_ p: LayoutPoint) -> LayoutPoint {
        origin + .init(x: cos(angle)*p.x - sin(angle)*p.y, y: sin(angle)*p.x + cos(angle)*p.y)
    }
    func local(_ p: LayoutPoint) -> LayoutPoint { vector(p-origin) }
    func vector(_ p: LayoutPoint) -> LayoutPoint {
        .init(x: cos(angle)*p.x + sin(angle)*p.y, y: -sin(angle)*p.x + cos(angle)*p.y)
    }
    static func make(surface: Surface2D, layer: LayoutLayer) -> Self {
        guard surface.kind == .ceiling else { return .init() }
        guard let i = layer.referenceEdge, surface.contour.indices.contains(i) else { return .init() }
        let a = surface.contour[i], d = surface.contour[(i+1)%surface.contour.count]-a
        return .init(origin: a, angle: atan2(d.y,d.x))
    }
}
struct LayoutFurringContact: Equatable {
    var point: LayoutPoint
    var edgeIndex: Int
    var distance: Double
}
struct LayoutFurringResult: Equatable {
    var lines: [LayoutJoint] = []
    var contacts: [LayoutFurringContact] = []
}

enum LayoutFurringEngine {
    static func calculate(surface: Surface2D, layer: LayoutLayer) throws -> LayoutFurringResult {
        guard let settings = layer.furring else { return .init() }
        guard [400.0,500.0,600.0].contains(settings.spacing), settings.offset.isFinite else { throw LayoutGeometryError.invalidFormat }
        // In grid coordinates the long side is X for horizontal boards, Y otherwise.
        let alongX = surface.kind == .wall ? false : settings.resolvedOrientation(boardOrientation: layer.orientation) == .horizontal
        func across(_ p: LayoutPoint) -> Double { alongX ? p.y : p.x }
        func along(_ p: LayoutPoint) -> Double { alongX ? p.x : p.y }
        let b = surface.bounds
        let low = across(b.min), high = across(b.max)
        let step = settings.spacing
        let offset = settings.offset.truncatingRemainder(dividingBy:step)
        guard low.isFinite, high.isFinite, (high-low)/step <= 2000 else { throw LayoutGeometryError.tooLarge }
        let first = Int(ceil((low-offset-0.001)/step)), last = Int(floor((high-offset+0.001)/step))
        guard first <= last else { return .init() }
        var result = LayoutFurringResult()
        for index in first...last {
            let coordinate = offset+Double(index)*step
            var intersections: [LayoutPoint] = []
            var contacts: [LayoutFurringContact] = []
            for (loopIndex,loop) in ([surface.contour]+surface.openings.map(\.contour)).enumerated() {
                for i in loop.indices {
                    let a = loop[i], z = loop[(i+1)%loop.count], delta = across(z)-across(a)
                    guard abs(delta) > 1e-8 else { continue }
                    let t = (coordinate-across(a))/delta
                    guard t >= -1e-8, t <= 1+1e-8 else { continue }
                    let point = a+(z-a)*min(1,max(0,t))
                    intersections.append(point)
                    if loopIndex == 0 {
                        contacts.append(.init(point:point,edgeIndex:i,distance:(point-a).length))
                    }
                }
            }
            let sorted = intersections.sorted { along($0) < along($1) }
            var unique: [LayoutPoint] = []
            for p in sorted where unique.last.map({(p-$0).length > 0.01}) ?? true { unique.append(p) }
            var segments: [LayoutJoint] = []
            func onBoundary(_ p:LayoutPoint,_ polygon:[LayoutPoint]) -> Bool {
                LayoutGeometry.edges(polygon).contains { LayoutGeometry.distance(p,to:$0.a,$0.b) < 0.001 }
            }
            for (a,z) in zip(unique,unique.dropFirst()) {
                let mid = (a+z)*0.5
                if LayoutGeometry.contains(mid,in:surface.contour) || onBoundary(mid,surface.contour),
                   !surface.openings.contains(where:{LayoutGeometry.contains(mid,in:$0.contour) && !onBoundary(mid,$0.contour)}) {
                    segments.append(.init(start:a,end:z))
                }
            }
            result.lines.append(contentsOf:segments)
            result.contacts.append(contentsOf:contacts.filter { contact in
                segments.contains { (contact.point-$0.start).length < 0.01 || (contact.point-$0.end).length < 0.01 }
            })
        }
        return result
    }
}
struct LayoutDocument: Codable, Equatable {
    var schemaVersion = 1
    var surface: Surface2D
    // V1 edits layer 1. Later layers can have independent formats and offsets.
    var layers: [LayoutLayer] = [.init()]
    var lighting: LayoutLighting? = nil
}
struct LayoutCutPiece: Equatable, Identifiable {
    var id: String
    var contour: [LayoutPoint]
    var holes: [[LayoutPoint]]
    var area: Double { abs(LayoutGeometry.area(contour)) - holes.reduce(0) { $0 + abs(LayoutGeometry.area($1)) } }
    var bounds: LayoutBounds { .init(points: contour) }
    func contains(_ p: LayoutPoint) -> Bool {
        LayoutGeometry.contains(p, in: contour) && !holes.contains { LayoutGeometry.contains(p, in: $0) }
    }
    // Interior point for a legible label even in a concave piece.
    var labelPoint: LayoutPoint {
        if contains(bounds.center) { return bounds.center }
        for e in LayoutGeometry.edges(contour) {
            let d = e.b - e.a, mid = (e.a + e.b) * 0.5
            let p = mid + LayoutPoint(x: -d.y, y: d.x) * (min(bounds.width, bounds.height) * 0.02 / d.length)
            if contains(p) { return p }
        }
        return contour[0]
    }
}
struct LayoutSheetPlacement: Equatable, Identifiable {
    var id: String
    var number: Int
    var origin: LayoutPoint
    var width: Double
    var height: Double
    var pieces: [LayoutCutPiece]
    var area: Double { pieces.reduce(0) { $0 + $1.area } }
    var isFull: Bool { abs(area - width * height) < 0.01 }
    var wasteArea: Double { max(0, width * height - area) }
}
struct LayoutJoint: Equatable {
    var start: LayoutPoint
    var end: LayoutPoint
}
struct SheetLayoutResult: Equatable {
    var sheets: [LayoutSheetPlacement]
    var joints: [LayoutJoint]
    var frame = LayoutGridFrame()
    var furring = LayoutFurringResult()
    var netArea: Double { sheets.reduce(0) { $0 + $1.area } }
    var wasteArea: Double { sheets.reduce(0) { $0 + $1.wasteArea } }
    var pieceCount: Int { sheets.reduce(0) { $0 + $1.pieces.count } }
}
enum SheetLayoutEngine {
    static func calculate(surface: Surface2D, layer: LayoutLayer) throws -> SheetLayoutResult {
        let layer = layer.forSurface(surface)
        try LayoutGeometry.validate(surface.contour)
        guard surface.openings.count <= 100 else { throw LayoutGeometryError.tooLarge }
        for opening in surface.openings { try LayoutGeometry.validate(opening.contour) }
        let frame = LayoutGridFrame.make(surface:surface,layer:layer)
        var surface = surface
        surface.contour = surface.contour.map(frame.local)
        surface.openings = surface.openings.map { opening in
            var copy = opening; copy.contour = copy.contour.map(frame.local); return copy
        }
        let furring = try LayoutFurringEngine.calculate(surface:surface,layer:layer)
        surface.contour = try surface.layingContour()
        let w = layer.cellWidth, h = layer.cellHeight
        guard w.isFinite, h.isFinite, w >= 1, h >= 1, w <= 100_000, h <= 100_000,
              layer.offset.finite, abs(layer.offset.x) <= 1_000_000, abs(layer.offset.y) <= 1_000_000 else { throw LayoutGeometryError.invalidFormat }
        let b = surface.bounds
        // Equivalent offsets modulo sheet size generate identical placements/IDs.
        func normalized(_ n: Double, _ period: Double) -> Double {
            let r = n.truncatingRemainder(dividingBy: period)
            return abs(r) < LayoutGeometry.epsilon ? 0 : (r < 0 ? r + period : r)
        }
        let offset = LayoutPoint(x: normalized(layer.offset.x, w), y: normalized(layer.offset.y, h))
        let c0 = Int(floor((b.min.x - offset.x) / w)), c1 = Int(ceil((b.max.x - offset.x) / w))
        let r0 = Int(floor((b.min.y - offset.y) / h)), r1 = Int(ceil((b.max.y - offset.y) / h))
        guard Double(c1 - c0) * Double(r1 - r0) <= 2000 else { throw LayoutGeometryError.tooLarge }
        var sheets: [LayoutSheetPlacement] = []
        var jointCandidates: [String: (LayoutJoint, Int)] = [:]
        for row in r0..<r1 {
            for col in c0..<c1 {
                try Task.checkCancellation()
                let origin = LayoutPoint(x: offset.x + Double(col) * w, y: offset.y + Double(row) * h)
                let bounds = LayoutBounds(min: origin, max: origin + .init(x: w, y: h))
                let loops = try LayoutGeometry.intersection(outer: surface.contour, holes: surface.openings.map(\.contour), rectangle: bounds)
                let outers = loops.filter { LayoutGeometry.area($0) > 0 }
                let holes = loops.filter { LayoutGeometry.area($0) < 0 }
                let id = "\(col):\(row)"
                var pieces: [LayoutCutPiece] = []
                for (index, outer) in outers.enumerated() {
                    let enclosed = holes.filter { LayoutGeometry.contains($0[0], in: outer) }
                    let piece = LayoutCutPiece(id: "\(id):\(index)", contour: outer, holes: enclosed)
                    if piece.area > LayoutGeometry.minimumArea { pieces.append(piece) }
                }
                guard !pieces.isEmpty else { continue }
                sheets.append(.init(id: id, number: sheets.count + 1, origin: origin, width: w, height: h, pieces: pieces))
                for piece in pieces {
                    for e in LayoutGeometry.edges(piece.contour) {
                        let vertical = abs(e.a.x - e.b.x) < LayoutGeometry.epsilon
                        let horizontal = abs(e.a.y - e.b.y) < LayoutGeometry.epsilon
                        guard vertical || horizontal else { continue }
                        let a = (e.a.x, e.a.y) < (e.b.x, e.b.y) ? e.a : e.b
                        let z = a == e.a ? e.b : e.a
                        let key = [a.x, a.y, z.x, z.y].map { String(Int64(($0 / LayoutGeometry.epsilon).rounded())) }.joined(separator: ":")
                        let previous = jointCandidates[key]
                        jointCandidates[key] = (.init(start: a, end: z), (previous?.1 ?? 0) + 1)
                    }
                }
            }
        }
        let joints = jointCandidates.keys.sorted().compactMap { key -> LayoutJoint? in
            guard let entry = jointCandidates[key], entry.1 > 1 else { return nil }; return entry.0
        }
        return .init(sheets: sheets, joints: joints, frame:frame,
                     furring:furring)
    }
}

enum LayoutPreset: String, CaseIterable {
    case rectangle = "Rectangle", slope = "Sous rampant", gable = "Pignon", lShape = "En L", freeform = "Dessiner la forme"

    func isAvailable(for kind: LayoutSupportKind) -> Bool {
        switch (kind, self) {
        case (_, .rectangle), (_, .freeform), (.wall, .slope), (.ceiling, .lShape):
            return true
        default:
            return false
        }
    }

    static func available(for kind: LayoutSupportKind) -> [Self] {
        allCases.filter { $0.isAvailable(for: kind) }
    }
    func contour(length: Double, height: Double, secondaryHeight: Double, mirrored: Bool = false,
                 lowerLength: Double? = nil) -> [LayoutPoint] {
        switch self {
        case .rectangle, .freeform:
            return [.zero, .init(x: length, y: 0), .init(x: length, y: height), .init(x: 0, y: height)]
        case .slope:
            let left = mirrored ? secondaryHeight : height, right = mirrored ? height : secondaryHeight
            return [.zero, .init(x: length, y: 0), .init(x: length, y: right), .init(x: 0, y: left)]
        case .gable:
            return [.zero, .init(x: length, y: 0), .init(x: length, y: height),
                    .init(x: length / 2, y: secondaryHeight), .init(x: 0, y: height)]
        case .lShape:
            // Preserve older saved L-shaped ceilings whose third dimension was
            // the depth of the return. New wall forms use min/max heights.
            let normal: [LayoutPoint]
            if secondaryHeight < height {
                normal = [.zero, .init(x: length, y: 0), .init(x: length, y: height / 2),
                          .init(x: length / 2, y: height / 2), .init(x: length / 2, y: height), .init(x: 0, y: height)]
            } else {
                let low = min(length - 10, max(10, lowerLength ?? length / 2))
                normal = [.init(x: length, y: height), .init(x: length - low, y: height),
                          .init(x: length - low, y: secondaryHeight), .init(x: 0, y: secondaryHeight),
                          .zero, .init(x: length, y: 0)]
            }
            return mirrored ? normal.map { .init(x: length - $0.x, y: $0.y) } : normal
        }
    }
    func contour(width: Double, height: Double, secondaryHeight: Double) -> [LayoutPoint] {
        contour(length: width, height: height, secondaryHeight: secondaryHeight)
    }
}
