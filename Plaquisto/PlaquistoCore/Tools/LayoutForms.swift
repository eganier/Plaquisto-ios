import SwiftUI

struct LayoutSurfaceForm: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (LayoutDocument) -> Void
    @State private var name = ""
    @State private var kind = LayoutSupportKind.wall
    @State private var preset = LayoutPreset.rectangle
    @State private var length = 4000.0
    @State private var height = 2500.0
    @State private var second = 3000.0
    @State private var lowerLength = 2000.0
    @State private var upperLength = 2000.0
    @State private var mirrored = false
    @State private var sketch: [LayoutPoint] = []
    @State private var measuredSides: [Double] = []
    @State private var referenceAngles: [Double] = []
    @State private var selectedCorrection: LayoutDimensionCorrection?
    private var generated: (contour: [LayoutPoint], corrections: [LayoutDimensionCorrection]) {
        if kind == .ceiling, preset == .freeform {
            guard sketch.count >= 3, measuredSides.count == sketch.count else { return ([], []) }
            return (try? LayoutGeometry.closedMeasuredContour(sketch: angledSketch, lengths: measuredSides)) ?? ([], [])
        }
        return (preset.contour(length: length, height: height, secondaryHeight: second, mirrored: mirrored,
                               lowerLength: lowerLength), [])
    }
    private var contour: [LayoutPoint] { generated.contour }
    private var tones: [LayoutEdgeTone] {
        switch (kind, preset) {
        case (.wall, .rectangle): return [.blue, .orange, .blue, .orange]
        case (.wall, .slope): return mirrored ? [.blue, .orange, .gray, .purple] : [.blue, .purple, .gray, .orange]
        case (.wall, .lShape): return [.green, .gray, .teal, .purple, .blue, .orange]
        case (.ceiling, .rectangle): return [.blue, .orange, .blue, .orange]
        default: return contour.indices.map { [.blue, .orange, .purple, .green][$0 % 4] }
        }
    }
    private var valid: Bool {
        length >= 10 && height >= 10 && length <= 100_000 && height <= 100_000
            && (!(preset == .slope || preset == .lShape) || second >= height)
            && (preset != .lShape || (lowerLength >= 10 && upperLength >= 10 && abs(lowerLength + upperLength - length) < 0.1))
            && (preset != .freeform || (sketch.count >= 3 && measuredSides.allSatisfy { $0 >= 10 }))
            && (try? LayoutGeometry.validate(contour)) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Support") {
                    TextField("Pièce (facultatif)", text: $name)
                    Picker("Type", selection: $kind) { ForEach(LayoutSupportKind.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                    Picker("Forme", selection: $preset) { ForEach(LayoutPreset.available(for: kind), id: \.self) { Text($0.rawValue) } }
                }
                if preset == .freeform, kind == .ceiling {
                    Section("Dessiner le plafond") {
                        LayoutSketchPad { points in acceptSketch(points) }.frame(height: 230)
                        Text("Tracez le contour en un seul geste. Plaquisto le transforme en côtés rectilignes que vous pourrez coter.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if measuredSides.count >= 3 {
                        Section("Cotes du plafond") {
                            ForEach(measuredSides.indices, id: \.self) { index in
                                LayoutDimensionField(title: "\(vertexName(index))–\(vertexName((index + 1) % measuredSides.count))", millimetres: $measuredSides[index], tint: toneColor(tones[index]))
                            }
                            if !referenceAngles.isEmpty {
                                ForEach(referenceAngles.indices, id: \.self) { index in
                                    HStack {
                                        Text("Angle \(vertexName(index))–\(vertexName(index + 1))–\(vertexName(index + 2))")
                                        Spacer()
                                        TextField("90", value: $referenceAngles[index], format: .number.precision(.fractionLength(0...1)))
                                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                                        Text("°").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if contour.isEmpty {
                            Section {
                                Label("Ces mesures ne permettent pas de refermer proprement la forme. Vérifiez les cotes ou redessinez le plafond.", systemImage: "exclamationmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } else {
                    Section("Dimensions") {
                        if preset != .lShape {
                            LayoutDimensionField(title: "Longueur", millimetres: $length, tint: .blue)
                        }
                        if kind == .ceiling {
                            LayoutDimensionField(title: "Largeur", millimetres: $height, tint: .orange)
                        } else if preset == .rectangle {
                            LayoutDimensionField(title: "Hauteur sous plafond", millimetres: $height, tint: .orange)
                        } else {
                            LayoutDimensionField(title: "Hauteur sous plafond mini", millimetres: $height, tint: .orange)
                            LayoutDimensionField(title: "Hauteur sous plafond maxi", millimetres: $second, tint: .purple)
                            if preset == .lShape {
                                LayoutDimensionField(title: "Longueur totale", millimetres: totalLengthBinding, tint: .blue)
                                LayoutDimensionField(title: "Longueur basse", millimetres: lowerLengthBinding, tint: .green)
                                LayoutDimensionField(title: "Longueur haute", millimetres: upperLengthBinding, tint: .teal)
                                Text("Renseignez deux longueurs : la troisième est calculée automatiquement.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Toggle("Miroir", isOn: $mirrored)
                        }
                    }
                }
                Section("Aperçu du support") {
                    LayoutMeasuredPreview(contour: contour, tones: tones, corrections: generated.corrections) { selectedCorrection = $0 }
                        .frame(height: 240)
                }
                Section { Text("Toutes les cotes sont en centimètres. Pour un rampant de plafond, renseignez les longueurs mesurées dans le plan incliné.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Créer le support").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        onCreate(.init(surface: .init(name: name.isEmpty ? kind.rawValue : name, kind: kind, contour: contour,
                                                      edgeTones: tones, dimensionCorrections: generated.corrections)))
                        dismiss()
                    }.disabled(!valid)
                }
            }
            .onChange(of: kind) { _, value in if !LayoutPreset.available(for: value).contains(preset) { preset = .rectangle } }
            .sheet(item: $selectedCorrection) { LayoutCorrectionDetail(correction: $0, edgeCount: contour.count) }
        }
    }
    private var angledSketch: [LayoutPoint] {
        guard sketch.count >= 4, referenceAngles.count == sketch.count - 3 else { return sketch }
        var result = [sketch[0], sketch[1]]
        for vertex in 1..<(sketch.count - 1) {
            let originalIncoming = sketch[vertex] - sketch[vertex - 1]
            let originalOutgoing = sketch[vertex + 1] - sketch[vertex]
            let incoming = result[vertex] - result[vertex - 1]
            guard incoming.length > 0, originalOutgoing.length > 0 else { return sketch }
            let angle = vertex - 1 < referenceAngles.count ? referenceAngles[vertex - 1] : interiorAngle(at: vertex, in: sketch)
            guard angle > 5, angle < 355 else { return sketch }
            let turn = LayoutGeometry.cross(originalIncoming, originalOutgoing) >= 0 ? 1.0 : -1.0
            let direction = atan2(incoming.y, incoming.x) + turn * (.pi - angle * .pi / 180)
            result.append(result[vertex] + LayoutPoint(x: cos(direction), y: sin(direction)) * originalOutgoing.length)
        }
        return result
    }
    private func acceptSketch(_ raw: [LayoutPoint]) {
        guard raw.count >= 3 else { sketch = []; measuredSides = []; return }
        let bounds = LayoutBounds(points: raw), factor = 4000 / max(1, max(bounds.width, bounds.height))
        let normalized = raw.map { LayoutPoint(x: ($0.x - bounds.min.x) * factor, y: ($0.y - bounds.min.y) * factor) }
        sketch = LayoutGeometry.area(normalized) < 0 ? Array(normalized.reversed()) : normalized
        measuredSides = LayoutGeometry.edges(sketch).map { ($0.b - $0.a).length.rounded() }
        referenceAngles = sketch.count >= 4 ? (1...(sketch.count - 3)).map { interiorAngle(at: $0, in: sketch).rounded() } : []
    }
    private func interiorAngle(at index: Int, in points: [LayoutPoint]) -> Double {
        let incoming = points[index - 1] - points[index], outgoing = points[(index + 1) % points.count] - points[index]
        let cosine = max(-1, min(1, LayoutGeometry.dot(incoming, outgoing) / max(0.0001, incoming.length * outgoing.length)))
        return acos(cosine) * 180 / .pi
    }
    private var totalLengthBinding: Binding<Double> {
        Binding(get: { length }, set: { value in
            length = value
            upperLength = max(10, value - lowerLength)
        })
    }
    private var lowerLengthBinding: Binding<Double> {
        Binding(get: { lowerLength }, set: { value in
            lowerLength = value
            upperLength = max(10, length - value)
        })
    }
    private var upperLengthBinding: Binding<Double> {
        Binding(get: { upperLength }, set: { value in
            upperLength = value
            lowerLength = max(10, length - value)
        })
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

func vertexName(_ index: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return index < alphabet.count ? String(alphabet[index]) : "P\(index + 1)"
}

func toneColor(_ tone: LayoutEdgeTone) -> Color {
    switch tone {
    case .blue: return .blue
    case .orange: return .orange
    case .purple: return .purple
    case .green: return .green
    case .teal: return .teal
    case .gray: return .gray
    }
}

func correctionColor(_ correction: LayoutDimensionCorrection) -> Color {
    if correction.difference > 50 { return .red }
    if correction.difference >= 20 { return .orange }
    return .yellow
}

struct LayoutCorrectionDetail: View {
    @Environment(\.dismiss) private var dismiss
    let correction: LayoutDimensionCorrection
    let edgeCount: Int
    var body: some View {
        NavigationStack {
            Form {
                Section("Cote \(vertexName(correction.edgeIndex))–\(vertexName((correction.edgeIndex + 1) % max(1, edgeCount)))") {
                    LabeledContent("Mesure saisie", value: layoutCM(correction.original))
                    LabeledContent("Mesure retenue", value: layoutCM(correction.corrected))
                    LabeledContent("Écart", value: layoutCM(correction.difference))
                    LabeledContent("Différence", value: correction.percentage.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...2))) + " %")
                }
                Section {
                    if correction.difference > 50 {
                        Label("L’écart dépasse 5 cm. Il est recommandé de refaire cette mesure avant de poursuivre.", systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                    } else {
                        Text("La forme a été refermée automatiquement en répartissant le léger écart de mesure entre ses côtés.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Correction de mesure").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct LayoutMeasuredPreview: View {
    let contour: [LayoutPoint]
    let tones: [LayoutEdgeTone]
    let corrections: [LayoutDimensionCorrection]
    let onCorrection: (LayoutDimensionCorrection) -> Void
    var body: some View {
        GeometryReader { proxy in
            let transform = LayoutViewport(bounds: paddedBounds, size: proxy.size, zoom: 1, pan: .zero)
            ZStack {
                Canvas { context, _ in
                    context.fill(layoutPath(contour, transform: transform), with: .color(.teal.opacity(0.08)))
                    for index in contour.indices {
                        let a = contour[index], b = contour[(index + 1) % contour.count]
                        let color = toneColor(tones.indices.contains(index) ? tones[index] : .blue)
                        var side = Path(); side.move(to: transform.screen(a)); side.addLine(to: transform.screen(b))
                        context.stroke(side, with: .color(color), lineWidth: 3)
                        let pa = transform.screen(a), pb = transform.screen(b), label = labelPosition(a: a, b: b, transform: transform)
                        let offset = CGSize(width: label.x - (pa.x + pb.x) / 2, height: label.y - (pa.y + pb.y) / 2)
                        let da = CGPoint(x: pa.x + offset.width, y: pa.y + offset.height)
                        let db = CGPoint(x: pb.x + offset.width, y: pb.y + offset.height)
                        var dimension = Path()
                        dimension.move(to: pa); dimension.addLine(to: da)
                        dimension.move(to: pb); dimension.addLine(to: db)
                        dimension.move(to: da); dimension.addLine(to: db)
                        context.stroke(dimension, with: .color(color.opacity(0.65)), lineWidth: 0.8)
                        context.draw(Text(vertexName(index)).font(.caption.bold()).foregroundStyle(.primary),
                                     at: transform.screen(a), anchor: .bottomTrailing)
                    }
                }
                ForEach(contour.indices, id: \.self) { index in
                    let a = contour[index], b = contour[(index + 1) % contour.count]
                    let position = labelPosition(a: a, b: b, transform: transform)
                    let correction = corrections.first { $0.edgeIndex == index }
                    Button {
                        if let correction { onCorrection(correction) }
                    } label: {
                        HStack(spacing: 3) {
                            Text("\(vertexName(index))–\(vertexName((index + 1) % contour.count))  \(layoutCM((b - a).length))")
                                .font(.caption2.monospacedDigit())
                            if let correction {
                                Image(systemName: correction.symbol).foregroundStyle(correctionColor(correction))
                            }
                        }
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(toneColor(tones.indices.contains(index) ? tones[index] : .blue))
                    }
                    .buttonStyle(.plain).allowsHitTesting(correction != nil)
                    .position(position)
                }
            }
        }
    }
    private var paddedBounds: LayoutBounds {
        let bounds = LayoutBounds(points: contour), padding = max(bounds.width, bounds.height) * 0.22
        return .init(min: .init(x: bounds.min.x - padding, y: bounds.min.y - padding),
                     max: .init(x: bounds.max.x + padding, y: bounds.max.y + padding))
    }
    private func labelPosition(a: LayoutPoint, b: LayoutPoint, transform: LayoutViewport) -> CGPoint {
        let midpoint = transform.screen((a + b) * 0.5), vector = b - a
        let length = max(1, vector.length), outward = LayoutGeometry.area(contour) >= 0 ? 1.0 : -1.0
        let normal = CGSize(width: outward * vector.y / length * 25, height: outward * vector.x / length * 25)
        return .init(x: midpoint.x + normal.width, y: midpoint.y + normal.height)
    }
}

struct LayoutSketchPad: View {
    let onComplete: ([LayoutPoint]) -> Void
    @State private var stroke: [LayoutPoint] = []
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, _ in
                var path = Path()
                if let first = stroke.first {
                    path.move(to: .init(x: first.x, y: first.y))
                    for point in stroke.dropFirst() { path.addLine(to: .init(x: point.x, y: point.y)) }
                }
                context.stroke(path, with: .color(.teal), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if stroke.isEmpty { Text("Dessinez ici").foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let point = LayoutPoint(x: min(max(0, value.location.x), proxy.size.width),
                                        y: proxy.size.height - min(max(0, value.location.y), proxy.size.height))
                if stroke.last.map({ ($0 - point).length > 3 }) ?? true { stroke.append(point) }
            }.onEnded { _ in
                var tolerance = 12.0
                var simplified = LayoutGeometry.simplifiedStroke(stroke, tolerance: tolerance)
                while simplified.count > 12 { tolerance += 5; simplified = LayoutGeometry.simplifiedStroke(stroke, tolerance: tolerance) }
                onComplete(simplified)
                stroke = simplified
            })
        }
        .accessibilityLabel("Zone de dessin du plafond")
    }
}
