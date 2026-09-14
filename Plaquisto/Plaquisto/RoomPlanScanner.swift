import ARKit
import RoomPlan
import SceneKit
import SwiftUI

struct ScannerLiveCeilingOverlay: UIViewRepresentable {
    let model: ScannerDebugModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.scene = SCNScene()
        view.scene?.rootNode.addChildNode(context.coordinator.camera)
        view.scene?.rootNode.addChildNode(context.coordinator.surface)
        view.scene?.rootNode.addChildNode(context.coordinator.boundaries)
        view.pointOfView = context.coordinator.camera
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        context.coordinator.view = view
        let link = CADisplayLink(target: context.coordinator, selector: #selector(Coordinator.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        context.coordinator.displayLink = link
        return view
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.displayLink?.invalidate()
        coordinator.displayLink = nil
        uiView.isPlaying = false
    }
    final class Coordinator: NSObject {
        weak var model: ScannerDebugModel?
        weak var view: SCNView?
        let camera = SCNNode()
        let surface = SCNNode()
        let boundaries = SCNNode()
        var displayLink: CADisplayLink?
        var revision: UUID?
        init(model: ScannerDebugModel) {
            self.model = model
            super.init()
            camera.camera = SCNCamera()
        }
        @MainActor @objc func tick() { refresh() }
        @MainActor func refresh() {
            guard let model, let view, let frame = model.liveARFrame,
                  view.bounds.width > 0, view.bounds.height > 0 else { return }
            guard case .normal = frame.camera.trackingState else {
                surface.isHidden = true; boundaries.isHidden = true; return
            }
            surface.isHidden = false
            boundaries.isHidden = false
            let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
            camera.simdTransform = simd_inverse(frame.camera.viewMatrix(for: orientation))
            camera.camera?.projectionTransform = SCNMatrix4(frame.camera.projectionMatrix(for: orientation, viewportSize: view.bounds.size, zNear: 0.01, zFar: 100))
            if revision != model.liveCeilingRevision {
                revision = model.liveCeilingRevision
                boundaries.childNodes.forEach { $0.removeFromParentNode() }
                let boundaryPoints = model.boundaryLines + model.boundaryPoints
                let orange = SCNMaterial()
                orange.diffuse.contents = UIColor.systemOrange
                orange.lightingModel = .constant
                for point in boundaryPoints {
                    let marker = SCNNode(geometry: SCNSphere(radius: 0.035))
                    marker.geometry?.materials = [orange]
                    marker.simdPosition = point
                    boundaries.addChildNode(marker)
                }
                if boundaryPoints.count >= 2 {
                    let pairedCount = boundaryPoints.count - boundaryPoints.count % 2
                    let line = SCNGeometry(sources: [SCNGeometrySource(vertices: boundaryPoints.prefix(pairedCount).map { SCNVector3($0.x, $0.y, $0.z) })],
                        elements: [SCNGeometryElement(indices: Array(0..<Int32(pairedCount)), primitiveType: .line)])
                    line.materials = [orange]
                    boundaries.addChildNode(SCNNode(geometry: line))
                }
                let vertices = model.liveCeilingVertices.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) }
                guard !vertices.isEmpty else { surface.geometry = nil; return }
                let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                    elements: [SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)])
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = (model.hasCeilingProposal ? UIColor.systemYellow : UIColor.systemGreen).withAlphaComponent(0.38)
                material.isDoubleSided = true
                material.writesToDepthBuffer = false
                geometry.materials = [material]
                surface.geometry = geometry
            }
        }
    }
}

// Preserve RoomCaptureView's existing delegate: it still receives every event.
private final class ScannerLiveRoomDelegate: NSObject, RoomCaptureSessionDelegate {
    weak var model: ScannerDebugModel?
    let downstream: RoomCaptureSessionDelegate?
    init(model: ScannerDebugModel, downstream: RoomCaptureSessionDelegate?) {
        self.model = model
        self.downstream = downstream
    }
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        downstream?.captureSession(session, didUpdate: room)
        Task { @MainActor in model?.receiveLiveRoom(room) }
    }
    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
        downstream?.captureSession(session, didAdd: room)
        Task { @MainActor in model?.receiveLiveRoom(room) }
    }
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        downstream?.captureSession(session, didChange: room)
        Task { @MainActor in model?.receiveLiveRoom(room) }
    }
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
        downstream?.captureSession(session, didRemove: room)
        Task { @MainActor in model?.receiveLiveRoom(room) }
    }
    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        downstream?.captureSession(session, didProvide: instruction)
    }
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        downstream?.captureSession(session, didStartWith: configuration)
    }
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        downstream?.captureSession(session, didEndWith: data, error: error)
    }
}

struct ScannerRoomCaptureRepresentable: UIViewRepresentable {
    let model: ScannerDebugModel

    func makeUIView(context: Context) -> RoomCaptureView {
        model.captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}


private struct ScannerMeshAnchorSnapshot {
    let identifier: UUID
    let transform: simd_float4x4
    let vertices: [SIMD3<Float>]
    let faces: [[Int32]]
    let classifications: [UInt8]

    var faceCount: Int { faces.count }
    let ceilingFaceCount: Int

    var firstCeilingWorldPoint: SIMD3<Float>? {
        guard let faceIndex = classifications.firstIndex(where: { Int($0) == ARMeshClassification.ceiling.rawValue }),
              faces.indices.contains(faceIndex),
              let vertexIndex = faces[faceIndex].first,
              vertices.indices.contains(Int(vertexIndex)) else { return nil }
        let point = transform * SIMD4<Float>(vertices[Int(vertexIndex)], 1)
        return SIMD3(point.x, point.y, point.z)
    }
}

@MainActor
final class ScannerDebugModel: NSObject, ObservableObject {
    @Published private(set) var summary: ScannerDebugSummary?
    @Published private(set) var meshCopyMilliseconds = 0.0
    let cameraFormatsDescription = ARWorldTrackingConfiguration.supportedVideoFormats.map {
        "\($0.captureDeviceType.rawValue) · \(Int($0.imageResolution.width))×\(Int($0.imageResolution.height)) · \($0.framesPerSecond) i/s"
    }.joined(separator: "\n")
    private var meshCopyRunning = false
    private var meshCopyGeneration = UUID()
    private var lastMeshCopy = Date.distantPast
    @Published private(set) var contourDiagnostic: String?
    @Published private(set) var lastReconstructionDiagnostic = "Aucune tentative enregistrée"
    private struct PlaneAttempt: Codable {
        let source: String
        let details: ScannerCeilingReconstruction.Diagnostics
    }
    private struct LiveAttempt: Codable {
        let seconds: Double
        let cameraXZ: [Double]?
        let walls: Int
        let meshFaces: Int
        let samplingStep: Int
        let minimumY: Double
        let sampledTriangles: Int
        let proposalIndex: Int
        let closuresEnabled: Bool
        let zones: Int
        let closures: Int
        let proposed: Bool
        let attempts: [PlaneAttempt]
    }
    private var liveAttempts: [LiveAttempt] = []
    private var diagnosticEvents: [String] = []
    private var diagnosticStarted = Date()
    private var totalDiagnosticAttempts = 0
    private func diagnosticMessage(_ stage: String) -> String {
        switch stage {
        case "contour": return "Contour non exploitable"
        case "insufficient_samples": return "Trop peu de points après filtrage du contour et de la hauteur"
        case "insufficient_plane_support": return "Trop peu de points sur un même plan"
        case "plane_support_below_70_percent": return "Le plan principal représente moins de 70 % de la surface retenue"
        case "degenerate_fit": return "Points trop peu répartis pour ajuster le plan"
        case "residual_above_4_cm": return "Écart au plan supérieur à 4 cm"
        case "slope_above_65_degrees": return "Inclinaison supérieure à 65°"
        case "success": return "Plan reconstitué"
        case "success_two_pans": return "Deux pans reconstitués · à valider ensemble"
        default: return "Reconstruction non évaluée"
        }
    }
    @Published var liveCeilingStatus = "Balayez les murs puis le plafond"
    @Published var liveCeilingLocked = false
    @Published var hasCeilingProposal = false
    private var proposedCeilingSurface: ScannerCeilingReconstruction.Surface?
    private var openContourAttempts = 0
    private var proposalIndex = 0
    private var lockedCeilingSurface: ScannerCeilingReconstruction.Surface?
    private var finalLockedCeilingSurface: ScannerCeilingReconstruction.Surface?
    @Published var placingBoundary = false
    @Published var boundaryInstruction = ""
    @Published var boundaryPoints: [SIMD3<Float>] = []
    @Published var virtualBoundaries: [ScannerCeilingReconstruction.Boundary] = []
    var boundaryLines: [SIMD3<Float>] = []
    var liveCeilingVertices: [SIMD3<Double>] = []
    var liveCeilingRevision = UUID()
    var liveARFrame: ARFrame? { arSession.currentFrame }
    private var liveRoom: PlaquistoRoomModel?
    private var roomAdapter = RoomPlanAdapter()
    func updateDocument(_ document: PlaquistoRoomDocument) {
        do { try PlaquistoRoomStore.save(document) }
        catch { errorMessage = error.localizedDescription }
    }
    private var liveGeneration = UUID()
    private var liveComputationRunning = false
    private var lastLiveComputation = Date.distantPast
    private var liveSessionDelegate: ScannerLiveRoomDelegate?
    private var previousIdleTimerDisabled: Bool?
    @Published var meshPreview: ScannerMeshPreview?
    @Published fileprivate(set) var errorMessage: String?
    @Published private(set) var statusText = "Prêt"
    @Published private(set) var isProcessing = false
    @Published private(set) var didFinish = false
    @Published private(set) var liveMeshAnchorCount = 0
    @Published private(set) var liveCeilingFaceCount = 0
    @Published private(set) var liveMeshConfigurationActive = false
    @Published private(set) var liveDelegateRetained = false
    @Published private(set) var highestObservedMeshY: Float?

    let roomPlanSupported = RoomCaptureSession.isSupported
    let meshClassificationSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)

    private let arSession = ARSession()
    private lazy var roomCaptureDelegate = ScannerRoomCaptureDelegate(model: self)
    private(set) lazy var captureView: RoomCaptureView = {
        let view = RoomCaptureView(frame: .zero, arSession: arSession)
        view.delegate = roomCaptureDelegate
        let observer = ScannerLiveRoomDelegate(model: self, downstream: view.captureSession.delegate)
        liveSessionDelegate = observer
        view.captureSession.delegate = observer
        return view
    }()

    // Conservés en mémoire pour vérifier que RoomPlan et les mesh utilisent bien
    // le même espace AR. Aucune persistance n'est faite dans ce prototype.
    private(set) var capturedRoom: CapturedRoom?
    private var meshSnapshots: [UUID: ScannerMeshAnchorSnapshot] = [:]
    private var captureStarted = false
    var cancellationRequested = false
    private var meshPollingTask: Task<Void, Never>?
    private var meshConfigurationRecoveryAttempts = 0

    var canStart: Bool { roomPlanSupported && meshClassificationSupported }

    func prepareForCapture() {
        roomAdapter = RoomPlanAdapter()
        liveAttempts = []
        diagnosticEvents = []
        diagnosticStarted = Date()
        totalDiagnosticAttempts = 0
        lastReconstructionDiagnostic = "Aucune tentative enregistrée"
        meshCopyGeneration = UUID()
        lastMeshCopy = .distantPast
        summary = nil
        clearLiveCeiling()
        liveRoom = nil
        finalLockedCeilingSurface = nil
        proposalIndex = 0
        virtualBoundaries = []
        boundaryLines = []
        cancelBoundary()
        contourDiagnostic = nil
        meshPreview = nil
        errorMessage = nil
        statusText = "Préparation…"
        isProcessing = false
        didFinish = false
        liveMeshAnchorCount = 0
        liveCeilingFaceCount = 0
        liveMeshConfigurationActive = false
        liveDelegateRetained = false
        highestObservedMeshY = nil
        capturedRoom = nil
        meshSnapshots.removeAll()
        captureStarted = false
        cancellationRequested = false
        meshConfigurationRecoveryAttempts = 0
    }

    func startCapture() {
        guard !captureStarted, canStart else { return }
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        captureStarted = true
        statusText = "Scan en cours"
        arSession.delegate = self

        let arConfiguration = ARWorldTrackingConfiguration()
        arConfiguration.sceneReconstruction = .meshWithClassification
        arConfiguration.planeDetection = [.horizontal, .vertical]
        arSession.run(arConfiguration, options: [.resetTracking, .removeExistingAnchors])

        var roomConfiguration = RoomCaptureSession.Configuration()
        roomConfiguration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: roomConfiguration)
        ensureMeshConfigurationIsActive()
        startMeshPolling()
        debugLog("Capture démarrée avec une ARSession commune")
    }

    func finishCapture() {
        guard captureStarted, !isProcessing else { return }
        isProcessing = true
        finalLockedCeilingSurface = lockedCeilingSurface
        clearLiveCeiling()
        statusText = "Traitement…"
        stopMeshPolling()
        // Freeze a final frame before stopping RoomPlan, without copying on UI.
        meshCopyGeneration = UUID()
        let generation = meshCopyGeneration
        let anchors = arSession.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Self.copyMesh(anchors) }.value
            guard let self, self.meshCopyGeneration == generation, self.captureStarted, !self.cancellationRequested else { return }
            self.applyMeshCopy(result)
            self.captureView.captureSession.stop(pauseARSession: false)
        }
    }

    func cancelCapture() {
        meshCopyGeneration = UUID()
        restoreIdleTimer()
        guard captureStarted else { return }
        cancellationRequested = true
        clearLiveCeiling()
        captureStarted = false
        stopMeshPolling()
        captureView.captureSession.stop(pauseARSession: true)
        arSession.pause()
        statusText = "Annulé"
        isProcessing = false
        debugLog("Capture annulée")
    }

    private struct MeshCopy {
        let snapshots: [UUID: ScannerMeshAnchorSnapshot]
        let maximumY: Float?
        let milliseconds: Double
    }
    nonisolated private static func copyMesh(_ anchors: [ARMeshAnchor]) -> MeshCopy {
        let started = Date()
        var snapshots: [UUID: ScannerMeshAnchorSnapshot] = [:]
        var maximumY: Float?
        for anchor in anchors {
            let geometry = anchor.geometry
            let vertices = (0..<geometry.vertices.count).map { vertexIndex in
                let vertex: (Float, Float, Float) = geometry.vertices[Int32(vertexIndex)]
                return SIMD3(vertex.0, vertex.1, vertex.2)
            }
            for vertex in vertices {
                let worldY = (anchor.transform * SIMD4<Float>(vertex, 1)).y
                if worldY.isFinite {
                    maximumY = max(maximumY ?? worldY, worldY)
                }
            }
            let faces = (0..<geometry.faces.count).map { geometry.faces[$0] }
            let classifications = (0..<geometry.faces.count).map { faceIndex -> UInt8 in
                guard let source = geometry.classification else { return 0 }
                return source[Int32(faceIndex)]
            }

            snapshots[anchor.identifier] = ScannerMeshAnchorSnapshot(
                identifier: anchor.identifier,
                transform: anchor.transform,
                vertices: vertices,
                faces: faces,
                classifications: classifications,
                ceilingFaceCount: classifications.reduce(0) { $0 + (Int($1) == ARMeshClassification.ceiling.rawValue ? 1 : 0) }
            )
        }
        return MeshCopy(snapshots: snapshots, maximumY: maximumY, milliseconds: Date().timeIntervalSince(started) * 1000)
    }
    private func applyMeshCopy(_ result: MeshCopy) {
        meshSnapshots = result.snapshots
        if let maximumY = result.maximumY {
            highestObservedMeshY = max(highestObservedMeshY ?? maximumY, maximumY)
        }
        meshCopyMilliseconds = result.milliseconds
        updateLiveMeshCounts()
    }

    private func startMeshPolling() {
        stopMeshPolling()
        meshPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                self?.pollMeshFromCurrentFrame()
            }
        }
    }

    private func stopMeshPolling() {
        meshPollingTask?.cancel()
        meshPollingTask = nil
    }

    private func pollMeshFromCurrentFrame() {
        guard captureStarted, !isProcessing, !cancellationRequested else { return }
        updateSessionDiagnostics()
        if !liveMeshConfigurationActive, meshConfigurationRecoveryAttempts < 3 {
            ensureMeshConfigurationIsActive()
        }
        guard let frame = arSession.currentFrame else { return }
        // One copy in flight, no callback backlog. Once accepted, only keep a
        // slower diagnostic snapshot; geometry is already frozen.
        guard !meshCopyRunning, Date().timeIntervalSince(lastMeshCopy) >= (liveCeilingLocked ? 1.2 : 0.4) else { return }
        meshCopyRunning = true
        lastMeshCopy = Date()
        let currentAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        let generation = meshCopyGeneration
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.copyMesh(currentAnchors) }.value
            guard let self else { return }
            self.meshCopyRunning = false
            guard self.meshCopyGeneration == generation, self.captureStarted, !self.isProcessing, !self.cancellationRequested else { return }
            self.applyMeshCopy(result)
            self.refreshLiveCeiling()
        }
    }

    private func clearLiveCeiling() {
        hasCeilingProposal = false
        proposedCeilingSurface = nil
        openContourAttempts = 0
        liveCeilingLocked = false
        lockedCeilingSurface = nil
        liveGeneration = UUID()
        liveCeilingVertices = []
        liveCeilingRevision = UUID()
        liveCeilingStatus = "Balayez les murs puis le plafond"
        lastLiveComputation = .distantPast
    }
    private func restoreIdleTimer() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }
    func unlockCeiling() { clearLiveCeiling() }
    func acceptCeilingProposal() {
        guard let surface = proposedCeilingSurface else { return }
        diagnosticEvents.append("\(Date().timeIntervalSince(diagnosticStarted)): proposal_accepted")
        liveGeneration = UUID()
        lockedCeilingSurface = surface
        liveCeilingVertices = surface.vertices
        liveCeilingLocked = true
        hasCeilingProposal = false
        proposedCeilingSurface = nil
        liveCeilingStatus = "Plafond validé et figé · \(surface.area.formatted(.number.precision(.fractionLength(2)))) m²"
        liveCeilingRevision = UUID()
    }
    func rejectCeilingProposal() {
        diagnosticEvents.append("\(Date().timeIntervalSince(diagnosticStarted)): proposal_rejected")
        proposalIndex += 1
        clearLiveCeiling()
        openContourAttempts = 3
        liveCeilingStatus = "Recherche d’une autre fermeture · continuez le scan"
    }

    func beginBoundary() {
        clearLiveCeiling()
        placingBoundary = true
        boundaryPoints = []
        boundaryInstruction = "Depuis la pièce à garder, visez un côté du passage avec la croix, au sol ou au plafond."
    }
    func cancelBoundary() {
        placingBoundary = false
        boundaryPoints = []
        liveCeilingRevision = UUID()
    }
    func markBoundaryPoint() {
        guard let frame = arSession.currentFrame, case .normal = frame.camera.trackingState else {
            boundaryInstruction = "Attendez que le suivi du téléphone soit stable."; return
        }
        let position = frame.camera.transform.columns.3
        let direction = -frame.camera.transform.columns.2
        let query = ARRaycastQuery(origin: SIMD3(position.x, position.y, position.z),
                                  direction: SIMD3(direction.x, direction.y, direction.z),
                                  allowing: .estimatedPlane, alignment: .any)
        guard let hit = arSession.raycast(query).first else {
            boundaryInstruction = "Aucune surface trouvée. Visez un angle visible au sol ou au plafond."; return
        }
        let p = hit.worldTransform.columns.3
        let point = SIMD3<Float>(p.x, p.y, p.z)
        if let first = boundaryPoints.first,
           simd_distance(SIMD2(first.x, first.z), SIMD2(point.x, point.z)) < 0.25 {
            boundaryInstruction = "Les points sont trop proches. Visez l’autre côté du passage."; return
        }
        boundaryPoints.append(point)
        liveCeilingRevision = UUID()
        boundaryInstruction = boundaryPoints.count == 1
            ? "Visez maintenant l’autre côté du passage, à la même limite de pièce."
            : "La ligne orange délimite la zone. Restez du côté à conserver, puis confirmez."
    }
    func confirmBoundary() {
        guard boundaryPoints.count == 2, let frame = arSession.currentFrame else { return }
        let a = boundaryPoints[0], b = boundaryPoints[1], camera = frame.camera.transform.columns.3
        let boundary = ScannerCeilingReconstruction.Boundary(start: SIMD2(Double(a.x), Double(a.z)),
            end: SIMD2(Double(b.x), Double(b.z)), keepPoint: SIMD2(Double(camera.x), Double(camera.z)))
        let v = boundary.end - boundary.start, p = boundary.keepPoint - boundary.start
        guard abs(v.x * p.y - v.y * p.x) / simd_length(v) >= 0.10 else {
            boundaryInstruction = "Reculez un peu dans la pièce que vous voulez conserver."; return
        }
        virtualBoundaries.append(boundary)
        boundaryLines.append(contentsOf: boundaryPoints)
        cancelBoundary()
        clearLiveCeiling()
    }
    func undoBoundary() {
        guard !virtualBoundaries.isEmpty else { return }
        virtualBoundaries.removeLast()
        boundaryLines.removeLast(2)
        clearLiveCeiling()
    }

    func receiveLiveRoom(_ room: CapturedRoom) {
        guard captureStarted, !isProcessing, !cancellationRequested else { return }
        liveRoom = roomAdapter.convert(room, preserving: liveRoom)
    }

    private func refreshLiveCeiling() {
        guard !liveCeilingLocked, !hasCeilingProposal, !placingBoundary, !liveComputationRunning, Date().timeIntervalSince(lastLiveComputation) >= 1.5,
              let room = liveRoom else { return }
        lastLiveComputation = Date()
        let walls = room.walls.map { wall -> ScannerCeilingReconstruction.Wall in
            .init(start: SIMD2(wall.start.x, wall.start.z), end: SIMD2(wall.end.x, wall.end.z))
        }
        let top = room.walls.map { Float($0.start.y + $0.height.effectiveValue) }.sorted()
        guard !top.isEmpty else { return }
        let minimumY = top[top.count / 2] - 0.5
        var triangles: [ScannerCeilingReconstruction.Triangle] = []
        // Bound live work; final reconstruction still uses the full snapshot.
        let count = meshSnapshots.values.reduce(0) { $0 + $1.faceCount }
        let step = max(1, (count + 5999) / 6000)
        for snapshot in meshSnapshots.values {
            for index in stride(from: 0, to: snapshot.faceCount, by: step) {
                let face = snapshot.faces[index]
                guard face.count == 3, face.allSatisfy({ snapshot.vertices.indices.contains(Int($0)) }) else { continue }
                let points = face.map { snapshot.transform * SIMD4<Float>(snapshot.vertices[Int($0)], 1) }
                let t = ScannerCeilingReconstruction.Triangle(
                    a: SIMD3(Double(points[0].x), Double(points[0].y), Double(points[0].z)),
                    b: SIMD3(Double(points[1].x), Double(points[1].y), Double(points[1].z)),
                    c: SIMD3(Double(points[2].x), Double(points[2].y), Double(points[2].z)))
                if t.area > 1e-7 && t.center.y >= Double(minimumY) && abs(t.normal.y) >= 0.42 { triangles.append(t) }
            }
        }
        let bounded = ScannerCeilingReconstruction.boundedWalls(walls, boundaries: virtualBoundaries)
        let generation = liveGeneration
        let shouldPropose = openContourAttempts >= 2
        let chosenProposal = proposalIndex
        let camera = arSession.currentFrame?.camera.transform.columns.3
        let keepPoint = camera.map { SIMD2<Double>(Double($0.x), Double($0.z)) }
        liveComputationRunning = true
        Task { [weak self] in
            let output = await Task.detached(priority: .utility) { () -> (Result<ScannerCeilingReconstruction.Surface, ScannerCeilingReconstruction.Failure>, ScannerCeilingReconstruction.Surface?, [PlaneAttempt], Int, Int) in
                var attempts: [PlaneAttempt] = []
                var zoneCount = 0, closureCount = 0
                func evaluate(_ candidate: [ScannerCeilingReconstruction.Wall], source: String) -> Result<ScannerCeilingReconstruction.Surface, ScannerCeilingReconstruction.Failure> {
                    // Sampled triangles retain their real area; scale the live
                    // support threshold with the stride, not the rendered area.
                    ScannerCeilingReconstruction.reconstruct(walls: candidate, triangles: triangles, minimumSupportArea: 0.15 / Double(step)) {
                        attempts.append(PlaneAttempt(source: source, details: $0))
                    }
                }
                func compute() -> (Result<ScannerCeilingReconstruction.Surface, ScannerCeilingReconstruction.Failure>, ScannerCeilingReconstruction.Surface?) {
                let result: Result<ScannerCeilingReconstruction.Surface, ScannerCeilingReconstruction.Failure> = bounded.map {
                    evaluate($0, source: "global")
                } ?? .failure(.contour)
                // Look for the local room even when the whole captured outline
                // closes: a kitchen + corridor must not silently lock as one room.
                if let keepPoint {
                    let zones = ScannerCeilingReconstruction.zoneProposals(walls: walls, keepPoint: keepPoint)
                    zoneCount = zones.count
                    for (index, candidate) in zones.enumerated().dropFirst(chosenProposal) {
                        if case .success(let surface) = evaluate(candidate, source: "zone_\(index)") {
                            return (result, surface)
                        }
                    }
                    if !zones.isEmpty { return (.failure(.observations), nil) }
                }
                if case .failure(.contour) = result, shouldPropose, let keepPoint {
                    let proposals = ScannerCeilingReconstruction.closureProposals(walls: walls, keepPoint: keepPoint)
                    closureCount = proposals.count
                    for (index, candidate) in proposals.enumerated().dropFirst(chosenProposal) {
                        if case .success(let surface) = evaluate(candidate, source: "closure_\(index)") {
                            return (result, surface)
                        }
                    }
                }
                if case .success(let surface) = result, surface.pans.count > 1 { return (result, surface) }
                return (result, nil)
                }
                let result = compute()
                return (result.0, result.1, attempts, zoneCount, closureCount)
            }.value
            guard let self else { return }
            self.liveComputationRunning = false
            guard self.liveGeneration == generation, self.captureStarted, !self.isProcessing else { return }
            self.totalDiagnosticAttempts += 1
            self.liveAttempts.append(LiveAttempt(seconds: Date().timeIntervalSince(self.diagnosticStarted),
                cameraXZ: keepPoint.map { [$0.x, $0.y] }, walls: walls.count, meshFaces: count,
                samplingStep: step, minimumY: Double(minimumY), sampledTriangles: triangles.count,
                proposalIndex: chosenProposal, closuresEnabled: shouldPropose, zones: output.3,
                closures: output.4, proposed: output.1 != nil, attempts: output.2))
            if self.liveAttempts.count > 120 { self.liveAttempts.removeFirst() }
            self.lastReconstructionDiagnostic = output.2.last.map { self.diagnosticMessage($0.details.stage) }
                ?? "Limites non exploitables : aucun plan évalué"
            if output.1 == nil, output.3 + output.4 > 0,
               chosenProposal >= max(output.3, output.4) {
                self.lastReconstructionDiagnostic = "Toutes les propositions disponibles ont été écartées"
            }
            if let proposal = output.1 {
                self.proposedCeilingSurface = proposal
                self.hasCeilingProposal = true
                self.liveCeilingVertices = proposal.vertices
                self.liveCeilingStatus = proposal.pans.count > 1
                    ? "Deux pans proposés en jaune · vérifiez la jonction puis validez"
                    : "Fermeture proposée en jaune · vérifiez puis validez"
                self.liveCeilingRevision = UUID()
                return
            }
            switch output.0 {
            case .success(let surface):
                self.liveCeilingVertices = surface.vertices
                self.lockedCeilingSurface = surface
                self.liveCeilingLocked = true
                self.liveCeilingStatus = "Plafond figé · \(surface.area.formatted(.number.precision(.fractionLength(2)))) m² (estimé)"
            case .failure(let reason):
                if case .contour = reason { self.openContourAttempts += 1 } else { self.openContourAttempts = 0 }
                // No raw triangle overlay: green means a complete reconstructed surface.
                self.liveCeilingVertices = []
                self.liveCeilingStatus = self.lastReconstructionDiagnostic
            }
            self.liveCeilingRevision = UUID()
        }
    }

    private func updateSessionDiagnostics() {
        if let configuration = arSession.configuration as? ARWorldTrackingConfiguration {
            liveMeshConfigurationActive = configuration.sceneReconstruction == .meshWithClassification
        } else {
            liveMeshConfigurationActive = false
        }
        liveDelegateRetained = arSession.delegate === self
    }

    private func ensureMeshConfigurationIsActive() {
        guard captureStarted, meshClassificationSupported else { return }
        guard let configuration = arSession.configuration as? ARWorldTrackingConfiguration else {
            meshConfigurationRecoveryAttempts += 1
            debugLog("Impossible de réactiver le mesh : configuration ARWorldTracking indisponible")
            return
        }
        guard configuration.sceneReconstruction != .meshWithClassification else {
            updateSessionDiagnostics()
            return
        }

        configuration.sceneReconstruction = .meshWithClassification
        configuration.planeDetection.formUnion([.horizontal, .vertical])
        meshConfigurationRecoveryAttempts += 1
        // Aucune option de réinitialisation : RoomPlan conserve son origine et son suivi.
        arSession.run(configuration)
        updateSessionDiagnostics()
        debugLog("Reconstruction du maillage réactivée après le démarrage de RoomPlan (tentative \(meshConfigurationRecoveryAttempts))")
    }

    private func remove(meshAnchors: [ARMeshAnchor]) {
        guard captureStarted, !isProcessing, !cancellationRequested else { return }
        for anchor in meshAnchors {
            meshSnapshots.removeValue(forKey: anchor.identifier)
        }
        updateLiveMeshCounts()
    }

    private func updateLiveMeshCounts() {
        liveMeshAnchorCount = meshSnapshots.count
        liveCeilingFaceCount = meshSnapshots.values.reduce(0) { $0 + $1.ceilingFaceCount }
    }

    func complete(with rawRoom: CapturedRoom) {
        guard captureStarted, !cancellationRequested else { return }
        restoreIdleTimer()
        // Ne pas relire currentFrame ici : le snapshot a été figé dans finishCapture.
        stopMeshPolling()
        capturedRoom = rawRoom
        var room = roomAdapter.convert(rawRoom, preserving: liveRoom)
        arSession.pause()
        captureStarted = false
        isProcessing = false

        let geometricAnalysis = analyzeGeometricCeilings(in: room)
        meshPreview = geometricAnalysis.preview
        if let surface = geometricAnalysis.preview.reconstruction {
            ScannerRoomBridge.apply(surface, to: &room, accepted: finalLockedCeilingSurface != nil,
                                    manuallyValidated: diagnosticEvents.contains { $0.contains("proposal_accepted") })
        }
        updateDocument(PlaquistoRoomDocument(room: room))
        let result = ScannerDebugSummary(
            walls: room.walls.count,
            floors: room.floors.count,
            doors: room.openings.filter { $0.kind == .door }.count,
            windows: room.openings.filter { $0.kind == .window }.count,
            openings: room.openings.filter { $0.kind == .passage }.count,
            objects: room.metadata.sourceObjectCount,
            meshConfigurationActive: liveMeshConfigurationActive,
            arDelegateRetained: liveDelegateRetained,
            meshAnchors: meshSnapshots.count,
            meshFaces: meshSnapshots.values.reduce(0) { $0 + $1.faceCount },
            ceilingMeshAnchors: meshSnapshots.values.filter { $0.ceilingFaceCount > 0 }.count,
            ceilingMeshFaces: meshSnapshots.values.reduce(0) { $0 + $1.ceilingFaceCount },
            geometricCeilingFaces: geometricAnalysis.candidateFaces,
            geometricHorizontalFaces: geometricAnalysis.horizontalFaces,
            geometricSlopedFaces: geometricAnalysis.slopedFaces,
            geometricCeilingArea: geometricAnalysis.candidateArea,
            roomFloorY: Double(geometricAnalysis.floorY),
            roomTopY: Double(geometricAnalysis.nominalTopY),
            geometricMinimumY: Double(geometricAnalysis.minimumCandidateY),
            meshMinimumY: geometricAnalysis.meshMinimumY.map(Double.init),
            meshMaximumY: geometricAnalysis.meshMaximumY.map(Double.init),
            upwardOrientedFaces: geometricAnalysis.upwardOrientedFaces,
            highestObservedMeshY: highestObservedMeshY.map(Double.init)
        )
        summary = result
        statusText = "Terminé"
        didFinish = true

        debugLog("RoomPlan — murs: \(result.walls), sols: \(result.floors), portes: \(result.doors), fenêtres: \(result.windows), ouvertures: \(result.openings), objets: \(result.objects)")
        debugLog("Session commune — configuration mesh active: \(result.meshConfigurationActive), delegate ARKit conservé: \(result.arDelegateRetained)")
        debugLog("ARKit — ancres mesh: \(result.meshAnchors), faces mesh: \(result.meshFaces), ancres plafond: \(result.ceilingMeshAnchors), faces plafond: \(result.ceilingMeshFaces)")
        debugLog(String(format: "Détection géométrique — sol y %.3f, haut nominal y %.3f, seuil y %.3f, mesh y %.3f…%.3f", geometricAnalysis.floorY, geometricAnalysis.nominalTopY, geometricAnalysis.minimumCandidateY, geometricAnalysis.meshMinimumY ?? .nan, geometricAnalysis.meshMaximumY ?? .nan))
        debugLog(String(format: "Candidats plafond — faces: %d, horizontales: %d, inclinées: %d, surface: %.2f m²", result.geometricCeilingFaces, result.geometricHorizontalFaces, result.geometricSlopedFaces, result.geometricCeilingArea))
        debugLog("Classifications ARKit — \(meshClassificationDescription())")
        if let firstSurface = room.walls.first {
            debugLog("Point mur Plaquisto témoin: \(firstSurface.start)")
        }
        if let firstMesh = meshSnapshots.values.first {
            debugLog("Origine mesh témoin: \(originDescription(firstMesh.transform))")
        }
        if let ceilingPoint = meshSnapshots.values.compactMap(\.firstCeilingWorldPoint).first {
            debugLog(String(format: "Point plafond dans le repère monde commun: x %.3f · y %.3f · z %.3f", ceilingPoint.x, ceilingPoint.y, ceilingPoint.z))
        }
    }

    
    private func analyzeGeometricCeilings(in room: PlaquistoRoomModel) -> ScannerGeometricCeilingAnalysis {
        let floorLevels = room.floors.compactMap { floor -> Float? in
            if let elevation = floor.referenceElevation { return Float(elevation) }
            let points = floor.boundaries.flatMap { $0 }
            return points.isEmpty ? nil : Float(points.reduce(0) { $0 + $1.y } / Double(points.count))
        }
        let wallTops = room.walls.map { Float($0.start.y + $0.height.effectiveValue) }
        let allWorldVertexHeights = meshSnapshots.values.flatMap { snapshot in
            snapshot.vertices.map { vertex -> Float in
                let world = snapshot.transform * SIMD4<Float>(vertex, 1)
                return world.y
            }
        }

        let floorY = median(floorLevels) ?? percentile(allWorldVertexHeights, fraction: 0.05) ?? 0
        let nominalTopY = median(wallTops) ?? percentile(allWorldVertexHeights, fraction: 0.95) ?? (floorY + 2.5)
        let roomHeight = max(nominalTopY - floorY, 1)
        // Bande supérieure volontairement assez large pour inclure le bas d'un rampant,
        // tout en écartant le sol et la plupart des meubles.
        let minimumCandidateY = max(floorY + 1.40, nominalTopY - max(1.50, roomHeight * 0.45))
        let horizontalNormalThreshold = Float(cos(15 * Double.pi / 180))
        let minimumVerticalNormalComponent: Float = 0.35

        var candidateFaces = 0
        var horizontalFaces = 0
        var slopedFaces = 0
        var candidateArea: Double = 0
        var upwardOrientedFaces = 0
        var previewTriangles: [ScannerMeshGroup: [SCNVector3]] = [:]
        var planeTriangles: [ScannerCeilingReconstruction.Triangle] = []

        for snapshot in meshSnapshots.values {
            for (faceIndex, face) in snapshot.faces.enumerated() where face.count >= 3 {
                let indices = face.prefix(3).map(Int.init)
                guard indices.allSatisfy(snapshot.vertices.indices.contains) else { continue }

                let points = indices.map { index -> SIMD3<Float> in
                    let world = snapshot.transform * SIMD4<Float>(snapshot.vertices[index], 1)
                    return SIMD3(world.x, world.y, world.z)
                }
                let edgeA = points[1] - points[0]
                let edgeB = points[2] - points[0]
                let crossProduct = simd_cross(edgeA, edgeB)
                let doubleArea = simd_length(crossProduct)
                guard doubleArea.isFinite, doubleArea > 0.000_001 else { continue }

                let centroidY = (points[0].y + points[1].y + points[2].y) / 3
                let verticalNormalComponent = abs(crossProduct.y / doubleArea)
                if verticalNormalComponent >= minimumVerticalNormalComponent {
                    upwardOrientedFaces += 1
                }
                let retained = centroidY >= minimumCandidateY && verticalNormalComponent >= minimumVerticalNormalComponent
                let appleCeiling = snapshot.classifications.indices.contains(faceIndex)
                    && Int(snapshot.classifications[faceIndex]) == ARMeshClassification.ceiling.rawValue
                if centroidY >= minimumCandidateY && verticalNormalComponent >= 0.42 {
                    let p = points.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }
                    planeTriangles.append(.init(a: p[0], b: p[1], c: p[2]))
                }
                let group: ScannerMeshGroup = appleCeiling
                    ? (retained ? .agreement : .appleOnly)
                    : (retained ? .filterOnly : .other)
                previewTriangles[group, default: []].append(contentsOf: points.map { SCNVector3($0.x, $0.y, $0.z) })
                guard retained else { continue }

                candidateFaces += 1
                candidateArea += Double(doubleArea / 2)
                if verticalNormalComponent >= horizontalNormalThreshold {
                    horizontalFaces += 1
                } else {
                    slopedFaces += 1
                }
            }
        }

        let walls = room.walls.map { wall -> ScannerCeilingReconstruction.Wall in
            .init(start: SIMD2(wall.start.x, wall.start.z), end: SIMD2(wall.end.x, wall.end.z))
        }
        let bounded = ScannerCeilingReconstruction.boundedWalls(walls, boundaries: virtualBoundaries)
        let wallDiagnostic = ScannerCeilingReconstruction.contourDiagnostic(walls: walls, boundaries: virtualBoundaries)
        var finalDetails: ScannerCeilingReconstruction.Diagnostics?
        let reconstruction: Result<ScannerCeilingReconstruction.Surface, ScannerCeilingReconstruction.Failure>
        if let locked = finalLockedCeilingSurface {
            reconstruction = .success(locked)
        } else if let bounded {
            reconstruction = ScannerCeilingReconstruction.reconstruct(walls: bounded, triangles: planeTriangles) { finalDetails = $0 }
        } else {
            reconstruction = .failure(.contour)
        }
        if let wallDiagnostic, let data = wallDiagnostic.data(using: .utf8),
           var report = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            report["reconstructionDiagnosticVersion"] = 1
            report["liveAttemptsTotal"] = totalDiagnosticAttempts
            report["liveAttemptsDropped"] = totalDiagnosticAttempts - liveAttempts.count
            report["lastLiveMessage"] = lastReconstructionDiagnostic
            report["events"] = diagnosticEvents
            report["finalUsedValidatedSurface"] = finalLockedCeilingSurface != nil
            report["finalPath"] = finalLockedCeilingSurface != nil ? "validated_surface" : (bounded == nil ? "invalid_boundaries" : "global_reconstruction")
            if case .success(let surface) = reconstruction {
                report["reconstructedPans"] = surface.pans.map {
                    ["area": $0.area, "slopeDegrees": $0.slopeDegrees, "fitErrorMeters": $0.fitError, "observedSupportArea": $0.observedSupportArea]
                }
            }
            report["liveRoomReceived"] = liveRoom != nil
            report["meshConfigurationActive"] = liveMeshConfigurationActive
            report["meshCopyMilliseconds"] = meshCopyMilliseconds
            if let encoded = try? JSONEncoder().encode(liveAttempts) {
                report["liveAttempts"] = try? JSONSerialization.jsonObject(with: encoded)
            }
            if let finalDetails, let encoded = try? JSONEncoder().encode(finalDetails) {
                report["finalPlaneAttempt"] = try? JSONSerialization.jsonObject(with: encoded)
            }
            if let encoded = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                contourDiagnostic = String(data: encoded, encoding: .utf8)
            } else { contourDiagnostic = wallDiagnostic }
        } else { contourDiagnostic = wallDiagnostic }
        let surface: ScannerCeilingReconstruction.Surface?
        let reconstructionMessage: String?
        switch reconstruction {
        case .success(let result): surface = result; reconstructionMessage = nil
        case .failure(let reason): surface = nil; reconstructionMessage = reason.message
        }
        return ScannerGeometricCeilingAnalysis(
            floorY: floorY,
            nominalTopY: nominalTopY,
            minimumCandidateY: minimumCandidateY,
            candidateFaces: candidateFaces,
            horizontalFaces: horizontalFaces,
            slopedFaces: slopedFaces,
            candidateArea: candidateArea,
            meshMinimumY: allWorldVertexHeights.min(),
            meshMaximumY: allWorldVertexHeights.max(),
            upwardOrientedFaces: upwardOrientedFaces,
            preview: ScannerMeshPreview(triangles: previewTriangles, wallEdges: room.walls.flatMap { wall in
                let corners = [wall.start, wall.effectiveEnd,
                               wall.effectiveEnd + RoomPoint(x: 0, y: wall.height.effectiveValue, z: 0),
                               wall.start + RoomPoint(x: 0, y: wall.height.effectiveValue, z: 0)]
                return [0,1,1,2,2,3,3,0].map { i in SCNVector3(Float(corners[i].x),Float(corners[i].y),Float(corners[i].z)) }
            }, reconstruction: surface, reconstructionMessage: reconstructionMessage)
        )
    }

    private func median(_ values: [Float]) -> Float? {
        percentile(values, fraction: 0.5)
    }

    private func percentile(_ values: [Float], fraction: Float) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clampedFraction = min(max(fraction, 0), 1)
        let index = Int((Float(sorted.count - 1) * clampedFraction).rounded())
        return sorted[index]
    }

    private func meshClassificationDescription() -> String {
        let labels: [Int: String] = [
            ARMeshClassification.none.rawValue: "aucune",
            ARMeshClassification.wall.rawValue: "mur",
            ARMeshClassification.floor.rawValue: "sol",
            ARMeshClassification.ceiling.rawValue: "plafond",
            ARMeshClassification.table.rawValue: "table",
            ARMeshClassification.seat.rawValue: "siège",
            ARMeshClassification.window.rawValue: "fenêtre",
            ARMeshClassification.door.rawValue: "porte"
        ]
        let counts = meshSnapshots.values
            .flatMap(\.classifications)
            .reduce(into: [Int: Int]()) { counts, classification in
                counts[Int(classification), default: 0] += 1
            }
        return counts.keys.sorted().map { rawValue in
            "\(labels[rawValue] ?? "inconnue \(rawValue)"): \(counts[rawValue, default: 0])"
        }.joined(separator: ", ")
    }

    func fail(_ error: Error?) {
        restoreIdleTimer()
        stopMeshPolling()
        arSession.pause()
        captureStarted = false
        isProcessing = false
        statusText = "Échec"
        errorMessage = error?.localizedDescription ?? "RoomPlan n’a pas produit de résultat exploitable."
        didFinish = true
        debugLog("Échec: \(errorMessage ?? "inconnu")")
    }

    private func originDescription(_ transform: simd_float4x4) -> String {
        let translation = transform.columns.3
        return String(format: "x %.3f · y %.3f · z %.3f", translation.x, translation.y, translation.z)
    }

    private func debugLog(_ message: String) {
        print("[Plaquisto Scanner Debug] \(message)")
    }
}

@objc(PLQScannerRoomCaptureDelegate)
private final class ScannerRoomCaptureDelegate: NSObject, RoomCaptureViewDelegate {
    private weak var model: ScannerDebugModel?

    init(model: ScannerDebugModel) {
        self.model = model
        super.init()
    }

    required init?(coder: NSCoder) {
        model = nil
        super.init()
    }

    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            Task { @MainActor in self.model?.errorMessage = error.localizedDescription }
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            if let error {
                self.model?.fail(error)
            } else {
                self.model?.complete(with: processedResult)
            }
        }
    }
}

extension ScannerDebugModel: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // Mesh is sampled from currentFrame, not copied a second time here.
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        // Replacing the full snapshot also removes disappeared anchors.
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in self.fail(error) }
    }
}
