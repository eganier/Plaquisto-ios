import Foundation

/// One explicitly identified ceiling edge spans one complete wall component.
/// Acquisition adapters must resolve adjacency in 3D; equal lengths are NOT evidence of adjacency.
/// Partial spans and uncertain matches must not be registered as full-span relations.
struct CeilingWallLink: Codable, Equatable, Identifiable {
    enum Origin: String, Codable { case manual, scan }
    var id = UUID()
    var roomID: UUID
    var ceilingComponentID: UUID
    var wallComponentID: UUID
    var ceilingSurfaceID: UUID
    var ceilingTopologyID: UUID?
    var ceilingVertexCount: Int
    var edgeIndex: Int
    var origin: Origin
    var sourceObservationID: String? = nil

    func identifiesEdge(in surface: Surface2D) -> Bool {
        surface.id == ceilingSurfaceID && surface.topologyID == ceilingTopologyID
            && surface.contour.count == ceilingVertexCount && surface.contour.indices.contains(edgeIndex)
    }
}

enum ComponentAdjacencyDecision { case undecided, keepWalls, applyWalls }

/// Immutable review shown before saving. Recomputed at commit to reject stale confirmations.
struct ComponentAdjacencyReview: Equatable {
    struct Change: Equatable, Identifiable {
        var link: CeilingWallLink
        var wallName: String
        var wallRevision: Int
        var oldLengthMM: Double
        var proposedLengthMM: Double?
        var proposedSurface: Surface2D?
        var reason: String?
        var id: UUID { link.id }
    }
    var changes: [Change]
    var canApply: Bool { !changes.isEmpty && changes.allSatisfy { $0.proposedSurface != nil } }
    var message: String {
        let details = changes.map { change in
            let old = (change.oldLengthMM / 10).formatted(.number.precision(.fractionLength(1)))
            let next = change.proposedLengthMM.map { ($0 / 10).formatted(.number.precision(.fractionLength(1))) }
            return "\(change.wallName) : \(old) cm" + (next.map { " → \($0) cm" } ?? "")
                + (change.reason.map { "\n\($0)" } ?? "")
        }.joined(separator: "\n\n")
        return details + "\n\nConserver les murs enregistre seulement le plafond et garde les écarts à vérifier. Les ouvertures, prises et ossatures ne sont pas déplacées ni redimensionnées."
    }
}

/// Portable geometric policy: millimetres, no RoomPlan/ARKit dependency.
enum ComponentAdjacency {
    static let toleranceMM = 0.1

    /// Wall length is horizontal, not the developed length of a sloping ceiling edge.
    static func wallSpan(of surface: Surface2D, edge: Int) -> Double? {
        guard surface.contour.indices.contains(edge), surface.contour.count >= 3 else { return nil }
        let d = surface.contour[(edge + 1) % surface.contour.count] - surface.contour[edge]
        let span: Double
        if let frame = surface.localFrame {
            guard abs(frame.axisX.length - 1) < 1e-6, abs(frame.axisY.length - 1) < 1e-6,
                  abs(frame.axisX.dot(frame.axisY)) < 1e-6 else { return nil }
            span = hypot(d.x * frame.axisX.x + d.y * frame.axisY.x,
                         d.x * frame.axisX.z + d.y * frame.axisY.z)
        } else {
            // Manual full-span links are only exposed for ceilings without a known 3D frame.
            span = d.length
        }
        return span.isFinite && span > toleranceMM ? span : nil
    }

    static func review(project: ProjectItem, componentID: UUID, proposed: Surface2D) -> ComponentAdjacencyReview {
        let works = project.works
        let components = works.flatMap(\.components)
        guard let source = components.first(where: { $0.id == componentID }), let original = source.surface else {
            return .init(changes: [])
        }
        let changes = (project.ceilingWallLinks ?? []).filter { $0.ceilingComponentID == componentID }.compactMap { link -> ComponentAdjacencyReview.Change? in
            guard let wall = components.first(where: { $0.id == link.wallComponentID }), let wallSurface = wall.surface else { return nil }
            let room = project.rooms.first { $0.id == link.roomID }
            let validRoom = room != nil // Organization changes never alter physical correspondences.
            var change = ComponentAdjacencyReview.Change(link: link,
                wallName: [room?.name, wall.name].compactMap { $0 }.joined(separator: " — "),
                wallRevision: wall.geometryRevision, oldLengthMM: wallSurface.bounds.width)
            guard validRoom, link.identifiesEdge(in: original), link.identifiesEdge(in: proposed) else {
                guard proposed != original else { return nil }
                change.reason = "Correspondance à vérifier : le contour ou le rattachement a changé. Aucun mur ne sera ajusté automatiquement."
                return change
            }
            guard let oldSpan = wallSpan(of: original, edge: link.edgeIndex),
                  let span = wallSpan(of: proposed, edge: link.edgeIndex) else {
                guard proposed != original else { return nil }
                change.reason = "La longueur horizontale du bord ne peut pas être déterminée. Vérifiez la géométrie 3D."
                return change
            }
            guard abs(span - oldSpan) > toleranceMM, abs(span - wallSurface.bounds.width) > toleranceMM else { return nil }
            change.proposedLengthMM = span
            do { change.proposedSurface = try resizedWall(wall, width: span) }
            catch { change.reason = error.localizedDescription }
            return change
        }
        return .init(changes: changes.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    static func warning(for link: CeilingWallLink, in project: ProjectItem) -> String? {
        let components = project.works.flatMap(\.components)
        guard let ceiling = components.first(where: { $0.id == link.ceilingComponentID })?.surface,
              let wall = components.first(where: { $0.id == link.wallComponentID })?.surface,
              link.identifiesEdge(in: ceiling), let length = wallSpan(of: ceiling, edge: link.edgeIndex),
              project.rooms.contains(where: { $0.id == link.roomID }) else {
            return "Lien plafond–mur à vérifier : contour ou pièce modifié."
        }
        guard abs(length - wall.bounds.width) > toleranceMM else { return nil }
        let a = (length / 10).formatted(.number.precision(.fractionLength(1)))
        let b = (wall.bounds.width / 10).formatted(.number.precision(.fractionLength(1)))
        return "Écart plafond–mur : bord \(a) cm, mur \(b) cm."
    }

    /// Conservative first propagation: rectangular wall, right boundary translated;
    /// fixed left origin, unchanged heights, openings, frame and electrical positions.
    static func resizedWall(_ component: WorkComponentRecord, width: Double) throws -> Surface2D {
        guard var wall = component.surface, wall.kind == .wall, width.isFinite, width >= 10, width <= 100_000 else { throw AdjustmentError.unsupported }
        let b = wall.bounds
        guard wall.contour.count == 4, b.width > toleranceMM,
              wall.contour.allSatisfy({ p in b.polygon.contains { (p - $0).length < toleranceMM } }) else { throw AdjustmentError.unsupported }
        if let intent = wall.contourIntent,
           !(intent.lockedLengthIndices ?? []).isEmpty || intent.userVertexPositions.contains(where: { $0 != nil })
                || intent.userAnglesDegrees.contains(where: { $0 != nil }) {
            throw AdjustmentError.locked
        }
        let delta = width - b.width
        wall.contour = wall.contour.map { p in abs(p.x - b.max.x) < toleranceMM ? .init(x: p.x + delta, y: p.y) : p }
        try LayoutGeometry.validate(wall.contour)
        func inside(_ p: LayoutPoint) -> Bool {
            LayoutGeometry.contains(p, in: wall.contour)
                || LayoutGeometry.edges(wall.contour).contains { LayoutGeometry.distance(p, to: $0.a, $0.b) < toleranceMM }
        }
        guard wall.openings.allSatisfy({ $0.contour.allSatisfy(inside) }) else { throw AdjustmentError.openingOutside }
        for plan in component.plans {
            let seenWall = component.isOppositeSide(plan.sideRoomID) ? wall.mirroredComponentSide() : wall
            if let lighting = plan.lighting, !LayoutPlanning.lightingFits(lighting, surface: seenWall) { throw AdjustmentError.electricityOutside }
            for layer in plan.layers { _ = try SheetLayoutEngine.calculate(surface: seenWall, layer: layer) }
        }
        if let intent = wall.contourIntent { wall.previousContourIntents.append(intent) }
        wall.contourIntent = .init(sketch: wall.contour)
        wall.dimensionCorrections = []
        return wall
    }

    enum AdjustmentError: Error, LocalizedError {
        case unsupported, locked, openingOutside, electricityOutside
        var errorDescription: String? {
            switch self {
            case .unsupported: "Ce contour nécessite un ajustement manuel du mur ; aucune déformation automatique n’est proposée."
            case .locked: "Le mur contient des contraintes verrouillées. Ajustez son contour manuellement."
            case .openingOutside: "Cette longueur ferait sortir une ouverture du mur. Ajustez le mur et son ouverture manuellement."
            case .electricityOutside: "Cette longueur ferait sortir un point électrique du mur. Ajustez son implantation avant de continuer."
            }
        }
    }
}
