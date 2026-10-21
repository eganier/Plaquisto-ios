import Foundation

struct CeilingReferenceRecord: Codable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let summary: String
    let sourcePage: Int
    let status: String
    let data: [String: CeilingJSONValue]
}

struct CeilingCataloguePayload: Codable {
    let version: String
    let ouvrage: CeilingReferenceRecord?
    let isolation: [CeilingReferenceRecord]
    let systemesFixation: [CeilingReferenceRecord]
    let parements: [CeilingReferenceRecord]
    let quantitatifs: [CeilingReferenceRecord]
    let pareVapeur: [CeilingReferenceRecord]?
    let regles: [CeilingReferenceRecord]

    var records: [CeilingReferenceRecord] {
        (ouvrage.map { [$0] } ?? []) + isolation + systemesFixation + parements + quantitatifs + (pareVapeur ?? []) + regles
    }
}

/// Resolves the administrator's size table without embedding production ranges
/// in iOS. A gap, overlap or fractional millimetre never guesses a reference.
enum GalvanizedHangerSelection {
    static func wholeMillimeters(plenumCM: Double) -> Int? {
        let mm = plenumCM * 10
        guard mm.isFinite, mm >= 0, mm <= 1_000_000,
              abs(mm - mm.rounded()) < 0.000001 else { return nil }
        return Int(mm.rounded())
    }

    static func usesSizing(_ system: CeilingReferenceRecord) -> Bool {
        system.data["components"]?.array?.contains {
            $0.object?["selection"]?.string == "galvanized_hanger"
        } == true
    }

    static func reference(plenumCM: Double, support: String, catalogue: CeilingCataloguePayload) -> CeilingReferenceRecord? {
        guard let mm = wholeMillimeters(plenumCM: plenumCM) else { return nil }
        let prefix: String
        switch support {
        case "Plancher bois horizontal": prefix = ""
        case "Plancher hourdis béton": prefix = "hourdis_"
        default: return nil
        }
        let matches = catalogue.quantitatifs.filter { record in
            guard record.status == "Publié", record.data["category"]?.string == "galvanized_hanger",
                  record.data["unit"]?.string == "unité",
                  let length = record.data["length_mm"]?.number,
                  let min = record.data["\(prefix)plenum_min_mm"]?.number,
                  let max = record.data["\(prefix)plenum_max_mm"]?.number,
                  length.isFinite, min.isFinite, max.isFinite,
                  length > 0, min >= 0, max >= min, max <= length,
                  length.rounded() == length, min.rounded() == min, max.rounded() == max else { return false }
            return Double(mm) >= min && Double(mm) <= max
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func components(for system: CeilingReferenceRecord, plenumCM: Double,
                           catalogue: CeilingCataloguePayload) -> [CeilingJSONValue] {
        let selected = reference(plenumCM: plenumCM, support: system.data["support"]?.string ?? "", catalogue: catalogue)
        return (system.data["components"]?.array ?? []).map { value in
            guard var object = value.object,
                  object["selection"]?.string == "galvanized_hanger" else { return value }
            // Old projects outside the new table keep their quantities but no
            // incorrect size or price is silently assigned to them.
            object["name"] = .string(selected?.title ?? "Suspentes acier galvanisées — taille à préciser")
            if let selected { object["reference_id"] = .string(selected.id) }
            return .object(object)
        }
    }
}

enum CompositeHangerSelection {
    static func usesSizing(_ system: CeilingReferenceRecord) -> Bool {
        system.data["components"]?.array?.contains { $0.object?["selection"]?.string == "composite_hanger" } == true
    }

    static func reference(plenumCM: Double, support: String, catalogue: CeilingCataloguePayload) -> CeilingReferenceRecord? {
        guard support == "Plancher bois horizontal",
              let mm = GalvanizedHangerSelection.wholeMillimeters(plenumCM: plenumCM) else { return nil }
        let matches = catalogue.quantitatifs.filter { record in
            guard record.status == "Publié", record.data["category"]?.string == "composite_hanger",
                  record.data["support"]?.string == support, record.data["unit"]?.string == "unité",
                  let model = record.data["model"]?.string, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let min = record.data["plenum_min_mm"]?.number, let max = record.data["plenum_max_mm"]?.number,
                  min.isFinite, max.isFinite, min >= 0, max >= min,
                  min.rounded() == min, max.rounded() == max else { return false }
            return Double(mm) >= min && Double(mm) <= max
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

enum CeilingHangerComponents {
    static func resolve(for system: CeilingReferenceRecord, plenumCM: Double,
                        catalogue: CeilingCataloguePayload) -> [CeilingJSONValue] {
        let selected = CompositeHangerSelection.reference(plenumCM: plenumCM,
            support: system.data["support"]?.string ?? "", catalogue: catalogue)
        return GalvanizedHangerSelection.components(for: system, plenumCM: plenumCM, catalogue: catalogue).map { value in
            guard var object = value.object, object["selection"]?.string == "composite_hanger" else { return value }
            object["name"] = .string(selected?.title ?? "Suspente composite pour pare-vapeur — modèle à préciser")
            object.removeValue(forKey: "reference_id")
            if let selected { object["reference_id"] = .string(selected.id) }
            return .object(object)
        }
    }
}

enum CeilingInsulationDefaults {
    static func firstThickness(available: [Double], betweenWood: Bool) -> Double {
        let choices = available.filter { $0.isFinite && $0 > 0 }.sorted()
        if betweenWood, choices.contains(60) { return 60 }
        // Never invent a thickness missing from the published product series.
        return choices.first ?? 0
    }
}

enum CeilingFixingDefaults {
    /// Only receives systems already filtered for support, plenum and ceiling shape.
    static func preferred(in compatible: [CeilingReferenceRecord], vaporBarrier: Bool) -> CeilingReferenceRecord? {
        if vaporBarrier, let composite = compatible.first(where: { $0.id == "FIX-BOIS-PARE-VAPEUR" }) {
            return composite
        }
        for id in ["FIX-BOIS-GALVA", "FIX-HOURDIS-GALVA", "FIX-HOURDIS-GRIFFE-GALVA"] {
            if let galvanized = compatible.first(where: { $0.id == id }) { return galvanized }
        }
        return compatible.first
    }
}

enum CeilingJSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([CeilingJSONValue])
    case object([String: CeilingJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([CeilingJSONValue].self) { self = .array(value) }
        else { self = .object(try box.decode([String: CeilingJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }

    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var string: String? { if case let .string(value) = self { value } else { nil } }
    var bool: Bool? { if case let .bool(value) = self { value } else { nil } }
    var array: [CeilingJSONValue]? { if case let .array(value) = self { value } else { nil } }
    var object: [String: CeilingJSONValue]? { if case let .object(value) = self { value } else { nil } }
}

/// Read-only catalogue projection, loaded with the existing cached catalogue request.
/// IDs are resolved from records, never guessed from their spelling.
struct WorkSummaryCatalogue {
    struct Record {
        let title: String?
        let data: [String: CeilingJSONValue]
    }
    var records: [String: Record] = [:]
    init() {}
    init(data: Data) throws {
        let root = try JSONDecoder().decode(CeilingJSONValue.self, from: data)
        func visit(_ value: CeilingJSONValue) {
            if let object = value.object {
                if let id = object["id"]?.string, let fields = object["data"]?.object {
                    records[id] = Record(title: object["title"]?.string, data: fields)
                } else {
                    object.values.forEach(visit)
                }
            } else { value.array?.forEach(visit) }
        }
        visit(root)
    }
    func name(_ id: String) -> String? {
        guard let record = records[id] else { return nil }
        return record.title ?? record.data["mechanical_family"]?.string ?? record.data["family"]?.string
    }
}

@MainActor
final class CeilingReferenceStore: ObservableObject {
    @Published var catalogue: CeilingCataloguePayload?
    @Published var workSummaryCatalogue = WorkSummaryCatalogue()
    @Published var isLoading = true
    @Published var error: String?
    @Published var isUsingOfflineData = false

    private let endpoint = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!
    private let cacheKey = "plaquisto.catalogue.v3"

    var records: [CeilingReferenceRecord] { catalogue?.records ?? [] }

    func load() async {
        isLoading = true
        error = nil

        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(CeilingCataloguePayload.self, from: data)
            guard !decoded.records.isEmpty else { throw URLError(.zeroByteResource) }
            catalogue = decoded
            workSummaryCatalogue = (try? WorkSummaryCatalogue(data: data)) ?? .init()
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheKey + ".lastSuccess")
            isUsingOfflineData = false
        } catch {
            if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
               let cachedCatalogue = try? JSONDecoder().decode(CeilingCataloguePayload.self, from: cachedData),
               !cachedCatalogue.records.isEmpty {
                catalogue = cachedCatalogue
                workSummaryCatalogue = (try? WorkSummaryCatalogue(data: cachedData)) ?? .init()
                isUsingOfflineData = true
            } else {
                self.error = "Impossible de charger Plaquisto Admin. Une première connexion Internet est nécessaire."
            }
        }

        isLoading = false
    }
}
