import SwiftUI

struct ScannerProjectSaveView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let document: PlaquistoRoomDocument
    @State private var projectID: UUID?
    @State private var surveyID: UUID?
    @State private var roomID: UUID?
    @State private var projectName = ""
    @State private var surveyName = "Relevé 3D"
    @State private var roomName = ""
    @State private var error: String?
    @State private var confirmingReplacement = false
    @State private var hasLoaded = false

    private var selectedProject: ProjectItem? { projectID.flatMap { store.project(id: $0) } }
    private var availableSurveys: [ProjectSurveyRecord] {
        projectID.map { store.surveys(projectID: $0) } ?? []
    }

    var body: some View {
        Form {
            Section("Projet") {
                Picker("Destination", selection: $projectID) {
                    Text("Créer un projet").tag(UUID?.none)
                    ForEach(store.projects) { project in Text(project.name).tag(Optional(project.id)) }
                }
                if projectID == nil {
                    TextField("Nom du projet", text: $projectName)
                }
            }

            Section("Relevé 3D") {
                if projectID != nil, !availableSurveys.isEmpty {
                    Picker("Relevé", selection: $surveyID) {
                        Text("Créer un relevé").tag(UUID?.none)
                        ForEach(availableSurveys) { survey in
                            Text("\(survey.name) · \(survey.checkpoints.count) pièce(s)").tag(Optional(survey.id))
                        }
                    }
                }
                if surveyID == nil {
                    TextField("Nom du relevé", text: $surveyName)
                }
                Text("Un relevé regroupe plusieurs pièces d’un même niveau. Une pièce reste exploitable même si son raccord avec les autres doit être vérifié.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Pièce") {
                if let selectedProject, !selectedProject.rooms.isEmpty {
                    Picker("Rattachement", selection: $roomID) {
                        Text("Créer une pièce").tag(UUID?.none)
                        ForEach(selectedProject.rooms) { room in Text(room.name).tag(Optional(room.id)) }
                    }
                }
                if roomID == nil {
                    TextField("Nom de la pièce", text: $roomName)
                } else if let room = selectedProject?.rooms.first(where: { $0.id == roomID }) {
                    LabeledContent("Pièce choisie", value: room.name)
                }
            }

            Section {
                Button("Enregistrer la pièce") {
                    if existingCheckpoint != nil { confirmingReplacement = true }
                    else { save() }
                }
                    .frame(maxWidth: .infinity)
                    .disabled(!canSave)
                if let error { Text(error).foregroundStyle(.red) }
            } footer: {
                Text("Cette étape enregistre le relevé. Depuis le relevé sauvegardé, sélectionnez plusieurs surfaces pour créer un ouvrage.")
            }
        }
        .navigationTitle("Enregistrer le relevé")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            projectID = store.projects.first?.id
            if let name = document.room.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { roomName = name }
            else { roomName = "Pièce 1" }
        }
        .onChange(of: projectID) { _, _ in surveyID = nil; roomID = nil }
        .onChange(of: roomID) { _, id in
            if let id, let room = selectedProject?.rooms.first(where: { $0.id == id }) { roomName = room.name }
        }
        .alert("Remplacer le scan de cette pièce ?", isPresented: $confirmingReplacement) {
            Button("Annuler", role: .cancel) { }
            Button("Remplacer le scan", role: .destructive) { save(replacing: true) }
        } message: {
            Text("Le scan et ses corrections enregistrés dans ce relevé seront remplacés par cette capture.")
        }
    }

    private var existingCheckpoint: ProjectRoomScanCheckpoint? {
        guard let survey = availableSurveys.first(where: { $0.id == surveyID }) else { return nil }
        let normalizedName = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let resolvedRoomID = roomID ?? selectedProject?.rooms.first {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalizedName
        }?.id
        return survey.checkpoints.first { $0.roomID == resolvedRoomID }
    }

    private var canSave: Bool {
        let projectOK = projectID != nil || !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let surveyOK = surveyID != nil || !surveyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let roomOK = roomID != nil || !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return projectOK && surveyOK && roomOK
    }

    private func save(replacing: Bool = false) {
        do {
            _ = try store.saveScannedRoom(projectID: projectID, newProjectName: projectName,
                surveyID: surveyID, surveyName: surveyName, roomID: roomID,
                roomName: roomName, document: document, replacingExistingCapture: replacing)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Reads the same project archive used by the business screens; no separate copy.
struct ProjectSurveyDetailView: View {
    let surveyID: UUID
    var body: some View { ScannerCampaignWorkspaceView(draft: ScanCampaignDraft(id: surveyID)) }
}

struct ProjectSurveyDetailsListView: View {
    @EnvironmentObject private var store: ProjectStore
    let surveyID: UUID

    var body: some View {
        if let survey = store.surveys.first(where: { $0.id == surveyID }) {
            List {
                Section {
                    NavigationLink {
                        ProjectSurveyFloorPlanView(surveyID: surveyID)
                    } label: {
                        Label("Voir le plan 2D", systemImage: "map")
                    }
                    NavigationLink {
                        SurveyWorkSelectionView(surveyID: surveyID)
                    } label: {
                        Label("Créer un ouvrage depuis les surfaces", systemImage: "square.stack.3d.up")
                    }
                }
                Section {
                    ForEach(survey.checkpoints) { checkpoint in
                        NavigationLink {
                            ProjectSurveyRoomView(surveyID: surveyID, checkpoint: checkpoint)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(checkpoint.document.room.name ?? "Pièce").font(.headline)
                                Text("\(checkpoint.document.room.walls.count) murs · \(checkpoint.document.room.openings.count) ouvertures")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                SurveyCheckpointStatusLabel(checkpoint: checkpoint)
                                if checkpoint.spatialLinkState == .needsLink {
                                    Label("Position entre les pièces à vérifier", systemImage: "link")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: { Text("Pièces du relevé") } footer: {
                    Text("Ouvrez une pièce pour contrôler sa géométrie en 3D ou en vue de dessus. Les captures indépendantes restent séparées tant que leur position relative n’est pas établie.")
                }
            }
            .navigationTitle(survey.name)
        } else {
            ContentUnavailableView("Relevé introuvable", systemImage: "cube")
        }
    }
}

/// Shared iOS/Lab renderer. View transforms never change the survey measurements.
struct SurveyFloorPlanView: View {
    let plan: ScanFloorPlan
    var showsDimensions = false
    var interactive = true
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @GestureState private var pinch = 1.0
    @GestureState private var drag = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let points = plan.points
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 1
            let minZ = points.map(\.z).min() ?? 0, maxZ = points.map(\.z).max() ?? 1
            let width = max(0.5, maxX-minX), height = max(0.5, maxZ-minZ)
            let fitted = max(1, min((proxy.size.width-56)/width, (proxy.size.height-56)/height))
            let scale = fitted * min(8, max(1, zoom*pinch))
            let dx = min(proxy.size.width/2 + width*scale/2 - 36, max(-proxy.size.width/2-width*scale/2+36, offset.width+drag.width))
            let dy = min(proxy.size.height/2 + height*scale/2 - 36, max(-proxy.size.height/2-height*scale/2+36, offset.height+drag.height))
            Canvas { context, size in
                func point(_ p: RoomPoint) -> CGPoint {
                    .init(x: size.width/2 + (p.x-(minX+maxX)/2)*scale + dx,
                          y: size.height/2 + (p.z-(minZ+maxZ)/2)*scale + dy)
                }
                for region in plan.regions {
                    var path = Path()
                    for ring in region.rings where ring.count > 2 {
                        path.addLines(ring.map(point)); path.closeSubpath()
                    }
                    context.fill(path, with: .color(.teal.opacity(0.08)), style: .init(eoFill: true))
                    if let ring = region.rings.first, ring.count > 2, !region.name.isEmpty {
                        let center = RoomPoint(x: ring.map(\.x).reduce(0,+)/Double(ring.count), y: 0,
                                               z: ring.map(\.z).reduce(0,+)/Double(ring.count))
                        let inside = region.rings.filter { PlaquistoWallGeometry.contains(center, polygon: $0) }.count % 2 == 1
                        let screenWidth = ((ring.map(\.x).max() ?? 0)-(ring.map(\.x).min() ?? 0))*scale
                        if inside && screenWidth > 90 {
                            context.draw(Text(region.name).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary),
                                         at: point(center))
                        }
                    }
                }
                for segment in plan.segments {
                    let a = point(segment.a), b = point(segment.b)
                    var line = Path(); line.move(to: a); line.addLine(to: b)
                    if let opening = segment.opening {
                        let window = [.window, .glazedBay].contains(opening)
                        context.stroke(line, with: .color(window ? .blue : .secondary.opacity(0.6)),
                            style: .init(lineWidth: window ? 2 : 1, dash: window ? [] : [4,3]))
                        if window {
                            let len = max(1, hypot(b.x-a.x, b.y-a.y))
                            let delta = CGSize(width: -(b.y-a.y)/len*3, height: (b.x-a.x)/len*3)
                            var parallel = Path()
                            parallel.move(to: .init(x: a.x+delta.width, y: a.y+delta.height))
                            parallel.addLine(to: .init(x: b.x+delta.width, y: b.y+delta.height))
                            context.stroke(parallel, with: .color(.blue), lineWidth: 1)
                        }
                    } else {
                        context.stroke(line, with: .color(.primary), style: .init(lineWidth: 4, lineCap: .butt))
                    }
                }
                if showsDimensions {
                    for dimension in plan.dimensions {
                        let a = point(dimension.a), b = point(dimension.b)
                        guard hypot(b.x-a.x, b.y-a.y) > 48 else { continue }
                        let label = Text("\(dimension.meters.formatted(.number.precision(.fractionLength(2)))) m")
                            .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                        context.draw(label, at: .init(x: (a.x+b.x)/2, y: (a.y+b.y)/2-12))
                    }
                }
                // Metric scale, derived from the current zoom (not a measurement).
                let target = min(80, size.width/4) / scale
                let magnitude = pow(10, floor(log10(max(0.0001, target))))
                let meters = ([1.0,2,5].last(where: { $0*magnitude <= target }) ?? 1) * magnitude
                var ruler = Path(); ruler.move(to: .init(x: 14, y: size.height-16))
                ruler.addLine(to: .init(x: 14+meters*scale, y: size.height-16))
                context.stroke(ruler, with: .color(.secondary), lineWidth: 2)
                context.draw(Text("\(meters.formatted()) m").font(.system(size: 9)).foregroundColor(.secondary),
                             at: .init(x: 14, y: size.height-27), anchor: .leading)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .contentShape(Rectangle())
            .gesture(MagnifyGesture().updating($pinch) { value, state, _ in
                if interactive { state = value.magnification }
            }.onEnded { value in if interactive { zoom = min(8, max(1, zoom*value.magnification)) } })
            .simultaneousGesture(DragGesture().updating($drag) { value, state, _ in
                if interactive { state = value.translation }
            }.onEnded { value in
                if interactive {
                    let maxDX = proxy.size.width/2 + width*scale/2 - 36
                    let maxDY = proxy.size.height/2 + height*scale/2 - 36
                    offset = .init(width: min(maxDX, max(-maxDX, offset.width+value.translation.width)),
                                   height: min(maxDY, max(-maxDY, offset.height+value.translation.height)))
                }
            })
            .overlay(alignment: .topTrailing) {
                if interactive {
                    Button { zoom = 1; offset = .zero } label: { Image(systemName: "scope").padding(9) }
                        .buttonStyle(.bordered).padding(8).accessibilityLabel("Recentrer le plan")
                }
            }
            .overlay { if points.isEmpty { Text("Aucun mur relevé").font(.caption).foregroundStyle(.secondary) } }
        }
        .clipped()
        .accessibilityLabel("Plan 2D du relevé, vue de dessus")
    }
}

struct ProjectSurveyFloorPlanView: View {
    @EnvironmentObject private var store: ProjectStore
    let surveyID: UUID
    @State private var dimensions = false
    var body: some View {
        if let survey = store.surveys.first(where: { $0.id == surveyID }) {
            let separate = survey.checkpoints.count > 1 && survey.checkpoints.contains { $0.spatialLinkState == .needsLink }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Afficher les longueurs des murs", isOn: $dimensions)
                    if separate {
                        Label("Pièces non raccordées : plans séparés, sans inventer leur position relative.", systemImage: "link")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(survey.checkpoints) { checkpoint in
                            Text(checkpoint.document.room.name ?? "Pièce").font(.headline)
                            SurveyFloorPlanView(plan: floorPlan([checkpoint]), showsDimensions: dimensions)
                                .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        SurveyFloorPlanView(plan: floorPlan(survey.checkpoints), showsDimensions: dimensions)
                            .frame(height: 430).clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text("Vue de dessus issue du même relevé que la maquette 3D. Bleu : fenêtres ; pointillés : portes et passages. Les sens d’ouverture ne sont pas déduits.")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Créer un ouvrage depuis les surfaces") { SurveyWorkSelectionView(surveyID: surveyID) }
                }.padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Plan 2D")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func floorPlan(_ checkpoints: [ProjectRoomScanCheckpoint]) -> ScanFloorPlan {
        var overview = ScanLiveOverview()
        for checkpoint in checkpoints { overview.update(id: checkpoint.id, room: checkpoint.document.room) }
        return ScanFloorPlan(overview: overview,
            transforms: Dictionary(uniqueKeysWithValues: checkpoints.map { ($0.id, $0.transformToSurvey) }))
    }
}

struct SurveyCheckpointStatusLabel: View {
    let checkpoint: ProjectRoomScanCheckpoint
    var body: some View {
        Group {
            switch checkpoint.effectiveWorkState {
            case .provisional:
                Label("Relevé provisoire · contrôle nécessaire", systemImage: "exclamationmark.triangle")
            case .awaitingValidation:
                Label("Relevé à valider avant attribution", systemImage: "checkmark.shield")
            case .validated:
                Label("Relevé validé pour les ouvrages", systemImage: "checkmark.seal")
            }
        }
        .font(.caption)
        .foregroundStyle(checkpoint.isUsableForWork ? Color.secondary : Color.orange)
    }
}

struct ProjectSurveyRoomView: View {
    @EnvironmentObject private var store: ProjectStore
    let surveyID: UUID
    let checkpoint: ProjectRoomScanCheckpoint
    @State private var expectedDocument: PlaquistoRoomDocument?
    @State private var confirmsValidation = false
    @State private var validationError: String?

    private var currentCheckpoint: ProjectRoomScanCheckpoint {
        store.surveys.first { $0.id == surveyID }?.checkpoints.first { $0.id == checkpoint.id } ?? checkpoint
    }

    var body: some View {
        PlaquistoRoomEditor(document: checkpoint.document, allowsImport: false,
            ceilingNumbers:store.surveys.first { $0.id==surveyID }.map { CeilingPlanNaming.numbers(in:$0) } ?? [:]) { edited in
            try store.updateSurveyRoom(surveyID: surveyID, checkpointID: checkpoint.id,
                expectedDocument: expectedDocument ?? checkpoint.document, document: edited)
            expectedDocument = edited
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                SurveyCheckpointStatusLabel(checkpoint: currentCheckpoint)
                if !currentCheckpoint.isUsableForWork {
                    Text("Contrôlez les contours, dimensions et ouvertures. Seules les corrections déjà enregistrées seront validées.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Valider le relevé pour les ouvrages") { confirmsValidation = true }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(.regularMaterial)
        }
        .confirmationDialog("Valider les mesures enregistrées ?", isPresented: $confirmsValidation, titleVisibility: .visible) {
            Button("J’ai contrôlé le relevé, valider") {
                do {
                    try store.validateSurveyCheckpoint(surveyID: surveyID, checkpointID: checkpoint.id,
                        expectedDocument: expectedDocument ?? checkpoint.document)
                } catch { validationError = error.localizedDescription }
            }
            Button("Continuer le contrôle", role: .cancel) {}
        } message: {
            Text("Les surfaces pourront être utilisées pour créer des ouvrages. Cette validation confirme votre contrôle ; elle ne garantit pas la précision du scan.")
        }
        .alert("Validation impossible", isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })) {
            Button("OK") { validationError = nil }
        } message: { Text(validationError ?? "") }
    }
}
