import SwiftUI

struct ToolsHomeView: View {
    var onOpenAccount: (() -> Void)?
    @StateObject private var technicalStore = ToolTechnicalStore()
    @State private var query = ""
    @AppStorage("plaquisto.tools.favorites") private var favoriteStorage = "thermal,vat"

    private var favorites: Set<String> {
        Set(favoriteStorage.split(separator: ",").map(String.init))
    }

    private var results: [ToolDefinition] { ToolCatalog.search(query) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if query.isEmpty, !favoriteTools.isEmpty {
                        section("Favoris", tools: favoriteTools)
                    }
                    ForEach(ToolCategory.allCases) { category in
                        let tools = results.filter { $0.category == category }
                        if !tools.isEmpty { section(category.rawValue, tools: tools) }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Outils")
            .searchable(text: $query, prompt: "Rechercher un outil")
            .navigationDestination(for: ToolDestination.self) { destination in
                ToolDestinationView(destination: destination)
            }
            .toolbar {
                if let onOpenAccount {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenAccount) { Image(systemName: "person.crop.circle") }
                            .accessibilityLabel("Compte et réglages")
                    }
                }
            }
        }
        .environmentObject(technicalStore)
        .task { await technicalStore.load() }
    }

    private var favoriteTools: [ToolDefinition] { ToolCatalog.all.filter { favorites.contains($0.id) } }

    @ViewBuilder
    private func section(_ title: String, tools: [ToolDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).foregroundStyle(.secondary)
            ForEach(tools) { tool in
                NavigationLink(value: tool.destination) {
                    ToolCard(tool: tool, isFavorite: favorites.contains(tool.id))
                }
                .buttonStyle(.plain)
                .disabled(!tool.isAvailable)
                .contextMenu {
                    Button(favorites.contains(tool.id) ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: favorites.contains(tool.id) ? "star.slash" : "star") {
                        toggleFavorite(tool.id)
                    }
                }
            }
        }
    }

    private func toggleFavorite(_ id: String) {
        var updated = favorites
        if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
        favoriteStorage = updated.sorted().joined(separator: ",")
    }
}

private struct ToolCard: View {
    let tool: ToolDefinition
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: tool.icon)
                .font(.title2)
                .foregroundStyle(tool.isAvailable ? Color.accentColor : .secondary)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(tool.isAvailable ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tool.title).font(.headline)
                    if !tool.isAvailable { Text("AVEC ASTRA").font(.caption2.bold()).foregroundStyle(.purple) }
                }
                Text(tool.shortDescription).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? .yellow : .secondary)
                .padding(8)
            if tool.isAvailable { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
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
        case .layout: ContentUnavailableView("Calepinage avec Astra", systemImage: "sparkles", description: Text("Le moteur polygonal interactif sera développé séparément avec Astra."))
        case .liningHeight: LiningHeightToolView()
        case .vat: VATToolView()
        case .arch: ArchTemplateToolView()
        }
    }
}

struct ToolNumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .onChange(of: text) { _, newValue in
                    let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                    value = Double(normalized) ?? 0
                }
            Text(unit).foregroundStyle(.secondary)
        }
        .onAppear { text = value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...3))) }
        .onChange(of: value) { _, newValue in
            if newValue == 0 { if !text.isEmpty { text = "" } }
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
