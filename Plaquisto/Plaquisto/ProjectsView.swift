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
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var showingEdit = false
    @State private var showingNewWork = false
    @State private var confirmingDelete = false
    @State private var workToDelete: WorkItem?
    @State private var workToRename: WorkItem?
    @State private var isolationWorkID: UUID?
    @State private var errorMessage = ""

    private var project: ProjectItem? { store.project(id: projectID) }

    var body: some View {
        Group {
            if let project {
                List {
                    Section("Projet") {
                        if !project.client.isEmpty { LabeledContent("Client", value: project.client) }
                        if !project.address.isEmpty { LabeledContent("Adresse", value: project.address) }
                        if !project.notes.isEmpty { Text(project.notes).foregroundStyle(.secondary) }
                    }
                    Section("Pièces") {
                        ForEach(project.rooms) { room in
                            NavigationLink { ProjectRoomDetailView(projectID: projectID, roomID: room.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(room.name)
                                    Text("\(project.ownedWorks(in: room.id).count) ouvrages").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        NavigationLink("Organiser les pièces et les ouvrages") { ProjectRoomOrganizationView(projectID: projectID) }
                    }
                    Section("Ouvrages") {
                        if project.works.isEmpty {
                            Text("Aucun ouvrage enregistré.").foregroundStyle(.secondary)
                        } else {
                            ForEach(project.works) { work in
                                VStack(alignment: .leading, spacing: 7) {
                                    NavigationLink {
                                        SavedWorkView(work: work)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(work.name).font(.headline)
                                            if let configuration = work.openingConfiguration {
                                                ForEach(OpeningSummaryFormatter.lines(for: configuration)) { line in
                                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                        Text("•")
                                                        Text(openingSummary(line))
                                                    }
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                }
                                            } else {
                                                Text(work.type.title).font(.subheadline).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    if work.layoutDocument != nil && !work.isPartition {
                                        NavigationLink { LinkedLayoutView(work:work) } label: {
                                            Label("Calepinage 2D existant",systemImage:"square.grid.3x3").font(.caption).foregroundStyle(.teal)
                                        }
                                        if work.layoutNeedsRecalculation == true {
                                            Label("Calepinage modifié : ouvrez l’ouvrage pour recalculer son quantitatif.",systemImage:"exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                    NavigationLink {
                                        WorkComponentsView(projectID: projectID, workID: work.id)
                                    } label: {
                                        Label("Composants d’ouvrage (\(work.components.count))", systemImage: "square.stack.3d.up")
                                            .font(.caption)
                                    }
                                    if let conflict = store.openingJoineryConflict(
                                        projectID: projectID,
                                        referenceWorkID: work.id
                                    ) {
                                        Button {
                                            isolationWorkID = work.id
                                        } label: {
                                            Label(joineryConflictSummary(conflict), systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.orange)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .swipeActions {
                                    Button { workToDelete = work } label: { Label("Supprimer", systemImage: "trash") }
                                        .tint(.red)
                                    Button { duplicateWork(work) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                                        .tint(.blue)
                                    Button { workToRename = work } label: { Label("Renommer", systemImage: "pencil") }
                                        .tint(.orange)
                                }
                            }
                        }
                        Button { showingNewWork = true } label: { Label("Ajouter un ouvrage", systemImage: "plus.circle.fill") }
                    }
                    if !project.works.isEmpty {
                        Section("Quantitatifs regroupés") {
                            NavigationLink {
                                CombinedQuantityView(works: project.works, title: "Quantitatif total")
                            } label: {
                                Label("Afficher le quantitatif total", systemImage: "sum")
                            }
                            NavigationLink {
                                WorkSelectionView(works: project.works)
                            } label: {
                                Label("Sélectionner des ouvrages", systemImage: "checklist")
                            }
                        }
                    }
                    Section { Button("Supprimer le projet", role: .destructive) { confirmingDelete = true } }
                }
                .navigationTitle(project.name)
                .navigationDestination(isPresented: Binding(
                    get: { isolationWorkID != nil },
                    set: { if !$0 { isolationWorkID = nil } }
                )) {
                    if let isolationWorkID,
                       let work = store.project(id: projectID)?.works.first(where: { $0.id == isolationWorkID }) {
                        SavedWorkView(work: work, opensIsolationStep: true)
                    } else {
                        ContentUnavailableView("Ouvrage introuvable", systemImage: "exclamationmark.triangle")
                    }
                }
                .toolbar { Button("Modifier") { showingEdit = true } }
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
            } else {
                ContentUnavailableView("Projet introuvable", systemImage: "exclamationmark.triangle")
            }
        }
        .alert("Action impossible", isPresented: errorBinding) { Button("OK") { errorMessage = "" } } message: { Text(errorMessage) }
    }

    private var errorBinding: Binding<Bool> { Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } }) }
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
                TextField("Surface au sol en m² (facultatif)", text: $area).keyboardType(.decimalPad)
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
                Section("Pièce propriétaire des ouvrages") {
                    ForEach(project.works) { work in
                        Picker(work.name, selection: Binding<UUID?>(get: { work.roomID }, set: { value in
                            guard let value else { return }
                            let adjacent = work.isPartition ? Array(Set(work.linkedRoomIDs + [work.roomID].compactMap { $0 }).subtracting([value])) : []
                            do { try store.assignWork(projectID: projectID, workID: work.id, ownerRoomID: value, adjacentRoomIDs: adjacent) }
                            catch { self.error = "Rattachement impossible." }
                        })) {
                            Text("À rattacher").tag(nil as UUID?)
                            ForEach(project.rooms) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .disabled(work.openingConfiguration?.sourceWorkID != nil)
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

private struct ProjectRoomDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    let roomID: UUID
    var body: some View {
        if let project = store.project(id: projectID), let room = project.rooms.first(where: { $0.id == roomID }) {
            List {
                Section("Ouvrages de la pièce") {
                    ForEach(project.ownedWorks(in: roomID)) { work in
                        NavigationLink(work.name) { WorkComponentsView(projectID: projectID, workID: work.id) }
                    }
                }
                if !project.linkedWorks(in: roomID).isEmpty {
                    Section("Cloisons liées — comptées dans leur pièce propriétaire") {
                        ForEach(project.linkedWorks(in: roomID)) { work in
                            NavigationLink(work.name) { WorkComponentsView(projectID: projectID, workID: work.id) }
                        }
                    }
                }
                NavigationLink("Quantitatif de la pièce") {
                    CombinedQuantityView(works: project.ownedWorks(in: roomID), title: room.name)
                }
            }.navigationTitle(room.name)
        }
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
                    Text("Le quantitatif est calculé dans le formulaire de l’ouvrage. Les métrés de plusieurs composants ne sont pas encore regroupés automatiquement.")
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
                                // Choose the smaller room only on initial association. Later changes
                                // keep explicit ownership, so an area edit cannot move quantities silently.
                                let candidates = [owner] + links
                                let firstAssociation = enabled && work.linkedRoomIDs.isEmpty && work.components.allSatisfy { $0.plans.isEmpty }
                                let selectedOwner = firstAssociation ? (store.suggestedPartitionOwner(projectID: projectID, roomIDs: candidates) ?? owner) : owner
                                do { try store.assignWork(projectID: projectID, workID: workID, ownerRoomID: selectedOwner, adjacentRoomIDs: candidates.filter { $0 != selectedOwner }) }
                                catch { self.error = "Modification impossible." }
                            }))
                        }
                    }
                }
                ForEach(work.components) { component in
                    Section(component.name) {
                        if component.surface == nil { Text("Contour à renseigner").foregroundStyle(.secondary) }
                        if [.distributionPartition, .alveolarPartition].contains(work.type) {
                            ForEach(project.rooms.filter { $0.id == work.roomID || work.linkedRoomIDs.contains($0.id) }) { room in
                                componentLink(component, side: room.id, title: "Côté \(room.name)")
                            }
                        } else {
                            componentLink(component, side: nil, title: "Plan de calepinage")
                        }
                    }
                }
                Section("Ajouter un composant d’ouvrage") {
                    TextField("Exemple : Mur A", text: $name)
                    Button("Ajouter le composant") {
                        do { try store.addComponent(projectID: projectID, workID: workID, name: name); name = ""; error = "" }
                        catch { self.error = "Nom vide ou déjà utilisé." }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.navigationTitle(work.name)
        }
    }
    private func componentLink(_ component: WorkComponentRecord, side: UUID?, title: String) -> some View {
        let plan = component.plans.first { $0.sideRoomID == side } ?? ComponentLayoutPlan(sideRoomID: side)
        return NavigationLink {
            ComponentPlanEditorView(projectID: projectID, workID: workID, component: component, side: side,
                kind: work?.type.category == .ceilings ? .ceiling : .wall, sharedFraming: work?.isPartition == true)
        } label: {
            VStack(alignment: .leading) {
                Label(title, systemImage: "square.grid.3x3")
                if component.plans.contains(where: { $0.sideRoomID == side }) && plan.geometryRevision != component.geometryRevision {
                    Text("Contour ou ossature modifié — calepinage à vérifier").font(.caption).foregroundStyle(.orange)
                }
            }
        }
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
    @State private var openedComponent: WorkComponentRecord

    init(projectID: UUID, workID: UUID, component: WorkComponentRecord, side: UUID?, kind: LayoutSupportKind, sharedFraming: Bool) {
        self.projectID = projectID; self.workID = workID; self.side = side
        self.kind = kind; self.sharedFraming = sharedFraming
        _openedComponent = State(initialValue: component)
    }

    var body: some View {
        let plan = openedComponent.plans.first { $0.sideRoomID == side } ?? ComponentLayoutPlan(sideRoomID: side)
        SheetLayoutView(initialDocument: openedComponent.document(for: plan), onSaveDocument: { document in
            try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: openedComponent.id,
                sideRoomID: side, document: document, expectedGeometryRevision: openedComponent.geometryRevision)
        }, requiredSupportKind: kind, sharedPartitionFraming: sharedFraming)
        .environmentObject(catalogue)
        .task { await catalogue.load() }
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
    @State private var roomName = ""
    @State private var category = WorkCategory.ceilings
    @State private var type = WorkType.ceilingOnFurring
    private struct Draft: Identifiable {
        let id = UUID()
        let name: String
        let type: WorkType
        let roomName: String
    }
    @State private var configurationDraft: Draft?
    @State private var activeAlert: NewWorkAlert?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var availableTypes: [WorkType] {
        WorkType.allCases.filter { $0.category == category }
    }

    private var canConfigure: Bool {
        availableTypes.contains(type) && !roomName.clean.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if category == .openings {
                    categoryPicker
                    .padding(20)
                    .background(Color(.systemGroupedBackground))

                    OpeningLabView(
                        heightOptions: store.openingHeightOptions(projectID: projectID)
                    ) { configuration in
                        saveOpening(configuration)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            categoryPicker

                        roomNameField

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ouvrage")
                                .font(.headline)

                            if availableTypes.isEmpty {
                                Text("Aucun ouvrage disponible dans cette catégorie pour le moment.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                Picker("Type d’ouvrage", selection: $type) {
                                    ForEach(availableTypes) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(category == .openings ? "Ouvertures" : "Ajouter un ouvrage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                if category != .openings {
                    ToolbarItem(placement: .confirmationAction) { Button("Configurer") { prepareConfiguration() }.disabled(!canConfigure) }
                }
            }
            .fullScreenCover(item: $configurationDraft) { draft in
                WorkConfiguratorContainer(projectID: projectID, workName: draft.name, workType: draft.type, onFinished: { dismiss() }, newRoomName: draft.roomName)
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .duplicateName(let duplicateName):
                    Alert(
                        title: Text("Nom déjà utilisé"),
                        message: Text("Un ouvrage nommé « \(duplicateName) » existe déjà dans ce projet. Choisissez un autre nom."),
                        dismissButton: .default(Text("OK"))
                    )
                case .saveFailed:
                    Alert(
                        title: Text("Enregistrement impossible"),
                        message: Text("Les ouvertures n’ont pas pu être enregistrées sur cet appareil."),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    private var roomNameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pièce concernée")
                .font(.headline)
            if let rooms = store.project(id: projectID)?.rooms, !rooms.isEmpty {
                Menu("Choisir une pièce existante") {
                    ForEach(rooms) { room in Button(room.name) { roomName = room.name } }
                }
            }
            TextField("Exemple : Salon", text: $roomName)
                .textFieldStyle(.plain)
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !roomName.clean.isEmpty {
                Text(type.generatedName(roomName: roomName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Catégorie d’ouvrage")
                .font(.title2.bold())

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(WorkCategory.allCases) { item in
                    Button {
                        category = item
                        if let firstType = WorkType.allCases.first(where: { $0.category == item }) {
                            type = firstType
                        }
                    } label: {
                        Text(item.cardTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 112)
                            .padding(.horizontal, 10)
                            .background(item.cardColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white, lineWidth: category == item ? 4 : 0)
                                    .padding(4)
                            }
                            .shadow(color: category == item ? item.cardColor.opacity(0.28) : .clear, radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
        }
    }

    private func prepareConfiguration() {
        let generatedName = type.generatedName(roomName: roomName)
        if store.workNameExists(projectID: projectID, name: generatedName) {
            activeAlert = .duplicateName(generatedName)
        } else {
            openConfigurator(with: generatedName)
        }
    }

    private func saveOpening(_ configuration: OpeningConfiguration) {
        let linkedRoomName = configuration.sourceWorkID.flatMap { sourceID in
            store.project(id: projectID)?.works.first(where: { $0.id == sourceID })?.inferredRoomName
        }
        let effectiveRoomName = linkedRoomName ?? configuration.roomName
        let workName = effectiveRoomName.map { WorkType.openings.generatedName(roomName: $0) }
            ?? store.defaultWorkName(projectID: projectID, type: .openings)
        if store.workNameExists(projectID: projectID, name: workName) {
            activeAlert = .duplicateName(workName)
            return
        }
        do {
            _ = try store.createConfiguredWork(
                projectID: projectID,
                name: workName,
                type: .openings,
                payload: .openings(configuration), roomID: nil, newRoomName: effectiveRoomName
            )
            dismiss()
        } catch {
            activeAlert = .saveFailed
        }
    }

    private func openConfigurator(with workName: String) {
        configurationDraft = Draft(name: workName, type: type, roomName: roomName)
    }
}

private enum NewWorkAlert: Identifiable {
    case duplicateName(String)
    case saveFailed

    var id: String {
        switch self {
        case .duplicateName: "duplicate-name"
        case .saveFailed: "save-failed"
        }
    }
}

private extension WorkCategory {
    var cardTitle: String {
        switch self {
        case .ceilings: "Plafonds"
        case .partitions: "Cloisons"
        case .wallInsulation: "Isolation des murs"
        case .openings: "Ouvertures"
        }
    }

    var cardColor: Color {
        switch self {
        case .ceilings: Color(red: 0.20, green: 0.43, blue: 0.57)
        case .partitions: Color(red: 0.76, green: 0.43, blue: 0.24)
        case .wallInsulation: Color(red: 0.22, green: 0.49, blue: 0.38)
        case .openings: Color(red: 0.45, green: 0.34, blue: 0.58)
        }
    }
}

struct SavedWorkView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let work: WorkItem
    var opensIsolationStep = false
    @State private var errorMessage = ""
    private var currentWork: WorkItem { store.project(id: work.projectID)?.works.first(where: { $0.id == work.id }) ?? work }
    private var recalculationDocument: LayoutDocument? { currentWork.layoutNeedsRecalculation == true ? currentWork.layoutDocument : nil }

    var body: some View {
        Group {
            switch currentWork.type {
            case .ceilingOnFurring:
                CeilingConfiguratorView(initialConfiguration: LayoutWorkGeometry.ceiling(recalculationDocument,base:currentWork.ceilingConfiguration ?? .init()), startsAtResult: recalculationDocument == nil, preserveInitialSpacing:true) { configuration in
                    do { try store.updateWork(currentWork, configuration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .ceilingOnRailsAndStuds:
                RailStudCeilingConfiguratorView(initialConfiguration: LayoutWorkGeometry.railCeiling(recalculationDocument,base:currentWork.railStudCeilingConfiguration ?? .init()), startsAtResult: recalculationDocument == nil) { configuration in
                    do { try store.updateWork(currentWork, railStudCeilingConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .modularCeiling:
                ModularCeilingConfiguratorView(
                    initialConfiguration: currentWork.modularCeilingConfiguration,
                    startsAtResult: true
                ) { configuration in
                    do { try store.updateWork(currentWork, modularCeilingConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningStuds:
                DoublageConfiguratorHost(
                    initialConfiguration: LayoutWorkGeometry.lining(recalculationDocument,base:currentWork.doublageConfiguration ?? .init()),
                    startsAtResult: !opensIsolationStep && recalculationDocument == nil,
                    initialStep: opensIsolationStep ? 4 : nil
                ) { configuration in
                    do { try store.updateWork(currentWork, doublageConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .distributionPartition:
                CloisonDistributionConfiguratorHost(initialConfiguration: LayoutWorkGeometry.partition(recalculationDocument,base:currentWork.cloisonDistributionConfiguration ?? .init()), startsAtResult: recalculationDocument == nil) { configuration in
                    do { try store.updateWork(currentWork, cloisonDistributionConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .alveolarPartition:
                AlveolarPartitionConfiguratorHost(initialConfiguration: currentWork.alveolarPartitionConfiguration, startsAtResult: true) { configuration in
                    do { try store.updateWork(currentWork, alveolarPartitionConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningBonded:
                BondedLiningConfiguratorHost(initialConfiguration: currentWork.bondedLiningConfiguration, startsAtResult: true) { configuration in
                    do { try store.updateWork(currentWork, bondedLiningConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningFurrings:
                FurringLiningConfiguratorHost(
                    initialConfiguration: LayoutWorkGeometry.furring(recalculationDocument,base:currentWork.furringLiningConfiguration ?? .init()),
                    startsAtResult: !opensIsolationStep && recalculationDocument == nil,
                    initialStep: opensIsolationStep ? 4 : nil
                ) { configuration in
                    do { try store.updateWork(currentWork, furringLiningConfiguration: configuration); dismiss() }
                    catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
                }
            case .peripheralLiningAdhesiveFacing:
                AdhesiveFacingConfiguratorHost(initialConfiguration: currentWork.adhesiveFacingConfiguration, startsAtResult: true) { configuration in
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
            }
        }
        .navigationTitle(currentWork.name)
        .alert("Enregistrement impossible", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) { Button("OK") {} } message: { Text(errorMessage) }
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
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
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
                payload: payload, roomID: roomID, newRoomName: newRoomName, document: layoutDocument)
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
