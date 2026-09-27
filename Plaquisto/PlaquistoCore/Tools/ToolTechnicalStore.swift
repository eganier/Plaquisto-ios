import Foundation
import SwiftUI

struct CeilingSpanOption: Identifiable, Hashable {
    let assembly: String
    let facing: String
    let stud: Int
    let spans: [Double]
    var id: String { "\(assembly)-\(facing)-\(stud)" }
    var title: String { "M\(stud) · \(assembly == "single" ? "simples" : "doublés") · \(facingLabel)" }
    var facingLabel: String {
        switch facing {
        case "ba13": "1 × BA13"
        case "ba18": "1 × BA18"
        case "double_ba13": "2 × BA13"
        case "acoustic_ba13": "1 × BA13 technique"
        case "double_acoustic_ba13": "2 × BA13 techniques"
        default: facing
        }
    }
}

struct PartitionHeightOption: Identifiable, Hashable {
    let id: String
    let type: String
    let frame: String
    let frameWidthMM: Int
    let facing: String
    let layers: Int
    let heights: [String: Double]
    var title: String { "\(type) · \(frame) · \(layers) peau\(layers > 1 ? "x" : "") \(facing)" }
}

struct LiningHeightOption: Identifiable, Hashable {
    let id: String
    let label: String
    let layers: Int
    let supportedFacings: [String]
    let frame: String
    let spacing: Double
    let assembly: String
    let maximumHeight: Double
    var title: String { "\(frame) · \(assembly) · entraxe \(Int(spacing * 100)) cm" }
}

struct FurringSupportOption: Identifiable, Hashable {
    let id: String
    let title: String
    let layers: Int
    let supportedFacings: [String]
    let maximumHeight: Double
    let maximumSupportSpacing: Double
}

struct InsulationMassOption: Identifiable, Hashable {
    let id: String
    let title: String
    let material: String
    let lambda: Double
    let thicknessMM: Int
    let surfaceMass: Double
}

struct InsulationSpacingBand: Identifiable, Hashable {
    let minimumMass: Double
    let maximumMass: Double
    let spacing: Double
    let maximumExclusive: Bool
    var id: String { "\(minimumMass)-\(maximumMass)-\(spacing)" }

    func contains(_ mass: Double) -> Bool {
        mass >= minimumMass && (maximumExclusive ? mass < maximumMass : mass <= maximumMass)
    }
}

@MainActor
final class ToolTechnicalStore: ObservableObject {
    @Published private(set) var ceilingSpans: [CeilingSpanOption] = []
    @Published private(set) var partitionHeights: [PartitionHeightOption] = []
    @Published private(set) var liningHeights: [LiningHeightOption] = []
    @Published private(set) var furringSupports: [FurringSupportOption] = []
    @Published private(set) var insulationMasses: [InsulationMassOption] = []
    @Published private(set) var insulationSpacingBands: [InsulationSpacingBand] = []
    @Published private(set) var layoutFormats: [LayoutCatalogFormat] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isOffline = false
    @Published private(set) var error: String?

    private let endpoint = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!
    private let cacheKey = "plaquisto.tools.catalogue.v1"

    func load() async {
        guard ceilingSpans.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            try parse(data)
            UserDefaults.standard.set(data, forKey: cacheKey)
            isOffline = false
        } catch {
            if let data = UserDefaults.standard.data(forKey: cacheKey), (try? parse(data)) != nil {
                isOffline = true
            } else {
                self.error = "Les données techniques ne sont pas disponibles. Une première connexion à Plaquisto Admin est nécessaire."
            }
        }
        isLoading = false
    }

    private func parse(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }

        layoutFormats = array(root["parements"]).flatMap { record -> [LayoutCatalogFormat] in
            guard let id = record["id"] as? String, let title = record["title"] as? String else { return [] }
            return array(dictionary(record["data"])?["dimensions"]).compactMap { dimension in
                guard let width = number(dimension["width_mm"]), let length = number(dimension["length_mm"]), width > 0, length > 0 else { return nil }
                return .init(id: "\(id)-\(width)-\(length)", title: title, width: width, length: length)
            }
        }

        let ceilingData = recordData(in: dictionary(root["plafondRailsMontants"]))
        ceilingSpans = array(ceilingData?["spans"]).compactMap { item in
            guard let assembly = item["assembly"] as? String,
                  let facing = item["facing"] as? String,
                  let stud = number(item["stud"]),
                  let spans = item["spans_m"] as? [NSNumber] else { return nil }
            return CeilingSpanOption(assembly: assembly, facing: facing, stud: Int(stud), spans: spans.map(\.doubleValue))
        }.sorted { ($0.stud, $0.assembly) < ($1.stud, $1.assembly) }

        let partitionSection = dictionary(root["cloisonDistribution"])
        let partitionData = recordData(in: partitionSection)
        partitionHeights = array(partitionData?["systems"]).compactMap { item in
            guard let id = item["id"] as? String,
                  let type = item["type"] as? String,
                  let frame = item["frame"] as? String,
                  let facing = item["facing_family"] as? String,
                  let layers = number(item["layers_per_face"]),
                  let rawHeights = item["heights"] as? [String: NSNumber] else { return nil }
            return PartitionHeightOption(
                id: id,
                type: type,
                frame: frame,
                frameWidthMM: Int(number(item["frame_width_mm"]) ?? 0),
                facing: facing,
                layers: Int(layers),
                heights: rawHeights.mapValues(\.doubleValue)
            )
        }

        let liningData = recordData(in: dictionary(root["doublage"]))
        liningHeights = array(liningData?["groups"]).flatMap { group -> [LiningHeightOption] in
            let groupID = group["id"] as? String ?? UUID().uuidString
            let label = group["label"] as? String ?? "Parement"
            let layers = label.contains("Double peau") ? 2 : (label.contains("Triple peau") ? 3 : 1)
            let supportedFacings: [String]
            switch groupID {
            case "BA13_BA15": supportedFacings = ["BA13", "BA15"]
            case "BA18": supportedFacings = ["BA18"]
            case "DOUBLE_1200": supportedFacings = ["BA13", "BA15", "BA18"]
            default: supportedFacings = []
            }
            return array(group["values"]).flatMap { value -> [LiningHeightOption] in
                guard let frame = value["frame"] as? String, let spacing = number(value["spacing_m"]) else { return [] }
                let simple = number(value["simple_m"]) ?? 0
                let double = number(value["double_m"]) ?? 0
                return [
                    .init(id: "\(groupID)-\(frame)-\(spacing)-simple", label: label, layers: layers, supportedFacings: supportedFacings, frame: frame, spacing: spacing, assembly: "Montants simples", maximumHeight: simple),
                    .init(id: "\(groupID)-\(frame)-\(spacing)-double", label: label, layers: layers, supportedFacings: supportedFacings, frame: frame, spacing: spacing, assembly: "Montants doublés", maximumHeight: double)
                ].filter { $0.maximumHeight > 0 }
            }
        }

        let furringData = recordData(in: dictionary(root["doublageFourrures"]))
        furringSupports = array(furringData?["support_rules"]).compactMap { item in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  let maxHeight = number(item["maximum_height_m"]),
                  let maxSpacing = number(item["maximum_support_spacing_m"]) else { return nil }
            let layers: Int
            if id.contains("triple") { layers = 3 }
            else if id.contains("double") { layers = 2 }
            else { layers = 1 }
            let supportedFacings: [String]
            switch id {
            case "single-ba13-ba15": supportedFacings = ["BA13", "BA15"]
            case "single-ba18": supportedFacings = ["BA18"]
            case "double-skin": supportedFacings = ["BA13"]
            case "triple-ba13": supportedFacings = ["BA13"]
            default: supportedFacings = []
            }
            return .init(id: id, title: title, layers: layers, supportedFacings: supportedFacings, maximumHeight: maxHeight, maximumSupportSpacing: maxSpacing)
        }

        let insulationRecords = array(root["isolation"])
        insulationMasses = insulationRecords.flatMap { record -> [InsulationMassOption] in
            let id = record["id"] as? String ?? UUID().uuidString
            let title = record["title"] as? String ?? "Isolant"
            let data = dictionary(record["data"])
            let material = data?["material"] as? String
                ?? title.components(separatedBy: " · ").first
                ?? title
            let lambda = number(data?["lambda_w_mk"]) ?? parsedLambda(data?["conductivity"] as? String ?? title)
            return array(data?["values"]).compactMap { value in
                guard let thickness = number(value["thickness_mm"]), let mass = number(value["max_weight_kg_m2"]) else { return nil }
                return .init(id: "\(id)-\(Int(thickness))", title: title, material: material, lambda: lambda, thicknessMM: Int(thickness), surfaceMass: mass)
            }
        }.sorted { ($0.title, $0.thicknessMM) < ($1.title, $1.thicknessMM) }

        let spacingRule = array(root["regles"]).first { $0["id"] as? String == "RULE-ISOLATION-SPACING" }
        let spacingData = dictionary(spacingRule?["data"])
        insulationSpacingBands = array(spacingData?["bands"]).compactMap { band in
            guard let minimum = number(band["min_kg_m2"]),
                  let maximum = number(band["max_kg_m2"]),
                  let spacing = number(band["spacing_m"]) else { return nil }
            return .init(minimumMass: minimum, maximumMass: maximum, spacing: spacing, maximumExclusive: band["max_exclusive"] as? Bool ?? false)
        }.sorted { $0.minimumMass < $1.minimumMass }
    }

    private func recordData(in section: [String: Any]?) -> [String: Any]? {
        guard let section else { return nil }
        let record = dictionary(section["regles"]) ?? dictionary(section["performance"])
        return dictionary(record?["data"])
    }

    private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private func array(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
    private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    private func parsedLambda(_ text: String) -> Double {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: #"0\.0[0-9]+"#, options: .regularExpression) else { return 0 }
        return Double(normalized[range]) ?? 0
    }
}
