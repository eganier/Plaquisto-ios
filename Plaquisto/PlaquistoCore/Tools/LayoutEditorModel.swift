import Foundation
import SwiftUI
import UIKit

struct LayoutCatalogFormat: Identifiable, Hashable {
    var id: String
    var title: String
    var width: Double
    var length: Double
    var productID: String? = nil
    var fourTaperedEdges = false
    var family = ""
    var function = ""
    var functionTitle: String {
        switch function {
        case "standard": return "Standard"
        case "hydrofuge": return "Hydrofuge H1"
        case "incendie": return "Protection incendie"
        case "phonique": return "Phonique"
        case "haute_durete": return "Haute dureté"
        case "quatre_bords_amincis": return "Quatre bords amincis"
        case "tres_haute_resistance_eau": return "Très haute résistance à l’eau"
        default: return title // Preserve unrecognized catalog functions instead of labelling them Standard.
        }
    }
    static func identifier(productID: String, width: Double, length: Double) -> String {
        "\(productID)-\(width)-\(length)"
    }
    var label: String { "\(title) · \(Int(width / 10)) × \(Int(length / 10)) cm" }
}

struct SavedLayoutDocument: Codable, Equatable, Identifiable {
    var id: UUID
    var document: LayoutDocument
    var createdAt: Date
    var updatedAt: Date
    var title: String { document.surface.name }

    init(id:UUID = UUID(), document:LayoutDocument, createdAt:Date = Date(), updatedAt:Date? = nil) {
        self.id = id; self.document = document; self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
    private enum CodingKeys:String,CodingKey { case id,document,createdAt,updatedAt }
    init(from decoder:Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        id = try values.decode(UUID.self,forKey:.id)
        document = try values.decode(LayoutDocument.self,forKey:.document)
        updatedAt = try values.decode(Date.self,forKey:.updatedAt)
        // Older libraries recorded only their last save date; keep that known date.
        createdAt = try values.decodeIfPresent(Date.self,forKey:.createdAt) ?? updatedAt
    }
}

@MainActor
final class LayoutEditorModel: ObservableObject {
    @Published private(set) var document: LayoutDocument?
    @Published private(set) var selectedSkinID: UUID?
    var editingDocument: LayoutDocument? {
        document.map { LayoutSkinEditing($0, selectedID: selectedSkinID).document }
    }
    func selectSkin(_ id: UUID) {
        guard !isOptimizing, editingGestureOriginal == nil, document?.layers.contains(where: { $0.id == id }) == true,
              selectedSkinID != id else { return }
        selectedSkinID = id
        result = nil; resultDocument = nil
        optimizationMessage = nil; optimizationFailed = false
        recalculate()
    }
    private func reconcileSkin() {
        if document?.layers.contains(where: { $0.id == selectedSkinID }) != true {
            selectedSkinID = document?.layers.first?.id
        }
    }
    private func storedDocument(from edited: LayoutDocument) -> LayoutDocument {
        guard let document else { return edited }
        return LayoutSkinEditing(document, selectedID: selectedSkinID).restoring(edited)
    }
    func applyEditing(_ edited: LayoutDocument) { apply(storedDocument(from: edited)) }
    private var editingGestureOriginal: LayoutDocument?
    func previewEditing(_ edited: LayoutDocument) {
        if editingGestureOriginal == nil { editingGestureOriginal = document }
        preview(storedDocument(from: edited))
    }
    func finishEditingGesture(from original: LayoutDocument) {
        let stored = editingGestureOriginal ?? storedDocument(from: original)
        editingGestureOriginal = nil
        finishGesture(from: stored)
    }
    func cancelEditingGesture(restoring original: LayoutDocument) {
        let stored = editingGestureOriginal ?? storedDocument(from: original)
        editingGestureOriginal = nil
        cancelGesture(restoring: stored)
    }
    @Published private(set) var savedDocuments: [SavedLayoutDocument] = []
    @Published private(set) var result: SheetLayoutResult?
    private(set) var resultDocument: LayoutDocument?
    @Published private(set) var error: String?
    @Published private(set) var isCalculating = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var saveError: String?
    @Published private(set) var isOptimizing = false
    @Published private(set) var optimizationMessage: String?
    @Published private(set) var optimizationFailed = false
    @Published private(set) var lightingWarning: String?
    private var past: [LayoutDocument] = []
    private var future: [LayoutDocument] = []
    private var calculation: Task<Void, Never>?
    private var revision = 0
    private var pendingBoardOptimization = false
    private let defaults: UserDefaults
    private let draftKey = "plaquisto.tools.layout.draft.v1"
    private let libraryKey = "plaquisto.tools.layout.library.v1"
    private var currentSavedID: UUID?
    private let persistsStandaloneLibrary: Bool

    init(defaults: UserDefaults = .standard, persistsStandaloneLibrary: Bool = true) {
        self.defaults = defaults
        self.persistsStandaloneLibrary = persistsStandaloneLibrary
        guard persistsStandaloneLibrary else { return }
        if let data = defaults.data(forKey: libraryKey) {
            savedDocuments = (try? JSONDecoder().decode([SavedLayoutDocument].self, from: data)) ?? []
        }
        if savedDocuments.isEmpty, let data = defaults.data(forKey: draftKey) {
            do {
                let d = try JSONDecoder().decode(LayoutDocument.self, from: data)
                guard d.schemaVersion == 1, !d.layers.isEmpty else { throw LayoutGeometryError.invalidFormat }
                savedDocuments = [.init(document: d)]
                if persistLibrary() { defaults.removeObject(forKey: draftKey) }
            } catch { saveError = "Le brouillon enregistré n’a pas pu être relu." }
        }
    }

    func open(_ saved: SavedLayoutDocument) {
        editingGestureOriginal = nil
        currentSavedID = saved.id
        document = saved.document
        document?.layers = saved.document.layers.map { $0.forSurface(saved.document.surface) }
        reconcileSkin()
        past = []; future = []; updateHistory(); recalculate()
    }

    func startNew() {
        editingGestureOriginal = nil
        calculation?.cancel()
        calculation = nil
        if persistsStandaloneLibrary { defaults.removeObject(forKey: draftKey) }
        currentSavedID = nil
        document = nil
        selectedSkinID = nil
        past = []; future = []; result = nil; error = nil; isCalculating = false; updateHistory()
    }

    func reloadSavedLibrary() {
        guard persistsStandaloneLibrary, document == nil,
              let data=defaults.data(forKey:libraryKey) else { return }
        do { savedDocuments=try JSONDecoder().decode([SavedLayoutDocument].self,from:data) }
        catch { saveError="Les calepinages enregistrés n’ont pas pu être relus." }
    }

    func saveCurrentAndClose() {
        guard persistsStandaloneLibrary else { return }
        guard let document else { return }
        if let currentSavedID, let index = savedDocuments.firstIndex(where: { $0.id == currentSavedID }) {
            savedDocuments[index].document = document
            savedDocuments[index].updatedAt = Date()
        } else {
            let saved = SavedLayoutDocument(document: document)
            savedDocuments.append(saved)
            currentSavedID = saved.id
        }
        savedDocuments.sort { $0.updatedAt > $1.updatedAt }
        guard persistLibrary() else { return }
        defaults.removeObject(forKey: draftKey)
        startNew()
    }

    func delete(_ saved: SavedLayoutDocument) {
        let previous = savedDocuments
        savedDocuments.removeAll { $0.id == saved.id }
        if !persistLibrary() { savedDocuments = previous }
    }

    func rename(_ saved:SavedLayoutDocument, to title:String) {
        let name = title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, let index = savedDocuments.firstIndex(where:{$0.id == saved.id}) else { return }
        let previous = savedDocuments
        savedDocuments[index].document.surface.name = name
        savedDocuments[index].updatedAt = Date()
        if !persistLibrary() { savedDocuments = previous }
    }

    func apply(_ newValue: LayoutDocument) {
        var newValue = newValue
        newValue.layers = newValue.layers.map { $0.forSurface(newValue.surface) }
        guard newValue != document else { return }
        let shouldOptimize = newValue.surface.kind == .ceiling && document?.surface.id == newValue.surface.id &&
            document?.layers.first(where: { $0.id == selectedSkinID }).map { old in
                newValue.layers.first(where: { $0.id == old.id }).map { old.orientation != $0.orientation || old.referenceEdge != $0.referenceEdge } ?? false
            } == true
        if let document { past.append(document); if past.count > 100 { past.removeFirst() } }
        future = []; document = newValue; reconcileSkin(); updateHistory(); persistDraft(); recalculate()
        if shouldOptimize {
            if isOptimizing { pendingBoardOptimization = true } else { optimize(furring:false) }
        }
    }

    func preview(_ value: LayoutDocument) {
        calculation?.cancel(); revision += 1; isCalculating = false
        document = value
    }
    func cancelGesture(restoring original:LayoutDocument) {
        document = original
        recalculate()
    }

    func optimize(furring:Bool) {
        guard let original = document, let projection = editingDocument, let layer = projection.layers.first, !isOptimizing else { return }
        let expectedSkinID = selectedSkinID
        isOptimizing = true; optimizationMessage = nil; optimizationFailed = false
        Task {
            defer {
                isOptimizing = false
                if pendingBoardOptimization { pendingBoardOptimization = false; optimize(furring:false) }
            }
            let worker = Task.detached(priority:.userInitiated) {
                try LayoutPlanning.optimize(surface:original.surface,layer:layer,furring:furring)
            }
            do {
                let value = try await worker.value
                guard document == original, selectedSkinID == expectedSkinID else { return }
                var copy = projection; copy.layers[0] = value; applyEditing(copy)
                optimizationMessage = value == layer ? "Aucune meilleure disposition trouvée parmi les essais." : "Meilleure disposition testée appliquée. Vous pouvez annuler cette modification."
            } catch { optimizationFailed = true; optimizationMessage = error.localizedDescription }
            isOptimizing = false
        }
    }

    func finishGesture(from original: LayoutDocument) {
        guard var updated = document, updated != original else { return }
        do {
            if updated.surface.contour != original.surface.contour {
                updated.surface = try original.surface.movingVertices(to:updated.surface.contour)
                document = updated
            }
            try LayoutGeometry.validate(updated.surface.contour)
            for opening in updated.surface.openings { try LayoutGeometry.validate(opening.contour) }
            if updated.lighting != original.lighting, let lighting = updated.lighting,
               !LayoutPlanning.lightingFits(lighting,surface:updated.surface) { throw LayoutLightingEditError.invalidPlacement }
            past.append(original); if past.count > 100 { past.removeFirst() }; future = []
            updateHistory(); persistDraft(); recalculate()
        } catch {
            document = original; recalculate()
            saveError = "Déplacement annulé : \(error.localizedDescription)"
        }
    }

    func editVertices(_ points: [LayoutPoint]) {
        guard var copy = document else { return }
        do {
            try LayoutGeometry.validate(points)
            if points.count == copy.surface.contour.count {
                copy.surface = try copy.surface.movingVertices(to:points)
            } else {
                copy.surface.previousContourIntents.append(copy.surface.editableIntent)
                copy.surface.contour = points
                copy.surface.topologyID = UUID()
                copy.surface.contourIntent = .init(sketch:points)
                copy.surface.dimensionCorrections = []
                copy.surface.edgeTones = points.indices.map { [.blue,.orange,.purple,.green,.teal][$0%5] }
                for i in copy.layers.indices { copy.layers[i].referenceEdge = nil }
            }
            apply(copy)
        } catch { saveError = error.localizedDescription }
    }

    func undo() {
        guard let previous = past.popLast(), let document else { return }
        future.append(document); self.document = previous; reconcileSkin(); updateHistory(); persistDraft(); recalculate()
    }
    func redo() {
        guard let next = future.popLast(), let document else { return }
        past.append(document); self.document = next; reconcileSkin(); updateHistory(); persistDraft(); recalculate()
    }
    private func updateHistory() { canUndo = !past.isEmpty; canRedo = !future.isEmpty }
    private func persistDraft() {
        guard persistsStandaloneLibrary else { return }
        do {
            if let document { defaults.set(try JSONEncoder().encode(document), forKey: draftKey) }
            saveError = nil
        } catch { saveError = "Impossible d’enregistrer ce brouillon." }
    }
    @discardableResult private func persistLibrary() -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(savedDocuments), forKey: libraryKey)
            saveError = nil
            return true
        } catch { saveError = "Impossible d’enregistrer les calepinages."; return false }
    }
    private func recalculate(delay: Bool = false) {
        calculation?.cancel(); revision += 1
        guard let document = editingDocument, let layer = document.layers.first else { return }
        lightingWarning = document.lighting.map { LayoutPlanning.lightingFits($0,surface:document.surface) } == false
            ? "Un spot empiète sur une ouverture, un bord ou un autre spot. Ouvrez Éclairage pour revoir la répartition." : nil
        let expectedRevision = revision
        isCalculating = true
        calculation = Task { [weak self] in
            if delay { try? await Task.sleep(nanoseconds: 40_000_000) }
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                Result { try SheetLayoutEngine.calculate(surface: document.surface, layer: layer) }
            }
            let output = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self, self.revision == expectedRevision else { return }
            switch output {
            case .success(let value): self.resultDocument = document; self.result = value; self.error = nil
            case .failure(let e): self.result = nil; self.error = e.localizedDescription
            }
            self.isCalculating = false
        }
    }
}

func layoutCM(_ millimetres: Double) -> String {
    (millimetres / 10).formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))) + " cm"
}
func layoutMM(_ millimetres: Double) -> String {
    millimetres.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))) + " mm"
}
func layoutArea(_ value: Double) -> String {
    (value / 1_000_000).formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(2))) + " m²"
}

// Keeps partial decimal input such as "0," and supports signed offsets.
struct LayoutDimensionField: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    let title: String
    @Binding var millimetres: Double
    var signed = false
    var tint: Color? = nil
    var unit = "cm"
    var displayScale = 0.1
    var showsDoneButton = true
    @State private var text = ""
    @State private var editing = false
    var body: some View {
        Group {
            if atlantique {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Atlantique.Typography.caption).foregroundStyle(tint ?? Atlantique.Palette.muted)
                    HStack {
                        input.font(Atlantique.Typography.heading).frame(minWidth: 32, maxWidth: .infinity, minHeight: 38)
                        Text(unit).font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
            HStack {
            Text(title).foregroundStyle(tint ?? Color.primary)
            Spacer(minLength: 12)
            input.multilineTextAlignment(.trailing).frame(width: 100, height: 34)
            Text(unit).foregroundStyle(.secondary)
            }
            }
        }
        .onAppear { synchronize() }
        .onChange(of: millimetres) { _, _ in if !editing { synchronize() } }
    }
    private var input: some View {
        PlaquistoNumericField(text: $text, signed: signed, onEditingChanged: { active in
                editing = active
                if !active { synchronize() }
            })
                .accessibilityLabel(title)
                .onChange(of: text) { _, value in
                    if value.isEmpty { millimetres = 0 }
                    else if let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite { millimetres = number / displayScale }
                }
    }
    private func synchronize() {
        text = millimetres == 0 ? "" : (millimetres * displayScale).formatted(.number.locale(Locale(identifier: "fr_FR")).grouping(.never).precision(.fractionLength(0...3)))
    }
}
