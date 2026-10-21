import XCTest
@testable import Plaquisto

final class PaintingTests: XCTestCase {
    // Contract fixture, not a production fallback: values published by Plaquisto Admin.
    private var rules: PaintingRules {
        .init(schemaVersion: 1, revision: "test", reservePercent: 10, airlessPercent: 5,
              yieldMin: 8, yieldMax: 12, yieldDefault: 10,
              compounds: [
                .init(id: "finition-poudre", name: "Finition · poudre", kgPerM2MM: 0.4, thicknessMin: 0.5, thicknessMax: 1.5, thicknessDefault: 1),
                .init(id: "charge-pate", name: "Charge · pâte", kgPerM2MM: 1.6, thicknessMin: 0.5, thicknessMax: 5, thicknessDefault: 2)
              ])
    }
    func testAirlessFivePercentThenTenPercentReserve() throws {
        var t = PaintingTreatment(rules: rules)
        t.independentTreatments = nil // Historical saved configurations retain their old calculation.
        t.airless = true
        let result = try PaintingCalculator.calculate(.init(area: 100, treatment: t))
        XCTAssertEqual(result[0].quantity, 11.55, accuracy: 1e-9)
        XCTAssertEqual(result[1].quantity, 23.1, accuracy: 1e-9)
        XCTAssertEqual(PaintingCalculator.displayedQuantity(result[1].quantity), 23.1)
        XCTAssertEqual(PaintingCalculator.displayedQuantity(11.55), 11.6)
        t.airless = false
        XCTAssertEqual(try PaintingCalculator.calculate(.init(area: 100, treatment: t))[1].quantity, 22, accuracy: 1e-9)
    }
    func testIndependentPassesPercentThicknessAndReserveWithoutPainting() throws {
        var t = PaintingTreatment(rules: rules)
        t.skimEnabled = true; t.paintEnabled = false; t.primerEnabled = false; t.airless = true
        t.passes = [.init(compoundID: "charge-pate", thicknessMM: 2, surfacePercent: 25),
                    .init(compoundID: "finition-poudre", thicknessMM: 1, surfacePercent: 100),
                    .init(compoundID: "finition-poudre", thicknessMM: 0.5, surfacePercent: 50)]
        let result = try PaintingCalculator.calculate(.init(area: 100, treatment: t))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].quantity, 88, accuracy: 1e-9)
        XCTAssertEqual(result[1].quantity, 55, accuracy: 1e-9)
    }
    func testNoPrimerTintAndThreeFinishCoats() throws {
        var t = PaintingTreatment(rules: rules)
        t.primerEnabled = false; t.finishCoats = 3
        t.finish = .init(name: "Velours", yieldM2PerL: 12, tint: "Terracotta")
        let result = try PaintingCalculator.calculate(.init(area: 120, treatment: t))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].quantity, 33, accuracy: 1e-9)
        XCTAssertTrue(result[0].name.contains("Terracotta"))
    }
    func testLegacyAreaAndSnapshotRoundTrip() throws {
        let legacy = try JSONDecoder().decode(PaintingBetaConfiguration.self, from: Data(#"{"area":42}"#.utf8))
        XCTAssertNil(legacy.treatment)
        XCTAssertEqual(try PaintingCalculator.calculate(legacy), [])
        let config = PaintingBetaConfiguration(area: 42, treatment: .init(rules: rules))
        XCTAssertEqual(try JSONDecoder().decode(PaintingBetaConfiguration.self, from: JSONEncoder().encode(config)), config)
    }
    func testInvalidRulesAndInputsRejected() throws {
        var bad = rules; bad.yieldMin = 0
        XCTAssertThrowsError(try bad.validate())
        bad = rules; bad.compounds[0].kgPerM2MM = .nan
        XCTAssertThrowsError(try bad.validate())
        var t = PaintingTreatment(rules: rules)
        XCTAssertThrowsError(try PaintingCalculator.calculate(.init(area: .infinity, treatment: t)))
        t.finish.yieldM2PerL = 0
        XCTAssertThrowsError(try PaintingCalculator.calculate(.init(area: 100, treatment: t)))
        t = .init(rules: rules); t.skimEnabled = true; t.passes[0].surfacePercent = 0
        XCTAssertThrowsError(try PaintingCalculator.calculate(.init(area: 100, treatment: t)))
        t.passes[0].surfacePercent = 101
        XCTAssertThrowsError(try PaintingCalculator.calculate(.init(area: 100, treatment: t)))
        t = .init(rules: rules); t.paintEnabled = false; t.primerEnabled = false
        XCTAssertThrowsError(try PaintingCalculator.calculate(.init(area: 100, treatment: t)))
    }
    @MainActor func testPersonalProductsPersistWithoutTintAndDeduplicate() throws {
        let suite = "PaintingTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PaintingProductStore(defaults: defaults)
        let product = PaintingProduct(name: " Peinture test ", yieldM2PerL: 9.5, tint: "Rouge")
        try store.save(product); try store.save(product)
        let loaded = PaintingProductStore(defaults: defaults)
        XCTAssertEqual(loaded.products.count, 1)
        XCTAssertEqual(loaded.products[0].name, "Peinture test")
        XCTAssertEqual(loaded.products[0].yieldM2PerL, 9.5)
    }
    @MainActor func testAdminEnvelopeAndOfflineCache() throws {
        let data = try JSONEncoder().encode(rules)
        let value = try JSONSerialization.jsonObject(with: data)
        let envelope = try JSONSerialization.data(withJSONObject: ["peintureRatissages": ["regles": ["data": value]]])
        XCTAssertEqual(try PaintingReferenceStore.decodeCatalogue(envelope), rules)
        XCTAssertThrowsError(try PaintingReferenceStore.decodeCatalogue(Data("{}".utf8)))
        let suite = "PaintingCacheTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(data, forKey: "plaquisto.painting.rules.v1")
        XCTAssertEqual(PaintingReferenceStore(defaults: defaults).rules, rules)
        var bad = rules; bad.yieldMin = 0
        defaults.set(try JSONEncoder().encode(bad), forKey: "plaquisto.painting.rules.v1")
        XCTAssertNil(PaintingReferenceStore(defaults: defaults).rules)
    }
    @MainActor func testSavedWorkQuantitiesAndTintSurviveReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Test peinture", client: "", address: "", notes: "")
        var t = PaintingTreatment(rules: rules)
        t.finish.tint = "Blanc"; t.airless = true
        let id = try store.createConfiguredWork(projectID: projectID, name: "Peinture", type: .paintingBeta,
            payload: .paintingBeta(.init(area: 100, treatment: t)), roomID: nil, newRoomName: nil)
        let work = try XCTUnwrap(ProjectStore(fileURL: url).project(id: projectID)?.works.first(where: { $0.id == id }))
        XCTAssertEqual(work.paintingBetaConfiguration?.treatment, t)
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let quantities = CombinedQuantityCalculator.calculate(works: [work, work], catalogue: catalogue)
        XCTAssertEqual(quantities.totalArea, 100)
        XCTAssertEqual(quantities.supplies.count, 2)
        XCTAssertEqual(try XCTUnwrap(quantities.supplies.first(where: { $0.name.contains("Blanc") })).quantity, 22, accuracy: 1e-9)
        var invalid = t; invalid.finish.yieldM2PerL = 0
        XCTAssertThrowsError(try store.updateWork(work, paintingBetaConfiguration: .init(area: 100, treatment: invalid)))
        XCTAssertEqual(store.project(id: projectID)?.works.first?.paintingBetaConfiguration?.treatment, t)
        var changed = work
        changed.layoutNeedsRecalculation = true
        changed.components = [.init(name: "Mur scanné", surface: .init(name: "Mur", kind: .wall,
            contour: [.init(x: 0,y: 0),.init(x: 4000,y: 0),.init(x: 4000,y: 2500),.init(x: 0,y: 2500)],
            openings: [.init(kind: .door, contour: [.init(x: 0,y: 0),.init(x: 1000,y: 0),.init(x: 1000,y: 2000),.init(x: 0,y: 2000)])]),
            surveySource: .init(surveyID: UUID(), checkpointID: UUID(), surfaceID: UUID(), boundaryIndex: 0, kind: .wall, capturedAt: Date()))]
        let refreshed = SurveyWorkGeometry.workForRecalculation(changed)
        XCTAssertEqual(try XCTUnwrap(refreshed.paintingBetaConfiguration?.area), 8, accuracy: 1e-9)
        XCTAssertEqual(refreshed.paintingBetaConfiguration?.treatment, t)
        XCTAssertEqual(try PaintingCalculator.calculate(XCTUnwrap(refreshed.paintingBetaConfiguration))[1].quantity, 1.76, accuracy: 1e-9)
    }
    func testPrimerOnlyAndRetiredAirlessInNewWorkflow() throws {
        var t = PaintingTreatment(rules: rules)
        t.paintEnabled = false; t.airless = true
        let result = try PaintingCalculator.calculate(.init(area:100,treatment:t))
        XCTAssertEqual(result.count,1)
        XCTAssertEqual(result[0].name,"Impression")
        XCTAssertEqual(result[0].quantity,11,accuracy:1e-9)
        t.primerEnabled=false
        XCTAssertThrowsError(try PaintingCalculator.calculate(.init(area:100,treatment:t)))
    }
    func testPassUnitsAndMoreThanThreeSequentialPasses() throws {
        var t = PaintingTreatment(rules:rules)
        t.paintEnabled=false; t.primerEnabled=false; t.skimEnabled=true
        t.rules.compounds.append(.init(id:"rebouchage-poudre",name:"Rebouchage · poudre",kgPerM2MM:1.15,thicknessMin:10,thicknessMax:50,thicknessDefault:10))
        t.passes = [.init(compoundID:"rebouchage-poudre",thicknessMM:10,surfacePercent:10),
                    .init(compoundID:"charge-pate",thicknessMM:1,surfacePercent:50),
                    .init(compoundID:"finition-poudre",thicknessMM:0.5),
                    .init(compoundID:"finition-poudre",thicknessMM:1)]
        let result=try PaintingCalculator.calculate(.init(area:100,treatment:t))
        XCTAssertEqual(result[0].quantity,126.5,accuracy:1e-9)
        XCTAssertEqual(result[1].quantity,88,accuracy:1e-9)
        XCTAssertEqual(result[2].quantity,66,accuracy:1e-9)
        t.passes[3].thicknessMM=1.5
        XCTAssertThrowsError(try PaintingCalculator.calculate(.init(area:100,treatment:t)))
    }
    func testInsulationLayersAndKnownLabelFormatsConsolidate() throws {
        let names = [
            "Isolation · 1re couche · Laine de verre, λ 0,032, 100 mm, R 3,13",
            "Isolation · 2e couche · Laine de verre, λ 0.032, 100 mm, R 3.12",
            "Isolation · Laine de verre, 100 mm, λ 0,032",
            "Laine de verre · λ 0,032 · 100 mm",
            "Isolation · Laine de verre · λ 0,032 · 100 mm",
            "Isolation · Laine de verre · 100 mm · λ 0,032"
        ]
        let rows = SupplyListingConsolidator.rows(names.map { .init(name: $0, quantity: 10, unit: "m²") })
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Isolation · Laine de verre · 100 mm · λ 0,032")
        XCTAssertEqual(rows.first?.measurements.first?.quantity, 60)
        let canonical = try XCTUnwrap(rows.first?.name)
        XCTAssertEqual(SupplyListingConsolidator.canonicalName(canonical), canonical)
        XCTAssertEqual(SupplyListingConsolidator.insulationName(reference: "Laine de verre · λ 0,032", thicknessMM: 100, lambda: 0.032), canonical)
    }

    func testInsulationConsolidationKeepsDifferentAndIncompleteReferencesSeparate() {
        let names = [
            "Isolation · Laine de verre · 100 mm · λ 0,032",
            "Isolation · Laine de verre · 120 mm · λ 0,032",
            "Isolation · Laine de verre · 100 mm · λ 0,035",
            "Isolation · Laine de roche · 100 mm · λ 0,032",
            "Isolation · Laine de verre revêtue kraft · 100 mm · λ 0,032",
            "Isolation · Marque A référence X · 100 mm · λ 0,032",
            "Isolation · Marque A référence Y · 100 mm · λ 0,032",
            "Isolation · Laine de verre · 100 mm · λ 0,0321",
            "Isolation · Laine de verre · 100 mm · λ 0,0322",
            "Isolation · Laine de verre · 100 mm · R 3,13"
        ]
        XCTAssertEqual(SupplyListingConsolidator.rows(names.map { .init(name: $0, quantity: 10, unit: "m²") }).count, names.count)
        for name in ["Isolation · Isolant, λ 0,032, 100 mm", "Isolation · 1re couche · Produit inconnu", "Isolation · Laine de verre · 100 mm · λ 0"] {
            XCTAssertEqual(SupplyListingConsolidator.canonicalName(name), name)
        }
    }

    func testLegacyAnchorAndEyeletSplitAndMergeWithSeparateComponents() {
        let entries: [SupplyListingEntry] = [
            .init(name: "Cheville et piton", quantity: 12, unit: "unité"),
            .init(name: "Cheville crampon 8 mm", quantity: 5, unit: "unités"),
            .init(name: "Piton de suspension 8 mm", quantity: 5, unit: "unités"),
            .init(name: "Cheville à bascule", quantity: 3, unit: "unité")
        ]
        let rows = SupplyListingConsolidator.rows(entries)
        XCTAssertEqual(rows.count, 3)
        for name in ["Cheville crampon 8 mm", "Piton de suspension 8 mm"] {
            XCTAssertEqual(rows.first(where: { $0.name == name })?.measurements.first?.quantity, 17)
        }
        XCTAssertEqual(rows.first(where: { $0.name == "Cheville à bascule" })?.measurements.first?.quantity, 3)
        let expanded = entries.flatMap(SupplyListingConsolidator.components)
        XCTAssertEqual(expanded.flatMap(SupplyListingConsolidator.components).count, expanded.count)
        XCTAssertEqual(SupplyListingConsolidator.components(.init(name: "Cheville et piton", quantity: 3, unit: "ml")).count, 1)
    }

    func testCanonicalNamesPreserveDistinctProducts() {
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Bande PP grand rouleau"),"Bande à joint")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Fourrures F45"),"Fourrures F45/F47")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Vis TTPC 25 ou 35"),"Vis TTPC 25")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Vis TTPC 25mm (1er parement)"),"Vis TTPC 25")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Vis TTPC 35"),"Vis TTPC 35")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Enduit en poudre"),"Enduit à joints en poudre")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Enduit en pâte"),"Enduit à joints en pâte")
    }
    func testFurringSupportAliasesSumAndSimplifiedOpeningsDoNotAddRevealSupports() throws {
        let old = "Appuis intermédiaires pour doublage sur fourrure"
        let names = [old, old + " — verticaux", old + " — horizontaux", old + " — embrasure",
                     "Appuis intermédiaires pour fourrures"]
        let rows = SupplyListingConsolidator.rows(names.enumerated().map {
            .init(name: $0.element, quantity: Double($0.offset + 1), unit: "unités")
        })
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Appuis intermédiaires pour fourrures")
        XCTAssertEqual(rows.first?.measurements.first?.quantity, 15)
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Appuis intermédiaires pour montants"), "Appuis intermédiaires pour montants")
        let result = OpeningQuantityCalculator.calculate(.init(kind: .window, width: 1.2, height: 1),
            context: .init(system: .furringLining, hsp: 2.5))
        let supports = result.quantities.filter { $0.name.hasPrefix("Appuis") }
        // Current wall-opening rule: only two full-height side profiles.
        // General lining supports are counted by the lining, not added again here.
        XCTAssertTrue(supports.isEmpty)
    }
    func testJointTapeAliasesConsolidateWithoutLosingQuantities() throws {
        let rows = SupplyListingConsolidator.rows([
            .init(name: "Bande PP grand rouleau", quantity: 15.8, unit: "ml"),
            .init(name: "Bande à joint", quantity: 28, unit: "ml")
        ])
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.name, "Bande à joint")
        XCTAssertEqual(row.measurements.count, 1)
        XCTAssertEqual(try XCTUnwrap(row.measurements.first).quantity, 43.8, accuracy: 1e-9)
    }
    func testTTPC35AliasesSumButDoNotMergeOtherLengths() throws {
        let rows = SupplyListingConsolidator.rows([
            .init(name: "Vis TTPC 35 mm (2e parement)", quantity: 100, unit: "unité"),
            .init(name: "Vis TTPC 35", quantity: 200, unit: "unités"),
            .init(name: "Vis TTPC 25", quantity: 50, unit: "unités"),
            .init(name: "Vis TTPC 45", quantity: 60, unit: "unités")
        ])
        XCTAssertEqual(rows.count, 3)
        let row = try XCTUnwrap(rows.first(where: { $0.name == "Vis TTPC 35" }))
        XCTAssertEqual(row.measurements.count, 1)
        XCTAssertEqual(try XCTUnwrap(row.measurements.first).quantity, 300)
    }
    func testTRPF13AliasesSumAllUsesWithoutMergingTRPF25() throws {
        let rows = SupplyListingConsolidator.rows([
            .init(name: "Vis TRPF 13", quantity: 10, unit: "unité"),
            .init(name: "Vis TRPF 13 · solidarisation des montants", quantity: 25, unit: "unités"),
            .init(name: "Vis TRPF 13 · fixation des suspentes", quantity: 40, unit: "unité"),
            .init(name: "Vis TRPF 25 · liaison rail/montant", quantity: 12, unit: "unité")
        ])
        XCTAssertEqual(rows.count, 2)
        let row = try XCTUnwrap(rows.first(where: { $0.name == "Vis TRPF 13" }))
        XCTAssertEqual(row.measurements.count, 1)
        XCTAssertEqual(try XCTUnwrap(row.measurements.first).quantity, 75)
        XCTAssertEqual(rows.last?.name, "Vis TRPF 25 · liaison rail/montant")
    }
    func testHalfClampSpellingAliasesSumWithoutMergingOtherFixings() throws {
        let rows = SupplyListingConsolidator.rows([
            .init(name: "Demi collier", quantity: 10, unit: "unité"),
            .init(name: "Demi-collier", quantity: 25, unit: "unités"),
            .init(name: "Cheville à bascule", quantity: 4, unit: "unité")
        ])
        XCTAssertEqual(rows.count, 2)
        let row = try XCTUnwrap(rows.first(where: { $0.name == "Demi-collier" }))
        XCTAssertEqual(row.measurements.count, 1)
        XCTAssertEqual(try XCTUnwrap(row.measurements.first).quantity, 35)
    }
    func testSimpleAndClawHourdisHangersMergeButClampingStaysDistinct() throws {
        let rows = SupplyListingConsolidator.rows([
            .init(name: "Suspente hourdis à griffe à serrer", quantity: 10, unit: "unité"),
            .init(name: "Suspente hourdis à serrer", quantity: 20, unit: "unités"),
            .init(name: "Suspente hourdis à griffe", quantity: 7, unit: "unité"),
            .init(name: "Suspente hourdis", quantity: 4, unit: "unité")
        ])
        XCTAssertEqual(rows.count, 2)
        for (name, expected) in [("Suspente hourdis à serrer", 30.0), ("Suspentes hourdis simples", 11.0)] {
            let row = try XCTUnwrap(rows.first(where: { $0.name == name }))
            XCTAssertEqual(try XCTUnwrap(row.measurements.first).quantity, expected)
        }
    }
    func testCeilingAndOpeningAnglesSumWithUnitsKeptSeparate() throws {
        let rows = SupplyListingConsolidator.rows([
            .init(name: "Cornière d’angle", quantity: 10, unit: "ml"),
            .init(name: "Cornière", quantity: 6, unit: "ml"),
            .init(name: "Cornières périphériques", quantity: 20, unit: "ml"),
            .init(name: "Cornières — longueur", quantity: 4, unit: "ml"),
            .init(name: "Cornières", quantity: 2, unit: "unité"),
            .init(name: "Cornières de rive · 3,00 m", quantity: 3, unit: "unités")
        ])
        XCTAssertEqual(rows.count, 2)
        let row = try XCTUnwrap(rows.first(where: { $0.name == "Cornière" }))
        XCTAssertEqual(row.measurements.count, 2)
        XCTAssertEqual(row.measurements.first(where: { $0.unit == "ml" })?.quantity, 40)
        XCTAssertEqual(row.measurements.first(where: { $0.unit == "unités" })?.quantity, 2)
        XCTAssertEqual(rows.last?.name, "Cornières de rive · 3,00 m")
    }
    func testOpeningFurringAliasesConsolidateAndKeepUnitsSeparate() throws {
        let rows = SupplyListingConsolidator.rows([
            .init(name: "Fourrures F45/F47", quantity: 20, unit: "ml"),
            .init(name: "Fourrures de renfort — longueur", quantity: 12.5, unit: "ml"),
            .init(name: "Fourrures transversales — longueur", quantity: 3, unit: "ml"),
            .init(name: "Fourrures de renfort", quantity: 5, unit: "unités"),
            .init(name: "Fourrures latérales d’embrasure", quantity: 2, unit: "unité"),
            .init(name: "Fourrures transversales d’embrasure", quantity: 4, unit: "unités"),
            .init(name: "Montants latéraux", quantity: 8, unit: "unités")
        ])
        XCTAssertEqual(rows.count, 2)
        let row = try XCTUnwrap(rows.first(where: { $0.name == "Fourrures F45/F47" }))
        XCTAssertEqual(row.measurements.first(where: { $0.unit == "ml" })?.quantity, 35.5)
        XCTAssertEqual(row.measurements.first(where: { $0.unit == "unités" })?.quantity, 11)
        XCTAssertEqual(rows.last?.name, "Montants latéraux")
    }
    func testSimplifiedWallOpeningsUseTwoFullHeightFurringsAndPreserveRoofRules() throws {
        let window = OpeningQuantityCalculator.calculate(.init(kind: .window, width: 1.2, height: 1),
            context: .init(system: .furringLining, hsp: 2.5))
        XCTAssertTrue(window.isComplete)
        let profiles = window.quantities.filter { $0.name == "Fourrures F45/F47" }
        XCTAssertEqual(profiles.count, 1)
        XCTAssertNil(profiles.first(where: { $0.unit == .unit }))
        XCTAssertEqual(profiles.first(where: { $0.unit == .linearMeter })?.quantity, 5)
        let roof = OpeningQuantityCalculator.calculate(.init(kind: .roofWindow, width: 1.2, height: 0.8),
            context: .init(system: .furringCeiling, spacing: 0.60))
        XCTAssertTrue(roof.isComplete)
        XCTAssertEqual(roof.quantities.first(where: { $0.name == "Fourrures F45/F47" && $0.unit == .linearMeter })?.quantity, 3)
        XCTAssertNil(roof.quantities.first(where: { $0.name == "Fourrures F45/F47" && $0.unit == .unit }), "The two pieces are already counted by their total length")
    }
    func testRailPluralAndFacingScrewAliasesPreserveDifferentProducts() {
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Rail R48"), "Rails R48")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Rails R70"), "Rails R70")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Rail pour cloison alvéolaire"), "Rail pour cloison alvéolaire")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Vis TTPC · parement"), "Vis TTPC 25")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Vis TTPC · première peau"), "Vis TTPC 25")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Vis TTPC · deuxième peau"), "Vis TTPC 35")
        XCTAssertEqual(SupplyListingConsolidator.canonicalName("Vis TTPC 45"), "Vis TTPC 45")
    }
    func testOpeningStudsUseLinearMetersAndTheExactWorkProfile() throws {
        let context = OpeningContext(system: .railStudLining, hsp: 2.5, frame: "R48 + M48/35")
        let result = OpeningQuantityCalculator.calculate(.init(kind: .window, width: 1.2, height: 1), context: context)
        let studs = result.quantities.filter { $0.name.hasPrefix("Montants") }
        XCTAssertEqual(studs.count, 1)
        XCTAssertEqual(studs.first?.name, "Montants M48/35")
        XCTAssertEqual(studs.first?.unit, .linearMeter)
        // Two full-height sides only; no lintel, sill or short reveal pieces.
        XCTAssertEqual(try XCTUnwrap(studs.first).quantity, 2 * 2.5, accuracy: 1e-9)
        XCTAssertEqual(context.railName, "Rails R48")
        XCTAssertEqual(OpeningContext.profileName(frame: "R48 + M48/50", rail: false), "Montants M48/50")
        XCTAssertEqual(OpeningContext().studName, "Montants — référence à préciser")
    }
    func testDoorAndRoofStudsHaveNoPieceCountAndWallDoorsUseSelectedProfile() throws {
        let context = OpeningContext(system: .distributionPartition, hsp: 2.5, frame: "R48 + M48/35")
        let door = OpeningQuantityCalculator.calculate(.init(kind: .interiorDoor, width: 0.9, height: 2), context: context)
        XCTAssertEqual(door.quantities.first(where: { $0.name == "Montants M48/35" })?.quantity, 5)
        XCTAssertNil(door.quantities.first(where: { $0.name == "Rails R48" }))
        XCTAssertFalse(door.quantities.contains(where: { $0.name.hasPrefix("Montants") && $0.unit == .unit }))
        let pocket = OpeningQuantityCalculator.calculate(.init(kind: .pocketDoor, width: 0.9, height: 2), context: context)
        XCTAssertEqual(pocket.quantities.first(where: { $0.name == "Montants M48/35" })?.quantity, 5)
        XCTAssertEqual(pocket.quantities.count,1)
        let roof = OpeningQuantityCalculator.calculate(.init(kind: .roofWindow, width: 1.2, height: 1),
            context: .init(system: .railStudCeiling, ceilingLengthInStudDirection: 3, frame: "R90 + M90"))
        XCTAssertEqual(roof.quantities.first(where: { $0.name == "Montants M90" })?.quantity, 6)
        XCTAssertFalse(roof.quantities.contains(where: { $0.name.hasPrefix("Montants") && $0.unit == .unit }))
    }
    func testOpeningFrameSnapshotIsOptionalForOldArchives() throws {
        let value = OpeningContext(system: .railStudLining, hsp: 2.5, frame: "R48 + M48/50")
        let saved = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(OpeningContext.self, from: saved), value)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        legacy.removeValue(forKey: "frame")
        let decoded = try JSONDecoder().decode(OpeningContext.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.frame)
        XCTAssertEqual(decoded.hsp, 2.5)
    }
    func testLiningDepthCompositionAndMeasuredOverride() throws {
        var f=FurringLiningConfiguration(); f.facingDepthMM=26; f.firstInsulation.thicknessMM=100
        XCTAssertEqual(LiningDepthEstimate.millimetres(.furringLining(f)),141)
        XCTAssertEqual(try XCTUnwrap(SurveyPlanFinishes.depth(.furringLining(f))),0.141,accuracy:1e-9)
        f.finishedDepthMM=160
        XCTAssertEqual(SurveyPlanFinishes.depth(.furringLining(f)),0.16)
        var s=DoublageConfiguration(); s.facingDepthMM=18; s.firstInsulation.thicknessMM=100
        s.insulationLayers=2; s.secondInsulation.thicknessMM=45
        XCTAssertEqual(LiningDepthEstimate.millimetres(.peripheralLining(s)),163)
        s.insulationEnabled=false
        XCTAssertEqual(LiningDepthEstimate.millimetres(.peripheralLining(s)),18)
    }
}
