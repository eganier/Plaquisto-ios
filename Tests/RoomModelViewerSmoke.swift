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
            if ProcessInfo.processInfo.arguments.contains("--plan-editor"),
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
}
