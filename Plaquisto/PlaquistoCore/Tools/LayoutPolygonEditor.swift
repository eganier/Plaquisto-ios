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
            for distance in stride(from: angle ? 30.0 : 24.0, through: 144.0, by: 18) {
                for tangent in [0.0, -22, 22, -44, 44] {
                    let candidate = CGPoint(x: max(size.width/2+3, min(viewport.size.width-size.width/2-3, anchor.x + normal.width*distance - normal.height*tangent)),
                                            y: max(size.height/2+3, min(viewport.size.height-size.height/2-3, anchor.y + normal.height*distance + normal.width*tangent)))
                    let box = CGRect(x: candidate.x-size.width/2-3, y: candidate.y-size.height/2-3, width: size.width+6, height: size.height+6)
                    let overlaps = occupied.filter { $0.intersects(box) }.count
                    let penalty = Double(overlaps)*10_000 + hypot(candidate.x-anchor.x, candidate.y-anchor.y)
                    if penalty < bestPenalty { bestPenalty = penalty; best = candidate }
                    if overlaps == 0 { occupied.append(box); return candidate }
                }
            }
            occupied.append(CGRect(x: best.x-size.width/2, y: best.y-size.height/2, width: size.width, height: size.height))
            return best
        }
        for i in points.indices {
            let a = points[i], b = points[(i+1)%points.count], v = b-a, length = max(1, v.length)
            let midpoint = viewport.screen((a+b)*0.5)
            let approximate = surface.contourIntent.map { $0.userMeasuredLengths[i] == nil } ?? false
            let text = "\(vertexName(i))–\(vertexName((i+1)%points.count))  \(approximate ? "≈ " : "")\(layoutCM(length))"
            let warning = surface.dimensionCorrections.contains { $0.edgeIndex == i }
            let width = min(195, Double(text.count)*6.0 + (warning ? 32 : 14))
            let size = CGSize(width: width, height: 32)
            let center = place(anchor: midpoint, normal: .init(width: winding*v.y/length, height: winding*v.x/length), size: size, angle: false)
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
                let size = CGSize(width: max(76, Double(text.count)*6+12), height: 30)
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
                        let offset = CGSize(width: label.center.x-label.anchor.x, height: label.center.y-label.anchor.y)
                        let da = CGPoint(x:a.x+offset.width, y:a.y+offset.height), db = CGPoint(x:b.x+offset.width, y:b.y+offset.height)
                        path.move(to:a); path.addLine(to:da); path.addLine(to:db); path.addLine(to:b)
                        for p in [da, db] { path.move(to:.init(x:p.x-3,y:p.y+3)); path.addLine(to:.init(x:p.x+3,y:p.y-3)) }
                    }
                    context.stroke(path, with: .color(color(label.index).opacity(0.35)), lineWidth: 0.7)
                }
            }.allowsHitTesting(false)
            ForEach(labels) { label in
                HStack(spacing: 0) {
                    Button { onSelect(label.angle ? .angle(label.index) : .length(label.index)) } label: {
                        Text(label.text).font(.system(size: 11, weight: .medium)).monospacedDigit().padding(.horizontal, 5).frame(minHeight: 30)
                    }
                    .accessibilityLabel(label.angle ? "Modifier l’angle \(vertexName(label.index))" : "Modifier la cote \(vertexName(label.index))–\(vertexName((label.index+1)%surface.contour.count))")
                    if !label.angle, let correction = surface.dimensionCorrections.first(where: { $0.edgeIndex == label.index }) {
                        Button { onSelect(.correction(label.index)) } label: {
                            Image(systemName: correction.symbol).foregroundStyle(correctionColor(correction)).frame(width: 28, height: 32)
                        }.accessibilityLabel("Correction de la cote \(vertexName(label.index))")
                    }
                }
                .buttonStyle(.plain).foregroundStyle(label.angle ? Color.secondary : color(label.index))
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
        else { intent.userMeasuredLengths[selection.index] = value }
        do { var copy = original; try copy.resolve(intent); preview = copy; error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func releaseAngle() {
        var intent = original.editableIntent; intent.userAnglesDegrees[selection.index] = nil
        do { var copy = original; try copy.resolve(intent); onSave(copy); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct LayoutManualContourEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Surface2D) -> Void
    @State private var surface: Surface2D?
    @State private var drawing: Bool
    @State private var selection: LayoutPolygonSelection?
    @State private var dragOriginal: Surface2D?
    @State private var dragVertex: Int?
    @State private var error: String?
    @State private var history: [Surface2D] = []
    init(surface: Surface2D?, onSave: @escaping (Surface2D) -> Void) {
        self.onSave = onSave; _surface = State(initialValue:surface); _drawing = State(initialValue:surface == nil)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:12) {
                Text(drawing ? "Dessinez le contour en un geste et revenez près du départ." : "Touchez une cote ou un angle. Glissez les sommets pour ajuster la forme.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                if drawing {
                    LayoutSketchPad { points in accept(points) }.padding(12)
                } else if let surface {
                    GeometryReader { proxy in
                        let viewport = planViewport(surface:dragOriginal ?? surface, size:proxy.size)
                        Canvas { context,_ in
                            let path = layoutPath(surface.contour, transform:viewport)
                            context.fill(path, with:.color(.teal.opacity(0.12)))
                            context.stroke(path, with:.color(.teal), lineWidth:2)
                            for (i,p) in surface.contour.enumerated() {
                                let point = viewport.screen(p)
                                context.fill(Path(ellipseIn:CGRect(x:point.x-7,y:point.y-7,width:14,height:14)),with:.color(.teal))
                                context.draw(Text(vertexName(i)).font(.caption.bold()),at:.init(x:point.x-10,y:point.y-12))
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:3).onChanged { value in
                            if dragOriginal == nil {
                                dragOriginal = surface
                                dragVertex = surface.contour.indices.min { a,b in
                                    let pa = viewport.screen(surface.contour[a]), pb = viewport.screen(surface.contour[b])
                                    return hypot(pa.x-value.startLocation.x,pa.y-value.startLocation.y) < hypot(pb.x-value.startLocation.x,pb.y-value.startLocation.y)
                                }.flatMap { i in let p = viewport.screen(surface.contour[i]); return hypot(p.x-value.startLocation.x,p.y-value.startLocation.y) < 32 ? i : nil }
                            }
                            if let original = dragOriginal, let i = dragVertex {
                                var copy = original; copy.contour[i] = viewport.world(value.location); self.surface = copy
                            }
                        }.onEnded { _ in finishDrag() })
                        .overlay { LayoutPolygonAnnotations(surface:surface, viewport:viewport) { selection = $0 } }
                    }.padding(8)
                    Text("≈ : cote issue du dessin, à remplacer par votre mesure.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Redessiner", systemImage:"pencil.tip") { drawing = true }
                        Spacer()
                        Button("Annuler la modification", systemImage:"arrow.uturn.backward") { if let previous = history.popLast() { self.surface = previous } }.disabled(history.isEmpty)
                    }.font(.subheadline).padding(.horizontal)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
            }
            .padding(.bottom).background(Color(.systemGroupedBackground))
            .navigationTitle("Dessiner le plafond").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Utiliser") { if let surface { onSave(surface); dismiss() } }.disabled(surface == nil || drawing) }
            }
            .sheet(item:$selection) { selected in
                if let surface {
                    if case .correction(let i) = selected, let correction = surface.dimensionCorrections.first(where:{$0.edgeIndex == i}) {
                        LayoutCorrectionDetail(correction:correction, edgeCount:surface.contour.count)
                    } else {
                        LayoutConstraintForm(selection:selected, surface:surface) { updated in history.append(surface); self.surface = updated }
                    }
                }
            }
        }
    }
    private func planViewport(surface:Surface2D, size:CGSize) -> LayoutViewport {
        let b = surface.bounds, margin = max(b.width,b.height)*0.25
        return .init(bounds:.init(min:b.min - .init(x:margin,y:margin), max:b.max + .init(x:margin,y:margin)),size:size,zoom:1,pan:.zero)
    }
    private func accept(_ points:[LayoutPoint]) {
        let b = LayoutBounds(points:points), scale = 4000 / max(1,max(b.width,b.height))
        let normalized = points.map { ($0-b.min)*scale }
        var copy = Surface2D(name:"Plafond", kind:.ceiling, contour:normalized,
                             edgeTones:normalized.indices.map { [.blue,.orange,.purple,.green,.teal][$0%5] },
                             contourIntent:.init(sketch:normalized))
        if let surface {
            history.append(surface)
            copy.previousContourIntents = surface.previousContourIntents + [surface.editableIntent]
        }
        surface = copy; error = nil
        withAnimation(.easeOut(duration:0.18)) { drawing = false }
    }
    private func finishDrag() {
        defer { dragOriginal = nil; dragVertex = nil }
        guard let original = dragOriginal, let i = dragVertex, let moved = surface else { return }
        var intent = original.editableIntent
        intent.userVertexPositions[i] = moved.contour[i]
        do { var copy = original; try copy.resolve(intent); history.append(original); surface = copy; error = nil }
        catch { surface = original; self.error = error.localizedDescription }
    }
}
