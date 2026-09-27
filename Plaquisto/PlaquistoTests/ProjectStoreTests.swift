import XCTest
import SwiftUI
@testable import Plaquisto

@MainActor
final class ProjectStoreTests: XCTestCase {
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
        XCTAssertEqual(result.supplies.first(where: { $0.name == "Fourrure F45" })?.quantity, 52)
        let union = CombinedQuantityCalculator.calculate(works: [first, first, second], catalogue: catalogue)
        XCTAssertEqual(union.totalArea, result.totalArea)
        XCTAssertEqual(union.supplies.first(where: { $0.name == "Fourrure F45" })?.quantity, 52)
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
        XCTAssertEqual(try XCTUnwrap(suggestions[.railStudLining]?.minimumJoineryLiningDepth), 0.126, accuracy: 0.000_1)
        XCTAssertEqual(suggestions[.distributionPartition]?.height, 2.48)
        XCTAssertEqual(suggestions[.distributionPartition]?.sourceWorkName, "Cloison chambre")
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
        XCTAssertEqual(result.supplies.first(where: { $0.name == "Rails" })?.quantity ?? 0, 32, accuracy: 0.001)
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
        XCTAssertEqual(WorkCategory.allCases.count, 5)
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

    func testHistoricalCheckpointWithoutWorkStateRequiresReviewAfterDecoding() throws {
        let checkpoint = ProjectRoomScanCheckpoint(roomID: UUID(), document: scanDocument(name: "Ancien relevé"),
            spatialLinkState: .sharedWorldSpace)
        let encoded = try JSONEncoder().encode(checkpoint)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["workState"])
        let decoded = try JSONDecoder().decode(ProjectRoomScanCheckpoint.self, from: encoded)
        XCTAssertEqual(decoded.effectiveWorkState, .awaitingValidation)
        XCTAssertFalse(decoded.isUsableForWork, "Missing historical state is not proof of user approval")
    }

    func testProvisionalSurveyCheckpointRequiresExplicitValidationBeforeWorkCreation() throws {
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
        XCTAssertFalse(checkpoint.isUsableForWork)
        XCTAssertEqual(ProjectStore(fileURL: fileURL).surveys.first?.checkpoints.first?.effectiveWorkState, .provisional)
        let selected = SurveyWorkGeometry.surfaces(in: survey)
        XCTAssertThrowsError(try store.createSurveyWork(surveyID: surveyID, selections: selected,
            name: "Doublage prématuré", type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(selected)), roomID: nil))

        // A recovered live checkpoint remains useful: explicit visual control can
        // validate it even when the acquisition pipeline cannot resume RoomBuilder.
        try store.validateSurveyCheckpoint(surveyID: surveyID, checkpointID: checkpoint.id,
            expectedDocument: checkpoint.document)
        survey = try XCTUnwrap(store.surveys.first { $0.id == surveyID })
        checkpoint = try XCTUnwrap(survey.checkpoints.first)
        XCTAssertEqual(checkpoint.effectiveWorkState, .validated)
        XCTAssertFalse(checkpoint.needsReview)
        XCTAssertEqual(survey.state, .validated)
        _ = try store.createSurveyWork(surveyID: surveyID,
            selections: SurveyWorkGeometry.surfaces(in: survey), name: "Doublage contrôlé",
            type: .peripheralLiningStuds,
            payload: .peripheralLining(SurveyWorkGeometry.lining(SurveyWorkGeometry.surfaces(in: survey))),
            roomID: nil)
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
        let configuration = SurveyWorkGeometry.partition(selected)
        XCTAssertEqual(configuration.area, 7.5, accuracy: 1e-8)
        let workID = try store.createSurveyWork(surveyID: surveyID, selections: selected,
            name: "Bureau", type: .distributionPartition, payload: .distributionPartition(configuration), roomID: nil)
        let work = try XCTUnwrap(store.project(id: projectID)?.works.first { $0.id == workID })
        XCTAssertTrue(work.isPartition)
        XCTAssertEqual(work.components.count, 1, "Two sides must not create two physical partitions")
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

    func testSurveyGeometryChangeMarksWorkWithoutChangingQuantitiesAndMetadataDoesNot() throws {
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
        XCTAssertTrue(flagged.surveySourceNeedsReview)
        XCTAssertEqual(flagged.payload, originalWork.payload)
        XCTAssertEqual(flagged.components, originalWork.components)
        XCTAssertEqual(store.surveys.first?.checkpoints.first?.effectiveWorkState, .awaitingValidation)
        XCTAssertEqual(ProjectStore(fileURL: fileURL).project(id: saved.projectID)?.works.first?.surveySourceNeedsReview, true)
        XCTAssertThrowsError(try store.validateSurveyCheckpoint(surveyID: saved.surveyID,
            checkpointID: saved.checkpointID, expectedDocument: renamed),
            "A stale review must not validate geometry that changed afterwards")

        try store.updateWork(flagged, doublageConfiguration: try XCTUnwrap(flagged.doublageConfiguration))
        flagged = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID })
        XCTAssertTrue(flagged.surveySourceNeedsReview, "Saving configuration must not silently accept a newer scan")

        let projectCopyID = try store.duplicateProject(id: saved.projectID)
        XCTAssertTrue(try XCTUnwrap(store.project(id: projectCopyID)?.works.first).surveySourceNeedsReview)
        let standaloneCopyID = try store.duplicateWork(projectID: saved.projectID, workID: workID)
        XCTAssertFalse(try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == standaloneCopyID }).surveySourceNeedsReview)

        try store.confirmKeepingCurrentSurveyGeometry(projectID: saved.projectID, workID: workID)
        let accepted = try XCTUnwrap(store.project(id: saved.projectID)?.works.first { $0.id == workID })
        XCTAssertFalse(accepted.surveySourceNeedsReview)
        XCTAssertEqual(accepted.payload, originalWork.payload)
        XCTAssertEqual(accepted.components, originalWork.components)
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
        XCTAssertEqual(quantities.supplies[0].name, "Surface à peindre (bêta)")
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
        XCTAssertEqual(try XCTUnwrap(store.project(id: saved.projectID)?.works.first?.doublageConfiguration?.area), 20, accuracy: 0.00001) // draft until saved
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
