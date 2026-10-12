import Foundation
import Combine

struct PaintingCompound: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kgPerM2MM: Double
    var thicknessMin: Double
    var thicknessMax: Double
    var thicknessDefault: Double
}

struct PaintingRules: Codable, Equatable {
    var schemaVersion: Int
    var revision: String
    var reservePercent: Double
    var airlessPercent: Double
    var yieldMin: Double
    var yieldMax: Double
    var yieldDefault: Double
    var compounds: [PaintingCompound]

    func validate() throws {
        guard schemaVersion == 1, !revision.isEmpty,
              reservePercent.isFinite, (0...100).contains(reservePercent),
              airlessPercent.isFinite, (0...100).contains(airlessPercent),
              yieldMin.isFinite, yieldMax.isFinite, yieldDefault.isFinite,
              yieldMin > 0, yieldMax > yieldMin, (yieldMin...yieldMax).contains(yieldDefault),
              !compounds.isEmpty, Set(compounds.map(\.id)).count == compounds.count,
              compounds.allSatisfy({
                  !$0.id.isEmpty && !$0.name.isEmpty && $0.kgPerM2MM.isFinite && $0.kgPerM2MM > 0 &&
                  $0.thicknessMin.isFinite && $0.thicknessMax.isFinite && $0.thicknessDefault.isFinite &&
                  $0.thicknessMin > 0 && $0.thicknessMax > $0.thicknessMin &&
                  ($0.thicknessMin...$0.thicknessMax).contains($0.thicknessDefault)
              }) else { throw PaintingError.invalidRules }
    }
}

struct PaintingPass: Codable, Equatable, Identifiable {
    var id = UUID()
    var compoundID: String
    var thicknessMM: Double
    var surfacePercent: Double = 100
}

struct PaintingProduct: Codable, Equatable {
    var name: String = ""
    var yieldM2PerL: Double
    var tint: String = ""
}

struct PaintingTreatment: Codable, Equatable {
    var rules: PaintingRules
    var skimEnabled = false
    var passes: [PaintingPass]
    var paintEnabled = true
    var primerEnabled = true
    var primer: PaintingProduct
    var finish: PaintingProduct
    var finishCoats = 2
    var airless = false
    // Nil on the original form, where paintEnabled also gated the primer.
    var independentTreatments: Bool? = true
    var includesPrimer: Bool { primerEnabled && (independentTreatments == true || paintEnabled) }

    init(rules: PaintingRules) {
        self.rules = rules
        let compound = rules.compounds.first(where: { $0.id == "finition-poudre" }) ?? rules.compounds.first
        passes = compound.map { [.init(compoundID: $0.id, thicknessMM: $0.thicknessDefault)] } ?? []
        primer = .init(yieldM2PerL: rules.yieldDefault)
        finish = .init(yieldM2PerL: rules.yieldDefault)
    }
}

enum PaintingError: LocalizedError {
    case invalidRules, invalidConfiguration, noTreatment
    var errorDescription: String? {
        switch self {
        case .invalidRules: "Les bases de calcul peinture sont indisponibles ou incompatibles. Actualisez Plaquisto Admin."
        case .invalidConfiguration: "Vérifiez la surface, les épaisseurs, les pourcentages et les rendements."
        case .noTreatment: "Choisissez au moins un ratissage ou une peinture."
        }
    }
}

struct PaintingSupply: Equatable {
    let name: String
    let quantity: Double
    let unit: String
}

enum PaintingCalculator {
    static func displayedQuantity(_ value: Double) -> Double {
        // Avoid turning 23.100000000000005 into 23.2 due only to binary round-off.
        let scaled = value * 10
        let nearest = scaled.rounded()
        let stable = abs(scaled - nearest) < 1e-9 ? nearest : scaled
        return stable.rounded(.up) / 10
    }
    static func calculate(_ configuration: PaintingBetaConfiguration) throws -> [PaintingSupply] {
        guard configuration.area.isFinite, configuration.area > 0 else { throw PaintingError.invalidConfiguration }
        guard let t = configuration.treatment else { return [] } // Legacy: never invent consumables.
        try t.rules.validate()
        guard t.skimEnabled || t.paintEnabled || t.includesPrimer else { throw PaintingError.noTreatment }
        let reserve = 1 + t.rules.reservePercent / 100
        var result: [PaintingSupply] = []
        func add(_ name: String, _ amount: Double, _ unit: String) throws {
            guard amount.isFinite, amount > 0 else { throw PaintingError.invalidConfiguration }
            if let index = result.firstIndex(where: { $0.name == name && $0.unit == unit }) {
                let total = result[index].quantity + amount
                guard total.isFinite else { throw PaintingError.invalidConfiguration }
                result[index] = .init(name: name, quantity: total, unit: unit)
            } else { result.append(.init(name: name, quantity: amount, unit: unit)) }
        }
        if t.skimEnabled {
            guard !t.passes.isEmpty else { throw PaintingError.invalidConfiguration }
            for pass in t.passes {
                guard let compound = t.rules.compounds.first(where: { $0.id == pass.compoundID }),
                      pass.thicknessMM.isFinite,
                      (t.independentTreatments == true ? PaintingPassKind.of(compound.id).rangeMM : compound.thicknessMin...compound.thicknessMax).contains(pass.thicknessMM),
                      pass.surfacePercent.isFinite, pass.surfacePercent > 0, pass.surfacePercent <= 100
                else { throw PaintingError.invalidConfiguration }
                try add("Enduit de \(compound.name)", configuration.area * (pass.surfacePercent / 100) * pass.thicknessMM * compound.kgPerM2MM * reserve, "kg")
            }
        }
        if t.paintEnabled || t.includesPrimer {
            guard !t.paintEnabled || (1...3).contains(t.finishCoats) else { throw PaintingError.invalidConfiguration }
            // Airless is retired. Preserve historical snapshots until edited.
            let paintFactor = reserve * (t.independentTreatments != true && t.airless ? 1 + t.rules.airlessPercent / 100 : 1)
            func paint(_ product: PaintingProduct, _ label: String, _ coats: Int) throws {
                guard product.yieldM2PerL.isFinite, (t.rules.yieldMin...t.rules.yieldMax).contains(product.yieldM2PerL) else {
                    throw PaintingError.invalidConfiguration
                }
                let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let tint = product.tint.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullName = label + (name.isEmpty ? "" : " · \(name)") + (tint.isEmpty ? "" : " · teinte \(tint)")
                try add(fullName, configuration.area / product.yieldM2PerL * Double(coats) * paintFactor, "L")
            }
            if t.includesPrimer { try paint(t.primer, "Impression", 1) }
            if t.paintEnabled { try paint(t.finish, "Peinture de finition", t.finishCoats) }
        }
        return result
    }
}

/// Input units, not consumption coefficients (which remain Admin-owned).
enum PaintingPassKind: String, CaseIterable, Identifiable {
    case rebouchage, charge, finition
    var id: String { rawValue }
    var title: String { switch self { case .rebouchage: "Rebouchage"; case .charge: "Garnissant"; case .finition: "Finition" } }
    var rangeMM: ClosedRange<Double> { switch self { case .rebouchage: 10...50; case .charge: 1...5; case .finition: 0.5...1 } }
    var stepMM: Double { switch self { case .rebouchage: 10; case .charge: 1; case .finition: 0.5 } }
    static func of(_ id: String) -> Self { allCases.first { id.hasPrefix($0.rawValue + "-") } ?? .finition }
}

/// Admin remains the only source of coefficients. Cache and per-work snapshots allow offline use.
@MainActor final class PaintingReferenceStore: ObservableObject {
    @Published private(set) var rules: PaintingRules?
    @Published private(set) var message: String?
    @Published private(set) var loading = false
    private let defaults: UserDefaults
    private let endpoint: URL
    private let cacheKey = "plaquisto.painting.rules.v1"
    init(defaults: UserDefaults = .standard,
         endpoint: URL = URL(string: "https://plaquisto-admin.vercel.app/api/ios/catalogue")!) {
        self.defaults = defaults; self.endpoint = endpoint
        if let data = defaults.data(forKey: cacheKey), let cached = try? JSONDecoder().decode(PaintingRules.self, from: data),
           (try? cached.validate()) != nil { rules = cached }
    }
    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PaintingError.invalidRules }
            let value = try Self.decodeCatalogue(data)
            defaults.set(try JSONEncoder().encode(value), forKey: cacheKey)
            rules = value; message = nil
        } catch {
            message = rules == nil ? "Bases peinture non disponibles. Publiez les règles dans Plaquisto Admin, puis réessayez." : "Actualisation Admin indisponible · dernières bases enregistrées."
        }
    }
    static func decodeCatalogue(_ data: Data) throws -> PaintingRules {
        struct Envelope: Decodable {
            struct Section: Decodable { struct Record: Decodable { var data: PaintingRules }; var regles: Record }
            var peintureRatissages: Section
        }
        let value = try JSONDecoder().decode(Envelope.self, from: data).peintureRatissages.regles.data
        try value.validate()
        return value
    }
}

struct SavedPaintingProduct: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var yieldM2PerL: Double
}

@MainActor final class PaintingProductStore: ObservableObject {
    @Published private(set) var products: [SavedPaintingProduct]
    private let defaults: UserDefaults
    private let key = "plaquisto.painting.personal-products.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        products = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedPaintingProduct].self, from: $0) } ?? []
    }
    func save(_ product: PaintingProduct) throws {
        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, product.yieldM2PerL.isFinite, product.yieldM2PerL > 0 else { throw PaintingError.invalidConfiguration }
        // Keep separate yields for the same product (different supports); exact duplicates are harmless.
        guard !products.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.yieldM2PerL == product.yieldM2PerL }) else { return }
        let next = (products + [.init(name: name, yieldM2PerL: product.yieldM2PerL)]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        products = next
    }
}
