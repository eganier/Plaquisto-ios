import Foundation

struct OpeningJoineryConflict: Equatable {
    let openingCount: Int
    let minimumDepth: Double
    let smallestEnteredDepth: Double
    let maximumCompatibleInsulationThickness: Double
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectItem] = []
    @Published private(set) var lastError: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Plaquisto", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("projects.json")
        }
        load()
    }

    func project(id: UUID) -> ProjectItem? { projects.first { $0.id == id } }

    func workNameExists(projectID: UUID, name: String, excluding workID: UUID? = nil) -> Bool {
        guard let project = project(id: projectID) else { return false }
        let normalizedName = name.normalizedForComparison
        return project.works.contains {
            $0.id != workID && $0.name.normalizedForComparison == normalizedName
        }
    }

    func defaultWorkName(projectID: UUID, type: WorkType) -> String {
        let baseName = type.defaultNameBase
        var number = 1
        while workNameExists(projectID: projectID, name: "\(baseName) \(number)") {
            number += 1
        }
        return "\(baseName) \(number)"
    }

    func openingHeightSuggestions(projectID: UUID) -> [OpeningWorkSystem: OpeningHeightSuggestion] {
        openingHeightOptions(projectID: projectID).compactMapValues(\.first)
    }

    /// Contrôle les tapées des ouvertures liées avec la composition actuelle du
    /// doublage. Le résultat est recalculé à chaque publication du chantier.
    func openingJoineryConflict(projectID: UUID, referenceWorkID: UUID) -> OpeningJoineryConflict? {
        guard let project = project(id: projectID),
              let referenceWork = project.works.first(where: { $0.id == referenceWorkID }),
              let reference = openingHeightOptions(projectID: projectID)
                .values
                .flatMap({ $0 })
                .first(where: { $0.sourceWorkID == referenceWorkID }),
              let minimumDepth = reference.minimumJoineryLiningDepth else { return nil }

        let incompatibleDepths = project.works.compactMap(\.openingConfiguration)
            .filter { $0.sourceWorkID == referenceWorkID }
            .flatMap(\.openings)
            .compactMap { opening -> Double? in
                guard opening.mountingMode == .onJoineryLining,
                      let depth = opening.revealDepth,
                      depth > 0,
                      depth + 0.000_1 < minimumDepth else { return nil }
                return depth
            }

        guard let smallestDepth = incompatibleDepths.min() else { return nil }
        let currentInsulationThickness: Double = switch referenceWork.type {
        case .peripheralLiningFurrings:
            Double(referenceWork.furringLiningConfiguration?.firstInsulation.thicknessMM ?? 0) / 1_000
        case .peripheralLiningStuds:
            referenceWork.doublageConfiguration.map { configuration in
                let millimeters = configuration.insulationEnabled
                    ? configuration.firstInsulation.thicknessMM + (configuration.insulationLayers == 2 ? configuration.secondInsulation.thicknessMM : 0)
                    : 0
                return Double(millimeters) / 1_000
            } ?? 0
        default:
            0
        }
        let fixedCompositionDepth = max(0, minimumDepth - currentInsulationThickness)
        return OpeningJoineryConflict(
            openingCount: incompatibleDepths.count,
            minimumDepth: minimumDepth,
            smallestEnteredDepth: smallestDepth,
            maximumCompatibleInsulationThickness: max(0, smallestDepth - fixedCompositionDepth)
        )
    }

    func openingHeightOptions(projectID: UUID) -> [OpeningWorkSystem: [OpeningHeightSuggestion]] {
        guard let works = project(id: projectID)?.works else { return [:] }

        func height(of work: WorkItem) -> Double? {
            switch work.type {
            case .peripheralLiningStuds:
                work.doublageConfiguration?.height
            case .distributionPartition:
                work.cloisonDistributionConfiguration?.height
            case .alveolarPartition:
                work.alveolarPartitionConfiguration?.height
            case .peripheralLiningBonded:
                work.bondedLiningConfiguration?.height
            case .peripheralLiningFurrings:
                work.furringLiningConfiguration?.height
            case .peripheralLiningAdhesiveFacing:
                work.adhesiveFacingConfiguration?.height
            case .ceilingOnFurring, .ceilingOnRailsAndStuds, .openings:
                nil
            }
        }

        func suggestions(types: Set<WorkType>) -> [OpeningHeightSuggestion] {
            works.compactMap { work in
                guard types.contains(work.type), let value = height(of: work), value > 0 else { return nil }
                let framing: (spacing: Double, doubled: Bool) = switch work.type {
                case .peripheralLiningStuds:
                    (work.doublageConfiguration?.spacing ?? 0.60, work.doublageConfiguration?.doubledStuds ?? false)
                case .distributionPartition:
                    (work.cloisonDistributionConfiguration?.spacing ?? 0.60, work.cloisonDistributionConfiguration?.doubledStuds ?? false)
                case .peripheralLiningFurrings:
                    (work.furringLiningConfiguration?.furringSpacing ?? 0.60, false)
                default:
                    (0.60, false)
                }
                let minimumJoineryLiningDepth: Double? = switch work.type {
                case .peripheralLiningFurrings:
                    work.furringLiningConfiguration.map { configuration in
                        let insulation = configuration.insulationEnabled ? configuration.firstInsulation.thicknessMM : 0
                        let facing = facingThicknessMM(
                            layers: [configuration.firstSkin, configuration.secondSkin, configuration.thirdSkin],
                            activeLayerCount: configuration.layers,
                            quantityNames: configuration.quantities.map(\.name)
                        )
                        return Double(insulation) / 1_000 + 0.015 + facing / 1_000
                    }
                case .peripheralLiningStuds:
                    work.doublageConfiguration.map { configuration in
                        let insulation = configuration.insulationEnabled
                            ? configuration.firstInsulation.thicknessMM + (configuration.insulationLayers == 2 ? configuration.secondInsulation.thicknessMM : 0)
                            : 0
                        let facing = facingThicknessMM(
                            layers: [configuration.firstSkin, configuration.secondSkin],
                            activeLayerCount: configuration.layers,
                            quantityNames: configuration.quantities.map(\.name)
                        )
                        return Double(insulation) / 1_000 + facing / 1_000
                    }
                default:
                    nil
                }
                return OpeningHeightSuggestion(
                    sourceWorkID: work.id,
                    height: value,
                    sourceWorkName: work.name,
                    spacing: framing.spacing,
                    doubledStuds: framing.doubled,
                    minimumJoineryLiningDepth: minimumJoineryLiningDepth
                )
            }
        }

        return [
            .furringLining: suggestions(types: [.peripheralLiningFurrings]),
            .railStudLining: suggestions(types: [.peripheralLiningStuds]),
            .distributionPartition: suggestions(types: [.distributionPartition, .alveolarPartition])
        ].filter { !$0.value.isEmpty }
    }

    private func facingThicknessMM<Selection>(
        layers: [[Selection]],
        activeLayerCount: Int,
        quantityNames: [String]
    ) -> Double where Selection: OpeningFacingSelection {
        let selectedLayers = layers.prefix(max(0, activeLayerCount))
        return selectedLayers.reduce(0) { total, layer in
            let candidates = layer.map(\.openingFacingID) + quantityNames
            return total + (candidates.compactMap(Self.plasterboardThicknessMM).first ?? 13)
        }
    }

    private static func plasterboardThicknessMM(in text: String) -> Double? {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard let expression = try? NSRegularExpression(pattern: #"ba\s*([0-9]{2})"#),
              let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let range = Range(match.range(at: 1), in: normalized) else { return nil }
        return Double(normalized[range])
    }

    func createProject(name: String, client: String, address: String, notes: String) throws -> UUID {
        let now = Date()
        let project = ProjectItem(id: UUID(), name: name.trimmed, client: client.trimmed, address: address.trimmed, notes: notes.trimmed, works: [], createdAt: now, updatedAt: now)
        var next = projects
        next.insert(project, at: 0)
        try commit(next)
        return project.id
    }

    func updateProject(id: UUID, name: String, client: String, address: String, notes: String) throws {
        var next = projects
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].name = name.trimmed
        next[index].client = client.trimmed
        next[index].address = address.trimmed
        next[index].notes = notes.trimmed
        next[index].updatedAt = Date()
        try commit(next)
    }

    func deleteProject(id: UUID) throws { try commit(projects.filter { $0.id != id }) }

    @discardableResult
    func duplicateProject(id: UUID) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == id }) else { throw StoreError.projectNotFound }
        let source = next[projectIndex]
        let existingNames = Set(next.map(\.name))
        let baseName = "\(source.name) – copie"
        var copyName = baseName
        var number = 2
        while existingNames.contains(copyName) {
            copyName = "\(baseName) \(number)"
            number += 1
        }
        let projectID = UUID()
        let now = Date()
        let copiedWorks = source.works.map { work in
            WorkItem(id: UUID(), projectID: projectID, name: work.name, type: work.type, payload: work.payload, createdAt: now, updatedAt: now)
        }
        let copy = ProjectItem(id: projectID, name: copyName, client: source.client, address: source.address, notes: source.notes, works: copiedWorks, createdAt: now, updatedAt: now)
        next.insert(copy, at: projectIndex + 1)
        try commit(next)
        return projectID
    }

    func createWork(projectID: UUID, name: String, type: WorkType, configuration: CeilingConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(id: UUID(), projectID: projectID, name: name.trimmed, type: type, configuration: configuration, createdAt: now, updatedAt: now)
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, railStudCeilingConfiguration: RailStudCeilingConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(id: UUID(), projectID: projectID, name: name.trimmed, type: type, railStudCeilingConfiguration: railStudCeilingConfiguration, createdAt: now, updatedAt: now)
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, doublageConfiguration: DoublageConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(
            id: UUID(),
            projectID: projectID,
            name: name.trimmed,
            type: type,
            doublageConfiguration: doublageConfiguration,
            createdAt: now,
            updatedAt: now
        )
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, cloisonDistributionConfiguration: CloisonDistributionConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(
            id: UUID(),
            projectID: projectID,
            name: name.trimmed,
            type: type,
            cloisonDistributionConfiguration: cloisonDistributionConfiguration,
            createdAt: now,
            updatedAt: now
        )
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, alveolarPartitionConfiguration: AlveolarPartitionConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(
            id: UUID(),
            projectID: projectID,
            name: name.trimmed,
            type: type,
            alveolarPartitionConfiguration: alveolarPartitionConfiguration,
            createdAt: now,
            updatedAt: now
        )
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, bondedLiningConfiguration: BondedLiningConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(id: UUID(), projectID: projectID, name: name.trimmed, type: type, bondedLiningConfiguration: bondedLiningConfiguration, createdAt: now, updatedAt: now)
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, furringLiningConfiguration: FurringLiningConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(id: UUID(), projectID: projectID, name: name.trimmed, type: type, furringLiningConfiguration: furringLiningConfiguration, createdAt: now, updatedAt: now)
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, adhesiveFacingConfiguration: AdhesiveFacingConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(id: UUID(), projectID: projectID, name: name.trimmed, type: type, adhesiveFacingConfiguration: adhesiveFacingConfiguration, createdAt: now, updatedAt: now)
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func createWork(projectID: UUID, name: String, type: WorkType, openingConfiguration: OpeningConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(
            id: UUID(),
            projectID: projectID,
            name: name.trimmed,
            type: type,
            openingConfiguration: openingConfiguration,
            createdAt: now,
            updatedAt: now
        )
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func updateWork(_ work: WorkItem, configuration: CeilingConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .ceiling(configuration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, railStudCeilingConfiguration: RailStudCeilingConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .railStudCeiling(railStudCeilingConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, doublageConfiguration: DoublageConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .peripheralLining(doublageConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, cloisonDistributionConfiguration: CloisonDistributionConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .distributionPartition(cloisonDistributionConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, alveolarPartitionConfiguration: AlveolarPartitionConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .alveolarPartition(alveolarPartitionConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, bondedLiningConfiguration: BondedLiningConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .bondedLining(bondedLiningConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, furringLiningConfiguration: FurringLiningConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .furringLining(furringLiningConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, adhesiveFacingConfiguration: AdhesiveFacingConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .adhesiveFacing(adhesiveFacingConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, openingConfiguration: OpeningConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .openings(openingConfiguration)
        if let roomName = openingRoomName(for: openingConfiguration, in: next[projectIndex]), !roomName.isEmpty {
            let generatedName = WorkType.openings.generatedName(roomName: roomName)
            if !next[projectIndex].works.contains(where: {
                $0.id != work.id && $0.name.normalizedForComparison == generatedName.normalizedForComparison
            }) {
                next[projectIndex].works[workIndex].name = generatedName
            }
        }
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func renameWork(projectID: UUID, workID: UUID, roomName: String) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == workID }) else {
            throw StoreError.workNotFound
        }

        let cleanRoomName = roomName.trimmed
        guard !cleanRoomName.isEmpty else { throw StoreError.invalidWorkName }
        let work = next[projectIndex].works[workIndex]
        let generatedName = work.type.generatedName(roomName: cleanRoomName)
        try validateWorkName(generatedName, in: next[projectIndex], excluding: workID)

        let now = Date()
        next[projectIndex].works[workIndex].name = generatedName
        next[projectIndex].works[workIndex].updatedAt = now

        if work.type == .openings,
           case .openings(var configuration) = next[projectIndex].works[workIndex].payload {
            configuration.roomName = cleanRoomName
            next[projectIndex].works[workIndex].payload = .openings(configuration)
        } else {
            for index in next[projectIndex].works.indices {
                guard case .openings(var configuration) = next[projectIndex].works[index].payload,
                      configuration.sourceWorkID == workID else { continue }
                let openingName = WorkType.openings.generatedName(roomName: cleanRoomName)
                let conflicts = next[projectIndex].works.contains {
                    $0.id != next[projectIndex].works[index].id &&
                    $0.name.normalizedForComparison == openingName.normalizedForComparison
                }
                guard !conflicts else { continue }
                configuration.roomName = cleanRoomName
                next[projectIndex].works[index].payload = .openings(configuration)
                next[projectIndex].works[index].name = openingName
                next[projectIndex].works[index].updatedAt = now
            }
        }

        next[projectIndex].updatedAt = now
        try commit(next)
    }

    @discardableResult
    func duplicateWork(projectID: UUID, workID: UUID) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == workID }) else { throw StoreError.workNotFound }
        let source = next[projectIndex].works[workIndex]
        let existingNames = Set(next[projectIndex].works.map { $0.name.normalizedForComparison })
        let baseName = "\(source.name) – copie"
        var copyName = baseName
        var number = 2
        while existingNames.contains(copyName.normalizedForComparison) {
            copyName = "\(baseName) \(number)"
            number += 1
        }
        let now = Date()
        let copy = WorkItem(id: UUID(), projectID: projectID, name: copyName, type: source.type, payload: source.payload, createdAt: now, updatedAt: now)
        next[projectIndex].works.insert(copy, at: workIndex + 1)
        next[projectIndex].updatedAt = now
        try commit(next)
        return copy.id
    }

    func deleteWork(projectID: UUID, workID: UUID) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        next[projectIndex].works.removeAll { $0.id == workID }
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    private func validateWorkName(_ name: String, in project: ProjectItem, excluding workID: UUID? = nil) throws {
        let normalizedName = name.normalizedForComparison
        guard !normalizedName.isEmpty else { throw StoreError.invalidWorkName }
        guard !project.works.contains(where: {
            $0.id != workID && $0.name.normalizedForComparison == normalizedName
        }) else {
            throw StoreError.duplicateWorkName
        }
    }

    private func openingRoomName(for configuration: OpeningConfiguration, in project: ProjectItem) -> String? {
        if let sourceWorkID = configuration.sourceWorkID,
           let source = project.works.first(where: { $0.id == sourceWorkID }) {
            return source.inferredRoomName
        }
        return configuration.roomName?.trimmed
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            projects = try decoder.decode([ProjectItem].self, from: Data(contentsOf: fileURL))
            lastError = nil
        } catch {
            lastError = "Les chantiers enregistrés n’ont pas pu être ouverts."
        }
    }

    private func commit(_ next: [ProjectItem]) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(next).write(to: fileURL, options: .atomic)
            projects = next
            lastError = nil
        } catch {
            lastError = "L’enregistrement local a échoué."
            throw error
        }
    }

    private enum StoreError: Error { case projectNotFound, workNotFound, invalidWorkName, duplicateWorkName }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedForComparison: String {
        trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
