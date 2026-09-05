import Foundation

enum BondedFacingKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case standard
    case hydro = "hydrofuge"
    case vaporBarrier = "pare_vapeur"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Standard"
        case .hydro: "Hydrofuge"
        case .vaporBarrier: "Pare-vapeur"
        }
    }
}

struct BondedComplexReference: Identifiable, Hashable {
    let facing: BondedFacingKind
    let supplyName: String
    let lambda: Double
    let insulationThicknessMM: Int
    let thermalResistance: Double
    let widthMM: Int
    let heightsMM: [Int]
    var id: String { "\(facing.rawValue)-\(lambda)-\(insulationThicknessMM)-\(widthMM)" }
}

struct BondedQuantityTable {
    let complex: Double
    let adhesive: Double
    let band: Double
    let powder: Double
    let names: [String: String]

    static let empty = BondedQuantityTable(complex: 0, adhesive: 0, band: 0, powder: 0, names: [:])
}

private struct BondedCatalogueResponse: Codable {
    let doublageColle: BondedRemotePayload?
}

private struct BondedRemotePayload: Codable {
    let ouvrage: LabReferenceRecord?
    let catalogue: LabReferenceRecord?
    let quantitatif: LabReferenceRecord?
}

@MainActor
final class BondedLiningReferenceStore: ObservableObject {
    @Published private(set) var references: [BondedComplexReference] = []
    @Published private(set) var facingKinds: [BondedFacingKind] = []
    @Published private(set) var revealDepthsMM: [Int] = []
    @Published private(set) var revealOffsetMM = 20
    @Published private(set) var quantities = BondedQuantityTable.empty
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
            let decoded = try JSONDecoder().decode(BondedCatalogueResponse.self, from: data)
            guard let payload = decoded.doublageColle, apply(payload) else { throw URLError(.zeroByteResource) }
        } catch {
            references = []
            facingKinds = []
            revealDepthsMM = []
            quantities = .empty
            self.error = "Connexion à Plaquisto Admin impossible. Vérifiez votre connexion Internet puis réessayez."
        }
        isLoading = false
    }

    @discardableResult
    private func apply(_ payload: BondedRemotePayload) -> Bool {
        guard payload.catalogue?.data["schema_version"]?.number == 1,
              payload.quantitatif?.data["schema_version"]?.number == 1,
              let catalogue = payload.catalogue?.data,
              let quantityData = payload.quantitatif?.data else { return false }

        let facingNames: [BondedFacingKind: String] = Dictionary(uniqueKeysWithValues: (catalogue["facings"]?.array ?? []).compactMap { value in
            guard let item = value.object, let code = item["code"]?.string, let kind = BondedFacingKind(rawValue: code) else { return nil }
            return (kind, item["supply_name"]?.string ?? kind.title)
        })
        let parsed = catalogue["complexes"]?.array?.compactMap { value -> BondedComplexReference? in
            guard let item = value.object,
                  let facingCode = item["facing"]?.string,
                  let facing = BondedFacingKind(rawValue: facingCode),
                  let lambda = item["lambda_w_mk"]?.number,
                  let thickness = item["insulation_thickness_mm"]?.number,
                  let resistance = item["thermal_resistance_m2_kw"]?.number,
                  let width = item["width_mm"]?.number else { return nil }
            let heights = item["heights_mm"]?.array?.compactMap(\.number).map(Int.init).sorted() ?? []
            guard !heights.isEmpty else { return nil }
            return BondedComplexReference(
                facing: facing,
                supplyName: facingNames[facing] ?? facing.title,
                lambda: lambda,
                insulationThicknessMM: Int(thickness),
                thermalResistance: resistance,
                widthMM: Int(width),
                heightsMM: heights
            )
        } ?? []

        let coefficients = quantityData["coefficients"]?.object ?? [:]
        let parsedQuantities = BondedQuantityTable(
            complex: coefficients["complex_m2_m2"]?.number ?? 0,
            adhesive: coefficients["adhesive_kg_m2"]?.number ?? 0,
            band: coefficients["band_ml_m2"]?.number ?? 0,
            powder: coefficients["powder_kg_m2"]?.number ?? 0,
            names: quantityData["component_names"]?.object?.compactMapValues(\.string) ?? [:]
        )
        guard !parsed.isEmpty, parsedQuantities.complex > 0 else { return false }

        references = parsed
        facingKinds = BondedFacingKind.allCases.filter { kind in parsed.contains { $0.facing == kind } }
        revealDepthsMM = catalogue["reveal_depths_mm"]?.array?.compactMap(\.number).map(Int.init).sorted() ?? []
        revealOffsetMM = Int(catalogue["reveal_to_insulation_offset_mm"]?.number ?? 20)
        quantities = parsedQuantities
        return !revealDepthsMM.isEmpty
    }

    func commonLambdas(for facings: Set<BondedFacingKind>) -> [Double] { commonValues(for: facings) { $0.lambda }.sorted() }
    func commonThicknesses(for facings: Set<BondedFacingKind>, lambda: Double) -> [Int] {
        commonValues(for: facings) { abs($0.lambda - lambda) < 0.0001 ? $0.insulationThicknessMM : nil }.sorted()
    }
    func commonWidths(for facings: Set<BondedFacingKind>, lambda: Double, thickness: Int) -> [Int] {
        commonValues(for: facings) { abs($0.lambda - lambda) < 0.0001 && $0.insulationThicknessMM == thickness ? $0.widthMM : nil }.sorted()
    }
    func commonHeights(for facings: Set<BondedFacingKind>, lambda: Double, thickness: Int, width: Int) -> [Int] {
        intersect(for: facings) { reference in
            guard abs(reference.lambda - lambda) < 0.0001, reference.insulationThicknessMM == thickness, reference.widthMM == width else { return [] }
            return Set(reference.heightsMM)
        }.sorted()
    }
    func resistance(lambda: Double, thickness: Int) -> Double? {
        references.first { abs($0.lambda - lambda) < 0.0001 && $0.insulationThicknessMM == thickness }?.thermalResistance
    }
    func supplyName(for facing: BondedFacingKind) -> String {
        references.first(where: { $0.facing == facing })?.supplyName ?? facing.title
    }

    private func commonValues<T: Hashable>(for facings: Set<BondedFacingKind>, transform: (BondedComplexReference) -> T?) -> Set<T> {
        intersect(for: facings) { reference in Set(transform(reference).map { [$0] } ?? []) }
    }
    private func intersect<T: Hashable>(for facings: Set<BondedFacingKind>, values: (BondedComplexReference) -> Set<T>) -> Set<T> {
        let selected = facings.isEmpty ? Set(facingKinds.prefix(1)) : facings
        let sets = selected.map { facing in references.filter { $0.facing == facing }.reduce(into: Set<T>()) { $0.formUnion(values($1)) } }
        guard let first = sets.first else { return [] }
        return sets.dropFirst().reduce(first) { $0.intersection($1) }
    }
}
