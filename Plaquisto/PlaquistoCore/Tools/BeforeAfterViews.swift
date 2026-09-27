import SwiftUI
import PhotosUI

private struct BeforeAfterAccountKey: EnvironmentKey {
    static let defaultValue = BeforeAfterAccountContext.unconfigured
}
extension EnvironmentValues {
    var beforeAfterAccount: BeforeAfterAccountContext {
        get { self[BeforeAfterAccountKey.self] }
        set { self[BeforeAfterAccountKey.self] = newValue }
    }
}

struct BeforeAfterHomeView: View {
    @Environment(\.beforeAfterAccount) private var account
    @State private var projects: [BeforeAfterProject] = []
    @State private var photo: PhotosPickerItem?
    @State private var selected: BeforeAfterProject?
    @State private var opening = false
    @State private var busy = false
    @State private var error: String?
    @State private var deletion: BeforeAfterProject?
    @State private var renaming: BeforeAfterProject?
    @State private var name = ""
    private let store = BeforeAfterProjectStore.shared

    var body: some View {
        List {
            Section {
                VStack(alignment:.leading,spacing:12) {
                    Image(systemName:"rectangle.on.rectangle.angled").font(.largeTitle).foregroundStyle(.tint)
                    Text("Le même cadrage, avant et après.").font(.title3.bold())
                    Text("Choisissez une photo Avant, retrouvez son cadrage avec la caméra, puis créez votre comparatif.").foregroundStyle(.secondary)
                    PhotosPicker(selection:$photo,matching:.images,preferredItemEncoding:.current) {
                        Label("Choisir la photo Avant",systemImage:"photo.badge.plus").frame(maxWidth:.infinity).padding(.vertical,7)
                    }.buttonStyle(.borderedProminent).disabled(busy)
                    if busy { ProgressView("Préparation de la photo…") }
                }.padding(.vertical,8)
            }
            Section {
                if projects.isEmpty {
                    Text("Vos projets seront conservés sur cet iPhone. Vous pourrez les rouvrir et modifier le comparatif.").foregroundStyle(.secondary)
                }
                ForEach(projects) { project in
                    Button { selected = project; opening = true } label: {
                        BeforeAfterProjectRow(project:project)
                    }.buttonStyle(.plain)
                    .swipeActions {
                        Button(role:.destructive) { deletion = project } label: { Label("Supprimer",systemImage:"trash") }
                        Button { renaming = project; name = project.name } label: { Label("Renommer",systemImage:"pencil") }.tint(.blue)
                    }
                }
            } header: { Text("Mes avant / après") }
            footer: { Text("Photos locales, sans synchronisation cloud ni rattachement à un projet. Export sans coordonnées GPS.") }
        }
        .navigationTitle("Montage avant / après").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented:$opening) {
            if let selected { BeforeAfterEditorView(project:selected,onSaved:{ Task { await reload() } }) }
        }
        .task { await reload() }
        .task(id:photo) {
            guard let photo else { return }
            busy = true
            defer { busy = false; self.photo = nil }
            do {
                guard let file = try await photo.loadTransferable(type:BeforeAfterImportedFile.self) else { throw BeforeAfterError.invalidImage }
                defer { try? FileManager.default.removeItem(at:file.url) }
                let project = try await store.create(from:file.url,identifier:photo.itemIdentifier,company:account.companyName)
                await reload(); selected = project; opening = true
            } catch { self.error = "Import impossible. Vérifiez que la photo est téléchargée depuis iCloud, puis réessayez. \(error.localizedDescription)" }
        }
        .alert("Avant / Après",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .alert("Supprimer ce projet et ses photos locales ?",isPresented:Binding(get:{ deletion != nil },set:{ if !$0 { deletion = nil } })) {
            Button("Annuler",role:.cancel) { deletion = nil }
            Button("Supprimer",role:.destructive) {
                if let deletion { Task { do { try await store.delete(deletion.id); await reload() } catch { self.error = error.localizedDescription } } }
                deletion = nil
            }
        } message: { Text("La photo d’origine dans votre photothèque ne sera pas supprimée.") }
        .alert("Renommer le projet",isPresented:Binding(get:{ renaming != nil },set:{ if !$0 { renaming = nil } })) {
            TextField("Nom",text:$name)
            Button("Annuler",role:.cancel) { renaming = nil }
            Button("Enregistrer") {
                if var project = renaming {
                    project.name = name.trimmingCharacters(in:.whitespacesAndNewlines)
                    Task { do { _ = try await store.save(project); await reload() } catch { self.error = error.localizedDescription } }
                }; renaming = nil
            }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }
    }
    private func reload() async {
        do { projects = try await store.list() } catch { self.error = error.localizedDescription }
    }
}

private struct BeforeAfterProjectRow: View {
    let project: BeforeAfterProject
    var body: some View {
        HStack(spacing:12) {
            BeforeAfterThumbnail(project:project)
            VStack(alignment:.leading,spacing:4) {
                Text(project.name).font(.headline).foregroundStyle(.primary)
                Text(project.updatedAt,format:.dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                Text(project.after == nil ? "Photo Après à prendre" : project.mode.title).font(.caption).foregroundStyle(.secondary)
                if !project.city.isEmpty { Text(project.city).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct BeforeAfterThumbnail: View {
    let project: BeforeAfterProject
    @Environment(\.beforeAfterAccount) private var account
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit() }
            else { Image(systemName:"photo").foregroundStyle(.secondary) }
        }.frame(width:112,height:84).background(.black.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:10))
            .task(id:(try? JSONEncoder().encode(project))?.base64EncodedString()) {
                image = await BeforeAfterProjectStore.shared.thumbnail(project:project,account:account)
            }
    }
}

@MainActor
final class BeforeAfterEditorModel: ObservableObject {
    @Published var project: BeforeAfterProject
    @Published var before: UIImage?
    @Published var pair: (UIImage,UIImage)?
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var exportURL: URL?
    @Published var saved = false
    private let store: BeforeAfterProjectStore
    private let processing: BeforeAfterProcessing
    init(project: BeforeAfterProject,store: BeforeAfterProjectStore = .shared,processing: BeforeAfterProcessing = .apple()) {
        self.project = project; self.store = store; self.processing = processing
    }
    func load() async {
        busy = true; status = "Chargement…"
        defer { busy = false }
        do {
            let url = try await store.imageURL(project.before,projectID:project.id)
            before = try await Task.detached(priority:.userInitiated) { UIImage(cgImage:try BeforeAfterImages.load(url,maxPixel:1200)) }.value
            if project.after != nil && project.alignment == nil { await alignAndSave() }
            try await refreshPair()
        } catch { self.error = error.localizedDescription }
    }
    func refreshPair() async throws {
        guard let after = project.after else { pair = nil; return }
        let a = try await store.imageURL(project.before,projectID:project.id)
        let b = try await store.imageURL(after,projectID:project.id), snapshot = project
        pair = try await Task.detached(priority:.userInitiated) {
            let p = try BeforeAfterAlignmentEngine.pair(project:snapshot,before:a,after:b,maxPixel:1000)
            return (UIImage(cgImage:p.0),UIImage(cgImage:p.1))
        }.value
    }
    func capture(_ data: Data, summary: String) async {
        busy = true; status = "Enregistrement de la photo…"
        defer { busy = false }
        do {
            project = try await store.addCapture(data,to:project,summary:summary)
            saved = true // A valid After is durable even if alignment fails or app is killed.
            await alignAndSave()
            try await refreshPair()
        } catch { self.error = error.localizedDescription }
    }
    private func alignAndSave() async {
        guard let after = project.after else { return }
        status = "Recalage des deux photos…"
        do {
            let a = try await store.imageURL(project.before,projectID:project.id)
            let b = try await store.imageURL(after,projectID:project.id)
            project.alignment = await processing.align(before:a,after:b)
            project.usesAlignment = project.alignment?.isUsable == true
            project = try await store.save(project)
        } catch { self.error = error.localizedDescription }
    }
    func retryAlignment() async {
        busy = true; defer { busy = false }
        await alignAndSave()
        do { try await refreshPair() } catch { self.error = error.localizedDescription }
    }
    func save() async -> Bool {
        busy = true; status = "Enregistrement…"; defer { busy = false }
        do { project = try await store.save(project); saved = true; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func persistEdits() async {
        guard !busy else { return }
        let snapshot = project
        do {
            _ = try await store.save(snapshot)
            if project == snapshot { saved = true }
        } catch { self.error = error.localizedDescription }
    }
    func export(account: BeforeAfterAccountContext) async {
        guard let after = project.after else { return }
        busy = true; status = "Préparation de l’export…"; defer { busy = false }
        do {
            project = try await store.save(project); saved = true
            let a = try await store.imageURL(project.before,projectID:project.id), b = try await store.imageURL(after,projectID:project.id)
            exportURL = try await processing.export(project:project,before:a,after:b,account:account)
        } catch { self.error = error.localizedDescription }
    }
}

private struct BeforeAfterEditorView: View {
    @StateObject private var model: BeforeAfterEditorModel
    @Environment(\.beforeAfterAccount) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var camera = false
    @State private var share = false
    @State private var confirmCity = false
    @State private var cityBusy = false
    @State private var pendingSave: Task<Void,Never>?
    @Environment(\.scenePhase) private var phase
    let onSaved: () -> Void
    init(project: BeforeAfterProject,onSaved: @escaping () -> Void) {
        _model = StateObject(wrappedValue:BeforeAfterEditorModel(project:project)); self.onSaved = onSaved
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if let pair = model.pair {
                    Text("Ajuster le comparatif").font(.headline)
                    BeforeAfterComparisonView(project:$model.project,pair:pair,account:account)
                    Picker("Mode de comparaison",selection:$model.project.mode) {
                        ForEach(BeforeAfterMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu)
                    // The gesture modifies only the mask, never the image registration.
                    if let alignment = model.project.alignment {
                        Label(alignment.message,systemImage:alignment.isUsable ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(alignment.isUsable ? Color.secondary : .orange)
                        if alignment.isUsable {
                            Toggle("Utiliser le recalage",isOn:$model.project.usesAlignment)
                                .onChange(of:model.project.usesAlignment) { _, _ in
                                    Task { model.busy = true; defer { model.busy = false }; do { try await model.refreshPair() } catch { model.error = error.localizedDescription } }
                                }
                        }
                    }
                    branding
                    if account.canDisableWatermark { Toggle("Filigrane Plaquisto",isOn:$model.project.showsWatermark) }
                    Button { Task { await model.export(account:account); if model.exportURL != nil { share = true; onSaved() } } } label: {
                        Label("Exporter et partager",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity).padding(.vertical,8)
                    }.buttonStyle(.borderedProminent)
                    Text("JPEG jusqu’à 2 000 px par photo. Enregistrez dans Photos ou Fichiers via le partage iOS. Les photos du projet sont conservées séparément du rendu.").font(.caption).foregroundStyle(.secondary)
                } else if let before = model.before {
                    Image(uiImage:before).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:18))
                    Text("Photo Avant enregistrée").font(.headline)
                    Text("Retrouvez son cadrage avec le calque sur la caméra, puis prenez la photo Après.").foregroundStyle(.secondary)
                }
                if model.before != nil {
                    Button { camera = true } label: {
                        Label(model.project.after == nil ? "Prendre la photo Après" : "Reprendre la photo Après",systemImage:"camera.fill").frame(maxWidth:.infinity).padding(.vertical,8)
                    }.buttonStyle(.bordered)
                }
                if model.saved { Label("Projet enregistré sur cet iPhone",systemImage:"checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            }.padding()
            .disabled(model.busy)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.project.name).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement:.topBarLeading) { Button { pendingSave?.cancel(); Task { if await model.save() { onSaved(); dismiss() } } } label: { Image(systemName:"chevron.left") }.accessibilityLabel("Revenir aux projets").disabled(model.busy) }
            ToolbarItem(placement:.topBarTrailing) { Button("Enregistrer") { Task { if await model.save() { onSaved(); dismiss() } } }.disabled(model.busy) }
        }
        .overlay { if model.busy { ProgressView(model.status).padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18)) } }
        .task { await model.load() }
        .onChange(of:model.project) { _, _ in
            model.saved = false
            pendingSave?.cancel()
            guard !model.busy else { return }
            pendingSave = Task {
                do { try await Task.sleep(for:.milliseconds(450)) } catch { return }
                await model.persistEdits(); onSaved()
            }
        }
        .onChange(of:phase) { _, value in
            if value != .active { pendingSave?.cancel(); Task { await model.persistEdits(); onSaved() } }
        }
        .fullScreenCover(isPresented:$camera) {
            if let before = model.before {
                BeforeAfterCameraView(before:before,metadata:model.project.before.metadata) { data,summary in
                    Task { await model.capture(data,summary:summary); onSaved() }
                }
            }
        }
        .sheet(isPresented:$share) { if let url = model.exportURL { BeforeAfterShareSheet(url:url) } }
        .alert("Avant / Après",isPresented:Binding(get:{ model.error != nil },set:{ if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("Rechercher la ville ?",isPresented:$confirmCity) {
            Button("Annuler",role:.cancel) {}
            Button("Rechercher") {
                Task {
                    cityBusy = true; defer { cityBusy = false }
                    do {
                        guard let city = try await BeforeAfterCityResolver.city(for:model.project.before.metadata) else {
                            model.error = "Ville introuvable. Vous pouvez la saisir manuellement."; return
                        }
                        model.project.city = city
                    } catch { model.error = "La recherche de ville a échoué. Vous pouvez la saisir manuellement." }
                }
            }
        } message: { Text("Les coordonnées de la photo seront utilisées par le service de géocodage Apple pour obtenir uniquement la ville. Elles ne seront pas ajoutées à l’image exportée.") }
    }
    private var branding: some View {
        DisclosureGroup("Texte sur l’image") {
            VStack(spacing:14) {
                Toggle("Ajouter mon texte",isOn:$model.project.showsBranding)
                if model.project.showsBranding {
                    TextField("Entreprise (facultatif)",text:$model.project.company).textFieldStyle(.roundedBorder)
                    TextField("Ville ou lieu (facultatif)",text:$model.project.city).textFieldStyle(.roundedBorder)
                    if model.project.before.metadata.hasLocation {
                        Button(cityBusy ? "Recherche…" : "Retrouver la ville via les métadonnées de la photo") { confirmCity = true }.disabled(cityBusy)
                    }
                }
            }.padding(.vertical,10)
        }
    }
}

private struct BeforeAfterMask: Shape {
    let mode: BeforeAfterMode
    let position: Double
    let angle:Double
    func path(in rect: CGRect) -> Path { Path(BeforeAfterRenderEngine.beforeMask(mode:mode,position:position,size:rect.size,angle:angle)) }
}
private struct BeforeAfterComparisonView: View {
    @Binding var project: BeforeAfterProject
    let pair: (UIImage,UIImage)
    let account: BeforeAfterAccountContext
    @State private var rotationDrag: (pivot:CGPoint,angle:Double,fingerAngle:Double)?
    @State private var dragging = false
    init(project: Binding<BeforeAfterProject>,pair: (UIImage,UIImage),account: BeforeAfterAccountContext) { _project = project; self.pair = pair; self.account = account }
    var body: some View {
        let ratio = pair.0.size.width/pair.0.size.height*(project.mode == .sideBySide ? 2 : 1)
        GeometryReader { geometry in
            let ends = BeforeAfterDividerGeometry.endpoints(mode:project.mode,position:project.dividerPosition,angle:project.effectiveDiagonalAngle)
            ZStack {
                if project.mode == .sideBySide {
                    HStack(spacing:0) { Image(uiImage:pair.0).resizable(); Image(uiImage:pair.1).resizable() }
                } else {
                    Image(uiImage:pair.1).resizable()
                    Image(uiImage:pair.0).resizable().mask(BeforeAfterMask(mode:project.mode,position:project.dividerPosition,angle:project.effectiveDiagonalAngle))
                }
                if account.requiresWatermark(requested:project.showsWatermark) {
                    BeforeAfterWatermarkView().allowsHitTesting(false)
                }
                if ends.count == 2 {
                    Path { path in
                        path.move(to:CGPoint(x:ends[0].x*geometry.size.width,y:ends[0].y*geometry.size.height))
                        path.addLine(to:CGPoint(x:ends[1].x*geometry.size.width,y:ends[1].y*geometry.size.height))
                    }.stroke(.white,lineWidth:1.5)
                    Image(systemName:project.mode == .horizontal ? "arrow.up.and.down" : "arrow.left.and.right")
                        .font(.caption.bold()).foregroundStyle(.black).padding(7).background(.white,in:Circle())
                        .position(x:(ends[0].x+ends[1].x)/2*geometry.size.width,y:(ends[0].y+ends[1].y)/2*geometry.size.height)
                    if project.mode == .diagonal {
                        let handle = rotationHandle(ends,size:geometry.size)
                        Image(systemName:"arrow.triangle.2.circlepath")
                            .font(.system(size:15,weight:.semibold)).foregroundStyle(.black)
                            .frame(width:36,height:36).background(.white,in:Circle())
                            .overlay(Circle().stroke(.black.opacity(0.2)))
                            .position(handle)
                            .accessibilityLabel("Tourner la diagonale")
                            .accessibilityHint("Glissez ce bouton autour du centre du séparateur")
                            .accessibilityAdjustableAction { direction in
                                project.diagonalAngle = project.effectiveDiagonalAngle + (direction == .increment ? .pi/36 : -.pi/36)
                            }
                    }
                }
                if project.mode == .diagonal {
                    ForEach([true,false],id:\.self) { isBefore in
                        let point = BeforeAfterDividerGeometry.labelPoint(before:isBefore,angle:project.effectiveDiagonalAngle)
                        let projection = BeforeAfterDividerGeometry.position(at:point,angle:project.effectiveDiagonalAngle)
                        if isBefore ? projection < project.dividerPosition : projection > project.dividerPosition {
                            badge(isBefore ? "AVANT" : "APRÈS")
                                .position(x:point.x*geometry.size.width,y:point.y*geometry.size.height)
                                .allowsHitTesting(false)
                        }
                    }
                }
                VStack {
                    HStack {
                        if project.mode != .diagonal && (project.mode == .sideBySide || project.dividerPosition > 0.15) { badge("AVANT") }
                        Spacer()
                        if (project.mode == .sideBySide || project.mode == .vertical) && (project.mode == .sideBySide || project.dividerPosition < 0.85) { badge("APRÈS") }
                    }
                    Spacer()
                    if project.mode == .horizontal && project.dividerPosition < 0.85 { HStack { Spacer(); badge("APRÈS") } }
                    if project.showsBranding, !project.branding.isEmpty { HStack { badge(project.branding); Spacer() } }
                }.padding(8).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance:0)
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        if project.mode == .diagonal, ends.count == 2 {
                            let handle = rotationHandle(ends,size:geometry.size)
                            if hypot(value.startLocation.x-handle.x,value.startLocation.y-handle.y) < 28 {
                                let pivot = CGPoint(x:(ends[0].x+ends[1].x)/2*geometry.size.width,y:(ends[0].y+ends[1].y)/2*geometry.size.height)
                                rotationDrag = (pivot,project.effectiveDiagonalAngle,
                                    atan2((value.startLocation.y-pivot.y)/geometry.size.height,(value.startLocation.x-pivot.x)/geometry.size.width))
                            }
                        }
                    }
                    updateGesture(at:value.location,size:geometry.size)
                }
                .onEnded { value in
                    updateGesture(at:value.location,size:geometry.size)
                    dragging = false; rotationDrag = nil
                })
        }.aspectRatio(ratio,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:16))
    }
    private func badge(_ title: String) -> some View {
        Text(title).font(.caption2.bold()).lineLimit(1).foregroundStyle(.white).padding(4).background(.black.opacity(0.6))
    }
    private func rotationHandle(_ ends:[BeforeAfterPoint],size:CGSize) -> CGPoint {
        .init(x:(ends[0].x*0.2+ends[1].x*0.8)*size.width,y:(ends[0].y*0.2+ends[1].y*0.8)*size.height)
    }
    private func updateGesture(at point:CGPoint,size:CGSize) {
        if let rotationDrag {
            let x = (point.x-rotationDrag.pivot.x)/size.width, y = (point.y-rotationDrag.pivot.y)/size.height
            guard hypot(x,y) > 0.025 else { return }
            let angle = rotationDrag.angle+atan2(y,x)-rotationDrag.fingerAngle
            project.diagonalAngle = angle
            project.divider = BeforeAfterDividerGeometry.position(at:.init(x:rotationDrag.pivot.x/size.width,y:rotationDrag.pivot.y/size.height),angle:angle)
        } else { updateDivider(at:point,size:size) }
    }
    private func updateDivider(at location: CGPoint,size: CGSize) {
        switch project.mode {
        case .sideBySide: break
        case .vertical: project.divider = min(1,max(0,location.x/size.width))
        case .horizontal: project.divider = min(1,max(0,location.y/size.height))
        case .diagonal: project.divider = BeforeAfterDividerGeometry.position(at:.init(x:location.x/size.width,y:location.y/size.height),angle:project.effectiveDiagonalAngle)
        }
    }
}

private struct BeforeAfterWatermarkView: View {
    var body: some View {
        Canvas { context, size in
            let text = Text("Plaquisto").font(.system(size:min(size.width,size.height)*0.075,weight:.bold))
                .foregroundStyle(.white.opacity(BeforeAfterWatermarkStyle.opacity))
            for point in BeforeAfterWatermarkStyle.positions {
                var c = context
                c.translateBy(x:point.x*size.width,y:point.y*size.height)
                c.rotate(by:.radians(BeforeAfterWatermarkStyle.angle))
                c.addFilter(.shadow(color:.black.opacity(0.18),radius:1,y:1))
                c.draw(text,at:.zero)
            }
        }.clipped()
    }
}

private struct BeforeAfterShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
