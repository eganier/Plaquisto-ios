import SwiftUI

@main
struct PlaquistoLabApp: App {
    @StateObject private var references = AlveolarPartitionReferenceStore()

    var body: some Scene {
        WindowGroup {
            AlveolarPartitionConfiguratorView()
                .environmentObject(references)
                .task { await references.load() }
        }
    }
}
