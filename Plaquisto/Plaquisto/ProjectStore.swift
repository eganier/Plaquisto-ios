import Foundation

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

    func createWork(projectID: UUID, name: String, type: WorkType, configuration: CeilingConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        let now = Date()
        let work = WorkItem(id: UUID(), projectID: projectID, name: name.trimmed, type: type, configuration: configuration, createdAt: now, updatedAt: now)
        next[projectIndex].works.insert(work, at: 0)
        next[projectIndex].updatedAt = now
        try commit(next)
        return work.id
    }

    func updateWork(_ work: WorkItem, configuration: CeilingConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].configuration = configuration
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func deleteWork(projectID: UUID, workID: UUID) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        next[projectIndex].works.removeAll { $0.id == workID }
        next[projectIndex].updatedAt = Date()
        try commit(next)
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

    private enum StoreError: Error { case projectNotFound, workNotFound }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
