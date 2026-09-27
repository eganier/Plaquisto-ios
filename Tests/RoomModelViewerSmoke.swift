// Standalone simulator app: compile only domain, wall geometry and production editor.
// No RoomPlanScanner, RoomPlanAdapter, ARKit or RoomPlan linked.
import SwiftUI

@main struct RoomModelViewerSmoke: App {
    private static var ceilingEstimate: Bool { ProcessInfo.processInfo.arguments.contains("--ceiling-estimate") }
    private static var storage: URL {
        ceilingEstimate ? PlaquistoRoomStore.defaultURL.deletingLastPathComponent().appendingPathComponent("ceiling-estimate-proof.json") : PlaquistoRoomStore.defaultURL
    }
    init() {
        let target=Self.storage
        if !FileManager.default.fileExists(atPath:target.path),
           let fixture=Bundle.main.url(forResource:"room",withExtension:"json") {
            do {
                var document=try PlaquistoRoomDocument.decode(Data(contentsOf:fixture))
                if Self.ceilingEstimate {
                    var room = document.initialRoom
                    room.slopes = []; room.ceilings = []
                    room.name = "Test plafond estimé — sans LiDAR"
                    document = PlaquistoRoomDocument(room: room)
                }
                try PlaquistoRoomStore.save(document, to: target)
            } catch { fatalError("Synthetic fixture load failed: \(error)") }
        }
    }
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--ceiling-zones") {
                SurveyPlanEditor(document:Self.ceilingZones()) { try PlaquistoRoomStore.save($0,to:Self.storage) }
            } else if ProcessInfo.processInfo.arguments.contains("--plan-editor"),
               let fixture=Bundle.main.url(forResource:"room",withExtension:"json"),
               let data=try? Data(contentsOf:fixture), let document=try? PlaquistoRoomDocument.decode(data) {
                SurveyPlanEditor(document:Self.withoutCeiling(document)) { try PlaquistoRoomStore.save($0,to:Self.storage) }
            } else {
                NavigationStack { PlaquistoSavedRoomView(storageURL: Self.storage) }
            }
        }
    }
    private static func withoutCeiling(_ document:PlaquistoRoomDocument) -> PlaquistoRoomDocument {
        var room=document.room
        room.slopes=[]; room.ceilings=[]
        return .init(room:room)
    }
    // Two adjacent rooms: flat kitchen on the left, a 3.70 m gable on the right.
    // A dedicated fixture keeps interaction checks away from the user's scans.
    private static func ceilingZones() -> PlaquistoRoomDocument {
        let source = GeometryProvenance(source:.roomPlan)
        let points = [(0.0,0.0),(8.0,0.0),(8.0,4.0),(0.0,4.0)].map { RoomPoint(x:$0.0,y:0,z:$0.1) }
        var walls = points.indices.map { i -> PlaquistoWall in
            let a = points[i], b = points[(i+1)%4], length = (b-a).length
            return .init(start:a,end:b,length:.init(rawValue:length,provenance:source),
                         height:.init(rawValue:2.5,provenance:source),provenance:source)
        }
        for i in [0,2] {
            let upper: [(Double,Double)] = i == 0
                ? [(0,2.5),(4,2.5),(6,3.7),(8,2.5)] : [(0,2.5),(2,3.7),(4,2.5),(8,2.5)]
            walls[i].height.rawValue = 3.7
            walls[i].localOutline = [.zero,.init(x:8,y:0,z:0)]+upper.reversed().map { .init(x:$0.0,y:$0.1,z:0) }
        }
        walls.append(.init(start:.init(x:4,y:0,z:0),end:.init(x:4,y:0,z:4),
            length:.init(rawValue:4,provenance:source),height:.init(rawValue:2.5,provenance:source),provenance:source))
        return .init(room:.init(name:"Cuisine et salon — essai plafonds",walls:walls,
            floors:[.init(boundaries:[points],referenceElevation:0,provenance:source)],metadata:.init(source:.roomPlan)))
    }
}
