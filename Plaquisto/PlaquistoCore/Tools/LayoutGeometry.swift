import Foundation

// All geometry is in millimetres, Y up. No SwiftUI, ARKit or RoomPlan dependency.
struct LayoutPoint: Codable, Hashable {
    var x: Double
    var y: Double
    static let zero = Self(x: 0, y: 0)
    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b) }
    var length: Double { hypot(x, y) }
    var finite: Bool { x.isFinite && y.isFinite }
}

struct LayoutBounds: Equatable {
    var min: LayoutPoint
    var max: LayoutPoint
    var width: Double { max.x - min.x }
    var height: Double { max.y - min.y }
    var center: LayoutPoint { (min + max) * 0.5 }
    var polygon: [LayoutPoint] { [min, .init(x: max.x, y: min.y), max, .init(x: min.x, y: max.y)] }
    init(points: [LayoutPoint]) {
        min = .init(x: points.map(\.x).min() ?? 0, y: points.map(\.y).min() ?? 0)
        max = .init(x: points.map(\.x).max() ?? 0, y: points.map(\.y).max() ?? 0)
    }
    init(min: LayoutPoint, max: LayoutPoint) { self.min = min; self.max = max }
    func overlaps(_ other: Self) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x && min.y <= other.max.y && max.y >= other.min.y
    }
}

enum LayoutGeometryError: Error, LocalizedError {
    case invalidContour, invalidFormat, tooLarge, topology
    var errorDescription: String? {
        switch self {
        case .invalidContour: return "Le contour doit être fermé, sans croisement ni côté nul. Vérifiez les sommets et les ouvertures."
        case .invalidFormat: return "Renseignez des dimensions de plaque positives et un décalage valide."
        case .tooLarge: return "Ce plan dépasse les limites de l’éditeur : 2 000 plaques ou 200 sommets par contour."
        case .topology: return "Cette découpe ne peut pas être calculée avec précision. Écartez légèrement les sommets superposés."
        }
    }
}

enum LayoutGeometry {
    // 0.00001 mm numerical tolerance; physical small cuts are retained.
    static let epsilon = 0.00001
    static let minimumArea = 0.0001 // square millimetres
    static func cross(_ a: LayoutPoint, _ b: LayoutPoint) -> Double { a.x * b.y - a.y * b.x }
    static func dot(_ a: LayoutPoint, _ b: LayoutPoint) -> Double { a.x * b.x + a.y * b.y }
    static func area(_ p: [LayoutPoint]) -> Double {
        guard p.count >= 3 else { return 0 }
        // Translate first to avoid cancellation for contours far from the origin.
        let o = p[0]
        return p.indices.reduce(0) { $0 + cross(p[$1] - o, p[($1 + 1) % p.count] - o) } / 2
    }
    static func contains(_ q: LayoutPoint, in p: [LayoutPoint]) -> Bool {
        var inside = false
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }
    static func distance(_ q: LayoutPoint, to a: LayoutPoint, _ b: LayoutPoint) -> Double {
        let d = b - a, l2 = dot(d, d)
        guard l2 > 0 else { return (q - a).length }
        return (q - (a + d * min(1, max(0, dot(q - a, d) / l2)))).length
    }

    struct Edge { var a: LayoutPoint; var b: LayoutPoint }
    static func edges(_ p: [LayoutPoint]) -> [Edge] { p.indices.map { .init(a: p[$0], b: p[($0 + 1) % p.count]) } }

    // Includes collinear overlaps: both endpoints become split points.
    static func splitParameters(_ e: Edge, by f: Edge) -> [Double] {
        let r = e.b - e.a, s = f.b - f.a, q = f.a - e.a
        let denom = cross(r, s)
        if abs(denom) > 1e-12 * r.length * s.length {
            let t = cross(q, s) / denom, u = cross(q, r) / denom
            if t >= -1e-10 && t <= 1 + 1e-10 && u >= -1e-10 && u <= 1 + 1e-10 { return [min(1, max(0, t))] }
            return []
        }
        guard abs(cross(q, r)) <= epsilon * r.length else { return [] }
        let l2 = dot(r, r)
        guard l2 > epsilon * epsilon else { return [] }
        return [dot(f.a - e.a, r) / l2, dot(f.b - e.a, r) / l2]
            .filter { $0 >= -1e-10 && $0 <= 1 + 1e-10 }.map { min(1, max(0, $0)) }
    }

    static func validate(_ p: [LayoutPoint]) throws {
        guard p.count >= 3, p.count <= 200 else { throw p.count > 200 ? LayoutGeometryError.tooLarge : .invalidContour }
        guard p.allSatisfy({ $0.finite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }), abs(area(p)) > minimumArea else { throw LayoutGeometryError.invalidContour }
        let es = edges(p)
        for i in es.indices {
            guard (es[i].b - es[i].a).length > epsilon else { throw LayoutGeometryError.invalidContour }
            // Adjacent sides may be collinear, but may not double back.
            let prev = p[(i + p.count - 1) % p.count] - p[i], next = p[(i + 1) % p.count] - p[i]
            if abs(cross(prev, next)) <= epsilon * max(prev.length, next.length), dot(prev, next) > 0 { throw LayoutGeometryError.invalidContour }
            for j in es.indices where j > i + 1 && !(i == 0 && j == es.count - 1) {
                if !splitParameters(es[i], by: es[j]).isEmpty || !splitParameters(es[j], by: es[i]).isEmpty { throw LayoutGeometryError.invalidContour }
            }
        }
    }

    private struct VertexKey: Hashable, Comparable {
        let x: Int64; let y: Int64
        init(_ p: LayoutPoint) { x = Int64((p.x / epsilon).rounded()); y = Int64((p.y / epsilon).rounded()) }
        var point: LayoutPoint { .init(x: Double(x) * epsilon, y: Double(y) * epsilon) }
        static func < (a: Self, b: Self) -> Bool { a.x == b.x ? a.y < b.y : a.x < b.x }
    }
    private struct SegmentKey: Hashable { let a: VertexKey; let b: VertexKey }

    // Boundary arrangement boolean: split every crossing, retain only segments
    // separating solid/empty regions, then assemble directed loops (solid on left).
    // Handles concave supports, overlapping openings, holes, and disconnected pieces.
    static func intersection(outer: [LayoutPoint], holes: [[LayoutPoint]], rectangle: LayoutBounds) throws -> [[LayoutPoint]] {
        let relevant = holes.filter { LayoutBounds(points: $0).overlaps(rectangle) }
        let allEdges = edges(outer) + relevant.flatMap { edges($0) } + edges(rectangle.polygon)
        func solid(_ p: LayoutPoint) -> Bool {
            p.x > rectangle.min.x && p.x < rectangle.max.x && p.y > rectangle.min.y && p.y < rectangle.max.y
                && contains(p, in: outer) && !relevant.contains { contains(p, in: $0) }
        }
        var segments = Set<SegmentKey>()
        for e in allEdges {
            try Task.checkCancellation()
            let d = e.b - e.a, length = d.length
            guard length > epsilon else { continue }
            var ts = [0.0, 1.0]
            for f in allEdges { ts += splitParameters(e, by: f) }
            ts.sort()
            for i in 1..<ts.count where (ts[i] - ts[i - 1]) * length > epsilon {
                let a = e.a + d * ts[i - 1], b = e.a + d * ts[i], mid = (a + b) * 0.5
                let delta = min(epsilon * 0.25, (b - a).length * 0.0001)
                let normal = LayoutPoint(x: -d.y / length, y: d.x / length) * delta
                let left = solid(mid + normal), right = solid(mid - normal)
                guard left != right else { continue }
                let ka = VertexKey(left ? a : b), kb = VertexKey(left ? b : a)
                if ka != kb { segments.insert(.init(a: ka, b: kb)) }
            }
        }
        var outgoing: [VertexKey: [VertexKey]] = [:]
        for edge in segments { outgoing[edge.a, default: []].append(edge.b) }
        var unused = segments, loops: [[LayoutPoint]] = []
        let ordered = segments.sorted { $0.a == $1.a ? $0.b < $1.b : $0.a < $1.a }
        for first in ordered where unused.contains(first) {
            var loop = [first.a.point], current = first
            var closed = false
            for _ in 0...segments.count {
                unused.remove(current)
                if current.b == first.a { closed = true; break }
                loop.append(current.b.point)
                let candidates = (outgoing[current.b] ?? []).filter { unused.contains(.init(a: current.b, b: $0)) }
                guard !candidates.isEmpty else { throw LayoutGeometryError.topology }
                let incoming = current.b.point - current.a.point
                let next = candidates.min { a, b in
                    let da = a.point - current.b.point, db = b.point - current.b.point
                    let aa = atan2(cross(incoming, da), dot(incoming, da)), ab = atan2(cross(incoming, db), dot(incoming, db))
                    return abs(aa - ab) > 1e-12 ? aa < ab : a < b
                }!
                current = .init(a: current.b, b: next)
            }
            guard closed else { throw LayoutGeometryError.topology }
            for cycle in splitTouchingCycles(loop) {
                let clean = simplified(cycle)
                if abs(area(clean)) > minimumArea { try validate(clean); loops.append(clean) }
            }
        }
        return loops
    }

    // At a tangency a boundary walk can visit the same vertex twice. Keep the
    // touching components as separate simple loops, not a self-touching polygon.
    private static func splitTouchingCycles(_ p: [LayoutPoint]) -> [[LayoutPoint]] {
        var visited: [LayoutPoint: Int] = [:]
        for (i, point) in p.enumerated() {
            if let first = visited[point] {
                let cycle = Array(p[first..<i])
                let remainder = Array(p[..<first]) + Array(p[i...])
                return (cycle.count >= 3 ? splitTouchingCycles(cycle) : []) + (remainder.count >= 3 ? splitTouchingCycles(remainder) : [])
            }
            visited[point] = i
        }
        return [p]
    }

    static func simplified(_ input: [LayoutPoint]) -> [LayoutPoint] {
        var p = input, changed = true
        while p.count > 3 && changed {
            changed = false
            for i in p.indices {
                let a = p[(i + p.count - 1) % p.count], b = p[i], c = p[(i + 1) % p.count]
                if distance(b, to: a, c) <= epsilon { p.remove(at: i); changed = true; break }
            }
        }
        return p
    }
}
