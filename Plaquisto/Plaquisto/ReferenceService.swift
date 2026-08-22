import Foundation

struct ReferenceRecord: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let summary: String
    let sourcePage: Int
    let status: String
    let data: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, status, data
        case sourcePage = "source_page"
    }
}

enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }

    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var string: String? { if case let .string(value) = self { value } else { nil } }
    var array: [JSONValue]? { if case let .array(value) = self { value } else { nil } }
}

@MainActor
final class ReferenceStore: ObservableObject {
    @Published var records: [ReferenceRecord] = []
    @Published var isLoading = true
    @Published var error: String?

    private let endpoint = URL(string: "https://omqnenxlliavmyramdux.supabase.co/rest/v1/reference_records?select=*&status=eq.Publi%C3%A9")!
    private let publicKey = "sb_publishable_LU4mBYJms4_0Ja8WodyfWg_RVBuRaPm"

    func load() async {
        isLoading = true; error = nil
        do {
            var request = URLRequest(url: endpoint)
            request.setValue(publicKey, forHTTPHeaderField: "apikey")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            records = try JSONDecoder().decode([ReferenceRecord].self, from: data)
            if records.isEmpty { throw URLError(.zeroByteResource) }
        } catch {
            self.error = "Impossible de charger le référentiel Plaquisto Admin. Vérifiez votre connexion Internet."
        }
        isLoading = false
    }
}
