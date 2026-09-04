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
        let configuration = CeilingConfiguration(length: 8, width: 5, support: "Dalle béton", plenum: 30)
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
        XCTAssertEqual(WorkCategory.allCases.count, 4)
    }
}
