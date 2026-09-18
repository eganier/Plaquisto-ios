import Foundation
import CoreGraphics
import CoreML

/// Apple runtime only. The exact same bundled detector is exported as ONNX;
/// photo geometry and tracing are platform-independent.
final class AppleBeforeAfterGuide: BeforeAfterGuideExtracting {
    private let modelURL: URL?
    private var model: MLModel?
    init(modelURL: URL? = Bundle.main.url(forResource:"StructuralContours",withExtension:"mlmodelc")) { self.modelURL = modelURL }
    func extract(_ raster: BeforeAfterGuideRaster) throws -> BeforeAfterGuide {
        guard let fit = BeforeAfterGuideFit(width:raster.width,height:raster.height),
              raster.width <= 4000, raster.height <= 4000,
              raster.rgba.count == raster.width*raster.height*4 else { throw BeforeAfterGuideFailure.invalidInput }
        if model == nil {
            guard let modelURL else { throw BeforeAfterGuideFailure.unavailable }
            let config = MLModelConfiguration(); config.computeUnits = .all
            model = try MLModel(contentsOf:modelURL,configuration:config)
        }
        guard let model, let provider = CGDataProvider(data:Data(raster.rgba) as CFData),
              let source = CGImage(width:raster.width,height:raster.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:raster.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { throw BeforeAfterGuideFailure.invalidInput }
        var bytes = [UInt8](repeating:0,count:512*512*4)
        guard let drawing = CGContext(data:&bytes,width:512,height:512,bitsPerComponent:8,bytesPerRow:512*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BeforeAfterGuideFailure.invalidInput }
        drawing.setFillColor(CGColor(gray:0.5,alpha:1)); drawing.fill(CGRect(x:0,y:0,width:512,height:512))
        drawing.interpolationQuality = .high
        drawing.draw(source,in:CGRect(x:fit.x,y:fit.y,width:fit.width,height:fit.height))
        let tensor = try MLMultiArray(shape:[1,3,512,512],dataType:.float32)
        let values = tensor.dataPointer.assumingMemoryBound(to:Float.self)
        for i in 0..<512*512 { for c in 0..<3 { values[c*512*512+i] = Float(bytes[i*4+c])/255 } }
        let result = try model.prediction(from:MLDictionaryFeatureProvider(dictionary:["rgb":MLFeatureValue(multiArray:tensor)]))
        guard let output = result.featureValue(for:"edges")?.multiArrayValue,
              output.shape.map(\.intValue) == [1,1,512,512] else { throw BeforeAfterGuideFailure.unavailable }
        let rowStride = output.strides[2].intValue, columnStride = output.strides[3].intValue
        var probabilities: [Float] = []; probabilities.reserveCapacity(fit.width*fit.height)
        for y in fit.y..<fit.y+fit.height { for x in fit.x..<fit.x+fit.width {
            probabilities.append(output[y*rowStride+x*columnStride].floatValue)
        } }
        return BeforeAfterGuideTracing.trace(probabilities:probabilities,width:fit.width,height:fit.height)
    }
    static func raster(_ image: CGImage) -> BeforeAfterGuideRaster? {
        guard image.width <= 4000, image.height <= 4000 else { return nil }
        var bytes = [UInt8](repeating:0,count:image.width*image.height*4)
        guard let context = CGContext(data:&bytes,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return .init(width:image.width,height:image.height,rgba:bytes)
    }
    static func render(_ guide: BeforeAfterGuide, width:Int, height:Int) -> CGImage? {
        guard width > 0, height > 0, width <= 2400, height <= 2400,
              let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let path = CGMutablePath()
        for line in guide.lines {
            guard let first = line.first else { continue }
            path.move(to:CGPoint(x:first.x*Double(width),y:(1-first.y)*Double(height)))
            for p in line.dropFirst() { path.addLine(to:CGPoint(x:p.x*Double(width),y:(1-p.y)*Double(height))) }
        }
        context.setLineWidth(max(1.4,Double(max(width,height))/400)); context.setLineCap(.round); context.setLineJoin(.round)
        context.setStrokeColor(CGColor(gray:1,alpha:1)); context.addPath(path); context.strokePath()
        return context.makeImage()
    }
}
