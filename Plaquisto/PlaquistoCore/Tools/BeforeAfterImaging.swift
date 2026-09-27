import UIKit
import CoreImage
import Vision
import simd

struct AppleBeforeAfterAlignment: BeforeAfterAligning {
    func align(before: URL, after: URL) -> BeforeAfterAlignment { BeforeAfterAlignmentEngine.align(before:before,after:after) }
}
struct AppleBeforeAfterExport: BeforeAfterExporting {
    func export(project: BeforeAfterProject, before: URL, after: URL, account: BeforeAfterAccountContext) throws -> URL {
        try BeforeAfterRenderEngine.export(project:project,before:before,after:after,account:account)
    }
}
extension BeforeAfterProcessing {
    static func apple() -> BeforeAfterProcessing { .init(alignment:AppleBeforeAfterAlignment(),exporter:AppleBeforeAfterExport()) }
}

enum BeforeAfterAlignmentEngine {
    private static let context = CIContext(options:[.cacheIntermediates:false])

    static func contourGuide(_ source: CIImage) -> CGImage? {
        guard let image = context.createCGImage(source,from:source.extent),
              let raster = AppleBeforeAfterGuide.raster(image),
              let guide = try? AppleBeforeAfterGuide().extract(raster) else { return nil }
        return AppleBeforeAfterGuide.render(guide,width:image.width,height:image.height)
    }

    static func canvas(_ image: CGImage, size: CGSize) -> CIImage {
        let scale = max(size.width/CGFloat(image.width),size.height/CGFloat(image.height))
        let input = CIImage(cgImage:image).transformed(by:.init(scaleX:scale,y:scale))
        return input.transformed(by:.init(translationX:(size.width-input.extent.width)/2,y:(size.height-input.extent.height)/2))
            .cropped(to:CGRect(origin:.zero,size:size))
    }
    static func warp(_ image: CIImage, corners: [BeforeAfterPoint], size: CGSize) -> CIImage {
        let points = corners.map { CIVector(x:$0.x*size.width,y:$0.y*size.height) }
        return image.applyingFilter("CIPerspectiveTransform",parameters:[
            "inputBottomLeft":points[0],"inputBottomRight":points[1],"inputTopRight":points[2],"inputTopLeft":points[3]
        ])
    }
    static func safeCrop(corners: [BeforeAfterPoint]) -> BeforeAfterCrop? { BeforeAfterAlignmentPolicy.safeCrop(corners:corners) }
    static func evaluate(score: Double, baseline: Double, corners: [BeforeAfterPoint]) -> BeforeAfterAlignment {
        BeforeAfterAlignmentPolicy.evaluate(score:score,baseline:baseline,corners:corners)
    }
    static func align(before: URL, after: URL) -> BeforeAfterAlignment {
        do {
            let reference = try BeforeAfterImages.load(before,maxPixel:720)
            return align(reference:reference,after:try BeforeAfterImages.load(after,maxPixel:1000))
        } catch { return .failed("Recalage indisponible. La prise manuelle reste disponible.") }
    }
    static func align(reference: CGImage, after: CGImage) -> BeforeAfterAlignment {
        do {
            let size = CGSize(width:reference.width,height:reference.height)
            let target = canvas(after,size:size)
            guard let floating = context.createCGImage(target,from:target.extent) else { throw BeforeAfterError.invalidImage }
            let request = VNHomographicImageRegistrationRequest(targetedCGImage:floating,options:[:])
            // Target = floating After, handler = unchanged Before (Apple Vision convention).
            try VNImageRequestHandler(cgImage:reference,options:[:]).perform([request])
            guard let observation = request.results?.first else { return .failed("Aucun recalage fiable trouvé. Le comparatif simple reste disponible.") }
            let matrix = observation.warpTransform
            let coordinates: [SIMD3<Float>] = [.init(0,0,1),.init(Float(size.width),0,1),.init(Float(size.width),Float(size.height),1),.init(0,Float(size.height),1)]
            let corners = coordinates.map { p -> BeforeAfterPoint in
                let q = matrix*p
                return .init(x:Double(q.x/q.z)/size.width,y:Double(q.y/q.z)/size.height)
            }
            guard let crop = safeCrop(corners:corners) else { return .init(quality:.weak,message:"La correction serait trop importante. Photos originales conservées ; reprenez le cadrage si nécessaire.") }
            let rect = CGRect(x:crop.x*size.width,y:crop.y*size.height,width:crop.width*size.width,height:crop.height*size.height)
            let beforeCI = CIImage(cgImage:reference)
            let aligned = warp(target,corners:corners,size:size)
            let score = edgeCorrelation(beforeCI,aligned,rect:rect)
            let baseline = edgeCorrelation(beforeCI,target,rect:rect)
            return evaluate(score:score,baseline:baseline,corners:corners)
        } catch {
            return .failed("Le recalage automatique n’a pas abouti. Les photos sont conservées et le comparatif simple reste disponible.")
        }
    }
    /// Correlation of edge strength, not a claim of metrological accuracy. Blank
    /// walls / unrelated scenes must not become successful identity transforms.
    private static func edgeCorrelation(_ a: CIImage,_ b: CIImage,rect: CGRect) -> Double {
        func gradients(_ image: CIImage) -> [Double] {
            let side = 128
            let scaled = image.cropped(to:rect).transformed(by:.init(translationX:-rect.minX,y:-rect.minY))
                .transformed(by:.init(scaleX:CGFloat(side)/rect.width,y:CGFloat(side)/rect.height))
            var pixels = [UInt8](repeating:0,count:side*side*4)
            context.render(scaled,toBitmap:&pixels,rowBytes:side*4,bounds:CGRect(x:0,y:0,width:side,height:side),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
            func gray(_ x:Int,_ y:Int) -> Double {
                let i = (y*side+x)*4
                return 0.299*Double(pixels[i])+0.587*Double(pixels[i+1])+0.114*Double(pixels[i+2])
            }
            return (1..<side-1).flatMap { y in (1..<side-1).map { x in hypot(gray(x+1,y)-gray(x-1,y),gray(x,y+1)-gray(x,y-1)) } }
        }
        let x = gradients(a), y = gradients(b), count = Double(x.count)
        let mx = x.reduce(0,+)/count, my = y.reduce(0,+)/count
        var covariance = 0.0, vx = 0.0, vy = 0.0
        for i in x.indices { let dx = x[i]-mx, dy = y[i]-my; covariance += dx*dy; vx += dx*dx; vy += dy*dy }
        guard vx/count > 4, vy/count > 4 else { return 0 }
        return covariance/sqrt(vx*vy)
    }
    static func pair(project: BeforeAfterProject, before: URL, after: URL, maxPixel: Int) throws -> (CGImage,CGImage) {
        let reference = try BeforeAfterImages.load(before,maxPixel:maxPixel)
        let size = CGSize(width:reference.width,height:reference.height)
        var first = CIImage(cgImage:reference)
        var second = canvas(try BeforeAfterImages.load(after,maxPixel:maxPixel),size:size)
        var rect = CGRect(origin:.zero,size:size)
        if project.usesAlignment, let alignment = project.alignment, alignment.isUsable, let corners = alignment.corners,
           let safe = safeCrop(corners:corners) {
            second = warp(second,corners:corners,size:size)
            rect = CGRect(x:safe.x*size.width,y:safe.y*size.height,width:safe.width*size.width,height:safe.height*size.height).integral
        }
        first = first.cropped(to:rect); second = second.cropped(to:rect)
        guard let a = context.createCGImage(first,from:rect), let b = context.createCGImage(second,from:rect) else { throw BeforeAfterError.export }
        return (a,b)
    }
}

enum BeforeAfterRenderEngine {
    /// Same normalized path is used for live preview and the exported bitmap.
    static func beforeMask(mode: BeforeAfterMode, position: Double, size: CGSize, angle:Double = .pi/4) -> CGPath {
        let p = position.isFinite ? min(1,max(0,position)) : 0.5
        let path = CGMutablePath(), w = size.width, h = size.height
        switch mode {
        case .sideBySide, .vertical: path.addRect(CGRect(x:0,y:0,width:w*p,height:h))
        case .horizontal: path.addRect(CGRect(x:0,y:0,width:w,height:h*p))
        case .diagonal:
            let points = BeforeAfterDividerGeometry.polygon(position:p,angle:angle)
            if let first = points.first {
                path.move(to:.init(x:first.x*w,y:first.y*h))
                for point in points.dropFirst() { path.addLine(to:.init(x:point.x*w,y:point.y*h)) }; path.closeSubpath()
            }
        }
        return path
    }
    static func render(project: BeforeAfterProject, pair: (CGImage,CGImage), account: BeforeAfterAccountContext) -> UIImage {
        let a = UIImage(cgImage:pair.0), b = UIImage(cgImage:pair.1)
        let sideBySide = project.mode == .sideBySide
        let size = CGSize(width:a.size.width*(sideBySide ? 2 : 1),height:a.size.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size:size,format:format).image { output in
            UIColor.black.setFill(); output.fill(CGRect(origin:.zero,size:size))
            if sideBySide {
                a.draw(in:CGRect(origin:.zero,size:a.size)); b.draw(in:CGRect(x:a.size.width,y:0,width:a.size.width,height:a.size.height))
            } else {
                b.draw(in:CGRect(origin:.zero,size:size))
                output.cgContext.saveGState()
                output.cgContext.addPath(beforeMask(mode:project.mode,position:project.dividerPosition,size:size,angle:project.effectiveDiagonalAngle)); output.cgContext.clip()
                a.draw(in:CGRect(origin:.zero,size:size)); output.cgContext.restoreGState()
                let ends = BeforeAfterDividerGeometry.endpoints(mode:project.mode,position:project.dividerPosition,angle:project.effectiveDiagonalAngle)
                if ends.count == 2 {
                    output.cgContext.move(to:CGPoint(x:ends[0].x*size.width,y:ends[0].y*size.height))
                    output.cgContext.addLine(to:CGPoint(x:ends[1].x*size.width,y:ends[1].y*size.height))
                    output.cgContext.setStrokeColor(UIColor.white.cgColor); output.cgContext.setLineWidth(max(1,size.width/1000)); output.cgContext.strokePath()
                }
            }
            if account.requiresWatermark(requested:project.showsWatermark) {
                let font = UIFont.systemFont(ofSize:min(size.width,size.height)*0.075,weight:.bold)
                let attrs: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:UIColor.white.withAlphaComponent(BeforeAfterWatermarkStyle.opacity)]
                let text = "Plaquisto" as NSString, textSize = text.size(withAttributes:attrs)
                for point in BeforeAfterWatermarkStyle.positions {
                    output.cgContext.saveGState()
                    output.cgContext.translateBy(x:point.x*size.width,y:point.y*size.height)
                    output.cgContext.rotate(by:BeforeAfterWatermarkStyle.angle)
                    output.cgContext.setShadow(offset:CGSize(width:0,height:1),blur:1,color:UIColor.black.withAlphaComponent(0.18).cgColor)
                    text.draw(at:CGPoint(x:-textSize.width/2,y:-textSize.height/2),withAttributes:attrs)
                    output.cgContext.restoreGState()
                }
            }
            let fontSize = max(16,size.width/45), padding = fontSize*0.7
            func label(_ text: String, x:CGFloat,y:CGFloat,maxWidth:CGFloat) {
                let font = UIFont.systemFont(ofSize:fontSize,weight:.semibold)
                let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
                let attrs: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:UIColor.white,.paragraphStyle:paragraph]
                let width = min(maxWidth,ceil((text as NSString).size(withAttributes:attrs).width))
                output.cgContext.saveGState()
                output.cgContext.setBlendMode(.normal)
                output.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
                output.cgContext.fill(CGRect(x:x-padding/2,y:y-padding/2,width:width+padding,height:font.lineHeight+padding))
                (text as NSString).draw(in:CGRect(x:x,y:y,width:width,height:ceil(font.lineHeight)),withAttributes:attrs)
                output.cgContext.restoreGState()
            }
            if project.mode == .diagonal {
                for isBefore in [true,false] {
                    let point = BeforeAfterDividerGeometry.labelPoint(before:isBefore,angle:project.effectiveDiagonalAngle)
                    let projection = BeforeAfterDividerGeometry.position(at:point,angle:project.effectiveDiagonalAngle)
                    if isBefore ? projection < project.dividerPosition : projection > project.dividerPosition {
                        label(isBefore ? "AVANT" : "APRÈS",x:max(padding,point.x*size.width-fontSize*2),y:point.y*size.height,maxWidth:fontSize*4.5)
                    }
                }
            } else if sideBySide || project.dividerPosition > 0.15 { label("AVANT",x:padding,y:padding,maxWidth:fontSize*4.5) }
            if project.mode != .diagonal && (sideBySide || project.dividerPosition < 0.85) {
                let bottomLabel = project.mode == .horizontal || project.mode == .diagonal
                label("APRÈS",x:size.width-fontSize*5.5,y:bottomLabel ? size.height-fontSize*6 : padding,maxWidth:fontSize*4.5)
            }
            if project.showsBranding, !project.branding.isEmpty {
                label(project.branding,x:padding,y:size.height-fontSize*4,maxWidth:size.width-padding*2)
            }
        }
    }
    static func export(project: BeforeAfterProject, before: URL, after: URL, account: BeforeAfterAccountContext) throws -> URL {
        let pair = try BeforeAfterAlignmentEngine.pair(project:project,before:before,after:after,maxPixel:2000)
        let image = render(project:project,pair:pair,account:account)
        guard let cg = image.cgImage else { throw BeforeAfterError.export }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Plaquisto-avant-apres-\(UUID().uuidString).jpg")
        try BeforeAfterImages.jpeg(cg,to:url)
        return url
    }
}
