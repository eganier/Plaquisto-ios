import Foundation
import RoomPlan
import simd

// Capture boundary. One instance per acquisition; source IDs are only lookup keys.
final class RoomPlanAdapter {
    private var ids: [UUID: UUID] = [:]
    private let roomID = UUID()
    private let createdAt = Date()
    private func id(_ source: UUID) -> UUID {
        if let existing = ids[source] { return existing }
        let created = UUID(); ids[source] = created; return created
    }
    private func point(_ surface: CapturedRoom.Surface, x: Float, y: Float, z: Float = 0) -> RoomPoint {
        let p = surface.transform * SIMD4(x,y,z,1)
        return .init(x:Double(p.x),y:Double(p.y),z:Double(p.z))
    }
    private func provenance(_ surface: CapturedRoom.Surface) -> GeometryProvenance {
        let confidence: String
        switch surface.confidence { case .high: confidence = "high"; case .medium: confidence = "medium"; case .low: confidence = "low"; @unknown default: confidence = "unknown" }
        return .init(source:.roomPlan,sourceIdentifier:surface.identifier.uuidString,confidenceLabel:confidence)
    }
    func convert(_ captured: CapturedRoom, preserving working: PlaquistoRoomModel? = nil) -> PlaquistoRoomModel {
        // Recover independent IDs from a working model when adapting an update.
        if let working {
            for w in working.walls { if let key = w.provenance.sourceIdentifier.flatMap(UUID.init(uuidString:)) { ids[key] = w.id } }
            for o in working.openings { if let key = o.provenance.sourceIdentifier.flatMap(UUID.init(uuidString:)) { ids[key] = o.id } }
            for f in working.floors { if let key = f.provenance.sourceIdentifier.flatMap(UUID.init(uuidString:)) { ids[key] = f.id } }
        }
        var result = PlaquistoRoomModel(id:working?.id ?? roomID, name:working?.name,
                                       metadata:.init(createdAt:working?.metadata.createdAt ?? createdAt,source:.roomPlan,sourceObjectCount:captured.objects.count))
        result.ceilings = working?.ceilings ?? []; result.slopes = working?.slopes ?? []
        result.walls = captured.walls.map { s in
            let source = provenance(s), domainID = id(s.identifier)
            var wall = PlaquistoWall(id:domainID,
                start:point(s,x:-s.dimensions.x/2,y:-s.dimensions.y/2), end:point(s,x:s.dimensions.x/2,y:-s.dimensions.y/2),
                length:.init(rawValue:Double(s.dimensions.x),provenance:source), height:.init(rawValue:Double(s.dimensions.y),provenance:source), provenance:source)
            if s.dimensions.z > 0 { wall.thickness = .init(rawValue:Double(s.dimensions.z),provenance:source) }
            if let old = working?.walls.first(where: { $0.id == domainID }) {
                wall.length = wall.length.preservingCorrection(from:old.length)
                wall.height = wall.height.preservingCorrection(from:old.height)
                wall.thickness = wall.thickness?.preservingCorrection(from:old.thickness) ?? old.thickness
            }
            return wall
        }
        let openings = captured.doors.map { ($0,RoomOpeningKind.door) } + captured.windows.map { ($0,RoomOpeningKind.window) } + captured.openings.map { ($0,RoomOpeningKind.passage) }
        result.openings = openings.map { s, kind in
            let center = point(s,x:0,y:0), source = provenance(s)
            let direct = s.parentIdentifier.flatMap { parent in result.walls.first { $0.provenance.sourceIdentifier == parent.uuidString } }
            let axis = point(s,x:1,y:0)-center
            let candidates = result.walls.compactMap { w -> (PlaquistoWall,Double)? in
                let delta = center-w.start, d = w.direction
                let along = delta.x*d.x+delta.z*d.z
                let distance = abs(delta.x*d.z-delta.z*d.x)
                guard distance < 0.2, abs(axis.x*d.x+axis.z*d.z) > 0.95,
                      along >= -0.1, along <= w.length.rawValue+0.1 else { return nil }
                return (w,distance)
            }.sorted { $0.1 < $1.1 }
            let fallback = candidates.count == 1 || (candidates.count > 1 && candidates[1].1-candidates[0].1 > 0.05) ? candidates.first?.0 : nil
            let wall = direct ?? fallback
            let delta = center-(wall?.start ?? .zero), d = wall?.direction ?? .zero
            var opening = PlaquistoOpening(id:id(s.identifier),wallID:wall?.id,kind:kind,center:center,
                width:.init(rawValue:Double(s.dimensions.x),provenance:source),height:.init(rawValue:Double(s.dimensions.y),provenance:source),
                sillHeight:.init(rawValue:max(0,center.y-Double(s.dimensions.y)/2-(wall?.start.y ?? 0)),provenance:source),
                positionOnWall:.init(rawValue:delta.x*d.x+delta.z*d.z-Double(s.dimensions.x)/2,provenance:source),provenance:source)
            if let old = working?.openings.first(where: { $0.id == opening.id }) {
                opening.width = opening.width.preservingCorrection(from:old.width)
                opening.height = opening.height.preservingCorrection(from:old.height)
                opening.sillHeight = opening.sillHeight.preservingCorrection(from:old.sillHeight)
                opening.positionOnWall = opening.positionOnWall.preservingCorrection(from:old.positionOnWall)
            }
            return opening
        }
        for i in result.walls.indices { result.walls[i].openingIDs = result.openings.filter { $0.wallID == result.walls[i].id }.map(\.id) }
        result.floors = captured.floors.map { s in
            let corners = s.polygonCorners.isEmpty
                ? [SIMD3(-s.dimensions.x/2,-s.dimensions.y/2,0),SIMD3(s.dimensions.x/2,-s.dimensions.y/2,0),SIMD3(s.dimensions.x/2,s.dimensions.y/2,0),SIMD3(-s.dimensions.x/2,s.dimensions.y/2,0)] : s.polygonCorners
            return .init(id:id(s.identifier),boundaries:[corners.map { point(s,x:$0.x,y:$0.y,z:$0.z) }],referenceElevation:Double(s.transform.columns.3.y),provenance:provenance(s))
        }
        return result
    }
}
