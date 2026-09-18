import Foundation

enum BeforeAfterMode: String, Codable, CaseIterable, Identifiable {
    case sideBySide, vertical, horizontal, diagonal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sideBySide: "Côte à côte"
        case .vertical: "Verticale"
        case .horizontal: "Horizontale"
        case .diagonal: "Diagonale"
        }
    }
}

struct BeforeAfterMetadata: Codable, Equatable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var orientation: Int?
    var make: String?
    var model: String?
    var capturedAt: String?
    var lens: String?
    var focalLength: Double?
    var focalLength35: Double?
    var iso: Double?
    var exposureSeconds: Double?
    var aperture: Double?
    var exposureBias: Double?
    var latitude: Double?
    var longitude: Double?
    var hasLocation: Bool { latitude != nil && longitude != nil }

    var rows: [(String, String)] {
        var result: [(String,String)] = []
        func add(_ title: String, _ value: String?) { if let value { result.append((title,value)) } }
        add("Marque",make); add("Modèle",model); add("Prise de vue",capturedAt); add("Objectif",lens)
        if let pixelWidth, let pixelHeight { add("Dimensions","\(pixelWidth) × \(pixelHeight) px") }
        if let orientation { add("Orientation EXIF","\(orientation)") }
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }
        add("Focale",focalLength.map { number($0)+" mm" })
        add("Équivalent 35 mm",focalLength35.map { number($0)+" mm" })
        add("ISO",iso.map(number)); add("Exposition",exposureSeconds.map { number($0)+" s" })
        add("Ouverture",aperture.map { "f/"+number($0) }); add("Correction d’exposition",exposureBias.map { number($0)+" EV" })
        if hasLocation { add("Localisation","Disponible (jamais ajoutée à l’export)") }
        return result
    }
}

struct BeforeAfterSourcePhoto: Codable, Equatable {
    var filename: String
    var libraryIdentifier: String?
    var metadata: BeforeAfterMetadata
}

enum BeforeAfterCompatibility: String {
    case sameModel, differentModel, unknown
    static func check(source: String?, current: String?) -> Self {
        func normalized(_ s: String?) -> String? {
            guard let s else { return nil }
            let value = s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator:" ")
            return value.isEmpty || value == "iphone" ? nil : value
        }
        guard let source = normalized(source), let current = normalized(current) else { return .unknown }
        return source == current ? .sameModel : .differentModel
    }
    var message: String {
        switch self {
        case .sameModel: "Même modèle détecté, sans garantie qu’il s’agisse du même téléphone. Les réglages compatibles peuvent être approchés."
        case .differentModel: "Modèle différent. Le cadrage guidé reste disponible, sans import automatique des réglages."
        case .unknown: "Modèle non vérifiable. Le cadrage guidé reste disponible, sans import automatique des réglages. Le modèle de ce téléphone sera lu lors de la première capture."
        }
    }
}

/// Adapter boundary for the real account/entitlement provider. Never infer a paid
/// entitlement from project JSON or an editable local preference.
struct BeforeAfterAccountContext {
    enum Plan { case start, plus, pro }
    var companyName: String?
    var verifiedPlan: Plan = .start
    var allowsLabWatermarkControl = false
    var canDisableWatermark: Bool { allowsLabWatermarkControl || verifiedPlan == .plus || verifiedPlan == .pro }
    func requiresWatermark(requested: Bool) -> Bool { requested || !canDisableWatermark }
    static let unconfigured = BeforeAfterAccountContext()
}

struct BeforeAfterPoint: Codable, Equatable {
    var x: Double
    var y: Double
}
struct BeforeAfterCrop: Codable, Equatable {
    var x = 0.0, y = 0.0, width = 1.0, height = 1.0
}
struct BeforeAfterAlignment: Codable, Equatable {
    enum Quality: String, Codable { case excellent, correct, weak, failed }
    var quality: Quality
    var message: String
    /// Normalized bottom-left coordinates: BL, BR, TR, TL. No device pixels persisted.
    var corners: [BeforeAfterPoint]?
    var crop = BeforeAfterCrop()
    var score: Double?
    var isUsable: Bool { corners?.count == 4 && (quality == .excellent || quality == .correct) }
    static func failed(_ message: String) -> Self { .init(quality:.failed,message:message) }
}

struct BeforeAfterProject: Codable, Identifiable, Equatable {
    var version = 1
    var id = UUID()
    var name = "Avant / Après"
    var createdAt = Date()
    var updatedAt = Date()
    var before: BeforeAfterSourcePhoto
    var after: BeforeAfterSourcePhoto?
    var alignment: BeforeAfterAlignment?
    var usesAlignment = true
    var mode: BeforeAfterMode = .vertical
    var divider = 0.5
    /// Optional for backward-compatible decoding of existing version-1 projects.
    var diagonalAngle: Double?
    var effectiveDiagonalAngle: Double {
        guard let diagonalAngle, diagonalAngle.isFinite else { return .pi/4 }
        return diagonalAngle.truncatingRemainder(dividingBy:2 * .pi)
    }
    var showsBranding = false
    var company = ""
    var city = ""
    var showsWatermark = true
    var cameraSettingsSummary: String?
    var dividerPosition: Double { divider.isFinite ? min(1,max(0,divider)) : 0.5 }
    var branding: String { [company,city].map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator:" — ") }
    mutating func prefill(account: BeforeAfterAccountContext, city suggestedCity: String? = nil) {
        if company.isEmpty { company = account.companyName ?? "" }
        if city.isEmpty { city = suggestedCity ?? "" }
    }
}

enum BeforeAfterError: LocalizedError {
    case invalidImage, storage, missingPhoto, cameraUnavailable, export
    var errorDescription: String? {
        switch self {
        case .invalidImage: "Cette photo ne peut pas être lue. Choisissez une autre image."
        case .storage: "Enregistrement impossible. Vérifiez l’espace disponible puis réessayez."
        case .missingPhoto: "Une photo de ce projet est manquante. Le projet n’a pas été modifié."
        case .cameraUnavailable: "La caméra n’est pas disponible. Réessayez sur l’iPhone."
        case .export: "L’image n’a pas pu être exportée. Réessayez."
        }
    }
}

/// Geometry/acceptance policy independent of the platform registration library.
enum BeforeAfterAlignmentPolicy {
    static func safeCrop(corners: [BeforeAfterPoint]) -> BeforeAfterCrop? {
        guard corners.count == 4, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let identity = [BeforeAfterPoint(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)]
        guard zip(corners,identity).allSatisfy({ hypot($0.x-$1.x,$0.y-$1.y) <= 0.26 }) else { return nil }
        func inside(_ p: BeforeAfterPoint) -> Bool {
            (0..<4).allSatisfy { index in
                let a = corners[index], b = corners[(index+1)%4]
                return (b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x) >= -0.0001
            }
        }
        for inset in stride(from:0.0,through:0.16,by:0.005) {
            let r = BeforeAfterCrop(x:inset,y:inset,width:1-2*inset,height:1-2*inset)
            if [BeforeAfterPoint(x:r.x,y:r.y),.init(x:1-inset,y:inset),.init(x:1-inset,y:1-inset),.init(x:inset,y:1-inset)].allSatisfy(inside) {
                return r
            }
        }
        return nil
    }
    static func evaluate(score: Double, baseline: Double, corners: [BeforeAfterPoint]) -> BeforeAfterAlignment {
        guard let crop = safeCrop(corners:corners), score.isFinite, score >= 0.28, score >= baseline-0.015 else {
            return .init(quality:.weak,message:"Recalage trop incertain : les photos originales sont conservées. Essayez une prise plus proche du cadrage Avant.",score:score.isFinite ? score : nil)
        }
        return .init(quality:score >= 0.65 ? .excellent : .correct,
                     message:score >= 0.65 ? "Correspondance visuelle forte. Vérifiez le résultat avec le séparateur." : "Recalage plausible. Vérifiez les lignes et les angles avant l’export.",
                     corners:corners,crop:crop,score:score)
    }
}

/// Platform-neutral live framing policy. Directions are image-space suggestions,
/// not a measured camera pose or distance in the room.
struct BeforeAfterFraming {
    var message: String
    var aligned: Bool = false
    static let searching = Self(message:"Retrouvez les grandes lignes du cadrage d’origine.")
    static func evaluate(_ alignment: BeforeAfterAlignment) -> Self {
        guard alignment.isUsable, let score = alignment.score, score >= 0.55,
              let c = alignment.corners, c.count == 4 else { return .searching }
        let x = c.map(\.x).reduce(0,+)/4-0.5, y = c.map(\.y).reduce(0,+)/4-0.5
        let scale = hypot(c[1].x-c[0].x,c[1].y-c[0].y)
        let rotation = atan2(c[1].y-c[0].y,c[1].x-c[0].x)*180 / .pi
        if abs(rotation) > 3 { return .init(message:rotation > 0 ? "Inclinez légèrement le téléphone dans le sens horaire." : "Inclinez légèrement le téléphone dans le sens antihoraire.") }
        if abs(x) > 0.035 { return .init(message:x > 0 ? "Essayez de tourner légèrement vers la gauche." : "Essayez de tourner légèrement vers la droite.") }
        if abs(y) > 0.035 { return .init(message:y > 0 ? "Essayez de descendre légèrement le téléphone." : "Essayez de monter légèrement le téléphone.") }
        if abs(scale-1) > 0.045 { return .init(message:scale > 1 ? "Essayez d’avancer légèrement." : "Essayez de reculer légèrement.") }
        let ideal = [BeforeAfterPoint(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)]
        guard zip(c,ideal).allSatisfy({ hypot($0.x-$1.x,$0.y-$1.y) < 0.055 }), score >= 0.72 else {
            return .init(message:"Affinez la superposition des contours ou prenez la photo manuellement.")
        }
        return .init(message:"Bon cadrage. Ne bougez plus…",aligned:true)
    }
}

enum BeforeAfterWatermarkStyle {
    static let opacity = 0.23
    static let angle = -Double.pi/7
    static let positions = [0.22,0.52,0.82].flatMap { y in
        [0.18,0.52,0.86].map { BeforeAfterPoint(x:$0,y:y) }
    }
}

struct BeforeAfterCaptureStability {
    private var start: Double?
    private var last: Double?
    mutating func reset() { start = nil; last = nil }
    mutating func update(aligned: Bool, time: Double) -> Double {
        guard aligned, time.isFinite else { reset(); return 0 }
        if let last, time-last > 1.3 || time < last { reset() }
        if start == nil { start = time }
        last = time
        return min(1,max(0,(time-(start ?? time))/1.8))
    }
}

enum BeforeAfterDividerGeometry {
    /// Screen-normalized top-left coordinates, reusable by any renderer.
    static func endpoints(mode: BeforeAfterMode, position: Double, angle: Double = .pi/4) -> [BeforeAfterPoint] {
        let p = position.isFinite ? min(1,max(0,position)) : 0.5
        guard p > 0, p < 1 else { return [] }
        switch mode {
        case .sideBySide: return []
        case .vertical: return [.init(x:p,y:0),.init(x:p,y:1)]
        case .horizontal: return [.init(x:0,y:p),.init(x:1,y:p)]
        case .diagonal:
            let (nx,ny,minimum,span) = projection(angle)
            let offset = minimum+p*span
            let square = corners
            var result: [BeforeAfterPoint] = []
            func append(_ point:BeforeAfterPoint) {
                if !result.contains(where:{ hypot($0.x-point.x,$0.y-point.y) < 1e-8 }) { result.append(point) }
            }
            for i in square.indices {
                let a = square[i], b = square[(i+1)%4]
                let va = nx*a.x+ny*a.y-offset, vb = nx*b.x+ny*b.y-offset
                if abs(va) < 1e-10 { append(a) }
                if va*vb < 0 {
                    let t = va/(va-vb)
                    append(.init(x:a.x+t*(b.x-a.x),y:a.y+t*(b.y-a.y)))
                }
            }
            return Array(result.prefix(2))
        }
    }
    private static let corners: [BeforeAfterPoint] = [.init(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)]
    private static func projection(_ angle:Double) -> (Double,Double,Double,Double) {
        let a = angle.isFinite ? angle : .pi/4
        let nx = cos(a), ny = sin(a), minimum = min(0,nx)+min(0,ny)
        return (nx,ny,minimum,abs(nx)+abs(ny))
    }
    static func position(at point:BeforeAfterPoint, angle:Double) -> Double {
        let (nx,ny,minimum,span) = projection(angle)
        return min(1,max(0,(nx*point.x+ny*point.y-minimum)/span))
    }
    static func labelPoint(before:Bool,angle:Double) -> BeforeAfterPoint {
        let candidates: [BeforeAfterPoint] = [.init(x:0.14,y:0.10),.init(x:0.86,y:0.10),.init(x:0.14,y:0.80),.init(x:0.86,y:0.80)]
        return candidates.sorted {
            let a = position(at:$0,angle:angle), b = position(at:$1,angle:angle)
            return before ? a < b : a > b
        }[0]
    }
    static func polygon(position:Double,angle:Double) -> [BeforeAfterPoint] {
        let p = position.isFinite ? min(1,max(0,position)) : 0.5
        if p <= 0 { return [] }; if p >= 1 { return corners }
        let (nx,ny,minimum,span) = projection(angle), offset = minimum+p*span
        var result: [BeforeAfterPoint] = []
        for i in corners.indices {
            let a = corners[i], b = corners[(i+1)%4]
            let va = nx*a.x+ny*a.y-offset, vb = nx*b.x+ny*b.y-offset
            if va <= 0 { result.append(a) }
            if va*vb < 0 {
                let t = va/(va-vb)
                result.append(.init(x:a.x+t*(b.x-a.x),y:a.y+t*(b.y-a.y)))
            }
        }
        return result
    }
}
