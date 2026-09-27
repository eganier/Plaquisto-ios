import SwiftUI

private struct LayoutCoveringAreaRatioKey: EnvironmentKey {
    static let defaultValue = 1.0
}
extension EnvironmentValues {
    /// Derived from the linked plan, never persisted as another geometry.
    /// Applies to boards/insulation only; support dimensions keep driving framing.
    var layoutCoveringAreaRatio: Double {
        get { self[LayoutCoveringAreaRatioKey.self] }
        set { self[LayoutCoveringAreaRatioKey.self] = newValue }
    }
}

struct LayoutExportForm: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let document: LayoutDocument
    @State private var projectID: UUID?
    @State private var projectName = ""
    @State private var roomName = ""
    @State private var type = WorkType.ceilingOnFurring
    @State private var configuring = false
    @State private var error: String?
    private var types: [WorkType] {
        document.surface.kind == .ceiling ? [.ceilingOnFurring,.ceilingOnRailsAndStuds] : [.peripheralLiningFurrings,.peripheralLiningStuds,.distributionPartition]
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Projet de destination") {
                    Picker("Projet",selection:$projectID) {
                        Text("Créer un projet").tag(nil as UUID?)
                        ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if projectID == nil { TextField("Nom du projet",text:$projectName) }
                    LabeledContent("Pièce (facultatif)") { TextField("Exemple : Salon",text:$roomName) }
                }
                Section("Type d’ouvrage") {
                    Picker("Système",selection:$type) { ForEach(types) { Text($0.title).tag($0) } }
                }
                Section {
                    Text("Le formulaire métier reçoit la surface nette et conserve le calepinage avec l’ouvrage. Vérifiez les portées, supports et hauteurs : les calculs métier restent ceux du formulaire, distincts du nombre exact de plaques dessiné.").font(.footnote).foregroundStyle(.secondary)
                    Button("Configurer et calculer le quantitatif") {
                        do {
                            _ = try SheetLayoutEngine.calculate(surface:document.surface,layer:document.layers.first ?? .init())
                            if projectID == nil { projectID = try store.createProject(name:projectName,client:"",address:"",notes:"") }
                            configuring = true
                        } catch { self.error = error.localizedDescription }
                    }.disabled(projectID == nil && projectName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Exporter vers un ouvrage").navigationBarTitleDisplayMode(.inline)
            .onAppear { type = types[0]; projectID = store.projects.first?.id }
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Fermer") { dismiss() } } }
            .fullScreenCover(isPresented:$configuring) {
                if let projectID {
                    WorkConfiguratorContainer(projectID:projectID,workName:type.generatedName(roomName:roomName),workType:type,onFinished:{ configuring = false; dismiss() },layoutDocument:document,newRoomName:roomName)
                }
            }
        }
    }
}

enum LayoutWorkGeometry {
    static func rectangle(_ document:LayoutDocument) -> (length:Double,width:Double)? {
        let points = document.surface.contour
        guard points.count == 4, document.surface.openings.isEmpty else { return nil }
        let edges = points.indices.map { points[($0+1)%4]-points[$0] }
        guard edges.allSatisfy({$0.length > 0}), edges.indices.allSatisfy({ i in
            abs(LayoutGeometry.dot(edges[i],edges[(i+1)%4])) < edges[i].length*edges[(i+1)%4].length*0.00001
        }) else { return nil }
        return (edges[0].length/1000,edges[1].length/1000)
    }
    static func area(_ document:LayoutDocument) -> Double {
        ((try? document.surface.netMeasuredArea()) ?? 0)/1_000_000
    }
    static func coveringAreaRatio(_ document: LayoutDocument?) -> Double {
        guard let document,
              let measured = try? document.surface.netMeasuredArea(), measured > 0,
              let laying = try? document.surface.netLayingArea(), laying.isFinite else { return 1 }
        return laying / measured
    }
    static func ceilingInsulation(_ configuration: CeilingConfiguration, catalogue: CeilingCataloguePayload,
                                  coveringRatio: Double) -> [(name: String, quantity: Double)] {
        let area = (configuration.enteredArea ?? configuration.length * configuration.width) * coveringRatio
        guard area.isFinite, area > 0 else { return [] }
        var selections = [(configuration.insulationID, configuration.insulationThickness)]
        if configuration.insulationLayers == 2, !configuration.insulationID.isEmpty {
            selections.append((configuration.secondInsulationID ?? "", configuration.secondInsulationThickness ?? 0))
        }
        // Useful net surface, one quantity per selected insulation layer. No
        // new waste coefficient is invented for this previously absent row.
        return selections.compactMap { id, thickness in
            guard !id.isEmpty, let record = catalogue.isolation.first(where: { $0.id == id }) else { return nil }
            return ("Isolation · \(record.title) · \(thickness.formatted(.number.precision(.fractionLength(0...1)))) mm", area)
        }
    }
    static func ceiling(_ document:LayoutDocument?, base:CeilingConfiguration = .init()) -> CeilingConfiguration {
        guard let document else { return base }
        var c = base; c.enteredArea = area(document); c.dimensionsSpecified = false
        c.length = document.surface.bounds.width/1000; c.width = document.surface.bounds.height/1000
        if let size = rectangle(document) { c.dimensionsSpecified = true; c.length = size.length; c.width = size.width }
        if let spacing = document.layers.first?.furring?.spacing { c.selectedSpacing = spacing/1000 }
        return c
    }
    static func railCeiling(_ document:LayoutDocument?, base:RailStudCeilingConfiguration = .init()) -> RailStudCeilingConfiguration {
        guard let document else { return base }
        var c = base; c.area = area(document); c.dimensionsSpecified = false
        c.length = document.surface.bounds.width/1000; c.width = document.surface.bounds.height/1000
        if let size = rectangle(document) { c.dimensionsSpecified = true; c.length = size.length; c.width = size.width }
        return c
    }
    static func lining(_ document:LayoutDocument?, base:DoublageConfiguration = .init()) -> DoublageConfiguration {
        guard let document else { return base }
        var c = base; c.geometryMode = "surface"; c.enteredSurface = area(document)
        c.height = document.surface.bounds.height/1000; c.enteredLength = document.surface.bounds.width/1000; c.wallCount = 1; return c
    }
    static func furring(_ document:LayoutDocument?, base:FurringLiningConfiguration = .init()) -> FurringLiningConfiguration {
        guard let document else { return base }
        var c = base; c.geometryMode = "surface"; c.enteredSurface = area(document)
        c.height = document.surface.bounds.height/1000; c.enteredLength = document.surface.bounds.width/1000; c.wallCount = 1; return c
    }
    static func partition(_ document:LayoutDocument?, base:CloisonDistributionConfiguration = .init()) -> CloisonDistributionConfiguration {
        guard let document else { return base }
        var c = base; c.height = document.surface.bounds.height/1000; c.geometryMode = "surface"; c.enteredSurface = area(document)
        c.enteredLength = document.surface.bounds.width/1000; return c
    }
}

struct LinkedLayoutView: View {
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var catalogue = ToolTechnicalStore()
    let work: WorkItem
    @State private var error: String?
    var body: some View {
        SheetLayoutView(initialDocument:work.layoutDocument,onSaveDocument:{ document in
            do { try store.updateLinkedLayout(projectID:work.projectID,workID:work.id,document:document) }
            catch { self.error = error.localizedDescription; throw error }
        })
        .environmentObject(catalogue)
        .task { await catalogue.load() }
        .alert("Enregistrement impossible",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("OK") {} } message: { Text(error ?? "") }
    }
}
