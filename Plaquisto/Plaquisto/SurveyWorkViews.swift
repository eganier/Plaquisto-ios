import SwiftUI
import SceneKit
import CryptoKit

/// Static thumbnails, not a continuously rendered SceneKit view in every row.
@MainActor enum SurveyThumbnailRenderer {
    private static let cache: NSCache<NSString,UIImage> = {
        let value=NSCache<NSString,UIImage>(); value.countLimit=24
        value.totalCostLimit=12*1024*1024; return value
    }()
    static func key(for survey:ProjectSurveyRecord) -> String? {
        let encoder=JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard let data=try? encoder.encode(survey.checkpoints) else { return nil }
        return survey.id.uuidString+SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    }
    static func image(for survey:ProjectSurveyRecord) -> UIImage? {
        guard let key=key(for:survey) else { return nil }
        if let image=cache.object(forKey:key as NSString) { return image }
        let surfaces=SurveyWorkGeometry.surfaces(in:survey)
        guard !surfaces.isEmpty else { return nil }
        let scene=SurveySceneRenderer.make(survey:survey,surfaces:surfaces)
        // Roofs remain stored; hide them only in this cutaway thumbnail.
        for surface in surfaces where surface.source.kind == .ceiling {
            scene.rootNode.childNode(withName:surface.id,recursively:false)?.isHidden=true
        }
        SurveySceneRenderer.frame(scene,aspect:4.0/3.0)
        MaquetteStyle.installStudio(in:scene,quality:.economical)
        let renderer=SCNRenderer(device:nil,options:nil)
        renderer.scene=scene; renderer.pointOfView=scene.rootNode.childNode(withName:"camera",recursively:false)
        if let camera=renderer.pointOfView?.camera { MaquetteStyle.configure(camera,quality:.economical) }
        let image=renderer.snapshot(atTime:0,with:CGSize(width:288,height:216),antialiasingMode:.multisampling2X)
        cache.setObject(image,forKey:key as NSString,cost:288*216*4)
        return image
    }
}

struct SurveyThumbnailView: View {
    let survey:ProjectSurveyRecord
    @State private var preview:UIImage?
    var body:some View {
        ZStack {
            Color(uiColor:MaquetteStyle.background)
            if let preview {
                Image(uiImage:preview).resizable().scaledToFit()
            } else {
                Image(systemName:"cube.transparent").font(.title).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .task(id:survey) {
            preview=nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            preview=SurveyThumbnailRenderer.image(for:survey)
        }
    }
}

/// Multi-selection is one draft across all rooms: tapping another room never
/// commits a half-configured work or drops the surfaces selected before it.
struct SurveyWorkSelectionView: View {
    @EnvironmentObject private var store: ProjectStore
    let surveyID: UUID
    @State private var selectionsByMode: [String: Set<String>] = [:]
    @State private var kind = SurveySurfaceSource.Kind.wall
    @State private var painting = false
    @State private var workType = WorkType.peripheralLiningStuds
    @State private var workName = ""
    @State private var creating: SurveyWorkFormDraft?
    @State private var savedName: String?
    @State private var showsPlan = true

    private var selectionMode: String { "\(painting)/\(kind.rawValue)" }
    private var selected: Set<String> { selectionsByMode[selectionMode] ?? [] }

    private var survey: ProjectSurveyRecord? { store.surveys.first { $0.id == surveyID } }
    private var candidates: [SurveyWorkSurface] { survey.map(SurveyWorkGeometry.surfaces) ?? [] }
    private var visible: [SurveyWorkSurface] { candidates.filter { $0.source.kind == kind } }
    private var unavailableCount: Int {
        (survey?.checkpoints ?? []).reduce(0) { total, checkpoint in
            let offered = Set(visible.filter { $0.source.checkpointID == checkpoint.id }.map { $0.source.surfaceID })
            let expected = kind == .wall ? checkpoint.document.room.walls.map(\.id) : checkpoint.document.room.slopes.filter(\.accepted).map(\.id)
            return total + expected.filter { !offered.contains($0) }.count
        }
    }
    private var chosen: [SurveyWorkSurface] {
        visible.filter { selected.contains($0.id) && isUsable($0) && !isClaimed($0) }
    }
    private var chosenIDs: Set<String> { Set(chosen.map(\.id)) }
    private var blockedIDs: Set<String> { Set(candidates.filter { isClaimed($0) || !isUsable($0) }.map(\.id)) }
    private var grossArea: Double { chosen.reduce(0) { $0 + $1.grossArea } }
    private var netArea: Double { SurveyWorkGeometry.totalArea(chosen) }
    private var project: ProjectItem? { survey.flatMap { store.project(id: $0.projectID) } }
    private var claimed: [SurveySurfaceSource] {
        project?.works.filter { $0.type.category == (painting ? .painting : (kind == .wall ? .wallInsulation : .ceilings)) }
            .flatMap(\.components).compactMap(\.surveySource) ?? []
    }
    private func isClaimed(_ value: SurveyWorkSurface) -> Bool { claimed.contains { SurveyWorkGeometry.hasSameSource($0, value.source) } }
    private func isUsable(_ value: SurveyWorkSurface) -> Bool {
        survey?.checkpoints.first { $0.id == value.source.checkpointID }?.isUsableForWork == true
    }
    private func toggle(_ id: String) {
        guard let value = visible.first(where: { $0.id == id }), !isClaimed(value), isUsable(value) else { return }
        var ids = selected
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        selectionsByMode[selectionMode] = ids
    }

    var body: some View {
        List {
            previewSection
            ForEach(survey?.checkpoints ?? []) { checkpoint in
                roomSection(checkpoint)
            }
            creationSection
        }
        .navigationTitle("Choisir les surfaces")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { selectionBar }
        .sheet(item: $creating) { draft in
            SurveyWorkForm(draft: draft) {
                creating = nil; selectionsByMode[selectionMode] = []; savedName = draft.name
            }
        }
        .alert("Ouvrage créé", isPresented: Binding(get: { savedName != nil }, set: { if !$0 { savedName = nil } })) {
            Button("Continuer la sélection") { savedName = nil }
        } message: { Text("\(savedName ?? "") est disponible dans votre projet avec ses composants et son quantitatif.") }
    }

    private var previewSection: some View {
        Section {
                Picker("Traitement", selection: $painting) {
                    Text("Doublage / plafond").tag(false)
                    Text("Peinture (bêta)").tag(true)
                }.pickerStyle(.segmented)
                Picker("Surfaces", selection: $kind) {
                    Text("Murs").tag(SurveySurfaceSource.Kind.wall)
                    Text("Plafonds").tag(SurveySurfaceSource.Kind.ceiling)
                }.pickerStyle(.segmented)
                Picker("Vue du relevé", selection: $showsPlan) {
                    Text("Plan 2D").tag(true)
                    Text("Vue 3D").tag(false)
                }.pickerStyle(.segmented)
                if let survey {
                    Group {
                        if showsPlan {
                            SurveySurfacePlan(survey: survey, surfaces: candidates, kind: kind,
                                selected: chosenIDs, blocked: blockedIDs, onTap: toggle)
                        } else {
                            SurveySurfaceScene(survey: survey, surfaces: candidates, kind: kind,
                                selected: chosenIDs, claimed: blockedIDs, onTap: toggle)
                        }
                    }
                        .frame(height: 310)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    if survey.checkpoints.count > 1 && survey.checkpoints.contains(where: { $0.spatialLinkState == .needsLink }) {
                        Label("Captures non raccordées : aperçu séparé, sans modifier leurs mesures.", systemImage: "link")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Touchez plusieurs surfaces sur le dessin ou dans la liste. Orange : sélection. Gris : indisponible. Vos sélections sont conservées séparément pour chaque traitement et famille de surfaces.")
                    .font(.footnote).foregroundStyle(.secondary)
                if kind == .ceiling && visible.isEmpty {
                    Label("Aucun contour de plafond validé dans ce relevé. Vérifiez d’abord les plafonds dans l’éditeur du scan.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if unavailableCount > 0 {
                    Label("\(unavailableCount) surface(s) non exploitable(s) : vérifiez leurs contours dans le relevé. Aucune surface de remplacement n’a été inventée.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
        }
    }

    @ViewBuilder private func roomSection(_ checkpoint: ProjectRoomScanCheckpoint) -> some View {
        let values = visible.filter { $0.source.checkpointID == checkpoint.id }
        Section(checkpoint.document.room.name ?? "Pièce") {
            if !checkpoint.isUsableForWork {
                SurveyCheckpointStatusLabel(checkpoint: checkpoint)
                Text("Ces surfaces ne peuvent pas encore être attribuées. Contrôlez les dimensions et les ouvertures, puis validez le relevé.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(values) { value in surfaceRow(value) }
            NavigationLink {
                ProjectSurveyRoomView(surveyID: surveyID, checkpoint: checkpoint)
            } label: {
                Label("Contrôler \(checkpoint.document.room.name ?? "la pièce")", systemImage: "ruler")
            }
        }
    }

    private func surfaceRow(_ value: SurveyWorkSurface) -> some View {
        let assigned = isClaimed(value)
        let usable = isUsable(value)
        let symbol = !usable ? "exclamationmark.triangle" : (assigned ? "checkmark.seal.fill" : (chosenIDs.contains(value.id) ? "checkmark.circle.fill" : "circle"))
        return Button { toggle(value.id) } label: {
            HStack {
                Image(systemName: symbol).foregroundStyle(assigned || !usable ? Color.gray : Color.orange)
                VStack(alignment: .leading) {
                    Text(value.name).foregroundStyle(.primary)
                    if assigned { Text("Déjà attribué à ce traitement").font(.caption).foregroundStyle(.secondary) }
                    if !usable { Text("Relevé à valider").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text("\(value.netArea.formatted(.number.precision(.fractionLength(2)))) m²")
            }
        }.buttonStyle(.plain).disabled(assigned || !usable)
    }

    private var creationSection: some View {
            Section {
                LabeledContent("Surfaces sélectionnées", value: "\(chosen.count)")
                LabeledContent("Surface brute", value: area(grossArea))
                LabeledContent("Ouvertures déduites", value: area(max(0, grossArea - netArea)))
                LabeledContent("Surface nette", value: area(netArea))
                if painting {
                    LabeledContent("Traitement", value: "Peinture (bêta)")
                } else if kind == .wall {
                    Picker("Système", selection: $workType) {
                        Text("Rails et montants").tag(WorkType.peripheralLiningStuds)
                        Text("Lisses et fourrures").tag(WorkType.peripheralLiningFurrings)
                    }
                } else {
                    LabeledContent("Système", value: "Plafond sur fourrures")
                }
                TextField("Nom de l’ouvrage (facultatif)", text: $workName)
            } header: { Text("Nouvel ouvrage") } footer: {
                Text("Chaque surface reste un composant de l’ouvrage avec son contour et ses ouvertures. Les ouvertures sont déjà déduites de la surface nette. Aucun ouvrage n’est créé avant l’enregistrement du formulaire.")
            }
    }

    private func area(_ value: Double) -> String { "\(value.formatted(.number.precision(.fractionLength(2)))) m²" }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(chosen.count) surface(s)").font(.headline)
                Text("\(area(netArea)) nets").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Continuer", action: continueToForm)
                .buttonStyle(.borderedProminent).disabled(chosen.isEmpty)
        }
        .padding().background(.regularMaterial)
    }

    private func continueToForm() {
        guard let project, !chosen.isEmpty else { return }
        let type: WorkType = painting ? .paintingBeta : (kind == .ceiling ? .ceilingOnFurring : workType)
        let typedName = workName.trimmingCharacters(in: .whitespacesAndNewlines)
        creating = .init(surveyID: surveyID, selections: chosen,
            name: typedName.isEmpty ? store.defaultWorkName(projectID: project.id, type: type) : typedName,
            type: type, roomID: nil)
    }
}

/// Deliberately limited to a metric surface; no invented paint yield or supplies.
struct PaintingBetaConfiguratorView: View {
    let readOnlyArea: Bool
    let onSave: (PaintingBetaConfiguration) -> Void
    @State private var area: Double

    init(initialConfiguration: PaintingBetaConfiguration = .init(), readOnlyArea: Bool = false,
         onSave: @escaping (PaintingBetaConfiguration) -> Void) {
        self.readOnlyArea = readOnlyArea; self.onSave = onSave
        _area = State(initialValue: initialConfiguration.area)
    }
    var body: some View {
        Form {
            Section("Surface à peindre") {
                if readOnlyArea {
                    LabeledContent("Surface nette", value: "\(area.formatted(.number.precision(.fractionLength(2)))) m²")
                } else {
                    HStack {
                        Text("Surface")
                        Spacer()
                        ZeroEmptyDecimalTextField(value: $area).multilineTextAlignment(.trailing).frame(width: 100)
                        Text("m²").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Label("Formulaire provisoire", systemImage: "paintbrush")
                Text("Cette première version conserve les surfaces à peindre. La préparation, les couches et les consommables seront ajoutés ultérieurement.")
                    .font(.footnote).foregroundStyle(.secondary)
                if readOnlyArea {
                    Text("Les ouvertures sont déjà déduites. Pour changer les dimensions, modifiez le contour de la surface source.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Enregistrer") { onSave(.init(area: area)) }
                    .disabled(!area.isFinite || area <= 0)
            }
        }
        .navigationTitle("Peinture (bêta)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SurveyWorkFormDraft: Identifiable {
    let id = UUID()
    let surveyID: UUID
    let selections: [SurveyWorkSurface]
    let name: String
    let type: WorkType
    let roomID: UUID?
}

struct SurveyWorkForm: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var lining = DoublageReferenceStore()
    @StateObject private var furring = FurringLiningReferenceStore()
    @StateObject private var partition = CloisonDistributionReferenceStore()
    let draft: SurveyWorkFormDraft
    let onSaved: () -> Void
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                switch draft.type {
                case .distributionPartition:
                    CloisonDistributionConfiguratorView(initialConfiguration: SurveyWorkGeometry.partition(draft.selections),
                        onSave: { save(.distributionPartition($0)) }, onClose: { dismiss() }, showsCloseButton: false)
                        .environmentObject(partition)
                        .task { await partition.load() }
                case .paintingBeta:
                    PaintingBetaConfiguratorView(initialConfiguration: .init(area: SurveyWorkGeometry.totalArea(draft.selections)),
                        readOnlyArea: true) { save(.paintingBeta($0)) }
                case .ceilingOnFurring:
                    CeilingConfiguratorView(initialConfiguration: SurveyWorkGeometry.ceiling(draft.selections), lockScannedGeometry: true) { save(.ceiling($0)) }
                case .peripheralLiningStuds:
                    DoublageConfiguratorView(initialConfiguration: SurveyWorkGeometry.lining(draft.selections),
                        onSave: { save(.peripheralLining($0)) }, onClose: { dismiss() }, showsCloseButton: false)
                        .environmentObject(lining)
                        .task { if lining.catalogue == nil { await lining.load() } }
                case .peripheralLiningFurrings:
                    FurringLiningConfiguratorView(initialConfiguration: SurveyWorkGeometry.furring(draft.selections),
                        onSave: { save(.furringLining($0)) }, onClose: { dismiss() }, showsCloseButton: false)
                        .environmentObject(furring)
                        .task { await furring.load() }
                default: ContentUnavailableView("Système non disponible", systemImage: "wrench")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .alert("Enregistrement impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func save(_ payload: WorkConfiguration) {
        do {
            try store.createSurveyWork(surveyID: draft.surveyID, selections: draft.selections,
                name: draft.name, type: draft.type, payload: payload, roomID: draft.roomID)
            onSaved()
        } catch { self.error = error.localizedDescription }
    }
}

/// Both previews use the same surface identifiers and registration. Camera
/// gestures change the view only; attribution remains in the parent draft.
struct SurveySurfacePlan: View {
    let survey: ProjectSurveyRecord
    let surfaces: [SurveyWorkSurface]
    let kind: SurveySurfaceSource.Kind
    let selected: Set<String>
    let blocked: Set<String>
    let onTap: (String) -> Void
    var showsDimensions = true
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag = CGSize.zero

    private struct DrawingSurface {
        let id: String
        let kind: SurveySurfaceSource.Kind
        let points: [CGPoint]
        var openings: [[CGPoint]] = []
        var windows: Set<Int> = []
        var outlines: [[CGPoint]] = []
        var title: String = ""
    }
    private var drawing: [DrawingSurface] {
        var result: [DrawingSurface] = []
        var offset = 0.0
        let separate = survey.checkpoints.count > 1 && survey.checkpoints.contains { $0.spatialLinkState == .needsLink }
        for checkpoint in survey.checkpoints {
            let values = surfaces.filter { $0.source.checkpointID == checkpoint.id }
            let points = values.flatMap(\.triangles)
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            func project(_ p: RoomPoint) -> CGPoint {
                if separate { return CGPoint(x: p.x - minX + offset, y: p.z) }
                let t = checkpoint.transformToSurvey.values
                return CGPoint(x: t[0]*p.x + t[4]*p.y + t[8]*p.z + t[12],
                               y: t[2]*p.x + t[6]*p.y + t[10]*p.z + t[14])
            }
            for value in values {
                if value.source.kind == .wall,
                   let wall = checkpoint.document.room.walls.first(where: { $0.id == value.source.surfaceID }) {
                    let openings = checkpoint.document.room.openings.filter { $0.wallID == wall.id }.map { opening in
                        let start = wall.start + wall.direction * opening.positionOnWall.effectiveValue
                        return [project(start), project(start + wall.direction * opening.width.effectiveValue)]
                    }
                    result.append(.init(id: value.id, kind: .wall,
                        points: [project(wall.start), project(wall.effectiveEnd)], openings: openings,
                        windows:Set(checkpoint.document.room.openings.filter { $0.wallID==wall.id }.enumerated().compactMap {
                            $0.element.kind == .window || $0.element.kind == .glazedBay ? $0.offset : nil
                        })))
                } else {
                    let slope=checkpoint.document.room.slopes.first { $0.id==value.source.surfaceID }
                    result.append(.init(id:value.id,kind:.ceiling,points:value.triangles.map(project),
                        outlines:(slope?.boundaries ?? []).map { $0.map(project) },
                        title:String(value.name.split(separator:"·").first ?? "").trimmingCharacters(in:.whitespaces)))
                }
            }
            offset += maxX - minX + 2
        }
        return result
    }

    var body: some View {
        let elements = drawing
        let labels = ceilingLabels(elements)
        GeometryReader { proxy in
            let points = elements.flatMap(\.points)
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 1
            let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 1
            let width = max(0.5, maxX - minX), height = max(0.5, maxY - minY)
            let fit = max(1, min((proxy.size.width - 96) / width, (proxy.size.height - 96) / height))
            let scale = fit * min(8, max(1, zoom * pinch))
            let limitX = max(0, proxy.size.width / 2 + width * scale / 2 - 40)
            let limitY = max(0, proxy.size.height / 2 + height * scale / 2 - 40)
            let dx = min(limitX, max(-limitX, offset.width + drag.width))
            let dy = min(limitY, max(-limitY, offset.height + drag.height))
            let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let screen: (CGPoint) -> CGPoint = { p in
                CGPoint(x: (p.x - center.x) * scale + proxy.size.width / 2 + dx,
                        y: (p.y - center.y) * scale + proxy.size.height / 2 + dy)
            }
            Canvas { context, _ in
                var occupied:[CGRect]=labels.map { label in
                    let p=screen(label.point), width=CGFloat(label.title.count)*6+16
                    return CGRect(x:p.x-width/2,y:p.y-14,width:width,height:28)
                }
                for element in elements.sorted(by: { $0.kind == .ceiling && $1.kind == .wall }) {
                    let path = shape(element, transform: screen)
                    let active = element.kind == kind
                    let color: Color = blocked.contains(element.id) ? .gray :
                        (selected.contains(element.id) ? .orange : ArchitecturalPlanInk.wall)
                    if element.kind == .wall {
                        context.stroke(path, with: .color(color.opacity(active ? 1 : 0.8)),
                                       style: StrokeStyle(lineWidth: 6, lineCap: .square))
                        for (i,opening) in element.openings.enumerated() where opening.count == 2 {
                            ArchitecturalPlanInk.opening(context,a:screen(opening[0]),b:screen(opening[1]),
                                window:element.windows.contains(i),selected:selected.contains(element.id))
                        }
                        if showsDimensions, let first = element.points.first, let last = element.points.last {
                            ArchitecturalPlanInk.dimension(context,a:screen(first),b:screen(last),
                                meters:Double(hypot(last.x-first.x,last.y-first.y)),center:screen(center),
                                occupied:&occupied,important:selected.contains(element.id))
                        }
                    } else {
                        // Fill triangles, not a bounding polygon: holes stay empty.
                        context.fill(path, with: .color(color.opacity(selected.contains(element.id) ? 0.22 : 0.055)))
                        for outline in element.outlines where !outline.isEmpty {
                            var border=Path(); border.move(to:screen(outline[0]))
                            for point in outline.dropFirst() { border.addLine(to:screen(point)) }; border.closeSubpath()
                            context.stroke(border,with:.color(color.opacity(0.45)),lineWidth:0.8)
                        }
                    }
                }
                for label in labels {
                    ArchitecturalPlanInk.ceilingLabel(context,title:label.title,point:screen(label.point))
                }
            }
            .background(ArchitecturalPlanInk.paper)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                let hits = elements.filter { $0.kind == kind }.filter { element in
                    let path = shape(element, transform: screen)
                    return element.kind == .wall
                        ? path.strokedPath(StrokeStyle(lineWidth: 28, lineCap: .round)).contains(tap.location)
                        : path.contains(tap.location)
                }
                let nearest = hits.min { a, b in
                    distance(tap.location, to: a, transform: screen) < distance(tap.location, to: b, transform: screen)
                }
                if let nearest { onTap(nearest.id) }
            })
            .simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = min(8, max(1, zoom * value.magnification)) })
            .simultaneousGesture(DragGesture(minimumDistance: 8).updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    offset = CGSize(width: min(limitX, max(-limitX, offset.width + value.translation.width)),
                                    height: min(limitY, max(-limitY, offset.height + value.translation.height)))
                })
            .overlay(alignment: .topTrailing) {
                Button { zoom = 1; offset = .zero } label: { Image(systemName: "scope").padding(10) }
                    .buttonStyle(.borderless).background(.regularMaterial, in: Circle()).padding(8)
                    .accessibilityLabel("Recentrer le plan")
            }
            .overlay {
                if elements.isEmpty { Text("Aucune surface exploitable dans ce relevé").font(.footnote).padding() }
            }
            .clipped()
        }
        .accessibilityLabel("Plan 2D de sélection des surfaces")
    }

    private func ceilingLabels(_ elements:[DrawingSurface]) -> [(title:String,point:CGPoint)] {
        Dictionary(grouping:elements.filter { $0.kind == .ceiling },by:\.title).sorted(by:{$0.key<$1.key}).compactMap { title,parts in
            let points=parts.flatMap(\.points)
            guard !points.isEmpty else { return nil }
            let center=CGPoint(x:((points.map(\.x).min() ?? 0)+(points.map(\.x).max() ?? 0))/2,
                               y:((points.map(\.y).min() ?? 0)+(points.map(\.y).max() ?? 0))/2)
            if parts.contains(where:{ shape($0,transform:{$0}).contains(center) }) { return (title,center) }
            var best:CGFloat=0, anchor:CGPoint?
            for part in parts {
                for i in stride(from:0,to:part.points.count-part.points.count%3,by:3) {
                    let a=part.points[i], b=part.points[i+1], c=part.points[i+2]
                    let dx1=b.x-a.x, dy1=b.y-a.y, dx2=c.x-a.x, dy2=c.y-a.y
                    let area=abs(dx1*dy2-dy1*dx2)
                    if area>best { best=area; anchor = .init(x:(a.x+b.x+c.x)/3,y:(a.y+b.y+c.y)/3) }
                }
            }
            return anchor.map { (title,$0) }
        }
    }

    private func shape(_ element: DrawingSurface, transform: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        if element.kind == .wall, let first = element.points.first, let last = element.points.last {
            path.move(to: transform(first)); path.addLine(to: transform(last))
        } else {
            for i in stride(from: 0, to: element.points.count - element.points.count % 3, by: 3) {
                path.move(to: transform(element.points[i]))
                path.addLine(to: transform(element.points[i + 1]))
                path.addLine(to: transform(element.points[i + 2]))
                path.closeSubpath()
            }
        }
        return path
    }

    private func distance(_ point: CGPoint, to element: DrawingSurface, transform: (CGPoint) -> CGPoint) -> CGFloat {
        guard let first = element.points.first, let last = element.points.last else { return .greatestFiniteMagnitude }
        let a = transform(first), b = transform(last)
        let vx = b.x - a.x, vy = b.y - a.y
        let t = min(1, max(0, ((point.x - a.x) * vx + (point.y - a.y) * vy) / max(0.0001, vx * vx + vy * vy)))
        return hypot(point.x - a.x - t * vx, point.y - a.y - t * vy)
    }
}

/// Presentation-only solids/materials. All selection IDs and quantity geometry stay unchanged.
@MainActor enum SurveySceneRenderer {
    static let background = MaquetteStyle.background
    /// Extrude the hole-aware wall mesh. Boundary edges include door/window reveals.
    static func wallSolid(_ triangles: [RoomPoint], normal: RoomPoint, thickness: Double) -> [RoomPoint] {
        let offset = normal*(thickness/2)
        var output: [RoomPoint] = [], edges: [String:(RoomPoint,RoomPoint,Int)] = [:]
        func key(_ p: RoomPoint) -> String { "\(Int64((p.x*100000).rounded()))/\(Int64((p.y*100000).rounded()))/\(Int64((p.z*100000).rounded()))" }
        for i in stride(from:0,to:triangles.count-triangles.count%3,by:3) {
            let a = triangles[i], b = triangles[i+1], c = triangles[i+2]
            output += [a+offset,b+offset,c+offset,c-offset,b-offset,a-offset]
            for (p,q) in [(a,b),(b,c),(c,a)] {
                let id = [key(p),key(q)].sorted().joined(separator:"|")
                edges[id] = (p,q,(edges[id]?.2 ?? 0)+1)
            }
        }
        for (_,edge) in edges where edge.2 == 1 {
            let a = edge.0-offset, b = edge.1-offset, c = edge.1+offset, d = edge.0+offset
            output += [a,b,c,a,c,d]
        }
        return output
    }
    static func make(survey: ProjectSurveyRecord, surfaces: [SurveyWorkSurface]) -> SCNScene {
        let scene = SCNScene(); scene.background.contents = background
        var offset = 0.0
        let separate = survey.checkpoints.count > 1 && survey.checkpoints.contains { $0.spatialLinkState == .needsLink }
        for checkpoint in survey.checkpoints {
            let values = surfaces.filter { $0.source.checkpointID == checkpoint.id }
            let points = values.flatMap(\.triangles)
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
            func transform(_ p: RoomPoint) -> RoomPoint {
                if separate { return .init(x:p.x-minX+offset,y:p.y,z:p.z) }
                let t = checkpoint.transformToSurvey.values
                return .init(x:t[0]*p.x+t[4]*p.y+t[8]*p.z+t[12],
                             y:t[1]*p.x+t[5]*p.y+t[9]*p.z+t[13],
                             z:t[2]*p.x+t[6]*p.y+t[10]*p.z+t[14])
            }
            for surface in values {
                var triangles = surface.triangles
                if surface.source.kind == .wall,
                   let wall = checkpoint.document.room.walls.first(where: { $0.id == surface.source.surfaceID }) {
                    triangles = wallSolid(triangles, normal:.init(x:-wall.direction.z,y:0,z:wall.direction.x),
                                          thickness:min(0.4,max(0.04,wall.thickness?.effectiveValue ?? 0.08)))
                }
                let mesh = MaquetteStyle.geometry(triangles.map(transform))
                mesh.firstMaterial = MaquetteStyle.material(surface.source.kind == .ceiling ? .ceiling : .wall)
                let node = SCNNode(geometry:mesh); node.name = surface.id; node.categoryBitMask = 1; node.castsShadow = true
                scene.rootNode.addChildNode(node)
            }
            for floor in checkpoint.document.room.floors {
                guard let outer = floor.boundaries.first, outer.count >= 3 else { continue }
                let elevation = floor.referenceElevation ?? outer[0].y
                let contour = outer.map { LayoutPoint(x:$0.x*1000,y:$0.z*1000) }
                let holes = floor.boundaries.dropFirst().map { boundary in
                    LayoutOpening(kind:.other,contour:boundary.map { .init(x:$0.x*1000,y:$0.z*1000) })
                }
                let shape = Surface2D(name:"Sol",kind:.ceiling,contour:contour,openings:holes,
                    localFrame:.init(origin:.init(x:0,y:elevation-0.012,z:0),
                                     axisX:.init(x:1,y:0,z:0),axisY:.init(x:0,y:0,z:1)))
                guard (try? shape.netMeasuredArea()) != nil else { continue }
                let triangles = SurveyWorkGeometry.ceilingTriangles(shape)
                // UVs remain metric in the room frame, even when the survey moves it.
                let mesh = MaquetteStyle.geometry(triangles.map(transform),textureCoordinates:triangles.map { MaquetteStyle.uv($0) })
                mesh.firstMaterial = MaquetteStyle.material(.floor)
                let node = SCNNode(geometry:mesh); node.name = "floor/\(floor.id)"; node.categoryBitMask = 2
                scene.rootNode.addChildNode(node)
            }
            offset += maxX-minX+2
        }
        MaquetteStyle.installStudio(in:scene,quality:.current)
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.automaticallyAdjustsZRange = true
        MaquetteStyle.configure(camera.camera!,quality:.current)
        scene.rootNode.addChildNode(camera)
        frame(scene, aspect:1)
        return scene
    }
    static func frame(_ scene: SCNScene, aspect: Double) {
        guard let camera = scene.rootNode.childNode(withName:"camera",recursively:false) else { return }
        let nodes = scene.rootNode.childNodes.filter { $0.geometry != nil }
        let bounds = nodes.flatMap { n -> [SCNVector3] in [n.boundingBox.min,n.boundingBox.max] }
        guard let first = bounds.first else { return }
        let lo = bounds.reduce(first) { SCNVector3(min($0.x,$1.x),min($0.y,$1.y),min($0.z,$1.z)) }
        let hi = bounds.reduce(first) { SCNVector3(max($0.x,$1.x),max($0.y,$1.y),max($0.z,$1.z)) }
        let center = SCNVector3((lo.x+hi.x)/2,(lo.y+hi.y)/2,(lo.z+hi.z)/2)
        let span = max(3,max(hi.x-lo.x,hi.z-lo.z))
        camera.position = SCNVector3(center.x+span*0.8,center.y+span*0.85,center.z+span)
        camera.look(at:center,up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        camera.camera?.orthographicScale = Double(span)*0.85/max(0.5,min(1,aspect))
    }
}

private final class SurveyArchitecturalView: SCNView {
    var needsInitialFraming = true
    override func layoutSubviews() {
        super.layoutSubviews()
        guard needsInitialFraming, bounds.width > 1, bounds.height > 1, let scene else { return }
        needsInitialFraming = false
        SurveySceneRenderer.frame(scene,aspect:Double(bounds.width/bounds.height))
    }
}

struct SurveySurfaceScene: UIViewRepresentable {
    let survey: ProjectSurveyRecord
    let surfaces: [SurveyWorkSurface]
    let kind: SurveySurfaceSource.Kind
    let selected: Set<String>
    let claimed: Set<String>
    let onTap: (String) -> Void
    var showsCeilings: Bool? = nil
    var resetToken = 0

    func makeCoordinator() -> Coordinator { Coordinator(onTap:onTap) }
    func makeUIView(context: Context) -> SCNView {
        let view = SurveyArchitecturalView()
        view.backgroundColor = SurveySceneRenderer.background
        view.allowsCameraControl = true
        MaquetteStyle.configure(view,quality:.current)
        view.addGestureRecognizer(UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        update(view,coordinator:context.coordinator)
    }
    func update(_ view:SCNView,coordinator:Coordinator) {
        coordinator.onTap = onTap
        coordinator.selectableIDs = Set(surfaces.filter { $0.source.kind == kind }.map(\.id))
        let key = GeometryKey(checkpoints:survey.checkpoints,surfaces:surfaces.map { .init(id:$0.id,kind:$0.source.kind,triangles:$0.triangles) })
        if coordinator.geometryKey != key {
            coordinator.geometryKey = key
            coordinator.geometryBuildCount += 1
            view.scene = SurveySceneRenderer.make(survey:survey,surfaces:surfaces)
            (view as? SurveyArchitecturalView)?.needsInitialFraming = true
            view.setNeedsLayout()
            view.pointOfView = view.scene?.rootNode.childNode(withName:"camera",recursively:false)
            coordinator.resetToken = -1
        }
        if coordinator.resetToken != resetToken, let scene = view.scene {
            coordinator.resetToken = resetToken
            SurveySceneRenderer.frame(scene,aspect:Double(max(1,view.bounds.width)/max(1,view.bounds.height)))
            if let camera = view.pointOfView {
                let distance = camera.position
                // Camera target is the geometric centre, independent of selection.
                let world = surfaces.flatMap(\.triangles)
                if !world.isEmpty {
                    let box = scene.rootNode.childNodes.filter { $0.geometry != nil }.map(\.boundingBox)
                    view.defaultCameraController.target = SCNVector3(
                        ((box.map { $0.min.x }.min() ?? distance.x)+(box.map { $0.max.x }.max() ?? distance.x))/2,
                        ((box.map { $0.min.y }.min() ?? 0)+(box.map { $0.max.y }.max() ?? 0))/2,
                        ((box.map { $0.min.z }.min() ?? distance.z)+(box.map { $0.max.z }.max() ?? distance.z))/2)
                }
            }
        }
        let quality=MaquetteStyle.Quality.current
        if coordinator.quality != quality, let scene=view.scene {
            coordinator.quality=quality
            MaquetteStyle.configure(view,quality:quality)
            MaquetteStyle.installStudio(in:scene,quality:quality)
            if let camera=view.pointOfView?.camera { MaquetteStyle.configure(camera,quality:quality) }
        }
        for surface in surfaces {
            guard let node = view.scene?.rootNode.childNode(withName:surface.id,recursively:false) else { continue }
            let ceiling = surface.source.kind == .ceiling
            node.isHidden = ceiling && !(showsCeilings ?? (kind == .ceiling))
            node.opacity = ceiling ? 0.88 : (kind == .ceiling ? 0.32 : 1)
            node.geometry?.firstMaterial = MaquetteStyle.material(ceiling ? .ceiling : .wall,
                state:selected.contains(surface.id) ? .selected : (claimed.contains(surface.id) ? .claimed : .normal),
                translucent:node.opacity < 1)
            node.castsShadow = !node.isHidden && node.opacity == 1
        }
    }
    struct GeometryKey:Equatable {
        struct Mesh:Equatable { let id:String; let kind:SurveySurfaceSource.Kind; let triangles:[RoomPoint] }
        let checkpoints:[ProjectRoomScanCheckpoint]
        let surfaces:[Mesh]
    }
    final class Coordinator: NSObject {
        var onTap: (String) -> Void
        var geometryKey:GeometryKey?
        var geometryBuildCount=0
        var quality:MaquetteStyle.Quality?
        var resetToken = -1
        var selectableIDs = Set<String>()
        init(onTap: @escaping (String) -> Void) { self.onTap = onTap }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in:view),options:[.searchMode:SCNHitTestSearchMode.all.rawValue])
            if let id = hits.compactMap({ $0.node.isHidden ? nil : $0.node.name }).first(where:selectableIDs.contains) { onTap(id) }
        }
    }
}
