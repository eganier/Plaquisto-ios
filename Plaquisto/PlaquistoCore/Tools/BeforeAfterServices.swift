import Foundation

// Platform boundaries: no Vision, AVFoundation, CoreImage, SwiftUI or UIImage in
// these contracts or persisted models. Android can implement the same operations
// and read the documented versioned JSON without Apple library identifiers.
protocol BeforeAfterAligning: Sendable {
    func align(before: URL, after: URL) -> BeforeAfterAlignment
}
protocol BeforeAfterExporting: Sendable {
    func export(project: BeforeAfterProject, before: URL, after: URL, account: BeforeAfterAccountContext) throws -> URL
}
protocol BeforeAfterReadingMetadata: Sendable {
    func read(url: URL) throws -> BeforeAfterMetadata
}

/// Serializes expensive operations outside the main actor; platform engines are
/// injected. The UI doesn't create Vision requests or interpret their matrices.
actor BeforeAfterProcessing {
    let alignment: any BeforeAfterAligning
    let exporter: any BeforeAfterExporting
    init(alignment: any BeforeAfterAligning, exporter: any BeforeAfterExporting) {
        self.alignment = alignment; self.exporter = exporter
    }
    func align(before: URL, after: URL) -> BeforeAfterAlignment { alignment.align(before:before,after:after) }
    func export(project: BeforeAfterProject, before: URL, after: URL, account: BeforeAfterAccountContext) throws -> URL {
        try exporter.export(project:project,before:before,after:after,account:account)
    }
}
