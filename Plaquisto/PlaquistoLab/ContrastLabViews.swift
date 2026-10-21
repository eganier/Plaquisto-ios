import SwiftUI

private enum LabRoute: Hashable {
    case project(UUID)
    case survey(UUID)
    case work(project: UUID, work: UUID)
}

struct ContrastLabRoot: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var tab = 0
    @State private var visitedTabs: Set<Int> = [0]
    @State private var settings = false
    @State private var hideTabBar = false
    @State private var keyboardVisible = false
    var body: some View {
        VStack(spacing: 0) {
        // Keep each visited navigation stack alive without a second, native tab bar.
        ZStack {
            LabProjectsView(onSettings: { settings = true }).atlantiqueDesign()
                .opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
            if visitedTabs.contains(1) {
            ScannerDebugView(onOpenAccount: { settings = true }).atlantiqueDesign()
                .opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1)
            }
            if visitedTabs.contains(2) {
            ToolsHomeView(onOpenAccount: { settings = true }).atlantiqueDesign()
                .opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2).accessibilityHidden(tab != 2)
            }
            if visitedTabs.contains(3) {
            StockHomeView().atlantiqueDesign()
                .opacity(tab == 3 ? 1 : 0).allowsHitTesting(tab == 3).accessibilityHidden(tab != 3)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        if !hideTabBar && !keyboardVisible { AtlantiqueTabBar(selection: $tab).background(Atlantique.Palette.blue) }
        }.background(Atlantique.Palette.blue.ignoresSafeArea())
        .onPreferenceChange(AtlantiqueTabBarHiddenKey.self) { hideTabBar = $0 }
        .onChange(of: tab) { _, value in visitedTabs.insert(value) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onChange(of: store.projectNavigationRequest) { _, request in if request != nil { tab = 0 } }
        .sheet(isPresented: $settings) { AtlantiqueSettingsView().atlantiqueDesign() }
    }
}

private struct LabCard: ViewModifier {
    func body(content: Content) -> some View {
        content.background { AtlantiqueSurface() }.foregroundStyle(Atlantique.Palette.ink)
    }
}
private struct LabPrimaryLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(Atlantique.Typography.button)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Atlantique.Palette.blue)
            .background { AtlantiqueSurface(radius: 12) }
    }
}

/// Swipe actions for cards hosted in ScrollView (SwiftUI swipeActions only
/// works on List rows). Vertical gestures remain available to the scroll view.
private struct LabSwipeActions: ViewModifier {
    let rename: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    var compact = false
    @State private var revealed = false
    @State private var drag: CGFloat = 0
    private let revealWidth: CGFloat = 116
    func body(content: Content) -> some View {
        content
                .frame(minHeight: compact ? 132 : 144)
                .contentShape(Rectangle())
                .background(LabCardSwipeGesture(changed:{ drag=$0 },ended:{ distance,velocity,cancelled in
                    withAnimation(.easeInOut(duration:0.22)) {
                        if !cancelled { revealed = (revealed ? -revealWidth : 0) + distance + velocity*0.12 < -revealWidth/2 }
                        drag=0
                    }
                }))
                .offset(x: min(0, max(-revealWidth, (revealed ? -revealWidth : 0) + drag)))
            .background(alignment: .trailing) {
                VStack(spacing: compact ? 0 : 6) {
                    action("Renommer", "pencil", Atlantique.Palette.actionInk, rename)
                    action("Dupliquer", "doc.on.doc", Atlantique.Palette.actionInk, duplicate)
                    action("Supprimer", "trash", Atlantique.Palette.danger, delete)
                }.frame(width: revealWidth - 8)
                    .opacity(revealed || drag < 0 ? 1 : 0).allowsHitTesting(revealed)
            }
        .clipped()
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
            VStack(spacing: compact ? 2 : 5) {
                Image(systemName: icon).font(.system(size: compact ? 17 : 24, weight: .regular))
                Text(title).font(Atlantique.Typography.font(compact ? 10 : 11, weight: .medium, relativeTo: .caption2))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 44)
                .background { AtlantiqueSurface(radius: 12) }
        }.buttonStyle(.plain).foregroundStyle(tint)
    }
}

/// A directional UIKit recognizer can fail a vertical gesture before recognition.
/// A SwiftUI high-priority DragGesture cannot, and would block the project list's
/// vertical scroll. This transparent probe never intercepts taps itself.
private struct LabCardSwipeGesture: UIViewRepresentable {
    let changed:(CGFloat)->Void
    let ended:(CGFloat,CGFloat,Bool)->Void
    func makeUIView(context:Context) -> Probe { Probe(changed:changed,ended:ended) }
    func updateUIView(_ view:Probe,context:Context) { view.changed=changed; view.ended=ended }
    static func dismantleUIView(_ view:Probe,coordinator:()) { view.detach() }
    final class HorizontalPan: UIGestureRecognizer {
        private var start:CGPoint?
        private var previous:CGPoint?
        private var timestamp:TimeInterval=0
        private(set) var distance:CGFloat=0
        private(set) var speed:CGFloat=0
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) {
            guard touches.count == 1,start == nil,let touch=touches.first else {
                state = state == .began || state == .changed ? .cancelled : .failed
                return
            }
            start=touch.location(in:nil); previous=start; timestamp=touch.timestamp
        }
        override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) {
            guard let touch=touches.first,let start else { return }
            let point=touch.location(in:nil),dx=point.x-start.x,dy=point.y-start.y
            distance=dx
            if touch.timestamp>timestamp { speed=(point.x-(previous?.x ?? point.x))/CGFloat(touch.timestamp-timestamp) }
            previous=point; timestamp=touch.timestamp
            if state == .possible {
                guard max(abs(dx),abs(dy))>=8 else { return }
                state = abs(dx)>abs(dy)*1.5 ? .began : .failed
            } else if state == .began || state == .changed { state = .changed }
        }
        override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) {
            // Some pointer/accessibility gestures deliver only their two ends.
            // Recognize that horizontal drag too, rather than opening the card.
            if state == .possible,let start,let point=touches.first?.location(in:nil) {
                let dx=point.x-start.x,dy=point.y-start.y
                if abs(dx)>=8,abs(dx)>abs(dy)*1.5 { distance=dx; speed=0; state = .ended; return }
            }
            state = state == .began || state == .changed ? .ended : .failed
        }
        override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent) { state = .cancelled }
        override func reset() { super.reset(); start=nil; previous=nil; timestamp=0; distance=0; speed=0 }
    }
    final class Probe:UIView,UIGestureRecognizerDelegate {
        var changed:(CGFloat)->Void
        var ended:(CGFloat,CGFloat,Bool)->Void
        private weak var observedWindow:UIWindow?
        private weak var gestureHost:UIView?
        private lazy var pan:HorizontalPan = {
            let result=HorizontalPan(target:self,action:#selector(cardPanChanged(_:)))
            result.cancelsTouchesInView=true; result.delegate=self
            return result
        }()
        init(changed:@escaping(CGFloat)->Void,ended:@escaping(CGFloat,CGFloat,Bool)->Void) {
            self.changed=changed; self.ended=ended; super.init(frame:.zero)
            isUserInteractionEnabled=false; backgroundColor = .clear
        }
        required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard observedWindow !== window else { return }
            detach(); observedWindow=window
            gestureHost=window?.rootViewController?.view
            gestureHost?.addGestureRecognizer(pan)
        }
        func detach() { gestureHost?.removeGestureRecognizer(pan); gestureHost=nil; observedWindow=nil }
        private func owner(_ responder:UIResponder?) -> UIViewController? {
            var current=responder
            while let value=current { if let controller=value as? UIViewController { return controller }; current=value.next }
            return nil
        }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch) -> Bool {
            guard window != nil,bounds.contains(touch.location(in:self)) else { return false }
            if owner(self)?.presentedViewController != nil { return false }
            var ancestor=superview
            while let view=ancestor {
                if view.isHidden || view.alpha<0.01 || (view.clipsToBounds && !view.bounds.contains(touch.location(in:view))) { return false }
                ancestor=view.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldBeRequiredToFailBy other:UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
        @objc private func cardPanChanged(_ recognizer:HorizontalPan) {
            let x=recognizer.distance
            switch recognizer.state {
            case .began,.changed: changed(x)
            case .ended: ended(x,recognizer.speed,false)
            case .cancelled,.failed: ended(0,0,true)
            default: break
            }
        }
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
                        Text("\(visible.count) projet\(visible.count == 1 ? "" : "s")").font(Atlantique.Typography.body).foregroundStyle(.white)
                        Spacer()
                        Button { adding = true } label: { Label("Nouveau", systemImage: "plus") }
                            .buttonStyle(AtlantiqueButtonStyle()).fixedSize(horizontal: true, vertical: false).accessibilityIdentifier("lab.newProject")
                    }
                    AtlantiqueSearchField(prompt: "Projet, lieu ou date", text: $search)
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
            }.background(Atlantique.Palette.blue)
            .atlantiquePage("Mes projets", root: true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSettings) { AtlantiqueToolbarGlyph(symbol: "gearshape") }.accessibilityLabel("Réglages de l’application")
                }.atlantiqueToolbarBackground()
            }
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
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if let survey, !survey.checkpoints.isEmpty {
                        SurveyThumbnailView(survey: survey).allowsHitTesting(false)
                    } else {
                        AtlantiqueSymbol(icon: .projects, size: 50)
                            .foregroundStyle(Atlantique.Palette.blue)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(height: 145).frame(maxWidth: .infinity)
                    .background(Atlantique.Palette.paper).clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.name).font(Atlantique.Typography.heading).lineLimit(2).frame(minHeight: 26, alignment: .leading)
                        Text("\(project.visibleWorks.reduce(0) { $0 + $1.area }.formatted(.number.precision(.fractionLength(0...1)))) m² · \(project.visibleWorks.count) ouvrages")
                            .font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                        Text("Modifié · " + project.updatedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").foregroundStyle(Atlantique.Palette.actionInk)
                }.frame(minHeight: 88, alignment: .top)
            }.padding(12).modifier(LabCard())
        }.buttonStyle(.plain).accessibilityLabel("Ouvrir \(project.name)")
    }
}

private struct LabWorkPreview: View {
    @EnvironmentObject private var store: ProjectStore
    let work: WorkItem
    var body: some View {
        if let source = work.components.compactMap(\.surveySource).first,
           let survey = store.surveys.first(where: { $0.id == source.surveyID }) {
            SurveyThumbnailView(survey: survey, selected: WorkPreviewSelection.surfaceIDs(work: work, survey: survey)).allowsHitTesting(false)
        } else {
            VStack(spacing: 5) {
                Image(systemName: work.type.category == .ceilings ? "square.3.layers.3d" : "rectangle.split.3x1").font(.system(size: 30, weight: .light))
                Text("Sans scan").font(Atlantique.Typography.font(12, relativeTo: .caption2))
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
    @State private var information = false
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
                        if !address.isEmpty { ProjectAddressMenu(address: address).font(Atlantique.Typography.body).foregroundStyle(.white) }
                        Button { scanning=true } label: {
                            Label { Text("Modéliser dans ce projet") } icon: { AtlantiqueSymbol(icon: .model, size: 24) }
                                .font(Atlantique.Typography.button).frame(maxWidth:.infinity,minHeight:52)
                        }.buttonStyle(AtlantiqueButtonStyle(kind: .secondary))
                        if !store.surveys(projectID: projectID).isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Relevés 3D").font(Atlantique.Typography.heading).foregroundStyle(.white)
                                ForEach(store.surveys(projectID: projectID)) { survey in
                                    VStack(spacing: 8) {
                                        surveyCard(survey)
                                        if !collapsedSurveys.contains(survey.id) && project.visibleWorks.contains(where: { owningSurvey($0) == survey.id }) {
                                            VStack(spacing: 8) {
                                                ForEach(project.visibleWorks.filter { owningSurvey($0) == survey.id }) { work in
                                                    workCard(work)
                                                }
                                            }.padding(.leading, 30)
                                                .overlay(alignment: .leading) {
                                                    Rectangle().fill(.white.opacity(0.5)).frame(width: 1).padding(.leading, 16)
                                                }
                                                .transition(.opacity.combined(with: .move(edge: .top)))
                                        }
                                    }.padding(.bottom, 16)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ouvrages sans relevés 3D").font(Atlantique.Typography.heading).foregroundStyle(.white); Spacer()
                                Button { adding = true } label: { Label("Ajouter", systemImage: "plus") }.buttonStyle(AtlantiqueButtonStyle()).fixedSize(horizontal: true, vertical: false)
                            }
                            if project.visibleWorks.isEmpty { Text("Ajoutez un ouvrage ou choisissez ses surfaces dans la maquette.").font(Atlantique.Typography.font(15, relativeTo: .subheadline)).foregroundStyle(.white.opacity(0.85)) }
                            ForEach(project.visibleWorks.filter { owningSurvey($0) == nil }) { work in workCard(work) }
                        }
                    }.padding(20)
                }.background(Atlantique.Palette.blue)
                .safeAreaInset(edge: .bottom) {
                    NavigationLink { LabQuantitySelection(projectID: projectID) } label: {
                        LabPrimaryLabel(title: "Voir les quantitatifs", symbol: "list.bullet.rectangle")
                    }.disabled(project.visibleWorks.isEmpty).opacity(project.visibleWorks.isEmpty ? 0.45 : 1)
                        .padding(.horizontal, 20).padding(.vertical, 10).background(Atlantique.Palette.blue)
                }
                .atlantiquePage(project.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Informations du projet", systemImage: "info.circle") { information = true }
                        Button("Modifier le projet", systemImage: "pencil") { editing = true }
                        Button("Dupliquer", systemImage: "plus.square.on.square") { perform { try store.duplicateProject(id: projectID) } }
                        Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { AtlantiqueToolbarGlyph() }.accessibilityLabel("Options du projet")
                    }.atlantiqueToolbarBackground()
                }
                .sheet(isPresented: $information) {
                    NavigationStack {
                        Form {
                            LabeledContent("Projet", value: project.name)
                            if !project.client.isEmpty { LabeledContent("Client", value: project.client) }
                            if !project.address.isEmpty { LabeledContent("Adresse", value: project.address) }
                            if !project.notes.isEmpty { Section("Notes") { Text(project.notes) } }
                        }.navigationTitle("Informations du projet").navigationBarTitleDisplayMode(.inline)
                            .toolbar { Button("Fermer") { information = false } }
                    }
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
    private func surveyCard(_ survey: ProjectSurveyRecord) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if !collapsedSurveys.insert(survey.id).inserted { collapsedSurveys.remove(survey.id) }
                }
            } label: {
                Image(systemName: "triangle.fill").font(.system(size: 11))
                    .rotationEffect(.degrees(collapsedSurveys.contains(survey.id) ? 90 : 180))
                    .foregroundStyle(Atlantique.Palette.actionInk).frame(width: 44, height: 84)
            }.buttonStyle(.plain)
                .accessibilityLabel(collapsedSurveys.contains(survey.id) ? "Déplier les ouvrages" : "Replier les ouvrages")
            NavigationLink(value: LabRoute.survey(survey.id)) {
                HStack(spacing: 10) {
                    SurveyThumbnailView(survey: survey).allowsHitTesting(false).frame(width: 78, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(survey.name).font(Atlantique.Typography.button).lineLimit(2)
                        Text("\(survey.scanDate.formatted(date: .abbreviated, time: .omitted)) · \(project?.visibleWorks.filter { owningSurvey($0) == survey.id }.count ?? 0) ouvrages")
                            .font(Atlantique.Typography.font(12, relativeTo: .caption)).foregroundStyle(Atlantique.Palette.muted)
                        Text("Ouvrir la maquette").font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.blue)
                    }; Spacer(minLength: 0)
                }.frame(minHeight: 96).padding(.trailing, 10)
            }.buttonStyle(.plain).accessibilityIdentifier("lab.survey.\(survey.id)")
        }.padding(.vertical, 6).frame(minHeight: 132).modifier(LabCard())
            .modifier(LabSwipeActions(rename: { beginRename(survey.id, name: survey.name, survey: true) },
                duplicate: { perform { try store.duplicateSurvey(projectID: projectID, surveyID: survey.id) } },
                delete: { surveyToDelete = survey }, compact: true))
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
                    Text(work.name).font(Atlantique.Typography.font(15, weight: .demi, relativeTo: .subheadline)).foregroundStyle(ContrastPalette.ink)
                    Text(work.type.title).font(Atlantique.Typography.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("\(work.area.formatted(.number.precision(.fractionLength(0...1)))) m²").font(Atlantique.Typography.font(15, weight: .demi, relativeTo: .subheadline)).foregroundStyle(ContrastPalette.blue)
                }; Spacer(minLength: 0)
            }.padding(10).frame(minHeight: 132).modifier(LabCard())
        }.buttonStyle(.plain).accessibilityIdentifier("lab.work.\(work.id)")
        .modifier(LabSwipeActions(rename: { beginRename(work.id, name: work.name, survey: false) },
            duplicate: { perform { try store.duplicateWork(projectID: projectID, workID: work.id) } }, delete: { workToDelete = work }, compact: true))
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
    @State private var configuration = false
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
                            Text(work.type.title).font(Atlantique.Typography.body).foregroundStyle(.white); Spacer()
                            Text("\(work.area.formatted(.number.precision(.fractionLength(0...1)))) m²").font(Atlantique.Typography.heading).foregroundStyle(.white)
                        }
                        if work.surveySourceNeedsReview { SurveySourceReviewNotice(work: work) }
                        if work.layoutNeedsRecalculation == true {
                            Label("Le plan a changé. Vérifiez le quantitatif avant de commander.", systemImage: "exclamationmark.triangle").font(Atlantique.Typography.font(15, relativeTo: .subheadline)).foregroundStyle(ContrastPalette.orange)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Configuration actuelle").font(Atlantique.Typography.button)
                            Text(WorkTechnicalSummary.text(for: work, catalogue: references.workSummaryCatalogue))
                                .font(Atlantique.Typography.font(15, relativeTo: .subheadline))
                            let openings = WorkOpeningRelations.summary(for: work, allWorks: store.project(id: projectID)?.works ?? [])
                            if !openings.isEmpty {
                                Divider()
                                Label("Ouvertures", systemImage: "door.left.hand.open").font(Atlantique.Typography.font(15, weight: .demi, relativeTo: .subheadline))
                                ForEach(Array(openings.enumerated()), id: \.offset) { _, title in
                                    Text(title).font(Atlantique.Typography.font(15, relativeTo: .subheadline))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).modifier(LabCard())
                        NavigationLink { CombinedQuantityView(works: [work], title: "Quantitatif") } label: {
                            LabPrimaryLabel(title: "Voir le quantitatif", symbol: "list.bullet.rectangle")
                        }
                        if work.type != .paintingBeta && work.type != .jointTreatment && (work.hasSavedLayout || !work.components.isEmpty || (work.type != .openings && !work.isPartition)) {
                            NavigationLink { WorkLayoutWorkbookView(projectID: projectID, workID: workID) } label: { action("Calepinage 2D", symbol: "square.grid.3x3") }
                        }
                        Button { configuration = true } label: { action("Modifier la configuration", symbol: "slider.horizontal.3") }.buttonStyle(.plain)
                        if work.supportsAttachedOpenings {
                            NavigationLink { WorkOpeningsView(work: work) } label: { action("Ajouter / gérer les ouvertures", symbol: "door.left.hand.open") }
                        }
                        if store.openingJoineryConflict(projectID: projectID, referenceWorkID: workID) != nil {
                            NavigationLink { SavedWorkView(work: work, opensIsolationStep: true) } label: {
                                Label("Vérifier l’isolant et les tapées", systemImage: "exclamationmark.triangle.fill").foregroundStyle(ContrastPalette.orange)
                            }
                        }
                    }.padding(20)
                }.background(Atlantique.Palette.blue)
                .atlantiquePage(work.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Renommer", systemImage: "pencil") { rename = true }
                        Button("Dupliquer", systemImage: "plus.square.on.square") { perform { try store.duplicateWork(projectID: projectID, workID: workID) } }
                        Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { AtlantiqueToolbarGlyph() }.accessibilityLabel("Options de l’ouvrage")
                    }.atlantiqueToolbarBackground()
                }
                .sheet(isPresented: $configuration) {
                    NavigationStack {
                        LabWorkConfigurationView(projectID: projectID, workID: workID)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { configuration = false }.atlantiqueToolbarAction() }.atlantiqueToolbarBackground() }
                    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
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
        HStack { Label(title, systemImage: symbol); Spacer(); Image(systemName: "chevron.right").font(Atlantique.Typography.caption) }
            .font(Atlantique.Typography.button).foregroundStyle(.white).padding(.vertical, 12)
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
                        Text(work.name).font(Atlantique.Typography.button)
                        Text(work.type.title).font(Atlantique.Typography.font(15, relativeTo: .subheadline)).foregroundStyle(.secondary)
                        Text("\(work.area.formatted(.number.precision(.fractionLength(0...1)))) m²").foregroundStyle(ContrastPalette.blue)
                    }
                    AtlantiqueSection("Modifier un réglage") {
                        ForEach(shortcuts(work)) { shortcut in
                            Button { editing = shortcut } label: {
                                HStack { Text(work.type == .ceilingOnFurring && shortcut.step == 3 ? "Ossature" : shortcut.title); Spacer(); Image(systemName:"chevron.right").font(Atlantique.Typography.caption) }
                                    .frame(minHeight:44).contentShape(Rectangle())
                            }.accessibilityIdentifier("lab.configuration.step.\(shortcut.step)")
                        }
                        NavigationLink("Ouvrir le formulaire complet") { SavedWorkView(work:work,startsAtBeginning:true) }
                    }
                    Section {
                        DisclosureGroup("Configuration actuelle") {
                            Text(WorkTechnicalSummary.text(for:work,catalogue:references.workSummaryCatalogue)).font(Atlantique.Typography.font(15, relativeTo: .subheadline))
                        }
                    }
                }
                .sheet(item:$editing) { shortcut in
                    NavigationStack {
                        SavedWorkView(work:work)
                            .environment(\.configurationEntryStep,shortcut.step)
                            .toolbar {
                                ToolbarItem(placement:.cancellationAction) { Button("Fermer") { editing=nil }.atlantiqueToolbarAction() }.atlantiqueToolbarBackground()
                            }
                    }.interactiveDismissDisabled()
                }
            } else { ContentUnavailableView("Ouvrage introuvable",systemImage:"square.stack") }
        }
        .navigationTitle("Configuration").navigationBarTitleDisplayMode(.inline).atlantiqueFormSurface().atlantiqueFormPage("Configuration")
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
                ToolbarItem(placement: .topBarTrailing) {
                Button { filtering=true } label: { AtlantiqueToolbarGlyph(symbol: "line.3.horizontal.decrease") }
                    .accessibilityLabel("Filtrer les ouvrages inclus")
                    .accessibilityValue("\(chosen.count) sur \(works.count)")
                }.atlantiqueToolbarBackground()
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

private struct AtlantiqueSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            AtlantiqueForm {
                AtlantiqueSection("Application") {
                    NavigationLink("Graphisme 3D") {
                        AtlantiqueForm { MaquetteRenderingSettingsSection() }.atlantiqueFormPage("Graphisme 3D")
                    }
                    NavigationLink("Données métier") { AtlantiqueCatalogueSettings() }
                    NavigationLink("À propos de Plaquisto") { AtlantiqueAboutView() }
                }
                AtlantiqueSection("Plaquisto Lab uniquement") {
                    NavigationLink("Composants Atlantique") { AtlantiqueGallery() }
                    NavigationLink("Ouvrir l’interface actuelle") {
                        ProjectsHomeView().environment(\.interfacePresentation, .standard).environment(\.usesAtlantiqueDesign, false)
                    }
                    Text("Les deux présentations utilisent les mêmes données du Lab, séparées de celles de Plaquisto.").font(.footnote).foregroundStyle(.secondary)
                }
            }.atlantiqueFormPage("Réglages")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() }.atlantiqueToolbarAction() } }
        }
    }
}

private struct AtlantiqueCatalogueSettings: View {
    @StateObject private var references = CeilingReferenceStore()
    @StateObject private var prices = SupplyPriceStore()
    @StateObject private var technical = ToolTechnicalStore()
    @State private var refreshing = false
    @State private var attempted = false
    @AppStorage("plaquisto.catalogue.v3.lastSuccess") private var catalogueTimestamp = 0.0
    var body: some View {
        AtlantiqueForm {
            AtlantiqueSection("Source") {
                LabeledContent("Catalogue", value: "Plaquisto Admin")
                LabeledContent("Dernière réception réussie", value: catalogueTimestamp > 0
                    ? Date(timeIntervalSince1970: catalogueTimestamp).formatted(date: .abbreviated, time: .shortened) : "Date non enregistrée")
                if UserDefaults.standard.data(forKey: "plaquisto.catalogue.v3") != nil {
                    Label("Dernier catalogue disponible hors ligne", systemImage: "internaldrive")
                }
            }
            Section {
                Button {
                    guard !refreshing else { return }
                    refreshing = true
                    Task {
                        async let catalogue: Void = references.load()
                        async let tariffs: Void = prices.load()
                        async let tools: Void = technical.load(force: true)
                        _ = await (catalogue, tariffs, tools)
                        attempted = true; refreshing = false
                    }
                } label: {
                    HStack { if refreshing { ProgressView() }; Text(refreshing ? "Actualisation…" : "Actualiser les données") }
                        .frame(minHeight: 44)
                }.disabled(refreshing)
                Text("Actualise les références et les tarifs, pas la version de l’application. Les projets enregistrés ne sont pas modifiés.").font(.footnote).foregroundStyle(.secondary)
            }
            if attempted {
                Section {
                    if let error = references.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    else { Label(references.isUsingOfflineData ? "Catalogue conservé hors ligne : non actualisé." : "Catalogue actualisé.", systemImage: references.isUsingOfflineData ? "wifi.slash" : "checkmark.circle") }
                    if let message = prices.message { Text(message).font(.footnote) }
                    if let error = technical.error { Text(error).font(.footnote) }
                    if technical.isOffline { Text("Outils techniques : cache conservé hors ligne.").font(.footnote) }
                }
            }
        }.atlantiqueFormPage("Données métier")
    }
}

private struct AtlantiqueAboutView: View {
    var body: some View {
        AtlantiqueForm {
            AtlantiqueSection("Plaquisto Lab") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Compilation", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                Text("Version de test locale. La vérification des mises à jour App Store n’est pas disponible pour cette distribution.").font(.footnote).foregroundStyle(.secondary)
            }
            AtlantiqueSection("Vos données") {
                Text("Les projets et le stock sont enregistrés sur cet appareil. Aucune synchronisation de compte n’est active.")
                Text("Le catalogue métier et les tarifs proviennent de Plaquisto Admin. Les exports sont partagés uniquement à votre demande.").font(.footnote).foregroundStyle(.secondary)
            }
        }.atlantiqueFormPage("À propos de Plaquisto")
    }
}
