import Foundation

struct SupplyListingEntry {
    let name: String
    let quantity: Double
    let unit: String
}

struct SupplyListingRow: Identifiable {
    struct Measurement: Identifiable {
        let unit: String
        let quantity: Double
        var id: String { unit }
    }

    let name: String
    let measurements: [Measurement]
    var id: String { name }

    var value: String {
        measurements.map { measurement in
            let discrete = SupplyListingConsolidator.isDiscrete(measurement.unit)
            let number = discrete
                ? String(Int(ceil(measurement.quantity)))
                : measurement.quantity.formatted(.number.precision(.fractionLength(0...2)))
            return "\(number) \(measurement.unit)"
        }
        .joined(separator: " · ")
    }
}

/// Builds a purchasing-oriented list: installation roles are removed when they
/// refer to the very same product, while each useful measurement is retained.
enum SupplyListingConsolidator {
    /// Quantities keep their calculation units internally. Purchasing screens
    /// and exports show facing area, using only explicitly dimensioned boards.
    static func displayedMeasurement(_ entry: SupplyListingEntry) -> SupplyListingEntry {
        guard canonicalUnit(entry.unit) == "plaques",
              let expression = try? NSRegularExpression(pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*[×x]\s*([0-9]+(?:[.,][0-9]+)?)\s*(mm|cm|m)$"#),
              let match = expression.firstMatch(in: entry.name, range: NSRange(entry.name.startIndex..., in: entry.name)) else { return entry }
        func part(_ index: Int) -> String {
            Range(match.range(at: index), in: entry.name).map { String(entry.name[$0]) } ?? ""
        }
        guard let width = Double(part(1).replacingOccurrences(of: ",", with: ".")),
              let length = Double(part(2).replacingOccurrences(of: ",", with: ".")),
              width > 0, length > 0 else { return entry }
        let scale = part(3) == "mm" ? 0.001 : part(3) == "cm" ? 0.01 : 1
        let quantity = entry.quantity * width * length * scale * scale
        guard quantity.isFinite else { return entry }
        return .init(name: entry.name, quantity: quantity, unit: "m²")
    }

    /// Legacy assembly stored as one unit: preserve its count for EACH component.
    static func components(_ entry: SupplyListingEntry) -> [SupplyListingEntry] {
        guard entry.name.trimmingCharacters(in: .whitespacesAndNewlines) == "Cheville et piton",
              canonicalUnit(entry.unit) == "unités" else { return [entry] }
        return ["Cheville crampon 8 mm", "Piton de suspension 8 mm"].map {
            .init(name: $0, quantity: entry.quantity, unit: "unités")
        }
    }

    static func rows(_ entries: [SupplyListingEntry]) -> [SupplyListingRow] {
        var namesInOrder: [String] = []
        var unitsInOrder: [String: [String]] = [:]
        var totals: [String: [String: Double]] = [:]

        for entry in entries.flatMap(components).map(displayedMeasurement) where entry.quantity > 0 {
            let name = canonicalName(entry.name)
            let unit = canonicalUnit(entry.unit)
            if totals[name] == nil {
                namesInOrder.append(name)
                totals[name] = [:]
                unitsInOrder[name] = []
            }
            if totals[name]?[unit] == nil {
                unitsInOrder[name, default: []].append(unit)
            }
            totals[name, default: [:]][unit, default: 0] += entry.quantity
        }

        return namesInOrder.map { name in
            let measurements = (unitsInOrder[name] ?? []).compactMap { unit -> SupplyListingRow.Measurement? in
                guard let quantity = totals[name]?[unit] else { return nil }
                return .init(unit: unit, quantity: quantity)
            }
            return SupplyListingRow(name: name, measurements: measurements)
        }
    }

    static func canonicalName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let insulation = canonicalInsulationName(name) { return insulation }

        for prefix in ["Première peau · ", "Deuxième peau · ", "Troisième peau · "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }

        for prefix in ["Parement · 1re peau · ", "Parement · 2e peau · ", "Parement · 3e peau · "] where name.hasPrefix(prefix) {
            name = "Parement · " + String(name.dropFirst(prefix.count))
        }
        // Facing identity is shared by partitions, linings and the plan engine.
        // Strip presentation words only, never dimensions or technical variants.
        if name.hasPrefix("Parement · BA") { name.removeFirst("Parement · ".count) }
        if name.range(of:#"^BA\d+\b"#,options:.regularExpression) != nil {
            name=name.replacingOccurrences(of:#"(?i)\s+(?:·\s*)?standard(?=\s*·|$)"#,with:"",options:.regularExpression)
        }

        if name == "Appuis intermédiaires pour doublage sur fourrure"
            || name.hasPrefix("Appuis intermédiaires pour doublage sur fourrure — ") {
            return "Appuis intermédiaires pour fourrures"
        }

        if name.hasSuffix(" — longueur") {
            name.removeLast(" — longueur".count)
        }
        if name.range(of: "^Rail R[0-9]+$", options: .regularExpression) != nil {
            return "Rails " + name.dropFirst(5)
        }
        if name.range(of: "^Montant M[0-9]+(?:/[0-9]+)?$", options: .regularExpression) != nil {
            return "Montants " + name.dropFirst(8)
        }
        switch name.lowercased() {
        case "vis ttpc · parement", "vis ttpc · première peau": return "Vis TTPC 25"
        case "vis ttpc · deuxième peau": return "Vis TTPC 35"
        case "suspente hourdis à griffe à serrer": return "Suspente hourdis à serrer"
        case "suspente hourdis", "suspente hourdis à griffe", "suspentes hourdis simples": return "Suspentes hourdis simples"
        case "cornière d’angle", "cornière d'angle", "cornières périphériques", "cornières", "cornière": return "Cornière"
        case "demi collier", "demi-collier": return "Demi-collier"
        case "bande pp grand rouleau", "bande à joint", "bande à joint · papier", "bande à joint papier": return "Bande à joint"
        case "vis ttpc 35 mm (2e parement)", "vis ttpc 35": return "Vis TTPC 35"
        case "vis trpf 13 · solidarisation des montants", "vis trpf 13 · fixation des suspentes",
             "vis trpf 13": return "Vis TRPF 13"
        case "fourrures f45", "fourrure f45", "fourrures f45/f47", "fourrure f45/f47",
             "fourrures de renfort", "fourrures latérales", "fourrures transversales",
             "fourrures latérales d’embrasure", "fourrures transversales d’embrasure": return "Fourrures F45/F47"
        case "vis ttpc 25 mm (1er parement)", "vis ttpc 25mm (1er parement)",
             "vis ttpc 25 ou 35", "viss ttpc 25 ou 35", "vis ttpc 25", "vis ttpc 25 mm": return "Vis TTPC 25"
        case "enduit en poudre", "enduit poudre collage, charge, finition": return "Enduit à joints en poudre"
        case "enduit en pâte", "enduit pâte prêt à l’emploi, collage, charge, finition": return "Enduit à joints en pâte"
        default: break
        }
        return name
    }

    /// Keep the complete catalogue designation; never infer a product from its
    /// material alone. Layer placement and derived R are not purchasing identities.
    static func insulationName(reference: String, thicknessMM: Double, lambda: Double?) -> String {
        func number(_ value: Double) -> String {
            let text = String(value)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text).replacingOccurrences(of: ".", with: ",")
        }
        var reference = reference
        if let lambda, lambda.isFinite, lambda > 0,
           let range = reference.range(of: #" · λ ([0-9]+(?:[.,][0-9]+)?)$"#, options: .regularExpression),
           let recorded = Double(reference[range].replacingOccurrences(of: " · λ ", with: "").replacingOccurrences(of: ",", with: ".")),
           abs(recorded - lambda) < 1e-10 {
            reference.removeSubrange(range)
        }
        let base = "Isolation · \(reference) · \(number(thicknessMM)) mm"
        guard let lambda, lambda.isFinite, lambda > 0 else { return base }
        return base + " · λ \(number(lambda))"
    }

    private static func canonicalInsulationName(_ raw: String) -> String? {
        var name = raw
        if name.hasPrefix("Isolation · ") { name.removeFirst("Isolation · ".count) }
        for prefix in ["1re couche · ", "2e couche · "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        // Only known complete legacy formats; retain unknown qualifiers and
        // incomplete references unchanged instead of merging approximately.
        let patterns = [
            (#"^(.+?)(?:, | · )λ ([0-9]+(?:[.,][0-9]+)?)(?:, | · )([0-9]+(?:[.,][0-9]+)?) mm(?:[,· ]+R [0-9]+(?:[.,][0-9]+)?)?$"#, 2, 3),
            (#"^(.+?)(?:, | · )([0-9]+(?:[.,][0-9]+)?) mm(?:, | · )λ ([0-9]+(?:[.,][0-9]+)?)(?:[,· ]+R [0-9]+(?:[.,][0-9]+)?)?$"#, 3, 2)
        ]
        for (pattern, lambdaIndex, thicknessIndex) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let referenceRange = Range(match.range(at: 1), in: name),
                  let lambdaRange = Range(match.range(at: lambdaIndex), in: name),
                  let thicknessRange = Range(match.range(at: thicknessIndex), in: name),
                  let lambda = Double(name[lambdaRange].replacingOccurrences(of: ",", with: ".")), lambda > 0, lambda.isFinite,
                  let thickness = Double(name[thicknessRange].replacingOccurrences(of: ",", with: ".")), thickness > 0, thickness.isFinite
            else { continue }
            let reference = String(name[referenceRange])
            guard reference != "Isolant", !reference.contains("λ") else { return nil }
            return insulationName(reference: reference, thicknessMM: thickness, lambda: lambda)
        }
        return nil
    }

    static func canonicalUnit(_ rawUnit: String) -> String {
        switch rawUnit.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() {
        case "unité", "unités", "unité(s)", "unite", "unites", "u", "u.", "pièce", "pièces": return "unités"
        case "plaque", "plaques", "plaque(s)": return "plaques"
        case "ml", "m.l.", "mètre linéaire", "mètres linéaires": return "ml"
        case "m2", "m²", "mètre carré", "mètres carrés": return "m²"
        case "kg", "kilogramme", "kilogrammes": return "kg"
        case "l", "litre", "litres": return "l"
        default: return rawUnit.trimmingCharacters(in:.whitespacesAndNewlines)
        }
    }

    static func isDiscrete(_ unit: String) -> Bool {
        let unit = canonicalUnit(unit)
        return unit == "unités" || unit == "plaques"
    }
}

enum OpeningWorkSystem: String, CaseIterable, Codable, Identifiable {
    case furringLining
    case railStudLining
    case distributionPartition
    case furringCeiling
    case railStudCeiling

    var id: Self { self }

    var title: String {
        switch self {
        case .furringLining: "Doublage lisses/fourrures"
        case .railStudLining: "Doublage rails/montants"
        case .distributionPartition: "Cloison de distribution"
        case .furringCeiling: "Plafond en fourrures"
        case .railStudCeiling: "Plafond rails/montants"
        }
    }

    var usesFurrings: Bool { self == .furringLining || self == .furringCeiling }
    var usesStuds: Bool { self == .railStudLining || self == .distributionPartition || self == .railStudCeiling }
    var isCeiling: Bool { self == .furringCeiling || self == .railStudCeiling }
    var isPeripheralLining: Bool { self == .furringLining || self == .railStudLining }

    var availableOpeningKinds: [OpeningKind] {
        switch self {
        case .furringLining, .railStudLining: [.window, .frenchDoorOrBay, .niche]
        case .distributionPartition: [.interiorDoor, .pocketDoor, .window, .niche]
        case .furringCeiling, .railStudCeiling: [.roofWindow]
        }
    }
}

enum OpeningKind: String, CaseIterable, Codable, Identifiable {
    case window
    case frenchDoorOrBay
    case interiorDoor
    case pocketDoor
    case roofWindow
    case niche

    var id: Self { self }

    var title: String {
        switch self {
        case .window: "Fenêtre"
        case .frenchDoorOrBay: "Porte-fenêtre / baie"
        case .interiorDoor: "Porte intérieure"
        case .pocketDoor: "Galandage"
        case .roofWindow: "Fenêtre de toit"
        case .niche: "Niche"
        }
    }

    var symbol: String {
        switch self {
        case .window: "window.vertical.closed"
        case .frenchDoorOrBay: "door.french.closed"
        case .interiorDoor: "door.left.hand.closed"
        case .pocketDoor: "rectangle.split.2x1"
        case .roofWindow: "window.ceiling"
        case .niche: "square.dashed"
        }
    }

    var isImplemented: Bool { self != .niche }

    var usesMountingMode: Bool { self == .window || self == .frenchDoorOrBay }

    func title(in system: OpeningWorkSystem) -> String {
        if self == .window, system == .distributionPartition { return "Verrière" }
        return title
    }
}

enum OpeningMountingMode: String, Codable, CaseIterable, Identifiable {
    case onJoineryLining
    case inReveal

    var id: Self { self }

    var title: String {
        switch self {
        case .onJoineryLining: "Sur tapée de menuiserie"
        case .inReveal: "En embrasure"
        }
    }
}

struct OpeningContext: Codable, Equatable {
    var system: OpeningWorkSystem
    var hsp: Double
    var spacing: Double
    var doubledStuds: Bool
    var revealDepth: Double?
    var ceilingLengthInStudDirection: Double?
    /// Exact source profile (including flange width), optional for old archives.
    var frame: String? = nil

    static func profileName(frame: String?, rail: Bool) -> String {
        let prefix = rail ? "Rails" : "Montants"
        guard let frame,
              let range = frame.range(of: rail ? "\\bR[0-9]+\\b" : "\\bM[0-9]+(?:/[0-9]+)?\\b", options: .regularExpression)
        else { return "\(prefix) — référence à préciser" }
        return "\(prefix) \(frame[range])"
    }
    var studName: String { Self.profileName(frame: frame, rail: false) }
    var railName: String { Self.profileName(frame: frame, rail: true) }

    init(
        system: OpeningWorkSystem = .furringLining,
        hsp: Double = 0,
        spacing: Double = 0.60,
        doubledStuds: Bool = false,
        revealDepth: Double? = nil,
        ceilingLengthInStudDirection: Double? = nil,
        frame: String? = nil
    ) {
        self.system = system
        self.hsp = hsp
        self.spacing = spacing
        self.doubledStuds = doubledStuds
        self.revealDepth = revealDepth
        self.ceilingLengthInStudDirection = ceilingLengthInStudDirection
        self.frame = frame
    }
}

struct OpeningInput: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: OpeningKind
    var width: Double
    var height: Double
    var mountingMode: OpeningMountingMode
    var revealDepth: Double?
    /// Nom personnalisé facultatif. Les anciennes données sans nom continuent
    /// d'utiliser le libellé numéroté généré par l'interface.
    var name: String? = nil

    init(
        id: UUID = UUID(),
        kind: OpeningKind,
        width: Double,
        height: Double,
        mountingMode: OpeningMountingMode = .onJoineryLining,
        revealDepth: Double? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.width = width
        self.height = height
        self.mountingMode = mountingMode
        self.revealDepth = revealDepth
        self.name = name
    }

    var area: Double { width * height }
}

struct OpeningQuantity: Identifiable, Codable, Equatable {
    enum Unit: String, Codable {
        case unit = "unités"
        case linearMeter = "ml"
        case squareMeter = "m²"
    }

    var name: String
    var quantity: Double
    var unit: Unit
    var id: String { "\(name)|\(unit.rawValue)" }
}

struct OpeningQuantityResult: Codable, Equatable {
    var opening: OpeningInput
    var quantities: [OpeningQuantity]
    var insulationAreaDeduction: Double
    var notes: [String]
    var isComplete: Bool
}

struct OpeningConfiguration: Codable, Equatable {
    var context: OpeningContext = OpeningContext()
    var openings: [OpeningInput] = []
    /// Ouvrage dont la hauteur et le système servent de référence.
    /// Optionnel pour relire sans migration les configurations historiques.
    var sourceWorkID: UUID? = nil
    var roomName: String? = nil
}

struct OpeningSummaryLine: Identifiable, Equatable {
    let kind: OpeningKind
    let width: Double
    let height: Double
    let count: Int
    let title: String

    var id: String {
        "\(kind.rawValue)|\(Int((width * 10_000).rounded()))|\(Int((height * 10_000).rounded()))"
    }
}

enum OpeningSummaryFormatter {
    static func lines(for configuration: OpeningConfiguration) -> [OpeningSummaryLine] {
        struct Key: Hashable {
            let kind: OpeningKind
            let widthCentimeters: Int
            let heightCentimeters: Int
        }

        var keys: [Key] = []
        var counts: [Key: Int] = [:]
        for opening in configuration.openings {
            let key = Key(
                kind: opening.kind,
                widthCentimeters: Int((opening.width * 100).rounded()),
                heightCentimeters: Int((opening.height * 100).rounded())
            )
            if counts[key] == nil { keys.append(key) }
            counts[key, default: 0] += 1
        }

        return keys.map { key in
            let count = counts[key, default: 0]
            return OpeningSummaryLine(
                kind: key.kind,
                width: Double(key.widthCentimeters) / 100,
                height: Double(key.heightCentimeters) / 100,
                count: count,
                title: pluralTitle(for: key.kind, system: configuration.context.system, count: count)
            )
        }
    }

    private static func pluralTitle(for kind: OpeningKind, system: OpeningWorkSystem, count: Int) -> String {
        if count == 1 { return kind.title(in: system) }
        if kind == .window, system == .distributionPartition { return "Verrières" }
        return switch kind {
        case .window: "Fenêtres"
        case .frenchDoorOrBay: "Portes-fenêtres / baies"
        case .interiorDoor: "Portes intérieures"
        case .pocketDoor: "Galandages"
        case .roofWindow: "Fenêtres de toit"
        case .niche: "Niches"
        }
    }
}

struct OpeningHeightSuggestion: Identifiable, Equatable {
    var id: UUID { sourceWorkID }
    var sourceWorkID: UUID
    var height: Double
    var sourceWorkName: String
    var spacing: Double
    var doubledStuds: Bool
    /// Profondeur minimale de tapée imposée par la composition de l'ouvrage lié.
    /// Nil pour les systèmes qui ne portent pas cette règle métier.
    var minimumJoineryLiningDepth: Double?
    var frame: String? = nil
}
