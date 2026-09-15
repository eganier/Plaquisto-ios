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
    case blue, orange, purple, green
}
struct LayoutDimensionCorrection: Codable, Equatable, Identifiable {
    var edgeIndex: Int
    var original: Double
    var corrected: Double
    var id: Int { edgeIndex }
    var difference: Double { abs(corrected - original) }
    var percentage: Double { original > 0 ? difference / original * 100 : 0 }
    var symbol: String { difference > 50 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill" }
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
    var bounds: LayoutBounds { .init(points: contour) }
}
extension Surface2D {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, contour, openings, provenance, sourceIdentifier, localFrame, edgeTones, dimensionCorrections
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
    var cellWidth: Double { orientation == .vertical ? min(sheetWidth, sheetLength) : max(sheetWidth, sheetLength) }
    var cellHeight: Double { orientation == .vertical ? max(sheetWidth, sheetLength) : min(sheetWidth, sheetLength) }
}
struct LayoutDocument: Codable, Equatable {
    var schemaVersion = 1
    var surface: Surface2D
    // V1 edits layer 1. Later layers can have independent formats and offsets.
    var layers: [LayoutLayer] = [.init()]
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
    var netArea: Double { sheets.reduce(0) { $0 + $1.area } }
    var wasteArea: Double { sheets.reduce(0) { $0 + $1.wasteArea } }
    var pieceCount: Int { sheets.reduce(0) { $0 + $1.pieces.count } }
}
enum SheetLayoutEngine {
    static func calculate(surface: Surface2D, layer: LayoutLayer) throws -> SheetLayoutResult {
        try LayoutGeometry.validate(surface.contour)
        guard surface.openings.count <= 100 else { throw LayoutGeometryError.tooLarge }
        for opening in surface.openings { try LayoutGeometry.validate(opening.contour) }
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
        return .init(sheets: sheets, joints: joints)
    }
}

enum LayoutPreset: String, CaseIterable {
    case rectangle = "Rectangle", slope = "Sous rampant", gable = "Pignon", lShape = "En L", freeform = "Dessiner la forme"
    static func available(for kind: LayoutSupportKind) -> [Self] {
        kind == .wall ? [.rectangle, .slope, .lShape] : [.rectangle, .freeform]
    }
    func contour(length: Double, height: Double, secondaryHeight: Double, mirrored: Bool = false) -> [LayoutPoint] {
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
                normal = [.zero, .init(x: length, y: 0), .init(x: length, y: secondaryHeight),
                          .init(x: length / 2, y: secondaryHeight), .init(x: length / 2, y: height), .init(x: 0, y: height)]
            }
            return mirrored ? Array(normal.map { .init(x: length - $0.x, y: $0.y) }.reversed()) : normal
        }
    }
    func contour(width: Double, height: Double, secondaryHeight: Double) -> [LayoutPoint] {
        contour(length: width, height: height, secondaryHeight: secondaryHeight)
    }
}
