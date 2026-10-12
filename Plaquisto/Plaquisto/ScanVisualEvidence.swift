import ARKit
import CoreImage
import SwiftUI
import simd

/// Experimental acquisition is gated by the actual target, not the UI theme.
enum ScanEvidencePolicy {
    static var enabled: Bool { isEnabled(bundleID: Bundle.main.bundleIdentifier) }
    static func isEnabled(bundleID: String?) -> Bool { bundleID == "fr.plaquisto.lab" }
    static let lifetime: TimeInterval = 24 * 60 * 60
    static let maximumFrames = 120
    static let maximumRoomBytes = 24 * 1024 * 1024
    static let maximumCacheBytes = 72 * 1024 * 1024
}

/// Calibration/depth always use unrotated sensor coordinates. JPEG orientation
/// is recorded separately so presenting a portrait photo never rotates 3D data.
struct ScanEvidenceFrame: Codable, Identifiable {
    var id = UUID()
    var capturedAt = Date()
    var timestamp: Double
    var cameraToWorld: [Float] // column-major, ARKit's original world reference
    var imageWidth: Int
    var imageHeight: Int
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float
    var depthWidth: Int
    var depthHeight: Int
    var depths: [Float] // metres; zero means missing/low confidence
    var photoQuarterTurns: Int? = nil // clockwise; nil reads early unrotated caches

    var transform: simd_float4x4? {
        guard cameraToWorld.count == 16, cameraToWorld.allSatisfy(\.isFinite) else { return nil }
        let m = simd_float4x4(columns: (
            SIMD4(cameraToWorld[0], cameraToWorld[1], cameraToWorld[2], cameraToWorld[3]),
            SIMD4(cameraToWorld[4], cameraToWorld[5], cameraToWorld[6], cameraToWorld[7]),
            SIMD4(cameraToWorld[8], cameraToWorld[9], cameraToWorld[10], cameraToWorld[11]),
            SIMD4(cameraToWorld[12], cameraToWorld[13], cameraToWorld[14], cameraToWorld[15])))
        guard abs(simd_determinant(m)) > 0.5 else { return nil }
        return m
    }
    var position: SIMD3<Float>? { transform.map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) } }
    var hasDepth: Bool { depthWidth > 0 && depthHeight > 0 && depths.count == depthWidth * depthHeight && depths.contains { $0 > 0 } }

    /// Normalized image coordinates plus optical-axis distance, not ray length.
    func project(_ point: RoomPoint) -> SIMD3<Float>? {
        guard point.finite, imageWidth > 0, imageHeight > 0,
              fx.isFinite, fy.isFinite, cx.isFinite, cy.isFinite, fx > 0, fy > 0,
              let transform else { return nil }
        let p = simd_inverse(transform) * SIMD4(Float(point.x), Float(point.y), Float(point.z), 1)
        let depth = -p.z
        guard depth.isFinite, depth > 0.15 else { return nil }
        let u = (fx * p.x / depth + cx) / Float(imageWidth)
        let v = (cy - fy * p.y / depth) / Float(imageHeight)
        guard u.isFinite, v.isFinite else { return nil }
        return SIMD3(u, v, depth)
    }
    func measuredDepth(at p: SIMD3<Float>) -> Float? {
        guard p.x >= 0, p.x < 1, p.y >= 0, p.y < 1,
              depthWidth > 0, depthHeight > 0, depths.count == depthWidth * depthHeight else { return nil }
        let value = depths[Int(p.y * Float(depthHeight)) * depthWidth + Int(p.x * Float(depthWidth))]
        return value.isFinite && value > 0 ? value : nil
    }
    func photoPoint(_ p: SIMD3<Float>) -> CGPoint {
        switch photoQuarterTurns ?? 0 {
        case 1: return CGPoint(x: CGFloat(1 - p.y), y: CGFloat(p.x))
        case 2: return CGPoint(x: CGFloat(1 - p.x), y: CGFloat(1 - p.y))
        case 3: return CGPoint(x: CGFloat(p.y), y: CGFloat(1 - p.x))
        default: return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        }
    }
}

enum ScanEvidenceAnalysis {
    enum Finding: String {
        case surface = "Profondeur proche du mur"
        case passage = "Profondeur derrière la zone"
        case mixed = "Observations contradictoires"
        case unknown = "Profondeur insuffisante"
    }
    struct Observation: Identifiable {
        var id: UUID { frame.id }
        let frame: ScanEvidenceFrame
        let visible: Int
        let near: Int
        let behind: Int
        let occluded: Int
    }
    struct Result {
        let finding: Finding
        let observations: [Observation]
        let independentViews: Int
    }

    /// Samples interiors, not just the frame of a doorway: observing the jambs
    /// must NEVER be interpreted as evidence that the opening is a solid wall.
    static func samples(triangles: [RoomPoint]) -> [RoomPoint] {
        var result: [RoomPoint] = []
        guard triangles.count % 3 == 0 else { return [] }
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let a = triangles[i], b = triangles[i+1], c = triangles[i+2]
            for weights in [(0.2, 0.2), (0.2, 0.6), (0.6, 0.2), (1.0/3, 1.0/3)] {
                result.append(a * weights.0 + b * weights.1 + c * (1 - weights.0 - weights.1))
            }
        }
        return result
    }
    static func analyze(triangles: [RoomPoint], frames: [ScanEvidenceFrame]) -> Result {
        let points = samples(triangles: triangles)
        guard !points.isEmpty else { return .init(finding: .unknown, observations: [], independentViews: 0) }
        let observations = frames.compactMap { frame -> Observation? in
            var visible = 0, near = 0, behind = 0, occluded = 0
            for point in points {
                guard let p = frame.project(point), p.x > 0.03, p.x < 0.97, p.y > 0.03, p.y < 0.97 else { continue }
                visible += 1
                guard let depth = frame.measuredDepth(at: p) else { continue }
                let delta = depth - p.z
                if abs(delta) <= 0.10 { near += 1 }
                else if delta > 0.25 { behind += 1 }
                else if delta < -0.15 { occluded += 1 }
            }
            guard visible >= max(3, points.count / 2) else { return nil }
            return .init(frame: frame, visible: visible, near: near, behind: behind, occluded: occluded)
        }.sorted { $0.visible == $1.visible ? $0.frame.timestamp < $1.frame.timestamp : $0.visible > $1.visible }
        var independent: [Observation] = []
        for observation in observations where observation.near + observation.behind >= max(3, points.count * 3 / 4) {
            guard let position = observation.frame.position,
                  independent.allSatisfy({ simd_distance($0.frame.position!, position) >= 0.20 }) else { continue }
            independent.append(observation)
        }
        // Photos are useful for human review even when RoomPlan does not expose
        // sceneDepth. Never manufacture a geometric verdict from RGB alone.
        let near = independent.filter { $0.near >= points.count * 3 / 4 && $0.behind == 0 }.count
        let behind = independent.filter { $0.behind >= points.count * 3 / 4 && $0.near == 0 }.count
        let mixed = independent.contains { $0.near > 0 && $0.behind > 0 } || (near > 0 && behind > 0)
        let finding: Finding = mixed ? .mixed : near >= 2 ? .surface : behind >= 2 ? .passage : .unknown
        return .init(finding: finding, observations: observations, independentViews: independent.count)
    }
}

/// A private cache, deliberately outside project archives/diagnostic sharing.
/// All I/O goes through one actor; cancel/delete cannot race a JPEG write.
actor ScanEvidenceStore {
    static let shared = ScanEvidenceStore()
    let root: URL
    private let context = CIContext(options: [.cacheIntermediates: false])
    init(root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plaquisto/ScanEvidence", isDirectory: true)) { self.root = root }

    struct Snapshot {
        let image: CVPixelBuffer
        let depth: CVPixelBuffer?
        let confidence: CVPixelBuffer?
        var record: ScanEvidenceFrame
        init(image: CVPixelBuffer, depth: CVPixelBuffer?, confidence: CVPixelBuffer?, record: ScanEvidenceFrame) {
            self.image = image; self.depth = depth; self.confidence = confidence; self.record = record
        }
        init(frame: ARFrame, orientation: UIInterfaceOrientation) {
            image = frame.capturedImage
            // Do not change RoomPlan's configuration or delegate to force depth.
            depth = frame.sceneDepth?.depthMap
            confidence = frame.sceneDepth?.confidenceMap
            let m = frame.camera.transform
            let intrinsics = frame.camera.intrinsics
            record = .init(timestamp: frame.timestamp,
                cameraToWorld: (0..<4).flatMap { column in (0..<4).map { m[column][$0] } },
                imageWidth: CVPixelBufferGetWidth(image), imageHeight: CVPixelBufferGetHeight(image),
                fx: intrinsics[0][0], fy: intrinsics[1][1], cx: intrinsics[2][0], cy: intrinsics[2][1],
                depthWidth: 0, depthHeight: 0, depths: [])
            switch orientation {
            case .portrait: record.photoQuarterTurns = 1
            case .portraitUpsideDown: record.photoQuarterTurns = 3
            case .landscapeRight: record.photoQuarterTurns = 0
            case .landscapeLeft: record.photoQuarterTurns = 2
            default: record.photoQuarterTurns = 1
            }
        }
    }
    enum WriteResult { case saved(hasDepth: Bool), full }
    private func directory(_ roomID: UUID) -> URL { root.appendingPathComponent(roomID.uuidString, isDirectory: true) }
    private func files(_ directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
    }
    private func byteCount(_ urls: [URL]) -> Int {
        urls.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    func prune(now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var retained: [(URL, Date, Int)] = []
        for folder in files(root) where UUID(uuidString: folder.lastPathComponent) != nil {
            let contents = files(folder)
            let date = contents.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max() ?? .distantPast
            if now.timeIntervalSince(date) > ScanEvidencePolicy.lifetime { try FileManager.default.removeItem(at: folder) }
            else { retained.append((folder, date, byteCount(contents))) }
        }
        var bytes = retained.reduce(0) { $0 + $1.2 }
        for (folder, _, count) in retained.sorted(by: { $0.1 < $1.1 }) where bytes > ScanEvidencePolicy.maximumCacheBytes {
            try FileManager.default.removeItem(at: folder); bytes -= count
        }
    }
    func remove(roomID: UUID) throws {
        let folder = directory(roomID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
    func frames(roomID: UUID, now: Date = Date()) throws -> [ScanEvidenceFrame] {
        try prune(now: now)
        return files(directory(roomID)).filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let frame = try? JSONDecoder().decode(ScanEvidenceFrame.self, from: data),
                  now.timeIntervalSince(frame.capturedAt) <= ScanEvidencePolicy.lifetime,
                  FileManager.default.fileExists(atPath: directory(roomID).appendingPathComponent(frame.id.uuidString + ".jpg").path)
            else { return nil }
            return frame
        }.sorted { $0.timestamp < $1.timestamp }
    }
    func photo(roomID: UUID, frame: ScanEvidenceFrame) -> Data? {
        guard Date().timeIntervalSince(frame.capturedAt) <= ScanEvidencePolicy.lifetime else { return nil }
        return try? Data(contentsOf: directory(roomID).appendingPathComponent(frame.id.uuidString + ".jpg"))
    }
    func write(_ snapshot: Snapshot, roomID: UUID) throws -> WriteResult {
        try autoreleasepool {
            let folder = directory(roomID)
            let existing = files(folder)
            guard existing.filter({ $0.pathExtension == "json" }).count < ScanEvidencePolicy.maximumFrames else { return .full }
            var frame = snapshot.record
            frame.depthWidth = 0; frame.depthHeight = 0; frame.depths = []
            let orientation: CGImagePropertyOrientation
            switch frame.photoQuarterTurns ?? 0 {
            case 1: orientation = .right
            case 2: orientation = .down
            case 3: orientation = .left
            default: orientation = .up
            }
            let image = CIImage(cvPixelBuffer: snapshot.image).oriented(orientation)
            let factor = min(1, 960 / max(image.extent.width, image.extent.height))
            let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            guard let jpeg = context.jpegRepresentation(of: scaled, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.68]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            if let depth = snapshot.depth, let confidence = snapshot.confidence,
               [kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_OneComponent32Float].contains(CVPixelBufferGetPixelFormatType(depth)),
               CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 {
                CVPixelBufferLockBaseAddress(depth, .readOnly)
                CVPixelBufferLockBaseAddress(confidence, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly); CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
                if let base = CVPixelBufferGetBaseAddress(depth), let confidenceBase = CVPixelBufferGetBaseAddress(confidence) {
                    let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
                    frame.depthWidth = min(width, 96)
                    frame.depthHeight = max(1, Int(Double(height) * Double(frame.depthWidth) / Double(width)))
                    let cw = CVPixelBufferGetWidth(confidence), ch = CVPixelBufferGetHeight(confidence)
                    for y in 0..<frame.depthHeight {
                        for x in 0..<frame.depthWidth {
                            let u = (Double(x) + 0.5) / Double(frame.depthWidth), v = (Double(y) + 0.5) / Double(frame.depthHeight)
                            let value = base.advanced(by: Int(v * Double(height)) * CVPixelBufferGetBytesPerRow(depth))
                                .assumingMemoryBound(to: Float.self)[Int(u * Double(width))]
                            let quality = confidenceBase.advanced(by: Int(v * Double(ch)) * CVPixelBufferGetBytesPerRow(confidence))
                                .assumingMemoryBound(to: UInt8.self)[Int(u * Double(cw))]
                            frame.depths.append(quality == ARConfidenceLevel.high.rawValue && value.isFinite && value >= 0.15 && value <= 6 ? value : 0)
                        }
                    }
                }
            }
            let metadata = try JSONEncoder().encode(frame)
            let addition = jpeg.count + metadata.count
            let globalBytes = files(root).filter { UUID(uuidString: $0.lastPathComponent) != nil }.reduce(0) { $0 + byteCount(files($1)) }
            guard byteCount(existing) + addition <= ScanEvidencePolicy.maximumRoomBytes,
                  globalBytes + addition <= ScanEvidencePolicy.maximumCacheBytes else { return .full }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let photo = folder.appendingPathComponent(frame.id.uuidString + ".jpg")
            try jpeg.write(to: photo, options: [.atomic, .completeFileProtection])
            do { try metadata.write(to: folder.appendingPathComponent(frame.id.uuidString + ".json"), options: [.atomic, .completeFileProtection]) }
            catch { try? FileManager.default.removeItem(at: photo); throw error }
            return .saved(hasDepth: frame.hasDepth)
        }
    }
}

/// One in-flight frame at most. No video, no ARSession delegate replacement,
/// no retained ARFrame, no network, and no synchronous disk work on the UI thread.
@MainActor final class ScanEvidenceRecorder {
    private var task: Task<Void, Never>?
    private var roomIDs = Set<UUID>()
    private(set) var saved = 0
    private(set) var withDepth = 0
    private(set) var status = "not_started"
    func start(source: @escaping @MainActor () -> (ScanEvidenceStore.Snapshot, UUID)?) {
        guard ScanEvidencePolicy.enabled else { return }
        stop()
        saved = 0; withDepth = 0; roomIDs = []; status = "recording"
        task = Task { [weak self] in
            try? await ScanEvidenceStore.shared.prune()
            var last: ScanEvidenceFrame?
            while !Task.isCancelled {
                if let (snapshot, roomID) = source() {
                    let current = snapshot.record
                    let moved: Bool
                    if let last, let a = last.transform, let b = current.transform {
                        moved = simd_distance(a.columns.3, b.columns.3) >= 0.20
                            || simd_dot(a.columns.2, b.columns.2) < cos(Float.pi / 18)
                            || current.timestamp - last.timestamp >= 8
                    } else { moved = true }
                    if moved {
                        self?.roomIDs.insert(roomID)
                        do {
                            let result = try await ScanEvidenceStore.shared.write(snapshot, roomID: roomID)
                            guard !Task.isCancelled else { return }
                            switch result {
                            case .full: self?.status = "quota_reached"; return
                            case .saved(let depth): self?.saved += 1; if depth { self?.withDepth += 1 }
                            }
                            last = current
                        } catch { if !Task.isCancelled { self?.status = "write_failed" }; return }
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    func stop(discard: Bool = false) {
        task?.cancel(); task = nil
        if status == "recording" { status = "stopped" }
        if discard {
            let ids = roomIDs
            Task { for id in ids { try? await ScanEvidenceStore.shared.remove(roomID: id) } }
        }
    }
    deinit { task?.cancel() }
}

/// Evidence assists a human decision; it never edits the captured geometry.
struct ScanEvidenceReview: View {
    let roomID: UUID
    let proposal: SurveyRepair.Proposal?
    @State private var frames: [ScanEvidenceFrame] = []
    @State private var result: ScanEvidenceAnalysis.Result?
    @State private var photo: UIImage?
    @State private var selectedID: UUID?
    @State private var loading = true
    @State private var error: String?
    @State private var deleting = false
    private var observation: ScanEvidenceAnalysis.Observation? {
        result?.observations.first { $0.id == selectedID } ?? result?.observations.first
    }
    var body: some View {
        Section {
            if loading { ProgressView("Analyse des observations…") }
            else if let error { Text(error).foregroundStyle(.secondary) }
            else if frames.isEmpty {
                Text("Aucune image temporaire. Faites un nouveau scan avec Plaquisto Lab. Les images expirent après 24 h et peuvent être supprimées par iOS.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                if let result {
                    Label(result.finding.rawValue, systemImage: "camera.metering.center.weighted")
                        .font(.subheadline.weight(.semibold))
                    Text("\(frames.count) images · \(frames.filter(\.hasDepth).count) avec profondeur. Ces indices ne prouvent pas qu’un mur doit être fermé : mobilier, vitrages et erreurs de mesure restent possibles.")
                        .font(.caption).foregroundStyle(.secondary)
                    if result.observations.isEmpty {
                        Text("La zone sélectionnée n’est pas suffisamment visible dans les images conservées.").font(.footnote)
                    } else {
                        if let photo, let observation {
                            Image(uiImage: photo).resizable().aspectRatio(contentMode: .fit)
                                .overlay {
                                    Canvas { context, size in
                                        let triangles = proposal?.highlight ?? []
                                        for i in stride(from: 0, to: triangles.count - triangles.count % 3, by: 3) {
                                            let projected = triangles[i..<i+3].compactMap { observation.frame.project($0) }
                                            guard projected.count == 3 else { continue }
                                            var path = Path()
                                            path.addLines(projected.map {
                                                let point = observation.frame.photoPoint($0)
                                                return CGPoint(x: point.x * size.width, y: point.y * size.height)
                                            })
                                            path.closeSubpath()
                                            context.fill(path, with: .color(.orange.opacity(0.2)))
                                            context.stroke(path, with: .color(.orange), lineWidth: 2)
                                        }
                                    }.clipped()
                                }
                                .frame(maxHeight: 180)
                                .accessibilityLabel("Photo du scan ; zone de réparation en orange")
                        }
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Array(result.observations.enumerated()), id: \.element.id) { index, item in
                                    Button("Photo \(index+1)") { selectedID = item.id }
                                        .buttonStyle(.bordered).tint(observation?.id == item.id ? .orange : .secondary)
                                }
                            }
                        }
                    }
                }
                Button("Supprimer les images temporaires", role: .destructive) { deleting = true }
                    .font(.footnote)
            }
        } header: { Text("Observations du scan · Lab") } footer: {
            Text("Traitement local uniquement. Photos exclues du projet, de l’export DAE et du diagnostic partagé. Le relevé original reste conservé.")
        }
        .task(id: "\(roomID)/\(proposal?.id ?? "none")") {
            loading = true; result = nil; photo = nil; selectedID = nil; error = nil
            do {
                let loaded = try await ScanEvidenceStore.shared.frames(roomID: roomID)
                guard !Task.isCancelled else { return }
                frames = loaded
                if let proposal {
                    let triangles = proposal.highlight
                    let analysis = await Task.detached(priority: .userInitiated) {
                        ScanEvidenceAnalysis.analyze(triangles: triangles, frames: loaded)
                    }.value
                    guard !Task.isCancelled else { return }
                    result = analysis
                }
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Les images temporaires n’ont pas pu être lues."; loading = false
            }
        }
        .task(id: observation?.id) {
            photo = nil
            guard let frame = observation?.frame,
                  let data = await ScanEvidenceStore.shared.photo(roomID: roomID, frame: frame), !Task.isCancelled else { return }
            photo = UIImage(data: data)
        }
        .confirmationDialog("Supprimer les photos et leurs profondeurs ? Le relevé 3D sera conservé.", isPresented: $deleting, titleVisibility: .visible) {
            Button("Supprimer les images", role: .destructive) {
                Task {
                    do { try await ScanEvidenceStore.shared.remove(roomID: roomID); frames = []; result = nil; photo = nil }
                    catch { self.error = "La suppression a échoué. Réessayez." }
                }
            }
        }
    }
}
