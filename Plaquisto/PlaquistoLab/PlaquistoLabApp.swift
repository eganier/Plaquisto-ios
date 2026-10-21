import SwiftUI

final class LabOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .portrait }
}

@main
struct PlaquistoLabApp: App {
    @UIApplicationDelegateAdaptor(LabOrientationDelegate.self) private var orientationDelegate
    // fr.plaquisto.lab has its own sandbox. No production container or App Group.
    @StateObject private var projects = ProjectStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-atlantique-gallery") {
                    AtlantiqueGallery()
                } else {
                    ContrastLabRoot()
                }
            }.environmentObject(projects)
                .task { try? await ScanEvidenceStore.shared.prune() }
                .environment(\.interfacePresentation, .contrastLab)
                .preferredColorScheme(.light)
                .tint(ContrastPalette.blue)
                .environment(\.beforeAfterAccount,BeforeAfterAccountContext(allowsLabWatermarkControl:true))
        }
    }
}
