import SwiftUI

struct ProjectsHomeView: View {
    @EnvironmentObject private var store: ProjectStore
    let onOpenAccount: () -> Void
    @State private var showingNewProject = false
    @State private var projectToDelete: ProjectItem?
    @State private var errorMessage = ""

    init(onOpenAccount: @escaping () -> Void = {}) {
        self.onOpenAccount = onOpenAccount
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun projet", systemImage: "building.2")
                    } description: {
                        Text("Créez votre premier projet pour y enregistrer vos ouvrages et leurs quantitatifs.")
                    } actions: {
                        Button("Créer un projet") { showingNewProject = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List(store.projects) { project in
                        NavigationLink(value: project.id) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(project.name).font(.headline)
                                Text(project.client.isEmpty ? "\(project.works.count) ouvrage(s)" : "\(project.client) · \(project.works.count) ouvrage(s)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions {
                            Button { projectToDelete = project } label: { Label("Supprimer", systemImage: "trash") }
                                .tint(.red)
                            Button { duplicateProject(project) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                                .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Mes projets")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingNewProject = true } label: { Label("Nouveau projet", systemImage: "plus") }
                    Button(action: onOpenAccount) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Compte et réglages")
                }
            }
            .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
            .sheet(isPresented: $showingNewProject) { ProjectFormView() }
            .confirmationDialog("Supprimer ce projet et tous ses ouvrages ?", isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }), titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) { if let projectToDelete { deleteProject(projectToDelete) } }
                Button("Annuler", role: .cancel) { projectToDelete = nil }
            }
            .alert("Action impossible", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                Button("OK") { errorMessage = "" }
            } message: { Text(errorMessage) }
        }
        .tint(Color(red: 0.12, green: 0.38, blue: 0.29))
    }

    private func duplicateProject(_ project: ProjectItem) {
        do { try store.duplicateProject(id: project.id) }
        catch { errorMessage = "Le projet n’a pas pu être dupliqué." }
    }

    private func deleteProject(_ project: ProjectItem) {
        do { try store.deleteProject(id: project.id); projectToDelete = nil }
        catch { errorMessage = "Le projet n’a pas pu être supprimé." }
    }
}

private struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var references = CeilingReferenceStore()
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    var roomID: UUID? = nil
    @State private var showingEdit = false
    @State private var showingNewWork = false
    @State private var confirmingDelete = false
    @State private var workToDelete: WorkItem?
    @State private var workToRename: WorkItem?
    @State private var surveyToDelete: ProjectSurveyRecord?
    private struct WorkDestination: Hashable {
        enum Screen: Hashable { case quantities, layout, configuration, insulation }
        let workID: UUID
        let screen: Screen
    }
    // One route for the whole list. Never embed multiple NavigationLinks in a
    // single List cell: a physical row tap can activate all of them on iOS.
    @State private var workDestination: WorkDestination?
    @State private var errorMessage = ""

    private var project: ProjectItem? { store.project(id: projectID) }

    var body: some View {
        Group {
            if let project {
                List {
                    if roomID == nil {
                    if !project.client.isEmpty || !project.address.isEmpty || !project.notes.isEmpty {
                    Section {
                        if !project.client.isEmpty { LabeledContent("Client", value: project.client) }
                        if !project.address.isEmpty { LabeledContent("Adresse", value: project.address) }
                        if !project.notes.isEmpty { Text(project.notes).foregroundStyle(.secondary) }
                    }
                    }
                    }
                    if roomID == nil, !store.surveys(projectID: projectID).isEmpty {
                        Section("Relevés 3D") {
                            ForEach(store.surveys(projectID: projectID)) { survey in
                                NavigationLink {
                                    ProjectSurveyDetailView(surveyID: survey.id)
                                } label: {
                                    HStack(spacing:12) {
                                        SurveyThumbnailView(survey:survey)
                                            .frame(width:100,height:76)
                                            .clipShape(RoundedRectangle(cornerRadius:12))
                                        VStack(alignment:.leading,spacing:5) {
                                            Text(survey.name).font(.headline)
                                            Text("\(survey.checkpoints.count) pièce(s)").font(.subheadline).foregroundStyle(.secondary)
                                            Text(survey.createdAt,format:.dateTime.day().month().year())
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(.vertical,4)
                                }
                                .swipeActions(edge:.trailing,allowsFullSwipe:false) {
                                    Button { surveyToDelete=survey } label: { Label("Supprimer",systemImage:"trash") }
                                        .tint(.red)
                                }
                            }
                        }
                    }
                    Section(roomID == nil ? "Ouvrages" : "Ouvrages de la pièce") {
                        if (roomID.map { project.ownedWorks(in: $0) } ?? project.works).isEmpty {
                            Text("Aucun ouvrage enregistré.").foregroundStyle(.secondary)
                        } else {
                            ForEach(roomID.map { project.ownedWorks(in: $0) } ?? project.works) { work in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(work.name).font(.headline)
                                    Text(WorkTechnicalSummary.text(for: work, catalogue: references.workSummaryCatalogue))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if work.surveySourceNeedsReview {
                                        SurveySourceReviewNotice(work: work)
                                    }
                                    if let configuration = work.openingConfiguration {
                                        ForEach(OpeningSummaryFormatter.lines(for: configuration)) { line in
                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                Text("•")
                                                Text(openingSummary(line))
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    Button {
                                        openWork(work.id, screen: .quantities)
                                    } label: {
                                        workAction("Quantitatif", icon: "sum")
                                    }.buttonStyle(.plain)
                                    .accessibilityIdentifier("work.\(work.id).quantities")
                                    if work.type != .paintingBeta && (work.hasSavedLayout || !work.components.isEmpty || (work.type != .openings && !work.isPartition)) {
                                        Button { openWork(work.id, screen: .layout) } label: {
                                            workAction(work.hasSavedLayout ? "Calepinage 2D existant" : "Créer un calepinage 2D", icon: "square.grid.3x3")
                                        }.buttonStyle(.plain)
                                        .accessibilityIdentifier("work.\(work.id).layout")
                                        if work.layoutNeedsRecalculation == true && !work.surveySourceNeedsReview {
                                            Label("Calepinage modifié : ouvrez « Modifier la configuration » pour recalculer le quantitatif.",systemImage:"exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                    Button {
                                        openWork(work.id, screen: .configuration)
                                    } label: {
                                        workAction("Modifier la configuration", icon: "slider.horizontal.3")
                                    }.buttonStyle(.plain)
                                    .accessibilityIdentifier("work.\(work.id).configuration")
                                    if let conflict = store.openingJoineryConflict(
                                        projectID: projectID,
                                        referenceWorkID: work.id
                                    ) {
                                        Button {
                                            openWork(work.id, screen: .insulation)
                                        } label: {
                                            Label(joineryConflictSummary(conflict), systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.orange)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .swipeActions(allowsFullSwipe: false) {
                                    Button { workToDelete = work } label: { Label("Supprimer", systemImage: "trash") }
                                        .tint(.red)
                                    Button { duplicateWork(work) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                                        .tint(.blue)
                                    Button { workToRename = work } label: { Label("Renommer", systemImage: "pencil") }
                                        .tint(.orange)
                                }
                            }
                        }
                    }
                    if let roomID {
                        if !project.linkedWorks(in: roomID).isEmpty {
                            Section("Autres cloisons liées — hors quantitatif de cette pièce") {
                                ForEach(project.linkedWorks(in: roomID)) { work in
                                    NavigationLink(work.name) { WorkLayoutWorkbookView(projectID: projectID, workID: work.id, initialSide: roomID) }
                                }
                            }
                        }
                    }
                    Section {
                        Button { showingNewWork = true } label: { Label("Ajouter un nouvel ouvrage", systemImage: "plus.circle.fill") }
                    }
                    Section {
                        if let roomID {
                            NavigationLink("Quantitatif de la pièce") {
                                CombinedQuantityView(works: project.ownedWorks(in: roomID), title: "Quantitatif de la pièce")
                            }
                        } else {
                            NavigationLink { ProjectWorkQuantitySelectionView(projectID: projectID) } label: {
                                Label("Voir les quantitatifs", systemImage: "sum")
                            }
                        }
                    }
                    if roomID == nil {
                        Section { Button("Supprimer le projet", role: .destructive) { confirmingDelete = true } }
                    }
                }
                .navigationTitle(project.rooms.first(where: { $0.id == roomID })?.name ?? project.name)
                .task { await references.load() }
                .navigationDestination(item: $workDestination) { destination in
                    if let work = store.project(id: projectID)?.works.first(where: { $0.id == destination.workID }) {
                        switch destination.screen {
                        case .quantities:
                            CombinedQuantityView(works: [work], title: "Quantitatif de l’ouvrage")
                        case .layout:
                            WorkLayoutWorkbookView(projectID: projectID, workID: work.id, initialSide: roomID)
                        case .configuration:
                            SavedWorkView(work: work, startsAtBeginning: true)
                        case .insulation:
                            SavedWorkView(work: work, opensIsolationStep: true)
                        }
                    } else {
                        ContentUnavailableView("Ouvrage introuvable", systemImage: "exclamationmark.triangle")
                    }
                }
                .toolbar { if roomID == nil { Button("Modifier") { showingEdit = true } } }
                .sheet(isPresented: $showingEdit) { ProjectFormView(project: project) }
                .sheet(isPresented: $showingNewWork) { NewWorkView(projectID: projectID) }
                .sheet(item: $workToRename) { work in
                    RenameWorkView(work: work) { roomName in
                        renameWork(work, roomName: roomName)
                    }
                }
                .confirmationDialog("Supprimer ce projet et tous ses ouvrages ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Supprimer définitivement", role: .destructive) { deleteProject() }
                    Button("Annuler", role: .cancel) {}
                }
                .confirmationDialog("Supprimer cet ouvrage ?", isPresented: Binding(get: { workToDelete != nil }, set: { if !$0 { workToDelete = nil } }), titleVisibility: .visible) {
                    Button("Supprimer définitivement", role: .destructive) { if let workToDelete { deleteWork(workToDelete) } }
                    Button("Annuler", role: .cancel) { workToDelete = nil }
                }
                .confirmationDialog("Supprimer ce relevé 3D ?",isPresented:Binding(get:{ surveyToDelete != nil },set:{ if !$0 { surveyToDelete=nil } }),titleVisibility:.visible) {
                    Button("Supprimer le relevé",role:.destructive) {
                        guard let survey=surveyToDelete else { return }
                        do { try store.deleteSurvey(projectID:projectID,surveyID:survey.id); surveyToDelete=nil }
                        catch { errorMessage=error.localizedDescription }
                    }
                    Button("Annuler",role:.cancel) { surveyToDelete=nil }
                } message: {
                    Text("Le relevé « \(surveyToDelete?.name ?? "") » sera supprimé du projet. Les ouvrages, calepinages et quantitatifs déjà créés seront conservés dans leur état actuel, sans lien avec ce relevé.")
                }
            } else {
                ContentUnavailableView("Projet introuvable", systemImage: "exclamationmark.triangle")
            }
        }
        .alert("Action impossible", isPresented: errorBinding) { Button("OK") { errorMessage = "" } } message: { Text(errorMessage) }
    }

    private var errorBinding: Binding<Bool> { Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } }) }
    private func organizationSummary(_ work: WorkItem, project: ProjectItem) -> String? {
        let values = [project.rooms.first { $0.id == work.roomID }?.name, work.level, work.zone].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
    private func deleteProject() { do { try store.deleteProject(id: projectID); dismiss() } catch { errorMessage = "Le projet n’a pas pu être supprimé." } }
    private func deleteWork(_ work: WorkItem) { do { try store.deleteWork(projectID: projectID, workID: work.id); workToDelete = nil } catch { errorMessage = "L’ouvrage n’a pas pu être supprimé." } }
    private func duplicateWork(_ work: WorkItem) { do { try store.duplicateWork(projectID: projectID, workID: work.id) } catch { errorMessage = "L’ouvrage n’a pas pu être dupliqué." } }
    private func renameWork(_ work: WorkItem, roomName: String) {
        do {
            try store.renameWorkTitle(projectID: projectID, workID: work.id, title: roomName)
            workToRename = nil
        } catch {
            errorMessage = "Ce nom est vide ou déjà utilisé dans ce projet."
        }
    }

    private func openWork(_ id: UUID, screen: WorkDestination.Screen) {
        guard workDestination == nil else { return }
        workDestination = WorkDestination(workID: id, screen: screen)
    }

    private func workAction(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }
        .font(.subheadline)
        .foregroundStyle(.tint)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func openingSummary(_ line: OpeningSummaryLine) -> String {
        let width = (line.width * 100).formatted(.number.precision(.fractionLength(0...1)))
        let height = (line.height * 100).formatted(.number.precision(.fractionLength(0...1)))
        return "\(line.title) \(width) × \(height) cm (×\(line.count))"
    }

    private func joineryConflictSummary(_ conflict: OpeningJoineryConflict) -> String {
        let maximumInsulation = (conflict.maximumCompatibleInsulationThickness * 100)
            .formatted(.number.precision(.fractionLength(0...1)))
        return "Épaisseur d’isolant incompatible avec les tapées de menuiserie. L’épaisseur d’isolation doit être inférieure ou égale à \(maximumInsulation) cm."
    }
}

private struct ProjectRoomOrganizationView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    @State private var name = ""
    @State private var area = ""
    @State private var error = ""
    @State private var renamingRoom: ProjectRoomRecord?
    @State private var renamedRoom = ""
    private var project: ProjectItem? { store.project(id: projectID) }
    var body: some View {
        Form {
            Section("Ajouter une pièce") {
                TextField("Nom de la pièce", text: $name)
                PlaquistoNumericField(placeholder: "Surface au sol en m² (facultatif)", text: $area)
                Button("Ajouter") {
                    do {
                        let value = area.isEmpty ? nil : Double(area.replacingOccurrences(of: ",", with: "."))
                        guard area.isEmpty || value != nil else { error = "Surface invalide."; return }
                        try store.createRoom(projectID: projectID, name: name, floorAreaM2: value)
                        name = ""; area = ""; error = ""
                    } catch { self.error = "Vérifiez le nom et la surface de la pièce." }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let project {
                Section("Pièces existantes") {
                    ForEach(project.rooms) { room in
                        Button { renamingRoom = room; renamedRoom = room.name } label: {
                            HStack {
                                Text(room.name)
                                Spacer()
                                if let area = room.floorAreaM2 { Text("\(area.formatted()) m²").foregroundStyle(.secondary) }
                                Image(systemName: "pencil").font(.caption)
                            }
                        }
                    }
                }
                Section("Organisation des ouvrages") {
                    ForEach(project.works) { work in
                        NavigationLink(work.name) { WorkOrganizationForm(projectID: projectID, work: work) }
                    }
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Organisation")
            .alert("Renommer la pièce", isPresented: Binding(get: { renamingRoom != nil }, set: { if !$0 { renamingRoom = nil } })) {
                TextField("Nom", text: $renamedRoom)
                Button("Annuler", role: .cancel) { renamingRoom = nil }
                Button("Enregistrer") {
                    guard let room = renamingRoom else { return }
                    do { try store.renameRoom(projectID: projectID, roomID: room.id, name: renamedRoom); renamingRoom = nil }
                    catch { self.error = "Ce nom de pièce est vide ou déjà utilisé." }
                }
            }
    }
}

private struct WorkOrganizationForm: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let work: WorkItem
    @State private var roomID: UUID?
    @State private var level: String
    @State private var zone: String
    @State private var newRoom = ""
    @State private var error: String?
    init(projectID: UUID, work: WorkItem) {
        self.projectID = projectID; self.work = work
        _roomID = State(initialValue: work.roomID)
        _level = State(initialValue: work.level ?? "")
        _zone = State(initialValue: work.zone ?? "")
    }
    var body: some View {
        Form {
            Section {
                Picker("Pièce", selection: $roomID) {
                    Text("Aucune").tag(nil as UUID?)
                    ForEach(store.project(id: projectID)?.rooms ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Nouvelle pièce (facultatif)", text: $newRoom)
                TextField("Niveau / étage (facultatif)", text: $level)
                TextField("Zone / logement (facultatif)", text: $zone)
            } footer: { Text("Tous ces rattachements sont facultatifs et indépendants. Ils ne changent ni le quantitatif ni le calepinage de l’ouvrage.") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Organisation")
        .toolbar {
            Button("Enregistrer") {
                do {
                    var room = roomID
                    if !newRoom.clean.isEmpty {
                        if let existing = store.project(id: projectID)?.rooms.first(where: { $0.name.caseInsensitiveCompare(newRoom.clean) == .orderedSame }) {
                            room = existing.id
                        } else { room = try store.createRoom(projectID: projectID, name: newRoom.clean) }
                    }
                    try store.updateWorkOrganization(projectID: projectID, workID: work.id, roomID: room, level: level, zone: zone)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

private struct ProjectRoomDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    let roomID: UUID
    var body: some View {
        ProjectDetailView(projectID: projectID, roomID: roomID)
    }
}

private struct WorkComponentsView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    let workID: UUID
    @State private var name = ""
    @State private var error = ""
    private var project: ProjectItem? { store.project(id: projectID) }
    private var work: WorkItem? { project?.works.first { $0.id == workID } }
    var body: some View {
        if let work, let project {
            List {
                Section {
                    NavigationLink("Configuration et quantitatif de l’ouvrage") { SavedWorkView(work: work) }
                    Text("Le quantitatif est calculé dans le formulaire de l’ouvrage. Les métrés des sous-parties ne sont pas encore regroupés automatiquement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if [.distributionPartition, .alveolarPartition].contains(work.type) {
                    Section {
                        Label("L’ossature est commune aux deux côtés. Décaler de 5 cm vers la droite ici la décale de 5 cm vers la gauche depuis l’autre pièce.", systemImage: "arrow.left.arrow.right")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Pièces voisines de la cloison") {
                        ForEach(project.rooms.filter { $0.id != work.roomID }) { room in
                            Toggle(room.name, isOn: Binding(get: { work.linkedRoomIDs.contains(room.id) }, set: { enabled in
                                guard let owner = work.roomID else { error = "Rattachez d’abord la cloison à sa pièce propriétaire."; return }
                                var links = work.linkedRoomIDs.filter { $0 != room.id }
                                if enabled { links.append(room.id) }
                                // Organization is chosen explicitly; never infer it from room area.
                                let candidates = [owner] + links
                                let selectedOwner = owner
                                do { try store.assignWork(projectID: projectID, workID: workID, ownerRoomID: selectedOwner, adjacentRoomIDs: candidates.filter { $0 != selectedOwner }) }
                                catch { self.error = "Modification impossible." }
                            }))
                        }
                    }
                }
                ForEach(work.components) { component in
                    Section(component.name) {
                        if component.surface?.kind == .ceiling {
                            NavigationLink("Murs reliés au plafond") {
                                CeilingWallLinksView(projectID: projectID, componentID: component.id)
                            }
                        }
                        ForEach((project.ceilingWallLinks ?? []).filter { $0.ceilingComponentID == component.id || $0.wallComponentID == component.id }) { link in
                            if let warning = ComponentAdjacency.warning(for: link, in: project) {
                                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Relations et pièces")
        }
    }
}

/// One work-owned workbook, whose tabs reuse the existing stable component/side identities.
private struct WorkLayoutWorkbookView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    let workID: UUID
    var initialSide: UUID? = nil
    private struct Selection: Identifiable {
        let id = UUID()
        let component: WorkComponentRecord
        let side: UUID?
        var key: String { component.id.uuidString + ":" + (side?.uuidString ?? "main") }
    }
    @State private var selected: Selection?
    @State private var drafts: [WorkComponentRecord] = []
    @State private var editingName = ""
    @State private var adding = false
    @State private var renaming = false
    @State private var relations = false
    @State private var error: String?
    private var project: ProjectItem? { store.project(id: projectID) }
    private var work: WorkItem? { project?.works.first { $0.id == workID } }
    private var selections: [Selection] {
        guard let work else { return [] }
        let components = work.components + drafts.filter { draft in !work.components.contains { $0.id == draft.id } }
        return components.flatMap { component in
            let stored = component.plans.compactMap(\.sideRoomID) + [component.referenceSideRoomID].compactMap { $0 }
            let ids = Array(Set(stored + [work.roomID].compactMap { $0 } + work.linkedRoomIDs)).sorted { $0.uuidString < $1.uuidString }
            let sides: [UUID?] = work.isPartition && !ids.isEmpty ? ids.map(Optional.some) : [nil]
            return sides.map { Selection(component: component, side: $0) }
        }
    }
    var body: some View {
        Group {
            if let work, let selected {
                ComponentPlanEditorView(projectID: projectID, workID: workID, component: selected.component,
                    side: selected.side, kind: work.type.category == .ceilings ? .ceiling : .wall,
                    sharedFraming: work.isPartition,
                    workbook: LayoutWorkbookNavigation(tabs: selections.map { item in
                        let room = project?.rooms.first { $0.id == item.side }?.name
                        let stale = item.component.plans.contains { $0.sideRoomID == item.side && $0.geometryRevision != item.component.geometryRevision }
                        return .init(id: item.key, title: item.component.name + (room.map { " · Côté \($0)" } ?? "") + (stale ? " — à vérifier" : ""))
                    }, selectedID: selected.key, select: { key in
                        self.selected = selections.first { $0.key == key }
                    }, add: {
                        editingName = ""; adding = true
                    }, rename: {
                        editingName = work.components.first { $0.id == selected.component.id }?.name ?? selected.component.name
                        renaming = true
                    }, relations: { relations = true }))
                    .id(selected.id)
            } else if work != nil {
                ProgressView("Ouverture du calepinage…")
            } else {
                ContentUnavailableView("Ouvrage introuvable", systemImage: "square.grid.3x3")
            }
        }
        .task {
            guard selected == nil, let work else { return }
            if work.components.isEmpty {
                drafts = [WorkComponentRecord(name: work.type.category == .ceilings ? "Plafond partie A" : "Mur A")]
            }
            let saved = selections.filter { $0.component.surface != nil && $0.component.plans.contains { !$0.layers.isEmpty } }
            selected = saved.first { $0.side == initialSide } ?? saved.first
                ?? selections.first { $0.side == initialSide } ?? selections.first
        }
        .alert("Nouvelle sous-partie", isPresented: $adding) {
            TextField("Nom : Mur B, Plafond partie B…", text: $editingName)
            Button("Annuler", role: .cancel) {}
            Button("Créer") {
                let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !selections.contains(where: { $0.component.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
                    error = "Ce nom est déjà utilisé."; return
                }
                let draft = WorkComponentRecord(name: name)
                drafts.append(draft)
                selected = selections.first { $0.component.id == draft.id && $0.side == selected?.side }
                    ?? selections.first { $0.component.id == draft.id }
            }.disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Renommer la sous-partie", isPresented: $renaming) {
            TextField("Nom", text: $editingName)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") {
                guard let selected else { return }
                do {
                    if work?.components.contains(where: { $0.id == selected.component.id }) == true {
                        try store.renameComponent(projectID: projectID, workID: workID, componentID: selected.component.id, name: editingName)
                    } else if let index = drafts.firstIndex(where: { $0.id == selected.component.id }) {
                        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !selections.contains(where: { $0.component.id != selected.component.id && $0.component.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
                            error = "Ce nom est déjà utilisé."; return
                        }
                        drafts[index].name = name
                    }
                    self.selected = selections.first { $0.key == selected.key }
                } catch { self.error = "Nom vide ou déjà utilisé. Le calepinage est conservé." }
            }.disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: $relations, onDismiss: {
            if let selected { self.selected = selections.first { $0.key == selected.key } ?? selections.first }
        }) {
            NavigationStack {
                WorkComponentsView(projectID: projectID, workID: workID)
                    .toolbar { Button("Fermer") { relations = false } }
            }
        }
        .alert("Action impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct ComponentPlanEditorView: View {
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var catalogue = ToolTechnicalStore()
    let projectID: UUID
    let workID: UUID
    let side: UUID?
    let kind: LayoutSupportKind
    let sharedFraming: Bool
    var workbook: LayoutWorkbookNavigation? = nil
    @State private var openedComponent: WorkComponentRecord

    init(projectID: UUID, workID: UUID, component: WorkComponentRecord, side: UUID?, kind: LayoutSupportKind, sharedFraming: Bool, workbook: LayoutWorkbookNavigation? = nil) {
        self.projectID = projectID; self.workID = workID; self.side = side
        self.kind = kind; self.sharedFraming = sharedFraming
        self.workbook = workbook
        _openedComponent = State(initialValue: component)
    }

    var body: some View {
        let plan = openedComponent.plans.first { $0.sideRoomID == side } ?? ComponentLayoutPlan(sideRoomID: side)
        SheetLayoutView(initialDocument: openedComponent.document(for: plan), onSaveDocument: { document in
            try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: openedComponent.id,
                sideRoomID: side, document: document, expectedGeometryRevision: openedComponent.geometryRevision,
                newComponent: openedComponent)
            refreshOpenedComponent()
        }, requiredSupportKind: kind, sharedPartitionFraming: sharedFraming, reviewLinkedDocument: { document in
            try store.reviewComponentPlan(projectID: projectID, componentID: openedComponent.id, document: document)
        }, saveReviewedDocument: { document, review, decision in
            try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: openedComponent.id,
                sideRoomID: side, document: document, expectedGeometryRevision: openedComponent.geometryRevision,
                adjacencyDecision: decision, reviewedAdjacency: review, newComponent: openedComponent)
            refreshOpenedComponent()
        }, workbook: workbook)
        .environmentObject(catalogue)
        .task { await catalogue.load() }
    }
    private func refreshOpenedComponent() {
        if let current = store.project(id: projectID)?.works.first(where: { $0.id == workID })?.components.first(where: { $0.id == openedComponent.id }) {
            openedComponent = current
        }
    }
}

private struct CeilingWallLinksView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    let componentID: UUID
    @State private var edge = 0
    @State private var selectedWall: UUID?
    @State private var error: String?
    @State private var removing: CeilingWallLink?
    private var project: ProjectItem? { store.project(id: projectID) }
    private func edgeTitle(_ index: Int, count: Int) -> String {
        "Bord \(vertexName(index))–\(vertexName((index + 1) % count))"
    }
    var body: some View {
        if let project, let work = project.works.first(where: { $0.components.contains { $0.id == componentID } }),
           let ceiling = work.components.first(where: { $0.id == componentID })?.surface {
            Form {
                Section {
                    Text("Identifiez le mur qui correspond à toute la longueur du bord. Ce lien n’ajuste aucune dimension à sa création. Le scan pourra ensuite fournir ces correspondances depuis sa géométrie 3D.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LayoutContourPreview(contours: [ceiling.contour], numbered: true, alphabetic: true)
                        .overlay {
                            Canvas { context, size in
                                if ceiling.contour.indices.contains(edge) {
                                    let viewport = LayoutViewport(bounds: ceiling.bounds, size: size, zoom: 1, pan: .zero)
                                    var line = Path()
                                    line.move(to: viewport.screen(ceiling.contour[edge]))
                                    line.addLine(to: viewport.screen(ceiling.contour[(edge + 1) % ceiling.contour.count]))
                                    context.stroke(line, with: .color(.orange), lineWidth: 4)
                                }
                            }.allowsHitTesting(false)
                        }
                        .frame(height: 180)
                        .accessibilityLabel("Contour du plafond. \(edgeTitle(edge, count: ceiling.contour.count)) sélectionné en orange.")
                }
                Section("Correspondances") {
                    ForEach((project.ceilingWallLinks ?? []).filter { $0.ceilingComponentID == componentID }) { link in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(edgeTitle(link.edgeIndex, count: link.ceilingVertexCount))
                            Text(project.works.flatMap(\.components).first(where: { $0.id == link.wallComponentID })?.name ?? "Mur")
                                .foregroundStyle(.secondary)
                            if let warning = ComponentAdjacency.warning(for: link, in: project) {
                                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                            Button("Retirer le lien", role: .destructive) { removing = link }
                        }
                    }
                }
                if let roomID = work.roomID {
                    Section("Identifier ou remplacer un lien") {
                        Picker("Bord du plafond", selection: $edge) {
                            ForEach(ceiling.contour.indices, id: \.self) { i in
                                let length = ComponentAdjacency.wallSpan(of: ceiling, edge: i) ?? 0
                                Text("\(edgeTitle(i, count: ceiling.contour.count)) · \((length / 10).formatted(.number.precision(.fractionLength(1)))) cm").tag(i)
                            }
                        }
                        Picker("Mur correspondant", selection: $selectedWall) {
                            Text("Choisir un composant").tag(nil as UUID?)
                            ForEach(project.works.filter { $0.roomID == roomID || $0.linkedRoomIDs.contains(roomID) }) { candidate in
                                ForEach(candidate.components.filter { $0.surface?.kind == .wall }) { wall in
                                    Text("\(candidate.name) — \(wall.name)").tag(Optional(wall.id))
                                }
                            }
                        }
                        Button("Confirmer la correspondance") {
                            guard let selectedWall else { return }
                            do {
                                try store.linkCeilingToWall(projectID: projectID, ceilingComponentID: componentID,
                                    edgeIndex: edge, wallComponentID: selectedWall, roomID: roomID)
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        }.disabled(selectedWall == nil)
                    }
                } else { Text("Rattachez d’abord l’ouvrage à une pièce.").foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Liens plafond–mur")
                .confirmationDialog("Retirer cette correspondance ?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                    Button("Retirer le lien", role: .destructive) {
                        if let removing {
                            do { try store.removeCeilingWallLink(projectID: projectID, linkID: removing.id) }
                            catch { self.error = error.localizedDescription }
                        }
                        removing = nil
                    }
                    Button("Annuler", role: .cancel) { removing = nil }
                } message: { Text("Les deux composants et leurs dimensions seront conservés.") }
        }
    }
}

private struct RenameWorkView: View {
    @Environment(\.dismiss) private var dismiss
    let work: WorkItem
    let onSave: (String) -> Void
    @State private var roomName: String

    init(work: WorkItem, onSave: @escaping (String) -> Void) {
        self.work = work
        self.onSave = onSave
        _roomName = State(initialValue: work.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom de l’ouvrage") {
                    TextField("Nom", text: $roomName)
                    Text("Renommer l’ouvrage ne change pas sa pièce de rattachement.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Renommer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { onSave(roomName) }
                        .disabled(roomName.clean.isEmpty)
                }
            }
        }
    }
}

private struct ProjectFormView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let project: ProjectItem?
    @State private var name: String
    @State private var client: String
    @State private var address: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage = ""

    init(project: ProjectItem? = nil) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _client = State(initialValue: project?.client ?? "")
        _address = State(initialValue: project?.address ?? "")
        _notes = State(initialValue: project?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations") {
                    TextField("Nom du projet", text: $name)
                    TextField("Client (facultatif)", text: $client)
                    TextField("Adresse (facultative)", text: $address)
                    TextField("Notes (facultatives)", text: $notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle(project == nil ? "Nouveau projet" : "Modifier le projet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.disabled(name.clean.isEmpty || isSaving) }
            }
            .alert("Enregistrement impossible", isPresented: errorBinding) { Button("OK") { errorMessage = "" } } message: { Text(errorMessage) }
        }
    }

    private var errorBinding: Binding<Bool> { Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } }) }
    private func save() {
        isSaving = true
        do {
            if let project { try store.updateProject(id: project.id, name: name, client: client, address: address, notes: notes) }
            else { _ = try store.createProject(name: name, client: client, address: address, notes: notes) }
            dismiss()
        } catch { errorMessage = "Le projet n’a pas pu être enregistré sur cet appareil."; isSaving = false }
    }
}

private struct NewWorkView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var customName = ""
    @State private var configurationDraft: Draft?
    @State private var duplicateName: String?
    @State private var category: WorkCategory?

    private struct Draft: Identifiable {
        let id = UUID()
        let name: String
        let type: WorkType
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    workNameField

                    categoryPicker

                    if let category {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.cardTitle).font(.headline)
                            ForEach(WorkType.allCases.filter { $0.category == category }) { type in
                                Button { prepareConfiguration(type) } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(category.cardColor).frame(width: 5)
                                        Text(type.title)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(16)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("work.creation.type.\(type.rawValue)")
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ajouter un ouvrage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .fullScreenCover(item: $configurationDraft) { draft in
                WorkConfiguratorContainer(projectID: projectID, workName: draft.name, workType: draft.type, onFinished: { dismiss() })
            }
            .alert("Nom déjà utilisé", isPresented: Binding(
                get: { duplicateName != nil },
                set: { if !$0 { duplicateName = nil } }
            )) {
                Button("OK") { duplicateName = nil }
            } message: {
                Text("Un ouvrage nommé « \(duplicateName ?? "") » existe déjà dans ce projet. Choisissez un autre nom.")
            }
        }
    }

    private var workNameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nom de l’ouvrage").font(.headline)
                Spacer()
                Text("Facultatif")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
            HStack(spacing: 12) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                TextField("Exemple : Plafond du salon", text: $customName)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("work.creation.name")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Si vous laissez ce champ vide, un nom sera proposé automatiquement.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catégorie d’ouvrage").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(WorkCategory.allCases) { item in
                    Button { category = item } label: {
                        Text(item.cardTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .padding(.horizontal, 10)
                            .background(item.cardColor, in: RoundedRectangle(cornerRadius: 20))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white, lineWidth: category == item ? 3 : 0)
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                    .accessibilityIdentifier("work.creation.category.\(item.rawValue)")
                }
            }
        }
    }

    private func prepareConfiguration(_ type: WorkType) {
        guard configurationDraft == nil else { return }
        let name = customName.clean.isEmpty ? store.defaultWorkName(projectID: projectID, type: type) : customName.clean
        guard !store.workNameExists(projectID: projectID, name: name) else {
            duplicateName = name
            return
        }
        configurationDraft = Draft(name: name, type: type)
    }
}

private extension WorkCategory {
    var cardTitle: String {
        switch self {
        case .ceilings: "Plafonds"
        case .partitions: "Cloisons"
        case .wallInsulation: "Isolation des murs"
        case .openings: "Ouvertures"
        case .painting: "Peinture (bêta)"
        }
    }

    var cardColor: Color {
        switch self {
        case .ceilings: Color(red: 0.20, green: 0.43, blue: 0.57)
        case .partitions: Color(red: 0.76, green: 0.43, blue: 0.24)
        case .wallInsulation: Color(red: 0.22, green: 0.49, blue: 0.38)
        case .openings: Color(red: 0.45, green: 0.34, blue: 0.58)
        case .painting: Color(red: 0.57, green: 0.37, blue: 0.24)
        }
    }
}

struct SavedWorkView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let work: WorkItem
    var opensIsolationStep = false
    var startsAtBeginning = false
    @State private var errorMessage = ""
    private var currentWork: WorkItem {
        SurveyWorkGeometry.workForRecalculation(store.project(id: work.projectID)?.works.first(where: { $0.id == work.id }) ?? work)
    }
    private var recalculationDocument: LayoutDocument? { currentWork.layoutNeedsRecalculation == true ? currentWork.layoutDocument : nil }

    var body: some View {
        Group {
            switch currentWork.type {
            case .ceilingOnFurring:
                CeilingConfiguratorView(initialConfiguration: LayoutWorkGeometry.ceiling(recalculationDocument,base:currentWork.ceilingConfiguration ?? .init()), startsAtResult: !startsAtBeginning && recalculationDocument == nil, preserveInitialSpacing:true, lockScannedGeometry: currentWork.components.contains { $0.surveySource != nil }) { configuration in
                    do { try store.updateWork(currentWork, configuration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .ceilingOnRailsAndStuds:
                RailStudCeilingConfiguratorView(initialConfiguration: LayoutWorkGeometry.railCeiling(recalculationDocument,base:currentWork.railStudCeilingConfiguration ?? .init()), startsAtResult: !startsAtBeginning && recalculationDocument == nil) { configuration in
                    do { try store.updateWork(currentWork, railStudCeilingConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .modularCeiling:
                ModularCeilingConfiguratorView(
                    initialConfiguration: currentWork.modularCeilingConfiguration,
                    startsAtResult: !startsAtBeginning
                ) { configuration in
                    do { try store.updateWork(currentWork, modularCeilingConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningStuds:
                DoublageConfiguratorHost(
                    initialConfiguration: LayoutWorkGeometry.lining(recalculationDocument,base:currentWork.doublageConfiguration ?? .init()),
                    startsAtResult: !startsAtBeginning && !opensIsolationStep && recalculationDocument == nil,
                    initialStep: opensIsolationStep ? 4 : nil
                ) { configuration in
                    do { try store.updateWork(currentWork, doublageConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .distributionPartition:
                CloisonDistributionConfiguratorHost(initialConfiguration: LayoutWorkGeometry.partition(recalculationDocument,base:currentWork.cloisonDistributionConfiguration ?? .init()), startsAtResult: !startsAtBeginning && recalculationDocument == nil) { configuration in
                    do { try store.updateWork(currentWork, cloisonDistributionConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .alveolarPartition:
                AlveolarPartitionConfiguratorHost(initialConfiguration: currentWork.alveolarPartitionConfiguration, startsAtResult: !startsAtBeginning) { configuration in
                    do { try store.updateWork(currentWork, alveolarPartitionConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningBonded:
                BondedLiningConfiguratorHost(initialConfiguration: currentWork.bondedLiningConfiguration, startsAtResult: !startsAtBeginning) { configuration in
                    do { try store.updateWork(currentWork, bondedLiningConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningFurrings:
                FurringLiningConfiguratorHost(
                    initialConfiguration: LayoutWorkGeometry.furring(recalculationDocument,base:currentWork.furringLiningConfiguration ?? .init()),
                    startsAtResult: !startsAtBeginning && !opensIsolationStep && recalculationDocument == nil,
                    initialStep: opensIsolationStep ? 4 : nil
                ) { configuration in
                    do { try store.updateWork(currentWork, furringLiningConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningAdhesiveFacing:
                AdhesiveFacingConfiguratorHost(initialConfiguration: currentWork.adhesiveFacingConfiguration, startsAtResult: !startsAtBeginning) { configuration in
                    do { try store.updateWork(currentWork, adhesiveFacingConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .openings:
                OpeningLabView(
                    initialConfiguration: currentWork.openingConfiguration,
                    heightOptions: store.openingHeightOptions(projectID: currentWork.projectID)
                ) { configuration in
                    do { try store.updateWork(currentWork, openingConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .paintingBeta:
                PaintingBetaConfiguratorView(initialConfiguration: {
                    if case .paintingBeta(let value) = currentWork.payload { return value }
                    return PaintingBetaConfiguration()
                }(), readOnlyArea: currentWork.components.contains { $0.surveySource != nil }) { configuration in
                    do { try store.updateWork(currentWork, paintingBetaConfiguration: configuration); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .navigationTitle(currentWork.name)
        .safeAreaInset(edge: .top) {
            if currentWork.surveySourceNeedsReview {
                SurveySourceReviewNotice(work: currentWork)
                    .padding(.horizontal).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
        .environment(\.layoutCoveringAreaRatio, LayoutWorkGeometry.coveringAreaRatio(currentWork.layoutDocument))
        .alert("Enregistrement impossible", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) { Button("OK") {} } message: { Text(errorMessage) }
    }
}

/// A source correction never silently replaces an already configured work.
/// Keep this warning visible both in the project and beside its quantities.
struct SurveySourceReviewNotice: View {
    @EnvironmentObject private var store: ProjectStore
    let work: WorkItem
    @State private var confirming = false
    @State private var showingSource = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Relevé modifié — ouvrage à contrôler", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            Text("Les dimensions et quantités de cet ouvrage ont été conservées. Comparez-les au relevé corrigé avant de les utiliser.")
                .font(.caption).foregroundStyle(.secondary)
            if !work.components.compactMap(\.surveySource).isEmpty {
                Button("Ouvrir le relevé source") { showingSource = true }
                    .font(.caption.weight(.semibold)).buttonStyle(.borderless)
            }
            Button("Conserver les dimensions de l’ouvrage…") { confirming = true }
                .font(.caption).buttonStyle(.borderless)
        }.fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showingSource) {
            if let source = work.components.compactMap(\.surveySource).first {
                NavigationStack {
                    ProjectSurveyDetailView(surveyID: source.surveyID)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fermer") { showingSource = false }
                            }
                        }
                }
            }
        }
        .alert("Conserver les dimensions actuelles ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("J’ai vérifié, conserver") {
                do { try store.confirmKeepingCurrentSurveyGeometry(projectID: work.projectID, workID: work.id) }
                catch { self.error = error.localizedDescription }
            }
        } message: {
            Text("Le contour, les ouvertures et les quantités de l’ouvrage resteront inchangés. Confirmez seulement après les avoir comparés au relevé corrigé. Aucun ajustement automatique ne sera effectué.")
        }
        .alert("Vérification non enregistrée", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct WorkConfiguratorContainer: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let workName: String
    let workType: WorkType
    let onFinished: () -> Void
    var layoutDocument: LayoutDocument? = nil
    var roomID: UUID? = nil
    var newRoomName: String? = nil
    var level: String? = nil
    var zone: String? = nil
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                switch workType {
                case .ceilingOnFurring:
                    CeilingConfiguratorView(initialConfiguration:LayoutWorkGeometry.ceiling(layoutDocument), preserveInitialSpacing:layoutDocument != nil) { configuration in save(configuration: configuration) }
                case .ceilingOnRailsAndStuds:
                    RailStudCeilingConfiguratorView(initialConfiguration:layoutDocument.map{LayoutWorkGeometry.railCeiling($0)}) { configuration in save(railStudCeilingConfiguration: configuration) }
                case .modularCeiling:
                    ModularCeilingConfiguratorView { configuration in save(modularCeilingConfiguration: configuration) }
                case .peripheralLiningStuds:
                    DoublageConfiguratorHost(initialConfiguration:layoutDocument.map{LayoutWorkGeometry.lining($0)}) { configuration in save(doublageConfiguration: configuration) }
                case .distributionPartition:
                    CloisonDistributionConfiguratorHost(initialConfiguration:layoutDocument.map{LayoutWorkGeometry.partition($0)},showsCloseButton: false) { configuration in
                        save(cloisonDistributionConfiguration: configuration)
                    }
                case .alveolarPartition:
                    AlveolarPartitionConfiguratorHost(showsCloseButton: false) { configuration in
                        save(alveolarPartitionConfiguration: configuration)
                    }
                case .peripheralLiningBonded:
                    BondedLiningConfiguratorHost(showsCloseButton: false) { configuration in
                        save(bondedLiningConfiguration: configuration)
                    }
                case .peripheralLiningFurrings:
                    FurringLiningConfiguratorHost(initialConfiguration:layoutDocument.map{LayoutWorkGeometry.furring($0)},showsCloseButton: false) { configuration in
                        save(furringLiningConfiguration: configuration)
                    }
                case .peripheralLiningAdhesiveFacing:
                    AdhesiveFacingConfiguratorHost(showsCloseButton: false) { configuration in
                        save(adhesiveFacingConfiguration: configuration)
                    }
                case .openings:
                    OpeningLabView(heightOptions: store.openingHeightOptions(projectID: projectID)) { configuration in
                        save(openingConfiguration: configuration)
                    }
                case .paintingBeta:
                    PaintingBetaConfiguratorView(initialConfiguration: .init(), readOnlyArea: false) { configuration in
                        savePayload(.paintingBeta(configuration))
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .environment(\.layoutCoveringAreaRatio, LayoutWorkGeometry.coveringAreaRatio(layoutDocument))
        .alert("Enregistrement impossible", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) { Button("OK") {} } message: { Text(errorMessage) }
    }

    private func save(configuration: CeilingConfiguration) { savePayload(.ceiling(configuration)) }
    private func save(railStudCeilingConfiguration: RailStudCeilingConfiguration) { savePayload(.railStudCeiling(railStudCeilingConfiguration)) }
    private func save(modularCeilingConfiguration: ModularCeilingConfiguration) { savePayload(.modularCeiling(modularCeilingConfiguration)) }
    private func save(doublageConfiguration: DoublageConfiguration) { savePayload(.peripheralLining(doublageConfiguration)) }
    private func save(cloisonDistributionConfiguration: CloisonDistributionConfiguration) { savePayload(.distributionPartition(cloisonDistributionConfiguration)) }
    private func save(alveolarPartitionConfiguration: AlveolarPartitionConfiguration) { savePayload(.alveolarPartition(alveolarPartitionConfiguration)) }
    private func save(bondedLiningConfiguration: BondedLiningConfiguration) { savePayload(.bondedLining(bondedLiningConfiguration)) }
    private func save(furringLiningConfiguration: FurringLiningConfiguration) { savePayload(.furringLining(furringLiningConfiguration)) }
    private func save(adhesiveFacingConfiguration: AdhesiveFacingConfiguration) { savePayload(.adhesiveFacing(adhesiveFacingConfiguration)) }
    private func save(openingConfiguration: OpeningConfiguration) { savePayload(.openings(openingConfiguration)) }

    private func savePayload(_ payload: WorkConfiguration) {
        do {
            try store.createConfiguredWork(projectID: projectID, name: workName, type: workType,
                payload: payload, roomID: roomID, newRoomName: newRoomName, document: layoutDocument, level: level, zone: zone)
            finish()
        } catch { errorMessage = "L’ouvrage n’a pas pu être enregistré. \(error.localizedDescription)" }
    }

    private func finish() {
        dismiss()
        onFinished()
    }
}

private struct DoublageConfiguratorHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var references = DoublageReferenceStore()
    let initialConfiguration: DoublageConfiguration?
    let startsAtResult: Bool
    let initialStep: Int?
    let onSave: (DoublageConfiguration) -> Void

    init(
        initialConfiguration: DoublageConfiguration? = nil,
        startsAtResult: Bool = false,
        initialStep: Int? = nil,
        onSave: @escaping (DoublageConfiguration) -> Void
    ) {
        self.initialConfiguration = initialConfiguration
        self.startsAtResult = startsAtResult
        self.initialStep = initialStep
        self.onSave = onSave
    }

    var body: some View {
        DoublageConfiguratorView(
            initialConfiguration: initialConfiguration,
            startsAtResult: startsAtResult,
            initialStep: initialStep,
            onSave: onSave,
            onClose: { dismiss() }
        )
        .environmentObject(references)
        .task { if references.catalogue == nil { await references.load() } }
    }
}

private struct CloisonDistributionConfiguratorHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var references = CloisonDistributionReferenceStore()
    let initialConfiguration: CloisonDistributionConfiguration?
    let startsAtResult: Bool
    let showsCloseButton: Bool
    let onSave: (CloisonDistributionConfiguration) -> Void

    init(
        initialConfiguration: CloisonDistributionConfiguration? = nil,
        startsAtResult: Bool = false,
        showsCloseButton: Bool = true,
        onSave: @escaping (CloisonDistributionConfiguration) -> Void
    ) {
        self.initialConfiguration = initialConfiguration
        self.startsAtResult = startsAtResult
        self.showsCloseButton = showsCloseButton
        self.onSave = onSave
    }

    var body: some View {
        CloisonDistributionConfiguratorView(
            initialConfiguration: initialConfiguration,
            startsAtResult: startsAtResult,
            onSave: onSave,
            onClose: { dismiss() },
            showsCloseButton: showsCloseButton
        )
        .environmentObject(references)
        .task { if references.systems.isEmpty { await references.load() } }
    }
}

private struct AlveolarPartitionConfiguratorHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var references = AlveolarPartitionReferenceStore()
    let initialConfiguration: AlveolarPartitionConfiguration?
    let startsAtResult: Bool
    let showsCloseButton: Bool
    let onSave: (AlveolarPartitionConfiguration) -> Void

    init(
        initialConfiguration: AlveolarPartitionConfiguration? = nil,
        startsAtResult: Bool = false,
        showsCloseButton: Bool = true,
        onSave: @escaping (AlveolarPartitionConfiguration) -> Void
    ) {
        self.initialConfiguration = initialConfiguration
        self.startsAtResult = startsAtResult
        self.showsCloseButton = showsCloseButton
        self.onSave = onSave
    }

    var body: some View {
        AlveolarPartitionConfiguratorView(
            initialConfiguration: initialConfiguration,
            startsAtResult: startsAtResult,
            onSave: onSave,
            onClose: { dismiss() },
            showsCloseButton: showsCloseButton
        )
        .environmentObject(references)
        .task { if references.panels.isEmpty { await references.load() } }
    }
}

private struct BondedLiningConfiguratorHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var references = BondedLiningReferenceStore()
    let initialConfiguration: BondedLiningConfiguration?
    let startsAtResult: Bool
    let showsCloseButton: Bool
    let onSave: (BondedLiningConfiguration) -> Void

    init(initialConfiguration: BondedLiningConfiguration? = nil, startsAtResult: Bool = false, showsCloseButton: Bool = true, onSave: @escaping (BondedLiningConfiguration) -> Void) {
        self.initialConfiguration = initialConfiguration
        self.startsAtResult = startsAtResult
        self.showsCloseButton = showsCloseButton
        self.onSave = onSave
    }

    var body: some View {
        BondedLiningConfiguratorView(initialConfiguration: initialConfiguration, startsAtResult: startsAtResult, onSave: onSave, onClose: { dismiss() }, showsCloseButton: showsCloseButton)
            .environmentObject(references)
            .task { if references.references.isEmpty { await references.load() } }
    }
}

private struct FurringLiningConfiguratorHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var references = FurringLiningReferenceStore()
    let initialConfiguration: FurringLiningConfiguration?
    let startsAtResult: Bool
    let initialStep: Int?
    let showsCloseButton: Bool
    let onSave: (FurringLiningConfiguration) -> Void

    init(initialConfiguration: FurringLiningConfiguration? = nil, startsAtResult: Bool = false, initialStep: Int? = nil, showsCloseButton: Bool = true, onSave: @escaping (FurringLiningConfiguration) -> Void) {
        self.initialConfiguration = initialConfiguration; self.startsAtResult = startsAtResult; self.initialStep = initialStep; self.showsCloseButton = showsCloseButton; self.onSave = onSave
    }

    var body: some View {
        FurringLiningConfiguratorView(initialConfiguration: initialConfiguration, startsAtResult: startsAtResult, initialStep: initialStep, onSave: onSave, onClose: { dismiss() }, showsCloseButton: showsCloseButton)
            .environmentObject(references)
            .task { if references.payload == nil { await references.load() } }
    }
}

private struct AdhesiveFacingConfiguratorHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var references = AdhesiveFacingReferenceStore()
    let initialConfiguration: AdhesiveFacingConfiguration?
    let startsAtResult: Bool
    let showsCloseButton: Bool
    let onSave: (AdhesiveFacingConfiguration) -> Void

    init(initialConfiguration: AdhesiveFacingConfiguration? = nil, startsAtResult: Bool = false, showsCloseButton: Bool = true, onSave: @escaping (AdhesiveFacingConfiguration) -> Void) {
        self.initialConfiguration = initialConfiguration
        self.startsAtResult = startsAtResult
        self.showsCloseButton = showsCloseButton
        self.onSave = onSave
    }

    var body: some View {
        AdhesiveFacingConfiguratorView(
            initialConfiguration: initialConfiguration,
            startsAtResult: startsAtResult,
            onSave: onSave,
            onClose: { dismiss() },
            showsCloseButton: showsCloseButton
        )
        .environmentObject(references)
        .task { if references.options.isEmpty { await references.load() } }
    }
}

private extension String { var clean: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
