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
    @Published private(set) var surveys: [ProjectSurveyRecord] = []
    @Published private(set) var lastError: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var storageIsReadable = true
    private struct Archive: Codable {
        var schemaVersion = 2
        var projects: [ProjectItem]
        var surveys: [ProjectSurveyRecord]

        private enum CodingKeys: String, CodingKey { case schemaVersion, projects, surveys }
        init(projects: [ProjectItem], surveys: [ProjectSurveyRecord]) {
            self.projects = projects; self.surveys = surveys
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            projects = try container.decode([ProjectItem].self, forKey: .projects)
            surveys = try container.decodeIfPresent([ProjectSurveyRecord].self, forKey: .surveys) ?? []
        }
    }

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
            self.fileURL = directory.appendingPathComponent("projects-v2.json")
        }
        load()
    }

    func project(id: UUID) -> ProjectItem? { projects.first { $0.id == id } }
    func surveys(projectID: UUID) -> [ProjectSurveyRecord] {
        surveys.filter { $0.projectID == projectID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Delete only the project survey. Derived works retain their independent
    /// geometry, layouts and quantities; remove references atomically with it.
    func deleteSurvey(projectID: UUID, surveyID: UUID) throws {
        guard surveys.contains(where: { $0.id == surveyID && $0.projectID == projectID }),
              let index=projects.firstIndex(where: { $0.id == projectID }) else { throw StoreError.invalidStructure }
        var next=projects
        let now=Date()
        for workIndex in next[index].works.indices {
            var detached=false
            for componentIndex in next[index].works[workIndex].components.indices {
                if next[index].works[workIndex].components[componentIndex].surveySource?.surveyID == surveyID {
                    next[index].works[workIndex].components[componentIndex].surveySource=nil
                    detached=true
                }
            }
            if detached {
                if next[index].works[workIndex].components.allSatisfy({ $0.surveySource == nil }) {
                    next[index].works[workIndex].surveySourceNeedsReview=false
                }
                next[index].works[workIndex].updatedAt=now
            }
        }
        next[index].updatedAt=now
        try commit(next,surveys:surveys.filter { $0.id != surveyID })
    }

    /// Edits the existing checkpoint without recreating the room or changing its
    /// spatial registration. A stale editor must not overwrite a newer revision.
    func updateSurveyRoom(surveyID: UUID, checkpointID: UUID,
                          expectedDocument: PlaquistoRoomDocument,
                          document: PlaquistoRoomDocument) throws {
        var next = surveys
        var nextProjects = projects
        guard let s = next.firstIndex(where: { $0.id == surveyID }),
              let c = next[s].checkpoints.firstIndex(where: { $0.id == checkpointID }),
              next[s].checkpoints[c].document == expectedDocument,
              document.initialRoom == expectedDocument.initialRoom else { throw StoreError.staleGeometry }
        try document.validate()
        let now = Date()
        let previousSurvey = next[s]
        next[s].checkpoints[c].document = document
        next[s].checkpoints[c].updatedAt = now
        next[s].updatedAt = now
        if hasEffectiveSurveyGeometryChange(before: previousSurvey, after: next[s], checkpointID: checkpointID) {
            next[s].checkpoints[c].needsReview = true
            next[s].checkpoints[c].workState = .awaitingValidation
            next[s].state = .readyForReview
            markWorksAffectedBySurveyGeometryChange(&nextProjects, before: previousSurvey,
                after: next[s], checkpointID: checkpointID, now: now)
        }
        try commit(nextProjects, surveys: next)
    }

    /// Explicitly approves the current portable geometry for métier attribution.
    /// A recovered provisional checkpoint can therefore be inspected/corrected and
    /// approved even when RoomBuilder can no longer resume after app relaunch.
    func validateSurveyCheckpoint(surveyID: UUID, checkpointID: UUID,
                                  expectedDocument: PlaquistoRoomDocument) throws {
        var next = surveys
        guard let s = next.firstIndex(where: { $0.id == surveyID }),
              let c = next[s].checkpoints.firstIndex(where: { $0.id == checkpointID }),
              next[s].checkpoints[c].document == expectedDocument else { throw StoreError.staleGeometry }
        try expectedDocument.validate()
        let now = Date()
        next[s].checkpoints[c].workState = .validated
        next[s].checkpoints[c].needsReview = false
        next[s].checkpoints[c].updatedAt = now
        next[s].updatedAt = now
        next[s].state = next[s].checkpoints.allSatisfy(\.isUsableForWork) ? .validated : .readyForReview
        try commit(projects, surveys: next)
    }

    struct ScanRoomSaveResult: Equatable {
        let projectID: UUID
        let surveyID: UUID
        let roomID: UUID
        let checkpointID: UUID
    }

    /// The whole continuous scan is committed once. Never partially creates a
    /// project when the second/third checkpoint is invalid or storage fails.
    @discardableResult
    func saveScanCampaign(_ draft: ScanCampaignDraft, projectID: UUID?, newProjectName: String,
                          surveyName: String, newProjectClient: String = "", newProjectAddress: String = "",
                          newProjectNotes: String = "") throws -> UUID {
        try draft.validate()
        guard !draft.includedChunks.isEmpty, !draft.hasUnreviewedDuplicates, !surveyName.trimmed.isEmpty,
              !surveys.contains(where: { $0.id == draft.id }) else { throw StoreError.invalidStructure }
        var next = projects
        let now = Date()
        let index: Int
        if let projectID {
            guard let i = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
            index = i
        } else {
            guard !newProjectName.trimmed.isEmpty else { throw StoreError.invalidWorkName }
            next.insert(.init(id: UUID(), name: newProjectName.trimmed, client: newProjectClient.trimmed,
                              address: newProjectAddress.trimmed, notes: newProjectNotes.trimmed, works: [],
                              createdAt: now, updatedAt: now), at: 0)
            index = 0
        }
        var survey = ProjectSurveyRecord(id: draft.id, projectID: next[index].id, name: surveyName.trimmed,
                                         state: .readyForReview, createdAt: now, updatedAt: now)
        survey.captureDiagnostic = draft.captureDiagnostic
        survey.captureLocation = draft.captureLocation
        survey.ceilingPlanNumbers = draft.ceilingPlanNumbers
        for chunk in draft.includedChunks {
            // A matching label alone never means it is the same business room.
            var name = chunk.name.trimmed
            var suffix = 2
            while next[index].rooms.contains(where: { $0.name.normalizedForComparison == name.normalizedForComparison }) {
                name = "\(chunk.name.trimmed) \(suffix)"; suffix += 1
            }
            let room = ProjectRoomRecord(name: name)
            next[index].rooms.append(room)
            var document = chunk.document
            if surveys.flatMap(\.checkpoints).contains(where: { $0.document.room.id == document.room.id }) {
                document = document.remappingDomainIDs()
            }
            document.room.name = name
            survey.checkpoints.append(.init(roomID: room.id, document: document,
                spatialLinkState: draft.sharesWorldSpace ? .sharedWorldSpace : .needsLink,
                workState: chunk.processingPending == true ? .provisional : .awaitingValidation,
                createdAt: now, updatedAt: now))
        }
        next[index].updatedAt = now
        try commit(next, surveys: surveys + [survey])
        return survey.id
    }

    /// Saves the business room and its portable scan checkpoint in one archive write.
    /// Opening then abandoning a screen cannot leave an empty Project, room or survey.
    @discardableResult
    func saveScannedRoom(projectID: UUID?, newProjectName: String?, surveyID: UUID?, surveyName: String,
                         roomID: UUID?, roomName: String, document: PlaquistoRoomDocument,
                         transformToSurvey: SurveyTransform3D = .identity,
                         spatialLinkState: SurveySpatialLinkState = .needsLink,
                         replacingExistingCapture: Bool = false) throws -> ScanRoomSaveResult {
        try document.validate()
        guard transformToSurvey.isValid, !roomName.trimmed.isEmpty, !surveyName.trimmed.isEmpty else {
            throw StoreError.invalidStructure
        }

        var nextProjects = projects
        var nextSurveys = surveys
        let now = Date()
        let resolvedProjectID: UUID
        let projectIndex: Int
        if let projectID {
            guard let index = nextProjects.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
            resolvedProjectID = projectID; projectIndex = index
        } else {
            guard surveyID == nil, roomID == nil, let name = newProjectName?.trimmed, !name.isEmpty else {
                throw StoreError.invalidWorkName
            }
            resolvedProjectID = UUID()
            nextProjects.insert(.init(id: resolvedProjectID, name: name, client: "", address: "", notes: "", works: [], createdAt: now, updatedAt: now), at: 0)
            projectIndex = 0
        }

        let resolvedRoomID: UUID
        if let roomID {
            guard nextProjects[projectIndex].rooms.contains(where: { $0.id == roomID }) else { throw StoreError.invalidStructure }
            resolvedRoomID = roomID
        } else if let existing = nextProjects[projectIndex].rooms.first(where: {
            $0.name.normalizedForComparison == roomName.normalizedForComparison
        }) {
            resolvedRoomID = existing.id
        } else {
            let room = ProjectRoomRecord(name: roomName.trimmed)
            nextProjects[projectIndex].rooms.append(room)
            resolvedRoomID = room.id
        }

        let resolvedSurveyID: UUID
        let surveyIndex: Int
        if let surveyID {
            guard let index = nextSurveys.firstIndex(where: { $0.id == surveyID && $0.projectID == resolvedProjectID }) else {
                throw StoreError.invalidStructure
            }
            resolvedSurveyID = surveyID; surveyIndex = index
        } else {
            let survey = ProjectSurveyRecord(projectID: resolvedProjectID, name: surveyName.trimmed,
                                            createdAt: now, updatedAt: now)
            nextSurveys.append(survey)
            resolvedSurveyID = survey.id; surveyIndex = nextSurveys.count - 1
        }

        var savedDocument = document
        savedDocument.room.name = roomName.trimmed
        let checkpointID: UUID
        if let index = nextSurveys[surveyIndex].checkpoints.firstIndex(where: { $0.roomID == resolvedRoomID }) {
            guard replacingExistingCapture else { throw StoreError.scanReplacementRequiresConfirmation }
            let previousSurvey = nextSurveys[surveyIndex]
            checkpointID = nextSurveys[surveyIndex].checkpoints[index].id
            nextSurveys[surveyIndex].checkpoints[index].document = savedDocument
            nextSurveys[surveyIndex].checkpoints[index].transformToSurvey = transformToSurvey
            nextSurveys[surveyIndex].checkpoints[index].spatialLinkState = spatialLinkState
            nextSurveys[surveyIndex].checkpoints[index].needsReview = true
            nextSurveys[surveyIndex].checkpoints[index].workState = .awaitingValidation
            nextSurveys[surveyIndex].checkpoints[index].updatedAt = now
            markWorksAffectedBySurveyGeometryChange(&nextProjects, before: previousSurvey,
                after: nextSurveys[surveyIndex], checkpointID: checkpointID, now: now)
        } else {
            // Saving the same source in another survey creates independent domain
            // identities while retaining the acquisition correlation metadata.
            if nextSurveys.flatMap(\.checkpoints).contains(where: { $0.document.room.id == savedDocument.room.id }) {
                savedDocument = savedDocument.remappingDomainIDs()
            }
            let checkpoint = ProjectRoomScanCheckpoint(roomID: resolvedRoomID, document: savedDocument,
                transformToSurvey: transformToSurvey, spatialLinkState: spatialLinkState,
                workState: .awaitingValidation, createdAt: now, updatedAt: now)
            nextSurveys[surveyIndex].checkpoints.append(checkpoint)
            checkpointID = checkpoint.id
        }
        nextSurveys[surveyIndex].state = .readyForReview
        nextSurveys[surveyIndex].updatedAt = now
        nextProjects[projectIndex].updatedAt = now
        try commit(nextProjects, surveys: nextSurveys)
        return .init(projectID: resolvedProjectID, surveyID: resolvedSurveyID, roomID: resolvedRoomID, checkpointID: checkpointID)
    }

    /// One transaction for forms: room creation/selection, work and optional plan.
    @discardableResult
    func createConfiguredWork(projectID: UUID, name: String, type: WorkType, payload: WorkConfiguration,
                              roomID: UUID?, newRoomName: String?, document: LayoutDocument? = nil, level: String? = nil, zone: String? = nil) throws -> UUID {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[i])
        var owner = roomID
        if case .openings(let opening) = payload, let reference = opening.sourceWorkID {
            guard let source = next[i].works.first(where: { $0.id == reference }) else { throw StoreError.workNotFound }
            owner = source.roomID
        } else if owner == nil, let roomName = newRoomName?.trimmed, !roomName.isEmpty {
            // This is the explicit room field submitted by the user, never an ouvrage-name parser.
            if let existing = next[i].rooms.first(where: { $0.name.normalizedForComparison == roomName.normalizedForComparison }) {
                owner = existing.id
            } else {
                let room = ProjectRoomRecord(name: roomName)
                next[i].rooms.append(room); owner = room.id
            }
        }
        if let owner { guard next[i].rooms.contains(where: { $0.id == owner }) else { throw StoreError.invalidStructure } }
        let now = Date()
        var work = WorkItem(id: UUID(), projectID: projectID, name: name.trimmed, type: type, payload: payload, createdAt: now, updatedAt: now)
        work.roomID = owner
        work.level = level?.trimmed.isEmpty == false ? level?.trimmed : nil
        work.zone = zone?.trimmed.isEmpty == false ? zone?.trimmed : nil
        work.layoutDocument = document
        work.layoutNeedsRecalculation = document == nil ? nil : false
        next[i].works.insert(work, at: 0); next[i].updatedAt = now
        try commit(next)
        return work.id
    }

    /// Organization is optional metadata, never a command to change physical geometry or side plans.
    func updateWorkOrganization(projectID: UUID, workID: UUID, roomID: UUID?, level: String?, zone: String?) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].works.firstIndex(where: { $0.id == workID }) else { throw StoreError.workNotFound }
        guard roomID.map({ id in next[i].rooms.contains { $0.id == id } }) ?? true else { throw StoreError.invalidStructure }
        next[i].works[j].roomID = roomID
        next[i].works[j].level = level?.trimmed.isEmpty == false ? level?.trimmed : nil
        next[i].works[j].zone = zone?.trimmed.isEmpty == false ? zone?.trimmed : nil
        next[i].works[j].updatedAt = Date(); next[i].updatedAt = Date()
        try commit(next)
    }

    /// The user deliberately keeps the ouvrage's current dimensions after
    /// reviewing a newer scan. No payload, component or layout is regenerated.
    func confirmKeepingCurrentSurveyGeometry(projectID: UUID, workID: UUID) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].works.firstIndex(where: { $0.id == workID }) else { throw StoreError.workNotFound }
        guard next[i].works[j].surveySourceNeedsReview else { return }
        let now = Date()
        next[i].works[j].surveySourceNeedsReview = false
        next[i].works[j].updatedAt = now
        next[i].updatedAt = now
        try commit(next)
    }

    func renameRoom(projectID: UUID, roomID: UUID, name: String) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].rooms.firstIndex(where: { $0.id == roomID }) else { throw StoreError.projectNotFound }
        guard !name.trimmed.isEmpty, !next[i].rooms.contains(where: { $0.id != roomID && $0.name.normalizedForComparison == name.normalizedForComparison }) else { throw StoreError.invalidWorkName }
        let oldName = next[i].rooms[j].name
        next[i].rooms[j].name = name.trimmed
        for k in next[i].works.indices where next[i].works[k].roomID == roomID {
            let work = next[i].works[k]
            if work.name == work.type.generatedName(roomName: oldName) {
                next[i].works[k].name = work.type.generatedName(roomName: name.trimmed)
            }
        }
        next[i].updatedAt = Date()
        try commit(next)
    }

    func renameWorkTitle(projectID: UUID, workID: UUID, title: String) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].works.firstIndex(where: { $0.id == workID }) else { throw StoreError.workNotFound }
        try validateWorkName(title, in: next[i], excluding: workID)
        next[i].works[j].name = title.trimmed
        next[i].works[j].updatedAt = Date(); next[i].updatedAt = Date()
        try commit(next)
    }

    @discardableResult
    func createRoom(projectID: UUID, name: String, floorAreaM2: Double? = nil) throws -> UUID {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        guard !name.trimmed.isEmpty,
              !next[i].rooms.contains(where: { $0.name.normalizedForComparison == name.normalizedForComparison }),
              floorAreaM2.map({ $0.isFinite && $0 > 0 }) ?? true else { throw StoreError.invalidWorkName }
        let room = ProjectRoomRecord(name: name.trimmed, floorAreaM2: floorAreaM2)
        next[i].rooms.append(room)
        next[i].updatedAt = Date()
        try commit(next)
        return room.id
    }

    /// Explicit ownership; never inferred again from display names.
    func assignWork(projectID: UUID, workID: UUID, ownerRoomID: UUID, adjacentRoomIDs: [UUID] = []) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].works.firstIndex(where: { $0.id == workID }) else { throw StoreError.workNotFound }
        let roomIDs = Set(next[i].rooms.map(\.id))
        guard roomIDs.contains(ownerRoomID), Set(adjacentRoomIDs).isSubset(of: roomIDs) else { throw StoreError.invalidStructure }
        if let sourceID = next[i].works[j].openingConfiguration?.sourceWorkID {
            guard next[i].works.first(where: { $0.id == sourceID })?.roomID == ownerRoomID else { throw StoreError.invalidStructure }
        }
        let isPartition = [.distributionPartition, .alveolarPartition].contains(next[i].works[j].type)
        guard adjacentRoomIDs.isEmpty || isPartition else { throw StoreError.invalidStructure }
        next[i].works[j].roomID = ownerRoomID
        next[i].works[j].linkedRoomIDs = Array(Set(adjacentRoomIDs).subtracting([ownerRoomID])).sorted { $0.uuidString < $1.uuidString }
        if isPartition {
            for k in next[i].works[j].components.indices {
                if next[i].works[j].components[k].referenceSideRoomID == nil {
                    next[i].works[j].components[k].referenceSideRoomID = ownerRoomID
                }
                for p in next[i].works[j].components[k].plans.indices where next[i].works[j].components[k].plans[p].sideRoomID == nil {
                    next[i].works[j].components[k].plans[p].sideRoomID = ownerRoomID
                }
            }
        }
        // Auxiliary openings inherit the reference work's owner, never count in the adjacent room.
        for k in next[i].works.indices where next[i].works[k].openingConfiguration?.sourceWorkID == workID {
            next[i].works[k].roomID = ownerRoomID
        }
        next[i].updatedAt = Date()
        try commit(next)
    }

    func suggestedPartitionOwner(projectID: UUID, roomIDs: [UUID]) -> UUID? {
        guard let project = project(id: projectID) else { return nil }
        let rooms = project.rooms.filter { roomIDs.contains($0.id) }
        guard rooms.count == Set(roomIDs).count, rooms.allSatisfy({ $0.floorAreaM2 != nil }) else { return nil }
        return rooms.sorted {
            if $0.floorAreaM2 == $1.floorAreaM2 { return $0.id.uuidString < $1.id.uuidString }
            return $0.floorAreaM2! < $1.floorAreaM2!
        }.first?.id
    }

    @discardableResult
    func addComponent(projectID: UUID, workID: UUID, name: String) throws -> UUID {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].works.firstIndex(where: { $0.id == workID }) else { throw StoreError.workNotFound }
        guard !name.trimmed.isEmpty,
              !next[i].works[j].components.contains(where: { $0.name.normalizedForComparison == name.normalizedForComparison }) else { throw StoreError.invalidWorkName }
        let component = WorkComponentRecord(name: name.trimmed)
        next[i].works[j].components.append(component)
        next[i].updatedAt = Date()
        try commit(next)
        return component.id
    }

    /// A workbook tab keeps its identity, geometry, side plans and adjacency links when renamed.
    func renameComponent(projectID: UUID, workID: UUID, componentID: UUID, name: String) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].works.firstIndex(where: { $0.id == workID }),
              let k = next[i].works[j].components.firstIndex(where: { $0.id == componentID }) else { throw StoreError.workNotFound }
        guard !name.trimmed.isEmpty, !next[i].works[j].components.contains(where: {
            $0.id != componentID && $0.name.normalizedForComparison == name.normalizedForComparison
        }) else { throw StoreError.invalidWorkName }
        next[i].works[j].components[k].name = name.trimmed
        next[i].works[j].components[k].surface?.name = name.trimmed
        next[i].works[j].updatedAt = Date()
        next[i].updatedAt = Date()
        try commit(next)
    }

    /// Called by a scan adapter after an explicit 3D match, or by a user identifying a full-span boundary.
    /// Registers evidence only: never resizes either component.
    func linkCeilingToWall(projectID: UUID, ceilingComponentID: UUID, edgeIndex: Int, wallComponentID: UUID,
                           roomID: UUID, origin: CeilingWallLink.Origin = .manual, sourceObservationID: String? = nil) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let ceilingWork = next[i].works.first(where: { $0.components.contains { $0.id == ceilingComponentID } }),
              let wallWork = next[i].works.first(where: { $0.components.contains { $0.id == wallComponentID } }),
              let ceiling = ceilingWork.components.first(where: { $0.id == ceilingComponentID })?.surface,
              let wall = wallWork.components.first(where: { $0.id == wallComponentID })?.surface,
              ceilingWork.roomID == roomID, wallWork.roomID == roomID || wallWork.linkedRoomIDs.contains(roomID),
              ceiling.kind == .ceiling, wall.kind == .wall,
              ComponentAdjacency.wallSpan(of: ceiling, edge: edgeIndex) != nil,
              origin != .scan || sourceObservationID?.isEmpty == false else { throw StoreError.invalidStructure }
        var links = next[i].ceilingWallLinks ?? []
        // Rebinding this edge is explicit. One complete wall span per room, no overlapping partial links.
        links.removeAll { $0.ceilingComponentID == ceilingComponentID && $0.edgeIndex == edgeIndex }
        guard !links.contains(where: { $0.roomID == roomID && $0.wallComponentID == wallComponentID }) else { throw StoreError.invalidStructure }
        links.append(.init(roomID: roomID, ceilingComponentID: ceilingComponentID, wallComponentID: wallComponentID,
            ceilingSurfaceID: ceiling.id, ceilingTopologyID: ceiling.topologyID, ceilingVertexCount: ceiling.contour.count,
            edgeIndex: edgeIndex, origin: origin, sourceObservationID: sourceObservationID))
        next[i].ceilingWallLinks = links; next[i].updatedAt = Date()
        try commit(next)
    }

    func removeCeilingWallLink(projectID: UUID, linkID: UUID) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        next[i].ceilingWallLinks?.removeAll { $0.id == linkID }
        next[i].updatedAt = Date()
        try commit(next)
    }

    func reviewComponentPlan(projectID: UUID, componentID: UUID, document: LayoutDocument) throws -> ComponentAdjacencyReview {
        guard let project = project(id: projectID) else { throw StoreError.projectNotFound }
        return ComponentAdjacency.review(project: project, componentID: componentID, proposed: document.surface)
    }

    /// Geometry belongs to the component; finishing and electrical layout belong to its side.
    /// The local edit and explicitly accepted adjacent changes commit atomically.
    func saveComponentPlan(projectID: UUID, workID: UUID, componentID: UUID, sideRoomID: UUID?, document: LayoutDocument, expectedGeometryRevision: Int? = nil,
                           adjacencyDecision: ComponentAdjacencyDecision = .undecided, reviewedAdjacency: ComponentAdjacencyReview? = nil,
                           newComponent: WorkComponentRecord? = nil) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == projectID }),
              let j = next[i].works.firstIndex(where: { $0.id == workID }) else { throw StoreError.workNotFound }
        // Insert the draft only in this transaction: failed validation or abandoned editors
        // must never leave an empty component in persistent storage.
        if !next[i].works[j].components.contains(where: { $0.id == componentID }), let newComponent {
            guard newComponent.id == componentID, newComponent.surface == nil, newComponent.plans.isEmpty,
                  !newComponent.name.trimmed.isEmpty,
                  !next[i].works[j].components.contains(where: {
                      $0.name.normalizedForComparison == newComponent.name.normalizedForComparison
                  }) else { throw StoreError.invalidStructure }
            next[i].works[j].components.append(newComponent)
        }
        guard let k = next[i].works[j].components.firstIndex(where: { $0.id == componentID }) else { throw StoreError.workNotFound }
        let work = next[i].works[j]
        let isPartition = [.distributionPartition, .alveolarPartition].contains(work.type)
        if isPartition {
            let storedSides = work.components[k].plans.compactMap(\.sideRoomID)
            guard sideRoomID.map({ $0 == work.roomID || work.linkedRoomIDs.contains($0) || storedSides.contains($0) }) ?? (work.roomID == nil) else { throw StoreError.invalidStructure }
        } else if sideRoomID != nil { throw StoreError.invalidStructure }
        guard !document.layers.isEmpty else { throw StoreError.invalidStructure }
        let expectedKind: LayoutSupportKind = work.type.category == .ceilings ? .ceiling : .wall
        guard document.surface.kind == expectedKind else { throw StoreError.invalidStructure }
        for layer in document.layers { _ = try SheetLayoutEngine.calculate(surface: document.surface, layer: layer) }
        var component = work.components[k]
        if let expectedGeometryRevision, expectedGeometryRevision != component.geometryRevision { throw StoreError.staleGeometry }
        if component.referenceSideRoomID == nil { component.referenceSideRoomID = sideRoomID }
        let opposite = component.isOppositeSide(sideRoomID)
        let surface = opposite ? document.surface.mirroredComponentSide() : document.surface
        let adjacency = ComponentAdjacency.review(project: next[i], componentID: componentID, proposed: surface)
        if !adjacency.changes.isEmpty {
            guard adjacencyDecision != .undecided else { throw StoreError.adjacencyConfirmationRequired }
            guard reviewedAdjacency == adjacency else { throw StoreError.staleAdjacency }
            if adjacencyDecision == .applyWalls {
                guard adjacency.canApply else { throw StoreError.invalidStructure }
                // Do not implicitly cascade into other ceilings touching the same wall.
                for change in adjacency.changes {
                    guard let w = next[i].works.firstIndex(where: { $0.components.contains { $0.id == change.link.wallComponentID } }),
                          let c = next[i].works[w].components.firstIndex(where: { $0.id == change.link.wallComponentID }),
                          let adjusted = change.proposedSurface else { throw StoreError.invalidStructure }
                    next[i].works[w].components[c].surface = adjusted
                    next[i].works[w].components[c].geometryRevision += 1
                    next[i].works[w].layoutNeedsRecalculation = true
                    next[i].works[w].updatedAt = Date()
                }
            }
        } else if let reviewedAdjacency, reviewedAdjacency != adjacency { throw StoreError.staleAdjacency }
        var framing = document.layers.first?.furring
        if opposite { framing?.offset.negate() }
        // The revision protects the whole shared support, including its physical frame.
        // An old editor must never restore the old frame after the opposite side moved it.
        if component.surface != surface || component.framing != framing {
            component.surface = surface
            component.framing = framing
            component.geometryRevision += 1
        }
        let index = component.plans.firstIndex { $0.sideRoomID == sideRoomID }
        var plan = index.map { component.plans[$0] } ?? ComponentLayoutPlan(sideRoomID: sideRoomID)
        plan.layers = document.layers
        for index in plan.layers.indices { plan.layers[index].furring = nil }
        plan.lighting = document.lighting
        plan.geometryRevision = component.geometryRevision
        if let index { component.plans[index] = plan } else { component.plans.append(plan) }
        next[i].works[j].components[k] = component
        if !work.isPartition && (work.components.count == 1 || work.components.contains(where: { $0.surveySource != nil })) {
            next[i].works[j].layoutNeedsRecalculation = true
        }
        next[i].works[j].updatedAt = Date()
        next[i].updatedAt = Date()
        try commit(next)
    }

    func createLayoutWork(projectID:UUID,name:String,type:WorkType,payload:WorkConfiguration,document:LayoutDocument) throws {
        var next = projects
        guard let i = next.firstIndex(where:{$0.id == projectID}) else { throw StoreError.projectNotFound }
        try validateWorkName(name,in:next[i])
        let now = Date()
        var work = WorkItem(id:UUID(),projectID:projectID,name:name,type:type,payload:payload,createdAt:now,updatedAt:now)
        work.layoutDocument = document; work.layoutNeedsRecalculation = false
        next[i].works.append(work); next[i].updatedAt = now
        try commit(next)
    }

    func updateLinkedLayout(projectID:UUID,workID:UUID,document:LayoutDocument) throws {
        guard let work = project(id: projectID)?.works.first(where: { $0.id == workID }),
              let current = work.layoutDocument, let component = work.components.first else { throw StoreError.invalidStructure }
        guard current != document else { return }
        try saveComponentPlan(projectID: projectID, workID: workID, componentID: component.id,
            sideRoomID: component.plans.first?.sideRoomID, document: document, expectedGeometryRevision: component.geometryRevision)
    }

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
    /// doublage. Le résultat est recalculé à chaque publication du projet.
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
            case .ceilingOnFurring, .ceilingOnRailsAndStuds, .modularCeiling, .openings, .paintingBeta:
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

    func deleteProject(id: UUID) throws {
        try commit(projects.filter { $0.id != id }, surveys: surveys.filter { $0.projectID != id })
    }

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
        let copiedIDs = Dictionary(uniqueKeysWithValues: source.works.map { ($0.id, UUID()) })
        let roomIDs = Dictionary(uniqueKeysWithValues: source.rooms.map { ($0.id, UUID()) })
        let componentIDs = Dictionary(uniqueKeysWithValues: source.works.flatMap(\.components).map { ($0.id, UUID()) })
        let copiedWorks = source.works.map { work in
            var payload = work.payload
            if case .openings(var configuration) = payload {
                configuration.sourceWorkID = configuration.sourceWorkID.flatMap { copiedIDs[$0] }
                payload = .openings(configuration)
            }
            var copy = WorkItem(id: copiedIDs[work.id]!, projectID: projectID, name: work.name, type: work.type, payload: payload, createdAt: now, updatedAt: now)
            copy.layoutDocument = work.layoutDocument; copy.layoutNeedsRecalculation = work.layoutNeedsRecalculation
            copy.surveySourceNeedsReview = work.surveySourceNeedsReview
            copy.roomID = work.roomID.flatMap { roomIDs[$0] }
            copy.level = work.level; copy.zone = work.zone
            copy.linkedRoomIDs = work.linkedRoomIDs.compactMap { roomIDs[$0] }
            copy.components = copiedComponents(work.components, roomIDs: roomIDs, componentIDs: componentIDs)
            return copy
        }
        var copy = ProjectItem(id: projectID, name: copyName, client: source.client, address: source.address, notes: source.notes, works: copiedWorks, createdAt: now, updatedAt: now)
        copy.rooms = source.rooms.map { ProjectRoomRecord(id: roomIDs[$0.id]!, name: $0.name, floorAreaM2: $0.floorAreaM2) }
        copy.ceilingWallLinks = try source.ceilingWallLinks?.map { link in
            var result = link
            guard let room = roomIDs[link.roomID], let ceilingID = componentIDs[link.ceilingComponentID],
                  let wallID = componentIDs[link.wallComponentID],
                  let sourceSurface = source.works.flatMap(\.components).first(where: { $0.id == link.ceilingComponentID })?.surface,
                  let copiedSurface = copiedWorks.flatMap(\.components).first(where: { $0.id == ceilingID })?.surface else { throw StoreError.invalidStructure }
            result.id = UUID(); result.roomID = room
            result.ceilingComponentID = ceilingID; result.wallComponentID = wallID
            // Preserve a deliberately invalid topology link as invalid; don't accidentally repair it on copy.
            if link.ceilingSurfaceID == sourceSurface.id { result.ceilingSurfaceID = copiedSurface.id }
            return result
        }
        let copiedSurveys = surveys.filter { $0.projectID == id }.map { sourceSurvey in
            var survey = sourceSurvey
            survey.id = UUID(); survey.projectID = projectID
            survey.createdAt = now; survey.updatedAt = now
            let originalNumbers=CeilingPlanNaming.numbers(in:sourceSurvey)
            survey.ceilingPlanNumbers=[:]
            survey.checkpoints = sourceSurvey.checkpoints.map { sourceCheckpoint in
                var checkpoint = sourceCheckpoint
                checkpoint.id = UUID()
                checkpoint.roomID = roomIDs[sourceCheckpoint.roomID]!
                checkpoint.document = sourceCheckpoint.document.remappingDomainIDs()
                for (old,new) in zip(sourceCheckpoint.document.room.ceilings,checkpoint.document.room.ceilings) {
                    survey.ceilingPlanNumbers?[new.id.uuidString]=originalNumbers[old.id.uuidString]
                }
                checkpoint.createdAt = now; checkpoint.updatedAt = now
                return checkpoint
            }
            return survey
        }
        let originalSurveys = surveys.filter { $0.projectID == id }
        for workIndex in copy.works.indices {
            for componentIndex in copy.works[workIndex].components.indices {
                guard var reference = source.works[workIndex].components[componentIndex].surveySource,
                      let surveyIndex = originalSurveys.firstIndex(where: { $0.id == reference.surveyID }),
                      let checkpointIndex = originalSurveys[surveyIndex].checkpoints.firstIndex(where: { $0.id == reference.checkpointID }) else { continue }
                let original = originalSurveys[surveyIndex].checkpoints[checkpointIndex]
                let copied = copiedSurveys[surveyIndex].checkpoints[checkpointIndex]
                let originalIDs = reference.kind == .wall ? original.document.room.walls.map(\.id) : original.document.room.slopes.map(\.id)
                let copiedIDs = reference.kind == .wall ? copied.document.room.walls.map(\.id) : copied.document.room.slopes.map(\.id)
                guard let surfaceIndex = originalIDs.firstIndex(of: reference.surfaceID), copiedIDs.indices.contains(surfaceIndex) else { continue }
                reference.surveyID = copiedSurveys[surveyIndex].id
                reference.checkpointID = copied.id
                reference.surfaceID = copiedIDs[surfaceIndex]
                copy.works[workIndex].components[componentIndex].surveySource = reference
            }
        }
        next.insert(copy, at: projectIndex + 1)
        try commit(next, surveys: surveys + copiedSurveys)
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

    func createWork(projectID: UUID, name: String, type: WorkType, modularCeilingConfiguration: ModularCeilingConfiguration) throws -> UUID {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[projectIndex])
        let now = Date()
        let work = WorkItem(
            id: UUID(),
            projectID: projectID,
            name: name.trimmed,
            type: type,
            modularCeilingConfiguration: modularCeilingConfiguration,
            createdAt: now,
            updatedAt: now
        )
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
        next[projectIndex].works[workIndex].layoutNeedsRecalculation = false
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, railStudCeilingConfiguration: RailStudCeilingConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .railStudCeiling(railStudCeilingConfiguration)
        next[projectIndex].works[workIndex].layoutNeedsRecalculation = false
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, paintingBetaConfiguration: PaintingBetaConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }),
              paintingBetaConfiguration.area.isFinite, paintingBetaConfiguration.area > 0 else { throw StoreError.invalidStructure }
        let current = next[projectIndex].works[workIndex]
        if current.components.contains(where: { $0.surveySource != nil }) {
            let measured = try current.components.compactMap(\.surface).reduce(0.0) { try $0 + $1.netMeasuredArea() / 1_000_000 }
            guard abs(measured - paintingBetaConfiguration.area) < 0.0001 else { throw SurveyWorkError.changedDimensions }
        }
        next[projectIndex].works[workIndex].payload = .paintingBeta(paintingBetaConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, modularCeilingConfiguration: ModularCeilingConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .modularCeiling(modularCeilingConfiguration)
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, doublageConfiguration: DoublageConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .peripheralLining(doublageConfiguration)
        next[projectIndex].works[workIndex].layoutNeedsRecalculation = false
        next[projectIndex].works[workIndex].updatedAt = Date()
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    func updateWork(_ work: WorkItem, cloisonDistributionConfiguration: CloisonDistributionConfiguration) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == work.projectID }),
              let workIndex = next[projectIndex].works.firstIndex(where: { $0.id == work.id }) else { throw StoreError.workNotFound }
        next[projectIndex].works[workIndex].payload = .distributionPartition(cloisonDistributionConfiguration)
        next[projectIndex].works[workIndex].layoutNeedsRecalculation = false
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
        next[projectIndex].works[workIndex].layoutNeedsRecalculation = false
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
        if let sourceID = openingConfiguration.sourceWorkID {
            guard let source = next[projectIndex].works.first(where: { $0.id == sourceID }) else { throw StoreError.workNotFound }
            next[projectIndex].works[workIndex].roomID = source.roomID
        }
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
        var copy = WorkItem(id: UUID(), projectID: projectID, name: copyName, type: source.type, payload: source.payload, createdAt: now, updatedAt: now)
        copy.layoutDocument = source.layoutDocument; copy.layoutNeedsRecalculation = source.layoutNeedsRecalculation
        copy.roomID = source.roomID
        copy.level = source.level; copy.zone = source.zone
        copy.linkedRoomIDs = source.linkedRoomIDs
        copy.components = copiedComponents(source.components, roomIDs: Dictionary(uniqueKeysWithValues: next[projectIndex].rooms.map { ($0.id, $0.id) }))
        next[projectIndex].works.insert(copy, at: workIndex + 1)
        next[projectIndex].updatedAt = now
        try commit(next)
        return copy.id
    }

    func deleteWork(projectID: UUID, workID: UUID) throws {
        var next = projects
        guard let projectIndex = next.firstIndex(where: { $0.id == projectID }) else { throw StoreError.projectNotFound }
        let removedComponents = Set(next[projectIndex].works.first(where: { $0.id == workID })?.components.map(\.id) ?? [])
        next[projectIndex].ceilingWallLinks?.removeAll { removedComponents.contains($0.ceilingComponentID) || removedComponents.contains($0.wallComponentID) }
        next[projectIndex].works.removeAll { $0.id == workID }
        for i in next[projectIndex].works.indices {
            guard case .openings(var configuration) = next[projectIndex].works[i].payload,
                  configuration.sourceWorkID == workID else { continue }
            configuration.sourceWorkID = nil
            next[projectIndex].works[i].payload = .openings(configuration)
        }
        next[projectIndex].updatedAt = Date()
        try commit(next)
    }

    /// Commit the configured ouvrage and every selected physical component in one
    /// archive write. Selection is revalidated against the latest scan and claims.
    @discardableResult
    func createSurveyWork(surveyID: UUID, selections: [SurveyWorkSurface], name: String,
                          type: WorkType, payload: WorkConfiguration, roomID: UUID?) throws -> UUID {
        guard let survey = surveys.first(where: { $0.id == surveyID }),
              !selections.isEmpty, Set(selections.map(\.id)).count == selections.count,
              selections.allSatisfy({ $0.source.surveyID == surveyID }) else { throw SurveyWorkError.invalidSelection }
        let selectedCheckpointIDs = Set(selections.map { $0.source.checkpointID })
        guard selectedCheckpointIDs.allSatisfy({ checkpointID in
            survey.checkpoints.first(where: { $0.id == checkpointID })?.isUsableForWork == true
        }) else { throw StoreError.scanCheckpointRequiresValidation }
        var next = projects
        guard let index = next.firstIndex(where: { $0.id == survey.projectID }) else { throw StoreError.projectNotFound }
        try validateWorkName(name, in: next[index])
        if let roomID, !next[index].rooms.contains(where: { $0.id == roomID }) { throw StoreError.invalidStructure }
        let available = SurveyWorkGeometry.surfaces(in: survey)
        // A future different treatment (e.g. paint on one existing side) may
        // reuse geometry. Exclusivity applies to this work family, not the scan.
        let claimed = next[index].works.filter { $0.type.category == type.category }
            .flatMap(\.components).compactMap(\.surveySource)
        var current: [SurveyWorkSurface] = []
        for selection in selections {
            guard let resolved = available.first(where: { $0.id == selection.id }),
                  resolved.sourceDocument == selection.sourceDocument else { throw SurveyWorkError.staleSource }
            guard !claimed.contains(where: { SurveyWorkGeometry.hasSameSource($0, resolved.source) }) else {
                throw SurveyWorkError.alreadyAssigned
            }
            current.append(resolved)
        }
        let area = SurveyWorkGeometry.totalArea(current)
        let submittedArea: Double
        switch (type, payload) {
        case (.distributionPartition, .distributionPartition(let configuration)):
            guard current.allSatisfy({ $0.source.kind == .wall && SurveyWorkGeometry.isDesignedPartition($0) }),
                  abs(configuration.height-SurveyWorkGeometry.partition(current).height) < 0.0001 else {
                throw SurveyWorkError.changedDimensions
            }
            submittedArea = configuration.area
        case (.paintingBeta, .paintingBeta(let configuration)):
            submittedArea = configuration.area
        case (.ceilingOnFurring, .ceiling(let configuration)):
            guard current.allSatisfy({ $0.source.kind == .ceiling }) else { throw SurveyWorkError.invalidSelection }
            submittedArea = configuration.enteredArea ?? configuration.length * configuration.width
        case (.peripheralLiningStuds, .peripheralLining(let configuration)):
            guard current.allSatisfy({ $0.source.kind == .wall }) else { throw SurveyWorkError.invalidSelection }
            guard configuration.measuredWallRuns == SurveyWorkGeometry.lining(current).measuredWallRuns,
                  configuration.wallCount == current.count else { throw SurveyWorkError.changedDimensions }
            submittedArea = configuration.area
        case (.peripheralLiningFurrings, .furringLining(let configuration)):
            guard current.allSatisfy({ $0.source.kind == .wall }) else { throw SurveyWorkError.invalidSelection }
            guard configuration.measuredWallRuns == SurveyWorkGeometry.furring(current).measuredWallRuns,
                  configuration.wallCount == current.count else { throw SurveyWorkError.changedDimensions }
            submittedArea = configuration.area
        default: throw SurveyWorkError.invalidSelection
        }
        guard area.isFinite, area > 0, submittedArea.isFinite, abs(area - submittedArea) < 0.0001 else {
            throw SurveyWorkError.changedDimensions
        }
        let now = Date()
        var work = WorkItem(id: UUID(), projectID: survey.projectID, name: name.trimmed,
            type: type, payload: payload, createdAt: now, updatedAt: now)
        work.roomID = roomID
        work.components = current.map { selected in
            var component = WorkComponentRecord(name: selected.surface.name)
            component.surface = selected.surface
            component.surveySource = selected.source
            component.referenceSideRoomID = selected.roomID
            // Geometry is available immediately, without pretending a default
            // board grid is a user-validated calepinage.
            return component
        }
        next[index].works.insert(work, at: 0)
        next[index].updatedAt = now
        try commit(next)
        return work.id
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
            let archive = try decoder.decode(Archive.self, from: Data(contentsOf: fileURL))
            guard archive.schemaVersion == 2 else { throw StoreError.invalidStructure }
            try validateStructure(archive.projects, surveys: archive.surveys)
            projects = archive.projects
            surveys = archive.surveys
            lastError = nil
        } catch {
            storageIsReadable = false
            lastError = "Les projets enregistrés n’ont pas pu être ouverts."
        }
    }

    private func commit(_ next: [ProjectItem], surveys nextSurveys: [ProjectSurveyRecord]? = nil) throws {
        guard storageIsReadable else { throw StoreError.invalidStructure }
        do {
            var committedSurveys = nextSurveys ?? surveys
            for i in committedSurveys.indices {
                committedSurveys[i].ceilingPlanNumbers=CeilingPlanNaming.numbers(in:committedSurveys[i])
            }
            try validateStructure(next, surveys: committedSurveys)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(Archive(projects: next, surveys: committedSurveys)).write(to: fileURL, options: .atomic)
            projects = next
            surveys = committedSurveys
            lastError = nil
        } catch {
            lastError = "L’enregistrement local a échoué."
            throw error
        }
    }

    private func copiedComponents(_ components: [WorkComponentRecord], roomIDs: [UUID: UUID], componentIDs: [UUID: UUID] = [:]) -> [WorkComponentRecord] {
        components.map { source in
            var copy = source
            copy.id = componentIDs[source.id] ?? UUID()
            // A standalone duplicate is a new independent work, not a second
            // claim on the scan. Project duplication reconnects mapped sources.
            copy.surveySource = nil
            copy.referenceSideRoomID = source.referenceSideRoomID.flatMap { roomIDs[$0] }
            copy.surface?.id = UUID()
            copy.surface?.openings = source.surface?.openings.map { opening in
                var result = opening; result.id = UUID(); return result
            } ?? []
            copy.plans = source.plans.map { original in
                var plan = original
                plan.id = UUID()
                plan.sideRoomID = original.sideRoomID.flatMap { roomIDs[$0] }
                plan.layers = original.layers.map { layer in var result = layer; result.id = UUID(); return result }
                return plan
            }
            return copy
        }
    }

    /// Marks only ouvrages whose effective métier surface changed. Renaming a
    /// room or editing unrelated metadata must not invalidate quantities.
    private func markWorksAffectedBySurveyGeometryChange(_ projects: inout [ProjectItem],
                                                          before: ProjectSurveyRecord,
                                                          after: ProjectSurveyRecord,
                                                          checkpointID: UUID,
                                                          now: Date) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == before.projectID }) else { return }
        let previousSurfaces = SurveyWorkGeometry.surfaces(in: before)
        let currentSurfaces = SurveyWorkGeometry.surfaces(in: after)

        func resolved(_ source: SurveySurfaceSource, in values: [SurveyWorkSurface]) -> Surface2D? {
            values.first(where: { SurveyWorkGeometry.hasSameSource($0.source, source) })?.surface
        }

        var projectChanged = false
        for workIndex in projects[projectIndex].works.indices {
            let affected = projects[projectIndex].works[workIndex].components.contains { component in
                guard let source = component.surveySource,
                      source.surveyID == before.id,
                      source.checkpointID == checkpointID else { return false }
                guard let old = resolved(source, in: previousSurfaces),
                      let new = resolved(source, in: currentSurfaces) else { return true }
                return !sameEffectiveSurfaceGeometry(old, new)
            }
            guard affected else { continue }
            projects[projectIndex].works[workIndex].surveySourceNeedsReview = true
            projects[projectIndex].works[workIndex].updatedAt = now
            projectChanged = true
        }
        if projectChanged { projects[projectIndex].updatedAt = now }
    }

    private func hasEffectiveSurveyGeometryChange(before: ProjectSurveyRecord,
                                                  after: ProjectSurveyRecord,
                                                  checkpointID: UUID) -> Bool {
        let previous = SurveyWorkGeometry.surfaces(in: before).filter { $0.source.checkpointID == checkpointID }
        let current = SurveyWorkGeometry.surfaces(in: after).filter { $0.source.checkpointID == checkpointID }
        guard previous.count == current.count else { return true }
        return previous.contains { old in
            guard let new = current.first(where: { SurveyWorkGeometry.hasSameSource($0.source, old.source) }) else {
                return true
            }
            return !sameEffectiveSurfaceGeometry(old.surface, new.surface)
        }
    }

    private func sameEffectiveSurfaceGeometry(_ lhs: Surface2D, _ rhs: Surface2D) -> Bool {
        guard lhs.kind == rhs.kind, lhs.contour == rhs.contour,
              lhs.localFrame == rhs.localFrame,
              lhs.openings.count == rhs.openings.count else { return false }
        return zip(lhs.openings, rhs.openings).allSatisfy { pair in
            pair.0.kind == pair.1.kind && pair.0.contour == pair.1.contour
        }
    }

    private func validateStructure(_ projects: [ProjectItem], surveys: [ProjectSurveyRecord]) throws {
        var ids = Set<UUID>()
        func claim(_ id: UUID) throws { guard ids.insert(id).inserted else { throw StoreError.invalidStructure } }
        for project in projects {
            try claim(project.id)
            let rooms = Set(project.rooms.map(\.id))
            let workIDs = Set(project.works.map(\.id))
            for room in project.rooms {
                try claim(room.id)
                guard !room.name.trimmed.isEmpty, room.floorAreaM2.map({ $0.isFinite && $0 > 0 }) ?? true else { throw StoreError.invalidStructure }
            }
            for work in project.works {
                try claim(work.id)
                if let source = work.openingConfiguration?.sourceWorkID {
                    guard source != work.id, workIDs.contains(source) else { throw StoreError.invalidStructure }
                }
                guard work.projectID == project.id,
                      work.roomID.map({ rooms.contains($0) }) ?? true,
                      Set(work.linkedRoomIDs).isSubset(of: rooms) else { throw StoreError.invalidStructure }
                for component in work.components {
                    try claim(component.id)
                    var sides = Set<UUID?>()
                    for plan in component.plans {
                        try claim(plan.id)
                        guard sides.insert(plan.sideRoomID).inserted,
                              plan.sideRoomID.map({ rooms.contains($0) }) ?? true,
                              plan.geometryRevision <= component.geometryRevision else { throw StoreError.invalidStructure }
                    }
                }
            }
            var edges = Set<String>(), walls = Set<String>()
            let components = project.works.flatMap(\.components)
            for link in project.ceilingWallLinks ?? [] {
                try claim(link.id)
                guard rooms.contains(link.roomID), link.ceilingComponentID != link.wallComponentID,
                      components.first(where: { $0.id == link.ceilingComponentID })?.surface?.kind == .ceiling,
                      components.first(where: { $0.id == link.wallComponentID })?.surface?.kind == .wall,
                      link.edgeIndex >= 0, link.edgeIndex < link.ceilingVertexCount, link.ceilingVertexCount >= 3,
                      link.origin != .scan || link.sourceObservationID?.isEmpty == false,
                      edges.insert("\(link.ceilingComponentID)/\(link.edgeIndex)").inserted,
                      walls.insert("\(link.roomID)/\(link.wallComponentID)").inserted else { throw StoreError.invalidStructure }
            }
        }
        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        for survey in surveys {
            try claim(survey.id)
            guard let project = projectsByID[survey.projectID], !survey.name.trimmed.isEmpty,
                  survey.levelName.map({ !$0.trimmed.isEmpty }) ?? true else { throw StoreError.invalidStructure }
            let rooms = Set(project.rooms.map(\.id))
            var checkpointRooms = Set<UUID>()
            for checkpoint in survey.checkpoints {
                try claim(checkpoint.id)
                try claim(checkpoint.document.room.id)
                guard rooms.contains(checkpoint.roomID), checkpointRooms.insert(checkpoint.roomID).inserted,
                      checkpoint.transformToSurvey.isValid,
                      checkpoint.createdAt <= checkpoint.updatedAt else { throw StoreError.invalidStructure }
                try checkpoint.document.validate()
            }
            guard survey.createdAt <= survey.updatedAt else { throw StoreError.invalidStructure }
        }
        for project in projects {
            var claims = Set<String>()
            for work in project.works {
                for component in work.components {
                    guard let source = component.surveySource else { continue }
                    guard let survey = surveys.first(where: { $0.id == source.surveyID && $0.projectID == project.id }),
                          survey.checkpoints.contains(where: { $0.id == source.checkpointID }),
                          source.boundaryIndex >= 0,
                          component.surface?.kind == (source.kind == .wall ? .wall : .ceiling) else { throw StoreError.invalidStructure }
                    let key = "\(work.type.category.rawValue)/\(source.surveyID)/\(source.checkpointID)/\(source.surfaceID)/\(source.boundaryIndex)/\(source.kind.rawValue)"
                    guard claims.insert(key).inserted else { throw StoreError.invalidStructure }
                }
            }
        }
    }

    private enum StoreError: Error, LocalizedError {
        case projectNotFound, workNotFound, invalidWorkName, duplicateWorkName, invalidStructure, staleGeometry, adjacencyConfirmationRequired, staleAdjacency, scanReplacementRequiresConfirmation, scanCheckpointRequiresValidation
        var errorDescription: String? {
            switch self {
            case .scanCheckpointRequiresValidation: "Contrôlez puis validez les surfaces du relevé avant de les utiliser dans un ouvrage."
            case .scanReplacementRequiresConfirmation: "Cette pièce possède déjà un scan dans ce relevé. Confirmez son remplacement pour continuer."
            case .adjacencyConfirmationRequired: "Des murs sont reliés à ce plafond. Confirmez leurs nouvelles longueurs depuis le plan du composant, ou choisissez de conserver les murs."
            case .staleAdjacency: "Un mur ou un lien a changé depuis votre confirmation. Vérifiez à nouveau les longueurs proposées."
            case .staleGeometry: "Le contour ou l’ossature commune a changé depuis l’ouverture de ce plan. Rouvrez cette sous-partie du calepinage."
            case .invalidStructure: "Les données ou leurs liens sont incompatibles. Aucune modification n’a été enregistrée."
            case .projectNotFound: "Projet introuvable."
            case .workNotFound: "Ouvrage ou composant introuvable."
            case .invalidWorkName: "Renseignez un nom valide."
            case .duplicateWorkName: "Ce nom est déjà utilisé."
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedForComparison: String {
        trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
