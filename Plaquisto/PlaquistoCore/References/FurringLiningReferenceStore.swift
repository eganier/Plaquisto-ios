import Foundation

struct FurringLiningPayload: Codable {
    let ouvrage: DoublageReferenceRecord?
    let parements: [DoublageReferenceRecord]
    let regles: DoublageReferenceRecord?
    let quantitatif: DoublageReferenceRecord?
    let isolants: [DoublageReferenceRecord]
}

struct FurringLiningSupportRule: Identifiable {
    let id: String
    let title: String
    let maximumHeight: Double
    let maximumSupportSpacing: Double
}

struct FurringLiningQuantities {
    var values: [String: Double] = [:]
    var names: [String: String] = [:]
    subscript(_ key: String) -> Double { values[key] ?? 0 }
    func name(_ key: String, fallback: String) -> String { names[key] ?? fallback }
}

struct FurringFacingSelection: Identifiable, Codable, Hashable {
    let id: UUID
    var facingID: String
    var formatID: String
    var surface: Double
    init(id: UUID = UUID(), facingID: String = "", formatID: String = "", surface: Double = 0) {
        self.id = id; self.facingID = facingID; self.formatID = formatID; self.surface = surface
    }
}

struct FurringInsulationSelection: Codable, Hashable {
    var familyID = ""
    var lambda = 0.0
    var thicknessMM = 0
}

enum FurringLiningCalculator {
    static func furringAxes(length: Double, spacing: Double, wallCount: Int) -> Int {
        guard length > 0, spacing > 0, wallCount > 0 else { return 0 }
        let baysPerWall = Int(ceil((length / Double(wallCount)) / spacing))
        return wallCount * (baysPerWall + 1)
    }
    static func recommendedSupportLines(height: Double, maximumSpacing: Double) -> Int {
        guard height > 0, maximumSpacing > 0 else { return 0 }
        return max(1, Int(ceil(height / maximumSpacing)) - 1)
    }
    static func horizontalSupportFurringLength(
        wallLength: Double,
        supportLines: Int,
        wasteFactor: Double,
        isIncluded: Bool
    ) -> Double {
        guard isIncluded, wallLength > 0, supportLines > 0 else { return 0 }
        return wallLength * Double(supportLines) * wasteFactor
    }
}

@MainActor
final class FurringLiningReferenceStore: ObservableObject {
    @Published private(set) var payload: FurringLiningPayload?
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?
    private let endpoint = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!

    var rules: [FurringLiningSupportRule] {
        payload?.regles?.data["support_rules"]?.array?.compactMap { item in
            guard let value = item.object, let id = value["id"]?.string, let title = value["title"]?.string,
                  let height = value["maximum_height_m"]?.number, let spacing = value["maximum_support_spacing_m"]?.number else { return nil }
            return FurringLiningSupportRule(id: id, title: title, maximumHeight: height, maximumSupportSpacing: spacing)
        } ?? []
    }
    func rule(_ id: String) -> FurringLiningSupportRule? { rules.first { $0.id == id } }
    var normalFurringSpacing: Double { ruleNumber("normal_furring_spacing_m") }
    var ba18Width900FurringSpacing: Double { ruleNumber("ba18_width_900_furring_spacing_m") }
    var tiledAreaMaximumSpacing: Double { payload?.regles?.data["tiled_area_rule"]?.object?["maximum_spacing_m"]?.number ?? 0 }
    var tiledAreaSingleFacingFamilies: Set<String> { Set(payload?.regles?.data["tiled_area_rule"]?.object?["single_facing_families"]?.array?.compactMap(\.string) ?? []) }
    var firstSupportHeightWhenMultiple: Double { ruleNumber("first_support_height_when_multiple_m") }
    var defaultWallCount: Int { Int(ruleNumber("default_wall_count")) }
    var quantities: FurringLiningQuantities {
        .init(values: payload?.quantitatif?.data["coefficients"]?.object?.compactMapValues(\.number) ?? [:], names: payload?.quantitatif?.data["component_names"]?.object?.compactMapValues(\.string) ?? [:])
    }
    var facings: [DoublageFacingChoice] {
        (payload?.parements ?? []).compactMap { record in
            guard let family = record.data["mechanical_family"]?.string else { return nil }
            let formats = record.data["dimensions"]?.array?.compactMap { item -> DoublageFacingFormat? in
                guard let object = item.object, let width = object["width_mm"]?.number, let length = object["length_mm"]?.number else { return nil }
                return .init(widthMM: Int(width), lengthMM: Int(length))
            } ?? []
            return formats.isEmpty ? nil : DoublageFacingChoice(id: record.id, title: record.title, mechanicalFamily: family, function: record.data["function"]?.string ?? "standard", formats: formats)
        }.sorted { $0.mechanicalFamily == $1.mechanicalFamily ? $0.title < $1.title : $0.mechanicalFamily < $1.mechanicalFamily }
    }
    var insulationFamilies: [DoublageInsulationFamily] {
        (payload?.isolants ?? []).compactMap { record in
            let lambdas = record.data["lambdas"]?.array?.compactMap { item -> DoublageInsulationLambda? in
                guard let object = item.object, let lambda = object["lambda_w_mk"]?.number else { return nil }
                let thicknesses = object["thicknesses_mm"]?.array?.compactMap(\.number).map(Int.init).sorted() ?? []
                return thicknesses.isEmpty ? nil : .init(value: lambda, thicknessesMM: thicknesses)
            } ?? []
            return lambdas.isEmpty ? nil : DoublageInsulationFamily(id: record.id, code: record.data["code"]?.string ?? record.id, title: record.title, lambdas: lambdas)
        }.sorted { $0.title < $1.title }
    }
    func load() async {
        isLoading = true; error = nil
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(DoublageCataloguePayload.self, from: data)
            guard let section = decoded.doublageFourrures, section.ouvrage != nil,
                  section.regles?.data["schema_version"]?.number == 1,
                  section.quantitatif?.data["schema_version"]?.number == 1 else { throw URLError(.zeroByteResource) }
            payload = section
        } catch {
            self.error = "Les données de cet ouvrage ne sont pas disponibles. Vérifiez la connexion et Plaquisto Admin, puis réessayez."
        }
        isLoading = false
    }
    private func ruleNumber(_ key: String) -> Double { payload?.regles?.data[key]?.number ?? 0 }
}
