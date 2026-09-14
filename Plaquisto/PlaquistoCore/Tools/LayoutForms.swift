import SwiftUI

struct LayoutSurfaceForm: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (LayoutDocument) -> Void
    @State private var name = ""
    @State private var kind = LayoutSupportKind.wall
    @State private var preset = LayoutPreset.rectangle
    @State private var width = 4000.0
    @State private var height = 2500.0
    @State private var second = 3000.0
    private var contour: [LayoutPoint] { preset.contour(width: width, height: height, secondaryHeight: second) }
    private var valid: Bool {
        width >= 10 && height >= 10 && width <= 100_000 && height <= 100_000
            && (!(preset == .slope || preset == .gable) || second >= 10)
            && (preset != .gable || second >= height)
            && (try? LayoutGeometry.validate(contour)) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Support") {
                    TextField("Pièce (facultatif)", text: $name)
                    Picker("Type", selection: $kind) { ForEach(LayoutSupportKind.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                    Picker("Forme", selection: $preset) { ForEach(LayoutPreset.allCases, id: \.self) { Text($0.rawValue) } }
                }
                Section("Dimensions") {
                    LayoutDimensionField(title: kind == .wall ? "Largeur" : "Longueur", millimetres: $width)
                    LayoutDimensionField(title: heightTitle, millimetres: $height)
                    if preset == .slope || preset == .gable {
                        LayoutDimensionField(title: preset == .gable ? "Hauteur au faîtage" : "Hauteur droite", millimetres: $second)
                    }
                    if preset == .lShape { Text("Le décroché est créé à mi-largeur et mi-hauteur. Vous pourrez déplacer chaque sommet sur le plan.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Aperçu du support") {
                    LayoutContourPreview(contours: [contour], numbered: true).frame(height: 190)
                }
                Section { Text("Toutes les cotes sont en centimètres. Pour un rampant de plafond, renseignez les longueurs mesurées dans le plan incliné.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Créer le support").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        onCreate(.init(surface: .init(name: name.isEmpty ? kind.rawValue : name, kind: kind, contour: contour)))
                        dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
    private var heightTitle: String {
        if preset == .gable { return "Hauteur des côtés" }
        if preset == .slope { return "Hauteur gauche" }
        return kind == .wall ? "Hauteur" : "Largeur"
    }
}

struct LayoutOpeningForm: View {
    @Environment(\.dismiss) private var dismiss
    let support: LayoutSupportKind
    let existing: LayoutOpening?
    let onSave: (LayoutOpening) -> Void
    let onDelete: (() -> Void)?
    @State private var kind: LayoutOpeningKind
    @State private var x: Double
    @State private var y: Double
    @State private var width: Double
    @State private var height: Double
    init(support: LayoutSupportKind, existing: LayoutOpening? = nil, onSave: @escaping (LayoutOpening) -> Void, onDelete: (() -> Void)? = nil) {
        self.support = support; self.existing = existing; self.onSave = onSave; self.onDelete = onDelete
        _kind = State(initialValue: existing?.kind ?? (support == .wall ? .window : .stairwell))
        _x = State(initialValue: existing?.bounds.min.x ?? 1000)
        _y = State(initialValue: existing?.bounds.min.y ?? (support == .wall ? 900 : 1000))
        _width = State(initialValue: existing?.bounds.width ?? 900)
        _height = State(initialValue: existing?.bounds.height ?? 1200)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Ouverture") {
                    Picker("Type", selection: $kind) { ForEach(LayoutOpeningKind.available(for: support), id: \.self) { Text($0.rawValue) } }
                    LayoutDimensionField(title: "Largeur", millimetres: $width)
                    LayoutDimensionField(title: support == .wall ? "Hauteur" : "Longueur", millimetres: $height)
                }
                Section("Position du coin inférieur gauche") {
                    LayoutDimensionField(title: "Depuis la gauche (X)", millimetres: $x, signed: true)
                    LayoutDimensionField(title: support == .wall ? "Depuis le sol (Y)" : "Depuis le bas (Y)", millimetres: $y, signed: true)
                    Text("La partie située dans le support sera retirée des plaques. Une porte peut toucher le sol ; les ouvertures qui se chevauchent ne sont déduites qu’une fois.").font(.footnote).foregroundStyle(.secondary)
                }
                if existing != nil, let onDelete { Section { Button("Supprimer l’ouverture", role: .destructive) { onDelete(); dismiss() } } }
            }
            .navigationTitle(existing == nil ? "Nouvelle ouverture" : "Modifier l’ouverture").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        let polygon = LayoutBounds(min: .init(x: x, y: y), max: .init(x: x + width, y: y + height)).polygon
                        onSave(.init(id: existing?.id ?? UUID(), kind: kind, contour: polygon)); dismiss()
                    }.disabled(width <= 0 || height <= 0 || [x, y, width, height].contains { !$0.isFinite || abs($0) > 100_000 })
                }
            }
            .onChange(of: kind) { _, value in if value == .door { y = 0 } }
        }
    }
}

struct LayoutVertexForm: View {
    @Environment(\.dismiss) private var dismiss
    let index: Int
    let onSave: ([LayoutPoint]) -> Void
    @State private var contour: [LayoutPoint]
    @State private var sideLength: Double
    @State private var message: String?
    init(index: Int, contour: [LayoutPoint], onSave: @escaping ([LayoutPoint]) -> Void) {
        self.index = index; self.onSave = onSave
        _contour = State(initialValue: contour)
        _sideLength = State(initialValue: (contour[(index + 1) % contour.count] - contour[index]).length)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Sommet \(index + 1)") {
                    LayoutDimensionField(title: "Depuis la gauche (X)", millimetres: $contour[index].x, signed: true)
                    LayoutDimensionField(title: "Depuis le bas (Y)", millimetres: $contour[index].y, signed: true)
                }
                Section("Côté vers le sommet \((index + 1) % contour.count + 1)") {
                    LayoutDimensionField(title: "Longueur du côté", millimetres: $sideLength)
                    Button("Appliquer cette longueur") {
                        let next = (index + 1) % contour.count, direction = contour[next] - contour[index]
                        if direction.length > 0, sideLength > 0 { contour[next] = contour[index] + direction * (sideLength / direction.length) }
                    }
                    Text("Déplace le sommet suivant dans la direction actuelle du côté.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Ajouter un sommet au milieu de ce côté") {
                        var copy = contour
                        copy.insert((contour[index] + contour[(index + 1) % contour.count]) * 0.5, at: index + 1)
                        save(copy)
                    }
                    Button("Supprimer ce sommet", role: .destructive) {
                        var copy = contour; copy.remove(at: index); save(copy)
                    }.disabled(contour.count <= 3)
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("Modifier le contour").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Valider") { save(contour) } }
            }
        }
    }
    private func save(_ p: [LayoutPoint]) {
        do { try LayoutGeometry.validate(p); onSave(p); dismiss() }
        catch { message = error.localizedDescription }
    }
}

struct LayoutSettingsForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalogue: ToolTechnicalStore
    let onSave: (LayoutLayer) -> Void
    @State private var layer: LayoutLayer
    init(layer: LayoutLayer, onSave: @escaping (LayoutLayer) -> Void) {
        self.onSave = onSave; _layer = State(initialValue: layer)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Format de plaque") {
                    Picker("Catalogue Plaquisto", selection: Binding(get: { layer.catalogFormatID ?? "manual" }, set: { id in
                        layer.catalogFormatID = id == "manual" ? nil : id
                        if let format = catalogue.layoutFormats.first(where: { $0.id == id }) { layer.sheetWidth = format.width; layer.sheetLength = format.length }
                    })) {
                        Text("Saisie manuelle").tag("manual")
                        ForEach(catalogue.layoutFormats) { Text($0.label).tag($0.id) }
                    }
                    LayoutDimensionField(title: "Largeur de plaque", millimetres: $layer.sheetWidth).disabled(layer.catalogFormatID != nil)
                    LayoutDimensionField(title: "Longueur de plaque", millimetres: $layer.sheetLength).disabled(layer.catalogFormatID != nil)
                    if catalogue.layoutFormats.isEmpty { Text("Le catalogue n’est pas disponible. Vous pouvez saisir le format manuellement.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Sens de pose") {
                    Picker("Orientation", selection: $layer.orientation) { ForEach(LayoutOrientation.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                    Text("Vertical : grande dimension selon l’axe Y. Horizontal : grande dimension selon l’axe X.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Décalage de la grille") {
                    LayoutDimensionField(title: "Horizontal (X)", millimetres: $layer.offset.x, signed: true)
                    LayoutDimensionField(title: "Vertical (Y)", millimetres: $layer.offset.y, signed: true)
                    Button("Remettre la grille à zéro") { layer.offset = .zero }
                }
                Section { Text("Calepinage géométrique d’une couche. Les règles de joints et la réutilisation des chutes ne sont pas appliquées.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Plaques et pose").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Appliquer") { onSave(layer); dismiss() }.disabled(layer.sheetWidth < 1 || layer.sheetLength < 1 || layer.sheetWidth > 100_000 || layer.sheetLength > 100_000) }
            }
        }
    }
}

struct LayoutCutSelection: Identifiable {
    let sheet: LayoutSheetPlacement
    let piece: LayoutCutPiece
    var id: String { piece.id }
}

struct LayoutCutDetail: View {
    @Environment(\.dismiss) private var dismiss
    let selection: LayoutCutSelection
    private var sheet: LayoutSheetPlacement { selection.sheet }
    private var piece: LayoutCutPiece { selection.piece }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LayoutContourPreview(contours: [piece.contour] + piece.holes, numbered: true,
                        reference: LayoutBounds(min: sheet.origin, max: sheet.origin + .init(x: sheet.width, y: sheet.height)))
                        .frame(height: 230)
                }
                Section("Dimensions de découpe") {
                    LabeledContent("Largeur", value: layoutCM(piece.bounds.width))
                    LabeledContent("Hauteur maximale", value: layoutCM(piece.bounds.height))
                    if let left = sideHeight(at: piece.bounds.min.x) { LabeledContent("Hauteur côté gauche", value: layoutCM(left)) }
                    if let right = sideHeight(at: piece.bounds.max.x) { LabeledContent("Hauteur côté droit", value: layoutCM(right)) }
                    LabeledContent("Surface du morceau", value: layoutArea(piece.area))
                    LabeledContent("Plaque brute", value: "\(layoutCM(sheet.width)) × \(layoutCM(sheet.height))")
                    if sheet.pieces.count > 1 { Text("Cette plaque brute fournit \(sheet.pieces.count) morceaux séparés.").font(.footnote) }
                }
                Section {
                    Text("Origine des cotes : coin inférieur gauche de la plaque brute. X vers la droite, Y vers le haut. Reportez les points dans l’ordre et reliez-les.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(([piece.contour] + piece.holes).enumerated()), id: \.offset) { loopIndex, loop in
                    Section(loopIndex == 0 ? "Contour extérieur" : "Ouverture \(loopIndex)") {
                        ForEach(Array(loop.enumerated()), id: \.offset) { i, point in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Point \(loopIndex == 0 ? "" : "\(loopIndex).")\(i + 1)").font(.headline)
                                Text("X : \(layoutMM(point.x - sheet.origin.x)) · Y : \(layoutMM(point.y - sheet.origin.y))")
                                Text("Côté suivant : \(layoutMM((loop[(i + 1) % loop.count] - point).length))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plaque \(sheet.number)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
    private func sideHeight(at x: Double) -> Double? {
        let ys = piece.contour.filter { abs($0.x - x) < 0.01 }.map(\.y)
        guard ys.count == 2, let a = ys.min(), let b = ys.max(),
              LayoutGeometry.edges(piece.contour).contains(where: { abs($0.a.x - x) < 0.01 && abs($0.b.x - x) < 0.01 }) else { return nil }
        return b - a
    }
}

struct LayoutContourPreview: View {
    let contours: [[LayoutPoint]]
    var numbered = false
    var reference: LayoutBounds? = nil
    var body: some View {
        Canvas { context, size in
            let bounds = reference ?? LayoutBounds(points: contours.flatMap { $0 })
            let transform = LayoutViewport(bounds: bounds, size: size, zoom: 1, pan: .zero)
            if let reference {
                context.stroke(layoutPath(reference.polygon, transform: transform), with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                context.draw(Text("0").font(.caption.bold()).foregroundStyle(.secondary), at: transform.screen(reference.min), anchor: .topTrailing)
            }
            var path = Path()
            for loop in contours { path.addPath(layoutPath(loop, transform: transform)) }
            context.fill(path, with: .color(.teal.opacity(0.16)), style: FillStyle(eoFill: true))
            context.stroke(path, with: .color(.teal), lineWidth: 2)
            if numbered {
                var labels: [CGRect] = []
                for (j, loop) in contours.enumerated() {
                    for (i, p) in loop.enumerated() {
                        let label = j == 0 ? "\(i + 1)" : "\(j).\(i + 1)"
                        let anchor = transform.screen(p)
                        let offsets: [CGSize] = [
                            .init(width: -12, height: -13), .init(width: 12, height: 13),
                            .init(width: 12, height: -13), .init(width: -12, height: 13),
                            .init(width: 0, height: -29), .init(width: 0, height: 29),
                            .init(width: -30, height: 0), .init(width: 30, height: 0)
                        ]
                        let offset = offsets.first { offset in
                            let box = CGRect(x: anchor.x + offset.width - 12, y: anchor.y + offset.height - 8, width: 24, height: 16)
                            return !labels.contains { $0.intersects(box) }
                        } ?? offsets[0]
                        let position = CGPoint(x: anchor.x + offset.width, y: anchor.y + offset.height)
                        labels.append(CGRect(x: position.x - 12, y: position.y - 8, width: 24, height: 16))
                        var leader = Path(); leader.move(to: anchor); leader.addLine(to: position)
                        context.stroke(leader, with: .color(.secondary.opacity(0.45)), lineWidth: 0.5)
                        context.fill(Path(ellipseIn: CGRect(x: anchor.x - 2, y: anchor.y - 2, width: 4, height: 4)), with: .color(.teal))
                        context.draw(Text(label).font(.caption.bold()).foregroundStyle(.primary), at: position)
                    }
                }
            }
        }
    }
}
