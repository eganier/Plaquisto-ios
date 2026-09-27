import SwiftUI

enum LayoutPolygonSelection: Identifiable {
    case length(Int), angle(Int), correction(Int)
    var id: String {
        switch self { case .length(let i): return "length-\(i)"; case .angle(let i): return "angle-\(i)"; case .correction(let i): return "correction-\(i)" }
    }
    var index: Int { switch self { case .length(let i), .angle(let i), .correction(let i): return i } }
}

private struct LayoutPlanLabel: Identifiable {
    var id: String
    var index: Int
    var angle: Bool
    var center: CGPoint
    var size: CGSize
    var anchor: CGPoint
    var text: String
}

// One label layout is shared by the manual editor and the calepinage canvas.
// Labels remain horizontal. Outside dimension lines, leaders and collision avoidance
// keep side labels distinct from vertex/angle controls on small phone screens.
struct LayoutPolygonAnnotations: View {
    let surface: Surface2D
    let viewport: LayoutViewport
    var showAngles = true
    var showDimensions = true
    var showsLocks = true
    let onSelect: (LayoutPolygonSelection) -> Void

    private var labels: [LayoutPlanLabel] {
        let points = surface.contour
        guard points.count >= 3 else { return [] }
        var occupied = points.map { p -> CGRect in let s = viewport.screen(p); return CGRect(x: s.x-12, y: s.y-12, width: 24, height: 24) }
        var result: [LayoutPlanLabel] = []
        let winding = LayoutGeometry.area(points) >= 0 ? 1.0 : -1.0
        func place(anchor: CGPoint, normal: CGSize, size: CGSize, angle: Bool) -> CGPoint {
            let horizontal = max(size.width / 2 + 3, min(viewport.size.width - size.width / 2 - 3, anchor.x))
            var best = CGPoint(x: horizontal, y: anchor.y), bestPenalty = Double.infinity
            // Search around the anchor, not just along its outward normal: on a
            // recess that normal can point into another side of the same room.
            let normalAngle = atan2(normal.height,normal.width)
            let screenEdges = LayoutGeometry.edges(points).map { (viewport.screen($0.a),viewport.screen($0.b)) }
            for distance in stride(from: angle ? 34.0 : 54.0, through: max(viewport.size.width,viewport.size.height), by: 18) {
                for step in 0..<16 {
                    let turn = Double(step <= 8 ? step : step-16) * .pi/8
                    let direction = normalAngle+turn
                    let candidate = CGPoint(x: max(size.width/2+3, min(viewport.size.width-size.width/2-3, anchor.x + cos(direction)*distance)),
                                            y: max(size.height/2+3, min(viewport.size.height-size.height/2-3, anchor.y + sin(direction)*distance)))
                    let box = CGRect(x: candidate.x-size.width/2-3, y: candidate.y-size.height/2-3, width: size.width+6, height: size.height+6)
                    let overlaps = occupied.filter { $0.intersects(box) }.count
                    let screenPoint = LayoutPoint(x:candidate.x,y:candidate.y)
                    let nearEdge = screenEdges.contains { a,b in
                        return LayoutGeometry.distance(screenPoint,to:.init(x:a.x,y:a.y),.init(x:b.x,y:b.y)) < 22
                    }
                    let inside = !angle && LayoutGeometry.contains(viewport.world(candidate),in:points)
                    let penalty = Double(overlaps)*10_000 + (nearEdge || inside ? 3000 : 0) + hypot(candidate.x-anchor.x, candidate.y-anchor.y) + abs(turn)*12
                    if penalty < bestPenalty { bestPenalty = penalty; best = candidate }
                }
            }
            occupied.append(CGRect(x: best.x-size.width/2-3, y: best.y-size.height/2-3, width: size.width+6, height: size.height+6))
            return best
        }
        for i in points.indices where showDimensions {
            let a = points[i], b = points[(i+1)%points.count], v = b-a, length = max(1, v.length)
            let midpoint = viewport.screen((a+b)*0.5)
            let approximate = surface.contourIntent.map { $0.userMeasuredLengths[i] == nil } ?? false
            let text = "\(vertexName(i))–\(vertexName((i+1)%points.count))  \(approximate ? "≈ " : "")\(layoutCM(length))"
            let warning = surface.dimensionCorrections.contains { $0.edgeIndex == i }
            let width = min(215, Double(text.count)*6.0 + (warning ? 48 : 30))
            let size = CGSize(width: width, height: 32)
            let rotated = LayoutViewport.rotated(v, by:viewport.rotation)
            let center = place(anchor: midpoint, normal: .init(width: winding*rotated.y/length, height: winding*rotated.x/length), size: size, angle: false)
            result.append(.init(id: "length-\(i)", index: i, angle: false, center: center, size: size, anchor: midpoint, text: text))
        }
        if showAngles {
            for i in points.indices {
                let p = viewport.screen(points[i]), previous = viewport.screen(points[(i+points.count-1)%points.count]), next = viewport.screen(points[(i+1)%points.count])
                let l1 = max(1, hypot(previous.x-p.x, previous.y-p.y)), l2 = max(1, hypot(next.x-p.x, next.y-p.y))
                var dx = (previous.x-p.x)/l1 + (next.x-p.x)/l2, dy = (previous.y-p.y)/l1 + (next.y-p.y)/l2
                let norm = max(0.01, hypot(dx,dy)); dx /= norm; dy /= norm
                let angle = LayoutPolygonSolver.interiorAngle(at: i, in: points)
                let text = "\(vertexName(i)) · \(angle.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))))°"
                let size = CGSize(width: max(92, Double(text.count)*6+28), height: 30)
                result.append(.init(id: "angle-\(i)", index: i, angle: true,
                                    center: place(anchor: p, normal: .init(width: dx, height: dy), size: size, angle: true), size: size, anchor: p, text: text))
            }
        }
        return result
    }

    var body: some View {
        let labels = labels
        ZStack {
            Canvas { context, _ in
                for label in labels {
                    var path = Path()
                    if label.angle {
                        path.move(to: label.anchor); path.addLine(to: label.center)
                    } else {
                        let a = viewport.screen(surface.contour[label.index]), b = viewport.screen(surface.contour[(label.index+1)%surface.contour.count])
                        let length = max(1,hypot(b.x-a.x,b.y-a.y))
                        let delta = CGSize(width:label.center.x-label.anchor.x,height:label.center.y-label.anchor.y)
                        let tangent = (delta.width*(b.x-a.x)+delta.height*(b.y-a.y))/length
                        let normal = (delta.width*(a.y-b.y)+delta.height*(b.x-a.x))/length
                        let distance = abs(tangent) < 24 ? normal : (normal < 0 ? -28.0 : 28.0)
                        let offset = CGSize(width:(a.y-b.y)/length*distance,height:(b.x-a.x)/length*distance)
                        let da = CGPoint(x:a.x+offset.width, y:a.y+offset.height), db = CGPoint(x:b.x+offset.width, y:b.y+offset.height)
                        path.move(to:a); path.addLine(to:da); path.addLine(to:db); path.addLine(to:b)
                        for p in [da, db] { path.move(to:.init(x:p.x-3,y:p.y+3)); path.addLine(to:.init(x:p.x+3,y:p.y-3)) }
                        if abs(tangent) >= 24 {
                            path.move(to:.init(x:(da.x+db.x)/2,y:(da.y+db.y)/2)); path.addLine(to:label.center)
                        }
                    }
                    context.stroke(path, with: .color(color(label.index).opacity(0.35)), lineWidth: 0.7)
                }
            }.allowsHitTesting(false)
            ForEach(labels) { label in
                HStack(spacing: 0) {
                    Button { onSelect(label.angle ? .angle(label.index) : .length(label.index)) } label: {
                        HStack(spacing:3) {
                            Text(label.text).monospacedDigit()
                            let locked = label.angle ? surface.contourIntent?.userAnglesDegrees[label.index] != nil : surface.contourIntent?.lockedLengthIndices?.contains(label.index) == true
                            if showsLocks { Image(systemName:locked ? "lock.fill" : "lock.open").font(.system(size:9)) }
                        }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 5).frame(minHeight: 30)
                    }
                    .accessibilityLabel(label.angle ? "Modifier l’angle \(vertexName(label.index))" : "Modifier la cote \(vertexName(label.index))–\(vertexName((label.index+1)%surface.contour.count))")
                    if !label.angle, let correction = surface.dimensionCorrections.first(where: { $0.edgeIndex == label.index }) {
                        Button { onSelect(.correction(label.index)) } label: {
                            Image(systemName: correction.symbol).foregroundStyle(correctionColor(correction)).frame(width: 28, height: 32)
                        }.accessibilityLabel("Correction de la cote \(vertexName(label.index))")
                    }
                }
                .buttonStyle(.plain).foregroundStyle(label.angle ? Color.secondary : color(label.index))
                .frame(width:label.size.width,height:label.size.height)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .position(label.center)
            }
        }
    }
    private func color(_ i: Int) -> Color {
        toneColor(surface.edgeTones.indices.contains(i) ? surface.edgeTones[i] : [.blue, .orange, .purple, .green, .teal][i%5])
    }
}

struct LayoutConstraintForm: View {
    @Environment(\.dismiss) private var dismiss
    let selection: LayoutPolygonSelection
    let original: Surface2D
    let onSave: (Surface2D) -> Void
    @State private var value: Double
    @State private var preview: Surface2D
    @State private var error: String?
    init(selection: LayoutPolygonSelection, surface: Surface2D, onSave: @escaping (Surface2D) -> Void) {
        self.selection = selection; original = surface; self.onSave = onSave
        _preview = State(initialValue: surface)
        let i = selection.index
        switch selection {
        case .angle:
            _value = State(initialValue: surface.editableIntent.userAnglesDegrees[i] ?? LayoutPolygonSolver.interiorAngle(at:i, in:surface.contour))
        default:
            _value = State(initialValue: surface.editableIntent.userMeasuredLengths[i] ?? (surface.contour[(i+1)%surface.contour.count]-surface.contour[i]).length)
        }
    }
    private var isAngle: Bool { if case .angle = selection { return true }; return false }
    var body: some View {
        NavigationStack {
            Form {
                Section(isAngle ? "Angle au sommet \(vertexName(selection.index))" : "Cote \(vertexName(selection.index))–\(vertexName((selection.index+1)%original.contour.count))") {
                    LayoutDimensionField(title:isAngle ? "Angle demandé" : "Mesure relevée", millimetres:$value, unit:isAngle ? "°" : "cm", displayScale:isAngle ? 1 : 0.1)
                    if isAngle {
                        Text("L’angle est imposé au contour. Les mesures relevées sont conservées ; les ajustements éventuels restent signalés.").font(.footnote).foregroundStyle(.secondary)
                        Button("Libérer cet angle") { releaseAngle() }
                    } else {
                        Text("Valider verrouille cette longueur. Une contrainte contradictoire sera refusée plutôt que de modifier une cote verrouillée.").font(.footnote).foregroundStyle(.secondary)
                        Button("Libérer cette cote",systemImage:"lock.open") { releaseAngle() }
                    }
                }
                Section("Aperçu") {
                    LayoutContourPreview(contours:[preview.contour], numbered:true).frame(height:210)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !preview.dimensionCorrections.isEmpty {
                    Section("Mesures ajustées") {
                        ForEach(preview.dimensionCorrections) { correction in
                            VStack(alignment:.leading, spacing:4) {
                                Label("\(vertexName(correction.edgeIndex))–\(vertexName((correction.edgeIndex+1)%preview.contour.count))", systemImage:correction.symbol).foregroundStyle(correctionColor(correction))
                                Text("Relevée : \(layoutCM(correction.original)) · retenue : \(layoutCM(correction.corrected))").font(.caption)
                                Text("Correction : \(correction.correctionDelta >= 0 ? "+" : "")\(layoutCM(correction.correctionDelta)) · \(correction.percentage.formatted(.number.precision(.fractionLength(0...2)))) %").font(.caption)
                            }
                        }
                        if preview.dimensionCorrections.contains(where: { $0.severity() == .red }) {
                            Text("Écart important. Vérifiez et reprenez ces mesures sur chantier.").foregroundStyle(.red).font(.footnote)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isAngle ? "Modifier l’angle" : "Modifier la cote").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Valider") { if update() { onSave(preview); dismiss() } }.disabled(error != nil) }
            }
            .onChange(of:value) { _,_ in _ = update() }
        }
    }
    @discardableResult private func update() -> Bool {
        var intent = original.editableIntent
        if isAngle { intent.userAnglesDegrees[selection.index] = value }
        else {
            intent.userMeasuredLengths[selection.index] = value
            intent.lockedLengthIndices = Array(Set((intent.lockedLengthIndices ?? [])+[selection.index]))
        }
        do { var copy = original; try copy.resolve(intent); preview = copy; error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func releaseAngle() {
        var intent = original.editableIntent
        if isAngle { intent.userAnglesDegrees[selection.index] = nil }
        else {
            intent.userMeasuredLengths[selection.index] = nil
            intent.lockedLengthIndices?.removeAll{$0 == selection.index}
        }
        intent.sketch = original.contour
        do { var copy = original; copy.previousContourIntents.append(original.editableIntent); try copy.resolve(intent); onSave(copy); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct LayoutManualContourEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Surface2D) -> Void
    let kind: LayoutSupportKind
    let title: String?
    @State private var surface: Surface2D?
    @State private var drawing: Bool
    @State private var offsetEdges: Set<Int> = []
    @State private var offsetStart: Surface2D?
    @State private var lastOffsetValue = 0.0
    @State private var editTopology = false
    @State private var selection: LayoutPolygonSelection?
    @State private var dragOriginal: Surface2D?
    @State private var dragVertex: Int?
    @State private var error: String?
    @State private var history: [Surface2D] = []
    @State private var scaleReference: Surface2D?
    @State private var scaleValue = 1.0
    @State private var scaleStart: Surface2D?
    @State private var topologyVertex: Int?
    @State private var topologyEdge: Int?
    @State private var topologyPoint: LayoutPoint?
    @State private var confirmingTopology = false
    @State private var viewZoom = 1.0
    @State private var viewPan = CGSize.zero
    @State private var viewBounds:LayoutBounds?
    @State private var dragPanOrigin = CGSize.zero
    @State private var pinching = false
    @GestureState private var magnification = 1.0
    @AppStorage("layout.showDimensions") private var showDimensions = true
    @AppStorage("layout.showAngles") private var showAngles = true
    init(surface: Surface2D?, kind:LayoutSupportKind = .ceiling, title:String? = nil, onSave: @escaping (Surface2D) -> Void) {
        self.kind = kind
        self.title = title
        var initial = surface; initial?.kind = kind
        // Before predefined shapes had an explicit provenance, they were saved
        // as "manual" too. The absence of a drawing intent identifies them and
        // keeps the drawing-only scale control hidden after later edits.
        if initial?.provenance == "manual", initial?.contourIntent == nil {
            initial?.provenance = "preset"
        }
        self.onSave = onSave; _surface = State(initialValue:initial); _drawing = State(initialValue:surface == nil)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:12) {
                Text(drawing ? "Dessinez le contour en un geste et revenez près du départ." : "Touchez une cote ou un angle. Glissez les sommets pour ajuster la forme.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                if kind == .wall { Text("Dessinez le mur de face, avec le sol horizontal en bas du dessin.").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                if drawing {
                    LayoutSketchPad(kind:kind) { points in accept(points) }.padding(12)
                } else if let surface {
                    HStack(spacing:24) {
                        Button { showDimensions.toggle() } label: {
                            LayoutVisibilityIcon(kind:.sheet,state:showDimensions ? .dimensioned : .hidden).frame(width:52,height:42)
                        }.accessibilityLabel(showDimensions ? "Masquer les cotes" : "Afficher les cotes")
                        Button { showAngles.toggle() } label: {
                            LayoutVisibilityIcon(kind:.angle,state:showAngles ? .visible : .hidden).frame(width:52,height:42)
                        }.accessibilityLabel(showAngles ? "Masquer les angles" : "Afficher les angles")
                    }
                    GeometryReader { proxy in
                        let viewport = planViewport(surface:dragOriginal ?? surface, size:proxy.size)
                        Canvas { context,_ in
                            let path = layoutPath(surface.contour, transform:viewport)
                            context.fill(path, with:.color(.teal.opacity(0.12)))
                            context.stroke(path, with:.color(.teal), lineWidth:5)
                            if let laying = try? surface.layingContour() {
                                context.stroke(layoutPath(laying,transform:viewport),with:.color(.secondary.opacity(0.5)),lineWidth:2)
                                for i in offsetEdges where laying.indices.contains(i) {
                                    var selected = Path(); selected.move(to:viewport.screen(laying[i])); selected.addLine(to:viewport.screen(laying[(i+1)%laying.count]))
                                    context.stroke(selected,with:.color(.orange),style:.init(lineWidth:7,lineCap:.round))
                                }
                            }
                            for (i,p) in surface.contour.enumerated() {
                                let point = viewport.screen(p)
                                context.fill(Path(ellipseIn:CGRect(x:point.x-7,y:point.y-7,width:14,height:14)),with:.color(.teal))
                                context.draw(Text(vertexName(i)).font(.caption.bold()),at:.init(x:point.x-10,y:point.y-12))
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:3).onChanged { value in
                            guard !pinching else { return }
                            if dragOriginal == nil {
                                dragOriginal = surface
                                dragPanOrigin = viewPan
                                dragVertex = surface.contour.indices.min { a,b in
                                    let pa = viewport.screen(surface.contour[a]), pb = viewport.screen(surface.contour[b])
                                    return hypot(pa.x-value.startLocation.x,pa.y-value.startLocation.y) < hypot(pb.x-value.startLocation.x,pb.y-value.startLocation.y)
                                }.flatMap { i in let p = viewport.screen(surface.contour[i]); return hypot(p.x-value.startLocation.x,p.y-value.startLocation.y) < 32 ? i : nil }
                            }
                            if let original = dragOriginal, let i = dragVertex {
                                let delta = viewport.world(value.location) - viewport.world(value.startLocation)
                                var copy = original; copy.contour[i] = original.contour[i] + delta; self.surface = copy
                            } else {
                                viewPan = viewport.constrainedPan(.init(width:dragPanOrigin.width+value.translation.width,height:dragPanOrigin.height+value.translation.height),contour:surface.contour)
                            }
                        }.onEnded { _ in finishDrag() })
                        .simultaneousGesture(MagnifyGesture().updating($magnification) { value,state,_ in state = value.magnification }
                            .onChanged { _ in
                                if !pinching {
                                    pinching = true; viewBounds = viewport.bounds
                                    if let original = dragOriginal { self.surface = original; viewPan = dragPanOrigin }
                                    dragOriginal = nil; dragVertex = nil
                                }
                            }.onEnded { value in
                                viewZoom = min(8,max(0.4,viewZoom*value.magnification))
                                let final = LayoutViewport(bounds:viewport.bounds,size:proxy.size,zoom:viewZoom,pan:viewPan)
                                viewPan = final.constrainedPan(viewPan,contour:surface.contour)
                                pinching = false
                            })
                        .simultaneousGesture(SpatialTapGesture().onEnded { value in
                            if !editTopology {
                                let p = viewport.world(value.location)
                                if let laying = try? surface.layingContour() {
                                    let edge = laying.indices.min(by: { a,b in
                                        LayoutGeometry.distance(p,to:laying[a],laying[(a+1)%laying.count]) < LayoutGeometry.distance(p,to:laying[b],laying[(b+1)%laying.count])
                                    }).flatMap { i in LayoutGeometry.distance(p,to:laying[i],laying[(i+1)%laying.count])*viewport.scale < 22 ? i : nil }
                                    if let edge {
                                        if offsetEdges.contains(edge) { offsetEdges.remove(edge) }
                                        else { offsetEdges.insert(edge) }
                                    }
                                }
                                return
                            }
                            topologyVertex = surface.contour.indices.first { i in
                                let p = viewport.screen(surface.contour[i]); return hypot(p.x-value.location.x,p.y-value.location.y) < 24
                            }
                            topologyEdge = nil; topologyPoint = nil
                            if topologyVertex == nil {
                                let p = viewport.world(value.location)
                                if let i = surface.contour.indices.min(by:{ a,b in
                                    LayoutGeometry.distance(p,to:surface.contour[a],surface.contour[(a+1)%surface.contour.count]) < LayoutGeometry.distance(p,to:surface.contour[b],surface.contour[(b+1)%surface.contour.count])
                                }) {
                                    let a = surface.contour[i], b = surface.contour[(i+1)%surface.contour.count], d = b-a
                                    if LayoutGeometry.distance(p,to:a,b)*viewport.scale < 20 {
                                        topologyEdge = i
                                        let t = max(0.05,min(0.95,LayoutGeometry.dot(p-a,d)/LayoutGeometry.dot(d,d)))
                                        topologyPoint = a+d*t
                                    }
                                }
                            }
                            confirmingTopology = topologyVertex != nil || topologyEdge != nil
                        })
                        .overlay { LayoutPolygonAnnotations(surface:surface, viewport:viewport, showAngles:showAngles, showDimensions:showDimensions) { selection = $0 } }
                        .overlay(alignment:.topTrailing) {
                            Button { viewZoom = 1; viewPan = .zero; viewBounds = nil } label: {
                                Image(systemName:"scope").padding(12).background(.regularMaterial,in:Circle())
                            }.padding(8).accessibilityLabel("Recentrer le contour")
                        }
                        .overlay(alignment:.bottomTrailing) {
                            Text(layoutArea(abs(LayoutGeometry.area(surface.contour)))).font(.subheadline.bold()).padding(9)
                                .background(.regularMaterial,in:Capsule()).padding(8).allowsHitTesting(false)
                        }
                    }.padding(8)
                    scaleControls(surface)
                    VStack(alignment:.leading,spacing:6) {
                        HStack {
                            Text("Décalage des bords de plaque").font(.subheadline.bold())
                            Spacer()
                            Button("Réinitialiser") { applyOffset(reset:true) }.font(.subheadline)
                        }
                        Text("Créez un espace entre les bords de plaques et les murs supports afin de faciliter le passage des gaines.").font(.caption).foregroundStyle(.secondary)
                        if offsetEdges.isEmpty {
                            Text("Sélectionnez un ou plusieurs bords sur le dessin.").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Slider(value:Binding(get:{ selectedOffset(surface) },set:{ value in
                                let crossedZero = value * lastOffsetValue < 0
                                let snapped = abs(value) < 0.25 || crossedZero ? 0 : value
                                if snapped == 0 && lastOffsetValue != 0 { UIImpactFeedbackGenerator(style:.light).impactOccurred() }
                                lastOffsetValue = snapped
                                applyOffset(cm:snapped)
                            }),in:-5...5,onEditingChanged:{ editing in
                                if editing { offsetStart = self.surface; lastOffsetValue = selectedOffset(surface) }
                                else { if let original = offsetStart, original != self.surface { history.append(original) }; offsetStart = nil }
                            })
                                .disabled(offsetEdges.isEmpty || editTopology)
                                .tint(.orange).accessibilityIdentifier("layout.contour.offset")
                                .accessibilityLabel("Décalage des bords sélectionnés en centimètres")
                            Text("\(selectedOffset(surface).formatted(.number.precision(.fractionLength(1)))) cm").monospacedDigit().frame(width:65,alignment:.trailing)
                        }
                        Text("−5 cm : vers l’intérieur · 0 : au mur · +5 cm : vers l’extérieur").font(.caption2).foregroundStyle(.secondary)
                        if let warning = surface.layingWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
                    }.padding(.horizontal)
                    HStack {
                        Button("Redessiner", systemImage:"pencil.tip") { drawing = true }
                        Spacer()
                        Button("Annuler la modification", systemImage:"arrow.uturn.backward") { if let previous = history.popLast() { self.surface = previous; resetScale() } }.disabled(history.isEmpty)
                    }.font(.subheadline).padding(.horizontal)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
            }
            .padding(.bottom).background(Color(.systemGroupedBackground))
            .navigationTitle(title ?? (kind == .wall ? "Dessiner le mur" : "Dessiner le plafond")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Utiliser") { if let surface { onSave(surface); dismiss() } }.disabled(surface == nil || drawing) }
                ToolbarItem(placement:.primaryAction) {
                    Menu {
                        Toggle("Ajouter ou supprimer des sommets",isOn:$editTopology)
                    } label: { Image(systemName:"ellipsis.circle") }
                }
            }
            .alert(topologyVertex != nil ? "Supprimer ce sommet ?" : "Ajouter un sommet ?",isPresented:$confirmingTopology) {
                Button("Annuler",role:.cancel) {}
                Button(topologyVertex != nil ? "Supprimer" : "Ajouter",role:topologyVertex != nil ? .destructive : nil) {
                    guard let original = self.surface else { return }
                    do {
                        let updated = try original.changingVertex(remove:topologyVertex,insertAfter:topologyEdge,point:topologyPoint)
                        history.append(original); self.surface = updated; error = nil; resetScale()
                    } catch { self.error = error.localizedDescription }
                }.disabled(topologyVertex != nil && (surface?.contour.count ?? 0) <= 3)
            } message: {
                Text("Les contraintes et décalages individuels des côtés modifiés seront libérés. Les autres mesures et décalages sont conservés.")
            }
            .sheet(item:$selection) { selected in
                if let surface {
                    if case .correction(let i) = selected, let correction = surface.dimensionCorrections.first(where:{$0.edgeIndex == i}) {
                        LayoutCorrectionDetail(correction:correction, edgeCount:surface.contour.count)
                    } else {
                        LayoutConstraintForm(selection:selected, surface:surface) { updated in history.append(surface); self.surface = updated; resetScale() }
                    }
                }
            }
        }
    }
    private func planViewport(surface:Surface2D, size:CGSize) -> LayoutViewport {
        let b = surface.bounds, margin = max(b.width,b.height)*0.25
        let viewport = LayoutViewport(bounds:viewBounds ?? .init(min:b.min - .init(x:margin,y:margin), max:b.max + .init(x:margin,y:margin)),size:size,zoom:min(8,max(0.4,viewZoom*magnification)),pan:viewPan)
        return LayoutViewport(bounds:viewport.bounds,size:size,zoom:viewport.zoom,pan:viewport.constrainedPan(viewPan,contour:surface.contour))
    }
    @ViewBuilder private func scaleControls(_ surface:Surface2D) -> some View {
        if surface.provenance == "manual", surface.contourIntent != nil {
            VStack(alignment:.leading,spacing:4) {
                HStack {
                    Text("Échelle du dessin").font(.subheadline.bold())
                    Spacer()
                    Text("× \(scaleValue.formatted(.number.precision(.fractionLength(2))))").monospacedDigit()
                }
                Slider(value:Binding(get:{scaleValue},set:{ value in
                    let base = scaleReference ?? surface
                    if let copy = try? base.scaledDrawing(by:value) {
                        scaleReference = base; self.surface = copy; scaleValue = value
                    }
                }),in:0.25...5,onEditingChanged:{ editing in
                    if editing { scaleStart = self.surface }
                    else if let original = scaleStart, original != self.surface { history.append(original); scaleStart = nil }
                }).disabled(!surface.canScaleDrawing).accessibilityLabel("Échelle réelle du dessin")
            }.padding(.horizontal)
        }
    }
    private func selectedOffset(_ surface:Surface2D) -> Double {
        guard let edge = offsetEdges.sorted().first, surface.contour.indices.contains(edge) else { return 0 }
        // The trade convention shown to the user follows the slider direction:
        // negative values move the board edge inward, positive values outward.
        // The geometry engine stores the inward normal with the opposite sign.
        return max(-5,min(5,LayoutLayingOffset.displayedCentimetres(storedMillimetres:surface.layingDistance(at:edge))))
    }
    private func applyOffset(cm:Double? = nil, reset:Bool = false) {
        guard let original = surface else { return }
        do {
            var updated = original
            if reset { updated = try original.changingLayingOffset(reset:true) }
            else if let cm, !offsetEdges.isEmpty {
                updated.edgeIDs = original.stableEdgeIDs
                for edge in offsetEdges where updated.contour.indices.contains(edge) {
                    updated.layingOffset.individualMM[updated.edgeIDs[edge]] = LayoutLayingOffset.storedMillimetres(displayedCentimetres:cm)
                }
                _ = try updated.layingContour()
            }
            if reset && updated != original { history.append(original) }
            surface = updated; error = nil
            if reset { offsetEdges.removeAll() }
        } catch { self.error = "Ce décalage ne peut pas être appliqué à cette forme." }
    }
    private func accept(_ points:[LayoutPoint]) {
        let b = LayoutBounds(points:points), scale = 4000 / max(1,max(b.width,b.height))
        let normalized = points.map { ($0-b.min)*scale }
        var copy = Surface2D(name:surface?.name ?? kind.rawValue, kind:kind, contour:normalized,
                             edgeTones:normalized.indices.map { [.blue,.orange,.purple,.green,.teal][$0%5] },
                             contourIntent:.init(sketch:normalized))
        if let surface {
            history.append(surface)
            copy.previousContourIntents = surface.previousContourIntents + [surface.editableIntent]
        }
        surface = copy; error = nil; resetScale()
        viewBounds = nil; viewPan = .zero; viewZoom = 1
        withAnimation(.easeOut(duration:0.18)) { drawing = false }
    }
    private func finishDrag() {
        defer { dragOriginal = nil; dragVertex = nil }
        guard let original = dragOriginal, let i = dragVertex, let moved = surface else { return }
        guard moved.contour.indices.contains(i) else { return }
        do { let copy = try original.movingVertices(to:moved.contour); history.append(original); surface = copy; error = nil; resetScale() }
        catch { surface = original; self.error = error.localizedDescription }
    }
    private func resetScale() { scaleReference = nil; scaleValue = 1; scaleStart = nil; offsetEdges.removeAll() }
}
