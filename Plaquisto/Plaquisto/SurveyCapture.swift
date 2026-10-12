import Foundation

/// One-shot final-scan cleanup, before ceilings or ouvrages exist. It operates
/// in X/Z only; native wall profiles and the complete initialRoom are retained.
enum ScanWallSimplification {
    private static let joinTolerance = 0.05 // metres, not a doorway repair
    private static let deviationTolerance = 0.04
    private static let heightTolerance = 0.04
    private static let angleCosine = cos(6 * Double.pi / 180)
    private struct Join {
        let a: Int; let b: Int
        let aEnd: Bool; let bEnd: Bool
    }
    struct Result {
        let document: PlaquistoRoomDocument
        let mergedGroups: Int
        let removedFragments: Int
    }

    static func process(_ document: PlaquistoRoomDocument) -> Result {
        func unchanged() -> Result { .init(document: document, mergedGroups: 0, removedFragments: 0) }
        // Never silently migrate an edited or furnished project document.
        guard document.room == document.initialRoom, document.room.ceilings.isEmpty,
              document.room.slopes.isEmpty, document.wallWorkIntents?.isEmpty != false,
              (try? document.validate()) != nil else { return unchanged() }
        let walls = document.room.walls
        func eligible(_ w: PlaquistoWall) -> Bool {
            w.provenance.source == .roomPlan && w.length.effectiveValue >= 0.15
                && w.length.manualValue == nil && w.height.manualValue == nil && w.thickness?.manualValue == nil
                && abs((w.end-w.start).horizontalLength-w.length.effectiveValue) < 0.01
                && !document.room.openings.contains { o in o.wallID == w.id &&
                    [o.width,o.height,o.sillHeight,o.positionOnWall].contains { $0.manualValue != nil } }
        }
        let active = walls.indices.filter { eligible(walls[$0]) }
        var joins: [Join] = []
        for (offset,i) in active.enumerated() {
            for j in active.dropFirst(offset+1) {
                let a=walls[i], b=walls[j]
                if let ta=a.thickness?.effectiveValue, let tb=b.thickness?.effectiveValue, abs(ta-tb)>0.005 { continue }
                for ae in [false,true] { for be in [false,true] {
                    let p=ae ? a.effectiveEnd : a.start, q=be ? b.effectiveEnd : b.start
                    let u=a.direction*(ae ? -1 : 1), v=b.direction*(be ? -1 : 1)
                    // Opposed rays at the shared end, not duplicate parallel wall faces.
                    guard (p-q).horizontalLength <= joinTolerance, abs(p.y-q.y) <= joinTolerance,
                          u.x*v.x+u.z*v.z < -angleCosine else { continue }
                    joins.append(.init(a:i,b:j,aEnd:ae,bEnd:be))
                } }
            }
        }
        var visited=Set<Int>(), result=document, groups=0, removed=0
        for root in active where !visited.contains(root) {
            var group=Set([root]), queue=[root]
            while let current=queue.popLast() {
                for edge in joins where edge.a == current || edge.b == current {
                    let other=edge.a == current ? edge.b : edge.a
                    if group.insert(other).inserted { queue.append(other) }
                }
            }
            visited.formUnion(group)
            guard group.count > 1 else { continue }
            let edges=joins.filter { group.contains($0.a) && group.contains($0.b) }
            guard edges.count == group.count-1 else { continue }
            // Each end can have one neighbour only. Branches and loops are not flattened.
            guard group.allSatisfy({ i in
                [false,true].allSatisfy { end in
                    edges.filter { ($0.a == i && $0.aEnd == end) || ($0.b == i && $0.bEnd == end) }.count <= 1
                }
            }) else { continue }
            let ends=group.filter { i in edges.filter { $0.a == i || $0.b == i }.count == 1 }.sorted {
                walls[$0].id.uuidString < walls[$1].id.uuidString
            }
            guard ends.count == 2, let first=ends.first else { continue }
            var order: [(Int,Bool)] = [], current=first, previous: Int? = nil
            while order.count < group.count {
                let next=edges.first { ($0.a == current && $0.b != previous) || ($0.b == current && $0.a != previous) }
                let forward: Bool
                if let next { forward = next.a == current ? next.aEnd : next.bEnd }
                else if let previous, let incoming=edges.first(where: { ($0.a == current && $0.b == previous) || ($0.b == current && $0.a == previous) }) {
                    forward = !(incoming.a == current ? incoming.aEnd : incoming.bEnd)
                } else { break }
                order.append((current,forward))
                guard let next else { break }
                previous=current; current=next.a == current ? next.b : next.a
            }
            guard order.count == group.count,
                  let updated = merge(result, originals: walls, order: order) else { continue }
            result=updated; groups += 1; removed += group.count-1
        }
        return .init(document:result,mergedGroups:groups,removedFragments:removed)
    }

    private static func merge(_ document: PlaquistoRoomDocument, originals: [PlaquistoWall], order: [(Int,Bool)]) -> PlaquistoRoomDocument? {
        let ordered=order.map { originals[$0.0] }
        let sourceIDs=Set(ordered.map(\.id))
        let first=ordered[0], last=ordered[ordered.count-1]
        let start=order[0].1 ? first.start : first.effectiveEnd
        let end=order[order.count-1].1 ? last.effectiveEnd : last.start
        let length=(end-start).horizontalLength
        guard length > 0.3 else { return nil }
        let axis=RoomPoint(x:(end.x-start.x)/length,y:0,z:(end.z-start.z)/length)
        func along(_ p:RoomPoint) -> Double { let d=p-start; return d.x*axis.x+d.z*axis.z }
        func perpendicular(_ p:RoomPoint) -> Double { let d=p-start; return abs(d.x*axis.z-d.z*axis.x) }
        // Fit to the outer endpoints: real corners stay put and adjacent walls stay connected.
        // Test ALL original fragments against this common line, avoiding chained drift.
        guard ordered.allSatisfy({ w in
            perpendicular(w.start) <= deviationTolerance && perpendicular(w.effectiveEnd) <= deviationTolerance
                && abs(w.direction.x*axis.x+w.direction.z*axis.z) >= angleCosine
        }) else { return nil }
        var breaks=[0.0]
        for i in 1..<ordered.count {
            let a=order[i-1].1 ? ordered[i-1].effectiveEnd : ordered[i-1].start
            let b=order[i].1 ? ordered[i].start : ordered[i].effectiveEnd
            let joint=(a+b)*0.5
            // Do not move a T junction, a return, or a neighbouring parallel wall face.
            guard !document.room.walls.contains(where: { !sourceIDs.contains($0.id) && segmentDistance(joint,$0.start,$0.effectiveEnd) < 0.04 }) else { return nil }
            breaks.append((along(a)+along(b))/2)
        }
        breaks.append(length)
        guard zip(breaks,breaks.dropFirst()).allSatisfy({ $0.1-$0.0 >= 0.15 }) else { return nil }
        var polygons: [[RoomPoint]] = []
        // Express all profiles in one wall-local frame. Only X is straightened.
        for i in ordered.indices {
            let w=ordered[i], forward=order[i].1, span=breaks[i+1]-breaks[i]
            let polygon=w.effectiveOutline
            guard polygon.allSatisfy({ $0.x >= -0.001 && $0.x <= w.length.effectiveValue+0.001 }) else { return nil }
            polygons.append(polygon.map { p in
                let fraction=forward ? p.x/w.length.effectiveValue : 1-p.x/w.length.effectiveValue
                return .init(x:breaks[i]+fraction*span,y:w.start.y+p.y,z:0)
            })
        }
        for i in 1..<polygons.count {
            let x=breaks[i]
            let left=polygons[i-1].indices.filter { abs(polygons[i-1][$0].x-x)<0.001 }.sorted { polygons[i-1][$0].y < polygons[i-1][$1].y }
            let right=polygons[i].indices.filter { abs(polygons[i][$0].x-x)<0.001 }.sorted { polygons[i][$0].y < polygons[i][$1].y }
            // Whole shared vertical edge only; never fill a real missing panel or height step.
            guard left.count == 2, right.count == 2,
                  abs(left[0]-left[1]) == 1 || abs(left[0]-left[1]) == polygons[i-1].count-1,
                  abs(right[0]-right[1]) == 1 || abs(right[0]-right[1]) == polygons[i].count-1 else { return nil }
            for k in 0..<2 {
                let a=polygons[i-1][left[k]].y, b=polygons[i][right[k]].y
                guard abs(a-b) <= heightTolerance else { return nil }
                polygons[i-1][left[k]].x=x; polygons[i][right[k]].x=x
                polygons[i-1][left[k]].y=(a+b)/2; polygons[i][right[k]].y=(a+b)/2
            }
        }
        var result=document
        let provenance=GeometryProvenance(source:.estimated,sourceIdentifier:"wall-straightening-v1")
        for i in ordered.indices {
            let old=ordered[i], span=breaks[i+1]-breaks[i]
            var w=old
            w.start=start+axis*breaks[i]; w.start.y=old.start.y
            w.end=start+axis*breaks[i+1]; w.end.y=old.start.y
            w.length = .init(rawValue:span,provenance:provenance)
            w.localOutline=polygons[i].map { .init(x:$0.x-breaks[i],y:$0.y-old.start.y,z:0) }
            guard let index=result.room.walls.firstIndex(where: { $0.id == old.id }) else { return nil }
            result.room.walls[index]=w
            for j in result.room.openings.indices where result.room.openings[j].wallID == old.id {
                var opening=result.room.openings[j]
                let oldCenter=opening.positionOnWall.effectiveValue+opening.width.effectiveValue/2
                let fraction=order[i].1 ? oldCenter/old.length.effectiveValue : 1-oldCenter/old.length.effectiveValue
                let position=fraction*span-opening.width.effectiveValue/2
                guard position >= -0.001, position+opening.width.effectiveValue <= span+0.001 else { return nil }
                opening.positionOnWall = .init(rawValue:max(0,position),provenance:provenance)
                opening.center=w.start+axis*(position+opening.width.effectiveValue/2)
                    + RoomPoint(x:0,y:opening.sillHeight.effectiveValue+opening.height.effectiveValue/2,z:0)
                result.room.openings[j]=opening
            }
        }
        for w in ordered.dropFirst() {
            guard let next=try? SurveyPlanEditing.mergingWalls(result,first:first.id,second:w.id) else { return nil }
            result=next
        }
        guard let index=result.room.walls.firstIndex(where: { $0.id == first.id }) else { return nil }
        result.room.walls[index].provenance=provenance
        result.room.walls[index].length.provenance=provenance
        result.room.walls[index].height.provenance=provenance
        result.room.walls[index].length.manuallyValidated=false
        result.room.walls[index].height.manuallyValidated=false
        for i in result.room.openings.indices where result.room.openings[i].wallID == first.id {
            for key in [\PlaquistoOpening.positionOnWall, \PlaquistoOpening.sillHeight] {
                let value=result.room.openings[i][keyPath:key].effectiveValue
                result.room.openings[i][keyPath:key] = .init(rawValue:value,provenance:provenance)
            }
        }
        let before=ordered.reduce(0.0) { $0+PlaquistoWallGeometry.analyze(wall:$1,room:document.room).gross }
        let after=PlaquistoWallGeometry.analyze(wall:result.room.walls[index],room:result.room).gross
        guard before > 0, abs(after-before) <= max(0.01,before*0.01) else { return nil }
        // Floor boundary points on the same fragments follow their new axis;
        // other walls, the reference frame and elevations remain untouched.
        for i in result.room.floors.indices {
            for j in result.room.floors[i].boundaries.indices {
                let old=result.room.floors[i].boundaries[j]
                let ring=old.map { p -> RoomPoint in
                    let t=along(p)
                    guard t > 0.001, t < length-0.001, perpendicular(p)<=deviationTolerance,
                          ordered.contains(where: { segmentDistance(p,$0.start,$0.effectiveEnd)<joinTolerance }) else { return p }
                    var projected=start+axis*t; projected.y=p.y; return projected
                }
                guard abs(abs(SurveyPlanFinishes.area(ring))-abs(SurveyPlanFinishes.area(old))) <= max(0.01,abs(SurveyPlanFinishes.area(old))*0.01),
                      (try? LayoutGeometry.validate(ring.map { .init(x:$0.x*1000,y:$0.z*1000) })) != nil else { return nil }
                result.room.floors[i].boundaries[j]=ring
            }
        }
        guard (try? result.validate()) != nil else { return nil }
        return result
    }

    private static func segmentDistance(_ p:RoomPoint,_ a:RoomPoint,_ b:RoomPoint) -> Double {
        let d=b-a, v=p-a, square=d.x*d.x+d.z*d.z
        guard square > 1e-12 else { return v.horizontalLength }
        let t=max(0,min(1,(v.x*d.x+v.z*d.z)/square))
        return (p-(a+d*t)).horizontalLength
    }
}

/// Camera-only rotation in the scan's X/Z plane. Editing always uses the inverse
/// transform so neither wall geometry nor the saved scan is rotated.
enum SurveyPlanCamera {
    static func rotated(_ point:RoomPoint,around center:RoomPoint,angle:Double) -> RoomPoint {
        let x=point.x-center.x, z=point.z-center.z, c=cos(angle), s=sin(angle)
        return .init(x:center.x+x*c-z*s,y:point.y,z:center.z+x*s+z*c)
    }
    static func nextWall(_ walls:[PlaquistoWall],after id:UUID?) -> PlaquistoWall? {
        let valid=walls.filter { ($0.effectiveEnd-$0.start).horizontalLength > 0.001 }
        guard !valid.isEmpty else { return nil }
        let next=id.flatMap { id in valid.firstIndex { $0.id == id } }.map { ($0+1)%valid.count } ?? 0
        return valid[next]
    }
    static func horizontalAngle(for wall:PlaquistoWall) -> Double {
        let d=wall.effectiveEnd-wall.start
        return -atan2(d.z,d.x)
    }
}

/// An explicit measured depth wins; otherwise use the ouvrage composition.
enum SurveyPlanFinishes {
    static func depth(_ payload: WorkConfiguration) -> Double? {
        let mm: Double?
        switch payload {
        case .peripheralLining(let c): mm = c.finishedDepthMM ?? LiningDepthEstimate.millimetres(payload)
        case .furringLining(let c): mm = c.finishedDepthMM ?? LiningDepthEstimate.millimetres(payload)
        case .bondedLining(let c): mm = c.hasReveal ? Double(c.revealMM) : nil
        default: mm = nil
        }
        guard let mm, mm.isFinite, mm > 0, mm <= 1000 else { return nil }
        return mm / 1000
    }
    static func depths(works: [WorkItem], surveyID: UUID, checkpointID: UUID) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for work in works where work.type.category == .wallInsulation {
            guard let depth = depth(work.payload) else { continue }
            for component in work.components {
                guard let source = component.surveySource, source.surveyID == surveyID,
                      source.checkpointID == checkpointID, source.kind == .wall else { continue }
                result[source.surfaceID] = depth
            }
        }
        return result
    }
    /// Edges of a counter-clockwise room, offset toward its usable space. Miter
    /// intersections keep clear dimensions coherent at non-square corners too.
    static func inset(_ walls: [PlaquistoWall], amounts: [Double]) -> [PlaquistoWall]? {
        guard walls.count >= 3, walls.count == amounts.count,
              amounts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { return nil }
        let lines = zip(walls, amounts).map { wall, amount -> (RoomPoint, RoomPoint) in
            let normal = RoomPoint(x: -wall.direction.z, y: 0, z: wall.direction.x)
            return (wall.start + normal * amount, wall.direction)
        }
        var corners: [RoomPoint] = []
        for i in walls.indices {
            let (a,u) = lines[(i+walls.count-1)%walls.count], (b,v) = lines[i]
            let cross = u.x*v.z-u.z*v.x
            if abs(cross) < 1e-8 { corners.append(b); continue }
            let delta = b-a, t = (delta.x*v.z-delta.z*v.x)/cross
            let corner = a+u*t
            guard corner.finite, (corner-walls[i].start).horizontalLength < 10 else { return nil }
            corners.append(corner)
        }
        guard area(corners) > 0.01,
              (try? LayoutGeometry.validate(corners.map { .init(x:$0.x*1000,y:$0.z*1000) })) != nil else { return nil }
        return walls.indices.map { i in
            var wall = walls[i]; wall.start = corners[i]; wall.end = corners[(i+1)%walls.count]
            wall.length.manualValue = (wall.end-wall.start).horizontalLength
            return wall
        }
    }
    static func area(_ ring: [RoomPoint]) -> Double {
        guard ring.count >= 3 else { return 0 }
        return ring.indices.reduce(0.0) { sum,i in
            let a=ring[i], b=ring[(i+1)%ring.count]; return sum+a.x*b.z-b.x*a.z
        } / 2
    }
    static func finishedWalls(in document: PlaquistoRoomDocument, depths: [UUID: Double]) -> [PlaquistoWall] {
        var shell = document.room
        shell.walls.removeAll { SurveyPlanEditing.isDesignedPartition($0, in: document) }
        return ScanEnclosedSpaces.wallsBySpace(in: shell).flatMap { ring in
            inset(ring, amounts: ring.map { depths[$0.id] ?? 0 }) ?? ring
        }
    }
    static func zones(in document: PlaquistoRoomDocument, depths: [UUID: Double]) -> [[PlaquistoWall]] {
        var room = document.room
        let shell = finishedWalls(in: document, depths: depths)
        // Without a closed shell keep the observed walls; do not invent a room.
        room.walls = shell.isEmpty ? room.walls : shell + room.walls.filter { SurveyPlanEditing.isDesignedPartition($0, in: document) }
        room.floors = []
        return ScanEnclosedSpaces.wallsBySpace(in: room).compactMap { ring in
            inset(ring, amounts: ring.map { SurveyPlanEditing.isDesignedPartition($0, in: document) ? ($0.thickness?.effectiveValue ?? 0.072)/2 : 0 })
        }
    }
    /// Dimensions to either side of an axis anchored on a support. The footprint
    /// of an oblique partition occupies more than just its nominal thickness.
    static func clearances(on wall: PlaquistoWall, at point: RoomPoint,
                           direction: RoomPoint?, thickness: Double) -> (Double, Double) {
        let d=point-wall.start
        let along=max(0,min(wall.length.effectiveValue,d.x*wall.direction.x+d.z*wall.direction.z))
        let sine=direction.map { abs($0.x*wall.direction.z-$0.z*wall.direction.x) } ?? 1
        let half=thickness/(2*max(0.05,sine))
        return (max(0,along-half),max(0,wall.length.effectiveValue-along-half))
    }
}

/// Metres, acquisition-neutral. All edits return a validated copy and preserve
/// the original scan. The caller owns Save/Cancel and downstream review warnings.
/// Suggestions only: the capture is never repaired automatically. The initial
/// RoomPlan document remains intact, including non-rectangular wall outlines.
enum SurveyRepair {
    struct Proposal: Identifiable {
        enum Operation { case bridge(PlaquistoWall, closingOpenings: [UUID]), closeOpening(UUID) }
        let id: String
        let title: String
        let operation: Operation
        let highlight: [RoomPoint]
    }
    private struct Endpoint {
        let wall: PlaquistoWall
        let point: RoomPoint
        let outward: RoomPoint
        let top: Double
    }
    private static func canSuggestClosing(_ opening:PlaquistoOpening, in room:PlaquistoRoomModel) -> Bool {
        // Classification and previous manual validation must not prevent an
        // explicit closure. Only geometry/attachment determines eligibility.
        guard room.walls.contains(where:{$0.id==opening.wallID}) else { return false }
        let values=[opening.positionOnWall.effectiveValue,opening.sillHeight.effectiveValue,
                    opening.width.effectiveValue,opening.height.effectiveValue]
        return values.allSatisfy(\.isFinite) && values[2]>0 && values[3]>0
    }
    static func proposals(in document: PlaquistoRoomDocument) -> [Proposal] {
        let walls = document.room.walls
        var result: [Proposal] = []
        for opening in document.room.openings where canSuggestClosing(opening,in:document.room) {
            guard let wall = walls.first(where: { $0.id == opening.wallID }) else { continue }
            let x = opening.positionOnWall.effectiveValue, y = opening.sillHeight.effectiveValue
            let w = opening.width.effectiveValue, h = opening.height.effectiveValue
            let local = [RoomPoint(x:x,y:y,z:0), .init(x:x+w,y:y,z:0), .init(x:x+w,y:y+h,z:0), .init(x:x,y:y+h,z:0)]
            let ring = local.map { wall.start + wall.direction * $0.x + RoomPoint(x:0,y:$0.y,z:0) }
            let wallNumber=(walls.firstIndex(where:{$0.id==wall.id}) ?? 0)+1
            result.append(.init(id:"opening/\(opening.id)", title:"\(opening.kind.title) · \(Int((w*100).rounded())) cm · Mur \(wallNumber)",
                operation:.closeOpening(opening.id), highlight:triangles(ring)))
        }
        var endpoints: [Endpoint] = []
        for wall in walls {
            for end in [false,true] {
                let point = end ? wall.effectiveEnd : wall.start
                // A point already meeting another wall is not a missing segment.
                guard !walls.contains(where: { other in
                    guard other.id != wall.id else { return false }
                    let v = point-other.start
                    let t = min(other.length.effectiveValue,max(0,v.x*other.direction.x+v.z*other.direction.z))
                    let nearest = other.start+other.direction*t
                    return (nearest-point).length < 0.005
                }) else { continue }
                let x = end ? wall.length.effectiveValue : 0
                guard let top = wall.effectiveOutline.filter({ abs($0.x-x)<0.02 }).map(\.y).max(), top > 0 else { continue }
                endpoints.append(.init(wall:wall,point:point,outward:wall.direction*(end ? 1 : -1),top:top))
            }
        }
        for i in endpoints.indices {
            for j in endpoints.indices where j > i {
                let a=endpoints[i], b=endpoints[j], span=b.point-a.point, length=span.horizontalLength
                guard a.wall.id != b.wall.id, length >= 0.005, length <= 100,
                      abs(span.y)<0.02 else { continue }
                let d=span*(1/length)
                // Allow missing sides/corners too, but never extend backwards
                // into the existing walls. Crossing/overlap is checked below.
                guard a.outward.x*d.x+a.outward.z*d.z >= -0.01,
                      b.outward.x*d.x+b.outward.z*d.z <= 0.01 else { continue }
                let source=GeometryProvenance(source:.manual)
                let height=max(a.top,b.top+span.y)
                var wall=PlaquistoWall(start:a.point,end:.init(x:b.point.x,y:a.point.y,z:b.point.z),
                    length:.init(rawValue:length,provenance:source,manuallyValidated:true),
                    height:.init(rawValue:height,provenance:source,manuallyValidated:true),
                    thickness:a.wall.thickness,provenance:source)
                wall.localOutline=[.zero,.init(x:length,y:0,z:0),.init(x:length,y:b.top+span.y,z:0),.init(x:0,y:a.top,z:0)]
                guard (try? SurveyPlanEditing.addingRepairWall(document,wall:wall)) != nil else { continue }
                // An unattached opening sitting in this missing wall is closed
                // by the same explicit operation, not left as a phantom quantity.
                let closing=document.room.openings.filter { opening in
                    guard opening.wallID == nil else { return false }
                    let v=opening.center-a.point
                    let t=v.x*d.x+v.z*d.z, half=opening.width.effectiveValue/2
                    return t-half >= -0.02 && t+half <= length+0.02 && v.y >= 0 && v.y <= height
                        && (opening.center-(a.point+d*t)).horizontalLength < 0.05
                }.map(\.id)
                let ring=wall.localOutline!.map { wall.start+wall.direction*$0.x+RoomPoint(x:0,y:$0.y,z:0) }
                result.append(.init(id:"gap/\(i)/\(j)",title:"Mur interrompu · \(Int((length*100).rounded())) cm",
                    operation:.bridge(wall,closingOpenings:closing),highlight:triangles(ring)))
            }
        }
        return result
    }
    private static func triangles(_ ring: [RoomPoint]) -> [RoomPoint] {
        [ring[0],ring[1],ring[2],ring[0],ring[2],ring[3]]
    }
    static func applying(_ proposals: [Proposal], to document: PlaquistoRoomDocument) throws -> PlaquistoRoomDocument {
        var result=document
        for proposal in proposals {
            switch proposal.operation {
            case .closeOpening(let id):
                guard let opening=result.room.openings.first(where:{$0.id==id}), canSuggestClosing(opening,in:result.room) else { throw RoomModelError.invalidGeometry }
                result=try SurveyPlanEditing.removingOpening(result,id:id)
            case .bridge(let wall,let closing):
                // Recheck conflicts against the other selected repairs too.
                result=try SurveyPlanEditing.addingRepairWall(result,wall:wall)
                for id in closing { result=try SurveyPlanEditing.removingOpening(result,id:id) }
            }
        }
        try result.validate()
        return result
    }
}

enum SurveyPlanEditing {
    /// A validated user-approved repair, not a new partition. Unlike partition
    /// drawing this accepts millimetric gaps and preserves the supplied outline.
    static func addingRepairWall(_ document:PlaquistoRoomDocument,wall:PlaquistoWall) throws -> PlaquistoRoomDocument {
        guard wall.start.finite, wall.effectiveEnd.finite,
              wall.length.effectiveValue >= 0.005, wall.length.effectiveValue <= 100,
              wall.height.effectiveValue > 0, wall.height.effectiveValue <= 100 else { throw Failure.invalidSize }
        guard !document.room.walls.contains(where:{ conflicts(wall,$0) }) else { throw Failure.crossingWalls }
        try LayoutGeometry.validate(wall.effectiveOutline.map { .init(x:$0.x*1000,y:$0.y*1000) })
        var result=document
        result.room.walls.append(wall)
        result.wallWorkIntents=(result.wallWorkIntents ?? []) + [.init(wallID:wall.id,use:.existingWall)]
        try result.validate()
        return result
    }
    /// Explicit contour replacement, never an automatic cleanup of RoomPlan.
    /// The caller previews the returned copy and confirms any removed openings.
    static func replacingContour(_ document:PlaquistoRoomDocument, walls:[PlaquistoWall],
                                 contour:[RoomPoint]) throws -> PlaquistoRoomDocument {
        try LayoutGeometry.validate(contour.map { .init(x:$0.x*1000,y:$0.z*1000) })
        let ids=Set(walls.map(\.id))
        guard !ids.isEmpty else { throw Failure.invalidSize }
        // A graph edge can be only a fragment of a shared scanned wall. Replacing
        // that entire wall would damage the neighboring room: refuse that case.
        for edge in walls {
            if let source=document.room.walls.first(where:{$0.id==edge.id}),
               abs(source.length.effectiveValue-edge.length.effectiveValue)>0.02 { throw Failure.sharedContour }
        }
        let source=GeometryProvenance(source:.manual)
        var result=document, used=Set<UUID>(), replacement:[PlaquistoWall]=[]
        for i in contour.indices {
            let a=contour[i], b=contour[(i+1)%contour.count], length=(b-a).horizontalLength
            guard length >= 0.1 else { throw Failure.invalidSize }
            let direction=(b-a)*(1/length)
            // Reuse only truly corresponding edges; topology changes must not
            // silently attach a saved layout/window to a different wall.
            let old=walls.filter { !used.contains($0.id) }.min {
                (($0.start-a).horizontalLength+($0.effectiveEnd-b).horizontalLength) < (($1.start-a).horizontalLength+($1.effectiveEnd-b).horizontalLength)
            }.flatMap { wall -> PlaquistoWall? in
                let aligned=abs(wall.direction.x*direction.z-wall.direction.z*direction.x)<0.05
                let near=min((wall.start-a).horizontalLength+(wall.effectiveEnd-b).horizontalLength,
                             (wall.start-b).horizontalLength+(wall.effectiveEnd-a).horizontalLength)<0.4
                return aligned && near ? document.room.walls.first(where:{$0.id==wall.id}) : nil
            }
            if var old {
                used.insert(old.id)
                if old.direction.x*direction.x+old.direction.z*direction.z < 0 {
                    old.start=b; old.end=a
                } else { old.start=a; old.end=b }
                old.length.manualValue=length; old.length.manuallyValidated=true
                replacement.append(old)
            } else {
                replacement.append(.init(start:a,end:b,length:.init(rawValue:length,provenance:source),
                    height:.init(rawValue:suggestedHeight(in:document.room,at:a),provenance:source),provenance:source))
            }
        }
        let untouched=document.room.walls.filter { !ids.contains($0.id) }
        guard !replacement.contains(where:{ edited in untouched.contains { conflicts(edited,$0) } }) else { throw Failure.crossingWalls }
        result.room.walls.removeAll { ids.contains($0.id) }; result.room.walls += replacement
        result.room.openings=result.room.openings.compactMap { opening in
            guard let wallID=opening.wallID, ids.contains(wallID) else { return opening }
            guard let wall=replacement.first(where:{$0.id==opening.wallID}),
                  (try? validateOpening(opening,wall:wall)) != nil else { return nil }
            var next=opening; next.center=openingCenter(opening,wall:wall); return next
        }
        let openingIDs=Set(result.room.openings.map(\.id))
        for i in result.room.walls.indices { result.room.walls[i].openingIDs.removeAll { !openingIDs.contains($0) } }
        result.wallWorkIntents?.removeAll { ids.contains($0.wallID) && !used.contains($0.wallID) }
        // Replace matching floor footprints only; unrelated levels/rooms survive.
        let oldRing=walls.map(\.start)
        for i in result.room.floors.indices {
            let floor=result.room.floors[i]
            if floor.boundaries.count == 1, let ring=floor.boundaries.first,
               ring.allSatisfy({ point in oldRing.contains { ($0-point).horizontalLength<0.03 } }) {
                result.room.floors[i].boundaries=[contour]
            }
        }
        try result.validate(); return result
    }
    enum Failure: Error, LocalizedError {
        case missingWall, invalidSize, openingOutside, overlappingOpening, crossingWalls, incompatibleMerge, sharedContour, scannedWallRemoval
        var errorDescription: String? {
            switch self {
            case .scannedWallRemoval: "Seules les cloisons ajoutées peuvent être supprimées ici. Pour corriger un mur scanné, modifiez le contour de la pièce."
            case .sharedContour: "Ce contour utilise une partie d’un mur partagé avec une autre pièce. Corrigez ce mur avec ses poignées pour conserver la pièce voisine."
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
    static func isDesignedPartition(_ wall: PlaquistoWall, in document: PlaquistoRoomDocument) -> Bool {
        wall.provenance.source == .manual && document.wallWorkIntents?.contains(where: {
            $0.wallID == wall.id && $0.use == .partition
        }) == true
    }

    /// Cheap gesture preview. Uses exactly the same junction policy as commit,
    /// but leaves validation and persistence to the end of the gesture.
    static func previewWalls(_ document: PlaquistoRoomDocument, wall: PlaquistoWall,
                             start: RoomPoint, end: RoomPoint) -> [PlaquistoWall] {
        document.room.walls.map { existing in
            var preview = existing
            preview.start = existing.id == wall.id ? start : movedJunction(existing.start,
                wall:wall, start:start, end:end, document:document)
            preview.end = existing.id == wall.id ? end : movedJunction(existing.effectiveEnd,
                wall:wall, start:start, end:end, document:document)
            let delta = preview.end-preview.start
            preview.length.manualValue = hypot(delta.x,delta.z)
            preview.length.manuallyValidated = true
            return preview
        }
    }

    private static func movedJunction(_ point: RoomPoint, wall: PlaquistoWall,
                                      start: RoomPoint, end: RoomPoint,
                                      document: PlaquistoRoomDocument) -> RoomPoint {
        // A projected partition never pulls the scanned shell along with it.
        guard !isDesignedPartition(wall, in:document) else { return point }
        if (point-wall.start).length < 0.03 { return start }
        if (point-wall.effectiveEnd).length < 0.03 { return end }
        return point
    }

    static func changingWall(_ document: PlaquistoRoomDocument, id: UUID,
                             start: RoomPoint, end: RoomPoint, height: Double,
                             preserveOpeningLocations: Bool = false) throws -> PlaquistoRoomDocument {
        guard let old = document.room.walls.first(where: { $0.id == id }) else { throw Failure.missingWall }
        guard start.finite, end.finite, height.isFinite, height > 0, height <= 100,
              hypot(end.x-start.x, end.z-start.z) >= 0.1 else { throw Failure.invalidSize }
        var result = document
        let a = RoomPoint(x: start.x, y: old.start.y, z: start.z)
        let b = RoomPoint(x: end.x, y: old.end.y, z: end.z)
        func moved(_ p: RoomPoint) -> RoomPoint {
            movedJunction(p, wall:old, start:a, end:b, document:document)
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
            if preserveOpeningLocations, wallID == id {
                let delta = document.room.openings[i].center-wall.start
                let position = delta.x*wall.direction.x + delta.z*wall.direction.z-result.room.openings[i].width.effectiveValue/2
                result.room.openings[i].positionOnWall.manualValue = abs(position) < 1e-8 ? 0 : position
                result.room.openings[i].positionOnWall.manuallyValidated = true
            }
            try validateOpening(result.room.openings[i], wall: wall)
            result.room.openings[i].center = openingCenter(result.room.openings[i], wall: wall)
        }
        // Refuse newly introduced crossings, while leaving pre-existing scan
        // imperfections editable. T-junctions at segment endpoints are allowed.
        for i in result.room.walls.indices {
            for j in result.room.walls.indices where j > i {
                if conflicts(result.room.walls[i], result.room.walls[j]),
                   !conflicts(document.room.walls[i], document.room.walls[j]) { throw Failure.crossingWalls }
            }
        }
        // Ceiling resizing is deliberately not implicit: the editor exposes an
        // explicit ceiling action, and the caller warns that it needs review.
        try result.validate(); return result
    }

    static func addingPartition(_ document: PlaquistoRoomDocument, start: RoomPoint,
                                end: RoomPoint, height: Double, thickness: Double = 0.072) throws -> PlaquistoRoomDocument {
        guard start.finite, end.finite, height.isFinite, height > 0, height <= 100,
              thickness.isFinite, thickness > 0, thickness <= 1,
              hypot(end.x-start.x, end.z-start.z) >= 0.1 else { throw Failure.invalidSize }
        var result = document
        let source = GeometryProvenance(source: .manual)
        let wall = PlaquistoWall(start: start, end: .init(x: end.x, y: start.y, z: end.z),
            length: .init(rawValue: hypot(end.x-start.x, end.z-start.z), provenance: source, manuallyValidated: true),
            height: .init(rawValue: height, provenance: source, manuallyValidated: true),
            thickness: .init(rawValue: thickness, provenance: source, manuallyValidated: true), provenance: source)
        guard !document.room.walls.contains(where: { conflicts(wall,$0) }) else { throw Failure.crossingWalls }
        result.room.walls.append(wall)
        result.wallWorkIntents = (result.wallWorkIntents ?? []) + [.init(wallID: wall.id, use: .partition)]
        try result.validate(); return result
    }

    static func addingDoor(_ document: PlaquistoRoomDocument, wallID: UUID,
                           width: Double, height: Double, position: Double) throws -> PlaquistoRoomDocument {
        guard width.isFinite, width > 0, height.isFinite, height > 0 else { throw Failure.invalidSize }
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

    /// Remove only a designed partition and its openings. Roof geometry and the
    /// original scan are deliberately retained; deleting a divider is not a roof merge.
    static func removingPartition(_ document: PlaquistoRoomDocument, id: UUID) throws -> PlaquistoRoomDocument {
        guard let wall=document.room.walls.first(where: { $0.id == id }) else { throw Failure.missingWall }
        guard isDesignedPartition(wall,in:document) else { throw Failure.scannedWallRemoval }
        var result=document
        let openings=Set(result.room.openings.filter { $0.wallID == id }.map(\.id))
        result.room.walls.removeAll { $0.id == id }
        result.room.openings.removeAll { openings.contains($0.id) }
        for i in result.room.walls.indices { result.room.walls[i].openingIDs.removeAll { openings.contains($0) } }
        result.wallWorkIntents?.removeAll { $0.wallID == id }
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
    private static func conflicts(_ a: PlaquistoWall, _ b: PlaquistoWall) -> Bool {
        guard abs(a.start.y-b.start.y) < 0.1 else { return false }
        func side(_ p: RoomPoint, _ q: RoomPoint, _ r: RoomPoint) -> Double {
            (q.x-p.x)*(r.z-p.z)-(q.z-p.z)*(r.x-p.x)
        }
        let direction = a.direction
        if abs(side(a.start,a.effectiveEnd,b.start))/max(0.1,a.length.effectiveValue) < 0.001,
           abs(side(a.start,a.effectiveEnd,b.effectiveEnd))/max(0.1,a.length.effectiveValue) < 0.001 {
            let p = b.start-a.start, q = b.effectiveEnd-a.start
            let x = p.x*direction.x+p.z*direction.z, y = q.x*direction.x+q.z*direction.z
            return min(a.length.effectiveValue,max(x,y))-max(0,min(x,y)) > 0.001
        }
        return side(a.start,a.effectiveEnd,b.start)*side(a.start,a.effectiveEnd,b.effectiveEnd) < -1e-10 &&
            side(b.start,b.effectiveEnd,a.start)*side(b.start,b.effectiveEnd,a.effectiveEnd) < -1e-10
    }
}

/// Screen-tolerance snapping in the survey's own coordinate frame. No world-axis
/// rounding and no mutation of the captured walls. Endpoints win over angles.
enum SurveyPlanSnapping {
    struct Result {
        var point: RoomPoint
        var key: String? = nil
        var title: String? = nil
        var guide: RoomPoint? = nil
    }
    static func snap(_ point: RoomPoint, anchor: RoomPoint? = nil, walls: [PlaquistoWall],
                     tolerance: Double, latched: String? = nil) -> Result {
        let walls = walls.filter { abs($0.start.y-point.y) < 0.1 }
        func distance(_ a: RoomPoint, _ b: RoomPoint) -> Double { hypot(a.x-b.x,a.z-b.z) }
        func threshold(_ key: String) -> Double { tolerance * (key == latched ? 1.5 : 1) }
        func projection(_ p: RoomPoint, _ w: PlaquistoWall) -> RoomPoint {
            let d = p-w.start, v = w.direction
            return w.start+v*min(w.length.effectiveValue,max(0,d.x*v.x+d.z*v.z))
        }
        var ends: [(point:RoomPoint,key:String)] = []
        for wall in walls {
            ends += [(wall.start,"\(wall.id)/start"),(wall.effectiveEnd,"\(wall.id)/end")]
        }
        if let endpoint = ends.filter({ distance(point,$0.point) <= threshold($0.key) })
            .min(by: { distance(point,$0.point) < distance(point,$1.point) }) {
            return .init(point:.init(x:endpoint.point.x,y:point.y,z:endpoint.point.z),key:endpoint.key,title:"Extrémité")
        }
        if let anchor, distance(anchor,point) >= 0.1,
           let reference = walls.min(by: { distance(anchor,projection(anchor,$0)) < distance(anchor,projection(anchor,$1)) }) {
            let along = reference.direction
            let directions = [along,RoomPoint(x:-along.z,y:0,z:along.x)]
            for (i,axis) in directions.enumerated() {
                let key = "\(reference.id)/axis/\(i)", delta = point-anchor
                let projected = anchor+axis*(delta.x*axis.x+delta.z*axis.z)
                guard distance(point,projected) <= threshold(key) else { continue }
                // If the right-angle guide reaches a nearby wall, satisfy both
                // constraints exactly instead of snapping to one then losing it.
                for target in walls {
                    let v = target.direction, d = target.start-anchor
                    let denominator = axis.x*v.z-axis.z*v.x
                    guard abs(denominator) > 1e-8 else { continue }
                    let t = (d.x*v.z-d.z*v.x)/denominator
                    let u = (d.x*axis.z-d.z*axis.x)/denominator
                    let intersection = anchor+axis*t
                    if u >= 0 && u <= target.length.effectiveValue,
                       distance(intersection,point) <= threshold(key) {
                        return .init(point:intersection,key:key,title:i == 0 ? "Parallèle · mur" : "90° · mur",guide:anchor)
                    }
                }
                return .init(point:projected,key:key,title:i == 0 ? "Parallèle" : "90°",guide:anchor)
            }
        }
        if let wall = walls.filter({ distance(point,projection(point,$0)) <= threshold("\($0.id)/wall") })
            .min(by: { distance(point,projection(point,$0)) < distance(point,projection(point,$1)) }) {
            let p = projection(point,wall)
            return .init(point:.init(x:p.x,y:point.y,z:p.z),key:"\(wall.id)/wall",title:"Sur le mur")
        }
        return .init(point:point)
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
