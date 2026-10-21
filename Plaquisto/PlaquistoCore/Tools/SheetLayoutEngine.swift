import Foundation

enum DoorHanding: String, Codable, CaseIterable, Identifiable {
    case right, left
    var id: Self { self }
    var title: String { self == .right ? "Poussant droit" : "Poussant gauche" }
}
enum DoorOpeningSide: String, Codable {
    case positive, negative
    var sign: Double { self == .positive ? 1 : -1 }
    var reversed: Self { self == .positive ? .negative : .positive }
}

enum LayoutSupportKind: String, Codable, CaseIterable { case wall = "Mur", ceiling = "Plafond" }
enum LayoutOrientation: String, Codable, CaseIterable { case vertical = "Vertical", horizontal = "Horizontal" }
enum LayoutOpeningKind: String, Codable, CaseIterable {
    case door = "Porte", window = "Fenêtre", bay = "Porte-fenêtre / baie", passage = "Ouverture libre"
    case stairwell = "Trémie", roofWindow = "Fenêtre de toit", hatch = "Trappe", other = "Autre ouverture"
    static func available(for kind: LayoutSupportKind) -> [Self] {
        kind == .wall ? [.door, .window, .bay, .passage, .hatch] : [.stairwell, .roofWindow, .hatch, .other]
    }
}
struct LayoutOpening: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: LayoutOpeningKind
    var contour: [LayoutPoint]
    var doorHanding:DoorHanding? = nil
    var doorOpeningSide:DoorOpeningSide? = nil
    var bounds: LayoutBounds { .init(points: contour) }
}
/// Edit in the opening's own axes, not its axis-aligned bounding box in the scan.
struct LayoutOpeningFrame {
    var center: LayoutPoint
    var angle: Double
    var width: Double
    var height: Double
    var normalizedContour: [LayoutPoint]

    init(contour: [LayoutPoint]) {
        let edge = LayoutGeometry.edges(contour).first { ($0.b - $0.a).length > 0.001 }
        let angle = edge.map { atan2($0.b.y - $0.a.y, $0.b.x - $0.a.x) } ?? 0
        self.angle = angle
        let local = contour.map { Self.rotate($0, by: -angle) }
        let bounds = LayoutBounds(points: local)
        let middle = (bounds.min + bounds.max) * 0.5
        center = Self.rotate(middle, by: angle)
        width = bounds.width; height = bounds.height
        normalizedContour = local.map { .init(x: ($0.x - middle.x) / max(bounds.width, 0.001), y: ($0.y - middle.y) / max(bounds.height, 0.001)) }
    }
    static func rotate(_ p: LayoutPoint, by angle: Double) -> LayoutPoint {
        .init(x: p.x * cos(angle) - p.y * sin(angle), y: p.x * sin(angle) + p.y * cos(angle))
    }
    func contour(center: LayoutPoint, width: Double, height: Double, angle: Double) -> [LayoutPoint] {
        normalizedContour.map { center + Self.rotate(.init(x: $0.x * width, y: $0.y * height), by: angle) }
    }
    static func wallAngle(_ contour: [LayoutPoint], edge: Int) -> Double? {
        guard contour.indices.contains(edge), contour.count > 1 else { return nil }
        let delta = contour[(edge + 1) % contour.count] - contour[edge]
        guard delta.length > 0.001 else { return nil }
        // Parallel is undirected; keep consistent width/length axes.
        let angle = atan2(delta.y, delta.x)
        return angle < 0 ? angle + .pi : angle
    }
}
enum LayoutEdgeTone: String, Codable {
    case blue, orange, purple, green, teal, gray
}
struct LayoutDimensionCorrection: Codable, Equatable, Identifiable {
    var edgeIndex: Int
    var original: Double
    var corrected: Double
    var id: Int { edgeIndex }
    var difference: Double { abs(corrected - original) }
    var percentage: Double { original > 0 ? difference / original * 100 : 0 }
    var symbol: String { severity() == .red ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill" }
}
struct Surface2D: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: LayoutSupportKind
    var contour: [LayoutPoint]
    var openings: [LayoutOpening] = []
    var provenance = "manual"
    var sourceIdentifier: String? = nil
    var localFrame: LayoutLocalFrame? = nil
    var edgeTones: [LayoutEdgeTone] = []
    var dimensionCorrections: [LayoutDimensionCorrection] = []
    var contourIntent: LayoutContourIntent? = nil
    // Retain measurements belonging to an earlier topology when adding/removing vertices.
    var previousContourIntents: [LayoutContourIntent] = []
    // Changes whenever vertices are inserted/removed, even if the final count is unchanged.
    var topologyID: UUID? = nil
    var edgeIDs: [String] = []
    var layingOffset = LayoutLayingOffset()
    var bounds: LayoutBounds { .init(points: contour) }
}
extension Surface2D {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, contour, openings, provenance, sourceIdentifier, localFrame, edgeTones, dimensionCorrections, contourIntent, previousContourIntents, topologyID, edgeIDs, layingOffset
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(LayoutSupportKind.self, forKey: .kind)
        contour = try values.decode([LayoutPoint].self, forKey: .contour)
        openings = try values.decodeIfPresent([LayoutOpening].self, forKey: .openings) ?? []
        provenance = try values.decodeIfPresent(String.self, forKey: .provenance) ?? "manual"
        sourceIdentifier = try values.decodeIfPresent(String.self, forKey: .sourceIdentifier)
        localFrame = try values.decodeIfPresent(LayoutLocalFrame.self, forKey: .localFrame)
        edgeTones = try values.decodeIfPresent([LayoutEdgeTone].self, forKey: .edgeTones) ?? []
        dimensionCorrections = try values.decodeIfPresent([LayoutDimensionCorrection].self, forKey: .dimensionCorrections) ?? []
        contourIntent = try values.decodeIfPresent(LayoutContourIntent.self, forKey: .contourIntent)
        previousContourIntents = try values.decodeIfPresent([LayoutContourIntent].self, forKey: .previousContourIntents) ?? []
        topologyID = try values.decodeIfPresent(UUID.self, forKey: .topologyID)
        edgeIDs = try values.decodeIfPresent([String].self, forKey: .edgeIDs) ?? []
        layingOffset = try values.decodeIfPresent(LayoutLayingOffset.self, forKey: .layingOffset) ?? .init()
    }
}
struct LayoutVector3: Codable, Equatable {
    var x: Double; var y: Double; var z: Double
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y + z * b.z }
    var length: Double { sqrt(dot(self)) }
}
struct LayoutLocalFrame: Codable, Equatable {
    var origin: LayoutVector3
    var axisX: LayoutVector3
    var axisY: LayoutVector3
}
// Scanner integration contract. Source positions are metres and axes orthonormal.
// A sloping plane is developed into its own plane, never flattened onto the floor.
enum Surface2DAdapter {
    static func projected(name: String, kind: LayoutSupportKind, contour: [LayoutVector3],
                          openings: [[LayoutVector3]], frame: LayoutLocalFrame, sourceID: String) throws -> Surface2D {
        guard abs(frame.axisX.length - 1) < 1e-6, abs(frame.axisY.length - 1) < 1e-6,
              abs(frame.axisX.dot(frame.axisY)) < 1e-6 else { throw LayoutGeometryError.invalidContour }
        func project(_ p: LayoutVector3) throws -> LayoutPoint {
            let d = p - frame.origin, x = d.dot(frame.axisX), y = d.dot(frame.axisY)
            let residual = max(0, d.dot(d) - x * x - y * y)
            guard residual.isFinite, residual < 0.0001 else { throw LayoutGeometryError.invalidContour }
            return .init(x: x * 1000, y: y * 1000)
        }
        let polygon = try contour.map(project)
        try LayoutGeometry.validate(polygon)
        let holes = try openings.map { vertices -> LayoutOpening in
            let p = try vertices.map(project); try LayoutGeometry.validate(p)
            return .init(kind: .other, contour: p)
        }
        return Surface2D(name: name, kind: kind, contour: polygon, openings: holes,
                         provenance: "scan", sourceIdentifier: sourceID, localFrame: frame)
    }
}
struct LayoutLayer: Codable, Equatable, Identifiable {
    var id = UUID()
    var sheetWidth = 1200.0
    var sheetLength = 2500.0
    var orientation = LayoutOrientation.vertical
    var offset = LayoutPoint.zero
    var catalogFormatID: String? = nil
    // Distinguishes an explicit manual choice from legacy plans missing their product.
    var manualFacing: Bool? = nil
    // Optional fields keep previously saved documents readable without migration.
    var referenceEdge: Int? = nil
    /// Preserves the original physical grid when its support is subdivided.
    var inheritedGridFrame: LayoutGridFrame? = nil
    var furring: LayoutFurringSettings? = nil
    var staggered: Bool? = nil
    var staggerOffset: Double? = nil
    var reuseOffcuts: Bool? = nil
    // Persisted with the plan: only 4BA requires factory edges at every joint.
    var fourTaperedEdges: Bool? = nil
    var cellWidth: Double { orientation == .vertical ? min(sheetWidth, sheetLength) : max(sheetWidth, sheetLength) }
    var cellHeight: Double { orientation == .vertical ? max(sheetWidth, sheetLength) : min(sheetWidth, sheetLength) }
    func forSupport(_ kind:LayoutSupportKind) -> Self {
        guard kind == .wall else { return self }
        var copy = self
        copy.referenceEdge = nil
        copy.inheritedGridFrame = nil
        copy.furring?.orientation = .vertical
        copy.furring?.parallelToBoards = orientation == .vertical
        return copy
    }
    func forSurface(_ surface:Surface2D) -> Self {
        var copy = forSupport(surface.kind)
        if surface.kind == .wall && surface.bounds.height <= cellHeight + 0.001 {
            copy.offset.y = surface.bounds.min.y
            if copy.staggered == true { copy.staggered = false }
        }
        return copy
    }
}
struct LayoutFurringSettings: Codable, Equatable {
    // Kept for decoding plans created before furring had its own absolute
    // orientation. New and edited plans persist `orientation` as the source of
    // truth, so rotating boards cannot rotate the frame with them.
    var parallelToBoards = false
    var spacing = 600.0
    var offset = 0.0
    var orientation: LayoutOrientation? = nil
    var referenceEdge: Int? = nil
    var usesOwnReference: Bool? = nil
    /// No perimeter angle: independent, immovable support lines 100 mm from the walls.
    var peripheralInset: Double? = nil
    var inheritedGridFrame: LayoutGridFrame? = nil
    /// Original physical perimeter, not the artificial boundary between two parts.
    var peripheralReferenceContour: [LayoutPoint]? = nil
    var openingSystem: LayoutOpeningFramingSystem? = nil
    var isFurringSystem: Bool? = nil
    var intermediateSupportLines: Int? = nil
    var includesHorizontalSupportFurring: Bool? = nil
    var maximumSupportSpacing: Double? = nil // millimetres, Admin rule snapshot
    var firstSupportHeightWhenMultiple: Double? = nil
    /// Fixed end studs, only for rail/stud peripheral linings (not partitions).
    var liningEndStudInset: Double? = nil
    /// Explicit plan overrides. Nil preserves legacy/form-driven defaults.
    var ceilingPerimeterSupport: Bool? = nil
    var ceilingSuspensionSpacing: Double? = nil // millimetres, default 1 200

    var resolvedCeilingPerimeterSupport: Bool { ceilingPerimeterSupport ?? (peripheralInset == nil || peripheralInset == 0) }
    var resolvedCeilingSuspensionSpacing: Double { ceilingSuspensionSpacing ?? 1200 }
    func allowsCeilingSupportControls(on surface: Surface2D) -> Bool {
        surface.kind == .ceiling && isFurringSystem != false
    }

    mutating func setCeilingPerimeterSupport(_ enabled: Bool) {
        ceilingPerimeterSupport = enabled
        peripheralInset = enabled ? nil : 100
    }

    func resolvedOrientation(boardOrientation: LayoutOrientation) -> LayoutOrientation {
        if let orientation { return orientation }
        if parallelToBoards { return boardOrientation }
        return boardOrientation == .horizontal ? .vertical : .horizontal
    }
}

extension LayoutLayer {
    var resolvedFurringOrientation: LayoutOrientation? {
        furring?.resolvedOrientation(boardOrientation: orientation)
    }

    mutating func materializeFurringOrientation() {
        guard var settings = furring else { return }
        let resolved = settings.resolvedOrientation(boardOrientation: orientation)
        settings.orientation = resolved
        settings.parallelToBoards = resolved == orientation
        furring = settings
    }

    mutating func setFurringOrientation(_ value: LayoutOrientation) {
        guard var settings = furring else { return }
        settings.orientation = value
        settings.parallelToBoards = value == orientation
        furring = settings
    }
}

// Engine and cut sheets stay in grid coordinates. Only the overview is transformed.
// This prevents rotated cuts from being measured using a world-axis bounding box.
struct LayoutGridFrame: Codable, Equatable {
    var origin = LayoutPoint.zero
    var angle = 0.0
    func world(_ p: LayoutPoint) -> LayoutPoint {
        origin + .init(x: cos(angle)*p.x - sin(angle)*p.y, y: sin(angle)*p.x + cos(angle)*p.y)
    }
    func local(_ p: LayoutPoint) -> LayoutPoint { vector(p-origin) }
    func vector(_ p: LayoutPoint) -> LayoutPoint {
        .init(x: cos(angle)*p.x + sin(angle)*p.y, y: -sin(angle)*p.x + cos(angle)*p.y)
    }
    static func make(surface: Surface2D, layer: LayoutLayer) -> Self {
        guard surface.kind == .ceiling else { return .init() }
        if let inherited=layer.inheritedGridFrame { return inherited }
        guard let i = layer.referenceEdge, surface.contour.indices.contains(i) else { return .init() }
        let a = surface.contour[i], d = surface.contour[(i+1)%surface.contour.count]-a
        return .init(origin: a, angle: atan2(d.y,d.x))
    }
}
struct LayoutFurringContact: Equatable {
    var point: LayoutPoint
    var edgeIndex: Int
    var distance: Double
}
struct LayoutFurringResult: Equatable {
    var lines: [LayoutJoint] = []
    var contacts: [LayoutFurringContact] = []
    var peripheralLines: [LayoutJoint] = []
    var openingProfiles: [LayoutOpeningProfile] = []
    var supportPoints: [LayoutPoint] = []
    var wallFixedProfiles: [LayoutWallFixedProfile] = []
    var fixedLines: [LayoutJoint] { peripheralLines + openingProfiles.map(\.line) + wallFixedProfiles.map(\.line) }
    var furringSpliceCount: Int {
        let angles=openingProfiles.filter { $0.role == .horizontal }.map(\.line)
            + wallFixedProfiles.filter { $0.role == .rightAngle }.map(\.line)
        let furrings=lines.filter { line in !angles.contains { LayoutOpeningFraming.same($0,line) } }
        return LayoutFurringEngine.continuousLengths(furrings).reduce(0) { $0 + LayoutFurringEngine.splices(lengthMM:$1) }
    }
}
struct LayoutWallFixedProfile: Equatable {
    enum Role { case leftFurring, rightAngle, supportHorizontal, endStud }
    var line: LayoutJoint
    var role: Role
}

enum LayoutOpeningFramingSystem: String, Codable { case furring, studs }
struct LayoutOpeningProfile: Equatable {
    enum Role { case side, shortVertical, horizontal }
    var line: LayoutJoint
    var role: Role
}

enum LayoutOpeningFraming {
    /// Physical millimetres. The 50 mm clearance is measured to the profile axis.
    static func profiles(surface: Surface2D, system: LayoutOpeningFramingSystem) -> [LayoutOpeningProfile] {
        guard surface.kind == .wall else { return [] }
        var profiles: [LayoutOpeningProfile] = []
        let wall = surface.bounds
        func add(_ a: LayoutPoint, _ b: LayoutPoint, _ role: LayoutOpeningProfile.Role) {
            let line = LayoutJoint(start: a, end: b)
            for clipped in clip(line, to: surface) where (clipped.end-clipped.start).length > 0.5 {
                // Neighboring openings can share one physical support.
                if !profiles.contains(where: { same($0.line, clipped) }) { profiles.append(.init(line: clipped, role: role)) }
            }
        }
        for opening in surface.openings {
            let b = opening.bounds, left = b.min.x - 50, right = b.max.x + 50
            for x in [left, right] { add(.init(x: x, y: wall.min.y), .init(x: x, y: wall.max.y), .side) }
        }
        return profiles
    }
    static func same(_ a: LayoutJoint, _ b: LayoutJoint) -> Bool {
        ((a.start-b.start).length < 0.5 && (a.end-b.end).length < 0.5) ||
        ((a.start-b.end).length < 0.5 && (a.end-b.start).length < 0.5)
    }
    /// The fixed jamb replaces a nearby regular member outside it. A half-grid
    /// spacing avoids a redundant pair, without deleting the next full bay.
    /// Only subtract the height actually covered by
    /// that jamb: sloping/stepped walls can leave a useful segment above it.
    /// Called on the regular grid only, never on the opening/perimeter profiles.
    static func subtractOpeningNeighbors(_ line: LayoutJoint, openings: [LayoutOpening],
                                         profiles: [LayoutOpeningProfile], spacing: Double) -> [LayoutJoint] {
        guard abs(line.start.x-line.end.x)<0.5 else { return [line] }
        let x=line.start.x
        var replacements: [LayoutJoint] = []
        for opening in openings {
            let left=opening.bounds.min.x-50, right=opening.bounds.max.x+50
            for side in [left,right] {
                let outsideDistance=side == left ? side-x : x-side
                guard outsideDistance >= -0.001, outsideDistance <= max(100,spacing/2)+0.001 else { continue }
                replacements += profiles.filter { $0.role == .side && abs($0.line.start.x-side)<0.5 }
                    .map { .init(start:.init(x:x,y:$0.line.start.y),end:.init(x:x,y:$0.line.end.y)) }
            }
        }
        return subtractFixed(line,fixed:replacements)
    }
    static func clip(_ line: LayoutJoint, to surface: Surface2D) -> [LayoutJoint] {
        let a = line.start, d = line.end-a
        guard d.length > 0.5 else { return [] }
        var cuts = [0.0, 1.0]
        for polygon in [surface.contour] + surface.openings.map(\.contour) {
            for edge in LayoutGeometry.edges(polygon) { cuts += LayoutGeometry.splitParameters(.init(a:a,b:line.end),by:edge) }
        }
        cuts = Array(Set(cuts)).sorted()
        return zip(cuts,cuts.dropFirst()).compactMap { lo, hi in
            let middle = a+d*((lo+hi)/2)
            let boundary = LayoutGeometry.edges(surface.contour).contains { LayoutGeometry.distance(middle,to:$0.a,$0.b)<0.01 }
            guard hi-lo>1e-8, LayoutGeometry.contains(middle,in:surface.contour) || boundary,
                  !surface.openings.contains(where:{LayoutGeometry.contains(middle,in:$0.contour)}) else { return nil }
            return .init(start:a+d*lo,end:a+d*hi)
        }
    }
    /// Subtract coincident fixed pieces, rather than counting/painting two profiles.
    static func subtractFixed(_ line: LayoutJoint, fixed: [LayoutJoint]) -> [LayoutJoint] {
        let d=line.end-line.start, length=d.length
        guard length>0.5 else { return [] }
        let u=d*(1/length)
        var intervals=[(0.0,length)]
        for f in fixed {
            let a=f.start-line.start, b=f.end-line.start
            guard abs(a.x*u.y-a.y*u.x)<0.5, abs(b.x*u.y-b.y*u.x)<0.5 else { continue }
            let lo=min(a.x*u.x+a.y*u.y,b.x*u.x+b.y*u.y), hi=max(a.x*u.x+a.y*u.y,b.x*u.x+b.y*u.y)
            intervals=intervals.flatMap { start,end -> [(Double,Double)] in
                if hi<=start || lo>=end { return [(start,end)] }
                return [(start,min(end,lo)),(max(start,hi),end)].filter { $0.1-$0.0>0.5 }
            }
        }
        return intervals.map { .init(start:line.start+u*$0.0,end:line.start+u*$0.1) }
    }
}

enum LayoutFurringEngine {
    /// Reunite touching subdivisions on one axis, never bridge an opening.
    static func continuousLengths(_ lines:[LayoutJoint]) -> [Double] {
        var groups:[String:[(Double,Double)]]=[:]
        for line in lines {
            let delta=line.end-line.start, length=delta.length
            guard line.start.finite, line.end.finite, length>0.001 else { continue }
            var u=delta*(1/length)
            if u.x < -0.000001 || (abs(u.x)<0.000001 && u.y<0) { u=u * -1 }
            let distance = -u.y*line.start.x+u.x*line.start.y
            let key="\(Int((atan2(u.y,u.x)*1_000_000).rounded()))/\(Int((distance*1000).rounded()))"
            let a=u.x*line.start.x+u.y*line.start.y, b=u.x*line.end.x+u.y*line.end.y
            groups[key,default:[]].append((min(a,b),max(a,b)))
        }
        return groups.values.flatMap { intervals -> [Double] in
            var merged:[(Double,Double)]=[]
            for range in intervals.sorted(by:{$0.0<$1.0}) {
                if let last=merged.last, range.0 <= last.1+0.001 {
                    merged[merged.count-1].1=max(last.1,range.1)
                } else { merged.append(range) }
            }
            return merged.map { $0.1-$0.0 }
        }
    }
    static func splices(lengthMM:Double) -> Int {
        guard lengthMM.isFinite, lengthMM > 0, lengthMM < 10_000_000 else { return 0 }
        return max(0,Int(ceil((lengthMM-0.001)/3000))-1)
    }

    /// Horizontal rows in the wall's physical frame, independent of grid offset.
    /// A supplementary row under a slope exists only where the local wall height
    /// requires it; user-added rows beyond the recommendation remain present.
    static func wallSupportRows(surface:Surface2D, settings:LayoutFurringSettings) -> [LayoutJoint] {
        let count=max(0,min(12,settings.intermediateSupportLines ?? 0)), b=surface.bounds
        guard count > 0, b.height > 0 else { return [] }
        let maximum=settings.maximumSupportSpacing
        let validRule=maximum.map { $0.isFinite && $0 >= 1 && $0 <= 100_000 } ?? false
        let spacing=validRule ? maximum! : b.height/Double(count+1)
        let recommended=max(1,Int(ceil(b.height/spacing))-1)
        let first=settings.firstSupportHeightWhenMultiple.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 600
        let step=count > recommended ? min(spacing,max(0,b.height-first)/Double(count)) : spacing
        var rows:[LayoutJoint]=[]
        for index in 0..<count {
            let elevation:Double
            if !validRule { elevation=spacing*Double(index+1) }
            else if count == 1 { elevation=min(spacing,max(0,b.height-100)) }
            else { elevation=min(b.height,first+Double(index)*step) }
            let y=b.min.y+elevation
            let threshold=validRule && count <= recommended && index > 0 ? max(y,b.min.y+Double(index+1)*spacing) : y
            let line=LayoutJoint(start:.init(x:b.min.x,y:y),end:.init(x:b.max.x,y:y))
            for clipped in LayoutOpeningFraming.clip(line,to:surface) {
                var xs=[clipped.start.x,clipped.end.x]
                // Changes in the outer upper envelope, not openings, determine
                // where the row becomes necessary.
                for edge in LayoutGeometry.edges(surface.contour) {
                    if edge.a.x > clipped.start.x && edge.a.x < clipped.end.x { xs.append(edge.a.x) }
                    let dy=edge.b.y-edge.a.y
                    if abs(dy)>0.001 {
                        let t=(threshold-edge.a.y)/dy
                        let x=edge.a.x+(edge.b.x-edge.a.x)*t
                        if t>=0 && t<=1 && x>clipped.start.x && x<clipped.end.x { xs.append(x) }
                    }
                }
                xs=Array(Set(xs)).sorted()
                var retained:[LayoutJoint]=[]
                for (lo,hi) in zip(xs,xs.dropFirst()) where hi-lo>0.5 {
                    let probe=LayoutPoint(x:(lo+hi)/2,y:threshold+0.01)
                    guard LayoutGeometry.contains(probe,in:surface.contour) else { continue }
                    if let last=retained.last, abs(last.end.x-lo)<0.01 { retained[retained.count-1].end.x=hi }
                    else { retained.append(.init(start:.init(x:lo,y:y),end:.init(x:hi,y:y))) }
                }
                rows += retained
            }
        }
        return rows
    }

    static func calculate(surface: Surface2D, layer: LayoutLayer, gridFrame:LayoutGridFrame = .init()) throws -> LayoutFurringResult {
        guard let settings = layer.furring else { return .init() }
        guard gridFrame.origin.finite, gridFrame.angle.isFinite,
              settings.inheritedGridFrame.map({ $0.origin.finite && $0.angle.isFinite }) ?? true,
              settings.peripheralReferenceContour?.allSatisfy(\.finite) ?? true else { throw LayoutGeometryError.invalidFormat }
        if surface.kind == .ceiling, settings.usesOwnReference == true {
            var localLayer = layer; localLayer.referenceEdge = settings.referenceEdge
            localLayer.inheritedGridFrame = nil
            let frame = settings.inheritedGridFrame.map { LayoutGridFrame(origin:gridFrame.local($0.origin),angle:$0.angle-gridFrame.angle) } ?? (settings.referenceEdge == nil
                ? LayoutGridFrame(origin:gridFrame.local(.zero),angle:-gridFrame.angle)
                : LayoutGridFrame.make(surface:surface,layer:localLayer))
            var local = surface
            local.contour = surface.contour.map(frame.local)
            local.openings = surface.openings.map { var o=$0; o.contour=o.contour.map(frame.local); return o }
            localLayer.furring?.usesOwnReference = false
            localLayer.furring?.peripheralReferenceContour = settings.peripheralReferenceContour?.map { frame.local(gridFrame.local($0)) }
            let result = try calculate(surface:local,layer:localLayer)
            return .init(lines:result.lines.map { .init(start:frame.world($0.start),end:frame.world($0.end)) },
                         contacts:result.contacts.map { .init(point:frame.world($0.point),edgeIndex:$0.edgeIndex,distance:$0.distance) },
                         peripheralLines:result.peripheralLines.map { .init(start:frame.world($0.start),end:frame.world($0.end)) })
        }
        guard [400.0,500.0,600.0].contains(settings.spacing), settings.offset.isFinite else { throw LayoutGeometryError.invalidFormat }
        // In grid coordinates the long side is X for horizontal boards, Y otherwise.
        let alongX = surface.kind == .wall ? false : settings.resolvedOrientation(boardOrientation: layer.orientation) == .horizontal
        func across(_ p: LayoutPoint) -> Double { alongX ? p.y : p.x }
        func along(_ p: LayoutPoint) -> Double { alongX ? p.x : p.y }
        let b = surface.bounds
        let low = across(b.min), high = across(b.max)
        let step = settings.spacing
        let offset = settings.offset.truncatingRemainder(dividingBy:step)
        guard low.isFinite, high.isFinite, (high-low)/step <= 2000 else { throw LayoutGeometryError.tooLarge }
        let first = Int(ceil((low-offset-0.001)/step)), last = Int(floor((high-offset+0.001)/step))
        var result = LayoutFurringResult()
        if let system = settings.openingSystem, surface.kind == .wall {
            result.openingProfiles = LayoutOpeningFraming.profiles(surface: surface, system: system)
        }
        let wallRows = surface.kind == .wall && settings.openingSystem == .furring
            ? wallSupportRows(surface:surface,settings:settings) : []
        if surface.kind == .wall, settings.openingSystem == .furring {
            if b.width > 240 {
                for (x,role) in [(b.min.x+120,LayoutWallFixedProfile.Role.leftFurring),(b.max.x-120,.rightAngle)] {
                    let line=LayoutJoint(start:.init(x:x,y:b.min.y),end:.init(x:x,y:b.max.y))
                    result.wallFixedProfiles += LayoutOpeningFraming.clip(line,to:surface).map { .init(line:$0,role:role) }
                }
            }
            if settings.includesHorizontalSupportFurring != false {
                result.wallFixedProfiles += wallRows.map { .init(line:$0,role:.supportHorizontal) }
            }
        }
        if surface.kind == .wall, settings.openingSystem == .studs,
           let inset = settings.liningEndStudInset {
            guard inset.isFinite, inset > 0, inset <= 1000 else { throw LayoutGeometryError.invalidFormat }
            // On very narrow returns keep one central stud rather than crossing
            // the end profiles or placing them outside the measured wall.
            let positions = b.width > 2*inset ? [b.min.x+inset,b.max.x-inset] : [b.center.x]
            for x in positions {
                let line = LayoutJoint(start:.init(x:x,y:b.min.y),end:.init(x:x,y:b.max.y))
                result.wallFixedProfiles += LayoutOpeningFraming.clip(line,to:surface)
                    .flatMap { LayoutOpeningFraming.subtractFixed($0,fixed:result.fixedLines) }
                    .map { .init(line:$0,role:.endStud) }
            }
        }
        let inset = surface.kind == .ceiling ? settings.peripheralInset ?? 0 : 0
        guard inset.isFinite, inset >= 0, inset <= 1000 else { throw LayoutGeometryError.invalidFormat }
        let perimeter = settings.peripheralReferenceContour?.map(gridFrame.local) ?? surface.contour
        let perimeterBounds = LayoutBounds(points:perimeter)
        let perimeterLow = across(perimeterBounds.min), perimeterHigh = across(perimeterBounds.max)
        if inset > 0, perimeterHigh-perimeterLow > inset*2 {
            let winding = LayoutGeometry.area(perimeter) >= 0 ? 1.0 : -1.0
            for edge in LayoutGeometry.edges(perimeter) {
                let d = edge.b-edge.a, length=d.length
                // Slightly oblique walls keep a true perpendicular 10 cm reserve.
                guard length>1, abs(along(d))/length >= cos(Double.pi/12) else { continue }
                let shift=LayoutPoint(x:-d.y/length,y:d.x/length)*(inset*winding)
                let a=edge.a+shift, b=edge.b+shift
                let segment=LayoutJoint(start:a,end:b)
                var cuts=[0.0,1.0]
                for loop in [surface.contour]+surface.openings.map(\.contour) {
                    for other in LayoutGeometry.edges(loop) {
                        cuts += LayoutGeometry.splitParameters(.init(a:a,b:b),by:other)
                    }
                }
                cuts=Array(Set(cuts)).sorted()
                for (lo,hi) in zip(cuts,cuts.dropFirst()) where hi-lo>1e-8 {
                    let middle=a+(b-a)*((lo+hi)/2)
                    guard LayoutPlanning.hitSupport(middle,surface:surface) else { continue }
                    result.peripheralLines.append(.init(start:segment.start+(b-a)*lo,end:segment.start+(b-a)*hi))
                }
            }
        }
        for index in (first <= last ? Array(first...last) : []) {
            let coordinate = offset+Double(index)*step
            if inset>0, (coordinate < perimeterLow+inset-0.001 || coordinate > perimeterHigh-inset+0.001) { continue }
            var intersections: [LayoutPoint] = []
            var contacts: [LayoutFurringContact] = []
            for (loopIndex,loop) in ([surface.contour]+surface.openings.map(\.contour)).enumerated() {
                for i in loop.indices {
                    let a = loop[i], z = loop[(i+1)%loop.count], delta = across(z)-across(a)
                    guard abs(delta) > 1e-8 else { continue }
                    let t = (coordinate-across(a))/delta
                    guard t >= -1e-8, t <= 1+1e-8 else { continue }
                    let point = a+(z-a)*min(1,max(0,t))
                    intersections.append(point)
                    if loopIndex == 0 {
                        contacts.append(.init(point:point,edgeIndex:i,distance:(point-a).length))
                    }
                }
            }
            let sorted = intersections.sorted { along($0) < along($1) }
            var unique: [LayoutPoint] = []
            for p in sorted where unique.last.map({(p-$0).length > 0.01}) ?? true { unique.append(p) }
            var segments: [LayoutJoint] = []
            func onBoundary(_ p:LayoutPoint,_ polygon:[LayoutPoint]) -> Bool {
                LayoutGeometry.edges(polygon).contains { LayoutGeometry.distance(p,to:$0.a,$0.b) < 0.001 }
            }
            for (a,z) in zip(unique,unique.dropFirst()) {
                let mid = (a+z)*0.5
                if LayoutGeometry.contains(mid,in:surface.contour) || onBoundary(mid,surface.contour),
                   !surface.openings.contains(where:{LayoutGeometry.contains(mid,in:$0.contour) && !onBoundary(mid,$0.contour)}) {
                    segments.append(.init(start:a,end:z))
                }
            }
            result.lines.append(contentsOf:segments.filter { segment in
                !result.peripheralLines.contains { fixed in
                    LayoutGeometry.distance(segment.start,to:fixed.start,fixed.end)<0.5 &&
                    LayoutGeometry.distance(segment.end,to:fixed.start,fixed.end)<0.5
                }
            })
            result.contacts.append(contentsOf:contacts.filter { contact in
                segments.contains { (contact.point-$0.start).length < 0.01 || (contact.point-$0.end).length < 0.01 }
            })
        }
        if surface.kind == .wall, settings.openingSystem != nil {
            result.lines = result.lines.flatMap {
                LayoutOpeningFraming.subtractOpeningNeighbors($0,openings:surface.openings,profiles:result.openingProfiles,spacing:settings.spacing)
            }
        }
        result.lines = result.lines.flatMap { LayoutOpeningFraming.subtractFixed($0, fixed: result.fixedLines) }
        result.lines += result.fixedLines
        if surface.kind == .wall, settings.openingSystem != nil {
            result.contacts = result.contacts.filter { contact in
                result.lines.contains { LayoutGeometry.distance(contact.point,to:$0.start,$0.end)<0.01 }
            }
        }
        if surface.kind == .wall, settings.openingSystem == .furring, let count = settings.intermediateSupportLines, count > 0 {
            for line in result.lines where abs(line.end.x-line.start.x)<0.5 {
                if result.wallFixedProfiles.contains(where:{ $0.role == .rightAngle && LayoutOpeningFraming.same($0.line,line) }) { continue }
                for row in wallRows where line.start.x >= row.start.x-0.01 && line.start.x <= row.end.x+0.01 {
                    let p=LayoutPoint(x:line.start.x,y:row.start.y)
                    if LayoutGeometry.distance(p,to:line.start,line.end)<0.01,
                       !result.supportPoints.contains(where:{($0-p).length<0.01}) { result.supportPoints.append(p) }
                }
            }
        }
        return result
    }
}
struct LayoutDocument: Codable, Equatable {
    var schemaVersion = 1
    var surface: Surface2D
    // V1 edits layer 1. Later layers can have independent formats and offsets.
    var layers: [LayoutLayer] = [.init()]
    var lighting: LayoutLighting? = nil
}
struct LayoutCutPiece: Equatable, Identifiable {
    var id: String
    var contour: [LayoutPoint]
    var holes: [[LayoutPoint]]
    var stock: LayoutStockUse? = nil
    var area: Double { abs(LayoutGeometry.area(contour)) - holes.reduce(0) { $0 + abs(LayoutGeometry.area($1)) } }
    var bounds: LayoutBounds { .init(points: contour) }
    func contains(_ p: LayoutPoint) -> Bool {
        LayoutGeometry.contains(p, in: contour) && !holes.contains { LayoutGeometry.contains(p, in: $0) }
    }
    // Interior point for a legible label even in a concave piece.
    var labelPoint: LayoutPoint {
        if contains(bounds.center) { return bounds.center }
        for e in LayoutGeometry.edges(contour) {
            let d = e.b - e.a, mid = (e.a + e.b) * 0.5
            let p = mid + LayoutPoint(x: -d.y, y: d.x) * (min(bounds.width, bounds.height) * 0.02 / d.length)
            if contains(p) { return p }
        }
        return contour[0]
    }
}
struct LayoutStockUse: Equatable {
    var number: Int
    var part: Int? = nil
    // Lower-left corner of the purchased sheet in this piece's grid frame.
    // This keeps the cutting diagram and spot coordinates correct after reuse.
    var origin: LayoutPoint
    var label: String { part.map { "\(number)-\($0)" } ?? "\(number)" }
}
struct LayoutSheetPlacement: Equatable, Identifiable {
    var id: String
    var number: Int
    var origin: LayoutPoint
    var width: Double
    var height: Double
    var pieces: [LayoutCutPiece]
    var area: Double { pieces.reduce(0) { $0 + $1.area } }
    var isFull: Bool { abs(area - width * height) < 0.01 }
    var wasteArea: Double { max(0, width * height - area) }
    func label(for piece: LayoutCutPiece) -> String {
        piece.stock?.label ?? (pieces.count > 1 ? "\(number)-\((pieces.firstIndex(where:{$0.id==piece.id}) ?? 0)+1)" : "\(number)")
    }
}
struct LayoutJoint: Equatable {
    var start: LayoutPoint
    var end: LayoutPoint
}
struct SheetLayoutResult: Equatable {
    var sheets: [LayoutSheetPlacement]
    var joints: [LayoutJoint]
    var frame = LayoutGridFrame()
    var furring = LayoutFurringResult()
    var staggerDistance = 0.0
    var netArea: Double { sheets.reduce(0) { $0 + $1.area } }
    var purchasedSheetCount: Int {
        let numbers = Set(sheets.flatMap(\.pieces).compactMap { $0.stock?.number })
        return numbers.isEmpty ? sheets.count : numbers.count
    }
    var savedSheetCount: Int { max(0,sheets.count-purchasedSheetCount) }
    var wasteArea: Double {
        guard let sheet=sheets.first else { return 0 }
        return max(0,Double(purchasedSheetCount)*sheet.width*sheet.height-netArea)
    }
    var pieceCount: Int { sheets.reduce(0) { $0 + $1.pieces.count } }
}
enum SheetLayoutEngine {
    static func calculate(surface: Surface2D, layer: LayoutLayer) throws -> SheetLayoutResult {
        let layer = layer.forSurface(surface)
        try LayoutGeometry.validate(surface.contour)
        guard surface.openings.count <= 100 else { throw LayoutGeometryError.tooLarge }
        for opening in surface.openings { try LayoutGeometry.validate(opening.contour) }
        let frame = LayoutGridFrame.make(surface:surface,layer:layer)
        guard frame.origin.finite, frame.angle.isFinite else { throw LayoutGeometryError.invalidFormat }
        var surface = surface
        surface.contour = surface.contour.map(frame.local)
        surface.openings = surface.openings.map { opening in
            var copy = opening; copy.contour = copy.contour.map(frame.local); return copy
        }
        let furring = try LayoutFurringEngine.calculate(surface:surface,layer:layer,gridFrame:frame)
        let measured = surface
        surface.contour = try surface.layingContour()
        let w = layer.cellWidth, h = layer.cellHeight
        guard w.isFinite, h.isFinite, w >= 1, h >= 1, w <= 100_000, h <= 100_000,
              layer.offset.finite, abs(layer.offset.x) <= 1_000_000, abs(layer.offset.y) <= 1_000_000 else { throw LayoutGeometryError.invalidFormat }
        var sheets = try LayoutBoardGrid.clippedSheets(surface:surface,layer:layer)
        let joints = LayoutBoardGrid.joints(sheets.flatMap(\.pieces))
        sheets = try LayoutOffcutPacking.assign(sheets, surface:measured, furring:furring, enabled:true,
            preserveFactoryEdges: surface.kind == .ceiling && layer.fourTaperedEdges == true)
        return .init(sheets: sheets, joints: joints, frame:frame,
                     furring:furring,staggerDistance:LayoutBoardGrid.staggerDistance(layer))
    }
}

/// One source for the computed layout and the lightweight grid drawn during a
/// drag. Alternate strips shift along the LONG board axis, never across it.
enum LayoutBoardGrid {
    /// Geometry only: no offcut packing or optimization during a gesture.
    /// Surface is in grid coordinates, with its laying contour already applied.
    static func clippedSheets(surface:Surface2D,layer:LayoutLayer) throws -> [LayoutSheetPlacement] {
        let w=layer.cellWidth, h=layer.cellHeight
        let cells = try cells(bounds:surface.bounds,layer:layer)
        var sheets:[LayoutSheetPlacement]=[]
        for cell in cells {
                try Task.checkCancellation()
                let origin = cell.origin
                let bounds = LayoutBounds(min: origin, max: origin + .init(x: w, y: h))
                let loops = try LayoutGeometry.intersection(outer: surface.contour, holes: surface.openings.map(\.contour), rectangle: bounds)
                let outers = loops.filter { LayoutGeometry.area($0) > 0 }
                let holes = loops.filter { LayoutGeometry.area($0) < 0 }
                let id = cell.id
                var pieces: [LayoutCutPiece] = []
                for (index, outer) in outers.enumerated() {
                    let enclosed = holes.filter { LayoutGeometry.contains($0[0], in: outer) }
                    let piece = LayoutCutPiece(id: "\(id):\(index)", contour: outer, holes: enclosed)
                    if piece.area > LayoutGeometry.minimumArea { pieces.append(piece) }
                }
                guard !pieces.isEmpty else { continue }
                sheets.append(.init(id: id, number: sheets.count + 1, origin: origin, width: w, height: h, pieces: pieces))
        }
        return sheets
    }
    /// Framing movement, lighting and camera changes do not invalidate board cuts.
    static func sameGeometry(_ a:LayoutDocument,_ b:LayoutDocument) -> Bool {
        guard a.surface == b.surface, var x=a.layers.first, var y=b.layers.first else { return false }
        guard staggerDistance(x) == staggerDistance(y) else { return false }
        x.furring=nil; y.furring=nil
        return x == y
    }
    struct Cell { var id:String; var origin:LayoutPoint }
    static func staggerChoices(_ layer:LayoutLayer) -> [Double] {
        let length = max(layer.cellWidth,layer.cellHeight)
        guard length.isFinite, length > 0, let f=layer.furring,
              LayoutPlanning.compatibleSpacings(layer).contains(f.spacing) else { return [] }
        if layer.resolvedFurringOrientation == layer.orientation { return [length/2] }
        let ratio=(length/f.spacing).rounded()
        guard ratio.isFinite, ratio>1, ratio<=250 else { return [] }
        let count = Int(ratio)
        return (1..<count).map { Double($0)*f.spacing }.sorted {
            abs($0-length/2) == abs($1-length/2) ? $0 < $1 : abs($0-length/2) < abs($1-length/2)
        }
    }
    static func staggerDistance(_ layer:LayoutLayer) -> Double {
        guard layer.staggered == true else { return 0 }
        let choices=staggerChoices(layer)
        if let requested=layer.staggerOffset, let matching=choices.first(where:{abs($0-requested)<0.001}) { return matching }
        return choices.first ?? 0
    }
    static func cells(bounds b:LayoutBounds, layer:LayoutLayer) throws -> [Cell] {
        let w=layer.cellWidth, h=layer.cellHeight, shift=staggerDistance(layer)
        guard w.isFinite,h.isFinite,w>=1,h>=1,w<=100_000,h<=100_000,layer.offset.finite,
              b.min.finite,b.max.finite,b.width>0,b.height>0,
              [b.min.x,b.min.y,b.max.x,b.max.y].allSatisfy({abs($0)<=1_000_000}) else { throw LayoutGeometryError.invalidFormat }
        func normalized(_ value:Double,_ period:Double) -> Double {
            let r=value.truncatingRemainder(dividingBy:period)
            return abs(r)<LayoutGeometry.epsilon ? 0 : (r<0 ? r+period : r)
        }
        let vertical=layer.orientation == .vertical
        let offset=LayoutPoint(x:normalized(layer.offset.x,w*(shift>0 && vertical ? 2 : 1)),
                               y:normalized(layer.offset.y,h*(shift>0 && !vertical ? 2 : 1)))
        let c0=Int(floor((b.min.x-offset.x-(vertical ? 0 : shift))/w)), c1=Int(ceil((b.max.x-offset.x)/w))
        let r0=Int(floor((b.min.y-offset.y-(vertical ? shift : 0))/h)), r1=Int(ceil((b.max.y-offset.y)/h))
        guard Double(c1-c0)*Double(r1-r0)<=4000 else { throw LayoutGeometryError.tooLarge }
        var result:[Cell]=[]
        for row in r0..<r1 { for col in c0..<c1 {
            let alternate=(vertical ? col : row)%2 != 0
            let p=offset+LayoutPoint(x:Double(col)*w+(!vertical && alternate ? shift : 0),
                                     y:Double(row)*h+(vertical && alternate ? shift : 0))
            guard p.x<b.max.x-0.001,p.y<b.max.y-0.001,p.x+w>b.min.x+0.001,p.y+h>b.min.y+0.001 else { continue }
            result.append(.init(id:"\(col):\(row)",origin:p))
        } }
        guard result.count<=2000 else { throw LayoutGeometryError.tooLarge }
        return result.sorted {
            let a = $0.origin, b = $1.origin
            return vertical ? (a.x == b.x ? a.y < b.y : a.x < b.x)
                : (a.y == b.y ? a.x < b.x : a.y < b.y)
        }
    }

    /// Split shared intervals at T junctions. Exact endpoint-key matching misses
    /// the shorter edges introduced by staggered courses.
    static func joints(_ pieces:[LayoutCutPiece]) -> [LayoutJoint] {
        struct Axis:Hashable { var vertical:Bool; var position:Int64 }
        var groups:[Axis:[(Double,Int)]]=[:]
        for piece in pieces { for e in LayoutGeometry.edges(piece.contour) {
            let vertical=abs(e.a.x-e.b.x)<LayoutGeometry.epsilon
            guard vertical || abs(e.a.y-e.b.y)<LayoutGeometry.epsilon else { continue }
            let key=Axis(vertical:vertical,position:Int64(((vertical ? e.a.x : e.a.y)/LayoutGeometry.epsilon).rounded()))
            let a=vertical ? e.a.y : e.a.x, b=vertical ? e.b.y : e.b.x
            groups[key,default:[]] += [(min(a,b),1),(max(a,b),-1)]
        } }
        var result:[LayoutJoint]=[]
        for key in groups.keys.sorted(by:{ $0.vertical == $1.vertical ? $0.position<$1.position : $0.vertical }) {
            let events=groups[key]!.sorted { $0.0<$1.0 }
            var count=0, previous=events[0].0
            for (position,change) in events {
                if count>=2,position-previous>LayoutGeometry.epsilon {
                    let coordinate=Double(key.position)*LayoutGeometry.epsilon
                    result.append(.init(start:key.vertical ? .init(x:coordinate,y:previous) : .init(x:previous,y:coordinate),
                                        end:key.vertical ? .init(x:coordinate,y:position) : .init(x:position,y:coordinate)))
                }
                count += change; previous=position
            }
        }
        return result
    }
}

/// Conservative rectangular-envelope packing: no rotation, no reuse inside an
/// opening, no imaginary material reclaimed from a diagonal or concave cut.
/// Units are millimetres. The 200 mm threshold is intentionally not a UI setting.
enum LayoutOffcutPacking {
    static let minimum = 200.0
    private struct Stock { var free:[LayoutBounds] }
    private struct Use { var stock:Int; var origin:LayoutPoint }

    static func hasSupports(_ piece:LayoutCutPiece, surface:Surface2D, furring:LayoutFurringResult) -> Bool {
        func contactLength(_ line:LayoutJoint) -> Double {
            guard piece.bounds.overlaps(.init(points:[line.start,line.end])) else { return 0 }
            let segment=LayoutGeometry.Edge(a:line.start,b:line.end)
            var cuts=[0.0,1.0]
            for edge in ([piece.contour]+piece.holes).flatMap({LayoutGeometry.edges($0)}) {
                cuts += LayoutGeometry.splitParameters(segment,by:edge)
            }
            cuts=cuts.filter{$0>=0 && $0<=1}.sorted()
            let d=line.end-line.start
            func onBoundary(_ p:LayoutPoint,_ contour:[LayoutPoint]) -> Bool {
                LayoutGeometry.edges(contour).contains { LayoutGeometry.distance(p,to:$0.a,$0.b)<0.001 }
            }
            return zip(cuts,cuts.dropFirst()).reduce(0) { sum,pair in
                let p=line.start+d*((pair.0+pair.1)/2)
                let inside=LayoutGeometry.contains(p,in:piece.contour) || onBoundary(p,piece.contour)
                let inHole=piece.holes.contains { LayoutGeometry.contains(p,in:$0) && !onBoundary(p,$0) }
                return sum + (inside && !inHole ? (pair.1-pair.0)*d.length : 0)
            }
        }
        func collinear(_ a:LayoutJoint,_ b:LayoutJoint) -> Bool {
            let v=a.end-a.start
            return v.length>0 && abs(LayoutGeometry.cross(v,b.start-a.start))/v.length<0.01 &&
                abs(LayoutGeometry.cross(v,b.end-a.start))/v.length<0.01
        }
        var supports:[LayoutJoint]=[]
        for line in furring.lines where contactLength(line)>1 {
            if !supports.contains(where:{collinear($0,line)}) { supports.append(line) }
            if supports.count>=2 { return true }
        }
        guard let support=supports.first else { return false }
        // Openings are not load-bearing peripheries; only the measured outer
        // boundary qualifies. A line coincident with a furring is not two supports.
        return LayoutGeometry.edges(surface.contour).contains { edge in
            let line=LayoutJoint(start:edge.a,end:edge.b)
            return !collinear(support,line) && contactLength(line)>1
        }
    }

    static func assign(_ input:[LayoutSheetPlacement], surface:Surface2D,
                       furring:LayoutFurringResult, enabled:Bool, preserveFactoryEdges:Bool = false) throws -> [LayoutSheetPlacement] {
        guard let first=input.first else { return input }
        let size=LayoutPoint(x:first.width,y:first.height)
        let joints = preserveFactoryEdges ? LayoutBoardGrid.joints(input.flatMap(\.pieces)) : []
        // Precompute only the joints touching each group, outside the packing search.
        let contacts = input.map { sharedEdges(of:$0, joints:joints) }
        let envelopes=input.map { LayoutBounds(points:$0.pieces.flatMap(\.contour)) }
        let eligible=input.map { sheet in
            enabled && !sheet.isFull && sheet.pieces.allSatisfy {
                $0.bounds.width>=minimum-0.001 && $0.bounds.height>=minimum-0.001 &&
                hasSupports($0,surface:surface,furring:furring)
            }
        }
        var stocks:[Stock]=[], uses:[Int:Use]=[:]
        let order=input.indices.sorted {
            let a=envelopes[$0].width*envelopes[$0].height, b=envelopes[$1].width*envelopes[$1].height
            return abs(a-b)<0.001 ? $0<$1 : a>b
        }
        for index in order {
            try Task.checkCancellation()
            let box=envelopes[index]
            var candidate:(stock:Int,rect:Int,score:Double,occupied:LayoutBounds)?
            if eligible[index] {
                for s in stocks.indices { for r in stocks[s].free.indices {
                    let free=stocks[s].free[r]
                    guard box.width<=free.width+0.001,box.height<=free.height+0.001 else { continue }
                    let score=free.width*free.height-box.width*box.height
                    // Try all corners: the required factory edge may be at the
                    // far end of the purchased board, not at the scrap's origin.
                    let anchors = [free.min, .init(x:free.max.x-box.width,y:free.min.y),
                        .init(x:free.min.x,y:free.max.y-box.height),
                        .init(x:free.max.x-box.width,y:free.max.y-box.height)]
                    for anchor in anchors {
                        let origin = box.min-anchor
                        guard !preserveFactoryEdges || factoryEdges(contacts[index],origin:origin,size:size) else { continue }
                        if candidate == nil || score<candidate!.score {
                            candidate=(s,r,score,.init(min:anchor,max:anchor + .init(x:box.width,y:box.height)))
                        }
                    }
                } }
            }
            let stock:Int, occupied:LayoutBounds
            if let candidate {
                stock=candidate.stock
                let free=stocks[stock].free.remove(at:candidate.rect)
                occupied = candidate.occupied
                stocks[stock].free += remainder(of:free,removing:occupied)
            } else {
                stock=stocks.count
                // Retain the original cutting position for an ineligible group.
                let lower=eligible[index] && !preserveFactoryEdges ? LayoutPoint.zero : box.min-input[index].origin
                occupied = .init(min:lower,max:lower + .init(x:box.width,y:box.height))
                stocks.append(.init(free:enabled ? remainder(of:.init(min:.zero,max:size),removing:occupied) : []))
            }
            uses[index] = .init(stock:stock,origin:box.min-occupied.min)
        }
        // Number purchased sheets by their first appearance on the plan, not by
        // packing order. Number all their pieces together: 2-1, 2-2, etc.
        var numbers:[Int:Int]=[:], totals:[Int:Int]=[:], ranks:[Int:Int]=[:]
        for i in input.indices {
            let s=uses[i]!.stock
            if numbers[s]==nil { numbers[s]=numbers.count+1 }
            totals[s,default:0] += input[i].pieces.count
        }
        var result=input
        for i in result.indices { for j in result[i].pieces.indices {
            let use=uses[i]!, rank=ranks[use.stock,default:0]+1
            ranks[use.stock]=rank
            result[i].pieces[j].stock = .init(number:numbers[use.stock]!,part:totals[use.stock]! > 1 ? rank : nil,origin:use.origin)
        } }
        return result
    }
    static func sharedEdges(of sheet:LayoutSheetPlacement, joints:[LayoutJoint]) -> [LayoutJoint] {
        sheet.pieces.flatMap { piece in
            LayoutGeometry.edges(piece.contour).compactMap { edge in
                let v = edge.b-edge.a
                guard v.length > 0.001 else { return nil }
                let touches = joints.contains { joint in
                    guard abs(LayoutGeometry.cross(v,joint.start-edge.a))/v.length < 0.001,
                          abs(LayoutGeometry.cross(v,joint.end-edge.a))/v.length < 0.001 else { return false }
                    let u = v*(1/v.length)
                    func along(_ p:LayoutPoint) -> Double { let d=p-edge.a; return d.x*u.x+d.y*u.y }
                    return min(v.length,max(along(joint.start),along(joint.end))) - max(0,min(along(joint.start),along(joint.end))) > 0.001
                }
                return touches ? LayoutJoint(start:edge.a,end:edge.b) : nil
            }
        }
    }
    static func factoryEdges(_ contacts:[LayoutJoint], origin:LayoutPoint, size:LayoutPoint) -> Bool {
        contacts.allSatisfy { edge in
            let a=edge.start-origin, b=edge.end-origin
            return [0.0,size.x].contains { abs(a.x-$0)<0.001 && abs(b.x-$0)<0.001 } ||
                [0.0,size.y].contains { abs(a.y-$0)<0.001 && abs(b.y-$0)<0.001 }
        }
    }
    private static func remainder(of free:LayoutBounds, removing box:LayoutBounds) -> [LayoutBounds] {
        // Four disjoint rectangles outside the reserved envelope. Holes and
        // diagonal scraps inside the envelope are deliberately not available.
        [LayoutBounds(min:free.min,max:.init(x:box.min.x,y:free.max.y)),
         .init(min:.init(x:box.max.x,y:free.min.y),max:free.max),
         .init(min:.init(x:box.min.x,y:free.min.y),max:.init(x:box.max.x,y:box.min.y)),
         .init(min:.init(x:box.min.x,y:box.max.y),max:.init(x:box.max.x,y:free.max.y))]
            .filter { $0.width>=minimum-0.001 && $0.height>=minimum-0.001 }
    }
}

enum LayoutPreset: String, CaseIterable {
    case rectangle = "Rectangle", slope = "Sous rampant", gable = "Pignon", lShape = "En L", freeform = "Dessiner la forme"

    func isAvailable(for kind: LayoutSupportKind) -> Bool {
        switch (kind, self) {
        case (_, .rectangle), (_, .freeform), (.wall, .slope), (.ceiling, .lShape):
            return true
        default:
            return false
        }
    }

    static func available(for kind: LayoutSupportKind) -> [Self] {
        allCases.filter { $0.isAvailable(for: kind) }
    }
    func contour(length: Double, height: Double, secondaryHeight: Double, mirrored: Bool = false,
                 lowerLength: Double? = nil) -> [LayoutPoint] {
        switch self {
        case .rectangle, .freeform:
            return [.zero, .init(x: length, y: 0), .init(x: length, y: height), .init(x: 0, y: height)]
        case .slope:
            let left = mirrored ? secondaryHeight : height, right = mirrored ? height : secondaryHeight
            return [.zero, .init(x: length, y: 0), .init(x: length, y: right), .init(x: 0, y: left)]
        case .gable:
            return [.zero, .init(x: length, y: 0), .init(x: length, y: height),
                    .init(x: length / 2, y: secondaryHeight), .init(x: 0, y: height)]
        case .lShape:
            // Preserve older saved L-shaped ceilings whose third dimension was
            // the depth of the return. New wall forms use min/max heights.
            let normal: [LayoutPoint]
            if secondaryHeight < height {
                normal = [.zero, .init(x: length, y: 0), .init(x: length, y: height / 2),
                          .init(x: length / 2, y: height / 2), .init(x: length / 2, y: height), .init(x: 0, y: height)]
            } else {
                let low = min(length - 10, max(10, lowerLength ?? length / 2))
                normal = [.init(x: length, y: height), .init(x: length - low, y: height),
                          .init(x: length - low, y: secondaryHeight), .init(x: 0, y: secondaryHeight),
                          .zero, .init(x: length, y: 0)]
            }
            return mirrored ? normal.map { .init(x: length - $0.x, y: $0.y) } : normal
        }
    }
    func contour(width: Double, height: Double, secondaryHeight: Double) -> [LayoutPoint] {
        contour(length: width, height: height, secondaryHeight: secondaryHeight)
    }
}
