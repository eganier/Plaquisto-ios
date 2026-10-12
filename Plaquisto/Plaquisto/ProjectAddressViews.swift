import SwiftUI
import MapKit

enum ProjectNavigationDestination: String, CaseIterable {
    case apple = "Plans", google = "Google Maps", waze = "Waze"
    func url(address: String) -> URL? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        switch self {
        case .apple:
            components.host = "maps.apple.com"
            components.queryItems = [.init(name: "daddr", value: value)]
        case .google:
            components.host = "www.google.com"; components.path = "/maps/dir/"
            components.queryItems = [.init(name: "api", value: "1"), .init(name: "destination", value: value)]
        case .waze:
            components.host = "waze.com"; components.path = "/ul"
            components.queryItems = [.init(name: "q", value: value), .init(name: "navigate", value: "yes")]
        }
        return components.url
    }
}

/// Universal links use the installed app, or its website when unavailable.
struct ProjectAddressMenu: View {
    @Environment(\.openURL) private var openURL
    let address: String
    @State private var failed = false
    var body: some View {
        Menu {
            ForEach(ProjectNavigationDestination.allCases, id: \.self) { destination in
                Button("Ouvrir dans \(destination.rawValue)") {
                    if let url = destination.url(address: address) {
                        openURL(url) { accepted in if !accepted { failed = true } }
                    }
                }
            }
            ShareLink(item: address) { Label("Partager l’adresse…", systemImage: "square.and.arrow.up") }
            Button("Copier l’adresse", systemImage: "doc.on.doc") { UIPasteboard.general.string = address }
        } label: {
            Label(address, systemImage: "location.circle").multilineTextAlignment(.leading)
                .frame(minHeight: 44, alignment: .leading)
        }.accessibilityLabel("Itinéraire vers \(address)")
            .alert("Ouverture impossible", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Essayez une autre application ou copiez l’adresse.") }
    }
}

@MainActor final class ProjectAddressSuggestions: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var unavailable = false
    private var active: MKLocalSearchCompleter?
    func cancel() {
        active?.delegate = nil; active?.cancel(); active = nil
        results = []; unavailable = false
    }
    func search(_ query: String) {
        cancel()
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return }
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = .address
        completer.delegate = self; active = completer
        completer.queryFragment = query
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard completer === active else { return }
        results = Array(completer.results.prefix(5)); unavailable = false
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard completer === active else { return }
        results = []; unavailable = true
    }
}

struct ProjectAddressField: View {
    @Binding var address: String
    @StateObject private var suggestions = ProjectAddressSuggestions()
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Adresse (facultative)", text: $address)
                .textContentType(.fullStreetAddress).autocorrectionDisabled()
                .focused($focused).accessibilityIdentifier("project.address")
            if focused {
                ForEach(Array(suggestions.results.enumerated()), id: \.offset) { _, result in
                    Button {
                        address = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                        focused = false; suggestions.cancel()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title).foregroundStyle(.primary)
                            if !result.subtitle.isEmpty { Text(result.subtitle).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    }.buttonStyle(.plain)
                }
                if suggestions.unavailable {
                    Text("Suggestions indisponibles. Vous pouvez saisir l’adresse librement.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
        }
        .task(id: focused ? address : "") {
            suggestions.cancel()
            guard focused, address.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled else { return }
            suggestions.search(address)
        }
        .onDisappear { suggestions.cancel() }
    }
}
