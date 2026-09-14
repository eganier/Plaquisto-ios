import Foundation
import simd

@main enum PlaquistoRoomModelChecks {
    static let source = GeometryProvenance(source: .manual)
    static func measure(_ n: Double) -> RoomMeasurement { .init(rawValue:n,provenance:source) }
    static func p(_ x:Double,_ y:Double,_ z:Double) -> RoomPoint { .init(x:x,y:y,z:z) }
    static func close(_ a:Double,_ b:Double) { precondition(abs(a-b)<1e-7, "\(a) != \(b)") }
    static func rejected(_ body: () throws -> Void) { do { try body(); fatalError("Invalid input accepted") } catch {} }
    static func main() throws {
        var wall = PlaquistoWall(start:p(0,0,0),end:p(4,0,0),length:measure(4),height:measure(2),provenance:source)
        var room = PlaquistoRoomModel(walls:[wall],metadata:.init(createdAt:Date(timeIntervalSince1970:0),source:.manual))
        close(PlaquistoWallGeometry.analyze(wall:wall,room:room).gross,8)
        let left = PlaquistoSlope(plane:.init(a:0.5,b:0,c:2),boundaries:[[p(0,2,0),p(2,3,0),p(2,3,3),p(0,2,3)]],provenance:source,accepted:true)
        let right = PlaquistoSlope(plane:.init(a:-0.5,b:0,c:4),boundaries:[[p(2,3,0),p(4,2,0),p(4,2,3),p(2,3,3)]],provenance:source,accepted:true)
        room.slopes = [left,right]
        room.ceilings = [.init(slopeIDs:room.slopes.map(\.id),provenance:source)]
        let gable = PlaquistoWallGeometry.analyze(wall:wall,room:room)
        close(gable.gross,10); precondition(gable.strips.count == 2)
        precondition(PlaquistoWallGeometry.triangles(wall:wall,room:room).count == 12)
        func opening(_ x:Double,_ w:Double,_ h:Double,_ sill:Double = 0) -> PlaquistoOpening {
            .init(wallID:wall.id,kind:.window,center:p(x+w/2,sill+h/2,0),width:measure(w),height:measure(h),sillHeight:measure(sill),positionOnWall:measure(x),provenance:source)
        }
        room.openings = [opening(1,2,2),opening(2,2,2)]
        room.walls[0].openingIDs = room.openings.map(\.id)
        close(PlaquistoWallGeometry.analyze(wall:wall,room:room).net,4) // union, not 8 m² deduction
        room.openings = [opening(-1,6,5)] // clipped to full gable
        room.walls[0].openingIDs = room.openings.map(\.id)
        close(PlaquistoWallGeometry.analyze(wall:wall,room:room).net,0)
        room.openings = [opening(0,4,1,2)] // triangle above eaves
        room.walls[0].openingIDs = room.openings.map(\.id)
        close(PlaquistoWallGeometry.analyze(wall:wall,room:room).openingArea,2)
        room.openings[0].wallID = nil; room.walls[0].openingIDs = []
        close(PlaquistoWallGeometry.analyze(wall:wall,room:room).net,10)
        room.slopes[0].accepted = false; room.slopes[1].accepted = false
        close(PlaquistoWallGeometry.analyze(wall:wall,room:room).gross,8)
        room.slopes[0].accepted = true; room.slopes[1].accepted = true
        let initial = room
        var doc = PlaquistoRoomDocument(room:room)
        try wall.length.correct(4.31); wall.length.updateScan(4.28,provenance:.init(source:.roomPlan))
        close(wall.length.effectiveValue,4.31); close(wall.length.rawValue,4.28)
        try wall.height.correct(2.5)
        close(PlaquistoWallGeometry.analyze(wall:wall,room:room).gross,4.31*2.5)
        doc.room.walls[0] = wall
        let data = try doc.encoded(), decoded = try PlaquistoRoomDocument.decode(data)
        precondition(decoded == doc); precondition(decoded.initialRoom == initial)
        precondition(decoded.room.walls[0].id == wall.id)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("room.json")
        defer { try? FileManager.default.removeItem(at:dir) }
        try PlaquistoRoomStore.save(doc,to:url)
        let loaded = try PlaquistoRoomStore.load(from:url)
        precondition(loaded == doc)
        var invalid = doc; invalid.schemaVersion = 2
        rejected { _ = try invalid.encoded() }
        let future = String(decoding:data,as:UTF8.self).replacingOccurrences(of:"\"schemaVersion\" : 1",with:"\"schemaVersion\" : 99")
        rejected { _ = try PlaquistoRoomDocument.decode(Data(future.utf8)) }
        rejected { try wall.height.correct(-1) }
        invalid = doc; invalid.room.walls.append(invalid.room.walls[0])
        rejected { try invalid.validate() }
        invalid = doc; invalid.room.openings[0].wallID = UUID()
        rejected { try invalid.validate() }
        invalid = doc; invalid.room.walls[0].length.rawValue = .nan
        rejected { try invalid.validate() }
        // Boundary extraction removes internal triangulation edges, including concave L.
        let vertices:[SIMD3<Double>] = [.init(0,2,0),.init(2,2,0),.init(2,2,1),
            .init(0,2,0),.init(2,2,1),.init(1,2,1),
            .init(0,2,0),.init(1,2,1),.init(1,2,2),
            .init(0,2,0),.init(1,2,2),.init(0,2,2)]
        let surface = ScannerCeilingReconstruction.Surface(vertices:vertices,area:3,slopeDegrees:0,observedSupportArea:2,fitError:0)
        ScannerRoomBridge.apply(surface,to:&room,accepted:true,manuallyValidated:true)
        precondition(room.slopes.count == 1 && room.slopes[0].boundaries.count == 1)
        let loop = room.slopes[0].boundaries[0]
        let area = abs(loop.indices.reduce(0.0) { sum,i in let b=loop[(i+1)%loop.count]; return sum+loop[i].x*b.z-b.x*loop[i].z })/2
        close(area,3); close(room.slopes[0].plane.height(x:1,z:1),2)
        precondition(!PlaquistoWallGeometry.contains(p(1.5,2,1.5),polygon:loop))
        // Exercise the bridge on actual two-pan reconstruction, not hand-authored planes.
        typealias Engine = ScannerCeilingReconstruction
        let outline:[SIMD2<Double>] = [.init(0,0),.init(4,0),.init(4,3),.init(0,3)]
        let walls = outline.indices.map { Engine.Wall(start:outline[$0],end:outline[($0+1)%4]) }
        var mesh:[Engine.Triangle] = []
        for x in 0..<20 {
            for z in 0..<15 {
                func v(_ i:Int,_ j:Int) -> SIMD3<Double> {
                    let xx=Double(i)*0.2
                    return .init(xx,3-abs(xx-2)*0.5,Double(j)*0.2)
                }
                let a=v(x,z),b=v(x+1,z),c=v(x+1,z+1),d=v(x,z+1)
                mesh += [.init(a:a,b:b,c:c),.init(a:a,b:c,c:d)]
            }
        }
        let roof = try Engine.reconstruct(walls:walls,triangles:mesh).get()
        ScannerRoomBridge.apply(roof,to:&room,accepted:true,manuallyValidated:true)
        precondition(room.slopes.count == 2)
        close(PlaquistoWallGeometry.analyze(wall:initial.walls[0],room:room).gross,10)
        _ = try PlaquistoRoomDocument(room:room).encoded()
        print("PASS: neutral schema, JSON persistence, manual priority, wall areas, openings union/clipping, gable, L bridge")
    }
}
