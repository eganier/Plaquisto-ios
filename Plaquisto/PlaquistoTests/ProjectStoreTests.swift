import XCTest
@testable import Plaquisto

@MainActor
final class ProjectStoreTests: XCTestCase {
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

    func testLegacyProjectsAreMigratedToTheNewConfigurationFormat() throws {
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

        XCTAssertEqual(store.project(id: projectID)?.works.first?.ceilingConfiguration?.length, 6)
        XCTAssertEqual(store.project(id: projectID)?.works.last?.doublageConfiguration?.area, 20)
        XCTAssertNil(store.lastError)
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
