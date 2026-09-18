import Foundation
import SwiftUI
import UIKit

struct LayoutCatalogFormat: Identifiable, Hashable {
    var id: String
    var title: String
    var width: Double
    var length: Double
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
    @Published private(set) var savedDocuments: [SavedLayoutDocument] = []
    @Published private(set) var result: SheetLayoutResult?
    @Published private(set) var error: String?
    @Published private(set) var isCalculating = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var saveError: String?
    @Published private(set) var isOptimizing = false
    @Published private(set) var optimizationMessage: String?
    @Published private(set) var lightingWarning: String?
    private var past: [LayoutDocument] = []
    private var future: [LayoutDocument] = []
    private var calculation: Task<Void, Never>?
    private var revision = 0
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
        currentSavedID = saved.id
        document = saved.document
        document?.layers = saved.document.layers.map { $0.forSurface(saved.document.surface) }
        past = []; future = []; updateHistory(); recalculate()
    }

    func startNew() {
        calculation?.cancel()
        calculation = nil
        if persistsStandaloneLibrary { defaults.removeObject(forKey: draftKey) }
        currentSavedID = nil
        document = nil
        past = []; future = []; result = nil; error = nil; isCalculating = false; updateHistory()
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
        if let document { past.append(document); if past.count > 100 { past.removeFirst() } }
        future = []; document = newValue; updateHistory(); persistDraft(); recalculate()
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
        guard let original = document, let layer = original.layers.first, !isOptimizing else { return }
        isOptimizing = true; optimizationMessage = nil
        Task {
            let worker = Task.detached(priority:.userInitiated) {
                try LayoutPlanning.optimize(surface:original.surface,layer:layer,furring:furring)
            }
            do {
                let value = try await worker.value
                guard document == original else { isOptimizing = false; return }
                var copy = original; copy.layers[0] = value; apply(copy)
                optimizationMessage = value == layer ? "Aucune meilleure position trouvée parmi les positions testées." : "Meilleure position testée appliquée. Vous pouvez annuler cette modification."
            } catch { optimizationMessage = error.localizedDescription }
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
        future.append(document); self.document = previous; updateHistory(); persistDraft(); recalculate()
    }
    func redo() {
        guard let next = future.popLast(), let document else { return }
        past.append(document); self.document = next; updateHistory(); persistDraft(); recalculate()
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
        guard let document, let layer = document.layers.first else { return }
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
            case .success(let value): self.result = value; self.error = nil
            case .failure(let e): self.result = nil; self.error = e.localizedDescription
            }
            self.isCalculating = false
        }
    }
}

func layoutCM(_ millimetres: Double) -> String {
    (millimetres / 10).formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...2))) + " cm"
}
func layoutMM(_ millimetres: Double) -> String {
    millimetres.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))) + " mm"
}
func layoutArea(_ value: Double) -> String {
    (value / 1_000_000).formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(2))) + " m²"
}

// Keeps partial decimal input such as "0," and supports signed offsets.
struct LayoutDimensionField: View {
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
        HStack {
            Text(title).foregroundStyle(tint ?? Color.primary)
            Spacer(minLength: 12)
            LayoutSelectAllTextField(text: $text, keyboardType: signed ? .numbersAndPunctuation : .decimalPad, showsDoneButton:showsDoneButton) { active in
                editing = active
                if !active { synchronize() }
            }
                .frame(width: 100, height: 34)
                .accessibilityLabel(title)
                .onChange(of: text) { _, value in
                    if value.isEmpty { millimetres = 0 }
                    else if let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite { millimetres = number / displayScale }
                }
            Text(unit).foregroundStyle(.secondary)
        }
        .onAppear { synchronize() }
        .onChange(of: millimetres) { _, _ in if !editing { synchronize() } }
    }
    private func synchronize() {
        text = millimetres == 0 ? "" : (millimetres * displayScale).formatted(.number.locale(Locale(identifier: "fr_FR")).grouping(.never).precision(.fractionLength(0...3)))
    }
}

private struct LayoutSelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    let keyboardType: UIKeyboardType
    var showsDoneButton = true
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = keyboardType
        field.textAlignment = .right
        field.placeholder = "0"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        if showsDoneButton {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(title: "Terminé", style: .done, target: context.coordinator, action: #selector(Coordinator.dismissKeyboard(_:)))
            ]
            field.inputAccessoryView = toolbar
        }
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.keyboardType = keyboardType
        if field.text != text { field.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UIGestureRecognizerDelegate {
        var parent: LayoutSelectAllTextField
        private var outsideTap: UITapGestureRecognizer?
        init(_ parent: LayoutSelectAllTextField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        @objc func dismissKeyboard(_ sender: UIBarButtonItem) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: sender, for: nil)
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged(true)
            DispatchQueue.main.async { textField.selectAll(nil) }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tappedOutside))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            textField.window?.addGestureRecognizer(tap)
            outsideTap = tap
        }
        @objc private func tappedOutside() {
            outsideTap?.view?.endEditing(true)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UIControl { return false }
                view = current.superview
            }
            return true
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if let outsideTap { outsideTap.view?.removeGestureRecognizer(outsideTap) }
            outsideTap = nil
            parent.onEditingChanged(false)
        }
    }
}
