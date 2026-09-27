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
    var projectSaveDestination: ((PlaquistoRoomDocument) -> AnyView)? = nil
    @State private var document: PlaquistoRoomDocument?
    @State private var errorMessage: String?
    @State private var importing = false
    @State private var revision = UUID()
    @State private var hasLoaded = false
    var body: some View {
        Group {
            if let document {
                PlaquistoRoomEditor(document:document, projectSaveDestination: projectSaveDestination) { edited in
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
    var allowsImport = true
    var ceilingNumbers: [String:Int] = [:]
    var projectSaveDestination: ((PlaquistoRoomDocument) -> AnyView)? = nil
    var onSave: (PlaquistoRoomDocument) throws -> Void
    @State private var selected: UUID?
    @State private var lengthText = ""
    @State private var heightText = ""
    @State private var message: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var estimateProposal: WallCeilingEstimate.Proposal?
    @State private var editingPlan = false
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
                Text("Habillage indicatif · épaisseur de présentation si non mesurée · sans mobilier.").font(.caption).foregroundStyle(.secondary)
                Text("\(document.room.openings.count) ouverture(s) enregistrée(s) · \(document.room.slopes.count) pan(s) de plafond").font(.caption)
                if !document.room.slopes.isEmpty {
                    Label(document.room.slopes.contains(where: { $0.provenance.source == .estimated })
                          ? "Plafond estimé à partir des murs" : "Plafond reconnu", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if document.room.slopes.isEmpty || document.room.ceilings.contains(where: { $0.provenance.source == .estimated }) {
                    Menu {
                        ForEach(Array(((try? WallCeilingEstimate.manualProposals(in: document.room)) ?? []).enumerated()), id: \.element.id) { index, value in
                            Button(value.ceilingID.flatMap { id in document.room.ceilings.first { $0.id==id } }.map {
                                CeilingPlanNaming.title($0,in:document.room,numbers:ceilingNumbers)
                            } ?? "Ajouter · zone \(index+1)") { estimateProposal = value }
                        }
                    } label: {
                        Label("Modifier la forme et les hauteurs du plafond", systemImage: "slider.horizontal.3")
                    }.buttonStyle(.bordered)
                }
                Text("Touchez un mur ou le plafond. Masquez le plafond pour sélectionner un mur situé derrière. Rotation à un doigt, zoom à deux doigts.").font(.caption).foregroundStyle(.secondary)
                Picker("Élément",selection:$selected) {
                    Text("Sélectionner un élément").tag(UUID?.none)
                    ForEach(Array(document.room.ceilings.enumerated()),id:\.element.id) { i,c in
                        Text(CeilingPlanNaming.title(c,in:document.room,numbers:ceilingNumbers)).tag(Optional(c.id))
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
                    PlaquistoNumericField(placeholder: "Longueur en mètres", text: $lengthText).textFieldStyle(.roundedBorder)
                    Button("Valider la longueur") { commit(height:false) }.buttonStyle(.borderedProminent)
                    measurementDetails(wall.length)
                    Text("Hauteur maximale : corriger ou valider").font(.headline)
                    PlaquistoNumericField(placeholder: "Hauteur en mètres", text: $heightText).textFieldStyle(.roundedBorder)
                    Text("La hauteur redimensionne proportionnellement le profil mesuré, sans aplatir le rampant. La longueur se corrige depuis le point de départ ; les murs voisins ne sont pas déplacés.").font(.caption).foregroundStyle(.secondary)
                    Button("Valider la hauteur maximale") { commit(height:true) }.buttonStyle(.bordered)
                    measurementDetails(wall.height)
                    if wall.height.manualValue != nil {
                        Button("Reprendre la hauteur du scan") {
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
                    if allowsImport { Button("Importer une pièce") { importing = true } }
                }.buttonStyle(.bordered)
                if let projectSaveDestination {
                    NavigationLink {
                        projectSaveDestination(document)
                    } label: {
                        Label("Enregistrer dans un projet", systemImage: "folder.badge.plus")
                    }.buttonStyle(.borderedProminent)
                }
                Text("Modèle initial et corrections enregistrés sur cet appareil.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle("Pièce et dimensions")
        .toolbar { Button("Modifier le plan", systemImage: "pencil.and.outline") { editingPlan = true } }
        .sheet(isPresented: $editingPlan) {
            SurveyPlanEditor(document: document,ceilingNumbers:ceilingNumbers) { edited in
                try onSave(edited); document = edited; fillFields()
            }
        }
        .sheet(item: $estimateProposal) { estimateProposal in
            WallCeilingEstimateView(document: document, proposal: estimateProposal) { edited in
                try onSave(edited)
                document = edited
                selected = edited.room.ceilings.last?.id
                ceilingMode = 1
                message = "Plafond estimé mis à jour. Les murs restent inchangés."
            }
        }
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
            LabeledContent("Pans",value:"\(pans.count)")
            LabeledContent("Origine",value:ceiling.provenance.source.title)
            if ceiling.provenance.source == .estimated {
                Label("Plafond estimé à partir des murs · non mesuré par le LiDAR", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !pans.isEmpty && pans.allSatisfy(\.manuallyValidated) {
                Text("Forme ajustée manuellement.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(pans.enumerated()),id:\.element.id) { i,pan in
                LabeledContent("Pan \(i+1)",value:"\(area(PlaquistoSurfaceGeometry.area(of:pan))) · \(pan.plane.slopeDegrees.formatted(.number.precision(.fractionLength(1))))°")
                Text("\(pan.provenance.source.title) · \(pan.accepted ? "accepté" : "non accepté")").font(.caption).foregroundStyle(.secondary)
                if !pan.accepted {
                    Button("Valider ce pan de plafond") { acceptCeilingPan(pan.id) }
                        .buttonStyle(.bordered)
                }
            }
            Text("Surface suivant les pentes, et non projection au sol. Les ouvertures de toit et trémies ne sont pas déduites.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func acceptCeilingPan(_ id: UUID) {
        var edited = document
        guard let index = edited.room.slopes.firstIndex(where: { $0.id == id }) else { return }
        edited.room.slopes[index].accepted = true
        edited.room.slopes[index].manuallyValidated = true
        do {
            try edited.validate()
            try onSave(edited)
            document = edited
            message = "Pan de plafond validé. Il peut maintenant être sélectionné pour créer un ouvrage."
        } catch { message = error.localizedDescription }
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

/// One editable room in plan; original capture and unsaved edits stay separate.
struct SurveyPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: PlaquistoRoomDocument
    let ceilingNumbers:[String:Int]
    let onSave: (PlaquistoRoomDocument) throws -> Void
    @State private var document: PlaquistoRoomDocument
    @State private var ceilingChoices: [WallCeilingEstimate.Proposal] = []
    @State private var choosingCeiling = false
    @State private var splittingCeiling: UUID?
    @State private var selected: UUID?
    @State private var selectedDoor: UUID?
    @State private var drawingPartition = false
    @State private var firstPoint: RoomPoint?
    @State private var height = 250.0
    @State private var length = 300.0
    @State private var doorWidth = 0.83
    @State private var doorHeight = 204.0
    @State private var openingWidth = 83.0
    @State private var openingHeight = 204.0
    @State private var openingSill = 0.0
    @State private var openingPosition = 0.0
    @State private var deletingOpening = false
    @State private var mergingWith: UUID?
    @State private var error: String?
    @State private var discard = false
    @State private var proposal: WallCeilingEstimate.Proposal?
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @GestureState private var pinch = 1.0
    @State private var dragging: (start: RoomPoint, current: RoomPoint)?
    init(document: PlaquistoRoomDocument, ceilingNumbers:[String:Int]=[:], onSave: @escaping (PlaquistoRoomDocument) throws -> Void) {
        original = document; self.onSave = onSave; self.ceilingNumbers=ceilingNumbers
        _document = State(initialValue: document)
    }
    private var wall: PlaquistoWall? { document.room.walls.first { $0.id == selected } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { drawingPartition.toggle(); splittingCeiling=nil; firstPoint = nil } label: {
                        Label(drawingPartition ? "Annuler le tracé" : "Cloison", systemImage: "plus.square")
                    }.tint(drawingPartition ? .orange : .accentColor)
                    Spacer()
                    ceilingMenu
                    Spacer()
                    Button { zoom = 1; offset = .zero } label: { Image(systemName: "scope") }
                        .accessibilityLabel("Recentrer le plan")
                }.buttonStyle(.bordered).padding()
                Text(splittingCeiling != nil ? "Touchez deux points pour tracer une limite traversant le plafond. Vous pourrez découper à nouveau chaque zone." :
                     (drawingPartition ? "Touchez les deux extrémités de la nouvelle cloison." : "Touchez un mur ou une ouverture pour le modifier. Le scan d’origine est conservé."))
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                if splittingCeiling != nil {
                    Button("Annuler le découpage") { splittingCeiling=nil; firstPoint=nil }
                }
                plan.frame(minHeight: 220)
                controls
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Modifier le plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if document != original { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        do { try document.validate(); try onSave(document); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(document == original)
                }
            }
            .interactiveDismissDisabled(document != original)
            .alert("Abandonner les modifications ?", isPresented: $discard) {
                Button("Continuer l’édition", role: .cancel) { }
                Button("Abandonner", role: .destructive) { dismiss() }
            }
            .alert("Modification impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .confirmationDialog("Supprimer cette ouverture du plan modifié ?", isPresented:$deletingOpening, titleVisibility:.visible) {
                Button("Supprimer l’ouverture",role:.destructive) {
                    if let id=selectedDoor {
                        edit { try SurveyPlanEditing.removingOpening(document,id:id) }
                        selectedDoor=nil
                    }
                }
            }
            .confirmationDialog("Fusionner ces deux murs ? Le contour et les ouvertures seront conservés. Les ouvrages déjà créés devront être vérifiés.", isPresented:Binding(get:{ mergingWith != nil },set:{ if !$0 { mergingWith=nil } }),titleVisibility:.visible) {
                Button("Fusionner les murs") {
                    if let first=selected, let second=mergingWith {
                        edit { try SurveyPlanEditing.mergingWalls(document,first:first,second:second) }
                        mergingWith=nil
                    }
                }
            }
            .sheet(item: $proposal) { proposal in
                WallCeilingEstimateView(document: document, proposal: proposal) { document = $0 }
            }
            .confirmationDialog("Plafond à modifier", isPresented: $choosingCeiling, titleVisibility: .visible) {
                ForEach(Array(ceilingChoices.enumerated()), id: \.element.id) { index, value in
                    Button("Plafond \(index + 1)") { proposal = value }
                }
            }
        }
    }

    private var ceilingMenu: some View {
        let choices=(try? WallCeilingEstimate.manualProposals(in:document.room)) ?? []
        let vacant=choices.filter { $0.ceilingID == nil }
        return Menu {
            Section("Créer par pièce") {
                ForEach(vacant) { value in
                    let index=vacant.firstIndex { $0.id==value.id } ?? 0
                    Button("Ajouter · zone \(index+1)") { proposal=value }
                }
                if vacant.isEmpty { Text("Toutes les zones fermées ont un plafond") }
            }
            Section("Plafonds existants") {
                ForEach(document.room.ceilings) { ceiling in
                    Menu(CeilingPlanNaming.title(ceiling,in:document.room,numbers:ceilingNumbers)) {
                        Button("Modifier la forme et les hauteurs") {
                            proposal=choices.first { $0.ceilingID==ceiling.id }
                        }.disabled(!choices.contains { $0.ceilingID==ceiling.id })
                        Button("Découper en deux zones",systemImage:"scissors") {
                            splittingCeiling=ceiling.id; drawingPartition=false; firstPoint=nil
                            selected=nil; selectedDoor=nil
                        }.disabled(ceiling.provenance.source != .estimated)
                    }
                }
            }
        } label: { Label("Plafonds",systemImage:"square.3.layers.3d") }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let opening=document.room.openings.first(where: { $0.id==selectedDoor }) {
                HStack {
                    Text(opening.kind.title).font(.headline)
                    Spacer()
                    Button("Supprimer",systemImage:"trash",role:.destructive) { deletingOpening=true }
                }
                HStack {
                    number("Largeur",value:$openingWidth)
                    number("Hauteur",value:$openingHeight)
                    number("Allège",value:$openingSill)
                    number("Position",value:$openingPosition)
                }
                Button("Appliquer à l’ouverture") {
                    edit { try SurveyPlanEditing.changingOpening(document,id:opening.id,width:openingWidth/100,
                        height:openingHeight/100,sill:openingSill/100,position:openingPosition/100) }
                }.buttonStyle(.borderedProminent)
                Text("Allège : hauteur depuis le bas du mur. Position : distance depuis son point de départ.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let wall {
                HStack {
                    number("Longueur", value: $length)
                    number("Hauteur maxi", value: $height)
                    Button("Appliquer") {
                        edit { try SurveyPlanEditing.changingWall(document, id: wall.id, start: wall.start,
                            end: wall.start+wall.direction*(length/100), height: height/100) }
                    }
                }
                HStack {
                    Picker("Largeur de porte", selection: $doorWidth) {
                        ForEach(SurveyPlanEditing.doorWidths, id: \.self) { Text("\(Int(($0*100).rounded())) cm").tag($0) }
                    }.pickerStyle(.segmented)
                    Button("Porte", systemImage: "door.left.hand.open") {
                        edit {
                            let next = try SurveyPlanEditing.addingDoor(document, wallID: wall.id, width: doorWidth,
                                height: doorHeight/100, position: max(0, (wall.length.effectiveValue-doorWidth)/2))
                            selectedDoor = next.room.openings.last?.id
                            return next
                        }
                    }.buttonStyle(.borderedProminent)
                }
                HStack {
                    number("Hauteur de porte", value: $doorHeight)
                    if let door = document.room.openings.first(where: { $0.id == selectedDoor }) {
                        Text("À \((door.positionOnWall.effectiveValue*100).formatted(.number.precision(.fractionLength(0)))) cm du bout du mur")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if wall.localOutline != nil {
                    Text("Le profil scanné est conservé ; changer la hauteur le redimensionne proportionnellement.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                let candidates=document.room.walls.filter {
                    $0.id != wall.id && (try? SurveyPlanEditing.mergingWalls(document,first:wall.id,second:$0.id)) != nil
                }
                Menu {
                    ForEach(candidates) { candidate in
                        let index=document.room.walls.firstIndex { $0.id==candidate.id } ?? 0
                        Button("Avec Mur \(index+1)") { mergingWith=candidate.id }
                    }
                } label: { Label("Fusionner avec un mur voisin",systemImage:"arrow.triangle.merge") }
                    .disabled(candidates.isEmpty)
                if candidates.isEmpty {
                    Text("Fusion disponible pour deux murs contigus partageant le même alignement et le même bord.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("Les plafonds existants ne sont pas redimensionnés automatiquement. Vérifiez-les après une correction des murs.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding().background(.regularMaterial)
    }
    private func number(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).lineLimit(1).fixedSize()
            HStack(spacing: 4) {
                ZeroEmptyDecimalTextField(value: value).frame(width: 65).multilineTextAlignment(.trailing)
                Text("cm").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func edit(_ action: () throws -> PlaquistoRoomDocument) {
        do { document = try action(); syncFields() } catch { self.error = error.localizedDescription }
    }
    private func syncFields() {
        if let wall { length = wall.length.effectiveValue*100; height = wall.height.effectiveValue*100 }
        if let opening=document.room.openings.first(where:{ $0.id==selectedDoor }) {
            openingWidth=opening.width.effectiveValue*100
            openingHeight=opening.height.effectiveValue*100
            openingSill=opening.sillHeight.effectiveValue*100
            openingPosition=opening.positionOnWall.effectiveValue*100
        }
    }
    private func prepareCeiling() {
        do {
            ceilingChoices = try WallCeilingEstimate.manualProposals(in: document.room)
            if ceilingChoices.count == 1 { proposal = ceilingChoices.first }
            else { choosingCeiling = true }
        } catch { self.error = error.localizedDescription }
    }
    private func tap(_ p: RoomPoint, tolerance: Double) {
        if let ceilingID=splittingCeiling {
            if let start=firstPoint {
                do {
                    document=try WallCeilingEstimate.split(document,ceilingID:ceilingID,from:start,to:p)
                    splittingCeiling=nil; firstPoint=nil
                } catch { self.error=error.localizedDescription; firstPoint=nil }
            } else { firstPoint=snappedToWall(p,tolerance:min(0.15,tolerance)) }
            return
        }
        if drawingPartition {
            let p = snappedToWall(p, tolerance: min(0.15, tolerance))
            if let firstPoint {
                do {
                    document = try SurveyPlanEditing.addingPartition(document, start: firstPoint, end: p,
                        height: SurveyPlanEditing.suggestedHeight(in: document.room, at: firstPoint))
                    selected = document.room.walls.last?.id; selectedDoor = nil
                    drawingPartition = false; self.firstPoint = nil; syncFields()
                } catch { self.error = error.localizedDescription }
            } else { firstPoint = p }
            return
        }
        if let opening = document.room.openings.min(by: { ($0.center-p).horizontalLength < ($1.center-p).horizontalLength }),
           (opening.center-p).horizontalLength < tolerance {
            selectedDoor = opening.id; selected = opening.wallID; syncFields(); return
        }
        selectedDoor = nil
        selected = document.room.walls.min(by: { distance(p, $0) < distance(p, $1) }).flatMap {
            distance(p, $0) < tolerance ? $0.id : nil
        }
        syncFields()
    }
    private func distance(_ p: RoomPoint, _ wall: PlaquistoWall) -> Double {
        let v = p-wall.start, along = min(wall.length.effectiveValue, max(0, v.x*wall.direction.x+v.z*wall.direction.z))
        return (p-(wall.start+wall.direction*along)).horizontalLength
    }
    private func snappedToWall(_ p: RoomPoint, tolerance: Double) -> RoomPoint {
        guard let wall = document.room.walls.min(by: { distance(p, $0) < distance(p, $1) }),
              distance(p, wall) < tolerance else { return p }
        let delta = p-wall.start
        let along = min(wall.length.effectiveValue, max(0, delta.x*wall.direction.x+delta.z*wall.direction.z))
        return wall.start+wall.direction*along
    }
    private func finishDrag(from a: RoomPoint, to b: RoomPoint, tolerance: Double) {
        defer { dragging = nil }
        if let door = document.room.openings.first(where: { $0.id == selectedDoor }), let wall,
           (door.center-a).horizontalLength < tolerance {
            let delta = b-wall.start
            let position = min(max(0, wall.length.effectiveValue-door.width.effectiveValue),
                max(0, delta.x*wall.direction.x+delta.z*wall.direction.z-door.width.effectiveValue/2))
            edit { try SurveyPlanEditing.movingDoor(document, id: door.id, position: position) }
        } else if let wall, distance(a, wall) < tolerance {
            let nearStart = (a-wall.start).horizontalLength < tolerance
            let nearEnd = (a-wall.effectiveEnd).horizontalLength < tolerance
            let delta = b-a
            edit { try SurveyPlanEditing.changingWall(document, id: wall.id,
                start: nearStart ? b : (nearEnd ? wall.start : wall.start+delta),
                end: nearEnd ? b : (nearStart ? wall.effectiveEnd : wall.effectiveEnd+delta),
                height: wall.height.effectiveValue) }
        }
    }
    private var plan: some View {
        GeometryReader { proxy in
            let points = document.room.walls.flatMap { [$0.start, $0.effectiveEnd] }
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 4
            let minZ = points.map(\.z).min() ?? 0, maxZ = points.map(\.z).max() ?? 4
            let scale = max(1, min((proxy.size.width-116)/max(1,maxX-minX), (proxy.size.height-116)/max(1,maxZ-minZ))) * zoom * pinch
            let center = RoomPoint(x: (minX+maxX)/2, y: document.room.walls.first?.start.y ?? 0, z: (minZ+maxZ)/2)
            let screen: (RoomPoint) -> CGPoint = { .init(x: proxy.size.width/2+($0.x-center.x)*scale+offset.width,
                y: proxy.size.height/2+($0.z-center.z)*scale+offset.height) }
            let world: (CGPoint) -> RoomPoint = { .init(x: ($0.x-proxy.size.width/2-offset.width)/scale+center.x,
                y: center.y, z: ($0.y-proxy.size.height/2-offset.height)/scale+center.z) }
            Canvas { context, _ in
                var occupied:[CGRect]=[]
                for ceiling in document.room.ceilings {
                    if let boundary=WallCeilingEstimate.footprint(of:ceiling,in:document.room),
                       let point=ArchitecturalPlanInk.interiorPoint(boundary) {
                        let label=CeilingPlanNaming.title(ceiling,in:document.room,numbers:ceilingNumbers)
                        let p=screen(point), width=CGFloat(label.count)*6+16
                        occupied.append(CGRect(x:p.x-width/2,y:p.y-14,width:width,height:28))
                    }
                }
                for ceiling in document.room.ceilings {
                    for slope in document.room.slopes where ceiling.slopeIDs.contains(slope.id) {
                        var path=Path()
                        for boundary in slope.boundaries where !boundary.isEmpty {
                            path.move(to:screen(boundary[0]))
                            for p in boundary.dropFirst() { path.addLine(to:screen(p)) }
                            path.closeSubpath()
                        }
                        context.fill(path,with:.color(.gray.opacity(0.07)),style:.init(eoFill:true))
                        context.stroke(path,with:.color(ceiling.id==splittingCeiling ? .orange : ArchitecturalPlanInk.wall.opacity(0.4)),lineWidth:1)
                    }
                    if let boundary=WallCeilingEstimate.footprint(of:ceiling,in:document.room),
                       let point=ArchitecturalPlanInk.interiorPoint(boundary) {
                        ArchitecturalPlanInk.ceilingLabel(context,title:CeilingPlanNaming.title(ceiling,in:document.room,numbers:ceilingNumbers),point:screen(point))
                    }
                }
                for wall in document.room.walls {
                    let a = screen(wall.start), b = screen(wall.effectiveEnd)
                    var line = Path(); line.move(to: a); line.addLine(to: b)
                    context.stroke(line, with: .color(wall.id == selected ? .orange : ArchitecturalPlanInk.wall), style: .init(lineWidth: 6, lineCap: .square))
                    ArchitecturalPlanInk.dimension(context,a:a,b:b,meters:wall.length.effectiveValue,
                        center:screen(center),occupied:&occupied,important:wall.id==selected)
                    if wall.id == selected {
                        for p in [a,b] { context.fill(Path(ellipseIn: CGRect(x:p.x-7,y:p.y-7,width:14,height:14)),with:.color(.orange)) }
                    }
                }
                for door in document.room.openings {
                    guard let wall = document.room.walls.first(where: { $0.id == door.wallID }) else { continue }
                    let a = wall.start+wall.direction*door.positionOnWall.effectiveValue
                    ArchitecturalPlanInk.opening(context,a:screen(a),b:screen(a+wall.direction*door.width.effectiveValue),
                        window:door.kind == .window || door.kind == .glazedBay,selected:door.id==selectedDoor)
                }
                if let firstPoint {
                    let p = screen(firstPoint)
                    context.fill(Path(ellipseIn: CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(.orange))
                }
                if let dragging {
                    var line = Path(); line.move(to: screen(dragging.start)); line.addLine(to: screen(dragging.current))
                    context.stroke(line, with: .color(.orange), style: .init(lineWidth: 2, dash: [4,3]))
                }
            }
            .contentShape(Rectangle())
            .background(ArchitecturalPlanInk.paper)
            .gesture(SpatialTapGesture().onEnded { tap(world($0.location), tolerance: 25/scale) })
            .simultaneousGesture(MagnifyGesture().updating($pinch) { value,state,_ in state = value.magnification }
                .onEnded { zoom = min(8,max(0.5,zoom*$0.magnification)) })
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                dragging = (world(value.startLocation), world(value.location))
            }.onEnded { value in
                let a = world(value.startLocation), b = world(value.location)
                if splittingCeiling == nil, !drawingPartition, let wall, distance(a,wall) < 25/scale { finishDrag(from:a,to:b,tolerance:25/scale) }
                else {
                    offset.width = min(proxy.size.width/2,max(-proxy.size.width/2,offset.width+value.translation.width))
                    offset.height = min(proxy.size.height/2,max(-proxy.size.height/2,offset.height+value.translation.height))
                    dragging = nil
                }
            })
            .clipped()
        }
    }
}

/// The same lightweight drafting conventions in the editor and survey top plan.
enum ArchitecturalPlanInk {
    static func interiorPoint(_ boundary:[RoomPoint]) -> RoomPoint? {
        guard !boundary.isEmpty else { return nil }
        let center=RoomPoint(x:((boundary.map(\.x).min() ?? 0)+(boundary.map(\.x).max() ?? 0))/2,y:0,
                             z:((boundary.map(\.z).min() ?? 0)+(boundary.map(\.z).max() ?? 0))/2)
        if PlaquistoWallGeometry.contains(center,polygon:boundary) { return center }
        var polygon=boundary.map { SIMD2($0.x,$0.z) }
        if ScannerCeilingReconstruction.triangulate(polygon) == nil { polygon.reverse() }
        guard let indices=ScannerCeilingReconstruction.triangulate(polygon) else { return nil }
        var best=0.0, point:RoomPoint?
        for i in stride(from:0,to:indices.count,by:3) {
            let a=polygon[indices[i]], b=polygon[indices[i+1]], c=polygon[indices[i+2]]
            let area=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))
            if area > best { best=area; let p=(a+b+c)/3; point = .init(x:p.x,y:0,z:p.y) }
        }
        return point
    }
    static let paper=Color(red:0.975,green:0.97,blue:0.95)
    static let wall=Color(red:0.22,green:0.24,blue:0.28)
    static func dimension(_ context:GraphicsContext, a:CGPoint, b:CGPoint, meters:Double,
                          center:CGPoint, occupied:inout [CGRect], important:Bool=false) {
        let length=hypot(b.x-a.x,b.y-a.y)
        guard length > 60 || important else { return }
        var nx = -(b.y-a.y)/max(1,length), ny=(b.x-a.x)/max(1,length)
        let mid=CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
        if (mid.x-center.x)*nx+(mid.y-center.y)*ny < 0 { nx = -nx; ny = -ny }
        let label=Text("\(meters.formatted(.number.precision(.fractionLength(2)))) m")
            .font(.system(size:10,weight:important ? .semibold : .regular)).foregroundColor(wall)
        var angle=atan2(b.y-a.y,b.x-a.x)
        if angle > .pi/2 { angle -= .pi }; if angle < -.pi/2 { angle += .pi }
        for offset in [30.0,48.0,66.0] {
            let p=CGPoint(x:mid.x+nx*(offset+10),y:mid.y+ny*(offset+10))
            let w=abs(cos(angle))*58+abs(sin(angle))*14
            let h=abs(sin(angle))*58+abs(cos(angle))*14
            let bounds=CGRect(x:p.x-w/2-3,y:p.y-h/2-3,width:w+6,height:h+6)
            if occupied.contains(where:{$0.intersects(bounds)}) { continue }
            occupied.append(bounds)
            var line=Path()
            for point in [a,b] {
                line.move(to:.init(x:point.x+nx*9,y:point.y+ny*9))
                line.addLine(to:.init(x:point.x+nx*(offset+4),y:point.y+ny*(offset+4)))
                let q=CGPoint(x:point.x+nx*offset,y:point.y+ny*offset)
                line.move(to:.init(x:q.x-3,y:q.y+3)); line.addLine(to:.init(x:q.x+3,y:q.y-3))
            }
            line.move(to:.init(x:a.x+nx*offset,y:a.y+ny*offset))
            line.addLine(to:.init(x:b.x+nx*offset,y:b.y+ny*offset))
            context.stroke(line,with:.color(wall.opacity(0.55)),lineWidth:0.65)
            var local=context; local.translateBy(x:p.x,y:p.y); local.rotate(by:.radians(angle))
            local.fill(Path(CGRect(x:-29,y:-7,width:58,height:14)),with:.color(paper))
            local.draw(label,at:.zero); return
        }
    }
    static func opening(_ context:GraphicsContext, a:CGPoint, b:CGPoint, window:Bool, selected:Bool) {
        let length=max(1,hypot(b.x-a.x,b.y-a.y)), nx = -(b.y-a.y)/length, ny=(b.x-a.x)/length
        var gap=Path(); gap.move(to:a); gap.addLine(to:b)
        context.stroke(gap,with:.color(paper),lineWidth:9)
        var lines=Path()
        for p in [a,b] {
            lines.move(to:.init(x:p.x-nx*4,y:p.y-ny*4)); lines.addLine(to:.init(x:p.x+nx*4,y:p.y+ny*4))
        }
        if window {
            for d in [-2.0,2.0] {
                lines.move(to:.init(x:a.x+nx*d,y:a.y+ny*d)); lines.addLine(to:.init(x:b.x+nx*d,y:b.y+ny*d))
            }
        }
        context.stroke(lines,with:.color(selected ? .orange : wall),lineWidth:selected ? 2 : 0.9)
    }
    static func ceilingLabel(_ context:GraphicsContext, title:String, point:CGPoint) {
        let text=Text(title).font(.system(size:11,weight:.medium)).foregroundColor(wall)
        let resolved=context.resolve(text), size=resolved.measure(in:.init(width:180,height:22))
        context.fill(Path(roundedRect:.init(x:point.x-size.width/2-5,y:point.y-11,width:size.width+10,height:22),
                          cornerRadius:4),with:.color(paper.opacity(0.94)))
        context.draw(resolved,at:point)
    }
}

private extension RoomPoint {
    var horizontalLength: Double { hypot(x,z) }
}

struct WallCeilingEstimateView: View {
    @Environment(\.dismiss) private var dismiss
    let document: PlaquistoRoomDocument
    let proposal: WallCeilingEstimate.Proposal
    private let unchangedInput: CeilingEstimateSettings
    let onSave: (PlaquistoRoomDocument) throws -> Void
    @State private var settings: CeilingEstimateSettings
    @State private var lowText: String
    @State private var highText: String
    @State private var selected: UUID?
    @State private var error: String?
    @State private var topView = false
    @State private var cameraReset = UUID()

    init(document: PlaquistoRoomDocument, proposal: WallCeilingEstimate.Proposal,
         onSave: @escaping (PlaquistoRoomDocument) throws -> Void) {
        self.document = document; self.proposal = proposal; self.onSave = onSave
        let target = proposal.ceilingID.flatMap { id in document.room.ceilings.first { $0.id == id } }
        let settings = target?.estimateSettings ?? proposal.suggestedSettings
        var rounded=settings
        rounded.lowHeight=(settings.lowHeight*100).rounded()/100
        rounded.highHeight=settings.shape == .flat ? rounded.lowHeight : (settings.highHeight*100).rounded()/100
        unchangedInput=rounded
        _settings = State(initialValue: settings)
        _lowText = State(initialValue: settings.lowHeight.formatted(.number.precision(.fractionLength(2))))
        _highText = State(initialValue: settings.highHeight.formatted(.number.precision(.fractionLength(2))))
    }
    private var input: CeilingEstimateSettings? {
        func number(_ text: String) -> Double? {
            Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        guard let low = number(lowText), let high = number(highText) else { return nil }
        var value = settings
        value.lowHeight = low; value.highHeight = settings.shape == .flat ? low : high
        return value.isValid ? value : nil
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var previewDocument: PlaquistoRoomDocument?
    @State private var previewIssue: String?

    private func refreshPreview() {
        guard let input else {
            previewIssue="Renseignez des hauteurs positives ; la hauteur maximale doit être supérieure ou égale à la minimale."
            return
        }
        if proposal.ceilingID != nil, input == unchangedInput {
            previewDocument=document; previewIssue=nil; selected=proposal.ceilingID
            return
        }
        do {
            previewDocument=try WallCeilingEstimate.applying(to:document,proposal:proposal,settings:input,manuallyEdited:true)
            selected=proposal.ceilingID ?? previewDocument?.room.ceilings.last?.id
            previewIssue=nil
        } catch { previewIssue=error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let landscape=geometry.size.width > 550 && geometry.size.width > geometry.size.height
                let layout=landscape ? AnyLayout(HStackLayout(alignment:.top,spacing:0)) : AnyLayout(VStackLayout(spacing:0))
                let previewHeight=landscape
                    ? max(90,geometry.size.height-100)
                    : max(90,min(dynamicTypeSize.isAccessibilitySize ? 140 : 230,geometry.size.height*0.32))
                layout {
                    previewPanel(height:previewHeight)
                        .frame(width:landscape ? geometry.size.width*0.48 : nil)
                    Form {
                        Section("Forme et hauteurs") {
                            Picker("Forme",selection:$settings.shape) {
                                ForEach(CeilingEstimateSettings.Shape.allCases) { shape in
                                    Text(shape.title).tag(shape)
                                }
                            }
                            heightField(settings.shape == .flat ? "Hauteur sous plafond" : "Hauteur minimale",text:$lowText)
                            if settings.shape != .flat { heightField("Hauteur maximale",text:$highText) }
                        }
                        if settings.shape != .flat {
                            Section("Réglage des pans") {
                                VStack(alignment:.leading,spacing:8) {
                                    LabeledContent("Orientation",value:"\((settings.azimuth*180/Double.pi).formatted(.number.precision(.fractionLength(0))))°")
                                    Slider(value:$settings.azimuth,in:(-Double.pi)...Double.pi)
                                        .accessibilityLabel("Orientation des pans")
                                        .accessibilityValue("\((settings.azimuth*180/Double.pi).formatted(.number.precision(.fractionLength(0)))) degrés")
                                }
                                if settings.shape != .singleSlope {
                                    VStack(alignment:.leading,spacing:8) {
                                        LabeledContent("Position du faîtage",value:"\((settings.ridgePosition*100).formatted(.number.precision(.fractionLength(0)))) %")
                                        Slider(value:$settings.ridgePosition,in:0.15...0.85)
                                            .accessibilityLabel("Position du faîtage")
                                            .accessibilityValue("\((settings.ridgePosition*100).formatted(.number.precision(.fractionLength(0)))) pour cent")
                                    }
                                }
                            }
                        }
                        if let previewIssue {
                            Section { Text(previewIssue).font(.footnote).foregroundStyle(.orange) }
                        }
                        Section {
                            DisclosureGroup("À propos des mesures") {
                                Text("Les hauteurs préremplies sont des estimations, pas des mesures du plafond. Hauteurs mesurées depuis le sol ; cette création ne modifie jamais le contour des murs.")
                                if proposal.maximumCornerAdjustment > 0.005 {
                                    Text("Raccord estimé des angles : jusqu’à \((proposal.maximumCornerAdjustment*100).formatted(.number.precision(.fractionLength(1)))) cm.")
                                }
                                Text("Ces formes sont des hypothèses modifiables, pas des mesures LiDAR. Les trémies et ouvertures de toit non relevées ne sont pas déduites.")
                            }.font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of:input,initial:true) { _, _ in refreshPreview() }
            .navigationTitle("Plafond")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Enregistrer") {
                        do {
                            guard input != nil, let previewDocument, previewIssue == nil else { throw WallCeilingEstimate.Failure.invalidHeight }
                            try onSave(previewDocument)
                            dismiss()
                        } catch { self.error=error.localizedDescription }
                    }.disabled(input == nil || previewDocument == nil || previewIssue != nil)
                }
            }
            .alert("Plafond non enregistré",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error=nil } })) {
                Button("OK") { error=nil }
            } message: { Text(error ?? "") }
        }
    }

    private func previewPanel(height:CGFloat) -> some View {
        VStack(spacing:8) {
            ZStack {
                if let previewDocument {
                    RoomDomainScene(room:previewDocument.room,selected:$selected,ceilingMode:2,
                        showFloor:true,topView:topView,cameraReset:cameraReset)
                } else {
                    ContentUnavailableView("Aperçu du plafond",systemImage:"cube.transparent",
                        description:Text("Renseignez les hauteurs pour afficher le plafond."))
                }
            }
            .frame(height:height)
            .clipShape(RoundedRectangle(cornerRadius:16))
            .accessibilityIdentifier("ceiling.fixedPreview")
            HStack {
                Picker("Vue",selection:$topView) {
                    Text("Perspective").tag(false)
                    Text("Dessus").tag(true)
                }.pickerStyle(.segmented)
                Button("Recentrer",systemImage:"scope") { cameraReset=UUID() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            if previewIssue != nil, previewDocument != nil {
                Label("Aperçu précédent · saisie à compléter",systemImage:"exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if let previewDocument {
                let target=previewDocument.room.ceilings.first { $0.id==selected }
                let pans=previewDocument.room.slopes.filter { target?.slopeIDs.contains($0.id) ?? false }
                Text("\(pans.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) }.formatted(.number.precision(.fractionLength(2)))) m² · Hauteurs estimées, à vérifier")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal,16).padding(.vertical,8)
    }
    private func heightField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).fixedSize(horizontal:false,vertical:true)
            Spacer()
            PlaquistoNumericField(placeholder: "0", text: text)
                .frame(minWidth:65,maxWidth:100)
                .multilineTextAlignment(.trailing).accessibilityLabel(title)
            Text("m").foregroundStyle(.secondary)
        }
    }
}

struct RoomDomainScene: UIViewRepresentable {
    let room: PlaquistoRoomModel
    @Binding var selected: UUID?
    let ceilingMode: Int
    let showFloor: Bool
    let topView: Bool
    let cameraReset: UUID
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> SCNView {
        let view=SCNView(); view.scene=SCNScene()
        MaquetteStyle.configure(view,quality:.current)
        view.allowsCameraControl=true
        view.addGestureRecognizer(UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view:SCNView,context:Context) {
        update(view,coordinator:context.coordinator)
    }
    func update(_ view:SCNView,coordinator:Coordinator) {
        let previous=coordinator.parent
        let reset=view.pointOfView == nil || coordinator.roomID != room.id || previous.topView != topView || previous.cameraReset != cameraReset
        let rebuild=coordinator.lastRoom != room
        coordinator.parent=self
        coordinator.lastRoom=room
        let root=view.scene!.rootNode
        let quality=MaquetteStyle.Quality.current
        if coordinator.quality != quality {
            coordinator.quality=quality
            MaquetteStyle.configure(view,quality:quality)
            MaquetteStyle.installStudio(in:view.scene!,quality:quality)
            if let camera=view.pointOfView?.camera { MaquetteStyle.configure(camera,quality:quality) }
        }
        if rebuild {
            coordinator.geometryBuildCount += 1
            coordinator.content?.removeFromParentNode()
            let content=SCNNode(); content.name="room-content"; root.addChildNode(content)
            coordinator.content=content
            coordinator.walls=[]; coordinator.roofs=[]; coordinator.floors=[]; coordinator.outlines=[]
            func vector(_ p:RoomPoint) -> SCNVector3 { .init(Float(p.x),Float(p.y),Float(p.z)) }
            func node(_ points:[RoomPoint],surface:MaquetteStyle.Surface,name:String?=nil) -> SCNNode {
                let geometry=MaquetteStyle.geometry(points,textureCoordinates:surface == .floor ? points.map { MaquetteStyle.uv($0) } : nil)
                geometry.materials=[MaquetteStyle.material(surface)]
                let node=SCNNode(geometry:geometry); node.name=name; node.castsShadow=true
                node.categoryBitMask=name == nil ? 2 : 1
                content.addChildNode(node)
                return node
            }
            for wall in room.walls {
                coordinator.walls.append(node(PlaquistoWallGeometry.displayTriangles(wall:wall,room:room),surface:.wall,name:wall.id.uuidString))
            }
            do {
                for floor in room.floors {
                    let points=floor.boundaries.flatMap { PlaquistoSurfaceGeometry.triangles($0) }.map { $0+RoomPoint(x:0,y:-0.008,z:0) }
                    coordinator.floors.append(node(points,surface:.floor))
                }
            }
            do {
                for pan in room.slopes {
                    let points=pan.boundaries.flatMap { loop in
                        PlaquistoSurfaceGeometry.triangles(loop.map { RoomPoint(x:$0.x,y:pan.plane.height(x:$0.x,z:$0.z),z:$0.z) })
                    }
                    let ceilingID=room.ceilings.first { $0.slopeIDs.contains(pan.id) }?.id
                    let roof=node(points,surface:.ceiling,name:ceilingID?.uuidString)
                    coordinator.roofs.append(roof)
                    // Outline each plane, not its triangulation: ridges and hip edges
                    // must remain readable even with soft, uniform roof materials.
                    let lines = pan.boundaries.flatMap { loop in
                        loop.indices.flatMap { i in [loop[i], loop[(i+1)%loop.count]] }
                    }.map { RoomPoint(x: $0.x, y: pan.plane.height(x: $0.x, z: $0.z) + 0.003, z: $0.z) }
                    let outline = SCNGeometry(sources: [SCNGeometrySource(vertices: lines.map(vector))],
                        elements: [SCNGeometryElement(indices: Array(0..<Int32(lines.count)), primitiveType: .line)])
                    outline.materials = [MaquetteStyle.outlineMaterial]
                    let edges = SCNNode(geometry: outline); edges.categoryBitMask = 2
                    content.addChildNode(edges); coordinator.outlines.append(edges)
                }
            }
        }
        for wall in coordinator.walls {
            wall.geometry?.firstMaterial=MaquetteStyle.material(.wall,state:wall.name == selected?.uuidString ? .selected : .normal)
        }
        for floor in coordinator.floors { floor.isHidden = !showFloor }
        for roof in coordinator.roofs {
            let highlighted=selected != nil && roof.name == selected?.uuidString
            roof.isHidden=ceilingMode == 0
            roof.opacity=ceilingMode == 1 ? (highlighted ? 0.6 : 0.25) : 1
            roof.geometry?.firstMaterial=MaquetteStyle.material(.ceiling,state:highlighted ? .selected : .normal,translucent:ceilingMode == 1)
            roof.renderingOrder=ceilingMode == 1 ? 20 : 0
            roof.castsShadow=ceilingMode == 2
        }
        for edges in coordinator.outlines {
            edges.isHidden=ceilingMode == 0
            edges.opacity=ceilingMode == 1 ? 0.35 : 0.75
        }
        func vector(_ p:RoomPoint) -> SCNVector3 { .init(Float(p.x),Float(p.y),Float(p.z)) }
        if reset {
            root.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }
            let points=room.walls.flatMap { PlaquistoWallGeometry.triangles(wall:$0,room:room) }
                + room.slopes.flatMap { $0.boundaries.flatMap { $0 } }
            let minP=RoomPoint(x:points.map(\.x).min() ?? 0,y:points.map(\.y).min() ?? 0,z:points.map(\.z).min() ?? 0)
            let maxP=RoomPoint(x:points.map(\.x).max() ?? 1,y:points.map(\.y).max() ?? 1,z:points.map(\.z).max() ?? 1)
            let center=(minP+maxP)*0.5, radius=max(1.5,(maxP-minP).length/2)
            let camera=SCNNode(); camera.camera=SCNCamera(); camera.camera?.zFar=10000; camera.camera?.zNear=0.01
            MaquetteStyle.configure(camera.camera!,quality:quality)
            camera.camera?.fieldOfView=45
            camera.camera?.usesOrthographicProjection=topView; camera.camera?.orthographicScale=radius*1.25
            camera.position=vector(center+(topView ? RoomPoint(x:0,y:radius*3,z:0.001) : RoomPoint(x:radius*1.65,y:radius*1.35,z:radius*1.65)))
            camera.look(at:vector(center)); root.addChildNode(camera); view.pointOfView=camera
            view.defaultCameraController.target=vector(center); coordinator.roomID=room.id
        }
    }
    final class Coordinator: NSObject {
        var parent:RoomDomainScene
        var lastRoom:PlaquistoRoomModel?; var roomID:UUID?
        var content:SCNNode?
        var walls:[SCNNode]=[], roofs:[SCNNode]=[], floors:[SCNNode]=[], outlines:[SCNNode]=[]
        var quality:MaquetteStyle.Quality?
        var geometryBuildCount=0
        init(_ parent:RoomDomainScene) { self.parent=parent }
        @objc func tap(_ gesture:UITapGestureRecognizer) {
            guard let view=gesture.view as? SCNView else { return }
            if let id=view.hitTest(gesture.location(in:view),options:[.categoryBitMask:1]).compactMap({ $0.node.name.flatMap(UUID.init(uuidString:)) }).first {
                parent.selected=id
            }
        }
    }
}
