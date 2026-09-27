// Compile with PlaquistoRoomModel.swift + PlaquistoWallGeometry.swift ONLY.
// Separate write/read processes prove there is no in-memory acquisition dependency.
import Foundation

@main enum RoomModelIndependenceChecks {
    static let scan = GeometryProvenance(source:.roomPlan,confidenceLabel:"high")
    static func m(_ value:Double) -> RoomMeasurement { .init(rawValue:value,provenance:scan) }
    static func p(_ x:Double,_ y:Double,_ z:Double) -> RoomPoint { .init(x:x,y:y,z:z) }
    static func close(_ a:Double,_ b:Double) { precondition(abs(a-b)<1e-7,"\(a) != \(b)") }
    static func fixture() throws -> PlaquistoRoomDocument {
        let corners = [p(0,0,0),p(4.28,0,0),p(4.28,0,3),p(0,0,3)]
        let walls = corners.indices.map { i in
            let a=corners[i], b=corners[(i+1)%4]
            return PlaquistoWall(start:a,end:b,length:m((b-a).length),height:m(2.5),provenance:scan)
        }
        var room = PlaquistoRoomModel(name:"Pièce synthétique — sans RoomPlan",walls:walls,
            metadata:.init(createdAt:Date(timeIntervalSince1970:0),source:.imported))
        func opening(_ kind:RoomOpeningKind,_ x:Double,_ width:Double,_ height:Double,_ sill:Double) -> PlaquistoOpening {
            .init(wallID:walls[0].id,kind:kind,center:p(x+width/2,sill+height/2,0),
                  width:m(width),height:m(height),sillHeight:m(sill),positionOnWall:m(x),provenance:scan)
        }
        room.openings = [opening(.door,0.2,0.9,2.1,0),opening(.window,2,1.2,1,1.2)]
        room.walls[0].openingIDs = room.openings.map(\.id)
        room.slopes = [.init(plane:.init(a:0,b:0,c:2.5),
            boundaries:[corners.map { p($0.x,2.5,$0.z) }],provenance:.init(source:.lidar),accepted:true,manuallyValidated:true)]
        room.ceilings = [.init(slopeIDs:room.slopes.map(\.id),provenance:.init(source:.lidar))]
        room.floors = [.init(boundaries:[corners],referenceElevation:0,provenance:scan)]
        var document = PlaquistoRoomDocument(room:room)
        try document.room.walls[0].length.correct(4.31)
        try document.room.walls[0].height.correct(2.6)
        return document
    }
    static func checks(_ document:PlaquistoRoomDocument) throws {
        try document.validate()
        let wall=document.room.walls[0]
        close(document.initialRoom.walls[0].length.rawValue,4.28)
        precondition(document.initialRoom.walls[0].length.manualValue == nil)
        close(wall.length.effectiveValue,4.31); close(wall.height.effectiveValue,2.6)
        precondition(wall.length.manuallyValidated && wall.height.manuallyValidated)
        let geometry=PlaquistoWallGeometry.analyze(wall:wall,room:document.room)
        close(geometry.gross,4.31*2.6)
        close(geometry.net,4.31*2.6-0.9*2.1-1.2)
        precondition(geometry.strips.allSatisfy { $0.heightSource == .manual && $0.manuallyValidated })
        // This exact merge function is used by RoomPlanAdapter.
        let next = m(4.4).preservingCorrection(from:wall.length)
        close(next.rawValue,4.4); close(next.effectiveValue,4.31); precondition(next.manuallyValidated)
        var room=document.initialRoom
        let rectangular=room.walls[0]
        close(PlaquistoWallGeometry.analyze(wall:rectangular,room:room).gross,4.28*2.5)
        room.openings = [room.openings[0]] // door only
        close(PlaquistoWallGeometry.analyze(wall:rectangular,room:room).net,4.28*2.5-1.89)
        room.openings = [document.initialRoom.openings[1]] // window only
        close(PlaquistoWallGeometry.analyze(wall:rectangular,room:room).net,4.28*2.5-1.2)
        for kind in RoomOpeningKind.allCases {
            room.openings[0].kind = kind
            close(PlaquistoWallGeometry.analyze(wall:rectangular,room:room).net,4.28*2.5-1.2)
        }
        room.openings = []
        room.slopes[0].plane = .init(a:0.5,b:0,c:2)
        room.slopes[0].boundaries = [[p(0,2,0),p(4.28,4.14,0),p(4.28,4.14,3),p(0,2,3)]]
        close(PlaquistoWallGeometry.analyze(wall:rectangular,room:room).gross,4.28*2.5)
        room.slopes = [
            .init(plane:.init(a:0.5,b:0,c:2),boundaries:[[p(0,2,0),p(2.14,3.07,0),p(2.14,3.07,3),p(0,2,3)]],provenance:scan,accepted:true),
            .init(plane:.init(a:-0.5,b:0,c:4.14),boundaries:[[p(2.14,3.07,0),p(4.28,2,0),p(4.28,2,3),p(2.14,3.07,3)]],provenance:scan,accepted:true)]
        close(PlaquistoWallGeometry.analyze(wall:rectangular,room:room).gross,4.28*2.5)
        let vertices=PlaquistoWallGeometry.triangles(wall:rectangular,room:room)
        precondition(vertices.count==6 && vertices.allSatisfy(\.finite))
        var gable=rectangular
        gable.localOutline=[p(0,0,0),p(4.28,0,0),p(4.28,2,0),p(2.14,3.07,0),p(0,2,0)]
        close(PlaquistoWallGeometry.analyze(wall:gable,room:room).gross,4.28*2+4.28*1.07/2)
        precondition(PlaquistoWallGeometry.triangles(wall:gable,room:room).count==12)
        var intent=document
        intent.wallWorkIntents = [.init(wallID:wall.id,use:.lining)]
        let roundTrip = try PlaquistoRoomDocument.decode(intent.encoded())
        precondition(roundTrip.wallWorkIntents == intent.wallWorkIntents)
        precondition(roundTrip.room == document.room) // business intent changes no geometry
    }
    static func main() throws {
        guard CommandLine.arguments.count==3 else { fatalError("usage: checks write|read path.json") }
        let url=URL(fileURLWithPath:CommandLine.arguments[2])
        if CommandLine.arguments[1]=="write" {
            let document=try fixture(); try checks(document)
            try PlaquistoRoomStore.save(document,to:url)
            print("WRITE: synthetic model and validated corrections saved; room ID \(document.room.id)")
        } else {
            let loaded=try PlaquistoRoomStore.load(from:url); try checks(loaded)
            print("READ: new process, JSON only; room ID \(loaded.room.id), walls \(loaded.room.walls.count)")
            print("PASS: rectangle, door, window, net area, one slope, gable, manual priority after reload, adapter merge, business intent isolation")
        }
    }
}
