import SwiftUI

struct JointTreatmentConfiguration: Codable, Equatable {
    enum Surface: String, Codable, CaseIterable, Identifiable {
        case walls, ceilings
        var id: String { rawValue }
        var title: String { self == .walls ? "Murs et cloisons" : "Plafonds" }
    }
    var area: Double = 0
    var surface: Surface = .walls
    var compound: String = "poudre"
    // Snapshot of existing Admin ratios, never independently maintained constants.
    var bandPerM2: Double = 0
    var powderPerM2: Double = 0
    var pastePerM2: Double = 0
    var catalogueVersion: String = ""
    var isValid: Bool {
        [area, bandPerM2, powderPerM2, pastePerM2].allSatisfy { $0.isFinite && $0 > 0 }
            && ["poudre", "pate"].contains(compound)
    }
}

enum JointTreatmentCalculator {
    static let reminder = "Prévoyez des bandes armées pour les angles saillants si la configuration l’exige."

    static func coverage(_ work: WorkItem, surface: JointTreatmentConfiguration.Surface) -> Double {
        let enabled: Bool
        let kind: JointTreatmentConfiguration.Surface
        var faces = 1.0
        switch work.payload {
        case .ceiling(let c): enabled = c.jointTreatment; kind = .ceilings
        case .railStudCeiling(let c): enabled = c.jointTreatment; kind = .ceilings
        case .peripheralLining(let c): enabled = c.jointTreatment; kind = .walls
        case .furringLining(let c): enabled = c.jointTreatment; kind = .walls
        case .bondedLining(let c): enabled = c.jointTreatment; kind = .walls
        case .adhesiveFacing(let c): enabled = c.jointTreatment; kind = .walls
        case .distributionPartition(let c): enabled = c.jointTreatment; kind = .walls; faces = 2
        case .alveolarPartition(let c): enabled = c.jointTreatment; kind = .walls; faces = 2
        default: return 0
        }
        guard enabled, kind == surface, work.area.isFinite else { return 0 }
        return max(0, work.area) * faces
    }

    static func deductions(_ configuration: JointTreatmentConfiguration, works: [WorkItem]) -> [(WorkItem, Double)] {
        var seen = Set<UUID>()
        return works.compactMap { work in
            guard seen.insert(work.id).inserted else { return nil }
            let area = coverage(work, surface: configuration.surface)
            return area > 0 ? (work, area) : nil
        }
    }

    static func remainingArea(_ configuration: JointTreatmentConfiguration, works: [WorkItem]) -> Double {
        guard configuration.area.isFinite else { return 0 }
        return max(0, configuration.area - deductions(configuration, works: works).reduce(0) { $0 + $1.1 })
    }

    static func quantities(_ configuration: JointTreatmentConfiguration, works: [WorkItem]) -> [LayoutQuantityLine] {
        guard configuration.isValid else { return [] }
        let area = remainingArea(configuration, works: works)
        return [
            .init(name: "Bande à joint", quantity: area * configuration.bandPerM2, unit: "ml"),
            .init(name: configuration.compound == "poudre" ? "Enduit à joints en poudre" : "Enduit à joints en pâte",
                  quantity: area * (configuration.compound == "poudre" ? configuration.powderPerM2 : configuration.pastePerM2), unit: "kg")
        ]
    }

    static func applyingReferences(_ configuration: JointTreatmentConfiguration, catalogue: CeilingCataloguePayload,
                                   records: WorkSummaryCatalogue) -> JointTreatmentConfiguration? {
        var result = configuration
        let ratios: [Double?]
        if configuration.surface == .walls {
            let values = records.records["QTY-DOUBLAGE-RAILS-MONTANTS"]?.data["coefficients"]?.object
            ratios = [values?["band_ml_m2"]?.number, values?["enduit_poudre_kg_m2"]?.number, values?["enduit_pate_kg_m2"]?.number]
        } else {
            ratios = ["QTY-BANDE", "QTY-ENDUIT-POUDRE", "QTY-ENDUIT-PATE"].map { id in
                catalogue.quantitatifs.first { $0.id == id }?.data["values"]?.object?["simple_060"]?.number
            }
        }
        guard ratios.allSatisfy({ $0.map { $0.isFinite && $0 > 0 } ?? false }) else { return nil }
        result.bandPerM2 = ratios[0]!
        result.powderPerM2 = ratios[1]!
        result.pastePerM2 = ratios[2]!
        result.catalogueVersion = catalogue.version
        return result
    }
}

struct JointTreatmentConfiguratorView: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var references = CeilingReferenceStore()
    let projectID: UUID
    let onSave: (JointTreatmentConfiguration) -> Void
    @State private var configuration: JointTreatmentConfiguration
    init(projectID: UUID, initial: JointTreatmentConfiguration = .init(), onSave: @escaping (JointTreatmentConfiguration) -> Void) {
        self.projectID = projectID; self.onSave = onSave
        _configuration = State(initialValue: initial)
    }
    private var works: [WorkItem] { store.project(id: projectID)?.works ?? [] }
    private var resolved: JointTreatmentConfiguration? {
        if let catalogue = references.catalogue {
            return JointTreatmentCalculator.applyingReferences(configuration, catalogue: catalogue, records: references.workSummaryCatalogue)
        }
        return configuration.isValid ? configuration : nil
    }
    var body: some View {
        AtlantiqueForm(bookLayout: true) {
            AtlantiqueSection("Surface à traiter") {
                HStack {
                    Text("Surface totale")
                    ZeroEmptyDecimalTextField(value: $configuration.area).multilineTextAlignment(.trailing).frame(width: 110)
                    Text("m²").foregroundStyle(.secondary)
                }
                AtlantiquePicker("Support", selection: $configuration.surface) {
                    ForEach(JointTreatmentConfiguration.Surface.allCases) { Text($0.title).tag($0) }
                }
                if !atlantique || Atlantique.Book.showsAdvancedFormControls {
                    Text("Indiquez la surface totale des faces à traiter, y compris celles déjà prévues dans les autres ouvrages.")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            AtlantiqueSection("Enduit à joints") {
                AtlantiqueSegmentedChoice(title: "Type", options: [("poudre", "Poudre"), ("pate", "Pâte")], selection: $configuration.compound)
            }
            JointTreatmentDeductionSection(configuration: configuration, works: works)
            AtlantiqueSection("Quantitatif") {
                if let value = resolved {
                    ForEach(Array(JointTreatmentCalculator.quantities(value, works: works).enumerated()), id: \.offset) { _, item in
                        LabeledContent(item.name, value: "\(item.quantity.formatted(.number.precision(.fractionLength(1)))) \(item.unit)")
                    }
                } else if references.isLoading { ProgressView("Chargement des bases Admin…") }
                else {
                    Text(references.error ?? "Les coefficients de jointoiement Admin sont indisponibles.").foregroundStyle(.orange)
                    Button("Réessayer") { Task { await references.load() } }
                }
                if !atlantique || Atlantique.Book.showsAdvancedFormControls {
                    Text(JointTreatmentCalculator.reminder).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Enregistrer") { if let value = resolved { onSave(value) } }
                    .atlantiqueActionStyle()
                    .disabled(resolved?.isValid != true)
            }
        }
        .atlantiqueFormPage("Bandes à joint")
        .toolbar {
            if atlantique {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { if let value = resolved { onSave(value) } }
                        .atlantiqueToolbarAction(primary: true)
                        .disabled(resolved?.isValid != true)
                }.atlantiqueToolbarBackground(atlantique)
            }
        }
        .task { await references.load() }
        .onChange(of: configuration.surface) { _, _ in
            // A wall snapshot must never be reused for a ceiling while offline.
            configuration.bandPerM2 = 0; configuration.powderPerM2 = 0; configuration.pastePerM2 = 0
        }
    }
}

struct JointTreatmentDeductionSection: View {
    let configuration: JointTreatmentConfiguration
    let works: [WorkItem]
    var body: some View {
        let deductions = JointTreatmentCalculator.deductions(configuration, works: works)
        if !deductions.isEmpty {
            AtlantiqueSection("Bandes déjà prévues") {
                Text("Ces ouvrages incluent déjà les bandes à joint et l’enduit. Leur surface est déduite de cet ouvrage pour éviter un double comptage ; leurs quantitatifs restent inchangés.")
                    .font(.footnote)
                ForEach(deductions, id: \.0.id) { work, area in
                    LabeledContent(work.name, value: "\(area.formatted(.number.precision(.fractionLength(1)))) m²")
                }
                LabeledContent("Surface restant à traiter", value: "\(JointTreatmentCalculator.remainingArea(configuration, works: works).formatted(.number.precision(.fractionLength(1)))) m²")
            }
        }
    }
}

extension ProjectItem {
    /// Linked opening records are implementation details of their parent ouvrage.
    /// Orphaned/legacy records remain visible and accessible.
    var visibleWorks: [WorkItem] {
        let ids = Set(works.filter(\.supportsAttachedOpenings).map(\.id))
        return works.filter { work in
            guard let parent = work.openingConfiguration?.sourceWorkID else { return true }
            return !ids.contains(parent) || parent == work.id
        }
    }
}

extension WorkItem {
    var jointTreatmentConfiguration: JointTreatmentConfiguration? {
        if case .jointTreatment(let value) = payload { return value }; return nil
    }
    var supportsAttachedOpenings: Bool {
        [.peripheralLiningStuds, .peripheralLiningFurrings, .distributionPartition, .alveolarPartition, .ceilingOnFurring, .ceilingOnRailsAndStuds].contains(type)
    }
}

enum WorkOpeningRelations {
    static func planOpenings(for work:WorkItem) -> [LayoutOpening] {
        var seen=Set<UUID>()
        return work.components.flatMap { $0.surface?.openings ?? [] }.filter { seen.insert($0.id).inserted }
    }

    static func planOpeningTitle(_ opening:LayoutOpening) -> String {
        let dimensions="\((opening.bounds.width/10).formatted(.number.locale(Locale(identifier:"fr_FR")).precision(.fractionLength(0...1)))) × \((opening.bounds.height/10).formatted(.number.locale(Locale(identifier:"fr_FR")).precision(.fractionLength(0...1)))) cm"
        let handing=opening.kind == .door ? opening.doorHanding.map { " · \($0.title)" } ?? "" : ""
        return "\(opening.kind.rawValue) · \(dimensions)\(handing)"
    }
    private static func attached(to work: WorkItem, allWorks: [WorkItem]) -> [OpeningConfiguration] {
        var seen = Set<UUID>()
        return allWorks.filter { $0.projectID == work.projectID && seen.insert($0.id).inserted }
            .compactMap(\.openingConfiguration).filter { $0.sourceWorkID == work.id }
    }

    static func insulationRemainingRatio(for work: WorkItem, allWorks: [WorkItem]) -> Double {
        guard work.area.isFinite, work.area > 0 else { return 1 }
        // Openings already represented by the measured contour are already
        // deducted from its net area; never subtract their ID a second time.
        var seen = Set(work.components.flatMap { $0.surface?.openings.map(\.id) ?? [] })
        let deduction = attached(to: work, allWorks: allWorks).reduce(0.0) { total, configuration in
            total + configuration.openings.reduce(0.0) { subtotal, opening in
                guard seen.insert(opening.id).inserted, opening.area.isFinite, opening.area > 0 else { return subtotal }
                let result = OpeningQuantityCalculator.calculate(opening, context: configuration.context)
                return subtotal + (result.isComplete ? result.insulationAreaDeduction : 0)
            }
        }
        // Preserve each layer's original reserve and treat only its parent
        // ouvrage, never another insulation reference in the project.
        return max(0, 1 - deduction / work.area)
    }

    static func summary(for work: WorkItem, allWorks: [WorkItem]) -> [String] {
        var seen = Set<UUID>()
        var lines: [String] = []
        func append(id: UUID, title: String, widthCM: Double, heightCM: Double) {
            guard seen.insert(id).inserted, widthCM.isFinite, heightCM.isFinite, widthCM > 0, heightCM > 0 else { return }
            func number(_ value: Double) -> String {
                value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1)))
            }
            lines.append("\(title) · \(number(widthCM)) × \(number(heightCM)) cm")
        }
        for opening in planOpenings(for:work) where seen.insert(opening.id).inserted {
            lines.append(planOpeningTitle(opening))
        }
        let configurations = attached(to: work, allWorks: allWorks) + (work.openingConfiguration.map { [$0] } ?? [])
        for configuration in configurations {
            for opening in configuration.openings {
                append(id: opening.id, title: opening.name?.isEmpty == false ? opening.name! : opening.kind.title(in: configuration.context.system),
                       widthCM: opening.width * 100, heightCM: opening.height * 100)
            }
        }
        return lines
    }

    static func includingAttached(to selected: [WorkItem], allWorks: [WorkItem]) -> [WorkItem] {
        let ids = Set(selected.map(\.id))
        let projects = Set(selected.map(\.projectID))
        var seen = Set<UUID>()
        let children = allWorks.filter { work in
            projects.contains(work.projectID) && work.openingConfiguration?.sourceWorkID.map { ids.contains($0) } == true
        }
        return (selected + children).filter { seen.insert($0.id).inserted }
    }
}

struct WorkOpeningsView: View {
    @EnvironmentObject private var store: ProjectStore
    let work: WorkItem
    @State private var creating = false
    @State private var deleting: WorkItem?
    @State private var error: String?
    private var current: WorkItem { store.project(id: work.projectID)?.works.first { $0.id == work.id } ?? work }
    private var linked: [WorkItem] { store.project(id: work.projectID)?.works.filter { $0.openingConfiguration?.sourceWorkID == work.id } ?? [] }
    private var options: [OpeningWorkSystem: [OpeningHeightSuggestion]] {
        store.openingHeightOptions(projectID: work.projectID).mapValues { $0.filter { $0.id == work.id } }
    }
    private var initial: OpeningConfiguration {
        var c = OpeningConfiguration()
        c.sourceWorkID = work.id
        switch current.type {
        case .peripheralLiningFurrings: c.context.system = .furringLining
        case .peripheralLiningStuds: c.context.system = .railStudLining
        case .distributionPartition, .alveolarPartition: c.context.system = .distributionPartition
        case .ceilingOnRailsAndStuds:
            c.context.system = .railStudCeiling
            c.context.ceilingLengthInStudDirection = current.railStudCeilingConfiguration?.length
        default: c.context.system = .furringCeiling
        }
        return c
    }
    var body: some View {
        List {
            Section {
                Text("Les ouvertures sont rattachées à cet ouvrage. Leurs fournitures sont incluses dans son quantitatif.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Ajouter une ouverture", systemImage: "plus") { creating = true }
            }
            if !WorkOpeningRelations.planOpenings(for:current).isEmpty {
                Section {
                    ForEach(WorkOpeningRelations.planOpenings(for:current)) { opening in
                        Label(WorkOpeningRelations.planOpeningTitle(opening),systemImage:opening.kind == .door ? "door.left.hand.open" : "rectangle")
                    }
                } header: { Text("Ouvertures du plan") } footer: {
                    Text("Déjà intégrées à l’ouvrage et déduites de sa surface. Modifiez-les dans le plan ou le calepinage.")
                }
            }
            ForEach(linked) { record in
                NavigationLink {
                    editor(record.openingConfiguration ?? initial, existing: record)
                } label: {
                    VStack(alignment: .leading) {
                        Text(record.name)
                        Text("\(record.openingConfiguration?.openings.count ?? 0) ouverture(s)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(allowsFullSwipe: false) {
                    Button("Supprimer", role: .destructive) { deleting = record }
                }
            }
        }
        .navigationTitle("Ouvertures")
        .sheet(isPresented: $creating) {
            NavigationStack {
                editor(initial, existing: nil)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { creating = false } } }
            }
        }
        .alert("Supprimer ces ouvertures ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Annuler", role: .cancel) { deleting = nil }
            Button("Supprimer", role: .destructive) {
                if let record = deleting {
                    do { try store.deleteWork(projectID: record.projectID, workID: record.id) }
                    catch { self.error = error.localizedDescription }
                }
                deleting = nil
            }
        }
        .alert("Enregistrement impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func editor(_ configuration: OpeningConfiguration, existing: WorkItem?) -> some View {
        AttachedOpeningEditor(configuration: configuration, options: options) { value in
            var value = value
            value.sourceWorkID = work.id
            if let existing { try store.updateWork(existing, openingConfiguration: value) }
            else {
                let name = store.defaultWorkName(projectID: work.projectID, type: .openings)
                try store.createConfiguredWork(projectID: work.projectID, name: name, type: .openings, payload: .openings(value), roomID: nil, newRoomName: nil)
                creating = false
            }
        }
    }
}

private struct AttachedOpeningEditor: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: OpeningConfiguration
    let options: [OpeningWorkSystem: [OpeningHeightSuggestion]]
    let save: (OpeningConfiguration) throws -> Void
    @State private var error: String?
    var body: some View {
        OpeningLabView(initialConfiguration: configuration, heightOptions: options, attachedToWork: true) { value in
            do { try save(value); dismiss() } catch { self.error = error.localizedDescription }
        }
        .alert("Enregistrement impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
