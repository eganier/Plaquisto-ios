import SwiftUI

/// Champ décimal partagé par les configurateurs Plaquisto.
/// Une valeur métier nulle est affichée comme un champ vide afin que la saisie
/// commence directement par le premier chiffre utile.
struct ZeroEmptyDecimalTextField: View {
    @Binding var value: Double
    var placeholder = "0"

    @State private var text = ""
    @State private var isFocused = false

    var body: some View {
        PlaquistoNumericField(placeholder: placeholder, text: userInput, onEditingChanged: { isFocused = $0 })
            .onAppear { synchronizeText() }
            .onChange(of: value) { _, _ in
                if !isFocused { synchronizeText() }
            }
            .onChange(of: isFocused) { _, focused in
                if focused, value == 0 {
                    text = ""
                } else if !focused {
                    synchronizeText()
                }
            }
    }

    /// Only a changed input from the keyboard may write back to the model.
    /// synchronizeText updates display state directly, never this binding.
    /// UIKit also sends the unchanged text on validation/end editing: ignoring
    /// that echo preserves the full scan precision when merely visiting a field.
    private var userInput: Binding<String> {
        Binding(get: { text }, set: { newText in
            guard newText != text else { return }
            text = newText
            let normalized = newText
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
            if normalized.isEmpty {
                value = 0
            } else if let parsed = Double(normalized), parsed.isFinite {
                value = parsed
            }
        })
    }

    private func synchronizeText() {
        text = value == 0
            ? ""
            : value.formatted(.number.locale(Locale(identifier: "fr_FR")).grouping(.never).precision(.fractionLength(0...2)))
    }
}
