import SwiftUI
import UIKit

/// Editing grammar only. Each caller retains ownership of its business value,
/// units, empty-value policy and validation.
enum PlaquistoNumericInput {
    static func replacing(_ text: String, range: NSRange, with replacement: String,
                          integer: Bool, signed: Bool) -> String? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        let cleaned = replacement.filter { !$0.isWhitespace }.replacingOccurrences(of: ".", with: ",")
        let result = text.replacingCharacters(in: swiftRange, with: cleaned)
        guard result.allSatisfy({ "0123456789,-".contains($0) }),
              result.filter({ $0 == "," }).count <= (integer ? 0 : 1),
              result.filter({ $0 == "-" }).count <= (signed ? 1 : 0),
              !result.dropFirst().contains("-") else { return nil }
        if result.isEmpty || result == "-" || result == "," || result == "-," { return result }
        let normalized = result.replacingOccurrences(of: ",", with: ".")
        guard let number = Double(normalized), number.isFinite else { return nil }
        if integer && Int(normalized) == nil { return nil }
        return result
    }

    static func shouldDismiss(translation: Double, predicted: Double) -> Bool {
        translation >= 65 || (translation > 12 && predicted >= 140)
    }

    static func visibleKeyboardHeight(fullHeight: Double, translation: Double) -> Double {
        max(1, fullHeight - max(0, translation))
    }
}

/// Uses the public UITextField inputView API: one native first responder owns
/// the keyboard, including in sheets, with native safe-area and focus handling.
struct PlaquistoNumericField: UIViewRepresentable {
    var placeholder = "0"
    @Binding var text: String
    var integer = false
    var signed = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onValidate: () -> Void = {}
    @Environment(\.isEnabled) private var enabled
    @Environment(\.multilineTextAlignment) private var alignment

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartInsertDeleteType = .no
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        context.coordinator.field = field
        context.coordinator.installKeyboard()
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        let old = context.coordinator.parent
        context.coordinator.parent = self
        field.isEnabled = enabled
        field.placeholder = placeholder
        field.textAlignment = alignment == .trailing ? .right : alignment == .center ? .center : .left
        if field.text != text { field.text = text }
        if old.integer != integer || old.signed != signed {
            context.coordinator.installKeyboard()
            if field.isFirstResponder { field.reloadInputViews() }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        .init(width: proposal.width ?? 110, height: max(34, uiView.intrinsicContentSize.height))
    }
    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) {
        field.resignFirstResponder()
        coordinator.removeOutsideTap()
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UIGestureRecognizerDelegate {
        var parent: PlaquistoNumericField
        weak var field: UITextField?
        private var outsideTap: UITapGestureRecognizer?
        private var keyboardGeneration = UUID()
        init(_ parent: PlaquistoNumericField) { self.parent = parent }

        func installKeyboard() {
            let generation = UUID()
            keyboardGeneration = generation
            field?.inputView = PlaquistoNumericInputView(integer: parent.integer, signed: parent.signed,
                key: { [weak self] in self?.press($0) },
                close: { [weak self] validate in
                    guard let self, self.keyboardGeneration == generation,
                          let field = self.field, field.isFirstResponder else { return }
                    self.changed(field)
                    if validate { self.parent.onValidate() }
                    field.resignFirstResponder()
                })
            field?.inputAccessoryView = nil
        }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func press(_ key: String) {
            guard let field, field.isFirstResponder else { return }
            if key == "delete" { field.deleteBackward(); changed(field); return }
            if key == "sign" {
                let current = field.text ?? ""
                field.text = current.hasPrefix("-") ? String(current.dropFirst()) : "-" + current
                changed(field)
                return
            }
            field.insertText(key)
            changed(field)
        }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString: String) -> Bool {
            guard let value = PlaquistoNumericInput.replacing(field.text ?? "", range: range,
                        with: replacementString, integer: parent.integer, signed: parent.signed) else { return false }
            // Apply normalized paste and hardware-keyboard input using the same
            // path as the keypad; keep the insertion point after the replacement.
            let previous = field.text ?? ""
            field.text = value
            let inserted = value.utf16.count - previous.utf16.count + range.length
            if let position = field.position(from: field.beginningOfDocument, offset: range.location + inserted) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            changed(field)
            return false
        }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            changed(field); parent.onValidate(); field.resignFirstResponder(); return false
        }
        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.onEditingChanged(true)
            DispatchQueue.main.async { [weak field] in
                guard let field, field.isFirstResponder else { return }
                field.selectAll(nil)
            }
            removeOutsideTap()
            let tap = UITapGestureRecognizer(target: self, action: #selector(tappedOutside))
            tap.cancelsTouchesInView = false; tap.delegate = self
            field.window?.addGestureRecognizer(tap); outsideTap = tap
        }
        func textFieldDidEndEditing(_ field: UITextField) {
            changed(field); removeOutsideTap(); parent.onEditingChanged(false)
            installKeyboard()
        }
        func removeOutsideTap() {
            if let outsideTap { outsideTap.view?.removeGestureRecognizer(outsideTap) }
            outsideTap = nil
        }
        @objc private func tappedOutside() { field?.resignFirstResponder() }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UIControl || current is UIInputView { return false }
                view = current.superview
            }
            return true
        }
    }
}

private final class PlaquistoNumericInputView: UIInputView {
    private let host: UIHostingController<PlaquistoNumericKeypad>
    private var landscape = false
    private var keyboardHeight: NSLayoutConstraint!
    private var panelHeight: NSLayoutConstraint!
    private var dragTranslation: CGFloat = 0
    private var fullHeight: CGFloat { landscape ? 245 : 320 }
    init(integer: Bool, signed: Bool, key: @escaping (String) -> Void, close: @escaping (Bool) -> Void) {
        host = UIHostingController(rootView: PlaquistoNumericKeypad(integer: integer, signed: signed, key: key, close: close))
        // iOS may still supply a backing plate even with a transparent input
        // view. Resize the actual input area, not an offset inside that plate.
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 320), inputViewStyle: .default)
        allowsSelfSizing = true
        backgroundColor = .clear
        clipsToBounds = true
        host.rootView = PlaquistoNumericKeypad(integer: integer, signed: signed, key: key, close: close,
            drag: { [weak self] translation, animated in self?.resizeForDrag(translation, animated: animated) })
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        keyboardHeight = heightAnchor.constraint(equalToConstant: fullHeight)
        panelHeight = host.view.heightAnchor.constraint(equalToConstant: fullHeight)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor), host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor), panelHeight, keyboardHeight
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: PlaquistoNumericInput.visibleKeyboardHeight(fullHeight: fullHeight, translation: dragTranslation))
    }
    private func resizeForDrag(_ translation: CGFloat, animated: Bool) {
        dragTranslation = max(0, translation)
        let changes = {
            self.keyboardHeight.constant = self.intrinsicContentSize.height
            self.invalidateIntrinsicContentSize()
            self.superview?.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else { UIView.performWithoutAnimation(changes) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let next = window?.windowScene?.interfaceOrientation.isLandscape == true
        if landscape != next {
            landscape = next
            panelHeight.constant = fullHeight
            resizeForDrag(0, animated: false)
        }
    }
}

struct PlaquistoNumericKeypad: View {
    var integer = false
    var signed = false
    let key: (String) -> Void
    let close: (Bool) -> Void
    var drag: (CGFloat, Bool) -> Void = { _, _ in }
    @State private var closing = false
    private let rows = [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"], ["0", ",", "delete"]]

    var body: some View {
        panel.allowsHitTesting(!closing)
    }

    private var panel: some View {
        VStack(spacing: 8) {
            ZStack {
                Capsule().fill(.secondary.opacity(0.4)).frame(width: 44, height: 6)
                    .accessibilityHidden(true)
                if signed {
                    HStack { Button("±") { key("sign") }.font(.title3).frame(width: 44, height: 32)
                        .accessibilityLabel("Changer le signe"); Spacer() }
                }
            }
            .frame(height: 32).frame(maxWidth: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    drag(value.translation.height, false)
                }
                .onEnded { value in
                    if PlaquistoNumericInput.shouldDismiss(translation: value.translation.height, predicted: value.predictedEndTranslation.height) {
                        dismiss(validate: false)
                    } else { drag(0, true) }
                })
            .accessibilityAction(named: "Fermer le clavier") { dismiss(validate: false) }
            HStack(spacing: 8) {
                VStack(spacing: 7) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 7) {
                            ForEach(row, id: \.self) { item in
                                Button { key(item) } label: {
                                    Group {
                                        if item == "delete" { Image(systemName: "delete.left").font(.system(size: 26)) }
                                        else { Text(item).font(.system(size: 30, weight: .regular, design: .rounded)) }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(NumericKeyStyle(secondary: item == "," || item == "delete"))
                                .disabled(item == "," && integer)
                                .accessibilityLabel(item == "delete" ? "Supprimer" : item == "," ? "Virgule" : item)
                                .accessibilityIdentifier("numeric.key.\(item)")
                            }
                        }
                    }
                }
                Button { dismiss(validate: true) } label: {
                    VStack(spacing: 9) {
                        Image(systemName: "checkmark").font(.system(size: 28, weight: .semibold))
                        Text("Valider").font(.system(size: 16, weight: .semibold)).minimumScaleFactor(0.7).lineLimit(1)
                    }
                    .frame(width: 68).frame(maxHeight: .infinity)
                    .foregroundStyle(.blue)
                    .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("numeric.validate")
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 20)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
    }
    private func dismiss(validate: Bool) {
        guard !closing else { return }
        closing = true
        // Hand over immediately to iOS, retaining the current visual offset.
        // One native dismissal moves the keyboard and updates the form's inset
        // together; no preliminary animation, delay or reset back to the top.
        close(validate)
    }
}

private struct NumericKeyStyle: ButtonStyle {
    var secondary: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.primary.opacity(enabled ? 1 : 0.25))
            .background(secondary ? Color(.tertiarySystemFill) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(configuration.isPressed ? 0.1 : 0)) }
    }
}

/// Format-based SwiftUI fields migrated without changing their empty policy.
struct PlaquistoOptionalNumberField: View {
    let placeholder: String
    @Binding var value: Double?
    @State private var text = ""
    @State private var editing = false
    var body: some View {
        PlaquistoNumericField(placeholder: placeholder, text: $text, onEditingChanged: { active in
            editing = active; if !active { synchronize() }
        })
        .onAppear { synchronize() }
        .onChange(of: value) { _, _ in if !editing { synchronize() } }
        .onChange(of: text) { _, text in
            if text.isEmpty { value = nil }
            else if let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite { value = number }
        }
    }
    private func synchronize() {
        text = value.map { $0.formatted(.number.locale(Locale(identifier: "fr_FR")).grouping(.never).precision(.fractionLength(0...10))) } ?? ""
    }
}

struct PlaquistoIntegerField: View {
    var placeholder = "0"
    @Binding var value: Int
    @State private var text = ""
    @State private var editing = false
    var body: some View {
        PlaquistoNumericField(placeholder: placeholder, text: $text, integer: true, onEditingChanged: { active in
            editing = active; if !active { text = String(value) }
        })
        .onAppear { text = String(value) }
        .onChange(of: value) { _, value in if !editing { text = String(value) } }
        .onChange(of: text) { _, text in if let number = Int(text) { value = number } }
    }
}
