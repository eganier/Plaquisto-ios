import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct PlaquistoRoomFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var document: PlaquistoRoomDocument
    init(_ document: PlaquistoRoomDocument) { self.document = document }
    init(configuration: ReadConfiguration) throws {
        document = try .decode(configuration.file.regularFileContents ?? Data())
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try document.encoded())
    }
}

// This screen can be hosted without the scanner or an ARSession.
struct PlaquistoSavedRoomView: View {
    var storageURL: URL = PlaquistoRoomStore.defaultURL
    @State private var document: PlaquistoRoomDocument?
    @State private var errorMessage: String?
    @State private var importing = false
    @State private var revision = UUID()
    @State private var hasLoaded = false
    var body: some View {
        Group {
            if let document {
                PlaquistoRoomEditor(document:document) { edited in
                    try PlaquistoRoomStore.save(edited,to:storageURL)
                    self.document = edited
                }.id(revision)
            } else {
                VStack(spacing:20) {
                    ContentUnavailableView("Pièce sauvegardée",systemImage:"cube",
                        description:Text(errorMessage ?? "Aucune pièce enregistrée. Faites un scan ou importez un fichier Plaquisto."))
                    Button("Importer un fichier Plaquisto") { importing = true }.buttonStyle(.bordered)
                }.navigationTitle("Pièce sauvegardée")
            }
        }
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button("Recharger",systemImage:"arrow.clockwise") { reload() }
            }
        }
        .onAppear {
            if !hasLoaded { hasLoaded = true; reload() }
        }
        .alert("Chargement impossible",isPresented:Binding(get:{ errorMessage != nil && document != nil },set:{ if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let imported = try PlaquistoRoomDocument.decode(Data(contentsOf:url))
                try PlaquistoRoomStore.save(imported,to:storageURL)
                reload()
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func reload() {
        do {
            document = try PlaquistoRoomStore.load(from:storageURL)
            revision = UUID(); errorMessage = nil
        } catch {
            if !FileManager.default.fileExists(atPath:storageURL.path), document == nil { errorMessage = nil }
            else { errorMessage = error.localizedDescription }
        }
    }
}

struct PlaquistoRoomEditor: View {
    @State var document: PlaquistoRoomDocument
    var onSave: (PlaquistoRoomDocument) throws -> Void
    @State private var selected: UUID?
    @State private var lengthText = ""
    @State private var heightText = ""
    @State private var message: String?
    @State private var exporting = false
    @State private var importing = false
    private var wall: PlaquistoWall? { document.room.walls.first { $0.id == selected } }
    private var ceiling: PlaquistoCeiling? { document.room.ceilings.first { $0.id == selected } }
    @State private var ceilingMode = 1
    @State private var showFloor = true
    @State private var topView = false
    @State private var cameraReset = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Label("Modèle Plaquisto sauvegardé · aucune capture nécessaire",systemImage:"internaldrive").font(.caption)
                Text(document.room.name ?? "Pièce").font(.headline)
                RoomDomainScene(room:document.room,selected:$selected,ceilingMode:ceilingMode,showFloor:showFloor,topView:topView,cameraReset:cameraReset)
                    .frame(height:360).clipShape(RoundedRectangle(cornerRadius:16))
                    .accessibilityLabel("Pièce en 3D : touchez un mur ou le plafond pour le sélectionner")
                HStack {
                    Picker("Vue",selection:$topView) {
                        Text("Perspective").tag(false)
                        Text("Dessus").tag(true)
                    }.pickerStyle(.segmented)
                    Button("Recentrer",systemImage:"arrow.counterclockwise") { cameraReset = UUID() }.labelStyle(.iconOnly)
                }
                Text("Plafond").font(.caption).foregroundStyle(.secondary)
                Picker("Plafond",selection:$ceilingMode) {
                    Text("Masqué").tag(0)
                    Text("Transparent").tag(1)
                    Text("Plein").tag(2)
                }.pickerStyle(.segmented)
                Toggle("Afficher le sol",isOn:$showFloor)
                Text("Maquette géométrique · épaisseur de présentation si non mesurée · sans textures ni meubles.").font(.caption).foregroundStyle(.secondary)
                Text("\(document.room.openings.count) ouverture(s) enregistrée(s) · \(document.room.slopes.filter(\.accepted).count) pan(s) de plafond accepté(s)").font(.caption)
                if !document.room.slopes.contains(where: \.accepted) {
                    Text("Aucun plafond validé dans cette sauvegarde.").font(.caption).foregroundStyle(.orange)
                }
                Text("Touchez un mur ou le plafond. Masquez le plafond pour sélectionner un mur situé derrière. Rotation à un doigt, zoom à deux doigts.").font(.caption).foregroundStyle(.secondary)
                Picker("Élément",selection:$selected) {
                    Text("Sélectionner un élément").tag(UUID?.none)
                    ForEach(Array(document.room.ceilings.enumerated()),id:\.element.id) { i,c in
                        Text("Plafond \(i+1)").tag(Optional(c.id))
                    }
                    ForEach(Array(document.room.walls.enumerated()),id:\.element.id) { i,w in
                        Text("Mur \(i+1)").tag(Optional(w.id))
                    }
                }
                if let ceiling { ceilingDetails(ceiling) }
                if let wall {
                    let geometry = PlaquistoWallGeometry.analyze(wall:wall,room:document.room)
                    Text("Identifiant Plaquisto").font(.caption).foregroundStyle(.secondary)
                    Text(wall.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    LabeledContent("Longueur effective",value:meters(wall.length.effectiveValue))
                    let heights = geometry.strips.flatMap { [$0.h0,$0.h1] }
                    LabeledContent("Hauteur du profil",value:"\(meters(heights.min() ?? 0)) à \(meters(heights.max() ?? 0))")
                    Text("Origine du profil : " + Set(geometry.strips.map { $0.heightSource.title }).sorted().joined(separator:", ")).font(.caption)
                    Text(geometry.strips.allSatisfy(\.manuallyValidated) ? "Profil issu de mesures validées manuellement." : "Profil comportant des mesures non validées manuellement.").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Surface brute",value:area(geometry.gross))
                    LabeledContent("Ouvertures déduites",value:area(geometry.openingArea))
                    LabeledContent("Surface nette géométrique",value:area(geometry.net))
                    Text("Les ouvertures rattachées sont déduites sans double comptage, dans les limites du mur. Cette surface n’applique pas de règle de fournitures.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Longueur : corriger ou valider").font(.headline)
                    TextField("Longueur en mètres",text:$lengthText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Button("Valider la longueur") { commit(height:false) }.buttonStyle(.borderedProminent)
                    measurementDetails(wall.length)
                    Text("Hauteur uniforme : corriger ou valider").font(.headline)
                    TextField("Hauteur en mètres",text:$heightText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Text("Une hauteur manuelle remplace le profil sous rampant de ce mur. La longueur se corrige depuis le point de départ ; les murs voisins ne sont pas déplacés.").font(.caption).foregroundStyle(.secondary)
                    Button("Valider la hauteur uniforme") { commit(height:true) }.buttonStyle(.bordered)
                    measurementDetails(wall.height)
                    if wall.height.manualValue != nil {
                        Button("Reprendre le profil issu du plafond") {
                            guard let i = document.room.walls.firstIndex(where: { $0.id == selected }) else { return }
                            var edited = document
                            edited.room.walls[i].height.manualValue = nil
                            edited.room.walls[i].height.manuallyValidated = false
                            do { try onSave(edited); document = edited; fillFields() }
                            catch { message = error.localizedDescription }
                        }
                    }
                    Divider()
                    Text("Portes, fenêtres et ouvertures").font(.headline)
                    let openings = document.room.openings.filter { $0.wallID == wall.id }
                    if openings.isEmpty { Text("Aucune ouverture rattachée à ce mur.").foregroundStyle(.secondary) }
                    ForEach(openings) { o in
                        VStack(alignment:.leading) {
                            Text(o.kind.title)
                            Text("\(meters(o.width.effectiveValue)) × \(meters(o.height.effectiveValue)) · allège \(meters(o.sillHeight.effectiveValue))").font(.caption)
                            Text("Largeur : \(o.width.effectiveSource.title) · hauteur : \(o.height.effectiveSource.title) · \(o.width.manuallyValidated && o.height.manuallyValidated ? "dimensions validées" : "dimensions à vérifier")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Géométrie uniquement : aucun doublage, cloison ou ouvrage créé. Le choix métier viendra après validation.").font(.caption).foregroundStyle(.secondary)
                }
                let unattached = document.room.openings.filter { $0.wallID == nil }.count
                if unattached > 0 { Text("\(unattached) ouverture(s) non rattachée(s), exclue(s) des surfaces nettes.").foregroundStyle(.orange) }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Exporter la pièce") { exporting = true }
                    Button("Importer une pièce") { importing = true }
                }.buttonStyle(.bordered)
                Text("Modèle initial et corrections enregistrés sur cet appareil. Importer remplace la pièce de travail du prototype.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle("Pièce et dimensions")
        .onAppear {
            if selected == nil { selected = document.room.walls.first?.id; fillFields() }
        }
        .onChange(of:selected) { _,_ in
            fillFields()
            if ceiling != nil && ceilingMode == 0 { ceilingMode = 1 }
        }
        .fileExporter(isPresented:$exporting,document:PlaquistoRoomFile(document),contentType:.json,defaultFilename:"plaquisto_room") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let imported = try PlaquistoRoomDocument.decode(Data(contentsOf:url))
                try onSave(imported); document = imported; selected = nil; message = "Pièce importée."
            } catch { message = error.localizedDescription }
        }
    }
    private func fillFields() { lengthText = wall.map { String($0.length.effectiveValue) } ?? ""; heightText = wall.map { String($0.height.effectiveValue) } ?? "" }
    @ViewBuilder private func ceilingDetails(_ ceiling:PlaquistoCeiling) -> some View {
        let pans = document.room.slopes.filter { ceiling.slopeIDs.contains($0.id) }
        let accepted = pans.filter(\.accepted)
        VStack(alignment:.leading,spacing:12) {
            Text("Plafond sélectionné").font(.headline)
            Text(ceiling.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
            LabeledContent("Surface reconstituée",value:area(accepted.reduce(0) { $0 + PlaquistoSurfaceGeometry.area(of:$1) }))
            LabeledContent("Pans acceptés",value:"\(accepted.count) / \(pans.count)")
            LabeledContent("Origine",value:ceiling.provenance.source.title)
            Text(!pans.isEmpty && pans.allSatisfy(\.manuallyValidated) ? "Plafond validé manuellement." : "Validation manuelle partielle ou absente.").font(.caption)
            ForEach(Array(pans.enumerated()),id:\.element.id) { i,pan in
                LabeledContent("Pan \(i+1)",value:"\(area(PlaquistoSurfaceGeometry.area(of:pan))) · \(pan.plane.slopeDegrees.formatted(.number.precision(.fractionLength(1))))°")
                Text("\(pan.provenance.source.title) · \(pan.accepted ? "accepté" : "non accepté")").font(.caption).foregroundStyle(.secondary)
            }
            Text("Surface suivant les pentes, et non projection au sol. Les ouvertures de toit et trémies ne sont pas déduites.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func measurementDetails(_ measurement:RoomMeasurement) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text("Valeur brute : \(meters(measurement.rawValue)) · \(measurement.provenance.source.title)")
            Text("Valeur effective : \(meters(measurement.effectiveValue)) · \(measurement.effectiveSource.title)")
            Text(measurement.manuallyValidated ? "Validée manuellement — prioritaire sur le scan." : "Non validée manuellement.")
            if let confidence = measurement.provenance.confidenceLabel { Text("Confiance de la source : \(confidence)") }
        }.font(.caption).foregroundStyle(.secondary)
    }
    private func meters(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(2)))+" m" }
    private func area(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(2)))+" m²" }
    private func commit(height: Bool) {
        guard let i = document.room.walls.firstIndex(where: { $0.id == selected }),
              let value = Double((height ? heightText : lengthText).replacingOccurrences(of:",",with:".").trimmingCharacters(in:.whitespaces)) else { message = "Saisis une dimension en mètres."; return }
        do {
            var edited = document
            if height { try edited.room.walls[i].height.correct(value) }
            else { try edited.room.walls[i].length.correct(value) }
            try edited.validate(); try onSave(edited); document = edited; message = "Dimension validée. Elle reste prioritaire sur le scan."
        } catch { message = error.localizedDescription }
    }
}

private struct RoomDomainScene: UIViewRepresentable {
    let room: PlaquistoRoomModel
    @Binding var selected: UUID?
    let ceilingMode: Int
    let showFloor: Bool
    let topView: Bool
    let cameraReset: UUID
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> SCNView {
        let view=SCNView(); view.scene=SCNScene()
        view.backgroundColor=UIColor(red:0.96,green:0.95,blue:0.92,alpha:1)
        view.allowsCameraControl=true; view.antialiasingMode = .multisampling4X
        view.addGestureRecognizer(UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view:SCNView,context:Context) {
        let coordinator=context.coordinator
        let previous=coordinator.parent
        let reset=view.pointOfView == nil || coordinator.roomID != room.id || previous.topView != topView || previous.cameraReset != cameraReset
        let refresh=reset || coordinator.lastRoom != room || coordinator.lastSelected != selected || previous.ceilingMode != ceilingMode || previous.showFloor != showFloor
        coordinator.parent=self
        guard refresh else { return }
        coordinator.lastRoom=room; coordinator.lastSelected=selected
        let root=view.scene!.rootNode
        root.childNodes.filter { $0.camera == nil }.forEach { $0.removeFromParentNode() }
        func vector(_ p:RoomPoint) -> SCNVector3 { .init(Float(p.x),Float(p.y),Float(p.z)) }
        func node(_ points:[RoomPoint],color:UIColor,name:String?=nil) -> SCNNode {
            var normals:[SCNVector3]=[]
            for i in stride(from:0,to:points.count,by:3) {
                let u=points[i+1]-points[i],v=points[i+2]-points[i]
                let n=RoomPoint(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
                normals += Array(repeating:vector(n*(1/max(n.length,1e-12))),count:3)
            }
            let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:points.map(vector)),SCNGeometrySource(normals:normals)],
                elements:[SCNGeometryElement(indices:Array(0..<Int32(points.count)),primitiveType:.triangles)])
            let material=SCNMaterial(); material.diffuse.contents=color; material.isDoubleSided=true
            material.lightingModel = .physicallyBased; material.roughness.contents=0.85
            geometry.materials=[material]
            let node=SCNNode(geometry:geometry); node.name=name; node.castsShadow=true
            node.categoryBitMask=name == nil ? 2 : 1
            return node
        }
        let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity=650; root.addChildNode(ambient)
        let sun=SCNNode(); sun.light=SCNLight(); sun.light?.type = .directional
        sun.light?.intensity=1000; sun.eulerAngles=SCNVector3(-Float.pi/3,-Float.pi/4,0)
        root.addChildNode(sun)
        for wall in room.walls {
            root.addChildNode(node(PlaquistoWallGeometry.displayTriangles(wall:wall,room:room),
                color:wall.id == selected ? UIColor(red:0.42,green:0.72,blue:0.61,alpha:1) : UIColor(white:0.94,alpha:1),
                name:wall.id.uuidString))
        }
        if showFloor {
            for floor in room.floors {
                let points=floor.boundaries.flatMap { PlaquistoSurfaceGeometry.triangles($0) }.map { $0+RoomPoint(x:0,y:-0.008,z:0) }
                root.addChildNode(node(points,color:UIColor(red:0.69,green:0.64,blue:0.53,alpha:1)))
            }
        }
        if ceilingMode != 0 {
            for pan in room.slopes where pan.accepted {
                let points=pan.boundaries.flatMap { loop in
                    PlaquistoSurfaceGeometry.triangles(loop.map { RoomPoint(x:$0.x,y:pan.plane.height(x:$0.x,z:$0.z),z:$0.z) })
                }
                let ceilingID=room.ceilings.first { $0.slopeIDs.contains(pan.id) }?.id
                let highlighted=ceilingID != nil && ceilingID == selected
                let roof=node(points,color:highlighted ? UIColor(red:0.42,green:0.72,blue:0.61,alpha:1) : UIColor(red:0.68,green:0.74,blue:0.83,alpha:1),name:ceilingID?.uuidString)
                roof.opacity=ceilingMode == 1 ? (highlighted ? 0.6 : 0.25) : 1
                roof.geometry?.firstMaterial?.writesToDepthBuffer=ceilingMode != 1
                roof.renderingOrder=ceilingMode == 1 ? 20 : 0
                root.addChildNode(roof)
            }
        }
        if reset {
            root.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }
            let points=room.walls.flatMap { PlaquistoWallGeometry.triangles(wall:$0,room:room) }
            let minP=RoomPoint(x:points.map(\.x).min() ?? 0,y:points.map(\.y).min() ?? 0,z:points.map(\.z).min() ?? 0)
            let maxP=RoomPoint(x:points.map(\.x).max() ?? 1,y:points.map(\.y).max() ?? 1,z:points.map(\.z).max() ?? 1)
            let center=(minP+maxP)*0.5, radius=max(1.5,(maxP-minP).length/2)
            let camera=SCNNode(); camera.camera=SCNCamera(); camera.camera?.zFar=10000; camera.camera?.zNear=0.01
            camera.camera?.fieldOfView=45
            camera.camera?.usesOrthographicProjection=topView; camera.camera?.orthographicScale=radius*1.25
            camera.position=vector(center+(topView ? RoomPoint(x:0,y:radius*3,z:0.001) : RoomPoint(x:radius*1.65,y:radius*1.35,z:radius*1.65)))
            camera.look(at:vector(center)); root.addChildNode(camera); view.pointOfView=camera
            view.defaultCameraController.target=vector(center); coordinator.roomID=room.id
        }
    }
    final class Coordinator: NSObject {
        var parent:RoomDomainScene
        var lastRoom:PlaquistoRoomModel?; var lastSelected:UUID?; var roomID:UUID?
        init(_ parent:RoomDomainScene) { self.parent=parent }
        @objc func tap(_ gesture:UITapGestureRecognizer) {
            guard let view=gesture.view as? SCNView else { return }
            if let id=view.hitTest(gesture.location(in:view),options:[.categoryBitMask:1]).compactMap({ $0.node.name.flatMap(UUID.init(uuidString:)) }).first {
                parent.selected=id
            }
        }
    }
}
