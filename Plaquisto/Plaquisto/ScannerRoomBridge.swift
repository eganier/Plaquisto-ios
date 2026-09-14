import Foundation
import simd

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
    static func boundaries(_ vertices: [SIMD3<Double>]) -> [[RoomPoint]] {
        func key(_ p: SIMD3<Double>) -> String { "\(Int64((p.x*100000).rounded()))/\(Int64((p.y*100000).rounded()))/\(Int64((p.z*100000).rounded()))" }
        var edges: [String:(String,String)] = [:], counts: [String:Int] = [:], points: [String:RoomPoint] = [:]
        for i in stride(from:0,to:vertices.count-2,by:3) {
            for j in 0..<3 {
                let a = vertices[i+j], b = vertices[i+(j+1)%3], ka = key(a), kb = key(b)
                guard ka != kb else { continue }
                let edge = [ka,kb].sorted().joined(separator:"|")
                counts[edge,default:0] += 1; edges[edge] = (ka,kb)
                points[ka] = .init(x:a.x,y:a.y,z:a.z); points[kb] = .init(x:b.x,y:b.y,z:b.z)
            }
        }
        var remaining = edges.filter { counts[$0.key] == 1 }.map(\.value)
        var loops: [[RoomPoint]] = []
        while !remaining.isEmpty {
            let first = remaining.removeFirst(); var path = [first.0]; var end = first.1
            while end != first.0, let next = remaining.firstIndex(where: { $0.0 == end }) {
                path.append(end); end = remaining.remove(at:next).1
            }
            if end == first.0, path.count >= 3 { loops.append(path.compactMap { points[$0] }) }
        }
        return loops
    }
}
