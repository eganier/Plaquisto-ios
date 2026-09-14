import Foundation

enum OpeningQuantityCalculator {
    static func exceededSteps(value: Double, step: Double) -> Int {
        guard value > step, step > 0 else { return 0 }
        return max(0, Int(ceil((value - step) / step - 1e-9)))
    }

    static func calculate(_ opening: OpeningInput, context: OpeningContext) -> OpeningQuantityResult {
        guard opening.width > 0, opening.height > 0 else {
            return .init(opening: opening, quantities: [], insulationAreaDeduction: 0,
                         notes: ["Renseignez une largeur et une hauteur supérieures à zéro."], isComplete: false)
        }

        guard opening.kind.isImplemented else {
            return .init(opening: opening, quantities: [], insulationAreaDeduction: opening.area,
                         notes: ["Le type Niche est prévu, mais son quantitatif reste volontairement à définir."], isComplete: false)
        }

        guard context.system.availableOpeningKinds.contains(opening.kind) else {
            return .init(opening: opening, quantities: [], insulationAreaDeduction: opening.area,
                         notes: ["Cette ouverture n’est pas compatible avec le système d’ouvrage sélectionné."], isComplete: false)
        }

        var quantities: [OpeningQuantity] = []
        var notes: [String] = []
        let add: (String, Double, OpeningQuantity.Unit) -> Void = { name, quantity, unit in
            guard quantity > 0 else { return }
            quantities.append(.init(name: name, quantity: quantity, unit: unit))
        }

        switch opening.kind {
        case .window:
            guard context.hsp > 0, context.spacing > 0 else {
                return invalidContext(opening, "La HSP et l’entraxe doivent être renseignés.")
            }
            let positions = 4 + exceededSteps(value: opening.width, step: context.spacing)
            addProfilePositions(positions, context: context, add: add)

            if context.system == .furringLining {
                let verticalSupports = 4 + 2 * exceededSteps(value: opening.height, step: 0.40)
                let horizontalSupports = 4 + 2 * exceededSteps(value: opening.width, step: 0.60)
                add("Appuis intermédiaires pour doublage sur fourrure — verticaux", Double(verticalSupports), .unit)
                add("Appuis intermédiaires pour doublage sur fourrure — horizontaux", Double(horizontalSupports), .unit)
            }

            add("Cornière", 2 * opening.width, .linearMeter)
            addRevealQuantities(opening: opening, context: context, includesBottom: true, add: add)
            addRevealNote(opening: opening, context: context, notes: &notes)

        case .frenchDoorOrBay:
            guard context.hsp > 0 else { return invalidContext(opening, "La HSP doit être renseignée.") }
            let positions = 4 + exceededSteps(value: opening.width, step: 0.60)
            addProfilePositions(positions, context: context, add: add)

            if context.system == .furringLining {
                let supports = 4 + exceededSteps(value: opening.width, step: 0.60)
                add("Appuis intermédiaires pour doublage sur fourrure — horizontaux", Double(supports), .unit)
            }

            add("Cornière", opening.width, .linearMeter)
            addRevealQuantities(opening: opening, context: context, includesBottom: false, add: add)
            addRevealNote(opening: opening, context: context, notes: &notes)

        case .interiorDoor:
            guard context.hsp > 0 else { return invalidContext(opening, "La HSP doit être renseignée.") }
            let multiplier = context.doubledStuds ? 2 : 1
            add("Montants latéraux", Double(4 * multiplier), .unit)
            add("Montants latéraux — longueur", Double(4 * multiplier) * context.hsp, .linearMeter)
            add("Rail de linteau", opening.width, .linearMeter)
            add("Montants au-dessus", Double(4 * multiplier), .unit)
            add("Montants au-dessus — longueur", Double(4 * multiplier) * max(0, context.hsp - 2.00), .linearMeter)
            notes.append("Les montants au-dessus suivent la règle métier HSP − 2,00 m.")

        case .pocketDoor:
            guard context.hsp > 0 else { return invalidContext(opening, "La HSP doit être renseignée.") }
            add("Montants R70/M70 au-dessus", 4, .unit)
            add("Montants R70/M70 au-dessus — longueur", 4 * max(0, context.hsp - opening.height), .linearMeter)
            add("Montants latéraux R70/M70", 2, .unit)
            add("Montants latéraux R70/M70 — longueur", 2 * context.hsp, .linearMeter)
            add("Rail R70 supplémentaire", opening.width + 0.60, .linearMeter)
            notes.append("Configuration d’ossature imposée : R70 / M70.")

        case .roofWindow:
            if context.system == .furringCeiling {
                guard context.spacing == 0.40 || context.spacing == 0.60 else {
                    return invalidContext(opening, "L’entraxe du plafond en fourrures doit être de 40 ou 60 cm.")
                }
                let roundedHeight = ceil(opening.height / context.spacing - 1e-9) * context.spacing
                add("Cornières", 2, .unit)
                add("Cornières — longueur", 2 * (roundedHeight + 0.30), .linearMeter)
                add("Fourrures transversales", 2, .unit)
                add("Fourrures transversales — longueur", 2 * (opening.width + 0.30), .linearMeter)
            } else if context.system == .railStudCeiling {
                guard let length = context.ceilingLengthInStudDirection, length > 0 else {
                    return invalidContext(opening, "La longueur du plafond dans le sens des montants doit être renseignée.")
                }
                add("Montants supplémentaires", 2, .unit)
                add("Montants supplémentaires — longueur", 2 * length, .linearMeter)
                add("Rails supplémentaires", 2, .unit)
                add("Rails supplémentaires — longueur", 2 * (opening.width + 0.30), .linearMeter)
            }

        case .niche:
            break
        }

        return .init(
            opening: opening,
            quantities: merged(quantities),
            insulationAreaDeduction: opening.area,
            notes: notes,
            isComplete: true
        )
    }

    static func totals(_ results: [OpeningQuantityResult]) -> [OpeningQuantity] {
        let complete = results.filter(\.isComplete)
        return merged(complete.flatMap(\.quantities) + [
            .init(name: "Surface d’isolant à déduire", quantity: complete.reduce(0) { $0 + $1.insulationAreaDeduction }, unit: .squareMeter)
        ])
    }

    private static func addProfilePositions(
        _ positions: Int,
        context: OpeningContext,
        add: (String, Double, OpeningQuantity.Unit) -> Void
    ) {
        if context.system == .furringLining {
            add("Fourrures de renfort", Double(positions), .unit)
            add("Fourrures de renfort — longueur", Double(positions) * context.hsp, .linearMeter)
        } else {
            let multiplier = context.doubledStuds ? 2 : 1
            add("Montants de renfort", Double(positions * multiplier), .unit)
            add("Montants de renfort — longueur", Double(positions * multiplier) * context.hsp, .linearMeter)
        }
    }

    private static func addRevealQuantities(
        opening: OpeningInput,
        context: OpeningContext,
        includesBottom: Bool,
        add: (String, Double, OpeningQuantity.Unit) -> Void
    ) {
        let lateralProfile = context.system == .furringLining ? "Fourrures latérales" : "Montants latéraux"
        let transverseProfile = context.system == .furringLining ? "Fourrures transversales" : "Montants transversaux"
        add("\(lateralProfile) d’embrasure", 2, .unit)
        let exceeded = exceededSteps(value: opening.width, step: 0.60)
        let zones = includesBottom ? 2 : 1
        add("\(transverseProfile) d’embrasure", Double((1 + exceeded) * zones), .unit)

        if context.system == .furringLining {
            add("Appuis intermédiaires pour doublage sur fourrure — embrasure", Double(4 + exceeded), .unit)
        }
    }

    private static func addRevealNote(opening: OpeningInput, context: OpeningContext, notes: inout [String]) {
        if opening.mountingMode == .inReveal {
            notes.append("Contour traité en embrasure.")
        } else if let depth = opening.revealDepth ?? context.revealDepth, depth > 0 {
            notes.append("Profondeur de tapée : \((depth * 100).formatted(.number.precision(.fractionLength(0...1)))) cm.")
        } else {
            notes.append("La profondeur de tapée reste à compléter dans l’ouvrage.")
        }
    }

    private static func merged(_ quantities: [OpeningQuantity]) -> [OpeningQuantity] {
        var values: [String: OpeningQuantity] = [:]
        for quantity in quantities where quantity.quantity > 0 {
            let key = quantity.id
            if var existing = values[key] {
                existing.quantity += quantity.quantity
                values[key] = existing
            } else {
                values[key] = quantity
            }
        }
        return values.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func invalidContext(_ opening: OpeningInput, _ message: String) -> OpeningQuantityResult {
        .init(opening: opening, quantities: [], insulationAreaDeduction: opening.area,
              notes: [message], isComplete: false)
    }
}
