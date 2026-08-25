import SwiftUI

@main
struct PlaquistoApp: App {
    @StateObject private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ProjectsHomeView()
                .environmentObject(projectStore)
        }
    }
}
