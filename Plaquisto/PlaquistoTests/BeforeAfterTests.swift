import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Plaquisto

final class BeforeAfterTests: XCTestCase {
    func testRotatedDividerMaskAndLineAgreeAtAllAngles() {
        for angle in stride(from:-Double.pi,through:2 * .pi,by:.pi/18) {
            for p in [0.1,0.3,0.5,0.8] {
                let ends = BeforeAfterDividerGeometry.endpoints(mode:.diagonal,position:p,angle:angle)
                XCTAssertEqual(ends.count,2)
                for point in ends {
                    XCTAssertEqual(BeforeAfterDividerGeometry.position(at:point,angle:angle),p,accuracy:1e-9)
                }
                let size = CGSize(width:320,height:180)
                let mask = BeforeAfterRenderEngine.beforeMask(mode:.diagonal,position:p,size:size,angle:angle)
                for x in [0.13,0.46,0.83] { for y in [0.17,0.57,0.91] {
                    let projection = BeforeAfterDividerGeometry.position(at:.init(x:x,y:y),angle:angle)
                    if abs(projection-p) > 1e-6 {
                        XCTAssertEqual(mask.contains(.init(x:x*size.width,y:y*size.height)),projection < p)
                    }
                } }
            }
        }
    }
    func testLegacyProjectDecodesWithoutDiagonalAngle() throws {
        let original = BeforeAfterProject(before:.init(filename:"before.jpg",metadata:.init()))
        let data = try JSONEncoder().encode(original)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("diagonalAngle"))
        let restored = try JSONDecoder().decode(BeforeAfterProject.self,from:data)
        XCTAssertEqual(restored.effectiveDiagonalAngle,.pi/4)
    }
    @MainActor func testLastCompositionPersistsAndThumbnailMatchesRenderer() async throws {
        let root = try directory(), a = try fixture(root,color:.red), b = try fixture(root,name:"after.jpg",color:.blue)
        let store = BeforeAfterProjectStore(root:root.appendingPathComponent("projects"))
        var project = try await store.create(from:a,identifier:nil,company:nil)
        project = try await store.addCapture(Data(contentsOf:b),to:project,summary:"Manual")
        project.alignment = .failed("fixture"); project.usesAlignment = false; project.showsWatermark = false
        let model = BeforeAfterEditorModel(project:project,store:store)
        let account = BeforeAfterAccountContext(allowsLabWatermarkControl:true)
        var renders: [Data] = []
        for mode in BeforeAfterMode.allCases {
            model.project.mode = mode; model.project.divider = 0.37; model.project.diagonalAngle = 2.4
            await model.persistEdits()
            let saved = try await store.list()
            let restored = try XCTUnwrap(saved.first)
            XCTAssertEqual(restored.mode,mode); XCTAssertEqual(restored.effectiveDiagonalAngle,2.4)
            let thumbnail = await store.thumbnail(project:restored,account:account)
            let result = try XCTUnwrap(thumbnail)
            let beforeURL = try await store.imageURL(restored.before,projectID:restored.id)
            let afterURL = try await store.imageURL(try XCTUnwrap(restored.after),projectID:restored.id)
            let pair = try BeforeAfterAlignmentEngine.pair(project:restored,before:beforeURL,after:afterURL,maxPixel:320)
            let expected = BeforeAfterRenderEngine.render(project:restored,pair:pair,account:account)
            XCTAssertEqual(result.size,expected.size)
            let data = try XCTUnwrap(result.pngData()); renders.append(data)
            XCTAssertEqual(data,expected.pngData(),"List preview must use the same saved composition as the renderer")
            let attachment = XCTAttachment(image:result); attachment.name = "Montage miniature — \(mode.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(Set(renders).count,4,"Every layout must have its own composition, not the original Before thumbnail")
        let old = renders.last
        model.project.diagonalAngle = -0.7
        await model.persistEdits()
        let saved = try await store.list()
        let rotated = await store.thumbnail(project:try XCTUnwrap(saved.first),account:account)
        XCTAssertNotEqual(rotated?.pngData(),old)
    }
    @MainActor
    func testCameraReferencePreparationDoesNotRequireContourModel() async throws {
        let controller = BeforeAfterCameraController()
        XCTAssertFalse(controller.referenceReady)
        XCTAssertFalse(controller.canAutoCapture)
        controller.prepareReference(UIImage(cgImage:image(color:.gray)))
        for _ in 0..<100 {
            if controller.referenceReady { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertTrue(controller.referenceReady)
        // A prepared photo alone must never trigger an automatic capture.
        XCTAssertFalse(controller.canAutoCapture)
    }
    func testStructuralGuideFitNeverStretchesOrCropsPhoto() {
        XCTAssertEqual(BeforeAfterGuideFit(width:600,height:800)?.width,384)
        XCTAssertEqual(BeforeAfterGuideFit(width:600,height:800)?.x,64)
        XCTAssertEqual(BeforeAfterGuideFit(width:800,height:600)?.height,384)
        XCTAssertEqual(BeforeAfterGuideFit(width:800,height:600)?.y,64)
        XCTAssertNil(BeforeAfterGuideFit(width:0,height:800))
        XCTAssertNil(BeforeAfterGuideFit(width:Int.max,height:800))
    }
    func testStructuralTracingRetainsLongEdgesAndRemovesSpeckles() {
        let w = 128, h = 128
        var edges = [Float](repeating:0.45,count:w*h)
        for x in 10..<118 { edges[30*w+x] = 0.99 }
        edges[80*w+50] = 0.99; edges[90*w+60] = 0.99
        let guide = BeforeAfterGuideTracing.trace(probabilities:edges,width:w,height:h)
        XCTAssertEqual(guide.lines.count,1)
        XCTAssertEqual(guide.lines.first?.count,2)
        XCTAssertEqual(guide.lines.first?.first?.y ?? 0,30.5/128,accuracy:0.001)
        XCTAssertTrue(BeforeAfterGuideTracing.trace(probabilities:[.nan],width:128,height:128).isEmpty)
        XCTAssertTrue(BeforeAfterGuideTracing.trace(probabilities:[Float](repeating:0.5,count:w*h),width:w,height:h).isEmpty)
    }
    func testStructuralTracingRejectsDenseTexturePatches() {
        var map = [Float](repeating:0.45,count:128*128)
        for y in 20..<100 { for x in 20..<100 { map[y*128+x] = 0.98 } }
        let guide = BeforeAfterGuideTracing.trace(probabilities:map,width:128,height:128)
        XCTAssertTrue(guide.isEmpty)
    }
    func testStructuralModelIsBundledAndMissingModelFailsExplicitly() throws {
        XCTAssertNotNil(Bundle.main.url(forResource:"StructuralContours",withExtension:"mlmodelc"))
        let raster = try XCTUnwrap(AppleBeforeAfterGuide.raster(image(color:.gray)))
        XCTAssertThrowsError(try AppleBeforeAfterGuide(modelURL:nil).extract(raster))
    }
    func testContourGuideKeepsLowContrastWallEdges() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let photo = UIGraphicsImageRenderer(size:CGSize(width:480,height:360),format:format).image { output in
            UIColor(white:0.76,alpha:1).setFill(); output.fill(CGRect(x:0,y:0,width:480,height:360))
            UIColor(white:0.72,alpha:1).setFill(); output.fill(CGRect(x:120,y:80,width:220,height:220))
        }
        let guide = try XCTUnwrap(BeforeAfterAlignmentEngine.contourGuide(CIImage(cgImage:photo.cgImage!)))
        var pixels = [UInt8](repeating:0,count:480*360*4)
        let context = CGContext(data:&pixels,width:480,height:360,bitsPerComponent:8,bytesPerRow:480*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(guide,in:CGRect(x:0,y:0,width:480,height:360))
        let visible = stride(from:3,to:pixels.count,by:4).filter { pixels[$0] > 100 }.count
        XCTAssertGreaterThan(visible,500,"A pale wall/window boundary must remain visible, not a transparent image")
        let evidence = XCTAttachment(image:UIImage(cgImage:guide)); evidence.name = "Contours mur pale — alpha"; evidence.lifetime = .keepAlways; add(evidence)
    }
    func testContourGuidePreservesSourceOrientation() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let photo = UIGraphicsImageRenderer(size:CGSize(width:240,height:320),format:format).image { output in
            UIColor.white.setFill(); output.fill(CGRect(x:0,y:0,width:240,height:320))
            UIColor.gray.setFill(); output.fill(CGRect(x:30,y:25,width:100,height:70))
        }
        let guide = try XCTUnwrap(BeforeAfterAlignmentEngine.contourGuide(CIImage(cgImage:photo.cgImage!)))
        func centroid(_ cg: CGImage, isGuide: Bool) -> CGPoint {
            var p = [UInt8](repeating:0,count:240*320*4)
            let c = CGContext(data:&p,width:240,height:320,bitsPerComponent:8,bytesPerRow:240*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(cg,in:CGRect(x:0,y:0,width:240,height:320))
            var x = 0.0, y = 0.0, count = 0.0
            for i in 0..<240*320 where isGuide ? p[i*4+3] > 100 : p[i*4] < 200 {
                x += Double(i%240); y += Double(i/240); count += 1
            }
            return CGPoint(x:x/max(1,count),y:y/max(1,count))
        }
        let a = centroid(photo.cgImage!,isGuide:false), b = centroid(guide,isGuide:true)
        XCTAssertEqual(a.x,b.x,accuracy:3)
        XCTAssertEqual(a.y,b.y,accuracy:3,"Contours must not flip vertically against the camera")
    }
    func testContourGuideHasTransparentBackgroundNotPhoto() throws {
        let flat = try XCTUnwrap(BeforeAfterAlignmentEngine.contourGuide(CIImage(cgImage:image(color:.gray))))
        let pattern = try XCTUnwrap(BeforeAfterAlignmentEngine.contourGuide(CIImage(cgImage:image())))
        func alphaCounts(_ cg: CGImage) -> (clear:Int,visible:Int) {
            var bytes = [UInt8](repeating:0,count:cg.width*cg.height*4)
            let context = CGContext(data:&bytes,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
            let alphas = stride(from:3,to:bytes.count,by:4).map { bytes[$0] }
            return (alphas.filter { $0 < 10 }.count,alphas.filter { $0 > 100 }.count)
        }
        XCTAssertGreaterThan(alphaCounts(flat).clear,flat.width*flat.height*9/10)
        XCTAssertGreaterThan(alphaCounts(pattern).clear,pattern.width*pattern.height/2)
        XCTAssertGreaterThan(alphaCounts(pattern).visible,100)
    }
    func testLabCanDisableWatermarkWithoutSubscription() {
        let lab = BeforeAfterAccountContext(allowsLabWatermarkControl:true)
        XCTAssertFalse(lab.requiresWatermark(requested:false))
        XCTAssertTrue(lab.requiresWatermark(requested:true))
        XCTAssertTrue(BeforeAfterAccountContext.unconfigured.requiresWatermark(requested:false))
    }
    func testLiveGuidanceRejectsUncertainAndDistortedMatches() {
        XCTAssertFalse(BeforeAfterFraming.evaluate(.failed("absent")).aligned)
        let corners = [BeforeAfterPoint(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)]
        let identity = BeforeAfterAlignmentPolicy.evaluate(score:0.9,baseline:0.9,corners:corners)
        XCTAssertTrue(BeforeAfterFraming.evaluate(identity).aligned)
        let weak = BeforeAfterAlignmentPolicy.evaluate(score:0.4,baseline:0.4,corners:corners)
        XCTAssertFalse(BeforeAfterFraming.evaluate(weak).aligned)
        let moved = corners.map { BeforeAfterPoint(x:$0.x+0.08,y:$0.y) }
        let result = BeforeAfterFraming.evaluate(BeforeAfterAlignmentPolicy.evaluate(score:0.9,baseline:0.5,corners:moved))
        XCTAssertFalse(result.aligned)
        XCTAssertTrue(result.message.contains("gauche"))
    }
    func testAutomaticCaptureRequiresContinuousStableWindow() {
        var gate = BeforeAfterCaptureStability()
        XCTAssertEqual(gate.update(aligned:true,time:0),0)
        XCTAssertLessThan(gate.update(aligned:true,time:0.6),1)
        XCTAssertLessThan(gate.update(aligned:true,time:1.2),1)
        XCTAssertEqual(gate.update(aligned:true,time:1.9),1)
        XCTAssertEqual(gate.update(aligned:false,time:2),0)
        XCTAssertEqual(gate.update(aligned:true,time:2.6),0)
        XCTAssertEqual(gate.update(aligned:true,time:5),0,"A stale result must not trigger capture")
        XCTAssertEqual(gate.update(aligned:true,time:.nan),0)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BeforeAfterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }
        return url
    }
    private func image(size: CGSize = .init(width:480,height:360), color: UIColor? = nil) -> CGImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size:size,format:format).image { context in
            (color ?? UIColor.white).setFill(); context.fill(CGRect(origin:.zero,size:size))
            guard color == nil else { return }
            for i in 0..<100 {
                UIColor(hue:CGFloat((i*37)%100)/100,saturation:0.8,brightness:0.3+CGFloat(i%7)/10,alpha:1).setFill()
                context.fill(CGRect(x:(i*53)%430,y:(i*71)%310,width:15+i%31,height:10+i%29))
            }
        }.cgImage!
    }
    private func fixture(_ root: URL,name:String = "source.jpg",color:UIColor? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        try BeforeAfterImages.jpeg(image(color:color),to:url); return url
    }
    func testMetadataAvailableAndMissing() {
        let properties: [String:Any] = [
            kCGImagePropertyPixelWidth as String:4000,kCGImagePropertyPixelHeight as String:3000,kCGImagePropertyOrientation as String:6,
            kCGImagePropertyTIFFDictionary as String:[kCGImagePropertyTIFFMake as String:"Apple",kCGImagePropertyTIFFModel as String:"iPhone 17 Pro"],
            kCGImagePropertyExifDictionary as String:[kCGImagePropertyExifFocalLength as String:6.8,kCGImagePropertyExifFocalLenIn35mmFilm as String:24,
                kCGImagePropertyExifISOSpeedRatings as String:[125],kCGImagePropertyExifExposureTime as String:0.01,kCGImagePropertyExifFNumber as String:1.8,
                kCGImagePropertyExifExposureBiasValue as String:-0.3,kCGImagePropertyExifDateTimeOriginal as String:"2026:09:17 10:00:00"],
            kCGImagePropertyGPSDictionary as String:[kCGImagePropertyGPSLatitude as String:45.7,kCGImagePropertyGPSLatitudeRef as String:"N",kCGImagePropertyGPSLongitude as String:4.8,kCGImagePropertyGPSLongitudeRef as String:"E"]
        ]
        let result = BeforeAfterMetadataExtractor.extract(properties:properties)
        XCTAssertEqual(result.model,"iPhone 17 Pro"); XCTAssertEqual(result.iso,125); XCTAssertEqual(result.focalLength35,24)
        XCTAssertEqual(result.latitude,45.7); XCTAssertEqual(result.longitude,4.8); XCTAssertEqual(result.orientation,6)
        XCTAssertEqual(result.aperture,1.8); XCTAssertEqual(result.exposureSeconds,0.01); XCTAssertEqual(result.pixelWidth,4000)
        let empty = BeforeAfterMetadataExtractor.extract(properties:[:])
        XCTAssertTrue(empty.rows.isEmpty); XCTAssertFalse(empty.hasLocation); XCTAssertNil(empty.model)
    }
    func testGPSRequiresCompleteValidCoordinates() {
        let p: [String:Any] = [kCGImagePropertyGPSDictionary as String:[kCGImagePropertyGPSLatitude as String:45.7,kCGImagePropertyGPSLongitude as String:4.8]]
        XCTAssertFalse(BeforeAfterMetadataExtractor.extract(properties:p).hasLocation)
    }
    func testModelCompatibilityIsConservative() {
        XCTAssertEqual(BeforeAfterCompatibility.check(source:" iPhone 17 Pro ",current:"iphone 17 pro"),.sameModel)
        XCTAssertEqual(BeforeAfterCompatibility.check(source:"iPhone 16 Pro",current:"iPhone 17 Pro"),.differentModel)
        XCTAssertEqual(BeforeAfterCompatibility.check(source:"iPhone",current:"iPhone"),.unknown)
        XCTAssertEqual(BeforeAfterCompatibility.check(source:nil,current:"iPhone 17 Pro"),.unknown)
        XCTAssertEqual(BeforeAfterCompatibility.check(source:"iPhone 17 Pro",current:nil),.unknown)
    }
    func testWatermarkCannotBeRemovedByProjectFlag() {
        let start = BeforeAfterAccountContext.unconfigured
        XCTAssertTrue(start.requiresWatermark(requested:false))
        XCTAssertFalse(BeforeAfterAccountContext(verifiedPlan:.plus).requiresWatermark(requested:false))
        XCTAssertFalse(BeforeAfterAccountContext(verifiedPlan:.pro).requiresWatermark(requested:false))
        XCTAssertTrue(BeforeAfterAccountContext(verifiedPlan:.pro).requiresWatermark(requested:true))
    }
    func testPrefillDoesNotOverwriteManualBrandingOrInventCity() {
        var p = BeforeAfterProject(before:.init(filename:"before.jpg",metadata:.init()))
        p.prefill(account:.init(companyName:"SOLTAE"))
        XCTAssertEqual(p.company,"SOLTAE"); XCTAssertEqual(p.city,"")
        p.prefill(account:.init(companyName:"Autre"),city:"Lyon")
        XCTAssertEqual(p.branding,"SOLTAE — Lyon")
        p.prefill(account:.unconfigured,city:"Paris"); XCTAssertEqual(p.city,"Lyon")
    }
    @MainActor func testNoGeolocationDoesNotGeocode() async throws {
        let city = try await BeforeAfterCityResolver.city(for:.init())
        XCTAssertNil(city)
    }
    func testCreateSaveReloadAndDividerAllModes() async throws {
        let root = try directory(), source = try fixture(root)
        let store = BeforeAfterProjectStore(root:root.appendingPathComponent("projects"))
        var project = try await store.create(from:source,identifier:"optional-ios-id",company:"Entreprise")
        XCTAssertEqual(project.company,"Entreprise")
        project = try await store.addCapture(Data(contentsOf:source),to:project,summary:"Automatique")
        for mode in BeforeAfterMode.allCases {
            project.mode = mode; project.divider = 0.73; project.city = "Lyon"
            project = try await store.save(project)
            let reloaded = try await BeforeAfterProjectStore(root:root.appendingPathComponent("projects")).list()
            XCTAssertEqual(reloaded.count,1); XCTAssertEqual(reloaded.first,project)
            XCTAssertEqual(reloaded.first?.dividerPosition,0.73)
        }
        let beforeURL = try await store.imageURL(project.before,projectID:project.id)
        XCTAssertNotNil(try BeforeAfterImages.load(beforeURL,maxPixel:120))
        let thumbnail = await store.thumbnail(project.id); XCTAssertNotNil(thumbnail)
        try await store.delete(project.id)
        let remaining = try await store.list(); XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
    func testStoreRejectsPhotoPathTraversal() async throws {
        let store = BeforeAfterProjectStore(root:try directory())
        do { _ = try await store.imageURL(.init(filename:"../secret.jpg",metadata:.init()),projectID:UUID()); XCTFail("Unsafe path") } catch {}
    }
    func testFailedCaptureDoesNotReplaceSavedProject() async throws {
        let root = try directory(), source = try fixture(root)
        let store = BeforeAfterProjectStore(root:root.appendingPathComponent("projects"))
        let project = try await store.create(from:source,identifier:nil,company:nil)
        do { _ = try await store.addCapture(Data([1,2,3]),to:project,summary:""); XCTFail("Invalid image") } catch {}
        let projects = try await store.list(); XCTAssertEqual(projects.first,project)
    }
    @MainActor func testReopeningCaptureResumesPendingAlignment() async throws {
        let root = try directory(), source = try fixture(root)
        let store = BeforeAfterProjectStore(root:root.appendingPathComponent("projects"))
        var project = try await store.create(from:source,identifier:nil,company:nil)
        project = try await store.addCapture(Data(contentsOf:source),to:project,summary:"Test")
        XCTAssertNil(project.alignment)
        let editor = BeforeAfterEditorModel(project:project,store:store)
        await editor.load()
        XCTAssertNotNil(editor.pair); XCTAssertTrue(editor.project.alignment?.isUsable == true)
        let persisted = try await store.list(); XCTAssertNotNil(persisted.first?.alignment)
    }
    func testComparisonMasksEndpointsAndAxes() {
        let size = CGSize(width:100,height:100)
        for mode in [BeforeAfterMode.vertical,.horizontal,.diagonal] {
            XCTAssertFalse(BeforeAfterRenderEngine.beforeMask(mode:mode,position:0,size:size).contains(.init(x:50,y:50)))
            XCTAssertTrue(BeforeAfterRenderEngine.beforeMask(mode:mode,position:1,size:size).contains(.init(x:50,y:50)))
        }
        XCTAssertTrue(BeforeAfterRenderEngine.beforeMask(mode:.diagonal,position:0.5,size:size).contains(.init(x:10,y:10)))
        XCTAssertFalse(BeforeAfterRenderEngine.beforeMask(mode:.diagonal,position:0.5,size:size).contains(.init(x:90,y:90)))
        var p = BeforeAfterProject(before:.init(filename:"x",metadata:.init())); p.divider = .nan
        XCTAssertEqual(p.dividerPosition,0.5)
        let ends = BeforeAfterDividerGeometry.endpoints(mode:.diagonal,position:0.25)
        XCTAssertEqual(ends.count,2)
        XCTAssertEqual(ends[0].x,0.5,accuracy:1e-10); XCTAssertEqual(ends[0].y,0,accuracy:1e-10)
        XCTAssertEqual(ends[1].x,0,accuracy:1e-10); XCTAssertEqual(ends[1].y,0.5,accuracy:1e-10)
        XCTAssertTrue(BeforeAfterDividerGeometry.endpoints(mode:.vertical,position:1).isEmpty)
    }
    func testAlignmentRejectsUnsafeOrWeakTransforms() {
        let corners = [BeforeAfterPoint(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)]
        XCTAssertTrue(BeforeAfterAlignmentEngine.evaluate(score:0.8,baseline:0.4,corners:corners).isUsable)
        XCTAssertFalse(BeforeAfterAlignmentEngine.evaluate(score:0.1,baseline:0,corners:corners).isUsable)
        XCTAssertFalse(BeforeAfterAlignmentEngine.evaluate(score:0.4,baseline:0.8,corners:corners).isUsable)
        XCTAssertNil(BeforeAfterAlignmentEngine.safeCrop(corners:corners.map { .init(x:$0.x+0.8,y:$0.y) }))
        XCTAssertNil(BeforeAfterAlignmentEngine.safeCrop(corners:[.init(x:.nan,y:0)]))
        let crop = BeforeAfterAlignmentEngine.safeCrop(corners:corners.map { .init(x:$0.x+0.05,y:$0.y) })
        XCTAssertNotNil(crop); XCTAssertGreaterThanOrEqual(crop?.x ?? 0,0.045)
    }
    func testAlignmentIdenticalTexturedImagesAndBlankFallback() throws {
        let root = try directory(), reference = try fixture(root)
        let result = BeforeAfterAlignmentEngine.align(before:reference,after:reference)
        XCTAssertTrue(result.isUsable,result.message)
        let blank = try fixture(root,name:"blank.jpg",color:.white)
        XCTAssertFalse(BeforeAfterAlignmentEngine.align(before:blank,after:blank).isUsable)
        XCTAssertFalse(BeforeAfterAlignmentEngine.align(before:root.appendingPathComponent("missing"),after:reference).isUsable)
    }
    func testExportBrandingAndGPSNotPropagated() throws {
        let root = try directory(), a = try fixture(root), b = try fixture(root,name:"after.jpg",color:.blue)
        var p = BeforeAfterProject(before:.init(filename:"before.jpg",metadata:.init(latitude:45.7,longitude:4.8)))
        p.mode = .sideBySide; p.company = "SOLTAE"; p.city = "Lyon"; p.showsBranding = true; p.showsWatermark = false
        let pair = try BeforeAfterAlignmentEngine.pair(project:p,before:a,after:b,maxPixel:480)
        let branded = BeforeAfterRenderEngine.render(project:p,pair:pair,account:.unconfigured)
        p.showsBranding = false
        let plain = BeforeAfterRenderEngine.render(project:p,pair:pair,account:.unconfigured)
        XCTAssertEqual(branded.size.width,960); XCTAssertNotEqual(branded.pngData(),plain.pngData())
        let paid = BeforeAfterRenderEngine.render(project:p,pair:pair,account:.init(verifiedPlan:.plus))
        XCTAssertNotEqual(plain.pngData(),paid.pngData())
        let export = try BeforeAfterRenderEngine.export(project:p,before:a,after:b,account:.unconfigured)
        defer { try? FileManager.default.removeItem(at:export) }
        XCTAssertFalse(try BeforeAfterMetadataExtractor.extract(url:export).hasLocation)
    }
    func testExportLabelsStayInsideImageAndBackgroundBlends() {
        let cg = image(color:.blue)
        var project = BeforeAfterProject(before:.init(filename:"x",metadata:.init()))
        project.mode = .sideBySide; project.showsWatermark = false
        let result = BeforeAfterRenderEngine.render(project:project,pair:(cg,cg),account:.init(verifiedPlan:.plus)).cgImage!
        var bytes = [UInt8](repeating:0,count:result.width*result.height*4)
        let ctx = CGContext(data:&bytes,width:result.width,height:result.height,bitsPerComponent:8,bytesPerRow:result.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(result,in:CGRect(x:0,y:0,width:result.width,height:result.height))
        // Both outermost rows remain blue: no cropped white lettering at top/bottom.
        for y in [0,result.height-1] {
            for x in 0..<result.width { XCTAssertLessThan(bytes[(y*result.width+x)*4],20) }
        }
        // Semi-transparent black badges retain the blue channel, not opaque grey.
        let coloredDark = stride(from:0,to:bytes.count,by:4).contains { i in bytes[i] < 10 && bytes[i+1] < 10 && bytes[i+2] > 40 && bytes[i+2] < 200 }
        XCTAssertTrue(coloredDark)
    }
    func testAlignmentTranslationDirectionAndCrop() throws {
        let root = try directory(), reference = try fixture(root), target = root.appendingPathComponent("shifted.jpg")
        let cg = try BeforeAfterImages.load(reference,maxPixel:480), original = UIImage(cgImage:cg)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let shifted = UIGraphicsImageRenderer(size:original.size,format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:original.size))
            original.draw(at:CGPoint(x:18,y:-12))
        }
        try BeforeAfterImages.jpeg(shifted.cgImage!,to:target)
        let result = BeforeAfterAlignmentEngine.align(before:reference,after:target)
        XCTAssertTrue(result.isUsable,result.message)
        XCTAssertEqual(result.corners?.first?.x ?? 10,-18.0/480,accuracy:0.025)
        XCTAssertEqual(result.corners?.first?.y ?? 10,-12.0/360,accuracy:0.025)
        XCTAssertGreaterThan(result.crop.x,0)
    }
    func testNewToolSearchAndNavigation() {
        XCTAssertEqual(ToolCatalog.search("avant après").map(\.destination),[.beforeAfter])
        XCTAssertTrue(ToolCatalog.search("rénovation").contains { $0.destination == .beforeAfter })
    }
    func testPlatformAlignmentServiceCanBeReplaced() async {
        struct OtherPlatform: BeforeAfterAligning {
            func align(before: URL,after: URL) -> BeforeAfterAlignment { .failed("Test adapter") }
        }
        let service = BeforeAfterProcessing(alignment:OtherPlatform(),exporter:AppleBeforeAfterExport())
        let result = await service.align(before:URL(fileURLWithPath:"/before"),after:URL(fileURLWithPath:"/after"))
        XCTAssertEqual(result.message,"Test adapter")
    }
}
