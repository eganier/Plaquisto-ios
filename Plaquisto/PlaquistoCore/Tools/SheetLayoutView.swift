import SwiftUI

struct LayoutViewport {
    let bounds: LayoutBounds
    let size: CGSize
    let zoom: Double
    let pan: CGSize
    var rotation: Double = 0
    var scale: Double { min(max(1, size.width - 70) / max(100, bounds.width), max(1, size.height - 70) / max(100, bounds.height)) * zoom }
    static func rotated(_ p: LayoutPoint, by angle: Double) -> LayoutPoint {
        .init(x: p.x * cos(angle) - p.y * sin(angle), y: p.x * sin(angle) + p.y * cos(angle))
    }
    func screen(_ p: LayoutPoint) -> CGPoint {
        let r = Self.rotated(p, by: rotation)
        return .init(x: size.width / 2 + pan.width + (r.x - bounds.center.x) * scale,
                     y: size.height / 2 + pan.height - (r.y - bounds.center.y) * scale)
    }
    func world(_ p: CGPoint) -> LayoutPoint {
        Self.rotated(.init(x: bounds.center.x + (p.x - size.width / 2 - pan.width) / scale,
                           y: bounds.center.y - (p.y - size.height / 2 - pan.height) / scale), by: -rotation)
    }
    func worldDelta(_ translation: CGSize) -> LayoutPoint {
        Self.rotated(.init(x: translation.width / scale, y: -translation.height / scale), by: -rotation)
    }
    static func fittedBounds(_ points: [LayoutPoint], rotation: Double) -> LayoutBounds {
        let b = LayoutBounds(points: points.map { rotated($0, by: rotation) })
        let margin = max(b.width, b.height) * 0.2
        return .init(min: b.min - .init(x: margin, y: margin), max: b.max + .init(x: margin, y: margin))
    }
    /// View-only alignment. Geometry, measured angles and layer offsets stay intact.
    static func horizontalBaseRotation(_ contour:[LayoutPoint]) -> Double {
        guard let edge = LayoutStrokeBeautifier.groundEdge(contour) else { return 0 }
        let vector = edge.b-edge.a
        return -atan2(vector.y,vector.x)
    }
    /// Camera-only detent: acquire within 2.5°, release after 5° to avoid flicker.
    static func snappedRotation(_ candidate: Double, contour: [LayoutPoint], latched: Double?) -> (angle: Double, latch: Double?) {
        if let latched, abs(candidate - latched) <= 5 * .pi / 180 { return (latched, latched) }
        let targets = LayoutGeometry.edges(contour).filter { ($0.b - $0.a).length > 1 }.map { edge in
            let d = edge.b - edge.a, direction = atan2(d.y, d.x)
            return ((candidate + direction) / (.pi / 2)).rounded() * (.pi / 2) - direction
        }
        if let target = targets.min(by: { abs($0-candidate) < abs($1-candidate) }), abs(target-candidate) <= 2.5 * .pi / 180 {
            return (target, target)
        }
        return (candidate, nil)
    }
}
func layoutPath(_ loop: [LayoutPoint], transform: LayoutViewport) -> Path {
    var path = Path()
    guard let first = loop.first else { return path }
    path.move(to: transform.screen(first))
    for p in loop.dropFirst() { path.addLine(to: transform.screen(p)) }
    path.closeSubpath(); return path
}

struct LayoutVisibilityIcon: View {
    enum Kind { case sheet, angle, framing, opening, electrical }
    let kind:Kind
    let state:LayoutVisibilityState
    var body:some View {
        Canvas { context,size in
            let drawingWidth = state == .dimensioned ? 56.0 : kind == .framing ? 43.0 : 40.0
            context.translateBy(x:(size.width-drawingWidth)/2,y:(size.height-40)/2)
            let hidden = state == .hidden
            let color = Color.primary.opacity(hidden ? 0.32 : 0.9)
            func line(_ points:[CGPoint],closed:Bool = false,fill:Bool = false) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to:first)
                for p in points.dropFirst() { path.addLine(to:p) }
                if closed { path.closeSubpath() }
                if fill && !hidden { context.fill(path,with:.color(.secondary.opacity(0.15))) }
                context.stroke(path,with:.color(color),style:.init(lineWidth:1.7,lineCap:.round,lineJoin:.round,dash:hidden ? [2,3] : []))
            }
            switch kind {
            case .sheet:
                line([.init(x:7,y:5),.init(x:31,y:5),.init(x:31,y:33),.init(x:7,y:33)],closed:true,fill:true)
                if !hidden { line([.init(x:10,y:9),.init(x:10,y:29)]) }
            case .angle:
                line([.init(x:10,y:5),.init(x:10,y:33),.init(x:36,y:33)])
                if !hidden {
                    var arc = Path(); arc.addArc(center:.init(x:10,y:33),radius:13,startAngle:.degrees(-90),endAngle:.degrees(0),clockwise:false)
                    context.stroke(arc,with:.color(color),lineWidth:1)
                    context.draw(Text("α").font(.system(size:15,weight:.medium)).foregroundStyle(color),at:.init(x:30,y:17))
                }
            case .framing:
                // Two extruded profiles: omega/furring and U-channel, seen obliquely.
                line([.init(x:2,y:30),.init(x:6,y:30),.init(x:6,y:20),.init(x:14,y:20),.init(x:14,y:30),.init(x:18,y:30)])
                line([.init(x:6,y:20),.init(x:12,y:7),.init(x:20,y:7),.init(x:14,y:20)],closed:true,fill:true)
                line([.init(x:14,y:30),.init(x:20,y:17),.init(x:20,y:7)])
                line([.init(x:23,y:23),.init(x:23,y:34),.init(x:35,y:34),.init(x:35,y:23)])
                line([.init(x:23,y:23),.init(x:29,y:10),.init(x:29,y:21),.init(x:23,y:34)],closed:true,fill:true)
                line([.init(x:35,y:34),.init(x:41,y:21),.init(x:41,y:10),.init(x:35,y:23)],closed:true,fill:true)
                line([.init(x:29,y:21),.init(x:41,y:21)])
            case .opening:
                line([.init(x:4,y:3),.init(x:36,y:3),.init(x:36,y:36),.init(x:4,y:36)],closed:true)
                line([.init(x:8,y:7),.init(x:32,y:7),.init(x:32,y:32),.init(x:8,y:32)],closed:true)
                line([.init(x:20,y:7),.init(x:20,y:32)])
                line([.init(x:8,y:19),.init(x:32,y:19)])
            case .electrical:
                line([.init(x:25,y:3),.init(x:8,y:22),.init(x:19,y:22),.init(x:14,y:37),.init(x:33,y:15),.init(x:22,y:15)],closed:true,fill:true)
            }
            if state == .dimensioned {
                context.translateBy(x:7,y:0)
                line([.init(x:45,y:5),.init(x:45,y:34)])
                line([.init(x:42,y:8),.init(x:45,y:5),.init(x:48,y:8)])
                line([.init(x:42,y:31),.init(x:45,y:34),.init(x:48,y:31)])
            }
        }.accessibilityHidden(true)
    }
}

private enum LayoutInteraction: String, CaseIterable {
    case openings = "Ouvertures", contour = "Contour", framing = "Ossatures", grid = "Plaques", lighting = "Électricité", move = "Vue"
    static var allCases: [Self] { [.move,.grid,.framing,.openings,.lighting] }
    var hint: String {
        switch self {
        case .openings: return "Touchez une ouverture pour la modifier, glissez-la pour la déplacer."
        case .contour: return "Glissez un sommet, ou touchez-le pour modifier ses cotes."
        case .grid: return "Touchez une plaque pour ses cotes. Glissez pour déplacer le calepinage."
        case .framing: return "Glissez pour décaler les fourrures. Le métrage est recalculé au relâchement."
        case .lighting: return "Touchez les spots à sélectionner, puis glissez-en un pour déplacer la sélection. Touchez le vide pour désélectionner."
        case .move: return "Glissez pour déplacer la vue. Pincez pour zoomer."
        }
    }
}
private enum LayoutEditorSheet: Identifiable {
    case newSurface, settings, furring, lighting, lightingSpacing(Set<Int>), export, opening(UUID?), vertex(Int), correction(Int), cut(LayoutCutSelection), pieces, furringDimensions
    var id: String {
        switch self {
        case .newSurface: return "new"
        case .settings: return "settings"
        case .furring: return "furring"
        case .lighting: return "lighting"
        case .lightingSpacing: return "lightingSpacing"
        case .export: return "export"
        case .opening(let id): return "opening-\(id?.uuidString ?? "new")"
        case .vertex(let i): return "vertex-\(i)"
        case .correction(let i): return "correction-\(i)"
        case .cut(let selection): return "cut-\(selection.id)"
        case .pieces: return "pieces"
        case .furringDimensions: return "furringDimensions"
        }
    }
}
private struct LayoutDragState {
    let document: LayoutDocument
    let viewport: LayoutViewport
    let vertex: Int?
    let opening: UUID?
    let initialPan: CGSize
    var spot: Int? = nil
    var spots: Set<Int> = []
}

/// Lightweight exact grid preview: contour and board joints only. No quantity
/// calculation when scrolling the library, and no lighting/framing annotations.
struct LayoutSavedThumbnail: View {
    let document:LayoutDocument
    var body:some View {
        Canvas { context,size in
            let surface = document.surface, bounds = surface.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = min((size.width-12)/bounds.width,(size.height-12)/bounds.height)
            func screen(_ p:LayoutPoint) -> CGPoint {
                .init(x:size.width/2+(p.x-bounds.center.x)*scale,y:size.height/2-(p.y-bounds.center.y)*scale)
            }
            func path(_ points:[LayoutPoint]) -> Path {
                var value = Path()
                guard let first = points.first else { return value }
                value.move(to:screen(first))
                for p in points.dropFirst() { value.addLine(to:screen(p)) }
                value.closeSubpath(); return value
            }
            var mask = path(surface.contour)
            for opening in surface.openings { mask.addPath(path(opening.contour)) }
            var boards = context
            boards.clip(to:mask,style:.init(eoFill:true))
            boards.fill(mask,with:.color(.teal.opacity(0.17)),style:.init(eoFill:true))
            if let layer = document.layers.first {
                let frame = LayoutGridFrame.make(surface:surface,layer:layer)
                let local = LayoutBounds(points:surface.contour.map(frame.local))
                func joints(step:Double,offset:Double,vertical:Bool) {
                    let low = vertical ? local.min.x : local.min.y, high = vertical ? local.max.x : local.max.y
                    guard step.isFinite, step > 0, offset.isFinite, (high-low)/step < 2000 else { return }
                    let remainder = offset.truncatingRemainder(dividingBy:step)
                    let first = ceil((low-remainder)/step), last = floor((high-remainder)/step)
                    guard first <= last else { return }
                    var lines = Path()
                    for index in Int(first)...Int(last) {
                        let v = remainder+Double(index)*step
                        let a = vertical ? LayoutPoint(x:v,y:local.min.y) : .init(x:local.min.x,y:v)
                        let b = vertical ? LayoutPoint(x:v,y:local.max.y) : .init(x:local.max.x,y:v)
                        lines.move(to:screen(frame.world(a))); lines.addLine(to:screen(frame.world(b)))
                    }
                    boards.stroke(lines,with:.color(.teal.opacity(0.8)),lineWidth:0.7)
                }
                joints(step:layer.cellWidth,offset:layer.offset.x,vertical:true)
                joints(step:layer.cellHeight,offset:layer.offset.y,vertical:false)
            }
            context.stroke(path(surface.contour),with:.color(.primary.opacity(0.8)),lineWidth:1.3)
        }.background(Color(.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:10)).accessibilityHidden(true)
    }
}

struct SheetLayoutView: View {
    var initialDocument: LayoutDocument? = nil
    var onSaveDocument: ((LayoutDocument) throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var loadedInitial = false
    @StateObject private var model = LayoutEditorModel()
    @EnvironmentObject private var catalogue: ToolTechnicalStore
    @State private var mode = LayoutInteraction.move
    @State private var sheet: LayoutEditorSheet?
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var rotation = 0.0
    @State private var rotationStart: Double?
    @State private var rotationLatch: Double?
    @State private var fittedBounds: LayoutBounds?
    @State private var lightingRotationOriginal: LayoutDocument?
    @State private var rotatingSpots: Set<Int> = []
    @State private var addingSpot = false
    @State private var addingKind = LayoutElectricalKind.light
    @GestureState private var magnification = 1.0
    @State private var drag: LayoutDragState?
    @State private var selectedVertex: Int?
    @State private var polygonSelection: LayoutPolygonSelection?
    @State private var editingShape = false
    @State private var visibility = LayoutVisibilitySettings()
    @State private var dimensionEdge = 0
    @State private var pinching = false
    @State private var selectedSpots: Set<Int> = []
    @State private var referenceSpot: Int?
    @State private var spotGuides: [LayoutPoint] = []
    @State private var spotEditError: String?
    @State private var renamingSaved: SavedLayoutDocument?
    @State private var savedName = ""
    @State private var deletingSaved: SavedLayoutDocument?
    @AppStorage("layout.snapSpots") private var snapSpots = true

    var body: some View {
        Group {
            if let document = model.document { editor(document) }
            else { entry }
        }
        .navigationTitle("Calepinage 2D").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.document != nil && onSaveDocument == nil)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if model.document != nil {
                if onSaveDocument == nil {
                    ToolbarItem(placement:.topBarLeading) {
                        Button { model.saveCurrentAndClose() } label: { Image(systemName:"chevron.left") }
                            .accessibilityLabel("Retour aux calepinages sauvegardés")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Enregistrer") {
                        if let onSaveDocument, let document = model.document {
                            do { try onSaveDocument(document); dismiss() } catch { return }
                        } else { model.saveCurrentAndClose(); selectedVertex = nil }
                    }
                    Menu {
                        if onSaveDocument == nil {
                            Button("Retour aux calepinages", systemImage: "list.bullet") { model.saveCurrentAndClose(); selectedVertex = nil }
                            Button("Nouveau support", systemImage: "plus") { sheet = .newSurface }
                        }
                        Button("Liste des découpes", systemImage: "list.number") { sheet = .pieces }.disabled(model.result == nil)
                        Button("Exporter vers un ouvrage",systemImage:"square.and.arrow.up") { sheet = .export }
                        Button("Modifier le contour et l’échelle",systemImage:"pencil.and.outline") { editingShape = true }
                        Divider()
                        Button { model.undo(); selectedVertex = nil } label: { Label("Annuler la modification", systemImage: "arrow.uturn.backward") }.disabled(!model.canUndo)
                        Button { model.redo(); selectedVertex = nil } label: { Label("Rétablir la modification", systemImage: "arrow.uturn.forward") }.disabled(!model.canRedo)
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Options du calepinage")
                }
            }
        }
        .sheet(item: $sheet) { destination in sheetContent(destination) }
        .alert("Renommer le calepinage",isPresented:Binding(get:{renamingSaved != nil},set:{if !$0 { renamingSaved = nil }})) {
            TextField("Nom du calepinage",text:$savedName)
            Button("Annuler",role:.cancel) { renamingSaved = nil }
            Button("Renommer") {
                if let saved = renamingSaved { model.rename(saved,to:savedName) }
                renamingSaved = nil
            }.disabled(savedName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }
        .alert("Supprimer ce calepinage ?",isPresented:Binding(get:{deletingSaved != nil},set:{if !$0 { deletingSaved = nil }})) {
            Button("Annuler",role:.cancel) { deletingSaved = nil }
            Button("Supprimer",role:.destructive) {
                if let saved = deletingSaved { model.delete(saved) }
                deletingSaved = nil
            }
        } message: { Text("« \(deletingSaved?.title ?? "") » sera supprimé de vos calepinages sauvegardés. Cette action ne peut pas être annulée.") }
        .onChange(of:model.document?.lighting?.count) { _,_ in selectedSpots = []; referenceSpot = nil }
        .onChange(of:model.document?.surface.id) { _,_ in
            selectedSpots = []; referenceSpot = nil
            mode = .move; visibility = LayoutVisibilitySettings()
            rotation = 0; rotationStart = nil; rotationLatch = nil; fittedBounds = nil; zoom = 1; pan = .zero
        }
        .onChange(of:mode) { _,_ in spotGuides = []; spotEditError = nil; addingSpot = false }
        .onAppear { if !loadedInitial, let initialDocument { model.apply(initialDocument); loadedInitial = true } }
        .fullScreenCover(isPresented:$editingShape) {
            if let document = model.document {
                LayoutManualContourEditor(surface:document.surface,kind:document.surface.kind,title:"Modifier le contour et l’échelle") { surface in
                    var copy = document; copy.surface = surface
                    if surface.contour.count != document.surface.contour.count || surface.id != document.surface.id {
                        for i in copy.layers.indices { copy.layers[i].referenceEdge = nil }
                    }
                    model.apply(copy)
                }
            }
        }
        .sheet(item:$polygonSelection) { selection in
            if let document = model.document {
                if case .correction(let i) = selection, let correction = document.surface.dimensionCorrections.first(where:{$0.edgeIndex == i}) {
                    LayoutCorrectionDetail(correction:correction, edgeCount:document.surface.contour.count)
                } else {
                    LayoutConstraintForm(selection:selection, surface:document.surface) { surface in
                        var copy = document; copy.surface = surface; model.apply(copy)
                    }
                }
            }
        }
    }

    private var entry: some View {
        List {
            Section("Calepinages sauvegardés") {
                if model.savedDocuments.isEmpty {
                    ContentUnavailableView("Aucun calepinage", systemImage: "square.grid.3x3",
                                           description: Text("Créez votre premier mur ou plafond."))
                } else {
                    ForEach(model.savedDocuments) { saved in
                        Button { model.open(saved) } label: {
                            HStack(spacing: 12) {
                                LayoutSavedThumbnail(document:saved.document).frame(width:82,height:72)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(saved.title).font(.headline).foregroundStyle(.primary)
                                    Text("\(saved.document.surface.kind.rawValue) · \(layoutArea(abs(LayoutGeometry.area(saved.document.surface.contour))))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("Créé le \(saved.createdAt.formatted(.dateTime.day().month().year().locale(Locale(identifier:"fr_FR"))))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                        .swipeActions(edge:.trailing,allowsFullSwipe:false) {
                            Button { deletingSaved = saved } label: { Label("Supprimer",systemImage:"trash") }.tint(.red)
                            Button { savedName = saved.title; renamingSaved = saved } label: { Label("Renommer",systemImage:"pencil") }.tint(.blue)
                        }
                    }
                }
            }
            Section {
                Button { sheet = .newSurface } label: { Label("Nouveau calepinage", systemImage: "plus") }
                Button {} label: { Label("Importer un ouvrage depuis Projets (à venir)", systemImage: "square.and.arrow.down") }.disabled(true)
            }
            if let error = model.saveError { Section { Text(error).font(.footnote).foregroundStyle(.orange) } }
        }
    }

    private func visibilityButton(_ kind:LayoutVisibilityIcon.Kind,title:String,state:Binding<LayoutVisibilityState>) -> some View {
        Button { state.wrappedValue = state.wrappedValue.next } label: {
            LayoutVisibilityIcon(kind:kind,state:state.wrappedValue).frame(height:42).frame(maxWidth:.infinity)
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(state.wrappedValue == .hidden ? "Masqués" : state.wrappedValue == .dimensioned ? "Visibles avec cotes" : "Visibles sans cotes")
            .accessibilityHint("Toucher pour changer l’affichage")
    }

    private func editor(_ document: LayoutDocument) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.surface.name).font(.headline).lineLimit(1)
                    Text("\(document.surface.kind.rawValue) · \(layoutCM(document.surface.bounds.width)) × \(layoutCM(document.surface.bounds.height))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isCalculating { ProgressView().accessibilityLabel("Calcul des découpes") }
                else if let result = model.result {
                    VStack(alignment: .trailing) {
                        if mode == .lighting {
                            Text("\(document.lighting?.positions.count ?? 0) \(document.surface.kind == .wall ? "points" : "spots")").font(.headline)
                            Text("\(selectedSpots.count) sélectionné(s)").font(.caption).foregroundStyle(.secondary)
                        } else if mode == .framing {
                            Text("\((result.furring.lines.reduce(0){$0+($1.end-$1.start).length}/1000).formatted(.number.precision(.fractionLength(2)))) ml").font(.headline)
                            Text("\(document.surface.kind == .wall ? "Ossature" : "Fourrures") · \(result.furring.lines.count) tronçons").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(result.sheets.count) plaques").font(.headline)
                            Text(layoutArea(result.netArea)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.horizontal)
            HStack(spacing:2) {
                ForEach(LayoutInteraction.allCases,id:\.self) { item in
                    Button { mode = item } label: {
                        Text(item == .lighting && document.surface.kind == .wall ? "Électricité" : item.rawValue).font(.system(size:12,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(minWidth:0,maxWidth:.infinity).frame(height:34)
                            .background(mode == item ? Color(.systemBackground) : .clear,in:Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(mode == item ? .isSelected : [])
                }
            }.padding(3).background(Color(.tertiarySystemFill),in:Capsule()).padding(.horizontal)
            HStack(spacing:2) {
                Button { visibility.angles.toggle() } label: {
                    LayoutVisibilityIcon(kind:.angle,state:visibility.angles ? .visible : .hidden)
                        .frame(height:42).frame(maxWidth:.infinity)
                }.buttonStyle(.plain).accessibilityLabel("Angles")
                    .accessibilityValue(visibility.angles ? "Visibles" : "Masqués")
                visibilityButton(.sheet,title:"Plaques",state:$visibility.sheets)
                visibilityButton(.framing,title:"Ossatures",state:$visibility.framing)
                visibilityButton(.opening,title:"Ouvertures",state:$visibility.openings)
                visibilityButton(.electrical,title:"Électricité",state:$visibility.electrical)
            }.padding(3).padding(.horizontal).disabled(drag != nil)
            GeometryReader { proxy in
                let bounds = drag?.document.surface.bounds ?? document.surface.bounds
                let viewport = LayoutViewport(bounds:fittedBounds ?? LayoutViewport.fittedBounds(bounds.polygon, rotation:0), size: proxy.size, zoom: zoom * magnification, pan: pan, rotation:rotation)
                Canvas { context, size in draw(context: &context, size: size, document: document, viewport: viewport) }
                    .background(Color(.secondarySystemGroupedBackground))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 7).onChanged { value in dragChanged(value, document: document, viewport: viewport) }.onEnded { _ in
                        if let drag { model.finishGesture(from: drag.document) }; drag = nil; spotGuides = []
                    })
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in tapped(value.location, document: document, viewport: viewport) })
                    .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in if mode != .lighting { state = value.magnification } }
                        .onChanged { _ in
                            if !pinching {
                                pinching = true
                                if let original = drag { model.cancelGesture(restoring:original.document); pan = original.initialPan; drag = nil; spotGuides = [] }
                            }
                        }.onEnded { value in if mode != .lighting { zoom = min(8, max(0.4, zoom * value.magnification)) }; pinching = false })
                    .simultaneousGesture(RotationGesture().onChanged { angle in
                        if mode == .lighting {
                            guard visibility.electrical.isVisible else { return }
                            if lightingRotationOriginal == nil {
                                if let original = drag { model.cancelGesture(restoring:original.document); pan = original.initialPan; drag = nil }
                                lightingRotationOriginal = model.document
                                rotatingSpots = selectedSpots.isEmpty ? Set(model.document?.lighting?.positions.indices.map { $0 } ?? []) : selectedSpots
                            }
                            guard var copy = lightingRotationOriginal, let light = copy.lighting else { return }
                            let snap = snapSpots ? LayoutPlanning.snappedLightingRotation(-angle.radians,lighting:light,selected:rotatingSpots,contour:copy.surface.contour,latched:rotationLatch) : (angle:-angle.radians,latch:nil)
                            if snap.latch != nil && rotationLatch == nil { UISelectionFeedbackGenerator().selectionChanged() }
                            rotationLatch = snap.latch
                            copy.lighting = LayoutPlanning.rotatedLighting(light,selected:rotatingSpots,angle:snap.angle)
                            model.preview(copy)
                            return
                        }
                        guard document.surface.kind == .ceiling else { return }
                        if rotationStart == nil {
                            rotationStart = rotation
                            // Keep the origin and camera framing fixed throughout the rotation.
                            fittedBounds = viewport.bounds
                            if let original = drag { model.cancelGesture(restoring:original.document); pan = original.initialPan; drag = nil; spotGuides = [] }
                        }
                        let snap = LayoutViewport.snappedRotation((rotationStart ?? rotation) - angle.radians, contour:document.surface.contour, latched:rotationLatch)
                        if snap.latch != nil && rotationLatch == nil { UISelectionFeedbackGenerator().selectionChanged() }
                        rotation = snap.angle; rotationLatch = snap.latch
                    }.onEnded { _ in
                        if let original = lightingRotationOriginal { model.finishGesture(from:original) }
                        lightingRotationOriginal = nil; rotatingSpots = []; rotationStart = nil; rotationLatch = nil
                    })
                    .overlay { LayoutPolygonAnnotations(surface:document.surface, viewport:viewport, showAngles:visibility.angles, showDimensions:false) { polygonSelection = $0 }.allowsHitTesting(false) }
                    .overlay(alignment: .topTrailing) {
                        Button { fittedBounds = LayoutViewport.fittedBounds(document.surface.contour, rotation:rotation); zoom = 1; pan = .zero } label: { Image(systemName: "scope").padding(12).background(.regularMaterial, in: Circle()) }
                            .padding(8).accessibilityLabel("Recentrer le plan")
                    }
                    .overlay(alignment: .bottomLeading) {
                        Button {
                            rotation = LayoutViewport.horizontalBaseRotation(document.surface.contour)
                            rotationStart = nil; rotationLatch = nil
                            fittedBounds = LayoutViewport.fittedBounds(document.surface.contour,rotation:rotation)
                            zoom = 1; pan = .zero
                        } label: { Image(systemName:"arrow.down.to.line").padding(12).background(.regularMaterial,in:Circle()) }
                            .padding(8).accessibilityLabel("Aligner le bas sur l’axe horizontal")
                            .disabled(drag != nil || pinching || lightingRotationOriginal != nil)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }.padding(.horizontal)
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
            } else {
                Text(addingSpot ? "Touchez le plan pour ajouter un spot. Répétez pour en placer plusieurs, puis touchez Terminer." : mode.hint).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            }
            if let saveError = model.saveError { Text(saveError).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if mode == .lighting { lightingControls(document) }
            if let warning = model.lightingWarning {
                Button { sheet = .lighting } label: { Label(warning,systemImage:"exclamationmark.triangle") }
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal)
            }
            if mode == .grid || mode == .framing {
                HStack {
                    Button { model.optimize(furring:mode == .framing) } label: {
                        Label(model.isOptimizing ? "Optimisation…" : "Optimiser",systemImage:"sparkles")
                    }.disabled(model.isOptimizing || model.isCalculating || drag != nil || (mode == .framing && document.layers.first?.furring == nil))
                    if let layer = document.layers.first, layer.furring != nil {
                        Button(mode == .framing ? "Caler sur les plaques" : "Caler sur les fourrures") {
                            var copy = document
                            copy.layers[0] = mode == .framing ? LayoutPlanning.alignFurring(to:layer) : LayoutPlanning.alignBoards(to:layer)
                            model.apply(copy)
                        }.disabled(!LayoutPlanning.compatibleSpacings(layer).contains(layer.furring?.spacing ?? 0))
                    }
                }.font(.caption).buttonStyle(.bordered).padding(.horizontal)
                if let message = model.optimizationMessage { Text(message).font(.caption2).foregroundStyle(.secondary).padding(.horizontal) }
                if let layer = document.layers.first, layer.furring != nil, !LayoutPlanning.aligned(layer) {
                    Label("Joints et fourrures décalés : utilisez « Caler ».",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            if mode == .contour, let index = selectedVertex, document.surface.contour.indices.contains(index) {
                Button("Modifier le sommet \(index + 1) · ajouter / supprimer") { sheet = .vertex(index) }.font(.subheadline)
            }
            if mode == .grid, let layer = document.layers.first {
                Text("Décalage X : \(layoutCM(layer.offset.x)) · Y : \(layoutCM(layer.offset.y))").font(.caption.monospacedDigit())
            }
            HStack(spacing: 8) {
                bottomButton("Plaques",symbol:"rectangle.portrait",destination:.settings)
                bottomButton(document.surface.kind == .wall ? "Ossature" : "Fourrures",symbol:"line.3.horizontal",destination:.furring)
                bottomButton("Ouvertures",symbol:"plus.rectangle",destination:.opening(nil))
                bottomButton(document.surface.kind == .wall ? "Électricité" : "Éclairage",symbol:"lightbulb",destination:.lighting)
            }.tint(.teal).padding(.horizontal).padding(.bottom, 8)
        }.padding(.top, 8)
    }

    private func bottomButton(_ title:String,symbol:String,destination:LayoutEditorSheet) -> some View {
        Button { sheet = destination } label: {
            VStack(spacing:5) {
                Image(systemName:symbol).font(.title3).frame(height:23)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.75)
            }.frame(minWidth:0,maxWidth:.infinity).frame(height:64)
                .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).frame(minWidth:0,maxWidth:.infinity)
    }

    @ViewBuilder private func lightingControls(_ document:LayoutDocument) -> some View {
        if let lighting = document.lighting {
            HStack {
                Button(selectedSpots.count == lighting.count ? "Désélectionner" : "Tout sélectionner") {
                    selectedSpots = selectedSpots.count == lighting.count ? [] : Set(lighting.positions.indices)
                    referenceSpot = selectedSpots.sorted().last
                }
                Menu {
                    Button(document.surface.kind == .wall ? "Centrer tous les points horizontalement" : "Centrer tous les spots") { centerSpots(document,selected:Set(lighting.positions.indices)) }
                    Button(document.surface.kind == .wall ? "Centrer la sélection horizontalement" : "Centrer la sélection") { centerSpots(document,selected:selectedSpots) }.disabled(selectedSpots.isEmpty)
                    Button("Rapprocher / écarter…") { sheet = .lightingSpacing(selectedSpots.isEmpty ? Set(lighting.positions.indices) : selectedSpots) }
                        .disabled((selectedSpots.isEmpty ? lighting.count : selectedSpots.count) < 2)
                    if document.surface.kind == .wall {
                        Button("Ajouter une prise sur le plan") { addingKind = .socket; addingSpot = true }
                        Button("Ajouter une lumière sur le plan") { addingKind = .light; addingSpot = true }
                        Button("Ajouter une rangée à une hauteur…") { sheet = .lighting }
                    } else { Button(addingSpot ? "Terminer l’ajout" : "Ajouter un spot sur le plan",systemImage:"plus.circle") { addingKind = .light; addingSpot.toggle() } }
                    if !selectedSpots.isEmpty {
                        Button("Supprimer la sélection",role:.destructive) {
                            var copy = document, value = lighting
                            value.kinds = lighting.positions.indices.filter { !selectedSpots.contains($0) }.map { lighting.kind(at:$0) }
                            value.positions = lighting.positions.enumerated().filter { !selectedSpots.contains($0.offset) }.map(\.element)
                            value.count = value.positions.count; copy.lighting = value.count == 0 ? nil : value
                            model.apply(copy); selectedSpots = []; referenceSpot = nil
                        }
                    }
                    Divider()
                    Toggle("Aimantation des positions et rotations",isOn:$snapSpots)
                    if let referenceSpot { Text("Alignement sur S\(referenceSpot+1), dernier spot sélectionné") }
                    ForEach(LayoutSpotArrangement.allCases,id:\.self) { action in
                        Button(action.rawValue) {
                            do {
                                var copy = document
                                copy.lighting = try LayoutPlanning.arrangedLighting(lighting,selected:selectedSpots,reference:referenceSpot,action:action,surface:document.surface)
                                model.apply(copy); spotEditError = nil
                            } catch { spotEditError = error.localizedDescription }
                        }.disabled(selectedSpots.count < action.minimumCount)
                    }
                } label: { Label("Organiser",systemImage:"slider.horizontal.3") }
                Toggle(isOn:$snapSpots) { Image(systemName:"scope") }.toggleStyle(.button).accessibilityLabel("Repères et aimantation des spots")
            }.font(.caption).buttonStyle(.bordered).padding(.horizontal)
            if addingSpot { Button("Terminer l’ajout") { addingSpot = false }.font(.caption) }
            if let spotEditError { Text(spotEditError).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
        } else {
            HStack {
                Button(document.surface.kind == .wall ? "Ajouter des rangées" : "Répartition automatique") { sheet = .lighting }
                if document.surface.kind == .wall {
                    Menu("À la main") {
                        Button("Prise") { addingKind = .socket; addingSpot = true }
                        Button("Lumière") { addingKind = .light; addingSpot = true }
                    }
                } else { Button(addingSpot ? "Terminer" : "Ajouter à la main") { addingKind = .light; addingSpot.toggle() } }
            }.buttonStyle(.bordered).font(.caption)
            if let spotEditError { Text(spotEditError).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func centerSpots(_ document:LayoutDocument,selected:Set<Int>) {
        guard let lighting = document.lighting else { return }
        do {
            var copy = document
            copy.lighting = try LayoutPlanning.centeredLighting(lighting,selected:selected,surface:document.surface)
            model.apply(copy); spotEditError = nil
        } catch { spotEditError = error.localizedDescription }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, document: LayoutDocument, viewport: LayoutViewport) {
        let surface = document.surface
        let origin = viewport.screen(.zero)
        var axes = Path()
        axes.move(to: .init(x: 0, y: origin.y)); axes.addLine(to: .init(x: size.width, y: origin.y))
        axes.move(to: .init(x: origin.x, y: 0)); axes.addLine(to: .init(x: origin.x, y: size.height))
        context.stroke(axes, with: .color(.secondary.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        if let result = model.result {
            if drag != nil && mode != .lighting {
                drawLiveGrids(context:&context,document:document,viewport:viewport)
            } else {
            for placement in result.sheets where visibility.sheets.isVisible {
                for (index, piece) in placement.pieces.enumerated() {
                    var path = layoutPath(piece.contour.map(result.frame.world), transform: viewport)
                    for hole in piece.holes { path.addPath(layoutPath(hole.map(result.frame.world), transform: viewport)) }
                    let color = placement.isFull ? Color.teal : Color.blue
                    context.fill(path, with: .color(color.opacity(placement.number % 2 == 0 ? 0.22 : 0.12)), style: FillStyle(eoFill: true))
                    context.stroke(path, with: .color(color.opacity(0.75)), lineWidth: 1)
                    if visibility.sheets.showsDimensions {
                        for edge in LayoutGeometry.edges(piece.contour) {
                            drawAlongDimension(context:&context,a:result.frame.world(edge.a),b:result.frame.world(edge.b),viewport:viewport,color:color,offset:9)
                        }
                    }
                    if piece.bounds.width * viewport.scale > 20 && piece.bounds.height * viewport.scale > 20 {
                        let label = placement.pieces.count > 1 ? "\(placement.number).\(index + 1)" : "\(placement.number)"
                        context.draw(Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary), at: viewport.screen(result.frame.world(piece.labelPoint)))
                    }
                }
            }
            }
            if visibility.framing.isVisible && (drag == nil || mode == .lighting) {
                for line in result.furring.lines {
                    var path = Path()
                    path.move(to:viewport.screen(result.frame.world(line.start)))
                    path.addLine(to:viewport.screen(result.frame.world(line.end)))
                    context.stroke(path,with:.color(.purple),style:StrokeStyle(lineWidth:1.5,dash:[6,3]))
                    if visibility.framing.showsDimensions {
                        drawAlongDimension(context:&context,a:result.frame.world(line.start),b:result.frame.world(line.end),viewport:viewport,color:.purple,offset:7)
                    }
                }
            }
        }
        context.stroke(layoutPath(surface.contour, transform: viewport), with: .color(.primary), lineWidth: 2)
        for opening in surface.openings where visibility.openings.isVisible {
            let p = layoutPath(opening.contour, transform: viewport)
            context.stroke(p, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            context.draw(Text(opening.kind.rawValue).font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange), at: viewport.screen(opening.bounds.center))
            if visibility.openings.showsDimensions || drag?.opening == opening.id {
                drawWallDimensions(context:&context,points:opening.contour,surface:surface,viewport:viewport,color:.orange)
            }
        }
        if let lighting = document.lighting, visibility.electrical.isVisible {
            for (i,p) in lighting.positions.enumerated() {
                let s = viewport.screen(p), radius = max(4,lighting.diameter/2*viewport.scale)
                context.fill(Path(ellipseIn:.init(x:s.x-radius,y:s.y-radius,width:2*radius,height:2*radius)),with:.color(.yellow))
                context.stroke(Path(ellipseIn:.init(x:s.x-radius,y:s.y-radius,width:2*radius,height:2*radius)),with:.color(.orange),lineWidth:1)
                if mode == .lighting && selectedSpots.contains(i) {
                    context.stroke(Path(ellipseIn:.init(x:s.x-13,y:s.y-13,width:26,height:26)),with:.color(i == referenceSpot ? .blue : .orange),lineWidth:2)
                }
                context.draw(Text(lighting.label(at:i,wall:document.surface.kind == .wall)).font(.system(size:10,weight:.bold)).foregroundStyle(lighting.kind(at:i) == .socket ? Color.blue : .orange),at:.init(x:s.x,y:s.y-radius-8))
                if visibility.electrical.showsDimensions { drawWallDimensions(context:&context,points:[p],surface:surface,viewport:viewport,color:.orange) }
            }
            if mode == .lighting, let anchor = drag?.spot, lighting.positions.indices.contains(anchor) {
                let p = viewport.screen(lighting.positions[anchor])
                for guide in spotGuides {
                    var path = Path(); path.move(to:p); path.addLine(to:viewport.screen(guide))
                    context.stroke(path,with:.color(.orange),style:.init(lineWidth:1,dash:[4,3]))
                }
            }
        }
        for i in surface.contour.indices {
            let a = surface.contour[i]
            if mode == .contour {
                let p = viewport.screen(a), radius = selectedVertex == i ? 8.0 : 6.0
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(selectedVertex == i ? .orange : .teal))
                context.draw(Text(vertexName(i)).font(.caption.bold()), at: .init(x: p.x + 12, y: p.y - 12))
            }
        }
    }

    private func drawLiveGrids(context:inout GraphicsContext,document:LayoutDocument,viewport:LayoutViewport) {
        guard let layer = document.layers.first else { return }
        let frame = LayoutGridFrame.make(surface:document.surface,layer:layer)
        let bounds = LayoutPlanning.localSurface(document.surface,frame:frame).bounds
        var clipped = context
        var clip = layoutPath(document.surface.contour,transform:viewport)
        for o in document.surface.openings { clip.addPath(layoutPath(o.contour,transform:viewport)) }
        clipped.clip(to:clip,style:.init(eoFill:true))
        if visibility.sheets.isVisible { clipped.fill(clip,with:.color(.teal.opacity(0.12)),style:.init(eoFill:true)) }
        func grid(step:Double,offset:Double,vertical:Bool,color:Color) {
            guard step >= 1 else { return }
            let low = vertical ? bounds.min.x : bounds.min.y, high = vertical ? bounds.max.x : bounds.max.y
            let start = Int(floor((low-offset)/step)), end = Int(ceil((high-offset)/step))
            guard end-start <= 2000 else { return }
            for n in start...end {
                let position = offset+Double(n)*step
                let a = vertical ? LayoutPoint(x:position,y:bounds.min.y) : LayoutPoint(x:bounds.min.x,y:position)
                let z = vertical ? LayoutPoint(x:position,y:bounds.max.y) : LayoutPoint(x:bounds.max.x,y:position)
                var path = Path(); path.move(to:viewport.screen(frame.world(a))); path.addLine(to:viewport.screen(frame.world(z)))
                clipped.stroke(path,with:.color(color),lineWidth:color == .purple ? 1.5 : 0.8)
            }
        }
        if visibility.sheets.isVisible {
            grid(step:layer.cellWidth,offset:layer.offset.x,vertical:true,color:.teal)
            grid(step:layer.cellHeight,offset:layer.offset.y,vertical:false,color:.teal)
        }
        if let f = layer.furring, visibility.framing.isVisible {
            grid(step:f.spacing,offset:f.offset,vertical:!LayoutPlanning.alongX(layer),color:.purple)
        }
    }

    private func drawAlongDimension(context:inout GraphicsContext,a:LayoutPoint,b:LayoutPoint,viewport:LayoutViewport,color:Color,offset:Double) {
        let p = viewport.screen(a), q = viewport.screen(b)
        guard hypot(q.x-p.x,q.y-p.y) > 28 else { return }
        var angle = atan2(q.y-p.y,q.x-p.x)
        if angle > .pi/2 { angle -= .pi }; if angle < -.pi/2 { angle += .pi }
        var label = context
        label.translateBy(x:(p.x+q.x)/2+sin(angle)*offset,y:(p.y+q.y)/2-cos(angle)*offset)
        label.rotate(by:.radians(angle))
        let text = Text(layoutCM((b-a).length)).font(.system(size:10,weight:.semibold)).foregroundStyle(color)
        let resolved = label.resolve(text), size = resolved.measure(in:CGSize(width:150,height:18))
        label.fill(Path(roundedRect:CGRect(x:-size.width/2-3,y:-size.height/2-1,width:size.width+6,height:size.height+2),cornerRadius:3),with:.color(Color(.secondarySystemGroupedBackground).opacity(0.9)))
        label.draw(resolved,at:.zero)
    }

    private func drawWallDimensions(context:inout GraphicsContext,points:[LayoutPoint],surface:Surface2D,viewport:LayoutViewport,color:Color) {
        var occupied: [CGRect] = []
        for dimension in LayoutPlanning.wallDimensions(points:points,surface:surface) {
            let a = viewport.screen(dimension.start), b = viewport.screen(dimension.end)
            var path = Path(); path.move(to:a); path.addLine(to:b)
            for p in [a,b] { path.move(to:.init(x:p.x-3,y:p.y+3)); path.addLine(to:.init(x:p.x+3,y:p.y-3)) }
            context.stroke(path,with:.color(color.opacity(0.8)),style:.init(lineWidth:0.8,dash:[3,3]))
            var label = CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2-8)
            for _ in 0..<6 {
                let box = CGRect(x:label.x-28,y:label.y-8,width:56,height:16)
                if !occupied.contains(where:{$0.intersects(box)}) { occupied.append(box); break }
                label.y += 16
            }
            context.draw(Text(layoutCM(dimension.distance)).font(.system(size:10,weight:.semibold)).foregroundStyle(color),at:label)
        }
    }

    private func drawFurringDimensions(context: inout GraphicsContext, surface:Surface2D, result:SheetLayoutResult, viewport:LayoutViewport) {
        guard surface.contour.indices.contains(dimensionEdge) else { return }
        let a = surface.contour[dimensionEdge], z = surface.contour[(dimensionEdge+1)%surface.contour.count]
        let winding = LayoutGeometry.area(surface.contour) >= 0 ? 1.0 : -1.0
        let start = viewport.screen(a), end = viewport.screen(z)
        let screenLength = hypot(end.x-start.x,end.y-start.y)
        let normal = CGSize(width:-winding*(end.y-start.y)/max(1,screenLength)*32,height:winding*(end.x-start.x)/max(1,screenLength)*32)
        func outward(_ p:CGPoint) -> CGPoint { .init(x:p.x+normal.width,y:p.y+normal.height) }
        var rail = Path(); rail.move(to:outward(start)); rail.addLine(to:outward(end))
        for contact in result.furring.contacts.filter({$0.edgeIndex == dimensionEdge}) {
            let p = viewport.screen(result.frame.world(contact.point)), label = outward(p)
            rail.move(to:p); rail.addLine(to:label)
            rail.move(to:.init(x:label.x-3,y:label.y+3)); rail.addLine(to:.init(x:label.x+3,y:label.y-3))
            context.draw(Text(layoutCM(contact.distance)).font(.system(size:10,weight:.semibold)).foregroundStyle(.purple),
                         at:.init(x:label.x+normal.width*0.45,y:label.y+normal.height*0.45))
        }
        context.stroke(rail,with:.color(.purple.opacity(0.8)),lineWidth:0.7)
    }

    private func nearestVertex(_ p: CGPoint, document: LayoutDocument, viewport: LayoutViewport) -> Int? {
        document.surface.contour.indices.min { a, b in
            let pa = viewport.screen(document.surface.contour[a]), pb = viewport.screen(document.surface.contour[b])
            return hypot(pa.x - p.x, pa.y - p.y) < hypot(pb.x - p.x, pb.y - p.y)
        }.flatMap { i in
            let point = viewport.screen(document.surface.contour[i])
            return hypot(point.x - p.x, point.y - p.y) < 28 ? i : nil
        }
    }
    private func tapped(_ p: CGPoint, document: LayoutDocument, viewport: LayoutViewport) {
        if mode == .lighting && addingSpot && visibility.electrical.isVisible {
            do {
                var copy = document
                copy.lighting = try LayoutPlanning.addingSpot(to:document.lighting,at:viewport.world(p),surface:document.surface,kind:addingKind)
                model.apply(copy); spotEditError = nil
            } catch { spotEditError = error.localizedDescription }
            return
        }
        if mode == .lighting {
            guard visibility.electrical.isVisible else { return }
            if let i = nearestSpot(p,document:document,viewport:viewport) {
                if selectedSpots.contains(i) { selectedSpots.remove(i); referenceSpot = selectedSpots.sorted().last }
                else { selectedSpots.insert(i); referenceSpot = i }
            } else { selectedSpots = []; referenceSpot = nil }
            spotEditError = nil
            return
        }
        if mode == .contour {
            selectedVertex = nearestVertex(p, document: document, viewport: viewport)
            if let selectedVertex { sheet = .vertex(selectedVertex) }
            return
        }
        guard mode == .grid || mode == .openings else { return }
        let point = viewport.world(p)
        if mode == .openings, visibility.openings.isVisible {
            if let opening = document.surface.openings.last(where: { LayoutGeometry.contains(point, in:$0.contour) }) { sheet = .opening(opening.id) }
            return
        }
        guard mode == .grid, visibility.sheets.isVisible else { return }
        guard !model.isCalculating, let result = model.result else { return }
        for placement in result.sheets {
            if let piece = placement.pieces.first(where: { $0.contains(result.frame.local(point)) }) {
                sheet = .cut(.make(sheet:placement,piece:piece,lighting:document.lighting,frame:result.frame,wall:document.surface.kind == .wall)); return
            }
        }
    }
    private func dragChanged(_ value: DragGesture.Value, document: LayoutDocument, viewport: LayoutViewport) {
        guard !pinching, rotationStart == nil, lightingRotationOriginal == nil, !model.isOptimizing else { return }
        if drag == nil {
            let vertex = mode == .contour ? nearestVertex(value.startLocation, document: document, viewport: viewport) : nil
            let p = viewport.world(value.startLocation)
            let opening = mode == .openings && visibility.openings.isVisible ? document.surface.openings.last(where: { LayoutGeometry.contains(p, in: $0.contour) })?.id : nil
            drag = .init(document: document, viewport: viewport, vertex: vertex, opening: opening, initialPan: pan)
            if mode == .lighting, visibility.electrical.isVisible, let i = nearestSpot(value.startLocation,document:document,viewport:viewport) {
                if !selectedSpots.contains(i) { selectedSpots = [i] }
                referenceSpot = i; drag?.spot = i; drag?.spots = selectedSpots; spotEditError = nil
            }
            if let vertex { selectedVertex = vertex }
        }
        guard let drag else { return }
        var updated = drag.document
        let delta = drag.viewport.worldDelta(value.translation)
        if mode == .lighting, let i = drag.spot, let lighting = drag.document.lighting {
            let snapped = snapSpots ? LayoutPlanning.snappedLightingDelta(lighting,selected:drag.spots,anchor:i,delta:delta,tolerance:8/drag.viewport.scale) : (delta:delta,guides:[])
            spotGuides = snapped.guides
            updated.lighting = LayoutPlanning.translatedLighting(lighting,indices:drag.spots,delta:snapped.delta)
        } else if mode == .grid && visibility.sheets.isVisible {
            let frame = LayoutGridFrame.make(surface:drag.document.surface,layer:drag.document.layers[0])
            updated.layers[0].offset = drag.document.layers[0].offset + frame.vector(delta)
            updated.layers[0] = updated.layers[0].forSurface(updated.surface)
        } else if mode == .framing && visibility.framing.isVisible {
            guard let f = updated.layers[0].furring else { return }
            let frame = LayoutGridFrame.make(surface:drag.document.surface,layer:drag.document.layers[0])
            let local = frame.vector(delta)
            let acrossDelta = LayoutPlanning.alongX(updated.layers[0]) ? local.y : local.x
            updated.layers[0].furring?.offset = f.offset + acrossDelta
        } else if mode == .contour, let i = drag.vertex {
            let p = drag.document.surface.contour[i] + delta
            updated.surface.contour[i] = .init(x: p.x.rounded(), y: p.y.rounded())
        } else if let id = drag.opening, let i = updated.surface.openings.firstIndex(where: { $0.id == id }) {
            updated.surface.openings[i].contour = drag.document.surface.openings[i].contour.map { $0 + delta }
        } else {
            pan = .init(width: drag.initialPan.width + value.translation.width, height: drag.initialPan.height + value.translation.height)
            return
        }
        model.preview(updated)
    }

    private func nearestSpot(_ point:CGPoint, document:LayoutDocument, viewport:LayoutViewport) -> Int? {
        guard let lighting = document.lighting else { return nil }
        return lighting.positions.indices.min { a,b in
            let p = viewport.screen(lighting.positions[a]), q = viewport.screen(lighting.positions[b])
            return hypot(p.x-point.x,p.y-point.y) < hypot(q.x-point.x,q.y-point.y)
        }.flatMap { i in
            let p = viewport.screen(lighting.positions[i])
            return hypot(p.x-point.x,p.y-point.y) <= 24 ? i : nil
        }
    }

    @ViewBuilder private func sheetContent(_ destination: LayoutEditorSheet) -> some View {
        switch destination {
        case .newSurface:
            LayoutSurfaceForm { document in model.startNew(); model.apply(document); zoom = 1; pan = .zero; selectedVertex = nil }
        case .settings:
            if let document = model.document, let layer = document.layers.first {
                LayoutSettingsForm(layer: layer, surface:document.surface) { value in var copy = document; copy.layers[0] = value; model.apply(copy) }.environmentObject(catalogue)
            }
        case .furring:
            if let document = model.document, let layer = document.layers.first {
                LayoutFurringForm(surface:document.surface,layer:layer) { value in
                    var copy = document; copy.layers[0] = value; model.apply(copy)
                }.environmentObject(catalogue)
            }
        case .lighting:
            if let document = model.document, let layer = document.layers.first {
                if document.surface.kind == .wall {
                    LayoutWallElectricalForm(surface:document.surface,layer:layer,lighting:document.lighting) { value in
                        var copy = document; copy.lighting = value; model.apply(copy)
                        mode = .lighting; selectedSpots = []; referenceSpot = nil
                    }
                } else {
                LayoutLightingForm(surface:document.surface,layer:layer,settings:document.lighting) { value in
                    var copy = document; copy.lighting = value; model.apply(copy)
                    mode = .lighting; selectedSpots = []; referenceSpot = nil
                }
                }
            }
        case .lightingSpacing(let selected):
            if let document = model.document, let layer = document.layers.first, let lighting = document.lighting {
                LayoutLightingSpacingForm(surface:document.surface,layer:layer,lighting:lighting,selected:selected) { value in
                    var copy = document; copy.lighting = value; model.apply(copy)
                }
            }
        case .export:
            if let document = model.document { LayoutExportForm(document:document) }
        case .opening(let id):
            if let document = model.document {
                LayoutOpeningForm(support: document.surface.kind, existing: document.surface.openings.first { $0.id == id }) { opening in
                    var copy = document
                    if let i = copy.surface.openings.firstIndex(where: { $0.id == opening.id }) { copy.surface.openings[i] = opening }
                    else { copy.surface.openings.append(opening) }
                    model.apply(copy)
                } onDelete: {
                    var copy = document; copy.surface.openings.removeAll { $0.id == id }; model.apply(copy)
                }
            }
        case .vertex(let index):
            if let document = model.document, document.surface.contour.indices.contains(index) {
                LayoutVertexForm(index: index, contour: document.surface.contour) { p in model.editVertices(p); selectedVertex = nil }
            }
        case .correction(let index):
            if let correction = model.document?.surface.dimensionCorrections.first(where: { $0.edgeIndex == index }) {
                LayoutCorrectionDetail(correction: correction, edgeCount: model.document?.surface.contour.count ?? 1)
            }
        case .cut(let selection): LayoutCutDetail(selection: selection)
        case .furringDimensions:
            NavigationStack {
                List {
                    if let document = model.document, let result = model.result {
                        Section {
                            Text("Distances cumulées depuis le premier angle de chaque mur, en centimètres. Les fourrures sont interrompues aux ouvertures. Repérage géométrique, sans validation de l’ossature.").font(.footnote)
                        }
                        ForEach(document.surface.contour.indices,id:\.self) { i in
                            Section("Mur \(vertexName(i))–\(vertexName((i+1)%document.surface.contour.count)) · depuis \(vertexName(i))") {
                                let contacts = result.furring.contacts.filter{$0.edgeIndex == i}.sorted{$0.distance < $1.distance}
                                if contacts.isEmpty { Text("Aucun croisement sur ce mur.").foregroundStyle(.secondary) }
                                ForEach(Array(contacts.enumerated()),id:\.offset) { index,contact in
                                    LabeledContent("Repère \(index+1)",value:layoutCM(contact.distance))
                                }
                            }
                        }
                    }
                }.navigationTitle("Repères des fourrures").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fermer") { sheet = nil } } }
            }
        case .pieces:
            NavigationStack {
                List {
                    if let result = model.result {
                        Section {
                            LabeledContent("Plaques brutes", value: "\(result.sheets.count)")
                            LabeledContent("Morceaux à poser", value: "\(result.pieceCount)")
                            LabeledContent("Surface nette", value: layoutArea(result.netArea))
                            LabeledContent("Chutes théoriques", value: layoutArea(result.wasteArea))
                            Text("Une plaque brute par case de grille utilisée. Les chutes ne sont pas réaffectées à d’autres cases.").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(result.sheets) { placement in
                            Section("Plaque \(placement.number)\(placement.isFull ? " · entière" : " · découpée")") {
                                ForEach(Array(placement.pieces.enumerated()), id: \.element.id) { index, piece in
                                    Button {
                                        sheet = .cut(.make(sheet:placement,piece:piece,lighting:model.document?.lighting,frame:result.frame,wall:model.document?.surface.kind == .wall))
                                    } label: {
                                        VStack(alignment: .leading) {
                                            Text("Morceau \(index + 1) · \(layoutArea(piece.area))")
                                            Text("\(layoutCM(piece.bounds.width)) × \(layoutCM(piece.bounds.height))").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.navigationTitle("Découpes").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { sheet = nil } } }
            }
        }
    }
}
