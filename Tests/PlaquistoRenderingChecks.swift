import Foundation

@main enum PlaquistoRenderingChecks {
    static func area(_ points:[RoomPoint]) -> Double {
        stride(from:0,to:points.count,by:3).reduce(0) { total,i in
            let u=points[i+1]-points[i],v=points[i+2]-points[i]
            let cross=RoomPoint(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
            return total+cross.length/2
        }
    }
    static func verify(_ room:PlaquistoRoomModel) {
        for wall in room.walls {
            let net=PlaquistoWallGeometry.analyze(wall:wall,room:room).net
            let visible=PlaquistoWallGeometry.solidTriangles(wall:wall,room:room)
            precondition(abs(area(visible)-net)<1e-6,"Rendered area \(area(visible)) != net \(net)")
            precondition(PlaquistoWallGeometry.displayTriangles(wall:wall,room:room).allSatisfy(\.finite))
        }
    }
    static func main() throws {
        let source=GeometryProvenance(source:.manual)
        func m(_ x:Double) -> RoomMeasurement { .init(rawValue:x,provenance:source) }
        func p(_ x:Double,_ y:Double,_ z:Double) -> RoomPoint { .init(x:x,y:y,z:z) }
        let wall=PlaquistoWall(start:p(0,0,0),end:p(4,0,0),length:m(4),height:m(3),provenance:source)
        var room=PlaquistoRoomModel(walls:[wall],metadata:.init(source:.manual))
        func opening(_ x:Double,_ w:Double,_ h:Double,_ sill:Double) -> PlaquistoOpening {
            .init(wallID:wall.id,kind:.passage,center:p(x+w/2,sill+h/2,0),width:m(w),height:m(h),sillHeight:m(sill),positionOnWall:m(x),provenance:source)
        }
        verify(room)
        room.openings=[opening(0.3,1,2.1,0)]; verify(room) // door
        room.openings=[opening(1,2,1,1)]; verify(room) // window
        room.openings += [opening(2,2,2,0)]; verify(room) // overlapping holes
        room.openings=[opening(-1,6,5,0)]; verify(room)
        precondition(PlaquistoWallGeometry.solidTriangles(wall:wall,room:room).isEmpty)
        room.slopes=[.init(plane:.init(a:0.5,b:0,c:1),boundaries:[[p(0,1,0),p(4,3,0),p(4,3,2),p(0,1,2)]],provenance:source,accepted:true)]
        room.openings=[opening(0,4,1,1.5)]; verify(room) // roof intersects both sill and lintel
        room.openings=[opening(0,2,5,0),opening(1,2,1,1)]; verify(room)
        let polygon=[p(0,2,0),p(2,2,0),p(2,2,1),p(1,2,1),p(1,2,2),p(0,2,2)]
        precondition(abs(area(PlaquistoSurfaceGeometry.triangles(polygon))-3)<1e-7)
        precondition(abs(area(PlaquistoSurfaceGeometry.triangles(polygon.reversed()))-3)<1e-7)
        let tilted=polygon.map { p($0.x,2+0.5*$0.x,$0.z) }
        precondition(abs(area(PlaquistoSurfaceGeometry.triangles(tilted))-3*sqrt(1.25))<1e-7)
        let slope=PlaquistoSlope(plane:.init(a:0.5,b:0,c:2),boundaries:[polygon],provenance:source,accepted:true)
        precondition(abs(PlaquistoSurfaceGeometry.area(of:slope)-3*sqrt(1.25))<1e-7)
        if CommandLine.arguments.count>1 {
            let document=try PlaquistoRoomStore.load(from:URL(fileURLWithPath:CommandLine.arguments[1]))
            verify(document.room)
            for pan in document.room.slopes where pan.accepted {
                precondition(!pan.boundaries.flatMap { PlaquistoSurfaceGeometry.triangles($0) }.isEmpty)
            }
            print("PASS: saved room with \(document.room.walls.count) walls, \(document.room.openings.count) openings, \(document.room.slopes.count) pans")
        }
        print("PASS: net render area, doors, windows, overlaps, full opening, sloped cutouts, concave/reversed/inclined surfaces")
    }
}
