import SwiftUI

@main
struct PlaquistoLabApp: App {
    @StateObject private var references = LabReferenceStore()

    var body: some Scene {
        WindowGroup {
            DoublageConfiguratorView()
                .environmentObject(references)
                .task { await references.load() }
        }
    }
}
