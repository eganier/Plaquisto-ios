import Foundation

enum ToolCategory: String, CaseIterable, Identifiable {
    case isolation = "Isolation"
    case partitions = "Cloisons & doublages"
    case ceilings = "Plafonds"
    case layout = "Traçage & calepinage"
    case site = "Calculs chantier"

    var id: String { rawValue }
}

enum ToolDestination: String, Hashable {
    case thermal, ceilingSpan, partitionHeight, furringSpacing
    case layout, liningHeight, vat, arch
}

struct ToolDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let shortDescription: String
    let icon: String
    let category: ToolCategory
    let keywords: [String]
    let destination: ToolDestination
    var isAvailable: Bool { destination != .layout }

    var searchableText: String {
        ([title, shortDescription, category.rawValue] + keywords)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

enum ToolCatalog {
    static let all: [ToolDefinition] = [
        .init(id: "thermal", title: "Résistance thermique", shortDescription: "Calculer R, l’épaisseur ou le lambda d’un isolant.", icon: "thermometer.medium", category: .isolation, keywords: ["R", "lambda", "épaisseur", "isolant"], destination: .thermal),
        .init(id: "furring-spacing", title: "Entraxe selon l’isolant", shortDescription: "Contrôler la masse surfacique et la règle d’entraxe disponible.", icon: "arrow.left.and.right", category: .isolation, keywords: ["fourrure", "laine", "densité", "poids"], destination: .furringSpacing),
        .init(id: "partition-height", title: "Hauteur de cloison", shortDescription: "Vérifier ou rechercher une configuration compatible.", icon: "rectangle.split.3x1", category: .partitions, keywords: ["montant", "rail", "entraxe", "BA13"], destination: .partitionHeight),
        .init(id: "lining-height", title: "Hauteur de doublage", shortDescription: "Contrôler un doublage sur montants ou fourrures.", icon: "square.3.layers.3d", category: .partitions, keywords: ["appui", "fourrure", "montant", "doublage"], destination: .liningHeight),
        .init(id: "ceiling-span", title: "Plafond autoportant", shortDescription: "Vérifier une portée ou trouver les montages compatibles.", icon: "rectangle.topthird.inset.filled", category: .ceilings, keywords: ["portée", "montant", "plafond", "autoportant"], destination: .ceilingSpan),
        .init(id: "layout", title: "Calepinage 2D", shortDescription: "Positionner les plaques, joints, coupes et ouvertures.", icon: "square.grid.3x3", category: .layout, keywords: ["plaque", "joint", "découpe", "mur", "plafond"], destination: .layout),
        .init(id: "arch", title: "Gabarit d’arche", shortDescription: "Tracer une arche et obtenir sa table de points.", icon: "pencil.and.ruler", category: .layout, keywords: ["arc", "ellipse", "gabarit", "courbe"], destination: .arch),
        .init(id: "vat", title: "Calcul de TVA", shortDescription: "Passer de HT à TTC ou de TTC à HT.", icon: "percent", category: .site, keywords: ["prix", "HT", "TTC", "TVA"], destination: .vat)
    ]

    static func search(_ query: String) -> [ToolDefinition] {
        let normalized = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return all }
        return all.filter { $0.searchableText.contains(normalized) }
    }
}

enum ThermalMode: String, CaseIterable, Identifiable {
    case resistance = "Trouver R"
    case thickness = "Trouver l’épaisseur"
    case lambda = "Trouver λ"
    var id: String { rawValue }
}

enum ThermalCalculator {
    static func resistance(thicknessMM: Double, lambda: Double) -> Double? {
        guard thicknessMM > 0, lambda > 0 else { return nil }
        let value = thicknessMM / 1_000 / lambda
        return value.isFinite ? value : nil
    }
    static func thickness(resistance: Double, lambda: Double) -> Double? {
        guard resistance > 0, lambda > 0 else { return nil }
        let value = resistance * lambda * 1_000
        return value.isFinite ? value : nil
    }
    static func lambda(thicknessMM: Double, resistance: Double) -> Double? {
        guard thicknessMM > 0, resistance > 0 else { return nil }
        let value = thicknessMM / 1_000 / resistance
        return value.isFinite ? value : nil
    }
}

enum VATDirection: String, CaseIterable, Identifiable {
    case netToGross = "HT → TTC"
    case grossToNet = "TTC → HT"
    var id: String { rawValue }
}

struct VATResult: Equatable {
    let net: Decimal
    let tax: Decimal
    let gross: Decimal
}

enum VATCalculator {
    static func calculate(amount: Decimal, rate: Decimal, direction: VATDirection) -> VATResult? {
        guard amount >= 0, rate >= 0 else { return nil }
        let divisor = Decimal(1) + rate / 100
        let net = direction == .netToGross ? amount : amount / divisor
        let gross = direction == .netToGross ? amount * divisor : amount
        return .init(net: rounded(net), tax: rounded(gross - net), gross: rounded(gross))
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var source = value, result = Decimal()
        NSDecimalRound(&result, &source, 2, .bankers)
        return result
    }
}

enum ArchKind: String, CaseIterable, Identifiable {
    case veryShallow = "Très surbaissée"
    case shallow = "Surbaissée"
    case rounded = "Arrondie"
    case semicircle = "Plein cintre"
    case elliptical = "Elliptique"
    var id: String { rawValue }

    var exponent: Double {
        switch self {
        case .veryShallow: 4.5
        case .shallow: 3
        case .rounded: 2.3
        case .semicircle, .elliptical: 2
        }
    }
}

struct ArchPoint: Identifiable, Equatable {
    let x: Double
    let y: Double
    var id: String { "\(x)-\(y)" }
}

enum ArchCalculator {
    static func points(kind: ArchKind, width: Double, rise requestedRise: Double, spacing: Double) -> [ArchPoint] {
        guard width > 0, spacing > 0 else { return [] }
        let rise = kind == .semicircle ? width / 2 : requestedRise
        guard rise > 0 else { return [] }
        var xs = stride(from: 0.0, through: width, by: spacing).map { min($0, width) }
        if xs.last != width { xs.append(width) }
        if !xs.contains(where: { abs($0 - width / 2) < 0.000_001 }) { xs.append(width / 2) }
        return xs.sorted().map { x in
            let u = abs((x - width / 2) / (width / 2))
            let inside = max(0, 1 - pow(u, kind.exponent))
            return ArchPoint(x: x, y: rise * pow(inside, 1 / kind.exponent))
        }
    }
}
