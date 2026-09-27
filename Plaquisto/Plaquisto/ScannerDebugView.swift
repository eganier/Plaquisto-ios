import SceneKit
import SwiftUI

struct ScannerDebugView: View {
    @EnvironmentObject private var store: ProjectStore
    let onOpenAccount: () -> Void
    @StateObject private var model = ScannerDebugModel()
    @State private var showingCapture = false
    @State private var showingWorkspace = false
    @State private var recoveredDrafts: [ScanCampaignDraft] = []
    @State private var recoveryError: String?
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.prepareForCapture()
                        showingCapture = true
                    } label: {
                        Label("Démarrer un relevé", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart || model.needsSaveRetry)
                    .listRowBackground(Color.clear)
                    if model.needsSaveRetry {
                        Text("Sauvegardez le relevé en mémoire avant de commencer une nouvelle capture.")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Réessayer la sauvegarde") { model.retryCampaignSave(); reloadDrafts() }
                    }
                }
                Section {
                    Text("Balayez lentement les murs et les ouvertures en suivant le guidage Apple. Touchez « Terminer le scan » pour ouvrir la maquette et le plan modifiables.")
                        .font(.subheadline)
                    Text("Capture native RoomPlan : commencez par une pièce. Le découpage automatique d’une maison en plusieurs pièces n’est pas activé.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.campaign.chunks.isEmpty {
                    Section("Dernier relevé") {
                        NavigationLink {
                            ScannerCampaignWorkspaceView(draft: model.campaign)
                        } label: {
                            Label("Ouvrir la maquette et choisir les surfaces", systemImage: "square.stack.3d.up")
                        }
                    }
                }
                let remainingDrafts = recoveredDrafts.filter { draft in
                    draft.id != model.campaign.id && !store.surveys.contains(where: { $0.id == draft.id })
                }
                if !remainingDrafts.isEmpty {
                    Section("Relevés à enregistrer") {
                        ForEach(remainingDrafts) { draft in
                            NavigationLink {
                                ScannerCampaignWorkspaceView(draft: draft)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("\(draft.chunks.count) pièce(s) conservée(s)")
                                    Text(draft.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let recoveryError { Text(recoveryError).foregroundStyle(.orange) }
                Section {
                    Button(showDiagnostics ? "Masquer les détails techniques" : "Détails techniques et diagnostic") {
                        showDiagnostics.toggle()
                    }.font(.footnote)
                }
                if showDiagnostics {
                Section {
                    capabilityRow("RoomPlan", available: model.roomPlanSupported)
                    capabilityRow("Maillage LiDAR classifié", available: model.meshClassificationSupported)
                } header: {
                    Text("Compatibilité")
                } footer: {
                    Text("Le scan doit être testé sur un iPhone Pro équipé d’un capteur LiDAR. Le simulateur ne permet pas de valider la capture.")
                }

                Section("Pièce Plaquisto") {
                    NavigationLink("Ouvrir la pièce sauvegardée") {
                        PlaquistoSavedRoomView(projectSaveDestination: { AnyView(ScannerProjectSaveView(document: $0)) })
                    }
                    Text("Murs et dimensions depuis le fichier Plaquisto, sans lancer de capture.").font(.caption).foregroundStyle(.secondary)
                }
                if let summary = model.summary {
                    if model.campaign.chunks.isEmpty, let document = model.latestDocument {
                        Section("Projet Plaquisto") {
                            NavigationLink {
                                ScannerProjectSaveView(document: document)
                            } label: {
                                Label("Enregistrer cette pièce dans un relevé", systemImage: "folder.badge.plus")
                            }
                            Text("Enregistrez cette pièce dans un projet pour la retrouver avec les autres pièces du relevé.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Plafonds après le scan") {
                        Text("Créez le plafond dans Modifier le plan → Plafond. Les hauteurs proposées restent à vérifier. Aucun plafond n’est déduit automatiquement et les contours des murs restent inchangés.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let preview = model.meshPreview {
                        Section {
                            NavigationLink {
                                ScannerMeshPreviewView(preview: preview)
                            } label: {
                                Label("Voir le scan en 3D", systemImage: "cube.transparent")
                            }
                        }
                    }
                    if let diagnostic = model.contourDiagnostic {
                        Section("Diagnostic de capture") {
                            Text(model.lastReconstructionDiagnostic)
                            ShareLink(item: model.campaign.captureDiagnostic ?? diagnostic) {
                                Label("Partager le diagnostic complet", systemImage: "square.and.arrow.up")
                            }
                            Text("Géométrie, événements de capture et configuration native. Sans photos ni maillage brut. Le rapport est sauvegardé avec le relevé et accessible depuis le menu de la maquette.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Résultat RoomPlan") {
                        resultRow("Murs", value: summary.walls)
                        resultRow("Sols", value: summary.floors)
                        resultRow("Portes", value: summary.doors)
                        resultRow("Fenêtres", value: summary.windows)
                        resultRow("Ouvertures", value: summary.openings)
                        resultRow("Objets", value: summary.objects)
                    }

                    Section("Résultat ARKit") {
                        diagnosticRow("Configuration mesh active", value: summary.meshConfigurationActive)
                        diagnosticRow("Delegate ARKit conservé", value: summary.arDelegateRetained)
                        resultRow("Ancres de maillage", value: summary.meshAnchors)
                        resultRow("Faces de maillage", value: summary.meshFaces)
                        resultRow("Ancres contenant un plafond", value: summary.ceilingMeshAnchors)
                        resultRow("Faces classées plafond", value: summary.ceilingMeshFaces)
                    }

                    Section("Diagnostic des hauteurs") {
                        measurementRow("Sol RoomPlan", value: summary.roomFloorY)
                        measurementRow("Haut des murs RoomPlan", value: summary.roomTopY)
                    }
                    Section("Performances et caméra") {
                        Text(model.cameraFormatsDescription).font(.caption)
                        Text("Aucune copie de maillage ni recherche de plafond ajoutée par Plaquisto pendant l’acquisition.").font(.caption)
                    }
                }

                }
                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

            }
            .navigationTitle("Scanner")
            .onAppear { reloadDrafts() }
            .toolbar {
                AccountToolbarButton(action: onOpenAccount)
            }
            .navigationDestination(isPresented: $showingWorkspace) {
                ScannerCampaignWorkspaceView(draft: model.campaign)
            }
            .fullScreenCover(isPresented: $showingCapture, onDismiss: {
                if model.didFinish && !model.campaign.chunks.isEmpty { showingWorkspace = true }
            }) {
                ScannerDebugCaptureView(model: model, isPresented: $showingCapture)
            }
            .onChange(of: showingCapture) { _, showing in if !showing { reloadDrafts() } }
        }
    }

    private func reloadDrafts() {
        do {
            let recovery = try ScanCampaignStore.recover()
            recoveredDrafts = recovery.drafts.filter { !$0.chunks.isEmpty }
            recoveryError = recovery.unreadableFiles.isEmpty ? nil : "\(recovery.unreadableFiles.count) relevé(s) illisible(s), conservé(s) sur l’appareil. Les autres relevés restent disponibles."
        } catch { recoveryError = "Un relevé sauvegardé n’a pas pu être relu : \(error.localizedDescription)" }
    }

    private func capabilityRow(_ title: String, available: Bool) -> some View {
        LabeledContent(title) {
            Label(available ? "Disponible" : "Indisponible", systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .secondary)
        }
    }

    private func resultRow(_ title: String, value: Int) -> some View {
        LabeledContent(title, value: value.formatted())
    }

    private func diagnosticRow(_ title: String, value: Bool) -> some View {
        LabeledContent(title, value: value ? "Oui" : "Non")
    }

    private func measurementRow(_ title: String, value: Double?) -> some View {
        LabeledContent(title, value: value.map { $0.formatted(.number.precision(.fractionLength(2))) + " m" } ?? "Indisponible")
    }
}


private struct ScannerDebugCaptureView: View {
    @ObservedObject var model: ScannerDebugModel
    @Binding var isPresented: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                // Apple's own live parametric model, coaching and camera view.
                ScannerRoomCaptureRepresentable(model: model)
                    .frame(height: geometry.size.height * 0.72)
                    .clipped()

                VStack {
                    HStack {
                        Button("Annuler") {
                            model.cancelCapture()
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.9))
                        .foregroundStyle(.primary)
                        Spacer()
                        Text(model.statusText)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding()
                    Spacer()
                    Button {
                        model.finishCapture()
                    } label: {
                        Label("Terminer le scan", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.finishingCampaign)
                    .padding()
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
        .onAppear { model.startCapture() }
        .onChange(of: model.didFinish) { _, didFinish in
            if didFinish { isPresented = false }
        }
        .onDisappear {
            if !model.didFinish { model.cancelCapture() }
        }
    }
}

struct ScannerDebugSummary: Codable {
    let walls: Int
    let floors: Int
    let doors: Int
    let windows: Int
    let openings: Int
    let objects: Int
    let meshConfigurationActive: Bool
    let arDelegateRetained: Bool
    let meshAnchors: Int
    let meshFaces: Int
    let ceilingMeshAnchors: Int
    let ceilingMeshFaces: Int
    let geometricCeilingFaces: Int
    let geometricHorizontalFaces: Int
    let geometricSlopedFaces: Int
    let geometricCeilingArea: Double
    let roomFloorY: Double?
    let roomTopY: Double?
    let geometricMinimumY: Double?
    let meshMinimumY: Double?
    let meshMaximumY: Double?
    let upwardOrientedFaces: Int
    let highestObservedMeshY: Double?
}

struct ScannerGeometricCeilingAnalysis {
    let floorY: Float
    let nominalTopY: Float
    let minimumCandidateY: Float
    let candidateFaces: Int
    let horizontalFaces: Int
    let slopedFaces: Int
    let candidateArea: Double
    let meshMinimumY: Float?
    let meshMaximumY: Float?
    let upwardOrientedFaces: Int
    let preview: ScannerMeshPreview
}

enum ScannerMeshGroup: String, CaseIterable, Identifiable {
    case agreement, appleOnly, filterOnly, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .agreement: return "Plafond Apple + filtre"
        case .appleOnly: return "Plafond Apple, écarté par le filtre"
        case .filterOnly: return "Filtre seul, à vérifier"
        case .other: return "Reste du maillage"
        }
    }
    var color: UIColor {
        switch self {
        case .agreement: return .systemGreen
        case .appleOnly: return .systemBlue
        case .filterOnly: return .systemOrange
        case .other: return .systemGray
        }
    }
}

struct ScannerMeshPreview {
    let id = UUID()
    let triangles: [ScannerMeshGroup: [SCNVector3]]
    let wallEdges: [SCNVector3]
    let reconstruction: ScannerCeilingReconstruction.Surface?
    let reconstructionMessage: String?
}

private struct ScannerMeshPreviewView: View {
    let preview: ScannerMeshPreview
    @State private var showOther = false
    @State private var viewFromAbove = true
    @State private var resetID = UUID()
    @State private var showReconstruction = true

    var body: some View {
        VStack(spacing: 12) {
            ScannerMeshSceneView(preview: preview, showOther: showOther,
                                 viewFromAbove: viewFromAbove, resetID: resetID,
                                 showReconstruction: showReconstruction && preview.reconstruction != nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Maillage 3D du scan. Rotation à un doigt, zoom à deux doigts.")

            HStack {
                Picker("Point de vue", selection: $viewFromAbove) {
                    Text("Dessus").tag(true)
                    Text("Perspective").tag(false)
                }
                .pickerStyle(.segmented)
                Button { resetID = UUID() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Recentrer la vue")
                .buttonStyle(.bordered)
            }
            Toggle("Afficher le reste du maillage", isOn: $showOther)
                .font(.subheadline)
            if let surface = preview.reconstruction {
                Toggle("Plafond reconstitué · \(surface.area.formatted(.number.precision(.fractionLength(2)))) m²", isOn: $showReconstruction)
                    .font(.subheadline).tint(.purple)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(ScannerMeshGroup.allCases) { group in
                    HStack(spacing: 8) {
                        Circle().fill(Color(uiColor: group.color)).frame(width: 10, height: 10)
                        Text(group.title)
                        Spacer()
                        Text(((preview.triangles[group]?.count ?? 0) / 3).formatted())
                            .monospacedDigit()
                    }
                }
                Text("Violet : surface reconstituée, ouvertures non déduites. Désactivez-la pour comparer au scan brut. Traits blancs : murs RoomPlan. Rotation à un doigt, zoom à deux doigts.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding()
        .navigationTitle("Scan en 3D")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScannerMeshSceneView: UIViewRepresentable {
    let preview: ScannerMeshPreview
    let showOther: Bool
    let viewFromAbove: Bool
    let resetID: UUID
    let showReconstruction: Bool

    final class Coordinator {
        var previewID: UUID?
        var resetID: UUID?
        var viewFromAbove: Bool?
        var center = SCNVector3Zero
        var radius: Float = 1
        var otherNode: SCNNode?
        var scanNodes: [SCNNode] = []
        var reconstructedNode: SCNNode?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.previewID != preview.id
        if changed {
            coordinator.previewID = preview.id
            coordinator.otherNode = nil
            coordinator.scanNodes = []
            coordinator.reconstructedNode = nil
            let scene = SCNScene()
            var boundsPoints = preview.wallEdges
            for group in ScannerMeshGroup.allCases {
                let vertices = preview.triangles[group] ?? []
                boundsPoints.append(contentsOf: vertices)
                guard !vertices.isEmpty else { continue }
                let node = geometryNode(vertices: vertices, type: .triangles, color: group.color)
                scene.rootNode.addChildNode(node)
                if group == .other { coordinator.otherNode = node }
                else { coordinator.scanNodes.append(node) }
            }
            if let surface = preview.reconstruction {
                let vertices = surface.vertices.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) }
                let node = geometryNode(vertices: vertices, type: .triangles, color: .systemPurple)
                scene.rootNode.addChildNode(node)
                coordinator.reconstructedNode = node
                boundsPoints.append(contentsOf: vertices)
            }
            if !preview.wallEdges.isEmpty {
                scene.rootNode.addChildNode(geometryNode(vertices: preview.wallEdges, type: .line, color: .white))
            }
            if let first = boundsPoints.first {
                var low = SIMD3<Float>(first.x, first.y, first.z)
                var high = low
                for point in boundsPoints {
                    let p = SIMD3<Float>(point.x, point.y, point.z)
                    low = simd_min(low, p)
                    high = simd_max(high, p)
                }
                let center = (low + high) / 2
                coordinator.center = SCNVector3(center.x, center.y, center.z)
                coordinator.radius = max(simd_length(high - low) / 2, 0.5)
            }
            view.scene = scene
        }
        coordinator.otherNode?.isHidden = !showOther
        coordinator.scanNodes.forEach { $0.isHidden = showReconstruction }
        coordinator.reconstructedNode?.isHidden = !showReconstruction
        if changed || coordinator.resetID != resetID || coordinator.viewFromAbove != viewFromAbove {
            coordinator.resetID = resetID
            coordinator.viewFromAbove = viewFromAbove
            view.defaultCameraController.stopInertia()
            view.scene?.rootNode.childNode(withName: "previewCamera", recursively: false)?.removeFromParentNode()
            let camera = SCNNode()
            camera.name = "previewCamera"
            camera.camera = SCNCamera()
            camera.camera?.zNear = 0.01
            camera.camera?.zFar = Double(coordinator.radius * 30)
            camera.camera?.fieldOfView = 50
            let center = coordinator.center
            let distance = coordinator.radius * 4
            camera.position = viewFromAbove
                ? SCNVector3(center.x, center.y + distance, center.z + distance * 0.001)
                : SCNVector3(center.x + distance * 0.65, center.y + distance * 0.65, center.z + distance * 0.65)
            camera.look(at: center)
            view.scene?.rootNode.addChildNode(camera)
            view.pointOfView = camera
            view.defaultCameraController.target = center
        }
    }

    private func geometryNode(vertices: [SCNVector3], type: SCNGeometryPrimitiveType, color: UIColor) -> SCNNode {
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: type)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
