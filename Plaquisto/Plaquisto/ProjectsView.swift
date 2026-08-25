import SwiftUI

struct ProjectsHomeView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var showingNewProject = false

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun chantier", systemImage: "building.2")
                    } description: {
                        Text("Créez votre premier chantier pour y enregistrer vos ouvrages et leurs quantitatifs.")
                    } actions: {
                        Button("Créer un chantier") { showingNewProject = true }.buttonStyle(.borderedProminent)
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
                    }
                }
            }
            .navigationTitle("Mes chantiers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewProject = true } label: { Label("Nouveau chantier", systemImage: "plus") }
                }
            }
            .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
            .sheet(isPresented: $showingNewProject) { ProjectFormView() }
        }
        .tint(Color(red: 0.12, green: 0.38, blue: 0.29))
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
    @State private var errorMessage = ""

    private var project: ProjectItem? { store.project(id: projectID) }

    var body: some View {
        Group {
            if let project {
                List {
                    Section("Chantier") {
                        if !project.client.isEmpty { LabeledContent("Client", value: project.client) }
                        if !project.address.isEmpty { LabeledContent("Adresse", value: project.address) }
                        if !project.notes.isEmpty { Text(project.notes).foregroundStyle(.secondary) }
                    }
                    Section("Ouvrages") {
                        if project.works.isEmpty {
                            Text("Aucun ouvrage enregistré.").foregroundStyle(.secondary)
                        } else {
                            ForEach(project.works) { work in
                                NavigationLink {
                                    SavedWorkView(work: work)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(work.name).font(.headline)
                                        Text(work.type.title).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions {
                                    Button("Supprimer", role: .destructive) { workToDelete = work }
                                }
                            }
                        }
                        Button { showingNewWork = true } label: { Label("Ajouter un ouvrage", systemImage: "plus.circle.fill") }
                    }
                    Section { Button("Supprimer le chantier", role: .destructive) { confirmingDelete = true } }
                }
                .navigationTitle(project.name)
                .toolbar { Button("Modifier") { showingEdit = true } }
                .sheet(isPresented: $showingEdit) { ProjectFormView(project: project) }
                .sheet(isPresented: $showingNewWork) { NewWorkView(projectID: projectID) }
                .confirmationDialog("Supprimer ce chantier et tous ses ouvrages ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Supprimer définitivement", role: .destructive) { deleteProject() }
                    Button("Annuler", role: .cancel) {}
                }
                .confirmationDialog("Supprimer cet ouvrage ?", isPresented: Binding(get: { workToDelete != nil }, set: { if !$0 { workToDelete = nil } }), titleVisibility: .visible) {
                    Button("Supprimer définitivement", role: .destructive) { if let workToDelete { deleteWork(workToDelete) } }
                    Button("Annuler", role: .cancel) { workToDelete = nil }
                }
            } else {
                ContentUnavailableView("Chantier introuvable", systemImage: "exclamationmark.triangle")
            }
        }
        .alert("Action impossible", isPresented: errorBinding) { Button("OK") { errorMessage = "" } } message: { Text(errorMessage) }
    }

    private var errorBinding: Binding<Bool> { Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } }) }
    private func deleteProject() { do { try store.deleteProject(id: projectID); dismiss() } catch { errorMessage = "Le chantier n’a pas pu être supprimé." } }
    private func deleteWork(_ work: WorkItem) { do { try store.deleteWork(projectID: projectID, workID: work.id); workToDelete = nil } catch { errorMessage = "L’ouvrage n’a pas pu être supprimé." } }
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
                    TextField("Nom du chantier", text: $name)
                    TextField("Client (facultatif)", text: $client)
                    TextField("Adresse (facultative)", text: $address)
                    TextField("Notes (facultatives)", text: $notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle(project == nil ? "Nouveau chantier" : "Modifier le chantier")
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
        } catch { errorMessage = "Le chantier n’a pas pu être enregistré sur cet appareil."; isSaving = false }
    }
}

private struct NewWorkView: View {
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var name = ""
    @State private var type = WorkType.ceilingOnFurring
    @State private var configuring = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nouvel ouvrage") {
                    TextField("Nom de l’ouvrage", text: $name)
                    Picker("Type", selection: $type) { ForEach(WorkType.allCases) { Text($0.title).tag($0) } }
                }
            }
            .navigationTitle("Ajouter un ouvrage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Configurer") { configuring = true }.disabled(name.clean.isEmpty) }
            }
            .fullScreenCover(isPresented: $configuring) {
                WorkConfiguratorContainer(projectID: projectID, workName: name.clean, workType: type) { dismiss() }
            }
        }
    }
}

private struct SavedWorkView: View {
    @EnvironmentObject private var store: ProjectStore
    let work: WorkItem
    @State private var errorMessage = ""
    private var currentWork: WorkItem { store.project(id: work.projectID)?.works.first(where: { $0.id == work.id }) ?? work }

    var body: some View {
        ConfiguratorView(initialConfiguration: currentWork.configuration, startsAtResult: true) { configuration in
            do { try store.updateWork(currentWork, configuration: configuration) }
            catch { errorMessage = "Les modifications n’ont pas pu être enregistrées." }
        }
        .navigationTitle(currentWork.name)
        .alert("Enregistrement impossible", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) { Button("OK") {} } message: { Text(errorMessage) }
    }
}

private struct WorkConfiguratorContainer: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let workName: String
    let workType: WorkType
    let onFinished: () -> Void
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ConfiguratorView { configuration in
                do {
                    _ = try store.createWork(projectID: projectID, name: workName, type: workType, configuration: configuration)
                    dismiss()
                    onFinished()
                } catch { errorMessage = "L’ouvrage n’a pas pu être enregistré." }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .alert("Enregistrement impossible", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) { Button("OK") {} } message: { Text(errorMessage) }
    }
}

private extension String { var clean: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
