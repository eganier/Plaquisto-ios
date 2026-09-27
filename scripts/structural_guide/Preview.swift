import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Builds a real guide with the app's production adapter, not a hand-drawn mockup.
@main struct GuidePreview {
    static func main() throws {
        let photo = URL(fileURLWithPath:CommandLine.arguments[1])
        let model = URL(fileURLWithPath:CommandLine.arguments[2])
        let prefix = CommandLine.arguments[3]
        guard let source = CGImageSourceCreateWithURL(photo as CFURL,nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1000] as CFDictionary),
              let raster = AppleBeforeAfterGuide.raster(cg) else { fatalError("Invalid photo") }
        let start = Date()
        let guide = try AppleBeforeAfterGuide(modelURL:model).extract(raster)
        let lines = AppleBeforeAfterGuide.render(guide,width:cg.width,height:cg.height)!
        func save(_ image: CGImage, _ suffix:String) {
            let out = URL(fileURLWithPath:prefix+suffix+".png")
            let dst = CGImageDestinationCreateWithURL(out as CFURL,UTType.png.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(dst,image,nil); CGImageDestinationFinalize(dst)
        }
        save(lines,"-transparent")
        let context = CGContext(data:nil,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x:0,y:0,width:cg.width,height:cg.height)
        context.setFillColor(CGColor(gray:0.035,alpha:1)); context.fill(rect)
        context.draw(lines,in:rect); save(context.makeImage()!,"-black")
        context.draw(cg,in:rect)
        context.setFillColor(CGColor(gray:0,alpha:0.30)); context.fill(rect)
        context.setShadow(offset:.zero,blur:3,color:CGColor(gray:1,alpha:0.6))
        context.draw(lines,in:rect); save(context.makeImage()!,"-overlay")
        print("lines",guide.lines.count,"points",guide.lines.map(\.count).reduce(0,+),"seconds",Date().timeIntervalSince(start))
    }
}
