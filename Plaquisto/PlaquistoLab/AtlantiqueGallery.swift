import SwiftUI

/// Isolated, interactive samples. Never reads/writes projects, prices or stock.
struct AtlantiqueGallery: View {
    @State private var search = ""
    @State private var spacing = 60
    @State private var mode = "3D"
    @State private var height = "280"
    @State private var membrane = false
    @State private var example = ProcessInfo.processInfo.arguments.contains("-atlantique-keyboard") ? 1 : 0
    @State private var status = ""
    @State private var keypadRevision = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AtlantiqueIconButton(icon: .back) { dismiss() }
                Text("Plaquisto").font(Atlantique.Typography.title).foregroundStyle(.white)
                Spacer(minLength: 0)
                AtlantiqueOptionsMenu {
                    Button("Réinitialiser la démo", systemImage: "arrow.counterclockwise") {
                        search = ""; spacing = 60; mode = "3D"; height = "280"; membrane = false; status = ""
                    }
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Composants · Atlantique").font(Atlantique.Typography.heading).foregroundStyle(.white)
                    AtlantiqueChoice(title: "Exemples", options: [(0, "Interface"), (1, "Saisie")], selection: $example)
                    if example == 0 { interfaceExamples } else { inputExamples }
                    if !status.isEmpty {
                        Text(status).font(Atlantique.Typography.caption).foregroundStyle(.white)
                            .accessibilityIdentifier("atlantique.gallery.status")
                    }
                }.padding(20)
            }
        }
        .background(Atlantique.Palette.blue.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .atlantiqueDesign()
    }

    private var interfaceExamples: some View {
        VStack(spacing: 18) {
            AtlantiqueSearchField(prompt: "Rechercher un projet", text: $search)
            AtlantiqueCard {
                HStack(alignment: .top, spacing: 14) {
                    AtlantiqueSymbol(icon: .projects, size: 38).foregroundStyle(Atlantique.Palette.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Maison Lumière").font(Atlantique.Typography.heading)
                        Text("2 relevés · 6 ouvrages").font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                        Text("Exemple sans données réelles").font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
            AtlantiqueChoice(title: "Affichage", options: [("3D", "3D"), ("2D", "2D")], selection: $mode)
            AtlantiqueCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Icônes communes").font(Atlantique.Typography.heading)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        ForEach([AtlantiqueIcon.dimensions, .boards, .framing, .openings, .electricity, .model], id: \.self) { icon in
                            VStack(spacing: 6) {
                                AtlantiqueSymbol(icon: icon, size: 30).foregroundStyle(Atlantique.Palette.blue)
                                Text(icon.label).font(Atlantique.Typography.caption)
                            }.accessibilityElement(children: .combine).accessibilityLabel(icon.label)
                        }
                    }
                }
            }
            Button("Créer un ouvrage") { status = "Action de démonstration uniquement." }
                .buttonStyle(AtlantiqueButtonStyle())
            HStack {
                Button("Retour") { status = "Retour · démonstration" }.buttonStyle(AtlantiqueButtonStyle(kind: .secondary))
                Button("Enregistrer") {}.buttonStyle(AtlantiqueButtonStyle()).disabled(true)
            }
        }
    }

    private var inputExamples: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ossature").font(Atlantique.Typography.heading).foregroundStyle(.white)
            AtlantiqueChoice(title: "Entraxe des fourrures", options: [(40, "40 cm"), (60, "60 cm")], selection: $spacing)
            AtlantiqueCard {
                AtlantiqueNumberRow(title: "Hauteur sous plafond", unit: "cm", text: $height)
            }
            AtlantiqueCard(selected: membrane) {
                Toggle("Prévoir un pare-vapeur", isOn: $membrane).font(Atlantique.Typography.button)
                    .tint(Atlantique.Palette.blue)
            }
            HStack {
                Button { status = "Entrée · démonstration" } label: { Label("Entrée", systemImage: "arrow.up") }
                    .buttonStyle(AtlantiqueButtonStyle(kind: .entry))
                Button { status = "Sortie · démonstration" } label: { Label("Sortie", systemImage: "arrow.down") }
                    .buttonStyle(AtlantiqueButtonStyle(kind: .exit))
            }
            Text("Clavier R50").font(Atlantique.Typography.heading).foregroundStyle(.white)
            PlaquistoNumericKeypad(key: press, close: { _ in
                status = "Valeur de démonstration : \(height) cm"
                keypadRevision += 1
            }, atlantique: true)
                .id(keypadRevision)
                .frame(height: 320)
        }
    }

    private func press(_ key: String) {
        if key == "delete" { if !height.isEmpty { height.removeLast() }; return }
        if let result = PlaquistoNumericInput.replacing(height, range: NSRange(location: height.utf16.count, length: 0),
                                                        with: key, integer: false, signed: false) { height = result }
    }
}
