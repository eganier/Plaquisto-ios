import SwiftUI

struct ThermalToolView: View {
    @State private var mode = ThermalMode.resistance
    @State private var thickness = 0.0
    @State private var lambda = 0.0
    @State private var resistance = 0.0

    private var result: (String, String)? {
        switch mode {
        case .resistance:
            return ThermalCalculator.resistance(thicknessMM: thickness, lambda: lambda).map { ("Résistance thermique", $0.formatted(.number.precision(.fractionLength(2))) + " m²·K/W") }
        case .thickness:
            return ThermalCalculator.thickness(resistance: resistance, lambda: lambda).map { ("Épaisseur nécessaire", $0.formatted(.number.precision(.fractionLength(0...1))) + " mm") }
        case .lambda:
            return ThermalCalculator.lambda(thicknessMM: thickness, resistance: resistance).map { ("Conductivité thermique", $0.formatted(.number.precision(.fractionLength(3))) + " W/(m·K)") }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Calcul", selection: $mode) { ForEach(ThermalMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
            }
            Section("Données") {
                if mode != .lambda { ToolNumberField(title: "Lambda λ", unit: "W/(m·K)", value: $lambda) }
                if mode != .thickness { ToolNumberField(title: "Épaisseur", unit: "mm", value: $thickness) }
                if mode != .resistance { ToolNumberField(title: "Résistance R", unit: "m²·K/W", value: $resistance) }
            }
            Section {
                if let result {
                    LabeledContent(result.0, value: result.1).font(.headline)
                } else {
                    Label("Renseignez des valeurs strictement positives.", systemImage: "info.circle").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Résistance thermique")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Réinitialiser") { reset() } } }
    }

    private func reset() { thickness = 0; lambda = 0; resistance = 0 }
}

struct VATToolView: View {
    @State private var direction = VATDirection.netToGross
    @State private var amount = 0.0
    @State private var rate = 20.0

    private var result: VATResult? {
        VATCalculator.calculate(amount: Decimal(amount), rate: Decimal(rate), direction: direction)
    }

    var body: some View {
        Form {
            Section {
                Picker("Sens", selection: $direction) { ForEach(VATDirection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            }
            Section("Montant") {
                ToolNumberField(title: direction == .netToGross ? "Montant HT" : "Montant TTC", unit: "€", value: $amount)
                Picker("Taux de TVA", selection: $rate) {
                    Text("5,5 %").tag(5.5); Text("10 %").tag(10.0); Text("20 %").tag(20.0)
                }
                .pickerStyle(.segmented)
            }
            if let result {
                Section("Résultat") {
                    LabeledContent("Montant HT", value: currency(result.net))
                    LabeledContent("TVA", value: currency(result.tax))
                    LabeledContent("Montant TTC", value: currency(result.gross)).font(.headline)
                }
            }
        }
        .navigationTitle("Calcul de TVA")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Réinitialiser") { amount = 0; rate = 20; direction = .netToGross } } }
    }

    private func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }
}

struct ArchTemplateToolView: View {
    @State private var kind = ArchKind.rounded
    @State private var width = 120.0
    @State private var rise = 40.0
    @State private var spacing = 10.0
    @State private var xFromCenter = false

    private var effectiveRise: Double { kind == .semicircle ? width / 2 : rise }
    private var points: [ArchPoint] { ArchCalculator.points(kind: kind, width: width, rise: rise, spacing: spacing) }

    var body: some View {
        Form {
            Section("Forme") {
                Picker("Type d’arche", selection: $kind) { ForEach(ArchKind.allCases) { Text($0.rawValue).tag($0) } }
                ToolNumberField(title: "Largeur", unit: "cm", value: $width)
                ToolNumberField(title: "Flèche", unit: "cm", value: $rise).disabled(kind == .semicircle)
                if kind == .semicircle { LabeledContent("Flèche imposée", value: format(width / 2) + " cm") }
                Picker("Pas des points", selection: $spacing) {
                    ForEach([5.0, 10, 15, 20], id: \.self) { Text("\(Int($0)) cm").tag($0) }
                }
            }
            Section("Aperçu") {
                ArchDiagram(points: points, width: width, rise: effectiveRise).frame(height: 190)
            }
            Section {
                Toggle("Abscisse depuis le centre", isOn: $xFromCenter)
            }
            Section("Table de traçage") {
                ForEach(points) { point in
                    LabeledContent("x = \(format(xFromCenter ? point.x - width / 2 : point.x)) cm", value: "y = \(format(point.y)) cm")
                }
            }
        }
        .navigationTitle("Gabarit d’arche")
    }

    private func format(_ value: Double) -> String { value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))) }
}

private struct ArchDiagram: View {
    let points: [ArchPoint]
    let width: Double
    let rise: Double

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard points.count > 1, width > 0, rise > 0 else { return }
                let pad = 18.0, usableWidth = size.width - pad * 2, usableHeight = size.height - pad * 2
                func mapped(_ point: ArchPoint) -> CGPoint {
                    CGPoint(x: pad + point.x / width * usableWidth, y: size.height - pad - point.y / rise * usableHeight)
                }
                var curve = Path(); curve.move(to: mapped(points[0]))
                points.dropFirst().forEach { curve.addLine(to: mapped($0)) }
                context.stroke(curve, with: .color(.accentColor), lineWidth: 3)
                var baseline = Path(); baseline.move(to: CGPoint(x: pad, y: size.height - pad)); baseline.addLine(to: CGPoint(x: size.width - pad, y: size.height - pad))
                context.stroke(baseline, with: .color(.secondary), style: .init(lineWidth: 1, dash: [5]))
                for point in points { context.fill(Path(ellipseIn: CGRect(x: mapped(point).x - 3, y: mapped(point).y - 3, width: 6, height: 6)), with: .color(.orange)) }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
