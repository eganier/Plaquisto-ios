import Foundation
import SwiftUI

enum StockFamily: String, Codable, CaseIterable, Identifiable {
    case boards = "Plaques et panneaux", frames = "Ossatures métalliques", supports = "Suspentes et appuis"
    case insulation = "Isolation et membranes", screws = "Vis et fixations"
    case coatings = "Bandes, enduits et colles", paints = "Peintures"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .boards: "rectangle.portrait"
        case .frames: "line.3.horizontal"
        case .supports: "link"
        case .insulation: "square.3.layers.3d"
        case .screws: "screwdriver"
        case .coatings: "paintbrush.pointed"
        case .paints: "paintbrush"
        }
    }
    static func classify(_ name: String) -> Self {
        let n = name.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"fr_FR"))
        if n.contains("suspente") || n.contains("appui") || n.contains("hourdis") || n.contains("tige") || n.contains("eclisse") { return .supports }
        if n.contains("enduit") || n.contains("bande") || n.contains("colle") || n.contains("mastic") || n.contains("adhesif") { return .coatings }
        if n.contains("peinture") || n.contains("impression") { return .paints }
        if n.contains("vis ") || n.contains("cheville") || n.contains("fixation") { return .screws }
        if n.contains("rail") || n.contains("montant") || n.contains("fourrure") || n.contains("lisse") || n.contains("corniere") { return .frames }
        if n.contains("isol") || n.contains("laine") || n.contains("biosource") || n.contains("vapeur") || n.contains("membrane") { return .insulation }
        return .boards
    }
}

struct StockProduct: Codable, Identifiable, Equatable {
    var name: String
    var unit: String
    var family: StockFamily
    var referenceID: String?
    var variant: String?
    var subcategory:String {
        let n = name.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"fr_FR"))
        switch family {
        case .boards:
            if n.contains("dalle") { return "Dalles de plafond" }
            if n.contains("complexe") { return "Complexes de doublage" }
            return n.contains("ba") ? "Plaques de plâtre" : "Plaques spécifiques"
        case .frames:
            for (word,label) in [("rail","Rails"),("montant","Montants"),("fourrure","Fourrures"),("lisse","Lisses"),("corniere","Cornières")] where n.contains(word) { return label }
            return "Plafonds démontables"
        case .supports:
            if n.contains("appui") { return "Appuis intermédiaires" }
            if n.contains("hourdis") { return "Attaches hourdis" }
            if n.contains("composite") { return "Suspentes composites" }
            if n.contains("galvanis") { return "Suspentes galvanisées" }
            return "Tiges et accessoires"
        case .insulation:
            if n.contains("vapeur") || n.contains("membrane") { return "Pare-vapeur et membranes" }
            if n.contains("verre") { return "Laine de verre" }
            if n.contains("roche") { return "Laine de roche" }
            if n.contains("biosource") || n.contains("chanvre") || n.contains("bois") { return "Biosourcés" }
            return "Isolants rigides"
        case .screws:
            if n.contains("ttpc") { return "Vis pour plaques" }
            return n.contains("vis") ? "Vis pour ossatures" : "Fixations au support"
        case .coatings:
            if n.contains("armee") { return "Bandes armées" }
            if n.contains("bande") { return "Bandes à joint" }
            if n.contains("joint") { return "Enduits à joints" }
            if n.contains("enduit") { return "Enduits de préparation / ratissage" }
            return n.contains("colle") ? "Mortiers-colles" : "Mastics et adhésifs"
        case .paints: return n.contains("impression") ? "Impressions" : "Peintures de finition"
        }
    }
    // Exact name/unit identity also supports unpriced supplies. No fuzzy substitutions.
    var id: String { Self.identity(name:name,unit:unit) }
    static func identity(name:String,unit:String) -> String {
        SupplyListingConsolidator.canonicalName(name).trimmingCharacters(in:.whitespacesAndNewlines)
            + "|" + Self.unit(unit)
    }
    static func unit(_ value:String) -> String {
        let canonical = SupplyListingConsolidator.canonicalUnit(value)
        return canonical == "unités" || canonical == "unité" ? "unité" : canonical
    }
    init(name:String,unit:String,family:StockFamily? = nil,referenceID:String? = nil,variant:String? = nil) {
        self.name = SupplyListingConsolidator.canonicalName(name)
        self.unit = Self.unit(unit); self.family = family ?? .classify(name)
        self.referenceID = referenceID; self.variant = variant
    }
}

struct StockEntry: Codable, Identifiable {
    var product: StockProduct
    var quantity: Double = 0
    var packName: String = "boîte"
    var packSize: Double = 1
    var usesPack = false
    var id: String { product.id }
}
struct StockReservation: Codable, Identifiable {
    var id = UUID()
    var productID: String
    var projectID: UUID
    var projectName: String
    var quantity: Double
}
struct StockEvent: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var productName: String
    var unit: String
    var before: Double
    var after: Double
    var reservedBefore: Double
    var reservedAfter: Double
    var projectName: String?
    var actor = "Moi"
}
struct StockArchive: Codable {
    var version = 1
    var entries: [StockEntry] = []
    var reservations: [StockReservation] = []
    var events: [StockEvent] = []
    /// Remap known purchasing aliases without losing physical stock or reservations.
    /// Loading is read-only; the normalized archive is persisted at the next operation.
    func normalizingProductNames() throws -> Self {
        var copy=self, products:[String:StockEntry]=[:], oldIDs=Set<String>(), aliases:[String:String]=[:]
        for entry in entries {
            let oldID=entry.product.name.trimmingCharacters(in:.whitespacesAndNewlines)+"|"+StockProduct.unit(entry.product.unit)
            guard oldIDs.insert(oldID).inserted, entry.quantity.isFinite, entry.quantity>=0,
                  entry.packSize.isFinite, entry.packSize>0 else { throw StockFailure.unreadable }
            var item=entry
            item.product=StockProduct(name:entry.product.name,unit:entry.product.unit,family:entry.product.family,referenceID:entry.product.referenceID,variant:entry.product.variant)
            aliases[oldID]=item.id
            if var existing=products[item.id] {
                existing.quantity += item.quantity
                guard existing.quantity.isFinite else { throw StockFailure.unreadable }
                if existing.packName != item.packName || existing.packSize != item.packSize || existing.usesPack != item.usesPack {
                    existing.usesPack=false; existing.packSize=1
                }
                if existing.product.referenceID != item.product.referenceID || existing.product.variant != item.product.variant {
                    existing.product.referenceID=nil; existing.product.variant=nil
                }
                products[item.id]=existing
            } else { products[item.id]=item }
        }
        copy.entries=products.values.sorted { $0.product.name.localizedStandardCompare($1.product.name) == .orderedAscending }
        copy.reservations=reservations.map { reservation in
            var result=reservation
            result.productID=aliases[reservation.productID] ?? reservation.productID
            return result
        }
        return copy
    }
}
enum StockMovement: String, CaseIterable, Identifiable {
    var allowsProjectAssignment: Bool { self == .exit }
    case entry = "Entrée", exit = "Sortie", inventory = "Inventaire"
    var id:String { rawValue }
    var symbol:String { self == .entry ? "plus" : self == .exit ? "minus" : "checkmark" }
}
enum StockFailure: LocalizedError {
    case invalid, unavailable, unreadable, missing
    var errorDescription:String? {
        switch self {
        case .invalid: "Renseignez une quantité valide, positive ou nulle pour un inventaire, et un conditionnement supérieur à zéro."
        case .unavailable: "Quantité indisponible : une partie du stock est réservée. Ajustez la quantité ou annulez la réservation concernée."
        case .unreadable: "Le fichier de stock ne peut pas être lu. Il est conservé sans modification ; aucune écriture n’est autorisée."
        case .missing: "Cette référence ou réservation n’existe plus."
        }
    }
}

@MainActor final class StockStore: ObservableObject {
    static let shared = StockStore()
    @Published private(set) var archive = StockArchive()
    @Published private(set) var loadError: String?
    private let fileURL: URL
    @Published private var undoState: StockArchive?
    var canUndo: Bool { undoState != nil }
    var entries:[StockEntry] { archive.entries }
    var reservations:[StockReservation] { archive.reservations }
    var events:[StockEvent] { archive.events.reversed() }
    var lastUpdatedAt:Date? { archive.events.last?.date }
    init(fileURL:URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Plaquisto/stock-v1.json")
        guard FileManager.default.fileExists(atPath:self.fileURL.path) else { return }
        do {
            let value = try JSONDecoder().decode(StockArchive.self,from:Data(contentsOf:self.fileURL)).normalizingProductNames()
            guard value.version == 1,
                  Set(value.entries.map(\.id)).count == value.entries.count,
                  value.entries.allSatisfy({ $0.quantity.isFinite && $0.quantity >= 0 && $0.packSize.isFinite && $0.packSize > 0 }),
                  value.reservations.allSatisfy({ r in r.quantity.isFinite && r.quantity > 0 && value.entries.contains { $0.id == r.productID } }) else { throw StockFailure.unreadable }
            archive = value
        } catch { loadError = StockFailure.unreadable.localizedDescription }
    }
    func entry(_ id:String) -> StockEntry? { entries.first { $0.id == id } }
    func reserved(_ id:String,excluding project:UUID? = nil) -> Double {
        reservations.filter { $0.productID == id && (project == nil || $0.projectID != project) }.reduce(0) { $0+$1.quantity }
    }
    func available(_ id:String,for project:UUID? = nil) -> Double {
        max(0,(entry(id)?.quantity ?? 0)-reserved(id,excluding:project))
    }
    private func save(_ next:StockArchive) throws {
        guard loadError == nil else { throw StockFailure.unreadable }
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:fileURL,options:.atomic)
        undoState = archive
        archive = next
    }
    func undoLast() throws {
        guard var previous = undoState else { return }
        previous.events = archive.events
        for item in entries {
            let old = previous.entries.first { $0.id == item.id }
            let reservation = previous.reservations.filter { $0.productID == item.id }.reduce(0) { $0+$1.quantity }
            if item.quantity != (old?.quantity ?? 0) || reserved(item.id) != reservation {
                previous.events.append(.init(title:"Dernière opération annulée",productName:item.product.name,unit:item.product.unit,before:item.quantity,after:old?.quantity ?? 0,reservedBefore:reserved(item.id),reservedAfter:reservation,projectName:nil))
            }
        }
        try save(previous)
        undoState = nil
    }
    func move(_ kind:StockMovement,product:StockProduct,quantity:Double,packName:String,packSize:Double,usesPack:Bool,projectID:UUID? = nil,projectName:String? = nil) throws {
        guard quantity.isFinite, quantity >= 0, (kind == .inventory || quantity > 0),
              packSize.isFinite, packSize > 0, !product.name.trimmingCharacters(in:.whitespaces).isEmpty else { throw StockFailure.invalid }
        var next = archive
        var item = entry(product.id) ?? StockEntry(product:product)
        let before = item.quantity, oldReserved = reserved(product.id)
        if kind == .exit {
            guard quantity <= available(product.id,for:projectID)+0.000001 else { throw StockFailure.unavailable }
            if let projectID {
                var remaining = quantity
                for i in next.reservations.indices where next.reservations[i].productID == product.id && next.reservations[i].projectID == projectID {
                    let taken = min(remaining,next.reservations[i].quantity)
                    next.reservations[i].quantity -= taken; remaining -= taken
                }
                next.reservations.removeAll { $0.quantity < 0.000001 }
            }
        }
        item.quantity = kind == .inventory ? quantity : max(0,before + (kind == .entry ? quantity : -quantity))
        guard item.quantity.isFinite else { throw StockFailure.invalid }
        item.packName = packName; item.packSize = packSize; item.usesPack = usesPack
        if let i = next.entries.firstIndex(where: { $0.id == product.id }) { next.entries[i] = item } else { next.entries.append(item) }
        next.events.append(.init(title:kind.rawValue,productName:product.name,unit:product.unit,before:before,after:item.quantity,
            reservedBefore:oldReserved,reservedAfter:next.reservations.filter { $0.productID == product.id }.reduce(0) { $0+$1.quantity },projectName:kind.allowsProjectAssignment ? projectName : nil))
        try save(next)
    }
    /// Sets quantities for these references only, never accumulating repeat taps.
    /// All lines are validated before a single atomic save.
    func reserve(projectID:UUID,projectName:String,quantities:[String:Double]) throws {
        var next = archive
        for (id,quantity) in quantities {
            guard let item = entry(id), quantity.isFinite, quantity >= 0 else { throw StockFailure.invalid }
            guard quantity <= available(id,for:projectID)+0.000001 else { throw StockFailure.unavailable }
            let before = reserved(id)
            next.reservations.removeAll { $0.productID == id && $0.projectID == projectID }
            if quantity > 0 { next.reservations.append(.init(productID:id,projectID:projectID,projectName:projectName,quantity:quantity)) }
            let after = next.reservations.filter { $0.productID == id }.reduce(0) { $0+$1.quantity }
            if abs(after-before) > 0.000001 {
                next.events.append(.init(title:"Réservation",productName:item.product.name,unit:item.product.unit,before:item.quantity,after:item.quantity,reservedBefore:before,reservedAfter:after,projectName:projectName))
            }
        }
        try save(next)
    }
    func cancel(_ reservation:StockReservation) throws {
        guard reservations.contains(where: { $0.id == reservation.id }), let item = entry(reservation.productID) else { throw StockFailure.missing }
        var next = archive
        next.reservations.removeAll { $0.id == reservation.id }
        let before = reserved(item.id)
        next.events.append(.init(title:"Réservation annulée",productName:item.product.name,unit:item.product.unit,before:item.quantity,after:item.quantity,reservedBefore:before,reservedAfter:before-reservation.quantity,projectName:reservation.projectName))
        try save(next)
    }
}

enum StockQuantity {
    static func packed(complete: Double, partial: Double, size: Double) -> Double? {
        guard complete.isFinite, complete >= 0, partial.isFinite, (0...1).contains(partial), size.isFinite, size > 0 else { return nil }
        let total = (complete + partial) * size
        return total.isFinite ? total : nil
    }
    static func text(_ value:Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    static func input(_ value:Double) -> String {
        let text = String(value)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text).replacingOccurrences(of:".",with:",")
    }
    static func parse(_ text:String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of:",",with:".").trimmingCharacters(in:.whitespaces)), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

struct StockTakeoffLine: Identifiable {
    var product:StockProduct
    var required:Double
    var fromStock:Double
    var id:String { product.id }
    var toBuy:Double { max(0,required-fromStock) }
    func exportLine(deduct:Bool,includeStock:Bool) -> String {
        let line = "\(product.name) : \(StockQuantity.text(deduct ? toBuy : required)) \(product.unit)"
        return includeStock ? line + " (besoin total : \(StockQuantity.text(required)) ; +\(StockQuantity.text(fromStock)) \(product.unit) disponibles en stock)" : line
    }
    @MainActor static func make(_ supplies:[CombinedSupply],stock:StockStore,projectID:UUID?) -> [Self] {
        SupplyListingConsolidator.rows(supplies.map { .init(name:$0.name,quantity:$0.quantity,unit:$0.unit) }).flatMap { row in
            row.measurements.map { measurement in
                let product = StockProduct(name:row.name,unit:measurement.unit)
                let required = SupplyListingConsolidator.isDiscrete(measurement.unit) ? ceil(measurement.quantity) : measurement.quantity
                return Self(product:product,required:required,fromStock:min(required,stock.available(product.id,for:projectID)))
            }
        }
    }
}

/// Inventory valuation never assigns zero to an unknown or ambiguous tariff.
enum StockValuation {
    static func unitPrice(_ product:StockProduct,prices:SupplyPriceCatalogue?) -> Double? {
        guard let prices, prices.isSupported else { return nil }
        let matches = prices.prices.filter { price in
            price.isUsable(on:SupplyCostEstimator.day()) && StockProduct.unit(price.unit) == product.unit &&
            (product.referenceID != nil ? price.referenceId == product.referenceID && price.variantKey == product.variant : StockProduct.identity(name:price.variantKey == "standard" && price.label.hasSuffix(" · standard") ? String(price.label.dropLast(" · standard".count)) : price.label,unit:price.unit) == product.id)
        }
        guard matches.count == 1 else { return nil }
        let value = matches[0].unitPriceHT+matches[0].repUnitHT
        return value.isFinite ? value : nil
    }
}

/// Catalogue is built from published Admin records (including nested work families).
/// The existing local catalogue cache makes it available offline after the first load.
enum StockCatalogue {
    static func filtered(_ products:[StockProduct],family:StockFamily?,subcategory:String,search:String) -> [StockProduct] {
        products.filter { (family == nil || $0.family == family) && (subcategory.isEmpty || $0.subcategory == subcategory) && (search.isEmpty || $0.name.localizedStandardContains(search)) }
    }
    static func products(data:Data?) -> [StockProduct] {
        guard let data, let root = try? JSONSerialization.jsonObject(with:data) else { return [] }
        var products:[String:StockProduct] = [:]
        var frameProducts:[String:StockProduct] = [:]
        func addFrame(_ code:String) {
            let code=code.trimmingCharacters(in:.whitespacesAndNewlines)
            guard code.range(of:#"^(?:R[0-9]+|M[0-9]+(?:[/\-][0-9]+)?)$"#,options:.regularExpression) != nil else { return }
            let product=StockProduct(name:"\(code.hasPrefix("R") ? "Rails" : "Montants") \(code)",unit:"ml",family:.frames)
            frameProducts[product.id]=product
        }
        func walk(_ value:Any) {
            if let array = value as? [Any] { array.forEach(walk); return }
            guard let object = value as? [String:Any] else { return }
            if let frame=object["frame"] as? String { frame.components(separatedBy:"+").forEach(addFrame) }
            // Rail/stud ceilings publish sizes in their technical system table,
            // rather than as separate quantity_item records. Do not invent prices.
            if object["suspension_allowed"] is Bool, let width=object["width_mm"] as? Int, width>0, width<1000 {
                addFrame("R\(width)"); addFrame("M\(width)")
            }
            if let id = object["id"] as? String, let name = object["title"] as? String, let kind = object["kind"] as? String, let fields = object["data"] as? [String:Any] {
                func add(_ label:String,_ unit:String,_ variant:String) {
                    let product = StockProduct(name:label,unit:unit,referenceID:id,variant:variant)
                    if let existing = products[product.id], existing.referenceID != product.referenceID {
                        // Same purchasing label published under several technical records:
                        // keep the material, but never arbitrarily pick one price identity.
                        var unlinked = product; unlinked.referenceID = nil; unlinked.variant = nil
                        products[product.id] = unlinked
                    } else { products[product.id] = product }
                }
                if kind == "facing", let dimensions = fields["dimensions"] as? [[String:Any]] {
                    for d in dimensions {
                        if let w = d["width_mm"] as? Double, let h = d["length_mm"] as? Double, w > 0, h > 0, w < 100_000, h < 100_000 {
                            add("\(name) · \(Int(w)) × \(Int(h)) mm","m²","\(Int(w))x\(Int(h))")
                        }
                    }
                } else if kind == "insulation_series" {
                    let lambdas = fields["lambdas"] as? [[String:Any]] ?? [fields]
                    for l in lambdas {
                        let thicknesses = l["thicknesses_mm"] as? [Double] ?? (l["values"] as? [[String:Any]] ?? []).compactMap { $0["thickness_mm"] as? Double }
                        if let lambda = l["lambda_w_mk"] as? Double, lambda.isFinite, lambda > 0 {
                            for thickness in thicknesses where thickness > 0 && thickness < 100_000 {
                                let value = String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),lambda)
                                add("\(name) · λ \(value) · \(Int(thickness)) mm","m²","lambda=\(value);thickness=\(Int(thickness))")
                            }
                        }
                    }
                } else if kind == "quantity_item", let unit = fields["unit"] as? String,
                          ["m²","ml","unité","unités","kg","L"].contains(unit), !["QTY-FIXATION","QTY-PLAQUE"].contains(id) {
                    add(name,unit,id == "QTY-BANDE" ? "papier" : "standard")
                }
            }
            for child in object.values { if child is [Any] || child is [String:Any] { walk(child) } }
        }
        walk(root)
        for (id,product) in frameProducts where products[id] == nil { products[id]=product }
        return products.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
