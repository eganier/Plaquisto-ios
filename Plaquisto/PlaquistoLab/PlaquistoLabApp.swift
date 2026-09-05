import SwiftUI

@main
struct PlaquistoLabApp: App {
    @StateObject private var references = BondedLiningReferenceStore()

    var body: some Scene {
        WindowGroup {
            BondedLiningConfiguratorView()
                .environmentObject(references)
        }
    }
}
