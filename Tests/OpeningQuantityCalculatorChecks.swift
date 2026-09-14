import Foundation

@main
enum OpeningQuantityCalculatorChecks {
    static func main() throws {
        try thresholdChecks()
        try windowChecks()
        try bayChecks()
        try partitionDoorChecks()
        try roofWindowChecks()
        try scopeChecks()
        try requiredContextChecks()
        try modelDefaultsChecks()
        try supplyListingChecks()
        print("PASS: seuils stricts, fenêtre, baie, porte, galandage, fenêtre de toit, niche, totaux et regroupement des fournitures")
    }

    private static func thresholdChecks() throws {
        try expect(OpeningQuantityCalculator.exceededSteps(value: 0.60, step: 0.60) == 0, "60 cm ne dépasse pas le seuil")
        try expect(OpeningQuantityCalculator.exceededSteps(value: 0.61, step: 0.60) == 1, "61 cm dépasse le seuil")
        try expect(OpeningQuantityCalculator.exceededSteps(value: 1.20, step: 0.60) == 1, "120 cm ne dépasse pas le second seuil")
        try expect(OpeningQuantityCalculator.exceededSteps(value: 1.21, step: 0.60) == 2, "121 cm dépasse le second seuil")
    }

    private static func windowChecks() throws {
        let base = OpeningQuantityCalculator.calculate(
            .init(kind: .window, width: 0.60, height: 0.40),
            context: .init(system: .furringLining, hsp: 2.50, spacing: 0.60)
        )
        try expect(base.isComplete, "fenêtre lisses/fourrures calculée")
        try expect(approximately(quantity("Fourrures de renfort", in: base), 4), "4 fourrures")
        try expect(approximately(quantity("Fourrures de renfort — longueur", in: base), 10), "4 fourrures pleine HSP")
        try expect(approximately(quantity("Appuis intermédiaires pour doublage sur fourrure — verticaux", in: base), 4), "4 appuis verticaux à 40 cm")
        try expect(approximately(quantity("Appuis intermédiaires pour doublage sur fourrure — horizontaux", in: base), 4), "4 appuis horizontaux à 60 cm")
        try expect(approximately(quantity("Cornière", in: base), 1.20), "cornière haut et bas")

        let exceeded = OpeningQuantityCalculator.calculate(
            .init(kind: .window, width: 1.21, height: 0.81),
            context: .init(system: .railStudLining, hsp: 2.50, spacing: 0.60, doubledStuds: true)
        )
        try expect(approximately(quantity("Montants de renfort", in: exceeded), 12), "6 positions doublées")
        try expect(approximately(quantity("Montants de renfort — longueur", in: exceeded), 30), "6 positions doublées de 2,50 m")
        try expect(quantity("Appuis intermédiaires pour doublage sur fourrure — horizontaux", in: exceeded) == nil, "aucun appui en rails/montants")
    }

    private static func bayChecks() throws {
        let result = OpeningQuantityCalculator.calculate(
            .init(kind: .frenchDoorOrBay, width: 1.20, height: 2.15),
            context: .init(system: .furringLining, hsp: 2.50, spacing: 0.40)
        )
        try expect(approximately(quantity("Fourrures de renfort", in: result), 5), "5 positions à 120 cm")
        try expect(approximately(quantity("Fourrures de renfort — longueur", in: result), 12.50), "5 positions pleine HSP")
        try expect(approximately(quantity("Appuis intermédiaires pour doublage sur fourrure — horizontaux", in: result), 5), "5 appuis de baie")
        try expect(approximately(quantity("Cornière", in: result), 1.20), "cornière supérieure uniquement")
    }

    private static func partitionDoorChecks() throws {
        let context = OpeningContext(system: .distributionPartition, hsp: 2.50)
        let door = OpeningQuantityCalculator.calculate(.init(kind: .interiorDoor, width: 0.83, height: 2.04), context: context)
        try expect(approximately(quantity("Montants latéraux", in: door), 4), "4 montants latéraux")
        try expect(approximately(quantity("Montants latéraux — longueur", in: door), 10), "4 montants pleine hauteur")
        try expect(approximately(quantity("Rail de linteau", in: door), 0.83), "rail sans supplément")
        try expect(approximately(quantity("Montants au-dessus — longueur", in: door), 2), "4 fois HSP moins 2 m")

        let pocket = OpeningQuantityCalculator.calculate(.init(kind: .pocketDoor, width: 0.83, height: 2.04), context: context)
        try expect(approximately(quantity("Montants R70/M70 au-dessus", in: pocket), 4), "4 montants courts du galandage")
        try expect(approximately(quantity("Montants R70/M70 au-dessus — longueur", in: pocket), 1.84), "longueur des 4 montants courts")
        try expect(approximately(quantity("Montants latéraux R70/M70", in: pocket), 2), "2 montants latéraux")
        try expect(approximately(quantity("Montants latéraux R70/M70 — longueur", in: pocket), 5), "longueur des montants latéraux")
        try expect(approximately(quantity("Rail R70 supplémentaire", in: pocket), 1.43), "largeur plus 60 cm")
    }

    private static func roofWindowChecks() throws {
        let opening = OpeningInput(kind: .roofWindow, width: 0.78, height: 1.30)
        let furring = OpeningQuantityCalculator.calculate(opening, context: .init(system: .furringCeiling, hsp: 0, spacing: 0.40))
        try expect(approximately(quantity("Cornières — longueur", in: furring), 3.80), "arrondi à 1,60 plus 30 cm, deux fois")
        try expect(approximately(quantity("Fourrures transversales — longueur", in: furring), 2.16), "largeur plus 30 cm, deux fois")

        let studs = OpeningQuantityCalculator.calculate(
            opening,
            context: .init(system: .railStudCeiling, hsp: 0, spacing: 0.60, ceilingLengthInStudDirection: 4.20)
        )
        try expect(approximately(quantity("Montants supplémentaires — longueur", in: studs), 8.40), "2 montants pleine longueur")
        try expect(approximately(quantity("Rails supplémentaires — longueur", in: studs), 2.16), "2 rails transversaux")
    }

    private static func scopeChecks() throws {
        let niche = OpeningQuantityCalculator.calculate(
            .init(kind: .niche, width: 0.60, height: 0.40),
            context: .init(system: .furringLining, hsp: 2.50)
        )
        try expect(!niche.isComplete && niche.quantities.isEmpty, "niche volontairement non finalisée")

        let first = OpeningQuantityCalculator.calculate(
            .init(kind: .window, width: 0.60, height: 0.40),
            context: .init(system: .furringLining, hsp: 2.50)
        )
        let second = OpeningQuantityCalculator.calculate(
            .init(kind: .window, width: 0.60, height: 0.40),
            context: .init(system: .furringLining, hsp: 2.50)
        )
        let totals = OpeningQuantityCalculator.totals([first, second])
        try expect(approximately(totals.first(where: { $0.name == "Fourrures de renfort" })?.quantity, 8), "les ouvertures sont additionnées après calcul séparé")
        try expect(approximately(totals.first(where: { $0.name == "Fourrures de renfort — longueur" })?.quantity, 20), "les longueurs sont additionnées")
        try expect(approximately(totals.first(where: { $0.name == "Surface d’isolant à déduire" })?.quantity, 0.48), "isolant déduit, plaques non concernées")
    }

    private static func requiredContextChecks() throws {
        let missingHSP = OpeningQuantityCalculator.calculate(
            .init(kind: .window, width: 1.20, height: 1.05),
            context: .init(system: .furringLining)
        )
        try expect(!missingHSP.isComplete, "la HSP est obligatoire pour une ouverture murale")

        let missingCeilingLength = OpeningQuantityCalculator.calculate(
            .init(kind: .roofWindow, width: 0.78, height: 1.18),
            context: .init(system: .railStudCeiling)
        )
        try expect(!missingCeilingLength.isComplete, "la longueur des montants est obligatoire pour un plafond rails/montants")
    }

    private static func modelDefaultsChecks() throws {
        let defaultOpening = OpeningInput(kind: .window, width: 0.60, height: 0.40)
        try expect(defaultOpening.mountingMode == .onJoineryLining, "le contour sur tapée est sélectionné par défaut")
        try expect(OpeningKind.window.title(in: .distributionPartition) == "Verrière", "une fenêtre de cloison est présentée comme une verrière")
        try expect(!OpeningWorkSystem.distributionPartition.availableOpeningKinds.contains(.frenchDoorOrBay), "les baies ne sont pas proposées en cloison de distribution")
    }

    private static func supplyListingChecks() throws {
        let result = OpeningQuantityCalculator.calculate(
            .init(kind: .window, width: 0.60, height: 0.40),
            context: .init(system: .furringLining, hsp: 2.50, spacing: 0.60)
        )
        let rows = SupplyListingConsolidator.rows(result.quantities.map {
            .init(name: $0.name, quantity: $0.quantity, unit: $0.unit.rawValue)
        })

        let supports = rows.first { $0.name == "Appuis intermédiaires pour doublage sur fourrure" }
        try expect(supports?.measurements.count == 1, "les appuis verticaux, horizontaux et d’embrasure tiennent sur une ligne")
        try expect(approximately(supports?.measurements.first?.quantity, 12), "les appuis regroupés conservent le total")

        let furrings = rows.first { $0.name == "Fourrures de renfort" }
        try expect(furrings?.measurements.count == 2, "le nombre et la longueur des fourrures tiennent sur une ligne")
        try expect(furrings?.value == "4 unités · 10 ml", "le contrôle chantier conserve unités et longueur")

        let facings = SupplyListingConsolidator.rows([
            .init(name: "Première peau · BA13 standard · 1 200 × 2 500 mm", quantity: 4, unit: "plaque(s)"),
            .init(name: "Deuxième peau · BA13 standard · 1 200 × 2 500 mm", quantity: 4, unit: "plaque(s)"),
        ])
        try expect(facings.count == 1 && facings[0].measurements[0].quantity == 8, "un même parement est regroupé quelle que soit sa peau")
    }

    private static func quantity(_ name: String, in result: OpeningQuantityResult) -> Double? {
        result.quantities.first(where: { $0.name == name })?.quantity
    }

    private static func approximately(_ actual: Double?, _ expected: Double, tolerance: Double = 0.000_001) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) <= tolerance
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }

    private struct CheckFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { "ÉCHEC : \(message)" }
    }
}
