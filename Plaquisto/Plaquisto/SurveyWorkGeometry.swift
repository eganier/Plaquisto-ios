import Foundation

/// A selectable physical surface. Units: source metres, developed layout millimetres.
/// No scanner SDK and no bounding-box substitution for a missing ceiling.
struct SurveyWorkSurface: Identifiable, Equatable {
    let source: SurveySurfaceSource
    let roomID: UUID
    let roomName: String
    let name: String
    let surface: Surface2D
    let triangles: [RoomPoint]
    let sourceDocument: PlaquistoRoomDocument
    var id: String { "\(source.checkpointID)/\(source.kind.rawValue)/\(source.surfaceID)/\(source.boundaryIndex)" }
    var netArea: Double { ((try? surface.netMeasuredArea()) ?? 0) / 1_000_000 }
    var grossArea: Double { abs(LayoutGeometry.area(surface.contour)) / 1_000_000 }
}

enum SurveyWorkError: Error, LocalizedError {
    case invalidSelection, staleSource, alreadyAssigned, changedDimensions
    var errorDescription: String? {
        switch self {
        case .invalidSelection: "Sélectionnez des surfaces valides de la même famille : murs ou plafonds."
        case .staleSource: "Le relevé a changé. Revenez à la sélection des surfaces avant de créer l’ouvrage."
        case .alreadyAssigned: "Une surface choisie appartient déjà à un ouvrage. Désélectionnez-la pour éviter un double comptage."
        case .changedDimensions: "Les dimensions du formulaire ne correspondent plus aux surfaces choisies. Corrigez d’abord le relevé, puis sélectionnez à nouveau ses surfaces."
        }
    }
}

enum SurveyWorkGeometry {
    static func surfaces(in survey: ProjectSurveyRecord) -> [SurveyWorkSurface] {
        let numbers=CeilingPlanNaming.numbers(in:survey)
        return survey.checkpoints.flatMap { checkpoint in
            let room = checkpoint.document.room
            let roomName = room.name ?? "Pièce"
            func source(_ id: UUID, _ kind: SurveySurfaceSource.Kind, _ index: Int = 0) -> SurveySurfaceSource {
                .init(surveyID: survey.id, checkpointID: checkpoint.id, surfaceID: id,
                      boundaryIndex: index, kind: kind, capturedAt: checkpoint.updatedAt)
            }
            func vector(_ p: RoomPoint) -> LayoutVector3 { .init(x: p.x, y: p.y, z: p.z) }
            var results: [SurveyWorkSurface] = []
            for (index, wall) in room.walls.enumerated() {
                let analysis = PlaquistoWallGeometry.analyze(wall: wall, room: room)
                guard !analysis.strips.isEmpty else { continue }
                let name = "Mur \(index + 1)"
                let contour = wall.effectiveOutline.map { LayoutPoint(x:$0.x*1000,y:$0.y*1000) }
                guard (try? LayoutGeometry.validate(contour)) != nil else { continue }
                let openings = room.openings.filter { $0.wallID == wall.id }.map { opening in
                    let x = opening.positionOnWall.effectiveValue * 1000, y = opening.sillHeight.effectiveValue * 1000
                    let width = opening.width.effectiveValue * 1000, height = opening.height.effectiveValue * 1000
                    let kind: LayoutOpeningKind = switch opening.kind {
                    case .door: .door
                    case .window: .window
                    case .glazedBay, .frenchDoor: .bay
                    case .passage: .passage
                    case .other: .other
                    }
                    return LayoutOpening(id: opening.id, kind: kind, contour: [
                        .init(x: x, y: y), .init(x: x + width, y: y),
                        .init(x: x + width, y: y + height), .init(x: x, y: y + height)])
                }
                let surface = Surface2D(name: "\(roomName) · \(name)", kind: .wall, contour: contour,
                    openings: openings, provenance: "scan", sourceIdentifier: wall.id.uuidString,
                    localFrame: .init(origin: vector(wall.start), axisX: vector(wall.direction), axisY: .init(x: 0, y: 1, z: 0)))
                guard let net = try? surface.netMeasuredArea(), net > 0 else { continue }
                results.append(.init(source: source(wall.id, .wall), roomID: checkpoint.roomID, roomName: roomName,
                    name: name, surface: surface, triangles: PlaquistoWallGeometry.solidTriangles(wall: wall, room: room), sourceDocument: checkpoint.document))
            }
            for (index, slope) in room.slopes.filter(\.accepted).enumerated() {
                let horizontalLoops = slope.boundaries.map { $0.map { LayoutPoint(x: $0.x, y: $0.z) } }
                guard horizontalLoops.allSatisfy({ (try? LayoutGeometry.validate($0.map { .init(x: $0.x * 1000, y: $0.y * 1000) })) != nil }) else { continue }
                // Reconstruction emits boundary loops, including holes. Intersecting
                // loops are ambiguous; never turn them into overlapping full ceilings.
                var ambiguous = false
                for a in horizontalLoops.indices {
                    for b in horizontalLoops.indices where b > a {
                        if LayoutGeometry.edges(horizontalLoops[a]).contains(where: { edge in
                            LayoutGeometry.edges(horizontalLoops[b]).contains { !LayoutGeometry.splitParameters(edge, by: $0).isEmpty }
                        }) { ambiguous = true }
                    }
                }
                guard !ambiguous else { continue }
                let depths = horizontalLoops.indices.map { i in
                    horizontalLoops.indices.filter { $0 != i && LayoutGeometry.contains(horizontalLoops[i][0], in: horizontalLoops[$0]) }.count
                }
                let axisX = RoomPoint(x: 1, y: slope.plane.a, z: 0) * (1 / sqrt(1 + slope.plane.a * slope.plane.a))
                let normal = RoomPoint(x: -slope.plane.a, y: 1, z: -slope.plane.b)
                let cross = RoomPoint(x: normal.y * axisX.z - normal.z * axisX.y,
                                      y: normal.z * axisX.x - normal.x * axisX.z,
                                      z: normal.x * axisX.y - normal.y * axisX.x)
                let axisY = cross * (1 / cross.length)
                for (boundaryIndex, boundary) in slope.boundaries.enumerated() {
                    guard depths[boundaryIndex].isMultiple(of: 2) else { continue }
                    let vertices = boundary.map { RoomPoint(x: $0.x, y: slope.plane.height(x: $0.x, z: $0.z), z: $0.z) }
                    let holes = slope.boundaries.indices.filter {
                        depths[$0] == depths[boundaryIndex] + 1 && LayoutGeometry.contains(horizontalLoops[$0][0], in: horizontalLoops[boundaryIndex])
                    }.map { i in
                        slope.boundaries[i].map { RoomPoint(x: $0.x, y: slope.plane.height(x: $0.x, z: $0.z), z: $0.z) }
                    }
                    guard let origin = vertices.first else { continue }
                    let parent=room.ceilings.first { $0.slopeIDs.contains(slope.id) }
                    let number=parent.flatMap { numbers[$0.id.uuidString] } ?? (index+1)
                    let panIndex=parent?.slopeIDs.firstIndex(of:slope.id) ?? 0
                    let name = "Plafond "+CeilingPlanNaming.letters(number)
                        + ((parent?.slopeIDs.count ?? 1)>1 ? " · pan \(panIndex+1)" : "")
                        + (slope.boundaries.count > 1 ? " · partie \(boundaryIndex + 1)" : "")
                    guard let surface = try? Surface2DAdapter.projected(name: "\(roomName) · \(name)", kind: .ceiling,
                        contour: vertices.map(vector), openings: holes.map { $0.map(vector) }, frame: .init(origin: vector(origin), axisX: vector(axisX), axisY: vector(axisY)),
                        sourceID: slope.id.uuidString), let net = try? surface.netMeasuredArea(), net > 0 else { continue }
                    results.append(.init(source: source(slope.id, .ceiling, boundaryIndex), roomID: checkpoint.roomID, roomName: roomName,
                        name: name, surface: surface, triangles: ceilingTriangles(surface), sourceDocument: checkpoint.document))
                }
            }
            return results
        }
    }

    static func totalArea(_ surfaces: [SurveyWorkSurface]) -> Double { surfaces.reduce(0) { $0 + $1.netArea } }
    static func isDesignedPartition(_ surface: SurveyWorkSurface) -> Bool {
        surface.sourceDocument.wallWorkIntents?.contains { $0.wallID == surface.source.surfaceID && $0.use == .partition } == true
    }
    static func partition(_ surfaces: [SurveyWorkSurface]) -> CloisonDistributionConfiguration {
        var result = CloisonDistributionConfiguration()
        result.geometryMode = "surface"
        result.enteredSurface = totalArea(surfaces) // ONE physical partition, not two faces.
        result.height = surfaces.map { $0.surface.bounds.height/1000 }.max() ?? 0
        result.enteredLength = surfaces.reduce(0) { $0 + $1.surface.bounds.width/1000 }
        return result
    }
    static func ceiling(_ surfaces: [SurveyWorkSurface]) -> CeilingConfiguration {
        var result = CeilingConfiguration()
        result.enteredArea = totalArea(surfaces); result.dimensionsSpecified = false
        // Existing surface-only configurator expects a calculation rectangle. Its
        // derived dimensions are never persisted as the component's real contour.
        result.length = sqrt(result.enteredArea ?? 0); result.width = result.length
        result.ceilingShape = surfaces.contains { item in
            guard let frame = item.surface.localFrame else { return false }
            return abs(frame.axisX.y) > 0.001 || abs(frame.axisY.y) > 0.001
        } ? "rampant" : "horizontal"
        return result
    }
    static func lining(_ surfaces: [SurveyWorkSurface]) -> DoublageConfiguration {
        var result = DoublageConfiguration()
        result.geometryMode = "surface"; result.enteredSurface = totalArea(surfaces)
        result.height = surfaces.map { $0.surface.bounds.height / 1000 }.max() ?? 0
        result.enteredLength = surfaces.reduce(0) { $0 + $1.surface.bounds.width / 1000 }
        result.wallCount = surfaces.count
        result.measuredWallRuns = surfaces.map { .init(length: $0.surface.bounds.width / 1000,
            height: $0.surface.bounds.height / 1000, netArea: $0.netArea) }
        return result
    }
    static func furring(_ surfaces: [SurveyWorkSurface]) -> FurringLiningConfiguration {
        let geometry = lining(surfaces)
        var result = FurringLiningConfiguration()
        result.geometryMode = "surface"; result.enteredSurface = geometry.enteredSurface
        result.height = geometry.height; result.enteredLength = geometry.enteredLength; result.wallCount = geometry.wallCount
        result.measuredWallRuns = geometry.measuredWallRuns
        return result
    }
    static func hasSameSource(_ lhs: SurveySurfaceSource, _ rhs: SurveySurfaceSource) -> Bool {
        lhs.surveyID == rhs.surveyID && lhs.checkpointID == rhs.checkpointID && lhs.surfaceID == rhs.surfaceID &&
        lhs.boundaryIndex == rhs.boundaryIndex && lhs.kind == rhs.kind
    }

    /// Existing forms expose one geometry step, while a scanned ouvrage can hold
    /// many supports. Re-open from all current components, never the single-plan
    /// compatibility facade (which is intentionally nil for a multi-wall work).
    static func workForRecalculation(_ work: WorkItem) -> WorkItem {
        guard work.layoutNeedsRecalculation == true,
              work.components.contains(where: { $0.surveySource != nil }),
              work.components.allSatisfy({ $0.surface != nil }) else { return work }
        let surfaces = work.components.compactMap(\.surface)
        let areas = surfaces.compactMap { try? $0.netMeasuredArea() / 1_000_000 }
        guard areas.count == surfaces.count, areas.allSatisfy({ $0.isFinite && $0 > 0 }) else { return work }
        let total = areas.reduce(0, +)
        let runs = zip(surfaces, areas).map { surface, area in
            MeasuredWallRun(length: surface.bounds.width / 1000, height: surface.bounds.height / 1000, netArea: area)
        }
        var result = work
        switch work.payload {
        case .ceiling(var value):
            let previous = value.enteredArea ?? value.length * value.width
            let ratio = previous > 0 ? total / previous : 1
            value.enteredArea = total; value.dimensionsSpecified = false
            value.length = sqrt(total); value.width = value.length
            value.firstSkin = value.firstSkin.map { var copy = $0; copy.area *= ratio; return copy }
            value.secondSkin = value.secondSkin.map { var copy = $0; copy.area *= ratio; return copy }
            result.payload = .ceiling(value)
        case .peripheralLining(var value):
            let ratio = value.area > 0 ? total / value.area : 1
            value.geometryMode = "surface"; value.enteredSurface = total
            value.enteredLength = runs.reduce(0) { $0 + $1.length }
            value.height = runs.map(\.height).max() ?? 0
            value.wallCount = runs.count; value.measuredWallRuns = runs
            value.firstSkin = value.firstSkin.map { var copy = $0; copy.surface *= ratio; return copy }
            value.secondSkin = value.secondSkin.map { var copy = $0; copy.surface *= ratio; return copy }
            result.payload = .peripheralLining(value)
        case .furringLining(var value):
            let ratio = value.area > 0 ? total / value.area : 1
            value.geometryMode = "surface"; value.enteredSurface = total
            value.enteredLength = runs.reduce(0) { $0 + $1.length }
            value.height = runs.map(\.height).max() ?? 0
            value.wallCount = runs.count; value.measuredWallRuns = runs
            value.firstSkin = value.firstSkin.map { var copy = $0; copy.surface *= ratio; return copy }
            value.secondSkin = value.secondSkin.map { var copy = $0; copy.surface *= ratio; return copy }
            value.thirdSkin = value.thirdSkin.map { var copy = $0; copy.surface *= ratio; return copy }
            result.payload = .furringLining(value)
        case .paintingBeta:
            result.payload = .paintingBeta(.init(area: total))
        default: break
        }
        return result
    }

    /// Exact vertical decomposition of validated non-intersecting boundary loops.
    /// This avoids displaying a filled trémie while deducting it in the quantities.
    static func ceilingTriangles(_ surface: Surface2D) -> [RoomPoint] {
        guard let frame = surface.localFrame else { return [] }
        let holes = surface.openings.map(\.contour)
        let edges = ([surface.contour] + holes).flatMap(LayoutGeometry.edges)
        let xs = Array(Set(edges.flatMap { [$0.a.x, $0.b.x] })).sorted()
        func y(_ edge: LayoutGeometry.Edge, _ x: Double) -> Double {
            edge.a.y + (edge.b.y - edge.a.y) * (x - edge.a.x) / (edge.b.x - edge.a.x)
        }
        func world(_ x: Double, _ y: Double) -> RoomPoint {
            .init(x: frame.origin.x + (frame.axisX.x*x + frame.axisY.x*y)/1000,
                  y: frame.origin.y + (frame.axisX.y*x + frame.axisY.y*y)/1000,
                  z: frame.origin.z + (frame.axisX.z*x + frame.axisY.z*y)/1000)
        }
        var output: [RoomPoint] = []
        for i in xs.indices.dropFirst() {
            let left = xs[i-1], right = xs[i], mid = (left + right)/2
            guard right - left > 0.00001 else { continue }
            let crossing = edges.filter { min($0.a.x, $0.b.x) < mid && max($0.a.x, $0.b.x) > mid }
                .sorted { y($0, mid) < y($1, mid) }
            for j in crossing.indices.dropFirst() {
                let lower = crossing[j-1], upper = crossing[j]
                let sample = LayoutPoint(x: mid, y: (y(lower, mid) + y(upper, mid))/2)
                guard LayoutGeometry.contains(sample, in: surface.contour), !holes.contains(where: { LayoutGeometry.contains(sample, in: $0) }) else { continue }
                let a = world(left, y(lower, left)), b = world(right, y(lower, right))
                let c = world(right, y(upper, right)), d = world(left, y(upper, left))
                output += [a,b,c,a,c,d]
            }
        }
        return output
    }
}
