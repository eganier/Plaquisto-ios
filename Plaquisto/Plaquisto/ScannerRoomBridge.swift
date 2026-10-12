import Foundation
import simd

/// User review of ceiling hypotheses. No ARSession ownership or coordinate changes.
struct ScannerCeilingReview {
    struct Choice {
        var room: PlaquistoRoomModel
        var vertices: [SIMD3<Double>] {
            room.slopes.flatMap { slope in
                guard slope.boundaries.count == 1, let ring = slope.boundaries.first else { return [SIMD3<Double>]() }
                var polygon = ring.map { SIMD2($0.x,$0.z) }
                if ScannerCeilingReconstruction.triangulate(polygon) == nil { polygon.reverse() }
                guard let indices = ScannerCeilingReconstruction.triangulate(polygon) else { return [] }
                return indices.map { i in SIMD3(polygon[i].x,slope.plane.height(x:polygon[i].x,z:polygon[i].y),polygon[i].y) }
            }
        }
        var area: Double { room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) } }
        var estimated: Bool { room.slopes.contains { $0.provenance.source == .estimated } }
    }
    private(set) var pending: Choice?
    private(set) var confirmed: [Choice] = []
    private var rejected: [Choice] = []

    mutating func propose(_ choice: Choice) -> Bool {
        guard pending == nil, !choice.estimated, !choice.vertices.isEmpty,
              choice.room.slopes.allSatisfy({ $0.provenance.source == .lidar }),
              !confirmed.contains(where: { Self.overlaps($0,choice) }),
              !rejected.contains(where: { Self.overlaps($0,choice) && abs($0.area-choice.area) < max(0.1,choice.area*0.02) }) else { return false }
        pending = choice; return true
    }
    mutating func accept() {
        guard var choice = pending else { return }
        for i in choice.room.slopes.indices {
            choice.room.slopes[i].accepted = true
            choice.room.slopes[i].manuallyValidated = true
        }
        confirmed.append(choice); pending = nil
    }
    mutating func reject() { if let pending { rejected.append(pending) }; pending = nil }
    mutating func retryLast() { pending = nil; _ = confirmed.popLast(); rejected = [] }

    /// Keep final estimates in other spaces, but never overlay a new hypothesis on
    /// a user-confirmed ceiling. Rejected hypotheses must not silently reappear.
    func applying(to input: PlaquistoRoomModel) -> PlaquistoRoomModel {
        var room = input
        let excluded = confirmed+rejected+(pending.map { [$0] } ?? [])
        let remove = room.ceilings.filter { ceiling in
            var part = room; part.slopes = room.slopes.filter { ceiling.slopeIDs.contains($0.id) }
            part.ceilings = [ceiling]
            return excluded.contains { Self.overlaps($0,Choice(room:part)) }
        }
        let ids = Set(remove.flatMap(\.slopeIDs))
        room.ceilings.removeAll { ceiling in remove.contains { $0.id == ceiling.id } }
        room.slopes.removeAll { ids.contains($0.id) }
        for choice in confirmed { room.ceilings += choice.room.ceilings; room.slopes += choice.room.slopes }
        return room
    }

    /// Positive projected intersection area (not merely a shared wall).
    static func overlaps(_ a: Choice, _ b: Choice) -> Bool {
        let av = a.vertices, bv = b.vertices
        func cross(_ p: SIMD2<Double>, _ q: SIMD2<Double>) -> Double { p.x*q.y-p.y*q.x }
        for i in stride(from:0,to:av.count,by:3) {
            for j in stride(from:0,to:bv.count,by:3) {
                var polygon = (0..<3).map { SIMD2(av[i+$0].x,av[i+$0].z) }
                var clip = (0..<3).map { SIMD2(bv[j+$0].x,bv[j+$0].z) }
                if cross(clip[1]-clip[0],clip[2]-clip[0]) < 0 { clip.reverse() }
                for k in 0..<3 {
                    let start = clip[k], edge = clip[(k+1)%3]-start
                    var output: [SIMD2<Double>] = []
                    for index in polygon.indices {
                        let p = polygon[index], q = polygon[(index+1)%polygon.count]
                        let dp = cross(edge,p-start), dq = cross(edge,q-start)
                        if dp >= 0 { output.append(p) }
                        if (dp >= 0) != (dq >= 0) { output.append(p+(q-p)*(dp/(dp-dq))) }
                    }
                    polygon = output
                }
                let area = abs(polygon.indices.reduce(0.0) { $0+cross(polygon[$1],polygon[($1+1)%polygon.count]) })/2
                if area > 0.001 { return true }
            }
        }
        return false
    }
}

/// Post-capture topology only. Does not change ARKit, wall positions or projects.
/// Bounded faces of the observed wall graph are candidate spaces, not semantic rooms.
enum ScanEnclosedSpaces {
    static func wallsBySpace(in room: PlaquistoRoomModel) -> [[PlaquistoWall]] {
        var walls = room.walls.filter { $0.start.finite && $0.effectiveEnd.finite && $0.length.effectiveValue > 0.05 }
        let observed = walls
        // A RoomPlan floor polygon is an observed footprint, not a bounding box.
        // It may supply a missing boundary edge, but never alters the saved walls.
        for floor in room.floors where floor.boundaries.count == 1 {
            guard let ring = floor.boundaries.first, ring.count >= 3 else { continue }
            let outline = ring.map { SIMD2($0.x,$0.z) }
            guard ScannerCeilingReconstruction.triangulate(outline) != nil ||
                ScannerCeilingReconstruction.triangulate(Array(outline.reversed())) != nil else { continue }
            let level = floor.referenceElevation ?? ring[0].y
            let nearby = observed.filter { abs($0.start.y-level) < 0.2 }
            guard nearby.count >= 3 else { continue }
            let heights = nearby.map { $0.height.effectiveValue }.sorted()
            let height = heights[heights.count/2]
            for i in ring.indices {
                let a = RoomPoint(x:ring[i].x,y:level,z:ring[i].z), q = ring[(i+1)%ring.count]
                let b = RoomPoint(x:q.x,y:level,z:q.z)
                let source = GeometryProvenance(source:.estimated)
                walls.append(.init(start:a,end:b,length:.init(rawValue:(b-a).length,provenance:source),
                    height:.init(rawValue:height,provenance:source),provenance:source))
            }
        }
        guard walls.count >= 3, walls.count <= 250 else { return [] }
        let tolerance = 0.08 // Maximum endpoint reconciliation, metres; never closes a doorway.
        func p(_ point: RoomPoint) -> SIMD2<Double> { .init(point.x, point.z) }
        func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x*b.y-a.y*b.x }
        var cuts = walls.map { _ in [0.0, 1.0] }
        for i in walls.indices {
            let a = p(walls[i].start), u = p(walls[i].effectiveEnd)-a
            for j in walls.indices where j > i && abs(walls[i].start.y-walls[j].start.y) < 0.2 {
                let b = p(walls[j].start), v = p(walls[j].effectiveEnd)-b
                let denominator = cross(u,v)
                if abs(denominator) > 1e-8 {
                    let t = cross(b-a,v)/denominator, s = cross(b-a,u)/denominator
                    if t >= 0 && t <= 1 && s >= 0 && s <= 1 { cuts[i].append(t); cuts[j].append(s) }
                }
                // Split long walls at T-junctions and overlapping segment ends.
                for (index, point, origin, axis) in [(i,b,a,u),(i,b+v,a,u),(j,a,b,v),(j,a+u,b,v)] {
                    let t = simd_dot(point-origin,axis)/simd_length_squared(axis)
                    if t > 0 && t < 1 && simd_distance(origin+t*axis,point) <= tolerance { cuts[index].append(t) }
                }
            }
        }
        struct Edge { let a: Int; let b: Int; let wall: PlaquistoWall }
        var nodes: [RoomPoint] = [], edges: [Edge] = [], keys = Set<String>()
        func node(_ point: RoomPoint) -> Int {
            if let i = nodes.indices.min(by: { (nodes[$0]-point).length < (nodes[$1]-point).length }),
               (nodes[i]-point).length <= tolerance { return i }
            nodes.append(point); return nodes.count-1
        }
        for i in walls.indices {
            let ts = Array(Set(cuts[i])).sorted(), wall = walls[i]
            for k in 1..<ts.count where (ts[k]-ts[k-1])*wall.length.effectiveValue > 0.02 {
                let a = node(wall.start + wall.direction*(ts[k-1]*wall.length.effectiveValue))
                let b = node(wall.start + wall.direction*(ts[k]*wall.length.effectiveValue))
                guard a != b, keys.insert("\(min(a,b))/\(max(a,b))").inserted else { continue }
                edges.append(.init(a: a, b: b, wall: wall))
            }
        }
        guard edges.count <= 2000 else { return [] }
        var neighbors = Array(repeating: [(node: Int, edge: Int)](), count: nodes.count)
        for (i,e) in edges.enumerated() { neighbors[e.a].append((e.b,i)); neighbors[e.b].append((e.a,i)) }
        // Remove graph bridges: a partial partition must not invalidate a closed room.
        var clock = 0, entered = Array(repeating: -1, count: nodes.count), low = entered, bridges = Set<Int>()
        func visit(_ n: Int, parent: Int) {
            entered[n] = clock; low[n] = clock; clock += 1
            for next in neighbors[n] where next.edge != parent {
                if entered[next.node] < 0 {
                    visit(next.node, parent: next.edge); low[n] = min(low[n],low[next.node])
                    if low[next.node] > entered[n] { bridges.insert(next.edge) }
                } else { low[n] = min(low[n],entered[next.node]) }
            }
        }
        for n in nodes.indices where entered[n] < 0 { visit(n,parent: -1) }
        for n in nodes.indices {
            neighbors[n] = neighbors[n].filter { !bridges.contains($0.edge) }.sorted {
                let a = nodes[$0.node]-nodes[n], b = nodes[$1.node]-nodes[n]
                return atan2(a.z,a.x) < atan2(b.z,b.x)
            }
        }
        var visited = Set<String>(), rings: [[Int]] = [], sources: [[Int]] = []
        for start in nodes.indices {
            for next in neighbors[start] {
                var a = start, b = next.node, ring: [Int] = [], source: [Int] = [], closed = false
                for _ in 0...edges.count*2 {
                    guard visited.insert("\(a)/\(b)").inserted,
                          let incoming = neighbors[b].firstIndex(where: { $0.node == a }),
                          let edge = neighbors[a].first(where: { $0.node == b })?.edge else { break }
                    ring.append(a); source.append(edge)
                    let c = neighbors[b][(incoming+neighbors[b].count-1)%neighbors[b].count].node
                    a = b; b = c
                    if a == start && b == next.node { closed = true; break }
                }
                guard closed, ring.count >= 3, Set(ring).count == ring.count else { continue }
                let area = ring.indices.reduce(0.0) { $0 + cross(p(nodes[ring[$1]]),p(nodes[ring[($1+1)%ring.count]])) }/2
                guard area >= 0.5 else { continue } // Reject exterior face and tiny slivers.
                rings.append(ring); sources.append(source)
            }
        }
        return rings.indices.compactMap { index in
            let ring = rings[index].map { nodes[$0] }
            // Nested boundaries / floor voids need explicit review, never a filled courtyard.
            let nested = rings.indices.contains { other in
                other != index && rings[other].allSatisfy { vertex in
                    !rings[index].contains(vertex) && PlaquistoWallGeometry.contains(nodes[vertex], polygon: ring)
                }
            }
            let voidInside = room.floors.contains { floor in
                abs((floor.referenceElevation ?? ring[0].y)-ring[0].y) < 0.2 && floor.boundaries.dropFirst().contains { hole in
                    hole.contains { PlaquistoWallGeometry.contains($0, polygon: ring) }
                }
            }
            guard !nested, !voidInside else { return nil }
            return ring.indices.map { i in
                var wall = edges[sources[index][i]].wall
                wall.start = ring[i]; wall.end = ring[(i+1)%ring.count]
                wall.length = .init(rawValue: hypot(wall.end.x-wall.start.x,wall.end.z-wall.start.z), provenance: wall.provenance)
                return wall
            }
        }
    }
}

/// Fallback from observed wall lines, not a LiDAR ceiling observation.
/// Domain output is portable; the existing contour solver supplies only X/Z.
enum CeilingZoneEditing {
    enum Failure: Error, LocalizedError {
        case notAdjacent
        var errorDescription: String? { "Ces plafonds doivent partager un bord et former une seule zone fermée, sans chevauchement ni trou. Aucun plafond n’a été modifié." }
    }

    /// Join boundary segments, not a convex hull: preserve recesses and never fill a void.
    /// Split shared edges at every vertex first (a neighbour may have extra vertices).
    static func joinedBoundary(_ a: [RoomPoint], _ b: [RoomPoint]) -> [RoomPoint]? {
        let tolerance = 0.00001
        func normalized(_ ring: [RoomPoint]) -> [RoomPoint] {
            let flat = ring.map { RoomPoint(x:$0.x,y:0,z:$0.z) }
            return SurveyPlanFinishes.area(flat) < 0 ? Array(flat.reversed()) : flat
        }
        let rings = [normalized(a), normalized(b)]
        guard rings.allSatisfy({ $0.count >= 3 && $0.allSatisfy(\.finite) }) else { return nil }
        let vertices = rings.flatMap { $0 }
        var nodes: [RoomPoint] = []
        func index(_ point: RoomPoint) -> Int {
            if let i = nodes.firstIndex(where: { ($0-point).horizontalLength < tolerance }) { return i }
            nodes.append(point); return nodes.count-1
        }
        struct Edge: Hashable { let start: Int; let end: Int }
        var edges = Set<Edge>(), sharedLength = 0.0
        for ring in rings {
            for i in ring.indices {
                let p=ring[i], q=ring[(i+1)%ring.count], d=q-p
                let length=d.horizontalLength
                guard length > tolerance else { continue }
                let breaks=([0.0,1.0]+vertices.compactMap { v -> Double? in
                    let t=((v.x-p.x)*d.x+(v.z-p.z)*d.z)/(length*length)
                    return t > 0 && t < 1 && (v-(p+d*t)).horizontalLength < tolerance ? t : nil
                }).sorted()
                for j in 1..<breaks.count where (breaks[j]-breaks[j-1])*length > tolerance {
                    let start=index(p+d*breaks[j-1]), end=index(p+d*breaks[j])
                    let edge=Edge(start:start,end:end), reverse=Edge(start:end,end:start)
                    if edges.remove(reverse) != nil { sharedLength += (nodes[end]-nodes[start]).horizontalLength }
                    else if !edges.insert(edge).inserted { return nil }
                }
            }
        }
        guard sharedLength > 0.01, let first=edges.first else { return nil }
        var outline:[RoomPoint]=[], current=first.start
        repeat {
            let next=edges.filter { $0.start == current }
            guard next.count == 1, let edge=next.first else { return nil }
            outline.append(nodes[current]); edges.remove(edge); current=edge.end
        } while current != first.start
        guard edges.isEmpty, outline.count >= 3 else { return nil }
        let expected=rings.reduce(0) { $0+abs(SurveyPlanFinishes.area($1)) }
        guard abs(abs(SurveyPlanFinishes.area(outline))-expected) < max(1e-6,expected*1e-6),
              ScannerCeilingReconstruction.triangulate(outline.map { SIMD2($0.x,$0.z) }) != nil ||
              ScannerCeilingReconstruction.triangulate(outline.reversed().map { SIMD2($0.x,$0.z) }) != nil else { return nil }
        return outline
    }

    static func merge(_ document: PlaquistoRoomDocument, first: UUID, second: UUID) throws -> PlaquistoRoomDocument {
        guard first != second,
              let a=document.room.ceilings.first(where: { $0.id == first }),
              let b=document.room.ceilings.first(where: { $0.id == second }),
              let pa=WallCeilingEstimate.footprint(of:a,in:document.room),
              let pb=WallCeilingEstimate.footprint(of:b,in:document.room),
              let outline=joinedBoundary(pa,pb), Set(a.slopeIDs).isDisjoint(with:b.slopeIDs) else { throw Failure.notAdjacent }
        var result=document
        var merged=a
        merged.footprint=outline
        merged.slopeIDs += b.slopeIDs
        // All actual planes, source IDs, openings and split ancestry remain byte-for-byte intact.
        merged.isHidden = a.isHidden == true && b.isHidden == true
        if a.estimateSettings != b.estimateSettings { merged.estimateSettings=nil }
        result.room.ceilings=result.room.ceilings.compactMap { ceiling in
            ceiling.id == second ? nil : ceiling.id == first ? merged : ceiling
        }
        try result.validate()
        return result
    }

    static func togglingVisibility(_ document: PlaquistoRoomDocument, ceilingID: UUID) -> PlaquistoRoomDocument {
        var result=document
        if let i=result.room.ceilings.firstIndex(where: { $0.id == ceilingID }) {
            result.room.ceilings[i].isHidden = result.room.ceilings[i].isHidden != true
        }
        return result
    }
}

enum WallCeilingEstimate {
    enum Failure: Error, LocalizedError {
        case existingCeiling, openContour, differentLevels, invalidHeight, invalidSplit
        var errorDescription: String? {
            switch self {
            case .invalidSplit: "La limite doit traverser le plafond et former deux zones fermées. Choisissez deux points plus éloignés ; aucun plafond n’a été modifié."
            case .existingCeiling: "Un plafond ou une proposition existe déjà. Contrôlez-le avant de créer un autre plafond."
            case .openContour: "Les limites ou les hauteurs du relevé ne permettent pas d’estimer ce plafond de façon fiable. Complétez ou corrigez le plan ; aucun rectangle de remplacement n’a été inventé."
            case .differentLevels: "Les pieds des murs sont à des niveaux différents. Ce secours est limité à une pièce sur un même niveau."
            case .invalidHeight: "Renseignez une hauteur sous plafond positive et finie, en mètres."
            }
        }
    }
    struct Proposal: Identifiable {
        let id = UUID()
        var ceilingID: UUID? = nil
        var boundary: [RoomPoint]
        let floorElevation: Double
        let suggestedHeight: Double
        let wallTopSpread: Double
        let maximumCornerAdjustment: Double
        let suggestedSettings: CeilingEstimateSettings
    }

    static func propose(in room: PlaquistoRoomModel) throws -> Proposal {
        var value = try propose(in: room, orderedSpace: false)
        value.ceilingID = room.ceilings.first { sameFootprint(value.boundary, footprint(of:$0,in:room) ?? []) }?.id
        return value
    }

    /// Graph faces already have ordered, joined edges. Do not ask the legacy
    /// unordered-wall solver to rediscover their neighbours: small recesses can
    /// otherwise look like several possible junctions within its 20 cm tolerance.
    private static func orderedContour(_ walls: [ScannerCeilingReconstruction.Wall]) -> [SIMD2<Double>]? {
        guard walls.count >= 3, walls.indices.allSatisfy({
            simd_distance(walls[$0].end, walls[($0 + 1) % walls.count].start) < 1e-6
                && simd_distance(walls[$0].start, walls[$0].end) > 1e-6
        }) else { return nil }
        var polygon = walls.map(\.start)
        func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x*b.y-a.y*b.x }
        // Reject crossing/touching non-neighbouring edges, without moving points.
        for i in polygon.indices {
            for j in polygon.indices where j > i+1 && !(i == 0 && j == polygon.count-1) {
                let a = polygon[i], b = polygon[(i+1)%polygon.count]
                let c = polygon[j], d = polygon[(j+1)%polygon.count]
                let overlap = max(min(a.x,b.x),min(c.x,d.x)) <= min(max(a.x,b.x),max(c.x,d.x))+1e-9
                    && max(min(a.y,b.y),min(c.y,d.y)) <= min(max(a.y,b.y),max(c.y,d.y))+1e-9
                if overlap && cross(b-a,c-a)*cross(b-a,d-a) <= 0
                    && cross(d-c,a-c)*cross(d-c,b-c) <= 0 { return nil }
            }
        }
        let area = polygon.indices.reduce(0.0) { $0+cross(polygon[$1],polygon[($1+1)%polygon.count]) }/2
        guard abs(area) >= 0.1 else { return nil }
        if area < 0 { polygon.reverse() }
        guard ScannerCeilingReconstruction.triangulate(polygon) != nil else { return nil }
        return polygon
    }

    private static func propose(in room: PlaquistoRoomModel, orderedSpace: Bool) throws -> Proposal {
        guard room.walls.count >= 3, room.walls.count <= 100,
              room.walls.allSatisfy({ $0.start.finite && $0.effectiveEnd.finite &&
                  $0.height.effectiveValue.isFinite && $0.height.effectiveValue > 0 }) else { throw Failure.openContour }
        let bases = room.walls.map { $0.start.y }.sorted()
        guard bases.last! - bases.first! <= 0.20 else { throw Failure.differentLevels }
        let walls = room.walls.map { ScannerCeilingReconstruction.Wall(
            start: .init($0.start.x, $0.start.z), end: .init($0.effectiveEnd.x, $0.effectiveEnd.z)) }
        guard let contour = orderedSpace ? orderedContour(walls) : ScannerCeilingReconstruction.closedContour(walls)
        else { throw Failure.openContour }
        let tops = room.walls.map { $0.start.y + $0.height.effectiveValue }.sorted()
        func median(_ values: [Double]) -> Double {
            (values[(values.count - 1) / 2] + values[values.count / 2]) / 2
        }
        let floor = median(bases)
        // Disclose endpoint extension/snap already bounded by the shared solver.
        let adjustment = contour.map { corner in
            walls.flatMap { [$0.start, $0.end] }.map { simd_distance(corner, $0) }.min() ?? 0
        }.max() ?? 0
        var settings = CeilingEstimateSettings(lowHeight: median(tops) - floor, highHeight: median(tops) - floor + 0.5)
        if let wall = room.walls.max(by: { $0.length.effectiveValue < $1.length.effectiveValue }) {
            settings.azimuth = atan2(wall.direction.x, -wall.direction.z)
        }
        // Two observed, parallel, opposite walls define a slope. A single high
        // wall (or noisy adjacent corners) is insufficient to invent a ramp.
        var bestSeparation = 0.0
        for i in room.walls.indices {
            for j in room.walls.indices where j > i {
                let a = room.walls[i], b = room.walls[j]
                let directionA = SIMD2(a.direction.x, a.direction.z)
                let directionB = SIMD2(b.direction.x, b.direction.z)
                guard abs(simd_dot(directionA, directionB)) > cos(5 * .pi / 180) else { continue }
                let midA = (walls[i].start + walls[i].end) / 2
                let midB = (walls[j].start + walls[j].end) / 2
                var normal = SIMD2(-directionA.y, directionA.x)
                if simd_dot(midB - midA, normal) < 0 { normal = -normal }
                let separation = simd_dot(midB - midA, normal)
                let topA = a.start.y + a.height.effectiveValue
                let topB = b.start.y + b.height.effectiveValue
                guard separation > max(0.5, bestSeparation), abs(topB - topA) > 0.10 else { continue }
                if topB < topA { normal = -normal }
                let positions = contour.map { simd_dot($0, normal) }
                let gradient = abs(topB - topA) / separation
                let origin = topB >= topA ? midA : midB
                let low = min(topA, topB) + gradient * (positions.min()! - simd_dot(origin, normal)) - floor
                let high = low + gradient * (positions.max()! - positions.min()!)
                guard low > 0, high <= 1000 else { continue }
                settings = .init(shape: .singleSlope, lowHeight: low, highHeight: high,
                                 azimuth: atan2(normal.y, normal.x))
                bestSeparation = separation
            }
        }
        return .init(boundary: contour.map { .init(x: $0.x, y: floor, z: $0.y) },
            floorElevation: floor, suggestedHeight: median(tops) - floor,
            wallTopSpread: tops.last! - tops.first!, maximumCornerAdjustment: adjustment,
            suggestedSettings: settings)
    }

    /// Only used when no ceiling was observed. Existing geometry is never overwritten automatically.
    static func addingIfMissing(to document: PlaquistoRoomDocument) throws -> PlaquistoRoomDocument {
        guard document.room.slopes.isEmpty, document.room.ceilings.isEmpty else { return document }
        let candidates = try proposals(in: document.room)
        var result = document
        for proposal in candidates {
            // Work in isolation, then append. No ceiling may replace a neighbouring space.
            var part = document; part.room.slopes = []; part.room.ceilings = []
            let generated = try applying(to: part, proposal: proposal, settings: proposal.suggestedSettings, manuallyEdited: false)
            result.room.slopes += generated.room.slopes
            var ceilings = generated.room.ceilings
            for i in ceilings.indices { ceilings[i].planNumber = result.room.ceilings.count+i+1 }
            result.room.ceilings += ceilings
        }
        try result.validate()
        return result
    }

    static func proposals(in room: PlaquistoRoomModel) throws -> [Proposal] {
        let spaces = ScanEnclosedSpaces.wallsBySpace(in: room)
        let values = spaces.compactMap { walls -> Proposal? in
            var local = room; local.walls = walls
            // Short lowered returns/lintels are not a roof slope when the long
            // surrounding walls agree. Only the estimation copy is adjusted.
            let top = walls.map { $0.start.y+$0.height.effectiveValue }.sorted()
            let typical = top[top.count/2]
            let support = walls.filter { abs($0.start.y+$0.height.effectiveValue-typical) < 0.10 }
                .reduce(0) { $0+$1.length.effectiveValue }
            if support >= walls.reduce(0, { $0+$1.length.effectiveValue })*0.8 {
                for i in local.walls.indices where local.walls[i].length.effectiveValue < 0.8 &&
                    typical-local.walls[i].start.y-local.walls[i].height.effectiveValue > 0.15 {
                    local.walls[i].height = .init(rawValue:typical-local.walls[i].start.y,provenance:.init(source:.estimated))
                }
            }
            guard var proposal = try? propose(in: local, orderedSpace: true) else { return nil }
            let settings = proposal.suggestedSettings
            if settings.shape == .flat, proposal.wallTopSpread > 0.20 { return nil }
            if settings.shape == .singleSlope {
                let axis = SIMD2(cos(settings.azimuth),sin(settings.azimuth))
                let positions = proposal.boundary.map { simd_dot(SIMD2($0.x,$0.z),axis) }
                let low = positions.min()!, high = positions.max()!
                guard local.walls.allSatisfy({ wall in
                    let middle = (wall.start+wall.effectiveEnd)*0.5
                    let t = (simd_dot(SIMD2(middle.x,middle.z),axis)-low)/(high-low)
                    let predicted = proposal.floorElevation+settings.lowHeight+t*(settings.highHeight-settings.lowHeight)
                    return abs(predicted-wall.start.y-wall.height.effectiveValue) <= 0.15
                }) else { return nil }
            }
            proposal.ceilingID = room.ceilings.first { ceiling in
                room.slopes.filter { ceiling.slopeIDs.contains($0.id) }.contains { slope in
                    guard let boundary = slope.boundaries.first else { return false }
                    let outline = boundary.map { SIMD2($0.x,$0.z) }
                    let polygon = ScannerCeilingReconstruction.triangulate(outline) != nil ? outline : Array(outline.reversed())
                    guard let indices = ScannerCeilingReconstruction.triangulate(polygon), indices.count >= 3 else { return false }
                    let p = (polygon[indices[0]]+polygon[indices[1]]+polygon[indices[2]])/3
                    let center = RoomPoint(x:p.x,y:proposal.floorElevation,z:p.y)
                    return PlaquistoWallGeometry.contains(center, polygon: proposal.boundary)
                }
            }?.id
            return proposal
        }
        if !values.isEmpty { return values }
        guard spaces.isEmpty, !room.floors.contains(where: { $0.boundaries.count > 1 }) else { throw Failure.openContour }
        // Retain the existing conservative single-room corner solver for small scan gaps.
        return [try propose(in: room)]
    }

    /// Recover editable closed footprints independently of the roof shape.
    /// Heights here are only defaults; the fitter uses the original wall contours.
    static func manualProposals(in room: PlaquistoRoomModel) throws -> [Proposal] {
        var support = room
        let heights = room.walls.map { $0.height.effectiveValue }.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !heights.isEmpty else { throw Failure.invalidHeight }
        let height = heights[heights.count/2]
        for i in support.walls.indices {
            support.walls[i].height = .init(rawValue:height,provenance:.init(source:.estimated))
        }
        let existing = room.ceilings.compactMap { ceiling -> Proposal? in
            guard ceiling.provenance.source == .estimated, let boundary = footprint(of:ceiling,in:room) else { return nil }
            let settings = ceiling.estimateSettings ?? .init(lowHeight:height,highHeight:height)
            let vertices=room.slopes.filter { ceiling.slopeIDs.contains($0.id) }.flatMap { $0.boundaries.flatMap { $0 } }
            let base = ceiling.floorElevation ?? ((vertices.map(\.y).min() ?? settings.lowHeight)-settings.lowHeight)
            return .init(ceilingID:ceiling.id,boundary:boundary,floorElevation:base,suggestedHeight:settings.lowHeight,
                         wallTopSpread:0,maximumCornerAdjustment:0,suggestedSettings:settings)
        }
        let zones = (try? proposals(in:support)) ?? []
        let vacant = zones.filter { zone in
            !room.ceilings.contains { ceiling in
                guard let outline=footprint(of:ceiling,in:room) else { return true }
                return overlaps(zone.boundary,outline)
            }
        }.map { zone -> Proposal in var copy=zone; copy.ceilingID=nil; return copy }
        guard !existing.isEmpty || !vacant.isEmpty else { throw Failure.openContour }
        return existing + vacant
    }

    /// Called after native capture finishes, never during live acquisition.
    /// Keep raw walls/initialRoom and existing roofs exactly as recorded. A zone
    /// with missing/invalid boundaries is skipped, not filled with an invented box.
    static func addingAutomaticCeilings(to document: PlaquistoRoomDocument) -> PlaquistoRoomDocument {
        guard let proposals = try? manualProposals(in:document.room) else { return document }
        var result = document
        for proposal in proposals where proposal.ceilingID == nil {
            guard !Task.isCancelled else { return document }
            let settings = CeilingAutoFit(room:document.room,proposal:proposal).automaticSettings()
            guard !Task.isCancelled else { return document }
            if let generated = try? applying(to:result,proposal:proposal,settings:settings,manuallyEdited:false) {
                result = generated
            }
        }
        return result
    }

    static func applying(to document: PlaquistoRoomDocument, proposal: Proposal,
                         settings: CeilingEstimateSettings, manuallyEdited: Bool) throws -> PlaquistoRoomDocument {
        if let ceilingID = proposal.ceilingID {
            guard let target = document.room.ceilings.first(where: { $0.id == ceilingID }) else { throw Failure.existingCeiling }
            guard !document.room.slopes.contains(where: { slope in
                !target.slopeIDs.contains(slope.id) && slope.boundaries.contains { overlaps(proposal.boundary,$0) }
            }) else { throw Failure.existingCeiling }
            var part = document
            part.room.ceilings = []; part.room.slopes = []
            var local = proposal; local.ceilingID = nil
            guard target.provenance.source == .estimated else { throw Failure.existingCeiling }
            var generated = try applying(to: part, proposal: local, settings: settings, manuallyEdited: manuallyEdited)
            generated.room.ceilings[0].id = target.id
            generated.room.ceilings[0].planNumber = target.planNumber
            generated.room.ceilings[0].isHidden = target.isHidden
            let previous = document.room.slopes.filter { target.slopeIDs.contains($0.id) }
            for i in generated.room.slopes.indices where previous.indices.contains(i) {
                generated.room.slopes[i].id = previous[i].id
            }
            generated.room.ceilings[0].slopeIDs = generated.room.slopes.map(\.id)
            var result = document
            if let index=result.room.ceilings.firstIndex(where:{ $0.id == ceilingID }) { result.room.ceilings[index]=generated.room.ceilings[0] }
            result.room.slopes.removeAll { target.slopeIDs.contains($0.id) }; result.room.slopes += generated.room.slopes
            try result.validate(); return result
        }
        guard settings.isValid else { throw Failure.invalidHeight }
        guard !document.room.slopes.contains(where: { slope in
            slope.boundaries.contains { overlaps(proposal.boundary,$0) }
        }) else { throw Failure.existingCeiling }
        var polygon = proposal.boundary.map { SIMD2($0.x, $0.z) }
        if ScannerCeilingReconstruction.triangulate(polygon) == nil { polygon.reverse() }
        guard let indices = ScannerCeilingReconstruction.triangulate(polygon) else { throw Failure.openContour }
        let planes = try planes(boundary: proposal.boundary, floorElevation: proposal.floorElevation, settings: settings)
        let source = GeometryProvenance(source: .estimated)
        var pans: [PlaquistoSlope] = []
        for (index, plane) in planes.enumerated() {
            var triangles: [SIMD3<Double>] = []
            for start in stride(from: 0, to: indices.count, by: 3) {
                var clipped = (0..<3).map { polygon[indices[start+$0]] }
                for (otherIndex, other) in planes.enumerated() where otherIndex != index {
                    clipped = clip(clipped, a: plane.a-other.a, b: plane.b-other.b, c: plane.c-other.c)
                }
                guard clipped.count >= 3 else { continue }
                for i in 1..<(clipped.count-1) {
                    let a = clipped[0], b = clipped[i], c = clipped[i+1]
                    guard abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)) > 1e-10 else { continue }
                    triangles += [a,c,b].map { .init($0.x, plane.height(x: $0.x, z: $0.y), $0.y) }
                }
            }
            let loops = ScannerRoomBridge.boundaries(triangles, resolvingTJunctions: true).map(simplify)
            guard !loops.isEmpty else { continue }
            pans.append(.init(plane: plane, boundaries: loops, provenance: source,
                              accepted: true, manuallyValidated: manuallyEdited))
        }
        guard !pans.isEmpty else { throw Failure.openContour }
        func projectedArea(_ loop: [RoomPoint]) -> Double {
            abs(loop.indices.reduce(0.0) { sum, i in
                let a = loop[i], b = loop[(i+1)%loop.count]
                return sum + a.x*b.z-b.x*a.z
            }) / 2
        }
        let originalArea = projectedArea(proposal.boundary)
        let coveredArea = pans.reduce(0.0) { $0 + $1.boundaries.reduce(0.0) { $0 + projectedArea($1) } }
        guard abs(coveredArea-originalArea) <= max(1e-6, originalArea*1e-6) else { throw Failure.openContour }
        // Preserve stable IDs while editing the same family; prevent stale geometry
        // from appearing as a new source without the existing review mechanism.
        var edited = document
        edited.room.slopes += pans
        let number = max(document.room.ceilings.count,document.room.ceilings.compactMap(\.planNumber).max() ?? 0)+1
        edited.room.ceilings.append(.init(slopeIDs:pans.map(\.id),provenance:source,estimateSettings:settings,
                                         footprint:proposal.boundary,floorElevation:proposal.floorElevation,planNumber:number))
        try edited.validate()
        return edited
    }

    /// Shared by the editor mesh and its fitter: the same settings always describe the same roof.
    static func planes(boundary: [RoomPoint], floorElevation: Double,
                       settings: CeilingEstimateSettings) throws -> [RoomPlane] {
        guard settings.isValid, floorElevation.isFinite, boundary.allSatisfy(\.finite) else { throw Failure.invalidHeight }
        let u = SIMD2(cos(settings.azimuth), sin(settings.azimuth)), v = SIMD2(-u.y, u.x)
        let polygon = boundary.map { SIMD2($0.x, $0.z) }
        let us = polygon.map { simd_dot($0, u) }, vs = polygon.map { simd_dot($0, v) }
        guard let u0 = us.min(), let u1 = us.max(), let v0 = vs.min(), let v1 = vs.max(),
              u1-u0 > 0.01, v1-v0 > 0.01 else { throw Failure.openContour }
        let bottom = floorElevation + settings.lowHeight
        let rise = settings.highHeight-settings.lowHeight
        let peak = u0+(u1-u0)*settings.ridgePosition
        func plane(_ axis: SIMD2<Double>, _ gradient: Double, _ origin: Double) -> RoomPlane {
            .init(a:axis.x*gradient, b:axis.y*gradient, c:bottom-gradient*origin)
        }
        if settings.shape == .flat || rise < 1e-8 { return [.init(a:0,b:0,c:bottom)] }
        if settings.shape == .singleSlope { return [plane(u,rise/(u1-u0),u0)] }
        var result = [plane(u,rise/(peak-u0),u0), plane(u,-rise/(u1-peak),u1)]
        if settings.shape == .fourSlopes {
            let run = min((u1-u0)/2,(v1-v0)/2)
            result += [plane(v,rise/run,v0), plane(v,-rise/run,v1)]
        }
        return result
    }

    static func footprint(of ceiling: PlaquistoCeiling, in room: PlaquistoRoomModel) -> [RoomPoint]? {
        if let footprint=ceiling.footprint { return footprint }
        var part=room; part.slopes=room.slopes.filter { ceiling.slopeIDs.contains($0.id) }
        guard part.slopes.allSatisfy({ $0.boundaries.count == 1 }) else { return nil }
        let vertices=ScannerCeilingReview.Choice(room:part).vertices.map { SIMD3($0.x,0,$0.z) }
        let loops=ScannerRoomBridge.boundaries(vertices).map(simplify)
        return loops.count == 1 ? loops.first : nil
    }
    private static func sameFootprint(_ a:[RoomPoint], _ b:[RoomPoint]) -> Bool {
        a.count == b.count && a.allSatisfy { p in b.contains { hypot(p.x-$0.x,p.z-$0.z) < 1e-5 } }
    }
    private static func overlaps(_ a:[RoomPoint], _ b:[RoomPoint]) -> Bool {
        func choice(_ boundary:[RoomPoint]) -> ScannerCeilingReview.Choice {
            var room=PlaquistoRoomModel(metadata:.init(source:.estimated))
            room.slopes=[.init(plane:.init(a:0,b:0,c:0),boundaries:[boundary],provenance:.init(source:.estimated))]
            return .init(room:room)
        }
        return ScannerCeilingReview.overlaps(choice(a),choice(b))
    }
    /// Cut only the chosen ceiling. Clip its actual planes, never recalculate its
    /// heights or alter scanned walls. Both pieces are committed atomically.
    static func split(_ document:PlaquistoRoomDocument, ceilingID:UUID,
                      from start:RoomPoint, to end:RoomPoint) throws -> PlaquistoRoomDocument {
        guard let target=document.room.ceilings.first(where:{$0.id==ceilingID}),
              target.provenance.source == .estimated,
              let outline=footprint(of:target,in:document.room),
              hypot(end.x-start.x,end.z-start.z) > 0.1 else { throw Failure.invalidSplit }
        let a=start.z-end.z, b=end.x-start.x, c = -a*start.x-b*start.z
        let original=document.room.slopes.filter { target.slopeIDs.contains($0.id) }
        guard original.allSatisfy({ $0.boundaries.count == 1 }) else { throw Failure.invalidSplit }
        var halves:[[PlaquistoSlope]]=[], footprints:[[RoomPoint]]=[]
        let splitOperation = UUID()
        for sign in [1.0,-1.0] {
            var footprintTriangles:[SIMD3<Double>]=[]
            var pans:[PlaquistoSlope]=[]
            for slope in original {
                var ring=slope.boundaries[0].map { SIMD2($0.x,$0.z) }
                if ScannerCeilingReconstruction.triangulate(ring) == nil { ring.reverse() }
                guard let indices=ScannerCeilingReconstruction.triangulate(ring) else { throw Failure.invalidSplit }
                var triangles:[SIMD3<Double>]=[]
                for i in stride(from:0,to:indices.count,by:3) {
                    let polygon=clip((0..<3).map { ring[indices[i+$0]] },a:sign*a,b:sign*b,c:sign*c)
                    guard polygon.count >= 3 else { continue }
                    for j in 1..<(polygon.count-1) {
                        let vertices=[polygon[0],polygon[j+1],polygon[j]]
                        let cross=(vertices[1].x-vertices[0].x)*(vertices[2].y-vertices[0].y) -
                            (vertices[1].y-vertices[0].y)*(vertices[2].x-vertices[0].x)
                        guard abs(cross)>1e-9 else { continue }
                        triangles += vertices.map { .init($0.x,slope.plane.height(x:$0.x,z:$0.y),$0.y) }
                        footprintTriangles += vertices.map { .init($0.x,0,$0.y) }
                    }
                }
                let loops=ScannerRoomBridge.boundaries(triangles, resolvingTJunctions: true).map(simplify)
                if !loops.isEmpty {
                    var next=slope; next.boundaries=loops
                    let ancestors=slope.splitOrigin.map { [$0.sourceSlopeID]+($0.ancestorSlopeIDs ?? []) }
                    next.splitOrigin = .init(operationID:splitOperation,sourceSlopeID:slope.id,ancestorSlopeIDs:ancestors)
                    if sign < 0 { next.id=UUID() }
                    pans.append(next)
                }
            }
            let loops=ScannerRoomBridge.boundaries(footprintTriangles, resolvingTJunctions: true).map(simplify)
            guard loops.count == 1, let boundary=loops.first,
                  pans.reduce(0, { $0+PlaquistoSurfaceGeometry.area(of:$1) }) > 0.05 else { throw Failure.invalidSplit }
            footprints.append(boundary); halves.append(pans)
        }
        let before=original.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) }
        let after=halves.flatMap { $0 }.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) }
        guard abs(before-after) < max(1e-6,before*1e-6), !outline.isEmpty else { throw Failure.invalidSplit }
        return try applyingSplit(document,target:target,original:original,halves:halves,footprints:footprints,outline:outline)
    }

    /// Close the new partition against the *raw* shell for ceiling topology.
    /// Finished faces remain the saved physical endpoints; no scanned wall moves.
    static func splitForNewPartition(before: PlaquistoRoomDocument, after: PlaquistoRoomDocument,
                                     depths: [UUID: Double]) throws -> PlaquistoRoomDocument {
        let oldIDs=Set(before.room.walls.map(\.id))
        let added=after.room.walls.filter { !oldIDs.contains($0.id) }
        guard !added.isEmpty else { throw Failure.invalidSplit }
        let finished=SurveyPlanFinishes.finishedWalls(in:before,depths:depths)
        var topology=after.room
        func extended(_ point:RoomPoint, direction:RoomPoint) -> RoomPoint {
            for face in finished {
                let delta=point-face.start, along=delta.x*face.direction.x+delta.z*face.direction.z
                guard along >= -0.01,along <= face.length.effectiveValue+0.01,
                      (point-(face.start+face.direction*along)).horizontalLength < 0.02,
                      let raw=before.room.walls.first(where:{$0.id==face.id}) else { continue }
                let cross=direction.x*raw.direction.z-direction.z*raw.direction.x
                guard abs(cross)>1e-6 else { continue }
                let d=raw.start-point, t=(d.x*raw.direction.z-d.z*raw.direction.x)/cross
                if abs(t)<2 { return point+direction*t }
            }
            return point
        }
        for i in topology.walls.indices where !oldIDs.contains(topology.walls[i].id) {
            let wall=topology.walls[i]
            topology.walls[i].start=extended(wall.start,direction:wall.direction)
            topology.walls[i].end=extended(wall.effectiveEnd,direction:wall.direction)
            topology.walls[i].length.manualValue=(topology.walls[i].end-topology.walls[i].start).horizontalLength
        }
        let zones=ScanEnclosedSpaces.wallsBySpace(in:topology).map { $0.map(\.start) }
        var matches: [(PlaquistoCeiling,[[RoomPoint]])]=[]
        for ceiling in before.room.ceilings {
            guard let outline=footprint(of:ceiling,in:before.room) else { continue }
            let contained=zones.filter { ring in
                guard let center=ArchitecturalPlanInk.interiorPoint(ring) else { return false }
                return PlaquistoWallGeometry.contains(center,polygon:outline)
            }
            let area=abs(SurveyPlanFinishes.area(outline)), sum=contained.reduce(0) { $0+abs(SurveyPlanFinishes.area($1)) }
            if contained.count == 2, abs(area-sum)<max(0.001,area*1e-5) { matches.append((ceiling,contained)) }
        }
        guard matches.count == 1, let (target,regions)=matches.first,
              let outline=footprint(of:target,in:before.room) else { throw Failure.invalidSplit }
        let original=after.room.slopes.filter { target.slopeIDs.contains($0.id) }
        guard !original.isEmpty, original.allSatisfy({$0.boundaries.count==1}) else { throw Failure.invalidSplit }
        let operation=UUID()
        var halves:[[PlaquistoSlope]]=[], usedIDs=Set<UUID>()
        for region in regions {
            var boundary=region.map { SIMD2($0.x,$0.z) }
            if ScannerCeilingReconstruction.triangulate(boundary)==nil { boundary.reverse() }
            guard let zoneIndices=ScannerCeilingReconstruction.triangulate(boundary) else { throw Failure.invalidSplit }
            var pans:[PlaquistoSlope]=[]
            for slope in original {
                var ring=slope.boundaries[0].map { SIMD2($0.x,$0.z) }
                if ScannerCeilingReconstruction.triangulate(ring)==nil { ring.reverse() }
                guard let indices=ScannerCeilingReconstruction.triangulate(ring) else { throw Failure.invalidSplit }
                var triangles:[SIMD3<Double>]=[]
                for i in stride(from:0,to:indices.count,by:3) {
                    for j in stride(from:0,to:zoneIndices.count,by:3) {
                        let zone=(0..<3).map { boundary[zoneIndices[j+$0]] }
                        let orient=(zone[1].x-zone[0].x)*(zone[2].y-zone[0].y)-(zone[1].y-zone[0].y)*(zone[2].x-zone[0].x)
                        var poly=(0..<3).map { ring[indices[i+$0]] }
                        for k in 0..<3 {
                            let p=zone[k],q=zone[(k+1)%3], sign=orient>0 ? -1.0 : 1.0
                            poly=clip(poly,a:sign*(p.y-q.y),b:sign*(q.x-p.x),c:sign*(p.x*q.y-q.x*p.y))
                        }
                        if poly.count >= 3 {
                            for k in 1..<(poly.count-1) {
                                let vertices=[poly[0],poly[k],poly[k+1]]
                                let cross=(vertices[1].x-vertices[0].x)*(vertices[2].y-vertices[0].y)-(vertices[1].y-vertices[0].y)*(vertices[2].x-vertices[0].x)
                                if abs(cross)>1e-9 { triangles += vertices.map { SIMD3($0.x,slope.plane.height(x:$0.x,z:$0.y),$0.y) } }
                            }
                        }
                    }
                }
                let loops=ScannerRoomBridge.boundaries(triangles).map(simplify)
                guard !loops.isEmpty else { continue }
                var next=slope; next.boundaries=loops
                next.splitOrigin = .init(operationID:operation,sourceSlopeID:slope.id,
                    ancestorSlopeIDs:slope.splitOrigin.map { [$0.sourceSlopeID]+($0.ancestorSlopeIDs ?? []) })
                if !usedIDs.insert(slope.id).inserted { next.id=UUID() }
                pans.append(next)
            }
            guard !pans.isEmpty else { throw Failure.invalidSplit }
            halves.append(pans)
        }
        let total=original.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) }
        guard abs(halves.flatMap{$0}.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) }-total)<max(1e-6,total*1e-6) else { throw Failure.invalidSplit }
        return try applyingSplit(after,target:target,original:original,halves:halves,footprints:regions,outline:outline)
    }

    private static func applyingSplit(_ document:PlaquistoRoomDocument,target:PlaquistoCeiling,
                                      original:[PlaquistoSlope],halves:[[PlaquistoSlope]],
                                      footprints:[[RoomPoint]],outline:[RoomPoint]) throws -> PlaquistoRoomDocument {
        var result=document
        result.room.slopes.removeAll { target.slopeIDs.contains($0.id) }
        result.room.slopes += halves.flatMap { $0 }
        let nextNumber=max(result.room.ceilings.count,result.room.ceilings.compactMap(\.planNumber).max() ?? 0)+1
        for i in 0..<2 {
            var ceiling=target
            ceiling.slopeIDs=halves[i].map(\.id)
            let reference=target.floorElevation ?? ((original.flatMap { $0.boundaries.flatMap { $0 } }.map(\.y).min() ?? 0)-(target.estimateSettings?.lowHeight ?? 0))
            ceiling.floorElevation=reference
            ceiling.footprint=footprints[i].map { .init(x:$0.x,y:reference,z:$0.z) }
            let vertices=halves[i].flatMap { $0.boundaries.flatMap { $0 } }
            var settings=target.estimateSettings ?? .init(lowHeight:2.5,highHeight:2.5)
            settings.lowHeight=(vertices.map(\.y).min() ?? reference)-reference
            settings.highHeight=(vertices.map(\.y).max() ?? reference)-reference
            if halves[i].count == 1, let plane=halves[i].first?.plane {
                settings.shape=plane.slopeDegrees < 1e-6 ? .flat : .singleSlope
                settings.azimuth=atan2(plane.b,plane.a)
            } else {
                let u=SIMD2(cos(settings.azimuth),sin(settings.azimuth))
                let previous=outline.map { simd_dot(SIMD2($0.x,$0.z),u) }
                let current=footprints[i].map { simd_dot(SIMD2($0.x,$0.z),u) }
                if let lo=previous.min(), let hi=previous.max(), let newLo=current.min(), let newHi=current.max(), newHi>newLo {
                    let peak=lo+(hi-lo)*settings.ridgePosition
                    settings.ridgePosition=min(0.85,max(0.15,(peak-newLo)/(newHi-newLo)))
                }
            }
            ceiling.estimateSettings=settings
            if i == 0, let index=result.room.ceilings.firstIndex(where:{$0.id==target.id}) {
                result.room.ceilings[index]=ceiling
            } else {
                ceiling.id=UUID(); ceiling.planNumber=nextNumber
                result.room.ceilings.append(ceiling)
            }
        }
        try result.validate()
        return result
    }

    private static func clip(_ polygon: [SIMD2<Double>], a: Double, b: Double, c: Double) -> [SIMD2<Double>] {
        guard !polygon.isEmpty else { return [] }
        var output: [SIMD2<Double>] = []
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i+1)%polygon.count]
            let dp = a*p.x+b*p.y+c, dq = a*q.x+b*q.y+c
            if dp <= 1e-9 { output.append(p) }
            if (dp < -1e-9 && dq > 1e-9) || (dp > 1e-9 && dq < -1e-9) {
                output.append(p + (q-p) * (dp/(dp-dq)))
            }
        }
        return output
    }

    private static func simplify(_ loop: [RoomPoint]) -> [RoomPoint] {
        guard loop.count > 3 else { return loop }
        return loop.indices.compactMap { i in
            let p = loop[(i+loop.count-1)%loop.count], q = loop[i], r = loop[(i+1)%loop.count]
            return abs((q.x-p.x)*(r.z-q.z)-(q.z-p.z)*(r.x-q.x)) > 1e-9 ? q : nil
        }
    }
}

// Technical reconstruction -> parametric domain planes and boundary loops.
// Triangles are consumed here, never saved as the working model.
enum ScannerRoomBridge {
    static func apply(_ surface: ScannerCeilingReconstruction.Surface, to room: inout PlaquistoRoomModel, accepted: Bool, manuallyValidated: Bool) {
        let source = GeometryProvenance(source:.lidar)
        var slopes: [PlaquistoSlope] = []
        for pan in surface.pans {
            let v = pan.vertices
            guard v.count >= 3 else { continue }
            let n = simd_cross(v[1]-v[0],v[2]-v[0])
            guard abs(n.y) > 1e-9 else { continue }
            let a = -n.x/n.y, b = -n.z/n.y
            let loops = boundaries(v)
            guard !loops.isEmpty else { continue }
            slopes.append(.init(plane:.init(a:a,b:b,c:v[0].y-a*v[0].x-b*v[0].z),boundaries:loops,
                                provenance:source,accepted:accepted,manuallyValidated:manuallyValidated))
        }
        room.slopes = slopes
        room.ceilings = slopes.isEmpty ? [] : [.init(slopeIDs:slopes.map(\.id),provenance:source)]
    }
    static func boundaries(_ vertices: [SIMD3<Double>], resolvingTJunctions: Bool = false) -> [[RoomPoint]] {
        guard vertices.count >= 3, vertices.count.isMultiple(of:3),
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && simd_length($0)<1e8 }) else { return [] }
        func key(_ p: SIMD3<Double>) -> String { "\(Int64((p.x*100000).rounded()))/\(Int64((p.y*100000).rounded()))/\(Int64((p.z*100000).rounded()))" }
        var edges: [String:(String,String)] = [:], counts: [String:Int] = [:], points: [String:RoomPoint] = [:]
        // Clipping adjacent triangles can leave A—C opposite A—B—C.
        // Split both into the same elementary edges before cancelling seams.
        // This changes topology only: no point, roof height or slope is averaged.
        var unique:[String:SIMD3<Double>]=[:]
        if resolvingTJunctions { for p in vertices { unique[key(p)] = p } }
        let candidates=unique.keys.sorted().compactMap { unique[$0] }
        var triangles=Set<String>()
        for i in stride(from:0,to:vertices.count-2,by:3) {
            if resolvingTJunctions {
                let tri=Array(vertices[i...i+2])
                guard simd_length(simd_cross(tri[1]-tri[0],tri[2]-tri[0]))>1e-12,
                      triangles.insert(tri.map(key).sorted().joined(separator:"|")).inserted else { continue }
            }
            for j in 0..<3 {
                let a = vertices[i+j], b = vertices[i+(j+1)%3], d=b-a, square=simd_length_squared(d)
                guard key(a) != key(b), square>1e-16 else { continue }
                var chain:[(Double,SIMD3<Double>)]=[(0,a),(1,b)]
                if resolvingTJunctions {
                    for p in candidates {
                        let t=simd_dot(p-a,d)/square
                        if t>1e-8, t<1-1e-8, simd_length(p-(a+d*t))<1e-6 { chain.append((t,p)) }
                    }
                    chain.sort { $0.0<$1.0 }
                }
                for k in 1..<chain.count {
                    let p=chain[k-1].1,q=chain[k].1,ka=key(p),kb=key(q)
                    guard ka != kb else { continue }
                    let edge = [ka,kb].sorted().joined(separator:"|")
                    counts[edge,default:0] += 1; edges[edge] = (ka,kb)
                    points[ka] = .init(x:p.x,y:p.y,z:p.z); points[kb] = .init(x:q.x,y:q.y,z:q.z)
                }
            }
        }
        var remaining = edges.keys.sorted().filter { counts[$0] == 1 }.compactMap { edges[$0] }
        if resolvingTJunctions {
            // Never return a partial silhouette for ambiguous/non-manifold input.
            guard !counts.values.contains(where: { $0>2 }),
                  Set(remaining.map { $0.0 }).count == remaining.count,
                  Set(remaining.map { $0.1 }).count == remaining.count else { return [] }
        }
        var loops: [[RoomPoint]] = []
        while !remaining.isEmpty {
            let first = remaining.removeFirst(); var path = [first.0]; var end = first.1
            while end != first.0, let next = remaining.firstIndex(where: { $0.0 == end }) {
                path.append(end); end = remaining.remove(at:next).1
            }
            if end == first.0, path.count >= 3 { loops.append(path.compactMap { points[$0] }) }
            else if resolvingTJunctions { return [] }
        }
        return loops
    }
}
