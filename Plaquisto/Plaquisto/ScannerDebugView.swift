import SceneKit
import SwiftUI

struct ScannerDebugView: View {
    let onOpenAccount: () -> Void
    @StateObject private var model = ScannerDebugModel()
    @State private var showingCapture = false

    var body: some View {
        NavigationStack {
            List {
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
                        PlaquistoSavedRoomView()
                    }
                    Text("Murs et dimensions depuis le fichier Plaquisto, sans lancer de capture.").font(.caption).foregroundStyle(.secondary)
                }
                if let summary = model.summary {
                    Section("Plafond reconstitué") {
                        if !model.virtualBoundaries.isEmpty {
                            Text("Zone délimitée par \(model.virtualBoundaries.count) limite(s) virtuelle(s) — aucun mur créé.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let surface = model.meshPreview?.reconstruction {
                            LabeledContent("Surface reconstituée", value: surface.area.formatted(.number.precision(.fractionLength(2))) + " m²")
                            LabeledContent("Pans reconstitués", value: "\(surface.pans.count)")
                            ForEach(surface.pans.indices, id: \.self) { index in
                                let pan = surface.pans[index]
                                LabeledContent("Pan \(index + 1)", value: "\(pan.area.formatted(.number.precision(.fractionLength(2)))) m² · \(pan.slopeDegrees.formatted(.number.precision(.fractionLength(1))))°")
                            }
                            Text("Surface continue estimée à partir des murs et des portions planes observées. Les ouvertures éventuelles ne sont pas déduites.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(model.meshPreview?.reconstructionMessage ?? "Reconstruction indisponible.")
                                .foregroundStyle(.secondary)
                        }
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
                        Section("Diagnostic de reconstruction") {
                            Text("Dernière tentative pendant le scan : \(model.lastReconstructionDiagnostic)")
                            ShareLink(item: diagnostic) {
                                Label("Partager le diagnostic complet", systemImage: "square.and.arrow.up")
                            }
                            Text("Murs, positions relatives de la caméra, compteurs et motifs de refus des 120 dernières tentatives. Sans photos ni maillage brut. Conservé en mémoire jusqu’au prochain scan.")
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

                    Section("Détection géométrique") {
                        resultRow("Faces candidates plafond", value: summary.geometricCeilingFaces)
                        resultRow("Faces horizontales", value: summary.geometricHorizontalFaces)
                        resultRow("Faces inclinées", value: summary.geometricSlopedFaces)
                        LabeledContent("Surface candidate", value: summary.geometricCeilingArea.formatted(.number.precision(.fractionLength(2))) + " m²")
                    }

                    Section("Diagnostic des hauteurs") {
                        measurementRow("Sol RoomPlan", value: summary.roomFloorY)
                        measurementRow("Haut des murs RoomPlan", value: summary.roomTopY)
                        measurementRow("Seuil de recherche", value: summary.geometricMinimumY)
                        measurementRow("Maillage le plus bas", value: summary.meshMinimumY)
                        measurementRow("Maillage le plus haut", value: summary.meshMaximumY)
                        measurementRow("Altitude maximale vue pendant le scan", value: summary.highestObservedMeshY)
                        resultRow("Faces non verticales (toutes hauteurs)", value: summary.upwardOrientedFaces)
                    }
                    Section("Performances et caméra") {
                        Text(model.cameraFormatsDescription).font(.caption)
                        LabeledContent("Dernière copie du maillage", value: model.meshCopyMilliseconds.formatted(.number.precision(.fractionLength(0))) + " ms (arrière-plan)")
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        model.prepareForCapture()
                        showingCapture = true
                    } label: {
                        Label(model.summary == nil ? "Démarrer un scan de test" : "Relancer un scan de test", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Scanner")
            .toolbar {
                AccountToolbarButton(action: onOpenAccount)
            }
            .fullScreenCover(isPresented: $showingCapture) {
                ScannerDebugCaptureView(model: model, isPresented: $showingCapture)
            }
        }
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
        ZStack {
            ScannerRoomCaptureRepresentable(model: model)
                .ignoresSafeArea()
            ScannerLiveCeilingOverlay(model: model)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if model.placingBoundary {
                Image(systemName: "plus.circle")
                    .font(.system(size: 32)).foregroundStyle(.orange)
                    .allowsHitTesting(false)
            }

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

                VStack(spacing: 10) {
                    if model.placingBoundary {
                        Text(model.boundaryInstruction)
                            .font(.caption).padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        HStack {
                            Button("Annuler la limite") { model.cancelBoundary() }
                            Button(model.boundaryPoints.count == 2 ? "Confirmer ce côté" : "Marquer ce point") {
                                if model.boundaryPoints.count == 2 { model.confirmBoundary() }
                                else { model.markBoundaryPoint() }
                            }
                        }.buttonStyle(.borderedProminent)
                    } else {
                        if model.hasCeilingProposal {
                            HStack {
                                Button("Valider ce plafond") { model.acceptCeilingProposal() }
                                Button("Autre proposition") { model.rejectCeilingProposal() }
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                    if model.liveCeilingLocked {
                        Button("Recalculer le plafond") { model.unlockCeiling() }
                            .buttonStyle(.borderedProminent)
                    }
                    Text(model.liveCeilingStatus)
                        .font(.caption.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                    Text("Maillage : \(model.liveMeshAnchorCount) ancres · \(model.liveCeilingFaceCount) faces plafond")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                    if let highestY = model.highestObservedMeshY {
                        Text("Altitude mesh maximale observée : \(Double(highestY).formatted(.number.precision(.fractionLength(2)))) m")
                            .font(.caption.monospacedDigit())
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button {
                        model.finishCapture()
                    } label: {
                        Label("Terminer le scan", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isProcessing || model.placingBoundary || model.hasCeilingProposal)
                }
                .padding()
            }
        }
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

struct ScannerDebugSummary {
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
