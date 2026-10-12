import SwiftUI

final class PlaquistoOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct PlaquistoApp: App {
    @UIApplicationDelegateAdaptor(PlaquistoOrientationDelegate.self) private var orientationDelegate
    @StateObject private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            PlaquistoRootView()
                .preferredColorScheme(.light)
                .environmentObject(projectStore)
                #if DEBUG
                .environment(\.beforeAfterAccount, BeforeAfterAccountContext(allowsLabWatermarkControl: true))
                #endif
        }
    }
}

private struct PlaquistoRootView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var selectedTab = AppTab.projects
    @State private var showingAccount = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ProjectsHomeView { showingAccount = true }
                .tabItem { Label("Projets", systemImage: "building.2") }
                .tag(AppTab.projects)

            ScannerDebugView(onOpenAccount: { showingAccount = true })
            .tabItem { Label("Scanner", systemImage: "viewfinder") }
            .tag(AppTab.scanner)

            ToolsHomeView(onOpenAccount: { showingAccount = true })
            .tabItem { Label("Outils", systemImage: "wrench.and.screwdriver") }
            .tag(AppTab.tools)

            AppSectionPlaceholder(
                title: "Stock",
                symbol: "shippingbox",
                message: "Visualisez prochainement les fournitures disponibles en magasin.",
                onOpenAccount: { showingAccount = true }
            )
            .tabItem { Label("Stock", systemImage: "shippingbox") }
            .tag(AppTab.stock)
        }
        .tint(Color(red: 0.12, green: 0.38, blue: 0.29))
        .onChange(of:store.projectNavigationRequest) { _, request in
            if request != nil { selectedTab = .projects }
        }
        .sheet(isPresented: $showingAccount) {
            AccountSettingsView()
        }
    }
}

private enum AppTab: Hashable {
    case projects, scanner, tools, stock
}

private struct AppSectionPlaceholder: View {
    let title: String
    let symbol: String
    let message: String
    let onOpenAccount: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: symbol, description: Text(message))
                .navigationTitle(title)
                .toolbar {
                    AccountToolbarButton(action: onOpenAccount)
                }
        }
    }
}

private struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Compte") {
                    LabeledContent("Profil", value: "À configurer")
                    LabeledContent("Entreprise", value: "À configurer")
                }

                MaquetteRenderingSettingsSection()

                Section("Application") {
                    LabeledContent("Données métier", value: "Plaquisto Admin")
                    LabeledContent("Mises à jour", value: "Automatiques")
                }

                Section("À propos") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Compilation", value: build)
                }
            }
            .navigationTitle("Compte et réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .tint(Color(red: 0.12, green: 0.38, blue: 0.29))
    }
}
