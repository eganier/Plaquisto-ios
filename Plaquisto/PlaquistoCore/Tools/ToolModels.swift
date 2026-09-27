import Foundation

enum ToolCategory: String, CaseIterable, Identifiable {
    case isolation = "Isolation"
    case partitions = "Cloisons & doublages"
    case ceilings = "Plafonds"
    case layout = "Traçage & calepinage"
    case angles = "Mesure d’angle"
    case photos = "Photos chantier"
    case site = "Calculs chantier"

    var id: String { rawValue }
}

enum ToolDestination: String, Hashable {
    case thermal, ceilingSpan, partitionHeight, furringSpacing
    case layout, liningHeight, vat, arch, wallAngle, exteriorWallAngle, beforeAfter
}

struct ToolDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let shortDescription: String
    let icon: String
    let category: ToolCategory
    let keywords: [String]
    let destination: ToolDestination
    var isAvailable: Bool { true }

    var searchableText: String {
        ([title, shortDescription, category.rawValue] + keywords)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

enum ToolCatalog {
    static let all: [ToolDefinition] = [
        .init(id: "before-after", title: "Montage avant / après", shortDescription: "Superposez deux photos avec une aide au cadrage et créez un montage prêt à partager.", icon: "rectangle.on.rectangle.angled", category: .photos, keywords: ["avant après", "photo chantier", "comparatif", "rénovation", "export", "partage"], destination: .beforeAfter),
        .init(id: "thermal", title: "Résistance thermique", shortDescription: "Calculer R, l’épaisseur ou le lambda d’un isolant.", icon: "thermometer.medium", category: .isolation, keywords: ["R", "lambda", "épaisseur", "isolant"], destination: .thermal),
        .init(id: "furring-spacing", title: "Entraxe des fourrures selon l’isolant", shortDescription: "Identifier l’entraxe recommandé entre fourrures selon la masse surfacique de l’isolant.", icon: "arrow.left.and.right", category: .ceilings, keywords: ["fourrure", "laine", "densité", "poids", "masse surfacique"], destination: .furringSpacing),
        .init(id: "partition-height", title: "Hauteur de cloison", shortDescription: "Vérifier ou rechercher une configuration compatible.", icon: "rectangle.split.3x1", category: .partitions, keywords: ["montant", "rail", "entraxe", "BA13"], destination: .partitionHeight),
        .init(id: "lining-height", title: "Hauteur de doublage", shortDescription: "Contrôler un doublage sur montants ou fourrures.", icon: "square.3.layers.3d", category: .partitions, keywords: ["appui", "fourrure", "montant", "doublage"], destination: .liningHeight),
        .init(id: "ceiling-span", title: "Plafond autoportant", shortDescription: "Vérifier une portée ou trouver les montages compatibles.", icon: "rectangle.topthird.inset.filled", category: .ceilings, keywords: ["portée", "montant", "plafond", "autoportant"], destination: .ceilingSpan),
        .init(id: "layout", title: "Calepinage 2D", shortDescription: "Positionner les plaques, joints, coupes et ouvertures.", icon: "square.grid.3x3", category: .layout, keywords: ["plaque", "joint", "découpe", "mur", "plafond"], destination: .layout),
        .init(id: "arch", title: "Gabarit d’arche", shortDescription: "Tracer une arche et obtenir sa table de points.", icon: "pencil.and.ruler", category: .layout, keywords: ["arc", "ellipse", "gabarit", "courbe"], destination: .arch),
        .init(id: "wall-angle", title: "Angle intérieur", shortDescription: "0–180°", icon: "angle", category: .angles, keywords: ["angle entre deux murs", "équerre", "degrés", "triangle", "mètre"], destination: .wallAngle),
        .init(id: "exterior-wall-angle", title: "Angle extérieur", shortDescription: "180–360°", icon: "angle", category: .angles, keywords: ["réflexe", "rentrant", "degrés", "triangle", "mètre", "murs"], destination: .exteriorWallAngle),
        .init(id: "vat", title: "Calcul de TVA", shortDescription: "Passer de HT à TTC ou de TTC à HT.", icon: "percent", category: .site, keywords: ["prix", "HT", "TTC", "TVA"], destination: .vat)
    ]

    static func search(_ query: String) -> [ToolDefinition] {
        let normalized = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return all }
        return all.filter { $0.searchableText.contains(normalized) }
    }
}

enum WallAngleError: Error, LocalizedError, Equatable {
    case invalidEqualSide, invalidOppositeSide, impossibleTriangle
    var errorDescription: String? {
        switch self {
        case .invalidEqualSide: return "La distance L doit être supérieure à 0."
        case .invalidOppositeSide: return "La distance entre les repères doit être supérieure à 0."
        case .impossibleTriangle: return "Cette mesure est impossible : la distance entre les repères doit être inférieure à deux fois la distance mesurée sur les murs."
        }
    }
}
enum WallAngleKind {
    case interior, exterior
    var title: String { self == .interior ? "Angle intérieur" : "Angle extérieur" }
    var range: String { self == .interior ? "0–180°" : "180–360°" }
    var explanation: String {
        self == .interior ? "Le plus petit angle entre les deux murs." : "L’angle restant autour du sommet, supérieur à 180°."
    }
    var equalSideTitle: String {
        self == .interior ? "L · Distance sur chaque mur" : "L · Distance sur les prolongements"
    }
    var measurementHelp: String {
        if self == .interior {
            return "Mesurez directement entre les deux murs."
        }
        return "Prolongez l’alignement des deux murs dans le vide, puis mesurez entre les deux prolongements."
    }
}

struct WallAngleResult: Equatable {
    let interiorDegrees: Double
    let exteriorDegrees: Double
    func degrees(for kind: WallAngleKind) -> Double {
        kind == .interior ? interiorDegrees : exteriorDegrees
    }
}

enum WallAngleCalculator {
    static func calculate(equalSide:Double, oppositeSide:Double) throws -> WallAngleResult {
        guard equalSide.isFinite, equalSide > 0 else { throw WallAngleError.invalidEqualSide }
        guard oppositeSide.isFinite, oppositeSide > 0 else { throw WallAngleError.invalidOppositeSide }
        // Divide first to avoid overflowing 2 × L for extreme inputs.
        let ratio = (oppositeSide/equalSide)/2
        guard ratio.isFinite, ratio > 0, ratio < 1 else { throw WallAngleError.impossibleTriangle }
        let degrees = 2 * asin(min(1,max(0,ratio))) * 180 / .pi
        guard degrees.isFinite, degrees > 0, degrees < 180 else { throw WallAngleError.impossibleTriangle }
        let exterior = 360 - degrees
        guard exterior > 180, exterior < 360 else { throw WallAngleError.impossibleTriangle }
        return WallAngleResult(interiorDegrees: degrees, exteriorDegrees: exterior)
    }
    // Compatibility entry point: the geometry and validation live only in calculate.
    static func angle(equalSide:Double, oppositeSide:Double) throws -> Double {
        try calculate(equalSide:equalSide, oppositeSide:oppositeSide).interiorDegrees
    }
    static func formattedDegrees(_ value:Double, signed:Bool = false) -> String {
        let rounded = (value*10).rounded()/10
        let number = (rounded == 0 ? 0 : value).formatted(.number.locale(Locale(identifier:"fr_FR")).precision(.fractionLength(1)))
        return (signed && rounded > 0 ? "+" : "") + number + "°"
    }
}

enum ThermalCalculator {
    static func catalogueLambda(conductivity: String?, lambda: Double?) -> Double? {
        if let conductivity,
           let match = conductivity.range(of: #"0[,.]\d+"#, options: .regularExpression),
           let value = Double(conductivity[match].replacingOccurrences(of: ",", with: ".")) { return value }
        return lambda
    }
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
