import SwiftUI

@main
struct PlaquistoLabApp: App {
    @StateObject private var references = FurringLiningReferenceStore()

    var body: some Scene {
        WindowGroup {
            FurringLiningConfiguratorView()
                .environmentObject(references)
                .task { await references.load() }
        }
    }
}
