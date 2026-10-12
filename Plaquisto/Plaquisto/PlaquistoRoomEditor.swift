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
            WallCeilingEstimateView(document: document, proposal: estimateProposal,ceilingNumbers:ceilingNumbers) { edited in
                try onSave(edited)
                document = edited
                selected = estimateProposal.ceilingID ?? edited.room.ceilings.last?.id
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
private struct SurveyPlanManipulation {
    enum Handle { case start, end, body, door }
    let handle: Handle
    let wall: PlaquistoWall
    let touch: RoomPoint
    let door: PlaquistoOpening?
    var start: RoomPoint
    var end: RoomPoint
    var doorPosition: Double?
    var preservesOpeningLocations: Bool {
        guard handle == .start || handle == .end else { return false }
        let v = end-start, axis = wall.direction
        return abs(v.x*axis.z-v.z*axis.x) < 1e-6 && v.x*axis.x+v.z*axis.z > 0
    }
    var preview: PlaquistoWall {
        var copy = wall
        copy.start = start; copy.end = end
        copy.length.manualValue = hypot(end.x-start.x,end.z-start.z)
        copy.length.manuallyValidated = true
        return copy
    }
}

private struct SurveyPlanUndoState {
    var document: PlaquistoRoomDocument
    var draftWall: PlaquistoWall?
    var selected: UUID?
    var selectedDoor: UUID?
    var firstPoint: RoomPoint?
    var drawingPartition: Bool
}

/// A cut is a draft until explicitly accepted. Neither dragging nor previewing
/// mutates the editor document or creates an undo entry.
struct SurveyCeilingCut {
    private(set) var start: RoomPoint?
    private(set) var end: RoomPoint?
    private(set) var preview: PlaquistoRoomDocument?
    mutating func begin(at point: RoomPoint) {
        guard preview == nil, point.finite else { return }
        start = point; end = point
    }
    mutating func move(to point: RoomPoint) {
        guard start != nil, preview == nil, point.finite else { return }
        end = point
    }
    mutating func finish(document: PlaquistoRoomDocument, ceilingID: UUID, minimumLength: Double) throws {
        guard preview == nil else { return }
        guard let start, let end,
              (end-start).horizontalLength >= max(0.02, minimumLength) else {
            reset(); throw RoomModelError.invalidGeometry
        }
        do { preview = try WallCeilingEstimate.split(document, ceilingID: ceilingID, from: start, to: end) }
        catch { reset(); throw error }
    }
    mutating func cancelGesture() { if preview == nil { reset() } }
    mutating func reset() { start = nil; end = nil; preview = nil }
    mutating func accept() -> PlaquistoRoomDocument? {
        let result = preview; reset(); return result
    }
}

/// Occupies the same space while drawing and previewing: inserting controls
/// only on touch-up would resize the canvas and shift the apparent cut.
struct SurveyCeilingCutConfirmation: View {
    let ready: Bool
    let redo: () -> Void
    let accept: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text("Valider cette séparation ?").font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                Button("Refaire la coupe", systemImage: "arrow.uturn.backward", action: redo)
                    .buttonStyle(.bordered).accessibilityIdentifier("ceiling.cut.redo")
                Button("Valider", systemImage: "checkmark", action: accept)
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("ceiling.cut.confirm")
            }
        }
        .padding(.horizontal).padding(.bottom, 8)
        .opacity(ready ? 1 : 0)
        .allowsHitTesting(ready)
        .accessibilityHidden(!ready)
    }
}

private enum SurveyPlanMode: String, CaseIterable, Identifiable {
    case view = "Vue", dimensions = "Cotes", partitions = "Cloisons", openings = "Ouvertures"
    var id: Self { self }
}

struct SurveyPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: PlaquistoRoomDocument
    let ceilingNumbers:[String:Int]
    let initiallyConfigureCeilings: Bool
    var liningDepths: [UUID: Double] = [:]
    var onRequestLining: (() -> Void)?
    @State private var mode: SurveyPlanMode = .view
    @State private var thicknessMM = 72.0
    @State private var pendingPoint: RoomPoint?
    @State private var cursor: RoomPoint?
    @State private var confirmingPoint = false
    @State private var needsLining = false
    @State private var showingProperties = false
    @State private var traceStart: PlaquistoRoomDocument?
    @State private var traceHistoryIndex = 0
    @State private var placingDoor = false
    @State private var pendingDoorWall: UUID?
    @State private var pendingDoorPosition = 0.0
    @State private var confirmingDoor = false
    @State private var zoneRings: [[PlaquistoWall]] = []
    @State private var finishedShell: [PlaquistoWall] = []
    @State private var proposedSplit: PlaquistoRoomDocument?
    @State private var confirmingSplit = false
    private struct ContourRoute: Identifiable {
        let id=UUID()
        let walls:[PlaquistoWall]
        let origin:RoomPoint
        let surface:Surface2D?
    }
    @State private var contourRoute:ContourRoute?
    @State private var pendingContour:PlaquistoRoomDocument?
    @State private var confirmingContour = false
    @State private var showingCeilingSplitPlan = false
    let onSave: (PlaquistoRoomDocument) throws -> Void
    @State private var document: PlaquistoRoomDocument
    @State private var ceilingChoices: [WallCeilingEstimate.Proposal] = []
    @State private var choosingCeiling = false
    @State private var pendingCeiling: WallCeilingEstimate.Proposal?
    @State private var pendingCeilingSplit: UUID?
    @State private var splittingCeiling: UUID?
    @State private var ceilingCut = SurveyCeilingCut()
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
    @State private var deletingPartition = false
    @State private var mergingWith: UUID?
    @State private var mergeCandidateIDs: Set<UUID> = []
    @State private var error: String?
    @State private var discard = false
    @State private var proposal: WallCeilingEstimate.Proposal?
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @State private var pinch = 1.0
    @State private var planDrag = CGSize.zero
    @State private var panning = false
    @State private var cancelledByPinch = false
    @State private var manipulation: SurveyPlanManipulation?
    @State private var draftWall: PlaquistoWall?
    @State private var history: [SurveyPlanUndoState] = []
    @State private var fixedStart = true
    @State private var snapping = true
    @State private var snapResult: SurveyPlanSnapping.Result?
    @State private var fittedPoints: [RoomPoint]?
    @State private var viewRotation = 0.0
    @State private var alignedWall: UUID?
    @State private var fullscreen = false
    @State private var canvasFitSize: CGSize?
    @State private var recenterToken = 0
    init(document: PlaquistoRoomDocument, ceilingNumbers:[String:Int]=[:], initiallyConfigureCeilings: Bool = false,
         liningDepths: [UUID: Double] = [:], resumePartitions: Bool = false, onRequestLining: (() -> Void)? = nil,
         onSave: @escaping (PlaquistoRoomDocument) throws -> Void) {
        original = document; self.onSave = onSave; self.ceilingNumbers=ceilingNumbers
        self.initiallyConfigureCeilings = initiallyConfigureCeilings
        self.liningDepths = liningDepths; self.onRequestLining = onRequestLining
        _mode = State(initialValue: resumePartitions ? .partitions : .view)
        _document = State(initialValue: document)
    }
    private var wall: PlaquistoWall? { draftWall ?? document.room.walls.first { $0.id == selected } }
    private var hasChanges: Bool { document != original || draftWall != nil || firstPoint != nil || ceilingCut.start != nil }
    var body: some View {
        Group {
            if initiallyConfigureCeilings && !showingCeilingSplitPlan {
                CeilingZonePicker(room: document.room, choices: ceilingChoices, numbers: ceilingNumbers,
                    onChoose: { proposal = $0 }, onSplit: { id in
                        startCeilingCut(id)
                    }, onMerge: { a,b in commitDocument(try CeilingZoneEditing.merge(document,first:a,second:b)) },
                    onToggleHidden: { commitDocument(CeilingZoneEditing.togglingVisibility(document,ceilingID:$0)) },
                    onClose: { if hasChanges { discard = true } else { dismiss() } }, onSave: {
                        do { try document.validate(); try onSave(document); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }, canSave: document != original)
                    .task { refreshCeilingChoices() }
                    .onChange(of: document) { _,_ in refreshCeilingChoices() }
                    .sheet(item: $proposal) { proposal in
                        WallCeilingEstimateView(document: document, proposal: proposal, ceilingNumbers: ceilingNumbers,
                            appliesToPlan: true) { commitDocument($0) }
                    }
                    .interactiveDismissDisabled(hasChanges)
                    .alert("Abandonner les modifications ?", isPresented: $discard) {
                        Button("Continuer l’édition", role: .cancel) { }
                        Button("Abandonner", role: .destructive) { dismiss() }
                    }
                    .alert("Modification impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                        Button("OK") { error = nil }
                    } message: { Text(error ?? "") }
            } else { planEditor }
        }
    }
    private var planEditor: some View {
        NavigationStack { planDialogs }
    }
    private var planContent: some View {
            VStack(spacing: 10) {
                HStack(spacing:2) {
                    ForEach(SurveyPlanMode.allCases) { item in
                        Button { mode=item } label: {
                            Text(item.rawValue).font(.system(size:12,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth:.infinity,minHeight:34)
                                .background(mode == item ? Color(.systemBackground) : .clear,in:Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(mode == item ? [.isSelected] : [])
                    }
                }.padding(3).background(Color(.tertiarySystemFill),in:Capsule()).padding(.horizontal)
                    .disabled(drawingPartition || placingDoor || manipulation != nil || splittingCeiling != nil)
                if !fullscreen { Text(instructions)
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
                if splittingCeiling != nil {
                    Button("Annuler le découpage", role: .cancel) { cancelCeilingCut() }
                }
                plan.frame(minHeight: 220)
                    .overlay(alignment:.topLeading) {
                        if mode == .view {
                            roundPlanButton("Orienter la vue sur le mur suivant",symbol:"arrow.clockwise") {
                                if let wall=SurveyPlanCamera.nextWall(document.room.walls,after:alignedWall) {
                                    viewRotation=SurveyPlanCamera.horizontalAngle(for:wall); alignedWall=wall.id
                                }
                            }.disabled(document.room.walls.isEmpty || ceilingCut.start != nil).padding(8)
                        } else {
                            roundPlanButton("Aimantation",symbol:"point.topleft.down.to.point.bottomright.curvepath",active:snapping) {
                                snapping.toggle(); snapResult=nil
                            }.accessibilityValue(snapping ? "Activée" : "Désactivée")
                                .disabled(manipulation != nil).padding(8)
                        }
                    }
                    .overlay(alignment:.topTrailing) {
                        roundPlanButton(fullscreen ? "Quitter le plein écran" : "Afficher le plan en plein écran",
                                        symbol:fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                            fullscreen.toggle()
                        }.contextMenu {
                            Button("Recentrer le plan",systemImage:"scope") {
                                fittedPoints=document.room.walls.flatMap { [$0.start,$0.effectiveEnd] }
                                zoom=1; offset = .zero; recenterToken += 1
                            }
                        }.disabled(manipulation != nil || cursor != nil || (ceilingCut.start != nil && ceilingCut.preview == nil)).padding(8)
                    }
                    .overlay(alignment:.bottomLeading) {
                        roundPlanButton("Annuler le dernier geste",symbol:"arrow.uturn.backward",action:undoPlanEdit)
                            .disabled(history.isEmpty || manipulation != nil || drawingPartition || placingDoor || splittingCeiling != nil).padding(8)
                    }
                    .overlay(alignment:.bottomTrailing) { selectionActions.padding(8) }
                    .clipShape(RoundedRectangle(cornerRadius:24))
                    .padding(.horizontal,fullscreen ? 4 : 16)
                if splittingCeiling != nil {
                    SurveyCeilingCutConfirmation(ready: ceilingCut.preview != nil,
                        redo: { ceilingCut.reset() }, accept: acceptCeilingCut)
                } else if splittingCeiling == nil && (!fullscreen || mode != .view) { editorTools }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(initiallyConfigureCeilings ? "Configurer les plafonds" : "Modifier le plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(fullscreen ? .hidden : .visible,for:.navigationBar)
            .statusBarHidden(fullscreen)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if hasChanges { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        do { try document.validate(); try onSave(document); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(document == original || draftWall != nil || firstPoint != nil || manipulation != nil || splittingCeiling != nil)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .onAppear { refreshPlanGeometry() }
            .onChange(of: document) { _,_ in refreshPlanGeometry() }
            .onChange(of: mode) { _,_ in selected=nil; selectedDoor=nil; snapResult=nil }
    }
    private var planForms: some View {
        planContent
            .sheet(isPresented: $showingProperties) {
                NavigationStack {
                    ScrollView { controls }
                        .navigationTitle("Dimensions").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fermer") { showingProperties=false } } }
                }.presentationDetents([.medium,.large])
            }
            .sheet(item:$contourRoute,onDismiss:{ confirmingContour = pendingContour != nil }) { route in
                LayoutManualContourEditor(surface:route.surface,title:"Contour de la pièce",allowsLayingOffset:false) { surface in
                    let points=surface.contour.map { RoomPoint(x:route.origin.x+$0.x/1000,y:route.origin.y,z:route.origin.z-$0.y/1000) }
                    do { pendingContour=try SurveyPlanEditing.replacingContour(document,walls:route.walls,contour:points) }
                    catch { self.error=error.localizedDescription }
                }
            }
            .confirmationDialog("Appliquer ce contour au relevé ?",isPresented:$confirmingContour,titleVisibility:.visible) {
                Button("Appliquer le contour") {
                    if let next=pendingContour { commitDocument(next); selected=nil; selectedDoor=nil; fittedPoints=nil }
                    pendingContour=nil
                }
                Button("Annuler",role:.cancel) { pendingContour=nil }
            } message: {
                let removed=max(0,document.room.openings.count-(pendingContour?.room.openings.count ?? document.room.openings.count))
                Text("\(removed) ouverture(s) ne peuvent pas être conservées sur le nouveau contour. Les plafonds et les ouvrages liés devront être vérifiés. Le scan d’origine reste conservé.")
            }
    }
    private var planPlacementDialogs: some View {
        planForms
            .confirmationDialog("Validez la position du point", isPresented: $confirmingPoint, titleVisibility:.visible) {
                Button("Valider et continuer") { acceptPoint(finish:false) }
                if firstPoint != nil { Button("Valider et terminer") { acceptPoint(finish:true) } }
                Button("Annuler",role:.cancel) { pendingPoint=nil; cursor=nil; snapResult=nil }
            }
            .confirmationDialog("Positionner cette porte ?",isPresented:$confirmingDoor,titleVisibility:.visible) {
                Button("Valider") { acceptDoor() }
                Button("Annuler",role:.cancel) { pendingDoorWall=nil; cursor=nil }
            }
            .confirmationDialog("Renseigner les doublages avant de tracer ?",isPresented:$needsLining,titleVisibility:.visible) {
                if onRequestLining != nil {
                    Button("Renseigner les doublages") {
                        do { if document != original { try onSave(document) }; onRequestLining?(); dismiss() }
                        catch { self.error=error.localizedDescription }
                    }
                }
                Button("Continuer sans doublage") { startTrace() }
                Button("Annuler",role:.cancel) { }
            } message: { Text("Les tapées définissent la position des faces finies. Sans ces données, les cotes sont prises sur les murs supports.") }
            .confirmationDialog("Diviser le plafond pour les nouvelles pièces ?",isPresented:$confirmingSplit,titleVisibility:.visible) {
                Button("Créer les deux sous-parties") { if let next=proposedSplit { commitDocument(next) }; proposedSplit=nil }
                Button("Conserver le plafond entier",role:.cancel) { proposedSplit=nil }
            } message: { Text("L’ouvrage est conservé. Ses calepinages seront répartis dans les deux sous-parties à l’enregistrement.") }
            .onChange(of: confirmingPoint) { _,visible in
                if !visible && proposedSplit != nil { confirmingSplit=true }
            }
    }
    private var planDialogs: some View {
        planPlacementDialogs
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
                        selectedDoor=nil; selected=nil; syncFields()
                    }
                }
            } message: { Text("Vous pourrez annuler ce geste avant d’enregistrer. Le scan d’origine reste conservé.") }
            .confirmationDialog("Supprimer cette cloison ?",isPresented:$deletingPartition,titleVisibility:.visible) {
                Button("Supprimer la cloison",role:.destructive) {
                    guard let id=selected else { return }
                    do {
                        commitDocument(try SurveyPlanEditing.removingPartition(document,id:id))
                        selected=nil; selectedDoor=nil; syncFields()
                    } catch { self.error=error.localizedDescription }
                }
                Button("Annuler",role:.cancel) { }
            } message: {
                let count=document.room.openings.filter { $0.wallID == selected }.count
                Text("La cloison et ses \(count) ouverture(s) seront retirées. Les plafonds ne seront pas fusionnés. Vous pourrez annuler ce geste avant d’enregistrer.")
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
                WallCeilingEstimateView(document: document, proposal: proposal,ceilingNumbers:ceilingNumbers,
                    appliesToPlan:true) { commitDocument($0) }
            }
            .sheet(isPresented:$choosingCeiling,onDismiss:{
                proposal = pendingCeiling; pendingCeiling = nil
                if let id = pendingCeilingSplit {
                    startCeilingCut(id); pendingCeilingSplit = nil
                }
            }) {
                CeilingZonePicker(room:document.room,choices:ceilingChoices,numbers:ceilingNumbers,onChoose:{ value in
                    pendingCeiling = value; choosingCeiling = false
                },onSplit:{ id in pendingCeilingSplit = id; choosingCeiling = false },
                onMerge:{ a,b in
                    commitDocument(try CeilingZoneEditing.merge(document,first:a,second:b)); refreshCeilingChoices()
                },onToggleHidden:{
                    commitDocument(CeilingZoneEditing.togglingVisibility(document,ceilingID:$0)); refreshCeilingChoices()
                })
            }
    }

    private var ceilingMenu: some View {
        Button { prepareCeiling() } label: { Label("Plafonds",systemImage:"square.3.layers.3d") }
            .disabled(drawingPartition || draftWall != nil || manipulation != nil || splittingCeiling != nil)
    }
    private func roundPlanButton(_ title:String,symbol:String,active:Bool = true,destructive:Bool = false,
                                 action:@escaping ()->Void) -> some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:19,weight:.medium))
                .foregroundStyle(destructive ? Color.red : active ? Color.accentColor : Color.secondary)
                .frame(width:44,height:44).background(.regularMaterial,in:Circle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    private var selectionActions: some View {
        HStack(spacing:8) {
            if mode != .view, mode != .openings || selectedDoor != nil,
               !drawingPartition, !placingDoor, splittingCeiling == nil, wall != nil {
                roundPlanButton("Modifier les dimensions de la sélection",symbol:"ruler") { showingProperties=true }
                if selectedDoor != nil {
                    roundPlanButton("Supprimer l’ouverture sélectionnée",symbol:"trash",destructive:true) { deletingOpening=true }
                } else if let wall, SurveyPlanEditing.isDesignedPartition(wall,in:document) {
                    roundPlanButton("Supprimer la cloison sélectionnée",symbol:"trash",destructive:true) { deletingPartition=true }
                }
            }
        }.disabled(manipulation != nil)
    }
    private func undoPlanEdit() {
        guard let previous=history.popLast() else { return }
        document=previous.document; draftWall=previous.draftWall
        selected=previous.selected; selectedDoor=previous.selectedDoor
        firstPoint=previous.firstPoint; drawingPartition=previous.drawingPartition
        snapResult=nil; manipulation=nil; syncFields()
    }
    private var instructions: String {
        // Keep the instruction height unchanged when the confirmation appears.
        if splittingCeiling != nil { return "Posez le doigt, glissez à travers le plafond, puis relâchez. Deux doigts pour déplacer et zoomer." }
        if drawingPartition { return "Positionnez le curseur, puis levez le doigt pour valider le point. Deux doigts pour naviguer." }
        if mode == .partitions { return "Touchez une cloison pour la modifier ou la supprimer. Deux doigts pour naviguer." }
        if mode == .openings && !placingDoor { return "Touchez une ouverture pour la modifier ou la supprimer. Deux doigts pour naviguer." }
        return mode == .view ? "Glissez pour déplacer le plan. Pincez pour zoomer." : "Un doigt pour modifier · deux doigts pour déplacer et zoomer."
    }

    private var editorTools: some View {
        VStack(spacing: 10) {
            if mode == .partitions {
                HStack {
                    Menu {
                        ForEach([50.0,72.0,98.0],id:\.self) { width in
                            Button("\(Int(width)) mm") { thicknessMM=width }
                        }
                    } label: { Label("Épaisseur",systemImage:"rectangle.split.2x1") }
                    ZeroEmptyDecimalTextField(value:$thicknessMM).frame(width:55)
                    Text("mm").foregroundStyle(.secondary)
                    Spacer()
                    number("Hauteur",value:$height)
                }.disabled(drawingPartition)
                if drawingPartition {
                    HStack {
                        Button("Annuler le tracé",systemImage:"xmark",role:.destructive) { cancelTrace() }
                        Spacer()
                        if document != traceStart { Button("Terminer") { finishTrace() }.buttonStyle(.borderedProminent) }
                    }
                } else {
                    HStack {
                        Button("Tracer une cloison",systemImage:"plus") {
                            guard thicknessMM.isFinite, thicknessMM > 0, thicknessMM <= 1000,
                                  height.isFinite, height > 0 else { error="Renseignez une épaisseur et une hauteur positives."; return }
                            let supports=document.room.walls.filter { !SurveyPlanEditing.isDesignedPartition($0,in:document) }
                            if supports.contains(where:{ liningDepths[$0.id] == nil }) { needsLining=true } else { startTrace() }
                        }.buttonStyle(.borderedProminent)
                    }
                }
            } else if mode == .openings {
                HStack {
                    Menu {
                        ForEach(SurveyPlanEditing.doorWidths,id:\.self) { width in
                            Button("Porte \(Int((width*100).rounded())-10) cm · réservation \(Int((width*100).rounded())) cm") { doorWidth=width }
                        }
                    } label: { Label("Porte",systemImage:"door.left.hand.open") }
                    ZeroEmptyDecimalTextField(value:Binding(get:{ doorWidth*100 },set:{ doorWidth=$0/100 })).frame(width:55)
                    Text("cm réservés").font(.caption)
                    Spacer()
                    Button(placingDoor ? "Annuler" : "Placer") {
                        placingDoor.toggle(); cursor=nil; pendingDoorWall=nil
                    }.buttonStyle(.borderedProminent)
                }
            } else if mode == .dimensions {
                HStack {
                    Button("Cotes du mur",systemImage:"ruler") { showingProperties=true }.disabled(wall == nil)
                    Spacer()
                    Menu {
                        let rings=ScanEnclosedSpaces.wallsBySpace(in:document.room)
                        if rings.isEmpty {
                            Button("Redessiner le contour du relevé") { openContour(document.room.walls,redraw:true) }
                        } else {
                            ForEach(rings.indices,id:\.self) { index in
                                Button("Modifier / redessiner la zone \(index+1)") { openContour(rings[index],redraw:false) }
                            }
                        }
                    } label: { Label("Contour de la pièce",systemImage:"pencil.and.outline") }
                }
            } else {
                HStack {
                    ceilingMenu
                    Spacer()
                }.buttonStyle(.bordered)
            }
        }.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20)).padding(.horizontal).padding(.bottom,8)
    }
    private func refreshPlanGeometry() {
        finishedShell=SurveyPlanFinishes.finishedWalls(in:document,depths:liningDepths)
        zoneRings=SurveyPlanFinishes.zones(in:document,depths:liningDepths)
    }
    private func openContour(_ walls:[PlaquistoWall],redraw:Bool) {
        guard !walls.isEmpty else { return }
        let points=walls.map(\.start)
        let origin=RoomPoint(x:points.map(\.x).min() ?? 0,y:points[0].y,z:points.map(\.z).max() ?? 0)
        let surface=Surface2D(name:"Pièce",kind:.ceiling,
            contour:points.map { .init(x:($0.x-origin.x)*1000,y:(origin.z-$0.z)*1000) },provenance:"scan")
        contourRoute = .init(walls:walls,origin:origin,surface:redraw ? nil : surface)
    }
    private func startTrace() {
        traceStart=document; traceHistoryIndex=history.count
        drawingPartition=true; firstPoint=nil; cursor=nil; selected=nil; selectedDoor=nil; snapResult=nil
    }
    private func cancelTrace() {
        if let traceStart { document=traceStart }
        if history.count > traceHistoryIndex { history.removeLast(history.count-traceHistoryIndex) }
        traceStart=nil; drawingPartition=false; firstPoint=nil; pendingPoint=nil; cursor=nil; snapResult=nil
    }
    private func acceptPoint(finish: Bool) {
        guard let point=pendingPoint else { return }
        do {
            if let start=firstPoint {
                let next=try SurveyPlanEditing.addingPartition(document,start:start,end:point,height:height/100,thickness:thicknessMM/1000)
                commitDocument(next)
            }
            firstPoint=point; pendingPoint=nil; cursor=nil; snapResult=nil
            if finish { finishTrace() }
        } catch { self.error=error.localizedDescription; pendingPoint=nil; cursor=nil }
    }
    private func finishTrace() {
        if let before=traceStart {
            proposedSplit=try? WallCeilingEstimate.splitForNewPartition(before:before,after:document,depths:liningDepths)
            if history.count>traceHistoryIndex { history.removeLast(history.count-traceHistoryIndex) }
            if before != document { history.append(.init(document:before,draftWall:nil,selected:nil,selectedDoor:nil,firstPoint:nil,drawingPartition:false)) }
        }
        traceStart=nil; drawingPartition=false; firstPoint=nil; pendingPoint=nil; cursor=nil; snapResult=nil
        if !confirmingPoint { confirmingSplit=proposedSplit != nil }
    }
    private func placement(_ point:RoomPoint,tolerance:Double) {
        if drawingPartition {
            cursor=snappedPoint(point,anchor:firstPoint,tolerance:tolerance)
        } else if placingDoor {
            let candidates=document.room.walls.filter { SurveyPlanEditing.isDesignedPartition($0,in:document) }
            guard let support=candidates.min(by:{ distance(point,$0)<distance(point,$1) }),
                  distance(point,support)<tolerance, doorWidth.isFinite,doorWidth>0,
                  doorWidth<=support.length.effectiveValue else { pendingDoorWall=nil; cursor=point; return }
            let d=point-support.start
            pendingDoorPosition=min(support.length.effectiveValue-doorWidth,max(0,d.x*support.direction.x+d.z*support.direction.z-doorWidth/2))
            pendingDoorWall=support.id
            cursor=support.start+support.direction*(pendingDoorPosition+doorWidth/2)
        }
    }
    private func finishPlacement() {
        if drawingPartition, let cursor { pendingPoint=cursor; confirmingPoint=true }
        else if placingDoor, pendingDoorWall != nil { confirmingDoor=true }
    }
    private func acceptDoor() {
        guard let wallID=pendingDoorWall else { return }
        do {
            let next=try SurveyPlanEditing.addingDoor(document,wallID:wallID,width:doorWidth,height:doorHeight/100,position:pendingDoorPosition)
            commitDocument(next); selected=wallID; selectedDoor=next.room.openings.last?.id
            placingDoor=false; pendingDoorWall=nil; cursor=nil; syncFields()
        } catch { self.error=error.localizedDescription }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let draftWall {
                HStack {
                    number("Longueur du tracé",value:$length)
                    number("Hauteur",value:$height)
                    Button("Ajuster") { resizeSelectedWall() }
                }
                Button(fixedStart ? "Départ fixe · inverser" : "Arrivée fixe · inverser",systemImage:"arrow.left.arrow.right") { fixedStart.toggle() }
                    .font(.caption)
                Button("Ajouter la cloison",systemImage:"plus") {
                    do {
                        let a = fixedStart ? draftWall.start : draftWall.effectiveEnd-draftWall.direction*(length/100)
                        let b = fixedStart ? draftWall.start+draftWall.direction*(length/100) : draftWall.effectiveEnd
                        let next = try SurveyPlanEditing.addingPartition(document,start:a,end:b,height:height/100)
                        commitDocument(next); self.draftWall=nil; selected=next.room.walls.last?.id; snapResult=nil; syncFields()
                    } catch { self.error=error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            } else if let opening=document.room.openings.first(where: { $0.id==selectedDoor }) {
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
                    number("Longueur du tracé", value: $length)
                    number("Hauteur maxi", value: $height)
                    Button("Appliquer") { resizeSelectedWall() }
                }
                Button(fixedStart ? "Départ fixe · inverser" : "Arrivée fixe · inverser",systemImage:"arrow.left.arrow.right") { fixedStart.toggle() }.font(.caption)
                if SurveyPlanEditing.isDesignedPartition(wall,in:document) {
                    Text("Cloison ajoutée : les murs supports restent fixes.").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Correction du relevé : les murs raccordés suivent le sommet déplacé.").font(.caption2).foregroundStyle(.secondary)
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
                let candidates=document.room.walls.filter { mergeCandidateIDs.contains($0.id) }
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
        do { commitDocument(try action()); syncFields() } catch { self.error = error.localizedDescription }
    }
    private func commitDocument(_ next: PlaquistoRoomDocument) {
        guard next != document else { return }
        remember()
        document=next
    }
    private func remember() {
        history.append(.init(document:document,draftWall:draftWall,selected:selected,selectedDoor:selectedDoor,
            firstPoint:firstPoint,drawingPartition:drawingPartition))
        if history.count > 30 { history.removeFirst() }
    }
    private func resizeSelectedWall() {
        guard let wall else { return }
        let a = fixedStart ? wall.start : wall.effectiveEnd-wall.direction*(length/100)
        let b = fixedStart ? wall.start+wall.direction*(length/100) : wall.effectiveEnd
        do {
            if draftWall != nil {
                let next=try SurveyPlanEditing.addingPartition(document,start:a,end:b,height:height/100)
                remember()
                draftWall=next.room.walls.last
            } else {
                commitDocument(try SurveyPlanEditing.changingWall(document,id:wall.id,start:a,end:b,height:height/100,preserveOpeningLocations:true))
            }
            syncFields()
        } catch { self.error=error.localizedDescription }
    }
    private func syncFields() {
        // Merge validation can be expensive on a large scan. Recompute only
        // after selection/commit, never for every finger-movement preview.
        if let wall, draftWall == nil {
            mergeCandidateIDs = Set(document.room.walls.filter {
                $0.id != wall.id && (try? SurveyPlanEditing.mergingWalls(document,first:wall.id,second:$0.id)) != nil
            }.map(\.id))
        } else { mergeCandidateIDs=[] }
        if let wall { length = wall.length.effectiveValue*100; height = wall.height.effectiveValue*100 }
        if let opening=document.room.openings.first(where:{ $0.id==selectedDoor }) {
            openingWidth=opening.width.effectiveValue*100
            openingHeight=opening.height.effectiveValue*100
            openingSill=opening.sillHeight.effectiveValue*100
            openingPosition=opening.positionOnWall.effectiveValue*100
        }
    }
    private func prepareCeiling() {
        if initiallyConfigureCeilings {
            cancelCeilingCut()
            return
        }
        do {
            ceilingChoices = try WallCeilingEstimate.manualProposals(in: document.room)
            pendingCeiling = nil
            pendingCeilingSplit = nil
            choosingCeiling = true
        } catch { self.error = error.localizedDescription }
    }
    private func refreshCeilingChoices() {
        do { ceilingChoices = try WallCeilingEstimate.manualProposals(in: document.room) }
        catch { self.error = error.localizedDescription }
    }
    private func startCeilingCut(_ id: UUID) {
        ceilingCut.reset(); splittingCeiling = id; showingCeilingSplitPlan = true
        drawingPartition = false; placingDoor = false; firstPoint = nil
        selected = nil; selectedDoor = nil; cursor = nil; snapResult = nil
        manipulation = nil; mode = .view
    }
    private func cancelCeilingCut() {
        ceilingCut.reset(); splittingCeiling = nil; firstPoint = nil
        showingCeilingSplitPlan = false
    }
    private func acceptCeilingCut() {
        guard let next = ceilingCut.accept() else { return }
        commitDocument(next)
        cancelCeilingCut()
    }
    private func tap(_ p: RoomPoint, tolerance: Double, scale: Double) {
        guard splittingCeiling == nil else { return }
        if drawingPartition {
            let p = snappedPoint(p,anchor:firstPoint,tolerance:min(0.15,tolerance))
            if let firstPoint {
                do {
                    let next = try SurveyPlanEditing.addingPartition(document, start: firstPoint, end: p,
                        height: SurveyPlanEditing.suggestedHeight(in: document.room, at: firstPoint))
                    remember()
                    draftWall = next.room.walls.last; selectedDoor = nil; fixedStart=true
                    drawingPartition = false; self.firstPoint = nil; syncFields()
                } catch { self.error = error.localizedDescription }
            } else { firstPoint = p }
            return
        }
        guard draftWall == nil else { return }
        if let wall, (centerHandle(wall,scale:scale)-p).horizontalLength < 22/scale { return }
        if mode != .partitions, let opening = opening(at:p,tolerance:tolerance) {
            selectedDoor = opening.id; selected = opening.wallID; syncFields(); return
        }
        selectedDoor = nil
        if mode == .openings { selected=nil; syncFields(); return }
        let candidates=document.room.walls.filter { mode != .partitions || SurveyPlanEditing.isDesignedPartition($0,in:document) }
        selected = candidates.min(by: { distance(p, $0) < distance(p, $1) }).flatMap {
            distance(p, $0) < tolerance ? $0.id : nil
        }
        syncFields()
    }
    private func opening(at point:RoomPoint,tolerance:Double) -> PlaquistoOpening? {
        document.room.openings.compactMap { opening -> (PlaquistoOpening,Double)? in
            guard let wall=document.room.walls.first(where: { $0.id == opening.wallID }) else { return nil }
            let start=wall.start+wall.direction*opening.positionOnWall.effectiveValue
            let delta=point-start
            let along=min(opening.width.effectiveValue,max(0,delta.x*wall.direction.x+delta.z*wall.direction.z))
            let gap=(point-(start+wall.direction*along)).horizontalLength
            return gap<tolerance ? (opening,gap) : nil
        }.min { $0.1<$1.1 }?.0
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
    private func adoptSnap(_ result: SurveyPlanSnapping.Result) {
        if result.key != nil && result.key != snapResult?.key { UISelectionFeedbackGenerator().selectionChanged() }
        snapResult = result.key == nil ? nil : result
    }
    private func snappedPoint(_ p: RoomPoint, anchor: RoomPoint?, tolerance: Double) -> RoomPoint {
        let supports=finishedShell.isEmpty ? document.room.walls : finishedShell + document.room.walls.filter { SurveyPlanEditing.isDesignedPartition($0,in:document) }
        let result = snapping ? SurveyPlanSnapping.snap(p,anchor:anchor,
            walls:(drawingPartition ? supports : document.room.walls).filter { $0.id != wall?.id },tolerance:tolerance,latched:snapResult?.key)
            : .init(point:p)
        adoptSnap(result)
        return result.point
    }
    private func centerHandle(_ wall: PlaquistoWall, scale: Double) -> RoomPoint {
        (wall.start+wall.effectiveEnd)*0.5 + RoomPoint(x:-wall.direction.z,y:0,z:wall.direction.x)*(28/scale)
    }
    private func beginManipulation(at point: RoomPoint, tolerance: Double, scale: Double) {
        guard splittingCeiling == nil, !drawingPartition, !placingDoor, mode != .view, let wall else { return }
        if mode == .partitions && !SurveyPlanEditing.isDesignedPartition(wall,in:document) { return }
        if mode == .openings && selectedDoor == nil { return }
        let door=document.room.openings.first { $0.id == selectedDoor }
        let handle: SurveyPlanManipulation.Handle
        if let door, opening(at:point,tolerance:tolerance)?.id == door.id { handle = .door }
        else if mode == .openings { return }
        else if (centerHandle(wall,scale:scale)-point).horizontalLength < tolerance { handle = .body }
        else {
            let a=(wall.start-point).horizontalLength, b=(wall.effectiveEnd-point).horizontalLength
            if min(a,b) < tolerance { handle = a <= b ? .start : .end }
            else if distance(point,wall) < tolerance { handle = .body }
            else { return }
        }
        manipulation = .init(handle:handle,wall:wall,touch:point,door:door,
            start:wall.start,end:wall.effectiveEnd,doorPosition:door?.positionOnWall.effectiveValue)
    }
    private func updateManipulation(to point: RoomPoint, tolerance: Double) {
        guard var move=manipulation else { return }
        let delta=point-move.touch, original=move.wall
        switch move.handle {
        case .start:
            move.start=snappedPoint(original.start+delta,anchor:original.effectiveEnd,tolerance:tolerance)
        case .end:
            move.end=snappedPoint(original.effectiveEnd+delta,anchor:original.start,tolerance:tolerance)
        case .body:
            var correction=RoomPoint.zero
            if snapping {
                let targets=document.room.walls.filter { $0.id != original.id }
                let starts=[original.start+delta,original.effectiveEnd+delta]
                let choices=starts.map { p in
                    (source:p,result:SurveyPlanSnapping.snap(p,walls:targets,tolerance:tolerance,latched:snapResult?.key))
                }.filter { $0.result.key != nil }
                if let best=choices.min(by:{ ($0.result.point-$0.source).length < ($1.result.point-$1.source).length }) {
                    correction=best.result.point-best.source; adoptSnap(best.result)
                } else { snapResult=nil }
            }
            move.start=original.start+delta+correction; move.end=original.effectiveEnd+delta+correction
        case .door:
            if let door=move.door {
                move.doorPosition=min(max(0,original.length.effectiveValue-door.width.effectiveValue),
                    max(0,door.positionOnWall.effectiveValue+delta.x*original.direction.x+delta.z*original.direction.z))
            }
        }
        manipulation=move
    }
    private func finishManipulation() {
        guard let move=manipulation else { return }
        defer { manipulation=nil; snapResult=nil }
        if draftWall != nil {
            do {
                let next=try SurveyPlanEditing.addingPartition(document,start:move.start,end:move.end,height:move.wall.height.effectiveValue)
                if move.start != move.wall.start || move.end != move.wall.effectiveEnd { remember(); draftWall=next.room.walls.last }
                syncFields()
            } catch { self.error=error.localizedDescription }
            return
        }
        if move.handle == .door, let door=move.door, let position=move.doorPosition {
            guard abs(position-door.positionOnWall.effectiveValue) > 1e-6 else { return }
            edit { try SurveyPlanEditing.movingDoor(document,id:door.id,position:position) }
        } else {
            guard (move.start-move.wall.start).horizontalLength > 1e-6 ||
                    (move.end-move.wall.effectiveEnd).horizontalLength > 1e-6 else { return }
            edit { try SurveyPlanEditing.changingWall(document,id:move.wall.id,start:move.start,end:move.end,
                height:move.wall.height.effectiveValue,preserveOpeningLocations:move.preservesOpeningLocations) }
        }
    }
    private var previewWalls: [PlaquistoWall] {
        guard let manipulation else { return document.room.walls + (draftWall.map { [$0] } ?? []) }
        if draftWall != nil { return document.room.walls + [manipulation.preview] }
        return SurveyPlanEditing.previewWalls(document,wall:manipulation.wall,start:manipulation.start,end:manipulation.end)
    }
    private var plan: some View {
        GeometryReader { proxy in
            let points = fittedPoints ?? original.room.walls.flatMap { [$0.start, $0.effectiveEnd] }
            let displayWalls = previewWalls
            let ceilingRoom = ceilingCut.preview?.room ?? document.room
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 4
            let minZ = points.map(\.z).min() ?? 0, maxZ = points.map(\.z).max() ?? 4
            let fitSize=canvasFitSize ?? proxy.size
            let scale = max(1, min((fitSize.width-116)/max(1,maxX-minX), (fitSize.height-116)/max(1,maxZ-minZ))) * zoom * pinch
            let center = RoomPoint(x: (minX+maxX)/2, y: document.room.walls.first?.start.y ?? 0, z: (minZ+maxZ)/2)
            let rotatedPoints=points.map { SurveyPlanCamera.rotated($0,around:center,angle:viewRotation) }
            let halfWidth=rotatedPoints.map { abs($0.x-center.x) }.max() ?? 2
            let halfHeight=rotatedPoints.map { abs($0.z-center.z) }.max() ?? 2
            let limitX = max(0, proxy.size.width/2 + halfWidth*scale - 40)
            let limitY = max(0, proxy.size.height/2 + halfHeight*scale - 40)
            let baseDX = min(limitX, max(-limitX, offset.width))
            let baseDY = min(limitY, max(-limitY, offset.height))
            let dx = min(limitX, max(-limitX, baseDX + (panning && !cancelledByPinch ? planDrag.width : 0)))
            let dy = min(limitY, max(-limitY, baseDY + (panning && !cancelledByPinch ? planDrag.height : 0)))
            let screen: (RoomPoint) -> CGPoint = {
                let p=SurveyPlanCamera.rotated($0,around:center,angle:viewRotation)
                return .init(x:proxy.size.width/2+(p.x-center.x)*scale+dx,y:proxy.size.height/2+(p.z-center.z)*scale+dy)
            }
            let world: (CGPoint) -> RoomPoint = {
                let p=RoomPoint(x:($0.x-proxy.size.width/2-baseDX)/scale+center.x,
                    y:center.y,z:($0.y-proxy.size.height/2-baseDY)/scale+center.z)
                return SurveyPlanCamera.rotated(p,around:center,angle:-viewRotation)
            }
            Canvas { context, _ in
                var occupied:[CGRect]=[]
                for ceiling in ceilingRoom.ceilings where ceiling.isHidden != true || ceiling.id == splittingCeiling {
                    if let boundary=WallCeilingEstimate.footprint(of:ceiling,in:ceilingRoom),
                       let point=ArchitecturalPlanInk.interiorPoint(boundary) {
                        let label=CeilingPlanNaming.title(ceiling,in:ceilingRoom,numbers:ceilingNumbers)
                        let p=screen(point), width=CGFloat(label.count)*6+16
                        occupied.append(CGRect(x:p.x-width/2,y:p.y-14,width:width,height:28))
                    }
                }
                for ceiling in ceilingRoom.ceilings where ceiling.isHidden != true || ceiling.id == splittingCeiling {
                    let isFirstHalf = ceiling.id == splittingCeiling
                    let isSecondHalf = ceilingCut.preview != nil && !document.room.ceilings.contains { $0.id == ceiling.id }
                    let color: Color = isFirstHalf ? .orange : isSecondHalf ? .blue : .gray
                    for slope in ceilingRoom.slopes where ceiling.slopeIDs.contains(slope.id) {
                        var path=Path()
                        for boundary in slope.boundaries where !boundary.isEmpty {
                            path.move(to:screen(boundary[0]))
                            for p in boundary.dropFirst() { path.addLine(to:screen(p)) }
                            path.closeSubpath()
                        }
                        context.fill(path,with:.color(color.opacity(isFirstHalf || isSecondHalf ? 0.25 : 0.07)),style:.init(eoFill:true))
                        context.stroke(path,with:.color(isFirstHalf || isSecondHalf ? color : ArchitecturalPlanInk.wall.opacity(0.4)),lineWidth:isFirstHalf || isSecondHalf ? 2 : 1)
                    }
                    if let boundary=WallCeilingEstimate.footprint(of:ceiling,in:ceilingRoom),
                       let point=ArchitecturalPlanInk.interiorPoint(boundary) {
                        ArchitecturalPlanInk.ceilingLabel(context,title:CeilingPlanNaming.title(ceiling,in:ceilingRoom,numbers:ceilingNumbers),point:screen(point))
                    }
                }
                for wall in displayWalls {
                    let a = screen(wall.start), b = screen(wall.effectiveEnd)
                    var line = Path(); line.move(to: a); line.addLine(to: b)
                    let active = wall.id == selected || wall.id == draftWall?.id
                    let physicalWidth=SurveyPlanEditing.isDesignedPartition(wall,in:document) ? (wall.thickness?.effectiveValue ?? 0.072)*scale : 6
                    context.stroke(line, with: .color(active ? .orange : ArchitecturalPlanInk.wall), style: .init(lineWidth: max(3,physicalWidth), lineCap: .butt))
                    ArchitecturalPlanInk.dimension(context,a:a,b:b,meters:wall.length.effectiveValue,
                        center:screen(center),occupied:&occupied,important:active)
                    if active {
                        for p in [a,b] { context.fill(Path(ellipseIn: CGRect(x:p.x-7,y:p.y-7,width:14,height:14)),with:.color(.orange)) }
                        let handle=screen(centerHandle(wall,scale:scale)), mid=screen((wall.start+wall.effectiveEnd)*0.5)
                        var leader=Path(); leader.move(to:mid); leader.addLine(to:handle)
                        context.stroke(leader,with:.color(.orange.opacity(0.7)),lineWidth:1)
                        context.fill(Path(ellipseIn:CGRect(x:handle.x-10,y:handle.y-10,width:20,height:20)),with:.color(.orange))
                        context.draw(Text("✥").font(.system(size:14,weight:.bold)).foregroundColor(.black),at:handle)
                        for (point,name) in [(a,"Départ"),(b,"Arrivée")] {
                            context.draw(Text(name).font(.system(size:10,weight:.semibold)).foregroundColor(ArchitecturalPlanInk.wall),
                                at:CGPoint(x:point.x,y:point.y-19))
                        }
                    }
                }
                for face in finishedShell {
                    guard let depth=liningDepths[face.id],
                          let raw=document.room.walls.first(where:{$0.id==face.id}) else { continue }
                    let a=face.start, b=face.effectiveEnd
                    func onRaw(_ p:RoomPoint)->RoomPoint {
                        let d=p-raw.start; return raw.start+raw.direction*(d.x*raw.direction.x+d.z*raw.direction.z)
                    }
                    let ring=[onRaw(a),onRaw(b),b,a]
                    var band=Path(); band.move(to:screen(ring[0]))
                    for p in ring.dropFirst() { band.addLine(to:screen(p)) }; band.closeSubpath()
                    context.fill(band,with:.color(Color.accentColor.opacity(0.17)))
                    var edge=Path(); edge.move(to:screen(a)); edge.addLine(to:screen(b))
                    context.stroke(edge,with:.color(.accentColor),lineWidth:1.5)
                    let mid=(a+b)*0.5
                    if mode == .dimensions {
                        ArchitecturalPlanInk.dimension(context,a:screen(onRaw(mid)),b:screen(mid),meters:depth,
                            center:screen(center),occupied:&occupied,important:true)
                    }
                }
                for (index,ring) in zoneRings.enumerated() {
                    let boundary=ring.map(\.start)
                    if let center=ArchitecturalPlanInk.interiorPoint(boundary) {
                        let area=SurveyPlanFinishes.area(boundary)
                        let label="Zone \(index+1) · \(area.formatted(.number.precision(.fractionLength(1)))) m²"
                        let p=screen(center)
                        context.draw(Text(label).font(.system(size:12,weight:.semibold)).foregroundColor(ArchitecturalPlanInk.wall),
                            at:CGPoint(x:p.x,y:p.y+22))
                    }
                }
                for door in document.room.openings {
                    guard let wall = displayWalls.first(where: { $0.id == door.wallID }) else { continue }
                    var position = manipulation?.handle == .door && manipulation?.door?.id == door.id
                        ? manipulation?.doorPosition ?? door.positionOnWall.effectiveValue : door.positionOnWall.effectiveValue
                    if manipulation?.preservesOpeningLocations == true, manipulation?.wall.id == wall.id {
                        let delta = door.center-wall.start
                        position = delta.x*wall.direction.x+delta.z*wall.direction.z-door.width.effectiveValue/2
                    }
                    let a = wall.start+wall.direction*position
                    ArchitecturalPlanInk.opening(context,a:screen(a),b:screen(a+wall.direction*door.width.effectiveValue),
                        window:door.kind == .window || door.kind == .glazedBay,selected:door.id==selectedDoor)
                }
                if let start = ceilingCut.start, let end = ceilingCut.end {
                    let a = screen(start), b = screen(end)
                    var cut = Path(); cut.move(to: a); cut.addLine(to: b)
                    context.stroke(cut, with: .color(.orange), style: .init(lineWidth: 2.5, lineCap: .round, dash: [7, 5]))
                    for p in [a,b] {
                        context.fill(Path(ellipseIn: CGRect(x:p.x-5,y:p.y-5,width:10,height:10)), with: .color(.orange))
                    }
                    let distance = hypot(b.x-a.x, b.y-a.y)
                    if distance > 24 {
                        let count = max(1, min(5, Int(distance/80)))
                        for i in 0..<count {
                            let t = CGFloat(i+1)/CGFloat(count+1)
                            let p = CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
                            context.fill(Path(ellipseIn: CGRect(x:p.x-13,y:p.y-13,width:26,height:26)), with: .color(ArchitecturalPlanInk.paper))
                            var scissors = context.resolve(Image(systemName:"scissors"))
                            scissors.shading = .color(.orange)
                            context.draw(scissors, at:p)
                        }
                    }
                }
                if let firstPoint {
                    let p = screen(firstPoint)
                    context.fill(Path(ellipseIn: CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(.orange))
                }
                if let cursor {
                    let p=screen(cursor)
                    var cross=Path(); cross.move(to:.init(x:p.x-10,y:p.y)); cross.addLine(to:.init(x:p.x+10,y:p.y))
                    cross.move(to:.init(x:p.x,y:p.y-10)); cross.addLine(to:.init(x:p.x,y:p.y+10))
                    context.stroke(cross,with:.color(.orange),lineWidth:2)
                    if drawingPartition {
                        if let firstPoint {
                            var line=Path(); line.move(to:screen(firstPoint)); line.addLine(to:p)
                            context.stroke(line,with:.color(.orange.opacity(0.65)),style:.init(lineWidth:max(3,thicknessMM/1000*scale),dash:[8,3]))
                            ArchitecturalPlanInk.dimension(context,a:screen(firstPoint),b:p,meters:(cursor-firstPoint).horizontalLength,
                                center:screen(center),occupied:&occupied,important:true)
                        }
                        let anchor=firstPoint ?? cursor
                        if let support=finishedShell.min(by:{ distance(anchor,$0)<distance(anchor,$1) }),distance(anchor,support)<0.03 {
                            let direction=firstPoint.map { start -> RoomPoint in
                                let d=cursor-start, length=max(1e-9,d.horizontalLength); return d*(1/length)
                            }
                            let (left,right)=SurveyPlanFinishes.clearances(on:support,at:anchor,direction:direction,thickness:thicknessMM/1000)
                            ArchitecturalPlanInk.dimension(context,a:screen(support.start),b:screen(support.start+support.direction*left),meters:left,center:screen(center),occupied:&occupied,important:true)
                            ArchitecturalPlanInk.dimension(context,a:screen(support.effectiveEnd-support.direction*right),b:screen(support.effectiveEnd),meters:right,center:screen(center),occupied:&occupied,important:true)
                        }
                    } else if placingDoor, let support=document.room.walls.first(where:{$0.id==pendingDoorWall}) {
                        let a=support.start+support.direction*pendingDoorPosition, b=a+support.direction*doorWidth
                        var slot=Path(); slot.move(to:screen(a)); slot.addLine(to:screen(b))
                        context.stroke(slot,with:.color(.orange),lineWidth:9)
                        ArchitecturalPlanInk.dimension(context,a:screen(support.start),b:screen(a),meters:pendingDoorPosition,center:screen(center),occupied:&occupied,important:true)
                        ArchitecturalPlanInk.dimension(context,a:screen(b),b:screen(support.effectiveEnd),meters:support.length.effectiveValue-pendingDoorPosition-doorWidth,center:screen(center),occupied:&occupied,important:true)
                    }
                }
                if let snapResult {
                    if let guide=snapResult.guide {
                        var line=Path(); line.move(to:screen(guide)); line.addLine(to:screen(snapResult.point))
                        context.stroke(line,with:.color(.blue),style:.init(lineWidth:1.5,dash:[5,3]))
                    }
                    let point=screen(snapResult.point)
                    context.stroke(Path(ellipseIn:CGRect(x:point.x-11,y:point.y-11,width:22,height:22)),with:.color(.blue),lineWidth:2)
                    context.draw(Text(snapResult.title ?? "").font(.system(size:12,weight:.bold)).foregroundColor(.blue),
                        at:CGPoint(x:point.x,y:point.y-35))
                }
            }
            .contentShape(Rectangle())
            .background(ArchitecturalPlanInk.paper)
            .overlay {
                SurveyPlanGestureSurface(single: { phase,point,delta in
                    if phase == .cancelled || phase == .failed {
                        manipulation=nil; cursor=nil; snapResult=nil; ceilingCut.cancelGesture(); return
                    }
                    if let ceilingID = splittingCeiling {
                        if ceilingCut.preview != nil {
                            // Inspect the two halves without starting another cut.
                            offset = .init(width:min(limitX,max(-limitX,offset.width+delta.width)),
                                           height:min(limitY,max(-limitY,offset.height+delta.height)))
                            return
                        }
                        if phase == .began { ceilingCut.begin(at: world(point)) }
                        if phase == .changed { ceilingCut.move(to: world(point)) }
                        if phase == .ended {
                            // Commit the last displayed guide, not a new coordinate
                            // from the lifting finger (which can drift on touch-up).
                            do { try ceilingCut.finish(document:document,ceilingID:ceilingID,minimumLength:12/scale) }
                            catch { self.error = "Tracez une coupe traversant le plafond pour obtenir deux parties. Vous pouvez recommencer." }
                        }
                        return
                    }
                    if mode == .view && splittingCeiling == nil {
                        offset = .init(width:min(limitX,max(-limitX,offset.width+delta.width)),
                                       height:min(limitY,max(-limitY,offset.height+delta.height)))
                        return
                    }
                    if drawingPartition || placingDoor {
                        // Fixed screen-space separation remains legible at every zoom.
                        let target=CGPoint(x:max(12,min(proxy.size.width-12,point.x-64)),
                                           y:max(12,min(proxy.size.height-12,point.y-18)))
                        placement(world(target),tolerance:min(0.20,18/scale))
                        if phase == .ended { finishPlacement() }
                    } else {
                        if phase == .began { beginManipulation(at:world(point),tolerance:22/scale,scale:scale) }
                        if manipulation != nil {
                            updateManipulation(to:world(point),tolerance:min(0.15,12/scale))
                            if phase == .ended { finishManipulation() }
                        } else if phase == .ended { tap(world(point),tolerance:25/scale,scale:scale) }
                    }
                }, navigate: { delta,factor,anchor in
                    ceilingCut.cancelGesture()
                    manipulation=nil; cursor=nil; snapResult=nil
                    let next=min(8,max(0.5,zoom*factor)), ratio=next/zoom
                    let ax=anchor.x-proxy.size.width/2, ay=anchor.y-proxy.size.height/2
                    let lx=max(0,proxy.size.width/2+halfWidth*scale*ratio-40)
                    let ly=max(0,proxy.size.height/2+halfHeight*scale*ratio-40)
                    offset = .init(width:min(lx,max(-lx,ax-(ax-offset.width)*ratio+delta.width)),
                                   height:min(ly,max(-ly,ay-(ay-offset.height)*ratio+delta.height)))
                    zoom=next
                })
            }
            .transaction { $0.animation = nil }
            .onAppear {
                if canvasFitSize == nil, proxy.size.width>116, proxy.size.height>116 { canvasFitSize=proxy.size }
            }
            .onChange(of:proxy.size) { _,size in
                if canvasFitSize == nil, size.width>116, size.height>116 { canvasFitSize=size }
            }
            .onChange(of:recenterToken) { _,_ in canvasFitSize=proxy.size }
            .clipped()
        }
    }
}

/// UIKit owns touch arbitration so a second finger cancels placement before
/// panning/pinching. No delayed drag commits or competing SwiftUI gestures.
private struct SurveyPlanGestureSurface: UIViewRepresentable {
    var single: (UIGestureRecognizer.State,CGPoint,CGSize)->Void
    var navigate: (CGSize,Double,CGPoint)->Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> UIView {
        let view=UIView(); view.backgroundColor = .clear; view.isMultipleTouchEnabled=true
        let one=SurveyPlanContactRecognizer(target:context.coordinator,action:#selector(Coordinator.one(_:)))
        one.minimumPressDuration=0; one.allowableMovement = .greatestFiniteMagnitude
        let pan=UIPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches=2; pan.maximumNumberOfTouches=2
        let pinch=UIPinchGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pinch(_:)))
        for gesture in [one,pan,pinch] { gesture.delegate=context.coordinator; view.addGestureRecognizer(gesture) }
        return view
    }
    func updateUIView(_ view:UIView,context:Context) { context.coordinator.parent=self }
    final class Coordinator:NSObject,UIGestureRecognizerDelegate {
        var parent:SurveyPlanGestureSurface
        var last=CGPoint.zero
        var cancelled=false
        init(_ parent:SurveyPlanGestureSurface) { self.parent=parent }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool { true }
        private func cancelSingle() {
            if !cancelled { cancelled=true; parent.single(.cancelled,last,.zero) }
        }
        @objc func one(_ gesture:SurveyPlanContactRecognizer) {
            let p=gesture.location(in:gesture.view)
            if gesture.numberOfTouches>1 { cancelSingle(); return }
            if gesture.state == .began {
                cancelled=false; last=gesture.initialPoint ?? p
                parent.single(.began,last,.zero)
                if last != p {
                    parent.single(.changed,p,.init(width:p.x-last.x,height:p.y-last.y))
                    last=p
                }
                return
            }
            guard !cancelled else { return }
            let delta=CGSize(width:p.x-last.x,height:p.y-last.y); last=p
            parent.single(gesture.state,p,delta)
        }
        @objc func pan(_ gesture:UIPanGestureRecognizer) {
            cancelSingle()
            let delta=gesture.translation(in:gesture.view); gesture.setTranslation(.zero,in:gesture.view)
            parent.navigate(.init(width:delta.x,height:delta.y),1,gesture.location(in:gesture.view))
        }
        @objc func pinch(_ gesture:UIPinchGestureRecognizer) {
            cancelSingle()
            let factor=gesture.scale; gesture.scale=1
            parent.navigate(.zero,factor,gesture.location(in:gesture.view))
        }
    }
}

/// Keep the physical touch-down point even when recognition is delivered after
/// the first movement (a zero-duration long press still runs on the next event).
private final class SurveyPlanContactRecognizer: UILongPressGestureRecognizer {
    private(set) var initialPoint: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if initialPoint == nil { initialPoint=touches.first?.location(in:view) }
        super.touchesBegan(touches,with:event)
    }
    override func reset() { super.reset(); initialPoint=nil }
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
    static let paper=Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.11,green:0.12,blue:0.13,alpha:1)
            : UIColor(red:0.975,green:0.97,blue:0.95,alpha:1)
    })
    static let wall=Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.85,green:0.86,blue:0.88,alpha:1)
            : UIColor(red:0.22,green:0.24,blue:0.28,alpha:1)
    })
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

extension RoomPoint {
    var horizontalLength: Double { hypot(x,z) }
}

/// Show the footprint in the context of the whole plan before editing its height.
/// No semantic room names are invented when the scan contains one open space.
struct CeilingZonePicker: View {
    @Environment(\.dismiss) private var dismiss
    let room: PlaquistoRoomModel
    let choices: [WallCeilingEstimate.Proposal]
    var numbers: [String:Int] = [:]
    let onChoose: (WallCeilingEstimate.Proposal) -> Void
    let onSplit: (UUID) -> Void
    let onMerge: (UUID, UUID) throws -> Void
    let onToggleHidden: (UUID) -> Void
    @State private var mergePair: [UUID] = []
    @State private var mergeError: String?
    var onClose: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var canSave = true
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choisissez la zone sur laquelle travailler. Chaque plafond conserve sa forme et ses hauteurs.")
                }
                Section("Ajouter un plafond") {
                    let vacant = choices.filter { $0.ceilingID == nil }
                    ForEach(vacant) { choice in
                        row(choice,title:"Créer un plafond",detail:"Dans la zone en orange")
                    }
                    if vacant.isEmpty {
                        Text("Les zones fermées ont déjà un plafond. Pour séparer une cuisine ouverte et un salon, utilisez « Découper » ci-dessous.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Modifier un plafond") {
                    ForEach(choices.filter { $0.ceilingID != nil }) { choice in
                        if let ceiling = room.ceilings.first(where:{ $0.id == choice.ceilingID }) {
                            VStack(alignment:.leading,spacing:12) {
                                row(choice,title:CeilingPlanNaming.title(ceiling,in:room,numbers:numbers),
                                    detail:ceiling.isHidden == true ? "Masqué · conservé dans le relevé" : ceiling.estimateSettings?.shape.title ?? "Modifier la forme et les hauteurs")
                                HStack(spacing:18) {
                                    Button { onSplit(ceiling.id) } label: { Label("Découper",systemImage:"scissors") }
                                        .disabled(ceiling.isHidden == true)
                                    Menu {
                                        let neighbours=room.ceilings.filter { other in
                                            guard other.id != ceiling.id,
                                                  let a=WallCeilingEstimate.footprint(of:ceiling,in:room),
                                                  let b=WallCeilingEstimate.footprint(of:other,in:room) else { return false }
                                            return CeilingZoneEditing.joinedBoundary(a,b) != nil
                                        }
                                        if neighbours.isEmpty { Text("Aucun plafond adjacent") }
                                        ForEach(neighbours) { other in
                                            Button(CeilingPlanNaming.title(other,in:room,numbers:numbers)) { mergePair=[ceiling.id,other.id] }
                                        }
                                    } label: { Label("Fusionner",systemImage:"square.on.square") }
                                    Button { onToggleHidden(ceiling.id) } label: {
                                        Label(ceiling.isHidden == true ? "Afficher" : "Masquer",systemImage:ceiling.isHidden == true ? "eye" : "eye.slash")
                                    }
                                }.font(.caption).buttonStyle(.borderless)
                            }
                        }
                    }
                    Text("Cuisine ouverte et salon : séparez leur plafond en traçant une limite entre les deux espaces.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choisir un plafond").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Fusionner ces deux plafonds ?",isPresented:Binding(get:{ mergePair.count == 2 },set:{ if !$0 { mergePair=[] } }),titleVisibility:.visible) {
                Button("Fusionner") {
                    guard mergePair.count == 2 else { return }
                    do { try onMerge(mergePair[0],mergePair[1]) } catch { mergeError=error.localizedDescription }
                    mergePair=[]
                }
                Button("Annuler",role:.cancel) { mergePair=[] }
            } message: { Text("Les pans, leurs pentes et les calepinages existants sont conservés. Enregistrez les plafonds pour appliquer la fusion.") }
            .alert("Fusion impossible",isPresented:Binding(get:{ mergeError != nil },set:{ if !$0 { mergeError=nil } })) {
                Button("OK") { mergeError=nil }
            } message: { Text(mergeError ?? "") }
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Fermer") {
                    if let onClose { onClose() } else { dismiss() }
                } }
                if let onSave {
                    ToolbarItem(placement:.confirmationAction) {
                        Button(action:onSave) { Image(systemName:"checkmark") }
                            .accessibilityLabel("Enregistrer les plafonds").disabled(!canSave)
                    }
                }
            }
        }
    }
    private func row(_ choice: WallCeilingEstimate.Proposal, title: String, detail: String) -> some View {
        Button { onChoose(choice) } label: {
            HStack(spacing:14) {
                Canvas { context, size in
                    let points = room.walls.flatMap { [$0.start,$0.effectiveEnd] }+choice.boundary
                    let x0 = points.map(\.x).min() ?? 0, z0 = points.map(\.z).min() ?? 0
                    let w = max(0.1,(points.map(\.x).max() ?? 1)-x0)
                    let h = max(0.1,(points.map(\.z).max() ?? 1)-z0)
                    let scale = min((size.width-12)/w,(size.height-12)/h)
                    func p(_ v:RoomPoint) -> CGPoint {
                        .init(x:(v.x-x0-w/2)*scale+size.width/2,y:(v.z-z0-h/2)*scale+size.height/2)
                    }
                    var zone = Path()
                    zone.addLines(choice.boundary.map(p)); zone.closeSubpath()
                    context.fill(zone,with:.color(.orange.opacity(0.35)))
                    context.stroke(zone,with:.color(.orange),lineWidth:2)
                    for wall in room.walls {
                        var line = Path(); line.move(to:p(wall.start)); line.addLine(to:p(wall.effectiveEnd))
                        context.stroke(line,with:.color(.primary.opacity(0.65)),lineWidth:1.5)
                    }
                }.frame(width:100,height:78).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Image(systemName:"chevron.right").font(.caption)
            }.padding(.vertical,4)
        }.buttonStyle(.plain)
    }
}

struct WallCeilingEstimateView: View {
    @Environment(\.dismiss) private var dismiss
    let document: PlaquistoRoomDocument
    @State private var proposal: WallCeilingEstimate.Proposal
    private let originalBoundary: [RoomPoint]
    private let unchangedInput: CeilingEstimateSettings
    private var fitting: CeilingAutoFit { CeilingAutoFit(room: document.room, proposal: proposal) }
    private let title: String
    private let appliesToPlan: Bool
    let onSave: (PlaquistoRoomDocument) throws -> Void
    @State private var settings: CeilingEstimateSettings
    @State private var lowText: String
    @State private var highText: String
    @State private var selected: UUID?
    @State private var error: String?
    @State private var topView = false
    @State private var cameraReset = UUID()
    @State private var estimatedRise: Bool
    @State private var previousSettings: SettingsSnapshot?
    @State private var draftsByShape: [CeilingEstimateSettings.Shape:SettingsSnapshot] = [:]
    private struct SettingsSnapshot: Equatable {
        let settings: CeilingEstimateSettings
        let low: String
        let high: String
        let estimatedRise: Bool
    }

    init(document: PlaquistoRoomDocument, proposal: WallCeilingEstimate.Proposal,
         ceilingNumbers:[String:Int] = [:], appliesToPlan:Bool = false,
         onSave: @escaping (PlaquistoRoomDocument) throws -> Void) {
        self.document = document; _proposal = State(initialValue: proposal); self.onSave = onSave
        originalBoundary = proposal.boundary
        self.appliesToPlan = appliesToPlan
        let target = proposal.ceilingID.flatMap { id in document.room.ceilings.first { $0.id == id } }
        title = target.map { CeilingPlanNaming.title($0,in:document.room,numbers:ceilingNumbers) } ?? "Nouveau plafond"
        let fitting = CeilingAutoFit(room:document.room,proposal:proposal)
        let suggestion = fitting.suggest(shape:.flat)
        let settings = target?.estimateSettings ?? suggestion.settings
        _estimatedRise = State(initialValue:settings.riseIsEstimated == true)
        var rounded=settings
        rounded.lowHeight=(settings.lowHeight*100).rounded()/100
        rounded.highHeight=settings.shape == .flat ? rounded.lowHeight : (settings.highHeight*100).rounded()/100
        unchangedInput=rounded
        _settings = State(initialValue: settings)
        _lowText = State(initialValue: settings.lowHeight.formatted(.number.precision(.fractionLength(2))))
        _highText = State(initialValue: settings.highHeight.formatted(.number.precision(.fractionLength(2))))
    }
    private var snapshot: SettingsSnapshot {
        .init(settings:settings,low:lowText,high:highText,estimatedRise:estimatedRise)
    }
    private func restore(_ value: SettingsSnapshot) {
        settings = value.settings; lowText = value.low; highText = value.high
        estimatedRise = value.estimatedRise
    }
    private func changeShape(to shape: CeilingEstimateSettings.Shape) {
        guard shape != settings.shape else { return }
        draftsByShape[settings.shape] = snapshot
        if let saved = draftsByShape[shape] {
            previousSettings = snapshot
            restore(saved)
        } else { adjust(to:shape) }
    }
    private func adjust(to shape: CeilingEstimateSettings.Shape) {
        let result = fitting.suggest(shape:shape,current:input)
        let next = SettingsSnapshot(settings:result.settings,
            low:result.settings.lowHeight.formatted(.number.precision(.fractionLength(2))),
            high:result.settings.highHeight.formatted(.number.precision(.fractionLength(2))),
            estimatedRise:result.estimatedRise)
        guard next != snapshot else { return }
        previousSettings = snapshot
        restore(next)
    }
    private func undoAdjustment() {
        guard let previousSettings else { return }
        draftsByShape[settings.shape] = snapshot
        restore(previousSettings)
        self.previousSettings = nil
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
        if proposal.ceilingID != nil, input == unchangedInput, proposal.boundary == originalBoundary {
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
                            Picker("Forme",selection:Binding(get:{ settings.shape },set:{ changeShape(to:$0) })) {
                                ForEach(CeilingEstimateSettings.Shape.allCases) { shape in
                                    Text(shape.title).tag(shape)
                                }
                            }
                            heightSlider(settings.shape == .flat ? "Hauteur sous plafond" : "Hauteur minimale",isLow:true)
                            if settings.shape != .flat { heightSlider("Hauteur maximale",isLow:false) }
                            DisclosureGroup("Saisie précise des hauteurs") {
                                heightField(settings.shape == .flat ? "Hauteur sous plafond" : "Hauteur minimale",text:$lowText)
                                if settings.shape != .flat { heightField("Hauteur maximale",text:$highText) }
                            }
                            Button("Ajuster aux murs",systemImage:"wand.and.stars") { adjust(to:settings.shape) }
                                .accessibilityIdentifier("ceiling.fitWalls")
                            if previousSettings != nil {
                                Button("Annuler l’ajustement",systemImage:"arrow.uturn.backward") { undoAdjustment() }
                            }
                            if estimatedRise {
                                Text("La pente ne peut pas être déduite des murs. Une forme de départ est proposée : ajustez la hauteur maximale et l’orientation.")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            if fitting.coverage < 0.75 {
                                Text("Une partie des bords n’a pas de profil de mur exploitable. Vérifiez les hauteurs de cette zone.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if settings.shape != .flat {
                            Section("Réglage des pans") {
                                VStack(alignment:.leading,spacing:8) {
                                    LabeledContent("Orientation",value:"\((settings.azimuth*180/Double.pi).formatted(.number.precision(.fractionLength(0))))°")
                                    Slider(value:$settings.azimuth,in:(-Double.pi)...Double.pi)
                                        .accessibilityLabel("Orientation des pans")
                                        .accessibilityValue("\((settings.azimuth*180/Double.pi).formatted(.number.precision(.fractionLength(0)))) degrés")
                                    Button("Tourner de 90°",systemImage:"rotate.right") {
                                        let angle = settings.azimuth+Double.pi/2
                                        settings.azimuth = atan2(sin(angle),cos(angle))
                                    }.font(.subheadline)
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
                            if appliesToPlan {
                                Text("Appliquez ce plafond, puis enregistrez le plan pour conserver vos modifications.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
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
            .onChange(of:proposal.boundary) { _, _ in refreshPreview() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button(appliesToPlan ? "Appliquer" : "Enregistrer") {
                        do {
                            guard input != nil, let previewDocument, previewIssue == nil else { throw WallCeilingEstimate.Failure.invalidHeight }
                            try onSave(previewDocument)
                            dismiss()
                        } catch { self.error=error.localizedDescription }
                    }.disabled(input == nil || previewDocument == nil || previewIssue != nil)
                        .accessibilityLabel(appliesToPlan ? "Appliquer au plan" : "Enregistrer le plafond")
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
                    RoomDomainScene(room:previewDocument.room,selected:.constant(selected),ceilingMode:2,
                        showFloor:true,topView:topView,cameraReset:cameraReset,
                        ceilingGaps:input.map { fitting.gaps(settings:$0) } ?? [])
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
            if previewIssue == nil, let input, let gap = fitting.gaps(settings:input).first {
                Text("Repères orange : écart avec les murs jusqu’à \((abs(gap.wall.y-gap.ceiling.y)*100).formatted(.number.precision(.fractionLength(0)))) cm")
                    .font(.caption).foregroundStyle(.orange)
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
    private func heightSlider(_ title:String,isLow:Bool) -> some View {
        let low=Double(lowText.replacingOccurrences(of:",",with:".")) ?? settings.lowHeight
        let high=Double(highText.replacingOccurrences(of:",",with:".")) ?? settings.highHeight
        // Stable range while dragging. Taller existing roofs retain their full editable range.
        let upper=max(5,ceil(max(unchangedInput.lowHeight,unchangedInput.highHeight)+1))
        let value=Binding<Double>(get:{ min(upper,max(0.1,isLow ? low : high)) },set:{ next in
            let formatted=next.formatted(.number.precision(.fractionLength(2)))
            if isLow {
                lowText=formatted
                if high < next { highText=formatted }
            } else {
                highText=formatted
                if low > next { lowText=formatted }
            }
            estimatedRise=false
        })
        return VStack(alignment:.leading,spacing:8) {
            LabeledContent(title,value:"\((isLow ? low : high).formatted(.number.precision(.fractionLength(2)))) m")
                .monospacedDigit()
            Slider(value:value,in:0.1...upper,step:0.01)
                .accessibilityLabel(title).accessibilityIdentifier(isLow ? "ceiling.height.low" : "ceiling.height.high")
        }
    }
}

struct RoomDomainScene: UIViewRepresentable {
    @AppStorage(MaquetteRendering.preferenceKey) private var rendering = MaquetteRendering.elevated.rawValue
    @Environment(\.colorScheme) private var colorScheme
    let room: PlaquistoRoomModel
    @Binding var selected: UUID?
    let ceilingMode: Int
    let showFloor: Bool
    let topView: Bool
    let cameraReset: UUID
    var ceilingGaps: [CeilingAutoFit.Gap] = []
    var repairTriangles: [RoomPoint] = []
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> SCNView {
        let view=UprightSurveySceneView(); view.scene=SCNScene()
        MaquetteStyle.configure(view,quality:.current)
        view.allowsCameraControl=true
        view.addGestureRecognizer(UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view:SCNView,context:Context) {
        _ = rendering
        update(view,coordinator:context.coordinator)
        MaquetteStyle.updateBackground(view, dark: colorScheme == .dark)
    }
    func update(_ view:SCNView,coordinator:Coordinator) {
        let previous=coordinator.parent
        let reset=view.pointOfView == nil || coordinator.roomID != room.id || previous.topView != topView || previous.cameraReset != cameraReset
        let rebuild=coordinator.lastRoom != room
        let rebuildShell = coordinator.content == nil || coordinator.lastRoom?.id != room.id ||
            coordinator.lastRoom?.walls != room.walls || coordinator.lastRoom?.openings != room.openings ||
            coordinator.lastRoom?.floors != room.floors
        coordinator.parent=self
        coordinator.lastRoom=room
        let root=view.scene!.rootNode
        if previous.repairTriangles != repairTriangles || rebuild {
            root.childNode(withName:"repair-preview",recursively:false)?.removeFromParentNode()
            if !repairTriangles.isEmpty {
                let geometry=MaquetteStyle.geometry(repairTriangles)
                let material=SCNMaterial()
                material.diffuse.contents=UIColor.systemOrange.withAlphaComponent(0.8)
                material.lightingModel = .constant; material.isDoubleSided=true
                material.readsFromDepthBuffer=false; material.writesToDepthBuffer=false
                geometry.materials=[material]
                let node=SCNNode(geometry:geometry); node.name="repair-preview"
                node.categoryBitMask=2; node.renderingOrder=40
                root.addChildNode(node)
            }
        }
        if previous.ceilingGaps != ceilingGaps || rebuild {
            root.childNode(withName:"ceiling-fit-gaps",recursively:false)?.removeFromParentNode()
            if !ceilingGaps.isEmpty {
                let vertices = ceilingGaps.flatMap { [$0.wall,$0.ceiling] }
                    .map { SCNVector3(Float($0.x),Float($0.y),Float($0.z)) }
                let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],
                    elements:[SCNGeometryElement(indices:Array(0..<Int32(vertices.count)),primitiveType:.line)])
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemOrange; material.lightingModel = .constant
                material.readsFromDepthBuffer = false; material.writesToDepthBuffer = false
                geometry.materials = [material]
                let node = SCNNode(geometry:geometry); node.name = "ceiling-fit-gaps"
                node.categoryBitMask = 2; node.renderingOrder = 30
                root.addChildNode(node)
            }
        }
        let quality=MaquetteStyle.Quality.current
        if coordinator.quality != quality || coordinator.rendering != MaquetteRendering.current {
            coordinator.quality=quality
            coordinator.rendering=MaquetteRendering.current
            MaquetteStyle.configure(view,quality:quality)
            MaquetteStyle.installStudio(in:view.scene!,quality:quality)
            if let camera=view.pointOfView?.camera { MaquetteStyle.configure(camera,quality:quality) }
        }
        view.defaultCameraController.interactionMode = topView ? .pan : .orbitTurntable
        if rebuild {
            coordinator.geometryBuildCount += 1
            if rebuildShell {
                coordinator.content?.removeFromParentNode()
                let content=SCNNode(); content.name="room-content"; root.addChildNode(content)
                coordinator.content=content
                coordinator.walls=[]; coordinator.floors=[]
            } else {
                // Height/orientation sliders rebuild only the roofs, not the scanned shell.
                (coordinator.roofs+coordinator.outlines).forEach { $0.removeFromParentNode() }
            }
            let content=coordinator.content!
            coordinator.roofs=[]; coordinator.outlines=[]
            func vector(_ p:RoomPoint) -> SCNVector3 { .init(Float(p.x),Float(p.y),Float(p.z)) }
            func node(_ points:[RoomPoint],surface:MaquetteStyle.Surface,name:String?=nil) -> SCNNode {
                let geometry=MaquetteStyle.geometry(points,textureCoordinates:surface == .floor ? points.map { MaquetteStyle.uv($0) } : nil)
                geometry.materials=[MaquetteStyle.material(surface)]
                let node=SCNNode(geometry:geometry); node.name=name; node.castsShadow=true
                if surface == .wall { MaquetteStyle.attachEdges(to:node,points:points) }
                node.categoryBitMask=name == nil ? 2 : 1
                content.addChildNode(node)
                return node
            }
            for wall in room.walls where rebuildShell {
                coordinator.walls.append(node(PlaquistoWallGeometry.displayTriangles(wall:wall,room:room),surface:.wall,name:wall.id.uuidString))
            }
            do {
                for floor in room.floors where rebuildShell {
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
                    let edges = SCNNode(); edges.categoryBitMask = 2; edges.name=ceilingID?.uuidString
                    let standard=SCNNode(geometry:outline); standard.name="maquette.standard"; standard.categoryBitMask=2
                    let ink=SCNNode(geometry:MaquetteStyle.edgeGeometry(lines))
                    ink.name="maquette.ink"; ink.categoryBitMask=2; ink.castsShadow=false
                    edges.addChildNode(standard); edges.addChildNode(ink)
                    content.addChildNode(edges); coordinator.outlines.append(edges)
                }
            }
        }
        for wall in coordinator.walls {
            wall.geometry?.firstMaterial=MaquetteStyle.material(.wall,state:wall.name == selected?.uuidString ? .selected : .normal)
            MaquetteStyle.updateEdges(on:wall,selected:wall.name == selected?.uuidString)
        }
        for floor in coordinator.floors {
            floor.isHidden = !showFloor
            floor.geometry?.firstMaterial=MaquetteStyle.material(.floor)
        }
        for roof in coordinator.roofs {
            let highlighted=selected != nil && roof.name == selected?.uuidString
            roof.isHidden=ceilingMode == 0 || (!highlighted && room.ceilings.contains { $0.id.uuidString == roof.name && $0.isHidden == true })
            roof.opacity=ceilingMode == 1 ? (highlighted ? 0.6 : 0.25) : 1
            if highlighted && MaquetteRendering.current == .elevated { roof.opacity=0.8 }
            roof.geometry?.firstMaterial=MaquetteStyle.material(.ceiling,state:highlighted ? .selected : .normal,translucent:roof.opacity < 1)
            roof.renderingOrder=ceilingMode == 1 ? 20 : 0
            roof.castsShadow=ceilingMode == 2 && !roof.isHidden
        }
        for edges in coordinator.outlines {
            edges.isHidden=ceilingMode == 0 || (edges.name != selected?.uuidString && room.ceilings.contains { $0.id.uuidString == edges.name && $0.isHidden == true })
            edges.opacity=ceilingMode == 1 ? 0.35 : 0.75
            if MaquetteRendering.current == .elevated { edges.opacity=1 }
            edges.childNode(withName:"maquette.standard",recursively:false)?.isHidden=MaquetteRendering.current == .elevated
            if let ink=edges.childNode(withName:"maquette.ink",recursively:false) {
                ink.isHidden=MaquetteRendering.current == .standard
                ink.geometry?.firstMaterial=MaquetteStyle.outline(selected:selected != nil && edges.name == selected?.uuidString)
            }
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
        var rendering:MaquetteRendering?
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
