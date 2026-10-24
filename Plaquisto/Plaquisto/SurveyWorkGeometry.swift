import Foundation
import CryptoKit

/// Presentation-only finished surfaces. Never writes back into a scan, a work,
/// its areas, or the DAE exporter. Dimensions come from the saved configuration.
enum SurveyWorkPreview {
    struct Mesh: Equatable {
        var surfaceID: String
        var kind: SurveySurfaceSource.Kind
        var triangles: [RoomPoint]
        var joints: [RoomPoint]
    }
    static func ceilingDrop(_ payload: WorkConfiguration) -> Double {
        let cm: Double
        switch payload {
        case .ceiling(let c): cm = c.plenum
        case .modularCeiling(let c): cm = c.plenumCM
        case .railStudCeiling(let c):
            let layers = [c.firstInsulation] + (c.insulationLayers == 2 ? [c.secondInsulation] : [])
            let below = c.insulationEnabled ? layers.filter { c.support != "wood" || $0.location == "below" }.reduce(0) { $0 + $1.thickness } : 0
            cm = c.frameMode == "selfSupporting" ? 0 : Double(below) / 10 + c.extraPlenumCM
        default: cm = 0
        }
        return cm.isFinite && cm > 0 && cm < 1000 ? cm / 100 : 0
    }
    static func make(survey: ProjectSurveyRecord, surfaces: [SurveyWorkSurface], works: [WorkItem], showJoints: Bool) -> [Mesh] {
        var result: [Mesh] = []
        let separate = survey.checkpoints.count > 1 && survey.checkpoints.contains { $0.spatialLinkState == .needsLink }
        var displayOffset = 0.0
        for checkpoint in survey.checkpoints {
            let values = surfaces.filter { $0.source.checkpointID == checkpoint.id }
            let points = values.flatMap(\.triangles)
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
            func transform(_ p: RoomPoint) -> RoomPoint {
                if separate { return .init(x: p.x - minX + displayOffset, y: p.y, z: p.z) }
                let t = checkpoint.transformToSurvey.values
                return .init(x: t[0]*p.x + t[4]*p.y + t[8]*p.z + t[12],
                    y: t[1]*p.x + t[5]*p.y + t[9]*p.z + t[13], z: t[2]*p.x + t[6]*p.y + t[10]*p.z + t[14])
            }
            let room = checkpoint.document.room
            let rings = ScanEnclosedSpaces.wallsBySpace(in: room)
            for selection in values {
                let candidates = works.flatMap { work in work.components.compactMap { component -> (WorkItem, WorkComponentRecord)? in
                    guard let source = component.surveySource, SurveyWorkGeometry.hasSameSource(source, selection.source) else { return nil }
                    return (work, component)
                } }
                // A painting work and a lining can refer to the same wall. Draw
                // the finished lining once, not two coincident opaque surfaces.
                guard let (work, component) = candidates.max(by: {
                    (SurveyPlanFinishes.depth($0.0.payload) ?? ceilingDrop($0.0.payload)) < (SurveyPlanFinishes.depth($1.0.payload) ?? ceilingDrop($1.0.payload))
                }), let surface = component.surface, let frame = surface.localFrame else { continue }
                let ceiling = selection.source.kind == .ceiling
                var normal = RoomPoint(x: 0, y: -1, z: 0)
                if !ceiling {
                    normal = .init(x: -frame.axisX.z, y: 0, z: frame.axisX.x)
                    if let ringWall = rings.flatMap({ $0 }).first(where: { $0.id == selection.source.surfaceID }) {
                        normal = .init(x: -ringWall.direction.z, y: 0, z: ringWall.direction.x)
                    } else {
                        let center = room.walls.reduce(RoomPoint.zero) { $0 + $1.start } * (1 / Double(max(1, room.walls.count)))
                        let toward = center - RoomPoint(x: frame.origin.x, y: frame.origin.y, z: frame.origin.z)
                        if toward.x * normal.x + toward.z * normal.z < 0 { normal = normal * -1 }
                    }
                }
                let depth = ceiling ? ceilingDrop(work.payload) : (SurveyPlanFinishes.depth(work.payload) ?? 0)
                let offset = normal * max(0.003, depth)
                let originalTriangles = SurveyWorkGeometry.ceilingTriangles(surface)
                guard !originalTriangles.isEmpty else { continue }
                let wall = room.walls.first { $0.id == selection.source.surfaceID }
                let back = min(0.4, max(0.04, wall?.thickness?.effectiveValue ?? 0.08)) / 2
                let triangles: [RoomPoint]
                if !ceiling {
                    let front = max(0.003, depth)
                    triangles = SurveySceneRenderer.wallSolid(originalTriangles.map { $0 + normal * ((front - back) / 2) }, normal: normal, thickness: front + back)
                } else { triangles = originalTriangles.map { $0 + offset } }
                var joints: [RoomPoint] = []
                var faces: [(LayoutDocument, RoomPoint)] = []
                if showJoints {
                    let front = component.plans.first { !component.isOppositeSide($0.sideRoomID) }
                    if let front, let document = component.document(for: front) {
                        faces.append((document, offset + normal * 0.002))
                    }
                    if !ceiling, work.isPartition {
                        if let rear = component.plans.first(where: { component.isOppositeSide($0.sideRoomID) }),
                           let document = component.document(for: rear) {
                            faces.append((document, normal * (-back - 0.002)))
                        } else if let front, var document = component.document(for: front) {
                            // Legacy partitions may only have a saved front plan.
                            // Mirror its pattern for display, without creating a plan
                            // or changing quantities. A saved rear plan always wins.
                            document.surface = document.surface.mirroredComponentSide()
                            faces.append((document, normal * (-back - 0.002)))
                        }
                    }
                }
                for (document, faceOffset) in faces {
                    guard let rawLayer = document.layers.last,
                          let faceFrame = document.surface.localFrame else { continue }
                    let layer = rawLayer.forSurface(document.surface)
                    let grid = LayoutGridFrame.make(surface: document.surface, layer: layer)
                    var local = document.surface
                    local.contour = local.contour.map(grid.local)
                    local.openings = local.openings.map { var copy = $0; copy.contour = copy.contour.map(grid.local); return copy }
                    if let contour = try? local.layingContour() { local.contour = contour }
                    if let sheets = try? LayoutBoardGrid.clippedSheets(surface: local, layer: layer) {
                        let lines = LayoutBoardGrid.joints(sheets.flatMap(\.pieces))
                        func world(_ p: LayoutPoint) -> RoomPoint {
                            let p = grid.world(p)
                            return RoomPoint(x: faceFrame.origin.x + (faceFrame.axisX.x*p.x + faceFrame.axisY.x*p.y)/1000,
                                y: faceFrame.origin.y + (faceFrame.axisX.y*p.x + faceFrame.axisY.y*p.y)/1000,
                                z: faceFrame.origin.z + (faceFrame.axisX.z*p.x + faceFrame.axisY.z*p.y)/1000) + faceOffset
                        }
                        joints += lines.flatMap { [world($0.start), world($0.end)] }
                    }
                }
                result.append(.init(surfaceID: selection.id, kind: selection.source.kind, triangles: triangles.map(transform), joints: joints.map(transform)))
            }
            displayOffset += maxX - minX + 2
        }
        return result
    }
}

/// Portable COLLADA writer: SceneKit's DAE *writer* is macOS-only.
/// Export domain geometry, never cameras, selection overlays or display recentering.
enum SurveyDAEExport {
    struct Mesh {
        var name:String
        var kind:String
        var triangles:[RoomPoint]
    }
    /// Shared position indices make coplanar faces connected in DAE importers.
    /// Exact welding only: never close a real gap or alter measured coordinates.
    static func indexedPositions(_ points: [RoomPoint]) -> (points: [RoomPoint], indices: [Int]) {
        var unique:[RoomPoint]=[], indices:[Int]=[], lookup:[String:Int]=[:]
        for p in points {
            let key="\(p.x == 0 ? 0 : p.x)/\(p.y == 0 ? 0 : p.y)/\(p.z == 0 ? 0 : p.z)"
            if let index=lookup[key] { indices.append(index) }
            else { lookup[key]=unique.count; indices.append(unique.count); unique.append(p) }
        }
        return (unique,indices)
    }
    enum Failure:Error,LocalizedError {
        case empty, unlinked, invalid
        case invalidSurface(String)
        var errorDescription:String? {
            switch self {
            case .empty: "Ce relevé ne contient aucune surface exportable."
            case .unlinked: "Confirmez les raccords entre les zones avant d’exporter le relevé en DAE."
            case .invalid: "La géométrie du relevé contient une donnée invalide et ne peut pas être exportée."
            case .invalidSurface(let name): "Impossible d’exporter « \(name) » : son contour ou ses dimensions sont invalides. Vérifiez cette surface dans Modifier le plan."
            }
        }
    }
    static func meshes(for survey:ProjectSurveyRecord) throws -> [Mesh] {
        guard survey.checkpoints.count < 2 || !survey.checkpoints.contains(where:{ $0.spatialLinkState == .needsLink }) else { throw Failure.unlinked }
        for checkpoint in survey.checkpoints {
            guard checkpoint.transformToSurvey.isValid else { throw Failure.invalid }
            // Validate before invoking the geometry engine, including NaN/Inf.
            // Export the current edited model, not its historical snapshot.
            do { try PlaquistoRoomDocument(room:checkpoint.document.room).validate() }
            catch { throw Failure.invalidSurface(checkpoint.document.room.name ?? "Pièce") }
        }
        let surfaces=SurveyWorkGeometry.surfaces(in:survey)
        var meshes:[Mesh]=[]
        for checkpoint in survey.checkpoints {
            let t=checkpoint.transformToSurvey.values
            let room=checkpoint.document.room
            let roomName=room.name ?? "Pièce"
            // The selection API deliberately skips unusable surfaces; an exporter
            // must instead report them so a partial file never looks complete.
            let selected=surfaces.filter { $0.source.checkpointID == checkpoint.id }
            for (index,wall) in room.walls.enumerated() where !selected.contains(where: { $0.source.kind == .wall && $0.source.surfaceID == wall.id }) {
                throw Failure.invalidSurface("\(roomName) · Mur \(index+1)")
            }
            for (index,slope) in room.slopes.filter(\.accepted).enumerated() where !selected.contains(where: { $0.source.kind == .ceiling && $0.source.surfaceID == slope.id }) {
                throw Failure.invalidSurface("\(roomName) · Plafond \(index+1)")
            }
            func transform(_ p:RoomPoint) -> RoomPoint {
                .init(x:t[0]*p.x+t[4]*p.y+t[8]*p.z+t[12],
                      y:t[1]*p.x+t[5]*p.y+t[9]*p.z+t[13],
                      z:t[2]*p.x+t[6]*p.y+t[10]*p.z+t[14])
            }
            for surface in selected {
                let name="\(surface.roomName) · \(surface.name)"
                var triangles=try usableTriangles(surface.triangles,name:name)
                if surface.source.kind == .wall,
                   let wall=checkpoint.document.room.walls.first(where:{ $0.id == surface.source.surfaceID }),
                   let thickness=wall.thickness?.effectiveValue, thickness.isFinite, thickness > 0 {
                    // Only a measured/authored thickness is exported. No invented 8 cm
                    // thickness from the illustrative viewer becomes a measurement.
                    triangles=SurveySceneRenderer.wallSolid(triangles,normal:.init(x:-wall.direction.z,y:0,z:wall.direction.x),thickness:thickness)
                }
                meshes.append(.init(name:name,kind:surface.source.kind == .wall ? "wall" : "ceiling",triangles:try usableTriangles(triangles.map(transform),name:name)))
            }
            for (index,floor) in checkpoint.document.room.floors.enumerated() {
                guard let outer=floor.boundaries.first, outer.count >= 3 else { throw Failure.invalid }
                let holes=floor.boundaries.dropFirst().map { boundary in
                    LayoutOpening(kind:.other,contour:boundary.map { .init(x:$0.x*1000,y:$0.z*1000) })
                }
                let shape=Surface2D(name:"Sol",kind:.ceiling,contour:outer.map { .init(x:$0.x*1000,y:$0.z*1000) },openings:holes,
                    localFrame:.init(origin:.init(x:0,y:floor.referenceElevation ?? outer[0].y,z:0),axisX:.init(x:1,y:0,z:0),axisY:.init(x:0,y:0,z:1)))
                guard (try? shape.netMeasuredArea()) != nil else { throw Failure.invalid }
                let name="\(roomName) · Sol \(index+1)"
                meshes.append(.init(name:name,kind:"floor",
                    triangles:try usableTriangles(SurveyWorkGeometry.ceilingTriangles(shape).map(transform),name:name)))
            }
            for (index, column) in (room.columns ?? []).enumerated() {
                let name = "\(roomName) · Poteau \(index+1)"
                meshes.append(.init(name: name, kind: "wall", triangles: try usableTriangles(column.triangles.map(transform), name: name)))
            }
        }
        guard !meshes.isEmpty else { throw Failure.empty }
        return meshes
    }
    /// Scan-line triangulation emits two triangles per band. At a pointed end,
    /// one has zero area (two coincident vertices), even for a valid surface.
    /// Remove only these invisible primitives, never an entire surface. NaN,
    /// malformed triples and fully collapsed meshes still fail explicitly.
    private static func usableTriangles(_ points:[RoomPoint],name:String) throws -> [RoomPoint] {
        guard !points.isEmpty, points.count.isMultiple(of:3),
              points.allSatisfy({ $0.finite && max(abs($0.x),abs($0.y),abs($0.z)) < 1e8 }) else {
            throw Failure.invalidSurface(name)
        }
        var result:[RoomPoint]=[]
        result.reserveCapacity(points.count)
        for i in stride(from:0,to:points.count,by:3) {
            let u=points[i+1]-points[i],v=points[i+2]-points[i]
            let normal=RoomPoint(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
            guard normal.finite, normal.length.isFinite else { throw Failure.invalidSurface(name) }
            if normal.length > 1e-12 { result.append(contentsOf:points[i...i+2]) }
        }
        guard !result.isEmpty else { throw Failure.invalidSurface(name) }
        return result
    }
    static func xml(meshes:[Mesh], title:String, date:Date) throws -> String {
        guard !meshes.isEmpty else { throw Failure.empty }
        func escape(_ value:String) -> String {
            String(value.unicodeScalars.filter { $0.value >= 32 && $0.value != 0xfffe && $0.value != 0xffff })
                .replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;")
                .replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")
        }
        func source(_ id:String,_ points:[RoomPoint]) -> String {
            let floats=points.map { "\($0.x) \($0.y) \($0.z)" }.joined(separator:" ")
            return "<source id=\"\(id)\"><float_array id=\"\(id)-array\" count=\"\(points.count*3)\">\(floats)</float_array><technique_common><accessor source=\"#\(id)-array\" count=\"\(points.count)\" stride=\"3\"><param name=\"X\" type=\"float\"/><param name=\"Y\" type=\"float\"/><param name=\"Z\" type=\"float\"/></accessor></technique_common></source>"
        }
        let stamp=ISO8601DateFormatter().string(from:date)
        var geometries="", nodes=""
        for (index,input) in meshes.enumerated() {
            var mesh=input
            mesh.triangles=try usableTriangles(mesh.triangles,name:mesh.name)
            guard ["wall","ceiling","floor"].contains(mesh.kind) else { throw Failure.invalid }
            let id="mesh-\(index)"
            var normals:[RoomPoint]=[]
            for i in stride(from:0,to:mesh.triangles.count,by:3) {
                let u=mesh.triangles[i+1]-mesh.triangles[i],v=mesh.triangles[i+2]-mesh.triangles[i]
                let n=RoomPoint(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
                guard n.finite, n.length.isFinite, n.length > 1e-12 else { throw Failure.invalid }
                normals += Array(repeating:n*(1/n.length),count:3)
            }
            let positions=indexedPositions(mesh.triangles)
            let indices=mesh.triangles.indices.map { "\(positions.indices[$0]) \($0)" }.joined(separator:" ")
            geometries += """
            <geometry id="\(id)" name="\(id)"><asset><created>\(stamp)</created><modified>\(stamp)</modified><title>\(escape(mesh.name))</title></asset><mesh>
            \(source(id+"-positions",positions.points))\(source(id+"-normals",normals))
            <vertices id="\(id)-vertices"><input semantic="POSITION" source="#\(id)-positions"/></vertices>
            <triangles count="\(mesh.triangles.count/3)" material="surface"><input semantic="VERTEX" source="#\(id)-vertices" offset="0"/><input semantic="NORMAL" source="#\(id)-normals" offset="1"/><p>\(indices)</p></triangles>
            </mesh></geometry>
            """
            // NCName-safe node names, with the human name retained in asset/title.
            let name=mesh.name.components(separatedBy:CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator:"_")
            nodes += "<node id=\"node-\(index)\" name=\"Surface_\(escape(name))\"><instance_geometry url=\"#\(id)\"><bind_material><technique_common><instance_material symbol=\"surface\" target=\"#\(mesh.kind)-material\"/></technique_common></bind_material></instance_geometry></node>"
        }
        var effects="",materials=""
        for (kind,color) in [("wall","0.88 0.87 0.84 1"),("floor","0.66 0.64 0.59 1"),("ceiling","0.95 0.95 0.93 1")] {
            effects += "<effect id=\"\(kind)-effect\"><profile_COMMON><technique sid=\"common\"><lambert><diffuse><color>\(color)</color></diffuse></lambert></technique><extra><technique profile=\"GOOGLEEARTH\"><double_sided>1</double_sided></technique></extra></profile_COMMON></effect>"
            materials += "<material id=\"\(kind)-material\"><instance_effect url=\"#\(kind)-effect\"/></material>"
        }
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
        <asset><contributor><authoring_tool>Plaquisto</authoring_tool></contributor><created>\(stamp)</created><modified>\(stamp)</modified><title>\(escape(title))</title><unit name="meter" meter="1"/><up_axis>Y_UP</up_axis></asset>
        <library_effects>\(effects)</library_effects><library_materials>\(materials)</library_materials>
        <library_geometries>\(geometries)</library_geometries>
        <library_visual_scenes><visual_scene id="Survey">\(nodes)</visual_scene></library_visual_scenes>
        <scene><instance_visual_scene url="#Survey"/></scene></COLLADA>
        """
    }
    static func write(_ survey:ProjectSurveyRecord) throws -> URL {
        let contents=try xml(meshes:meshes(for:survey),title:survey.name,date:survey.scanDate)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("PlaquistoDAE").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let name=survey.name.components(separatedBy:CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator:"-")
        let url=folder.appendingPathComponent(String((name.isEmpty ? "Releve-3D" : name).prefix(80))+".dae")
        try contents.write(to:url,atomically:true,encoding:.utf8)
        return url
    }
}

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

/// Applies only the opening delta from a saved wall layout. The raw capture,
/// unrelated openings and edited wall contours are never overwritten.
enum SurveyLayoutOpeningSync {
    static func apply(before:Surface2D,after:Surface2D,wallID:UUID,
                      document:PlaquistoRoomDocument) throws -> PlaquistoRoomDocument {
        guard let frame=after.localFrame,
              let wall=document.room.walls.first(where:{$0.id == wallID}) else { throw RoomModelError.invalidGeometry }
        let old=Dictionary(uniqueKeysWithValues:before.openings.map { ($0.id,$0) })
        let newIDs=Set(after.openings.map(\.id))
        let changed=after.openings.filter { old[$0.id] != $0 }
        let removed=Set(old.keys).subtracting(newIDs).union(changed.map(\.id))
        var result=document
        result.room.openings.removeAll { $0.wallID == wallID && removed.contains($0.id) }
        for i in result.room.walls.indices { result.room.walls[i].openingIDs.removeAll { removed.contains($0) } }
        for opening in changed {
            let local:[LayoutPoint]=opening.contour.map { point in
                let origin=RoomPoint(x:frame.origin.x,y:frame.origin.y,z:frame.origin.z)
                let x=RoomPoint(x:frame.axisX.x,y:frame.axisX.y,z:frame.axisX.z) * (point.x/1000)
                let y=RoomPoint(x:frame.axisY.x,y:frame.axisY.y,z:frame.axisY.z) * (point.y/1000)
                let delta=origin+x+y-wall.start
                return .init(x:delta.x*wall.direction.x+delta.z*wall.direction.z,y:delta.y)
            }
            let bounds=LayoutBounds(points:local)
            // The portable wall model represents rectangular openings. Refuse an
            // oblique/free-form replacement rather than silently enlarge the hole.
            let rectangular=local.allSatisfy { p in
                let onX=min(abs(p.x-bounds.min.x),abs(p.x-bounds.max.x)) < 0.00001
                let onY=min(abs(p.y-bounds.min.y),abs(p.y-bounds.max.y)) < 0.00001
                return onX && onY
            }
            guard local.count == 4,rectangular,bounds.min.x >= -0.000001,bounds.min.y >= -0.000001 else { throw RoomModelError.invalidGeometry }
            let kind:RoomOpeningKind = switch opening.kind {
            case .door: .door
            case .window: .window
            case .bay: .glazedBay
            case .passage: .passage
            default: .other
            }
            let existing=document.room.openings.first { $0.id == opening.id }
            result = try SurveyPlanEditing.addingDoor(result,wallID:wallID,width:bounds.width,height:bounds.height,
                position:max(0,bounds.min.x),handing:opening.doorHanding,openingSide:opening.doorOpeningSide,
                kind:kind,sill:max(0,bounds.min.y),pocket:existing?.isPocketDoor == true)
            let index=result.room.openings.count-1
            let generated=result.room.openings[index].id
            result.room.openings[index].id=opening.id
            result.room.openings[index].layoutKind=opening.kind
            for i in result.room.walls.indices {
                result.room.walls[i].openingIDs=result.room.walls[i].openingIDs.map { $0 == generated ? opening.id : $0 }
            }
        }
        try result.validate()
        return result
    }
}

enum SurveyWorkGeometry {
    /// Projection is repeatable: rebuilding a selection must not manufacture new
    /// identities and make a prepared calepinage appear to have changed geometry.
    /// Include the checkpoint and boundary so disjoint ceiling parts stay distinct.
    private static func projectedID(_ source: SurveySurfaceSource, hole: Int? = nil) -> UUID {
        let key = "plaquisto-survey-projection/v1/\(source.surveyID)/\(source.checkpointID)/\(source.kind.rawValue)/\(source.surfaceID)/\(source.boundaryIndex)/\(hole.map { "hole/\($0)" } ?? "surface")"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80 // UUIDv8: application-defined stable hash.
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    /// Do not filter the canonical geometry: hidden ceilings still feed existing works.
    static func isHidden(_ surface: SurveyWorkSurface, in survey: ProjectSurveyRecord) -> Bool {
        guard surface.source.kind == .ceiling,
              let room = survey.checkpoints.first(where: { $0.id == surface.source.checkpointID })?.document.room else { return false }
        return room.ceilings.contains { $0.isHidden == true && $0.slopeIDs.contains(surface.source.surfaceID) }
    }
    /// Standalone snapshot: retain exact scanned geometry/openings, without
    /// assigning a work, creating a project or modifying the source survey.
    static func quickLayoutDocument(_ selected:SurveyWorkSurface) -> LayoutDocument {
        var surface=selected.surface
        surface.id=UUID()
        surface.name="\(selected.roomName) · \(selected.name)"
        return .newSupport(surface)
    }
    /// An explicit split is the only geometry edit allowed to inherit a saved
    /// layout automatically. Both children remain in the parent's local frame.
    static func splitComponents(_ component:WorkComponentRecord, old:SurveyWorkSurface,
                                children:[SurveyWorkSurface]) throws -> [WorkComponentRecord] {
        guard let parent=component.surface, let frame=parent.localFrame, !children.isEmpty,
              component.plans.allSatisfy({$0.geometryRevision == component.geometryRevision}) else { throw SurveyWorkError.staleSource }
        func converted(_ point:LayoutPoint, from source:Surface2D) throws -> LayoutPoint {
            guard let sourceFrame=source.localFrame else { throw SurveyWorkError.staleSource }
            let world=LayoutVector3(
                x:sourceFrame.origin.x+(sourceFrame.axisX.x*point.x+sourceFrame.axisY.x*point.y)/1000,
                y:sourceFrame.origin.y+(sourceFrame.axisX.y*point.x+sourceFrame.axisY.y*point.y)/1000,
                z:sourceFrame.origin.z+(sourceFrame.axisX.z*point.x+sourceFrame.axisY.z*point.y)/1000)
            let delta=world-frame.origin
            let x=delta.dot(frame.axisX), y=delta.dot(frame.axisY)
            let residual=LayoutVector3(x:delta.x-x*frame.axisX.x-y*frame.axisY.x,
                y:delta.y-x*frame.axisX.y-y*frame.axisY.y,z:delta.z-x*frame.axisX.z-y*frame.axisY.z)
            guard residual.length < 0.001 else { throw SurveyWorkError.changedDimensions }
            return .init(x:x*1000,y:y*1000)
        }
        let previous=try old.surface.contour.map { try converted($0,from:old.surface) }
        func sameBoundary(_ a:[LayoutPoint],_ b:[LayoutPoint])->Bool {
            abs(abs(LayoutGeometry.area(a))-abs(LayoutGeometry.area(b)))<1 &&
            a.allSatisfy { p in LayoutGeometry.edges(b).contains { LayoutGeometry.distance(p,to:$0.a,$0.b)<0.01 } } &&
            b.allSatisfy { p in LayoutGeometry.edges(a).contains { LayoutGeometry.distance(p,to:$0.a,$0.b)<0.01 } }
        }
        guard sameBoundary(previous,parent.contour) else { throw SurveyWorkError.changedDimensions }
        let surfaces=try children.map { child -> Surface2D in
            var surface=child.surface
            surface.localFrame=frame
            surface.contour=try child.surface.contour.map { try converted($0,from:child.surface) }
            // Keep openings in the same frame; the engine clips them to each child.
            surface.openings=parent.openings
            surface.edgeIDs=surface.contour.indices.map { _ in UUID().uuidString }
            surface.layingOffset = .init()
            for (i,edge) in LayoutGeometry.edges(surface.contour).enumerated() {
                if let oldIndex=LayoutGeometry.edges(parent.contour).firstIndex(where:{
                    LayoutGeometry.distance(edge.a,to:$0.a,$0.b)<0.01 && LayoutGeometry.distance(edge.b,to:$0.a,$0.b)<0.01
                }) {
                    surface.layingOffset.individualMM[surface.edgeIDs[i]]=parent.layingDistance(at:oldIndex)
                }
            }
            return surface
        }
        let beforeArea=try parent.netMeasuredArea()
        let afterArea=try surfaces.reduce(0.0) { try $0+$1.netMeasuredArea() }
        guard abs(beforeArea-afterArea)<max(1,beforeArea*0.000001) else { throw SurveyWorkError.changedDimensions }
        func frozen(_ original:LayoutLayer)->LayoutLayer {
            var layer=original
            layer.inheritedGridFrame=LayoutGridFrame.make(surface:parent,layer:original)
            layer.referenceEdge=nil
            if var f=original.furring {
                var framingLayer=original
                if f.usesOwnReference == true {
                    framingLayer.referenceEdge=f.referenceEdge
                    framingLayer.inheritedGridFrame=f.inheritedGridFrame
                }
                f.inheritedGridFrame=LayoutGridFrame.make(surface:parent,layer:framingLayer)
                f.referenceEdge=nil; f.usesOwnReference=true
                f.peripheralReferenceContour=f.peripheralReferenceContour ?? parent.contour
                layer.furring=f
            }
            return layer
        }
        return zip(children,surfaces).enumerated().map { index,pair in
            let (child,surface)=pair
            var result=component
            if index>0 { result.id=UUID() }
            result.name=child.surface.name; result.surface=surface; result.surveySource=child.source
            result.geometryRevision += 1
            result.plans=component.plans.map { plan in
                var next=plan
                if index>0 { next.id=UUID() }
                var layers=component.document(for:plan)?.layers ?? plan.layers
                layers=layers.map(frozen)
                next.layers=layers; next.geometryRevision=result.geometryRevision
                if var lights=plan.lighting {
                    let selected=lights.positions.indices.filter { spot in
                        // First containing child owns a point on the shared boundary.
                        surfaces.firstIndex(where:{ s in
                            LayoutGeometry.contains(lights.positions[spot],in:s.contour) ||
                            LayoutGeometry.edges(s.contour).contains { LayoutGeometry.distance(lights.positions[spot],to:$0.a,$0.b)<0.01 }
                        }) == index
                    }
                    lights.kinds=selected.map { lights.kind(at:$0) }
                    lights.positions=selected.map { lights.positions[$0] }; lights.count=lights.positions.count
                    next.lighting=lights.positions.isEmpty ? nil : lights
                }
                return next
            }
            result.framing=result.plans.first?.layers.first?.furring
            return result
        }
    }

    static func availableWorkTypes(for surfaces:[SurveyWorkSurface]) -> [WorkType] {
        guard !surfaces.isEmpty else { return [] }
        if surfaces.allSatisfy({$0.source.kind == .ceiling}) { return [.ceilingOnFurring,.ceilingOnRailsAndStuds,.modularCeiling,.frenchCeiling,.paintingBeta] }
        if surfaces.allSatisfy(isDesignedPartition) { return [.distributionPartition,.paintingBeta] }
        if surfaces.contains(where:isDesignedPartition) { return [.paintingBeta] }
        return [.peripheralLiningStuds,.peripheralLiningFurrings,.paintingBeta]
    }
    static func railStudCeiling(_ surfaces:[SurveyWorkSurface]) -> RailStudCeilingConfiguration {
        let base=ceiling(surfaces)
        var result=RailStudCeilingConfiguration()
        result.area=totalArea(surfaces); result.dimensionsSpecified=false
        result.length=base.length; result.width=base.width
        result.shape=base.ceilingShape == "rampant" ? "sloped" : "horizontal"
        return result
    }
    static func modularCeiling(_ surfaces: [SurveyWorkSurface]) -> ModularCeilingConfiguration {
        var result = ModularCeilingConfiguration()
        result.surveyedSurfaces = surfaces.map(\.surface)
        let bounds = surfaces.map { ModularCeilingCalculator.aligned($0.surface).bounds }
        result.length = (bounds.map(\.width).max() ?? 0) / 1000
        result.width = (bounds.map(\.height).max() ?? 0) / 1000
        return result
    }
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
                let contour = PlaquistoWallGeometry.outline(wall:wall,room:room).map { LayoutPoint(x:$0.x*1000,y:$0.y*1000) }
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
                    return LayoutOpening(id: opening.id, kind: opening.layoutKind ?? kind, contour: [
                        .init(x: x, y: y), .init(x: x + width, y: y),
                        .init(x: x + width, y: y + height), .init(x: x, y: y + height)],
                        doorHanding:opening.doorHanding,doorOpeningSide:opening.doorOpeningSide)
                }
                let surface = Surface2D(id: projectedID(source(wall.id, .wall)), name: "\(roomName) · \(name)", kind: .wall, contour: contour,
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
                    let holeIndices = slope.boundaries.indices.filter {
                        depths[$0] == depths[boundaryIndex] + 1 && LayoutGeometry.contains(horizontalLoops[$0][0], in: horizontalLoops[boundaryIndex])
                    }
                    let holes = holeIndices.map { i in
                        slope.boundaries[i].map { RoomPoint(x: $0.x, y: slope.plane.height(x: $0.x, z: $0.z), z: $0.z) }
                    }
                    guard let origin = vertices.first else { continue }
                    let parent=room.ceilings.first { $0.slopeIDs.contains(slope.id) }
                    let number=parent.flatMap { numbers[$0.id.uuidString] } ?? (index+1)
                    let panIndex=parent?.slopeIDs.firstIndex(of:slope.id) ?? 0
                    let name = "Plafond "+CeilingPlanNaming.letters(number)
                        + ((parent?.slopeIDs.count ?? 1)>1 ? " · pan \(panIndex+1)" : "")
                        + (slope.boundaries.count > 1 ? " · partie \(boundaryIndex + 1)" : "")
                    guard var surface = try? Surface2DAdapter.projected(name: "\(roomName) · \(name)", kind: .ceiling,
                        contour: vertices.map(vector), openings: holes.map { $0.map(vector) }, frame: .init(origin: vector(origin), axisX: vector(axisX), axisY: vector(axisY)),
                        sourceID: slope.id.uuidString), let net = try? surface.netMeasuredArea(), net > 0 else { continue }
                    let identity = source(slope.id, .ceiling, boundaryIndex)
                    surface.id = projectedID(identity)
                    for i in surface.openings.indices {
                        surface.openings[i].id = projectedID(identity, hole: holeIndices[i])
                    }
                    // A full-height column occupies the ceiling too. Intersect its
                    // vertical footprint with the actual plane (not the screen axes),
                    // then let the layout boolean clip it at edges and existing holes.
                    if let frame = surface.localFrame {
                        for column in (room.columns ?? []).filter(\.isValid) {
                            let contour = column.corners.map { corner -> LayoutPoint in
                                let top = vector(.init(x: corner.x,
                                    y: slope.plane.height(x: corner.x, z: corner.z), z: corner.z))
                                let delta = top - frame.origin
                                return .init(x: delta.dot(frame.axisX) * 1000,
                                             y: delta.dot(frame.axisY) * 1000)
                            }
                            let opening = LayoutOpening(id: column.id, kind: .other, contour: contour)
                            var probe = surface
                            probe.openings = [opening]
                            if let remaining = try? probe.netMeasuredArea(),
                               abs(LayoutGeometry.area(surface.contour)) - remaining > 0.01 {
                                surface.openings.append(opening)
                            }
                        }
                    }
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
            height: $0.surface.bounds.height / 1000, netArea: $0.netArea,
            openingCount:$0.surface.openings.count,openingArea:max(0,$0.grossArea-$0.netArea)) }
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
    static func workForRecalculation(_ work: WorkItem, includingEmptySurveyWork: Bool = false) -> WorkItem {
        guard work.layoutNeedsRecalculation == true,
              (includingEmptySurveyWork || work.components.contains(where: { $0.surveySource != nil })),
              work.components.allSatisfy({ $0.surface != nil }) else { return work }
        let surfaces = work.components.compactMap(\.surface)
        let areas = surfaces.compactMap { try? $0.netMeasuredArea() / 1_000_000 }
        guard areas.count == surfaces.count, areas.allSatisfy({ $0.isFinite && $0 > 0 }) else { return work }
        let total = areas.reduce(0, +)
        let isSloped = surfaces.contains {
            guard let frame = $0.localFrame else { return false }
            return abs(frame.axisX.y) > 0.001 || abs(frame.axisY.y) > 0.001
        }
        let runs = zip(surfaces, areas).map { surface, area in
            MeasuredWallRun(length: surface.bounds.width / 1000, height: surface.bounds.height / 1000, netArea: area,
                openingCount:surface.openings.count,openingArea:max(0,abs(LayoutGeometry.area(surface.contour))/1_000_000-area))
        }
        var result = work
        switch work.payload {
        case .modularCeiling(var value):
            value.surveyedSurfaces = surfaces
            let bounds = surfaces.map { ModularCeilingCalculator.aligned($0).bounds }
            value.length = (bounds.map(\.width).max() ?? 0) / 1000
            value.width = (bounds.map(\.height).max() ?? 0) / 1000
            result.payload = .modularCeiling(value)
        case .ceiling(var value):
            let previous = value.enteredArea ?? value.length * value.width
            let ratio = previous > 0 ? total / previous : 1
            value.enteredArea = total; value.dimensionsSpecified = false
            value.ceilingShape = isSloped ? "rampant" : "horizontal"
            value.length = sqrt(total); value.width = value.length
            value.firstSkin = value.firstSkin.map { var copy = $0; copy.area *= ratio; return copy }
            value.secondSkin = value.secondSkin.map { var copy = $0; copy.area *= ratio; return copy }
            result.payload = .ceiling(value)
        case .railStudCeiling(var value):
            let ratio=value.effectiveArea>0 ? total/value.effectiveArea : 1
            value.area=total; value.dimensionsSpecified=false
            value.shape = isSloped ? "sloped" : "horizontal"
            value.length=sqrt(total); value.width=value.length
            value.firstSkin=value.firstSkin.map { var copy=$0; copy.area *= ratio; return copy }
            value.secondSkin=value.secondSkin.map { var copy=$0; copy.area *= ratio; return copy }
            result.payload = .railStudCeiling(value)
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
        case .paintingBeta(var value):
            value.area = total
            result.payload = .paintingBeta(value)
        case .distributionPartition(var value):
            let ratio = value.area > 0 ? total / value.area : 1
            value.geometryMode = "surface"; value.enteredSurface = total
            value.enteredLength = runs.reduce(0) { $0 + $1.length }
            value.height = runs.map(\.height).max() ?? 0
            value.faceAFirst = value.faceAFirst.map { var copy = $0; copy.surface *= ratio; return copy }
            value.faceASecond = value.faceASecond.map { var copy = $0; copy.surface *= ratio; return copy }
            value.faceBFirst = value.faceBFirst.map { var copy = $0; copy.surface *= ratio; return copy }
            value.faceBSecond = value.faceBSecond.map { var copy = $0; copy.surface *= ratio; return copy }
            result.payload = .distributionPartition(value)
        default: break
        }
        return result
    }

    /// Stored form estimates keep their published coefficients and selected
    /// products. Rescale surface supplies by net area, peripheral rails by length,
    /// and vertical framing/supports by the actual runs rather than by area alone.
    /// Ceiling-on-furring and painting estimates are calculated live elsewhere.
    static func updatingStoredQuantities(_ updated: WorkItem, from old: WorkItem) -> WorkItem {
        var result = updated
        func ratio(_ next: Double, _ previous: Double) -> Double {
            previous > 0 ? max(0, next) / previous : (next == 0 ? 0 : 1)
        }
        let areaRatio = ratio(updated.area, old.area)
        func quantity(_ value: Double, factor: Double, unit: String) -> Double {
            // Round only for display/purchase, not every successive geometry edit.
            value * factor
        }
        func runs(_ work: WorkItem) -> [MeasuredWallRun] {
            work.components.compactMap(\.surface).map {
                .init(length: $0.bounds.width / 1000, height: $0.bounds.height / 1000,
                      netArea: ((try? $0.netMeasuredArea()) ?? 0) / 1_000_000)
            }
        }
        let before = runs(old), after = runs(updated)
        let lengthRatio = ratio(after.reduce(0) { $0 + $1.length }, before.reduce(0) { $0 + $1.length })
        switch updated.payload {
        case .peripheralLining(var value):
            func studs(_ values: [MeasuredWallRun]) -> Double {
                values.reduce(0) { $0 + Double(DoublageStudCalculator.studs(length: $1.length,
                    spacing: value.spacing, wallCount: 1, doubled: value.doubledStuds)) * $1.height }
            }
            let studRatio = ratio(studs(after), studs(before))
            value.quantities = value.quantities.map { row in
                var copy = row
                let name = SupplyListingConsolidator.canonicalName(row.name)
                let factor = name.hasPrefix("Rails") ? lengthRatio
                    : name.hasPrefix("Montants") || name == "Scotch double-face" ? studRatio : areaRatio
                copy.quantity = quantity(row.quantity, factor: factor, unit: row.unit)
                return copy
            }
            result.payload = .peripheralLining(value)
        case .furringLining(var value):
            let spacing = value.furringSpacing ?? 0.6
            func framing(_ values: [MeasuredWallRun]) -> (axes: Double, vertical: Double, total: Double) {
                let axes = values.reduce(0.0) { $0 + Double(FurringLiningCalculator.furringAxes(length: $1.length, spacing: spacing, wallCount: 1)) }
                let vertical = values.reduce(0.0) { $0 + Double(FurringLiningCalculator.furringAxes(length: $1.length, spacing: spacing, wallCount: 1)) * $1.height }
                let horizontal = value.includesHorizontalSupportFurring != false
                    ? values.reduce(0.0) { $0 + $1.length } * Double(value.selectedSupportLines) : 0
                return (axes, vertical, vertical + horizontal)
            }
            let a = framing(before), b = framing(after)
            value.quantities = value.quantities.map { row in
                var copy = row
                let name = SupplyListingConsolidator.canonicalName(row.name)
                let factor: Double
                if name.hasPrefix("Fourrures") { factor = ratio(b.total, a.total) }
                else if name.hasPrefix("Rails") { factor = lengthRatio }
                else if name.hasPrefix("Appuis intermédiaires pour fourrures") { factor = ratio(b.axes, a.axes) }
                else if name == "Scotch double-face" { factor = ratio(b.vertical, a.vertical) }
                else { factor = areaRatio }
                copy.quantity = quantity(row.quantity, factor: factor, unit: row.unit)
                return copy
            }
            result.payload = .furringLining(value)
        case .railStudCeiling(var value):
            let previous = old.railStudCeilingConfiguration
            let perimeterRatio = ratio(value.length + value.width, (previous?.length ?? 0) + (previous?.width ?? 0))
            value.quantities = value.quantities.map { row in
                var copy = row
                let factor = SupplyListingConsolidator.canonicalName(row.name).hasPrefix("Rails R") ? perimeterRatio : areaRatio
                copy.quantity = quantity(row.quantity, factor: factor, unit: row.unit)
                return copy
            }
            result.payload = .railStudCeiling(value)
        case .distributionPartition(var value):
            value.quantities = value.quantities.map { row in
                var copy = row
                let factor = SupplyListingConsolidator.canonicalName(row.name).hasPrefix("Rails") ? lengthRatio : areaRatio
                copy.quantity = quantity(row.quantity, factor: factor, unit: row.unit)
                return copy
            }
            result.payload = .distributionPartition(value)
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
