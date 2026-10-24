import SwiftUI

struct ToolsHomeView: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    var onOpenAccount: (() -> Void)?
    @StateObject private var technicalStore = ToolTechnicalStore()
    @State private var query = ""

    private var results: [ToolDefinition] { ToolCatalog.search(query) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if atlantique { AtlantiqueSearchField(prompt: "Rechercher un outil", text: $query) }
                    ForEach(ToolCategory.allCases) { category in
                        let tools = results.filter { $0.category == category }
                        if !tools.isEmpty { section(category.rawValue, tools: tools) }
                    }
                }
                .padding()
            }
            .background(atlantique ? Atlantique.Palette.blue : Color(.systemGroupedBackground))
            .navigationTitle("Outils").atlantiquePage("Outils", root: true)
            .modifier(ToolSearchModifier(text: $query, native: !atlantique))
            .navigationDestination(for: ToolDestination.self) { destination in
                ToolDestinationView(destination: destination)
            }
            .toolbar {
                if let onOpenAccount {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenAccount) { if atlantique { AtlantiqueToolbarGlyph(symbol: "gearshape") } else { Image(systemName: "person.crop.circle") } }
                            .accessibilityLabel("Réglages")
                    }.atlantiqueToolbarBackground(atlantique)
                }
            }
        }
        .environmentObject(technicalStore)
        .task { await technicalStore.load() }
    }

    @ViewBuilder
    private func section(_ title: String, tools: [ToolDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Atlantique.Typography.heading).foregroundStyle(atlantique ? .white : .secondary)
            ForEach(tools) { tool in
                let isAvailable = tool.isAvailable
                NavigationLink(value: tool.destination) {
                    ToolCard(tool: tool, isAvailable: isAvailable)
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
            }
        }
    }
}

private struct ToolCard: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    let tool: ToolDefinition
    let isAvailable: Bool

    private var displayTitle: String {
        atlantique && tool.destination == .furringSpacing ? "Entraxe des fourrures" : tool.title
    }
    private var displayDescription: String {
        guard atlantique else { return tool.shortDescription }
        switch tool.destination {
        case .furringSpacing: return "Selon la masse surfacique de l’isolant."
        case .partitionHeight: return "Rechercher une configuration compatible."
        case .ceilingSpan: return "Trouver les montages compatibles."
        default: return tool.shortDescription
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if tool.destination == .wallAngle || tool.destination == .exteriorWallAngle {
                    WallAngleIcon(kind: tool.destination == .wallAngle ? .interior : .exterior)
                        .padding(4)
                } else if tool.destination == .arch && atlantique {
                    ArchToolIcon().stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round)).padding(6)
                } else {
                    Image(systemName: tool.destination == .liningHeight ? "rectangle.split.3x1" : tool.destination == .vat ? "calculator" : tool.icon)
                }
            }
                .font(.title2)
                .foregroundStyle(isAvailable ? Color.accentColor : .secondary)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(isAvailable ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayTitle).font(atlantique ? Atlantique.Typography.button : .headline)
                }
                Text(displayDescription).font(atlantique ? Atlantique.Typography.caption : .subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if isAvailable { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(atlantique ? Atlantique.Palette.actionInk : .secondary) }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: atlantique ? 17 : 18))
        .shadow(color: .black.opacity(atlantique ? 0.10 : 0), radius: 6, y: 4)
    }
}

private struct ToolDestinationView: View {
    let destination: ToolDestination

    var body: some View {
        switch destination {
        case .thermal: ThermalToolView()
        case .ceilingSpan: CeilingSpanToolView()
        case .partitionHeight: PartitionHeightToolView()
        case .furringSpacing: FurringSpacingToolView()
        case .layout: SheetLayoutView()
        case .liningHeight: LiningHeightToolView()
        case .vat: VATToolView()
        case .arch: ArchTemplateToolView()
        case .wallAngle: WallAngleToolView()
        case .exteriorWallAngle: WallAngleToolView(kind: .exterior)
        case .beforeAfter: BeforeAfterHomeView()
        }
    }
}

struct ToolNumberField: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    let title: String
    let unit: String
    @Binding var value: Double
    @State private var text = ""

    var body: some View {
        Group {
            if atlantique {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                    HStack {
                        numericInput.font(Atlantique.Typography.heading)
                            .accessibilityLabel(title)
                        Text(unit).font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                    }.frame(minHeight: 36)
                }
            } else { HStack {
            Text(title)
            Spacer()
            numericInput
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit).foregroundStyle(.secondary)
            } }
        }
        .onAppear { text = value == 0 ? "" : value.formatted(.number.locale(Locale(identifier: "fr_FR")).grouping(.never).precision(.fractionLength(0...3))) }
        .onChange(of: value) { _, newValue in
            if newValue == 0 { if !text.isEmpty { text = "" } }
        }
    }
    private var numericInput: some View {
        PlaquistoNumericField(text: $text)
            .onChange(of: text) { _, newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                value = Double(normalized) ?? 0
            }
    }
}

struct ToolResultCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ToolSearchModifier: ViewModifier {
    @Binding var text: String
    let native: Bool
    func body(content: Content) -> some View {
        if native { content.searchable(text: $text, prompt: "Rechercher un outil") } else { content }
    }
}

private struct ArchToolIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .init(x: rect.minX, y: rect.maxY))
        path.addLine(to: .init(x: rect.minX, y: rect.midY))
        path.addCurve(to: .init(x: rect.maxX, y: rect.midY),
                      control1: .init(x: rect.minX, y: rect.minY - rect.height * 0.15),
                      control2: .init(x: rect.maxX, y: rect.minY - rect.height * 0.15))
        path.addLine(to: .init(x: rect.maxX, y: rect.maxY))
        return path
    }
}
