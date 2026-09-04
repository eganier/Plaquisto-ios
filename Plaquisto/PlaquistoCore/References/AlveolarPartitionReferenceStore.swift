import Foundation

enum AlveolarJSONValue: Codable {
    case string(String), number(Double), bool(Bool), array([AlveolarJSONValue]), object([String: AlveolarJSONValue]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([AlveolarJSONValue].self) { self = .array(value) }
        else { self = .object(try box.decode([String: AlveolarJSONValue].self)) }
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
    var array: [AlveolarJSONValue]? { if case let .array(value) = self { value } else { nil } }
    var object: [String: AlveolarJSONValue]? { if case let .object(value) = self { value } else { nil } }
}

struct AlveolarReferenceRecord: Codable {
    let id: String
    let title: String
    let data: [String: AlveolarJSONValue]
}

private struct AlveolarCatalogueResponse: Codable {
    let version: String
    let cloisonAlveolaire: AlveolarRemotePayload?
}

private struct AlveolarRemotePayload: Codable {
    let ouvrage: AlveolarReferenceRecord?
    let parements: [AlveolarReferenceRecord]
    let regles: AlveolarReferenceRecord?
    let quantitatif: AlveolarReferenceRecord?
}

struct AlveolarPanelFormat: Identifiable, Hashable {
    let widthMM: Int
    let heightMM: Int
    var id: String { "\(widthMM)x\(heightMM)" }
    var title: String { "\(widthMM) × \(heightMM) mm" }
}

struct AlveolarPanel: Identifiable, Hashable {
    let id: String
    let title: String
    let function: String
    let formats: [AlveolarPanelFormat]

    var functionTitle: String { function == "hydrofuge" ? "Hydrofuge" : "Standard" }
}

struct AlveolarQuantityCoefficients {
    let panel: Double
    let semelle: Double
    let rail: Double
    let clavette: Double
    let ttpc35: Double
    let ttpc70: Double
    let band: Double
    let powder: Double
    let paste: Double
}

struct AlveolarQuantityTable {
    let byWidth: [Int: AlveolarQuantityCoefficients]
    let names: [String: String]
}

@MainActor
final class AlveolarPartitionReferenceStore: ObservableObject {
    @Published private(set) var panels: [AlveolarPanel] = []
    @Published private(set) var maximumHeight = 2.70
    @Published private(set) var quantities = AlveolarQuantityTable(byWidth: [:], names: [:])
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?

    private let endpoint = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!

    func load() async {
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(AlveolarCatalogueResponse.self, from: data)
            guard let payload = decoded.cloisonAlveolaire, apply(payload) else {
                throw URLError(.zeroByteResource)
            }
        } catch {
            panels = []
            quantities = AlveolarQuantityTable(byWidth: [:], names: [:])
            self.error = "Connexion à Plaquisto Admin impossible. Vérifiez votre connexion Internet puis réessayez."
        }
        isLoading = false
    }

    @discardableResult
    private func apply(_ payload: AlveolarRemotePayload) -> Bool {
        guard payload.regles?.data["schema_version"]?.number == 1,
              payload.quantitatif?.data["schema_version"]?.number == 1 else { return false }

        let parsedPanels = payload.parements.compactMap { record -> AlveolarPanel? in
            guard record.data["material"]?.string == "panneau_cloison_alveolaire" else { return nil }
            let formats = record.data["dimensions"]?.array?.compactMap { value -> AlveolarPanelFormat? in
                guard let item = value.object,
                      let width = item["width_mm"]?.number,
                      let height = item["length_mm"]?.number else { return nil }
                return AlveolarPanelFormat(widthMM: Int(width), heightMM: Int(height))
            }.sorted { lhs, rhs in
                lhs.widthMM == rhs.widthMM ? lhs.heightMM < rhs.heightMM : lhs.widthMM < rhs.widthMM
            } ?? []
            guard !formats.isEmpty else { return nil }
            return AlveolarPanel(
                id: record.id,
                title: record.title,
                function: record.data["function"]?.string ?? "standard",
                formats: formats
            )
        }.sorted { lhs, rhs in
            let lhsRank = lhs.function == "standard" ? 0 : 1
            let rhsRank = rhs.function == "standard" ? 0 : 1
            return lhsRank < rhsRank
        }

        guard let quantityData = payload.quantitatif?.data,
              let widths = quantityData["by_panel_width_mm"]?.object else { return false }
        var parsedWidths: [Int: AlveolarQuantityCoefficients] = [:]
        for (key, value) in widths {
            guard let width = Int(key), let item = value.object else { continue }
            parsedWidths[width] = AlveolarQuantityCoefficients(
                panel: item["panel_m2_m2"]?.number ?? 0,
                semelle: item["semelle_ml_m2"]?.number ?? 0,
                rail: item["rail_ml_m2"]?.number ?? 0,
                clavette: item["clavette_unit_m2"]?.number ?? 0,
                ttpc35: item["ttpc35_unit_m2"]?.number ?? 0,
                ttpc70: item["ttpc70_unit_m2"]?.number ?? 0,
                band: item["band_ml_m2"]?.number ?? 0,
                powder: item["enduit_poudre_kg_m2"]?.number ?? 0,
                paste: item["enduit_pate_kg_m2"]?.number ?? 0
            )
        }
        let names = quantityData["component_names"]?.object?.compactMapValues(\.string) ?? [:]
        guard !parsedPanels.isEmpty, !parsedWidths.isEmpty else { return false }

        panels = parsedPanels
        maximumHeight = payload.regles?.data["maximum_height_m"]?.number ?? 2.70
        quantities = AlveolarQuantityTable(byWidth: parsedWidths, names: names)
        return true
    }
}
