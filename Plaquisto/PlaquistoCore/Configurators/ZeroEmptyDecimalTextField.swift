import SwiftUI

/// Champ décimal partagé par les configurateurs Plaquisto.
/// Une valeur métier nulle est affichée comme un champ vide afin que la saisie
/// commence directement par le premier chiffre utile.
struct ZeroEmptyDecimalTextField: View {
    @Binding var value: Double
    var placeholder = "0"

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .onAppear { synchronizeText() }
            .onChange(of: value) { _, _ in
                if !isFocused { synchronizeText() }
            }
            .onChange(of: text) { _, newText in
                let normalized = newText
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: ".")

                if normalized.isEmpty {
                    value = 0
                } else if let parsed = Double(normalized) {
                    value = parsed
                }
            }
            .onChange(of: isFocused) { _, focused in
                if focused, value == 0 {
                    text = ""
                } else if !focused {
                    synchronizeText()
                }
            }
    }

    private func synchronizeText() {
        text = value == 0
            ? ""
            : value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
