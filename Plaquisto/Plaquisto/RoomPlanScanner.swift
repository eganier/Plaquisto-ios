import ARKit
import RoomPlan
import SceneKit
import SwiftUI
import CoreLocation

/// One bounded fix during capture; no background tracking or GPS in diagnostics.
@MainActor private final class ScanLocationCapture:NSObject,@preconcurrency CLLocationManagerDelegate {
    private let manager=CLLocationManager()
    private var result:((ScanLocationFix)->Void)?
    private var timeout:Task<Void,Never>?
    override init() { super.init(); manager.delegate=self; manager.desiredAccuracy=kCLLocationAccuracyNearestTenMeters }
    func start(_ result:@escaping (ScanLocationFix)->Void) {
        stop(); self.result=result
        timeout=Task { [weak self] in
            try? await Task.sleep(for:.seconds(20))
            guard !Task.isCancelled else { return }; self?.stop()
        }
        requestIfAuthorized()
    }
    func stop() { result=nil; timeout?.cancel(); timeout=nil; manager.stopUpdatingLocation() }
    private func requestIfAuthorized() {
        guard result != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse,.authorizedAlways: manager.requestLocation()
        default: stop()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) { requestIfAuthorized() }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let location=locations.last else { return }
        let fix=ScanLocationFix(latitude:location.coordinate.latitude,longitude:location.coordinate.longitude,
            horizontalAccuracy:location.horizontalAccuracy,capturedAt:location.timestamp)
        guard fix.isUsable(at:Date()) else { stop(); return }
        let callback=result; stop(); callback?(fix)
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) { stop() }
}


// Preserve RoomCaptureView's existing delegate: it still receives every event.
private final class ScannerLiveRoomDelegate: NSObject, RoomCaptureSessionDelegate {
    weak var model: ScannerDebugModel?
    let downstream: RoomCaptureSessionDelegate?
    private let generationLock = NSLock()
    private var generation = UUID()
    func activate(_ id: UUID) { generationLock.lock(); generation = id; generationLock.unlock() }
    private func snapshotGeneration() -> UUID {
        generationLock.lock(); defer { generationLock.unlock() }; return generation
    }
    init(model: ScannerDebugModel, downstream: RoomCaptureSessionDelegate?) {
        self.model = model
        self.downstream = downstream
    }
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let token = snapshotGeneration()
        downstream?.captureSession(session, didUpdate: room)
        Task { @MainActor in model?.receiveLiveRoom(room, generation: token) }
    }
    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
        let token = snapshotGeneration()
        downstream?.captureSession(session, didAdd: room)
        Task { @MainActor in model?.receiveLiveRoom(room, generation: token) }
    }
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        let token = snapshotGeneration()
        downstream?.captureSession(session, didChange: room)
        Task { @MainActor in model?.receiveLiveRoom(room, generation: token) }
    }
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
        let token = snapshotGeneration()
        downstream?.captureSession(session, didRemove: room)
        Task { @MainActor in model?.receiveLiveRoom(room, generation: token) }
    }
    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        downstream?.captureSession(session, didProvide: instruction)
    }
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        downstream?.captureSession(session, didStartWith: configuration)
    }
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        let token = snapshotGeneration()
        // Keep native preview callbacks; Plaquisto presents its editable result
        // after the single RoomBuilder pass.
        downstream?.captureSession(session, didEndWith: data, error: error)
        Task { @MainActor in await model?.processEndedRoom(data, error: error, generation: token) }
    }
}

struct ScannerRoomCaptureRepresentable: UIViewRepresentable {
    let model: ScannerDebugModel

    func makeUIView(context: Context) -> RoomCaptureView {
        model.captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}


@MainActor
final class ScannerDebugModel: NSObject, ObservableObject {
    private let locationCapture=ScanLocationCapture()
    @Published private(set) var campaign = ScanCampaignDraft()
    @Published private(set) var liveOverview = ScanLiveOverview()
    @Published private(set) var currentRoomName = "Pièce à identifier"
    private var referenceGroupID = UUID()
    private var activeChunkID = UUID()
    var activeOverviewID: UUID { activeChunkID }
    private var processingChunkID: UUID?
    @Published private(set) var finishingCampaign = false
    private var lastLiveCheckpoint = Date.distantPast
    private var lastOverviewUpdate = Date.distantPast
    private var currentRawRoom: CapturedRoom?
    private var chunkStartedAt = Date()
    private var finishWatchdog: Task<Void, Never>?
    @Published private(set) var needsSaveRetry = false
    private var retryMarksComplete = false
    private var transitionWatchdog: Task<Void, Never>?
    private var chunkProcessingTask: Task<Void, Never>?
    private struct PendingChunkContext {
        let id: UUID
        let groupID: UUID
        let campaignID: UUID
        let startedAt: Date
        let adapter: RoomPlanAdapter
        let liveRoom: PlaquistoRoomModel?
        let meshActive: Bool
        let delegateRetained: Bool
    }
    @Published private(set) var summary: ScannerDebugSummary?
    @Published private(set) var latestDocument: PlaquistoRoomDocument?
    @Published private(set) var meshCopyMilliseconds = 0.0
    let cameraFormatsDescription = ARWorldTrackingConfiguration.supportedVideoFormats.map {
        "\($0.captureDeviceType.rawValue) · \(Int($0.imageResolution.width))×\(Int($0.imageResolution.height)) · \($0.framesPerSecond) i/s"
    }.joined(separator: "\n")
    @Published private(set) var contourDiagnostic: String?
    @Published private(set) var lastReconstructionDiagnostic = "Plafonds : création après scan uniquement"
    private var diagnosticEvents: [String] = []
    private var diagnosticStarted = Date()
    private var liveRoom: PlaquistoRoomModel?
    private var roomAdapter = RoomPlanAdapter()
    func updateDocument(_ document: PlaquistoRoomDocument) {
        do {
            try PlaquistoRoomStore.save(document)
            latestDocument = document
        }
        catch { errorMessage = error.localizedDescription }
    }
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

    // One native session, configured by RoomPlan. Never restart/reposition it
    // as the user walks between rooms.
    private var arSession: ARSession { captureView.captureSession.arSession }
    private lazy var roomCaptureDelegate = ScannerRoomCaptureDelegate(model: self)
    private(set) lazy var captureView: RoomCaptureView = makeCaptureView()

    private func makeCaptureView() -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero, arSession: ARSession())
        view.isModelEnabled = true
        view.delegate = roomCaptureDelegate
        let observer = ScannerLiveRoomDelegate(model: self, downstream: view.captureSession.delegate)
        liveSessionDelegate = observer
        view.captureSession.delegate = observer
        return view
    }

    // Latest diagnostic result. Campaign checkpoints are persisted separately.
    private(set) var capturedRoom: CapturedRoom?
    private var captureStarted = false
    var cancellationRequested = false

    var canStart: Bool { roomPlanSupported }

    func prepareForCapture() {
        locationCapture.stop()
        finishWatchdog?.cancel()
        needsSaveRetry = false
        transitionWatchdog?.cancel()
        chunkProcessingTask?.cancel()
        campaign = ScanCampaignDraft()
        liveOverview = ScanLiveOverview()
        lastLiveCheckpoint = .distantPast
        lastOverviewUpdate = .distantPast
        referenceGroupID = UUID()
        activeChunkID = UUID()
        processingChunkID = nil
        finishingCampaign = false
        currentRawRoom = nil
        currentRoomName = "Pièce à identifier"
        roomAdapter = RoomPlanAdapter()
        diagnosticEvents = []
        diagnosticStarted = Date()
        summary = nil
        latestDocument = nil
        liveRoom = nil
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
        captureStarted = false
        cancellationRequested = false
        // A new user-requested scan gets a fresh native session. No room
        // transition, coordinate reset or restart occurs during that capture.
        captureView = makeCaptureView()
    }

    func startCapture() {
        guard !captureStarted, canStart else { return }
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        captureStarted = true
        let locationCampaignID=campaign.id
        locationCapture.start { [weak self] fix in
            guard let self, self.campaign.id == locationCampaignID, !self.cancellationRequested else { return }
            self.campaign.captureLocation=fix
            if !self.campaign.chunks.isEmpty { _ = self.persistCampaign() }
        }
        chunkStartedAt = Date()
        statusText = "Scan en cours"

        var roomConfiguration = RoomCaptureSession.Configuration()
        roomConfiguration.isCoachingEnabled = true
        _ = captureView
        liveSessionDelegate?.activate(activeChunkID)
        // RoomPlan owns acquisition. No custom mesh configuration, ceiling
        // polling or world-origin correction. Ceilings are edited after capture.
        captureView.captureSession.run(configuration: roomConfiguration)
        recordCaptureEvent("capture_started", "Acquisition RoomPlan native unique")
        recordCaptureEvent("ceiling_postscan_only", "Aucune recherche ni validation de plafond pendant le scan ; création explicite dans l’éditeur")
        debugLog("Capture native démarrée")
    }

    func finishCapture() {
        guard captureStarted, !finishingCampaign else { return }
        finishingCampaign = true
        let campaignID = campaign.id
        finishWatchdog?.cancel()
        finishWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard !Task.isCancelled, let self, self.campaign.id == campaignID, !self.didFinish else { return }
            self.chunkProcessingTask?.cancel()
            self.transitionWatchdog?.cancel()
            self.captureStarted = false
            self.cancellationRequested = true
            self.captureView.captureSession.stop(pauseARSession: true)
            self.arSession.pause()
            self.restoreIdleTimer()
            self.campaign.assemblyMessage = "Le raffinement a pris trop de temps. Les portions sauvegardées sont conservées et restent à contrôler."
            self.finishDurably()
        }
        if isProcessing { statusText = "Finalisation du relevé…"; return }
        finishNativeCapture()
    }

    private func finishNativeCapture() {
        guard captureStarted, !isProcessing else { return }
        recordCaptureEvent("room_stopping", "Fin demandée par l’utilisateur")
        // Keep a recoverable draft before Apple's final processing.
        guard checkpointLiveRoom() else { fail(nil); return }
        isProcessing = true
        processingChunkID = activeChunkID
        statusText = "Finalisation du relevé…"
        let campaignID = campaign.id
        let chunkID = activeChunkID
        transitionWatchdog?.cancel()
        transitionWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, self.campaign.id == campaignID,
                  self.activeChunkID == chunkID, self.captureStarted, self.isProcessing else { return }
            self.errorMessage = "Le traitement de la pièce n’a pas abouti. Les pièces déjà sauvegardées restent disponibles."
            self.fail(nil)
        }
        captureView.captureSession.stop(pauseARSession: true)
    }

    func cancelCapture() {
        locationCapture.stop()
        recordCaptureEvent("capture_cancelled", "Annulation utilisateur")
        finishWatchdog?.cancel()
        transitionWatchdog?.cancel()
        chunkProcessingTask?.cancel()
        if captureStarted, !isProcessing { _ = checkpointLiveRoom() }
        retryMarksComplete = false
        if !campaign.chunks.isEmpty { needsSaveRetry = !persistCampaign() }
        restoreIdleTimer()
        cancellationRequested = true
        processingChunkID = nil
        guard captureStarted else { return }
        captureStarted = false
        captureView.captureSession.stop(pauseARSession: true)
        arSession.pause()
        statusText = "Annulé"
        isProcessing = false
        debugLog("Capture annulée")
    }

    private func restoreIdleTimer() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }
    func receiveLiveRoom(_ room: CapturedRoom, generation: UUID) {
        updateSessionDiagnostics()
        guard generation == activeChunkID, captureStarted, !isProcessing, !cancellationRequested else { return }
        currentRawRoom = room
        currentRoomName = ScanRoomUsage.proposedName(RoomPlanAdapter.usages(in: room))
        liveRoom = roomAdapter.convert(room, preserving: liveRoom)
        if let liveRoom, Date().timeIntervalSince(lastOverviewUpdate) >= 0.4 {
            lastOverviewUpdate = Date()
            liveOverview.update(id: activeChunkID, room: liveRoom)
        }
        // Portable periodic recovery, without claiming that a draft can resume AR.
        if Date().timeIntervalSince(lastLiveCheckpoint) >= 5,
           let liveRoom, (try? PlaquistoRoomDocument(room: liveRoom).validate()) != nil {
            _ = checkpointLiveRoom(isProcessing: false)
        }
    }

    @discardableResult private func checkpointLiveRoom(isProcessing: Bool = true) -> Bool {
        guard var room = liveRoom, !room.walls.isEmpty || !room.floors.isEmpty else { return true }
        room.name = currentRoomName
        let usages = currentRawRoom.map(RoomPlanAdapter.usages(in:)) ?? []
        let chunk = ScanRoomChunk(id: activeChunkID, referenceGroupID: referenceGroupID,
            name: currentRoomName, usages: usages, document: PlaquistoRoomDocument(room: room),
            capturedAt: chunkStartedAt, processingPending: true)
        // Invalid transient geometry must not overwrite the last sound checkpoint.
        do { try chunk.document.validate() }
        catch {
            if campaign.chunks.contains(where: { $0.id == activeChunkID }) { return true }
            errorMessage = "La géométrie en cours n’a pas pu être sauvegardée : \(error.localizedDescription)"
            return false
        }
        campaign.upsert(chunk, preserveName: false)
        liveOverview.update(id: activeChunkID, room: room, isProcessing: isProcessing)
        lastLiveCheckpoint = Date()
        return persistCampaign()
    }

    private func updateSessionDiagnostics() {
        if let configuration = arSession.configuration as? ARWorldTrackingConfiguration {
            liveMeshConfigurationActive = configuration.sceneReconstruction == .meshWithClassification
        } else {
            liveMeshConfigurationActive = false
        }
        liveDelegateRetained = arSession.delegate != nil
    }

    private func recordCaptureEvent(_ name: String, _ detail: String) {
        var events = campaign.captureEvents ?? []
        events.append(.init(roomID: activeChunkID, name: name, detail: detail))
        if events.count > 500 { events.removeFirst(events.count - 500) }
        campaign.captureEvents = events
        if !campaign.chunks.isEmpty { _ = persistCampaign() }
    }

    func processEndedRoom(_ data: CapturedRoomData, error: Error?, generation: UUID) async {
        guard generation == activeChunkID, captureStarted, !cancellationRequested else { return }
        recordCaptureEvent("room_ended", error?.localizedDescription ?? "Fin de capture native sans erreur")
        guard let token = processingChunkID else {
            // An unexpected native termination must not be presented as success.
            if !isProcessing { fail(error) }
            return
        }
        processingChunkID = nil // Consume once; late/duplicate callbacks cannot append.
        if let error { fail(error); return }
        transitionWatchdog?.cancel()
        let context = PendingChunkContext(id: token, groupID: referenceGroupID, campaignID: campaign.id,
            startedAt: chunkStartedAt, adapter: roomAdapter, liveRoom: liveRoom,
            meshActive: liveMeshConfigurationActive, delegateRetained: liveDelegateRetained)
        arSession.pause()
        let previous = chunkProcessingTask
        chunkProcessingTask = Task { [weak self] in
            await previous?.value // Ordered names/checkpoints, bounded CPU concurrency.
            guard let self, !Task.isCancelled, self.campaign.id == context.campaignID,
                  self.captureStarted, !self.cancellationRequested else { return }
            do {
                let room = try await RoomBuilder(options: []).capturedRoom(from: data)
                guard !Task.isCancelled, self.campaign.id == context.campaignID,
                      self.captureStarted, !self.cancellationRequested else { return }
                await self.complete(with: room, context: context)
            } catch {
                guard !Task.isCancelled, self.campaign.id == context.campaignID,
                      self.captureStarted, !self.cancellationRequested else { return }
                // Keep the recoverable draft when native final processing fails.
                self.campaign.assemblyMessage = "Une portion du relevé reste à vérifier : \(error.localizedDescription)"
                self.persistCampaign()
                self.finalizeCampaign()
            }
        }
    }

    @discardableResult private func persistCampaign() -> Bool {
        refreshPersistedDiagnostic()
        do { try ScanCampaignStore.save(campaign); return true }
        catch { errorMessage = "Impossible de sauvegarder le relevé : \(error.localizedDescription)"; return false }
    }

    private func refreshPersistedDiagnostic() {
        // Save the actual pipeline counters, not just the final wall geometry.
        // Called with periodic checkpoints and on completion/error/cancellation.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func object<T: Encodable>(_ value: T) -> Any? {
            guard let data = try? encoder.encode(value) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        var report: [String: Any] = [
            "format": "plaquisto-capture-diagnostic-v1",
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "campaignID": campaign.id.uuidString,
            "chunkID": activeChunkID.uuidString,
            "meshConfigurationActive": liveMeshConfigurationActive,
            "meshAnchors": liveMeshAnchorCount,
            "ceilingWorkflow": "postscan_manual",
            "wallGeometry": "native_polygon_corners",
            "meshSamplingEnabled": false,
            "meshFaces": 0,
            "ceilingMeshFaces": liveCeilingFaceCount,
            "liveRoomReceived": liveRoom != nil,
            "liveAttemptsTotal": 0,
            "liveAttemptsDropped": 0,
            "status": statusText,
            "lastLiveMessage": lastReconstructionDiagnostic,
            "hasCeilingProposal": false,
            "confirmedCeilings": 0,
            "liveAttempts": [],
            "captureEvents": object(campaign.captureEvents ?? []) ?? []
        ]
        if let summary { report["summary"] = object(summary) }
        if let contourDiagnostic { report["captureNote"] = contourDiagnostic }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            campaign.captureDiagnostic = String(data: data, encoding: .utf8)
        }
    }

    private func finalizeCampaign() {
        guard !Task.isCancelled, captureStarted, !cancellationRequested else { return }
        transitionWatchdog?.cancel()
        restoreIdleTimer()
        arSession.pause()
        captureStarted = false
        recordCaptureEvent("capture_processed", "Résultat RoomPlan transmis à l’éditeur")
        finishDurably()
    }

    /// Completion is durable before the UI claims success; failure keeps an
    /// explicit retry path and the entire in-memory survey intact.
    private func finishDurably() {
        locationCapture.stop()
        finishWatchdog?.cancel()
        isProcessing = false
        retryMarksComplete = true
        refreshPersistedDiagnostic()
        do {
            campaign = try ScanCampaignStore.completing(campaign)
            needsSaveRetry = false
            statusText = "Relevé sauvegardé"
        } catch {
            needsSaveRetry = true
            statusText = "Capture terminée · sauvegarde à réessayer"
            errorMessage = "Le relevé est conservé en mémoire, mais sa sauvegarde n’a pas abouti : \(error.localizedDescription)"
        }
        didFinish = true
    }

    func retryCampaignSave() {
        guard needsSaveRetry else { return }
        if retryMarksComplete { finishDurably() }
        else { needsSaveRetry = !persistCampaign() }
        if !needsSaveRetry { errorMessage = nil }
    }

    private func complete(with rawRoom: CapturedRoom, context: PendingChunkContext) async {
        guard !Task.isCancelled, campaign.id == context.campaignID, captureStarted, !cancellationRequested else { return }
        // Ne pas relire currentFrame ici : le snapshot a été figé dans finishCapture.
        capturedRoom = rawRoom
        var room = context.adapter.convert(rawRoom, preserving: context.liveRoom)
        guard !room.walls.isEmpty || !room.floors.isEmpty else {
            // Keep the last recoverable checkpoint if native processing returns no geometry.
            if campaign.chunks.isEmpty { fail(nil) }
            else { finalizeCampaign() }
            return
        }
        let usages = RoomPlanAdapter.usages(in: rawRoom)
        room.name = ScanRoomUsage.proposedName(usages)
        let chunk = ScanRoomChunk(id: context.id, referenceGroupID: context.groupID,
            name: room.name ?? "Pièce à identifier", usages: usages,
            document: PlaquistoRoomDocument(room: room), capturedAt: context.startedAt, processingPending: false)
        campaign.upsert(chunk, preserveName: false)
        liveOverview.update(id: context.id, room: room)
        // Persist native portable geometry, with no automatic ceiling inference.
        guard persistCampaign() else { fail(nil); return }
        do {
            let folder = ScanCampaignStore.directory.appendingPathComponent(context.campaignID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(rawRoom).write(to: folder.appendingPathComponent(context.id.uuidString + ".roomplan"), options: .atomic)
        } catch { errorMessage = "Le modèle portable est sauvegardé, mais pas son cache RoomPlan : \(error.localizedDescription)" }
        contourDiagnostic = "Capture RoomPlan native. Plafonds à créer après le scan dans Modifier le plan. Les contours de murs proviennent de polygonCorners, sans reconstruction depuis un plafond."
        meshPreview = nil
        var document = PlaquistoRoomDocument(room: room)
        if let index = campaign.chunks.firstIndex(where: { $0.id == context.id }) {
            room.name = campaign.chunks[index].name
            document.room.name = room.name
            campaign.chunks[index].document = document
        }
        liveOverview.update(id: context.id, room: room)
        latestDocument = document
        updateDocument(document)
        let result = ScannerDebugSummary(
            walls: room.walls.count,
            floors: room.floors.count,
            doors: room.openings.filter { $0.kind == .door }.count,
            windows: room.openings.filter { $0.kind == .window }.count,
            openings: room.openings.filter { $0.kind == .passage }.count,
            objects: room.metadata.sourceObjectCount,
            meshConfigurationActive: context.meshActive,
            arDelegateRetained: context.delegateRetained,
            meshAnchors: 0,
            meshFaces: 0,
            ceilingMeshAnchors: 0,
            ceilingMeshFaces: 0,
            geometricCeilingFaces: 0,
            geometricHorizontalFaces: 0,
            geometricSlopedFaces: 0,
            geometricCeilingArea: 0,
            roomFloorY: room.walls.map(\.start.y).min() ?? 0,
            roomTopY: room.walls.map { $0.start.y+$0.height.effectiveValue }.max() ?? 0,
            geometricMinimumY: 0,
            meshMinimumY: nil,
            meshMaximumY: nil,
            upwardOrientedFaces: 0,
            highestObservedMeshY: nil
        )
        summary = result

        debugLog("RoomPlan — murs: \(result.walls), sols: \(result.floors), portes: \(result.doors), fenêtres: \(result.windows), ouvertures: \(result.openings), objets: \(result.objects)")
        debugLog("Session commune — configuration mesh active: \(result.meshConfigurationActive), delegate ARKit conservé: \(result.arDelegateRetained)")
        debugLog("ARKit — ancres mesh: \(result.meshAnchors), faces mesh: \(result.meshFaces), ancres plafond: \(result.ceilingMeshAnchors), faces plafond: \(result.ceilingMeshFaces)")
        debugLog("Plafonds : création après scan uniquement, sans reconstruction automatique")
        debugLog(String(format: "Candidats plafond — faces: %d, horizontales: %d, inclinées: %d, surface: %.2f m²", result.geometricCeilingFaces, result.geometricHorizontalFaces, result.geometricSlopedFaces, result.geometricCeilingArea))
        if let firstSurface = room.walls.first {
            debugLog("Point mur Plaquisto témoin: \(firstSurface.start)")
        }
        guard persistCampaign() else { fail(nil); return }
        finalizeCampaign()
    }

    func fail(_ error: Error?) {
        recordCaptureEvent("capture_failed", error?.localizedDescription ?? "Erreur de capture")
        finishWatchdog?.cancel()
        transitionWatchdog?.cancel()
        chunkProcessingTask?.cancel()
        if captureStarted, !isProcessing { _ = checkpointLiveRoom() }
        cancellationRequested = true
        processingChunkID = nil
        restoreIdleTimer()
        captureStarted = false
        captureView.captureSession.stop(pauseARSession: true)
        arSession.pause()
        isProcessing = false
        statusText = "Échec"
        errorMessage = error?.localizedDescription ?? errorMessage ?? "RoomPlan n’a pas produit de résultat exploitable."
        campaign.assemblyMessage = "Capture interrompue. Les pièces déjà enregistrées restent disponibles."
        retryMarksComplete = false
        if !campaign.chunks.isEmpty { needsSaveRetry = !persistCampaign() }
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
        false
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        // Results are processed exactly once by processEndedRoom(_:error:).
    }
}
