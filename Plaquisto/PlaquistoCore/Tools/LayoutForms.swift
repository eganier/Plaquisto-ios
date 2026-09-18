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
    @State private var manualSurface: Surface2D?
    @State private var showingDrawing = false
    @State private var selectedCorrection: LayoutDimensionCorrection?
    @State private var presetReview: Surface2D?
    @State private var reviewedDocument: LayoutDocument?
    private var generated: (contour: [LayoutPoint], corrections: [LayoutDimensionCorrection]) {
        if preset == .freeform {
            return (manualSurface?.contour ?? [], manualSurface?.dimensionCorrections ?? [])
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
            && (preset != .freeform || manualSurface != nil)
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
                if preset == .freeform {
                    Section(kind == .wall ? "Dessiner le mur" : "Dessiner le plafond") {
                        Button(manualSurface == nil ? "Dessiner le contour" : "Modifier le contour et les mesures", systemImage: "pencil.and.outline") { showingDrawing = true }
                        Text("Dessinez en grand, puis touchez les cotes et les angles du plan pour renseigner vos mesures.")
                            .font(.footnote).foregroundStyle(.secondary)
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
                        .frame(height: max(320,min(640,Double(contour.count)*32+120)))
                }
                Section { Text("Toutes les cotes sont en centimètres. Pour un rampant de plafond, renseignez les longueurs mesurées dans le plan incliné.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Créer le support").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(preset == .freeform ? "Créer" : "Suivant") {
                        var surface = preset == .freeform ? manualSurface! : Surface2D(name:kind.rawValue, kind:kind, contour:contour, edgeTones:tones)
                        surface.name = name.isEmpty ? kind.rawValue : name
                        surface.kind = kind
                        if preset == .freeform {
                            onCreate(.newSupport(surface)); dismiss()
                        } else { presetReview = surface }
                    }.disabled(!valid)
                }
            }
            .onChange(of: kind) { _, value in if !LayoutPreset.available(for: value).contains(preset) { preset = .rectangle } }
            .sheet(item: $selectedCorrection) { LayoutCorrectionDetail(correction: $0, edgeCount: contour.count) }
            .fullScreenCover(isPresented:$showingDrawing) { LayoutManualContourEditor(surface:manualSurface,kind:kind) { manualSurface = $0 } }
            .fullScreenCover(item:$presetReview,onDismiss:{
                if let document = reviewedDocument {
                    reviewedDocument = nil; onCreate(document); dismiss()
                }
            }) { surface in
                LayoutManualContourEditor(surface:surface,kind:surface.kind,title:"Modifier le contour et l’échelle") { updated in
                    reviewedDocument = .newSupport(updated)
                }
            }
        }
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
            .scrollDismissesKeyboard(.interactively)
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
            .scrollDismissesKeyboard(.interactively)
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
    let surface: Surface2D
    @State private var layer: LayoutLayer
    @State private var compatibilityMessage: String?
    init(layer: LayoutLayer, surface: Surface2D, onSave: @escaping (LayoutLayer) -> Void) {
        self.surface = surface; self.onSave = onSave; _layer = State(initialValue: layer.forSupport(surface.kind))
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
                    LayoutLivePreview(surface:surface,layer:layer).frame(height:210)
                    if surface.kind == .ceiling { Picker("Mur de référence",selection:Binding(get:{layer.referenceEdge ?? -1},set:{ value in
                        layer.referenceEdge = value < 0 ? nil : value
                        if value >= 0 { layer.orientation = .horizontal }
                        layer.offset = .zero
                    })) {
                        Text("Axes du plan").tag(-1)
                        ForEach(surface.contour.indices,id:\.self) { i in
                            Text("\(vertexName(i))–\(vertexName((i+1)%surface.contour.count)) · \(layoutCM((surface.contour[(i+1)%surface.contour.count]-surface.contour[i]).length))").tag(i)
                        }
                    } }
                    Picker("Grand côté des plaques",selection:$layer.orientation) {
                        Text(layer.referenceEdge == nil ? "Horizontal" : "Parallèle au mur").tag(LayoutOrientation.horizontal)
                        Text(layer.referenceEdge == nil ? "Vertical" : "Perpendiculaire").tag(LayoutOrientation.vertical)
                    }.pickerStyle(.segmented)
                    Text(surface.kind == .wall ? "Orientation du grand côté des plaques par rapport au sol. L’ossature reste verticale." : "Orientation du grand côté de la plaque. Le départ de la grille est le premier angle du mur choisi.").font(.footnote).foregroundStyle(.secondary)
                }
                if layer.furring != nil {
                    Section("Coordination avec les fourrures") {
                        if let compatibilityMessage { Label(compatibilityMessage,systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        Button("Caler les plaques sur les fourrures") { layer = LayoutPlanning.alignBoards(to:layer) }
                        Text(LayoutPlanning.aligned(layer) ? "Les joints parallèles aux fourrures sont alignés sur la trame." : "Les plaques sont décalées de la trame de fourrures.").font(.footnote)
                    }
                }
                Section { Text("Calepinage géométrique d’une couche. Les règles de joints et la réutilisation des chutes ne sont pas appliquées.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of:layer.sheetLength) { _,_ in reconcileSpacing() }
            .onChange(of:layer.sheetWidth) { _,_ in reconcileSpacing() }
            .onChange(of:layer.orientation) { _,_ in reconcileSpacing() }
            .navigationTitle("Plaques et pose").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Appliquer") { onSave(layer); dismiss() }.disabled(layer.sheetWidth < 1 || layer.sheetLength < 1 || layer.sheetWidth > 100_000 || layer.sheetLength > 100_000 || (layer.furring != nil && LayoutPlanning.compatibleSpacings(layer).isEmpty)) }
            }
        }
    }
    private func reconcileSpacing() {
        layer = layer.forSupport(surface.kind)
        guard let f = layer.furring else { return }
        let options = LayoutPlanning.compatibleSpacings(layer)
        if !options.contains(f.spacing) {
            if let spacing = options.max() {
                layer.furring?.spacing = spacing
                layer = LayoutPlanning.alignFurring(to:layer)
                compatibilityMessage = "Attention : passage à \(layoutCM(spacing)) d’entraxe pour respecter les dimensions des plaques."
            } else { compatibilityMessage = "Aucun entraxe de 40, 50 ou 60 cm ne correspond à ce format. Choisissez un autre format." }
        }
    }
}

struct LayoutCutSelection: Identifiable {
    let sheet: LayoutSheetPlacement
    let piece: LayoutCutPiece
    var spots: [LayoutPoint] = []
    var spotDiameter: Double = 0
    var spotLabels: [String] = []
    var id: String { piece.id }
    static func make(sheet:LayoutSheetPlacement,piece:LayoutCutPiece,lighting:LayoutLighting?,frame:LayoutGridFrame,wall:Bool) -> Self {
        let indices = (lighting?.positions.indices.map { $0 } ?? []).filter { i in
            piece.contains(frame.local(lighting!.positions[i]))
        }
        return .init(sheet:sheet,piece:piece,spots:indices.map { frame.local(lighting!.positions[$0]) },spotDiameter:lighting?.diameter ?? 0,
                     spotLabels:indices.map { lighting!.label(at:$0,wall:wall) })
    }
}

struct LayoutCutDetail: View {
    @Environment(\.dismiss) private var dismiss
    let selection: LayoutCutSelection
    @AppStorage("layout.cut.edges") private var showEdges = true
    @AppStorage("layout.cut.raw") private var showRaw = false
    @AppStorage("layout.cut.holes") private var showHoles = true
    @AppStorage("layout.cut.spots") private var showSpots = true
    @AppStorage("layout.cut.coordinates") private var showCoordinates = false
    private var sheet: LayoutSheetPlacement { selection.sheet }
    private var piece: LayoutCutPiece { selection.piece }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:16) {
                    Canvas { context,size in draw(context:&context,size:size) }
                        .frame(height:420)
                        .background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20))
                        .accessibilityLabel("Dessin coté de la plaque \(sheet.number), mesures en centimètres")
                    VStack(alignment:.leading,spacing:12) {
                        Text("Visibilité des cotes").font(.headline)
                        Toggle("Côtés et découpes",isOn:$showEdges)
                        Toggle("Dimensions de la plaque brute",isOn:$showRaw)
                        if !piece.holes.isEmpty { Toggle("Cotes des ouvertures",isOn:$showHoles) }
                        if !selection.spots.isEmpty { Toggle("Position et diamètre des perçages",isOn:$showSpots) }
                        Toggle("Repères X/Y des sommets",isOn:$showCoordinates)
                        Text("Cotes en cm. Les repères X/Y et les positions des perçages partent du coin inférieur gauche de la plaque brute (0).")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding().background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20))
                    if selection.spots.contains(where:{ p in
                        ([piece.contour]+piece.holes).flatMap { LayoutGeometry.edges($0) }.contains { LayoutGeometry.distance(p,to:$0.a,$0.b) < selection.spotDiameter/2 }
                    }) {
                        Label("Un perçage chevauche une coupe ou un joint : repositionnez le spot ou les plaques.",systemImage:"exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plaque \(sheet.number)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
    private func draw(context:inout GraphicsContext,size:CGSize) {
        let raw = LayoutBounds(min:sheet.origin,max:sheet.origin + .init(x:sheet.width,y:sheet.height))
        let v = LayoutViewport(bounds:raw,size:size,zoom:0.82,pan:.zero)
        context.stroke(layoutPath(raw.polygon,transform:v),with:.color(.secondary.opacity(0.5)),style:.init(lineWidth:1,dash:[4,4]))
        var path = layoutPath(piece.contour,transform:v)
        for hole in piece.holes { path.addPath(layoutPath(hole,transform:v)) }
        context.fill(path,with:.color(.teal.opacity(0.16)),style:.init(eoFill:true))
        context.stroke(path,with:.color(.teal),lineWidth:2)
        var occupied:[CGRect] = []
        func label(_ text:String, at anchor:CGPoint, color:Color) {
            let width = min(size.width-8,max(30,Double(text.count)*5.8+8)), height = 18.0
            var p = CGPoint(x:max(width/2+2,min(size.width-width/2-2,anchor.x)),y:max(10,min(size.height-10,anchor.y)))
            let original = p
            for offset in [0.0,20,-20,40,-40,60,-60,80,-80] {
                p.y = max(10,min(size.height-10,original.y+offset))
                if !occupied.contains(where:{$0.intersects(.init(x:p.x-width/2,y:p.y-height/2,width:width,height:height))}) { break }
            }
            occupied.append(.init(x:p.x-width/2,y:p.y-height/2,width:width,height:height))
            if hypot(p.x-anchor.x,p.y-anchor.y) > 5 {
                var leader = Path(); leader.move(to:anchor); leader.addLine(to:p)
                context.stroke(leader,with:.color(color.opacity(0.5)),lineWidth:0.5)
            }
            context.fill(Path(roundedRect:occupied.last!,cornerRadius:4),with:.color(Color(.secondarySystemGroupedBackground).opacity(0.94)))
            context.draw(Text(text).font(.system(size:10,weight:.semibold)).foregroundStyle(color),at:p)
        }
        func dimension(_ a:LayoutPoint,_ b:LayoutPoint,offset:Double,color:Color) {
            let start = v.screen(a), end = v.screen(b), length = hypot(end.x-start.x,end.y-start.y)
            guard length > 1 else { return }
            let nx = -(end.y-start.y)/length, ny = (end.x-start.x)/length
            let p = CGPoint(x:start.x+nx*offset,y:start.y+ny*offset), q = CGPoint(x:end.x+nx*offset,y:end.y+ny*offset)
            var rail = Path(); rail.move(to:start); rail.addLine(to:p); rail.move(to:end); rail.addLine(to:q)
            rail.move(to:p); rail.addLine(to:q)
            for tick in [p,q] { rail.move(to:.init(x:tick.x-3,y:tick.y+3)); rail.addLine(to:.init(x:tick.x+3,y:tick.y-3)) }
            context.stroke(rail,with:.color(color.opacity(0.7)),lineWidth:0.7)
            label(layoutCM((b-a).length),at:.init(x:(p.x+q.x)/2+nx*9,y:(p.y+q.y)/2+ny*9),color:color)
        }
        for (j,loop) in ([piece.contour]+piece.holes).enumerated() {
            let winding = LayoutGeometry.area(loop) >= 0 ? 1.0 : -1.0
            for (i,p) in loop.enumerated() {
                if (j == 0 && showEdges) || (j > 0 && showHoles) {
                    dimension(p,loop[(i+1)%loop.count],offset:winding*15,color:j == 0 ? .teal : .orange)
                }
                if showCoordinates {
                    let s = v.screen(p)
                    label("\(j == 0 ? "" : "O\(j)·")\(vertexName(i))  X \(layoutCM(p.x-sheet.origin.x)) · Y \(layoutCM(p.y-sheet.origin.y))",at:.init(x:s.x,y:s.y-12),color:.secondary)
                }
            }
        }
        if showRaw {
            dimension(raw.min,.init(x:raw.max.x,y:raw.min.y),offset:38,color:.blue)
            dimension(.init(x:raw.max.x,y:raw.min.y),raw.max,offset:38,color:.blue)
        }
        for (i,p) in selection.spots.enumerated() {
            let s = v.screen(p), radius = max(4,selection.spotDiameter/2*v.scale)
            context.stroke(Path(ellipseIn:.init(x:s.x-radius,y:s.y-radius,width:radius*2,height:radius*2)),with:.color(.orange),lineWidth:2)
            if showSpots {
                dimension(.init(x:raw.min.x,y:p.y),p,offset:0,color:.orange)
                dimension(.init(x:p.x,y:raw.min.y),p,offset:0,color:.orange)
                let name = selection.spotLabels.indices.contains(i) ? selection.spotLabels[i] : "S\(i+1)"
                label("\(name) · Ø \(layoutCM(selection.spotDiameter))",at:.init(x:s.x,y:s.y-radius-12),color:.orange)
            }
        }
        if showRaw || showSpots || showCoordinates { label("0",at:v.screen(raw.min),color:.secondary) }
    }
}

struct LayoutContourPreview: View {
    let contours: [[LayoutPoint]]
    var numbered = false
    var alphabetic = false
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
                        let label = j == 0 ? (alphabetic ? vertexName(i) : "\(i + 1)") : "\(j).\(i + 1)"
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
    switch correction.severity() {
    case .none: return .secondary
    case .yellow: return .yellow
    case .orange: return .orange
    case .red: return .red
    }
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
                    LabeledContent("Correction", value: "\(correction.correctionDelta >= 0 ? "+" : "")\(layoutCM(correction.correctionDelta))")
                    LabeledContent("Différence", value: correction.percentage.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...2))) + " %")
                }
                Section {
                    if correction.severity() == .red {
                        Label("Écart important. Nous vous recommandons de vérifier et reprendre cette mesure sur chantier.", systemImage: "exclamationmark.octagon.fill")
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
            let transform = LayoutViewport(bounds:paddedBounds,size:proxy.size,zoom:1,pan:.zero)
            let surface = Surface2D(name:"Aperçu",kind:.wall,contour:contour,edgeTones:tones,dimensionCorrections:corrections)
            ZStack {
                Canvas { context,_ in
                    context.fill(layoutPath(contour,transform:transform),with:.color(.teal.opacity(0.08)))
                    for i in contour.indices {
                        let a = contour[i], b = contour[(i+1)%contour.count]
                        var side = Path(); side.move(to:transform.screen(a)); side.addLine(to:transform.screen(b))
                        context.stroke(side,with:.color(toneColor(tones.indices.contains(i) ? tones[i] : .blue)),lineWidth:3)
                        context.draw(Text(vertexName(i)).font(.caption.bold()).foregroundStyle(.primary),at:transform.screen(a),anchor:.bottomTrailing)
                    }
                }
                LayoutPolygonAnnotations(surface:surface,viewport:transform,showAngles:false,showDimensions:true,showsLocks:false) { selected in
                    if case .correction(let i) = selected, let correction = corrections.first(where:{$0.edgeIndex == i}) { onCorrection(correction) }
                }
            }
        }
    }
    private var paddedBounds:LayoutBounds {
        let b = LayoutBounds(points:contour), padding = max(b.width,b.height)*0.4
        return .init(min:b.min - .init(x:padding,y:padding),max:b.max + .init(x:padding,y:padding))
    }
}

struct LayoutSketchPad: View {
    let kind: LayoutSupportKind
    let onComplete: ([LayoutPoint]) -> Void
    @State private var stroke: [LayoutPoint] = []
    @State private var drawing = false
    @State private var closed = false
    @State private var message: String?
    @State private var zoom = 1.0
    @State private var pinching = false
    @State private var resumeAfterZoom = false
    @State private var previousStroke: [LayoutPoint] = []
    @State private var cameraBounds:LayoutBounds?
    @GestureState private var magnification = 1.0
    private let configuration = PolygonBeautificationConfiguration.standard
    var body: some View {
        GeometryReader { proxy in
            let viewport = LayoutViewport(bounds:cameraBounds ?? .init(min:.zero,max:.init(x:proxy.size.width,y:proxy.size.height)),size:proxy.size,zoom:min(8,max(0.4,zoom*magnification)),pan:.zero)
            Canvas { context, _ in
                var path = Path()
                if let first = stroke.first {
                    path.move(to: viewport.screen(first))
                    for point in stroke.dropFirst() { path.addLine(to: viewport.screen(point)) }
                    if closed { path.closeSubpath() }
                }
                context.stroke(path, with: .color(.teal), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let first = stroke.first {
                    let p = viewport.screen(first)
                    context.stroke(Path(ellipseIn:CGRect(x:p.x-12,y:p.y-12,width:24,height:24)),with:.color(.teal.opacity(0.5)),style:StrokeStyle(lineWidth:1,dash:[3,3]))
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if stroke.isEmpty { Text("Dessinez ici").foregroundStyle(.secondary) }
            }
            .overlay(alignment:.bottom) { if let message { Text(message).font(.footnote).foregroundStyle(.red).padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) } }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !pinching else { return }
                if !drawing {
                    previousStroke = stroke
                    let canResume = resumeAfterZoom && stroke.last.map { (viewport.world(value.startLocation)-$0).length * viewport.scale < 36 } == true
                    if !canResume { stroke = [] }
                    resumeAfterZoom = false; closed = false; message = nil; drawing = true
                }
                let point = viewport.world(value.location)
                if stroke.count < configuration.maximumSamples, stroke.last.map({ ($0 - point).length >= configuration.samplingDistance }) ?? true { stroke.append(point) }
            }.onEnded { value in
                guard drawing, !pinching else { return }
                drawing = false
                guard stroke.count < configuration.maximumSamples else {
                    message = "Ce tracé est trop long. Redessinez le contour en un geste plus court."
                    return
                }
                let end = viewport.world(value.location)
                if stroke.count < configuration.maximumSamples { stroke.append(end) }
                do {
                    let polygon = try LayoutStrokeBeautifier.polygon(from:stroke,kind:kind)
                    withAnimation(.easeOut(duration:0.18)) { stroke = polygon; closed = true }
                    onComplete(polygon)
                } catch { message = error.localizedDescription }
            })
            .simultaneousGesture(MagnifyGesture().updating($magnification) { value,state,_ in state = value.magnification }
                .onChanged { _ in
                    if !pinching {
                        pinching = true
                        if stroke.count < 3 { stroke = previousStroke }
                        drawing = false; resumeAfterZoom = !stroke.isEmpty
                        message = stroke.isEmpty ? nil : "Reprenez le trait depuis son extrémité pour continuer."
                    }
                }.onEnded { value in zoom = min(8,max(0.4,zoom*value.magnification)); pinching = false })
            .overlay(alignment:.topTrailing) {
                Button { cameraBounds = stroke.count > 1 ? LayoutViewport.fittedBounds(stroke,rotation:0) : nil; zoom = 1 } label: { Image(systemName:"scope").padding(12).background(.regularMaterial,in:Circle()) }
                    .padding(8).accessibilityLabel("Recentrer le dessin")
            }
            .overlay(alignment:.topLeading) { Text("Zoom × \((zoom*magnification).formatted(.number.precision(.fractionLength(1))))").font(.caption).padding(8).allowsHitTesting(false) }
            .clipped()
        }
        .accessibilityLabel("Zone de dessin du support, zoom à deux doigts")
    }
}
