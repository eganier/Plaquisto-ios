import XCTest
@testable import Plaquisto

@MainActor
final class ProjectStoreTests: XCTestCase {
    private func componentDocument(kind: LayoutSupportKind = .wall) -> LayoutDocument {
        LayoutDocument(surface: Surface2D(name: "Mur A", kind: kind, contour: [
            .init(x: 0, y: 0), .init(x: 4000, y: 0), .init(x: 4000, y: 2500), .init(x: 0, y: 2500)
        ]), layers: [.init(furring: .init(parallelToBoards: true, spacing: 600, offset: 100))])
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
        XCTAssertEqual(WorkCategory.allCases.count, 4)
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
}
