import SwiftUI

final class LabOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .portrait }
}

@main
struct PlaquistoLabApp: App {
    @UIApplicationDelegateAdaptor(LabOrientationDelegate.self) private var orientationDelegate
    // fr.plaquisto.lab has its own sandbox. No production container or App Group.
    @StateObject private var projects: ProjectStore
    init() {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-atlantique-lot1-fixture") {
            // Explicit QA launch only. Never seeds or replaces the user's archive.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AtlantiqueLot1QA-v2/projects.json")
            let store = ProjectStore(fileURL: url)
            if store.projects.isEmpty {
                do { try Self.seedLot1(store) }
                catch { assertionFailure("Lot 1 fixture failed: \(error)") }
            }
            _projects = StateObject(wrappedValue: store)
        } else { _projects = StateObject(wrappedValue: ProjectStore()) }
        #else
        _projects = StateObject(wrappedValue: ProjectStore())
        #endif
    }
    #if targetEnvironment(simulator)
    private static func seedLot1(_ store: ProjectStore) throws {
        let project = try store.createProject(name: "Maison Lumière · Démo", client: "Client de démonstration", address: "", notes: "Données fictives pour la recette graphique")
        let contour: [LayoutPoint] = [.init(x: 0, y: 0), .init(x: 6700, y: 0), .init(x: 6700, y: 4200),
                                     .init(x: 4000, y: 4200), .init(x: 4000, y: 6000), .init(x: 0, y: 6000)]
        let room = try ManualRoomModel.room(contour: contour, commonHeight: 2.6, constraints: [:], name: "Salon / Cuisine")
        var document = PlaquistoRoomDocument(room: room)
        document = try SurveyPlanEditing.addingDoor(document, wallID: room.walls[0].id, width: 0.83, height: 2.04, position: 1.2)
        let saved = try store.saveScannedRoom(projectID: project, newProjectName: nil, surveyID: nil, surveyName: "Rez-de-chaussée", roomID: nil, roomName: "Salon / Cuisine", document: document)
        for checkpoint in store.surveys.first(where: { $0.id == saved.surveyID })!.checkpoints {
            try store.validateSurveyCheckpoint(surveyID: saved.surveyID, checkpointID: checkpoint.id, expectedDocument: checkpoint.document)
        }
        let surfaces = SurveyWorkGeometry.surfaces(in: store.surveys.first { $0.id == saved.surveyID }!)
        let wall = Array(surfaces.filter { $0.source.kind == .wall }.prefix(1))
        var lining = SurveyWorkGeometry.furring(wall)
        lining.insulationEnabled = false
        lining.furringSpacing = 0.6
        lining.firstSkin = [.init(facingID: "FACING-BA13-STANDARD", formatID: "1200x2600", surface: lining.area)]
        lining.quantities = [.init(name: "BA13 · 1200 × 2600 mm", quantity: lining.area * 1.1, unit: "m²"),
                             .init(name: "Fourrures", quantity: 32, unit: "ml"),
                             .init(name: "Appuis intermédiaires 120", quantity: 12, unit: "unités")]
        let liningID = try store.createSurveyWork(surveyID: saved.surveyID, selections: wall, name: "Doublage du salon", type: .peripheralLiningFurrings, payload: .furringLining(lining), roomID: nil)
        let ceilings = surfaces.filter { $0.source.kind == .ceiling }
        _ = try store.createSurveyWork(surveyID: saved.surveyID, selections: ceilings, name: "Plafond du salon", type: .ceilingOnFurring, payload: .ceiling(SurveyWorkGeometry.ceiling(ceilings)), roomID: nil)
        if let component = store.project(id: project)?.works.first(where: { $0.id == liningID })?.components.first, let surface = component.surface {
            var layout = LayoutDocument.newSupport(surface)
            layout.layers[0].sheetLength = 2600
            layout.layers[0].manualFacing = true
            layout.layers[0].furring = .init()
            try store.saveComponentPlan(projectID: project, workID: liningID, componentID: component.id, sideRoomID: nil, document: layout)
        }
        let copy = try store.duplicateSurvey(projectID: project, surveyID: saved.surveyID)
        try store.renameSurvey(projectID: project, surveyID: copy, name: "Étage")
        _ = try store.createProject(name: "Atelier des Pins · Démo", client: "", address: "", notes: "Projet sans relevé pour vérifier les vignettes")
    }
    #endif
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
