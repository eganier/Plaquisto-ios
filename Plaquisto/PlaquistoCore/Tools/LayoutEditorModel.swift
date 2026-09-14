import Foundation
import SwiftUI

struct LayoutCatalogFormat: Identifiable, Hashable {
    var id: String
    var title: String
    var width: Double
    var length: Double
    var label: String { "\(title) · \(Int(width / 10)) × \(Int(length / 10)) cm" }
}

@MainActor
final class LayoutEditorModel: ObservableObject {
    @Published private(set) var document: LayoutDocument?
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
    private let key = "plaquisto.tools.layout.draft.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do {
                let d = try JSONDecoder().decode(LayoutDocument.self, from: data)
                guard d.schemaVersion == 1, !d.layers.isEmpty else { throw LayoutGeometryError.invalidFormat }
                document = d; recalculate()
            } catch { saveError = "Le brouillon enregistré n’a pas pu être relu." }
        }
    }

    func apply(_ newValue: LayoutDocument) {
        guard newValue != document else { return }
        if let document { past.append(document); if past.count > 100 { past.removeFirst() } }
        future = []; document = newValue; updateHistory(); persist(); recalculate()
    }

    func preview(_ value: LayoutDocument) { document = value; recalculate(delay: true) }

    func finishGesture(from original: LayoutDocument) {
        guard let updated = document, updated != original else { return }
        do {
            try LayoutGeometry.validate(updated.surface.contour)
            for opening in updated.surface.openings { try LayoutGeometry.validate(opening.contour) }
            past.append(original); if past.count > 100 { past.removeFirst() }; future = []
            updateHistory(); persist(); recalculate()
        } catch {
            document = original; recalculate()
            saveError = "Déplacement annulé : le contour se croisait ou comportait un côté nul."
        }
    }

    func undo() {
        guard let previous = past.popLast(), let document else { return }
        future.append(document); self.document = previous; updateHistory(); persist(); recalculate()
    }
    func redo() {
        guard let next = future.popLast(), let document else { return }
        past.append(document); self.document = next; updateHistory(); persist(); recalculate()
    }
    private func updateHistory() { canUndo = !past.isEmpty; canRedo = !future.isEmpty }
    private func persist() {
        do {
            if let document { defaults.set(try JSONEncoder().encode(document), forKey: key) }
            saveError = nil
        } catch { saveError = "Impossible d’enregistrer ce brouillon." }
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
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", text: $text)
                .keyboardType(signed ? .numbersAndPunctuation : .decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 100).focused($focused)
                .accessibilityLabel(title)
                .onChange(of: text) { _, value in
                    if value.isEmpty { millimetres = 0 }
                    else if let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite { millimetres = number * 10 }
                }
            Text("cm").foregroundStyle(.secondary)
        }
        .onAppear { synchronize() }
        .onChange(of: millimetres) { _, _ in if !focused { synchronize() } }
        .onChange(of: focused) { _, active in if !active { synchronize() } }
    }
    private func synchronize() {
        text = millimetres == 0 ? "" : (millimetres / 10).formatted(.number.locale(Locale(identifier: "fr_FR")).grouping(.never).precision(.fractionLength(0...3)))
    }
}
