import Foundation

struct LabReferenceRecord: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let data: [String: LabJSONValue]
}

struct LabCataloguePayload: Codable {
    let version: String
    let doublage: LabDoublagePayload?
}

struct LabDoublagePayload: Codable {
    let ouvrage: LabReferenceRecord?
    let parements: [LabReferenceRecord]
    let performance: LabReferenceRecord?
    let quantitatif: LabReferenceRecord?
}

enum LabJSONValue: Codable {
    case string(String), number(Double), bool(Bool), array([LabJSONValue]), object([String: LabJSONValue]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([LabJSONValue].self) { self = .array(value) }
        else { self = .object(try box.decode([String: LabJSONValue].self)) }
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

    var string: String? { if case let .string(value) = self { value } else { nil } }
    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var bool: Bool? { if case let .bool(value) = self { value } else { nil } }
    var array: [LabJSONValue]? { if case let .array(value) = self { value } else { nil } }
    var object: [String: LabJSONValue]? { if case let .object(value) = self { value } else { nil } }
}

struct LabHeightValue: Identifiable {
    let frame: String
    let spacing: Double
    let simple: Double
    let double: Double
    var id: String { "\(frame)-\(spacing)" }
}

struct LabPerformanceGroup: Identifiable {
    let id: String
    let label: String
    let width: Double
    let alternatives: [String]
    let values: [LabHeightValue]
}

struct LabFacingFormat: Identifiable, Hashable {
    let widthMM: Int
    let lengthMM: Int
    var id: String { "\(widthMM)x\(lengthMM)" }
    var title: String { "\(widthMM) × \(lengthMM) mm" }
}

struct LabFacingChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let mechanicalFamily: String
    let function: String
    let formats: [LabFacingFormat]
}

struct LabSingleCompatibilityRule {
    let families: [String]
    let widthsMM: [Int]
    let performanceGroupID: String
}

struct LabDoubleCompatibilityRule {
    let families: [String]
    let widthsMM: [Int]
    let performanceGroupID: String
}

struct LabFacingCompatibility {
    let sameWidthRequired: Bool
    let normalizeFamilies: [String: String]
    let single: [LabSingleCompatibilityRule]
    let exactDouble: [LabDoubleCompatibilityRule]
    let setDouble: [LabDoubleCompatibilityRule]
}

struct LabQuantityTable {
    let coefficients: [String: Double]
    let ttpc25: [String: Double]
    let ttpc35: [String: Double]
    let trpf13: [String: Double]
}

@MainActor
final class LabReferenceStore: ObservableObject {
    @Published var catalogue: LabCataloguePayload?
    @Published var isLoading = true
    @Published var error: String?
    @Published var isUsingOfflineData = false

    private let endpoint = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!
    private let cacheKey = "plaquisto.lab.catalogue.doublage.v2"

    var facings: [LabFacingChoice] {
        (catalogue?.doublage?.parements ?? []).compactMap { record in
            guard let family = record.data["mechanical_family"]?.string else { return nil }
            let formats = record.data["dimensions"]?.array?.compactMap { value -> LabFacingFormat? in
                guard let object = value.object,
                      let width = object["width_mm"]?.number,
                      let length = object["length_mm"]?.number else { return nil }
                return LabFacingFormat(widthMM: Int(width), lengthMM: Int(length))
            }.sorted { $0.widthMM == $1.widthMM ? $0.lengthMM < $1.lengthMM : $0.widthMM < $1.widthMM } ?? []
            guard !formats.isEmpty else { return nil }
            return LabFacingChoice(id: record.id, title: record.title, mechanicalFamily: family, function: record.data["function"]?.string ?? "standard", formats: formats)
        }.sorted { lhs, rhs in
            if lhs.mechanicalFamily == rhs.mechanicalFamily { return lhs.title < rhs.title }
            let left = Int(lhs.mechanicalFamily.dropFirst(2)) ?? 0
            let right = Int(rhs.mechanicalFamily.dropFirst(2)) ?? 0
            return left < right
        }
    }

    var compatibility: LabFacingCompatibility? {
        guard let data = catalogue?.doublage?.performance?.data,
              let object = data["compatibility"]?.object else { return nil }
        func rule(_ value: LabJSONValue) -> LabDoubleCompatibilityRule? {
            guard let item = value.object,
                  let families = item["families"]?.array?.compactMap(\.string),
                  let widths = item["widths_mm"]?.array?.compactMap(\.number).map({ Int($0) }),
                  let group = item["performance_group_id"]?.string else { return nil }
            return LabDoubleCompatibilityRule(families: families, widthsMM: widths, performanceGroupID: group)
        }
        let single = object["single"]?.array?.compactMap { value -> LabSingleCompatibilityRule? in
            guard let parsed = rule(value) else { return nil }
            return LabSingleCompatibilityRule(families: parsed.families, widthsMM: parsed.widthsMM, performanceGroupID: parsed.performanceGroupID)
        } ?? []
        let double = object["double"]?.object
        let normalize = double?["normalize_families"]?.object?.compactMapValues(\.string) ?? [:]
        return LabFacingCompatibility(
            sameWidthRequired: object["same_width_required"]?.bool ?? true,
            normalizeFamilies: normalize,
            single: single,
            exactDouble: double?["exact"]?.array?.compactMap(rule) ?? [],
            setDouble: double?["sets"]?.array?.compactMap(rule) ?? []
        )
    }

    var groups: [LabPerformanceGroup] {
        guard let raw = catalogue?.doublage?.performance?.data["groups"]?.array else { return [] }
        return raw.compactMap { item in
            guard let object = item.object,
                  let id = object["id"]?.string,
                  let label = object["label"]?.string,
                  let width = object["width_mm"]?.number else { return nil }
            let alternatives = object["alternatives"]?.array?.compactMap(\.string) ?? [label]
            let values = object["values"]?.array?.compactMap { value -> LabHeightValue? in
                guard let row = value.object,
                      let frame = row["frame"]?.string,
                      let spacing = row["spacing_m"]?.number else { return nil }
                return LabHeightValue(frame: frame, spacing: spacing, simple: row["simple_m"]?.number ?? 0, double: row["double_m"]?.number ?? 0)
            } ?? []
            return LabPerformanceGroup(id: id, label: label, width: width, alternatives: alternatives, values: values)
        }
    }

    var quantityTable: LabQuantityTable? {
        guard let data = catalogue?.doublage?.quantitatif?.data else { return nil }
        func numbers(_ key: String) -> [String: Double] {
            data[key]?.object?.compactMapValues(\.number) ?? [:]
        }
        return LabQuantityTable(coefficients: numbers("coefficients"), ttpc25: numbers("ttpc25_unit_m2"), ttpc35: numbers("ttpc35_unit_m2"), trpf13: numbers("trpf13_unit_m2"))
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(LabCataloguePayload.self, from: data)
            guard decoded.doublage?.ouvrage != nil else { throw URLError(.zeroByteResource) }
            catalogue = decoded
            UserDefaults.standard.set(data, forKey: cacheKey)
            isUsingOfflineData = false
        } catch {
            if let data = UserDefaults.standard.data(forKey: cacheKey),
               let decoded = try? JSONDecoder().decode(LabCataloguePayload.self, from: data) {
                catalogue = decoded
                isUsingOfflineData = true
            } else {
                self.error = "Les données du doublage ne sont pas encore disponibles. Publiez d’abord Plaquisto Admin, puis réessayez."
            }
        }
        isLoading = false
    }
}
