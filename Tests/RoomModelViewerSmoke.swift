// Standalone simulator app: compile only domain, wall geometry and production editor.
// No RoomPlanScanner, RoomPlanAdapter, ARKit or RoomPlan linked.
import SwiftUI

@main struct RoomModelViewerSmoke: App {
    init() {
        let target=PlaquistoRoomStore.defaultURL
        if !FileManager.default.fileExists(atPath:target.path),
           let fixture=Bundle.main.url(forResource:"room",withExtension:"json") {
            do {
                let document=try PlaquistoRoomDocument.decode(Data(contentsOf:fixture))
                try PlaquistoRoomStore.save(document)
            } catch { fatalError("Synthetic fixture load failed: \(error)") }
        }
    }
    var body: some Scene {
        WindowGroup { NavigationStack { PlaquistoSavedRoomView() } }
    }
}
