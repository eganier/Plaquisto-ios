import XCTest
import SwiftUI
@testable import Plaquisto

final class PartitionRegressionTests: XCTestCase {
    func testInsulationDefaultTracksFrameWidthInsteadOfFirstThinRoll() {
        let wool = CloisonInsulation(id:"wool",title:"Laine de verre phonique",lambda:0.04,thicknessesMM:[30,45,60,70,85],maxOverFrameMM:10)
        XCTAssertEqual(wool.preferredThickness(frameWidthMM:45),45)
        XCTAssertEqual(wool.preferredThickness(frameWidthMM:48),45)
        XCTAssertEqual(wool.preferredThickness(frameWidthMM:70),70)
        XCTAssertEqual(wool.preferredThickness(frameWidthMM:90),85)
        let rigid = CloisonInsulation(id:"wood",title:"Laine de bois",lambda:0.036,thicknessesMM:[40,50,60,80,100],maxOverFrameMM:0)
        XCTAssertEqual(rigid.preferredThickness(frameWidthMM:48),40)
        XCTAssertEqual(rigid.preferredThickness(frameWidthMM:70),60)
        XCTAssertEqual(rigid.preferredThickness(frameWidthMM:20),0)
    }
    func testReal279SquareMeterPartitionRepairsBothSixSquareMeterFacesOnlyOnce() throws {
        var c=CloisonDistributionConfiguration()
        c.enteredLength=9.3; c.height=3
        c.faceAFirst=[.init(facingID:"FACING-BA13-STANDARD",formatID:"1200x3000",surface:6)]
        c.faceBFirst=c.faceAFirst
        c.quantities=[.init(name:"Parement · BA13 Standard · 1200 × 3000 mm",quantity:12.6,unit:"m²"),
            .init(name:"Rails R48",quantity:23.44,unit:"ml")]
        let repaired=c.repairingStaleFacingAreas()
        XCTAssertEqual(repaired.faceAFirst[0].surface,27.9,accuracy:1e-8)
        XCTAssertEqual(repaired.faceBFirst[0].surface,27.9,accuracy:1e-8)
        XCTAssertEqual(repaired.quantities[0].quantity,58.59,accuracy:1e-8)
        XCTAssertEqual(repaired.quantities[1].quantity,23.44)
        XCTAssertEqual(repaired.repairingStaleFacingAreas(),repaired)
        XCTAssertEqual(try JSONDecoder().decode(CloisonDistributionConfiguration.self,from:JSONEncoder().encode(repaired)),repaired)
    }
    func testPartitionAndLiningBoardNamesConsolidateWithoutMixingVariants() {
        let rows=SupplyListingConsolidator.rows([
            .init(name:"Parement · BA13 Standard · 1200 × 3000 mm",quantity:58.59,unit:"m²"),
            .init(name:"BA13 · 1200 × 3000 mm",quantity:10,unit:"m²"),
            .init(name:"BA13 · 1200 × 2600 mm",quantity:5,unit:"m²"),
            .init(name:"Parement · BA13 Hydrofuge H1 · 1200 × 3000 mm",quantity:7,unit:"m²")])
        XCTAssertEqual(rows.count,3)
        XCTAssertEqual(rows.first?.name,"BA13 · 1200 × 3000 mm")
        XCTAssertEqual(rows.first?.measurements.first?.quantity ?? 0,68.59,accuracy:1e-8)
    }
    func testGeometryChangeResizesEachFaceAndPreservesMixedShares() {
        let mixed:[CloisonFacingSelection]=[.init(facingID:"standard",surface:4),.init(facingID:"hydro",surface:2)]
        let resized=PartitionFacingArea.resized(mixed,area:27.9)
        XCTAssertEqual(resized[0].surface,18.6,accuracy:1e-8)
        XCTAssertEqual(resized[1].surface,9.3,accuracy:1e-8)
        XCTAssertEqual(resized.map(\.facingID),mixed.map(\.facingID))
    }
    func testWallOpeningsCountOnlyTwoFullHeightProfiles() {
        for system in [OpeningWorkSystem.furringLining,.railStudLining,.distributionPartition] {
            let context=OpeningContext(system:system,hsp:3,spacing:0.6,doubledStuds:true,frame:"R48 + M48/35")
            let opening=OpeningInput(kind:.window,width:1,height:1)
            let result=OpeningQuantityCalculator.calculate(opening,context:context)
            XCTAssertTrue(result.isComplete)
            XCTAssertEqual(result.quantities.count,1)
            XCTAssertEqual(result.quantities.first?.quantity,6)
        }
    }
}

final class FurringIntermediateSupportTests: XCTestCase {
    private let ranges: [(String, Int, Int, Bool)] = [
        ("15-45",0,60,true),("75",60,85,false),("100",85,100,false),
        ("120",100,120,false),("140",120,140,false),("75-160",75,160,true),("200",140,200,false)]
    private var records: [DoublageReferenceRecord] {
        ranges.map { model, min, max, direct in
            .init(id: "QTY-APPUI-FOURRURE-\(model)", title: "Appuis intermédiaires pour fourrures \(model)", summary: "",
                  data: ["category": .string("intermediate_support"), "unit": .string("unité"), "model": .string(model),
                         "insulation_min_mm": .number(Double(min)), "insulation_max_mm": .number(Double(max)),
                         "direct_masonry": .bool(direct)])
        }
    }
    private var models: [FurringIntermediateSupport] { records.compactMap(FurringIntermediateSupport.init(record:)) }
    func testEveryInsulationThicknessAndSharedBoundary() {
        for mm in 0...201 {
            let expected: String? = mm < 60 || mm > 200 ? nil : mm < 85 ? "75" : mm < 100 ? "100" : mm < 120 ? "120" : mm < 140 ? "140" : "200"
            let value = FurringIntermediateSupportSelection.select(thicknessMM: mm, directMasonry: false, models: models)
            XCTAssertEqual(value?.id, expected.map { "QTY-APPUI-FOURRURE-\($0)" }, "\(mm) mm")
            let direct: String? = mm <= 60 ? "15-45" : (75...160).contains(mm) ? "75-160" : nil
            XCTAssertEqual(FurringIntermediateSupportSelection.select(thicknessMM: mm, directMasonry: true, models: models)?.id,
                           direct.map { "QTY-APPUI-FOURRURE-\($0)" }, "direct \(mm) mm")
        }
        XCTAssertNil(FurringIntermediateSupportSelection.select(thicknessMM: -1, directMasonry: false, models: models))
        XCTAssertNil(FurringIntermediateSupportSelection.select(thicknessMM: 120, directMasonry: false, models: []))
    }
    func testInvalidOrAmbiguousRulesNeverGuess() {
        let record = records[2]
        for patch: [String: DoublageJSONValue] in [["insulation_min_mm": .number(.nan)], ["insulation_max_mm": .number(85)],
                ["insulation_min_mm": .number(85.5)], ["model": .string("")], ["direct_masonry": .string("oui")]] {
            var data = record.data; data.merge(patch) { _, new in new }
            XCTAssertNil(FurringIntermediateSupport(record: .init(id: record.id, title: record.title, summary: "", data: data)))
        }
        XCTAssertNil(FurringIntermediateSupportSelection.select(thicknessMM: 90, directMasonry: false, models: models + [models[2]]))
        var data = record.data; data["insulation_max_mm"] = .number(110)
        let overlap = FurringIntermediateSupport(record: .init(id: "OTHER", title: "Other", summary: "", data: data))!
        XCTAssertNil(FurringIntermediateSupportSelection.select(thicknessMM: 105, directMasonry: false, models: models + [overlap]))
    }
    func testPersistenceDefaultAndQuantitiesKeepModelIdentity() throws {
        let initial = FurringLiningConfiguration()
        XCTAssertTrue(initial.includesHorizontalSupportFurring ?? true)
        var value = initial
        value.includesHorizontalSupportFurring = false
        value.intermediateSupportReferenceID = "QTY-APPUI-FOURRURE-75-160"
        value.intermediateSupportTitle = "Appuis intermédiaires pour fourrures 75-160"
        value.finishedDepthMM = 900 // No effect on support identity.
        value.quantities = [.init(name: value.supportSupplyName, quantity: 12, unit: "unité")]
        let decoded = try JSONDecoder().decode(FurringLiningConfiguration.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.supportSupplyName, value.intermediateSupportTitle)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        legacy.removeValue(forKey: "intermediateSupportReferenceID"); legacy.removeValue(forKey: "intermediateSupportTitle")
        legacy.removeValue(forKey: "includesHorizontalSupportFurring")
        let old = try JSONDecoder().decode(FurringLiningConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.intermediateSupportReferenceID)
        XCTAssertTrue(old.includesHorizontalSupportFurring ?? true)
        XCTAssertEqual(FurringLiningCalculator.horizontalSupportFurringLength(wallLength: 8, supportLines: 2, wasteFactor: 1.05, isIncluded: false), 0)
        XCTAssertEqual(FurringLiningCalculator.horizontalSupportFurringLength(wallLength: 8, supportLines: 2, wasteFactor: 1.05, isIncluded: true), 16.8, accuracy: 0.001)
        let supplies = SupplyListingConsolidator.rows([
            .init(name: "Appuis intermédiaires pour fourrures 120", quantity: 3, unit: "unité"),
            .init(name: "Appuis intermédiaires pour fourrures 140", quantity: 4, unit: "unité")])
        XCTAssertEqual(supplies.count, 2)
    }
}

final class CompositeHangerSelectionTests: XCTestCase {
    private let ranges: [(String, Int, Int)] = [("fermette",20,80),("12-16",81,160),("16-20",161,200),("20-24",201,240),("24-28",241,280)]
    private var records: [CeilingReferenceRecord] {
        ranges.map { model, min, max in
            .init(id: "QTY-SUSPENTE-COMPOSITE-\(model.uppercased())", kind: "quantity_item",
                  title: "Suspente composite pour pare-vapeur \(model)", summary: "", sourcePage: 0, status: "Publié",
                  data: ["category": .string("composite_hanger"), "model": .string(model), "unit": .string("unité"),
                         "support": .string("Plancher bois horizontal"), "plenum_min_mm": .number(Double(min)), "plenum_max_mm": .number(Double(max))])
        }
    }
    private func catalogue(_ items: [CeilingReferenceRecord]) -> CeilingCataloguePayload {
        .init(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: items, pareVapeur: nil, regles: [])
    }
    func testEveryIntegerMillimeterSelectsTheExpectedModel() {
        for (model,min,max) in ranges {
            for mm in min...max {
                XCTAssertEqual(CompositeHangerSelection.reference(plenumCM: Double(mm)/10, support: "Plancher bois horizontal",
                    catalogue: catalogue(records))?.data["model"]?.string, model, "\(mm) mm")
            }
        }
    }
    func testInvalidOrAmbiguousSelectionDoesNotGuessAModel() {
        for cm in [1.9,28.1,8.05,Double.nan,Double.infinity] {
            XCTAssertNil(CompositeHangerSelection.reference(plenumCM: cm, support: "Plancher bois horizontal", catalogue: catalogue(records)))
        }
        XCTAssertNil(CompositeHangerSelection.reference(plenumCM: 8, support: "Plancher hourdis béton", catalogue: catalogue(records)))
        XCTAssertNil(CompositeHangerSelection.reference(plenumCM: 8, support: "Plancher bois horizontal", catalogue: catalogue(records + [records[0]])))
        XCTAssertNil(CompositeHangerSelection.reference(plenumCM: 8, support: "Plancher bois horizontal", catalogue: catalogue([])))
    }
    func testQuantitiesKeepScrewsAndTheSelectedModelForPricing() {
        let system = CeilingReferenceRecord(id: "FIX-BOIS-PARE-VAPEUR", kind: "fixing_system", title: "Composite", summary: "", sourcePage: 0,
            status: "Publié", data: ["support": .string("Plancher bois horizontal"), "pare_vapeur_compatible": .bool(true), "components": .array([
                .object(["name": .string("Vis TTPC 35"), "quantity": .number(2), "unit": .string("unité")]),
                .object(["name": .string("Suspente composite pour pare-vapeur"), "selection": .string("composite_hanger"), "quantity": .number(1), "unit": .string("unité")])])])
        for (model,min,_) in ranges {
            let values = CeilingHangerComponents.resolve(for: system, plenumCM: Double(min)/10, catalogue: catalogue(records))
            XCTAssertEqual(values[0].object?["name"]?.string, "Vis TTPC 35")
            XCTAssertEqual(values[0].object?["quantity"]?.number, 2)
            XCTAssertEqual(values[1].object?["quantity"]?.number, 1)
            XCTAssertEqual(values[1].object?["name"]?.string, "Suspente composite pour pare-vapeur \(model)")
            XCTAssertEqual(values[1].object?["reference_id"]?.string, "QTY-SUSPENTE-COMPOSITE-\(model.uppercased())")
        }
        let unresolved = CeilingHangerComponents.resolve(for: system, plenumCM: 29, catalogue: catalogue(records))
        XCTAssertNil(unresolved[1].object?["reference_id"])
        XCTAssertTrue(unresolved[1].object?["name"]?.string?.contains("modèle à préciser") == true)
    }
}

final class GalvanizedHangerSelectionTests: XCTestCase {
    private var records: [CeilingReferenceRecord] {
        let lengths = [80, 180, 240, 300, 400, 500, 600]
        let wood = [(20,60),(61,150),(151,210),(211,270),(271,370),(371,470),(471,570)]
        let hourdis = [(20,70),(71,170),(171,230),(231,290),(291,390),(391,490),(491,590)]
        return lengths.indices.map { i in
            CeilingReferenceRecord(id: "QTY-SUSPENTE-GALVA-\(lengths[i])", kind: "quantity_item",
                title: "Suspentes acier galvanisées \(lengths[i]) mm", summary: "", sourcePage: 0, status: "Publié",
                data: ["category": .string("galvanized_hanger"), "unit": .string("unité"),
                       "length_mm": .number(Double(lengths[i])),
                       "plenum_min_mm": .number(Double(wood[i].0)), "plenum_max_mm": .number(Double(wood[i].1)),
                       "hourdis_plenum_min_mm": .number(Double(hourdis[i].0)), "hourdis_plenum_max_mm": .number(Double(hourdis[i].1))])
        }
    }

    private func catalogue(_ items: [CeilingReferenceRecord]) -> CeilingCataloguePayload {
        .init(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [],
              quantitatifs: items, pareVapeur: nil, regles: [])
    }

    func testEveryIntegerMillimeterUsesItsSupportSpecificRange() {
        for (support, prefix, upper) in [("Plancher bois horizontal", "", 570), ("Plancher hourdis béton", "hourdis_", 590)] {
            for mm in 20...upper {
                let expected = records.first { Double(mm) >= $0.data["\(prefix)plenum_min_mm"]!.number! && Double(mm) <= $0.data["\(prefix)plenum_max_mm"]!.number! }
                XCTAssertEqual(GalvanizedHangerSelection.reference(plenumCM: Double(mm)/10, support: support,
                               catalogue: catalogue(records))?.id, expected?.id, "\(support), \(mm) mm")
            }
            XCTAssertNil(GalvanizedHangerSelection.reference(plenumCM: 1.9, support: support, catalogue: catalogue(records)))
            XCTAssertNil(GalvanizedHangerSelection.reference(plenumCM: Double(upper+1)/10, support: support, catalogue: catalogue(records)))
        }
    }

    func testFractionalMillimetersAndAmbiguousCataloguesAreNotGuessed() {
        for cm in [6.05, Double.nan, Double.infinity, -1] {
            XCTAssertNil(GalvanizedHangerSelection.wholeMillimeters(plenumCM: cm))
        }
        XCTAssertEqual(GalvanizedHangerSelection.wholeMillimeters(plenumCM: 6.1), 61)
        XCTAssertNil(GalvanizedHangerSelection.reference(plenumCM: 6, support: "Plancher bois horizontal",
                     catalogue: catalogue(records + [records[0]])))
        XCTAssertNil(GalvanizedHangerSelection.reference(plenumCM: 6, support: "Dalle béton", catalogue: catalogue(records)))
    }

    func testComponentsKeepAccessoriesAndQuantitiesButUseTheSelectedSupply() {
        for support in ["Plancher bois horizontal", "Plancher hourdis béton"] {
            let system = CeilingReferenceRecord(id: "fix", kind: "fixing_system", title: "test", summary: "", sourcePage: 0,
                status: "Publié", data: ["support": .string(support), "components": .array([
                    .object(["name": .string("Suspente acier galvanisé"), "selection": .string("galvanized_hanger"), "quantity": .number(1)]),
                    .object(["name": .string("Accessoire conservé"), "quantity": .number(2)])])])
            let result = GalvanizedHangerSelection.components(for: system, plenumCM: 7, catalogue: catalogue(records))
            let length = support == "Plancher bois horizontal" ? 180 : 80
            XCTAssertEqual(result[0].object?["reference_id"]?.string, "QTY-SUSPENTE-GALVA-\(length)")
            XCTAssertEqual(result[0].object?["quantity"]?.number, 1)
            XCTAssertEqual(result[1].object?["name"]?.string, "Accessoire conservé")
            XCTAssertEqual(result[1].object?["quantity"]?.number, 2)
        }
    }

    func testFirstInsulationDefaultsTo60OnlyWhenThePublishedSeriesAllowsIt() {
        XCTAssertEqual(CeilingInsulationDefaults.firstThickness(available: [45,60,80,100], betweenWood: true), 60)
        XCTAssertEqual(CeilingInsulationDefaults.firstThickness(available: [45,80], betweenWood: true), 45)
        XCTAssertEqual(CeilingInsulationDefaults.firstThickness(available: [45,60,80], betweenWood: false), 45)
    }

    func testFixingDefaultsPreferGalvanizedOrCompositeWithoutInventingCompatibility() {
        func system(_ id: String) -> CeilingReferenceRecord {
            .init(id: id, kind: "fixing_system", title: id, summary: "", sourcePage: 0, status: "Publié", data: [:])
        }
        let wood = [system("FIX-BOIS-TIGE"), system("FIX-BOIS-PARE-VAPEUR"), system("FIX-BOIS-GALVA")]
        XCTAssertEqual(CeilingFixingDefaults.preferred(in: wood, vaporBarrier: false)?.id, "FIX-BOIS-GALVA")
        XCTAssertEqual(CeilingFixingDefaults.preferred(in: wood, vaporBarrier: true)?.id, "FIX-BOIS-PARE-VAPEUR")
        let hourdis = [system("FIX-HOURDIS-SEUL"), system("FIX-HOURDIS-GRIFFE-GALVA"), system("FIX-HOURDIS-GALVA")]
        XCTAssertEqual(CeilingFixingDefaults.preferred(in: hourdis, vaporBarrier: false)?.id, "FIX-HOURDIS-GALVA")
        XCTAssertEqual(CeilingFixingDefaults.preferred(in: hourdis, vaporBarrier: true)?.id, "FIX-HOURDIS-GALVA")
        XCTAssertEqual(CeilingFixingDefaults.preferred(in: [wood[0]], vaporBarrier: true)?.id, "FIX-BOIS-TIGE")
        XCTAssertNil(CeilingFixingDefaults.preferred(in: [], vaporBarrier: true))
    }
}

@MainActor
final class WoodCeilingPlenumDiagramTests: XCTestCase {
    func testDiagramRendersAtPhoneWidthsWithCurrentValue() throws {
        for width in [280.0, 340.0, 400.0] {
            let renderer = ImageRenderer(content: WoodCeilingPlenumDiagram(plenumCM: 12)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(width: width)
                .background(Color.white))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, width * 230 / 360, accuracy: 0.5)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Plénum — \(Int(width)) points"
            attachment.lifetime = .keepAlways
            add(attachment)
            if width == 340 {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("plaquisto-plenum-preview.png")
                try XCTUnwrap(image.pngData()).write(to: url)
                print("PLENUM_PREVIEW: \(url.path)")
            }
        }
    }

    func testDiagramUpdatesTheDisplayedPlenum() throws {
        func rendered(_ value: Double) throws -> Data {
            let renderer = ImageRenderer(content: WoodCeilingPlenumDiagram(plenumCM: value)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(width: 340)
                .background(Color.white))
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }
        XCTAssertNotEqual(try rendered(12), try rendered(24.5))
    }
}

@MainActor
final class ProjectStoreTests: XCTestCase {
    func testFrenchCeilingBetaIsListedWithoutInventingAConfiguration() throws {
        let type = WorkType.frenchCeiling
        XCTAssertTrue(WorkType.allCases.contains(type))
        XCTAssertEqual(type.category,.ceilings)
        XCTAssertEqual(type.title,"Plafond à la française (bêta)")
        XCTAssertEqual(type.generatedName(roomName:"Salon"),"Salon - Plafond à la française")
        XCTAssertTrue(WorkConfigurationShortcut.choices(for:type).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(WorkType.self,from:JSONEncoder().encode(type)),type)
    }

    func testFrenchCeilingBetaCannotSaveAnotherCeilingCalculator() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store = ProjectStore(fileURL:url)
        let id = try store.createProject(name:"Plafond français",client:"",address:"",notes:"")
        let before = try Data(contentsOf:url)
        XCTAssertThrowsError(try store.createConfiguredWork(projectID:id,name:"Salon",type:.frenchCeiling,
            payload:.ceiling(.init()),roomID:nil,newRoomName:nil))
        XCTAssertThrowsError(try store.createWork(projectID:id,name:"Salon",type:.frenchCeiling,configuration:.init()))
        XCTAssertTrue(try XCTUnwrap(store.project(id:id)).works.isEmpty)
        XCTAssertEqual(try Data(contentsOf:url),before)
    }

    func testModularCeilingFromScanIsSavedAndTracksCeilingChanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        var document = scanDocument(name: "Atelier")
        let source = document.room.walls[0].provenance
        let ring: [RoomPoint] = [.init(x: 0, y: 0, z: 0), .init(x: 4, y: 0, z: 0), .init(x: 4, y: 0, z: 3), .init(x: 0, y: 0, z: 3)]
        document.room.walls = ring.indices.map { i in
            let a = ring[i], b = ring[(i + 1) % ring.count]
            return .init(start: a, end: b, length: .init(rawValue: (b-a).length, provenance: source), height: .init(rawValue: 2.5, provenance: source), provenance: source)
        }
        document = try WallCeilingEstimate.addingIfMissing(to: document)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Modulaire", surveyID: nil, surveyName: "Scan", roomID: nil, roomName: "Atelier", document: document)
        let survey = try XCTUnwrap(store.surveys.first)
        let selected = SurveyWorkGeometry.surfaces(in: survey).filter { $0.source.kind == .ceiling }
        XCTAssertTrue(SurveyWorkGeometry.availableWorkTypes(for: selected).contains(.modularCeiling))
        XCTAssertTrue(SurveyWorkGeometry.availableWorkTypes(for: selected).contains(.frenchCeiling))
        XCTAssertFalse(SurveyWorkGeometry.availableWorkTypes(for:SurveyWorkGeometry.surfaces(in:survey).filter { $0.source.kind == .wall }).contains(.frenchCeiling))
        XCTAssertThrowsError(try store.createSurveyWork(surveyID:survey.id,selections:selected,name:"Français",
            type:.frenchCeiling,payload:.ceiling(.init()),roomID:nil))
        var configuration = SurveyWorkGeometry.modularCeiling(selected)
        configuration.plenumCM = 20
        XCTAssertEqual(configuration.area, 12, accuracy: 0.001)
        let id = try store.createSurveyWork(surveyID: survey.id, selections: selected, name: "Dalles", type: .modularCeiling, payload: .modularCeiling(configuration), roomID: nil)
        let work = try XCTUnwrap(ProjectStore(fileURL: url).project(id: saved.projectID)?.works.first { $0.id == id })
        XCTAssertEqual(work.modularCeilingConfiguration, configuration)
        XCTAssertEqual(work.components.count, selected.count)
        XCTAssertNotNil(work.automaticLayout)
        XCTAssertTrue(work.components.allSatisfy { !$0.plans.isEmpty })
        XCTAssertEqual(work.components.first?.plans.first?.layers.first?.sheetWidth, 600)
        XCTAssertNil(work.components.first?.plans.first?.layers.first?.furring)
        var altered = work
        altered.components[0].surface?.openings = [.init(kind: .stairwell, contour: LayoutBounds(min: .init(x: 1000, y: 1000), max: .init(x: 2000, y: 2000)).polygon)]
        altered.layoutNeedsRecalculation = true
        let refreshed = SurveyWorkGeometry.workForRecalculation(altered)
        XCTAssertEqual(refreshed.modularCeilingConfiguration?.surveyedSurfaces, altered.components.compactMap(\.surface))
        XCTAssertEqual(refreshed.modularCeilingConfiguration?.plenumCM, 20)
    }

    func testModularCeilingScanClipsConcaveContourAndHoleWithoutYawInflation() throws {
        let contour: [LayoutPoint] = [.init(x: 0, y: 0), .init(x: 6000, y: 0), .init(x: 6000, y: 2400), .init(x: 3600, y: 2400), .init(x: 3600, y: 3600), .init(x: 0, y: 3600)]
        let hole = LayoutBounds(min: .init(x: 1200, y: 600), max: .init(x: 1800, y: 1200)).polygon
        var baseline: ModularCeilingQuantities?
        for yaw in [0.0, 0.19, -0.47] {
            let surface = Surface2D(name: "Atelier", kind: .ceiling, contour: contour.map { LayoutOpeningFrame.rotate($0, by: yaw) },
                openings: [.init(kind: .stairwell, contour: hole.map { LayoutOpeningFrame.rotate($0, by: yaw) })])
            var c = ModularCeilingConfiguration(length: 6, width: 3.6)
            c.surveyedSurfaces = [surface]
            let q = try ModularCeilingCalculator.scanned(c, surfaces: [surface])
            XCTAssertEqual(q.area, 18.36, accuracy: 0.001)
            XCTAssertEqual(c.area, q.area, accuracy: 0.001)
            XCTAssertEqual(q.installedTiles, 51)
            XCTAssertEqual(q.fullTiles, 51)
            if let baseline {
                XCTAssertEqual(q.mainRunnerLength, baseline.mainRunnerLength, accuracy: 0.001)
                XCTAssertEqual(q.hangers, baseline.hangers)
                XCTAssertEqual(q.orderedTiles, baseline.orderedTiles)
                XCTAssertEqual(q.perimeter, baseline.perimeter, accuracy: 0.001)
            } else { baseline = q }
        }
    }
    func testFacingPurchasingDisplayUsesAreaAndDoesNotChangeInternalCounts() throws {
        let board = SupplyListingEntry(name: "BA13 · 1200 × 2400 mm", quantity: 20, unit: "plaque(s)")
        let rows = SupplyListingConsolidator.rows([board,
            .init(name: board.name, quantity: 2.4, unit: "m²"),
            .init(name: "BA13 · 1200 × 2600 mm", quantity: 10.78, unit: "m²")])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].measurements.count, 1)
        XCTAssertEqual(rows[0].measurements[0].unit, "m²")
        XCTAssertEqual(rows[0].measurements[0].quantity, 60, accuracy: 0.00001)
        XCTAssertEqual(rows[1].measurements[0].quantity, 10.78)
        XCTAssertEqual(board.quantity, 20)
        XCTAssertEqual(SupplyListingConsolidator.displayedMeasurement(.init(name: "BA13 · 120 × 260 cm", quantity: 2, unit: "plaques")).quantity, 6.24, accuracy: 0.00001)
        XCTAssertEqual(SupplyListingConsolidator.displayedMeasurement(.init(name: "Format inconnu", quantity: 2, unit: "plaques")).unit, "plaques")
        XCTAssertEqual(SupplyListingConsolidator.displayedMeasurement(.init(name: "Vis 25 mm", quantity: 100, unit: "unités")).quantity, 100)
    }

    func testAttachedOpeningInsulationIsDeductedOnlyFromParentAndEachLayer() throws {
        let project = UUID(), now = Date()
        var config = DoublageConfiguration(height: 2.5, enteredLength: 8)
        config.quantities = [.init(name: "Isolation · Laine 100 mm", quantity: 22, unit: "m²"),
                             .init(name: "Isolation · Laine 60 mm", quantity: 22, unit: "m²"),
                             .init(name: "Rails", quantity: 16, unit: "ml")]
        var source = WorkItem(id: UUID(), projectID: project, name: "Doublage", type: .peripheralLiningStuds,
                             doublageConfiguration: config, createdAt: now, updatedAt: now)
        let other = WorkItem(id: UUID(), projectID: project, name: "Autre", type: .peripheralLiningStuds,
                            doublageConfiguration: config, createdAt: now, updatedAt: now)
        let input = OpeningInput(kind: .window, width: 2, height: 1)
        let openingConfig = OpeningConfiguration(context: .init(system: .railStudLining, hsp: 2.5), openings: [input], sourceWorkID: source.id)
        let opening = WorkItem(id: UUID(), projectID: project, name: "Fenêtre", type: .openings,
                              openingConfiguration: openingConfig, createdAt: now, updatedAt: now)
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let all = [source, other, opening]
        let result = CombinedQuantityCalculator.calculate(works: [source, other, opening, opening], catalogue: catalogue, projectWorks: all)
        for name in ["Isolation · Laine 100 mm", "Isolation · Laine 60 mm"] {
            XCTAssertEqual(try XCTUnwrap(result.supplies.first { $0.name == name }).quantity, 41.8, accuracy: 0.00001)
        }
        XCTAssertFalse(result.supplies.contains { $0.name.contains("déduire") })
        let only = CombinedQuantityCalculator.calculate(works: [source], catalogue: catalogue, projectWorks: all)
        XCTAssertEqual(try XCTUnwrap(only.supplies.first { $0.name == "Isolation · Laine 100 mm" }).quantity, 19.8, accuracy: 0.00001)
        XCTAssertEqual(WorkOpeningRelations.insulationRemainingRatio(for: source, allWorks: [other]), 1)
        // Automatic minimum quantities must not reapply the subtraction recursively.
        source.automaticLayout = .init(configurationFingerprint: LayoutQuantityCalculator.configurationFingerprint(source), minimumSupplies: [], warnings: [])
        let automatic = CombinedQuantityCalculator.calculate(works: [source], catalogue: catalogue, projectWorks: [source, opening])
        XCTAssertEqual(try XCTUnwrap(automatic.supplies.first { $0.name == "Isolation · Laine 100 mm" }).quantity, 19.8, accuracy: 0.00001)
        // A scanned/layout opening already included in net area is not deducted twice.
        var surface = Surface2D(name: "Mur", kind: .wall, contour: [.init(x:0,y:0),.init(x:8000,y:0),.init(x:8000,y:2500),.init(x:0,y:2500)])
        surface.openings = [.init(id: input.id, kind: .window, contour: [.init(x:0,y:0),.init(x:2000,y:0),.init(x:2000,y:1000),.init(x:0,y:1000)])]
        source.components = [.init(name: "Mur", surface: surface)]
        XCTAssertEqual(WorkOpeningRelations.insulationRemainingRatio(for: source, allWorks: [opening]), 1)
        XCTAssertEqual(WorkOpeningRelations.summary(for: source, allWorks: [opening, opening]).count, 1)
        XCTAssertTrue(WorkOpeningRelations.summary(for: source, allWorks: [opening])[0].contains("200 × 100 cm"))
        XCTAssertFalse(OpeningQuantityCalculator.totals([OpeningQuantityCalculator.calculate(input, context: openingConfig.context)]).contains { $0.name.contains("déduire") })
    }

    func testConfigurationShortcutsCoverOnlyEditableSteps() {
        let expected: [(WorkType, ClosedRange<Int>)] = [
            (.ceilingOnFurring, 0...6), (.ceilingOnRailsAndStuds, 0...7),
            (.peripheralLiningStuds, 1...5), (.peripheralLiningFurrings, 1...5),
            (.distributionPartition, 1...6), (.alveolarPartition, 1...3),
            (.peripheralLiningBonded, 1...5), (.peripheralLiningAdhesiveFacing, 1...4),
            (.modularCeiling, 0...2)
        ]
        for (type, range) in expected {
            let shortcuts = WorkConfigurationShortcut.choices(for: type)
            XCTAssertEqual(shortcuts.map(\.step), Array(range), type.title)
            XCTAssertEqual(Set(shortcuts.map(\.id)).count, shortcuts.count)
            XCTAssertTrue(shortcuts.allSatisfy { !$0.title.isEmpty })
        }
        for type in [WorkType.paintingBeta, .jointTreatment, .openings] {
            XCTAssertTrue(WorkConfigurationShortcut.choices(for: type).isEmpty)
        }
        XCTAssertEqual(WorkConfigurationShortcut.choices(for: .ceilingOnFurring)[2].title, "Isolation et pare-vapeur")
        XCTAssertEqual(WorkConfigurationShortcut.choices(for: .peripheralLiningFurrings)[3].step, 4)
    }

    func testConfigurationEntryIsOptionalAndRejectsInvalidSteps() async throws {
        for entry: Int? in [nil, -1, 2, 7] {
            var entries: [Int] = []
            let controller = UIHostingController(rootView:
                Text("Formulaire")
                    .configurationEntry(in: 0...6) { entries.append($0) }
                    .environment(\.configurationEntryStep, entry)
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(entries, entry == 2 ? [2] : [])
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testConfigurationEntryDoesNotResetStepWhenReturningToForm() async throws {
        var entries: [Int] = []
        let controller = UIHostingController(rootView:
            Text("Formulaire")
                .configurationEntry(in: 1...5) { entries.append($0) }
                .environment(\.configurationEntryStep, 4)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(entries, [4])
        window.isHidden = true
        window.rootViewController = nil
    }

    func testSavingCeilingPlanAutomaticallyUpdatesPartialQuantitiesAndReloads() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store=ProjectStore(fileURL:url)
        let project=try store.createProject(name:"Quantités automatiques",client:"",address:"",notes:"")
        let id=try store.createWork(projectID:project,name:"Plafond",type:.ceilingOnFurring,configuration:.init(length:8,width:3))
        _ = try store.addComponent(projectID:project,workID:id,name:"Salon")
        _ = try store.addComponent(projectID:project,workID:id,name:"Cuisine non calepinée")
        let component=try XCTUnwrap(store.project(id:project)?.works.first?.components.first)
        var document=LayoutDocument.newSupport(.init(name:"Salon",kind:.ceiling,
            contour:LayoutPreset.rectangle.contour(length:4000,height:3000,secondaryHeight:0)))
        document.layers[0].furring = .init(spacing:600,offset:0,orientation:.horizontal)
        try store.saveComponentPlan(projectID:project,workID:id,componentID:component.id,sideRoomID:nil,document:document)
        var work=try XCTUnwrap(store.project(id:project)?.works.first)
        let initial=try XCTUnwrap(LayoutQuantityCalculator.validated(work))
        XCTAssertEqual(initial.framingCoverage,0.5,accuracy:0.00001)
        XCTAssertEqual(initial.boardCoverage(0),0.5,accuracy:0.00001)
        document.layers[0].furring?.spacing=400
        try store.saveComponentPlan(projectID:project,workID:id,componentID:component.id,sideRoomID:nil,document:document)
        work=try XCTUnwrap(ProjectStore(fileURL:url).project(id:project)?.works.first)
        let updated=try XCTUnwrap(LayoutQuantityCalculator.validated(work))
        XCTAssertGreaterThan(updated.framingMeters,initial.framingMeters)
        XCTAssertEqual(updated.framingCoverage,0.5,accuracy:0.00001)
        XCTAssertEqual(updated,try LayoutQuantityCalculator.make(work:work,formats:[]))
        XCTAssertNil(work.components[1].surface)

        // Simulate a pre-migration archive waiting for the former confirmation.
        var archive=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        var projects=try XCTUnwrap(archive["projects"] as? [[String:Any]])
        var works=try XCTUnwrap(projects[0]["works"] as? [[String:Any]])
        var stale=try XCTUnwrap(works[0]["layoutQuantityTakeoff"] as? [String:Any])
        stale["fingerprint"]="ancienne version"; stale["framingMeters"]=9999.0
        works[0]["layoutQuantityTakeoff"]=stale; projects[0]["works"]=works; archive["projects"]=projects
        try JSONSerialization.data(withJSONObject:archive).write(to:url)
        let migrated=try XCTUnwrap(ProjectStore(fileURL:url).project(id:project)?.works.first)
        XCTAssertEqual(LayoutQuantityCalculator.validated(migrated),updated)
        XCTAssertEqual(ProjectStore(fileURL:url).project(id:project)?.works.first?.layoutQuantityTakeoff,updated)
    }

    /// Exercise the actual form path: preparation happens before the store
    /// rebuilds its authoritative scan surfaces, not inside createSurveyWork.
    private func preparedSurveyLayout(_ selections: [SurveyWorkSurface], type: WorkType,
                                      payload: WorkConfiguration) throws -> AutomaticSurveyLayout.Prepared {
        let now = Date()
        var work = WorkItem(id: UUID(), projectID: UUID(), name: "Préparation", type: type,
                            payload: payload, createdAt: now, updatedAt: now)
        work.components = selections.map { selection in
            var component = WorkComponentRecord(name: selection.surface.name, surface: selection.surface)
            component.surveySource = selection.source
            component.referenceSideRoomID = selection.roomID
            return component
        }
        return try AutomaticSurveyLayout.prepare(work, formats: [], catalogue: nil)
    }

    func testExternallyPreparedFurringLiningPreservesPreciseWallsAndOpenings() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var document = scanDocument(name: "Salon")
        let provenance = document.room.walls[0].provenance
        func measure(_ value: Double) -> RoomMeasurement { .init(rawValue: value, provenance: provenance) }
        document.room.walls = [
            .init(start: .zero, end: .init(x: 4.318762, y: 0, z: 0),
                  length: measure(4.318762), height: measure(2.537842), provenance: provenance),
            .init(start: .init(x: 4.318762, y: 0, z: 0), end: .init(x: 4.318762, y: 0, z: 4.721125),
                  length: measure(4.721125), height: measure(2.603912), provenance: provenance),
            .init(start: .init(x: 4.318762, y: 0, z: 4.721125), end: .init(x: 0.297599, y: 0, z: 4.721125),
                  length: measure(4.021163), height: measure(2.472194), provenance: provenance)
        ]
        document = try SurveyPlanEditing.addingDoor(document, wallID: document.room.walls[0].id,
            width: 0.831724, height: 2.041873, position: 1.127341)
        // Overlapping cutouts must be deducted as a union, including after
        // preparing layouts outside the store as the actual save button does.
        let windowWallID = document.room.walls[1].id
        for position in [0.923456, 1.423456] {
            let opening = PlaquistoOpening(wallID: windowWallID, kind: .window, center: .zero,
                width: measure(1.127345), height: measure(0.987654), sillHeight: measure(1.012345),
                positionOnWall: measure(position), provenance: provenance)
            document.room.openings.append(opening)
            document.room.walls[1].openingIDs.append(opening.id)
        }
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Fourrures précises", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let survey = try XCTUnwrap(store.surveys.first)
        let selected = SurveyWorkGeometry.surfaces(in: survey)
        XCTAssertEqual(selected.count, 3)
        var configuration = SurveyWorkGeometry.furring(selected)
        configuration.firstSkin = [.init(facingID: "ba13", formatID: "1200x2600", surface: configuration.area)]
        let payload = WorkConfiguration.furringLining(configuration)
        let prepared = try preparedSurveyLayout(selected, type: .peripheralLiningFurrings, payload: payload)
        XCTAssertEqual(prepared.sourceSurfaces, SurveyWorkGeometry.surfaces(in: survey).map(\.surface))
        XCTAssertEqual(prepared.components.map { $0.plans.count }, [1, 1, 1])
        let id = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Doublage sur lisses et fourrures", type: .peripheralLiningFurrings,
            payload: payload, roomID: nil, automatic: prepared)
        let restoredStore = ProjectStore(fileURL: fileURL)
        XCTAssertNil(restoredStore.lastError)
        let restored = try XCTUnwrap(restoredStore.project(id: saved.projectID)?.works.first { $0.id == id })
        XCTAssertEqual(restored.payload, payload)
        XCTAssertEqual(restored.components.compactMap(\.surface), selected.map(\.surface))
        XCTAssertEqual(restored.components.map(\.plans), prepared.components.map(\.plans))
        XCTAssertEqual(restored.components.map { $0.surface?.openings.count }, [1, 2, 0])
        XCTAssertEqual(restored.area, SurveyWorkGeometry.totalArea(selected), accuracy: 0.0000001)
        XCTAssertEqual(restored.furringLiningConfiguration?.measuredWallRuns, configuration.measuredWallRuns)
        XCTAssertEqual(configuration.measuredWallRuns?[1].openingArea ?? 0,
                       (1.127345 + 0.5) * 0.987654, accuracy: 0.000001)
    }

    func testExternallyPreparedFurringLiningRejectsRoundedOrChangedMeasurements() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var document = scanDocument(name: "Salon")
        try document.room.walls[0].length.correct(4.318762)
        try document.room.walls[0].height.correct(2.537842)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Contrôles", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let selected = SurveyWorkGeometry.surfaces(in: try XCTUnwrap(store.surveys.first))
        let original = SurveyWorkGeometry.furring(selected)
        for mutation in 0..<4 {
            var configuration = original
            switch mutation {
            case 0: configuration.enteredSurface = (configuration.enteredSurface * 100).rounded() / 100
            case 1: configuration.measuredWallRuns = nil
            case 2: configuration.measuredWallRuns?[0].length += 0.01
            default: configuration.wallCount = 2
            }
            let payload = WorkConfiguration.furringLining(configuration)
            let prepared = try preparedSurveyLayout(selected, type: .peripheralLiningFurrings, payload: payload)
            XCTAssertThrowsError(try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
                name: "Mesures modifiées", type: .peripheralLiningFurrings,
                payload: payload, roomID: nil, automatic: prepared)) {
                guard case SurveyWorkError.changedDimensions = $0 else { return XCTFail("Unexpected error: \($0)") }
            }
            XCTAssertTrue(store.project(id: saved.projectID)!.works.isEmpty)
        }
    }

    func testExternallyPreparedPartitionSavesWithAndWithoutDoor() throws {
        for withDoor in [false, true] {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let store = ProjectStore(fileURL: fileURL)
            var document = try SurveyPlanEditing.addingPartition(scanDocument(name: "Salon"),
                start: .init(x: 0, y: 0, z: 1), end: .init(x: 3, y: 0, z: 1), height: 2.5)
            let wallID = try XCTUnwrap(document.wallWorkIntents?.first(where: { $0.use == .partition })?.wallID)
            if withDoor {
                document = try SurveyPlanEditing.addingDoor(document, wallID: wallID,
                    width: 0.83, height: 2.04, position: 1,handing:.left,openingSide:.negative)
            }
            let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Test", surveyID: nil,
                surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
            let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0]).filter(SurveyWorkGeometry.isDesignedPartition)
            XCTAssertEqual(selected.map(\.surface), SurveyWorkGeometry.surfaces(in: store.surveys[0])
                .filter(SurveyWorkGeometry.isDesignedPartition).map(\.surface))
            var configuration = SurveyWorkGeometry.partition(selected)
            configuration.faceAFirst = [.init(facingID: "ba13", formatID: "1200x2400", surface: configuration.area)]
            configuration.faceBFirst = configuration.faceAFirst
            let payload = WorkConfiguration.distributionPartition(configuration)
            let prepared = try preparedSurveyLayout(selected, type: .distributionPartition, payload: payload)
            let id = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
                name: "Cloison", type: .distributionPartition, payload: payload, roomID: nil, automatic: prepared)
            let work = try XCTUnwrap(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.first { $0.id == id })
            XCTAssertEqual(work.components.count, 1)
            XCTAssertEqual(work.components[0].surface, selected[0].surface)
            XCTAssertEqual(work.components[0].surface?.openings.count, withDoor ? 1 : 0)
            XCTAssertEqual(work.components[0].plans.count, 2)
            XCTAssertEqual(work.area, 7.5 - (withDoor ? 0.83 * 2.04 : 0), accuracy: 0.000001)
            XCTAssertEqual(work.components[0].plans, prepared.components[0].plans)
            XCTAssertEqual(WorkOpeningRelations.planOpenings(for:work).count,withDoor ? 1 : 0)
            XCTAssertEqual(WorkOpeningRelations.insulationRemainingRatio(for:work,allWorks:[work]),1)
            XCTAssertEqual(configuration.faceAFirst[0].surface+configuration.faceBFirst[0].surface,work.area*2,accuracy:1e-8)
            if withDoor {
                let door=try XCTUnwrap(work.components[0].surface?.openings.first)
                XCTAssertEqual(door.doorHanding,.left)
                XCTAssertEqual(door.doorOpeningSide,.negative)
                XCTAssertEqual(door.bounds.width,830,accuracy:1e-8)
                XCTAssertEqual(door.bounds.height,2040,accuracy:1e-8)
                XCTAssertEqual(door.bounds.min.x,1000,accuracy:1e-8)
                XCTAssertTrue(WorkOpeningRelations.summary(for:work,allWorks:[work])[0].contains("Poussant gauche"))
                let checkpoint=try XCTUnwrap(store.surveys[0].checkpoints.first)
                let flipped=try SurveyPlanEditing.movingDoor(checkpoint.document,id:door.id,position:1,openingSide:.positive)
                try store.updateSurveyRoom(surveyID:saved.surveyID,checkpointID:checkpoint.id,expectedDocument:checkpoint.document,document:flipped)
                let updated=try XCTUnwrap(ProjectStore(fileURL:fileURL).project(id:saved.projectID)?.works.first { $0.id==id })
                XCTAssertEqual(updated.components[0].surface?.openings.first?.doorOpeningSide,.positive)
                XCTAssertEqual(updated.area,work.area,accuracy:1e-8)
                XCTAssertEqual(WorkOpeningRelations.planOpenings(for:updated).count,1)
            }
        }
    }

    func testExternallyPreparedCeilingRetainsDistinctBoundariesAndHoleIdentities() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var document = scanDocument(name: "Salon")
        func rectangle(_ x: Double, _ z: Double, _ w: Double, _ d: Double) -> [RoomPoint] {
            [(x,z), (x+w,z), (x+w,z+d), (x,z+d)].map { .init(x: $0.0, y: 3, z: $0.1) }
        }
        document.room.slopes = [.init(plane: .init(a: 0, b: 0, c: 3),
            boundaries: [rectangle(0,0,4,3), rectangle(1,1,1,1), rectangle(5,0,2,2)],
            provenance: document.room.walls[0].provenance, accepted: true)]
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Test", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0]).filter { $0.source.kind == .ceiling }
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(Set(selected.map { $0.surface.id }).count, 2)
        XCTAssertEqual(selected.map(\.surface), SurveyWorkGeometry.surfaces(in: store.surveys[0])
            .filter { $0.source.kind == .ceiling }.map(\.surface))
        var configuration = SurveyWorkGeometry.ceiling(selected)
        configuration.firstSkin = [.init(facingID: "ba13", dimensionID: "1200x2400", area: 15)]
        let payload = WorkConfiguration.ceiling(configuration)
        let prepared = try preparedSurveyLayout(selected, type: .ceilingOnFurring, payload: payload)
        _ = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Plafond", type: .ceilingOnFurring, payload: payload, roomID: nil, automatic: prepared)
        let work = try XCTUnwrap(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.first)
        XCTAssertEqual(work.components.compactMap(\.surface), selected.map(\.surface))
        XCTAssertEqual(work.components.map { $0.plans.count }, [1,1])
        XCTAssertEqual(work.area, 15, accuracy: 0.000001)
    }

    func testExternallyPreparedLiningStillRejectsChangedContourOpeningFrameAndConfiguration() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var document = scanDocument(name: "Salon")
        document = try SurveyPlanEditing.addingDoor(document, wallID: document.room.walls[0].id,
            width: 0.83, height: 2.04, position: 1)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Test", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        var configuration = SurveyWorkGeometry.lining(selected)
        configuration.firstSkin = [.init(facingID: "ba13", formatID: "1200x2400", surface: configuration.area)]
        let payload = WorkConfiguration.peripheralLining(configuration)
        let prepared = try preparedSurveyLayout(selected, type: .peripheralLiningStuds, payload: payload)
        for mutation in 0..<5 {
            var invalid = prepared
            switch mutation {
            case 0: invalid.sourceSurfaces[0].contour[0].x += 10
            case 1: invalid.sourceSurfaces[0].openings[0].contour[0].x += 10
            case 2: invalid.sourceSurfaces[0].localFrame?.origin.x += 1
            case 3: invalid.configurationFingerprint += "changed"
            default: invalid.sourceSurfaces[0].id = UUID()
            }
            XCTAssertThrowsError(try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
                name: "Invalide", type: .peripheralLiningStuds, payload: payload, roomID: nil, automatic: invalid)) {
                guard case SurveyWorkError.changedDimensions = $0 else { return XCTFail("Unexpected error: \($0)") }
            }
            XCTAssertTrue(store.project(id: saved.projectID)!.works.isEmpty)
        }
        _ = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Doublage", type: .peripheralLiningStuds, payload: payload, roomID: nil, automatic: prepared)
        XCTAssertEqual(store.project(id: saved.projectID)?.works.count, 1)
    }

    private var priceTestCatalogue: CeilingCataloguePayload {
        .init(version:"test",ouvrage:nil,isolation:[],systemesFixation:[],parements:[
            .init(id:"FACING-BA13-STANDARD",kind:"facing",title:"BA13 standard",summary:"",sourcePage:0,status:"validated",data:["dimensions":.array([.object(["width_mm":.number(1200),"length_mm":.number(2500)])])])
        ],quantitatifs:[.init(id:"QTY-VIS-25",kind:"quantity",title:"Vis TTPC 25",summary:"",sourcePage:0,status:"validated",data:["unit":.string("unité")])],pareVapeur:[],regles:[])
    }
    private func priceTestTariff() -> SupplyPrice {
        .init(id:"test",referenceId:"QTY-VIS-25",variantKey:"standard",label:"Vis",unit:"unité",unitPriceHT:0.00851,repUnitHT:0,priceDate:"2026-09-29",validUntil:"2026-10-29",status:"validated",updatedAt:"2026-10-09T12:00:00Z")
    }
    private func priceTestPayload(_ rows:[SupplyPrice]) -> SupplyPriceCatalogue {
        .init(version:"1.0",revision:"test",currency:"EUR",lowerMultiplier:0.95,upperMultiplier:1.05,prices:rows)
    }
    func testPriceEstimateDoesNotRoundToPacksAndUsesFivePercentRange() throws {
        let result=SupplyCostEstimator.estimate([.init(name:"Vis TTPC 25",quantity:150,unit:"unités")],prices:priceTestPayload([priceTestTariff()]),catalogue:priceTestCatalogue,day:"2026-10-09")
        XCTAssertEqual(try XCTUnwrap(result.total),1.2765,accuracy:0.000001)
        XCTAssertEqual(try XCTUnwrap(result.lower),1.2765*0.95,accuracy:0.000001)
        XCTAssertEqual(try XCTUnwrap(result.upper),1.2765*1.05,accuracy:0.000001)
        XCTAssertTrue(result.missing.isEmpty)
    }
    func testPriceEstimateResolvesExactBoardFormatAndIncludesREPOnce() throws {
        var price=priceTestTariff(); price.referenceId="FACING-BA13-STANDARD"; price.variantKey="1200x2500"; price.unit="m²"; price.unitPriceHT=2.84; price.repUnitHT=0.19
        let result=SupplyCostEstimator.estimate([
            .init(name:"BA13 standard · 1200 × 2500 mm",quantity:2,unit:"plaques"),
            .init(name:"BA13 standard · 1200 × 2400 mm",quantity:1,unit:"plaques")
        ],prices:priceTestPayload([price]),catalogue:priceTestCatalogue,day:"2026-10-09")
        XCTAssertEqual(try XCTUnwrap(result.total),18.18,accuracy:0.000001)
        XCTAssertEqual(result.missing.count,1)
        XCTAssertEqual(result.priced.first?.quantity,6)
    }
    func testPricesMissingExpiredProposedAmbiguousOrInvalidAreNeverZero() throws {
        let supply=[CombinedSupply(name:"Vis TTPC 25",quantity:150,unit:"unités")]
        let valid=priceTestTariff()
        var expired=valid; expired.validUntil="2026-10-01"
        var proposed=valid; proposed.status="proposed"
        var invalid=valid; invalid.unitPriceHT = .nan
        var wrongUnit=valid; wrongUnit.unit="kg"
        var future=valid; future.priceDate="2027-01-01"
        for rows in [[],[expired],[proposed],[invalid],[wrongUnit],[future],[valid,valid]] {
            let result=SupplyCostEstimator.estimate(supply,prices:priceTestPayload(rows),catalogue:priceTestCatalogue,day:"2026-10-09")
            XCTAssertNil(result.total)
            XCTAssertEqual(result.missing.count,1)
        }
        let decoded=try JSONDecoder().decode(SupplyPriceCatalogue.self,from:JSONEncoder().encode(priceTestPayload([valid])))
        XCTAssertEqual(decoded.prices.first?.unitPriceHT,0.00851)
    }

    func testSurveyCreationGeneratesPlansAtomicallyAndCopiesThem() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:fileURL) }
        let store=ProjectStore(fileURL:fileURL)
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Auto",surveyID:nil,surveyName:"Scan",roomID:nil,roomName:"Salon",document:scanDocument(name:"Salon"))
        let surfaces=SurveyWorkGeometry.surfaces(in:store.surveys[0])
        var c=SurveyWorkGeometry.lining(surfaces)
        c.firstSkin=[.init(facingID:"ba13",formatID:"1200x2400",surface:c.area)]
        let id=try store.createSurveyWork(surveyID:saved.surveyID,selections:surfaces,name:"Doublage",type:.peripheralLiningStuds,payload:.peripheralLining(c),roomID:nil)
        let work=try XCTUnwrap(store.project(id:saved.projectID)?.works.first { $0.id == id })
        XCTAssertTrue(work.components.allSatisfy { !$0.plans.isEmpty })
        XCTAssertNotNil(work.automaticLayout)
        let reopened=ProjectStore(fileURL:fileURL)
        let persisted=try XCTUnwrap(reopened.project(id:saved.projectID)?.works.first)
        XCTAssertEqual(persisted.payload,work.payload)
        XCTAssertEqual(persisted.automaticLayout,work.automaticLayout)
        XCTAssertEqual(persisted.components[0].plans,work.components[0].plans)
        XCTAssertEqual(persisted.components[0].framing,work.components[0].framing)
        // The existing project archive deliberately persists ISO-8601 seconds.
        XCTAssertEqual(persisted.createdAt.timeIntervalSince1970,work.createdAt.timeIntervalSince1970,accuracy:1)
        let copiedID=try store.duplicateProject(id:saved.projectID)
        let copy=try XCTUnwrap(store.project(id:copiedID)?.works.first)
        XCTAssertEqual(copy.automaticLayout,work.automaticLayout)
        XCTAssertNotEqual(copy.components[0].plans[0].id,work.components[0].plans[0].id)
        var copiedLayer=copy.components[0].plans[0].layers[0]
        XCTAssertNotEqual(copiedLayer.id,work.components[0].plans[0].layers[0].id)
        copiedLayer.id=work.components[0].plans[0].layers[0].id
        XCTAssertEqual(copiedLayer,work.components[0].plans[0].layers[0])
    }

    func testExistingCoverageRequiresExplicitConfirmationAndKeepsBothWorks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        let saved = try store.saveScannedRoom(projectID:nil,newProjectName:"Recouvrement",surveyID:nil,surveyName:"Scan",roomID:nil,roomName:"Salon",document:scanDocument(name:"Salon"))
        let survey = try XCTUnwrap(store.surveys.first)
        let surfaces = SurveyWorkGeometry.surfaces(in: survey)
        var c = SurveyWorkGeometry.lining(surfaces)
        c.firstSkin = [.init(facingID: "ba13", formatID: "1200x2400", surface: c.area)]
        let first = try store.createSurveyWork(surveyID: saved.surveyID, selections: surfaces, name: "Premier", type: .peripheralLiningStuds, payload: .peripheralLining(c), roomID: nil)
        let works = try XCTUnwrap(store.project(id: saved.projectID)).works
        XCTAssertEqual(SurveyOverlapView.conflictingIDs(selections: surfaces, works: works), Set(surfaces.map(\.id)))
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: saved.surveyID, selections: surfaces, name: "Deuxième", type: .peripheralLiningStuds, payload: .peripheralLining(c), roomID: nil))
        let second = try store.createSurveyWork(surveyID: saved.surveyID, selections: surfaces, name: "Deuxième", type: .peripheralLiningStuds, payload: .peripheralLining(c), roomID: nil, allowsExistingCoverage: true)
        XCTAssertNotEqual(first, second)
        let result = try XCTUnwrap(store.project(id: saved.projectID)).works
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.hasSavedLayout })
        XCTAssertEqual(ProjectStore(fileURL: url).project(id: saved.projectID)?.works.count, 2)
        XCTAssertTrue(result.first { $0.id == second }?.components.allSatisfy { $0.allowsExistingSurveyCoverage == true } == true)
        let copy = try store.duplicateProject(id: saved.projectID)
        XCTAssertEqual(store.project(id: copy)?.works.count, 2)
        XCTAssertEqual(store.surveys.first, survey)
        try store.renameSurvey(projectID: saved.projectID, surveyID: saved.surveyID, name: "Variante")
        XCTAssertEqual(ProjectStore(fileURL: url).surveys.first?.name, "Variante")
        XCTAssertThrowsError(try store.renameSurvey(projectID: saved.projectID, surveyID: saved.surveyID, name: "   "))
    }

    func testAutomaticQuantitiesOnlyIncreaseAndInvalidateOnConfigurationChange() throws {
        var c=FurringLiningConfiguration(); c.enteredSurface=10; c.geometryMode="surface"
        c.quantities=[.init(name:"Fourrures F45/F47",quantity:40,unit:"ml"),.init(name:"Vis TTPC 25",quantity:150,unit:"unités")]
        var work=WorkItem(id:UUID(),projectID:UUID(),name:"Doublage",type:.peripheralLiningFurrings,payload:.furringLining(c),createdAt:Date(),updatedAt:Date())
        work.automaticLayout = .init(configurationFingerprint:LayoutQuantityCalculator.configurationFingerprint(work),minimumSupplies:[
            .init(name:"Fourrures F45/F47",quantity:50,unit:"ml"),.init(name:"Vis TTPC 25",quantity:80,unit:"unités")],warnings:[])
        let catalogue=CeilingCataloguePayload(version:"test",ouvrage:nil,isolation:[],systemesFixation:[],parements:[],quantitatifs:[],pareVapeur:[],regles:[])
        let result=CombinedQuantityCalculator.calculate(works:[work],catalogue:catalogue)
        XCTAssertEqual(result.supplies.first { $0.unit == "ml" }?.quantity,50)
        XCTAssertEqual(result.supplies.first { $0.name == "Vis TTPC 25" }?.quantity,150)
        XCTAssertEqual(try JSONDecoder().decode(WorkItem.self,from:JSONEncoder().encode(work)),work)
        c.furringSpacing=0.4; work.payload = .furringLining(c)
        XCTAssertEqual(CombinedQuantityCalculator.calculate(works:[work],catalogue:catalogue).supplies.first { $0.unit == "ml" }?.quantity,40)
    }

    private func jointWork(_ payload: WorkConfiguration, type: WorkType, projectID: UUID) -> WorkItem {
        .init(id: UUID(), projectID: projectID, name: type.title, type: type, payload: payload, createdAt: Date(), updatedAt: Date())
    }

    func testJointTreatmentDeductsOnlyMatchingEnabledSurfacesAndBothPartitionSides() throws {
        let projectID = UUID()
        var wall = DoublageConfiguration(); wall.geometryMode = "surface"; wall.enteredSurface = 20
        var partition = CloisonDistributionConfiguration(); partition.geometryMode = "surface"; partition.enteredSurface = 10
        var ceiling = CeilingConfiguration(); ceiling.enteredArea = 30
        let works = [jointWork(.peripheralLining(wall), type: .peripheralLiningStuds, projectID: projectID),
                     jointWork(.distributionPartition(partition), type: .distributionPartition, projectID: projectID),
                     jointWork(.ceiling(ceiling), type: .ceilingOnFurring, projectID: projectID)]
        var c = JointTreatmentConfiguration(area: 100, bandPerM2: 1.73, powderPerM2: 0.33, pastePerM2: 0.47)
        XCTAssertEqual(JointTreatmentCalculator.remainingArea(c, works: works + [works[0]]), 60)
        let quantities = JointTreatmentCalculator.quantities(c, works: works)
        XCTAssertEqual(quantities[0].quantity, 103.8, accuracy: 0.0001)
        XCTAssertEqual(quantities[1].quantity, 19.8, accuracy: 0.0001)
        c.compound = "pate"
        XCTAssertEqual(JointTreatmentCalculator.quantities(c, works: works)[1].quantity, 28.2, accuracy: 0.0001)
        c.surface = .ceilings
        XCTAssertEqual(JointTreatmentCalculator.remainingArea(c, works: works), 70)
        c.area = 15
        XCTAssertEqual(JointTreatmentCalculator.remainingArea(c, works: works), 0)
        wall.jointTreatment = false
        XCTAssertEqual(JointTreatmentCalculator.coverage(jointWork(.peripheralLining(wall), type: .peripheralLiningStuds, projectID: projectID), surface: .walls), 0)
    }

    func testJointTreatmentUsesProjectContextEvenForIndividualQuantity() throws {
        let id = UUID()
        var ceiling = CeilingConfiguration(); ceiling.enteredArea = 20
        let existing = jointWork(.ceiling(ceiling), type: .ceilingOnFurring, projectID: id)
        let otherProject = jointWork(.ceiling(ceiling), type: .ceilingOnFurring, projectID: UUID())
        let c = JointTreatmentConfiguration(area: 50, surface: .ceilings, bandPerM2: 1.58, powderPerM2: 0.37, pastePerM2: 0.53)
        let work = jointWork(.jointTreatment(c), type: .jointTreatment, projectID: id)
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let result = CombinedQuantityCalculator.calculate(works: [work], catalogue: catalogue, projectWorks: [existing, otherProject, work])
        XCTAssertEqual(result.totalArea, 30)
        XCTAssertEqual(try XCTUnwrap(result.supplies.first { $0.name == "Bande à joint" }).quantity, 47.4, accuracy: 0.0001)
        XCTAssertEqual(existing.ceilingConfiguration, ceiling)
        XCTAssertEqual(try JSONDecoder().decode(WorkItem.self, from: JSONEncoder().encode(work)), work)
    }

    func testJointReferencesComeFromExistingAdminRecordsAndRejectMissingValues() throws {
        let catalogue = CeilingCataloguePayload(version: "admin-test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [
            .init(id: "QTY-BANDE", kind: "quantity_item", title: "Bande", summary: "", sourcePage: 1, status: "Publié", data: ["values": .object(["simple_060": .number(1.9)])]),
            .init(id: "QTY-ENDUIT-POUDRE", kind: "quantity_item", title: "Poudre", summary: "", sourcePage: 1, status: "Publié", data: ["values": .object(["simple_060": .number(0.4)])]),
            .init(id: "QTY-ENDUIT-PATE", kind: "quantity_item", title: "Pâte", summary: "", sourcePage: 1, status: "Publié", data: ["values": .object(["simple_060": .number(0.6)])])
        ], pareVapeur: [], regles: [])
        var c = JointTreatmentConfiguration(area: 10, surface: .ceilings)
        let snapshot = try XCTUnwrap(JointTreatmentCalculator.applyingReferences(c, catalogue: catalogue, records: .init()))
        XCTAssertEqual(snapshot.bandPerM2, 1.9)
        XCTAssertEqual(snapshot.catalogueVersion, "admin-test")
        c.surface = .walls
        XCTAssertNil(JointTreatmentCalculator.applyingReferences(c, catalogue: catalogue, records: .init()))
        let data = Data(#"{"doublage":{"quantitatif":{"id":"QTY-DOUBLAGE-RAILS-MONTANTS","data":{"coefficients":{"band_ml_m2":1.73,"enduit_poudre_kg_m2":0.33,"enduit_pate_kg_m2":0.47}}}}}"#.utf8)
        let wall = try XCTUnwrap(JointTreatmentCalculator.applyingReferences(c, catalogue: catalogue, records: WorkSummaryCatalogue(data: data)))
        XCTAssertEqual(wall.bandPerM2, 1.73)
        XCTAssertEqual(wall.powderPerM2, 0.33)
        XCTAssertFalse(JointTreatmentConfiguration(area: .nan).isValid)
    }

    func testAttachedOpeningsAreIncludedOnceAndLegacyRemainVisible() throws {
        let id = UUID()
        let parent = jointWork(.ceiling(.init()), type: .ceilingOnFurring, projectID: id)
        var c = OpeningConfiguration(); c.sourceWorkID = parent.id
        let child = jointWork(.openings(c), type: .openings, projectID: id)
        let legacy = jointWork(.openings(.init()), type: .openings, projectID: id)
        let project = ProjectItem(id: id, name: "Test", client: "", address: "", notes: "", works: [parent, child, legacy], createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(project.visibleWorks.map(\.id), [parent.id, legacy.id])
        XCTAssertEqual(WorkOpeningRelations.includingAttached(to: [parent, child], allWorks: project.works).map(\.id), [parent.id, child.id])
        XCTAssertEqual(WorkOpeningRelations.includingAttached(to: [legacy], allWorks: project.works).map(\.id), [legacy.id])
    }

    func testJointWorkPersistenceAndAttachedOpeningDuplication() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("joint-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Joints", client: "", address: "", notes: "")
        let c = JointTreatmentConfiguration(area: 40, bandPerM2: 1.73, powderPerM2: 0.33, pastePerM2: 0.47)
        let id = try store.createConfiguredWork(projectID: projectID, name: "Bandes", type: .jointTreatment, payload: .jointTreatment(c), roomID: nil, newRoomName: nil)
        let reloaded = ProjectStore(fileURL: url)
        XCTAssertEqual(reloaded.project(id: projectID)?.works.first { $0.id == id }?.jointTreatmentConfiguration, c)
        let parent = try store.createConfiguredWork(projectID: projectID, name: "Plafond", type: .ceilingOnFurring, payload: .ceiling(.init()), roomID: nil, newRoomName: nil)
        var opening = OpeningConfiguration(); opening.sourceWorkID = parent
        _ = try store.createConfiguredWork(projectID: projectID, name: "Ouvertures", type: .openings, payload: .openings(opening), roomID: nil, newRoomName: nil)
        let copied = try store.duplicateWork(projectID: projectID, workID: parent)
        XCTAssertEqual(store.project(id: projectID)?.works.filter { $0.openingConfiguration?.sourceWorkID == copied }.count, 1)
        XCTAssertEqual(store.project(id: projectID)?.works.filter { $0.openingConfiguration?.sourceWorkID == parent }.count, 1)
    }

    func testContrastPresentationIsOptIn() {
        var environment = EnvironmentValues()
        XCTAssertEqual(environment.interfacePresentation, .standard)
        environment.interfacePresentation = .contrastLab
        XCTAssertEqual(environment.interfacePresentation, .contrastLab)
        XCTAssertEqual(EnvironmentValues().interfacePresentation, .standard)
    }

    func testWorkPreviewSelectsOnlyItsOwnScannedSurfaces() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Lab preview", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let survey = try XCTUnwrap(store.surveys.first)
        let selected = Array(SurveyWorkGeometry.surfaces(in: survey).filter { $0.source.kind == .wall }.prefix(1))
        XCTAssertEqual(selected.count, 1)
        let workID = try store.createSurveyWork(surveyID: survey.id, selections: selected, name: "Doublage",
            type: .peripheralLiningFurrings, payload: .furringLining(SurveyWorkGeometry.furring(selected)), roomID: nil)
        let work = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID })
        XCTAssertEqual(WorkPreviewSelection.surfaceIDs(work: work, survey: survey), Set(selected.map(\.id)))
        var unrelatedSurvey = survey
        unrelatedSurvey.id = UUID()
        XCTAssertTrue(WorkPreviewSelection.surfaceIDs(work: work, survey: unrelatedSurvey).isEmpty)
    }

    func testAdhesiveFacingFormatSelectionHandlesEmptyAndSingleFormatCatalogue() {
        XCTAssertNil(AdhesiveFacingFormat.selected(id: "1200x2500", in: []))
        let only = AdhesiveFacingFormat(widthMM: 1200, heightMM: 2400)
        XCTAssertEqual(AdhesiveFacingFormat.selected(id: "1200x2500", in: [only]), only)
        let selected = AdhesiveFacingFormat(widthMM: 1200, heightMM: 2600)
        XCTAssertEqual(AdhesiveFacingFormat.selected(id: selected.id, in: [only, selected]), selected)
    }

    private func adhesiveCatalogue(records:[[String:Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject:["doublageParementColle":[
            "parements":records,
            "catalogue":["id":"rule","data":["schema_version":1,"allowed_families":["BA6","BA13"],
                "formats":[["width_mm":1200,"height_mm":2700]]]],
            "quantitatif":["id":"quantities","data":["schema_version":1,
                "coefficients":["plate_m2_m2":1.05,"adhesive_kg_m2":1.8,"band_ml_m2":1.4,"powder_kg_m2":0.33]]]
        ]])
    }

    func testAdhesiveFacingUsesCommonReferencesAndProductSpecificFormats() throws {
        let store=AdhesiveFacingReferenceStore()
        let records:[[String:Any]] = [
            ["id":"FACING-BA13-QUATRE-BORDS-AMINCIS","title":"BA13 quatre bords amincis","data":[
                "mechanical_family":"BA13","function":"quatre_bords_amincis","catalog_schema_version":2,
                "dimensions":[["width_mm":1200,"length_mm":2400]]]],
            ["id":"FACING-BA25-STANDARD","title":"BA25","data":[
                "mechanical_family":"BA25","function":"standard","catalog_schema_version":2,
                "compatible_work_codes":["doublage-peripherique-parement-colle"],
                "dimensions":[["width_mm":900,"length_mm":2600]]]],
            ["id":"incompatible","data":["mechanical_family":"BA13","function":"standard","catalog_schema_version":2,
                "compatible_work_codes":["other"],"dimensions":[["width_mm":1200,"length_mm":2500]]]],
            ["id":"invalid","data":["mechanical_family":"BA13","function":"standard","catalog_schema_version":2,
                "dimensions":[["width_mm":-1,"length_mm":2500]]]]
        ]
        XCTAssertTrue(try store.apply(data:adhesiveCatalogue(records:records)))
        XCTAssertEqual(store.families,["BA13","BA25"])
        let four=try XCTUnwrap(store.functions(for:"BA13").first)
        XCTAssertEqual(four.id,"FACING-BA13-QUATRE-BORDS-AMINCIS")
        XCTAssertEqual(four.formats.map(\.id),["1200x2400"])
        XCTAssertEqual(four.quantityTitle(format:four.formats[0]),"BA13 quatre bords amincis · 1200 × 2400 mm")
        XCTAssertEqual(store.formats(for:"FACING-BA25-STANDARD").map(\.id),["900x2600"])
        XCTAssertEqual(store.quantities.plate,1.05)
        XCTAssertEqual(store.quantities.adhesive,1.8)
    }

    func testAdhesiveFacingPreservesSavedFormatWithoutAddingItToNewWorks() throws {
        let store=AdhesiveFacingReferenceStore()
        XCTAssertTrue(try store.apply(data:adhesiveCatalogue(records:[
            ["id":"board","title":"BA13","data":["mechanical_family":"BA13","function":"standard",
                "catalog_schema_version":2,"dimensions":[["width_mm":1200,"length_mm":2400]]]]
        ])))
        XCTAssertEqual(store.formats(for:"board",preserving:"1200x2700").map(\.id),["1200x2400","1200x2700"])
        XCTAssertEqual(store.formats(for:"board").map(\.id),["1200x2400"])
        XCTAssertEqual(store.formats(for:"board",preserving:"1200x2400").count,1)
        XCTAssertNil(AdhesiveFacingFormat.legacy("1200x-1"))
        XCTAssertNil(AdhesiveFacingFormat.legacy("bad"))
    }

    func testAdhesiveFacingStillDecodesLegacyCatalogue() throws {
        let store=AdhesiveFacingReferenceStore()
        XCTAssertTrue(try store.apply(data:adhesiveCatalogue(records:[
            ["id":"legacy","title":"BA13","data":["mechanical_family":"BA13","function":"standard"]]
        ])))
        XCTAssertEqual(store.formats(for:"legacy").map(\.id),["1200x2700"])
    }

    func testAdhesiveFacingFormRendersWhileCatalogueIsStillLoading() async throws {
        // Regression: the alert message accessed formats[1] before the first network response.
        for editing in [false, true] {
            let references = AdhesiveFacingReferenceStore()
            var saves = 0
            let controller = UIHostingController(rootView: NavigationStack {
                AdhesiveFacingConfiguratorView(
                    initialConfiguration: editing ? AdhesiveFacingConfiguration() : nil,
                    startsAtResult: editing,
                    onSave: { _ in saves += 1 }
                ).environmentObject(references)
            })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(references.isLoading)
            XCTAssertTrue(references.formats.isEmpty)
            XCTAssertEqual(saves, 0)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testPartitionJunctionSplitsLinkedWallWithoutLosingSavedLayoutOrArea() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store=ProjectStore(fileURL:url)
        let document=scanDocument(name:"Mur à diviser")
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Jonction",surveyID:nil,surveyName:"Scan",roomID:nil,roomName:"Pièce",document:document)
        let survey=try XCTUnwrap(store.surveys.first), checkpoint=try XCTUnwrap(survey.checkpoints.first)
        let wall=try XCTUnwrap(checkpoint.document.room.walls.first)
        let selections=SurveyWorkGeometry.surfaces(in:survey).filter { $0.source.kind == .wall && $0.source.surfaceID==wall.id }
        let configuration=SurveyWorkGeometry.lining(selections)
        let workID=try store.createSurveyWork(surveyID:survey.id,selections:selections,name:"Doublage",type:.peripheralLiningStuds,payload:.peripheralLining(configuration),roomID:nil)
        let component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
        var layout=LayoutDocument.newSupport(try XCTUnwrap(component.surface))
        layout.layers[0].offset = .init(x:127,y:311)
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,document:layout)
        // Avoid the fixture's opening when choosing the T-junction.
        let point=wall.start+wall.direction*(wall.length.effectiveValue*0.1)
        let cut=try SurveyPlanEditing.splittingJoinedWalls(checkpoint.document,at:[point],excluding:UUID())
        try store.updateSurveyRoom(surveyID:survey.id,checkpointID:checkpoint.id,expectedDocument:checkpoint.document,document:cut)
        let reloaded=ProjectStore(fileURL:url)
        let work=try XCTUnwrap(reloaded.project(id:saved.projectID)?.works.first)
        XCTAssertEqual(work.components.count,2)
        XCTAssertEqual(work.area,configuration.area,accuracy:1e-8)
        XCTAssertTrue(work.components.allSatisfy { $0.plans.count==1 && $0.plans[0].layers[0].offset==layout.layers[0].offset })
        XCTAssertEqual(try work.components.reduce(0.0) { $0+(try XCTUnwrap($1.surface).netMeasuredArea()) },configuration.area*1_000_000,accuracy:0.01)
    }

    func testBentPartitionSplitInheritsCeilingLayoutInSameWork() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store=ProjectStore(fileURL:url)
        var document=scanDocument(name:"Salon")
        let source=document.room.walls[0].provenance
        let ring:[RoomPoint]=[.init(x:0,y:0,z:0),.init(x:4,y:0,z:0),.init(x:4,y:0,z:3),.init(x:0,y:0,z:3)]
        document.room.walls=ring.indices.map { i in
            let a=ring[i],b=ring[(i+1)%ring.count]
            return .init(start:a,end:b,length:.init(rawValue:(b-a).length,provenance:source),height:.init(rawValue:2.5,provenance:source),provenance:source)
        }
        document=try WallCeilingEstimate.addingIfMissing(to:document)
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Cloison",surveyID:nil,surveyName:"Scan",roomID:nil,roomName:"Salon",document:document)
        try validateAllCheckpoints(in:store,surveyID:saved.surveyID)
        let survey=try XCTUnwrap(store.surveys.first),checkpoint=try XCTUnwrap(survey.checkpoints.first)
        let selection=SurveyWorkGeometry.surfaces(in:survey).filter { $0.source.kind == .ceiling }
        let workID=try store.createSurveyWork(surveyID:survey.id,selections:selection,name:"Plafond",type:.ceilingOnFurring,payload:.ceiling(SurveyWorkGeometry.ceiling(selection)),roomID:nil)
        let component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
        var layout=LayoutDocument.newSupport(try XCTUnwrap(component.surface))
        layout.layers[0].offset = .init(x:127,y:311)
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,document:layout)
        var partition=try SurveyPlanEditing.addingPartition(checkpoint.document,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:1.5),height:2.5)
        partition=try SurveyPlanEditing.addingPartition(partition,start:.init(x:2,y:0,z:1.5),end:.init(x:4,y:0,z:1.5),height:2.5)
        let split=try WallCeilingEstimate.splitForNewPartition(before:checkpoint.document,after:partition,depths:[:])
        try store.updateSurveyRoom(surveyID:survey.id,checkpointID:checkpoint.id,expectedDocument:checkpoint.document,document:split)
        let project=try XCTUnwrap(ProjectStore(fileURL:url).project(id:saved.projectID))
        XCTAssertEqual(project.works.count,1)
        let parts=try XCTUnwrap(project.works.first).components
        XCTAssertEqual(parts.count,2)
        XCTAssertTrue(parts.allSatisfy { $0.plans.count == 1 && $0.plans[0].layers[0].offset == layout.layers[0].offset })
        XCTAssertEqual(try parts.reduce(0.0) { $0 + (try XCTUnwrap($1.surface).netMeasuredArea()) },12_000_000,accuracy:0.01)
        let partitionID=try XCTUnwrap(partition.room.walls.last?.id)
        let reunited=try SurveyPlanEditing.removingPartition(split,id:partitionID)
        try store.updateSurveyRoom(surveyID:survey.id,checkpointID:checkpoint.id,expectedDocument:split,document:reunited)
        let reloaded=ProjectStore(fileURL:url)
        XCTAssertEqual(reloaded.surveys.first?.checkpoints.first?.document.room.ceilings.count,1)
        let retained=try XCTUnwrap(reloaded.project(id:saved.projectID)?.works.first)
        XCTAssertEqual(retained.components.map(\.id),parts.map(\.id))
        XCTAssertEqual(retained.components.map(\.plans),parts.map(\.plans))
        XCTAssertEqual(try retained.components.reduce(0.0) { $0 + (try XCTUnwrap($1.surface).netMeasuredArea()) },12_000_000,accuracy:0.01)
    }
    func testCeilingSplitInheritsSavedLayoutAndRepeatedCutsAcrossReloads() throws {
        for pitch in [0.0,0.25] {
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
            defer { try? FileManager.default.removeItem(at:url) }
            let store=ProjectStore(fileURL:url)
            var document=scanDocument(name:"Cuisine salon")
            let provenance=GeometryProvenance(source:.estimated)
            let floor:[RoomPoint]=[.init(x:0,y:0,z:0),.init(x:4,y:0,z:0),.init(x:4,y:0,z:3),.init(x:0,y:0,z:3)]
            let slope=PlaquistoSlope(plane:.init(a:pitch,b:0,c:3),boundaries:[floor.map { .init(x:$0.x,y:3+pitch*$0.x,z:$0.z) }],provenance:provenance,accepted:true)
            document.room.slopes=[slope]
            document.room.ceilings=[.init(slopeIDs:[slope.id],provenance:provenance,
                estimateSettings:.init(shape:pitch == 0 ? .flat : .singleSlope,lowHeight:3,highHeight:3+4*pitch),footprint:floor,floorElevation:0)]
            let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Division",surveyID:nil,surveyName:"Scan",roomID:nil,roomName:"Salon",document:document)
            try validateAllCheckpoints(in:store,surveyID:saved.surveyID)
            let survey=try XCTUnwrap(store.surveys.first)
            let selection=SurveyWorkGeometry.surfaces(in:survey).filter { $0.source.kind == .ceiling }
            let workID=try store.createSurveyWork(surveyID:survey.id,selections:selection,name:"Plafond",type:.ceilingOnFurring,payload:.ceiling(SurveyWorkGeometry.ceiling(selection)),roomID:nil)
            let component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
            var layout=LayoutDocument.newSupport(try XCTUnwrap(component.surface))
            layout.layers[0].offset = .init(x:137,y:223)
            layout.layers[0].staggered=true
            layout.layers[0].staggerOffset=1200
            layout.layers[0].furring = .init(spacing:600,offset:137,orientation:.vertical,referenceEdge:1,usesOwnReference:true,peripheralInset:100)
            let bounds=layout.surface.bounds
            layout.lighting = .init(count:3,positions:[
                .init(x:bounds.min.x+bounds.width*0.25,y:bounds.center.y),
                bounds.center,
                .init(x:bounds.min.x+bounds.width*0.75,y:bounds.center.y)])
            try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,document:layout)
            let original=try SheetLayoutEngine.calculate(surface:layout.surface,layer:layout.layers[0])
            let checkpoint=try XCTUnwrap(store.surveys.first?.checkpoints.first)
            let split=try WallCeilingEstimate.split(checkpoint.document,ceilingID:document.room.ceilings[0].id,
                from:.init(x:2,y:0,z:-1),to:.init(x:2,y:0,z:4))
            try store.updateSurveyRoom(surveyID:survey.id,checkpointID:checkpoint.id,expectedDocument:checkpoint.document,document:split)
            var work=try XCTUnwrap(ProjectStore(fileURL:url).project(id:saved.projectID)?.works.first)
            XCTAssertEqual(work.components.count,2)
            XCTAssertEqual(Set(work.components.map(\.id)).count,2)
            XCTAssertEqual(Set(work.components.flatMap { $0.plans.map(\.id) }).count,2)
            XCTAssertEqual(work.components.flatMap { $0.plans.flatMap { $0.lighting?.positions ?? [] } }.count,3)
            var net=0.0, framing=0.0
            for part in work.components {
                let inherited=try XCTUnwrap(part.document(for:XCTUnwrap(part.plans.first)))
                XCTAssertEqual(inherited.surface.localFrame,layout.surface.localFrame)
                XCTAssertEqual(inherited.layers[0].offset,layout.layers[0].offset)
                XCTAssertEqual(inherited.layers[0].staggered,true)
                XCTAssertEqual(inherited.layers[0].inheritedGridFrame,original.frame)
                XCTAssertEqual(inherited.layers[0].furring?.offset,137)
                XCTAssertEqual(inherited.layers[0].furring?.peripheralReferenceContour,layout.surface.contour)
                let result=try SheetLayoutEngine.calculate(surface:inherited.surface,layer:inherited.layers[0])
                net += result.netArea
                framing += result.furring.lines.reduce(0) { $0+($1.end-$1.start).length }
                for sheet in result.sheets {
                    XCTAssertTrue(original.sheets.contains { ($0.origin-sheet.origin).length<0.001 })
                }
            }
            XCTAssertEqual(net,original.netArea,accuracy:0.1)
            XCTAssertEqual(framing,original.furring.lines.reduce(0) { $0+($1.end-$1.start).length },accuracy:0.1)
            // Multiple cuts before a single editor save must resolve ancestry.
            let again=try WallCeilingEstimate.split(split,ceilingID:split.room.ceilings[0].id,
                from:.init(x:-1,y:0,z:1),to:.init(x:5,y:0,z:1))
            let last=try XCTUnwrap(again.room.ceilings.last)
            let third=try WallCeilingEstimate.split(again,ceilingID:last.id,
                from:.init(x:-1,y:0,z:2),to:.init(x:5,y:0,z:2))
            try store.updateSurveyRoom(surveyID:survey.id,checkpointID:checkpoint.id,expectedDocument:split,document:third)
            work=try XCTUnwrap(ProjectStore(fileURL:url).project(id:saved.projectID)?.works.first)
            XCTAssertEqual(work.components.count,4)
            XCTAssertEqual(work.components.flatMap { $0.plans.flatMap { $0.lighting?.positions ?? [] } }.count,3)
            XCTAssertTrue(work.components.allSatisfy { $0.plans.count == 1 && $0.plans[0].geometryRevision == $0.geometryRevision })
            let savedPlans=work.components.map(\.plans), savedPayload=work.payload
            var merged=third
            while merged.room.ceilings.count > 1 {
                let first=merged.room.ceilings[0].id
                let next=try XCTUnwrap(merged.room.ceilings.dropFirst().compactMap {
                    try? CeilingZoneEditing.merge(merged,first:first,second:$0.id)
                }.first)
                merged=next
            }
            merged=CeilingZoneEditing.togglingVisibility(merged,ceilingID:merged.room.ceilings[0].id)
            try store.updateSurveyRoom(surveyID:survey.id,checkpointID:checkpoint.id,expectedDocument:third,document:merged)
            let retained=try XCTUnwrap(ProjectStore(fileURL:url).project(id:saved.projectID)?.works.first)
            XCTAssertEqual(retained.components.map(\.plans),savedPlans,"Grouping/hiding cannot invalidate saved layouts")
            XCTAssertEqual(retained.payload,savedPayload,"Keep existing quantities")
            let updatedSurvey=try XCTUnwrap(store.surveys.first)
            let hiddenSelection=SurveyWorkGeometry.surfaces(in:updatedSurvey).filter { $0.source.kind == .ceiling }
            XCTAssertThrowsError(try store.createSurveyWork(surveyID:survey.id,selections:hiddenSelection,
                name:"Peinture cachée",type:.ceilingOnFurring,payload:.ceiling(SurveyWorkGeometry.ceiling(hiddenSelection)),roomID:nil))
        }
    }

    func testQuickScannedLayoutKeepsOpeningsWithoutCreatingProjectOrWork() throws {
        var document=scanDocument(name:"Cuisine")
        let wall=document.room.walls[0]
        document.room.openings=[.init(wallID:wall.id,kind:.window,center:.init(x:1.5,y:1.5,z:0),width:.init(rawValue:1,provenance:wall.provenance),height:.init(rawValue:1,provenance:wall.provenance),sillHeight:.init(rawValue:1,provenance:wall.provenance),positionOnWall:.init(rawValue:1,provenance:wall.provenance),provenance:wall.provenance)]
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Relevé",checkpoints:[.init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        let chosen=try XCTUnwrap(SurveyWorkGeometry.surfaces(in:survey).first)
        let layout=SurveyWorkGeometry.quickLayoutDocument(chosen)
        XCTAssertEqual(layout.surface.contour,chosen.surface.contour)
        XCTAssertEqual(layout.surface.openings,chosen.surface.openings)
        XCTAssertEqual(layout.surface.localFrame,chosen.surface.localFrame)
        XCTAssertNotEqual(layout.surface.id,chosen.surface.id)
        XCTAssertEqual(layout.surface.name,"Cuisine · Mur 1")
        XCTAssertNotNil(layout.layers[0].furring)
        XCTAssertEqual(try layout.surface.netMeasuredArea(),9_000_000,accuracy:0.001)
        XCTAssertEqual(survey.checkpoints[0].document,document)
    }

    func testApprovedLayoutQuantityIsPersistedAndReplacesOnlySelectedSupplies() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store=ProjectStore(fileURL:url)
        let project=try store.createProject(name:"Quantités",client:"",address:"",notes:"")
        let id=try store.createWork(projectID:project,name:"Plafond",type:.ceilingOnFurring,configuration:.init(length:4,width:3))
        var work=try XCTUnwrap(store.project(id:project)?.works.first)
        let takeoff=LayoutQuantityTakeoff(fingerprint:LayoutQuantityCalculator.fingerprint(work),area:12,
            boards:[.init(name:"Plaque test",quantity:6,unit:"plaque(s)")],framingMeters:27.5,perimeterMeters:15.4,hangers:18)
        try store.saveLayoutQuantityTakeoff(projectID:project,workID:id,takeoff:takeoff)
        work=try XCTUnwrap(ProjectStore(fileURL:url).project(id:project)?.works.first)
        XCTAssertEqual(LayoutQuantityCalculator.validated(work),takeoff)
        func row(_ id:String,_ name:String,_ unit:String,_ ratio:Double) -> CeilingReferenceRecord {
            .init(id:id,kind:"quantity_item",title:name,summary:"",sourcePage:0,status:"Publié",data:["unit":.string(unit),"values":.object(["simple_060":.number(ratio)])])
        }
        let catalogue=CeilingCataloguePayload(version:"test",ouvrage:nil,isolation:[],systemesFixation:[],parements:[],quantitatifs:[
            row("QTY-FOURRURE","Fourrure F45","ml",2),row("QTY-CORNIERE","Cornières anciennes","ml",1),row("QTY-VIS-25","Vis test","unité",15)
        ],pareVapeur:[],regles:[])
        let result=CombinedQuantityCalculator.calculate(works:[work,work],catalogue:catalogue)
        XCTAssertEqual(result.totalArea,12)
        XCTAssertEqual(result.supplies.first{$0.name == "Fourrures F45/F47"}?.quantity,27.5)
        XCTAssertEqual(result.supplies.first{$0.name == "Cornière"}?.quantity,15.4)
        XCTAssertNil(result.supplies.first{$0.name == "Cornières anciennes"})
        XCTAssertEqual(result.supplies.first{$0.name == "Vis test"}?.quantity,180)
        XCTAssertEqual(result.supplies.first{$0.name == "Plaque test"}?.quantity,6)
        // A saved plan refines half the ouvrage; the unplanned half keeps its
        // formula estimate. Neither the total area nor unrelated supplies shrink.
        var half=takeoff; half.area=6; half.coverageFraction=0.5; half.boardCoverageFractions=[0.5]
        work.layoutQuantityTakeoff=half
        let mixed=CombinedQuantityCalculator.calculate(works:[work],catalogue:catalogue)
        XCTAssertEqual(mixed.totalArea,12)
        XCTAssertEqual(mixed.supplies.first{$0.name == "Fourrures F45/F47"}?.quantity,27.5+12)
        XCTAssertEqual(mixed.supplies.first{$0.name == "Cornière"}?.quantity,15.4+6)
        XCTAssertEqual(mixed.supplies.first{$0.name == "Vis test"}?.quantity,180)
        var stale=takeoff; stale.fingerprint="ancien"
        XCTAssertThrowsError(try store.saveLayoutQuantityTakeoff(projectID:project,workID:id,takeoff:stale))
        XCTAssertEqual(store.project(id:project)?.works.first?.layoutQuantityTakeoff,takeoff)
    }

    func testDeleteSurveyKeepsDerivedWorksLayoutsAndOtherSurveys() throws {
        let fileURL=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:fileURL) }
        let store=ProjectStore(fileURL:fileURL)
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Maison",surveyID:nil,
            surveyName:"À supprimer",roomID:nil,roomName:"Salon",document:scanDocument(name:"Salon"))
        let other=try store.saveScannedRoom(projectID:saved.projectID,newProjectName:nil,surveyID:nil,
            surveyName:"Conservé",roomID:nil,roomName:"Cuisine",document:scanDocument(name:"Cuisine"))
        try validateAllCheckpoints(in:store,surveyID:saved.surveyID)
        let survey=try XCTUnwrap(store.surveys.first { $0.id == saved.surveyID })
        let selected=SurveyWorkGeometry.surfaces(in:survey)
        let workID=try store.createSurveyWork(surveyID:survey.id,selections:selected,name:"Doublage",
            type:.peripheralLiningFurrings,payload:.furringLining(SurveyWorkGeometry.furring(selected)),roomID:nil)
        let component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
        let plan=try XCTUnwrap(component.document(for:.init()))
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,
            sideRoomID:nil,document:plan,expectedGeometryRevision:component.geometryRevision)
        let before=try XCTUnwrap(store.project(id:saved.projectID))
        XCTAssertThrowsError(try store.deleteSurvey(projectID:UUID(),surveyID:saved.surveyID))
        XCTAssertEqual(store.project(id:saved.projectID),before)
        try store.deleteSurvey(projectID:saved.projectID,surveyID:saved.surveyID)
        let restored=ProjectStore(fileURL:fileURL)
        XCTAssertNil(restored.lastError)
        XCTAssertEqual(restored.surveys.map(\.id),[other.surveyID])
        let project=try XCTUnwrap(restored.project(id:saved.projectID))
        XCTAssertEqual(project.rooms,before.rooms)
        let work=try XCTUnwrap(project.works.first)
        XCTAssertEqual(work.payload,before.works[0].payload)
        XCTAssertTrue(work.hasSavedLayout)
        var expected=before.works[0].components
        for i in expected.indices { expected[i].surveySource=nil }
        XCTAssertEqual(work.components,expected)
        XCTAssertFalse(work.surveySourceNeedsReview)
        XCTAssertThrowsError(try store.deleteSurvey(projectID:saved.projectID,surveyID:saved.surveyID))
    }

    func testScannedFurringWorkSurvivesRoundedReadOnlyFieldsAndReload() async throws {
        let fileURL=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:fileURL) }
        let store=ProjectStore(fileURL:fileURL)
        var document=scanDocument(name:"Salon")
        try document.room.walls[0].length.correct(4.318762)
        try document.room.walls[0].height.correct(2.537842)
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Précision",surveyID:nil,
            surveyName:"Scan",roomID:nil,roomName:"Salon",document:document)
        try validateAllCheckpoints(in:store,surveyID:saved.surveyID)
        let survey=try XCTUnwrap(store.surveys.first)
        let selections=SurveyWorkGeometry.surfaces(in:survey)
        var configuration=SurveyWorkGeometry.furring(selections)
        let original=configuration
        // Same disabled fields as the scan-prefilled furring form, with real
        // SwiftUI onAppear/onChange delivery (not a format-only unit test).
        let controller=UIHostingController(rootView:VStack {
            ZeroEmptyDecimalTextField(value:Binding(get:{ configuration.height },set:{ configuration.height=$0 }))
            ZeroEmptyDecimalTextField(value:Binding(get:{ configuration.enteredSurface },set:{ configuration.enteredSurface=$0 }))
        }.disabled(true))
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController=controller; window.makeKeyAndVisible()
        defer { window.isHidden=true; window.rootViewController=nil }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for:.milliseconds(250))
        XCTAssertEqual(configuration.height,original.height)
        XCTAssertEqual(configuration.enteredSurface,original.enteredSurface)
        let id=try store.createSurveyWork(surveyID:survey.id,selections:selections,name:"Doublage précis",
            type:.peripheralLiningFurrings,payload:.furringLining(configuration),roomID:nil)
        let restored=try XCTUnwrap(ProjectStore(fileURL:fileURL).project(id:saved.projectID)?.works.first { $0.id == id })
        guard case .furringLining(let payload)=restored.payload else { return XCTFail("Wrong work type") }
        XCTAssertEqual(payload.height,original.height)
        XCTAssertEqual(payload.area,SurveyWorkGeometry.totalArea(selections))
        XCTAssertEqual(payload.measuredWallRuns,original.measuredWallRuns)
        XCTAssertEqual(restored.components.count,selections.count)
    }

    func testLayoutDraftDoesNotPersistUntilSuccessfulSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        let project = try store.createProject(name: "Brouillons", client: "", address: "", notes: "")
        let work = try store.createConfiguredWork(projectID: project, name: "Plafond", type: .ceilingOnFurring,
            payload: .ceiling(.init(length: 4, width: 3)), roomID: nil, newRoomName: nil)
        let other = try store.createConfiguredWork(projectID: project, name: "Autre plafond", type: .ceilingOnFurring,
            payload: .ceiling(.init(length: 2, width: 3)), roomID: nil, newRoomName: nil)
        let draft = WorkComponentRecord(name: "Plafond partie A")
        let document = componentDocument(kind: .ceiling)
        _ = try store.reviewComponentPlan(projectID: project, componentID: draft.id, document: document)
        // Opening/reviewing then abandoning has no persistent side effects.
        XCTAssertTrue(ProjectStore(fileURL: url).project(id: project)!.works.allSatisfy { $0.components.isEmpty && !$0.hasSavedLayout })
        var invalid = document
        invalid.layers = []
        XCTAssertThrowsError(try store.saveComponentPlan(projectID: project, workID: work, componentID: draft.id,
            sideRoomID: nil, document: invalid, newComponent: draft))
        XCTAssertTrue(ProjectStore(fileURL: url).project(id: project)!.works.allSatisfy { $0.components.isEmpty })
        try store.saveComponentPlan(projectID: project, workID: work, componentID: draft.id,
            sideRoomID: nil, document: document, expectedGeometryRevision: 0, newComponent: draft)
        let loaded = try XCTUnwrap(ProjectStore(fileURL: url).project(id: project))
        let saved = try XCTUnwrap(loaded.works.first { $0.id == work })
        XCTAssertTrue(saved.hasSavedLayout)
        XCTAssertEqual(saved.components.count, 1)
        XCTAssertEqual(saved.components.first?.id, draft.id)
        XCTAssertEqual(saved.layoutDocument?.surface, document.surface)
        XCTAssertFalse(try XCTUnwrap(loaded.works.first { $0.id == other }).hasSavedLayout)
        // Subsequent saves must update the same component, not append the draft again.
        try store.saveComponentPlan(projectID: project, workID: work, componentID: draft.id,
            sideRoomID: nil, document: document, newComponent: draft)
        XCTAssertEqual(store.project(id: project)!.works.first { $0.id == work }!.components.count, 1)
    }

    func testLayoutExistenceIgnoresLegacyEmptyComponentsAndIncludesMultiplePlans() {
        var work = summaryWork(.ceiling(.init()), type: .ceilingOnFurring)
        var component = WorkComponentRecord(name: "Ancien brouillon")
        work.components = [component]
        XCTAssertFalse(work.hasSavedLayout)
        component.surface = componentDocument(kind: .ceiling).surface
        work.components = [component]
        XCTAssertFalse(work.hasSavedLayout)
        component.plans = [.init(sideRoomID: nil)]
        component.plans[0].layers = []
        work.components = [component]
        XCTAssertFalse(work.hasSavedLayout)
        component.plans[0].layers = [.init()]
        work.components = [component, WorkComponentRecord(name: "Autre")]
        XCTAssertTrue(work.hasSavedLayout)
        XCTAssertNil(work.layoutDocument) // The single-support facade is not an existence flag.
    }

    func testTechnicalSummaryUsesSavedSelectionsAndCentralThermalCalculation() throws {
        let catalogue = try summaryCatalogue()
        var c = FurringLiningConfiguration(geometryMode: "surface", enteredSurface: 24.6)
        c.firstInsulation = .init(familyID: "wood", lambda: 0.038, thicknessMM: 120)
        c.firstSkin = [.init(facingID: "board", surface: 24.6)]
        let work = summaryWork(.furringLining(c), type: .peripheralLiningFurrings)
        let summary = WorkTechnicalSummary.text(for: work, catalogue: catalogue)
        XCTAssertTrue(summary.contains(work.type.title))
        XCTAssertTrue(summary.contains("Laine de bois 120 mm (R 3,16)"))
        XCTAssertTrue(summary.contains("BA13"))
        XCTAssertTrue(summary.contains("24,6 m²"))
        XCTAssertFalse(summary.contains(work.name))
        c.insulationEnabled = false
        c.firstSkin = []
        let noInsulation = WorkTechnicalSummary.text(for: summaryWork(.furringLining(c), type: .peripheralLiningFurrings), catalogue: catalogue)
        XCTAssertFalse(noInsulation.contains("Laine"))
        XCTAssertFalse(noInsulation.contains("BA13"))
        XCTAssertFalse(noInsulation.contains("R 3"))
    }

    func testTechnicalSummaryCeilingsDoubleLayersAndMissingReferences() throws {
        var c = CeilingConfiguration(length: 4, width: 3, enteredArea: 12.01)
        c.insulationID = "glass"; c.insulationThickness = 100
        c.insulationLayers = 2; c.secondInsulationID = "glass"; c.secondInsulationThickness = 200
        c.firstSkin = [.init(facingID: "board", dimensionID: "", area: 12)]
        c.secondSkin = [.init(facingID: "unknown", dimensionID: "", area: 12)]
        let work = summaryWork(.ceiling(c), type: .ceilingOnFurring)
        let summary = WorkTechnicalSummary.text(for: work, catalogue: try summaryCatalogue())
        XCTAssertTrue(summary.contains("Laine de verre 100 mm (R 2,86)"))
        XCTAssertTrue(summary.contains("Laine de verre 200 mm (R 5,71)"))
        XCTAssertTrue(summary.contains("12,01 m²"))
        XCTAssertFalse(summary.contains("unknown"))
        let offline = WorkTechnicalSummary.text(for: work, catalogue: .init())
        XCTAssertTrue(offline.contains("Isolant 100 mm"))
        XCTAssertFalse(offline.contains("R 2"))
        XCTAssertFalse(offline.contains("N/A"))
    }

    func testTechnicalSummaryOtherWorkTypesAndPublishedBondedResistance() throws {
        let catalogue = try summaryCatalogue()
        var rail = RailStudCeilingConfiguration()
        rail.firstInsulation = .init(seriesID: "glass", thickness: 100)
        rail.firstSkin = [.init(productID: "board")]
        var partition = CloisonDistributionConfiguration()
        partition.insulationID = "glass"; partition.insulationThicknessMM = 100
        partition.faceAFirst = [.init(facingID: "board")]
        var lining = DoublageConfiguration()
        lining.firstInsulation = .init(familyID: "wood", lambda: 0.038, thicknessMM: 120)
        lining.firstSkin = [.init(facingID: "board")]
        let cases: [(WorkConfiguration, WorkType, String)] = [
            (.railStudCeiling(rail), .ceilingOnRailsAndStuds, "R 2,86"),
            (.distributionPartition(partition), .distributionPartition, "BA13"),
            (.peripheralLining(lining), .peripheralLiningStuds, "Laine de bois"),
            (.modularCeiling(.init(length: 4, width: 3)), .modularCeiling, "Dalles 600 × 600 mm"),
            (.adhesiveFacing(.init()), .peripheralLiningAdhesiveFacing, "BA13"),
            (.alveolarPartition(.init(panels: [.init(panelID: "panel")])), .alveolarPartition, "Panneau alvéolaire"),
            (.bondedLining(.init(lambda: 0.032, insulationThicknessMM: 100)), .peripheralLiningBonded, "R 3,1"),
            (.openings(.init()), .openings, WorkType.openings.title)
        ]
        for (payload, type, expected) in cases {
            let summary = WorkTechnicalSummary.text(for: summaryWork(payload, type: type), catalogue: catalogue)
            XCTAssertTrue(summary.contains(expected), "\(type): \(summary)")
            XCTAssertFalse(summary.contains("•  •"))
        }
    }

    func testConfigurationEditPreservesWorkIdentityNameAndSavedLayout() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(fileURL: folder.appendingPathComponent("projects.json"))
        let project = try store.createProject(name: "Edition", client: "", address: "", notes: "")
        let id = try store.createConfiguredWork(projectID: project, name: "Mon plafond", type: .ceilingOnFurring,
            payload: .ceiling(.init(length: 4, width: 3)), roomID: nil, newRoomName: nil,
            document: componentDocument(kind: .ceiling))
        let before = try XCTUnwrap(store.project(id: project)?.works.first)
        var config = try XCTUnwrap(before.ceilingConfiguration)
        config.insulationID = "glass"; config.insulationThickness = 200
        try store.updateWork(before, configuration: config)
        let after = try XCTUnwrap(store.project(id: project)?.works.first)
        XCTAssertEqual(store.project(id: project)?.works.count, 1)
        XCTAssertEqual(after.id, id)
        XCTAssertEqual(after.name, before.name)
        XCTAssertEqual(after.components, before.components)
        XCTAssertTrue(after.hasSavedLayout)
        XCTAssertTrue(WorkTechnicalSummary.text(for: after, catalogue: try summaryCatalogue()).contains("200 mm (R 5,71)"))
    }

    private func summaryWork(_ payload: WorkConfiguration, type: WorkType) -> WorkItem {
        WorkItem(id: UUID(), projectID: UUID(), name: "Nom personnalisé", type: type,
            payload: payload, createdAt: Date(), updatedAt: Date())
    }
    private func summaryCatalogue() throws -> WorkSummaryCatalogue {
        try WorkSummaryCatalogue(data: Data(#"{"isolation":[{"id":"glass","title":"Laine de verre","data":{"lambda_w_mk":0.035}}],"doublageFourrures":{"isolants":[{"id":"wood","title":"Laine de bois","data":{}}],"parements":[{"id":"board","title":"BA13","data":{}}]},"alveolaire":{"parements":[{"id":"panel","title":"Panneau alvéolaire","data":{}}]},"doublageColle":{"catalogue":{"id":"complex","data":{"complexes":[{"lambda_w_mk":0.032,"insulation_thickness_mm":100,"thermal_resistance_m2_kw":3.1}]}}}}"#.utf8))
    }

    func testLayingOffsetExportsMeasuredSupportAndSeparateCoveringRatio() throws {
        var surface = Surface2D(name:"Plafond",kind:.ceiling,contour:[.zero,.init(x:5000,y:0),.init(x:5000,y:5000),.init(x:0,y:5000)])
        let original = LayoutDocument(surface:surface,layers:[.init()])
        surface = try surface.changingLayingOffset(globalMM:30)
        let inset = LayoutDocument(surface:surface,layers:[.init()])
        XCTAssertEqual(LayoutWorkGeometry.area(inset),25,accuracy:0.000001)
        XCTAssertEqual(LayoutWorkGeometry.coveringAreaRatio(inset),24.4036/25,accuracy:0.000001)
        XCTAssertEqual(LayoutWorkGeometry.ceiling(inset),LayoutWorkGeometry.ceiling(original))
        XCTAssertEqual(LayoutWorkGeometry.railCeiling(inset),LayoutWorkGeometry.railCeiling(original))
        XCTAssertEqual(LayoutWorkGeometry.furring(inset),LayoutWorkGeometry.furring(original))
        XCTAssertEqual(LayoutWorkGeometry.lining(inset),LayoutWorkGeometry.lining(original))
        XCTAssertEqual(LayoutWorkGeometry.partition(inset),LayoutWorkGeometry.partition(original))
        surface = try surface.changingLayingOffset(reset:true)
        XCTAssertEqual(LayoutWorkGeometry.coveringAreaRatio(LayoutDocument(surface:surface,layers:[.init()])),1)
        XCTAssertEqual(LayoutWorkGeometry.coveringAreaRatio(nil),1)
    }

    func testLayingOffsetChangesCoveringsButNotCombinedFraming() throws {
        let surface = Surface2D(name:"Plafond",kind:.ceiling,contour:[.zero,.init(x:5000,y:0),.init(x:5000,y:5000),.init(x:0,y:5000)])
        let framing = CeilingReferenceRecord(id:"QTY-FOURRURE",kind:"quantity_item",title:"Fourrure",summary:"",sourcePage:0,status:"Publié",data:["unit":.string("ml"),"values":.object(["simple_060":.number(2)])])
        let board = CeilingReferenceRecord(id:"board",kind:"",title:"BA13",summary:"",sourcePage:0,status:"Publié",data:["dimensions":.array([.object(["width_mm":.number(1200),"length_mm":.number(2400)])])])
        let insulation = CeilingReferenceRecord(id:"wool",kind:"",title:"Laine de verre",summary:"",sourcePage:0,status:"Publié",data:[:])
        let catalogue = CeilingCataloguePayload(version:"test",ouvrage:nil,isolation:[insulation],systemesFixation:[],parements:[board],quantitatifs:[framing],pareVapeur:[],regles:[])
        var configuration = CeilingConfiguration(length:5,width:5)
        configuration.insulationID = "wool"
        configuration.firstSkin = [.init(facingID:"board",dimensionID:"1200x2400",area:25)]
        var work = WorkItem(id:UUID(),projectID:UUID(),name:"Test",type:.ceilingOnFurring,configuration:configuration,createdAt:Date(),updatedAt:Date())
        work.layoutDocument = LayoutDocument(surface:surface,layers:[.init()])
        let before = CombinedQuantityCalculator.calculate(works:[work],catalogue:catalogue)
        work.layoutDocument = LayoutDocument(surface:try surface.changingLayingOffset(globalMM:50),layers:[.init()])
        let after = CombinedQuantityCalculator.calculate(works:[work],catalogue:catalogue)
        XCTAssertEqual(before.supplies.first { $0.name == "Fourrure" }?.quantity,after.supplies.first { $0.name == "Fourrure" }?.quantity)
        XCTAssertEqual(try XCTUnwrap(after.supplies.first { $0.name.hasPrefix("Isolation") }?.quantity),24.01,accuracy:0.000001)
        XCTAssertEqual(try XCTUnwrap(before.supplies.first { $0.name.hasPrefix("BA13") }?.quantity),10)
        XCTAssertEqual(try XCTUnwrap(after.supplies.first { $0.name.hasPrefix("BA13") }?.quantity),9)
        XCTAssertEqual(work.ceilingConfiguration,configuration)
    }

    func testEmptyProjectAcceptsUnorganizedWorkWithWorkbookAndCopiesMetadata() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("projects.json"), store = ProjectStore(fileURL: url)
        let project = try store.createProject(name: "Plateau", client: "", address: "", notes: "")
        let work = try store.createConfiguredWork(projectID: project, name: "Plafond plateau", type: .ceilingOnFurring,
            payload: .ceiling(.init(length: 4, width: 2.5)), roomID: nil, newRoomName: nil,
            document: componentDocument(kind: .ceiling))
        XCTAssertTrue(store.project(id: project)!.rooms.isEmpty)
        XCTAssertEqual(store.project(id: project)!.works[0].components.count, 1)
        try store.updateWorkOrganization(projectID: project, workID: work, roomID: nil, level: "RDC", zone: "Logement A")
        let copy = try store.duplicateWork(projectID: project, workID: work)
        let loaded = try XCTUnwrap(ProjectStore(fileURL: url).project(id: project))
        XCTAssertEqual(loaded.works.first { $0.id == copy }?.level, "RDC")
        XCTAssertEqual(loaded.works.first { $0.id == copy }?.zone, "Logement A")
        XCTAssertNil(loaded.works.first { $0.id == copy }?.roomID)
    }

    func testOptionalOrganizationPreservesWorkbookAndFiltersWithoutDuplicates() throws {
        let f = try adjacencyFixture()
        let components = f.ceiling
        let links = f.project.ceilingWallLinks
        try f.store.updateWorkOrganization(projectID: f.projectID, workID: f.ceilingWorkID, roomID: nil, level: "1er étage", zone: "Appartement 2")
        XCTAssertEqual(f.ceiling, components)
        XCTAssertEqual(f.project.ceilingWallLinks, links)
        XCTAssertEqual(f.project.filteredWorks(level: "1er étage").map(\.id), [f.ceilingWorkID])
        XCTAssertEqual(f.project.filteredWorks(zone: "Appartement 2").map(\.id), [f.ceilingWorkID])
        XCTAssertTrue(f.project.filteredWorks(roomID: f.roomID, level: "1er étage").isEmpty)
        XCTAssertEqual(f.project.filteredWorks().count, 2)
        let reloaded = try XCTUnwrap(ProjectStore(fileURL: f.url).project(id: f.projectID))
        XCTAssertEqual(reloaded.works.first { $0.id == f.ceilingWorkID }?.level, "1er étage")
        XCTAssertEqual(reloaded.works.first { $0.id == f.ceilingWorkID }?.components, [components])
        try f.store.updateWorkOrganization(projectID: f.projectID, workID: f.ceilingWorkID, roomID: f.roomID, level: nil, zone: nil)
        XCTAssertEqual(f.ceiling, components)
        XCTAssertEqual(f.project.works.first { $0.id == f.ceilingWorkID }?.roomID, f.roomID)
    }

    func testWorkbookPartsPersistIndependentlyAndRenameWithoutChangingIdentity() throws {
        for kind in [LayoutSupportKind.wall, .ceiling] {
            let f = try adjacencyFixture()
            let workID = kind == .wall ? f.wallWorkID : f.ceilingWorkID
            let original = try XCTUnwrap(f.project.works.first { $0.id == workID }?.components.first)
            let secondID = try f.store.addComponent(projectID: f.projectID, workID: workID, name: "Partie B")
            let thirdID = try f.store.addComponent(projectID: f.projectID, workID: workID, name: "Partie C")
            var second = componentDocument(kind: kind)
            second.surface.name = "Partie B"
            second.surface.contour[1].x = 5000; second.surface.contour[2].x = 5000
            var third = componentDocument(kind: kind)
            third.surface.name = "Partie C"
            third.surface.contour[2].y = 3000; third.surface.contour[3].y = 3000
            try f.store.saveComponentPlan(projectID: f.projectID, workID: workID, componentID: secondID, sideRoomID: nil, document: second)
            try f.store.saveComponentPlan(projectID: f.projectID, workID: workID, componentID: thirdID, sideRoomID: nil, document: third)
            let beforeRename = try XCTUnwrap(f.project.works.first { $0.id == workID }?.components.first { $0.id == secondID })
            try f.store.renameComponent(projectID: f.projectID, workID: workID, componentID: secondID, name: "Mur baie vitrée")
            XCTAssertThrowsError(try f.store.renameComponent(projectID: f.projectID, workID: workID, componentID: thirdID, name: "Mur baie vitrée"))
            XCTAssertThrowsError(try f.store.renameComponent(projectID: f.projectID, workID: workID, componentID: thirdID, name: " "))
            let loaded = try XCTUnwrap(ProjectStore(fileURL: f.url).project(id: f.projectID))
            let parts = try XCTUnwrap(loaded.works.first { $0.id == workID }?.components)
            XCTAssertEqual(parts.count, 3)
            XCTAssertEqual(parts[0], original)
            XCTAssertEqual(parts[1].id, secondID)
            XCTAssertEqual(parts[1].name, "Mur baie vitrée")
            XCTAssertEqual(parts[1].surface?.name, "Mur baie vitrée")
            XCTAssertEqual(parts[1].surface?.contour, second.surface.contour)
            XCTAssertEqual(parts[1].plans, beforeRename.plans)
            XCTAssertEqual(parts[1].geometryRevision, beforeRename.geometryRevision)
            XCTAssertEqual(parts[2].surface?.contour, third.surface.contour)
            XCTAssertEqual(loaded.ceilingWallLinks, f.project.ceilingWallLinks)
        }
    }

    func testRoomQuantitySelectionUsesOwnersAndIncludesEmptyRoomsWithoutDuplication() throws {
        let f = try adjacencyFixture()
        let other = try f.store.createRoom(projectID: f.projectID, name: "Bureau")
        let empty = try f.store.createRoom(projectID: f.projectID, name: "Vide")
        var project = f.project
        project.works[0].linkedRoomIDs = [other]
        XCTAssertTrue(project.quantityWorks(in: []).isEmpty)
        XCTAssertTrue(project.quantityWorks(in: [empty]).isEmpty)
        XCTAssertTrue(project.quantityWorks(in: [other]).isEmpty)
        XCTAssertEqual(project.quantityWorks(in: [f.roomID]), project.ownedWorks(in: f.roomID))
        XCTAssertEqual(project.quantityWorks(in: [f.roomID, other]), project.works)
        XCTAssertEqual(project.quantityWorks(in: Set(project.rooms.map(\.id))), project.works)
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let selected = CombinedQuantityCalculator.calculate(works: project.quantityWorks(in: [f.roomID, other, empty]), catalogue: catalogue)
        let total = CombinedQuantityCalculator.calculate(works: project.works, catalogue: catalogue)
        XCTAssertEqual(selected.totalArea, total.totalArea)
        XCTAssertEqual(selected.supplies.map(\.quantity), total.supplies.map(\.quantity))
        XCTAssertEqual(selected.supplies.map(\.name), total.supplies.map(\.name))
    }

    func testUnassignedLegacyWorksRemainExplicitlySelectable() throws {
        let f = try adjacencyFixture()
        var project = f.project
        project.works[0].roomID = nil
        XCTAssertEqual(project.quantityWorks(in: [f.roomID]).count, 1)
        XCTAssertEqual(project.quantityWorks(in: [], includeUnassigned: true).count, 1)
        XCTAssertEqual(project.quantityWorks(in: [f.roomID], includeUnassigned: true), project.works)
    }

    func testNewConfiguredWorkAllowsNoRoomAndCreatesOrReusesNamedRoomAtomically() throws {
        let f = try adjacencyFixture()
        let before = f.project
        let unassigned = try f.store.createConfiguredWork(projectID: f.projectID, name: "Sans pièce", type: .ceilingOnFurring,
            payload: .ceiling(.init()), roomID: nil, newRoomName: " ")
        XCTAssertNil(f.project.works.first { $0.id == unassigned }?.roomID)
        XCTAssertEqual(f.project.rooms, before.rooms)
        let first = try f.store.createConfiguredWork(projectID: f.projectID, name: "Bureau plafond", type: .ceilingOnFurring,
            payload: .ceiling(.init()), roomID: nil, newRoomName: "Bureau")
        let second = try f.store.createConfiguredWork(projectID: f.projectID, name: "Bureau autre plafond", type: .ceilingOnFurring,
            payload: .ceiling(.init()), roomID: nil, newRoomName: " bureau ")
        XCTAssertEqual(f.project.rooms.count, before.rooms.count + 1)
        XCTAssertNotNil(f.project.works.first { $0.id == first }?.roomID)
        XCTAssertEqual(f.project.works.first { $0.id == first }?.roomID, f.project.works.first { $0.id == second }?.roomID)
        let reloaded = try XCTUnwrap(ProjectStore(fileURL: f.url).project(id: f.projectID))
        XCTAssertEqual(reloaded.rooms, f.project.rooms)
        XCTAssertEqual(reloaded.works.map(\.roomID), f.project.works.map(\.roomID))
    }

    private func componentDocument(kind: LayoutSupportKind = .wall) -> LayoutDocument {
        LayoutDocument(surface: Surface2D(name: "Mur A", kind: kind, contour: [
            .init(x: 0, y: 0), .init(x: 4000, y: 0), .init(x: 4000, y: 2500), .init(x: 0, y: 2500)
        ]), layers: [.init(furring: .init(parallelToBoards: true, spacing: 600, offset: 100))])
    }

    @MainActor private struct AdjacencyFixture {
        let store: ProjectStore
        let url: URL
        let projectID: UUID
        let roomID: UUID
        let ceilingWorkID: UUID
        let wallWorkID: UUID
        let ceilingID: UUID
        let wallID: UUID
        var project: ProjectItem { store.project(id: projectID)! }
        var ceiling: WorkComponentRecord { project.works.first { $0.id == ceilingWorkID }!.components[0] }
        var wall: WorkComponentRecord { project.works.first { $0.id == wallWorkID }!.components[0] }
        func resizedCeiling(_ width: Double) -> LayoutDocument {
            var result = ceiling.document(for: ceiling.plans[0])!
            result.surface.contour[1].x = width; result.surface.contour[2].x = width
            return result
        }
        func save(_ document: LayoutDocument, decision: ComponentAdjacencyDecision = .undecided, review: ComponentAdjacencyReview? = nil) throws {
            try store.saveComponentPlan(projectID: projectID, workID: ceilingWorkID, componentID: ceilingID,
                sideRoomID: nil, document: document, expectedGeometryRevision: ceiling.geometryRevision,
                adjacencyDecision: decision, reviewedAdjacency: review)
        }
        func review(_ document: LayoutDocument) throws -> ComponentAdjacencyReview {
            try store.reviewComponentPlan(projectID: projectID, componentID: ceilingID, document: document)
        }
    }

    private func adjacencyFixture() throws -> AdjacencyFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json"), store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Relations", client: "", address: "", notes: "")
        let roomID = try store.createRoom(projectID: projectID, name: "Salon")
        var wall = componentDocument()
        wall.surface.openings = [.init(kind: .window, contour: [.init(x: 500, y: 500), .init(x: 1500, y: 500), .init(x: 1500, y: 1500), .init(x: 500, y: 1500)])]
        let wallWorkID = try store.createConfiguredWork(projectID: projectID, name: "Doublage", type: .peripheralLiningStuds,
            payload: .peripheralLining(.init(height: 2.5, enteredLength: 4)), roomID: roomID, newRoomName: nil, document: wall)
        let ceilingWorkID = try store.createConfiguredWork(projectID: projectID, name: "Plafond", type: .ceilingOnFurring,
            payload: .ceiling(.init(length: 4, width: 2.5)), roomID: roomID, newRoomName: nil, document: componentDocument(kind: .ceiling))
        let project = try XCTUnwrap(store.project(id: projectID))
        let ceilingID = try XCTUnwrap(project.works.first { $0.id == ceilingWorkID }?.components.first?.id)
        let wallID = try XCTUnwrap(project.works.first { $0.id == wallWorkID }?.components.first?.id)
        try store.linkCeilingToWall(projectID: projectID, ceilingComponentID: ceilingID, edgeIndex: 0,
                                   wallComponentID: wallID, roomID: roomID)
        return .init(store: store, url: url, projectID: projectID, roomID: roomID,
            ceilingWorkID: ceilingWorkID, wallWorkID: wallWorkID, ceilingID: ceilingID, wallID: wallID)
    }

    func testCeilingWallChangeRequiresDecisionAndRefusalPreservesWallAfterReload() throws {
        let f = try adjacencyFixture(), before = f.project, wall = f.wall
        let document = f.resizedCeiling(4200), review = try f.review(document)
        XCTAssertEqual(review.changes.count, 1)
        XCTAssertEqual(review.changes.first?.oldLengthMM, 4000)
        XCTAssertEqual(review.changes.first?.proposedLengthMM, 4200)
        XCTAssertTrue(review.canApply)
        XCTAssertThrowsError(try f.save(document))
        XCTAssertEqual(f.project, before, "No partial save before confirmation")
        XCTAssertThrowsError(try f.store.updateLinkedLayout(projectID: f.projectID, workID: f.ceilingWorkID, document: document))
        XCTAssertEqual(f.project, before, "Legacy layout entry must not bypass confirmation")
        try f.save(document, decision: .keepWalls, review: review)
        XCTAssertEqual(f.wall, wall)
        XCTAssertEqual(f.ceiling.surface?.bounds.width, 4200)
        let reloaded = try XCTUnwrap(ProjectStore(fileURL: f.url).project(id: f.projectID))
        XCTAssertEqual(reloaded.works.flatMap(\.components), f.project.works.flatMap(\.components))
        XCTAssertEqual(reloaded.ceilingWallLinks, f.project.ceilingWallLinks)
        XCTAssertNotNil(ComponentAdjacency.warning(for: reloaded.ceilingWallLinks![0], in: reloaded))
        XCTAssertTrue(try f.review(document).changes.isEmpty, "Do not repeatedly ask after an explicit refusal with no further change")
    }

    func testAcceptedCeilingWallChangeIsAtomicAndPreservesOpeningsAndFrame() throws {
        let f = try adjacencyFixture(), beforeWall = f.wall
        let document = f.resizedCeiling(4200), review = try f.review(document)
        try f.save(document, decision: .applyWalls, review: review)
        XCTAssertEqual(f.wall.surface?.bounds.width, 4200)
        XCTAssertEqual(f.wall.surface?.bounds.height, 2500)
        XCTAssertEqual(f.wall.surface?.openings, beforeWall.surface?.openings)
        XCTAssertEqual(f.wall.framing, beforeWall.framing)
        XCTAssertEqual(f.wall.plans, beforeWall.plans, "Dependent plans are invalidated, not rewritten or scaled")
        XCTAssertEqual(f.wall.geometryRevision, beforeWall.geometryRevision + 1)
        XCTAssertLessThan(f.wall.plans[0].geometryRevision, f.wall.geometryRevision)
        XCTAssertNil(ComponentAdjacency.warning(for: f.project.ceilingWallLinks![0], in: f.project))
        XCTAssertEqual(f.project.works.first { $0.id == f.wallWorkID }?.doublageConfiguration?.enteredLength, 4,
                       "Business quantity is marked stale, not silently overwritten")
        XCTAssertEqual(f.project.works.first { $0.id == f.wallWorkID }?.layoutNeedsRecalculation, true)
        let reloaded = try XCTUnwrap(ProjectStore(fileURL: f.url).project(id: f.projectID))
        XCTAssertEqual(reloaded.works.flatMap(\.components), f.project.works.flatMap(\.components))
        XCTAssertEqual(reloaded.ceilingWallLinks, f.project.ceilingWallLinks)
    }

    func testStaleCeilingWallConfirmationCannotOverwriteNewWallGeometryOrLinks() throws {
        let f = try adjacencyFixture(), document = f.resizedCeiling(4200), review = try f.review(document)
        var changedWall = try XCTUnwrap(f.wall.document(for: f.wall.plans[0]))
        changedWall.layers[0].furring?.offset += 50
        try f.store.saveComponentPlan(projectID: f.projectID, workID: f.wallWorkID, componentID: f.wallID,
            sideRoomID: nil, document: changedWall, expectedGeometryRevision: f.wall.geometryRevision)
        let before = f.project
        XCTAssertThrowsError(try f.save(document, decision: .applyWalls, review: review))
        XCTAssertEqual(f.project, before)
        let fresh = try f.review(document)
        try f.store.removeCeilingWallLink(projectID: f.projectID, linkID: fresh.changes[0].id)
        XCTAssertThrowsError(try f.save(document, decision: .applyWalls, review: fresh))
        XCTAssertEqual(f.ceiling.surface?.bounds.width, 4000)
    }

    func testCeilingTopologyEditRequiresRebindingEvenWhenVertexCountIsRestored() throws {
        let f = try adjacencyFixture()
        var document = f.resizedCeiling(4200)
        document.surface = try document.surface.changingVertex(insertAfter: 0, point: .init(x: 2000, y: 0))
        document.surface = try document.surface.changingVertex(remove: 1)
        XCTAssertEqual(document.surface.contour.count, 4)
        let review = try f.review(document)
        XCTAssertEqual(review.changes.count, 1)
        XCTAssertFalse(review.canApply)
        XCTAssertThrowsError(try f.save(document, decision: .applyWalls, review: review))
        try f.save(document, decision: .keepWalls, review: review)
        XCTAssertEqual(f.wall.surface?.bounds.width, 4000)
        XCTAssertNotNil(ComponentAdjacency.warning(for: f.project.ceilingWallLinks![0], in: f.project))
        let copiedID = try f.store.duplicateProject(id: f.projectID)
        let copied = try XCTUnwrap(f.store.project(id: copiedID))
        XCTAssertNotNil(ComponentAdjacency.warning(for: copied.ceilingWallLinks![0], in: copied))
    }

    func testCeilingWallLinksRemapOnProjectCopyButNotOnSingleWorkCopyOrDelete() throws {
        let f = try adjacencyFixture()
        let copyID = try f.store.duplicateProject(id: f.projectID)
        let copy = try XCTUnwrap(ProjectStore(fileURL: f.url).project(id: copyID))
        let link = try XCTUnwrap(copy.ceilingWallLinks?.first)
        XCTAssertNotEqual(link.id, f.project.ceilingWallLinks![0].id)
        XCTAssertNotEqual(link.ceilingComponentID, f.ceilingID)
        XCTAssertNotEqual(link.wallComponentID, f.wallID)
        XCTAssertTrue(copy.rooms.contains { $0.id == link.roomID })
        XCTAssertNil(ComponentAdjacency.warning(for: link, in: copy))
        let duplicateID = try f.store.duplicateWork(projectID: f.projectID, workID: f.wallWorkID)
        let duplicate = try XCTUnwrap(f.project.works.first { $0.id == duplicateID })
        XCTAssertFalse(f.project.ceilingWallLinks!.contains { $0.wallComponentID == duplicate.components[0].id })
        try f.store.deleteWork(projectID: f.projectID, workID: f.wallWorkID)
        XCTAssertTrue(f.project.ceilingWallLinks!.isEmpty)
        XCTAssertEqual(f.project.works.first { $0.id == duplicateID }?.components[0], duplicate.components[0])
    }

    func testWallAdjustmentBlocksOpeningElectricityAndLockedContours() throws {
        let f = try adjacencyFixture()
        let tooShort = f.resizedCeiling(1000), review = try f.review(tooShort)
        XCTAssertFalse(review.canApply, "A window cannot be silently cropped")
        XCTAssertNotNil(review.changes[0].reason)
        var wall = f.wall
        wall.surface?.openings = []
        wall.plans[0].lighting = .init(count: 1, positions: [.init(x: 3900, y: 1500)], kinds: [.socket])
        XCTAssertThrowsError(try ComponentAdjacency.resizedWall(wall, width: 3000))
        wall.plans[0].lighting = nil
        var intent = LayoutContourIntent(sketch: wall.surface!.contour)
        intent.lockedLengthIndices = [0]; intent.userMeasuredLengths[0] = 4000
        wall.surface?.contourIntent = intent
        XCTAssertThrowsError(try ComponentAdjacency.resizedWall(wall, width: 4200))
        XCTAssertEqual(f.wall.surface?.bounds.width, 4000)
    }

    func testSlopingCeilingUsesHorizontalWallSpanAndAdapterRequiresExplicitEvidence() throws {
        var surface = componentDocument(kind: .ceiling).surface
        surface.localFrame = .init(origin: .init(x: 0, y: 0, z: 0),
            axisX: .init(x: 0.8, y: 0.6, z: 0), axisY: .init(x: 0, y: 0, z: 1))
        XCTAssertEqual(ComponentAdjacency.wallSpan(of: surface, edge: 0)!, 3200, accuracy: 0.001)
        let f = try adjacencyFixture()
        XCTAssertThrowsError(try f.store.linkCeilingToWall(projectID: f.projectID, ceilingComponentID: f.ceilingID,
            edgeIndex: 0, wallComponentID: f.wallID, roomID: f.roomID, origin: .scan))
        try f.store.linkCeilingToWall(projectID: f.projectID, ceilingComponentID: f.ceilingID,
            edgeIndex: 0, wallComponentID: f.wallID, roomID: f.roomID, origin: .scan, sourceObservationID: "scan-room/ceiling-edge/wall")
        XCTAssertEqual(f.project.ceilingWallLinks?.first?.origin, .scan)
        let otherRoom = try f.store.createRoom(projectID: f.projectID, name: "Autre")
        XCTAssertThrowsError(try f.store.linkCeilingToWall(projectID: f.projectID, ceilingComponentID: f.ceilingID,
            edgeIndex: 0, wallComponentID: f.wallID, roomID: otherRoom))
        try f.store.assignWork(projectID: f.projectID, workID: f.ceilingWorkID, ownerRoomID: otherRoom)
        XCTAssertTrue(try f.review(f.resizedCeiling(4200)).canApply, "Organization does not change an explicit physical correspondence")
        XCTAssertNil(ComponentAdjacency.warning(for: f.project.ceilingWallLinks![0], in: f.project))
    }

    func testConfiguredWorkCreatesExplicitRoomAtomicallyAndRenameKeepsIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        let workID = try store.createConfiguredWork(projectID: projectID, name: "Salon - Doublage périphérique",
            type: .peripheralLiningStuds, payload: .peripheralLining(.init(height: 2.5, enteredLength: 12)), roomID: nil, newRoomName: "Salon")
        let room = try XCTUnwrap(store.project(id: projectID)?.rooms.first)
        XCTAssertEqual(store.project(id: projectID)?.works.first?.roomID, room.id)
        try store.renameRoom(projectID: projectID, roomID: room.id, name: "Séjour")
        XCTAssertEqual(store.project(id: projectID)?.works.first?.id, workID)
        XCTAssertEqual(store.project(id: projectID)?.works.first?.name, "Séjour - Doublage périphérique")
        XCTAssertThrowsError(try store.createConfiguredWork(projectID: projectID, name: "Séjour - Doublage périphérique",
            type: .peripheralLiningStuds, payload: .peripheralLining(.init()), roomID: nil, newRoomName: "Pièce fantôme"))
        XCTAssertEqual(store.project(id: projectID)?.rooms.count, 1)
        let reloaded = ProjectStore(fileURL: url)
        XCTAssertEqual(reloaded.project(id: projectID)?.rooms.first?.id, room.id)
        XCTAssertEqual(reloaded.project(id: projectID)?.ownedWorks(in: room.id).map(\.id), [workID])
    }

    func testFourComponentsKeepWholeWorkQuantityAndUnknownGeometry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        let id = try store.createWork(projectID: projectID, name: "Doublage", type: .peripheralLiningStuds,
            doublageConfiguration: .init(height: 2.5, enteredLength: 16))
        var componentIDs: [UUID] = []
        for name in ["Mur A", "Mur B", "Mur C", "Mur D"] { componentIDs.append(try store.addComponent(projectID: projectID, workID: id, name: name)) }
        try store.saveComponentPlan(projectID: projectID, workID: id, componentID: componentIDs[0], sideRoomID: nil, document: componentDocument())
        let work = try XCTUnwrap(ProjectStore(fileURL: url).project(id: projectID)?.works.first)
        XCTAssertEqual(work.components.count, 4)
        XCTAssertNotNil(work.components[0].surface)
        XCTAssertNil(work.components[1].surface)
        XCTAssertNil(work.layoutDocument, "A multi-component work must never expose one arbitrary wall as its total layout")
        XCTAssertEqual(work.doublageConfiguration?.area, 40)
        XCTAssertEqual(work.components[0].document(for: work.components[0].plans[0]), componentDocumentIdentityAdjusted(work.components[0]))
        XCTAssertThrowsError(try store.saveComponentPlan(projectID: projectID, workID: id, componentID: componentIDs[0], sideRoomID: nil,
            document: componentDocument(), expectedGeometryRevision: 0))
        XCTAssertThrowsError(try store.saveComponentPlan(projectID: projectID, workID: id, componentID: componentIDs[0], sideRoomID: nil,
            document: componentDocument(kind: .ceiling)))
    }

    private func componentDocumentIdentityAdjusted(_ component: WorkComponentRecord) -> LayoutDocument? {
        guard let surface = component.surface, let plan = component.plans.first else { return nil }
        var layers = plan.layers; layers[0].furring = component.framing
        return LayoutDocument(surface: surface, layers: layers, lighting: plan.lighting)
    }

    func testPartitionOwnerSidesSharedGeometryAndCopyLinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        let bureau = try store.createRoom(projectID: projectID, name: "Bureau", floorAreaM2: 9)
        let salon = try store.createRoom(projectID: projectID, name: "Salon", floorAreaM2: 30)
        let id = try store.createWork(projectID: projectID, name: "Cloison", type: .distributionPartition, cloisonDistributionConfiguration: .init())
        XCTAssertEqual(store.suggestedPartitionOwner(projectID: projectID, roomIDs: [salon, bureau]), bureau)
        try store.assignWork(projectID: projectID, workID: id, ownerRoomID: bureau, adjacentRoomIDs: [salon])
        let componentID = try store.addComponent(projectID: projectID, workID: id, name: "Cloison A")
        var document = componentDocument()
        document.surface.openings = [.init(kind: .window, contour: [.init(x: 500, y: 900), .init(x: 1000, y: 900), .init(x: 1000, y: 1500), .init(x: 500, y: 1500)])]
        try store.saveComponentPlan(projectID: projectID, workID: id, componentID: componentID, sideRoomID: bureau, document: document)
        var component = try XCTUnwrap(store.project(id: projectID)?.works.first?.components.first)
        let opposite = try XCTUnwrap(component.document(for: .init(sideRoomID: salon)))
        XCTAssertEqual(opposite.surface.openings[0].id, document.surface.openings[0].id)
        XCTAssertEqual(opposite.surface.openings[0].contour[0].x, -500)
        XCTAssertEqual(opposite.surface.mirroredComponentSide(), document.surface)
        XCTAssertEqual(opposite.layers[0].furring?.offset, -100)
        try store.saveComponentPlan(projectID: projectID, workID: id, componentID: componentID, sideRoomID: salon, document: opposite)
        component = try XCTUnwrap(store.project(id: projectID)?.works.first?.components.first)
        XCTAssertEqual(component.geometryRevision, 1, "Opening the opposite side must not modify physical geometry")
        XCTAssertEqual(component.plans.count, 2)
        XCTAssertTrue(component.plans.allSatisfy { $0.layers.allSatisfy { $0.furring == nil } })
        XCTAssertEqual(store.project(id: projectID)?.ownedWorks(in: bureau).count, 1)
        XCTAssertEqual(store.project(id: projectID)?.ownedWorks(in: salon).count, 0)
        XCTAssertEqual(store.project(id: projectID)?.linkedWorks(in: salon).map(\.id), [id])
        var changed = document; changed.surface.contour[1].x = 4100
        try store.saveComponentPlan(projectID: projectID, workID: id, componentID: componentID, sideRoomID: bureau, document: changed)
        component = try XCTUnwrap(store.project(id: projectID)?.works.first?.components.first)
        XCTAssertEqual(component.plans.first { $0.sideRoomID == salon }?.geometryRevision, 1)
        XCTAssertEqual(component.geometryRevision, 2)
        let copyID = try store.duplicateProject(id: projectID)
        let copied = try XCTUnwrap(ProjectStore(fileURL: url).project(id: copyID))
        let copyWork = try XCTUnwrap(copied.works.first)
        XCTAssertNotEqual(copyWork.id, id)
        XCTAssertEqual(copied.rooms.first { $0.name == "Bureau" }?.id, copyWork.roomID)
        XCTAssertNotEqual(copyWork.components[0].id, componentID)
        XCTAssertTrue(copyWork.components[0].plans.allSatisfy { copied.rooms.map(\.id).contains($0.sideRoomID!) })
        XCTAssertNotEqual(copyWork.components[0].surface?.openings[0].id, document.surface.openings[0].id)
        try store.updateWorkOrganization(projectID: projectID, workID: id, roomID: nil, level: "RDC", zone: nil)
        let detached = try XCTUnwrap(ProjectStore(fileURL: url).project(id: projectID)?.works.first)
        XCTAssertNil(detached.roomID)
        XCTAssertEqual(detached.components, [component], "Removing organization must preserve both existing sides and their shared frame")
    }

    func testFutureArchiveCannotBeOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("projects.json")
        let data = Data("{\"schemaVersion\":999,\"projects\":[]}".utf8)
        try data.write(to: url)
        let store = ProjectStore(fileURL: url)
        XCTAssertNotNil(store.lastError)
        XCTAssertThrowsError(try store.createProject(name: "Test", client: "", address: "", notes: ""))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testMovingSharedFrameRightOnOneSideMovesItLeftOnTheOtherAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        let a = try store.createRoom(projectID: projectID, name: "A", floorAreaM2: 9)
        let b = try store.createRoom(projectID: projectID, name: "B", floorAreaM2: 20)
        let workID = try store.createWork(projectID: projectID, name: "Cloison", type: .distributionPartition, cloisonDistributionConfiguration: .init())
        try store.assignWork(projectID: projectID, workID: workID, ownerRoomID: a, adjacentRoomIDs: [b])
        let componentID = try store.addComponent(projectID: projectID, workID: workID, name: "Cloison A")
        var first = componentDocument()
        first.lighting = .init(count: 1, positions: [.init(x: 700, y: 400)], kinds: [.socket])
        try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: componentID, sideRoomID: a, document: first)
        var component = try XCTUnwrap(store.project(id: projectID)?.works.first?.components.first)
        let beforeB = try XCTUnwrap(component.document(for: .init(sideRoomID: b)))
        XCTAssertNil(beforeB.lighting, "A socket must not appear on the opposite side")
        try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: componentID, sideRoomID: b, document: beforeB)
        let beforeRevision = component.geometryRevision
        first.layers[0].furring?.offset += 50 // 5 cm right as seen from A.
        try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: componentID, sideRoomID: a, document: first, expectedGeometryRevision: beforeRevision)
        component = try XCTUnwrap(ProjectStore(fileURL: url).project(id: projectID)?.works.first?.components.first)
        let planA = try XCTUnwrap(component.plans.first { $0.sideRoomID == a })
        let planB = try XCTUnwrap(component.plans.first { $0.sideRoomID == b })
        let afterA = try XCTUnwrap(component.document(for: planA))
        var afterB = try XCTUnwrap(component.document(for: planB))
        XCTAssertEqual(afterA.layers[0].furring?.offset, 150)
        XCTAssertEqual(afterB.layers[0].furring?.offset, -150)
        let frameA = try LayoutFurringEngine.calculate(surface: afterA.surface, layer: afterA.layers[0])
        let frameB = try LayoutFurringEngine.calculate(surface: afterB.surface, layer: afterB.layers[0])
        XCTAssertEqual(frameA.lines.map { $0.start.x }.sorted(), frameB.lines.map { -$0.start.x }.sorted())
        XCTAssertEqual((afterB.layers[0].furring?.offset ?? 0) - (beforeB.layers[0].furring?.offset ?? 0), -50)
        XCTAssertEqual(afterA.surface, first.surface, "Moving framing must not modify the contour")
        XCTAssertEqual(afterA.lighting, first.lighting)
        XCTAssertNil(afterB.lighting)
        XCTAssertEqual(component.geometryRevision, beforeRevision + 1)
        XCTAssertLessThan(planB.geometryRevision, component.geometryRevision)
        XCTAssertThrowsError(try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: componentID, sideRoomID: b, document: beforeB, expectedGeometryRevision: beforeRevision))
        // The reverse direction works too: right 5 cm on B restores the initial A offset.
        afterB.layers[0].furring?.offset += 50
        try store.saveComponentPlan(projectID: projectID, workID: workID, componentID: componentID, sideRoomID: b, document: afterB, expectedGeometryRevision: component.geometryRevision)
        component = try XCTUnwrap(ProjectStore(fileURL: url).project(id: projectID)?.works.first?.components.first)
        XCTAssertEqual(component.document(for: planA)?.layers[0].furring?.offset, 100)
    }

    func testLinkedLayoutDoesNotWriteToStandaloneDraftOrLibrary() throws {
        let suite = "linked-layout-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = Data("preserve".utf8)
        defaults.set(draft, forKey: "plaquisto.tools.layout.draft.v1")
        let model = LayoutEditorModel(defaults: defaults, persistsStandaloneLibrary: false)
        model.apply(componentDocument())
        model.startNew()
        XCTAssertEqual(defaults.data(forKey: "plaquisto.tools.layout.draft.v1"), draft)
        XCTAssertNil(defaults.data(forKey: "plaquisto.tools.layout.library.v1"))
    }

    func testProjectDuplicationRelinksOpeningsToCopiedWorksAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        let projectID = try store.createProject(name: "Test duplication", client: "", address: "", notes: "")
        let sourceID = try store.createWork(projectID: projectID, name: "Salon - Doublage périphérique",
            type: .peripheralLiningStuds, doublageConfiguration: .init(height: 2.6, enteredLength: 4))
        let openingID = try store.createWork(projectID: projectID, name: "Salon - Ouvertures",
            type: .openings, openingConfiguration: .init(sourceWorkID: sourceID))
        let copyID = try store.duplicateProject(id: projectID)
        let reloaded = ProjectStore(fileURL: url)
        let copy = try XCTUnwrap(reloaded.project(id: copyID))
        let copiedSource = try XCTUnwrap(copy.works.first { $0.type == .peripheralLiningStuds })
        let copiedOpening = try XCTUnwrap(copy.works.first { $0.type == .openings })
        XCTAssertNotEqual(copiedSource.id, sourceID)
        XCTAssertEqual(copiedOpening.openingConfiguration?.sourceWorkID, copiedSource.id)
        XCTAssertEqual(reloaded.project(id: projectID)?.works.first { $0.id == openingID }?.openingConfiguration?.sourceWorkID, sourceID)
    }

    func testProjectsAndWorksSurviveAStoreReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = ProjectStore(fileURL: fileURL)
        let projectID = try firstStore.createProject(name: "Maison Martin", client: "Martin", address: "1 rue Test", notes: "Rénovation")
        let configuration = CeilingConfiguration(
            length: 8,
            width: 5,
            support: "Plancher bois horizontal",
            plenum: 30,
            insulationID: "INSULATION-TEST",
            insulationThickness: 100,
            insulationLayers: 2,
            secondInsulationID: "INSULATION-TEST",
            secondInsulationThickness: 60,
            firstInsulationLocation: "between",
            secondInsulationLocation: "below"
        )
        let workID = try firstStore.createWork(projectID: projectID, name: "Plafond séjour", type: .ceilingOnFurring, configuration: configuration)

        let reloadedStore = ProjectStore(fileURL: fileURL)
        let reloadedProject = try XCTUnwrap(reloadedStore.project(id: projectID))
        let reloadedWork = try XCTUnwrap(reloadedProject.works.first { $0.id == workID })
        XCTAssertEqual(reloadedProject.name, "Maison Martin")
        XCTAssertEqual(reloadedWork.ceilingConfiguration, configuration)
    }

    func testUpdatingAWorkDoesNotCreateADuplicate() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Test", client: "", address: "", notes: "")
        let workID = try store.createWork(projectID: projectID, name: "Plafond", type: .ceilingOnFurring, configuration: CeilingConfiguration())
        let work = try XCTUnwrap(store.project(id: projectID)?.works.first)
        var changed = try XCTUnwrap(work.ceilingConfiguration)
        changed.length = 12

        try store.updateWork(work, configuration: changed)

        let works = try XCTUnwrap(store.project(id: projectID)?.works)
        XCTAssertEqual(works.count, 1)
        XCTAssertEqual(works.first?.id, workID)
        XCTAssertEqual(works.first?.ceilingConfiguration?.length, 12)
    }

    func testModularCeilingUsesMetricCountsFromTheReferenceExample() {
        let configuration = ModularCeilingConfiguration(
            length: 8,
            width: 5,
            tileFormat: .square600,
            tileThicknessMM: 20,
            plenumCM: 15,
            wastePercent: 5
        )

        let result = ModularCeilingCalculator.calculate(configuration)

        XCTAssertEqual(result.area, 40)
        XCTAssertEqual(result.installedTiles, 126)
        XCTAssertEqual(result.fullTiles, 84)
        XCTAssertEqual(result.cutTiles, 42)
        XCTAssertEqual(result.orderedTiles, 133)
        XCTAssertEqual(result.mainRunnerLines, 4)
        XCTAssertEqual(result.mainRunnerLength, 32)
        XCTAssertEqual(result.mainRunnerBars, 10)
        XCTAssertEqual(result.crossTees1200Useful, 65)
        XCTAssertEqual(result.crossTees1200Ordered, 69)
        XCTAssertEqual(result.crossTees600Useful, 56)
        XCTAssertEqual(result.crossTees600Ordered, 59)
        XCTAssertEqual(result.perimeterAngleBars, 10)
        XCTAssertEqual(result.hangers, 28)
    }

    func testRectangularModularTilesDoNotUseSixHundredMillimeterCrossTees() {
        let configuration = ModularCeilingConfiguration(
            length: 8,
            width: 5,
            tileFormat: .rectangle600x1200,
            tileThicknessMM: 20,
            plenumCM: 15,
            wastePercent: 5
        )

        let result = ModularCeilingCalculator.calculate(configuration)

        XCTAssertEqual(result.installedTiles, 70)
        XCTAssertEqual(result.crossTees600Useful, 0)
        XCTAssertEqual(result.crossTees600Ordered, 0)
        XCTAssertEqual(result.crossTees1200Useful, 65)
    }

    func testModularCeilingSurvivesAStoreReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Bureaux", client: "", address: "", notes: "")
        let configuration = ModularCeilingConfiguration(
            length: 6.4,
            width: 4.2,
            tileFormat: .rectangle600x1200,
            tileThicknessMM: 20,
            plenumCM: 18,
            wastePercent: 7
        )
        let workID = try store.createWork(
            projectID: projectID,
            name: "Bureau - Plafond modulaire",
            type: .modularCeiling,
            modularCeilingConfiguration: configuration
        )

        let reloaded = ProjectStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.project(id: projectID)?.works.first(where: { $0.id == workID })?.modularCeilingConfiguration, configuration)
    }

    func testDefaultWorkNameUsesTheFirstAvailableNumber() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Test", client: "", address: "", notes: "")
        _ = try store.createWork(projectID: projectID, name: "Plafond sur fourrures 1", type: .ceilingOnFurring, configuration: CeilingConfiguration())

        XCTAssertEqual(store.defaultWorkName(projectID: projectID, type: .ceilingOnFurring), "Plafond sur fourrures 2")
    }

    func testDuplicateWorkNamesAreRejectedIgnoringCaseAndAccents() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Test", client: "", address: "", notes: "")
        _ = try store.createWork(projectID: projectID, name: "Cloison séjour", type: .distributionPartition, cloisonDistributionConfiguration: CloisonDistributionConfiguration())

        XCTAssertTrue(store.workNameExists(projectID: projectID, name: "  CLOISON SEJOUR  "))
        XCTAssertThrowsError(
            try store.createWork(projectID: projectID, name: "Cloison sejour", type: .distributionPartition, cloisonDistributionConfiguration: CloisonDistributionConfiguration())
        )
    }

    func testDuplicatingAWorkCopiesItsConfigurationWithANewIdentity() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Test", client: "", address: "", notes: "")
        var configuration = CeilingConfiguration()
        configuration.width = 7.5
        let originalID = try store.createWork(projectID: projectID, name: "Séjour", type: .ceilingOnFurring, configuration: configuration)

        let copyID = try store.duplicateWork(projectID: projectID, workID: originalID)

        let works = try XCTUnwrap(store.project(id: projectID)?.works)
        XCTAssertEqual(works.count, 2)
        XCTAssertNotEqual(copyID, originalID)
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.name, "Séjour – copie")
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.ceilingConfiguration, configuration)
    }

    func testCombinedQuantityAddsTheSelectedWorks() throws {
        let projectID = UUID()
        let now = Date()
        let first = WorkItem(id: UUID(), projectID: projectID, name: "A", type: .ceilingOnFurring, configuration: CeilingConfiguration(length: 5, width: 4), createdAt: now, updatedAt: now)
        let second = WorkItem(id: UUID(), projectID: projectID, name: "B", type: .ceilingOnFurring, configuration: CeilingConfiguration(length: 3, width: 2), createdAt: now, updatedAt: now)
        let fourrure = CeilingReferenceRecord(id: "QTY-FOURRURE", kind: "quantity_item", title: "Fourrure F45", summary: "", sourcePage: 0, status: "Publié", data: [
            "unit": .string("ml"),
            "values": .object(["simple_060": .number(2)])
        ])
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [fourrure], pareVapeur: [], regles: [])

        let result = CombinedQuantityCalculator.calculate(works: [first, second], catalogue: catalogue)

        XCTAssertEqual(result.totalArea, 26)
        XCTAssertEqual(result.supplies.first(where: { $0.name == "Fourrures F45/F47" })?.quantity, 52)
        let union = CombinedQuantityCalculator.calculate(works: [first, first, second], catalogue: catalogue)
        XCTAssertEqual(union.totalArea, result.totalArea)
        XCTAssertEqual(union.supplies.first(where: { $0.name == "Fourrures F45/F47" })?.quantity, 52)
    }

    func testDuplicatingAProjectCopiesItsWorksWithNewIdentities() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let originalProjectID = try store.createProject(name: "Maison", client: "Martin", address: "Paris", notes: "Test")
        let originalWorkID = try store.createWork(projectID: originalProjectID, name: "Séjour", type: .ceilingOnFurring, configuration: CeilingConfiguration(length: 6, width: 4))

        let copyID = try store.duplicateProject(id: originalProjectID)

        let copy = try XCTUnwrap(store.project(id: copyID))
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertEqual(copy.name, "Maison – copie")
        XCTAssertEqual(copy.client, "Martin")
        XCTAssertEqual(copy.works.count, 1)
        XCTAssertNotEqual(copy.works.first?.id, originalWorkID)
        XCTAssertEqual(copy.works.first?.projectID, copyID)
        XCTAssertEqual(copy.works.first?.ceilingConfiguration?.length, 6)
    }

    func testDoublageSurvivesReloadAndDuplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        var configuration = DoublageConfiguration(height: 2.5, enteredLength: 8)
        configuration.quantities = [DoublageQuantity(name: "Rails", quantity: 16.8, unit: "ml")]
        let workID = try store.createWork(
            projectID: projectID,
            name: "Doublage séjour",
            type: .peripheralLiningStuds,
            doublageConfiguration: configuration
        )
        let copyID = try store.duplicateWork(projectID: projectID, workID: workID)

        let reloaded = ProjectStore(fileURL: fileURL)
        let works = try XCTUnwrap(reloaded.project(id: projectID)?.works)
        XCTAssertEqual(works.count, 2)
        XCTAssertEqual(works.first(where: { $0.id == workID })?.doublageConfiguration?.area, 20)
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.doublageConfiguration, configuration)
    }

    func testDistributionPartitionSurvivesReloadAndDuplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        var configuration = CloisonDistributionConfiguration(height: 2.5, enteredLength: 4)
        configuration.quantities = [CloisonQuantity(name: "Rails R48", quantity: 8.4, unit: "ml")]
        let workID = try store.createWork(
            projectID: projectID,
            name: "Cloison chambre",
            type: .distributionPartition,
            cloisonDistributionConfiguration: configuration
        )
        let copyID = try store.duplicateWork(projectID: projectID, workID: workID)

        let reloaded = ProjectStore(fileURL: fileURL)
        let works = try XCTUnwrap(reloaded.project(id: projectID)?.works)
        XCTAssertEqual(works.count, 2)
        XCTAssertEqual(works.first(where: { $0.id == workID })?.cloisonDistributionConfiguration?.area, 10)
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.cloisonDistributionConfiguration, configuration)
    }

    func testOpeningsSurviveReloadAndDuplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        let configuration = OpeningConfiguration(
            context: OpeningContext(system: .furringLining, hsp: 2.50, spacing: 0.60),
            openings: [
                OpeningInput(kind: .window, width: 1.20, height: 1.05, name: "Fenêtre évier"),
                OpeningInput(kind: .frenchDoorOrBay, width: 1.80, height: 2.15)
            ]
        )
        let workID = try store.createWork(
            projectID: projectID,
            name: "Ouvertures séjour",
            type: .openings,
            openingConfiguration: configuration
        )
        let copyID = try store.duplicateWork(projectID: projectID, workID: workID)

        let reloaded = ProjectStore(fileURL: fileURL)
        let works = try XCTUnwrap(reloaded.project(id: projectID)?.works)
        XCTAssertEqual(works.first(where: { $0.id == workID })?.openingConfiguration, configuration)
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.openingConfiguration, configuration)
    }

    func testOpeningHeightSuggestionsReuseTheMatchingExistingWork() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")

        _ = try store.createWork(
            projectID: projectID,
            name: "Doublage séjour",
            type: .peripheralLiningStuds,
            doublageConfiguration: DoublageConfiguration(
                height: 2.62,
                layers: 2,
                firstSkin: [.init(facingID: "parement-ba13-standard")],
                secondSkin: [.init(facingID: "parement-ba13-hydrofuge")],
                insulationEnabled: true,
                insulationLayers: 1,
                firstInsulation: .init(familyID: "laine-verre", lambda: 0.032, thicknessMM: 100)
            )
        )
        _ = try store.createWork(
            projectID: projectID,
            name: "Cloison chambre",
            type: .distributionPartition,
            cloisonDistributionConfiguration: CloisonDistributionConfiguration(height: 2.48)
        )

        let suggestions = store.openingHeightSuggestions(projectID: projectID)

        XCTAssertEqual(suggestions[.railStudLining]?.height, 2.62)
        XCTAssertEqual(suggestions[.railStudLining]?.sourceWorkName, "Doublage séjour")
        XCTAssertEqual(suggestions[.railStudLining]?.frame, DoublageConfiguration().frame)
        XCTAssertEqual(try XCTUnwrap(suggestions[.railStudLining]?.minimumJoineryLiningDepth), 0.126, accuracy: 0.000_1)
        XCTAssertEqual(suggestions[.distributionPartition]?.height, 2.48)
        XCTAssertEqual(suggestions[.distributionPartition]?.sourceWorkName, "Cloison chambre")
        XCTAssertEqual(suggestions[.distributionPartition]?.frame, CloisonDistributionConfiguration().frame)
    }

    func testOpeningHeightSuggestionsIgnoreAnEmptyHeight() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        _ = try store.createWork(
            projectID: projectID,
            name: "Doublage incomplet",
            type: .peripheralLiningFurrings,
            furringLiningConfiguration: FurringLiningConfiguration(height: 0)
        )

        XCTAssertNil(store.openingHeightSuggestions(projectID: projectID)[.furringLining])
    }

    func testOpeningHeightOptionsListOnlyCompatibleWorksWithTheirHeights() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")

        _ = try store.createWork(
            projectID: projectID,
            name: "Doublage cuisine",
            type: .peripheralLiningFurrings,
            furringLiningConfiguration: FurringLiningConfiguration(
                height: 2.52,
                firstSkin: [.init(facingID: "parement-ba13-standard")],
                insulationEnabled: true,
                firstInsulation: .init(familyID: "laine-verre", lambda: 0.032, thicknessMM: 100)
            )
        )
        _ = try store.createWork(
            projectID: projectID,
            name: "Doublage salon",
            type: .peripheralLiningFurrings,
            furringLiningConfiguration: FurringLiningConfiguration(height: 2.70)
        )
        _ = try store.createWork(
            projectID: projectID,
            name: "Cloison chambre",
            type: .distributionPartition,
            cloisonDistributionConfiguration: CloisonDistributionConfiguration(height: 2.45)
        )

        let options = store.openingHeightOptions(projectID: projectID)
        XCTAssertEqual(options[.furringLining]?.map(\.sourceWorkName), ["Doublage salon", "Doublage cuisine"])
        XCTAssertEqual(options[.furringLining]?.map(\.height), [2.70, 2.52])
        XCTAssertEqual(try XCTUnwrap(options[.furringLining]?.last?.minimumJoineryLiningDepth), 0.128, accuracy: 0.000_1)
        XCTAssertEqual(options[.distributionPartition]?.map(\.sourceWorkName), ["Cloison chambre"])
        XCTAssertNil(options[.railStudLining])
    }

    func testJoineryConflictFollowsTheCurrentReferenceWorkComposition() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")

        var lining = FurringLiningConfiguration(
            height: 2.52,
            firstSkin: [.init(facingID: "parement-ba13-standard")],
            insulationEnabled: true,
            firstInsulation: .init(familyID: "laine-verre", lambda: 0.032, thicknessMM: 100)
        )
        let liningID = try store.createWork(
            projectID: projectID,
            name: "Cuisine - Doublage périphérique",
            type: .peripheralLiningFurrings,
            furringLiningConfiguration: lining
        )
        _ = try store.createWork(
            projectID: projectID,
            name: "Cuisine - Ouvertures",
            type: .openings,
            openingConfiguration: OpeningConfiguration(
                context: OpeningContext(system: .furringLining, hsp: 2.52),
                openings: [
                    OpeningInput(
                        kind: .window,
                        width: 1.20,
                        height: 1.05,
                        mountingMode: .onJoineryLining,
                        revealDepth: 0.12
                    )
                ],
                sourceWorkID: liningID,
                roomName: "Cuisine"
            )
        )

        let conflict = try XCTUnwrap(store.openingJoineryConflict(projectID: projectID, referenceWorkID: liningID))
        XCTAssertEqual(conflict.openingCount, 1)
        XCTAssertEqual(conflict.minimumDepth, 0.128, accuracy: 0.000_1)
        XCTAssertEqual(conflict.smallestEnteredDepth, 0.12, accuracy: 0.000_1)
        XCTAssertEqual(conflict.maximumCompatibleInsulationThickness, 0.092, accuracy: 0.000_1)

        lining.firstInsulation.thicknessMM = 80
        let work = try XCTUnwrap(store.project(id: projectID)?.works.first(where: { $0.id == liningID }))
        try store.updateWork(work, furringLiningConfiguration: lining)

        XCTAssertNil(store.openingJoineryConflict(projectID: projectID, referenceWorkID: liningID))
    }

    func testAlveolarPartitionSurvivesReloadAndDuplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        var configuration = AlveolarPartitionConfiguration(height: 2.5, enteredLength: 4)
        configuration.quantities = [AlveolarQuantity(name: "Clavettes", quantity: 40, unit: "unités")]
        let workID = try store.createWork(
            projectID: projectID,
            name: "Cloison alvéolaire",
            type: .alveolarPartition,
            alveolarPartitionConfiguration: configuration
        )
        let copyID = try store.duplicateWork(projectID: projectID, workID: workID)

        let reloaded = ProjectStore(fileURL: fileURL)
        let works = try XCTUnwrap(reloaded.project(id: projectID)?.works)
        XCTAssertEqual(works.count, 2)
        XCTAssertEqual(works.first(where: { $0.id == workID })?.alveolarPartitionConfiguration?.area, 10)
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.alveolarPartitionConfiguration, configuration)
    }

    func testPersistedMixedProjectConsolidatesSuppliesWithoutMergingTechnicalVariants() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store=ProjectStore(fileURL:url)
        let project=try store.createProject(name:"Essai multi-ouvrages",client:"Test",address:"",notes:"")
        for width in [48,70] {
            var c=CloisonDistributionConfiguration(height:2.5,enteredLength:4)
            c.frame="R\(width) + M\(width)"; c.insulationThicknessMM = width == 48 ? 45 : 70
            c.quantities=[.init(name:"Rails",quantity:8,unit:"ml"),.init(name:"Montants",quantity:20,unit:"ml"),
                .init(name:"Parement · BA13 Standard · 1200 × 2400 mm",quantity:21,unit:"m²"),
                .init(name:"Vis TTPC 25mm (1er parement)",quantity:100,unit:"unités"),
                .init(name:"Bande à joint",quantity:30,unit:"ml")]
            _ = try store.createWork(projectID:project,name:"Cloison R\(width)",type:.distributionPartition,cloisonDistributionConfiguration:c)
        }
        var lining=DoublageConfiguration(height:2.5,enteredLength:4)
        lining.quantities=[.init(name:"Rail R48",quantity:8,unit:"ml"),.init(name:"Montant M48",quantity:20,unit:"ml"),
            .init(name:"BA13 · 1200 × 2400 mm",quantity:10.5,unit:"m²"),
            .init(name:"Vis TTPC 25",quantity:100,unit:"unité"),.init(name:"Bande PP grand rouleau",quantity:15,unit:"ml")]
        _ = try store.createWork(projectID:project,name:"Doublage montants",type:.peripheralLiningStuds,doublageConfiguration:lining)
        var furring=FurringLiningConfiguration(height:2.5,enteredLength:4)
        furring.quantities=[.init(name:"Fourrures F45",quantity:12,unit:"ml"),.init(name:"Fourrures F45/F47",quantity:6,unit:"ml"),
            .init(name:"Bande à joint · papier",quantity:15,unit:"ml"),.init(name:"BA13 Hydrofuge H1 · 1200 × 2400 mm",quantity:10.5,unit:"m²")]
        _ = try store.createWork(projectID:project,name:"Doublage hydro",type:.peripheralLiningFurrings,furringLiningConfiguration:furring)
        var ceiling=RailStudCeilingConfiguration()
        ceiling.area=10; ceiling.studWidth=70
        ceiling.quantities=[.init(name:"Rails R70",quantity:8,unit:"ml"),.init(name:"Montants M70",quantity:20,unit:"ml"),
            .init(name:"BA13 · 1200 × 2400 mm",quantity:4,unit:"plaque(s)"),.init(name:"Vis TTPC 35 mm (2e parement)",quantity:100,unit:"unités")]
        _ = try store.createWork(projectID:project,name:"Plafond double peau",type:.ceilingOnRailsAndStuds,railStudCeilingConfiguration:ceiling)
        var adhesive=AdhesiveFacingConfiguration(height:2.5,enteredLength:4)
        adhesive.quantities=[.init(name:"BA13 · 1200 × 2600 mm",quantity:10.5,unit:"m²"),.init(name:"Bande à joint",quantity:15,unit:"ml")]
        _ = try store.createWork(projectID:project,name:"Parement collé",type:.peripheralLiningAdhesiveFacing,adhesiveFacingConfiguration:adhesive)
        let works=try XCTUnwrap(ProjectStore(fileURL:url).project(id:project)?.works)
        XCTAssertEqual(works.count,6)
        let catalogue=CeilingCataloguePayload(version:"test",ouvrage:nil,isolation:[],systemesFixation:[],parements:[],quantitatifs:[],pareVapeur:[],regles:[])
        let result=CombinedQuantityCalculator.calculate(works:works+works,catalogue:catalogue)
        let rows=SupplyListingConsolidator.rows(result.supplies.map { .init(name:$0.name,quantity:$0.quantity,unit:$0.unit) })
        func value(_ name:String)->Double { rows.first { $0.name==name }?.measurements.first?.quantity ?? 0 }
        XCTAssertEqual(Set(rows.map(\.name)).count,rows.count)
        XCTAssertEqual(value("Rails R48"),16)
        XCTAssertEqual(value("Rails R70"),16)
        XCTAssertEqual(value("Montants M48"),40)
        XCTAssertEqual(value("Montants M70"),40)
        XCTAssertEqual(value("Fourrures F45/F47"),18)
        XCTAssertEqual(value("Vis TTPC 25"),300)
        XCTAssertEqual(value("Vis TTPC 35"),100)
        XCTAssertEqual(value("Bande à joint"),105)
        XCTAssertEqual(value("BA13 · 1200 × 2400 mm"),64.02,accuracy:1e-6)
        XCTAssertEqual(value("BA13 · 1200 × 2600 mm"),10.5)
        XCTAssertEqual(value("BA13 Hydrofuge H1 · 1200 × 2400 mm"),10.5)
    }

    func testCombinedQuantityIncludesAllWorkTypes() {
        let projectID = UUID()
        let now = Date()
        let ceiling = WorkItem(id: UUID(), projectID: projectID, name: "Plafond", type: .ceilingOnFurring, configuration: CeilingConfiguration(length: 5, width: 4), createdAt: now, updatedAt: now)
        var doublageConfiguration = DoublageConfiguration(height: 2.5, enteredLength: 8)
        doublageConfiguration.quantities = [DoublageQuantity(name: "Rails", quantity: 16.8, unit: "ml")]
        let doublage = WorkItem(id: UUID(), projectID: projectID, name: "Doublage", type: .peripheralLiningStuds, doublageConfiguration: doublageConfiguration, createdAt: now, updatedAt: now)
        var partitionConfiguration = CloisonDistributionConfiguration(height: 2.5, enteredLength: 4)
        partitionConfiguration.quantities = [CloisonQuantity(name: "Rails", quantity: 8.4, unit: "ml")]
        let partition = WorkItem(id: UUID(), projectID: projectID, name: "Cloison", type: .distributionPartition, cloisonDistributionConfiguration: partitionConfiguration, createdAt: now, updatedAt: now)
        var alveolarConfiguration = AlveolarPartitionConfiguration(height: 2.5, enteredLength: 4)
        alveolarConfiguration.quantities = [AlveolarQuantity(name: "Rails", quantity: 6.8, unit: "ml")]
        let alveolar = WorkItem(id: UUID(), projectID: projectID, name: "Alvéolaire", type: .alveolarPartition, alveolarPartitionConfiguration: alveolarConfiguration, createdAt: now, updatedAt: now)
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])

        let result = CombinedQuantityCalculator.calculate(works: [ceiling, doublage, partition, alveolar], catalogue: catalogue)

        XCTAssertEqual(result.totalArea, 60)
        XCTAssertEqual(result.supplies.first(where: { $0.name == "Rails R48" })?.quantity ?? 0, 25.2, accuracy: 0.001)
        XCTAssertEqual(result.supplies.first(where: { $0.name == "Rail pour cloison alvéolaire" })?.quantity ?? 0, 6.8, accuracy: 0.001)
        XCTAssertFalse(result.supplies.contains(where: { $0.name == "Rails" }))
    }

    func testIdenticalInsulationLayersMergeAcrossWorksWithoutChangingConfigurations() {
        let projectID = UUID(), now = Date()
        var lining = DoublageConfiguration(height: 2.5, enteredLength: 8)
        lining.insulationLayers = 2
        lining.firstInsulation = .init(familyID: "glass", lambda: 0.032, thicknessMM: 100)
        lining.secondInsulation = lining.firstInsulation
        lining.quantities = [
            .init(name: "Isolation · 1re couche · Laine de verre, λ 0,032, 100 mm, R 3,13", quantity: 22, unit: "m²"),
            .init(name: "Isolation · 2e couche · Laine de verre, λ 0,032, 100 mm, R 3,13", quantity: 22, unit: "m²")
        ]
        let source = WorkItem(id: UUID(), projectID: projectID, name: "Doublage", type: .peripheralLiningStuds,
                              doublageConfiguration: lining, createdAt: now, updatedAt: now)
        let ceiling = WorkItem(id: UUID(), projectID: projectID, name: "Plafond", type: .ceilingOnFurring,
            configuration: CeilingConfiguration(length: 5, width: 4, insulationID: "glass032", insulationThickness: 100),
            createdAt: now, updatedAt: now)
        let record = CeilingReferenceRecord(id: "glass032", kind: "insulation_series", title: "Laine de verre · λ 0,032",
            summary: "", sourcePage: 0, status: "Publié", data: ["lambda_w_mk": .number(0.032)])
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [record], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let result = CombinedQuantityCalculator.calculate(works: [source, ceiling], catalogue: catalogue)
        let insulation = result.supplies.filter { $0.name.hasPrefix("Isolation") }
        XCTAssertEqual(insulation.count, 1)
        XCTAssertEqual(insulation.first?.quantity, 64) // Keep each work's existing reserve rule.
        XCTAssertEqual(insulation.first?.unit, "m²")
        XCTAssertEqual(source.doublageConfiguration, lining)
        XCTAssertEqual(source.doublageConfiguration?.insulationLayers, 2)
    }

    func testOpeningStudsMergeWithTheirSourceProfileInCombinedQuantity() {
        let projectID = UUID()
        let now = Date()
        var lining = DoublageConfiguration(height: 2.5, enteredLength: 8)
        lining.frame = "R48 + M48/35"
        lining.quantities = [DoublageQuantity(name: "Montants", quantity: 20, unit: "ml")]
        let source = WorkItem(id: UUID(), projectID: projectID, name: "Doublage", type: .peripheralLiningStuds,
                              doublageConfiguration: lining, createdAt: now, updatedAt: now)
        // Legacy opening archives have no profile snapshot: resolve it from the source ouvrage.
        let opening = WorkItem(id: UUID(), projectID: projectID, name: "Fenêtre", type: .openings,
            openingConfiguration: .init(context: .init(system: .railStudLining, hsp: 2.5),
                openings: [.init(kind: .window, width: 1.2, height: 1)], sourceWorkID: source.id),
            createdAt: now, updatedAt: now)
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let result = CombinedQuantityCalculator.calculate(works: [source, opening], catalogue: catalogue)
        let studs = result.supplies.filter { $0.name.hasPrefix("Montants") }
        XCTAssertEqual(studs.count, 1)
        XCTAssertEqual(studs.first?.name, "Montants M48/35")
        XCTAssertEqual(studs.first?.unit, "ml")
        XCTAssertEqual(studs.first?.quantity ?? 0, 25, accuracy: 0.001) // 20 ml + two full-height jambs, no lintels.
    }

    func testLegacyArchiveIsNotSilentlyImportedOrOverwritten() throws {
        struct LegacyWork: Encodable {
            let id: UUID
            let projectID: UUID
            let name: String
            let type: WorkType
            let configuration: CeilingConfiguration
            let doublageConfiguration: DoublageConfiguration?
            let createdAt: Date
            let updatedAt: Date
        }
        struct LegacyProject: Encodable {
            let id: UUID
            let name: String
            let client: String
            let address: String
            let notes: String
            let works: [LegacyWork]
            let createdAt: Date
            let updatedAt: Date
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = Date()
        let projectID = UUID()
        let legacyWork = LegacyWork(
            id: UUID(),
            projectID: projectID,
            name: "Ancien plafond",
            type: .ceilingOnFurring,
            configuration: CeilingConfiguration(length: 6, width: 4),
            doublageConfiguration: nil,
            createdAt: now,
            updatedAt: now
        )
        let legacyDoublage = LegacyWork(
            id: UUID(),
            projectID: projectID,
            name: "Ancien doublage",
            type: .peripheralLiningStuds,
            configuration: CeilingConfiguration(),
            doublageConfiguration: DoublageConfiguration(height: 2.5, enteredLength: 8),
            createdAt: now,
            updatedAt: now
        )
        let legacyProject = LegacyProject(id: projectID, name: "Ancien chantier", client: "", address: "", notes: "", works: [legacyWork, legacyDoublage], createdAt: now, updatedAt: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyProject]).write(to: fileURL)

        let store = ProjectStore(fileURL: fileURL)

        XCTAssertNil(store.project(id: projectID))
        XCTAssertNotNil(store.lastError)
        let original = try Data(contentsOf: fileURL)
        XCTAssertThrowsError(try store.createProject(name: "Nouveau", client: "", address: "", notes: ""))
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testWorkTypesAreAssignedToTheirFutureCategories() {
        XCTAssertEqual(WorkType.ceilingOnFurring.category, .ceilings)
        XCTAssertEqual(WorkType.peripheralLiningStuds.category, .wallInsulation)
        XCTAssertEqual(WorkType.distributionPartition.category, .partitions)
        XCTAssertEqual(WorkType.alveolarPartition.category, .partitions)
        XCTAssertEqual(WorkType.openings.category, .openings)
        XCTAssertEqual(WorkType.paintingBeta.category, .painting)
        XCTAssertEqual(WorkCategory.allCases.count, 6)
        XCTAssertEqual(WorkType.jointTreatment.category, .joints)
    }

    func testDoublageStudCountIncludesEveryWallEnd() {
        XCTAssertEqual(DoublageStudCalculator.studs(length: 4, spacing: 0.6, wallCount: 1, doubled: false), 8)
        XCTAssertEqual(DoublageStudCalculator.studs(length: 4, spacing: 0.6, wallCount: 4, doubled: false), 12)
    }

    func testDoublageDoubleStudsKeepWallEndsSingle() {
        // Pour quatre murs estimés à 1 m : 3 axes par mur, soit 2 montants simples aux extrémités et 2 au centre.
        XCTAssertEqual(DoublageStudCalculator.studs(length: 4, spacing: 0.6, wallCount: 4, doubled: true), 16)
        XCTAssertEqual(DoublageStudCalculator.studAxes(length: 4, spacing: 0.6, wallCount: 4), 12)
    }

    func testFurringLiningCalculatesAxesAndIntermediateSupportLines() {
        XCTAssertEqual(FurringLiningCalculator.furringAxes(length: 20, spacing: 0.6, wallCount: 4), 40)
        XCTAssertEqual(FurringLiningCalculator.recommendedSupportLines(height: 2.62, maximumSpacing: 1.3), 2)
        XCTAssertEqual(FurringLiningCalculator.horizontalSupportFurringLength(wallLength: 20, supportLines: 2, wasteFactor: 1.05, isIncluded: true), 42)
        XCTAssertEqual(FurringLiningCalculator.horizontalSupportFurringLength(wallLength: 20, supportLines: 2, wasteFactor: 1.05, isIncluded: false), 0)
    }

    func testFurringLiningSurvivesReloadAndDuplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        var configuration = FurringLiningConfiguration()
        configuration.height = 2.62
        configuration.enteredLength = 20
        configuration.wallCount = 4
        configuration.selectedSupportLines = 2
        configuration.includesHorizontalSupportFurring = false
        configuration.quantities = [DoublageQuantity(name: "Fourrures", quantity: 100.8, unit: "ml")]
        let workID = try store.createWork(
            projectID: projectID,
            name: "Doublage séjour",
            type: .peripheralLiningFurrings,
            furringLiningConfiguration: configuration
        )
        let copyID = try store.duplicateWork(projectID: projectID, workID: workID)

        let reloaded = ProjectStore(fileURL: fileURL)
        let works = try XCTUnwrap(reloaded.project(id: projectID)?.works)
        XCTAssertEqual(works.first(where: { $0.id == workID })?.furringLiningConfiguration, configuration)
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.furringLiningConfiguration, configuration)
    }

    func testAdhesiveFacingSurvivesReloadAndDuplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        var configuration = AdhesiveFacingConfiguration()
        configuration.height = 2.5
        configuration.enteredLength = 8
        configuration.facingFamily = "BA13"
        configuration.facingFunctionID = "FACING-BA13-STANDARD"
        configuration.quantities = [AdhesiveFacingQuantity(name: "Mortier adhésif", quantity: 36, unit: "kg")]
        let workID = try store.createWork(
            projectID: projectID,
            name: "Parement collé séjour",
            type: .peripheralLiningAdhesiveFacing,
            adhesiveFacingConfiguration: configuration
        )
        let copyID = try store.duplicateWork(projectID: projectID, workID: workID)

        let reloaded = ProjectStore(fileURL: fileURL)
        let works = try XCTUnwrap(reloaded.project(id: projectID)?.works)
        XCTAssertEqual(works.first(where: { $0.id == workID })?.adhesiveFacingConfiguration, configuration)
        XCTAssertEqual(works.first(where: { $0.id == copyID })?.adhesiveFacingConfiguration, configuration)
    }

    func testGeneratedWorkNamesUseRoomAndSimpleWorkCategory() {
        XCTAssertEqual(
            WorkType.peripheralLiningFurrings.generatedName(roomName: " Salon "),
            "Salon - Doublage périphérique"
        )
        XCTAssertEqual(
            WorkType.peripheralLiningStuds.generatedName(roomName: "Salon"),
            "Salon - Doublage périphérique"
        )
        XCTAssertEqual(
            WorkType.ceilingOnRailsAndStuds.generatedName(roomName: "Buanderie"),
            "Buanderie - Plafond"
        )
    }

    func testOpeningSummaryGroupsIdenticalKindsAndDimensions() {
        let configuration = OpeningConfiguration(
            context: OpeningContext(system: .furringLining, hsp: 2.5),
            openings: [
                OpeningInput(kind: .window, width: 0.60, height: 0.40),
                OpeningInput(kind: .window, width: 0.60, height: 0.40),
                OpeningInput(kind: .window, width: 0.70, height: 2.00),
                OpeningInput(kind: .frenchDoorOrBay, width: 0.70, height: 2.00)
            ]
        )

        let lines = OpeningSummaryFormatter.lines(for: configuration)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].title, "Fenêtres")
        XCTAssertEqual(lines[0].count, 2)
        XCTAssertEqual(lines[1].title, "Fenêtre")
        XCTAssertEqual(lines[1].count, 1)
        XCTAssertEqual(lines[2].title, "Porte-fenêtre / baie")
    }

    func testRenamingReferenceWorkAlsoRenamesItsLinkedOpenings() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Maison", client: "", address: "", notes: "")
        let sourceID = try store.createWork(
            projectID: projectID,
            name: "Salon - Doublage périphérique",
            type: .peripheralLiningFurrings,
            furringLiningConfiguration: FurringLiningConfiguration(height: 2.50)
        )
        let openingsID = try store.createWork(
            projectID: projectID,
            name: "Salon - Ouvertures",
            type: .openings,
            openingConfiguration: OpeningConfiguration(
                context: OpeningContext(system: .furringLining, hsp: 2.50),
                openings: [OpeningInput(kind: .window, width: 0.60, height: 0.40)],
                sourceWorkID: sourceID,
                roomName: "Salon"
            )
        )

        try store.renameWork(projectID: projectID, workID: sourceID, roomName: "Cuisine")

        let works = try XCTUnwrap(store.project(id: projectID)?.works)
        XCTAssertEqual(works.first(where: { $0.id == sourceID })?.name, "Cuisine - Doublage périphérique")
        XCTAssertEqual(works.first(where: { $0.id == openingsID })?.name, "Cuisine - Ouvertures")
        XCTAssertEqual(works.first(where: { $0.id == openingsID })?.openingConfiguration?.roomName, "Cuisine")
    }

    func testScannedRoomsPersistAsAtomicProjectSurveyCheckpoints() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let first = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison Martin", surveyID: nil,
            surveyName: "Rez-de-chaussée", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))

        XCTAssertEqual(store.project(id: first.projectID)?.rooms.map(\.name), ["Salon"])
        XCTAssertEqual(store.surveys(projectID: first.projectID).first?.checkpoints.count, 1)

        let second = try store.saveScannedRoom(projectID: first.projectID, newProjectName: nil, surveyID: first.surveyID,
            surveyName: "ignoré", roomID: nil, roomName: "Cuisine", document: scanDocument(name: "Cuisine"))
        XCTAssertEqual(second.surveyID, first.surveyID)
        XCTAssertNotEqual(second.roomID, first.roomID)

        let reloaded = ProjectStore(fileURL: fileURL)
        let survey = try XCTUnwrap(reloaded.surveys(projectID: first.projectID).first)
        XCTAssertEqual(survey.name, "Rez-de-chaussée")
        XCTAssertEqual(survey.checkpoints.count, 2)
        XCTAssertEqual(Set(survey.checkpoints.map(\.roomID)), Set(reloaded.project(id: first.projectID)!.rooms.map(\.id)))
        XCTAssertTrue(survey.checkpoints.allSatisfy { $0.transformToSurvey == .identity })
        XCTAssertTrue(survey.checkpoints.allSatisfy { $0.spatialLinkState == .needsLink })
        XCTAssertEqual(survey.checkpoints.first?.id, first.checkpointID)
    }

    func testDuplicateAndDeleteProjectIncludePortableSurveys() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Relevé", roomID: nil, roomName: "Bureau", document: scanDocument(name: "Bureau"))
        let sourceSurvey = try XCTUnwrap(store.surveys(projectID: saved.projectID).first)
        let sourceCheckpoint = try XCTUnwrap(sourceSurvey.checkpoints.first)

        let copyID = try store.duplicateProject(id: saved.projectID)
        let copiedSurvey = try XCTUnwrap(store.surveys(projectID: copyID).first)
        let copiedCheckpoint = try XCTUnwrap(copiedSurvey.checkpoints.first)
        XCTAssertNotEqual(copiedSurvey.id, sourceSurvey.id)
        XCTAssertNotEqual(copiedCheckpoint.id, sourceCheckpoint.id)
        XCTAssertNotEqual(copiedCheckpoint.roomID, sourceCheckpoint.roomID)
        XCTAssertNotEqual(copiedCheckpoint.document.room.id, sourceCheckpoint.document.room.id)
        XCTAssertEqual(copiedCheckpoint.document.room.walls.first?.length.effectiveValue,
                       sourceCheckpoint.document.room.walls.first?.length.effectiveValue)

        try store.deleteProject(id: saved.projectID)
        XCTAssertTrue(store.surveys(projectID: saved.projectID).isEmpty)
        XCTAssertEqual(store.surveys(projectID: copyID).count, 1)
        XCTAssertEqual(ProjectStore(fileURL: fileURL).surveys(projectID: copyID).count, 1)
    }

    func testDuplicateSurveyIsIndependentAndDoesNotCopyOrRelinkWorks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let source = try XCTUnwrap(store.surveys.first)
        let selected = SurveyWorkGeometry.surfaces(in: source)
        _ = try store.createSurveyWork(surveyID: source.id, selections: selected,
            name: "Doublage", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil)
        let works = try XCTUnwrap(store.project(id: saved.projectID)).works
        let copyID = try store.duplicateSurvey(projectID: saved.projectID, surveyID: source.id)
        let copy = try XCTUnwrap(store.surveys.first { $0.id == copyID })
        let checkpoint = try XCTUnwrap(copy.checkpoints.first)
        XCTAssertEqual(copy.name, "Scan – copie")
        XCTAssertEqual(copy.projectID, source.projectID)
        XCTAssertEqual(copy.scanDate, source.scanDate)
        XCTAssertEqual(checkpoint.roomID, source.checkpoints[0].roomID)
        XCTAssertEqual(checkpoint.transformToSurvey, source.checkpoints[0].transformToSurvey)
        XCTAssertNotEqual(checkpoint.id, source.checkpoints[0].id)
        XCTAssertNotEqual(checkpoint.document.room.id, source.checkpoints[0].document.room.id)
        XCTAssertNotEqual(checkpoint.document.room.walls[0].id, source.checkpoints[0].document.room.walls[0].id)
        var modified = checkpoint.document
        try modified.room.walls[0].length.correct(4.5)
        try store.updateSurveyRoom(surveyID: copyID, checkpointID: checkpoint.id, expectedDocument: checkpoint.document, document: modified)
        XCTAssertEqual(store.surveys.first { $0.id == source.id }, source)
        XCTAssertEqual(store.project(id: saved.projectID)?.works, works)
        let reloaded = try XCTUnwrap(ProjectStore(fileURL: url).surveys.first { $0.id == copyID }?.checkpoints[0].document)
        // The archive's ISO-8601 date encoding intentionally drops subsecond precision.
        XCTAssertEqual(try reloaded.encoded(), try modified.encoded())
        let second = try store.duplicateSurvey(projectID: saved.projectID, surveyID: source.id)
        XCTAssertEqual(store.surveys.first { $0.id == second }?.name, "Scan – copie 2")
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.duplicateSurvey(projectID: saved.projectID, surveyID: UUID()))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testScannedRoomValidationLeavesNoPhantomProject() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var invalidTransform = SurveyTransform3D.identity
        invalidTransform.values.removeLast()
        XCTAssertThrowsError(try store.saveScannedRoom(projectID: nil, newProjectName: "Fantôme", surveyID: nil,
            surveyName: "Relevé", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"),
            transformToSurvey: invalidTransform))
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(store.surveys.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSurveyCorrectionsPersistAndRejectStaleEditorAndSilentReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Relevé", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        let original = try XCTUnwrap(store.surveys.first?.checkpoints.first?.document)
        var corrected = original
        try corrected.room.walls[0].length.correct(4.2)
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: original, document: corrected)
        let persisted = try Data(contentsOf: fileURL)
        XCTAssertThrowsError(try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: original, document: original))
        XCTAssertThrowsError(try store.saveScannedRoom(projectID: saved.projectID, newProjectName: nil,
            surveyID: saved.surveyID, surveyName: "Relevé", roomID: saved.roomID, roomName: "Salon",
            document: scanDocument(name: "Nouveau scan")))
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)
        let reloaded = ProjectStore(fileURL: fileURL)
        let checkpoint = try XCTUnwrap(reloaded.surveys.first?.checkpoints.first)
        XCTAssertEqual(checkpoint.id, saved.checkpointID)
        XCTAssertEqual(checkpoint.document.room.walls[0].length.effectiveValue, 4.2)
        XCTAssertEqual(checkpoint.document.initialRoom.walls[0].length.effectiveValue, 4)
        XCTAssertEqual(checkpoint.document.room.walls[0].id, original.room.walls[0].id)

        _ = try store.saveScannedRoom(projectID: saved.projectID, newProjectName: nil,
            surveyID: saved.surveyID, surveyName: "Relevé", roomID: saved.roomID, roomName: "Salon",
            document: scanDocument(name: "Salon"), replacingExistingCapture: true)
        XCTAssertEqual(store.surveys.first?.checkpoints.count, 1)
        XCTAssertEqual(store.surveys.first?.checkpoints.first?.id, saved.checkpointID)
    }

    func testExistingArchiveWithoutSurveysRemainsReadable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: fileURL)
        let projectID = try store.createProject(name: "Existant", client: "", address: "", notes: "")
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        archive.removeValue(forKey: "surveys")
        try JSONSerialization.data(withJSONObject: archive).write(to: fileURL, options: .atomic)
        let reloaded = ProjectStore(fileURL: fileURL)
        XCTAssertNil(reloaded.lastError)
        XCTAssertNotNil(reloaded.project(id: projectID))
        XCTAssertTrue(reloaded.surveys.isEmpty)
        _ = try reloaded.saveScannedRoom(projectID: projectID, newProjectName: nil, surveyID: nil,
            surveyName: "Relevé", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        XCTAssertEqual(ProjectStore(fileURL: fileURL).surveys.count, 1)
    }

    func testSurveyWriteFailureDoesNotPublishPhantomData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: fileURL)
        // Force a real I/O error: the expected parent directory is a regular file.
        try Data("occupied".utf8).write(to: folder)
        XCTAssertThrowsError(try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Relevé", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon")))
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(store.surveys.isEmpty)
    }

    func testSurveyTransformRefusesRescalingReflectionAndNonfiniteValues() {
        XCTAssertTrue(SurveyTransform3D.identity.isValid)
        var transform = SurveyTransform3D.identity
        transform.values[12] = 10
        XCTAssertTrue(transform.isValid)
        transform.values[0] = 2
        XCTAssertFalse(transform.isValid)
        transform.values[0] = -1
        XCTAssertFalse(transform.isValid)
        transform.values[0] = 1
        transform.values[12] = .infinity
        XCTAssertFalse(transform.isValid)
    }

    func testHistoricalCheckpointWithoutWorkStateIsUsableWithoutManualReview() throws {
        let checkpoint = ProjectRoomScanCheckpoint(roomID: UUID(), document: scanDocument(name: "Ancien relevé"),
            spatialLinkState: .sharedWorldSpace)
        let encoded = try JSONEncoder().encode(checkpoint)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["workState"])
        let decoded = try JSONDecoder().decode(ProjectRoomScanCheckpoint.self, from: encoded)
        XCTAssertEqual(decoded.effectiveWorkState, .awaitingValidation)
        XCTAssertTrue(decoded.isUsableForWork, "Valid saved geometry needs no manual approval")
    }

    func testRecoveredSurveyCheckpointWithValidGeometryNeedsNoExplicitValidation() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var draft = ScanCampaignDraft()
        draft.append(.init(referenceGroupID: UUID(), name: "Salon", usages: [.livingRoom],
            document: scanDocument(name: "Salon"), processingPending: true))

        let surveyID = try store.saveScanCampaign(draft, projectID: nil,
            newProjectName: "Maison", surveyName: "Relevé interrompu")
        var survey = try XCTUnwrap(store.surveys.first { $0.id == surveyID })
        var checkpoint = try XCTUnwrap(survey.checkpoints.first)
        XCTAssertEqual(checkpoint.effectiveWorkState, .provisional)
        XCTAssertTrue(checkpoint.isUsableForWork)
        XCTAssertEqual(ProjectStore(fileURL: fileURL).surveys.first?.checkpoints.first?.effectiveWorkState, .provisional)
        let selected = SurveyWorkGeometry.surfaces(in: survey)
        let workID = try store.createSurveyWork(surveyID: surveyID, selections: selected,
            name: "Doublage prématuré", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil)
        XCTAssertNotNil(store.project(id: survey.projectID)?.works.first { $0.id == workID })

        // A recovered live checkpoint remains useful: explicit visual control can
        // validate it even when the acquisition pipeline cannot resume RoomBuilder.
        try store.validateSurveyCheckpoint(surveyID: surveyID, checkpointID: checkpoint.id,
            expectedDocument: checkpoint.document)
        survey = try XCTUnwrap(store.surveys.first { $0.id == surveyID })
        checkpoint = try XCTUnwrap(survey.checkpoints.first)
        XCTAssertEqual(checkpoint.effectiveWorkState, .validated)
        XCTAssertFalse(checkpoint.needsReview)
        XCTAssertEqual(survey.state, .validated)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: surveyID,
            selections: SurveyWorkGeometry.surfaces(in: survey), name: "Doublage contrôlé",
            type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(SurveyWorkGeometry.surfaces(in: survey))),
            roomID: nil), "Approval must not allow assigning the same surfaces twice")
    }

    func testDesignedPartitionFromScanKeepsSingleAreaAndProjectFormMetadata() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let document = try SurveyPlanEditing.addingPartition(scanDocument(name: "Salon"),
            start: .init(x: 0, y: 0, z: 1), end: .init(x: 3, y: 0, z: 1), height: 2.5)
        var draft = ScanCampaignDraft()
        draft.append(.init(referenceGroupID: UUID(), name: "Salon", usages: [.livingRoom], document: document))
        let surveyID = try store.saveScanCampaign(draft, projectID: nil, newProjectName: "Maison",
            surveyName: "Relevé", newProjectClient: "Client test", newProjectAddress: "Adresse test", newProjectNotes: "Note test")
        let projectID = try XCTUnwrap(store.surveys.first?.projectID)
        let project = try XCTUnwrap(store.project(id: projectID))
        XCTAssertEqual(project.client, "Client test")
        XCTAssertEqual(project.address, "Adresse test")
        XCTAssertEqual(project.notes, "Note test")
        try validateAllCheckpoints(in: store, surveyID: surveyID)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0]).filter(SurveyWorkGeometry.isDesignedPartition)
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(SurveyWorkGeometry.totalArea(selected), 7.5, accuracy: 1e-8)
        var configuration = SurveyWorkGeometry.partition(selected)
        configuration.faceAFirst=[.init(facingID:"ba13",formatID:"1200x2400",surface:7.5)]
        configuration.faceBFirst=configuration.faceAFirst
        XCTAssertEqual(configuration.area, 7.5, accuracy: 1e-8)
        let workID = try store.createSurveyWork(surveyID: surveyID, selections: selected,
            name: "Bureau", type: .distributionPartition, payload: .distributionPartition(configuration), roomID: nil)
        let work = try XCTUnwrap(store.project(id: projectID)?.works.first { $0.id == workID })
        XCTAssertTrue(work.isPartition)
        XCTAssertEqual(work.components.count, 1, "Two sides must not create two physical partitions")
        let component=work.components[0]
        XCTAssertEqual(component.plans.count,2)
        XCTAssertEqual(Set(component.plans.compactMap(\.sideRoomID)),Set(component.localLayoutSideIDs ?? []))
        let copiedProjectID=try store.duplicateProject(id:projectID)
        let copied=try XCTUnwrap(store.project(id:copiedProjectID)?.works.first?.components.first)
        XCTAssertEqual(copied.plans.count,2)
        XCTAssertTrue(Set(copied.localLayoutSideIDs ?? []).isDisjoint(with:component.localLayoutSideIDs ?? []))
        XCTAssertEqual(copied.referenceSideRoomID,copied.localLayoutSideIDs?.first)
        XCTAssertEqual(Set(copied.plans.compactMap(\.sideRoomID)),Set(copied.localLayoutSideIDs ?? []))
        XCTAssertEqual(copied.framing,component.framing)
        XCTAssertEqual(try XCTUnwrap(work.cloisonDistributionConfiguration?.area), 7.5, accuracy: 1e-8)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: surveyID, selections: selected,
            name: "Doublon", type: .distributionPartition, payload: .distributionPartition(configuration), roomID: nil))
        XCTAssertEqual(ProjectStore(fileURL: fileURL).project(id: projectID)?.works.count, 1)
    }

    /// Synthetic, portable fixture for manually checking the production 3D/2D
    /// workspace in a separately identified simulator app (never a real scan).
    func testWorkspaceTwoRoomVisualFixture() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let source = GeometryProvenance(source: .manual)
        var draft = ScanCampaignDraft(); let group = UUID()
        for index in 0..<2 {
            let x = Double(index)*4
            let vertices = [(x,0.0),(x+4,0.0),(x+4,3.0),(x,3.0)].map { RoomPoint(x: $0.0, y: 0, z: $0.1) }
            let walls = vertices.indices.map { i in
                let start = vertices[i], end = vertices[(i+1)%vertices.count]
                return PlaquistoWall(start: start, end: end,
                    length: .init(rawValue: (end-start).length, provenance: source),
                    height: .init(rawValue: 2.5, provenance: source), provenance: source)
            }
            var document = PlaquistoRoomDocument(room: .init(name: index == 0 ? "Salon test" : "Bureau test",
                walls: walls, metadata: .init(source: .manual)))
            document = try SurveyPlanEditing.addingDoor(document, wallID: walls[0].id, width: 0.83, height: 2.04, position: 1)
            document = try WallCeilingEstimate.addingIfMissing(to: document)
            draft.append(.init(referenceGroupID: group, name: document.room.name!, usages: [], document: document))
        }
        // These synthetic vertices were authored in one frame; unlike raw
        // RoomBuilder outputs they need no actual device assembly.
        draft.assemblyVerified = true; draft.isComplete = true
        _ = try store.saveScanCampaign(draft, projectID: nil, newProjectName: "TEST — Maquette deux pièces",
            surveyName: "Relevé synthétique")
        XCTAssertEqual(store.surveys[0].checkpoints.count, 2)
        XCTAssertEqual(SurveyWorkGeometry.surfaces(in: store.surveys[0]).filter { $0.source.kind == .wall }.count, 8)
        let attachment = XCTAttachment(data: try Data(contentsOf: fileURL), uniformTypeIdentifier: "public.json")
        attachment.name = "workspace-synthetic-projects.json"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSurveyEditsUpdateOpeningsQuantitiesAndKeepPlacedLayoutWithoutReview() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        let survey = try XCTUnwrap(store.surveys.first)
        let selected = SurveyWorkGeometry.surfaces(in: survey)
        var configuration = SurveyWorkGeometry.furring(selected)
        configuration.quantities = [
            .init(name: "Plaques BA13", quantity: 11, unit: "m²"),
            .init(name: "Rails pour fourrure ou lisses de doublage", quantity: 8.8, unit: "ml"),
            .init(name: "Appuis intermédiaires pour fourrures", quantity: 8, unit: "unités")
        ]
        let workID = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Doublage", type: .peripheralLiningFurrings, payload: .furringLining(configuration), roomID: nil)
        var work = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        let component = try XCTUnwrap(work.components.first)
        let document = LayoutDocument(surface: try XCTUnwrap(component.surface), layers: [LayoutLayer()])
        try store.saveComponentPlan(projectID: saved.projectID, workID: workID, componentID: component.id,
            sideRoomID: nil, document: document, expectedGeometryRevision: component.geometryRevision)
        work = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        let savedPlans = work.components[0].plans
        var edited = survey.checkpoints[0].document
        let wall = edited.room.walls[0]
        func measure(_ value: Double) -> RoomMeasurement { .init(rawValue: value, provenance: wall.provenance) }
        edited.room.openings = [.init(wallID: wall.id, kind: .window, center: .init(x: 1.5, y: 1.5, z: 0),
            width: measure(1), height: measure(1), sillHeight: measure(1), positionOnWall: measure(1), provenance: wall.provenance)]
        edited.room.walls[0].openingIDs = edited.room.openings.map(\.id)
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: survey.checkpoints[0].document, document: edited)
        let updated = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        XCTAssertFalse(updated.surveySourceNeedsReview)
        XCTAssertEqual(updated.area, 9, accuracy: 0.00001)
        XCTAssertEqual(updated.components[0].surface?.openings.count, 1)
        XCTAssertEqual(updated.components[0].plans.map(\.layers), savedPlans.map(\.layers))
        XCTAssertEqual(updated.components[0].plans[0].geometryRevision, updated.components[0].geometryRevision)
        let quantities = try XCTUnwrap(updated.furringLiningConfiguration?.quantities)
        XCTAssertEqual(quantities[0].quantity, 9.9, accuracy: 0.00001)
        XCTAssertEqual(quantities[1].quantity, 8.8, accuracy: 0.00001, "An opening does not shorten perimeter rails")
        XCTAssertEqual(quantities[2].quantity, 8, accuracy: 0.00001)
        let reloaded = try XCTUnwrap(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.first)
        XCTAssertEqual(reloaded.payload, updated.payload)
        XCTAssertEqual(reloaded.components.map(\.surface), updated.components.map(\.surface))
        XCTAssertEqual(reloaded.components.map(\.plans), updated.components.map(\.plans))

        // Removing the opening restores the initial quantities without repeated rounding.
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: edited, document: survey.checkpoints[0].document)
        let restored = try XCTUnwrap(store.project(id: saved.projectID)?.works.first?.furringLiningConfiguration)
        XCTAssertEqual(restored.quantities[0].quantity, 11, accuracy: 0.00001)
    }

    func testSurveyGeometryChangeAutomaticallyUpdatesLinkedWorkAndMetadataDoesNot() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        var survey = try XCTUnwrap(store.surveys.first { $0.id == saved.surveyID })
        let selected = SurveyWorkGeometry.surfaces(in: survey)
        let workID = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Doublage", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil)
        let originalWork = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID })

        var renamed = survey.checkpoints[0].document
        renamed.room.name = "Séjour"
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: survey.checkpoints[0].document, document: renamed)
        XCTAssertFalse(try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID }).surveySourceNeedsReview)
        XCTAssertEqual(store.surveys.first?.checkpoints.first?.effectiveWorkState, .validated)

        survey = try XCTUnwrap(store.surveys.first { $0.id == saved.surveyID })
        var corrected = survey.checkpoints[0].document
        try corrected.room.walls[0].length.correct(4.5)
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: survey.checkpoints[0].document, document: corrected)
        var flagged = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID })
        XCTAssertFalse(flagged.surveySourceNeedsReview)
        XCTAssertNotEqual(flagged.payload, originalWork.payload)
        XCTAssertEqual(flagged.area, SurveyWorkGeometry.totalArea(SurveyWorkGeometry.surfaces(in: store.surveys[0])), accuracy: 0.0001)
        XCTAssertEqual(flagged.components.map(\.id), originalWork.components.map(\.id))
        XCTAssertNotEqual(flagged.components, originalWork.components)
        XCTAssertEqual(store.surveys.first?.checkpoints.first?.effectiveWorkState, .validated)
        XCTAssertEqual(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.first?.surveySourceNeedsReview, false)
        XCTAssertThrowsError(try store.validateSurveyCheckpoint(surveyID: saved.surveyID,
            checkpointID: saved.checkpointID, expectedDocument: renamed),
            "A stale review must not validate geometry that changed afterwards")

        try store.updateWork(flagged, doublageConfiguration: try XCTUnwrap(flagged.doublageConfiguration))
        flagged = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID })
        XCTAssertFalse(flagged.surveySourceNeedsReview)

        let projectCopyID = try store.duplicateProject(id: saved.projectID)
        XCTAssertFalse(try XCTUnwrap(store.project(id: projectCopyID)?.works.first).surveySourceNeedsReview)
        let standaloneCopyID = try store.duplicateWork(projectID: saved.projectID, workID: workID)
        XCTAssertFalse(try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == standaloneCopyID }).surveySourceNeedsReview)

        try store.confirmKeepingCurrentSurveyGeometry(projectID: saved.projectID, workID: workID)
        let accepted = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID })
        XCTAssertFalse(accepted.surveySourceNeedsReview)
        XCTAssertEqual(accepted.payload, flagged.payload)
        XCTAssertEqual(accepted.components, flagged.components)
    }

    func testDeletingAScannedWallUpdatesOnlyItsLinkedWorkAndClearsItsQuantities() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        var document = scanDocument(name: "Salon")
        var other = document.room.walls[0]
        other.id = UUID(); other.start.z = 3; other.end.z = 3
        document.room.walls.append(other)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        let surfaces = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        for (index, surface) in surfaces.enumerated() {
            var configuration = SurveyWorkGeometry.lining([surface])
            configuration.quantities = [.init(name: "BA13", quantity: 11, unit: "m²")]
            _ = try store.createSurveyWork(surveyID: saved.surveyID, selections: [surface],
                name: "Mur \(index)", type: .peripheralLiningStuds, payload: .peripheralLining(configuration), roomID: nil)
        }
        let untouched = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.name == "Mur 1" })
        var edited = document
        edited.room.walls.removeFirst()
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: document, document: edited)
        let deleted = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.name == "Mur 0" })
        XCTAssertTrue(deleted.components.isEmpty)
        XCTAssertEqual(deleted.area, 0)
        XCTAssertEqual(deleted.doublageConfiguration?.quantities.first?.quantity, 0)
        XCTAssertFalse(deleted.surveySourceNeedsReview)
        XCTAssertEqual(store.project(id: saved.projectID)?.works.first { $0.name == "Mur 1" }, untouched)
    }

    func testSurveyCeilingEditRefreshesPreviouslyAdoptedLayoutTakeoff() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        var document = scanDocument(name: "Salon")
        let boundary: [RoomPoint] = [.init(x: 0, y: 3, z: 0), .init(x: 4, y: 3, z: 0),
                                    .init(x: 4, y: 3, z: 3), .init(x: 0, y: 3, z: 3)]
        document.room.slopes = [.init(plane: .init(a: 0, b: 0, c: 3), boundaries: [boundary],
            provenance: document.room.walls[0].provenance, accepted: true)]
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0]).filter { $0.source.kind == .ceiling }
        let workID = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected, name: "Plafond",
            type: .ceilingOnFurring, payload: .ceiling(SurveyWorkGeometry.ceiling(selected)), roomID: nil)
        var work = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        let component = try XCTUnwrap(work.components.first)
        var layout = LayoutDocument.newSupport(try XCTUnwrap(component.surface))
        layout.layers[0].furring = .init(spacing: 600, offset: 0, orientation: .horizontal)
        try store.saveComponentPlan(projectID: saved.projectID, workID: workID, componentID: component.id,
            sideRoomID: nil, document: layout)
        work = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        let takeoff = try LayoutQuantityCalculator.make(work: work, formats: [])
        try store.saveLayoutQuantityTakeoff(projectID: saved.projectID, workID: workID, takeoff: takeoff)
        var edited = document
        edited.room.slopes[0].boundaries[0][1].x = 5
        edited.room.slopes[0].boundaries[0][2].x = 5
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: document, document: edited)
        let updated = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        XCTAssertEqual(updated.area, 15, accuracy: 0.00001)
        XCTAssertFalse(updated.surveySourceNeedsReview)
        let updatedTakeoff = try XCTUnwrap(LayoutQuantityCalculator.validated(updated))
        XCTAssertEqual(updatedTakeoff.area, 15, accuracy: 0.00001)
        XCTAssertGreaterThan(updatedTakeoff.perimeterMeters, takeoff.perimeterMeters)
        XCTAssertEqual(updated.components[0].plans[0].layers, work.components[0].plans[0].layers)
    }

    func testLegacyReviewFlagMigratesToCurrentGeometryOnlyOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        let document = scanDocument(name: "Salon")
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        _ = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected, name: "Doublage",
            type: .peripheralLiningStuds, payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil)
        var legacy = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        legacy.surveySourceNeedsReview = true
        var edited = document
        try edited.room.walls[0].length.correct(5)
        try store.updateSurveyRoom(surveyID: saved.surveyID, checkpointID: saved.checkpointID,
            expectedDocument: document, document: edited)
        // Simulate the old version: corrected survey, unchanged linked work and review flag.
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var projects = try XCTUnwrap(archive["projects"] as? [[String: Any]])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        projects[0]["works"] = [try JSONSerialization.jsonObject(with: encoder.encode(legacy))]
        archive["projects"] = projects
        try JSONSerialization.data(withJSONObject: archive).write(to: url)
        let restored = ProjectStore(fileURL: url)
        XCTAssertNil(restored.lastError)
        let updated = try XCTUnwrap(restored.projects.first?.works.first)
        XCTAssertFalse(updated.surveySourceNeedsReview)
        XCTAssertEqual(updated.area, 12.5, accuracy: 0.00001)
        let reloaded = try XCTUnwrap(ProjectStore(fileURL: url).projects.first?.works.first)
        XCTAssertEqual(reloaded.payload, updated.payload)
        XCTAssertEqual(reloaded.components.map(\.surface), updated.components.map(\.surface))
        XCTAssertEqual(reloaded.components.map(\.geometryRevision), updated.components.map(\.geometryRevision))
    }

    func testSurveySelectionKeepsEachCorrectedWallAndDeductsOverlappingOpeningsOnce() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var document = scanDocument(name: "Salon")
        try document.room.walls[0].length.correct(5)
        let wall = document.room.walls[0]
        func measure(_ value: Double) -> RoomMeasurement { .init(rawValue: value, provenance: wall.provenance) }
        document.room.openings = [
            .init(wallID: wall.id, kind: .window, center: .zero, width: measure(1), height: measure(1), sillHeight: measure(1), positionOnWall: measure(1), provenance: wall.provenance),
            .init(wallID: wall.id, kind: .window, center: .zero, width: measure(1), height: measure(1), sillHeight: measure(1), positionOnWall: measure(1.5), provenance: wall.provenance)
        ]
        document.room.walls[0].openingIDs = document.room.openings.map(\.id)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Relevé", roomID: nil, roomName: "Salon", document: document)
        _ = try store.saveScannedRoom(projectID: saved.projectID, newProjectName: nil, surveyID: saved.surveyID,
            surveyName: "Relevé", roomID: nil, roomName: "Bureau", document: scanDocument(name: "Bureau"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let survey = try XCTUnwrap(store.surveys.first)
        let selected = SurveyWorkGeometry.surfaces(in: survey)
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(selected[0].surface.bounds.width, 5000, accuracy: 0.001)
        XCTAssertEqual(selected[0].netArea, 11, accuracy: 0.0001) // 12.5 - union 1.5, not 2
        XCTAssertEqual(SurveyWorkGeometry.totalArea(selected), 21, accuracy: 0.0001)
        let seed = SurveyWorkGeometry.lining(selected)
        XCTAssertEqual(seed.measuredWallRuns?.reduce(0) { $0 + $1.length }, 9)
        XCTAssertEqual(seed.measuredWallRuns?.reduce(0) { $0+($1.openingCount ?? 0) },2)
        XCTAssertEqual(seed.measuredWallRuns?.reduce(0) { $0+($1.openingArea ?? 0) },1.5)
        let furringSeed=SurveyWorkGeometry.furring(selected)
        XCTAssertEqual(furringSeed.measuredWallRuns,seed.measuredWallRuns)
        XCTAssertEqual(furringSeed.area,21)
        let workID = try store.createSurveyWork(surveyID: survey.id, selections: selected,
            name: "Doublage", type: .peripheralLiningStuds, payload: .peripheralLining(seed), roomID: nil)
        let reloaded = ProjectStore(fileURL: fileURL)
        let work = try XCTUnwrap(reloaded.project(id: saved.projectID)?.works.first { $0.id == workID })
        XCTAssertEqual(work.components.count, 2)
        XCTAssertEqual(work.components[0].surface?.openings.count, 2)
        XCTAssertEqual(work.components[0].surveySource?.surfaceID, wall.id)
        XCTAssertEqual(work.doublageConfiguration?.area, 21)
        XCTAssertFalse(work.hasSavedLayout)
        XCTAssertNotNil(work.components[0].document(for: .init())) // Ready for 2D, no fake saved layout.
    }

    func testSurveyAssignmentRejectsDuplicatesAcrossLiningTechniquesAndStaleSource() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let survey = try XCTUnwrap(store.surveys.first)
        let selected = SurveyWorkGeometry.surfaces(in: survey)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: survey.id, selections: selected + selected,
            name: "Double sélection", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil))
        var edited = survey.checkpoints[0].document
        try edited.room.walls[0].height.correct(3)
        try store.updateSurveyRoom(surveyID: survey.id, checkpointID: survey.checkpoints[0].id,
            expectedDocument: survey.checkpoints[0].document, document: edited)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: survey.id, selections: selected,
            name: "Périmé", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let fresh = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        _ = try store.createSurveyWork(surveyID: survey.id, selections: fresh,
            name: "Doublage rails", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(fresh)), roomID: saved.roomID)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: survey.id, selections: fresh,
            name: "Même mur fourrures", type: .peripheralLiningFurrings,
            payload: .furringLining(SurveyWorkGeometry.furring(fresh)), roomID: nil))
        XCTAssertEqual(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.count, 1)
    }

    func testSurveyCeilingsAreDevelopedInTheirPlaneAndUnvalidatedCeilingsStayUnavailable() throws {
        var document = scanDocument(name: "Combles")
        let provenance = document.room.walls[0].provenance
        let boundary: [RoomPoint] = [.init(x: 0,y: 2,z: 0), .init(x: 4,y: 2,z: 0), .init(x: 4,y: 5,z: 3), .init(x: 0,y: 5,z: 3)]
        let slope = PlaquistoSlope(plane: .init(a: 0,b: 1,c: 2), boundaries: [boundary], provenance: provenance, accepted: true)
        document.room.slopes = [slope, .init(plane: .init(a: 0,b: 0,c: 3), boundaries: [boundary], provenance: provenance)]
        let checkpoint = ProjectRoomScanCheckpoint(roomID: UUID(), document: document, spatialLinkState: .needsLink)
        let survey = ProjectSurveyRecord(projectID: UUID(), name: "Relevé", checkpoints: [checkpoint])
        let ceilings = SurveyWorkGeometry.surfaces(in: survey).filter { $0.source.kind == .ceiling }
        XCTAssertEqual(ceilings.count, 1)
        XCTAssertEqual(try XCTUnwrap(ceilings.first).netArea, 12 * sqrt(2), accuracy: 0.0001)
        XCTAssertEqual(SurveyWorkGeometry.ceiling(ceilings).enteredArea!, 12 * sqrt(2), accuracy: 0.0001)
    }

    func testSurveyWorkCopyRemapsProvenanceWithoutDuplicatingClaimsInOriginalProject() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        let workID = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Doublage", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: saved.roomID)
        let copyID = try store.duplicateProject(id: saved.projectID)
        let copiedSurvey = try XCTUnwrap(store.surveys(projectID: copyID).first)
        let copiedWork = try XCTUnwrap(store.project(id: copyID)?.works.first)
        let copiedSource = try XCTUnwrap(copiedWork.components[0].surveySource)
        XCTAssertEqual(copiedSource.surveyID, copiedSurvey.id)
        XCTAssertEqual(copiedSource.checkpointID, copiedSurvey.checkpoints[0].id)
        XCTAssertEqual(copiedSource.surfaceID, copiedSurvey.checkpoints[0].document.room.walls[0].id)
        XCTAssertNotEqual(copiedSource.surfaceID, selected[0].source.surfaceID)
        let duplicateID = try store.duplicateWork(projectID: saved.projectID, workID: workID)
        XCTAssertNil(store.project(id: saved.projectID)?.works.first { $0.id == duplicateID }?.components[0].surveySource)
    }

    func testSurveyCeilingHoleIsNotASecondSurfaceAndIsDeductedInSavedWork() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        var document = scanDocument(name: "Salon")
        let outer: [RoomPoint] = [.init(x: 0,y: 3,z: 0), .init(x: 4,y: 3,z: 0), .init(x: 4,y: 3,z: 3), .init(x: 0,y: 3,z: 3)]
        let hole: [RoomPoint] = [.init(x: 1,y: 3,z: 1), .init(x: 2,y: 3,z: 1), .init(x: 2,y: 3,z: 2), .init(x: 1,y: 3,z: 2)]
        document.room.slopes = [.init(plane: .init(a: 0,b: 0,c: 3), boundaries: [outer, hole],
            provenance: document.room.walls[0].provenance, accepted: true)]
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: document)
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0]).filter { $0.source.kind == .ceiling }
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected[0].surface.openings.count, 1)
        XCTAssertEqual(selected[0].netArea, 11, accuracy: 0.00001)
        let vertices = selected[0].triangles
        let drawnArea = stride(from: 0, to: vertices.count, by: 3).reduce(0.0) { total, i in
            let a = vertices[i], b = vertices[i+1], c = vertices[i+2]
            return total + abs((b.x-a.x)*(c.z-a.z) - (b.z-a.z)*(c.x-a.x))/2
        }
        XCTAssertEqual(drawnArea, 11, accuracy: 0.00001)
        _ = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Plafond", type: .ceilingOnFurring, payload: .ceiling(SurveyWorkGeometry.ceiling(selected)), roomID: saved.roomID)
        let work = try XCTUnwrap(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.first)
        XCTAssertEqual(try XCTUnwrap(work.ceilingConfiguration?.enteredArea), 11, accuracy: 0.00001)
        XCTAssertEqual(work.components.count, 1)
        XCTAssertEqual(work.components[0].surface?.openings.count, 1)
    }

    func testSurveyWorkWriteFailureAndChangedDimensionsLeaveNoPartialWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        var wrong = SurveyWorkGeometry.lining(selected); wrong.enteredSurface += 1
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Dimension changée", type: .peripheralLiningStuds, payload: .peripheralLining(wrong), roomID: nil))
        XCTAssertTrue(store.project(id: saved.projectID)!.works.isEmpty)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Échec disque", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil))
        XCTAssertTrue(store.project(id: saved.projectID)!.works.isEmpty)
    }

    func testSurveyRailStudCeilingRetainsExactGeometryAndSharesCeilingClaims() throws {
        let fileURL=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:fileURL) }
        let store=ProjectStore(fileURL:fileURL)
        var document=scanDocument(name:"Salon")
        let boundary:[RoomPoint]=[.init(x:0,y:3,z:0),.init(x:4,y:3,z:0),.init(x:4,y:3,z:3),.init(x:0,y:3,z:3)]
        document.room.slopes=[.init(plane:.init(a:0,b:0,c:3),boundaries:[boundary],provenance:document.room.walls[0].provenance,accepted:true)]
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Maison",surveyID:nil,surveyName:"Scan",roomID:nil,roomName:"Salon",document:document)
        try validateAllCheckpoints(in:store,surveyID:saved.surveyID)
        let surfaces=SurveyWorkGeometry.surfaces(in:store.surveys[0])
        let selected=surfaces.filter { $0.source.kind == .ceiling }
        XCTAssertTrue(SurveyWorkGeometry.availableWorkTypes(for:selected).contains(.ceilingOnRailsAndStuds))
        XCTAssertTrue(SurveyWorkGeometry.availableWorkTypes(for:selected).contains(.ceilingOnFurring))
        XCTAssertFalse(SurveyWorkGeometry.availableWorkTypes(for:surfaces.filter { $0.source.kind == .wall }).contains(.ceilingOnRailsAndStuds))
        let configuration=SurveyWorkGeometry.railStudCeiling(selected)
        XCTAssertEqual(configuration.effectiveArea,12,accuracy:0.00001)
        XCTAssertFalse(configuration.dimensionsSpecified)
        var bad=configuration; bad.area += 1
        XCTAssertThrowsError(try store.createSurveyWork(surveyID:saved.surveyID,selections:selected,name:"Invalide",type:.ceilingOnRailsAndStuds,payload:.railStudCeiling(bad),roomID:nil))
        _ = try store.createSurveyWork(surveyID:saved.surveyID,selections:selected,name:"Plafond",type:.ceilingOnRailsAndStuds,payload:.railStudCeiling(configuration),roomID:nil)
        let work=try XCTUnwrap(ProjectStore(fileURL:fileURL).project(id:saved.projectID)?.works.first)
        XCTAssertEqual(work.components.first?.surface?.contour,selected.first?.surface.contour)
        XCTAssertEqual(try XCTUnwrap(work.railStudCeilingConfiguration?.effectiveArea),12,accuracy:0.00001)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID:saved.surveyID,selections:selected,name:"Doublon",type:.ceilingOnFurring,payload:.ceiling(SurveyWorkGeometry.ceiling(selected)),roomID:nil))
        store.showProject(saved.projectID)
        let request=try XCTUnwrap(store.projectNavigationRequest)
        XCTAssertEqual(request.projectID,saved.projectID)
        store.showProject(UUID())
        XCTAssertEqual(store.projectNavigationRequest,request)
        store.showProject(saved.projectID)
        XCTAssertNotEqual(store.projectNavigationRequest?.id,request.id)
        XCTAssertNil(ProjectStore(fileURL:fileURL).projectNavigationRequest)
    }

    func testPaintingBetaReusesSurfaceWithoutDuplicatingLiningOrInventingSupplies() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        _ = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Doublage", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil)
        let paintingID = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Peinture salon", type: .paintingBeta, payload: .paintingBeta(.init(area: 10)), roomID: nil)
        let painting = try XCTUnwrap(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.first { $0.id == paintingID })
        XCTAssertEqual(painting.components.count, 1)
        XCTAssertNil(painting.components[0].framing)
        XCTAssertTrue(painting.components[0].plans.isEmpty)
        XCTAssertEqual(painting.paintingBetaConfiguration?.area, 10)
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let quantities = CombinedQuantityCalculator.calculate(works: [painting], catalogue: catalogue)
        XCTAssertEqual(quantities.totalArea, 10)
        XCTAssertEqual(quantities.supplies.count, 1)
        XCTAssertEqual(quantities.supplies[0].name, "Surface à traiter · traitements à renseigner")
        XCTAssertEqual(quantities.supplies[0].unit, "m²")
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Même peinture", type: .paintingBeta, payload: .paintingBeta(.init(area: 10)), roomID: nil))
        XCTAssertThrowsError(try store.updateWork(painting, paintingBetaConfiguration: .init(area: 11)))
        XCTAssertEqual(store.project(id: saved.projectID)?.works.count, 2)
    }

    func testScannedMultiComponentEditReopensFormFromAllCurrentContours() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ProjectStore(fileURL: fileURL)
        let saved = try store.saveScannedRoom(projectID: nil, newProjectName: "Maison", surveyID: nil,
            surveyName: "Scan", roomID: nil, roomName: "Salon", document: scanDocument(name: "Salon"))
        _ = try store.saveScannedRoom(projectID: saved.projectID, newProjectName: nil, surveyID: saved.surveyID,
            surveyName: "Scan", roomID: nil, roomName: "Bureau", document: scanDocument(name: "Bureau"))
        try validateAllCheckpoints(in: store, surveyID: saved.surveyID)
        let selected = SurveyWorkGeometry.surfaces(in: store.surveys[0])
        let workID = try store.createSurveyWork(surveyID: saved.surveyID, selections: selected,
            name: "Doublage", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil)
        let component = try XCTUnwrap(store.project(id: saved.projectID)?.works.first?.components.first)
        var surface = try XCTUnwrap(component.surface)
        surface.contour = [.init(x: 0,y: 0), .init(x: 6000,y: 0), .init(x: 6000,y: 2500), .init(x: 0,y: 2500)]
        try store.saveComponentPlan(projectID: saved.projectID, workID: workID, componentID: component.id,
            sideRoomID: nil, document: .init(surface: surface, layers: [.init()]), expectedGeometryRevision: 0)
        let work = try XCTUnwrap(store.project(id: saved.projectID)?.works.first)
        XCTAssertNil(work.layoutDocument)
        XCTAssertEqual(work.layoutNeedsRecalculation, true)
        let refreshed = SurveyWorkGeometry.workForRecalculation(work)
        XCTAssertEqual(try XCTUnwrap(refreshed.doublageConfiguration?.area), 25, accuracy: 0.00001)
        XCTAssertEqual(refreshed.doublageConfiguration?.measuredWallRuns?.map(\.length), [6,4])
        XCTAssertEqual(refreshed.components.count, 2)
        XCTAssertEqual(try XCTUnwrap(store.project(id: saved.projectID)?.works.first?.doublageConfiguration?.area), 25, accuracy: 0.00001) // saving the plan applies its geometry immediately
    }

    func testLayoutWallHatchSynchronizesSurveyAndQuantitiesExactlyOnce() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store=ProjectStore(fileURL:url)
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Trappes",surveyID:nil,
            surveyName:"Scan",roomID:nil,roomName:"Pièce",document:scanDocument(name:"Pièce"))
        let survey=try XCTUnwrap(store.surveys.first)
        let surfaces=SurveyWorkGeometry.surfaces(in:survey)
        let workID=try store.createSurveyWork(surveyID:saved.surveyID,selections:surfaces,name:"Doublage",
            type:.peripheralLiningFurrings,payload:.furringLining(SurveyWorkGeometry.furring(surfaces)),roomID:nil)
        var component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
        var layout=try XCTUnwrap(component.initialDocument(sideRoomID:nil,configuration:nil))
        let opening=LayoutOpening(kind:.hatch,contour:[.init(x:1000,y:1000),.init(x:1600,y:1000),.init(x:1600,y:1600),.init(x:1000,y:1600)])
        layout.surface.openings.append(opening)
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,
            document:layout,expectedGeometryRevision:component.geometryRevision)
        var actual=try XCTUnwrap(store.surveys.first?.checkpoints.first?.document)
        XCTAssertEqual(actual.initialRoom,survey.checkpoints[0].document.initialRoom)
        XCTAssertEqual(actual.room.openings.count,1)
        XCTAssertEqual(actual.room.openings[0].id,opening.id)
        XCTAssertEqual(actual.room.openings[0].layoutKind,.hatch)
        XCTAssertEqual(actual.room.openings[0].width.effectiveValue,0.6,accuracy:1e-8)
        XCTAssertEqual(try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.area),9.64,accuracy:1e-8)
        XCTAssertEqual(SurveyWorkGeometry.surfaces(in:store.surveys[0])[0].surface.openings[0].kind,.hatch)
        component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,
            document:layout,expectedGeometryRevision:component.geometryRevision)
        XCTAssertEqual(store.surveys[0].checkpoints[0].document.room.openings.count,1)
        XCTAssertEqual(try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.area),9.64,accuracy:1e-8)
        // A stale open editor cannot reintroduce an opening after another edit.
        let staleRevision=component.geometryRevision
        layout.surface.openings[0].contour=layout.surface.openings[0].contour.map { .init(x:$0.x+300,y:$0.y) }
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,
            document:layout,expectedGeometryRevision:staleRevision)
        XCTAssertEqual(store.surveys[0].checkpoints[0].document.room.openings[0].positionOnWall.effectiveValue,1.3,accuracy:1e-8)
        XCTAssertThrowsError(try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,
            document:layout,expectedGeometryRevision:staleRevision))
        component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
        layout.surface.openings=[]
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:nil,
            document:layout,expectedGeometryRevision:component.geometryRevision)
        actual=try XCTUnwrap(ProjectStore(fileURL:url).surveys.first?.checkpoints.first?.document)
        XCTAssertTrue(actual.room.openings.isEmpty)
        XCTAssertTrue(actual.room.walls[0].openingIDs.isEmpty)
        XCTAssertEqual(try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.area),10,accuracy:1e-8)
    }

    func testLayoutOpeningSyncUsesLocalFrameAndPreservesOtherOpenings() throws {
        var document=scanDocument(name:"Mur tourné")
        let source=document.room.walls[0].provenance
        document.room.walls[0].start = .init(x:5,y:1,z:2)
        document.room.walls[0].end = .init(x:5,y:1,z:6)
        let id=document.room.walls[0].id
        document=try SurveyPlanEditing.addingDoor(document,wallID:id,width:0.8,height:2,position:0.2)
        let preserved=document.room.openings[0]
        let before=Surface2D(name:"Mur",kind:.wall,contour:[.init(x:0,y:0),.init(x:4000,y:0),.init(x:4000,y:2500),.init(x:0,y:2500)],
            localFrame:.init(origin:.init(x:5,y:1,z:2),axisX:.init(x:0,y:0,z:1),axisY:.init(x:0,y:1,z:0)))
        var after=before
        after.openings=[.init(kind:.window,contour:[.init(x:2000,y:1000),.init(x:3000,y:1000),.init(x:3000,y:2000),.init(x:2000,y:2000)])]
        let result=try SurveyLayoutOpeningSync.apply(before:before,after:after,wallID:id,document:document)
        XCTAssertEqual(result.room.openings[0],preserved)
        XCTAssertEqual(result.room.openings[1].center,.init(x:5,y:2.5,z:4.5))
        XCTAssertEqual(result.room.openings[1].provenance.source,.manual)
        XCTAssertEqual(source.source,.roomPlan)
        after.openings[0].contour=after.openings[0].contour.map { .init(x:$0.x-1800,y:$0.y) }
        XCTAssertThrowsError(try SurveyLayoutOpeningSync.apply(before:before,after:after,wallID:id,document:document))
    }

    func testOppositePartitionLayoutHatchUpdatesBothFacesWithoutMirroringTheScan() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store=ProjectStore(fileURL:url)
        var document=scanDocument(name:"Cloison")
        document.wallWorkIntents=[.init(wallID:document.room.walls[0].id,use:.partition)]
        let saved=try store.saveScannedRoom(projectID:nil,newProjectName:"Cloison",surveyID:nil,
            surveyName:"Scan",roomID:nil,roomName:"Pièce",document:document)
        let surfaces=SurveyWorkGeometry.surfaces(in:store.surveys[0])
        var configuration=SurveyWorkGeometry.partition(surfaces)
        configuration.faceAFirst=[.init(facingID:"ba13",formatID:"1200x2400",surface:10)]
        configuration.faceBFirst=configuration.faceAFirst
        let workID=try store.createSurveyWork(surveyID:saved.surveyID,selections:surfaces,name:"Cloison",
            type:.distributionPartition,payload:.distributionPartition(configuration),roomID:nil)
        let component=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.components.first)
        let opposite=try XCTUnwrap(component.plans.first { component.isOppositeSide($0.sideRoomID) })
        var layout=try XCTUnwrap(component.document(for:opposite))
        var surface=try XCTUnwrap(component.surface)
        surface.openings=[.init(kind:.hatch,contour:[.init(x:1000,y:1000),.init(x:1600,y:1000),.init(x:1600,y:1600),.init(x:1000,y:1600)])]
        layout.surface=surface.mirroredComponentSide()
        try store.saveComponentPlan(projectID:saved.projectID,workID:workID,componentID:component.id,sideRoomID:opposite.sideRoomID,
            document:layout,expectedGeometryRevision:component.geometryRevision)
        let updated=try XCTUnwrap(store.project(id:saved.projectID)?.works.first?.cloisonDistributionConfiguration)
        XCTAssertEqual(updated.area,9.64,accuracy:1e-8)
        XCTAssertEqual(updated.faceAFirst[0].surface,9.64,accuracy:1e-8)
        XCTAssertEqual(updated.faceBFirst[0].surface,9.64,accuracy:1e-8)
        XCTAssertEqual(store.surveys[0].checkpoints[0].document.room.openings[0].positionOnWall.effectiveValue,1,accuracy:1e-8)
    }

    private func validateAllCheckpoints(in store: ProjectStore, surveyID: UUID) throws {
        let checkpoints = try XCTUnwrap(store.surveys.first { $0.id == surveyID }).checkpoints
        for checkpoint in checkpoints {
            try store.validateSurveyCheckpoint(surveyID: surveyID, checkpointID: checkpoint.id,
                expectedDocument: checkpoint.document)
        }
    }

    private func scanDocument(name: String) -> PlaquistoRoomDocument {
        let provenance = GeometryProvenance(source: .roomPlan, sourceIdentifier: UUID().uuidString, confidenceLabel: "high")
        let wall = PlaquistoWall(start: .init(x: 0, y: 0, z: 0), end: .init(x: 4, y: 0, z: 0),
            length: .init(rawValue: 4, provenance: provenance),
            height: .init(rawValue: 2.5, provenance: provenance), provenance: provenance)
        return PlaquistoRoomDocument(room: .init(name: name, walls: [wall],
            metadata: .init(source: .roomPlan, sourceObjectCount: 0)))
    }
}
