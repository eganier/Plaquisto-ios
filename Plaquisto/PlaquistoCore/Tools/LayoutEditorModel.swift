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
    var id = UUID()
    var document: LayoutDocument
    var updatedAt = Date()
    var title: String { document.surface.name }
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
    private var past: [LayoutDocument] = []
    private var future: [LayoutDocument] = []
    private var calculation: Task<Void, Never>?
    private var revision = 0
    private let defaults: UserDefaults
    private let draftKey = "plaquisto.tools.layout.draft.v1"
    private let libraryKey = "plaquisto.tools.layout.library.v1"
    private var currentSavedID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        past = []; future = []; updateHistory(); recalculate()
    }

    func startNew() {
        calculation?.cancel()
        calculation = nil
        defaults.removeObject(forKey: draftKey)
        currentSavedID = nil
        document = nil
        past = []; future = []; result = nil; error = nil; isCalculating = false; updateHistory()
    }

    func saveCurrentAndClose() {
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
        savedDocuments.removeAll { $0.id == saved.id }
        persistLibrary()
    }

    func apply(_ newValue: LayoutDocument) {
        guard newValue != document else { return }
        if let document { past.append(document); if past.count > 100 { past.removeFirst() } }
        future = []; document = newValue; updateHistory(); persistDraft(); recalculate()
    }

    func preview(_ value: LayoutDocument) { document = value; recalculate(delay: true) }

    func finishGesture(from original: LayoutDocument) {
        guard var updated = document, updated != original else { return }
        do {
            if updated.surface.contour != original.surface.contour {
                var intent = original.surface.editableIntent
                for i in updated.surface.contour.indices where updated.surface.contour[i] != original.surface.contour[i] {
                    intent.userVertexPositions[i] = updated.surface.contour[i]
                }
                try updated.surface.resolve(intent)
                document = updated
            }
            try LayoutGeometry.validate(updated.surface.contour)
            for opening in updated.surface.openings { try LayoutGeometry.validate(opening.contour) }
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
                var intent = copy.surface.editableIntent
                for i in points.indices where points[i] != copy.surface.contour[i] { intent.userVertexPositions[i] = points[i] }
                try copy.surface.resolve(intent)
            } else {
                copy.surface.previousContourIntents.append(copy.surface.editableIntent)
                copy.surface.contour = points
                copy.surface.contourIntent = .init(sketch:points)
                copy.surface.dimensionCorrections = []
                copy.surface.edgeTones = points.indices.map { [.blue,.orange,.purple,.green,.teal][$0%5] }
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
    @State private var text = ""
    @State private var editing = false
    var body: some View {
        HStack {
            Text(title).foregroundStyle(tint ?? Color.primary)
            Spacer(minLength: 12)
            LayoutSelectAllTextField(text: $text, keyboardType: signed ? .numbersAndPunctuation : .decimalPad) { active in
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
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = keyboardType
        field.textAlignment = .right
        field.placeholder = "0"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Terminé", style: .done, target: context.coordinator, action: #selector(Coordinator.dismissKeyboard(_:)))
        ]
        field.inputAccessoryView = toolbar
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
