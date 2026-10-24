import Foundation

/// Manual floor coordinates are millimetres; the shared survey model is metres,
/// Y up. Explicit height constraints describe ONE plane, never a triangulated roof.
enum ManualRoomModel {
    enum Failure: Error, LocalizedError {
        case height, incompatibleHeights
        var errorDescription: String? {
            switch self {
            case .height: return "Les hauteurs doivent rester comprises entre 20 cm et 20 m sur tout le contour."
            case .incompatibleHeights: return "Ces hauteurs ne forment pas un seul rampant. Libérez une hauteur déjà renseignée, ou modifiez les plafonds après la création."
            }
        }
    }
    static func floorPoints(_ contour: [LayoutPoint]) -> [RoomPoint] {
        contour.map { .init(x: $0.x / 1000, y: 0, z: -$0.y / 1000) }
    }
    static func plane(contour: [LayoutPoint], commonHeight: Double, constraints: [Int: Double]) throws -> RoomPlane {
        try LayoutGeometry.validate(contour)
        guard commonHeight.isFinite, (0.2...20).contains(commonHeight),
              constraints.allSatisfy({ contour.indices.contains($0.key) && $0.value.isFinite && (0.2...20).contains($0.value) }) else {
            throw Failure.height
        }
        let points = floorPoints(contour), indices = constraints.keys.sorted()
        guard let first = indices.first, let height = constraints[first] else {
            return .init(a: 0, b: 0, c: commonHeight)
        }
        let origin = points[first]
        let rows = indices.dropFirst().map { index in
            (x: points[index].x - origin.x, z: points[index].z - origin.z, h: constraints[index]! - height)
        }
        var a = 0.0, b = 0.0
        // Farthest constraint is numerically more stable than an adjacent tiny edge.
        if let base = rows.max(by: { $0.x*$0.x+$0.z*$0.z < $1.x*$1.x+$1.z*$1.z }) {
            let squared = base.x*base.x + base.z*base.z
            guard squared > 1e-12 else { throw Failure.incompatibleHeights }
            a = base.h*base.x/squared; b = base.h*base.z/squared
            if let other = rows.max(by: { abs(base.x*$0.z-base.z*$0.x) < abs(base.x*$1.z-base.z*$1.x) }) {
                let determinant = base.x*other.z-base.z*other.x
                if abs(determinant) > 1e-8 {
                    a = (base.h*other.z-base.z*other.h)/determinant
                    b = (base.x*other.h-base.h*other.x)/determinant
                }
            }
        }
        let plane = RoomPlane(a: a, b: b, c: height-a*origin.x-b*origin.z)
        guard constraints.allSatisfy({ abs(plane.height(x: points[$0.key].x, z: points[$0.key].z)-$0.value) < 0.00001 }) else {
            throw Failure.incompatibleHeights
        }
        guard points.allSatisfy({ let h = plane.height(x: $0.x, z: $0.z); return h.isFinite && (0.2...20).contains(h) }) else {
            throw Failure.height
        }
        return plane
    }
    static func room(contour: [LayoutPoint], commonHeight: Double, constraints: [Int: Double], name: String) throws -> PlaquistoRoomModel {
        let roof = try plane(contour: contour, commonHeight: commonHeight, constraints: constraints)
        let floor = floorPoints(contour), provenance = GeometryProvenance(source: .manual)
        let ceiling = floor.map { RoomPoint(x: $0.x, y: roof.height(x: $0.x, z: $0.z), z: $0.z) }
        func measure(_ value: Double) -> RoomMeasurement {
            .init(rawValue: value, provenance: provenance, manualValue: value, manuallyValidated: true)
        }
        var room = PlaquistoRoomModel(name: name, metadata: .init(source: .manual))
        room.walls = floor.indices.map { i in
            let j = (i+1)%floor.count, length = (floor[j]-floor[i]).length
            return PlaquistoWall(start: floor[i], end: floor[j], length: measure(length),
                height: measure(max(ceiling[i].y, ceiling[j].y)), provenance: provenance,
                localOutline: [.zero, .init(x: length, y: 0, z: 0), .init(x: length, y: ceiling[j].y, z: 0), .init(x: 0, y: ceiling[i].y, z: 0)])
        }
        let slope = PlaquistoSlope(plane: roof, boundaries: [ceiling], provenance: provenance, accepted: true, manuallyValidated: true)
        room.slopes = [slope]
        let heights = ceiling.map(\.y)
        let settings = CeilingEstimateSettings(shape: roof.slopeDegrees < 1e-6 ? .flat : .singleSlope,
            lowHeight: heights.min()!, highHeight: heights.max()!, azimuth: atan2(roof.b, roof.a),
            riseIsEstimated: false, extendsWalls: true)
        room.ceilings = [.init(slopeIDs: [slope.id], provenance: provenance, estimateSettings: settings, footprint: floor, floorElevation: 0)]
        room.floors = [.init(boundaries: [floor], referenceElevation: 0, provenance: provenance)]
        try PlaquistoRoomDocument(room: room).validate()
        return room
    }
    static func campaign(room: PlaquistoRoomModel) throws -> ScanCampaignDraft {
        var draft = ScanCampaignDraft()
        draft.chunks = [.init(referenceGroupID: UUID(), name: room.name ?? "Ma pièce", usages: [.unidentified],
            document: .init(room: room), needsReview: false, keepAfterReview: true)]
        draft.isComplete = true
        draft.assemblyVerified = true
        try draft.validate()
        return draft
    }
}
