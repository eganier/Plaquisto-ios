import Foundation

enum LayoutVisibilityState: Int, CaseIterable {
    case visible, dimensioned, hidden
    var isVisible: Bool { self != .hidden }
    var showsDimensions: Bool { self == .dimensioned }
    var next: Self { Self(rawValue:(rawValue+1)%3)! }
}

struct LayoutVisibilitySettings {
    var sheets = LayoutVisibilityState.visible
    var framing = LayoutVisibilityState.visible
    var openings = LayoutVisibilityState.visible
    var electrical = LayoutVisibilityState.visible
    var angles = false
}

extension LayoutDocument {
    /// Only new supports receive a starter frame. Saved plans keep their choices,
    /// including an explicitly absent frame, when reopened.
    static func newSupport(_ surface:Surface2D) -> Self {
        var layer = LayoutLayer(furring:.init()).forSurface(surface)
        if surface.kind == .ceiling {
            // Standard ceiling starter configuration: 240 × 120 cm boards are
            // compatible with 60 cm furring centres in both board orientations.
            layer.sheetWidth = 1200
            layer.sheetLength = 2400
            layer.furring?.spacing = 600
        } else {
            let spacing = LayoutPlanning.compatibleSpacings(layer).last ?? 400
            layer.furring?.spacing = spacing
        }
        return .init(surface:surface,layers:[layer])
    }
}

enum LayoutElectricalKind: String, Codable, CaseIterable {
    case light = "Lumière", socket = "Prise"
    var prefix: String { self == .socket ? "P" : "L" }
}
struct LayoutLighting: Codable, Equatable {
    var count = 6
    var spread = 0.75
    var diameter = 68.0
    var positions: [LayoutPoint] = []
    var kinds: [LayoutElectricalKind]? = nil
    func kind(at index:Int) -> LayoutElectricalKind { kinds?.indices.contains(index) == true ? kinds![index] : .light }
    func label(at index:Int, wall:Bool) -> String { "\(wall ? kind(at:index).prefix : "S")\(index+1)" }
}

enum LayoutSpotArrangement: String, CaseIterable {
    case horizontal = "Aligner horizontalement", vertical = "Aligner verticalement"
    case distributeX = "Répartir horizontalement", distributeY = "Répartir verticalement"
    var minimumCount: Int { self == .horizontal || self == .vertical ? 2 : 3 }
}

enum LayoutLightingEditError: Error, LocalizedError {
    case invalidPlacement
    var errorDescription: String? { "Placement impossible : les spots doivent rester dans le plafond, hors des ouvertures et sans se chevaucher." }
}

struct LayoutWallDimension: Identifiable {
    var id: String
    var start: LayoutPoint
    var end: LayoutPoint
    var distance: Double { (end-start).length }
}

enum LayoutPlanning {
    static func centeredLighting(_ lighting:LayoutLighting, selected:Set<Int>, surface:Surface2D) throws -> LayoutLighting {
        let points = selected.sorted().filter { lighting.positions.indices.contains($0) }.map { lighting.positions[$0] }
        guard !points.isEmpty else { return lighting }
        var delta = surface.bounds.center-LayoutBounds(points:points).center
        if surface.kind == .wall { delta.y = 0 }
        let copy = translatedLighting(lighting,indices:selected,delta:delta)
        guard lightingFits(copy,surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        return copy
    }
    static func addingSpot(to lighting:LayoutLighting?, at point:LayoutPoint, surface:Surface2D, kind:LayoutElectricalKind = .light) throws -> LayoutLighting {
        var copy = lighting ?? .init()
        copy.kinds = copy.positions.indices.map { copy.kind(at:$0) } + [kind]
        copy.positions.append(point); copy.count = copy.positions.count
        guard lightingFits(copy,surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        return copy
    }
    static func addingWallRow(to lighting:LayoutLighting?, count:Int, height:Double, kind:LayoutElectricalKind, surface:Surface2D) throws -> LayoutLighting {
        guard surface.kind == .wall, (1...64).contains(count), height.isFinite, height > 0 else { throw LayoutLightingEditError.invalidPlacement }
        let y = surface.bounds.min.y + height
        let intervals = LayoutGeometry.edges(surface.contour).compactMap { edge -> Double? in
            let d = edge.b-edge.a
            guard abs(d.y) > 0.001 else { return nil }
            let t = (y-edge.a.y)/d.y
            return t >= 0 && t < 1 ? edge.a.x+t*d.x : nil
        }.sorted()
        guard let first = intervals.first, let last = intervals.last, last-first > 1 else { throw LayoutLightingEditError.invalidPlacement }
        var copy = lighting
        for i in 0..<count {
            let point = LayoutPoint(x:first+(last-first)*Double(i+1)/Double(count+1),y:y)
            copy = try addingSpot(to:copy,at:point,surface:surface,kind:kind)
        }
        return copy!
    }
    static func rotatedLighting(_ lighting:LayoutLighting, selected:Set<Int>, angle:Double) -> LayoutLighting {
        let indices = selected.filter { lighting.positions.indices.contains($0) }
        guard !indices.isEmpty else { return lighting }
        let center = indices.reduce(LayoutPoint.zero) { $0 + lighting.positions[$1] } * (1/Double(indices.count))
        var copy = lighting
        for i in indices {
            let d = lighting.positions[i]-center
            copy.positions[i] = center + .init(x:d.x*cos(angle)-d.y*sin(angle),y:d.x*sin(angle)+d.y*cos(angle))
        }
        return copy
    }
    static func scaledLighting(_ lighting:LayoutLighting, selected:Set<Int>, factor:Double) -> LayoutLighting {
        let indices = selected.filter { lighting.positions.indices.contains($0) }
        guard !indices.isEmpty, factor.isFinite, factor > 0 else { return lighting }
        let center = indices.reduce(LayoutPoint.zero) { $0+lighting.positions[$1] }*(1/Double(indices.count))
        var copy = lighting
        for i in indices { copy.positions[i] = center+(lighting.positions[i]-center)*factor }
        return copy
    }
    static func lightingDirection(_ lighting:LayoutLighting, selected:Set<Int>) -> Double? {
        let indices = selected.filter { lighting.positions.indices.contains($0) }.sorted()
        var nearest:LayoutPoint?
        for i in indices {
            for j in indices where j > i {
                let d = lighting.positions[j]-lighting.positions[i]
                if d.length > 1 && d.length < (nearest?.length ?? .infinity) { nearest = d }
            }
        }
        return nearest.map { atan2($0.y,$0.x) }
    }
    static func snappedLightingRotation(_ candidate:Double, lighting:LayoutLighting, selected:Set<Int>, contour:[LayoutPoint], latched:Double?) -> (angle:Double,latch:Double?) {
        if let latched, abs(candidate-latched) <= 5 * .pi/180 { return (latched,latched) }
        guard let direction = lightingDirection(lighting,selected:selected) else { return (candidate,nil) }
        let targets = LayoutGeometry.edges(contour).filter { ($0.b-$0.a).length > 1 }.map { edge in
            let d = edge.b-edge.a, wall = atan2(d.y,d.x)
            return ((candidate+direction-wall)/(.pi/2)).rounded()*(.pi/2)+wall-direction
        }
        if let target = targets.min(by:{abs($0-candidate)<abs($1-candidate)}), abs(target-candidate) <= 2.5 * .pi/180 { return (target,target) }
        return (candidate,nil)
    }
    static func lightingFits(_ settings: LayoutLighting, surface: Surface2D) -> Bool {
        guard (1...64).contains(settings.count), settings.positions.count == settings.count,
              settings.diameter.isFinite, (10...500).contains(settings.diameter),
              settings.positions.allSatisfy(\.finite) else { return false }
        for i in settings.positions.indices {
            for j in settings.positions.indices where j > i {
                if (settings.positions[i]-settings.positions[j]).length < settings.diameter+10-0.001 { return false }
            }
        }
        return settings.positions.allSatisfy { p in
            LayoutGeometry.contains(p,in:surface.contour)
            && !surface.openings.contains { LayoutGeometry.contains(p,in:$0.contour) }
            && ([surface.contour]+surface.openings.map(\.contour)).allSatisfy { loop in
                LayoutGeometry.edges(loop).allSatisfy { LayoutGeometry.distance(p,to:$0.a,$0.b) >= settings.diameter/2+10 }
            }
        }
    }

    static func translatedLighting(_ lighting:LayoutLighting, indices:Set<Int>, delta:LayoutPoint) -> LayoutLighting {
        var copy = lighting
        for i in indices where copy.positions.indices.contains(i) { copy.positions[i] = copy.positions[i] + delta }
        return copy
    }

    static func arrangedLighting(_ lighting:LayoutLighting, selected:Set<Int>, reference:Int?, action:LayoutSpotArrangement, surface:Surface2D) throws -> LayoutLighting {
        let indices = selected.filter { lighting.positions.indices.contains($0) }.sorted()
        guard indices.count >= action.minimumCount else { return lighting }
        let anchor = reference.flatMap { indices.contains($0) ? $0 : nil } ?? indices[0]
        var copy = lighting
        switch action {
        case .horizontal: for i in indices { copy.positions[i].y = lighting.positions[anchor].y }
        case .vertical: for i in indices { copy.positions[i].x = lighting.positions[anchor].x }
        case .distributeX, .distributeY:
            let x = action == .distributeX
            func coordinate(_ i:Int) -> Double { x ? lighting.positions[i].x : lighting.positions[i].y }
            let sorted = indices.sorted { coordinate($0) == coordinate($1) ? $0 < $1 : coordinate($0) < coordinate($1) }
            let first = coordinate(sorted[0]), last = coordinate(sorted[sorted.count-1])
            for (rank,i) in sorted.enumerated() {
                let value = first+(last-first)*Double(rank)/Double(sorted.count-1)
                if x { copy.positions[i].x = value } else { copy.positions[i].y = value }
            }
        }
        guard lightingFits(copy,surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        return copy
    }

    static func snappedLightingDelta(_ lighting:LayoutLighting, selected:Set<Int>, anchor:Int, delta:LayoutPoint, tolerance:Double) -> (delta:LayoutPoint, guides:[LayoutPoint]) {
        guard lighting.positions.indices.contains(anchor) else { return (delta,[]) }
        let proposed = lighting.positions[anchor]+delta
        let others = lighting.positions.indices.filter { !selected.contains($0) }
        var result = delta, guides:[LayoutPoint] = []
        if let i = others.min(by:{abs(lighting.positions[$0].x-proposed.x) < abs(lighting.positions[$1].x-proposed.x)}), abs(lighting.positions[i].x-proposed.x) <= tolerance {
            result.x += lighting.positions[i].x-proposed.x; guides.append(lighting.positions[i])
        }
        if let i = others.min(by:{abs(lighting.positions[$0].y-proposed.y) < abs(lighting.positions[$1].y-proposed.y)}), abs(lighting.positions[i].y-proposed.y) <= tolerance {
            result.y += lighting.positions[i].y-proposed.y; guides.append(lighting.positions[i])
        }
        return (result,guides)
    }
    static func localSurface(_ surface:Surface2D, frame:LayoutGridFrame) -> Surface2D {
        var copy = surface; copy.contour = copy.contour.map(frame.local)
        copy.openings = copy.openings.map { var o = $0; o.contour = o.contour.map(frame.local); return o }
        return copy
    }

    // Each corner is projected normally onto each wall segment. Retain visible
    // feet only: concave boundaries must not be crossed en route to a far wall.
    static func wallDimensions(points:[LayoutPoint], surface:Surface2D) -> [LayoutWallDimension] {
        let edges = LayoutGeometry.edges(surface.contour)
        var result: [LayoutWallDimension] = []
        for (j,p) in points.enumerated() {
            for (i,e) in edges.enumerated() {
                let d = e.b-e.a, squared = LayoutGeometry.dot(d,d)
                guard squared > 0 else { continue }
                let t = LayoutGeometry.dot(p-e.a,d)/squared
                guard t >= 0, t <= 1 else { continue }
                let foot = e.a+d*t
                guard (foot-p).length > 0.1 else { continue }
                let crossings = edges.flatMap { LayoutGeometry.splitParameters(.init(a:p,b:foot),by:$0) }
                guard !crossings.contains(where:{$0 > 0.00001 && $0 < 0.99999}),
                      LayoutGeometry.contains((p+foot)*0.5,in:surface.contour) else { continue }
                result.append(.init(id:"\(j)-\(i)",start:p,end:foot))
            }
        }
        return result
    }

    static func alongX(_ layer:LayoutLayer) -> Bool {
        layer.resolvedFurringOrientation == .horizontal
    }
    static func crossingDimension(_ layer:LayoutLayer) -> Double { alongX(layer) ? layer.cellHeight : layer.cellWidth }
    static func compatibleSpacings(_ layer:LayoutLayer) -> [Double] {
        [400.0,500.0,600.0].filter { spacing in
            let count = crossingDimension(layer)/spacing
            return count >= 1 && abs(count-count.rounded()) < 0.00001
        }
    }
    static func alignFurring(to layer:LayoutLayer) -> LayoutLayer {
        var copy = layer
        if var f = copy.furring { f.offset = alongX(copy) ? copy.offset.y : copy.offset.x; copy.furring = f }
        return copy
    }
    static func alignBoards(to layer:LayoutLayer, support:LayoutSupportKind) -> LayoutLayer {
        var copy = layer
        if let f = layer.furring {
            let current = alongX(layer) ? layer.offset.y : layer.offset.x
            let target: Double
            if support == .ceiling {
                // Offsets live in the reference edge's local grid coordinates.
                // Compatible board dimensions are multiples of spacing, so all
                // parallel joints share this phase. Preserve the chosen grid
                // period and move by at most half one furring spacing.
                guard current.isFinite, f.offset.isFinite, f.spacing.isFinite,
                      compatibleSpacings(layer).contains(f.spacing) else { return layer }
                let delta = (f.offset - current).remainder(dividingBy: f.spacing)
                guard abs(delta) > 0.000001 else { return layer }
                target = current + delta
            } else {
                // Wall alignment retains its existing behavior.
                target = f.offset
            }
            if alongX(layer) { copy.offset.y = target } else { copy.offset.x = target }
        }
        return copy
    }
    static func aligned(_ layer:LayoutLayer) -> Bool {
        guard let f = layer.furring, compatibleSpacings(layer).contains(f.spacing) else { return layer.furring == nil }
        let delta = (alongX(layer) ? layer.offset.y : layer.offset.x)-f.offset
        return abs(delta/f.spacing-(delta/f.spacing).rounded()) < 0.00001
    }

    static func lighting(_ settings:LayoutLighting, surface:Surface2D) throws -> LayoutLighting {
        guard (1...64).contains(settings.count), (0.2...1.2).contains(settings.spread),
              settings.diameter.isFinite, (10...500).contains(settings.diameter) else { throw LayoutGeometryError.invalidFormat }
        let b = surface.bounds, radius = settings.diameter/2
        func valid(_ p:LayoutPoint) -> Bool {
            LayoutGeometry.contains(p,in:surface.contour) && !surface.openings.contains { LayoutGeometry.contains(p,in:$0.contour) }
            && ([surface.contour]+surface.openings.map(\.contour)).allSatisfy { loop in
                LayoutGeometry.edges(loop).allSatisfy { LayoutGeometry.distance(p,to:$0.a,$0.b) >= radius+10 }
            }
        }
        var best: [LayoutPoint] = [], bestScore = Double.infinity
        for rows in 1...settings.count {
            let cols = Int(ceil(Double(settings.count)/Double(rows)))
            let dx = b.width/Double(cols)*settings.spread, dy = b.height/Double(rows)*settings.spread
            guard min(dx,dy) > settings.diameter+10 else { continue }
            var points: [LayoutPoint] = []
            for row in 0..<rows {
                let n = settings.count/rows+(row < settings.count%rows ? 1 : 0)
                for col in 0..<n {
                    points.append(b.center + .init(x:(Double(col)-Double(n-1)/2)*dx,y:(Double(row)-Double(rows-1)/2)*dy))
                }
            }
            let score = abs(log(max(0.001,dx/dy)))
            if points.allSatisfy(valid), score < bestScore { best = points; bestScore = score }
        }
        if best.isEmpty {
            // Deterministic farthest-point fallback for concave rooms. Never drop
            // spots silently or put holes outside the ceiling / inside a hatch.
            var candidates: [LayoutPoint] = []
            for y in 0..<25 { for x in 0..<25 {
                let p = b.center + .init(x:(Double(x)/24-0.5)*b.width*settings.spread,
                                        y:(Double(y)/24-0.5)*b.height*settings.spread)
                if valid(p) { candidates.append(p) }
            } }
            if let first = candidates.min(by:{($0-b.center).length < ($1-b.center).length}) { best = [first] }
            while best.count < settings.count {
                guard let p = candidates.max(by:{ a,z in
                    (best.map{($0-a).length}.min() ?? 0) < (best.map{($0-z).length}.min() ?? 0)
                }), best.allSatisfy({($0-p).length > settings.diameter+10}) else { throw LayoutGeometryError.invalidContour }
                best.append(p)
            }
        }
        var copy = settings; copy.positions = best; return copy
    }

    // Bounded deterministic offset search, not an assertion of global optimality.
    // Once aligned, moving either grid keeps the shared joint phase aligned.
    static func optimize(surface:Surface2D, layer:LayoutLayer, furring:Bool) throws -> LayoutLayer {
        let layer = layer.forSurface(surface)
        var best = layer
        let initial = try SheetLayoutEngine.calculate(surface:surface,layer:layer)
        func score(_ result:SheetLayoutResult) -> (Double,Double) {
            if furring { return (result.furring.lines.reduce(0){$0+($1.end-$1.start).length},Double(result.furring.lines.count)) }
            return (Double(result.sheets.count),result.wasteArea)
        }
        var bestScore = score(initial)
        let b = localSurface(surface,frame:.make(surface:surface,layer:layer)).bounds
        // Include exact wall-aligned starts in addition to uniform samples.
        let xs = [layer.offset.x,b.min.x,b.max.x] + (0..<9).map{Double($0)*layer.cellWidth/9}
        let ys = [layer.offset.y,b.min.y,b.max.y] + (0..<9).map{Double($0)*layer.cellHeight/9}
        for x in xs { for y in ys {
            try Task.checkCancellation()
            var candidate = layer; candidate.offset = .init(x:x,y:y)
            if layer.furring != nil { candidate = alignFurring(to:candidate) }
            guard let result = try? SheetLayoutEngine.calculate(surface:surface,layer:candidate) else { continue }
            let value = score(result)
            if value.0+0.01 < bestScore.0 || (abs(value.0-bestScore.0) < 0.01 && value.1+0.01 < bestScore.1) { best = candidate; bestScore = value }
        } }
        return best
    }
}

extension Surface2D {
    func changingVertex(remove index:Int? = nil, insertAfter edge:Int? = nil, point:LayoutPoint? = nil) throws -> Surface2D {
        let old = editableIntent
        var indices = Array(contour.indices).map{Optional($0)}
        var points = contour
        if let index {
            guard points.count > 3, points.indices.contains(index) else { throw LayoutGeometryError.invalidContour }
            points.remove(at:index); indices.remove(at:index)
        } else if let edge, let point {
            guard points.count < 200, points.indices.contains(edge) else { throw LayoutGeometryError.invalidContour }
            points.insert(point,at:edge+1); indices.insert(nil,at:edge+1)
        }
        try LayoutGeometry.validate(points)
        var copy = self, intent = LayoutContourIntent(sketch:points)
        let oldIDs = stableEdgeIDs
        copy.edgeIDs = indices.indices.map { i in
            if let source = indices[i], indices[(i+1)%indices.count] == (source+1)%contour.count { return oldIDs[source] }
            return UUID().uuidString
        }
        copy.layingOffset.individualMM = layingOffset.individualMM.filter { copy.edgeIDs.contains($0.key) }
        copy.topologyID = UUID()
        var locks: [Int] = []
        for i in points.indices {
            guard let source = indices[i] else { continue }
            let next = indices[(i+1)%points.count], prev = indices[(i+points.count-1)%points.count]
            intent.userVertexPositions[i] = old.userVertexPositions[source]
            if next == (source+1)%contour.count {
                intent.userMeasuredLengths[i] = old.userMeasuredLengths[source]
                if old.lockedLengthIndices?.contains(source) == true { locks.append(i) }
            }
            if next == (source+1)%contour.count && prev == (source+contour.count-1)%contour.count {
                intent.userAnglesDegrees[i] = old.userAnglesDegrees[source]
            }
        }
        intent.lockedLengthIndices = locks
        copy.previousContourIntents.append(old)
        copy.edgeTones = indices.map { i in i.flatMap { edgeTones.indices.contains($0) ? edgeTones[$0] : nil } ?? .teal }
        try copy.resolve(intent)
        _ = try copy.layingContour()
        return copy
    }
}
