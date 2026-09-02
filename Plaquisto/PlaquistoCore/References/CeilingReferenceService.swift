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

@MainActor
final class CeilingReferenceStore: ObservableObject {
    @Published var catalogue: CeilingCataloguePayload?
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
            UserDefaults.standard.set(data, forKey: cacheKey)
            isUsingOfflineData = false
        } catch {
            if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
               let cachedCatalogue = try? JSONDecoder().decode(CeilingCataloguePayload.self, from: cachedData),
               !cachedCatalogue.records.isEmpty {
                catalogue = cachedCatalogue
                isUsingOfflineData = true
            } else {
                self.error = "Impossible de charger Plaquisto Admin. Une première connexion Internet est nécessaire."
            }
        }

        isLoading = false
    }
}
