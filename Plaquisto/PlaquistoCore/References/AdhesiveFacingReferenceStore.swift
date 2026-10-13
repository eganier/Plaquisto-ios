import Foundation

struct AdhesiveFacingOption: Identifiable, Hashable {
    let id: String
    let family: String
    let function: String
    let title: String
    let formats: [AdhesiveFacingFormat]

    func quantityTitle(format: AdhesiveFacingFormat) -> String { "\(title) · \(format.title)" }

    var functionTitle: String {
        switch function {
        case "hydrofuge": "Hydrofuge H1"
        case "incendie": "Protection incendie"
        case "phonique": "Phonique"
        case "haute_durete": "Haute dureté"
        case "quatre_bords_amincis": "Quatre bords amincis"
        case "tres_haute_resistance_eau": "Très haute résistance à l’eau"
        default: "Standard"
        }
    }
}

struct AdhesiveFacingFormat: Identifiable, Hashable {
    let widthMM: Int
    let heightMM: Int
    var id: String { "\(widthMM)x\(heightMM)" }
    var title: String { "\(widthMM) × \(heightMM) mm" }

    static func selected(id: String, in formats: [Self]) -> Self? {
        formats.first { $0.id == id } ?? formats.first
    }

    static func legacy(_ id: String) -> Self? {
        let parts = id.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ $0 > 0 && $0 <= 100_000 }) else { return nil }
        return .init(widthMM:parts[0],heightMM:parts[1])
    }
}

struct AdhesiveFacingQuantityTable {
    let plate: Double
    let adhesive: Double
    let band: Double
    let powder: Double
    let names: [String: String]

    static let empty = AdhesiveFacingQuantityTable(plate: 0, adhesive: 0, band: 0, powder: 0, names: [:])
}

private struct AdhesiveFacingCatalogue: Codable {
    let doublageParementColle: AdhesiveFacingPayload?
}

private struct AdhesiveFacingPayload: Codable {
    let parements: [AdhesiveFacingRecord]
    let catalogue: AdhesiveFacingRecord?
    let quantitatif: AdhesiveFacingRecord?
}

private struct AdhesiveFacingRecord: Codable {
    let id: String
    let title: String?
    let data: [String: AdhesiveFacingJSON]
}

private enum AdhesiveFacingJSON: Codable {
    case string(String), number(Double), bool(Bool), array([AdhesiveFacingJSON]), object([String: AdhesiveFacingJSON]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([AdhesiveFacingJSON].self) { self = .array(decoded) }
        else { self = .object(try value.decode([String: AdhesiveFacingJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var array: [AdhesiveFacingJSON]? { if case .array(let value) = self { value } else { nil } }
    var object: [String: AdhesiveFacingJSON]? { if case .object(let value) = self { value } else { nil } }
}

@MainActor
final class AdhesiveFacingReferenceStore: ObservableObject {
    @Published private(set) var options: [AdhesiveFacingOption] = []
    @Published private(set) var formats: [AdhesiveFacingFormat] = []
    @Published private(set) var quantities = AdhesiveFacingQuantityTable.empty
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?

    private let endpoint = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!

    var families: [String] {
        Array(Set(options.map(\.family))).sorted { plateOrder($0) < plateOrder($1) }
    }

    func functions(for family: String) -> [AdhesiveFacingOption] {
        options.filter { $0.family == family }.sorted { functionOrder($0.function) < functionOrder($1.function) }
    }

    func formats(for optionID: String, preserving legacyID: String? = nil) -> [AdhesiveFacingFormat] {
        var result = options.first { $0.id == optionID }?.formats ?? []
        // Existing saved formats stay editable without becoming catalogue choices for new works.
        if let legacyID, let legacy = AdhesiveFacingFormat.legacy(legacyID), !result.contains(legacy) {
            result.append(legacy)
        }
        return result
    }

    @discardableResult
    func apply(data: Data) throws -> Bool {
        apply(try JSONDecoder().decode(AdhesiveFacingCatalogue.self, from:data))
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard try apply(data:data) else { throw URLError(.zeroByteResource) }
        } catch {
            options = []
            formats = []
            quantities = .empty
            self.error = "Connexion à Plaquisto Admin impossible. Vérifiez votre connexion Internet puis réessayez."
        }
        isLoading = false
    }

    private func apply(_ catalogue: AdhesiveFacingCatalogue) -> Bool {
        guard let payload = catalogue.doublageParementColle,
              payload.catalogue?.data["schema_version"]?.number == 1,
              payload.quantitatif?.data["schema_version"]?.number == 1 else { return false }
        let allowedFamilies = Set(payload.catalogue?.data["allowed_families"]?.array?.compactMap(\.string) ?? [])
        func format(_ value: AdhesiveFacingJSON, lengthKey: String) -> AdhesiveFacingFormat? {
            guard let item = value.object, let width = item["width_mm"]?.number,
                  let height = item[lengthKey]?.number,
                  [width,height].allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 && $0.rounded() == $0 }) else { return nil }
            return .init(widthMM:Int(width),heightMM:Int(height))
        }
        let legacyFormats = payload.catalogue?.data["formats"]?.array?.compactMap { format($0,lengthKey:"height_mm") } ?? []
        options = payload.parements.compactMap { record in
            guard let family = record.data["mechanical_family"]?.string,
                  let function = record.data["function"]?.string else { return nil }
            let commonCatalogue = record.data["catalog_schema_version"]?.number == 2
            if commonCatalogue {
                if let works = record.data["compatible_work_codes"]?.array,
                   !works.compactMap(\.string).contains("doublage-peripherique-parement-colle") { return nil }
            } else if !allowedFamilies.contains(family) { return nil }
            let choices = record.data["dimensions"]?.array?.compactMap { format($0,lengthKey:"length_mm") }
                ?? (commonCatalogue ? [] : legacyFormats)
            guard !choices.isEmpty else { return nil }
            return AdhesiveFacingOption(id: record.id, family: family, function: function,
                                        title:record.title ?? family,formats:choices)
        }
        formats = Array(Set(options.flatMap(\.formats))).sorted {
            $0.widthMM == $1.widthMM ? $0.heightMM < $1.heightMM : $0.widthMM > $1.widthMM
        }

        let quantityData = payload.quantitatif?.data
        let coefficients = quantityData?["coefficients"]?.object ?? [:]
        quantities = AdhesiveFacingQuantityTable(
            plate: coefficients["plate_m2_m2"]?.number ?? 0,
            adhesive: coefficients["adhesive_kg_m2"]?.number ?? 0,
            band: coefficients["band_ml_m2"]?.number ?? 0,
            powder: coefficients["powder_kg_m2"]?.number ?? 0,
            names: quantityData?["component_names"]?.object?.compactMapValues(\.string) ?? [:]
        )
        return !options.isEmpty && !formats.isEmpty && quantities.plate > 0 && quantities.adhesive > 0
    }

    private func plateOrder(_ family: String) -> Int {
        ["BA6", "BA10", "BA13", "BA15", "BA18", "BA18S", "BA25"].firstIndex(of:family) ?? 99
    }
    private func functionOrder(_ function: String) -> Int {
        ["standard", "hydrofuge", "incendie", "phonique", "haute_durete", "quatre_bords_amincis", "tres_haute_resistance_eau"].firstIndex(of: function) ?? 99
    }
}
