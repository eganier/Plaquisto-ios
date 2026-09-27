import Foundation
import simd

// Reconstruct a complete ceiling from observed plane patches and wall boundaries.
// Flat, single-slope and two opposing observed slopes are supported.
// Les trous du mesh ne sont pas interprétés comme des trémies.
enum ScannerCeilingReconstruction {
    struct Wall {
        let start: SIMD2<Double>
        let end: SIMD2<Double>
    }
    struct Boundary {
        let start: SIMD2<Double>
        let end: SIMD2<Double>
        let keepPoint: SIMD2<Double>
    }
    // Detect a throat with two corridor sides AND returns on both sides.
    // Build only the local face containing the camera, ignoring other rooms.
    static func zoneProposals(walls input: [Wall], keepPoint: SIMD2<Double>) -> [[Wall]] {
        guard input.count >= 4, input.count <= 100 else { return [] }
        let walls = normalizedWalls(input)
        let ends = walls.flatMap { [$0.start, $0.end] }
        var proposals: [(Double, [Wall])] = []
        for i in ends.indices {
            for j in ends.indices where j > i && i / 2 != j / 2 {
                let a = ends[i], b = ends[j], width = simd_distance(a, b)
                guard width >= 0.5, width <= 3 else { continue }
                let across = (b - a) / width
                let u = simd_normalize(ends[i ^ 1] - a), v = simd_normalize(ends[j ^ 1] - b)
                guard simd_dot(u, v) > 0.85, abs(simd_dot(u, across)) < 0.3,
                      cross(across, keepPoint - a) * cross(across, u) < -0.25 else { continue }
                func shoulder(_ point: SIMD2<Double>, _ outward: SIMD2<Double>) -> Bool {
                    walls.contains { wall in
                        let nearStart = simd_distance(wall.start, point) <= 0.25
                        let nearEnd = simd_distance(wall.end, point) <= 0.25
                        guard nearStart || nearEnd else { return false }
                        let span = (nearStart ? wall.end : wall.start) - point
                        return simd_dot(span, outward) > 0.25 && abs(cross(simd_normalize(span), outward)) < 0.25
                    }
                }
                guard shoulder(a, -across), shoulder(b, across) else { continue }
                let side = cross(across, keepPoint - a) > 0 ? 1.0 : -1.0
                var local: [Wall] = []
                for wall in walls {
                    let da = side * cross(across, wall.start - a), db = side * cross(across, wall.end - a)
                    if da < -0.04 && db < -0.04 { continue }
                    var start = wall.start, end = wall.end
                    if da * db < 0 {
                        let p = start + (end - start) * (da / (da - db))
                        if da < 0 { start = p } else { end = p }
                    }
                    if simd_distance(start, end) > 0.02 { local.append(Wall(start: start, end: end)) }
                }
                local.append(Wall(start: a, end: b))
                if let polygon = localFace(local, containing: keepPoint), abs(signedArea(polygon)) > width * width * 1.5 {
                    let boundary = polygon.indices.map { Wall(start: polygon[$0], end: polygon[($0 + 1) % polygon.count]) }
                    proposals.append((abs(cross(across, keepPoint - a)), boundary))
                }
            }
        }
        if !proposals.isEmpty { return proposals.sorted { $0.0 < $1.0 }.prefix(6).map { $0.1 } }
        return supportedRectangleProposals(walls: walls, keepPoint: keepPoint)
    }

    // Unlike passage proposals, this only chooses an already closed face. An L
    // stays an L; no extra wall or virtual cut is introduced here.
    static func localCeilingWalls(_ walls: [Wall], keepPoint: SIMD2<Double>) -> [Wall]? {
        guard walls.count >= 3, walls.count <= 100,
              let polygon = localFace(normalizedWalls(walls), containing: keepPoint) else { return nil }
        return polygon.indices.map { Wall(start: polygon[$0], end: polygon[($0 + 1) % polygon.count]) }
    }

    static func isCeilingObservation(_ triangle: Triangle, classifiedCeiling: Bool,
                                     minimumY: Double, floorY: Double) -> Bool {
        guard triangle.area.isFinite, triangle.area > 1e-7,
              triangle.center.y.isFinite, abs(triangle.normal.y) >= 0.42 else { return false }
        // Wall heights only reject low clutter; they never supply the fitted
        // height or slope. Apple's ceiling label preserves low roof patches.
        return triangle.center.y >= (classifiedCeiling ? floorY + 0.5 : minimumY)
    }

    // Last resort, explicitly yellow: rectangle supported by four observed wall
    // lines, with a recognized throat on an edge. Never a mesh bounding box.
    private static func supportedRectangleProposals(walls: [Wall], keepPoint: SIMD2<Double>) -> [[Wall]] {
        guard let longest = walls.max(by: { simd_distance($0.start, $0.end) < simd_distance($1.start, $1.end) }) else { return [] }
        let u = simd_normalize(longest.end - longest.start), v = SIMD2(-u.y, u.x)
        func local(_ p: SIMD2<Double>) -> SIMD2<Double> { SIMD2(simd_dot(p, u), simd_dot(p, v)) }
        let point = local(keepPoint)
        struct Line { let axis: Int; let level: Double; let low: Double; let high: Double }
        let lines: [Line] = walls.compactMap { wall in
            let a = local(wall.start), b = local(wall.end), d = b - a
            let length = simd_length(d)
            guard length >= 0.30 else { return nil }
            if abs(d.x) / length >= 0.99 { return Line(axis: 0, level: (a.y + b.y) / 2, low: min(a.x, b.x), high: max(a.x, b.x)) }
            if abs(d.y) / length >= 0.99 { return Line(axis: 1, level: (a.x + b.x) / 2, low: min(a.y, b.y), high: max(a.y, b.y)) }
            return nil
        }
        func levels(_ axis: Int) -> [Double] {
            var values: [Double] = []
            for line in lines.filter({ $0.axis == axis }).sorted(by: { $0.high - $0.low > $1.high - $1.low }) {
                if !values.contains(where: { abs($0 - line.level) < 0.12 }) { values.append(line.level) }
            }
            return values.prefix(16).sorted()
        }
        func coverage(_ axis: Int, _ level: Double, _ low: Double, _ high: Double) -> Double {
            let ranges = lines.filter { $0.axis == axis && abs($0.level - level) <= 0.18 }
                .map { (max(low, $0.low), min(high, $0.high)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
            var end = low, total = 0.0
            for range in ranges { total += max(0, range.1 - max(end, range.0)); end = max(end, range.1) }
            return total / (high - low)
        }
        func passage(_ axis: Int, _ edge: Double, _ sign: Double, _ low: Double, _ high: Double) -> Bool {
            let sides = lines.filter { line in
                line.axis == axis && line.level > low + 0.25 && line.level < high - 0.25
                    && (sign > 0 ? line.high > edge + 0.6 && line.low < edge + 0.75 : line.low < edge - 0.6 && line.high > edge - 0.75)
            }
            for a in sides {
                for b in sides where b.level - a.level >= 0.5 && b.level - a.level <= 2.0 {
                    let lowerReturn = lines.contains { $0.axis != axis && abs($0.level - edge) <= 0.75 && abs($0.high - a.level) <= 0.18 && $0.low < a.level - 0.25 }
                    let upperReturn = lines.contains { $0.axis != axis && abs($0.level - edge) <= 0.75 && abs($0.low - b.level) <= 0.18 && $0.high > b.level + 0.25 }
                    if lowerReturn && upperReturn { return true }
                }
            }
            return false
        }
        let xs = levels(1), ys = levels(0)
        var candidates: [(Double, [Wall])] = []
        for x0 in xs where x0 < point.x - 0.2 {
            for x1 in xs where x1 > point.x + 0.2 {
                for y0 in ys where y0 < point.y - 0.2 {
                    for y1 in ys where y1 > point.y + 0.2 {
                        let width = x1 - x0, height = y1 - y0
                        guard width >= 1.5, height >= 1.5 else { continue }
                        let support = [coverage(1, x0, y0, y1), coverage(1, x1, y0, y1), coverage(0, y0, x0, x1), coverage(0, y1, x0, x1)]
                        guard support.allSatisfy({ $0 >= 0.30 }), support.reduce(0, +) >= 2.5 else { continue }
                        guard passage(0, x0, -1, y0, y1) || passage(0, x1, 1, y0, y1)
                            || passage(1, y0, -1, x0, x1) || passage(1, y1, 1, x0, x1) else { continue }
                        let corners = [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)].map { u * $0.x + v * $0.y }
                        let boundary = corners.indices.map { Wall(start: corners[$0], end: corners[($0 + 1) % 4]) }
                        candidates.append((support.reduce(0, +), boundary))
                    }
                }
            }
        }
        return candidates.sorted { $0.0 > $1.0 }.prefix(4).map { $0.1 }
    }

    // Planar graph: split intersections, trace bounded faces, keep the camera's
    // face. Unlike a hull this preserves recesses and ignores detached branches.
    private static func localFace(_ walls: [Wall], containing point: SIMD2<Double>) -> [SIMD2<Double>]? {
        var nodes: [SIMD2<Double>] = []
        var neighbors: [Set<Int>] = []
        func node(_ p: SIMD2<Double>) -> Int {
            if let i = nodes.firstIndex(where: { simd_distance($0, p) <= 0.15 }) { return i }
            nodes.append(p); neighbors.append([]); return nodes.count - 1
        }
        for wall in walls {
            let d = wall.end - wall.start
            var parameters = [0.0, 1.0]
            for other in walls {
                let e = other.end - other.start, denominator = cross(d, e)
                guard abs(denominator) > 1e-9 else { continue }
                let t = cross(other.start - wall.start, e) / denominator
                let s = cross(other.start - wall.start, d) / denominator
                if t > 0 && t < 1 && s >= 0 && s <= 1 { parameters.append(t) }
            }
            let sorted = parameters.sorted()
            for k in 1..<sorted.count {
                let a = node(wall.start + d * sorted[k - 1]), b = node(wall.start + d * sorted[k])
                if a != b { neighbors[a].insert(b); neighbors[b].insert(a) }
            }
        }
        var pruned = true
        while pruned {
            pruned = false
            for i in nodes.indices where neighbors[i].count == 1 {
                let j = neighbors[i].first!
                neighbors[j].remove(i); neighbors[i].removeAll(); pruned = true
            }
        }
        let ordered = nodes.indices.map { i in neighbors[i].sorted {
            atan2(nodes[$0].y - nodes[i].y, nodes[$0].x - nodes[i].x) < atan2(nodes[$1].y - nodes[i].y, nodes[$1].x - nodes[i].x)
        } }
        var visited = Set<String>(), faces: [[SIMD2<Double>]] = []
        for start in nodes.indices {
            for end in ordered[start] {
                var a = start, b = end, path: [Int] = []
                for _ in 0..<(walls.count * walls.count * 4 + 4) {
                    guard visited.insert("\(a):\(b)").inserted else { break }
                    path.append(a)
                    guard let reverse = ordered[b].firstIndex(of: a) else { break }
                    let next = ordered[b][(reverse + ordered[b].count - 1) % ordered[b].count]
                    a = b; b = next
                    if a == start && b == end {
                        if Set(path).count == path.count {
                            let polygon = path.map { nodes[$0] }
                            if polygon.count >= 3, signedArea(polygon) > 0.1, contains(point, polygon: polygon) { faces.append(polygon) }
                        }
                        break
                    }
                }
            }
        }
        return faces.min { signedArea($0) < signedArea($1) }
    }
    // Suggestions only: these inferred closures MUST be approved by the user.
    static func closureProposals(walls input: [Wall], keepPoint: SIMD2<Double>) -> [[Wall]] {
        guard input.count >= 2, input.count <= 100 else { return [] }
        let walls = normalizedWalls(input)
        let ends = walls.flatMap { [$0.start, $0.end] }
        var candidates: [(Double, [Wall])] = []
        // An observed room loop can coexist with spurs or neighboring loops.
        // Extract its bounded face before inventing a closing segment. Keep
        // this on the proposal path: never silently approve a selected room.
        if closedContour(input) == nil, let polygon = localFace(input, containing: keepPoint) {
            let boundary = polygon.indices.map {
                Wall(start: polygon[$0], end: polygon[($0 + 1) % polygon.count])
            }
            if closedContour(boundary) != nil { candidates.append((-1, boundary)) }
        }
        let loose = ends.indices.filter { i in
            !ends.indices.contains { j in j / 2 != i / 2 && simd_distance(ends[i], ends[j]) <= 0.30 }
        }
        if loose.count == 2 {
            let a = ends[loose[0]], b = ends[loose[1]]
            let gap = simd_distance(a, b)
            if gap >= 0.35 && gap <= 3 {
                let closed = walls + [Wall(start: a, end: b)]
                if closedContour(closed) != nil { candidates.append((gap, closed)) }
            }
        }
        // Facing wall ends can indicate the mouth of a corridor. Keep the side
        // occupied by the camera; never close everything with a bounding box.
        var cuts: [(Double, Boundary)] = []
        for i in ends.indices {
            for j in ends.indices where j > i && j / 2 != i / 2 {
                let span = ends[j] - ends[i], width = simd_length(span)
                guard width >= 0.5, width <= 3 else { continue }
                let u = simd_normalize(ends[i ^ 1] - ends[i])
                let v = simd_normalize(ends[j ^ 1] - ends[j])
                let across = span / width
                guard abs(simd_dot(u, v)) > 0.85, abs(simd_dot(u, across)) < 0.35 else { continue }
                let distance = abs(cross(across, keepPoint - ends[i]))
                guard distance >= 0.25 else { continue }
                cuts.append((distance + width * 0.2, Boundary(start: ends[i], end: ends[j], keepPoint: keepPoint)))
            }
        }
        for (score, cut) in cuts.sorted(by: { $0.0 < $1.0 }).prefix(24) {
            if let closed = boundedWalls(walls, boundaries: [cut]), closedContour(closed) != nil {
                candidates.append((score, closed))
            }
        }
        var seen = Set<String>()
        return candidates.sorted { $0.0 < $1.0 }.compactMap { _, candidate in
            guard let contour = closedContour(candidate), contains(keepPoint, polygon: contour) else { return nil }
            let key = contour.map { "\(Int(($0.x * 100).rounded())),\(Int(($0.y * 100).rounded()))" }.sorted().joined(separator: ";")
            return seen.insert(key).inserted ? candidate : nil
        }.prefix(6).map { $0 }
    }

    // A user-approved vertical cutting plane; never a physical support wall.
    // A cut with multiple disjoint crossings is deliberately rejected.
    static func boundedWalls(_ input: [Wall], boundaries: [Boundary]) -> [Wall]? {
        var walls = input
        for boundary in boundaries {
            let vector = boundary.end - boundary.start
            let length = simd_length(vector)
            guard length >= 0.25 else { return nil }
            let direction = vector / length
            let side = cross(direction, boundary.keepPoint - boundary.start)
            guard abs(side) >= 0.10 else { return nil }
            let sign = side > 0 ? 1.0 : -1.0
            func distance(_ p: SIMD2<Double>) -> Double { sign * cross(direction, p - boundary.start) }
            var kept: [Wall] = []
            var junctions: [SIMD2<Double>] = []
            for wall in walls {
                let a = distance(wall.start), b = distance(wall.end)
                if a < -0.04 && b < -0.04 { continue }
                var start = wall.start, end = wall.end
                if a * b < 0 {
                    let intersection = wall.start + (wall.end - wall.start) * (a / (a - b))
                    if a < 0 { start = intersection } else { end = intersection }
                }
                for p in [start, end] where abs(distance(p)) <= 0.04 {
                    let projected = boundary.start + direction * simd_dot(p - boundary.start, direction)
                    if !junctions.contains(where: { simd_distance($0, projected) < 0.08 }) { junctions.append(projected) }
                }
                if simd_distance(start, end) > 0.01 { kept.append(.init(start: start, end: end)) }
            }
            guard junctions.count == 2 else { return nil }
            kept.append(.init(start: junctions[0], end: junctions[1]))
            walls = kept
        }
        return walls
    }
    struct Triangle {
        let a: SIMD3<Double>
        let b: SIMD3<Double>
        let c: SIMD3<Double>
        var center: SIMD3<Double> { (a + b + c) / 3 }
        var cross: SIMD3<Double> { simd_cross(b - a, c - a) }
        var area: Double { simd_length(cross) / 2 }
        var normal: SIMD3<Double> { simd_normalize(cross) }
    }
    struct Pan {
        let vertices: [SIMD3<Double>]
        let area: Double
        let slopeDegrees: Double
        let observedSupportArea: Double
        let fitError: Double
    }
    struct Surface {
        let pans: [Pan]
        var vertices: [SIMD3<Double>] { pans.flatMap(\.vertices) }
        var area: Double { pans.reduce(0) { $0 + $1.area } }
        var slopeDegrees: Double { pans.map(\.slopeDegrees).max() ?? 0 }
        var observedSupportArea: Double { pans.reduce(0) { $0 + $1.observedSupportArea } }
        var fitError: Double { pans.map(\.fitError).max() ?? 0 }
        init(pans: [Pan]) { self.pans = pans }
        init(vertices: [SIMD3<Double>], area: Double, slopeDegrees: Double, observedSupportArea: Double, fitError: Double) {
            pans = [Pan(vertices: vertices, area: area, slopeDegrees: slopeDegrees,
                        observedSupportArea: observedSupportArea, fitError: fitError)]
        }
    }
    enum Failure: Error {
        case contour, observations, severalPlanes
        var message: String {
            switch self {
            case .contour: return "Les murs ne forment pas un contour fermé unique exploitable."
            case .observations: return "Pas assez de portions planes de plafond pour reconstruire sa surface."
            case .severalPlanes: return "Les surfaces détectées ne correspondent pas à un seul plan fiable."
            }
        }
    }

    struct Diagnostics: Codable {
        var stage = "contour"
        var inputTriangles = 0
        var retainedTriangles = 0
        var retainedArea = 0.0
        var inlierTriangles = 0
        var inlierArea = 0.0
        var supportRatio: Double?
        var residualMeters: Double?
        var slopeDegrees: Double?
        var detectedPans = 0
        var minimumSupportArea = 0.15
    }

    static func reconstruct(walls: [Wall], triangles: [Triangle], allowTwoPans: Bool = true, minimumSupportArea: Double = 0.15, diagnostic: ((Diagnostics) -> Void)? = nil) -> Result<Surface, Failure> {
        var report = Diagnostics(inputTriangles: triangles.count)
        report.minimumSupportArea = minimumSupportArea
        defer { diagnostic?(report) }
        guard let polygon = closedContour(walls), let indices = triangulate(polygon) else { return .failure(.contour) }
        report.stage = "insufficient_samples"
        let samples = triangles.filter {
            $0.area.isFinite && $0.area > 1e-7 && abs($0.normal.y) >= 0.42
                && contains(SIMD2($0.center.x, $0.center.z), polygon: polygon)
        }
        let totalArea = samples.reduce(0) { $0 + $1.area }
        report.retainedTriangles = samples.count
        report.retainedArea = totalArea
        guard samples.count >= 12, totalArea >= minimumSupportArea else { return .failure(.observations) }

        // Hypothèses déterministes tirées des normales du mesh. Un vote est pondéré
        // par la surface, pas par le nombre de triangles (densité LiDAR variable).
        var best: [Triangle] = []
        var bestArea = 0.0
        for index in stride(from: 0, to: samples.count, by: max(1, samples.count / 120)) {
            let seed = samples[index]
            let inliers = samples.filter {
                abs(simd_dot(seed.normal, $0.center - seed.center)) <= 0.06
                    && abs(simd_dot(seed.normal, $0.normal)) >= cos(20 * .pi / 180)
            }
            let area = inliers.reduce(0) { $0 + $1.area }
            if area > bestArea { bestArea = area; best = inliers }
        }
        report.stage = "insufficient_plane_support"
        report.inlierTriangles = best.count
        report.inlierArea = bestArea
        report.supportRatio = bestArea / totalArea
        guard best.count >= 12, bestArea >= minimumSupportArea else { return .failure(.observations) }
        if allowTwoPans, bestArea / totalArea < 0.85,
           let surface = reconstructTwoPans(walls: walls, polygon: polygon, indices: indices,
                                            samples: samples, first: best, totalArea: totalArea, minimumSupportArea: minimumSupportArea) {
            report.stage = "success_two_pans"
            report.detectedPans = 2
            report.supportRatio = surface.observedSupportArea / totalArea
            report.residualMeters = surface.fitError
            return .success(surface)
        }
        report.stage = "plane_support_below_70_percent"
        guard bestArea / totalArea >= 0.7 else { return .failure(.severalPlanes) }

        // Régression y = ax + bz + c, centrée pour la stabilité numérique.
        let origin = best.reduce(SIMD3<Double>.zero) { $0 + $1.center * $1.area } / bestArea
        var matrix = simd_double3x3(0)
        var rhs = SIMD3<Double>.zero
        for triangle in best {
            for point in [triangle.a, triangle.b, triangle.c] {
                let p = point - origin
                let v = SIMD3<Double>(p.x, p.z, 1)
                let w = triangle.area / 3
                matrix += simd_double3x3(columns: (v * v.x, v * v.y, v * v.z)) * w
                rhs += v * p.y * w
            }
        }
        report.stage = "degenerate_fit"
        guard abs(simd_determinant(matrix)) > 1e-12 else { return .failure(.observations) }
        let fit = simd_inverse(matrix) * rhs
        guard fit.x.isFinite, fit.y.isFinite, fit.z.isFinite else { return .failure(.observations) }
        let factor = sqrt(1 + fit.x * fit.x + fit.y * fit.y)
        let residual = sqrt(best.reduce(0) { sum, t in
            let p = t.center - origin
            let error = (p.y - fit.x * p.x - fit.y * p.z - fit.z) / factor
            return sum + error * error * t.area
        } / bestArea)
        report.residualMeters = residual
        report.stage = "residual_above_4_cm"
        guard residual <= 0.04 else { return .failure(.severalPlanes) }
        let slope = atan(hypot(fit.x, fit.y)) * 180 / .pi
        report.slopeDegrees = slope
        report.stage = "slope_above_65_degrees"
        guard slope <= 65 else { return .failure(.severalPlanes) }
        report.stage = "success"
        report.detectedPans = 1
        let vertices = indices.map { index -> SIMD3<Double> in
            let p = polygon[index]
            let height: Double = origin.y + fit.x * (p.x - origin.x) + fit.y * (p.y - origin.z) + fit.z
            return SIMD3<Double>(p.x, height, p.y)
        }
        let area = abs(signedArea(polygon)) * factor
        return .success(Surface(vertices: vertices, area: area, slopeDegrees: slope,
                                observedSupportArea: bestArea, fitError: residual))
    }

    // First multi-pan case: two observed opposing slopes meeting at a ridge.
    // Clip each contour triangle to both half-planes so concave outlines are
    // preserved without a hull, overlap, or filling external recesses.
    private static func reconstructTwoPans(walls: [Wall], polygon: [SIMD2<Double>], indices: [Int],
                                           samples: [Triangle], first: [Triangle], totalArea: Double, minimumSupportArea: Double) -> Surface? {
        guard case .success(let a) = reconstruct(walls: walls, triangles: first, allowTwoPans: false, minimumSupportArea: minimumSupportArea) else { return nil }
        func equation(_ surface: Surface) -> SIMD3<Double>? {
            let v = surface.vertices
            guard v.count >= 3 else { return nil }
            let n = simd_cross(v[1] - v[0], v[2] - v[0])
            guard abs(n.y) > 1e-9 else { return nil }
            let x = -n.x / n.y, z = -n.z / n.y
            return SIMD3(x, z, v[0].y - x * v[0].x - z * v[0].z)
        }
        guard let pa = equation(a) else { return nil }
        func height(_ p: SIMD3<Double>, _ xz: SIMD2<Double>) -> Double { p.x * xz.x + p.y * xz.y + p.z }
        func distance(_ t: Triangle, _ p: SIMD3<Double>) -> Double {
            abs(t.center.y - height(p, SIMD2(t.center.x, t.center.z))) / sqrt(1 + p.x * p.x + p.y * p.y)
        }
        let remaining = samples.filter { distance($0, pa) > 0.06 }
        guard case .success(let b) = reconstruct(walls: walls, triangles: remaining, allowTwoPans: false, minimumSupportArea: minimumSupportArea),
              let pb = equation(b), a.slopeDegrees >= 5, b.slopeDegrees >= 5 else { return nil }
        let ga = SIMD2(pa.x, pa.y), gb = SIMD2(pb.x, pb.y)
        guard simd_dot(simd_normalize(ga), simd_normalize(gb)) < -0.5 else { return nil }
        let planes = [pa, pb], fits = [a, b]
        var supports: [[Triangle]] = [[], []]
        for t in samples {
            let d = [distance(t, pa), distance(t, pb)]
            let i = d[0] <= d[1] ? 0 : 1
            let normal = simd_normalize(SIMD3(-planes[i].x, 1, -planes[i].y))
            if d[i] <= 0.06 && abs(simd_dot(normal, t.normal)) >= cos(20 * .pi / 180) { supports[i].append(t) }
        }
        let areas = supports.map { $0.reduce(0) { $0 + $1.area } }
        guard areas.allSatisfy({ $0 >= minimumSupportArea && $0 / totalArea >= 0.20 }),
              areas.reduce(0, +) / totalArea >= 0.85 else { return nil }
        var pans: [Pan] = []
        for i in 0..<2 {
            let p = planes[i], other = planes[1 - i]
            func side(_ x: SIMD2<Double>) -> Double { height(p, x) - height(other, x) }
            let correctSideArea = supports[i].filter { side(SIMD2($0.center.x, $0.center.z)) <= 0.06 }.reduce(0) { $0 + $1.area }
            guard correctSideArea / areas[i] >= 0.9 else { return nil }
            var vertices: [SIMD3<Double>] = []
            for k in stride(from: 0, to: indices.count, by: 3) {
                let triangle = (0..<3).map { polygon[indices[k + $0]] }
                var clipped: [SIMD2<Double>] = []
                for j in 0..<3 {
                    let start = triangle[j], end = triangle[(j + 1) % 3]
                    let ds = side(start), de = side(end)
                    if ds <= 0 { clipped.append(start) }
                    if (ds < 0 && de > 0) || (ds > 0 && de < 0) { clipped.append(start + (end - start) * (ds / (ds - de))) }
                }
                if clipped.count >= 3 {
                    for j in 1..<(clipped.count - 1) {
                        let points = [clipped[0], clipped[j], clipped[j + 1]].map { SIMD3($0.x, height(p, $0), $0.y) }
                        if Triangle(a: points[0], b: points[1], c: points[2]).area > 1e-9 { vertices += points }
                    }
                }
            }
            let area = stride(from: 0, to: vertices.count, by: 3).reduce(0.0) { $0 + Triangle(a: vertices[$1], b: vertices[$1 + 1], c: vertices[$1 + 2]).area }
            let projected = area / sqrt(1 + p.x * p.x + p.y * p.y)
            guard projected >= abs(signedArea(polygon)) * 0.1 else { return nil }
            pans.append(Pan(vertices: vertices, area: area, slopeDegrees: fits[i].slopeDegrees,
                            observedSupportArea: areas[i], fitError: fits[i].fitError))
        }
        return Surface(pans: pans)
    }

    // In-memory, explicitly shared report: enough wall geometry to replay failures.
    static func contourDiagnostic(walls: [Wall], boundaries: [Boundary] = []) -> String? {
        guard walls.allSatisfy({ [$0.start.x, $0.start.y, $0.end.x, $0.end.y].allSatisfy(\.isFinite) }) else { return nil }
        let cleaned = normalizedWalls(walls)
        func rows(_ list: [Wall]) -> [[String: Any]] {
            list.enumerated().map { index, wall in
                ["id": index + 1, "start": [wall.start.x, wall.start.y],
                 "end": [wall.end.x, wall.end.y], "length": simd_distance(wall.start, wall.end)]
            }
        }
        let ends = cleaned.flatMap { [$0.start, $0.end] }
        let distances: [[String: Any]] = ends.indices.map { i in
            let nearest = ends.indices.filter { $0 / 2 != i / 2 }
                .sorted { simd_distance(ends[i], ends[$0]) < simd_distance(ends[i], ends[$1]) }.prefix(3)
            return ["wall": i / 2 + 1, "endpoint": i % 2 == 0 ? "start" : "end",
                    "nearest": nearest.map { j -> [String: Any] in
                        ["wall": j / 2 + 1, "endpoint": j % 2 == 0 ? "start" : "end",
                         "distance": simd_distance(ends[i], ends[j])]
                    }]
        }
        let payload: [String: Any] = ["format": "plaquisto-contour-v1", "units": "meters", "axes": ["worldX", "worldZ"],
                                      "virtualBoundaries": boundaries.map { ["start": [$0.start.x, $0.start.y], "end": [$0.end.x, $0.end.y], "keepPoint": [$0.keepPoint.x, $0.keepPoint.y]] },
                                      "boundedWalls": boundedWalls(walls, boundaries: boundaries).map(rows) as Any? ?? NSNull(),
                                      "rawWalls": rows(walls), "normalizedWalls": rows(cleaned),
                                      "endpointDistances": distances, "closedContour": closedContour(walls)?.map { [$0.x, $0.y] } as Any? ?? NSNull()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Merge only overlapping / almost touching pieces on the same supporting line.
    // A parallel wall or an actual opening must not disappear during cleanup.
    private static func normalizedWalls(_ input: [Wall]) -> [Wall] {
        var walls = input.filter { simd_distance($0.start, $0.end) > 0.01 }
        var changed = true
        while changed {
            changed = false
            outer: for i in walls.indices {
                for j in walls.indices where j > i {
                    let a = walls[i], b = walls[j]
                    let length = simd_distance(a.start, a.end)
                    let direction = (a.end - a.start) / length
                    let other = simd_normalize(b.end - b.start)
                    guard abs(simd_dot(direction, other)) >= cos(3 * .pi / 180),
                          abs(cross(direction, b.start - a.start)) <= 0.04,
                          abs(cross(direction, b.end - a.start)) <= 0.04 else { continue }
                    let t0 = simd_dot(b.start - a.start, direction)
                    let t1 = simd_dot(b.end - a.start, direction)
                    guard min(t0, t1) <= length + 0.20, max(t0, t1) >= -0.20 else { continue }
                    walls[i] = Wall(start: a.start + direction * min(0, t0, t1),
                                    end: a.start + direction * max(length, t0, t1))
                    walls.remove(at: j)
                    changed = true
                    break outer
                }
            }
        }
        return walls
    }

    /// Shared with the explicit flat-ceiling fallback. Does not invent missing
    /// walls or use a bounding rectangle; rejects ambiguous/open contours.
    static func closedContour(_ input: [Wall]) -> [SIMD2<Double>]? {
        guard input.count <= 100,
              input.allSatisfy({ [$0.start.x, $0.start.y, $0.end.x, $0.end.y].allSatisfy(\.isFinite) }) else { return nil }
        let walls = normalizedWalls(input)
        guard walls.count >= 3, walls.count <= 100 else { return nil }
        let endpoints = walls.flatMap { [$0.start, $0.end] }
        guard endpoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        // Use line intersections at corners instead of averaging shortened ends.
        // Corrections are bounded (30 cm and 25% of each wall), never a hull.
        func junction(_ i: Int, _ j: Int) -> SIMD2<Double>? {
            guard i / 2 != j / 2 else { return nil }
            let p = endpoints[i], q = endpoints[j]
            let u = endpoints[i ^ 1] - p, v = endpoints[j ^ 1] - q
            let lu = simd_length(u), lv = simd_length(v)
            let denominator = cross(u, v)
            if abs(denominator) / (lu * lv) >= sin(15 * .pi / 180) {
                let point = p + u * (cross(q - p, v) / denominator)
                if simd_distance(point, p) <= min(0.30, lu * 0.25),
                   simd_distance(point, q) <= min(0.30, lv * 0.25) { return point }
                return nil
            }
            return simd_distance(p, q) <= 0.20 ? (p + q) / 2 : nil
        }
        var matches = [Int: Int]()
        for i in endpoints.indices {
            let candidates = endpoints.indices.filter { junction(i, $0) != nil }
            guard candidates.count == 1 else { return nil }
            matches[i] = candidates[0]
        }
        guard matches.allSatisfy({ matches[$0.value] == $0.key }) else { return nil }
        var polygon: [SIMD2<Double>] = []
        var visited = Set<Int>()
        var entry = 0
        repeat {
            guard visited.insert(entry / 2).inserted, let previous = matches[entry] else { return nil }
            guard let point = junction(entry, previous) else { return nil }
            polygon.append(point)
            guard let next = matches[entry ^ 1] else { return nil }
            entry = next
        } while entry != 0
        guard visited.count == walls.count, abs(signedArea(polygon)) >= 0.1 else { return nil }
        // Retirer les sommets colinéaires provenant d'un mur découpé en segments.
        var changed = true
        while changed && polygon.count > 3 {
            changed = false
            for i in polygon.indices {
                let a = polygon[(i + polygon.count - 1) % polygon.count]
                let b = polygon[i]
                let c = polygon[(i + 1) % polygon.count]
                if abs(cross(b - a, c - b)) < 1e-6 {
                    polygon.remove(at: i); changed = true; break
                }
            }
        }
        for i in polygon.indices {
            for j in polygon.indices where j > i + 1 && !(i == 0 && j == polygon.count - 1) {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let c = polygon[j], d = polygon[(j + 1) % polygon.count]
                let boxesOverlap = max(min(a.x, b.x), min(c.x, d.x)) <= min(max(a.x, b.x), max(c.x, d.x)) + 1e-9
                    && max(min(a.y, b.y), min(c.y, d.y)) <= min(max(a.y, b.y), max(c.y, d.y)) + 1e-9
                if boxesOverlap && cross(b - a, c - a) * cross(b - a, d - a) <= 0
                    && cross(d - c, a - c) * cross(d - c, b - c) <= 0 { return nil }
            }
        }
        return signedArea(polygon) > 0 ? polygon : Array(polygon.reversed())
    }

    static func triangulate(_ polygon: [SIMD2<Double>]) -> [Int]? {
        var remaining = Array(polygon.indices)
        var triangles: [Int] = []
        while remaining.count > 3 {
            var removed = false
            for i in remaining.indices {
                let a = remaining[(i + remaining.count - 1) % remaining.count]
                let b = remaining[i], c = remaining[(i + 1) % remaining.count]
                guard cross(polygon[b] - polygon[a], polygon[c] - polygon[b]) > 1e-9 else { continue }
                let hasInterior = remaining.contains { k in
                    k != a && k != b && k != c
                        && cross(polygon[b] - polygon[a], polygon[k] - polygon[a]) >= -1e-9
                        && cross(polygon[c] - polygon[b], polygon[k] - polygon[b]) >= -1e-9
                        && cross(polygon[a] - polygon[c], polygon[k] - polygon[c]) >= -1e-9
                }
                if !hasInterior {
                    triangles += [a, b, c]; remaining.remove(at: i); removed = true; break
                }
            }
            guard removed else { return nil }
        }
        return triangles + remaining
    }

    private static func contains(_ point: SIMD2<Double>, polygon: [SIMD2<Double>]) -> Bool {
        var inside = false
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if (a.y > point.y) != (b.y > point.y)
                && point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }
    private static func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
    private static func signedArea(_ p: [SIMD2<Double>]) -> Double {
        p.indices.reduce(0) { $0 + cross(p[$1], p[($1 + 1) % p.count]) } / 2
    }
}
