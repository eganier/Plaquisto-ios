import SwiftUI

struct LayoutLivePreview: View {
    let surface: Surface2D
    let layer: LayoutLayer
    @State private var result: SheetLayoutResult?
    @State private var error: String?
    var body: some View {
        Canvas { context,size in
            let viewport = LayoutViewport(bounds:surface.bounds,size:size,zoom:1,pan:.zero)
            if let result {
                let geometry=LayoutPlanning.worldFurring(surface:surface,layer:layer)
                var mask=layoutPath(surface.contour,transform:viewport)
                for opening in surface.openings { mask.addPath(layoutPath(opening.contour,transform:viewport)) }
                context.drawLayer { steel in
                    steel.clip(to:mask,style:.init(eoFill:true))
                    LayoutPreciseStyle.drawProfiles(context:&steel,geometry:geometry,viewport:viewport)
                }
                for sheet in result.sheets { for piece in sheet.pieces {
                    var p = layoutPath(piece.contour.map(result.frame.world),transform:viewport)
                    for hole in piece.holes { p.addPath(layoutPath(hole.map(result.frame.world),transform:viewport)) }
                    let tint=sheet.number.isMultiple(of:2) ? Color(red:0.86,green:0.89,blue:0.91) : Color(red:0.98,green:0.985,blue:0.99)
                    context.fill(p,with:.color(tint.opacity(LayoutPreciseStyle.plateOpacity(focus:1))),style:.init(eoFill:true))
                    context.stroke(p,with:.color(LayoutPreciseStyle.ink),lineWidth:LayoutPreciseStyle.edgeWidth)
                } }
            }
            context.stroke(layoutPath(surface.contour,transform:viewport),with:.color(LayoutPreciseStyle.ink),lineWidth:LayoutPreciseStyle.edgeWidth)
            for (i,p) in surface.contour.enumerated() {
                let s = viewport.screen(p)
                context.draw(Text(vertexName(i)).font(.caption.bold()),at:.init(x:s.x-10,y:s.y-10))
            }
        }
        .overlay(alignment:.bottom) { if let error { Text(error).font(.caption).foregroundStyle(.orange) } }
        .task(id:layer) {
            let worker = Task.detached { try SheetLayoutEngine.calculate(surface:surface,layer:layer) }
            do {
                let value = try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                if !Task.isCancelled { result = value; error = nil }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; result = nil } }
        }
    }
}

struct LayoutFurringForm: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalogue: ToolTechnicalStore
    @Environment(\.interfacePresentation) private var presentation
    let surface: Surface2D
    let onSave: (LayoutLayer)->Void
    let allowsSimplifiedCeiling: Bool
    @State private var layer: LayoutLayer
    @State private var notice: String?
    private var simplifiedCeiling: Bool {
        presentation == .contrastLab && allowsSimplifiedCeiling && layer.furring?.allowsCeilingSupportControls(on:surface) == true
    }
    init(surface:Surface2D,layer:LayoutLayer,allowsSimplifiedCeiling:Bool = true,onSave:@escaping(LayoutLayer)->Void) {
        self.surface = surface; self.onSave = onSave
        self.allowsSimplifiedCeiling = allowsSimplifiedCeiling
        var copy = layer; if copy.furring == nil { copy.furring = .init() }
        copy.materializeFurringOrientation()
        copy = copy.forSupport(surface.kind)
        _layer = State(initialValue:copy)
    }
    private func binding<T>(_ key:WritableKeyPath<LayoutFurringSettings,T>) -> Binding<T> {
        .init(get:{(layer.furring ?? .init())[keyPath:key]},set:{value in
            notice = nil
            var f = layer.furring ?? .init(); f[keyPath:key] = value; layer.furring = f
        })
    }
    private var compatible: Bool { LayoutPlanning.compatibleSpacings(layer).contains(layer.furring?.spacing ?? 0) }
    private var formats: [LayoutCatalogFormat] {
        catalogue.layoutFormats.filter { f in
            var copy = layer; copy.sheetWidth = f.width; copy.sheetLength = f.length
            return LayoutPlanning.compatibleSpacings(copy).contains(copy.furring?.spacing ?? 0)
        }
    }
    var body: some View {
        NavigationStack {
            AtlantiqueForm {
                if !simplifiedCeiling {
                Section { LayoutLivePreview(surface:surface,layer:layer).frame(height:220) }
                if surface.kind == .ceiling { AtlantiqueSection("Orientation des fourrures") {
                    Picker("Sens des fourrures", selection: Binding(
                        get: { layer.resolvedFurringOrientation ?? .horizontal },
                        set: { layer.setFurringOrientation($0) }
                    )) {
                        Text("Horizontales").tag(LayoutOrientation.horizontal)
                        Text("Verticales").tag(LayoutOrientation.vertical)
                    }.pickerStyle(.segmented)
                } } else { Section { Label("Ossature verticale, perpendiculaire au sol",systemImage:"arrow.up") } }
                if surface.kind == .wall, let system=layer.furring?.openingSystem {
                    AtlantiqueSection("Encadrements des ouvertures") {
                        let geometry=LayoutPlanning.worldFurring(surface:surface,layer:layer)
                        Text("Renforts fixes à 5 cm des ouvertures (mesurés à l’axe). La trame mobile peut se caler et fusionner sur les renforts latéraux.").font(.footnote)
                        let horizontal=geometry.openingProfiles.filter { $0.role == .horizontal }.reduce(0.0) { $0+($1.line.end-$1.line.start).length/1000 }
                        LabeledContent(system == .furring ? "Cornières d’encadrement" : "Rails d’encadrement",value:"\(horizontal.formatted(.number.precision(.fractionLength(1)))) ml")
                        if system == .furring {
                            Text("Profils fixes à 12 cm des bords : fourrure à gauche, cornière à droite.").font(.caption).foregroundStyle(.secondary)
                            LabeledContent("Appuis intermédiaires sur le plan",value:"\(geometry.supportPoints.count)")
                            LabeledContent("Traverses horizontales",value:layer.furring?.includesHorizontalSupportFurring == false ? "Sans — fixation dans la maçonnerie" : "Selon les lignes d’appuis")
                            if layer.furring?.maximumSupportSpacing == nil {
                                Text("Hauteurs indicatives pour cet ancien ouvrage. Réenregistrez son formulaire pour récupérer la règle d’appuis du catalogue.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if layer.furring?.isFurringSystem != false && (surface.kind == .ceiling || layer.furring?.openingSystem == .furring) {
                    AtlantiqueSection("Raccords des fourrures") {
                        LabeledContent("Éclisses sur le plan",value:"\(LayoutPlanning.worldFurring(surface:surface,layer:layer).furringSpliceCount)")
                        Text("Une éclisse à chaque raccord de longueurs de 3 m, par tronçon continu.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
                Section(surface.kind == .wall ? "Entraxe de l’ossature" : "Entraxe des fourrures") {
                    Picker("Entraxe",selection:binding(\.spacing)) {
                        Text("40 cm").tag(400.0)
                        if !atlantique || layer.furring?.spacing == 500 { Text("50 cm").tag(500.0) }
                        Text("60 cm").tag(600.0)
                    }.pickerStyle(.segmented)
                    if let notice { Label(notice,systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    if !compatible {
                        Label("Format de plaque incompatible avec cet entraxe. Choisissez un format compatible ci-dessous.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                        ForEach(formats.prefix(12)) { format in
                            Button(format.label) { layer.sheetWidth = format.width; layer.sheetLength = format.length; layer.catalogFormatID = format.id; layer.manualFacing = false; layer.fourTaperedEdges = format.fourTaperedEdges }
                        }
                        if formats.isEmpty { Text("Aucun format compatible chargé. Modifiez le format dans Plaques.").font(.footnote) }
                    }
                }
                if simplifiedCeiling {
                    AtlantiqueSection("Périphérie") {
                        Picker("Appui en périphérie",selection:Binding(
                            get:{layer.furring?.resolvedCeilingPerimeterSupport ?? true},
                            set:{layer.furring?.setCeilingPerimeterSupport($0)}
                        )) {
                            Text("Cornière périphérique").tag(true)
                            Text("2 fourrures à 10 cm des bords").tag(false)
                        }.pickerStyle(.inline).labelsHidden()
                            .accessibilityIdentifier("layout.furring.periphery")
                    }
                    AtlantiqueSection("Suspentes") {
                        LayoutDimensionField(title: "Entraxe des suspentes", millimetres: Binding(
                            get:{layer.furring?.resolvedCeilingSuspensionSpacing ?? 1200},
                            set:{layer.furring?.ceilingSuspensionSpacing = $0}
                        )).accessibilityLabel("Entraxe des suspentes")
                            .accessibilityIdentifier("layout.furring.suspensionSpacing")
                    }
                } else {
                AtlantiqueSection("Calage sur les plaques") {
                    Button("Caler les fourrures sur le calepinage des plaques") { layer = LayoutPlanning.alignFurring(to:layer) }
                    Text(LayoutPlanning.aligned(layer) ? "Trames alignées." : "Trames décalées : les fourrures ne tombent pas toutes sur les joints attendus.").font(.footnote)
                }
                Section {
                    Text("Compatibilité géométrique des joints uniquement. L’entraxe admissible selon le parement et l’isolant doit être vérifié dans les outils techniques.").font(.footnote).foregroundStyle(.secondary)
                    Button("Retirer les fourrures",role:.destructive) { layer.furring = nil; onSave(layer); dismiss() }
                }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(surface.kind == .wall ? "Ossature" : "Fourrures").navigationBarTitleDisplayMode(.inline)
            .atlantiqueFormPage("Ossature")
            .onAppear {
                if !compatible, let spacing = LayoutPlanning.compatibleSpacings(layer).max() {
                    layer.furring?.spacing = spacing
                    notice = "Attention : passage à \(layoutCM(spacing)) d’entraxe pour correspondre aux plaques."
                }
            }
            .onChange(of:layer.furring?.orientation) { _,_ in
                if !compatible, let spacing = LayoutPlanning.compatibleSpacings(layer).max() {
                    layer.furring?.spacing = spacing
                    notice = "Attention : passage à \(layoutCM(spacing)) d’entraxe pour ce sens de pose."
                }
            }
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Appliquer") { onSave(layer); dismiss() }.disabled(!compatible || (simplifiedCeiling && !(200...1200).contains(layer.furring?.ceilingSuspensionSpacing ?? 1200))) }
            }
        }
    }
}

struct LayoutLightingSpacingForm: View {
    @Environment(\.dismiss) private var dismiss
    let surface:Surface2D
    let layer:LayoutLayer
    let lighting:LayoutLighting
    let selected:Set<Int>
    let onSave:(LayoutLighting)->Void
    @State private var factor = 1.0
    @State private var lengthFactor = 1.0
    private var preview:LayoutLighting {
        guard surface.kind == .ceiling else { return LayoutPlanning.scaledLighting(lighting,selected:selected,factor:factor) }
        var frame = LayoutPlanning.framingFrame(surface:surface,layer:layer)
        if lighting.perpendicularToFurring == true { frame.angle += .pi/2 }
        return LayoutPlanning.scaledLighting(lighting,selected:selected,widthFactor:factor,lengthFactor:lengthFactor,frame:frame)
    }
    private var valid:Bool { LayoutPlanning.lightingFits(preview,surface:surface) }
    var body:some View {
        NavigationStack {
            AtlantiqueForm {
                Section {
                    ZStack {
                        LayoutLivePreview(surface:surface,layer:layer)
                        Canvas { context,size in
                            let viewport = LayoutViewport(bounds:surface.bounds,size:size,zoom:1,pan:.zero)
                            for (i,point) in preview.positions.enumerated() {
                                let p = viewport.screen(point), color:Color = selected.contains(i) ? .orange : .secondary
                                context.fill(Path(ellipseIn:.init(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(color))
                                context.draw(Text(preview.label(at:i,wall:surface.kind == .wall)).font(.caption2.bold()).foregroundStyle(color),at:.init(x:p.x,y:p.y-14))
                            }
                        }
                    }.frame(height:280)
                }
                AtlantiqueSection("Écartement de \(selected.count) points") {
                    LabeledContent(surface.kind == .ceiling ? "Largeur" : "Écartement",value:"× \(factor.formatted(.number.precision(.fractionLength(2))))")
                    Slider(value:$factor,in:0.25...3).accessibilityLabel(surface.kind == .ceiling ? "Écartement en largeur" : "Multiplier l’écartement du groupe")
                    if surface.kind == .ceiling {
                        LabeledContent("Longueur",value:"× \(lengthFactor.formatted(.number.precision(.fractionLength(2))))")
                        Slider(value:$lengthFactor,in:0.25...3).accessibilityLabel("Écartement en longueur")
                    }
                    Text("Vers la gauche pour rapprocher, vers la droite pour écarter. Le centre du groupe reste fixe.").font(.footnote).foregroundStyle(.secondary)
                    if !valid { Label("Le groupe rencontre un bord, une ouverture ou un autre point. Réduisez l’écartement.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
                    Button("Revenir à l’écartement initial") { factor = 1; lengthFactor = 1 }
                }
            }
            .navigationTitle("Régler l’écartement").atlantiqueFormPage("Régler l’écartement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Appliquer") { onSave(preview); dismiss() }.disabled(!valid) }
            }
        }
    }
}

struct LayoutWallElectricalForm: View {
    @Environment(\.dismiss) private var dismiss
    let surface:Surface2D
    let layer:LayoutLayer
    let onSave:(LayoutLighting?)->Void
    @State private var lighting:LayoutLighting?
    @State private var kind = LayoutElectricalKind.socket
    @State private var count = 3
    @State private var height = 0.0
    @State private var error:String?
    init(surface:Surface2D,layer:LayoutLayer,lighting:LayoutLighting?,onSave:@escaping(LayoutLighting?)->Void) {
        self.surface = surface; self.layer = layer; self.onSave = onSave; _lighting = State(initialValue:lighting)
    }
    var body:some View {
        NavigationStack {
            AtlantiqueForm {
                Section {
                    ZStack {
                        LayoutLivePreview(surface:surface,layer:layer)
                        Canvas { context,size in
                            let v = LayoutViewport(bounds:surface.bounds,size:size,zoom:1,pan:.zero)
                            for height in LayoutWallLighting.heights(lighting,surface:surface) {
                                for segment in LayoutWallLighting.rowSegments(height:height,surface:surface) {
                                    var path=Path(); path.move(to:v.screen(segment.start)); path.addLine(to:v.screen(segment.end))
                                    context.stroke(path,with:.color(.orange.opacity(0.6)),style:.init(lineWidth:1,dash:[4,4]))
                                }
                            }
                            if let lighting {
                                for (i,p) in lighting.positions.enumerated() {
                                    let s = v.screen(p), color:Color = lighting.kind(at:i) == .socket ? .blue : .orange
                                    context.fill(Path(ellipseIn:.init(x:s.x-5,y:s.y-5,width:10,height:10)),with:.color(color))
                                    context.draw(Text(lighting.label(at:i,wall:true)).font(.caption2.bold()).foregroundStyle(color),at:.init(x:s.x,y:s.y-14))
                                }
                            }
                        }
                    }.frame(height:220)
                    Text("P : prise · L : lumière. Les hauteurs sont mesurées au centre du point depuis le bas du mur (sol).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                AtlantiqueSection("Ajouter une rangée") {
                    LayoutDimensionField(title:"Hauteur depuis le sol",millimetres:$height)
                    Button("Créer la rangée",systemImage:"plus.circle") {
                        do { lighting=try LayoutWallLighting.addingRow(lighting,height:height,surface:surface); error=nil }
                        catch { self.error=error.localizedDescription }
                    }.disabled(height<=0)
                }
                if !LayoutWallLighting.heights(lighting,surface:surface).isEmpty {
                    AtlantiqueSection("Rangées") {
                        ForEach(LayoutWallLighting.heights(lighting,surface:surface),id:\.self) { row in
                            Button { height=row } label: {
                                LabeledContent("Hauteur depuis le sol",value:layoutCM(row))
                            }
                        }
                        .onDelete { offsets in
                            let rows=LayoutWallLighting.heights(lighting,surface:surface)
                            lighting?.wallRowHeights=rows.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
                        }
                        Text("Appliquez, puis ajoutez vos points sur le plan : ils s’aimantent à ces hauteurs.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                AtlantiqueSection("Répartir des points à cette hauteur") {
                    Picker("Équipement",selection:$kind) { ForEach(LayoutElectricalKind.allCases,id:\.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                    Stepper("\(count) point(s) aligné(s)",value:$count,in:1...min(64,max(1,64-(lighting?.count ?? 0))))
                    Button("Ajouter les points à \(layoutCM(height))",systemImage:"plus.circle") {
                        do { lighting = try LayoutPlanning.addingWallRow(to:lighting,count:count,height:height,kind:kind,surface:surface); error = nil }
                        catch { self.error = "Cette rangée rencontre un bord, une ouverture ou un autre point. Modifiez la hauteur ou le nombre, ou ajoutez les points un à un sur le plan." }
                    }.disabled(height <= 0 || (lighting?.count ?? 0)+count > 64)
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                if let lighting {
                    AtlantiqueSection("Implantation") {
                        LabeledContent("Points positionnés",value:"\(lighting.count)")
                        Text("Ajoutez une autre rangée à une autre hauteur, ou appliquez pour déplacer et aligner les points directement sur le plan.").font(.footnote)
                        Button("Effacer les points",role:.destructive) {
                            var copy=lighting
                            copy.wallRowHeights=LayoutWallLighting.heights(lighting,surface:surface)
                            copy.positions=[]; copy.kinds=[]; copy.count=0
                            self.lighting=copy
                        }.disabled(lighting.positions.isEmpty)
                    }
                }
                Section { Text("Plan géométrique d’implantation, sans validation des règles électriques ni des distances réglementaires.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Prises et lumières").atlantiqueFormPage("Prises et lumières").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Appliquer") { onSave(lighting); dismiss() } }
            }
        }
    }
}

struct LayoutWallPointForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    let lighting: LayoutLighting
    let index: Int
    let surface: Surface2D
    let onSave: (LayoutLighting)->Void
    @State private var fromRight = false
    @State private var distance: Double
    @State private var point: LayoutPoint
    @State private var dimensionID = 0
    @State private var error: String?
    init(lighting: LayoutLighting, index: Int, surface: Surface2D, onSave: @escaping(LayoutLighting)->Void) {
        self.lighting = lighting; self.index = index; self.surface = surface; self.onSave = onSave
        let point = lighting.positions[index]
        _point = State(initialValue: point)
        _distance = State(initialValue: point.x - (LayoutWallLighting.span(at: point, surface: surface)?.start.x ?? surface.bounds.min.x))
    }
    private var dimensions: [LayoutPlacementDimensions.Dimension] {
        LayoutPlacementDimensions.dimensions(contour: surface.contour, center: point)
    }
    private var dimensionBinding: Binding<Double> {
        Binding(get: { dimensions.first { $0.id == dimensionID }?.distance ?? 0 }, set: { value in
            guard let dimension = dimensions.first(where: { $0.id == dimensionID }),
                  let moved = LayoutPlacementDimensions.movedCenter(point, dimension: dimension, distance: value) else { return }
            point = moved; error = nil
        })
    }
    var body: some View {
        NavigationStack {
            AtlantiqueForm {
                if atlantique {
                    Section { preview.frame(height: 300) }
                    Section {
                        Picker("Cote", selection: $dimensionID) { ForEach(dimensions) { Text($0.label).tag($0.id) } }.pickerStyle(.segmented)
                        if dimensions.contains(where: { $0.id == dimensionID }) {
                            LayoutDimensionField(title: "Distance " + ["A", "B", "C", "D"][dimensionID], millimetres: dimensionBinding)
                        }
                    }
                } else {
                    LabeledContent("Hauteur depuis le sol", value: layoutCM(lighting.positions[index].y - surface.bounds.min.y))
                    Picker("Mesurer depuis", selection: $fromRight) {
                        Text("Bord gauche").tag(false); Text("Bord droit").tag(true)
                    }.pickerStyle(.segmented)
                    .onChange(of: fromRight) { _, _ in
                        if let limits = LayoutWallLighting.span(at: lighting.positions[index], surface: surface) {
                            distance = (limits.end.x - limits.start.x) - distance
                        }
                    }
                    LayoutDimensionField(title: fromRight ? "Distance depuis la droite" : "Distance depuis la gauche", millimetres: $distance)
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Position de \(lighting.label(at: index, wall: true))")
            .atlantiqueFormPage("Électricité").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        do {
                            if atlantique {
                                onSave(try LayoutWallLighting.positioning(lighting, index: index, point: point, surface: surface))
                            } else {
                                onSave(try LayoutWallLighting.positioning(lighting, index: index, distance: distance, fromRight: fromRight, surface: surface))
                            }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
    private var preview: some View {
        Canvas { context, size in
            let bounds = surface.bounds
            let scale = min((size.width - 40) / max(bounds.width, 1), (size.height - 40) / max(bounds.height, 1))
            func screen(_ p: LayoutPoint) -> CGPoint { .init(x: size.width / 2 + (p.x - bounds.center.x) * scale, y: size.height / 2 - (p.y - bounds.center.y) * scale) }
            var path = Path()
            if let first = surface.contour.first {
                path.move(to: screen(first))
                for p in surface.contour.dropFirst() { path.addLine(to: screen(p)) }
                path.closeSubpath()
            }
            context.stroke(path, with: .color(Atlantique.Palette.ink), lineWidth: 2)
            for dimension in dimensions {
                var line = Path(); line.move(to: screen(dimension.start)); line.addLine(to: screen(dimension.end))
                context.stroke(line, with: .color(Atlantique.Palette.ink.opacity(0.5)), lineWidth: 1)
                context.draw(Text("\(dimension.label) · \(layoutCM(dimension.distance))").font(.caption.bold()), at: screen((dimension.start + dimension.end) * 0.5))
            }
            for i in lighting.positions.indices {
                let p = screen(i == index ? point : lighting.positions[i])
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(i == index ? Atlantique.Palette.actionInk : .gray))
            }
        }
    }
}

struct LayoutFurringDistanceForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var value:Double
    let onSave:(Double)throws->Void
    @State private var error:String?
    var body:some View {
        NavigationStack {
            AtlantiqueForm {
                LayoutDimensionField(title:"Distance mur / fourrure",millimetres:$value)
                Text("La trame se déplace en conservant l’entraxe. Les fourrures périphériques à 10 cm restent fixes.").font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Positionner les fourrures").atlantiqueFormPage("Positionner les fourrures").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) {
                        Button("Valider") {
                            do { try onSave(value); dismiss() }
                            catch { self.error="Cette distance ne place pas une fourrure mobile dans le plafond. Vérifiez la valeur et le contour." }
                        }
                    }
                }
        }
    }
}

struct LayoutLightingForm: View {
    private struct PreviewKey: Equatable { var settings:LayoutLighting; var generation:Int }
    @State private var regenerate = 0
    @State private var lastRegeneration = 0
    @Environment(\.dismiss) private var dismiss
    let surface: Surface2D
    let layer: LayoutLayer
    let onSave: (LayoutLighting?)->Void
    @State private var settings: LayoutLighting
    @State private var preview: LayoutLighting?
    @State private var error: String?
    @State private var hasLoaded = false
    @State private var groupOrigin: LayoutLighting?
    @State private var placementCenter: LayoutPoint?
    @State private var generation = 0
    @State private var lastSettings: LayoutLighting?
    init(surface:Surface2D,layer:LayoutLayer,settings:LayoutLighting?,onSave:@escaping(LayoutLighting?)->Void) {
        self.surface = surface; self.layer = layer; self.onSave = onSave
        _settings = State(initialValue:settings ?? .init())
    }
    var body: some View {
        NavigationStack {
            GeometryReader { container in
                VStack(spacing:8) {
                    GeometryReader { proxy in
                    ZStack {
                        LayoutLivePreview(surface:surface,layer:layer)
                        Canvas { context,size in
                            let v = LayoutViewport(bounds:surface.bounds,size:size,zoom:1,pan:.zero)
                            for (i,p) in (preview?.positions ?? []).enumerated() {
                                let s = v.screen(p)
                                context.fill(Path(ellipseIn:.init(x:s.x-5,y:s.y-5,width:10,height:10)),with:.color(.orange))
                                context.draw(Text("\(i+1)").font(.caption2.bold()),at:.init(x:s.x,y:s.y-13))
                            }
                        }.allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .highPriorityGesture(DragGesture(minimumDistance:3).onChanged { value in
                        guard let preview else { return }
                        if groupOrigin == nil { groupOrigin = preview }
                        guard let original = groupOrigin else { return }
                        let v = LayoutViewport(bounds:surface.bounds,size:proxy.size,zoom:1,pan:.zero)
                        let delta = LayoutPoint(x:value.translation.width/v.scale,y: -value.translation.height/v.scale)
                        self.preview = LayoutPlanning.translatedLighting(original,indices:Set(original.positions.indices),delta:delta)
                    }.onEnded { _ in
                        guard groupOrigin != nil else { return }
                        if let current = preview, LayoutPlanning.lightingFits(current,surface:surface) {
                            placementCenter = center(current); error = nil
                        } else { preview = groupOrigin; error = LayoutLightingEditError.invalidPlacement.localizedDescription }
                        groupOrigin = nil
                    })
                    }.frame(height:min(320,max(150,container.size.height*0.40)))
                        .background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))
                        .clipShape(RoundedRectangle(cornerRadius:24)).padding(.horizontal)
                    Text("Glissez sur le dessin pour déplacer les spots.")
                        .font(.caption).foregroundStyle(.secondary)
                AtlantiqueForm {
                AtlantiqueSection("Répartition des spots") {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:58))]) {
                        ForEach(LayoutPlanning.automaticSpotCounts,id:\.self) { count in
                            Button {
                                settings.count=count; settings.positions=[]
                                placementCenter=nil
                                regenerate += 1
                            } label: {
                                VStack(spacing:4) {
                                    Canvas { context,size in
                                        for p in LayoutPlanning.spotPattern(count,twelve:settings.twelveSpotGrid ?? .sixByTwo) ?? [] {
                                            let x=size.width/2+p.x*size.width*0.3, y=size.height/2+p.y*size.height*0.3
                                            let radius=Double(count >= 10 ? 2 : 3)
                                            context.fill(Path(ellipseIn:.init(x:x-radius,y:y-radius,width:radius*2,height:radius*2)),with:.color(.primary))
                                        }
                                    }.frame(width:38,height:32)
                                    Text("\(count)")
                                }.frame(maxWidth:.infinity).padding(5)
                                    .background(settings.count == count ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill),in:RoundedRectangle(cornerRadius:9))
                            }.buttonStyle(.plain).accessibilityLabel("Disposition de \(count) spots")
                        }
                    }
                    if settings.count == 12 {
                        Picker("Disposition",selection:Binding(get:{ settings.twelveSpotGrid ?? .sixByTwo },set:{ settings.twelveSpotGrid = $0 })) {
                            ForEach(LayoutTwelveSpotGrid.allCases,id:\.self) { grid in Text(grid.title).tag(grid) }
                        }.pickerStyle(.segmented)
                    }
                    Button {
                        settings.perpendicularToFurring = !(settings.perpendicularToFurring ?? false)
                    } label: {
                        Label(settings.perpendicularToFurring == true ? "90° · Perpendiculaire aux fourrures" : "90° · Dans le sens des fourrures",systemImage:"rotate.right")
                    }
                    if settings.count > 1 {
                        Text("Écartement en largeur")
                        Slider(value:Binding(get:{ settings.resolvedWidthSpread },set:{ settings.widthSpread = $0 }),in:0.2...1.2)
                            .accessibilityLabel("Écartement en largeur")
                        Text("Écartement en longueur")
                        Slider(value:Binding(get:{ settings.resolvedLengthSpread },set:{ settings.lengthSpread = $0 }),in:0.2...1.2)
                            .accessibilityLabel("Écartement en longueur")
                        Text("Les deux écartements suivent les axes de la disposition. Ils conservent vos déplacements manuels.").font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Diamètre du perçage",value:"\(settings.diameter.formatted(.number.precision(.fractionLength(0)))) mm")
                    Text("Choisissez une disposition pour recréer une grille. Vous pouvez ensuite déplacer chaque spot sur le plan.").font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.orange) }
                }
                Section { Button("Retirer l’éclairage",role:.destructive) { onSave(nil); dismiss() } }
                }
                }
            }.background(Color(.systemGroupedBackground))
                .navigationTitle("Répartition automatique").atlantiqueFormPage("Répartition automatique").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .task(id:PreviewKey(settings:settings,generation:regenerate)) {
                    let fresh = lastRegeneration != regenerate
                    lastRegeneration=regenerate
                    await update(preserveExisting:!fresh)
                }
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Appliquer") { if let preview { onSave(preview); dismiss() } }.disabled(preview == nil || groupOrigin != nil || preview.map{ !LayoutPlanning.lightingFits($0,surface:surface) } == true) }
                }
        }
    }
    private func center(_ lighting:LayoutLighting) -> LayoutPoint {
        lighting.positions.reduce(.zero,+)*(1/Double(max(1,lighting.positions.count)))
    }
    private func update(preserveExisting:Bool) async {
        generation += 1
        let revision = generation
        let previousSettings = lastSettings
        lastSettings = settings
        if !hasLoaded {
            hasLoaded = true
            if !settings.positions.isEmpty {
                preview = settings; placementCenter = center(settings)
                error = LayoutPlanning.lightingFits(settings,surface:surface) ? nil : LayoutLightingEditError.invalidPlacement.localizedDescription
                return
            }
        }
        if preserveExisting, let previousSettings, previousSettings.count == settings.count,
           previousSettings.twelveSpotGrid == settings.twelveSpotGrid, let existing = preview {
            let current = LayoutPlanning.adjustedLighting(existing,from:previousSettings,to:settings,
                frame:LayoutPlanning.framingFrame(surface:surface,layer:layer))
            preview = current
            error = LayoutPlanning.lightingFits(current,surface:surface) ? nil : LayoutLightingEditError.invalidPlacement.localizedDescription
            return
        }
        preview = nil
        do { try await Task.sleep(nanoseconds:80_000_000) } catch { return }
        let input = settings, support = surface, framing=layer
        let worker = Task.detached(priority:.userInitiated) { Result { try LayoutPlanning.lighting(input,surface:support,layer:framing) } }
        let result = await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
        guard !Task.isCancelled, revision == generation, settings == input else { return }
        switch result {
        case .success(let value):
            let adjusted = preserveExisting ? placementCenter.map { LayoutPlanning.translatedLighting(value,indices:Set(value.positions.indices),delta:$0-center(value)) } ?? value : value
            preview = adjusted
            error = LayoutPlanning.lightingFits(adjusted,surface:surface) ? nil : "Le groupe dépasse le plafond ou une ouverture : déplacez-le sur l’aperçu, ou recentrez la répartition."
        case .failure: preview = nil; error = "Impossible de placer tous les spots avec cet écartement et ce diamètre. Réduisez l’écartement ou le nombre."
        }
    }
}
