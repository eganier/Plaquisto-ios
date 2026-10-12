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
