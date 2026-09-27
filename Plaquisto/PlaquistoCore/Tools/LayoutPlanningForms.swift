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
                for sheet in result.sheets { for piece in sheet.pieces {
                    var p = layoutPath(piece.contour.map(result.frame.world),transform:viewport)
                    for hole in piece.holes { p.addPath(layoutPath(hole.map(result.frame.world),transform:viewport)) }
                    context.fill(p,with:.color(.teal.opacity(sheet.number%2 == 0 ? 0.25 : 0.1)),style:.init(eoFill:true))
                    context.stroke(p,with:.color(.teal),lineWidth:0.8)
                } }
                for line in result.furring.lines {
                    var p = Path(); p.move(to:viewport.screen(result.frame.world(line.start))); p.addLine(to:viewport.screen(result.frame.world(line.end)))
                    context.stroke(p,with:.color(.purple),style:.init(lineWidth:1,dash:[4,3]))
                }
            }
            context.stroke(layoutPath(surface.contour,transform:viewport),with:.color(.primary),lineWidth:1.5)
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalogue: ToolTechnicalStore
    let surface: Surface2D
    let onSave: (LayoutLayer)->Void
    @State private var layer: LayoutLayer
    @State private var notice: String?
    init(surface:Surface2D,layer:LayoutLayer,onSave:@escaping(LayoutLayer)->Void) {
        self.surface = surface; self.onSave = onSave
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
            Form {
                Section { LayoutLivePreview(surface:surface,layer:layer).frame(height:220) }
                if surface.kind == .ceiling { Section("Orientation des fourrures") {
                    Picker("Sens des fourrures", selection: Binding(
                        get: { layer.resolvedFurringOrientation ?? .horizontal },
                        set: { layer.setFurringOrientation($0) }
                    )) {
                        Text("Horizontales").tag(LayoutOrientation.horizontal)
                        Text("Verticales").tag(LayoutOrientation.vertical)
                    }.pickerStyle(.segmented)
                } } else { Section { Label("Ossature verticale, perpendiculaire au sol",systemImage:"arrow.up") } }
                Section(surface.kind == .wall ? "Entraxe de l’ossature" : "Entraxe des fourrures") {
                    Picker("Entraxe",selection:binding(\.spacing)) {
                        Text("40 cm").tag(400.0); Text("50 cm").tag(500.0); Text("60 cm").tag(600.0)
                    }.pickerStyle(.segmented)
                    if let notice { Label(notice,systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    if !compatible {
                        Label("Format de plaque incompatible avec cet entraxe. Choisissez un format compatible ci-dessous.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                        ForEach(formats.prefix(12)) { format in
                            Button(format.label) { layer.sheetWidth = format.width; layer.sheetLength = format.length; layer.catalogFormatID = format.id }
                        }
                        if formats.isEmpty { Text("Aucun format compatible chargé. Modifiez le format dans Plaques.").font(.footnote) }
                    }
                }
                Section("Calage sur les plaques") {
                    Button("Caler les fourrures sur le calepinage des plaques") { layer = LayoutPlanning.alignFurring(to:layer) }
                    Text(LayoutPlanning.aligned(layer) ? "Trames alignées." : "Trames décalées : les fourrures ne tombent pas toutes sur les joints attendus.").font(.footnote)
                }
                Section {
                    Text("Compatibilité géométrique des joints uniquement. L’entraxe admissible selon le parement et l’isolant doit être vérifié dans les outils techniques.").font(.footnote).foregroundStyle(.secondary)
                    Button("Retirer les fourrures",role:.destructive) { layer.furring = nil; onSave(layer); dismiss() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(surface.kind == .wall ? "Ossature" : "Fourrures").navigationBarTitleDisplayMode(.inline)
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
                ToolbarItem(placement:.confirmationAction) { Button("Appliquer") { onSave(layer); dismiss() }.disabled(!compatible) }
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
    private var preview:LayoutLighting { LayoutPlanning.scaledLighting(lighting,selected:selected,factor:factor) }
    private var valid:Bool { LayoutPlanning.lightingFits(preview,surface:surface) }
    var body:some View {
        NavigationStack {
            Form {
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
                Section("Écartement de \(selected.count) points") {
                    Slider(value:$factor,in:0.25...3).accessibilityLabel("Multiplier l’écartement du groupe")
                    LabeledContent("Écartement",value:"× \(factor.formatted(.number.precision(.fractionLength(2))))")
                    Text("Vers la gauche pour rapprocher, vers la droite pour écarter. Le centre du groupe et les positions relatives sont conservés.").font(.footnote).foregroundStyle(.secondary)
                    if !valid { Label("Le groupe rencontre un bord, une ouverture ou un autre point. Réduisez l’écartement.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
                    Button("Revenir à l’écartement initial") { factor = 1 }
                }
            }
            .navigationTitle("Régler l’écartement").navigationBarTitleDisplayMode(.inline)
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
            Form {
                Section {
                    ZStack {
                        LayoutLivePreview(surface:surface,layer:layer)
                        Canvas { context,size in
                            let v = LayoutViewport(bounds:surface.bounds,size:size,zoom:1,pan:.zero)
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
                Section("Ajouter une rangée") {
                    Picker("Équipement",selection:$kind) { ForEach(LayoutElectricalKind.allCases,id:\.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                    Stepper("\(count) point(s) aligné(s)",value:$count,in:1...min(64,max(1,64-(lighting?.count ?? 0))))
                    LayoutDimensionField(title:"Hauteur depuis le sol",millimetres:$height)
                    Button("Ajouter la rangée à cette hauteur",systemImage:"plus.circle") {
                        do { lighting = try LayoutPlanning.addingWallRow(to:lighting,count:count,height:height,kind:kind,surface:surface); error = nil }
                        catch { self.error = "Cette rangée rencontre un bord, une ouverture ou un autre point. Modifiez la hauteur ou le nombre, ou ajoutez les points un à un sur le plan." }
                    }.disabled(height <= 0 || (lighting?.count ?? 0)+count > 64)
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                if let lighting {
                    Section("Implantation") {
                        LabeledContent("Points positionnés",value:"\(lighting.count)")
                        Text("Ajoutez une autre rangée à une autre hauteur, ou appliquez pour déplacer et aligner les points directement sur le plan.").font(.footnote)
                        Button("Effacer les points",role:.destructive) { self.lighting = nil }
                    }
                }
                Section { Text("Plan géométrique d’implantation, sans validation des règles électriques ni des distances réglementaires.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Prises et lumières").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Appliquer") { onSave(lighting); dismiss() } }
            }
        }
    }
}

struct LayoutLightingForm: View {
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
    @State private var rotationOriginal: LayoutLighting?
    @State private var rotationLatch: Double?
    @State private var rotationDelta = 0.0
    @State private var placementRotation = 0.0
    @AppStorage("layout.snapSpots") private var snapSpots = true
    init(surface:Surface2D,layer:LayoutLayer,settings:LayoutLighting?,onSave:@escaping(LayoutLighting?)->Void) {
        self.surface = surface; self.layer = layer; self.onSave = onSave; _settings = State(initialValue:settings ?? .init())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                        guard rotationOriginal == nil else { return }
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
                    .simultaneousGesture(RotationGesture().onChanged { angle in
                        if rotationOriginal == nil {
                            if let original = groupOrigin { preview = original; groupOrigin = nil }
                            rotationOriginal = preview
                        }
                        guard let original = rotationOriginal else { return }
                        let selected = Set(original.positions.indices)
                        let snap = snapSpots ? LayoutPlanning.snappedLightingRotation(-angle.radians,lighting:original,selected:selected,contour:surface.contour,latched:rotationLatch) : (angle:-angle.radians,latch:nil)
                        if snap.latch != nil && rotationLatch == nil { UISelectionFeedbackGenerator().selectionChanged() }
                        rotationDelta = snap.angle; rotationLatch = snap.latch
                        preview = LayoutPlanning.rotatedLighting(original,selected:selected,angle:snap.angle)
                    }.onEnded { _ in
                        if let current = preview, LayoutPlanning.lightingFits(current,surface:surface) {
                            placementRotation += rotationDelta; placementCenter = center(current); error = nil
                        } else { preview = rotationOriginal; error = LayoutLightingEditError.invalidPlacement.localizedDescription }
                        rotationOriginal = nil; rotationLatch = nil; rotationDelta = 0
                    })
                    }.frame(height:230)
                    Label("Glissez pour déplacer le groupe. Tournez avec deux doigts pour l’orienter.",systemImage:"hand.draw").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Aimantation sur les côtés",isOn:$snapSpots)
                    if rotationLatch != nil { Text("Spots alignés sur un côté").font(.caption).foregroundStyle(.orange) }
                }
                Section("Répartition des spots") {
                    Stepper("Nombre de spots : \(settings.count)",value:$settings.count,in:1...64)
                    LayoutDimensionField(title:"Diamètre du perçage",millimetres:$settings.diameter,unit:"mm",displayScale:1)
                    Text("Écarter les spots")
                    Slider(value:$settings.spread,in:0.2...1.2).accessibilityLabel("Écartement des spots")
                    Button("Centrer tous les spots") {
                        guard let current = preview else { return }
                        do {
                            let centered = try LayoutPlanning.centeredLighting(current,selected:Set(current.positions.indices),surface:surface)
                            preview = centered; placementCenter = center(centered); error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                    Text("L’écartement rapproche ou éloigne vos spots sans refaire leur disposition. Seul un changement du nombre recrée une répartition régulière.").font(.footnote).foregroundStyle(.secondary)
                    Text("Répartition régulière si la forme le permet. Les ouvertures et les bords sont exclus. Aucun calcul électrique ou photométrique.").font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.orange) }
                }
                Section { Button("Retirer l’éclairage",role:.destructive) { onSave(nil); dismiss() } }
            }.navigationTitle("Éclairage").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .task(id:settings) { await update(preserveExisting:true) }
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Appliquer") { if let preview { onSave(preview); dismiss() } }.disabled(preview == nil || groupOrigin != nil || rotationOriginal != nil || preview.map{ !LayoutPlanning.lightingFits($0,surface:surface) } == true) }
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
                placementRotation = (LayoutPlanning.lightingDirection(settings,selected:Set(settings.positions.indices)) ?? 0).truncatingRemainder(dividingBy:.pi/2)
                error = LayoutPlanning.lightingFits(settings,surface:surface) ? nil : LayoutLightingEditError.invalidPlacement.localizedDescription
                return
            }
        }
        if preserveExisting, let previousSettings, previousSettings.count == settings.count, var current = preview {
            if previousSettings.spread > 0 && previousSettings.spread != settings.spread {
                current = LayoutPlanning.scaledLighting(current,selected:Set(current.positions.indices),factor:settings.spread/previousSettings.spread)
            }
            current.diameter = settings.diameter
            current.spread = settings.spread
            preview = current
            error = LayoutPlanning.lightingFits(current,surface:surface) ? nil : LayoutLightingEditError.invalidPlacement.localizedDescription
            return
        }
        preview = nil
        do { try await Task.sleep(nanoseconds:80_000_000) } catch { return }
        let input = settings, support = surface
        let worker = Task.detached(priority:.userInitiated) { Result { try LayoutPlanning.lighting(input,surface:support) } }
        let result = await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
        guard !Task.isCancelled, revision == generation, settings == input else { return }
        switch result {
        case .success(let value):
            let rotated = LayoutPlanning.rotatedLighting(value,selected:Set(value.positions.indices),angle:placementRotation)
            let adjusted = preserveExisting ? placementCenter.map { LayoutPlanning.translatedLighting(rotated,indices:Set(rotated.positions.indices),delta:$0-center(rotated)) } ?? rotated : rotated
            preview = adjusted
            error = LayoutPlanning.lightingFits(adjusted,surface:surface) ? nil : "Le groupe dépasse le plafond ou une ouverture : déplacez-le sur l’aperçu, ou recentrez la répartition."
        case .failure: preview = nil; error = "Impossible de placer tous les spots avec cet écartement et ce diamètre. Réduisez l’écartement ou le nombre."
        }
    }
}
