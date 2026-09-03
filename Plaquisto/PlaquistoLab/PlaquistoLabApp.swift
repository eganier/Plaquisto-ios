import SwiftUI

@main
struct PlaquistoLabApp: App {
    @StateObject private var references = CloisonDistributionReferenceStore()

    var body: some Scene {
        WindowGroup {
            CloisonDistributionConfiguratorView()
                .environmentObject(references)
                .task { await references.load() }
        }
    }
}
