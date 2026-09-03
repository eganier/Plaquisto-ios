import Foundation

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
    var array: [LabJSONValue]? { if case let .array(value) = self { value } else { nil } }
    var object: [String: LabJSONValue]? { if case let .object(value) = self { value } else { nil } }
}

struct LabReferenceRecord: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let data: [String: LabJSONValue]
}

struct CloisonCatalogueResponse: Codable {
    let version: String
    let cloisonDistribution: CloisonRemotePayload?
}

struct CloisonRemotePayload: Codable {
    let ouvrage: LabReferenceRecord?
    let parements: [LabReferenceRecord]
    let performance: LabReferenceRecord?
    let quantitatif: LabReferenceRecord?
    let isolants: [LabReferenceRecord]
}

struct CloisonFacingFormat: Identifiable, Hashable {
    let widthMM: Int
    let lengthMM: Int
    var id: String { "\(widthMM)x\(lengthMM)" }
    var title: String { "\(widthMM) × \(lengthMM) mm" }
}

struct CloisonFacingChoice: Identifiable, Hashable {
    let id: String
    let family: String
    let function: String
    let formats: [CloisonFacingFormat]

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

struct CloisonSystem: Identifiable, Hashable {
    let id: String
    let type: String
    let totalThicknessMM: Int
    let frame: String
    let frameWidthMM: Int
    let layersPerFace: Int
    let facingFamily: String
    let recommendedInsulationMM: Int
    let heights: [String: Double]

    var title: String { "\(type) · \(frame)" }
}

struct CloisonInsulation: Identifiable, Hashable {
    let id: String
    let title: String
    let lambda: Double
    let thicknessesMM: [Int]
    let maxOverFrameMM: Int
}

struct CloisonQuantityTable {
    let coefficients: [String: Double]
    let studs: [String: Double]
    let firstLayerScrews: [String: Double]
    let secondLayerScrews: [String: Double]
    let frameScrews: [String: Double]
}

@MainActor
final class CloisonDistributionReferenceStore: ObservableObject {
    @Published private(set) var systems: [CloisonSystem] = []
    @Published private(set) var facings: [CloisonFacingChoice] = []
    @Published private(set) var insulations: [CloisonInsulation] = []
    @Published private(set) var quantities = CloisonQuantityTable(coefficients: [:], studs: [:], firstLayerScrews: [:], secondLayerScrews: [:], frameScrews: [:])
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
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(CloisonCatalogueResponse.self, from: data)
            guard let payload = decoded.cloisonDistribution, apply(payload) else { throw URLError(.zeroByteResource) }
        } catch {
            systems = []
            facings = []
            insulations = []
            self.error = "Connexion à Plaquisto Admin impossible. Vérifiez votre connexion Internet puis réessayez."
        }
        isLoading = false
    }

    @discardableResult
    private func apply(_ payload: CloisonRemotePayload) -> Bool {
        guard payload.performance?.data["schema_version"]?.number ?? 0 >= 3 else {
            return false
        }

        let parsedSystems = parseSystems(payload.performance)
        let parsedFacings = parseFacings(payload.parements)
        let parsedInsulations = parseInsulations(payload.isolants)
        guard let parsedQuantities = parseQuantities(payload.quantitatif),
              !parsedSystems.isEmpty, !parsedFacings.isEmpty, !parsedInsulations.isEmpty else { return false }
        systems = parsedSystems
        facings = parsedFacings
        insulations = parsedInsulations
        quantities = parsedQuantities
        return true
    }

    private func parseSystems(_ record: LabReferenceRecord?) -> [CloisonSystem] {
        record?.data["systems"]?.array?.compactMap { value in
            guard let item = value.object,
                  let id = item["id"]?.string,
                  let type = item["type"]?.string,
                  let frame = item["frame"]?.string,
                  let family = item["facing_family"]?.string,
                  let heights = item["heights"]?.object?.compactMapValues(\.number) else { return nil }
            return CloisonSystem(
                id: id,
                type: type,
                totalThicknessMM: Int(item["total_thickness_mm"]?.number ?? 0),
                frame: frame,
                frameWidthMM: Int(item["frame_width_mm"]?.number ?? 0),
                layersPerFace: Int(item["layers_per_face"]?.number ?? 1),
                facingFamily: family,
                recommendedInsulationMM: Int(item["recommended_insulation_mm"]?.number ?? 0),
                heights: heights
            )
        } ?? []
    }

    private func parseFacings(_ records: [LabReferenceRecord]) -> [CloisonFacingChoice] {
        records.compactMap { record in
            guard let family = record.data["mechanical_family"]?.string,
                  ["BA13", "BA15", "BA18"].contains(family) else { return nil }
            let formats = record.data["dimensions"]?.array?.compactMap { value -> CloisonFacingFormat? in
                guard let item = value.object,
                      let width = item["width_mm"]?.number,
                      let length = item["length_mm"]?.number,
                      Int(width) == 1200 else { return nil }
                return CloisonFacingFormat(widthMM: Int(width), lengthMM: Int(length))
            }.sorted { $0.lengthMM < $1.lengthMM } ?? []
            guard !formats.isEmpty else { return nil }
            return CloisonFacingChoice(id: record.id, family: family, function: record.data["function"]?.string ?? "standard", formats: formats)
        }.sorted { lhs, rhs in
            if lhs.family == rhs.family { return lhs.functionTitle < rhs.functionTitle }
            return Self.familyRank(lhs.family) < Self.familyRank(rhs.family)
        }
    }

    private func parseInsulations(_ records: [LabReferenceRecord]) -> [CloisonInsulation] {
        records.compactMap { record in
            guard let lambda = record.data["lambda_w_mk"]?.number else { return nil }
            let thicknesses = record.data["thicknesses_mm"]?.array?.compactMap(\.number).map(Int.init).sorted() ?? []
            guard !thicknesses.isEmpty else { return nil }
            return CloisonInsulation(id: record.id, title: record.title, lambda: lambda, thicknessesMM: thicknesses, maxOverFrameMM: Int(record.data["max_over_frame_mm"]?.number ?? 10))
        }.sorted { $0.title < $1.title }
    }

    private func parseQuantities(_ record: LabReferenceRecord?) -> CloisonQuantityTable? {
        guard let data = record?.data else { return nil }
        func numbers(_ key: String) -> [String: Double] { data[key]?.object?.compactMapValues(\.number) ?? [:] }
        let result = CloisonQuantityTable(
            coefficients: numbers("coefficients"),
            studs: numbers("stud_ml_m2"),
            firstLayerScrews: numbers("ttpc_first_layer_unit_m2"),
            secondLayerScrews: numbers("ttpc_second_layer_unit_m2"),
            frameScrews: numbers("trpf13_unit_m2")
        )
        return result.coefficients.isEmpty ? nil : result
    }

    private static func familyRank(_ family: String) -> Int {
        switch family {
        case "BA13": 13
        case "BA15": 15
        case "BA18": 18
        default: 0
        }
    }

}
