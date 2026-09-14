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
    static func rows(_ entries: [SupplyListingEntry]) -> [SupplyListingRow] {
        var namesInOrder: [String] = []
        var unitsInOrder: [String: [String]] = [:]
        var totals: [String: [String: Double]] = [:]

        for entry in entries where entry.quantity > 0 {
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

        for prefix in ["Première peau · ", "Deuxième peau · ", "Troisième peau · "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }

        for prefix in ["Parement · 1re peau · ", "Parement · 2e peau · ", "Parement · 3e peau · "] where name.hasPrefix(prefix) {
            name = "Parement · " + String(name.dropFirst(prefix.count))
        }

        if name.hasPrefix("Appuis intermédiaires pour doublage sur fourrure — ") {
            return "Appuis intermédiaires pour doublage sur fourrure"
        }

        if name.hasSuffix(" — longueur") {
            name.removeLast(" — longueur".count)
        }
        return name
    }

    static func canonicalUnit(_ rawUnit: String) -> String {
        switch rawUnit.lowercased() {
        case "unité", "unités": "unités"
        case "plaque", "plaques", "plaque(s)": "plaques"
        default: rawUnit
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

    init(
        system: OpeningWorkSystem = .furringLining,
        hsp: Double = 0,
        spacing: Double = 0.60,
        doubledStuds: Bool = false,
        revealDepth: Double? = nil,
        ceilingLengthInStudDirection: Double? = nil
    ) {
        self.system = system
        self.hsp = hsp
        self.spacing = spacing
        self.doubledStuds = doubledStuds
        self.revealDepth = revealDepth
        self.ceilingLengthInStudDirection = ceilingLengthInStudDirection
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
}
