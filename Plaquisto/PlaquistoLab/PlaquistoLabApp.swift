import SwiftUI

@main
struct PlaquistoLabApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(spacing: 18) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)

                    Text("Plaquisto Lab")
                        .font(.largeTitle.bold())

                    Text("Prêt pour le prochain ouvrage")
                        .font(.title3.weight(.semibold))

                    Text("Le Lab est maintenant vide. Le prochain configurateur pourra être développé ici sans modifier Plaquisto iOS.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }
}
