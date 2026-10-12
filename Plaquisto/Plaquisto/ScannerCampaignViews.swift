import SwiftUI
import CoreLocation

private struct SurveyExportFile:Identifiable {
    let id=UUID()
    let url:URL
}
private struct SurveyExportShareSheet:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context) -> UIActivityViewController {
        UIActivityViewController(activityItems:[url],applicationActivities:nil)
    }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}

@MainActor enum ScanAddressSuggestion {
    static func address(for fix:ScanLocationFix?) async -> String? {
        guard let fix, fix.isUsable(at:fix.capturedAt) else { return nil }
        // Use the recorded site, never the phone's location when reopening later.
        guard let place=try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude:fix.latitude,longitude:fix.longitude)).first,
              !Task.isCancelled else { return nil }
        let street=[place.subThoroughfare,place.thoroughfare].compactMap { $0 }.joined(separator:" ")
        let town=[place.postalCode,place.locality].compactMap { $0 }.joined(separator:" ")
        let address=[street,town,place.country ?? ""].filter { !$0.isEmpty }.joined(separator:", ")
        return address.isEmpty ? nil : address
    }
}

private struct SurveyRepairView: View {
    @Environment(\.dismiss) private var dismiss
    let document: PlaquistoRoomDocument
    let onSave: (PlaquistoRoomDocument) throws -> Void
    private let proposals: [SurveyRepair.Proposal]
    @State private var selected = Set<String>()
    @State private var focused: String?
    @State private var preview: PlaquistoRoomDocument
    @State private var original = false
    @State private var previewError: String?
    @State private var saveError: String?
    @State private var cameraReset = UUID()
    init(document:PlaquistoRoomDocument,onSave:@escaping (PlaquistoRoomDocument) throws -> Void) {
        self.document=document; self.onSave=onSave
        proposals=SurveyRepair.proposals(in:document)
        _preview=State(initialValue:document)
        _focused=State(initialValue:proposals.first?.id)
    }
    private var chosen: [SurveyRepair.Proposal] { proposals.filter { selected.contains($0.id) } }
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing:0) {
                    RoomDomainScene(room:original ? document.room : preview.room,selected:.constant(nil),
                        ceilingMode:0,showFloor:true,topView:false,cameraReset:cameraReset,
                        repairTriangles:original ? [] : proposals.first(where:{$0.id==focused})?.highlight ?? [])
                        .frame(height:proxy.size.height*(ScanEvidencePolicy.enabled ? 0.38 : 0.48))
                        .overlay(alignment:.topTrailing) {
                            Toggle("Avant",isOn:$original).toggleStyle(.button)
                                .padding(10).background(.regularMaterial,in:Capsule()).padding(12)
                        }
                    List {
                        if ScanEvidencePolicy.enabled {
                            if !proposals.isEmpty {
                                Picker("Zone à examiner", selection: $focused) {
                                    ForEach(proposals) { Text($0.title).tag(Optional($0.id)) }
                                }.pickerStyle(.menu)
                            }
                            ScanEvidenceReview(roomID: document.initialRoom.id,
                                proposal: proposals.first(where: { $0.id == focused }))
                        }
                        if proposals.isEmpty {
                            Text("Aucune ouverture ni interruption de mur détectée. Pour un trou absent du modèle, corrigez le contour dans Modifier le plan.")
                        } else {
                            Section {
                                ForEach(proposals) { proposal in
                                    HStack {
                                        Button { focused=proposal.id; original=false } label: {
                                            Label(proposal.title,systemImage:"viewfinder")
                                                .foregroundStyle(focused==proposal.id ? Color.orange : Color.primary)
                                                .frame(maxWidth:.infinity,alignment:.leading)
                                        }.buttonStyle(.borderless)
                                        Toggle("Fermer cette zone",isOn:Binding(get:{ selected.contains(proposal.id) },set:{ enabled in
                                            if enabled { selected.insert(proposal.id) } else { selected.remove(proposal.id) }
                                            focused=proposal.id; original=false; refresh()
                                        })).labelsHidden().tint(.orange)
                                    }
                                }
                            } header: { Text("Fermetures possibles") } footer: {
                                Text("Portes, fenêtres, passages ou murs manquants : choisissez les zones à boucher. Vérifiez l’aperçu orange avant d’appliquer. Rien n’est enregistré sans votre validation.")
                            }
                            if let previewError { Text(previewError).foregroundStyle(.red) }
                        }
                    }
                    if !proposals.isEmpty {
                        Button("Appliquer les réparations (\(selected.count))") {
                            do {
                                let updated=try SurveyRepair.applying(chosen,to:document)
                                try onSave(updated); dismiss()
                            } catch { saveError=error.localizedDescription }
                        }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || previewError != nil)
                            .padding().frame(maxWidth:.infinity).background(.regularMaterial)
                    }
                }
            }
            .navigationTitle("Réparer le relevé").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } } }
            .alert("Réparation non enregistrée",isPresented:Binding(get:{saveError != nil},set:{if !$0 {saveError=nil}})) {
                Button("OK",role:.cancel) { saveError=nil }
            } message: { Text(saveError ?? "") }
        }
    }
    private func refresh() {
        do { preview=try SurveyRepair.applying(chosen,to:document); previewError=nil }
        catch { preview=document; previewError=error.localizedDescription }
    }
}

/// The scan opens here immediately: selection precedes project/work creation.
struct ScannerCampaignWorkspaceView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.interfacePresentation) private var presentation
    private var isLab: Bool { presentation == .contrastLab }
    @State var draft: ScanCampaignDraft
    var quickLayout = false
    @State private var quickDocument: LayoutDocument?
    @State private var showingQuickLayout = false
    @State private var selectedKeys: Set<String> = []
    @State private var kind = SurveySurfaceSource.Kind.wall
    @State private var plan = false
    @State private var dimensions = true
    @State private var creating = false
    @State private var savingSurvey = false
    @State private var choosingRoom = false
    @State private var configuringCeilings = false
    @State private var liningCheckpoint: UUID?
    @State private var choosingLining = false
    @State private var liningRequestPending = false
    @State private var editingLining: WorkItem?
    private struct EditorRoute: Identifiable {
        let checkpoint: ProjectRoomScanCheckpoint
        let ceilings: Bool
        var resumePartitions = false
        var id: UUID { checkpoint.id }
    }
    @State private var editing: EditorRoute?
    @State private var repairing: ProjectRoomScanCheckpoint?
    @State private var choosingRepairRoom = false
    @State private var destinationProject: UUID?
    @State private var revision = Date()
    @State private var showsCeilings = false
    @State private var cameraReset = 0
    @State private var diagnosticExport: ScanDiagnosticExport?
    @State private var diagnosticError: String?
    @State private var daeExport:SurveyExportFile?
    @State private var exportingDAE=false
    private var survey: ProjectSurveyRecord {
        if let saved = store.surveys.first(where: { $0.id == draft.id }) { return saved }
        return ProjectSurveyRecord(id: draft.id, projectID: draft.id, name: "Mon relevé", checkpoints: draft.includedChunks.map {
            .init(id: $0.id, roomID: $0.document.room.id, document: $0.document,
                spatialLinkState: draft.sharesWorldSpace ? .sharedWorldSpace : .needsLink,
                workState: .awaitingValidation, updatedAt: revision)
        },captureLocation:draft.captureLocation,capturedAt:draft.createdAt,ceilingPlanNumbers:draft.ceilingPlanNumbers)
    }
    private var surfaces: [SurveyWorkSurface] {
        SurveyWorkGeometry.surfaces(in: survey).filter { !SurveyWorkGeometry.isHidden($0, in: survey) }
    }
    private var liningWorks: [WorkItem] {
        store.project(id:survey.projectID)?.works.filter { $0.type.category == .wallInsulation } ?? []
    }
    private var liningClaims: Set<UUID> { Set(liningWorks.flatMap(\.components).compactMap(\.surveySource).filter { $0.surveyID==survey.id }.map(\.surfaceID)) }
    static func key(_ value: SurveyWorkSurface) -> String {
        "\(value.source.surfaceID)/\(value.source.kind.rawValue)/\(value.source.boundaryIndex)"
    }
    private var chosen: [SurveyWorkSurface] { surfaces.filter { $0.source.kind == kind && selectedKeys.contains(Self.key($0)) } }
    private var chosenIDs: Set<String> { Set(chosen.map(\.id)) }
    private var surfacePicker: some View {
        Picker("Surfaces", selection: $kind) {
            Text("Murs").tag(SurveySurfaceSource.Kind.wall)
            Text("Plafonds").tag(SurveySurfaceSource.Kind.ceiling)
        }.pickerStyle(.segmented).disabled(choosingLining)
    }
    private func toggle(_ id: String) {
        guard let value = surfaces.first(where: { $0.id == id && $0.source.kind == kind }) else { return }
        if choosingLining {
            guard value.source.kind == .wall, value.source.checkpointID == liningCheckpoint else { return }
            if liningClaims.contains(value.source.surfaceID) {
                editingLining=liningWorks.first { $0.components.contains { $0.surveySource?.surfaceID == value.source.surfaceID } }
                return
            }
        }
        let key = Self.key(value)
        if selectedKeys.contains(key) { selectedKeys.remove(key) }
        else if quickLayout && !choosingLining { selectedKeys = [key] }
        else { selectedKeys.insert(key) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Vue", selection: $plan) { Text("3D").tag(false); Text("Plan 2D").tag(true) }.pickerStyle(.segmented)
                if !isLab { surfacePicker }
            }.padding()
            if survey.checkpoints.count > 1 && survey.checkpoints.contains(where: { $0.spatialLinkState == .needsLink }) {
                Label("Raccord non confirmé : zones présentées séparément", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal)
            }
            Group {
                if plan {
                    SurveySurfacePlan(survey: survey, surfaces: surfaces, kind: kind, selected: chosenIDs,
                        blocked: [], onTap: toggle, showsDimensions: dimensions)
                } else {
                    SurveySurfaceScene(survey: survey, surfaces: surfaces, kind: kind, selected: chosenIDs,
                        claimed: [], onTap: toggle, showsCeilings: showsCeilings, resetToken: cameraReset)
                }
            }.overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                if kind == .ceiling {
                    VStack(alignment: .leading, spacing: 6) {
                        if !surfaces.contains(where: { $0.source.kind == .ceiling }) {
                            Text("Les plafonds ne sont pas encore configurés.").font(.caption)
                        }
                        Button("Configurer les plafonds", systemImage: "square.3.layers.3d") {
                            openEditor(ceilings: true)
                        }.buttonStyle(.borderedProminent)
                    }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding()
                } else if chosen.isEmpty && (!isLab || choosingLining || quickLayout) {
                    Text(choosingLining ? "Sélectionnez les murs à doubler. Touchez un doublage existant pour renseigner sa tapée." : quickLayout ? "Touchez le mur à calepiner" : "Touchez les murs à inclure dans un ouvrage")
                        .font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding()
                }
                if isLab {
                    surfacePicker.padding(8).background(.regularMaterial, in: Capsule()).padding(12)
                }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: isLab ? 24 : 0))
            .padding(.horizontal, isLab ? 12 : 0)
            .overlay(alignment: .topTrailing) {
                if !plan {
                    VStack(spacing: 12) {
                        Button { cameraReset += 1 } label: { Image(systemName: "scope").padding(12) }
                            .accessibilityLabel("Recentrer la maquette")
                        Button { showsCeilings.toggle() } label: {
                            Image(systemName: showsCeilings ? "square.3.layers.3d.top.filled" : "square.3.layers.3d.slash").padding(12)
                        }.accessibilityLabel(showsCeilings ? "Masquer les plafonds" : "Afficher les plafonds")
                    }.buttonStyle(.borderless).background(.regularMaterial, in: Capsule()).padding()
                }
            }
            HStack {
                Button("Modifier le plan", systemImage: "pencil.and.outline") {
                    openEditor(ceilings: false)
                }.disabled(choosingLining)
                Spacer()
                if plan { Toggle("Cotes", isOn: $dimensions).fixedSize() }
                Button(action:exportDAE) {
                    if exportingDAE { ProgressView().accessibilityLabel("Préparation du DAE") }
                    else { Label(plan ? "DAE" : "Exporter DAE",systemImage:"square.and.arrow.up").lineLimit(1) }
                }.disabled(exportingDAE)
                    .accessibilityLabel(exportingDAE ? "Préparation du DAE" : "Exporter le relevé en DAE")
                    .accessibilityIdentifier("survey.exportDAE")
            }.padding().background(.regularMaterial)
        }
        .background(isLab ? ContrastPalette.paper : Color(uiColor: .systemBackground))
        .navigationTitle(survey.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing:8) {
            if choosingLining {
                Button("Revenir au tracé des cloisons",systemImage:"arrow.uturn.backward") { returnToPlan() }
            }
            if !quickLayout && !store.surveys.contains(where:{ $0.id == draft.id }) {
                Button("Enregistrer le relevé dans un projet",systemImage:"folder.badge.plus") { savingSurvey=true }
                    .buttonStyle(.bordered).frame(maxWidth:.infinity)
            }
            HStack {
                VStack(alignment: .leading) {
                    Text("\(chosen.count) surface(s)").font(.headline)
                    Text("\(SurveyWorkGeometry.totalArea(chosen).formatted(.number.precision(.fractionLength(2)))) m² nets")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if quickLayout && !choosingLining {
                    Button("Calepiner cette surface") {
                        if let surface=chosen.first {
                            quickDocument=SurveyWorkGeometry.quickLayoutDocument(surface)
                            showingQuickLayout=true
                        }
                    }.buttonStyle(.borderedProminent).disabled(chosen.count != 1)
                } else {
                    Button(choosingLining ? "Créer le doublage" : "Créer un ouvrage") { creating = true }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty)
                        .tint(isLab ? ContrastPalette.ink : Color.accentColor)
                }
            }.padding().background(.regularMaterial)
            }.background(.regularMaterial)
        }
        .toolbar {
            Menu {
                Button("Partager le diagnostic complet", systemImage: "square.and.arrow.up") {
                    do { diagnosticExport = try ScanDiagnosticExport.prepare(draft: draft, survey: survey) }
                    catch { diagnosticError = "Impossible de préparer le diagnostic : \(error.localizedDescription)" }
                }
                Divider()
                Button("Tout désélectionner") { selectedKeys = [] }
                Button("Créer ou modifier un plafond", systemImage: "square.3.layers.3d.top.filled") {
                    openEditor(ceilings: true)
                }
                Button("Réparer le relevé", systemImage: "wand.and.stars") {
                    if survey.checkpoints.count == 1 { repairing=survey.checkpoints.first }
                    else { choosingRepairRoom=true }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .onChange(of: kind) { _, value in showsCeilings = value == .ceiling; if quickLayout { selectedKeys=[] } }
        .navigationDestination(isPresented: $showingQuickLayout) {
            if let quickDocument { SheetLayoutView(initialDocument: quickDocument) }
        }
        .alert("Partage impossible", isPresented: Binding(get: { diagnosticError != nil }, set: { if !$0 { diagnosticError = nil } })) {
            Button("OK", role: .cancel) { diagnosticError = nil }
        } message: { Text(diagnosticError ?? "") }
        .sheet(item:$daeExport) { file in SurveyExportShareSheet(url:file.url) }
        .sheet(item: $diagnosticExport) { export in
            NavigationStack {
                Form {
                    Section {
                        Text(export.limited
                            ? "Ce scan contient un diagnostic partiel : les détails de détection n’ont pas été conservés à l’époque. Les données encore disponibles seront partagées."
                            : "Le fichier contient les tentatives de reconstruction, les compteurs LiDAR et les données géométriques du relevé.")
                        Text("Sans photos, maillage brut, nom de client ni adresse. Le plan et les positions relatives de la caméra peuvent figurer dans le rapport.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        ShareLink(item: export.url) {
                            Label("Partager le fichier de diagnostic", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .navigationTitle("Diagnostic du scan").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { diagnosticExport = nil }
                } }
            }
        }
        .confirmationDialog("Zone à modifier", isPresented: $choosingRoom, titleVisibility: .visible) {
            ForEach(survey.checkpoints) { checkpoint in
                Button(checkpoint.document.room.name ?? "Pièce") { editing = .init(checkpoint: checkpoint, ceilings: configuringCeilings) }
            }
        }
        .confirmationDialog("Zone à réparer", isPresented:$choosingRepairRoom, titleVisibility:.visible) {
            ForEach(Array(survey.checkpoints.enumerated()), id:\.element.id) { index, checkpoint in
                Button(checkpoint.document.room.name ?? "Zone \(index+1)") { repairing=checkpoint }
            }
        }
        .sheet(item:$repairing) { checkpoint in
            SurveyRepairView(document:checkpoint.document) { document in
                try saveEditedDocument(document,checkpoint:checkpoint)
            }
        }
        .sheet(item: $editing,onDismiss: {
            if liningRequestPending { liningRequestPending=false; choosingLining=true; kind = .wall; selectedKeys=[] }
        }) { route in
            let checkpoint = route.checkpoint
            SurveyPlanEditor(document: checkpoint.document,ceilingNumbers:CeilingPlanNaming.numbers(in:survey),
                             initiallyConfigureCeilings: route.ceilings,
                             liningDepths:SurveyPlanFinishes.depths(works:liningWorks,surveyID:survey.id,checkpointID:checkpoint.id),
                             resumePartitions:route.resumePartitions,
                             onRequestLining:{ liningCheckpoint=checkpoint.id; liningRequestPending=true; editing=nil }) { document in
                try saveEditedDocument(document,checkpoint:checkpoint)
            }
        }
        .sheet(isPresented: $creating, onDismiss: {
            if choosingLining { returnToPlan() }
            else if let destinationProject { store.showProject(destinationProject); self.destinationProject = nil }
        }) {
            SurveyWorkspaceCreationFlow(draft: draft, selectedKeys: Set(chosen.map(Self.key)), onSaved:{ projectID in
                selectedKeys = []; if !choosingLining { destinationProject = projectID }; creating = false
            },restrictToLining:choosingLining)
        }
        .sheet(item:$editingLining,onDismiss:{ returnToPlan() }) { work in
            SavedWorkView(work:work,startsAtBeginning:true)
        }
        .sheet(isPresented:$savingSurvey) {
            SurveyWorkspaceCreationFlow(draft:draft,selectedKeys:[],onSaved:{ _ in savingSurvey=false },saveOnly:true)
        }
    }
    private func saveEditedDocument(_ document:PlaquistoRoomDocument, checkpoint:ProjectRoomScanCheckpoint) throws {
        if store.surveys.contains(where: { $0.id == draft.id }) {
            try store.updateSurveyRoom(surveyID:draft.id,checkpointID:checkpoint.id,
                expectedDocument:checkpoint.document,document:document)
        } else {
            guard let i=draft.chunks.firstIndex(where:{$0.id==checkpoint.id}),
                  draft.chunks[i].document==checkpoint.document else { throw RoomModelError.invalidGeometry }
            var updated=draft
            updated.ceilingPlanNumbers=CeilingPlanNaming.numbers(in:survey)
            updated.chunks[i].document=document
            updated.ceilingPlanNumbers=CeilingPlanNaming.numbering(updated.includedChunks.flatMap { $0.document.room.ceilings },existing:updated.ceilingPlanNumbers)
            try ScanCampaignStore.save(updated)
            draft=updated; revision=Date()
        }
        selectedKeys=[]
    }
    private func exportDAE() {
        guard !exportingDAE else { return }
        let snapshot=survey
        exportingDAE=true
        Task {
            defer { exportingDAE=false }
            do {
                let url=try await Task.detached(priority:.userInitiated) { try SurveyDAEExport.write(snapshot) }.value
                daeExport = .init(url:url)
            } catch { diagnosticError=error.localizedDescription }
        }
    }

    private func openEditor(ceilings: Bool) {
        configuringCeilings = ceilings
        if survey.checkpoints.count == 1, let checkpoint = survey.checkpoints.first { editing = .init(checkpoint: checkpoint, ceilings: ceilings) }
        else { choosingRoom = true }
    }
    private func returnToPlan() {
        let checkpoint=survey.checkpoints.first { $0.id==liningCheckpoint }
        choosingLining=false; selectedKeys=[]; destinationProject=nil
        if let checkpoint { editing = .init(checkpoint:checkpoint,ceilings:false,resumePartitions:true) }
    }
}

private struct SurveyWorkspaceCreationFlow: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let draft: ScanCampaignDraft
    let selectedKeys: Set<String>
    let onSaved: (UUID) -> Void
    var saveOnly=false
    var restrictToLining=false
    @State private var projectID: UUID?
    @State private var projectName = ""
    @State private var client = ""
    @State private var address = ""
    @State private var addressEdited=false
    @State private var surveyName="Relevé 3D"
    @State private var notes = ""
    @State private var name = ""
    @State private var category: WorkCategory?
    @State private var configuration: SurveyWorkFormDraft?
    @State private var error: String?
    private var survey: ProjectSurveyRecord? { store.surveys.first { $0.id == draft.id } }
    private var chosen: [SurveyWorkSurface] {
        guard let survey else { return [] }
        return SurveyWorkGeometry.surfaces(in: survey).filter {
            selectedKeys.contains(ScannerCampaignWorkspaceView.key($0)) && !SurveyWorkGeometry.isHidden($0,in:survey)
        }
    }
    private var types: [WorkType] {
        SurveyWorkGeometry.availableWorkTypes(for: chosen).filter { !restrictToLining || $0.category == .wallInsulation }
    }
    var body: some View {
        NavigationStack {
            Form {
                if survey == nil {
                    Section("Destination du relevé") {
                        if saveOnly { TextField("Nom du relevé",text:$surveyName) }
                        Picker("Projet", selection: $projectID) {
                            Text("Créer un nouveau projet").tag(UUID?.none)
                            ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if projectID == nil {
                        Section("Nouveau projet") {
                            TextField("Nom du projet", text: $projectName)
                            TextField("Client (facultatif)", text: $client)
                            TextField("Adresse (facultative)",text:Binding(get:{ address },set:{ address=$0; addressEdited=true }))
                            Text(draft.captureLocation == nil ? "Adresse du scan indisponible : vous pouvez la saisir manuellement." : "Adresse proposée depuis la position du scan · à vérifier.")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("Notes (facultatives)", text: $notes, axis: .vertical)
                        }
                    }
                    Section {
                        Button(saveOnly ? "Enregistrer le relevé" : "Continuer vers l’ouvrage") { attach() }
                            .disabled((projectID == nil && projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || surveyName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Section("Nom de l’ouvrage") {
                        HStack { Image(systemName: "pencil").foregroundStyle(.secondary); TextField("Facultatif", text: $name) }
                    }
                    Section("Catégorie") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                            ForEach(WorkCategory.allCases.filter { item in types.contains { $0.category == item } }) { item in
                                Button { category = item } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: icon(item)).font(.title)
                                        Text(item == .wallInsulation ? "Doublage périphérique" : item.title).font(.subheadline)
                                    }.frame(maxWidth: .infinity, minHeight: 90)
                                        .background(category == item ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Section {
                        LabeledContent("Surfaces", value: "\(chosen.count) · \(SurveyWorkGeometry.totalArea(chosen).formatted(.number.precision(.fractionLength(2)))) m² nets")
                    }
                    if let category {
                        Section("Type d’ouvrage") {
                            ForEach(types.filter { $0.category == category }) { type in
                                Button(type.title) { configure(type) }
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(saveOnly ? "Enregistrer le relevé" : (survey == nil ? "Choisir le projet" : "Ajouter un ouvrage"))
            .task {
                if restrictToLining { category = .wallInsulation }
                if let suggested=await ScanAddressSuggestion.address(for:draft.captureLocation), !addressEdited, address.isEmpty {
                    address=suggested
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .sheet(item: $configuration) { draft in
                SurveyWorkForm(draft: draft) { if let survey { onSaved(survey.projectID) } }
            }
        }
    }
    private func icon(_ category: WorkCategory) -> String {
        switch category {
        case .ceilings: "square.3.layers.3d"
        case .partitions: "rectangle.split.2x1"
        case .wallInsulation: "rectangle.leadinghalf.inset.filled"
        case .painting: "paintbrush"
        case .joints: "rectangle.and.pencil.and.ellipsis"
        case .openings: "door.left.hand.open"
        }
    }
    private func attach() {
        do {
            try ScanCampaignStore.save(draft)
            try store.saveScanCampaign(draft, projectID: projectID, newProjectName: projectName, surveyName: surveyName,
                newProjectClient: client, newProjectAddress: address, newProjectNotes: notes)
            if saveOnly, let survey { onSaved(survey.projectID); dismiss() }
        } catch { self.error = error.localizedDescription }
    }
    private func configure(_ type: WorkType) {
        do {
            guard let survey, !chosen.isEmpty else { return }
            for checkpoint in survey.checkpoints where chosen.contains(where: { $0.source.checkpointID == checkpoint.id }) {
                try store.validateSurveyCheckpoint(surveyID: survey.id, checkpointID: checkpoint.id, expectedDocument: checkpoint.document)
            }
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            configuration = .init(surveyID: survey.id, selections: chosen,
                name: typed.isEmpty ? store.defaultWorkName(projectID: survey.projectID, type: type) : typed, type: type, roomID: nil)
        } catch { self.error = error.localizedDescription }
    }
}

/// Review stays usable after the AR session ends, including recovered drafts.
struct ScannerCampaignReviewView: View {
    @EnvironmentObject private var store: ProjectStore
    @State var draft: ScanCampaignDraft
    @State private var projectID: UUID?
    @State private var projectName = ""
    @State private var surveyName = "Relevé de la maison"
    @State private var error: String?
    @State private var showPlan2D = false
    private var previewSurvey: ProjectSurveyRecord {
        .init(id: draft.id, projectID: draft.id, name: "Relevé", checkpoints: draft.includedChunks.map {
            .init(id: $0.id, roomID: $0.document.room.id, document: $0.document,
                spatialLinkState: draft.sharesWorldSpace ? .sharedWorldSpace : .needsLink)
        })
    }

    var body: some View {
        Form {
            if store.surveys.contains(where: { $0.id == draft.id }) {
                Section {
                    NavigationLink("Ouvrir le relevé et créer les ouvrages") {
                        ProjectSurveyDetailView(surveyID: draft.id)
                    }
                    Text("Ce relevé est enregistré dans le projet.").foregroundStyle(.secondary)
                }
            } else {
                if !draft.includedChunks.isEmpty && draft.sharesWorldSpace {
                    Section("Relevé complet") {
                        Picker("Vue du relevé", selection: $showPlan2D) {
                            Text("Maquette 3D").tag(false)
                            Text("Plan 2D").tag(true)
                        }.pickerStyle(.segmented)
                        Group {
                            if showPlan2D {
                                SurveyFloorPlanView(plan: ScanFloorPlan(overview: ScanLiveOverview(draft: draft)))
                            } else {
                                SurveySurfaceScene(survey: previewSurvey, surfaces: SurveyWorkGeometry.surfaces(in: previewSurvey),
                                    kind: .wall, selected: [], claimed: [], onTap: { _ in })
                            }
                        }.frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text("Toutes les zones conservées dans le même repère. Le plan 2D et la maquette 3D utilisent les mêmes mesures.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach($draft.chunks) { $chunk in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Nom de la pièce", text: $chunk.name)
                                .font(.headline)
                            Text("\(chunk.document.room.walls.count) murs · \(chunk.document.room.openings.count) ouvertures")
                                .font(.caption).foregroundStyle(.secondary)
                            if chunk.processingPending == true {
                                Label("Géométrie sauvegardée pendant le scan", systemImage: "square.and.arrow.down")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            if chunk.possibleDuplicateOf != nil {
                                Label("Chevauchement avec une zone déjà scannée : comparez avant de l’inclure. Rien n’est fusionné automatiquement.", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                                if let previous = draft.chunks.first(where: { $0.id == chunk.possibleDuplicateOf }) {
                                    NavigationLink("Comparer avec « \(previous.name) »") {
                                        List {
                                            ForEach([previous, chunk]) { compared in
                                                Section(compared.name) {
                                                    let overview = ScanLiveOverview(draft: ScanCampaignDraft(chunks: [compared]))
                                                    SurveyFloorPlanView(plan: ScanFloorPlan(overview: overview))
                                                        .frame(height: 240)
                                                    Text("\(compared.document.room.walls.count) murs · \(compared.document.room.openings.count) ouvertures")
                                                        .font(.caption)
                                                }
                                            }
                                            Text("Les plans sont cadrés séparément. Conservez les deux si leurs surfaces sont différentes ; écartez uniquement une capture redondante.")
                                                .font(.footnote)
                                        }.navigationTitle("Comparer les captures")
                                    }
                                }
                                Picker("Cette capture", selection: $chunk.keepAfterReview) {
                                    Text("À vérifier").tag(Bool?.none)
                                    Text("Conserver").tag(Optional(true))
                                    Text("Écarter").tag(Optional(false))
                                }
                            }
                            NavigationLink("Ouvrir la pièce") {
                                PlaquistoRoomEditor(document: chunk.document, allowsImport: false) { edited in
                                    var next = draft
                                    guard let i = next.chunks.firstIndex(where: { $0.id == chunk.id }) else { return }
                                    next.chunks[i].document = edited
                                    try ScanCampaignStore.save(next)
                                    draft = next
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                } header: { Text("Pièces détectées · noms modifiables") } footer: {
                    Text("Les noms sont des propositions. Une zone ouverte peut réunir salon et cuisine. Les contours et les plafonds restent modifiables dans l’éditeur.")
                }
                if let message = draft.assemblyMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                if !draft.isComplete {
                    Section { Label("Capture interrompue : la dernière géométrie sauvegardée reste disponible.", systemImage: "exclamationmark.triangle") }
                }
                Section("Enregistrer dans un projet") {
                    Picker("Projet", selection: $projectID) {
                        Text("Nouveau projet").tag(UUID?.none)
                        ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if projectID == nil { TextField("Nom du projet", text: $projectName) }
                    TextField("Nom du relevé", text: $surveyName)
                    Button("Enregistrer toutes les pièces") { save() }
                        .disabled(draft.includedChunks.isEmpty || draft.hasUnreviewedDuplicates || surveyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (projectID == nil && projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            || draft.chunks.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
        }
        .navigationTitle("Détails du relevé")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Names are local until project commit; don't lose them on Back.
            do { try ScanCampaignStore.save(draft) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func save() {
        do {
            try ScanCampaignStore.save(draft)
            try store.saveScanCampaign(draft, projectID: projectID, newProjectName: projectName, surveyName: surveyName)
        } catch { self.error = error.localizedDescription }
    }
}
