import SwiftUI

private enum LabRoute: Hashable {
    case project(UUID)
    case survey(UUID)
    case work(project: UUID, work: UUID)
}

struct ContrastLabRoot: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var tab = 0
    @State private var settings = false
    var body: some View {
        TabView(selection: $tab) {
            LabProjectsView(onSettings: { settings = true })
                .tabItem { Label("Projets", systemImage: "folder") }.tag(0)
            ScannerDebugView(onOpenAccount: { settings = true })
                .tabItem { Label("Scanner", systemImage: "viewfinder") }.tag(1)
            ToolsHomeView(onOpenAccount: { settings = true })
                .tabItem { Label("Outils", systemImage: "wrench.and.screwdriver") }.tag(2)
            StockHomeView()
                .tabItem { Label("Stock", systemImage: "shippingbox") }.tag(3)
        }
        .onChange(of: store.projectNavigationRequest) { _, request in if request != nil { tab = 0 } }
        .sheet(isPresented: $settings) {
            NavigationStack {
                List {
                    Section {
                        Label("Plaquisto Lab · Contraste", systemImage: "sparkles")
                        Text("Vos projets de test sont séparés de ceux de Plaquisto.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Section {
                        NavigationLink("Ouvrir l’interface actuelle") {
                            ProjectsHomeView().environment(\.interfacePresentation, .standard)
                        }
                    } header: { Text("Comparer") } footer: {
                        Text("Les deux présentations utilisent ici les mêmes données du Lab. Les calculs et fonctions métier sont conservés.")
                    }
                    MaquetteRenderingSettingsSection()
                    Section("Application") {
                        LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    }
                }.navigationTitle("Réglages")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { settings = false } } }
            }
        }
    }
}

private struct LabCard: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.black.opacity(0.035)) }
            .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
    }
}
private struct LabPrimaryLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(.white)
            .background(ContrastPalette.ink, in: RoundedRectangle(cornerRadius: 17))
    }
}

/// Swipe actions for cards hosted in ScrollView (SwiftUI swipeActions only
/// works on List rows). Vertical scrolling remains simultaneous and unchanged.
private struct LabSwipeActions: ViewModifier {
    let rename: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var revealed = false
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    withAnimation(.easeInOut(duration: 0.22)) { revealed = value.translation.width < -30 }
                })
            if revealed {
                HStack(spacing: 8) {
                    action("Renommer", "pencil", .orange, rename)
                    action("Dupliquer", "doc.on.doc", .blue, duplicate)
                    action("Supprimer", "trash", .red, delete)
                }.padding(.top, 8).transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .contextMenu {
            Button("Renommer", systemImage: "pencil", action: rename)
            Button("Dupliquer", systemImage: "doc.on.doc", action: duplicate)
            Button("Supprimer", systemImage: "trash", role: .destructive, action: delete)
        }
        .accessibilityAction(named: "Renommer", rename)
        .accessibilityAction(named: "Dupliquer", duplicate)
        .accessibilityAction(named: "Supprimer", delete)
    }
    private func action(_ title: String, _ icon: String, _ tint: Color, _ operation: @escaping () -> Void) -> some View {
        Button { operation(); withAnimation { revealed = false } } label: {
            VStack(spacing: 4) { Image(systemName: icon); Text(title).font(.caption) }
                .frame(maxWidth: .infinity, minHeight: 52)
        }.buttonStyle(.bordered).tint(tint)
    }
}

private struct LabProjectsView: View {
    @EnvironmentObject private var store: ProjectStore
    let onSettings: () -> Void
    @State private var search = ""
    @State private var path: [LabRoute] = []
    @State private var adding = false
    @State private var deleting: ProjectItem?
    @State private var renaming: ProjectItem?
    @State private var renameText = ""
    @State private var error: String?
    private var visible: [ProjectItem] {
        store.projects.filter { ProjectGalleryIndex.matches($0, surveys: store.surveys(projectID: $0.id), query: search) }
    }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("\(visible.count) projet\(visible.count == 1 ? "" : "s")").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { adding = true } label: { Label("Nouveau", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("lab.newProject")
                    }
                    if let error = store.lastError { Text(error).foregroundStyle(.red) }
                    if store.projects.isEmpty {
                        ContentUnavailableView("Votre premier projet", systemImage: "folder.badge.plus", description: Text("Créez un projet ou commencez par un scan."))
                    } else if visible.isEmpty { ContentUnavailableView.search(text: search) }
                    LazyVStack(spacing: 16) {
                        ForEach(visible) { project in
                            LabProjectCard(project: project, survey: store.surveys(projectID: project.id).max { $0.scanDate < $1.scanDate }) {
                                path.append(.project(project.id))
                            }.accessibilityIdentifier("lab.project.\(project.id)")
                            .modifier(LabSwipeActions(rename: { renameText = project.name; renaming = project },
                                duplicate: { perform { try store.duplicateProject(id: project.id) } }, delete: { deleting = project }))
                        }
                    }
                }.padding(20)
            }.background(ContrastPalette.paper)
            .navigationTitle("Mes projets")
            .searchable(text: $search, prompt: "Projet, lieu ou date")
            .toolbar { Button(action: onSettings) { Image(systemName: "gearshape") }.accessibilityLabel("Réglages de l’application") }
            .navigationDestination(for: LabRoute.self) { route in
                switch route {
                case .project(let id): LabProjectView(projectID: id)
                case .survey(let id): ProjectSurveyDetailView(surveyID: id)
                case .work(let project, let work): LabWorkView(projectID: project, workID: work)
                }
            }
            .onChange(of: store.projectNavigationRequest, initial: true) { _, request in
                if let request { path = [.project(request.projectID)] }
            }
            .sheet(isPresented: $adding) { ProjectFormView() }
            .alert("Renommer le projet", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nom", text: $renameText)
                Button("Enregistrer") {
                    if let item = renaming { perform { try store.updateProject(id: item.id, name: renameText, client: item.client, address: item.address, notes: item.notes) } }
                    renaming = nil
                }.disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Annuler", role: .cancel) { renaming = nil }
            }
            .task(id: store.surveys.map(\.id)) {
                for survey in store.surveys where survey.captureAddress == nil && survey.captureLocation != nil {
                    guard !Task.isCancelled else { return }
                    if let address = await ScanAddressSuggestion.address(for: survey.captureLocation) {
                        try? store.cacheScanAddress(surveyID: survey.id, address: address)
                    }
                }
            }
            .confirmationDialog("Supprimer ce projet et tous ses ouvrages ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let deleting { perform { try store.deleteProject(id: deleting.id) } }; deleting = nil
                }
                Button("Annuler", role: .cancel) { deleting = nil }
            }
            .alert("Action impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func perform(_ operation: () throws -> Void) { do { try operation() } catch { self.error = error.localizedDescription } }
}

private struct LabProjectCard: View {
    let project: ProjectItem
    let survey: ProjectSurveyRecord?
    let onOpen: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                if let survey, !survey.checkpoints.isEmpty {
                    SurveyThumbnailView(survey: survey).frame(height: 156).clipped().background(ContrastPalette.wash)
                }
            }.buttonStyle(.plain).accessibilityLabel("Ouvrir \(project.name)")
            VStack(alignment: .leading, spacing: 9) {
                Button(action: onOpen) {
                HStack {
                    Text(project.name).font(.title3.weight(.bold)); Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44)
                }.buttonStyle(.plain)
                let address = project.address.isEmpty ? (survey?.captureAddress ?? "") : project.address
                if !address.isEmpty { ProjectAddressMenu(address: address).font(.subheadline).foregroundStyle(ContrastPalette.blue).lineLimit(2) }
                if survey == nil {
                    ForEach(ProjectGalleryIndex.summary(project), id: \.title) { item in
                        Text("\(item.area.formatted(.number.precision(.fractionLength(0...1)))) m² · \(item.title)")
                            .font(.subheadline).foregroundStyle(ContrastPalette.blue)
                    }
                }
                Text("\(project.visibleWorks.count) ouvrage(s) · " + (survey.map { "Scan du \($0.scanDate.formatted(date: .numeric, time: .omitted))" } ?? "Créé le \(project.createdAt.formatted(date: .numeric, time: .omitted))"))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.foregroundStyle(ContrastPalette.ink).clipShape(RoundedRectangle(cornerRadius: 22)).modifier(LabCard())
    }
}

private struct LabWorkPreview: View {
    @EnvironmentObject private var store: ProjectStore
    let work: WorkItem
    var body: some View {
        if let source = work.components.compactMap(\.surveySource).first,
           let survey = store.surveys.first(where: { $0.id == source.surveyID }) {
            SurveyThumbnailView(survey: survey, selected: WorkPreviewSelection.surfaceIDs(work: work, survey: survey))
        } else {
            VStack(spacing: 5) {
                Image(systemName: work.type.category == .ceilings ? "square.3.layers.3d" : "rectangle.split.3x1").font(.system(size: 30, weight: .light))
                Text("Sans scan").font(.caption2)
            }.foregroundStyle(ContrastPalette.blue).frame(maxWidth: .infinity, maxHeight: .infinity).background(ContrastPalette.wash)
        }
    }
}

private struct LabProjectView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var adding = false
    @State private var editing = false
    @State private var deleting = false
    @State private var surveyToDelete: ProjectSurveyRecord?
    @State private var collapsedSurveys: Set<UUID> = []
    @State private var workToDelete: WorkItem?
    @State private var renameID: UUID?
    @State private var renameIsSurvey = false
    @State private var renameText = ""
    @State private var scanning = false
    @State private var error: String?
    private var project: ProjectItem? { store.project(id: projectID) }
    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        let address = project.address.isEmpty ? (store.surveys(projectID: projectID).compactMap(\.captureAddress).first ?? "") : project.address
                        if !address.isEmpty { ProjectAddressMenu(address: address).font(.subheadline) }
                        Button { scanning=true } label: {
                            Label("Scanner dans ce projet",systemImage:"viewfinder")
                                .font(.headline).frame(maxWidth:.infinity,minHeight:52)
                        }.buttonStyle(.bordered).tint(ContrastPalette.blue)
                        if !store.surveys(projectID: projectID).isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Relevés 3D").font(.headline)
                                ForEach(store.surveys(projectID: projectID)) { survey in
                                    HStack(spacing: 4) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            if !collapsedSurveys.insert(survey.id).inserted { collapsedSurveys.remove(survey.id) }
                                        }
                                    } label: {
                                        Image(systemName: "triangle.fill").font(.caption)
                                            .rotationEffect(.degrees(collapsedSurveys.contains(survey.id) ? 90 : 180))
                                            .frame(width: 32, height: 60)
                                    }.accessibilityLabel(collapsedSurveys.contains(survey.id) ? "Déplier les ouvrages" : "Replier les ouvrages")
                                    NavigationLink(value: LabRoute.survey(survey.id)) {
                                        HStack(spacing: 14) {
                                            SurveyThumbnailView(survey: survey).frame(width: 100, height: 78).clipShape(RoundedRectangle(cornerRadius: 14))
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(survey.name).font(.subheadline.weight(.semibold)).foregroundStyle(ContrastPalette.ink)
                                                Text(survey.scanDate, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                                                Text("Ouvrir la maquette").font(.caption.weight(.semibold)).foregroundStyle(ContrastPalette.blue)
                                            }; Spacer(minLength: 0)
                                        }.padding(10).modifier(LabCard())
                                    }.buttonStyle(.plain)
                                    }
                                    .modifier(LabSwipeActions(rename: { beginRename(survey.id, name: survey.name, survey: true) },
                                        duplicate: { perform { try store.duplicateSurvey(projectID: projectID, surveyID: survey.id) } }, delete: { surveyToDelete = survey }))
                                    if !collapsedSurveys.contains(survey.id) {
                                        ForEach(project.visibleWorks.filter { owningSurvey($0) == survey.id }) { work in
                                            workCard(work).padding(.leading, 28).transition(.opacity.combined(with: .move(edge: .top)))
                                        }
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(store.surveys(projectID: projectID).isEmpty ? "Ouvrages" : "Ouvrages sans relevé").font(.headline); Spacer()
                                Button { adding = true } label: { Label("Ajouter", systemImage: "plus") }.frame(minHeight: 44)
                            }
                            if project.visibleWorks.isEmpty { Text("Ajoutez un ouvrage ou choisissez ses surfaces dans la maquette.").font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(project.visibleWorks.filter { owningSurvey($0) == nil }) { work in workCard(work) }
                        }
                        if !project.client.isEmpty || !project.notes.isEmpty {
                            DisclosureGroup("Informations du projet") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if !project.client.isEmpty { Text(project.client) }
                                    if !project.notes.isEmpty { Text(project.notes) }
                                }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }.padding(16).modifier(LabCard())
                        }
                    }.padding(20)
                }.background(ContrastPalette.paper)
                .safeAreaInset(edge: .bottom) {
                    NavigationLink { LabQuantitySelection(projectID: projectID) } label: {
                        LabPrimaryLabel(title: "Voir les quantitatifs", symbol: "list.bullet.rectangle")
                    }.disabled(project.visibleWorks.isEmpty).opacity(project.visibleWorks.isEmpty ? 0.45 : 1)
                        .padding(.horizontal, 20).padding(.vertical, 10).background(.ultraThinMaterial)
                }
                .navigationTitle(project.name).navigationBarTitleDisplayMode(.large)
                .toolbar {
                    Menu {
                        Button("Modifier le projet", systemImage: "pencil") { editing = true }
                        Button("Dupliquer", systemImage: "plus.square.on.square") { perform { try store.duplicateProject(id: projectID) } }
                        Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Options du projet")
                }
                .sheet(isPresented: $editing) { ProjectFormView(project: project) }
                .fullScreenCover(isPresented:$scanning) {
                    ScannerDebugView(targetProjectID:projectID,onOpenAccount:{})
                }
                .sheet(isPresented: $adding) { NewWorkView(projectID: projectID) }
            } else { ContentUnavailableView("Projet introuvable", systemImage: "folder") }
        }
        .confirmationDialog("Supprimer ce projet et tous ses ouvrages ?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { perform { try store.deleteProject(id: projectID); dismiss() } }
        }
        .confirmationDialog("Supprimer le relevé ?", isPresented: Binding(get: { surveyToDelete != nil }, set: { if !$0 { surveyToDelete = nil } }), titleVisibility: .visible) {
            Button("Supprimer le relevé", role: .destructive) {
                if let surveyToDelete { perform { try store.deleteSurvey(projectID: projectID, surveyID: surveyToDelete.id) } }; surveyToDelete = nil
            }
        } message: { Text("Les ouvrages et calepinages restent conservés, sans lien avec ce relevé.") }
        .confirmationDialog("Supprimer cet ouvrage ?", isPresented: Binding(get: { workToDelete != nil }, set: { if !$0 { workToDelete = nil } }), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let workToDelete { perform { try store.deleteWork(projectID: projectID, workID: workToDelete.id) } }
                workToDelete = nil
            }
        }
        .alert("Renommer", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Nom", text: $renameText)
            Button("Enregistrer") {
                if let id = renameID { perform {
                    if renameIsSurvey { try store.renameSurvey(projectID: projectID, surveyID: id, name: renameText) }
                    else { try store.renameWorkTitle(projectID: projectID, workID: id, title: renameText) }
                } }; renameID = nil
            }.disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Annuler", role: .cancel) { renameID = nil }
        }
        .alert("Action impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func owningSurvey(_ work: WorkItem) -> UUID? {
        let ids = Set(work.components.compactMap { $0.surveySource?.surveyID })
        return store.surveys(projectID: projectID).first { ids.contains($0.id) }?.id
    }
    private func beginRename(_ id: UUID, name: String, survey: Bool) { renameID = id; renameText = name; renameIsSurvey = survey }
    private func workCard(_ work: WorkItem) -> some View {
        NavigationLink(value: LabRoute.work(project: projectID, work: work.id)) {
            HStack(spacing: 12) {
                LabWorkPreview(work: work).frame(width: 104, height: 84).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 7) {
                    Text(work.name).font(.subheadline.weight(.semibold)).foregroundStyle(ContrastPalette.ink)
                    Text(work.type.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("\(work.area.formatted(.number.precision(.fractionLength(0...1)))) m²").font(.subheadline.weight(.semibold)).foregroundStyle(ContrastPalette.blue)
                }; Spacer(minLength: 0)
            }.padding(10).modifier(LabCard())
        }.buttonStyle(.plain).accessibilityIdentifier("lab.work.\(work.id)")
        .modifier(LabSwipeActions(rename: { beginRename(work.id, name: work.name, survey: false) },
            duplicate: { perform { try store.duplicateWork(projectID: projectID, workID: work.id) } }, delete: { workToDelete = work }))
    }
    private func perform(_ operation: () throws -> Void) { do { try operation() } catch { self.error = error.localizedDescription } }
}

private struct LabWorkView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var references = CeilingReferenceStore()
    let projectID: UUID
    let workID: UUID
    @State private var rename = false
    @State private var deleting = false
    @State private var error: String?
    private var work: WorkItem? { store.project(id: projectID)?.works.first { $0.id == workID } }
    var body: some View {
        Group {
            if let work {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        LabWorkPreview(work: work).frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 24))
                        HStack(alignment: .top) {
                            Text(work.type.title).font(.subheadline).foregroundStyle(.secondary); Spacer()
                            Text("\(work.area.formatted(.number.precision(.fractionLength(0...1)))) m²").font(.title3.bold()).foregroundStyle(ContrastPalette.blue)
                        }
                        if work.surveySourceNeedsReview { SurveySourceReviewNotice(work: work) }
                        if work.layoutNeedsRecalculation == true {
                            Label("Le plan a changé. Vérifiez le quantitatif avant de commander.", systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(ContrastPalette.orange)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Configuration actuelle").font(.headline)
                            Text(WorkTechnicalSummary.text(for: work, catalogue: references.workSummaryCatalogue))
                                .font(.subheadline)
                            let openings = WorkOpeningRelations.summary(for: work, allWorks: store.project(id: projectID)?.works ?? [])
                            if !openings.isEmpty {
                                Divider()
                                Label("Ouvertures", systemImage: "door.left.hand.open").font(.subheadline.weight(.semibold))
                                ForEach(Array(openings.enumerated()), id: \.offset) { _, title in
                                    Text(title).font(.subheadline)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).modifier(LabCard())
                        NavigationLink { CombinedQuantityView(works: [work], title: "Quantitatif") } label: {
                            LabPrimaryLabel(title: "Voir le quantitatif", symbol: "list.bullet.rectangle")
                        }
                        if work.type != .paintingBeta && work.type != .jointTreatment && (work.hasSavedLayout || !work.components.isEmpty || (work.type != .openings && !work.isPartition)) {
                            NavigationLink { WorkLayoutWorkbookView(projectID: projectID, workID: workID) } label: { action("Calepinage 2D", symbol: "square.grid.3x3") }
                        }
                        NavigationLink { LabWorkConfigurationView(projectID:projectID,workID:workID) } label: { action("Modifier la configuration", symbol: "slider.horizontal.3") }
                        if work.supportsAttachedOpenings {
                            NavigationLink { WorkOpeningsView(work: work) } label: { action("Ajouter / gérer les ouvertures", symbol: "door.left.hand.open") }
                        }
                        if store.openingJoineryConflict(projectID: projectID, referenceWorkID: workID) != nil {
                            NavigationLink { SavedWorkView(work: work, opensIsolationStep: true) } label: {
                                Label("Vérifier l’isolant et les tapées", systemImage: "exclamationmark.triangle.fill").foregroundStyle(ContrastPalette.orange)
                            }
                        }
                    }.padding(20)
                }.background(ContrastPalette.paper)
                .navigationTitle(work.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Menu {
                        Button("Renommer", systemImage: "pencil") { rename = true }
                        Button("Dupliquer", systemImage: "plus.square.on.square") { perform { try store.duplicateWork(projectID: projectID, workID: workID) } }
                        Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Options de l’ouvrage")
                }
                .sheet(isPresented: $rename) {
                    RenameWorkView(work: work) { title in perform { try store.renameWorkTitle(projectID: projectID, workID: workID, title: title); rename = false } }
                }
                .task { await references.load() }
            } else { ContentUnavailableView("Ouvrage introuvable", systemImage: "square.stack") }
        }
        .confirmationDialog("Supprimer cet ouvrage ?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { perform { try store.deleteWork(projectID: projectID, workID: workID); dismiss() } }
        }
        .alert("Action impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func action(_ title: String, symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol); Spacer(); Image(systemName: "chevron.right").font(.caption) }
            .font(.subheadline.weight(.semibold)).padding(18).modifier(LabCard())
    }
    private func perform(_ operation: () throws -> Void) { do { try operation() } catch { self.error = error.localizedDescription } }
}

private struct LabWorkConfigurationView: View {
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var references = CeilingReferenceStore()
    let projectID: UUID
    let workID: UUID
    @State private var editing: WorkConfigurationShortcut?
    private var work: WorkItem? { store.project(id:projectID)?.works.first { $0.id == workID } }
    private func shortcuts(_ work: WorkItem) -> [WorkConfigurationShortcut] {
        WorkConfigurationShortcut.choices(for:work.type).filter {
            // Support/plenum/suspension do not apply to a self-supporting ceiling.
            !(work.railStudCeilingConfiguration?.frameMode == "selfSupporting" && [4,5,6].contains($0.step))
        }
    }
    var body: some View {
        Group {
            if let work {
                List {
                    Section {
                        Text(work.name).font(.headline)
                        Text(work.type.title).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(work.area.formatted(.number.precision(.fractionLength(0...1)))) m²").foregroundStyle(ContrastPalette.blue)
                    }
                    Section("Modifier un réglage") {
                        ForEach(shortcuts(work)) { shortcut in
                            Button { editing = shortcut } label: {
                                HStack { Text(shortcut.title); Spacer(); Image(systemName:"chevron.right").font(.caption) }
                                    .frame(minHeight:44).contentShape(Rectangle())
                            }.accessibilityIdentifier("lab.configuration.step.\(shortcut.step)")
                        }
                        NavigationLink("Ouvrir le formulaire complet") { SavedWorkView(work:work,startsAtBeginning:true) }
                    }
                    Section {
                        DisclosureGroup("Configuration actuelle") {
                            Text(WorkTechnicalSummary.text(for:work,catalogue:references.workSummaryCatalogue)).font(.subheadline)
                        }
                    }
                }
                .sheet(item:$editing) { shortcut in
                    NavigationStack {
                        SavedWorkView(work:work)
                            .environment(\.configurationEntryStep,shortcut.step)
                            .toolbar {
                                ToolbarItem(placement:.cancellationAction) { Button("Fermer") { editing=nil } }
                            }
                    }.interactiveDismissDisabled()
                }
            } else { ContentUnavailableView("Ouvrage introuvable",systemImage:"square.stack") }
        }
        .navigationTitle("Configuration").navigationBarTitleDisplayMode(.inline)
        .task { await references.load() }
    }
}

private struct LabQuantitySelection: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    @State private var selected: Set<UUID>?
    @State private var filtering = false
    private var works: [WorkItem] { store.project(id: projectID)?.visibleWorks ?? [] }
    private var chosen: [WorkItem] { works.filter { selected?.contains($0.id) ?? true } }
    var body: some View {
        CombinedQuantityView(works:chosen,title:selected == nil ? "Quantitatif du projet" : "Quantitatif sélectionné")
            // Recreate the share document for each selection; never share an old total.
            .id(chosen.map(\.id))
            .toolbar {
                Button { filtering=true } label: { Label("Filtrer",systemImage:"line.3.horizontal.decrease") }
                    .accessibilityLabel("Filtrer les ouvrages inclus")
                    .accessibilityValue("\(chosen.count) sur \(works.count)")
            }
            .sheet(isPresented:$filtering) {
                NavigationStack {
                    LabQuantityFilter(works:works,selected:Set(chosen.map(\.id))) { selection in
                        selected = selection == Set(works.map(\.id)) ? nil : selection
                        filtering=false
                    }
                }
            }
    }
}

private struct LabQuantityFilter: View {
    @Environment(\.dismiss) private var dismiss
    let works: [WorkItem]
    @State var selected: Set<UUID>
    let apply: (Set<UUID>) -> Void
    var body: some View {
        List {
            Section {
                ForEach(works) { work in
                    Button {
                        if !selected.insert(work.id).inserted { selected.remove(work.id) }
                    } label: {
                        HStack(spacing: 12) {
                            LabWorkPreview(work: work).frame(width: 70, height: 55).clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(work.name).foregroundStyle(ContrastPalette.ink); Spacer()
                            Image(systemName: selected.contains(work.id) ? "checkmark.circle.fill" : "circle")
                        }.padding(.vertical, 5)
                    }.accessibilityValue(selected.contains(work.id) ? "Inclus" : "Exclu")
                }
            } header: { Text("Ouvrages à inclure") }
        }.scrollContentBackground(.hidden).background(ContrastPalette.paper)
            .navigationTitle("Ouvrages inclus").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.primaryAction) {
                    Button(selected.count == works.count ? "Aucun" : "Tout") { selected = selected.count == works.count ? [] : Set(works.map(\.id)) }
                        .accessibilityLabel(selected.count == works.count ? "Tout désélectionner" : "Tout sélectionner")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { apply(selected) } label: {
                    LabPrimaryLabel(title: "Appliquer · \(selected.count) ouvrage(s)", symbol: "checkmark")
                }.padding(20).background(.ultraThinMaterial)
            }
    }
}
