import SwiftUI

struct ProjectWorkQuantitySelectionView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID
    @State private var selected: Set<UUID> = []
    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                let chosen = project.visibleWorks.filter { selected.contains($0.id) }
                List {
                    if project.visibleWorks.isEmpty {
                        ContentUnavailableView("Aucun ouvrage", systemImage: "sum", description: Text("Ajoutez un ouvrage au projet pour préparer son quantitatif."))
                    } else {
                        Section("Ouvrages à inclure") {
                            Button(selected.isSuperset(of: project.visibleWorks.map(\.id)) ? "Tout désélectionner" : "Tout sélectionner") {
                                selected = selected.isSuperset(of: project.visibleWorks.map(\.id)) ? [] : Set(project.visibleWorks.map(\.id))
                            }
                            ForEach(project.visibleWorks) { work in
                                Button {
                                    if selected.contains(work.id) { selected.remove(work.id) } else { selected.insert(work.id) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(work.name).foregroundStyle(.primary)
                                            if work.surveySourceNeedsReview {
                                                Label("Relevé modifié — à contrôler", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.caption).foregroundStyle(.orange)
                                            }
                                            Text([project.rooms.first { $0.id == work.roomID }?.name, work.level, work.zone].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(work.id) ? "checkmark.circle.fill" : "circle")
                                    }
                                }.accessibilityAddTraits(selected.contains(work.id) ? .isSelected : [])
                            }
                        }
                        Section {
                            Text("\(chosen.count) ouvrage(s) sélectionné(s)")
                                .font(.caption).foregroundStyle(.secondary)
                            NavigationLink {
                                CombinedQuantityView(works: chosen, title: chosen.count == project.visibleWorks.count ? "Quantitatif du projet" : "Quantitatif sélectionné")
                            } label: { Label("Afficher le quantitatif", systemImage: "sum") }
                            .disabled(chosen.isEmpty)
                        } footer: { Text("Chaque ouvrage est compté une seule fois.") }
                    }
                }
            }
        }.navigationTitle("Voir les quantitatifs").navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkSelectionView: View {
    let works: [WorkItem]
    @State private var selectedIDs: Set<UUID>

    init(works: [WorkItem]) {
        self.works = works
        _selectedIDs = State(initialValue: Set(works.map(\.id)))
    }

    private var selectedWorks: [WorkItem] { works.filter { selectedIDs.contains($0.id) } }

    var body: some View {
        List {
            Section {
                ForEach(works) { work in
                    Button {
                        if selectedIDs.contains(work.id) { selectedIDs.remove(work.id) }
                        else { selectedIDs.insert(work.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(work.name).foregroundStyle(.primary)
                                Text(work.type.title).font(.caption).foregroundStyle(.secondary)
                                if work.surveySourceNeedsReview {
                                    Label("Relevé modifié — à contrôler", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Image(systemName: selectedIDs.contains(work.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(work.id) ? Color.accentColor : Color.secondary)
                        }
                    }
                }
            } header: {
                Text("Ouvrages à inclure")
            } footer: {
                Text("Les quantités identiques seront additionnées dans un seul récapitulatif.")
            }

            Section {
                NavigationLink {
                    CombinedQuantityView(works: selectedWorks, title: "Quantitatif sélectionné")
                } label: {
                    Label("Afficher le quantitatif de \(selectedWorks.count) ouvrage(s)", systemImage: "sum")
                }
                .disabled(selectedWorks.isEmpty)
            }
        }
        .navigationTitle("Sélection des ouvrages")
        .toolbar {
            Button(selectedIDs.count == works.count ? "Tout désélectionner" : "Tout sélectionner") {
                selectedIDs = selectedIDs.count == works.count ? [] : Set(works.map(\.id))
            }
        }
    }
}

struct CombinedQuantityView: View {
    @StateObject private var store = CeilingReferenceStore()
    @StateObject private var prices = SupplyPriceStore()
    @EnvironmentObject private var projectStore: ProjectStore
    @Environment(\.interfacePresentation) private var presentation
    private var isLab: Bool { presentation == .contrastLab }
    let works: [WorkItem]
    let title: String
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var currentWorks: [WorkItem] {
        let refreshed = works.map { work in projectStore.project(id: work.projectID)?.works.first { $0.id == work.id } ?? work }
        return WorkOpeningRelations.includingAttached(to: refreshed, allWorks: projectWorks)
    }

    private var projectWorks: [WorkItem] {
        var seen = Set<UUID>()
        return works.flatMap { projectStore.project(id: $0.projectID)?.works ?? [$0] }.filter { seen.insert($0.id).inserted }
    }

    private var summary: CombinedQuantitySummary? {
        store.catalogue.map { CombinedQuantityCalculator.calculate(works: currentWorks, catalogue: $0, projectWorks: projectWorks) }
    }

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView("Aucun ouvrage à quantifier", systemImage: "sum",
                    description: Text("Cette sélection ne contient aucun ouvrage. Le quantitatif est nul."))
            } else if store.isLoading {
                ProgressView("Calcul du quantitatif…")
            } else if let error = store.error {
                ContentUnavailableView("Référentiel indisponible", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if let summary {
                List {
                    if let catalogue=store.catalogue {
                        SupplyCostSection(estimate:SupplyCostEstimator.estimate(summary.supplies,prices:prices.catalogue,catalogue:catalogue,day:SupplyCostEstimator.day()),loading:prices.isLoading,message:prices.message)
                    }
                    ForEach(currentWorks.filter { $0.jointTreatmentConfiguration != nil }) { work in
                        if let c = work.jointTreatmentConfiguration {
                            JointTreatmentDeductionSection(configuration: c, works: projectWorks.filter { $0.projectID == work.projectID })
                            Section { Text(JointTreatmentCalculator.reminder).font(.footnote) }
                        }
                    }
                    ForEach(currentWorks.filter { $0.automaticLayout != nil }) { work in
                        if let automatic = work.automaticLayout,
                           automatic.configurationFingerprint == LayoutQuantityCalculator.configurationFingerprint(work) {
                            Section("Calepinage automatique · " + work.name) {
                                Text("Les besoins du plan complètent l’estimation du formulaire uniquement à la hausse. Marge incluse, sans ajout d’une seconde marge.").font(.footnote)
                                ForEach(automatic.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                            }
                        }
                    }
                    let toReview = currentWorks.filter(\.surveySourceNeedsReview)
                    if !toReview.isEmpty {
                        Section("Quantités à contrôler") {
                            ForEach(toReview) { work in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(work.name).font(.headline)
                                    SurveySourceReviewNotice(work: work)
                                }
                            }
                        }
                    }
                    Section("Ouvrages inclus") {
                        if isLab {
                            DisclosureGroup("\(currentWorks.count) ouvrage(s)") { includedWorks }
                        } else {
                            includedWorks
                        }
                        LabeledContent("Surface totale", value: format(summary.totalArea) + " m²").fontWeight(.semibold)
                    }
                    Section("Fournitures totales indicatives") {
                        ForEach(currentWorks.filter { $0.layoutQuantityTakeoff != nil || ($0.hasSavedLayout && $0.automaticLayout == nil && ($0.type == .ceilingOnFurring || $0.type == .ceilingOnRailsAndStuds)) }) { work in
                            if LayoutQuantityCalculator.applicable(work) != nil {
                                if isLab {
                                    DisclosureGroup("Calcul affiné · \(work.name)") { takeoffExplanation(work) }
                                        .font(.subheadline)
                                } else { takeoffExplanation(work) }
                            } else {
                                Label("\(work.name) : le calepinage n’est pas exploitable pour le calcul détaillé. L’estimation du formulaire est affichée.",systemImage:"exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        ForEach(supplyRows(summary.supplies)) { row in
                            if isLab {
                                HStack(alignment: .firstTextBaseline, spacing: 20) {
                                    Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(row.value).fontWeight(.bold).foregroundStyle(ContrastPalette.blue)
                                        .multilineTextAlignment(.trailing)
                                }.padding(.vertical, 8)
                            } else { LabeledContent(row.name, value: row.value) }
                        }
                    }
                    if !isLab { Section {
                        if let exportURL {
                            ShareLink(item: exportURL) { Label("Partager la liste", systemImage: "square.and.arrow.up") }
                        } else { ProgressView("Préparation de la liste…") }
                        if let exportError { Text(exportError).foregroundStyle(.red) }
                    } }
                }
                .scrollContentBackground(isLab ? .hidden : .visible)
                .background(isLab ? ContrastPalette.paper : Color(uiColor: .systemGroupedBackground))
                .safeAreaInset(edge: .bottom) {
                    if isLab {
                        VStack(spacing: 6) {
                            if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
                            if let exportURL {
                                ShareLink(item: exportURL) {
                                    Label("Partager la liste", systemImage: "square.and.arrow.up")
                                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                                        .foregroundStyle(.white).background(ContrastPalette.ink, in: RoundedRectangle(cornerRadius: 17))
                                }
                            } else if exportError == nil { ProgressView("Préparation de la liste…") }
                        }.padding().background(.regularMaterial)
                    }
                }
                .task(id: exportText(summary)) {
                    exportURL = nil
                    do {
                        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Quantitatifs", isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let url = directory.appendingPathComponent("Quantitatif-\(UUID().uuidString.prefix(8)).txt")
                        try exportText(summary).write(to: url, atomically: true, encoding: .utf8)
                        exportURL = url; exportError = nil
                    } catch { exportError = "Impossible de préparer le partage : \(error.localizedDescription)" }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !works.isEmpty && store.catalogue == nil { await store.load() } }
        .task { if !works.isEmpty { await prices.load() } }
    }

    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func takeoffExplanation(_ work: WorkItem) -> some View {
        Text("\(work.name) : quantitatif actualisé automatiquement par les calepinages enregistrés (ossature : \(Int((LayoutQuantityCalculator.applicable(work)?.framingCoverage ?? 0)*100)) % de la surface). La part restante et les autres fournitures conservent l’estimation du formulaire. Marge de 10 % incluse sur les plaques, profilés et périphéries calculés sur plan.")
            .font(.caption).foregroundStyle(.secondary)
    }
    private var includedWorks: some View {
        ForEach(currentWorks) { work in
            NavigationLink { SavedWorkView(work: work) } label: {
                if work.type == .openings {
                    LabeledContent(work.name, value: "\(work.openingConfiguration?.openings.count ?? 0) ouverture(s)")
                } else {
                    LabeledContent(work.name, value: format(work.area) + " m²")
                }
            }
        }
    }
    private func exportText(_ summary: CombinedQuantitySummary) -> String {
        var lines = ["Plaquisto — \(title)", "", "Ouvrages inclus :"]
        lines += currentWorks.map { "• \($0.name)" }
        for work in currentWorks {
            if let automatic=work.automaticLayout,automatic.configurationFingerprint == LayoutQuantityCalculator.configurationFingerprint(work) {
                lines.append("\(work.name) : estimation complétée à la hausse par le calepinage automatique, marge déjà incluse.")
                lines += automatic.warnings
            }
            if let c = work.jointTreatmentConfiguration {
                let context = projectWorks.filter { $0.projectID == work.projectID }
                lines.append("Bandes à joint : surface restante \(JointTreatmentCalculator.remainingArea(c, works: context)) m²")
                for (source, area) in JointTreatmentCalculator.deductions(c, works: context) {
                    lines.append("Déjà prévu dans \(source.name) : \(area) m² (déduit)")
                }
                lines.append(JointTreatmentCalculator.reminder)
            }
        }
        lines += ["", "Surface totale : \(format(summary.totalArea)) m²", "", "Fournitures indicatives :"]
        lines += supplyRows(summary.supplies).map { "\($0.name) : \($0.value)" }
        if let catalogue=store.catalogue {
            let estimate=SupplyCostEstimator.estimate(summary.supplies,prices:prices.catalogue,catalogue:catalogue,day:SupplyCostEstimator.day())
            if let lower=estimate.lower,let upper=estimate.upper {
                lines += ["",estimate.missing.isEmpty ? "Estimation des fournitures HT :" : "Estimation PARTIELLE des fournitures HT :", "\(SupplyCostEstimator.money(lower)) à \(SupplyCostEstimator.money(upper)) HT (±5 %, éco-contribution incluse, hors main-d’œuvre et livraison)"]
                if let revision=prices.catalogue?.revision { lines.append("Révision des tarifs : \(revision)") }
            } else { lines += ["", "Estimation indisponible : aucun tarif validé correspondant."] }
            if let message=prices.message { lines.append(message) }
            if !estimate.missing.isEmpty { lines += ["Non chiffrées (exclues du montant) :"] + estimate.missing.map(\.name) }
        }
        let review = currentWorks.filter(\.surveySourceNeedsReview)
        if !review.isEmpty { lines += ["", "Relevés modifiés à contrôler : " + review.map(\.name).joined(separator: ", ")] }
        return lines.joined(separator: "\n")
    }
    private func supplyRows(_ supplies: [CombinedSupply]) -> [SupplyListingRow] {
        SupplyListingConsolidator.rows(supplies.map {
            .init(name: $0.name, quantity: $0.quantity, unit: $0.unit)
        })
    }
}

struct CombinedSupply: Identifiable {
    let name: String
    let quantity: Double
    let unit: String
    var id: String { "\(name)|\(unit)" }
}

struct CombinedQuantitySummary {
    let totalArea: Double
    let supplies: [CombinedSupply]
}

enum CombinedQuantityCalculator {
    /// Store-side recalculation also works offline, without a reference store.
    /// Resolve its stable format IDs here so an automatic update never replaces
    /// a known facing (notably 4 tapered edges) with a generic purchase label.
    private static func namedTakeoff(_ takeoff: LayoutQuantityTakeoff, catalogue: CeilingCataloguePayload) -> LayoutQuantityTakeoff {
        var result=takeoff
        for i in result.boards.indices {
            guard let id=result.boards[i].formatID else { continue }
            for record in catalogue.parements {
                for dimension in record.data["dimensions"]?.array ?? [] {
                    guard let data=dimension.object, let width=data["width_mm"]?.number, let length=data["length_mm"]?.number,
                          LayoutCatalogFormat.identifier(productID:record.id,width:width,length:length) == id else { continue }
                    result.boards[i].name="\(record.title) · \(Int(width)) × \(Int(length)) mm"
                }
            }
        }
        return result
    }
    static func calculate(works: [WorkItem], catalogue: CeilingCataloguePayload, projectWorks: [WorkItem]? = nil) -> CombinedQuantitySummary {
        let works = WorkOpeningRelations.includingAttached(to: works, allWorks: projectWorks ?? works)
        var totals: [String: CombinedSupply] = [:]
        var totalArea = 0.0

        func add(name: String, quantity: Double, unit: String) {
            guard quantity > 0 else { return }
            for component in SupplyListingConsolidator.components(.init(name: name, quantity: quantity, unit: unit)) {
                let name = SupplyListingConsolidator.canonicalName(component.name)
                let unit = SupplyListingConsolidator.canonicalUnit(component.unit)
                let key = "\(name)|\(unit)"
                let previous = totals[key]?.quantity ?? 0
                totals[key] = CombinedSupply(name: name, quantity: previous + component.quantity, unit: unit)
            }
        }

        var includedWorkIDs = Set<UUID>()
        for work in works where includedWorkIDs.insert(work.id).inserted {
            if let automatic = work.automaticLayout,
               automatic.configurationFingerprint == LayoutQuantityCalculator.configurationFingerprint(work) {
                var baseline = work; baseline.automaticLayout = nil
                let initial = calculate(works: [baseline], catalogue: catalogue)
                var merged: [String: LayoutQuantityLine] = [:]
                for line in initial.supplies.map({ LayoutQuantityLine(name: $0.name, quantity: $0.quantity, unit: $0.unit) }) + automatic.minimumSupplies {
                    let name = SupplyListingConsolidator.canonicalName(line.name)
                    let unit = SupplyListingConsolidator.canonicalUnit(line.unit)
                    let key = name + "|" + unit
                    if line.quantity > (merged[key]?.quantity ?? 0) {
                        merged[key] = .init(name: name, quantity: line.quantity, unit: unit)
                    }
                }
                totalArea += initial.totalArea
                for line in merged.values { add(name: line.name, quantity: line.quantity, unit: line.unit) }
                continue
            }
            if let configuration = work.jointTreatmentConfiguration {
                let context = (projectWorks ?? works).filter { $0.projectID == work.projectID }
                totalArea += JointTreatmentCalculator.remainingArea(configuration, works: context)
                for item in JointTreatmentCalculator.quantities(configuration, works: context) {
                    add(name: item.name, quantity: item.quantity, unit: item.unit)
                }
                continue
            }
            let takeoff = LayoutQuantityCalculator.applicable(work).map { namedTakeoff($0,catalogue:catalogue) }
            if case .paintingBeta(let configuration) = work.payload {
                totalArea += configuration.area
                if configuration.treatment == nil {
                    add(name: "Surface à traiter · traitements à renseigner", quantity: configuration.area, unit: "m²")
                } else if let supplies = try? PaintingCalculator.calculate(configuration) {
                    for item in supplies { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                }
                continue
            }
            if work.type == .openings, let configuration = work.openingConfiguration {
                var context = configuration.context
                if let source = works.first(where: { $0.id == configuration.sourceWorkID }) {
                    context.frame = source.doublageConfiguration?.frame ?? source.cloisonDistributionConfiguration?.frame
                        ?? source.railStudCeilingConfiguration.map { "R\($0.studWidth) + M\($0.studWidth)" }
                        ?? context.frame
                }
                let results = configuration.openings.map {
                    OpeningQuantityCalculator.calculate($0, context: context)
                }
                for item in OpeningQuantityCalculator.totals(results) {
                    let source = works.first(where: { $0.id == configuration.sourceWorkID })?.furringLiningConfiguration
                    let name = SupplyListingConsolidator.canonicalName(item.name) == "Appuis intermédiaires pour fourrures"
                        ? (source?.supportSupplyName ?? item.name) : item.name
                    add(name: name, quantity: item.quantity, unit: item.unit.rawValue)
                }
                continue
            }
            if work.type == .ceilingOnRailsAndStuds, let ceiling = work.railStudCeilingConfiguration {
                totalArea += ceiling.effectiveArea
                let suspensionNames = Set((ceiling.suppliesPerSuspension ?? []).map(\.name))
                for item in ceiling.quantities {
                    let remaining:Double
                    if let takeoff, item.unit == "plaque(s)" { remaining=1-takeoff.boardCoverage(0) }
                    else if let takeoff, item.name.hasPrefix("Montant M") || item.name.hasPrefix("Montants M") || item.name.hasPrefix("Rail R") || item.name.hasPrefix("Rails R") || suspensionNames.contains(item.name) { remaining=1-takeoff.framingCoverage }
                    else { remaining=1 }
                    add(name:item.name,quantity:item.quantity*remaining,unit:item.unit)
                }
                if let takeoff {
                    for board in takeoff.boards { add(name:board.name,quantity:board.quantity,unit:board.unit) }
                    add(name:"Montant M\(ceiling.studWidth)",quantity:takeoff.framingMeters,unit:"ml")
                    add(name:"Rails R\(ceiling.studWidth)",quantity:takeoff.perimeterMeters,unit:"ml")
                    for item in ceiling.suppliesPerSuspension ?? [] {
                        add(name:item.name,quantity:item.quantity*Double(takeoff.hangers),unit:item.unit)
                    }
                }
                continue
            }
            if work.type == .modularCeiling, let ceiling = work.modularCeilingConfiguration {
                let quantities = ModularCeilingCalculator.calculate(ceiling)
                totalArea += quantities.area
                add(name: "Dalles modulaires \(ceiling.tileFormat.title)", quantity: Double(quantities.orderedTiles), unit: "unité(s)")
                add(name: "Profilés porteurs T24 · 3,60 m", quantity: Double(quantities.mainRunnerBars), unit: "unité(s)")
                add(name: "Entretoises T24 · 1,20 m", quantity: Double(quantities.crossTees1200Ordered), unit: "unité(s)")
                add(name: "Entretoises T24 · 0,60 m", quantity: Double(quantities.crossTees600Ordered), unit: "unité(s)")
                add(name: "Cornières de rive · 3,00 m", quantity: Double(quantities.perimeterAngleBars), unit: "unité(s)")
                add(name: "Suspentes + fixations", quantity: Double(quantities.hangers), unit: "unité(s)")
                continue
            }
            if work.type == .peripheralLiningStuds, let doublage = work.doublageConfiguration {
                totalArea += doublage.area
                for item in doublage.quantities {
                    let name = item.name == "Rails" ? OpeningContext.profileName(frame: doublage.frame, rail: true)
                        : item.name == "Montants" ? OpeningContext.profileName(frame: doublage.frame, rail: false) : item.name
                    add(name: name, quantity: item.quantity, unit: item.unit)
                }
                continue
            }
            if work.type == .distributionPartition, let partition = work.cloisonDistributionConfiguration {
                totalArea += partition.area
                for item in partition.quantities {
                    let name = item.name == "Rails" ? OpeningContext.profileName(frame: partition.frame, rail: true)
                        : item.name == "Montants" ? OpeningContext.profileName(frame: partition.frame, rail: false) : item.name
                    add(name: name, quantity: item.quantity, unit: item.unit)
                }
                continue
            }
            if work.type == .alveolarPartition, let partition = work.alveolarPartitionConfiguration {
                totalArea += partition.area
                for item in partition.quantities {
                    let name = item.name == "Rails" ? "Rail pour cloison alvéolaire" : item.name
                    add(name: name, quantity: item.quantity, unit: item.unit)
                }
                continue
            }
            if work.type == .peripheralLiningBonded, let lining = work.bondedLiningConfiguration {
                totalArea += lining.area
                for item in lining.quantities { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                continue
            }
            if work.type == .peripheralLiningFurrings, let lining = work.furringLiningConfiguration {
                totalArea += lining.area
                for item in lining.quantities { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                continue
            }
            if work.type == .peripheralLiningAdhesiveFacing, let lining = work.adhesiveFacingConfiguration {
                totalArea += lining.area
                for item in lining.quantities { add(name: item.name, quantity: item.quantity, unit: item.unit) }
                continue
            }
            guard let configuration = work.ceilingConfiguration else { continue }
            let area = configuration.enteredArea ?? configuration.length * configuration.width
            let remainingFraming=1-(takeoff?.framingCoverage ?? 0)
            totalArea += area
            let prefix = configuration.layers == 1 ? "simple" : "double"
            let key = "\(prefix)_0\(Int((configuration.selectedSpacing * 100).rounded()))"
            let fixingRatio = catalogue.quantitatifs.first(where: { $0.id == "QTY-FIXATION" })?.data["values"]?.object?[key]?.number ?? 0
            let estimatedFixings=fixingRatio*area+LayoutQuantityCalculator.estimatedAdditionalEndHangers(configuration)
            let fixingCount = Double(takeoff?.hangers ?? 0) + estimatedFixings * remainingFraming

            for item in catalogue.quantitatifs where !["QTY-FIXATION", "QTY-PLAQUE"].contains(item.id) {
                if item.id == "QTY-CORNIERE" && configuration.perimeterSupport == false { continue }
                if !configuration.jointTreatment && ["QTY-BANDE", "QTY-ENDUIT-POUDRE", "QTY-ENDUIT-PATE"].contains(item.id) { continue }
                if configuration.jointTreatment && configuration.compoundChoice == "poudre" && item.id == "QTY-ENDUIT-PATE" { continue }
                if configuration.jointTreatment && configuration.compoundChoice == "pate" && item.id == "QTY-ENDUIT-POUDRE" { continue }
                guard let ratio = item.data["values"]?.object?[key]?.number,
                      let unit = item.data["unit"]?.string else { continue }
                let exactSplices=item.id == "QTY-ECLISSE" && takeoff?.furringSplices != nil
                let remainder=["QTY-FOURRURE","QTY-CORNIERE"].contains(item.id) || exactSplices ? remainingFraming : 1
                let name=takeoff != nil && item.id == "QTY-CORNIERE" ? "Cornière" : item.title
                add(name:name,quantity:ratio*area*remainder,unit:unit)
            }

            if let takeoff {
                add(name:catalogue.quantitatifs.first { $0.id == "QTY-FOURRURE" }?.title ?? "Fourrure F45",quantity:takeoff.framingMeters,unit:"ml")
                add(name:"Cornière",quantity:takeoff.perimeterMeters,unit:"ml")
                if let splices=takeoff.furringSplices {
                    let item=catalogue.quantitatifs.first { $0.id == "QTY-ECLISSE" }
                    add(name:item?.title ?? "Éclisse",quantity:Double(splices),unit:item?.data["unit"]?.string ?? "unité")
                }
            }
            if let system = catalogue.systemesFixation.first(where: { $0.id == configuration.fixingSystemID }) {
                for component in CeilingHangerComponents.resolve(for: system, plenumCM: configuration.plenum, catalogue: catalogue) {
                    guard let object = component.object,
                          let name = object["name"]?.string,
                          let ratio = object["quantity"]?.number,
                          let unit = object["unit"]?.string,
                          let calculation = object["calculation"]?.string else { continue }
                    var quantity = fixingCount * ratio
                    if calculation == "plenum_m" { quantity *= configuration.plenum / 100 }
                    add(name: name, quantity: quantity, unit: unit)
                }
            } else if takeoff != nil {
                add(name:"Suspentes — système à préciser",quantity:fixingCount,unit:"unité(s)")
            }

            if configuration.vaporBarrier {
                let systemHandlesVaporBarrier = catalogue.systemesFixation.first(where: { $0.id == configuration.fixingSystemID })?.data["pare_vapeur_compatible"]?.bool == true
                let fourrureRatio = catalogue.quantitatifs.first(where: { $0.id == "QTY-FOURRURE" })?.data["values"]?.object?[key]?.number ?? 0
                for record in catalogue.pareVapeur ?? [] {
                    for component in record.data["components"]?.array ?? [] {
                        guard let object = component.object,
                              let name = object["name"]?.string,
                              let ratio = object["quantity"]?.number,
                              let unit = object["unit"]?.string,
                              let calculation = object["calculation"]?.string else { continue }
                        if object["exclude_when_system_handles_vapor_barrier"]?.bool == true && systemHandlesVaporBarrier { continue }
                        let quantity = calculation == "fourrure_ml" ? ratio * fourrureRatio * area : ratio * area
                        add(name: name, quantity: quantity, unit: unit)
                    }
                }
            }

            let coveringRatio = LayoutWorkGeometry.coveringAreaRatio(work.layoutDocument)
            for item in LayoutWorkGeometry.ceilingInsulation(configuration, catalogue: catalogue, coveringRatio: coveringRatio) {
                add(name: item.name, quantity: item.quantity, unit: "m²")
            }
            if let takeoff {
                for board in takeoff.boards { add(name:board.name,quantity:board.quantity,unit:board.unit) }
            }
            addParements(configuration.firstSkin,catalogue:catalogue,coveringRatio:coveringRatio*(1-(takeoff?.boardCoverage(0) ?? 0)),add:add)
            if configuration.layers == 2 {
                addParements(configuration.secondSkin,catalogue:catalogue,coveringRatio:coveringRatio*(1-(takeoff?.boardCoverage(1) ?? 0)),add:add)
            }
        }

        return CombinedQuantitySummary(totalArea: totalArea, supplies: totals.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private static func addParements(_ selections: [FacingSelection], catalogue: CeilingCataloguePayload, coveringRatio: Double, add: (String, Double, String) -> Void) {
        for selection in selections {
            guard let facing = catalogue.parements.first(where: { $0.id == selection.facingID }),
                  let dimension = facing.data["dimensions"]?.array?.compactMap({ $0.object }).first(where: {
                      guard let width = $0["width_mm"]?.number, let length = $0["length_mm"]?.number else { return false }
                      return "\(Int(width))x\(Int(length))" == selection.dimensionID
                  }),
                  let width = dimension["width_mm"]?.number,
                  let length = dimension["length_mm"]?.number else { continue }
            let boardArea = width * length / 1_000_000
            guard boardArea > 0 else { continue }
            let quantity = ceil(selection.area * coveringRatio * 1.05 / boardArea)
            add("\(facing.title) · \(Int(width)) × \(Int(length)) mm", quantity, "plaque(s)")
        }
    }
}

extension WorkItem {
    var area: Double {
        switch type {
        case .ceilingOnFurring:
            guard let configuration = ceilingConfiguration else { return 0 }
            return configuration.enteredArea ?? configuration.length * configuration.width
        case .ceilingOnRailsAndStuds: return railStudCeilingConfiguration?.effectiveArea ?? 0
        case .modularCeiling: return modularCeilingConfiguration?.area ?? 0
        case .peripheralLiningStuds: return doublageConfiguration?.area ?? 0
        case .distributionPartition: return cloisonDistributionConfiguration?.area ?? 0
        case .alveolarPartition: return alveolarPartitionConfiguration?.area ?? 0
        case .peripheralLiningBonded: return bondedLiningConfiguration?.area ?? 0
        case .peripheralLiningFurrings: return furringLiningConfiguration?.area ?? 0
        case .peripheralLiningAdhesiveFacing: return adhesiveFacingConfiguration?.area ?? 0
        case .jointTreatment: return jointTreatmentConfiguration?.area ?? 0
        case .openings: return 0
        case .paintingBeta:
            guard case .paintingBeta(let configuration) = payload else { return 0 }
            return configuration.area
        }
    }
}

enum WorkTechnicalSummary {
    static func text(for work: WorkItem, catalogue: WorkSummaryCatalogue) -> String {
        var parts = [work.type.title]
        var facingIDs: [String] = []
        func number(_ value: Double, decimals: Int = 2) -> String {
            value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...decimals)))
        }
        func insulation(_ id: String, _ thickness: Double, lambda: Double? = nil) {
            guard !id.isEmpty else { return }
            let record = catalogue.records[id]
            let name = record?.data["material"]?.string ?? catalogue.name(id)
            var detail = name ?? ""
            if thickness.isFinite && thickness > 0 {
                detail += (detail.isEmpty ? "Isolant " : " ") + number(thickness) + " mm"
                if let lambda = lambda ?? ThermalCalculator.catalogueLambda(
                    conductivity: record?.data["conductivity"]?.string, lambda: record?.data["lambda_w_mk"]?.number),
                   let resistance = ThermalCalculator.resistance(thicknessMM: thickness, lambda: lambda) {
                    detail += " (R \(number(resistance)))"
                }
            }
            if !detail.isEmpty { parts.append(detail) }
        }
        switch work.payload {
        case .ceiling(let c):
            insulation(c.insulationID, c.insulationThickness)
            if c.insulationLayers == 2 { insulation(c.secondInsulationID ?? "", c.secondInsulationThickness ?? 0) }
            facingIDs = (c.firstSkin + (c.layers > 1 ? c.secondSkin : [])).map(\.facingID)
        case .railStudCeiling(let c):
            parts.append("R\(c.studWidth) + M\(c.studWidth)")
            if c.insulationEnabled {
                insulation(c.firstInsulation.seriesID, Double(c.firstInsulation.thickness))
                if c.insulationLayers == 2 { insulation(c.secondInsulation.seriesID, Double(c.secondInsulation.thickness)) }
            }
            facingIDs = (c.firstSkin + (c.facingLayers > 1 ? c.secondSkin : [])).map(\.productID)
        case .modularCeiling(let c): parts.append("Dalles \(c.tileFormat.title)")
        case .peripheralLining(let c):
            parts.append(c.frame)
            if c.insulationEnabled {
                insulation(c.firstInsulation.familyID, Double(c.firstInsulation.thicknessMM), lambda: c.firstInsulation.lambda)
                if c.insulationLayers == 2 { insulation(c.secondInsulation.familyID, Double(c.secondInsulation.thicknessMM), lambda: c.secondInsulation.lambda) }
            }
            facingIDs = (c.firstSkin + (c.layers > 1 ? c.secondSkin : [])).map(\.facingID)
        case .furringLining(let c):
            if c.insulationEnabled { insulation(c.firstInsulation.familyID, Double(c.firstInsulation.thicknessMM), lambda: c.firstInsulation.lambda) }
            facingIDs = (c.firstSkin + (c.layers > 1 ? c.secondSkin : []) + (c.layers > 2 ? c.thirdSkin : [])).map(\.facingID)
        case .distributionPartition(let c):
            parts.append(c.frame)
            if c.insulationEnabled { insulation(c.insulationID, Double(c.insulationThicknessMM)) }
            facingIDs = (c.faceAFirst + c.faceBFirst + (c.layers > 1 ? c.faceASecond + c.faceBSecond : [])).map(\.facingID)
        case .alveolarPartition(let c): facingIDs = c.panels.map(\.panelID)
        case .bondedLining(let c):
            // This product uses published complex R values, not an approximation e/lambda.
            if c.insulationThicknessMM > 0 {
                var detail = "Isolant \(c.insulationThicknessMM) mm"
                let complexes = catalogue.records.values.flatMap { $0.data["complexes"]?.array ?? [] }
                let resistance = complexes.compactMap(\.object).first {
                    $0["insulation_thickness_mm"]?.number == Double(c.insulationThicknessMM)
                    && abs(($0["lambda_w_mk"]?.number ?? 0) - c.lambda) < 0.0001
                }?["thermal_resistance_m2_kw"]?.number
                if let resistance, resistance.isFinite { detail += " (R \(number(resistance)))" }
                parts.append(detail)
            }
            parts += c.allocations.map { $0.facing.title }
        case .adhesiveFacing(let c): parts.append(c.facingFamily)
        case .jointTreatment(let c): parts.append(c.surface.title)
        case .openings: break
        case .paintingBeta:
            if let treatment = work.paintingBetaConfiguration?.treatment {
                if treatment.skimEnabled { parts.append("\(treatment.passes.count) passe(s) de ratissage") }
                if treatment.paintEnabled { parts.append("\(treatment.finishCoats) couche(s) de finition") }
            } else { parts.append("Traitements à renseigner") }
        }
        var seen = Set<String>()
        parts += facingIDs.compactMap { catalogue.name($0) }.filter { seen.insert($0).inserted }
        if work.area.isFinite && work.area > 0 { parts.append("\(number(work.area)) m²") }
        return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " • ")
    }
}
