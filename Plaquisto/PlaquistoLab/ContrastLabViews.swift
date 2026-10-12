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

private struct LabProjectsView: View {
    @EnvironmentObject private var store: ProjectStore
    let onSettings: () -> Void
    @State private var search = ""
    @State private var path: [LabRoute] = []
    @State private var adding = false
    @State private var deleting: ProjectItem?
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
                            .contextMenu {
                                Button("Dupliquer", systemImage: "plus.square.on.square") { perform { try store.duplicateProject(id: project.id) } }
                                Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = project }
                            }
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
    @State private var error: String?
    private var project: ProjectItem? { store.project(id: projectID) }
    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        let address = project.address.isEmpty ? (store.surveys(projectID: projectID).compactMap(\.captureAddress).first ?? "") : project.address
                        if !address.isEmpty { ProjectAddressMenu(address: address).font(.subheadline) }
                        if !store.surveys(projectID: projectID).isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Relevés 3D").font(.headline)
                                ForEach(store.surveys(projectID: projectID)) { survey in
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
                                    .contextMenu { Button("Supprimer le relevé", systemImage: "trash", role: .destructive) { surveyToDelete = survey } }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ouvrages").font(.headline); Spacer()
                                Button { adding = true } label: { Label("Ajouter", systemImage: "plus") }.frame(minHeight: 44)
                            }
                            if project.visibleWorks.isEmpty { Text("Ajoutez un ouvrage ou choisissez ses surfaces dans la maquette.").font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(project.visibleWorks) { work in
                                NavigationLink(value: LabRoute.work(project: projectID, work: work.id)) {
                                    HStack(spacing: 12) {
                                        LabWorkPreview(work: work).frame(width: 104, height: 84).clipShape(RoundedRectangle(cornerRadius: 14))
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(work.name).font(.subheadline.weight(.semibold)).foregroundStyle(ContrastPalette.ink)
                                            Text(work.type.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            Text("\(work.area.formatted(.number.precision(.fractionLength(0...1)))) m²").font(.subheadline.weight(.semibold)).foregroundStyle(ContrastPalette.blue)
                                            if work.layoutNeedsRecalculation == true || work.surveySourceNeedsReview {
                                                Label("À vérifier", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(ContrastPalette.orange)
                                            }
                                        }; Spacer(minLength: 0)
                                    }.padding(10).modifier(LabCard())
                                }.buttonStyle(.plain).accessibilityIdentifier("lab.work.\(work.id)")
                            }
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
        .alert("Action impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
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
                        NavigationLink { CombinedQuantityView(works: [work], title: "Quantitatif") } label: {
                            LabPrimaryLabel(title: "Voir le quantitatif", symbol: "list.bullet.rectangle")
                        }
                        if work.type != .paintingBeta && work.type != .jointTreatment && (work.hasSavedLayout || !work.components.isEmpty || (work.type != .openings && !work.isPartition)) {
                            NavigationLink { WorkLayoutWorkbookView(projectID: projectID, workID: workID) } label: { action("Calepinage 2D", symbol: "square.grid.3x3") }
                        }
                        NavigationLink { SavedWorkView(work: work, startsAtBeginning: true) } label: { action("Modifier la configuration", symbol: "slider.horizontal.3") }
                        if work.supportsAttachedOpenings {
                            NavigationLink { WorkOpeningsView(work: work) } label: { action("Ajouter / gérer les ouvertures", symbol: "door.left.hand.open") }
                        }
                        if store.openingJoineryConflict(projectID: projectID, referenceWorkID: workID) != nil {
                            NavigationLink { SavedWorkView(work: work, opensIsolationStep: true) } label: {
                                Label("Vérifier l’isolant et les tapées", systemImage: "exclamationmark.triangle.fill").foregroundStyle(ContrastPalette.orange)
                            }
                        }
                        DisclosureGroup("Détails techniques") {
                            Text(WorkTechnicalSummary.text(for: work, catalogue: references.workSummaryCatalogue))
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                        }.padding(16).modifier(LabCard())
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

private struct LabQuantitySelection: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    @State private var selected: Set<UUID> = []
    @State private var initialized = false
    private var works: [WorkItem] { store.project(id: projectID)?.visibleWorks ?? [] }
    private var chosen: [WorkItem] { works.filter { selected.contains($0.id) } }
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
            .navigationTitle("Quantitatifs").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(selected.count == works.count ? "Aucun" : "Tout") { selected = selected.count == works.count ? [] : Set(works.map(\.id)) }
                    .accessibilityLabel(selected.count == works.count ? "Tout désélectionner" : "Tout sélectionner")
            }
            .onAppear { if !initialized { selected = Set(works.map(\.id)); initialized = true } }
            .safeAreaInset(edge: .bottom) {
                NavigationLink { CombinedQuantityView(works: chosen, title: "Quantitatif du projet") } label: {
                    LabPrimaryLabel(title: "Afficher · \(chosen.count) ouvrage(s)", symbol: "list.bullet.rectangle")
                }.disabled(chosen.isEmpty).opacity(chosen.isEmpty ? 0.45 : 1).padding(20).background(.ultraThinMaterial)
            }
    }
}
