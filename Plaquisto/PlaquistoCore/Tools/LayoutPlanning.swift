import Foundation
import CryptoKit

/// One readable label per displayed length and direction. Never changes quantities
/// or editable wall-distance callouts. Preferred indices are the visible segments.
enum LayoutDimensionLabels {
    static func representatives(_ lines: [LayoutJoint], preferred: Set<Int>) -> Set<Int> {
        var seen = Set<String>(), selected = Set<Int>()
        for i in lines.indices.filter({ preferred.contains($0) }) {
            let delta = lines[i].end - lines[i].start
            guard delta.length.isFinite, delta.length > 0 else { continue }
            var angle = atan2(delta.y, delta.x).truncatingRemainder(dividingBy: .pi)
            if angle < 0 { angle += .pi }
            let direction = Int((angle * 180 / .pi).rounded()) % 180
            let key = "\(Int(delta.length.rounded()))/\(direction)"
            if seen.insert(key).inserted { selected.insert(i) }
        }
        return selected
    }
}

enum LayoutCutQuality {
    /// Each connected cut piece is assessed separately, never its individual
    /// edges or tips. A narrow extension attached to a substantial board is OK.
    static func smallPieces(_ result: SheetLayoutResult) -> [LayoutCutPiece] {
        result.sheets.flatMap(\.pieces).filter {
            if $0.bounds.width < 300-0.01 || $0.bounds.height < 300-0.01 || $0.area < 300*300-0.01 { return true }
            let points=$0.contour
            // An oblique strip can have a large axis-aligned bounding box but
            // remain too narrow to handle. Check its width across every edge.
            return LayoutGeometry.edges(points).contains { edge in
                let d=edge.b-edge.a
                guard d.length>0.01 else { return false }
                let projections=points.map { ($0.x*d.y-$0.y*d.x)/d.length }
                return (projections.max()! - projections.min()!) < 300-0.01
            }
        }
    }
}

struct AutomaticLayoutRecord: Codable, Equatable {
    var configurationFingerprint: String
    var minimumSupplies: [LayoutQuantityLine]
    var warnings: [String]
}

enum AutomaticSurveyLayout {
    /// Re-read physical framing from saved plans so old cached opening lintels
    /// never survive a change of the opening rule. Count a partition only once.
    static func wallFramingMinimum(_ work:WorkItem) -> [LayoutQuantityLine]? {
        guard work.furringLiningConfiguration != nil || work.doublageConfiguration != nil || work.cloisonDistributionConfiguration != nil,
              !work.components.isEmpty else { return nil }
        var framing=0.0, angles=0.0, rails=0.0, sides=0.0, supports=0, splices=0
        for component in work.components {
            guard let plan=component.plans.first, plan.geometryRevision==component.geometryRevision,
                  let document=component.document(for:plan), document.surface.kind == .wall,
                  let layer=document.layers.first,
                  let result=try? SheetLayoutEngine.calculate(surface:document.surface,
                    layer:WorkLayoutDefaults.resolvingSupport(layer,configuration:work.payload)) else { return nil }
            let angleLines=result.furring.wallFixedProfiles.filter { $0.role == .rightAngle }.map(\.line)
            for line in result.furring.lines {
                let meters=(line.end-line.start).length/1000
                if angleLines.contains(where:{LayoutOpeningFraming.same($0,line)}) { angles += meters }
                else { framing += meters }
            }
            sides += result.furring.openingProfiles.filter { $0.role == .side }.reduce(0) { $0+($1.line.end-$1.line.start).length/1000 }
            rails += document.surface.bounds.width/1000*2
            supports += result.furring.supportPoints.count
            splices += result.furring.furringSpliceCount
        }
        if let c=work.furringLiningConfiguration {
            var rows:[LayoutQuantityLine]=[
                .init(name:"Fourrures F45/F47",quantity:framing*1.1,unit:"ml"),
                .init(name:"Cornière",quantity:angles*1.1,unit:"ml"),
                .init(name:c.supportSupplyName,quantity:Double(supports),unit:"unités")]
            if let source=c.quantities.first(where:{$0.name.lowercased().contains("lisses") || $0.name.lowercased().contains("rails pour fourrure")}) {
                rows.append(.init(name:source.name,quantity:rails*1.1,unit:source.unit))
            }
            if let source=c.quantities.first(where:{$0.name.lowercased().contains("éclisse")}) {
                rows.append(.init(name:source.name,quantity:Double(splices),unit:source.unit))
            }
            return rows
        }
        let frame=work.cloisonDistributionConfiguration?.frame ?? work.doublageConfiguration?.frame
        let doubled=work.cloisonDistributionConfiguration?.doubledStuds ?? work.doublageConfiguration?.doubledStuds ?? false
        return [.init(name:OpeningContext.profileName(frame:frame,rail:false),quantity:((framing-sides)*(doubled ? 2 : 1)+sides)*1.1,unit:"ml"),
                .init(name:OpeningContext.profileName(frame:frame,rail:true),quantity:rails*1.1,unit:"ml")]
    }

    static func refreshedMinimum(_ record:AutomaticLayoutRecord,work:WorkItem) -> [LayoutQuantityLine] {
        guard let framing=wallFramingMinimum(work) else { return record.minimumSupplies }
        let names=Set(framing.map { SupplyListingConsolidator.canonicalName($0.name) })
        return record.minimumSupplies.filter { !names.contains(SupplyListingConsolidator.canonicalName($0.name)) }+framing
    }

    struct Prepared {
        var sourceSurfaces: [Surface2D]
        var configurationFingerprint: String
        var components: [WorkComponentRecord]
        var record: AutomaticLayoutRecord
    }

    /// No I/O and no mutation of existing plans. The form runs this off the main
    /// actor, then the store revalidates the scan before committing atomically.
    static func prepare(_ work: WorkItem, formats: [LayoutCatalogFormat], catalogue: CeilingCataloguePayload?) throws -> Prepared {
        var generated = work
        if let configuration = work.modularCeilingConfiguration {
            _ = try ModularCeilingCalculator.scanned(configuration, surfaces: work.components.compactMap(\.surface))
            for i in generated.components.indices where generated.components[i].plans.isEmpty {
                guard let surface = generated.components[i].surface, generated.components[i].surveySource != nil else { continue }
                let layer = ModularCeilingCalculator.layoutLayer(configuration, surface: surface)
                generated.components[i].plans = [.init(layers: [layer], geometryRevision: generated.components[i].geometryRevision)]
            }
            let fingerprint = LayoutQuantityCalculator.configurationFingerprint(work)
            return .init(sourceSurfaces: work.components.compactMap(\.surface), configurationFingerprint: fingerprint,
                components: generated.components, record: .init(configurationFingerprint: fingerprint, minimumSupplies: [], warnings: []))
        }
        var warnings: [String] = []
        var boardCounts: [String: (LayoutLayer, Int)] = [:]
        var framing = 0.0, angles = 0.0, rails = 0.0, supports = 0, splices = 0
        for i in generated.components.indices {
            try Task.checkCancellation()
            guard let surface = generated.components[i].surface,
                  generated.components[i].surveySource != nil,
                  generated.components[i].plans.isEmpty else { continue }
            let configurations = skins(work.payload)
            guard !configurations.isEmpty else {
                if work.type != .paintingBeta {
                    warnings.append("\(surface.name) : ce système nécessite encore un calepinage manuel. Le quantitatif du formulaire est conservé.")
                }
                continue
            }
            let sides = work.isPartition ? [UUID(), UUID()] : []
            if !sides.isEmpty {
                generated.components[i].localLayoutSideIDs = sides
                generated.components[i].referenceSideRoomID = sides[0]
            }
            let groups = work.isPartition ? [configurations, skins(work.payload, opposite: true)] : [configurations]
            // Reject incomplete configurations before accumulating any quantities.
            guard groups.flatMap({ $0 }).allSatisfy({
                WorkLayoutDefaults.document(surface: surface, configuration: $0).layers.first?.catalogFormatID != nil
            }) else {
                warnings.append("\(surface.name) : choisissez les formats de toutes les peaux pour générer le calepinage.")
                continue
            }
            for (faceIndex, configurations) in groups.enumerated() {
            let surface = faceIndex == 0 ? surface : surface.mirroredComponentSide()
            var layers: [LayoutLayer] = []
            for (index, configuration) in configurations.enumerated() {
                var layer = WorkLayoutDefaults.document(surface: surface, configuration: configuration).layers[0]
                layer = WorkLayoutDefaults.resolvingFacing(layer, configuration: configuration, formats: formats)
                // Partition skins reuse the lining's facing configuration, not
                // its end-stud rule. Resolve framing from the actual ouvrage.
                layer = WorkLayoutDefaults.resolvingSupport(layer,configuration:work.payload)
                guard layer.catalogFormatID != nil else {
                    warnings.append("\(surface.name) : choisissez un format de plaque pour générer le calepinage.")
                    continue
                }
                let shared = index > 0 ? layers.first?.furring : faceIndex > 0 ? generated.components[i].framing : nil
                if var shared {
                    if faceIndex > 0 && index == 0 { shared.offset.negate() }
                    layer.furring = shared
                    layer = LayoutPlanning.alignBoards(to: layer, support: surface.kind)
                }
                layer = try LayoutPlanning.optimize(surface: surface, layer: layer, furring: false, alignFraming: shared == nil, lockFraming: shared != nil)
                let result = try SheetLayoutEngine.calculate(surface: surface, layer: layer)
                if !LayoutCutQuality.smallPieces(result).isEmpty {
                    warnings.append("\(surface.name) : des petites découpes isolées restent à vérifier autour du contour ou des ouvertures.")
                }
                if !LayoutPlanning.aligned(layer) {
                    warnings.append("\(surface.name) : le format des plaques et l’entraxe choisi nécessitent une vérification des jonctions.")
                }
                if index == 0, faceIndex == 0, surface.kind == .wall {
                    let horizontal = result.furring.openingProfiles.filter { $0.role == .horizontal }.map(\.line)
                        + result.furring.wallFixedProfiles.filter { $0.role == .rightAngle }.map(\.line)
                    for line in result.furring.lines {
                        let length = (line.end-line.start).length/1000
                        if horizontal.contains(where: { LayoutOpeningFraming.same($0, line) }) { angles += length }
                        else { framing += length }
                    }
                    rails += surface.bounds.width/1000*2
                    supports += result.furring.supportPoints.count
                    splices += result.furring.furringSpliceCount
                }
                layers.append(layer)
            }
            guard layers.count == configurations.count else { continue }
            if faceIndex == 0 { generated.components[i].framing = layers.first?.furring }
            for j in layers.indices { layers[j].furring = nil }
            generated.components[i].plans.append(.init(sideRoomID: sides.isEmpty ? nil : sides[faceIndex], layers: layers, geometryRevision: generated.components[i].geometryRevision))
            }
        }
        // Include preserved plans as well as newly generated ones when backfilling
        // an older ouvrage. Otherwise its previous board allowance would vanish.
        for component in generated.components {
            for plan in component.plans where plan.geometryRevision == component.geometryRevision {
                guard let document = component.document(for: plan) else { continue }
                for layer in document.layers {
                    guard let key = layer.catalogFormatID else { continue }
                    let result = try SheetLayoutEngine.calculate(surface: document.surface, layer: layer)
                    boardCounts[key] = (layer, (boardCounts[key]?.1 ?? 0) + result.purchasedSheetCount)
                }
            }
        }
        var minimum: [LayoutQuantityLine] = []
        if work.type.category == .ceilings, generated.hasSavedLayout, let catalogue {
            do {
                generated.layoutQuantityTakeoff = try LayoutQuantityCalculator.make(work: generated, formats: formats)
                minimum = CombinedQuantityCalculator.calculate(works: [generated], catalogue: catalogue).supplies.map {
                    .init(name: $0.name, quantity: $0.quantity, unit: $0.unit)
                }
            } catch { warnings.append(error.localizedDescription) }
        } else if generated.hasSavedLayout {
            let initial = storedSupplies(work.payload)
            for (_, entry) in boardCounts {
                let (layer, count) = entry
                guard let format = formats.first(where: { $0.id == layer.catalogFormatID }) else {
                    warnings.append("Quantité de plaques à vérifier : le nom du parement n’a pas pu être résolu."); continue
                }
                // Match both product and dimensions. Never merge two different
                // formats or add an unrelated generic board line to the order.
                func normalized(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: " ", with: "") }
                let dimensions = ["\(Int(layer.sheetWidth))x\(Int(layer.sheetLength))", "\(Int(layer.sheetWidth/10))x\(Int(layer.sheetLength/10))"]
                guard let source = initial.first(where: {
                    normalized(SupplyListingConsolidator.canonicalName($0.name)).contains(normalized(SupplyListingConsolidator.canonicalName(format.title))) && dimensions.contains(where: normalized($0.name).contains)
                }) else { warnings.append("\(format.title) : vérifiez la quantité, la référence du formulaire n’a pas pu être rapprochée du plan."); continue }
                let quantity = ceil(Double(count)*1.1)
                minimum.append(.init(name: source.name, quantity: source.unit == "m²" ? quantity*layer.sheetWidth*layer.sheetLength/1_000_000 : quantity, unit: source.unit))
            }
            if let c = work.furringLiningConfiguration {
                minimum += [.init(name: "Fourrures F45/F47", quantity: framing*1.1, unit: "ml"),
                            .init(name: "Cornière", quantity: angles*1.1, unit: "ml"),
                            .init(name: c.supportSupplyName, quantity: Double(supports), unit: "unités")]
                if let source = initial.first(where: { $0.name.lowercased().contains("lisses") || $0.name.lowercased().contains("rails pour fourrure") }) {
                    minimum.append(.init(name: source.name, quantity: rails*1.1, unit: "ml"))
                }
                if let source = initial.first(where: { $0.name.lowercased().contains("éclisse") }) {
                    minimum.append(.init(name: source.name, quantity: Double(splices), unit: source.unit))
                }
                if c.maximumSupportSpacing == nil { warnings.append("Appuis : règle de hauteur à compléter dans le formulaire.") }
            } else if let c = work.cloisonDistributionConfiguration {
                minimum += [.init(name: OpeningContext.profileName(frame: c.frame, rail: false), quantity: framing*(c.doubledStuds ? 2 : 1)*1.1, unit: "ml"),
                            .init(name: OpeningContext.profileName(frame: c.frame, rail: true), quantity: (rails+angles)*1.1, unit: "ml")]
            } else if let c = work.doublageConfiguration {
                minimum += [.init(name: OpeningContext.profileName(frame: c.frame, rail: false), quantity: framing*(c.doubledStuds ? 2 : 1)*1.1, unit: "ml"),
                            .init(name: OpeningContext.profileName(frame: c.frame, rail: true), quantity: (rails+angles)*1.1, unit: "ml")]
            }
        }
        if work.type.category == .ceilings && generated.hasSavedLayout && catalogue == nil {
            warnings.append("Quantitatif conservé : référentiel Admin indisponible pour comparer les fournitures.")
        }
        let fingerprint = LayoutQuantityCalculator.configurationFingerprint(work)
        var record = AutomaticLayoutRecord(configurationFingerprint: fingerprint, minimumSupplies: minimum, warnings: Array(Set(warnings)).sorted())
        record.minimumSupplies = refreshedMinimum(record,work:generated)
        return Prepared(sourceSurfaces: work.components.compactMap(\.surface), configurationFingerprint: fingerprint, components: generated.components, record: record)
    }

    private static func skins(_ payload: WorkConfiguration, opposite: Bool = false) -> [WorkConfiguration] {
        switch payload {
        case .distributionPartition(let c):
            return (0..<c.layers).map { index in
                var lining = DoublageConfiguration()
                lining.spacing = c.spacing; lining.frame = c.frame; lining.doubledStuds = c.doubledStuds
                let choices = opposite ? (index == 0 ? c.faceBFirst : c.faceBSecond) : (index == 0 ? c.faceAFirst : c.faceASecond)
                lining.firstSkin = choices.map { .init(facingID:$0.facingID,formatID:$0.formatID,surface:$0.surface) }
                return .peripheralLining(lining)
            }
        case .ceiling(let c): return (0..<c.layers).map { index in var c=c; c.firstSkin=index == 0 ? c.firstSkin : c.secondSkin; return .ceiling(c) }
        case .railStudCeiling(let c): return (0..<c.facingLayers).map { index in var c=c; c.firstSkin=index == 0 ? c.firstSkin : c.secondSkin; return .railStudCeiling(c) }
        case .peripheralLining(let c): return (0..<c.layers).map { index in var c=c; c.firstSkin=index == 0 ? c.firstSkin : c.secondSkin; return .peripheralLining(c) }
        case .furringLining(let c): return (0..<c.layers).map { index in var c=c; c.firstSkin=index == 0 ? c.firstSkin : index == 1 ? c.secondSkin : c.thirdSkin; return .furringLining(c) }
        default: return []
        }
    }
    private static func storedSupplies(_ payload: WorkConfiguration) -> [LayoutQuantityLine] {
        switch payload {
        case .furringLining(let c): return c.quantities.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        case .peripheralLining(let c): return c.quantities.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        case .distributionPartition(let c): return c.quantities.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        default: return []
        }
    }
}

enum LayoutQuantityCalculator {
    /// Formula-only estimate for the parts not yet laid out. The exact segment
    /// end count replaces it when a plan is approved.
    static func estimatedAdditionalEndHangers(_ configuration:CeilingConfiguration) -> Double {
        guard configuration.perimeterSupport == false, configuration.selectedSpacing>0 else { return 0 }
        let area=configuration.enteredArea ?? configuration.length*configuration.width
        let measuredCrossSpan=configuration.furringDirection == "width" ? configuration.length : configuration.width
        let crossSpan=configuration.dimensionsSpecified != false && measuredCrossSpan>0 ? measuredCrossSpan : sqrt(max(0,area))
        guard crossSpan.isFinite, crossSpan>0 else { return 0 }
        return 2*(ceil(crossSpan/configuration.selectedSpacing)+1)
    }
    struct Source: Encodable { var configuration:WorkConfiguration; var components:[WorkComponentRecord] }
    struct Unavailable: LocalizedError {
        var message:String
        var errorDescription:String? { message }
    }
    static func fingerprint(_ work:WorkItem) -> String {
        let encoder=JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard let data=try? encoder.encode(Source(configuration:work.payload,components:work.components)) else { return "" }
        return SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    }
    static func validated(_ work:WorkItem) -> LayoutQuantityTakeoff? {
        guard let takeoff=work.layoutQuantityTakeoff, takeoff.fingerprint == fingerprint(work) else { return nil }
        return takeoff
    }
    static func configurationFingerprint(_ work:WorkItem) -> String {
        let encoder=JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard let data=try? encoder.encode(work.payload) else { return "" }
        return SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    }
    /// Saved geometry is authoritative. Never keep an obsolete snapshot merely
    /// because the user has not approved it a second time.
    static func applicable(_ work:WorkItem) -> LayoutQuantityTakeoff? {
        guard work.layoutQuantityTakeoff != nil else { return nil }
        if let current=validated(work) { return current }
        return try? make(work:work,formats:[])
    }
    static func make(work:WorkItem, formats:[LayoutCatalogFormat]) throws -> LayoutQuantityTakeoff {
        let skins:Int, peripheral:Bool, supportSpacing:Double?, maxSpan:Double?, multiplier:Double
        switch work.payload {
        case .ceiling(let c):
            skins=c.layers; peripheral=c.perimeterSupport ?? true; supportSpacing=1.2; maxSpan=nil; multiplier=1
        case .railStudCeiling(let c):
            skins=c.facingLayers; peripheral=true; multiplier=c.assembly == "double" ? 2 : 1
            supportSpacing=c.frameMode == "suspended" ? c.suspensionSpacingMeters : nil
            maxSpan=c.frameMode == "selfSupporting" ? c.maximumSpanMeters : nil
            if c.frameMode == "suspended" && (supportSpacing == nil || c.suppliesPerSuspension == nil) || c.frameMode == "selfSupporting" && maxSpan == nil {
                throw Unavailable(message:"Enregistrez d’abord le formulaire rails/montants pour récupérer les distances admissibles de ce montage.")
            }
        default: throw Unavailable(message:"La reprise du quantitatif depuis le plan est disponible pour les plafonds sur fourrures ou rails/montants.")
        }
        guard !work.components.isEmpty else { throw Unavailable(message:"Aucun calepinage lié à cet ouvrage.") }
        guard work.area.isFinite, work.area>0 else { throw Unavailable(message:"Renseignez d’abord la surface totale de l’ouvrage pour répartir son quantitatif.") }
        var boards:[String:(String,Int)]=[:], area=0.0, framing=0.0, perimeter=0.0, hangers=0, splices=0
        var coveredAreaBySkin=Array(repeating:0.0,count:skins)
        let railStud=work.railStudCeilingConfiguration != nil
        for component in work.components {
            guard let plan=component.plans.first, plan.geometryRevision == component.geometryRevision,
                  let document=component.document(for:plan), document.surface.kind == .ceiling else { continue }
            // Use the same measured net area as scan-to-ouvrage conversion.
            // Board edge offsets affect purchases, not the share of the ouvrage.
            let componentArea=try document.surface.netMeasuredArea()/1_000_000
            for (i,storedLayer) in document.layers.prefix(skins).enumerated() {
                let layer = WorkLayoutDefaults.resolvingSupport(storedLayer,configuration:work.payload)
                let result=try SheetLayoutEngine.calculate(surface:document.surface,layer:layer)
                // Legacy rails/montants quantities aggregate both skins. Keep
                // their board estimate until every skin of this part is drawn.
                if !railStud || document.layers.count == skins {
                    let format=formats.first { $0.id == layer.catalogFormatID }
                    let key=layer.catalogFormatID ?? "\(layer.sheetWidth)x\(layer.sheetLength)"
                    let name=format.map { "\($0.title) · \(Int($0.width)) × \(Int($0.length)) mm" }
                        ?? work.layoutQuantityTakeoff?.boards.first(where: { $0.formatID == key })?.name
                        ?? "Plaques \(Int(layer.sheetWidth/10)) × \(Int(layer.sheetLength/10)) cm"
                    let previous=boards[key]?.1 ?? 0; boards[key]=(name,previous+result.purchasedSheetCount)
                    coveredAreaBySkin[i] += componentArea
                }
                if i == 0, layer.furring != nil {
                    let planPeripheral = railStud ? peripheral : (layer.furring?.ceilingPerimeterSupport ?? peripheral)
                    let planSupportSpacing = railStud ? supportSpacing : layer.furring.map { $0.resolvedCeilingSuspensionSpacing / 1000 }
                    if let spacing = planSupportSpacing, !spacing.isFinite || spacing <= 0 {
                        throw Unavailable(message:"Distance entre suspentes invalide dans le calepinage.")
                    }
                    if !railStud { splices += result.furring.furringSpliceCount }
                    area += componentArea
                    if planPeripheral { perimeter += LayoutGeometry.edges(document.surface.contour).reduce(0) { $0+($1.b-$1.a).length/1000 } }
                    for line in result.furring.lines {
                        let length=(line.end-line.start).length/1000
                        framing += length*multiplier
                        if let maxSpan, length > maxSpan+0.001 {
                            throw Unavailable(message:"Une ligne de montants dépasse la portée autoportante autorisée par le formulaire. Vérifiez le montage avant de reprendre le quantitatif.")
                        }
                        if let spacing=planSupportSpacing {
                            guard spacing.isFinite, spacing>0 else { throw Unavailable(message:"Distance entre suspentes invalide dans le formulaire.") }
                            let ends=[line.start,line.end].map(result.frame.world)
                            let boundarySupports=planPeripheral ? ends.filter { p in LayoutGeometry.edges(document.surface.contour).contains { LayoutGeometry.distance(p,to:$0.a,$0.b)<1 } }.count : 0
                            hangers += max(0,Int(ceil(max(0,length-0.000001)/spacing))+1-boundarySupports)
                        }
                    }
                }
            }
        }
        guard area>0 || coveredAreaBySkin.contains(where:{$0>0}) else {
            throw Unavailable(message:"Aucun calepinage exploitable : le quantitatif du formulaire reste disponible.")
        }
        return .init(fingerprint:fingerprint(work),area:area,
            boards:boards.keys.sorted().compactMap { key in boards[key].map { .init(name:$0.0,quantity:ceil(Double($0.1)*1.1),unit:"plaque(s)",formatID:key) } },
            framingMeters:framing*1.1,perimeterMeters:perimeter*1.1,hangers:hangers,furringSplices:railStud ? nil : splices,
            coverageFraction:min(1,area/work.area),boardCoverageFractions:coveredAreaBySkin.map { min(1,$0/work.area) },
            configurationFingerprint:configurationFingerprint(work))
    }
}

/// Initial values only: never applied to an existing component plan.
enum WorkLayoutDefaults {
    /// Only for the first, unsplit component of a dimensioned ouvrage. Never
    /// infer a rectangle from area alone or overwrite scan/user geometry.
    static func firstComponent(name: String, configuration: WorkConfiguration) -> WorkComponentRecord {
        let length: Double, width: Double, specified: Bool
        switch configuration {
        case .railStudCeiling(let value):
            length = value.length; width = value.width; specified = value.dimensionsSpecified
        case .ceiling(let value):
            length = value.length; width = value.width; specified = value.dimensionsSpecified != false
        default: return WorkComponentRecord(name:name)
        }
        guard specified, length.isFinite, width.isFinite, length > 0, width > 0,
              length <= 100, width <= 100 else { return WorkComponentRecord(name:name) }
        let surface = Surface2D(name:name,kind:.ceiling,
            contour:LayoutPreset.rectangle.contour(length:length * 1000,height:width * 1000,secondaryHeight:0))
        return WorkComponentRecord(name:name,surface:surface)
    }

    static func document(surface: Surface2D, configuration: WorkConfiguration) -> LayoutDocument {
        var document = LayoutDocument.newSupport(surface)
        var formats: [(id: String, area: Double)] = []
        var spacing: Double?
        switch configuration {
        case .ceiling(let value):
            formats = value.firstSkin.map { ($0.dimensionID, $0.area) }
            spacing = value.selectedSpacing
            document.layers[0].furring?.peripheralInset = value.perimeterSupport == false ? 100 : nil
        case .railStudCeiling(let value):
            formats = value.firstSkin.map { ($0.dimensionID, $0.area) }
            spacing = 0.6 // This configurator uses fixed 60 cm stud centres.
        case .peripheralLining(let value):
            formats = value.firstSkin.map { ($0.formatID, $0.surface) }
            spacing = value.spacing
        case .furringLining(let value):
            formats = value.firstSkin.map { ($0.formatID, $0.surface) }
            spacing = value.furringSpacing
        default: return .init(surface:surface)
        }
        let totals = formats.reduce(into: [String: Double]()) { $0[$1.id, default: 0] += max(0, $1.area) }
        let primary = totals.keys.sorted().max { totals[$0, default: 0] < totals[$1, default: 0] }
        if let primary {
            let dimensions = primary.split(separator: "x").compactMap { Double($0) }
            if dimensions.count == 2, dimensions.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 }) {
                document.layers[0].sheetWidth = dimensions[0]
                document.layers[0].sheetLength = dimensions[1]
            }
            switch configuration {
            case .ceiling(let value):
                document.layers[0].fourTaperedEdges = value.firstSkin.filter { $0.dimensionID == primary }.max { $0.area < $1.area }?.fourTaperedEdges
            case .railStudCeiling(let value):
                document.layers[0].fourTaperedEdges = value.firstSkin.filter { $0.dimensionID == primary }.max { $0.area < $1.area }?.fourTaperedEdges
            default: break
            }
        }
        // Never silently replace the ouvrage's technical spacing choice.
        if let spacing, spacing.isFinite, spacing > 0 { document.layers[0].furring?.spacing = spacing * 1000 }
        document.layers[0] = resolvingFacing(document.layers[0], configuration: configuration, formats: [])
        return document
    }
    private struct Facing {
        var productID: String
        var dimensionID: String
        var area: Double
        var fourTaperedEdges: Bool?
    }

    private static func facing(configuration: WorkConfiguration, layer: LayoutLayer) -> Facing? {
        let choices: [Facing]
        switch configuration {
        case .ceiling(let value):
            choices = value.firstSkin.map { Facing(productID:$0.facingID,dimensionID:$0.dimensionID,area:$0.area,fourTaperedEdges:$0.fourTaperedEdges) }
        case .railStudCeiling(let value):
            choices = value.firstSkin.map { Facing(productID:$0.productID,dimensionID:$0.dimensionID,area:$0.area,fourTaperedEdges:$0.fourTaperedEdges) }
        case .peripheralLining(let value):
            choices = value.firstSkin.map { Facing(productID:$0.facingID,dimensionID:$0.formatID,area:$0.surface,fourTaperedEdges:nil) }
        case .furringLining(let value):
            choices = value.firstSkin.map { Facing(productID:$0.facingID,dimensionID:$0.formatID,area:$0.surface,fourTaperedEdges:nil) }
        default: return nil
        }
        return choices.filter {
            let dimensions = $0.dimensionID.split(separator:"x").compactMap { Double($0) }
            return !$0.productID.isEmpty && dimensions.count == 2
                && abs(dimensions[0] - layer.sheetWidth) < 0.001
                && abs(dimensions[1] - layer.sheetLength) < 0.001
        }.max { $0.area < $1.area }
    }

    /// Resolve by product AND dimensions, never by dimensions alone. Explicit
    /// manual/catalogue changes made in the plan take precedence over the ouvrage.
    static func resolvingFacing(_ layer: LayoutLayer, configuration: WorkConfiguration?, formats: [LayoutCatalogFormat]) -> LayoutLayer {
        let layer = resolvingSupport(layer,configuration:configuration)
        guard layer.manualFacing != true else { return layer }
        var result = layer
        if let configuration, let choice = facing(configuration:configuration,layer:layer) {
            let id = LayoutCatalogFormat.identifier(productID:choice.productID,width:layer.sheetWidth,length:layer.sheetLength)
            if result.catalogFormatID == nil { result.catalogFormatID = id }
            if result.catalogFormatID == id, let edges = choice.fourTaperedEdges {
                result.fourTaperedEdges = edges
            }
        }
        if let format = formats.first(where: { $0.id == result.catalogFormatID
            && abs($0.width-result.sheetWidth) < 0.001 && abs($0.length-result.sheetLength) < 0.001 }) {
            result.fourTaperedEdges = format.fourTaperedEdges
        }
        return result
    }
    static func resolvingSupport(_ layer:LayoutLayer, configuration:WorkConfiguration?) -> LayoutLayer {
        var result=layer
        if case .ceiling(let value) = configuration {
            // Nil is the legacy/default furring system; do not rewrite otherwise
            // unchanged manual plans just to materialize this default.
            result.furring?.isFurringSystem = nil
            let peripheral = result.furring?.ceilingPerimeterSupport ?? value.perimeterSupport ?? true
            result.furring?.peripheralInset = peripheral ? nil : 100
        }
        if case .railStudCeiling = configuration { result.furring?.isFurringSystem = false }
        if case .distributionPartition = configuration { result.furring?.liningEndStudInset = nil }
        if case .peripheralLining = configuration {
            result.furring?.openingSystem = .studs
            result.furring?.isFurringSystem = false
            result.furring?.liningEndStudInset = 100
        }
        if case .furringLining(let value) = configuration {
            result.furring?.isFurringSystem = true
            result.furring?.openingSystem = .furring
            result.furring?.intermediateSupportLines = value.selectedSupportLines
            result.furring?.includesHorizontalSupportFurring = value.includesHorizontalSupportFurring ?? true
            result.furring?.maximumSupportSpacing = value.maximumSupportSpacing.map { $0*1000 }
            result.furring?.firstSupportHeightWhenMultiple = value.firstSupportHeightWhenMultiple.map { $0*1000 }
        }
        return result
    }
    // Resolve older ouvrages that predate the persisted edge information, using
    // product identity, not guesses based on the board dimensions or display name.
    static func fourTaperedEdges(configuration: WorkConfiguration, layer: LayoutLayer, formats:[LayoutCatalogFormat]) -> Bool? {
        guard let choice = facing(configuration:configuration,layer:layer) else { return nil }
        return formats.first { $0.productID == choice.productID }?.fourTaperedEdges ?? choice.fourTaperedEdges
    }
}

enum LayoutVisibilityState: Int, CaseIterable {
    case visible, dimensioned, hidden
    var isVisible: Bool { self != .hidden }
    var showsDimensions: Bool { self == .dimensioned }
    var next: Self { Self(rawValue:(rawValue+1)%3)! }
}

struct LayoutVisibilitySettings {
    enum Element: String, CaseIterable {
        case sheets, framing, openings, electrical
        var title: String {
            switch self {
            case .sheets: return "Plaques"
            case .framing: return "Ossature"
            case .openings: return "Ouvertures"
            case .electrical: return "Électricité"
            }
        }
    }
    var sheets = LayoutVisibilityState.visible
    var framing = LayoutVisibilityState.visible
    var openings = LayoutVisibilityState.visible
    var electrical = LayoutVisibilityState.visible
    var angles = false
    var sheetNumbers = false

    subscript(element: Element) -> LayoutVisibilityState {
        get {
            switch element {
            case .sheets: return sheets
            case .framing: return framing
            case .openings: return openings
            case .electrical: return electrical
            }
        }
        set {
            switch element {
            case .sheets: sheets = newValue
            case .framing: framing = newValue
            case .openings: openings = newValue
            case .electrical: electrical = newValue
            }
        }
    }
    var dimensionedElement: Element? { Element.allCases.first { self[$0].showsDimensions } }
    /// One dimension layer at a time, in toolbar order; hidden layers are skipped.
    /// After the last visible layer, dimensions turn off rather than wrapping.
    mutating func cycleDimensions() {
        let elements = Element.allCases
        let start = dimensionedElement.flatMap { elements.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let next = elements.dropFirst(start).first { self[$0].isVisible }
        for element in elements where self[element].isVisible { self[element] = element == next ? .dimensioned : .visible }
    }
    mutating func toggleVisibility(_ element: Element) {
        let wasDimensioned = self[element].showsDimensions
        if wasDimensioned { cycleDimensions() }
        self[element] = self[element].isVisible ? .hidden : .visible
    }
}

extension LayoutDocument {
    /// Only new supports receive a starter frame. Saved plans keep their choices,
    /// including an explicitly absent frame, when reopened.
    static func newSupport(_ surface:Surface2D) -> Self {
        var layer = LayoutLayer(furring:.init()).forSurface(surface)
        if surface.kind == .ceiling {
            // Standard ceiling starter configuration: 240 × 120 cm boards are
            // compatible with 60 cm furring centres in both board orientations.
            layer.sheetWidth = 1200
            layer.sheetLength = 2400
            layer.furring?.spacing = 600
            layer.referenceEdge = LayoutPlanning.longestReferenceEdge(surface)
            layer.orientation = .vertical // Long dimension perpendicular to the reference wall.
        } else {
            let spacing = LayoutPlanning.compatibleSpacings(layer).last ?? 400
            layer.furring?.spacing = spacing
        }
        return .init(surface:surface,layers:[layer])
    }
}

enum LayoutElectricalKind: String, Codable, CaseIterable {
    case light = "Lumière", socket = "Prise"
    var prefix: String { self == .socket ? "P" : "L" }
}
struct LayoutLighting: Codable, Equatable {
    var count = 6
    var spread = 0.75
    var diameter = 68.0
    var positions: [LayoutPoint] = []
    var kinds: [LayoutElectricalKind]? = nil
    var dicePattern: Bool? = nil
    var perpendicularToFurring: Bool? = nil
    // Optional fields keep older saved manual layouts decodable, unchanged.
    var widthSpread: Double? = nil
    var lengthSpread: Double? = nil
    var twelveSpotGrid: LayoutTwelveSpotGrid? = nil
    /// Guide heights in millimetres above the wall's floor; independent of points.
    var wallRowHeights: [Double]? = nil
    var resolvedWidthSpread: Double { widthSpread ?? spread }
    var resolvedLengthSpread: Double { lengthSpread ?? spread }
    func kind(at index:Int) -> LayoutElectricalKind { kinds?.indices.contains(index) == true ? kinds![index] : .light }
    func label(at index:Int, wall:Bool) -> String { "\(wall ? kind(at:index).prefix : "S")\(index+1)" }
}

enum LayoutTwelveSpotGrid: String, Codable, CaseIterable {
    case sixByTwo, fourByThree, threeByFour
    var columns: Int { switch self { case .sixByTwo: return 6; case .fourByThree: return 4; case .threeByFour: return 3 } }
    var rows: Int { 12 / columns }
    var title: String { "\(columns) × \(rows)" }
}

enum LayoutSpotArrangement: String, CaseIterable {
    case horizontal = "Aligner horizontalement", vertical = "Aligner verticalement"
    case distributeX = "Répartir horizontalement", distributeY = "Répartir verticalement"
    var minimumCount: Int { self == .horizontal || self == .vertical ? 2 : 3 }
}

enum LayoutLightingEditError: Error, LocalizedError {
    case invalidPlacement
    var errorDescription: String? { "Placement impossible : les points doivent rester dans le mur ou le plafond, hors des ouvertures et sans se chevaucher." }
}

enum LayoutWallLighting {
    static func heights(_ lighting:LayoutLighting?,surface:Surface2D) -> [Double] {
        let values=lighting?.wallRowHeights ?? lighting?.positions.map { $0.y-surface.bounds.min.y } ?? []
        return Array(Set(values.filter { $0.isFinite && $0>0 && $0<surface.bounds.height })).sorted()
    }
    static func rowSegments(height:Double,surface:Surface2D) -> [LayoutJoint] {
        let y=surface.bounds.min.y+height
        return LayoutOpeningFraming.clip(.init(start:.init(x:surface.bounds.min.x,y:y),end:.init(x:surface.bounds.max.x,y:y)),to:surface)
    }
    static func addingRow(_ lighting:LayoutLighting?,height:Double,surface:Surface2D) throws -> LayoutLighting {
        guard surface.kind == .wall, height.isFinite, height>0, height<surface.bounds.height,
              !rowSegments(height:height,surface:surface).isEmpty else { throw LayoutLightingEditError.invalidPlacement }
        var copy=lighting ?? .init(count:0)
        copy.wallRowHeights=Array(Set(heights(lighting,surface:surface)+[height])).sorted()
        return copy
    }
    static func snapped(_ point:LayoutPoint,lighting:LayoutLighting?,surface:Surface2D,tolerance:Double) -> LayoutPoint {
        guard surface.kind == .wall, let height=heights(lighting,surface:surface).min(by:{
            abs(surface.bounds.min.y+$0-point.y)<abs(surface.bounds.min.y+$1-point.y)
        }), abs(surface.bounds.min.y+height-point.y)<=tolerance else { return point }
        return .init(x:point.x,y:surface.bounds.min.y+height)
    }
    /// Actual outer wall limits at this height, not the opening's edges or the
    /// bounding rectangle of a sloped/stepped wall.
    static func span(at point:LayoutPoint,surface:Surface2D) -> LayoutJoint? {
        var outer=surface; outer.openings=[]
        return rowSegments(height:point.y-surface.bounds.min.y,surface:outer).first {
            point.x >= $0.start.x-0.01 && point.x <= $0.end.x+0.01
        }
    }
    static func positioning(_ lighting:LayoutLighting,index:Int,distance:Double,fromRight:Bool,surface:Surface2D) throws -> LayoutLighting {
        guard lighting.positions.indices.contains(index), distance.isFinite, distance>=0,
              let limits=span(at:lighting.positions[index],surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        var copy=lighting
        copy.wallRowHeights=heights(lighting,surface:surface)
        copy.positions[index].x=fromRight ? limits.end.x-distance : limits.start.x+distance
        guard LayoutPlanning.lightingFits(copy,surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        return copy
    }
}

struct LayoutWallDimension: Identifiable {
    var id: String
    var start: LayoutPoint
    var end: LayoutPoint
    var distance: Double { (end-start).length }
}

enum LayoutPlanning {
    static func framingFrame(surface:Surface2D,layer:LayoutLayer) -> LayoutGridFrame {
        var copy=layer
        if layer.furring?.usesOwnReference == true {
            copy.referenceEdge=layer.furring?.referenceEdge
            copy.inheritedGridFrame=layer.furring?.inheritedGridFrame
        }
        let base=LayoutGridFrame.make(surface:surface,layer:copy)
        return .init(origin:base.origin,angle:base.angle+(alongX(layer) ? 0 : Double.pi/2))
    }
    /// Lightweight geometry only: no board cutting/stock optimisation during gestures.
    static func worldFurring(surface:Surface2D,layer:LayoutLayer) -> LayoutFurringResult {
        let frame=LayoutGridFrame.make(surface:surface,layer:layer)
        var local=surface
        local.contour=surface.contour.map(frame.local)
        local.openings=surface.openings.map { var o=$0; o.contour=o.contour.map(frame.local); return o }
        guard let result=try? LayoutFurringEngine.calculate(surface:local,layer:layer,gridFrame:frame) else { return .init() }
        func world(_ l:LayoutJoint) -> LayoutJoint { .init(start:frame.world(l.start),end:frame.world(l.end)) }
        return .init(lines:result.lines.map(world),contacts:result.contacts.map {
            .init(point:frame.world($0.point),edgeIndex:$0.edgeIndex,distance:$0.distance)
        },peripheralLines:result.peripheralLines.map(world),
        openingProfiles:result.openingProfiles.map { .init(line:world($0.line),role:$0.role) },
        supportPoints:result.supportPoints.map(frame.world),
        wallFixedProfiles:result.wallFixedProfiles.map { .init(line:world($0.line),role:$0.role) })
    }
    static func snappedFurringOffset(_ layer:LayoutLayer,surface:Surface2D,joints:[LayoutJoint],tolerance:Double) -> Double? {
        guard let f=layer.furring, f.spacing>0 else { return nil }
        let frame=framingFrame(surface:surface,layer:layer)
        // Rotating the frame by 90° reverses its transverse coordinate.
        let sign=alongX(layer) ? 1.0 : -1.0
        var best:Double?
        for joint in joints {
            let a=frame.local(joint.start), b=frame.local(joint.end)
            guard abs(b.y-a.y)<1, abs(b.x-a.x)>1 else { continue }
            let coordinate=(a.y+b.y)/2*sign
            let delta=coordinate-f.offset-((coordinate-f.offset)/f.spacing).rounded()*f.spacing
            if abs(delta)<=tolerance, best == nil || abs(delta)<abs(best!) { best=delta }
        }
        return best.map { f.offset+$0 }
    }
    static func snappedOpeningSupport(_ layer:LayoutLayer, surface:Surface2D, tolerance:Double) -> Double? {
        guard surface.kind == .wall, let f=layer.furring, let system=f.openingSystem, f.spacing>0 else { return nil }
        let deltas=LayoutOpeningFraming.profiles(surface:surface,system:system).filter { $0.role == .side }.map {
            ($0.line.start.x-f.offset).remainder(dividingBy:f.spacing)
        }.filter { abs($0)<=tolerance }
        return deltas.min(by:{abs($0)<abs($1)}).map { f.offset+$0 }
    }
    /// Only the regular frame is a plate-alignment target. Opening reinforcements
    /// cannot attract a board joint, even though they are drawn in the same layer.
    static func snappedWallBoards(_ layer:LayoutLayer, surface:Surface2D, tolerance:Double) -> LayoutLayer {
        guard surface.kind == .wall, layer.furring != nil, layer.cellWidth>0 else { return layer }
        let geometry=worldFurring(surface:surface,layer:layer)
        let deltas=geometry.lines.filter { !geometry.fixedLines.contains($0) && abs($0.end.x-$0.start.x)<0.5 }.map {
            ($0.start.x-layer.offset.x).remainder(dividingBy:layer.cellWidth)
        }.filter { abs($0)<=tolerance }
        guard let delta=deltas.min(by:{abs($0)<abs($1)}) else { return layer }
        var copy=layer; copy.offset.x += delta; return copy
    }

    /// Closest regular supports to the board joints; fixed perimeter supports
    /// are never moved by editing one of these dimensions.
    static func junctionSupports(lines:[LayoutJoint],fixed:[LayoutJoint],joints:[LayoutJoint],spacing:Double) -> [LayoutJoint] {
        var result:[LayoutJoint]=[]
        for joint in joints {
            let d=joint.end-joint.start, length=d.length
            guard length>1 else { continue }
            let u=d*(1/length), middle=(joint.start+joint.end)*0.5
            let choices=lines.filter { line in
                let v=line.end-line.start
                return !fixed.contains(line) && v.length>1 && abs(v.x*u.y-v.y*u.x)/v.length<0.001 &&
                    min((line.end-middle).x*u.x+(line.end-middle).y*u.y,(line.start-middle).x*u.x+(line.start-middle).y*u.y)<length/2 &&
                    max((line.end-middle).x*u.x+(line.end-middle).y*u.y,(line.start-middle).x*u.x+(line.start-middle).y*u.y) > -length/2
            }
            func distance(_ l:LayoutJoint)->Double { let p=(l.start+l.end)*0.5-middle; return abs(p.x*u.y-p.y*u.x) }
            if let nearest=choices.min(by:{distance($0)<distance($1)}), distance(nearest)<=spacing/2+1,
               !result.contains(nearest) { result.append(nearest) }
        }
        return result
    }
    static func settingFurringDistance(_ layer:LayoutLayer,surface:Surface2D,dimension:LayoutWallDimension,distance:Double) throws -> LayoutLayer {
        guard distance.isFinite, distance>0, dimension.distance>0, let original=layer.furring else { throw LayoutGeometryError.invalidFormat }
        let ray=(dimension.end-dimension.start)*(1/dimension.distance)
        let delta=ray*(dimension.distance-distance)
        let frame=framingFrame(surface:surface,layer:layer)
        var result=layer
        result.furring?.offset=original.offset+frame.vector(delta).y*(alongX(layer) ? 1 : -1)
        let geometry=worldFurring(surface:surface,layer:result), target=dimension.start+delta
        guard geometry.lines.contains(where:{ line in
            !geometry.peripheralLines.contains(line) && LayoutGeometry.distance(target,to:line.start,line.end)<1 &&
            framingWallDimensions(line,surface:surface).contains { d in
                let v=d.end-d.start
                return v.x*ray.x+v.y*ray.y>0 && abs(d.distance-distance)<1
            }
        }) else { throw LayoutGeometryError.invalidContour }
        return result
    }
    static func hitSupport(_ point:LayoutPoint, surface:Surface2D) -> Bool {
        LayoutGeometry.contains(point,in:surface.contour)
            && !surface.openings.contains { LayoutGeometry.contains(point,in:$0.contour) }
    }
    static func isJunction(_ line:LayoutJoint, joints:[LayoutJoint]) -> Bool {
        let d=line.end-line.start, length=d.length
        guard length>1 else { return false }
        let u=d*(1/length)
        return joints.contains { joint in
            let a=joint.start-line.start, b=joint.end-line.start
            guard abs(a.x*u.y-a.y*u.x)<1, abs(b.x*u.y-b.y*u.x)<1 else { return false }
            let x=a.x*u.x+a.y*u.y, y=b.x*u.x+b.y*u.y
            return min(length,max(x,y))-max(0,min(x,y))>1
        }
    }
    static func framingWallDimensions(_ line:LayoutJoint, surface:Surface2D) -> [LayoutWallDimension] {
        let middle=(line.start+line.end)*0.5, d=line.end-line.start
        guard d.length>1 else { return [] }
        let n=LayoutPoint(x:-d.y/d.length,y:d.x/d.length)
        return [-1.0,1.0].compactMap { sign in
            let ray=n*sign
            let hits=LayoutGeometry.edges(surface.contour).compactMap { edge -> Double? in
                let e=edge.b-edge.a, v=edge.a-middle, cross=ray.x*e.y-ray.y*e.x
                guard abs(cross)>0.00001 else { return nil }
                let t=(v.x*e.y-v.y*e.x)/cross, s=(v.x*ray.y-v.y*ray.x)/cross
                return t>0.5 && s>=0 && s<=1 ? t : nil
            }
            guard let distance=hits.min() else { return nil }
            return .init(id:"\(sign)",start:middle,end:middle+ray*distance)
        }
    }
    static func longestReferenceEdge(_ surface: Surface2D) -> Int? {
        surface.contour.indices.max {
            (surface.contour[($0+1)%surface.contour.count]-surface.contour[$0]).length <
            (surface.contour[($1+1)%surface.contour.count]-surface.contour[$1]).length
        }
    }

    /// Layout coordinates are y-up. Traversal therefore follows polygon winding,
    /// not array order (RoomPlan can supply either winding).
    static func nextReferenceEdge(_ surface: Surface2D, current: Int?, clockwise: Bool) -> Int? {
        let count = surface.contour.count
        guard count > 1 else { return nil }
        let current = current.flatMap { surface.contour.indices.contains($0) ? $0 : nil }
            ?? longestReferenceEdge(surface) ?? 0
        let ccw = LayoutGeometry.area(surface.contour) > 0
        let step = clockwise == ccw ? -1 : 1
        return (current + step + count) % count
    }

    static func centeredLighting(_ lighting:LayoutLighting, selected:Set<Int>, surface:Surface2D) throws -> LayoutLighting {
        let points = selected.sorted().filter { lighting.positions.indices.contains($0) }.map { lighting.positions[$0] }
        guard !points.isEmpty else { return lighting }
        var delta = surface.bounds.center-LayoutBounds(points:points).center
        if surface.kind == .wall { delta.y = 0 }
        let copy = translatedLighting(lighting,indices:selected,delta:delta)
        guard lightingFits(copy,surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        return copy
    }
    static func addingSpot(to lighting:LayoutLighting?, at point:LayoutPoint, surface:Surface2D, kind:LayoutElectricalKind = .light) throws -> LayoutLighting {
        var copy = lighting ?? .init()
        if surface.kind == .wall, copy.wallRowHeights == nil {
            let previous=LayoutWallLighting.heights(lighting,surface:surface)
            copy.wallRowHeights=previous.isEmpty ? [point.y-surface.bounds.min.y] : previous
        }
        copy.kinds = copy.positions.indices.map { copy.kind(at:$0) } + [kind]
        copy.positions.append(point); copy.count = copy.positions.count
        guard lightingFits(copy,surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        return copy
    }
    static func addingWallRow(to lighting:LayoutLighting?, count:Int, height:Double, kind:LayoutElectricalKind, surface:Surface2D) throws -> LayoutLighting {
        guard surface.kind == .wall, (1...64).contains(count), height.isFinite, height > 0 else { throw LayoutLightingEditError.invalidPlacement }
        let y = surface.bounds.min.y + height
        let intervals = LayoutGeometry.edges(surface.contour).compactMap { edge -> Double? in
            let d = edge.b-edge.a
            guard abs(d.y) > 0.001 else { return nil }
            let t = (y-edge.a.y)/d.y
            return t >= 0 && t < 1 ? edge.a.x+t*d.x : nil
        }.sorted()
        guard let first = intervals.first, let last = intervals.last, last-first > 1 else { throw LayoutLightingEditError.invalidPlacement }
        var copy:LayoutLighting? = try LayoutWallLighting.addingRow(lighting,height:height,surface:surface)
        for i in 0..<count {
            let point = LayoutPoint(x:first+(last-first)*Double(i+1)/Double(count+1),y:y)
            copy = try addingSpot(to:copy,at:point,surface:surface,kind:kind)
        }
        return copy!
    }
    static func rotatedLighting(_ lighting:LayoutLighting, selected:Set<Int>, angle:Double) -> LayoutLighting {
        let indices = selected.filter { lighting.positions.indices.contains($0) }
        guard !indices.isEmpty else { return lighting }
        let center = indices.reduce(LayoutPoint.zero) { $0 + lighting.positions[$1] } * (1/Double(indices.count))
        var copy = lighting
        for i in indices {
            let d = lighting.positions[i]-center
            copy.positions[i] = center + .init(x:d.x*cos(angle)-d.y*sin(angle),y:d.x*sin(angle)+d.y*cos(angle))
        }
        return copy
    }
    static func scaledLighting(_ lighting:LayoutLighting, selected:Set<Int>, factor:Double) -> LayoutLighting {
        scaledLighting(lighting,selected:selected,widthFactor:factor,lengthFactor:factor,frame:.init())
    }
    static func scaledLighting(_ lighting:LayoutLighting, selected:Set<Int>, widthFactor:Double, lengthFactor:Double, frame:LayoutGridFrame) -> LayoutLighting {
        let indices = selected.filter { lighting.positions.indices.contains($0) }
        guard !indices.isEmpty, widthFactor.isFinite, widthFactor > 0,
              lengthFactor.isFinite, lengthFactor > 0 else { return lighting }
        let center = indices.reduce(LayoutPoint.zero) { $0+lighting.positions[$1] }*(1/Double(indices.count))
        let localCenter = frame.local(center)
        var copy = lighting
        for i in indices {
            let delta = frame.local(lighting.positions[i])-localCenter
            copy.positions[i] = frame.world(localCenter + .init(x:delta.x*widthFactor,y:delta.y*lengthFactor))
        }
        return copy
    }
    /// Adjust the saved positions themselves, including any individual manual edits.
    static func adjustedLighting(_ lighting:LayoutLighting, from previous:LayoutLighting, to settings:LayoutLighting, frame:LayoutGridFrame) -> LayoutLighting {
        var previousFrame = frame
        if previous.perpendicularToFurring == true { previousFrame.angle += .pi/2 }
        let selected = Set(lighting.positions.indices)
        var copy = lighting
        if previous.resolvedWidthSpread != settings.resolvedWidthSpread || previous.resolvedLengthSpread != settings.resolvedLengthSpread {
            copy = scaledLighting(copy,selected:selected,
                widthFactor:settings.resolvedWidthSpread/previous.resolvedWidthSpread,
                lengthFactor:settings.resolvedLengthSpread/previous.resolvedLengthSpread,frame:previousFrame)
        }
        if (previous.perpendicularToFurring == true) != (settings.perpendicularToFurring == true) {
            copy = rotatedLighting(copy,selected:selected,angle:settings.perpendicularToFurring == true ? .pi/2 : -.pi/2)
        }
        copy.widthSpread = settings.widthSpread; copy.lengthSpread = settings.lengthSpread
        copy.spread = settings.spread; copy.diameter = settings.diameter
        copy.perpendicularToFurring = settings.perpendicularToFurring
        return copy
    }
    static func lightingDirection(_ lighting:LayoutLighting, selected:Set<Int>) -> Double? {
        let indices = selected.filter { lighting.positions.indices.contains($0) }.sorted()
        var nearest:LayoutPoint?
        for i in indices {
            for j in indices where j > i {
                let d = lighting.positions[j]-lighting.positions[i]
                if d.length > 1 && d.length < (nearest?.length ?? .infinity) { nearest = d }
            }
        }
        return nearest.map { atan2($0.y,$0.x) }
    }
    static func snappedLightingRotation(_ candidate:Double, lighting:LayoutLighting, selected:Set<Int>, contour:[LayoutPoint], latched:Double?) -> (angle:Double,latch:Double?) {
        if let latched, abs(candidate-latched) <= 5 * .pi/180 { return (latched,latched) }
        guard let direction = lightingDirection(lighting,selected:selected) else { return (candidate,nil) }
        let targets = LayoutGeometry.edges(contour).filter { ($0.b-$0.a).length > 1 }.map { edge in
            let d = edge.b-edge.a, wall = atan2(d.y,d.x)
            return ((candidate+direction-wall)/(.pi/2)).rounded()*(.pi/2)+wall-direction
        }
        if let target = targets.min(by:{abs($0-candidate)<abs($1-candidate)}), abs(target-candidate) <= 2.5 * .pi/180 { return (target,target) }
        return (candidate,nil)
    }
    static func lightingFits(_ settings: LayoutLighting, surface: Surface2D) -> Bool {
        guard (surface.kind == .wall ? 0...64 : 1...64).contains(settings.count), settings.positions.count == settings.count,
              settings.diameter.isFinite, (10...500).contains(settings.diameter),
              settings.positions.allSatisfy(\.finite) else { return false }
        for i in settings.positions.indices {
            for j in settings.positions.indices where j > i {
                if (settings.positions[i]-settings.positions[j]).length < settings.diameter+10-0.001 { return false }
            }
        }
        return settings.positions.allSatisfy { p in
            LayoutGeometry.contains(p,in:surface.contour)
            && !surface.openings.contains { LayoutGeometry.contains(p,in:$0.contour) }
            && ([surface.contour]+surface.openings.map(\.contour)).allSatisfy { loop in
                LayoutGeometry.edges(loop).allSatisfy { LayoutGeometry.distance(p,to:$0.a,$0.b) >= settings.diameter/2+10 }
            }
        }
    }

    static func translatedLighting(_ lighting:LayoutLighting, indices:Set<Int>, delta:LayoutPoint) -> LayoutLighting {
        var copy = lighting
        for i in indices where copy.positions.indices.contains(i) { copy.positions[i] = copy.positions[i] + delta }
        return copy
    }

    static func arrangedLighting(_ lighting:LayoutLighting, selected:Set<Int>, reference:Int?, action:LayoutSpotArrangement, surface:Surface2D, frame:LayoutGridFrame? = nil) throws -> LayoutLighting {
        if let frame {
            var local=surface, lights=lighting
            local.contour=surface.contour.map(frame.local)
            local.openings=surface.openings.map { var o=$0; o.contour=o.contour.map(frame.local); return o }
            lights.positions=lighting.positions.map(frame.local)
            var arranged=try arrangedLighting(lights,selected:selected,reference:reference,action:action,surface:local)
            arranged.positions=arranged.positions.map(frame.world)
            return arranged
        }
        let indices = selected.filter { lighting.positions.indices.contains($0) }.sorted()
        guard indices.count >= action.minimumCount else { return lighting }
        let anchor = reference.flatMap { indices.contains($0) ? $0 : nil } ?? indices[0]
        var copy = lighting
        switch action {
        case .horizontal: for i in indices { copy.positions[i].y = lighting.positions[anchor].y }
        case .vertical: for i in indices { copy.positions[i].x = lighting.positions[anchor].x }
        case .distributeX, .distributeY:
            let x = action == .distributeX
            func coordinate(_ i:Int) -> Double { x ? lighting.positions[i].x : lighting.positions[i].y }
            let sorted = indices.sorted { coordinate($0) == coordinate($1) ? $0 < $1 : coordinate($0) < coordinate($1) }
            let first = coordinate(sorted[0]), last = coordinate(sorted[sorted.count-1])
            for (rank,i) in sorted.enumerated() {
                let value = first+(last-first)*Double(rank)/Double(sorted.count-1)
                if x { copy.positions[i].x = value } else { copy.positions[i].y = value }
            }
        }
        guard lightingFits(copy,surface:surface) else { throw LayoutLightingEditError.invalidPlacement }
        return copy
    }

    static func snappedLightingDelta(_ lighting:LayoutLighting, selected:Set<Int>, anchor:Int, delta:LayoutPoint, tolerance:Double) -> (delta:LayoutPoint, guides:[LayoutPoint]) {
        guard lighting.positions.indices.contains(anchor) else { return (delta,[]) }
        let proposed = lighting.positions[anchor]+delta
        let others = lighting.positions.indices.filter { !selected.contains($0) }
        var result = delta, guides:[LayoutPoint] = []
        if let i = others.min(by:{abs(lighting.positions[$0].x-proposed.x) < abs(lighting.positions[$1].x-proposed.x)}), abs(lighting.positions[i].x-proposed.x) <= tolerance {
            result.x += lighting.positions[i].x-proposed.x; guides.append(lighting.positions[i])
        }
        if let i = others.min(by:{abs(lighting.positions[$0].y-proposed.y) < abs(lighting.positions[$1].y-proposed.y)}), abs(lighting.positions[i].y-proposed.y) <= tolerance {
            result.y += lighting.positions[i].y-proposed.y; guides.append(lighting.positions[i])
        }
        return (result,guides)
    }
    static func localSurface(_ surface:Surface2D, frame:LayoutGridFrame) -> Surface2D {
        var copy = surface; copy.contour = copy.contour.map(frame.local)
        copy.openings = copy.openings.map { var o = $0; o.contour = o.contour.map(frame.local); return o }
        return copy
    }

    // Each corner is projected normally onto each wall segment. Retain visible
    // feet only: concave boundaries must not be crossed en route to a far wall.
    static func wallDimensions(points:[LayoutPoint], surface:Surface2D) -> [LayoutWallDimension] {
        let edges = LayoutGeometry.edges(surface.contour)
        var result: [LayoutWallDimension] = []
        for (j,p) in points.enumerated() {
            for (i,e) in edges.enumerated() {
                let d = e.b-e.a, squared = LayoutGeometry.dot(d,d)
                guard squared > 0 else { continue }
                let t = LayoutGeometry.dot(p-e.a,d)/squared
                guard t >= 0, t <= 1 else { continue }
                let foot = e.a+d*t
                guard (foot-p).length > 0.1 else { continue }
                let crossings = edges.flatMap { LayoutGeometry.splitParameters(.init(a:p,b:foot),by:$0) }
                guard !crossings.contains(where:{$0 > 0.00001 && $0 < 0.99999}),
                      LayoutGeometry.contains((p+foot)*0.5,in:surface.contour) else { continue }
                result.append(.init(id:"\(j)-\(i)",start:p,end:foot))
            }
        }
        return result
    }

    static func alongX(_ layer:LayoutLayer) -> Bool {
        layer.resolvedFurringOrientation == .horizontal
    }
    static func crossingDimension(_ layer:LayoutLayer) -> Double { alongX(layer) ? layer.cellHeight : layer.cellWidth }
    static func compatibleSpacings(_ layer:LayoutLayer) -> [Double] {
        [400.0,500.0,600.0].filter { spacing in
            let count = crossingDimension(layer)/spacing
            return count >= 1 && abs(count-count.rounded()) < 0.00001
        }
    }
    static func alignFurring(to layer:LayoutLayer) -> LayoutLayer {
        var copy = layer
        if var f = copy.furring {
            f.referenceEdge = layer.referenceEdge; f.usesOwnReference = true
            f.inheritedGridFrame = layer.inheritedGridFrame
            f.offset = alongX(copy) ? copy.offset.y : copy.offset.x; copy.furring = f
        }
        return copy
    }
    /// Shared action for the normal and full-screen toolbars. The active tab
    /// provides the reference: framing moves boards, boards moves the frame.
    static func alignOtherLayer(_ layer:LayoutLayer, surface:Surface2D, framingMode:Bool) -> LayoutLayer {
        guard framingMode else { return alignFurring(to:layer) }
        if surface.kind == .wall { return snappedWallBoards(layer,surface:surface,tolerance:.infinity) }
        return alignBoards(to:layer,support:surface.kind)
    }
    static func alignBoards(to layer:LayoutLayer, support:LayoutSupportKind) -> LayoutLayer {
        var copy = layer
        if let f = layer.furring {
            if support == .ceiling, f.usesOwnReference == true {
                copy.referenceEdge = f.referenceEdge
                copy.inheritedGridFrame = f.inheritedGridFrame
            }
            let current = alongX(layer) ? layer.offset.y : layer.offset.x
            let target: Double
            if support == .ceiling {
                // Offsets live in the reference edge's local grid coordinates.
                // Compatible board dimensions are multiples of spacing, so all
                // parallel joints share this phase. Preserve the chosen grid
                // period and move by at most half one furring spacing.
                guard current.isFinite, f.offset.isFinite, f.spacing.isFinite,
                      compatibleSpacings(layer).contains(f.spacing) else { return layer }
                let delta = (f.offset - current).remainder(dividingBy: f.spacing)
                guard abs(delta) > 0.000001 else { return copy }
                target = current + delta
            } else {
                guard current.isFinite, f.offset.isFinite, f.spacing>0 else { return layer }
                target = current + (f.offset-current).remainder(dividingBy:f.spacing)
            }
            if alongX(layer) { copy.offset.y = target } else { copy.offset.x = target }
        }
        return copy
    }
    static func aligned(_ layer:LayoutLayer) -> Bool {
        guard let f = layer.furring, compatibleSpacings(layer).contains(f.spacing) else { return layer.furring == nil }
        if f.usesOwnReference == true && f.referenceEdge != layer.referenceEdge { return false }
        let delta = (alongX(layer) ? layer.offset.y : layer.offset.x)-f.offset
        return abs(delta/f.spacing-(delta/f.spacing).rounded()) < 0.00001
    }

    static let automaticSpotCounts = [1,2,3,4,6,8,9,10,12]

    static func spotGrid(_ count:Int, twelve:LayoutTwelveSpotGrid = .sixByTwo) -> (columns:Int,rows:Int)? {
        switch count {
        case 1,2,3: return (count,1)
        case 4,6,8,10: return (count/2,2)
        case 9: return (3,3)
        case 12: return (twelve.columns,twelve.rows)
        default: return nil
        }
    }
    static func spotPattern(_ count:Int, twelve:LayoutTwelveSpotGrid = .sixByTwo) -> [LayoutPoint]? {
        guard let grid = spotGrid(count,twelve:twelve) else { return nil }
        return (0..<grid.rows).flatMap { row in (0..<grid.columns).map { column in
            LayoutPoint(x:grid.columns == 1 ? 0 : Double(column)*2/Double(grid.columns-1)-1,
                        y:grid.rows == 1 ? 0 : Double(row)*2/Double(grid.rows-1)-1)
        } }
    }
    static func lighting(_ settings:LayoutLighting, surface:Surface2D, layer:LayoutLayer? = nil) throws -> LayoutLighting {
        guard (1...64).contains(settings.count), (0.2...1.2).contains(settings.spread),
              (0.2...1.2).contains(settings.resolvedWidthSpread), (0.2...1.2).contains(settings.resolvedLengthSpread),
              settings.diameter.isFinite, (10...500).contains(settings.diameter) else { throw LayoutGeometryError.invalidFormat }
        if let pattern=spotPattern(settings.count,twelve:settings.twelveSpotGrid ?? .sixByTwo) {
            var frame=layer.map { framingFrame(surface:surface,layer:$0) } ?? .init()
            if settings.perpendicularToFurring == true { frame.angle += .pi/2 }
            let bounds=LayoutBounds(points:surface.contour.map(frame.local))
            var centers=[bounds.center]
            for row in 0..<7 { for col in 0..<7 {
                let x=bounds.min.x+bounds.width*Double(col+1)/8
                let y=bounds.min.y+bounds.height*Double(row+1)/8
                centers.append(.init(x:x,y:y))
            } }
            // Keep the requested rows, columns and count in awkward footprints.
            for shrink in [1.0,0.85,0.7,0.55,0.4] {
                let dx=max(0,bounds.width-settings.diameter-20)*settings.resolvedWidthSpread*shrink/2
                let dy=max(0,bounds.height-settings.diameter-20)*settings.resolvedLengthSpread*shrink/2
                for center in centers {
                    var copy=settings
                    copy.positions=pattern.map { frame.world(center + .init(x:$0.x*dx,y:$0.y*dy)) }
                    if lightingFits(copy,surface:surface) { return copy }
                }
            }
            throw LayoutLightingEditError.invalidPlacement
        }
        let b = surface.bounds, radius = settings.diameter/2
        func valid(_ p:LayoutPoint) -> Bool {
            LayoutGeometry.contains(p,in:surface.contour) && !surface.openings.contains { LayoutGeometry.contains(p,in:$0.contour) }
            && ([surface.contour]+surface.openings.map(\.contour)).allSatisfy { loop in
                LayoutGeometry.edges(loop).allSatisfy { LayoutGeometry.distance(p,to:$0.a,$0.b) >= radius+10 }
            }
        }
        var best: [LayoutPoint] = [], bestScore = Double.infinity
        for rows in 1...settings.count {
            let cols = Int(ceil(Double(settings.count)/Double(rows)))
            let dx = b.width/Double(cols)*settings.spread, dy = b.height/Double(rows)*settings.spread
            guard min(dx,dy) > settings.diameter+10 else { continue }
            var points: [LayoutPoint] = []
            for row in 0..<rows {
                let n = settings.count/rows+(row < settings.count%rows ? 1 : 0)
                for col in 0..<n {
                    points.append(b.center + .init(x:(Double(col)-Double(n-1)/2)*dx,y:(Double(row)-Double(rows-1)/2)*dy))
                }
            }
            let score = abs(log(max(0.001,dx/dy)))
            if points.allSatisfy(valid), score < bestScore { best = points; bestScore = score }
        }
        if best.isEmpty {
            // Deterministic farthest-point fallback for concave rooms. Never drop
            // spots silently or put holes outside the ceiling / inside a hatch.
            var candidates: [LayoutPoint] = []
            for y in 0..<25 { for x in 0..<25 {
                let p = b.center + .init(x:(Double(x)/24-0.5)*b.width*settings.spread,
                                        y:(Double(y)/24-0.5)*b.height*settings.spread)
                if valid(p) { candidates.append(p) }
            } }
            if let first = candidates.min(by:{($0-b.center).length < ($1-b.center).length}) { best = [first] }
            while best.count < settings.count {
                guard let p = candidates.max(by:{ a,z in
                    (best.map{($0-a).length}.min() ?? 0) < (best.map{($0-z).length}.min() ?? 0)
                }), best.allSatisfy({($0-p).length > settings.diameter+10}) else { throw LayoutGeometryError.invalidContour }
                best.append(p)
            }
        }
        var copy = settings; copy.positions = best; return copy
    }

    // Bounded deterministic offset search, not an assertion of global optimality.
    // Once aligned, moving either grid keeps the shared joint phase aligned.
    static func optimize(surface:Surface2D, layer:LayoutLayer, furring:Bool, alignFraming:Bool = false, lockFraming:Bool = false) throws -> LayoutLayer {
        let layer = alignFraming ? alignFurring(to: layer.forSurface(surface)) : layer.forSurface(surface)
        var best = layer
        let initial = try SheetLayoutEngine.calculate(surface:surface,layer:layer)
        func score(_ result:SheetLayoutResult) -> (Double,Double,Double) {
            if furring { return (0,result.furring.lines.reduce(0){$0+($1.end-$1.start).length},Double(result.furring.lines.count)) }
            return (Double(LayoutCutQuality.smallPieces(result).count),Double(result.purchasedSheetCount),result.wasteArea)
        }
        func better(_ a:(Double,Double,Double), than b:(Double,Double,Double)) -> Bool {
            if abs(a.0-b.0)>0.01 { return a.0<b.0 }
            if abs(a.1-b.1)>0.01 { return a.1<b.1 }
            return a.2+0.01<b.2
        }
        var bestScore = score(initial)
        if furring, let settings=layer.furring {
            // Retain an existing joint-support phase. Removing an edge line by
            // shifting the frame must not leave the board joints unsupported.
            if aligned(layer) { return layer }
            // Only translate the framing in its own reference frame. Never move
            // the boards as a side effect of optimizing the framing.
            for offset in [settings.offset] + (0..<25).map({ Double($0)*settings.spacing/25 }) {
                try Task.checkCancellation()
                var candidate=layer; candidate.furring?.offset=offset
                guard let result=try? SheetLayoutEngine.calculate(surface:surface,layer:candidate) else { continue }
                let value=score(result)
                if better(value,than:bestScore) {
                    best=candidate; bestScore=value
                }
            }
            return best
        }
        let b = localSurface(surface,frame:.make(surface:surface,layer:layer)).bounds
        // Include exact wall-aligned starts in addition to uniform samples.
        let xs = [layer.offset.x,b.min.x,b.max.x,(b.min.x+b.max.x-layer.cellWidth)/2,b.min.x+300,b.max.x-300] + (0..<9).map{Double($0)*layer.cellWidth/9}
        let ys = [layer.offset.y,b.min.y,b.max.y,(b.min.y+b.max.y-layer.cellHeight)/2,b.min.y+300,b.max.y-300] + (0..<9).map{Double($0)*layer.cellHeight/9}
        for x in xs { for y in ys {
            try Task.checkCancellation()
            var candidate = layer; candidate.offset = .init(x:x,y:y)
            if lockFraming { candidate = alignBoards(to:candidate,support:surface.kind) }
            if layer.furring != nil && (alignFraming || layer.furring?.usesOwnReference != true) { candidate = alignFurring(to:candidate) }
            guard let result = try? SheetLayoutEngine.calculate(surface:surface,layer:candidate) else { continue }
            let value = score(result)
            if better(value,than:bestScore) { best = candidate; bestScore = value }
        } }
        // Refine the stagger after the bounded offset search. Test only shifts
        // compatible with the frame, without multiplying the entire search.
        if !furring, layer.staggered == true {
            let base = best
            for shift in LayoutBoardGrid.staggerChoices(base).prefix(8) {
                try Task.checkCancellation()
                var candidate=base; candidate.staggerOffset=shift
                guard let result=try? SheetLayoutEngine.calculate(surface:surface,layer:candidate) else { continue }
                let value=score(result)
                if better(value,than:bestScore) {
                    best=candidate; bestScore=value
                }
            }
        }
        return best
    }
}

extension Surface2D {
    func changingVertex(remove index:Int? = nil, insertAfter edge:Int? = nil, point:LayoutPoint? = nil) throws -> Surface2D {
        let old = editableIntent
        var indices = Array(contour.indices).map{Optional($0)}
        var points = contour
        if let index {
            guard points.count > 3, points.indices.contains(index) else { throw LayoutGeometryError.invalidContour }
            points.remove(at:index); indices.remove(at:index)
        } else if let edge, let point {
            guard points.count < 200, points.indices.contains(edge) else { throw LayoutGeometryError.invalidContour }
            points.insert(point,at:edge+1); indices.insert(nil,at:edge+1)
        }
        try LayoutGeometry.validate(points)
        var copy = self, intent = LayoutContourIntent(sketch:points)
        let oldIDs = stableEdgeIDs
        copy.edgeIDs = indices.indices.map { i in
            if let source = indices[i], indices[(i+1)%indices.count] == (source+1)%contour.count { return oldIDs[source] }
            return UUID().uuidString
        }
        copy.layingOffset.individualMM = layingOffset.individualMM.filter { copy.edgeIDs.contains($0.key) }
        copy.topologyID = UUID()
        var locks: [Int] = []
        for i in points.indices {
            guard let source = indices[i] else { continue }
            let next = indices[(i+1)%points.count], prev = indices[(i+points.count-1)%points.count]
            intent.userVertexPositions[i] = old.userVertexPositions[source]
            if next == (source+1)%contour.count {
                intent.userMeasuredLengths[i] = old.userMeasuredLengths[source]
                if old.lockedLengthIndices?.contains(source) == true { locks.append(i) }
            }
            if next == (source+1)%contour.count && prev == (source+contour.count-1)%contour.count {
                intent.userAnglesDegrees[i] = old.userAnglesDegrees[source]
            }
        }
        intent.lockedLengthIndices = locks
        copy.previousContourIntents.append(old)
        copy.edgeTones = indices.map { i in i.flatMap { edgeTones.indices.contains($0) ? edgeTones[$0] : nil } ?? .teal }
        try copy.resolve(intent)
        _ = try copy.layingContour()
        return copy
    }
}
