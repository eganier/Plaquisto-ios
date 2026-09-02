import SwiftUI

@main
struct PlaquistoLabApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentUnavailableView {
                    Label("Plaquisto Lab", systemImage: "hammer.fill")
                } description: {
                    Text("L’atelier est prêt pour le prochain configurateur d’ouvrage.")
                }
                .navigationTitle("Laboratoire")
            }
            .tint(Color(red: 0.12, green: 0.38, blue: 0.29))
        }
    }
}
