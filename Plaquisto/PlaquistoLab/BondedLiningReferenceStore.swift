import Foundation

enum BondedFacingFunction: String, CaseIterable, Identifiable, Hashable {
    case standard = "Standard"
    case hydro = "Hydrofuge"
    case vaporBarrier = "Pare-vapeur"
    var id: Self { self }
    var supplyName: String {
        switch self {
        case .standard: "Complexe de doublage standard"
        case .hydro: "Complexe de doublage hydrofuge"
        case .vaporBarrier: "Complexe de doublage pare-vapeur"
        }
    }
}

struct BondedComplexReference: Identifiable, Hashable {
    let facing: BondedFacingFunction
    let lambda: Double
    let insulationThicknessMM: Int
    let thermalResistance: Double
    let widthMM: Int
    let heightsMM: [Int]
    var id: String { "\(facing.id)-\(lambda)-\(insulationThicknessMM)-\(widthMM)" }
    var totalThicknessMM: Int { insulationThicknessMM + 13 }
    var revealDepthMM: Int { insulationThicknessMM + 20 }
}

struct BondedFacingAllocation: Identifiable, Hashable {
    let id: UUID
    var facing: BondedFacingFunction
    var surface: Double
    init(id: UUID = UUID(), facing: BondedFacingFunction = .standard, surface: Double = 0) {
        self.id = id; self.facing = facing; self.surface = surface
    }
}

struct BondedQuantityCoefficients {
    let complexM2PerM2 = 1.05
    let adhesiveKgPerM2 = 1.80
    let bandMLPerM2 = 1.40
    let powderKgPerM2 = 0.33
}

@MainActor
final class BondedLiningReferenceStore: ObservableObject {
    let references: [BondedComplexReference]
    let quantities = BondedQuantityCoefficients()

    init() {
        let standardHeights = [2500, 2600, 2700, 2800, 3000]
        var values: [BondedComplexReference] = []
        func add(_ facing: BondedFacingFunction, lambda: Double, thickness: Int, resistance: Double, width: Int = 1200, heights: [Int] = standardHeights) {
            values.append(.init(facing: facing, lambda: lambda, insulationThicknessMM: thickness, thermalResistance: resistance, widthMM: width, heightsMM: heights))
        }
        for item in [(20, 0.65), (40, 1.30), (60, 1.90), (80, 2.55), (100, 3.15), (120, 3.80), (140, 4.40), (160, 5.05), (180, 5.65)] {
            add(.standard, lambda: 0.032, thickness: item.0, resistance: item.1)
        }
        for item in [(40, 1.30), (60, 1.90), (80, 2.55)] {
            add(.standard, lambda: 0.032, thickness: item.0, resistance: item.1, width: 600, heights: [2500])
        }
        for item in [(80, 2.75), (100, 3.40), (120, 4.10), (140, 4.75), (160, 5.35), (180, 6.05)] {
            add(.standard, lambda: 0.030, thickness: item.0, resistance: item.1)
        }
        add(.hydro, lambda: 0.030, thickness: 80, resistance: 2.75)
        add(.hydro, lambda: 0.032, thickness: 100, resistance: 3.15)
        add(.hydro, lambda: 0.030, thickness: 100, resistance: 3.40)
        add(.hydro, lambda: 0.032, thickness: 120, resistance: 3.80)
        add(.vaporBarrier, lambda: 0.032, thickness: 100, resistance: 3.15, heights: [2500, 2600, 2700])
        references = values
    }

    func commonLambdas(for facings: Set<BondedFacingFunction>) -> [Double] {
        commonValues(for: facings) { $0.lambda }.sorted()
    }
    func commonThicknesses(for facings: Set<BondedFacingFunction>, lambda: Double) -> [Int] {
        commonValues(for: facings) { abs($0.lambda - lambda) < 0.0001 ? $0.insulationThicknessMM : nil }.sorted()
    }
    func commonWidths(for facings: Set<BondedFacingFunction>, lambda: Double, thickness: Int) -> [Int] {
        commonValues(for: facings) { abs($0.lambda - lambda) < 0.0001 && $0.insulationThicknessMM == thickness ? $0.widthMM : nil }.sorted()
    }
    func commonHeights(for facings: Set<BondedFacingFunction>, lambda: Double, thickness: Int, width: Int) -> [Int] {
        let selected = facings.isEmpty ? Set([BondedFacingFunction.standard]) : facings
        let sets = selected.map { facing in
            Set(references.filter { $0.facing == facing && abs($0.lambda - lambda) < 0.0001 && $0.insulationThicknessMM == thickness && $0.widthMM == width }.flatMap(\.heightsMM))
        }
        guard let first = sets.first else { return [] }
        return sets.dropFirst().reduce(first) { $0.intersection($1) }.sorted()
    }
    func resistance(lambda: Double, thickness: Int) -> Double? {
        references.first { abs($0.lambda - lambda) < 0.0001 && $0.insulationThicknessMM == thickness }?.thermalResistance
    }
    private func commonValues<T: Hashable>(for facings: Set<BondedFacingFunction>, transform: (BondedComplexReference) -> T?) -> Set<T> {
        let selected = facings.isEmpty ? Set([BondedFacingFunction.standard]) : facings
        let sets = selected.map { facing in Set(references.filter { $0.facing == facing }.compactMap(transform)) }
        guard let first = sets.first else { return [] }
        return sets.dropFirst().reduce(first) { $0.intersection($1) }
    }
}
