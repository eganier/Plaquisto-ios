import SwiftUI

struct LayoutViewport {
    let bounds: LayoutBounds
    let size: CGSize
    let zoom: Double
    let pan: CGSize
    var scale: Double { min(max(1, size.width - 70) / max(100, bounds.width), max(1, size.height - 70) / max(100, bounds.height)) * zoom }
    func screen(_ p: LayoutPoint) -> CGPoint {
        .init(x: size.width / 2 + pan.width + (p.x - bounds.center.x) * scale,
              y: size.height / 2 + pan.height - (p.y - bounds.center.y) * scale)
    }
    func world(_ p: CGPoint) -> LayoutPoint {
        .init(x: bounds.center.x + (p.x - size.width / 2 - pan.width) / scale,
              y: bounds.center.y - (p.y - size.height / 2 - pan.height) / scale)
    }
}
func layoutPath(_ loop: [LayoutPoint], transform: LayoutViewport) -> Path {
    var path = Path()
    guard let first = loop.first else { return path }
    path.move(to: transform.screen(first))
    for p in loop.dropFirst() { path.addLine(to: transform.screen(p)) }
    path.closeSubpath(); return path
}

private enum LayoutInteraction: String, CaseIterable {
    case inspect = "Sélection", contour = "Contour", grid = "Grille", move = "Vue"
    var hint: String {
        switch self {
        case .inspect: return "Touchez une plaque pour ses cotes, une ouverture pour la modifier."
        case .contour: return "Glissez un sommet, ou touchez-le pour modifier ses cotes."
        case .grid: return "Glissez pour décaler les plaques. Réglage précis dans « Plaques »."
        case .move: return "Glissez pour déplacer la vue. Pincez pour zoomer."
        }
    }
}
private enum LayoutEditorSheet: Identifiable {
    case newSurface, settings, opening(UUID?), vertex(Int), correction(Int), cut(LayoutCutSelection), pieces
    var id: String {
        switch self {
        case .newSurface: return "new"
        case .settings: return "settings"
        case .opening(let id): return "opening-\(id?.uuidString ?? "new")"
        case .vertex(let i): return "vertex-\(i)"
        case .correction(let i): return "correction-\(i)"
        case .cut(let selection): return "cut-\(selection.id)"
        case .pieces: return "pieces"
        }
    }
}
private struct LayoutDragState {
    let document: LayoutDocument
    let viewport: LayoutViewport
    let vertex: Int?
    let opening: UUID?
    let initialPan: CGSize
}

struct SheetLayoutView: View {
    @StateObject private var model = LayoutEditorModel()
    @EnvironmentObject private var catalogue: ToolTechnicalStore
    @State private var mode = LayoutInteraction.inspect
    @State private var sheet: LayoutEditorSheet?
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var magnification = 1.0
    @State private var drag: LayoutDragState?
    @State private var selectedVertex: Int?
    @State private var polygonSelection: LayoutPolygonSelection?

    var body: some View {
        Group {
            if let document = model.document { editor(document) }
            else { entry }
        }
        .navigationTitle("Calepinage 2D").navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if model.document != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Enregistrer") { model.saveCurrentAndClose(); selectedVertex = nil }
                    Menu {
                        Button("Retour aux calepinages", systemImage: "list.bullet") { model.startNew(); selectedVertex = nil }
                        Button("Nouveau support", systemImage: "plus") { sheet = .newSurface }
                        Button("Liste des découpes", systemImage: "list.number") { sheet = .pieces }.disabled(model.result == nil)
                        Divider()
                        Button { model.undo(); selectedVertex = nil } label: { Label("Annuler la modification", systemImage: "arrow.uturn.backward") }.disabled(!model.canUndo)
                        Button { model.redo(); selectedVertex = nil } label: { Label("Rétablir la modification", systemImage: "arrow.uturn.forward") }.disabled(!model.canRedo)
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Options du calepinage")
                }
            }
        }
        .sheet(item: $sheet) { destination in sheetContent(destination) }
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
                                Image(systemName: saved.document.surface.kind == .wall ? "rectangle.portrait" : "rectangle")
                                    .foregroundStyle(.teal).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(saved.title).font(.headline).foregroundStyle(.primary)
                                    Text("\(saved.document.surface.kind.rawValue) · \(layoutCM(saved.document.surface.bounds.width)) × \(layoutCM(saved.document.surface.bounds.height))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let documents = offsets.map { model.savedDocuments[$0] }
                        for document in documents { model.delete(document) }
                    }
                }
            }
            Section {
                Button { sheet = .newSurface } label: { Label("Nouveau calepinage", systemImage: "plus") }
                Button {} label: { Label("Importer un ouvrage depuis Chantier (à venir)", systemImage: "square.and.arrow.down") }.disabled(true)
            }
            if let error = model.saveError { Section { Text(error).font(.footnote).foregroundStyle(.orange) } }
        }
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
                        Text("\(result.sheets.count) plaques").font(.headline)
                        Text(layoutArea(result.netArea)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(.horizontal)
            Picker("Action sur le plan", selection: $mode) { ForEach(LayoutInteraction.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).padding(.horizontal)
            GeometryReader { proxy in
                let bounds = drag?.document.surface.bounds ?? document.surface.bounds
                let margin = max(bounds.width,bounds.height)*0.2
                let viewport = LayoutViewport(bounds:.init(min:bounds.min - .init(x:margin,y:margin),max:bounds.max + .init(x:margin,y:margin)), size: proxy.size, zoom: zoom * magnification, pan: pan)
                Canvas { context, size in draw(context: &context, size: size, document: document, viewport: viewport) }
                    .background(Color(.secondarySystemGroupedBackground))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 7).onChanged { value in dragChanged(value, document: document, viewport: viewport) }.onEnded { _ in
                        if let drag { model.finishGesture(from: drag.document) }; drag = nil
                    })
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in tapped(value.location, document: document, viewport: viewport) })
                    .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }.onEnded { value in zoom = min(8, max(0.4, zoom * value.magnification)) })
                    .overlay { LayoutPolygonAnnotations(surface:document.surface, viewport:viewport) { polygonSelection = $0 } }
                    .overlay(alignment: .topTrailing) {
                        Button { zoom = 1; pan = .zero } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").padding(12).background(.regularMaterial, in: Circle()) }
                            .padding(8).accessibilityLabel("Recentrer le plan")
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text("X →   Y ↑   ·   cotes en cm").font(.caption2).padding(8).background(.regularMaterial, in: Capsule()).padding(8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }.padding(.horizontal)
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
            } else {
                Text(mode.hint).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            }
            if let saveError = model.saveError { Text(saveError).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if mode == .contour, let index = selectedVertex, document.surface.contour.indices.contains(index) {
                Button("Modifier le sommet \(index + 1) · ajouter / supprimer") { sheet = .vertex(index) }.font(.subheadline)
            }
            if mode == .grid, let layer = document.layers.first {
                Text("Décalage X : \(layoutCM(layer.offset.x)) · Y : \(layoutCM(layer.offset.y))").font(.caption.monospacedDigit())
            }
            HStack(spacing: 10) {
                Button { sheet = .settings } label: { Label("Plaques", systemImage: "slider.horizontal.3") }
                Button { sheet = .opening(nil) } label: { Label("Ouverture", systemImage: "plus.rectangle") }
                Button { sheet = .pieces } label: { Image(systemName: "list.number") }.accessibilityLabel("Liste des découpes")
            }.buttonStyle(.bordered).tint(.teal).padding(.bottom, 8)
        }.padding(.top, 8)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, document: LayoutDocument, viewport: LayoutViewport) {
        let surface = document.surface
        let origin = viewport.screen(.zero)
        var axes = Path()
        axes.move(to: .init(x: 0, y: origin.y)); axes.addLine(to: .init(x: size.width, y: origin.y))
        axes.move(to: .init(x: origin.x, y: 0)); axes.addLine(to: .init(x: origin.x, y: size.height))
        context.stroke(axes, with: .color(.secondary.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        if let result = model.result {
            for placement in result.sheets {
                for (index, piece) in placement.pieces.enumerated() {
                    var path = layoutPath(piece.contour, transform: viewport)
                    for hole in piece.holes { path.addPath(layoutPath(hole, transform: viewport)) }
                    let color = placement.isFull ? Color.teal : Color.blue
                    context.fill(path, with: .color(color.opacity(placement.number % 2 == 0 ? 0.22 : 0.12)), style: FillStyle(eoFill: true))
                    context.stroke(path, with: .color(color.opacity(0.75)), lineWidth: 1)
                    if piece.bounds.width * viewport.scale > 20 && piece.bounds.height * viewport.scale > 20 {
                        let label = placement.pieces.count > 1 ? "\(placement.number).\(index + 1)" : "\(placement.number)"
                        context.draw(Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary), at: viewport.screen(piece.labelPoint))
                    }
                }
            }
        }
        context.stroke(layoutPath(surface.contour, transform: viewport), with: .color(.primary), lineWidth: 2)
        for opening in surface.openings {
            let p = layoutPath(opening.contour, transform: viewport)
            context.stroke(p, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            context.draw(Text(opening.kind.rawValue).font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange), at: viewport.screen(opening.bounds.center))
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
        if mode == .contour {
            selectedVertex = nearestVertex(p, document: document, viewport: viewport)
            if let selectedVertex { sheet = .vertex(selectedVertex) }
            return
        }
        guard mode == .inspect else { return }
        let point = viewport.world(p)
        if let opening = document.surface.openings.last(where: { LayoutGeometry.contains(point, in: $0.contour) }) { sheet = .opening(opening.id); return }
        guard !model.isCalculating, let result = model.result else { return }
        for placement in result.sheets {
            if let piece = placement.pieces.first(where: { $0.contains(point) }) { sheet = .cut(.init(sheet: placement, piece: piece)); return }
        }
    }
    private func dragChanged(_ value: DragGesture.Value, document: LayoutDocument, viewport: LayoutViewport) {
        if drag == nil {
            let vertex = mode == .contour ? nearestVertex(value.startLocation, document: document, viewport: viewport) : nil
            let p = viewport.world(value.startLocation)
            let opening = mode == .inspect ? document.surface.openings.last(where: { LayoutGeometry.contains(p, in: $0.contour) })?.id : nil
            drag = .init(document: document, viewport: viewport, vertex: vertex, opening: opening, initialPan: pan)
            if let vertex { selectedVertex = vertex }
        }
        guard let drag else { return }
        var updated = drag.document
        let delta = LayoutPoint(x: value.translation.width / drag.viewport.scale, y: -value.translation.height / drag.viewport.scale)
        if mode == .grid {
            updated.layers[0].offset = drag.document.layers[0].offset + delta
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

    @ViewBuilder private func sheetContent(_ destination: LayoutEditorSheet) -> some View {
        switch destination {
        case .newSurface:
            LayoutSurfaceForm { document in model.startNew(); model.apply(document); zoom = 1; pan = .zero; selectedVertex = nil }
        case .settings:
            if let document = model.document, let layer = document.layers.first {
                LayoutSettingsForm(layer: layer) { value in var copy = document; copy.layers[0] = value; model.apply(copy) }.environmentObject(catalogue)
            }
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
                                        sheet = .cut(.init(sheet: placement, piece: piece))
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
