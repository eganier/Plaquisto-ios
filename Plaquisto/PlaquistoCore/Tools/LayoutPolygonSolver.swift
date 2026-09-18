import Foundation

extension Surface2D {
    /// A drag edits the sketch, not a permanently pinned vertex on the old sketch.
    /// Only visible angle/length locks may move neighbouring vertices.
    func movingVertices(to points: [LayoutPoint]) throws -> Surface2D {
        guard points.count == contour.count else { throw LayoutGeometryError.invalidContour }
        try LayoutGeometry.validate(points)
        guard LayoutGeometry.area(points) * LayoutGeometry.area(contour) > 0 else {
            throw LayoutPolygonError.incompatibleConstraints
        }
        guard points != contour else { return self }
        let previous = editableIntent
        var intent = previous
        intent.sketch = points
        // Old drags were saved as invisible persistent pins. Replace them with
        // the current gesture's temporary targets, without losing measured locks.
        intent.userVertexPositions = points.indices.map { points[$0] != contour[$0] ? points[$0] : nil }
        var configuration = GeometryResolutionConfiguration.standard
        configuration.measuredLengthWeight = 0
        configuration.sketchLengthWeight = 0
        configuration.sketchDirectionWeight = 0
        configuration.sketchPositionWeight = 0.2
        let resolved = try LayoutPolygonSolver.resolve(intent, configuration:configuration)
        var copy = self
        copy.previousContourIntents.append(previous)
        copy.contour = resolved.contour
        copy.dimensionCorrections = resolved.corrections
        intent.sketch = resolved.contour
        intent.userVertexPositions = Array(repeating:nil,count:points.count)
        copy.contourIntent = intent
        return copy
    }

    var canScaleDrawing: Bool {
        provenance == "manual" && contourIntent.map { $0.userMeasuredLengths.allSatisfy { $0 == nil } } == true
    }
    func scaledDrawing(by factor: Double) throws -> Surface2D {
        guard canScaleDrawing, factor.isFinite, factor >= 0.05, factor <= 20 else { throw LayoutGeometryError.invalidFormat }
        let origin = bounds.min
        func scale(_ p: LayoutPoint) -> LayoutPoint { origin+(p-origin)*factor }
        var copy = self
        copy.contour = contour.map(scale)
        try LayoutGeometry.validate(copy.contour)
        copy.openings = openings.map { opening in var o = opening; o.contour = o.contour.map(scale); return o }
        if var intent = contourIntent {
            intent.sketch = intent.sketch.map(scale)
            intent.userVertexPositions = intent.userVertexPositions.map { $0.map(scale) }
            copy.contourIntent = intent
        }
        return copy
    }
}

// Capture/beautification distances are screen points; resolved geometry is millimetres.
struct PolygonBeautificationConfiguration {
    static let standard = Self()
    var samplingDistance = 2.5
    var maximumSamples = 2048
    var closureDistance = 28.0
    var closureFraction = 0.14
    var simplificationDistance = 10.0
    var minimumSegment = 12.0
    var maximumCornerBevel = 32.0
    var collinearAngleDegrees = 10.0
    var snapAngleDegrees = 3.0
}

struct GeometryResolutionConfiguration {
    static let standard = Self()
    var significantCorrection = 0.1 // 0.1 mm, numerical noise is not a field correction.
    var yellowLimit = 20.0
    var orangeLimit = 50.0
    var minimumLength = 10.0
    var maximumIterations = 60
    var measuredLengthWeight = 1.0
    var sketchLengthWeight = 0.08
    var sketchDirectionWeight = 0.04
    var sketchPositionWeight = 0.0
    var manualAngleWeight = 100.0
    var manualVertexWeight = 100.0
    var maximumAngleResidualDegrees = 0.25
    var maximumVertexResidual = 0.5
}

enum LayoutCorrectionSeverity { case none, yellow, orange, red }

extension LayoutDimensionCorrection {
    var correctionDelta: Double { corrected - original }
    func severity(_ configuration: GeometryResolutionConfiguration = .standard) -> LayoutCorrectionSeverity {
        if difference <= configuration.significantCorrection { return .none }
        if difference < configuration.yellowLimit { return .yellow }
        if difference <= configuration.orangeLimit { return .orange }
        return .red
    }
}

enum LayoutPolygonError: Error, LocalizedError {
    case openStroke, shortStroke, incompatibleConstraints
    var errorDescription: String? {
        switch self {
        case .openStroke: return "Le tracé reste ouvert. Revenez près du point de départ avant de relever le doigt."
        case .shortStroke: return "Dessinez un contour plus grand, avec au moins trois côtés."
        case .incompatibleConstraints: return "Ces contraintes ne donnent pas un contour valide. Vérifiez les angles ou les mesures ; le plan précédent est conservé."
        }
    }
}

enum LayoutStrokeBeautifier {
    static func polygon(from raw: [LayoutPoint], kind:LayoutSupportKind = .ceiling, configuration c: PolygonBeautificationConfiguration = .standard) throws -> [LayoutPoint] {
        guard raw.count >= 4, raw.count <= c.maximumSamples, raw.allSatisfy(\.finite) else { throw LayoutPolygonError.shortStroke }
        var points: [LayoutPoint] = []
        for point in raw where points.last.map({ ($0 - point).length >= c.samplingDistance }) ?? true { points.append(point) }
        guard points.count >= 4 else { throw LayoutPolygonError.shortStroke }
        let bounds = LayoutBounds(points: points), size = max(bounds.width, bounds.height)
        guard size >= c.minimumSegment * 3 else { throw LayoutPolygonError.shortStroke }
        let gap = (raw.last! - raw.first!).length
        guard gap <= max(c.closureDistance, size * c.closureFraction) else { throw LayoutPolygonError.openStroke }
        if (points.last! - points[0]).length < c.minimumSegment { points.removeLast() }
        // Cyclic five-point filter removes hand tremor, without treating the start as a corner.
        let smoothed = points.indices.map { i in
            points[(i + points.count - 2) % points.count] * 0.1
                + points[(i + points.count - 1) % points.count] * 0.2 + points[i] * 0.4
                + points[(i + 1) % points.count] * 0.2 + points[(i + 2) % points.count] * 0.1
        }
        // Split the closed ring at distant points, so RDP never sees coincident endpoints.
        let first = smoothed.indices.max { (smoothed[$0] - bounds.center).length < (smoothed[$1] - bounds.center).length }!
        let ring = Array(smoothed[first...]) + Array(smoothed[..<first])
        let opposite = ring.indices.max { (ring[$0] - ring[0]).length < (ring[$1] - ring[0]).length }!
        let polygon = rdp(Array(ring[...opposite]), tolerance: c.simplificationDistance).dropLast()
            + rdp(Array(ring[opposite...]) + [ring[0]], tolerance: c.simplificationDistance).dropLast()
        var cleaned = Array(polygon)
        var changed = true
        while changed && cleaned.count > 3 {
            changed = false
            for i in cleaned.indices {
                let a = cleaned[(i + cleaned.count - 1) % cleaned.count], b = cleaned[i], d = cleaned[(i + 1) % cleaned.count]
                let incoming = b - a, outgoing = d - b
                let turn = abs(atan2(LayoutGeometry.cross(incoming, outgoing), LayoutGeometry.dot(incoming, outgoing))) * 180 / .pi
                if incoming.length < c.minimumSegment || outgoing.length < c.minimumSegment || turn < c.collinearAngleDegrees {
                    cleaned.remove(at: i); changed = true; break
                }
            }
        }
        // A rounded hand-drawn corner can leave two close vertices joined by a
        // tiny bevel. Intersect its two supporting lines when both turns agree.
        // This is local geometric cleanup, never recognition of a preset shape.
        changed = true
        while changed && cleaned.count > 3 {
            changed = false
            for i in cleaned.indices {
                let next = (i+1)%cleaned.count, previous = (i+cleaned.count-1)%cleaned.count, after = (i+2)%cleaned.count
                let a = cleaned[previous], b = cleaned[i], d = cleaned[next], e = cleaned[after]
                let incoming = b-a, bevel = d-b, outgoing = e-d
                guard bevel.length < c.maximumCornerBevel,
                      LayoutGeometry.cross(incoming,bevel)*LayoutGeometry.cross(bevel,outgoing) > 0 else { continue }
                let determinant = LayoutGeometry.cross(incoming,outgoing)
                guard abs(determinant) > 1e-6 else { continue }
                let corner = a + incoming * (LayoutGeometry.cross(d-a,outgoing)/determinant)
                guard (corner-b).length <= c.maximumCornerBevel, (corner-d).length <= c.maximumCornerBevel else { continue }
                var candidate = cleaned; candidate[i] = corner; candidate.remove(at:next)
                if (try? LayoutGeometry.validate(candidate)) != nil { cleaned = candidate; changed = true; break }
            }
        }
        try LayoutGeometry.validate(cleaned)
        if LayoutGeometry.area(cleaned) < 0 { cleaned.reverse() }
        // Very small axis snapping only. Closure is distributed by least squares.
        let directions = LayoutGeometry.edges(cleaned).map { edge -> LayoutPoint in
            let v = edge.b - edge.a, angle = atan2(v.y, v.x), snapped = (angle / (.pi / 2)).rounded() * (.pi / 2)
            let use = abs(angle - snapped) <= c.snapAngleDegrees * .pi / 180 ? snapped : angle
            return .init(x: cos(use), y: sin(use))
        }
        let lengths = LayoutGeometry.edges(cleaned).map { ($0.b - $0.a).length }
        if kind == .wall, let snapped = try? LayoutPolygonSolver.closeDirections(directions, lengths: lengths, origin: cleaned[0], minimum: c.minimumSegment / 2),
           zip(snapped, cleaned).allSatisfy({ ($0 - $1).length < c.simplificationDistance * 2 }) { cleaned = snapped }
        return try alignedToGround(cleaned,squareGroundCorners:kind == .wall)
    }

    /// Applied only when lifting the finger after a new sketch, never when
    /// editing measured/locked geometry. Rigid rotation first; conservative
    /// cleanup of the two convex ground corners second.
    static func alignedToGround(_ polygon:[LayoutPoint], squareGroundCorners:Bool = false, cornerToleranceDegrees:Double = 8) throws -> [LayoutPoint] {
        try LayoutGeometry.validate(polygon)
        var points = polygon
        if LayoutGeometry.area(points) < 0 { points.reverse() }
        guard let edge = groundEdge(points), let base = points.firstIndex(of:edge.a) else { return points }
        points = Array(points[base...])+Array(points[..<base])
        let origin = points[0], vector = points[1]-origin, angle = -atan2(vector.y,vector.x)
        let aligned = points.map { p -> LayoutPoint in
            let v = p-origin
            return .init(x:v.x*cos(angle)-v.y*sin(angle),y:v.x*sin(angle)+v.y*cos(angle))
        }
        var result = aligned
        result[0] = .zero; result[1] = .init(x:vector.length,y:0)
        if squareGroundCorners && result.count >= 4 {
            // Project the upper neighbour, keeping the ground segment intact.
            if abs(LayoutPolygonSolver.interiorAngle(at:0,in:aligned)-90) <= cornerToleranceDegrees,
               aligned.last!.y > 0 { result[result.count-1].x = 0 }
            if abs(LayoutPolygonSolver.interiorAngle(at:1,in:aligned)-90) <= cornerToleranceDegrees,
               aligned[2].y > 0 { result[2].x = vector.length }
            if (try? LayoutGeometry.validate(result)) == nil || LayoutGeometry.area(result) <= 0 { return aligned }
        }
        return result
    }

    static func groundEdge(_ polygon:[LayoutPoint]) -> (a:LayoutPoint,b:LayoutPoint)? {
        guard polygon.count >= 3 else { return nil }
        let points = LayoutGeometry.area(polygon) < 0 ? Array(polygon.reversed()) : polygon
        let width = LayoutBounds(points:points).width
        return LayoutGeometry.edges(points).filter {
            let v = $0.b-$0.a
            return v.x > abs(v.y) && v.length >= width*0.15
        }.min { ($0.a.y+$0.b.y) < ($1.a.y+$1.b.y) }.map { ($0.a,$0.b) }
    }

    // Iterative RDP avoids recursive stack growth on adversarial scribbles.
    private static func rdp(_ p: [LayoutPoint], tolerance: Double) -> [LayoutPoint] {
        guard p.count > 2 else { return p }
        var keep: Set<Int> = [0, p.count - 1], stack = [(0, p.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var distance = tolerance, split: Int?
            for i in (start + 1)..<end {
                let d = LayoutGeometry.distance(p[i], to: p[start], p[end])
                if d > distance { distance = d; split = i }
            }
            if let split { keep.insert(split); stack.append((start, split)); stack.append((split, end)) }
        }
        return keep.sorted().map { p[$0] }
    }
}

// The source sketch and manually entered values never contain resolved replacements.
// Nil is an inferred value, not a field measurement. Arrays follow contour vertex order.
struct LayoutContourIntent: Codable, Equatable {
    var sketch: [LayoutPoint]
    var userMeasuredLengths: [Double?]
    var userAnglesDegrees: [Double?]
    var userVertexPositions: [LayoutPoint?]
    var lockedLengthIndices: [Int]? = nil
    init(sketch: [LayoutPoint]) {
        self.sketch = sketch
        userMeasuredLengths = Array(repeating: nil, count: sketch.count)
        userAnglesDegrees = Array(repeating: nil, count: sketch.count)
        userVertexPositions = Array(repeating: nil, count: sketch.count)
    }
}

struct LayoutResolvedPolygon {
    var contour: [LayoutPoint]
    var corrections: [LayoutDimensionCorrection]
}

enum LayoutPolygonSolver {
    static func interiorAngle(at i: Int, in p: [LayoutPoint]) -> Double {
        guard p.count >= 3, p.indices.contains(i) else { return 0 }
        let incoming = p[i] - p[(i + p.count - 1) % p.count], outgoing = p[(i + 1) % p.count] - p[i]
        let winding = LayoutGeometry.area(p) >= 0 ? 1.0 : -1.0
        return 180 - winding * atan2(LayoutGeometry.cross(incoming, outgoing), LayoutGeometry.dot(incoming, outgoing)) * 180 / .pi
    }

    // Levenberg–Marquardt least squares on the shared vertex coordinates.
    // Closure is structural (last edge always ends at vertex zero), never a soft penalty.
    // Local analytic Jacobians keep each iteration bounded and deterministic.
    static func resolve(_ intent: LayoutContourIntent, configuration c: GeometryResolutionConfiguration = .standard) throws -> LayoutResolvedPolygon {
        let n = intent.sketch.count
        guard n >= 3, n <= 200, intent.userMeasuredLengths.count == n,
              intent.userAnglesDegrees.count == n, intent.userVertexPositions.count == n,
              intent.userMeasuredLengths.compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= c.minimumLength && $0 <= 100_000 }),
              intent.userAnglesDegrees.compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 5 && $0 < 355 }),
              intent.userVertexPositions.compactMap({ $0 }).allSatisfy(\.finite) else { throw LayoutGeometryError.invalidContour }
        try LayoutGeometry.validate(intent.sketch)
        let originalLengths = LayoutGeometry.edges(intent.sketch).map { ($0.b - $0.a).length }
        let targets = (0..<n).map { intent.userMeasuredLengths[$0] ?? originalLengths[$0] }
        let scale = max(100, targets.reduce(0, +) / Double(n)), origin = intent.sketch[0]
        let reference = intent.sketch.map { ($0 - origin) * (1 / scale) }
        var x = reference.flatMap { [$0.x, $0.y] }
        let winding = LayoutGeometry.area(reference) >= 0 ? 1.0 : -1.0
        func rows(_ values: [Double]) -> [(Double, [(Int, Double)])] {
            func point(_ i: Int) -> LayoutPoint { .init(x: values[2 * i], y: values[2 * i + 1]) }
            var result: [(Double, [(Int, Double)])] = []
            func add(_ residual: Double, _ derivative: [(Int, Double)], _ weight: Double) {
                result.append((residual * weight, derivative.map { ($0.0, $0.1 * weight) }))
            }
            for i in 0..<n {
                if c.sketchPositionWeight > 0 {
                    add(values[2*i] - reference[i].x, [(2*i, 1)], c.sketchPositionWeight)
                    add(values[2*i+1] - reference[i].y, [(2*i+1, 1)], c.sketchPositionWeight)
                }
                let next = (i + 1) % n, d = point(next) - point(i), length = max(1e-9, d.length), u = d * (1 / length)
                add(length - targets[i] / scale,
                    [(2*i, -u.x), (2*i+1, -u.y), (2*next, u.x), (2*next+1, u.y)],
                    intent.lockedLengthIndices?.contains(i) == true ? 100 : (intent.userMeasuredLengths[i] == nil ? c.sketchLengthWeight : c.measuredLengthWeight))
                let source = reference[next] - reference[i], sourceLength = max(1e-9, source.length)
                let sourceAngle = atan2(source.y, source.x)
                let difference = wrapped(atan2(d.y, d.x) - sourceAngle)
                let g = LayoutPoint(x: -d.y / (length * length), y: d.x / (length * length))
                add(difference, [(2*i, -g.x), (2*i+1, -g.y), (2*next, g.x), (2*next+1, g.y)],
                    c.sketchDirectionWeight * min(1, sourceLength))
                if let angle = intent.userAnglesDegrees[i] {
                    let prev = (i + n - 1) % n, incoming = point(i) - point(prev), l2 = max(1e-12, LayoutGeometry.dot(incoming, incoming))
                    let gi = LayoutPoint(x: -incoming.y / l2, y: incoming.x / l2)
                    let targetTurn = winding * (.pi - angle * .pi / 180)
                    let residual = wrapped(atan2(d.y, d.x) - atan2(incoming.y, incoming.x) - targetTurn)
                    add(residual, [(2*prev, gi.x), (2*prev+1, gi.y), (2*i, -g.x-gi.x), (2*i+1, -g.y-gi.y),
                                   (2*next, g.x), (2*next+1, g.y)], c.manualAngleWeight)
                }
                if let target = intent.userVertexPositions[i] {
                    let p = (target - origin) * (1 / scale)
                    add(values[2*i] - p.x, [(2*i, 1)], c.manualVertexWeight)
                    add(values[2*i+1] - p.y, [(2*i+1, 1)], c.manualVertexWeight)
                }
            }
            // Translation gauge only; a moved vertex supplies the gauge when present.
            if intent.userVertexPositions.allSatisfy({ $0 == nil }) {
                add(values[0], [(0, 1)], c.manualVertexWeight)
                add(values[1], [(1, 1)], c.manualVertexWeight)
            }
            return result
        }
        var damping = 0.001
        for _ in 0..<c.maximumIterations {
            let r = rows(x), cost = r.reduce(0) { $0 + $1.0 * $1.0 }, size = x.count
            var h = Array(repeating: Array(repeating: 0.0, count: size), count: size), gradient = Array(repeating: 0.0, count: size)
            for (residual, jacobian) in r {
                for (a, da) in jacobian {
                    gradient[a] += da * residual
                    for (b, db) in jacobian { h[a][b] += da * db }
                }
            }
            if (gradient.map(abs).max() ?? 0) < 1e-10 { break }
            for i in 0..<size { h[i][i] += damping * max(1, h[i][i]) }
            guard let delta = linearSolve(h, gradient.map { -$0 }) else { break }
            let candidate = zip(x, delta).map(+)
            let candidateCost = rows(candidate).reduce(0) { $0 + $1.0 * $1.0 }
            if candidateCost < cost {
                x = candidate; damping = max(1e-10, damping / 3)
                if delta.map(abs).max() ?? 0 < 1e-8 { break }
            } else {
                damping *= 10
                if damping > 1e10 { break }
            }
        }
        let contour = (0..<n).map { LayoutPoint(x: x[2*$0], y: x[2*$0+1]) * scale + origin }
        try LayoutGeometry.validate(contour)
        guard LayoutGeometry.area(contour) * LayoutGeometry.area(intent.sketch) > 0,
              LayoutGeometry.edges(contour).allSatisfy({ ($0.b - $0.a).length >= c.minimumLength }) else { throw LayoutPolygonError.incompatibleConstraints }
        for i in 0..<n {
            if intent.lockedLengthIndices?.contains(i) == true, let length = intent.userMeasuredLengths[i],
               abs((contour[(i+1)%n]-contour[i]).length-length) > 0.5 {
                throw LayoutPolygonError.incompatibleConstraints
            }
            if let angle = intent.userAnglesDegrees[i], abs(interiorAngle(at: i, in: contour) - angle) > c.maximumAngleResidualDegrees {
                throw LayoutPolygonError.incompatibleConstraints
            }
            if let position = intent.userVertexPositions[i], (contour[i]-position).length > c.maximumVertexResidual {
                throw LayoutPolygonError.incompatibleConstraints
            }
        }
        let corrections = (0..<n).compactMap { i -> LayoutDimensionCorrection? in
            guard let length = intent.userMeasuredLengths[i] else { return nil }
            let resolved = (contour[(i + 1) % n] - contour[i]).length
            guard abs(resolved - length) > c.significantCorrection else { return nil }
            return .init(edgeIndex: i, original: length, corrected: resolved)
        }
        return .init(contour: contour, corrections: corrections)
    }

    static func closeDirections(_ directions: [LayoutPoint], lengths: [Double], origin: LayoutPoint, minimum: Double) throws -> [LayoutPoint] {
        let error = zip(directions, lengths).reduce(LayoutPoint.zero) { $0 + $1.0 * $1.1 }
        let xx = directions.reduce(0) { $0 + $1.x * $1.x }, xy = directions.reduce(0) { $0 + $1.x * $1.y }, yy = directions.reduce(0) { $0 + $1.y * $1.y }
        let determinant = xx * yy - xy * xy
        guard abs(determinant) > 1e-8 else { throw LayoutGeometryError.invalidContour }
        let lambda = LayoutPoint(x: (yy * error.x - xy * error.y) / determinant, y: (xx * error.y - xy * error.x) / determinant)
        let corrected = zip(directions, lengths).map { $1 - LayoutGeometry.dot($0, lambda) }
        guard corrected.allSatisfy({ $0 >= minimum }) else { throw LayoutGeometryError.invalidContour }
        var p = [origin]
        for i in 0..<(directions.count - 1) { p.append(p[i] + directions[i] * corrected[i]) }
        try LayoutGeometry.validate(p)
        return p
    }

    private static func wrapped(_ radians: Double) -> Double { atan2(sin(radians), cos(radians)) }
    private static func linearSolve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        // Cholesky: normal matrix is symmetric positive definite after LM damping.
        let n = rhs.count
        var l = matrix
        for i in 0..<n {
            for j in 0...i {
                var value = matrix[i][j]
                for k in 0..<j { value -= l[i][k] * l[j][k] }
                if i == j { guard value > 0, value.isFinite else { return nil }; l[i][j] = sqrt(value) }
                else { l[i][j] = value / l[j][j] }
            }
        }
        var y = rhs
        for i in 0..<n { for j in 0..<i { y[i] -= l[i][j] * y[j] }; y[i] /= l[i][i] }
        var x = y
        for i in (0..<n).reversed() { for j in (i+1)..<n { x[i] -= l[j][i] * x[j] }; x[i] /= l[i][i] }
        return x
    }
}

extension Surface2D {
    var editableIntent: LayoutContourIntent {
        if let contourIntent { return contourIntent }
        var intent = LayoutContourIntent(sketch: contour)
        intent.userMeasuredLengths = LayoutGeometry.edges(contour).map { ($0.b - $0.a).length }
        for correction in dimensionCorrections where contour.indices.contains(correction.edgeIndex) {
            intent.userMeasuredLengths[correction.edgeIndex] = correction.original
        }
        return intent
    }
    mutating func resolve(_ intent: LayoutContourIntent) throws {
        let resolved = try LayoutPolygonSolver.resolve(intent)
        contourIntent = intent; contour = resolved.contour; dimensionCorrections = resolved.corrections
    }
}
