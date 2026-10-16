import SwiftUI

/// Presentation only; never select a different calculator or storage engine.
enum InterfacePresentation: Equatable { case standard, contrastLab }
private struct InterfacePresentationKey: EnvironmentKey {
    static let defaultValue: InterfacePresentation = .standard
}
extension EnvironmentValues {
    var interfacePresentation: InterfacePresentation {
        get { self[InterfacePresentationKey.self] }
        set { self[InterfacePresentationKey.self] = newValue }
    }
}
enum ContrastPalette {
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let ink = Color(red: 0.09, green: 0.13, blue: 0.16)
    static let blue = Color(red: 0.13, green: 0.36, blue: 0.64)
    static let orange = Color(red: 0.66, green: 0.27, blue: 0.07)
    static let wash = Color(red: 0.90, green: 0.94, blue: 0.98)
}
struct AccountToolbarButton: ToolbarContent {
    let action: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: action) { Image(systemName: "gearshape") }
                .accessibilityLabel("Compte et réglages")
        }
    }
}
enum WorkPreviewSelection {
    static func surfaceIDs(work: WorkItem, survey: ProjectSurveyRecord) -> Set<String> {
        let sources = work.components.compactMap(\.surveySource)
        return Set(SurveyWorkGeometry.surfaces(in: survey).filter { surface in
            sources.contains { source in
                source.surveyID == surface.source.surveyID && source.checkpointID == surface.source.checkpointID &&
                source.surfaceID == surface.source.surfaceID && source.kind == surface.source.kind &&
                source.boundaryIndex == surface.source.boundaryIndex
            }
        }.map(\.id))
    }
}

/// Optional navigation entry point. Does not change a configuration or its rules.
struct WorkConfigurationShortcut: Identifiable, Equatable {
    let title: String
    let step: Int
    var id: Int { step }
    static func choices(for type: WorkType) -> [Self] {
        let entries: [(String,Int)]
        switch type {
        case .ceilingOnFurring:
            entries = [("Dimensions et forme",0),("Support",1),("Isolation et pare-vapeur",2),("Entraxe et plénum",3),("Fixations",4),("Parements",5),("Bandes à joint",6)]
        case .ceilingOnRailsAndStuds:
            entries = [("Dimensions",0),("Isolation",1),("Parements",2),("Ossature",3),("Support",4),("Plénum",5),("Suspension",6),("Bandes à joint",7)]
        case .peripheralLiningStuds, .peripheralLiningFurrings:
            entries = [("Dimensions",1),("Parements",2),("Ossature",3),("Isolation et pare-vapeur",4),("Bandes à joint",5)]
        case .distributionPartition:
            entries = [("Dimensions",1),("Ossature",2),("Parements",3),("Vérification de hauteur",4),("Isolation",5),("Bandes à joint",6)]
        case .alveolarPartition:
            entries = [("Dimensions",1),("Panneaux",2),("Bandes à joint",3)]
        case .peripheralLiningBonded:
            entries = [("Dimensions",1),("Parements",2),("Isolation",3),("Format",4),("Bandes à joint",5)]
        case .peripheralLiningAdhesiveFacing:
            entries = [("Dimensions",1),("Parements",2),("Format",3),("Bandes à joint",4)]
        case .modularCeiling:
            entries = [("Dimensions",0),("Dalles et trame",1),("Plénum et suspension",2)]
        default: entries = []
        }
        return entries.map { .init(title:$0.0,step:$0.1) }
    }
}

private struct ConfigurationEntryStepKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}
extension EnvironmentValues {
    var configurationEntryStep: Int? {
        get { self[ConfigurationEntryStepKey.self] }
        set { self[ConfigurationEntryStepKey.self] = newValue }
    }
}
private struct ConfigurationEntryModifier: ViewModifier {
    @Environment(\.configurationEntryStep) private var entry
    @State private var applied = false
    let range: ClosedRange<Int>
    let action: (Int) -> Void
    func body(content: Content) -> some View {
        content.onAppear {
            guard !applied else { return }
            applied = true
            if let entry, range.contains(entry) { action(entry) }
        }
    }
}
extension View {
    func configurationEntry(in range: ClosedRange<Int>, perform: @escaping (Int) -> Void) -> some View {
        modifier(ConfigurationEntryModifier(range:range,action:perform))
    }
}
