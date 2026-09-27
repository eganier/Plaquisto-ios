import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable
import UIKit
import CoreLocation

struct AppleBeforeAfterMetadata: BeforeAfterReadingMetadata {
    func read(url: URL) throws -> BeforeAfterMetadata { try BeforeAfterMetadataExtractor.extract(url:url) }
}

enum BeforeAfterMetadataExtractor {
    static func extract(url: URL) throws -> BeforeAfterMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] else { throw BeforeAfterError.invalidImage }
        return extract(properties:properties)
    }
    static func extract(properties p: [String:Any]) -> BeforeAfterMetadata {
        let exif = p[kCGImagePropertyExifDictionary as String] as? [String:Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String:Any] ?? [:]
        let gps = p[kCGImagePropertyGPSDictionary as String] as? [String:Any] ?? [:]
        func number(_ dict:[String:Any],_ key:CFString) -> Double? {
            guard let n = dict[key as String] as? NSNumber, n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        var m = BeforeAfterMetadata()
        func integer(_ key: CFString, maximum: Double) -> Int? {
            guard let value = number(p,key), value > 0, value <= maximum else { return nil }
            return Int(value)
        }
        m.pixelWidth = integer(kCGImagePropertyPixelWidth,maximum:1_000_000)
        m.pixelHeight = integer(kCGImagePropertyPixelHeight,maximum:1_000_000)
        m.orientation = integer(kCGImagePropertyOrientation,maximum:8)
        m.make = tiff[kCGImagePropertyTIFFMake as String] as? String
        m.model = tiff[kCGImagePropertyTIFFModel as String] as? String
        m.capturedAt = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String
        m.lens = exif[kCGImagePropertyExifLensModel as String] as? String
        m.focalLength = number(exif,kCGImagePropertyExifFocalLength)
        m.focalLength35 = number(exif,kCGImagePropertyExifFocalLenIn35mmFilm)
        m.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        if let iso = m.iso, !iso.isFinite || iso <= 0 { m.iso = nil }
        m.exposureSeconds = number(exif,kCGImagePropertyExifExposureTime)
        m.aperture = number(exif,kCGImagePropertyExifFNumber)
        m.exposureBias = number(exif,kCGImagePropertyExifExposureBiasValue)
        if let lat = number(gps,kCGImagePropertyGPSLatitude), let lon = number(gps,kCGImagePropertyGPSLongitude),
           abs(lat) <= 90, abs(lon) <= 180,
           let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
           let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
           ["N","S"].contains(latRef.uppercased()), ["E","W"].contains(lonRef.uppercased()) {
            m.latitude = abs(lat) * (latRef.uppercased() == "S" ? -1 : 1)
            m.longitude = abs(lon) * (lonRef.uppercased() == "W" ? -1 : 1)
        }
        return m
    }
}

enum BeforeAfterImages {
    static func load(_ url: URL, maxPixel: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:maxPixel,
                kCGImageSourceShouldCacheImmediately:true
              ] as CFDictionary) else { throw BeforeAfterError.invalidImage }
        return image
    }
    static func jpeg(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data,UTType.jpeg.identifier as CFString,1,nil) else { throw BeforeAfterError.export }
        // Do not propagate source EXIF/GPS to derived files or exports.
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BeforeAfterError.export }
        try (data as Data).write(to:url,options:.atomic)
    }
}

struct BeforeAfterImportedFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType:.image) { received in
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("before-after-import-\(UUID().uuidString)")
            try FileManager.default.copyItem(at:received.file,to:destination)
            return Self(url:destination)
        }
    }
}

/// Disk IO and image decoding stay off the main actor. One JSON per project,
/// atomic replacement; images are written before their reference is committed.
actor BeforeAfterProjectStore {
    static let shared = BeforeAfterProjectStore()
    let root: URL
    private let metadataReader: any BeforeAfterReadingMetadata
    init(root: URL? = nil, metadataReader: any BeforeAfterReadingMetadata = AppleBeforeAfterMetadata()) {
        self.root = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("BeforeAfter",isDirectory:true)
        self.metadataReader = metadataReader
    }
    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString,isDirectory:true) }
    private var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    private var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted,.sortedKeys]; return e }
    func imageURL(_ photo: BeforeAfterSourcePhoto, projectID: UUID) throws -> URL {
        guard photo.filename == URL(fileURLWithPath:photo.filename).lastPathComponent,
              !["", ".", ".."].contains(photo.filename) else { throw BeforeAfterError.missingPhoto }
        let url = directory(projectID).appendingPathComponent(photo.filename)
        guard FileManager.default.fileExists(atPath:url.path) else { throw BeforeAfterError.missingPhoto }
        return url
    }
    func list() throws -> [BeforeAfterProject] {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            .filter { UUID(uuidString:$0.lastPathComponent) != nil }
            .compactMap { url in
                guard let data = try? Data(contentsOf:url.appendingPathComponent("project.json")),
                      let project = try? decoder.decode(BeforeAfterProject.self,from:data), project.version == 1,
                      project.id.uuidString == url.lastPathComponent else { return nil }
                return project
            }.sorted { $0.updatedAt > $1.updatedAt }
    }
    func save(_ project: BeforeAfterProject) throws -> BeforeAfterProject {
        var project = project
        project.updatedAt = Date(timeIntervalSince1970:Date().timeIntervalSince1970.rounded(.down))
        project.createdAt = Date(timeIntervalSince1970:project.createdAt.timeIntervalSince1970.rounded(.down))
        project.divider = project.dividerPosition
        _ = try imageURL(project.before,projectID:project.id)
        if let after = project.after { _ = try imageURL(after,projectID:project.id) }
        let url = directory(project.id).appendingPathComponent("project.json")
        try encoder.encode(project).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        return project
    }
    func create(from url: URL, identifier: String?, company: String?) throws -> BeforeAfterProject {
        let metadata = try metadataReader.read(url:url)
        let id = UUID(), dir = directory(id)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        do {
            let image = try BeforeAfterImages.load(url,maxPixel:2400)
            try BeforeAfterImages.jpeg(image,to:dir.appendingPathComponent("before.jpg"))
            let thumb = try BeforeAfterImages.load(url,maxPixel:320)
            try BeforeAfterImages.jpeg(thumb,to:dir.appendingPathComponent("thumbnail.jpg"))
            var project = BeforeAfterProject(id:id,before:.init(filename:"before.jpg",libraryIdentifier:identifier,metadata:metadata))
            project.company = company ?? ""
            return try save(project)
        } catch {
            try? FileManager.default.removeItem(at:dir) // Only our new, uncommitted UUID directory.
            throw error
        }
    }
    func addCapture(_ data: Data, to project: BeforeAfterProject, summary: String) throws -> BeforeAfterProject {
        let temporary = directory(project.id).appendingPathComponent("capture-\(UUID().uuidString).tmp")
        try data.write(to:temporary,options:.atomic)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let metadata = try metadataReader.read(url:temporary)
        let image = try BeforeAfterImages.load(temporary,maxPixel:2400)
        let filename = "after-\(UUID().uuidString).jpg"
        try BeforeAfterImages.jpeg(image,to:directory(project.id).appendingPathComponent(filename))
        var result = project
        result.after = .init(filename:filename,metadata:metadata)
        result.alignment = nil
        result.cameraSettingsSummary = summary
        return try save(result)
    }
    func thumbnail(_ id: UUID) -> UIImage? {
        guard let cg = try? BeforeAfterImages.load(directory(id).appendingPathComponent("thumbnail.jpg"),maxPixel:240) else { return nil }
        return UIImage(cgImage:cg)
    }
    /// Rebuild from the saved composition, including old projects whose disk
    /// thumbnail contains only Before. Never crop away the comparison divider.
    func thumbnail(project:BeforeAfterProject,account:BeforeAfterAccountContext) -> UIImage? {
        guard let after = project.after else { return thumbnail(project.id) }
        do {
            let a = try imageURL(project.before,projectID:project.id)
            let b = try imageURL(after,projectID:project.id)
            let pair = try BeforeAfterAlignmentEngine.pair(project:project,before:a,after:b,maxPixel:320)
            return BeforeAfterRenderEngine.render(project:project,pair:pair,account:account)
        } catch { return thumbnail(project.id) }
    }
    func delete(_ id: UUID) throws { try FileManager.default.removeItem(at:directory(id)) }
}

@MainActor
enum BeforeAfterCityResolver {
    static func city(for metadata: BeforeAfterMetadata) async throws -> String? {
        guard let lat = metadata.latitude, let lon = metadata.longitude else { return nil }
        // Invoked only after explicit user consent: Apple's geocoder may use network.
        return try await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude:lat,longitude:lon)).first?.locality
    }
}
