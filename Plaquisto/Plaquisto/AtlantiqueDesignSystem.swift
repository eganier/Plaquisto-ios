import SwiftUI
import UIKit

/// Approved Atlantique × Orange books. Presentation only: no catalogue, pricing or storage.
enum Atlantique {
    enum Palette {
        static let blue = color(0x285982)
        static let orange = color(0xFF8A1F)
        // Darker orange for small controls/text on light surfaces.
        static let actionInk = color(0xAD5100)
        static let ink = color(0x17324A)
        static let muted = color(0x637686)
        static let paper = color(0xF3F6FA)
        static let surface = Color.white
        static let selected = color(0xFFF0DF)
        static let separator = color(0xD5DFE8)
        static let disabled = color(0xDDE2E8)
        static let keyboard = color(0xE4EAF0)
        static let validation = color(0xBCD5E9)
        static let success = color(0x21845B)
        static let danger = color(0xB83440)

        private static func color(_ hex: UInt32) -> Color {
            Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
        }
    }

    enum Metrics {
        static let spacing: CGFloat = 16
        static let cardRadius: CGFloat = 17
        static let controlRadius: CGFloat = 12
        static let touchTarget: CGFloat = 48
    }

    enum Typography {
        enum Weight: String, CaseIterable {
            case regular = "AvenirNext-Regular"
            case medium = "AvenirNext-Medium"
            case demi = "AvenirNext-DemiBold"
            case bold = "AvenirNext-Bold"
        }
        static func font(_ size: CGFloat = 17, weight: Weight = .regular,
                         relativeTo style: Font.TextStyle = .body) -> Font {
            .custom(weight.rawValue, size: size, relativeTo: style)
        }
        static func uiFont(size: CGFloat = 17, weight: Weight = .regular) -> UIFont {
            UIFontMetrics(forTextStyle: .body).scaledFont(for:
                UIFont(name: weight.rawValue, size: size) ?? .systemFont(ofSize: size))
        }
        static let title = font(28, weight: .bold, relativeTo: .title)
        static let heading = font(20, weight: .demi, relativeTo: .title3)
        static let body = font()
        static let button = font(17, weight: .demi)
        static let caption = font(14, relativeTo: .caption)
    }
}

private struct AtlantiqueEnabledKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var usesAtlantiqueDesign: Bool {
        get { self[AtlantiqueEnabledKey.self] }
        set { self[AtlantiqueEnabledKey.self] = newValue }
    }
}

extension View {
    /// Opt-in while screens migrate. Never installs a global UIAppearance proxy.
    func atlantiqueDesign() -> some View {
        environment(\.usesAtlantiqueDesign, true)
            .font(Atlantique.Typography.body)
            .tint(Atlantique.Palette.actionInk)
            .foregroundStyle(Atlantique.Palette.ink)
            .preferredColorScheme(.light)
    }
}

/// Background blur is limited to the surface: text, dimensions and drawings stay crisp.
struct AtlantiqueSurface: View {
    var selected = false
    var radius = Atlantique.Metrics.cardRadius
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(.regularMaterial)
            .overlay {
                shape.fill(selected ? Atlantique.Palette.selected : Atlantique.Palette.surface)
                    .opacity(opaque || contrast == .increased || selected ? 1 : 0.94)
            }
            .overlay {
                shape.strokeBorder(contrast == .increased ? Atlantique.Palette.muted : .white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: Atlantique.Palette.ink.opacity(0.09), radius: 10, y: 4)
    }
}

struct AtlantiqueCard<Content: View>: View {
    var selected: Bool
    private let content: Content
    init(selected: Bool = false, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.content = content()
    }
    var body: some View {
        content.padding(Atlantique.Metrics.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { AtlantiqueSurface(selected: selected) }
            .foregroundStyle(Atlantique.Palette.ink)
    }
}

enum AtlantiqueButtonKind { case primary, secondary, destructive, entry, exit }
struct AtlantiqueButtonStyle: ButtonStyle {
    var kind: AtlantiqueButtonKind = .primary
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fill: Color {
        guard enabled else { return Atlantique.Palette.disabled }
        switch kind {
        case .primary: return Atlantique.Palette.orange
        case .secondary: return .white
        case .destructive, .exit: return Atlantique.Palette.danger
        case .entry: return Atlantique.Palette.success
        }
    }
    private var ink: Color {
        guard enabled else { return Atlantique.Palette.muted }
        switch kind {
        case .primary: return Atlantique.Palette.ink
        case .secondary: return Atlantique.Palette.blue
        case .destructive, .entry, .exit: return .white
        }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Atlantique.Typography.button)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Atlantique.Metrics.touchTarget)
            .foregroundStyle(ink)
            .background(fill, in: RoundedRectangle(cornerRadius: Atlantique.Metrics.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Atlantique.Metrics.controlRadius)
                    .strokeBorder(.white.opacity(0.6), lineWidth: 1)
            }
            .opacity(configuration.isPressed && enabled ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A single normalized icon grid keeps toolbar symbols aligned with their captions.
enum AtlantiqueIcon: String, CaseIterable {
    case projects, model, tools, stock, dimensions, boards, framing, openings, electricity, move
    case options, back, add, rename, duplicate, delete

    var label: String {
        switch self {
        case .projects: return "Projets"
        case .model: return "Modéliser"
        case .tools: return "Outils"
        case .stock: return "Stock"
        case .dimensions: return "Cotes"
        case .boards: return "Plaques"
        case .framing: return "Ossature"
        case .openings: return "Ouvertures"
        case .electricity: return "Électricité"
        case .move: return "Déplacer le plan"
        case .options: return "Options"
        case .back: return "Retour"
        case .add: return "Ajouter"
        case .rename: return "Renommer"
        case .duplicate: return "Dupliquer"
        case .delete: return "Supprimer"
        }
    }
    var systemName: String {
        switch self {
        case .projects: return "folder"
        case .model: return "pencil" // Drawn together with scan brackets below, no ruler/cube.
        case .tools: return "wrench.and.screwdriver"
        case .stock: return "shippingbox"
        case .dimensions: return "ruler"
        case .boards, .openings: return "rectangle.portrait"
        case .framing: return "line.3.horizontal"
        case .electricity: return "bolt"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .options: return "ellipsis"
        case .back: return "chevron.left"
        case .add: return "plus"
        case .rename: return "pencil"
        case .duplicate: return "doc.on.doc"
        case .delete: return "trash"
        }
    }
}

struct AtlantiqueSymbol: View {
    let icon: AtlantiqueIcon
    var size: CGFloat = 28
    var body: some View {
        Group {
            switch icon {
            case .framing:
                HStack(spacing: size * 0.2) {
                    ForEach(0..<3) { _ in Capsule().frame(width: max(2, size * 0.075), height: size * 0.8) }
                }
            case .openings:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.07).stroke(lineWidth: size * 0.075)
                        .frame(width: size * 0.6, height: size * 0.9)
                    Rectangle().stroke(lineWidth: size * 0.05).frame(width: size * 0.3, height: size * 0.3)
                }
            case .model:
                ZStack {
                    ScanBrackets().stroke(style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    Image(systemName: "pencil").font(.system(size: size * 0.76, weight: .regular))
                }.padding(size * 0.06)
            default:
                Image(systemName: icon.systemName).font(.system(size: size * 0.9, weight: .regular))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    private struct ScanBrackets: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let d = rect.width * 0.22
            for (x, y, sx, sy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                                    (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
                p.move(to: CGPoint(x: x + d * sx, y: y))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y + d * sy))
            }
            return p
        }
    }
}

struct AtlantiqueIconButton: View {
    let icon: AtlantiqueIcon
    var label: String? = nil
    var selected = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            AtlantiqueSymbol(icon: icon, size: 24)
                .foregroundStyle(enabled ? Atlantique.Palette.actionInk : Atlantique.Palette.muted)
                .frame(width: 48, height: 48)
                .background { AtlantiqueSurface(selected: selected, radius: 14) }
        }.buttonStyle(.plain).accessibilityLabel(label ?? icon.label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Native menu owns focus/VoiceOver and destructive roles; callers own all actions.
struct AtlantiqueOptionsMenu<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Menu { content } label: {
            AtlantiqueSymbol(icon: .options, size: 24)
                .foregroundStyle(Atlantique.Palette.actionInk)
                .frame(width: 48, height: 48)
                .background { AtlantiqueSurface(radius: 14) }
        }.accessibilityLabel("Options")
    }
}

struct AtlantiqueChoice<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection = option.value }
                } label: {
                    Text(option.title).font(Atlantique.Typography.button)
                        .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
                        .foregroundStyle(selection == option.value ? Atlantique.Palette.ink : Atlantique.Palette.muted)
                        .background(selection == option.value ? (enabled ? Atlantique.Palette.orange : Atlantique.Palette.disabled) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(option.title)")
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }.padding(4).background { AtlantiqueSurface(radius: 14) }
    }
}

struct AtlantiqueSearchField: View {
    var prompt = "Rechercher"
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Atlantique.Palette.muted).accessibilityHidden(true)
            TextField(prompt, text: $text).font(Atlantique.Typography.body).accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .foregroundStyle(Atlantique.Palette.actionInk).accessibilityLabel("Effacer la recherche")
            }
        }.padding(.horizontal, 14).frame(minHeight: 52)
            .background { AtlantiqueSurface(radius: 14) }
            .foregroundStyle(Atlantique.Palette.ink)
    }
}

struct AtlantiqueNumberRow: View {
    let title: String
    let unit: String
    @Binding var text: String
    var integer = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
            HStack {
                PlaquistoNumericField(text: $text, integer: integer).accessibilityLabel(title)
                Text(unit).font(Atlantique.Typography.body).foregroundStyle(Atlantique.Palette.muted)
            }
        }
    }
}
