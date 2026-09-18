import SwiftUI

@main
struct PlaquistoLabApp: App {
    @StateObject private var projects = ProjectStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                ToolsHomeView().tabItem { Label("Outils",systemImage:"wrench.and.screwdriver") }
                ProjectsHomeView().tabItem { Label("Projets Lab",systemImage:"building.2") }
            }.environmentObject(projects)
                .environment(\.beforeAfterAccount,BeforeAfterAccountContext(allowsLabWatermarkControl:true))
        }
    }
}
