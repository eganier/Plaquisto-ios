import XCTest
import SwiftUI
@testable import Plaquisto

final class SheetLayoutEngineTests: XCTestCase {
    func testHorizontalAlignmentIsViewOnlyAndWorksForBothWindings() throws {
        let polygon:[LayoutPoint] = [.zero,.init(x:4000,y:300),.init(x:4300,y:3000),.init(x:-200,y:2700)]
        for contour in [polygon,Array(polygon.reversed())] {
            let rotation = LayoutViewport.horizontalBaseRotation(contour)
            let edge = try XCTUnwrap(LayoutStrokeBeautifier.groundEdge(contour))
            let a = LayoutViewport.rotated(edge.a,by:rotation), b = LayoutViewport.rotated(edge.b,by:rotation)
            XCTAssertEqual(a.y,b.y,accuracy:0.000001)
            let rotated = contour.map { LayoutViewport.rotated($0,by:rotation) }
            for i in contour.indices {
                XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:i,in:contour),LayoutPolygonSolver.interiorAngle(at:i,in:rotated),accuracy:0.000001)
            }
            XCTAssertEqual(abs(LayoutGeometry.area(contour)),abs(LayoutGeometry.area(rotated)),accuracy:0.000001)
        }
    }

    @MainActor func testSavedLayoutCreationDateSurvivesRenameSaveAndLegacyDecode() throws {
        let name = "layout-library-metadata-\(UUID())", defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let date = Date(timeIntervalSince1970:1_700_000_000)
        let original = SavedLayoutDocument(document:.init(surface:surface()),createdAt:date)
        defaults.set(try JSONEncoder().encode([original]),forKey:"plaquisto.tools.layout.library.v1")
        let model = LayoutEditorModel(defaults:defaults)
        model.rename(original,to:"  Salon  ")
        XCTAssertEqual(model.savedDocuments.first?.title,"Salon")
        XCTAssertEqual(model.savedDocuments.first?.createdAt,date)
        model.rename(model.savedDocuments[0],to:" \n ")
        XCTAssertEqual(model.savedDocuments.first?.title,"Salon")
        let renamed = model.savedDocuments[0]
        model.open(renamed)
        var changed = try XCTUnwrap(model.document); changed.layers[0].offset.x = 90
        model.apply(changed); model.saveCurrentAndClose()
        XCTAssertNil(model.document)
        XCTAssertEqual(model.savedDocuments.count,1)
        XCTAssertEqual(model.savedDocuments[0].createdAt,date)
        XCTAssertEqual(model.savedDocuments[0].document,changed)
        let reloaded = LayoutEditorModel(defaults:defaults)
        XCTAssertEqual(reloaded.savedDocuments,model.savedDocuments)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        legacy.removeValue(forKey:"createdAt")
        let decoded = try JSONDecoder().decode(SavedLayoutDocument.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertEqual(decoded.createdAt,date)
        XCTAssertEqual(decoded.document,original.document)
        reloaded.delete(reloaded.savedDocuments[0])
        XCTAssertTrue(LayoutEditorModel(defaults:defaults).savedDocuments.isEmpty)
    }

    @MainActor func testSavedThumbnailAndUpdatedVisibilityIconsRender() throws {
        let wall = LayoutDocument.newSupport(surface(.lShape))
        var ceiling = LayoutDocument.newSupport(surface())
        ceiling.surface.kind = .ceiling
        ceiling.layers[0].referenceEdge = 1
        let content = VStack(spacing:16) {
            HStack {
                LayoutSavedThumbnail(document:wall).frame(width:140,height:110)
                LayoutSavedThumbnail(document:ceiling).frame(width:140,height:110)
            }
            ForEach([LayoutVisibilityState.visible,.dimensioned,.hidden],id:\.rawValue) { state in
                HStack(spacing:2) {
                    LayoutVisibilityIcon(kind:.angle,state:state == .hidden ? .hidden : .visible)
                    LayoutVisibilityIcon(kind:.sheet,state:state)
                    LayoutVisibilityIcon(kind:.framing,state:state)
                    LayoutVisibilityIcon(kind:.opening,state:state)
                    LayoutVisibilityIcon(kind:.electrical,state:state)
                }.frame(height:44)
            }
        }.padding().frame(width:390).background(Color(.systemGroupedBackground))
        let renderer = ImageRenderer(content:content); renderer.scale = 2
        let attachment = XCTAttachment(image:try XCTUnwrap(renderer.uiImage))
        attachment.name = "Bibliothèque et icônes alignées"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testViewportRotationKeepsOriginAndRoundTripsCoordinates() {
        let bounds = LayoutBounds(min:.init(x:-500,y:-500),max:.init(x:5000,y:4000))
        let base = LayoutViewport(bounds:bounds,size:.init(width:390,height:600),zoom:1.7,pan:.init(width:23,height:-11))
        for angle in [-2.2,0,.pi/2,4.9] {
            var rotated = base; rotated.rotation = angle
            XCTAssertEqual(rotated.screen(.zero),base.screen(.zero))
            let point = LayoutPoint(x:1400,y:3300)
            let back = rotated.world(rotated.screen(point))
            XCTAssertEqual(back.x,point.x,accuracy:0.000001); XCTAssertEqual(back.y,point.y,accuracy:0.000001)
            let delta = CGSize(width:31,height:-17), worldDelta = rotated.worldDelta(delta)
            let moved = rotated.screen(point+worldDelta), old = rotated.screen(point)
            XCTAssertEqual(moved.x-old.x,31,accuracy:0.000001); XCTAssertEqual(moved.y-old.y,-17,accuracy:0.000001)
        }
    }
    func testRotatedRecenterFitsEveryCorner() {
        let points = surface(width:6000,height:2500).contour
        let angle = 1.1
        let viewport = LayoutViewport(bounds:LayoutViewport.fittedBounds(points,rotation:angle),size:.init(width:390,height:400),zoom:1,pan:.zero,rotation:angle)
        for point in points {
            let p = viewport.screen(point)
            XCTAssertTrue((0...390).contains(p.x)); XCTAssertTrue((0...400).contains(p.y))
        }
    }
    func testRotationDetentAcquiresAndReleasesForAnyWall() {
        let points = surface().contour.map { LayoutViewport.rotated($0,by:0.4) }
        let acquired = LayoutViewport.snappedRotation(-0.39,contour:points,latched:nil)
        XCTAssertEqual(acquired.angle,-0.4,accuracy:0.000001); XCTAssertNotNil(acquired.latch)
        let held = LayoutViewport.snappedRotation(-0.34,contour:points,latched:acquired.latch)
        XCTAssertEqual(held.angle,-0.4,accuracy:0.000001)
        let released = LayoutViewport.snappedRotation(-0.2,contour:points,latched:held.latch)
        XCTAssertNil(released.latch); XCTAssertEqual(released.angle,-0.2)
    }
    func testSpotRotationPreservesCenterDistancesTypesAndOtherPoints() throws {
        var lighting = LayoutLighting(); lighting.count = 3
        lighting.positions = [.init(x:1000,y:1000),.init(x:2000,y:1000),.init(x:4000,y:2500)]
        lighting.kinds = [.socket,.light,.socket]
        let rotated = LayoutPlanning.rotatedLighting(lighting,selected:[0,1],angle:.pi/2)
        XCTAssertEqual(rotated.positions[0].x,1500,accuracy:0.001)
        XCTAssertEqual(rotated.positions[0].y,500,accuracy:0.001)
        XCTAssertEqual(rotated.positions[1].y,1500,accuracy:0.001)
        XCTAssertEqual(rotated.positions[2],lighting.positions[2]); XCTAssertEqual(rotated.kinds,lighting.kinds)
        XCTAssertEqual((rotated.positions[1]-rotated.positions[0]).length,1000,accuracy:0.001)
        let s = surface(width:6000,height:4000)
        XCTAssertTrue(LayoutPlanning.lightingFits(rotated,surface:s))
        let snap = LayoutPlanning.snappedLightingRotation(0.01,lighting:lighting,selected:[0,1],contour:s.contour,latched:nil)
        XCTAssertEqual(snap.angle,0,accuracy:0.000001); XCTAssertNotNil(snap.latch)
        XCTAssertEqual(try JSONDecoder().decode(LayoutLighting.self,from:JSONEncoder().encode(rotated)),rotated)
    }
    func testSpotSpacingScalesCustomSelectionWithoutRegeneratingPattern() {
        var lighting = LayoutLighting(); lighting.count = 4
        lighting.positions = [.init(x:1000,y:500),.init(x:1700,y:1100),.init(x:2000,y:1000),.init(x:4000,y:3000)]
        let selected:Set<Int> = [0,1,2]
        let scaled = LayoutPlanning.scaledLighting(lighting,selected:selected,factor:1.5)
        XCTAssertEqual(scaled.positions[3],lighting.positions[3])
        XCTAssertEqual((scaled.positions[1]-scaled.positions[0]).length,(lighting.positions[1]-lighting.positions[0]).length*1.5,accuracy:0.001)
        let before = selected.reduce(LayoutPoint.zero) { $0+lighting.positions[$1] }
        let after = selected.reduce(LayoutPoint.zero) { $0+scaled.positions[$1] }
        XCTAssertEqual(before.x,after.x,accuracy:0.001); XCTAssertEqual(before.y,after.y,accuracy:0.001)
        let back = LayoutPlanning.scaledLighting(scaled,selected:selected,factor:1/1.5)
        for i in selected { XCTAssertEqual((back.positions[i]-lighting.positions[i]).length,0,accuracy:0.001) }
        XCTAssertEqual(LayoutPlanning.scaledLighting(lighting,selected:selected,factor:.nan),lighting)
    }
    func testCenterAndManualSpotsRespectGeometryAndDefaultDiameter() throws {
        var s = surface(width:6000,height:4000)
        s.kind = .ceiling
        let first = try LayoutPlanning.addingSpot(to:nil,at:.init(x:1000,y:1000),surface:s)
        XCTAssertEqual(first.count,1); XCTAssertEqual(first.diameter,68)
        let centered = try LayoutPlanning.centeredLighting(first,selected:[0],surface:s)
        XCTAssertEqual(centered.positions,[s.bounds.center])
        XCTAssertThrowsError(try LayoutPlanning.addingSpot(to:first,at:first.positions[0],surface:s))
        XCTAssertThrowsError(try LayoutPlanning.addingSpot(to:first,at:.init(x:-100,y:0),surface:s))
    }
    func testWallRowsPersistTypesAndSeparateHeights() throws {
        let s = surface(width:5000,height:3000)
        let sockets = try LayoutPlanning.addingWallRow(to:nil,count:3,height:350,kind:.socket,surface:s)
        let combined = try LayoutPlanning.addingWallRow(to:sockets,count:2,height:1800,kind:.light,surface:s)
        XCTAssertEqual(combined.positions.map(\.y),[350,350,350,1800,1800])
        XCTAssertEqual(combined.kinds,[.socket,.socket,.socket,.light,.light])
        XCTAssertEqual(combined.positions[1].x-combined.positions[0].x,combined.positions[2].x-combined.positions[1].x,accuracy:0.001)
        let centered = try LayoutPlanning.centeredLighting(combined,selected:[0,1],surface:s)
        XCTAssertEqual(centered.positions.map(\.y),combined.positions.map(\.y))
        XCTAssertThrowsError(try LayoutPlanning.addingWallRow(to:combined,count:2,height:4000,kind:.light,surface:s))
        let old = Data("{\"count\":1,\"spread\":0.75,\"diameter\":75,\"positions\":[{\"x\":100,\"y\":200}]}".utf8)
        let decoded = try JSONDecoder().decode(LayoutLighting.self,from:old)
        XCTAssertEqual(decoded.kind(at:0),.light); XCTAssertEqual(decoded.diameter,75)
    }
    func testWallFramingAlwaysVerticalAndBoardHeightLockDependsOnOrientation() throws {
        let s = surface(.slope,width:4000,height:2000,second:3000)
        var layer = LayoutLayer(); layer.furring = .init(); layer.referenceEdge = 2
        for orientation in LayoutOrientation.allCases {
            layer.orientation = orientation
            for parallel in [true,false] {
                layer.furring?.parallelToBoards = parallel
                let result = try SheetLayoutEngine.calculate(surface:s,layer:layer)
                XCTAssertEqual(result.frame.angle,0)
                for line in result.furring.lines { XCTAssertEqual(line.start.x,line.end.x,accuracy:0.001) }
            }
        }
        layer.orientation = .vertical; layer.sheetLength = 3000; layer.offset = .init(x:130,y:300)
        XCTAssertEqual(layer.forSurface(s).offset,.init(x:130,y:0))
        layer.sheetLength = 2500
        XCTAssertEqual(layer.forSurface(s).offset.y,300)
        layer.sheetLength = 3000; layer.orientation = .horizontal
        XCTAssertEqual(layer.forSurface(s).offset.y,300)
        XCTAssertTrue(LayoutPreset.available(for:.wall).contains(.freeform))
    }
    func testLightingGroupTranslationPreservesIntervalsAndOtherSpots() throws {
        let s = surface(width:6000,height:4000)
        let lighting = try LayoutPlanning.lighting(.init(),surface:s)
        let delta = LayoutPoint(x:100,y:200)
        let moved = LayoutPlanning.translatedLighting(lighting,indices:Set(lighting.positions.indices),delta:delta)
        XCTAssertTrue(LayoutPlanning.lightingFits(moved,surface:s))
        for i in lighting.positions.indices { XCTAssertEqual(moved.positions[i],lighting.positions[i]+delta) }
        let pair = LayoutPlanning.translatedLighting(lighting,indices:[0,1],delta:delta)
        XCTAssertEqual(pair.positions[2],lighting.positions[2])
        XCTAssertEqual((pair.positions[1]-pair.positions[0]).length,(lighting.positions[1]-lighting.positions[0]).length,accuracy:0.001)
        XCTAssertEqual(try JSONDecoder().decode(LayoutLighting.self,from:JSONEncoder().encode(moved)),moved)
    }
    func testLightingAlignmentUsesReferenceAndDistributionKeepsExtremes() throws {
        let s = surface(width:6000,height:4000)
        var lighting = LayoutLighting(); lighting.count = 4
        lighting.positions = [.init(x:500,y:500),.init(x:1700,y:900),.init(x:4000,y:1400),.init(x:5000,y:3000)]
        let horizontal = try LayoutPlanning.arrangedLighting(lighting,selected:[0,1,2],reference:1,action:.horizontal,surface:s)
        XCTAssertEqual(horizontal.positions.map(\.y),[900,900,900,3000])
        let vertical = try LayoutPlanning.arrangedLighting(lighting,selected:[0,1,2],reference:2,action:.vertical,surface:s)
        XCTAssertEqual(vertical.positions.map(\.x),[4000,4000,4000,5000])
        let distributed = try LayoutPlanning.arrangedLighting(lighting,selected:[0,1,2],reference:nil,action:.distributeX,surface:s)
        XCTAssertEqual(distributed.positions.map(\.x),[500,2250,4000,5000])
        XCTAssertEqual(distributed.positions.map(\.y),lighting.positions.map(\.y))
        let dy = try LayoutPlanning.arrangedLighting(lighting,selected:[0,1,2,3],reference:nil,action:.distributeY,surface:s)
        XCTAssertEqual(dy.positions[1].y,500+2500.0/3,accuracy:0.001)
        XCTAssertEqual(dy.positions[3],lighting.positions[3])
        lighting.positions[1].x = 500
        XCTAssertThrowsError(try LayoutPlanning.arrangedLighting(lighting,selected:[0,1],reference:0,action:.horizontal,surface:s))
        var opening = s
        opening.openings = [.init(kind:.stairwell,contour:LayoutBounds(min:.init(x:3900,y:400),max:.init(x:4100,y:600)).polygon)]
        XCTAssertThrowsError(try LayoutPlanning.arrangedLighting(lighting,selected:[0,2],reference:0,action:.horizontal,surface:opening))
    }
    func testLightingSnapOnlyUsesUnselectedSpotsWithinTolerance() {
        var light = LayoutLighting(); light.count = 3
        light.positions = [.init(x:500,y:500),.init(x:1500,y:1500),.init(x:2500,y:2500)]
        let snap = LayoutPlanning.snappedLightingDelta(light,selected:[0],anchor:0,delta:.init(x:990,y:995),tolerance:20)
        XCTAssertEqual(snap.delta,.init(x:1000,y:1000))
        let excluded = LayoutPlanning.snappedLightingDelta(light,selected:[0,1],anchor:0,delta:.init(x:990,y:995),tolerance:20)
        XCTAssertEqual(excluded.delta,.init(x:990,y:995)); XCTAssertTrue(excluded.guides.isEmpty)
    }
    @MainActor func testLightingDragCommitsOnceSupportsUndoAndRejectsOutside() async throws {
        let key = "spot-drag-\(UUID())", defaults = UserDefaults(suiteName:key)!
        defer { defaults.removePersistentDomain(forName:key) }
        let model = LayoutEditorModel(defaults:defaults)
        var original = LayoutDocument(surface:surface(width:6000,height:4000))
        original.lighting = try LayoutPlanning.lighting(.init(),surface:original.surface)
        model.apply(original)
        for _ in 0..<200 where model.isCalculating { try await Task.sleep(nanoseconds:5_000_000) }
        let cached = model.result
        var copy = original; copy.lighting = LayoutPlanning.translatedLighting(try XCTUnwrap(original.lighting),indices:[0,1],delta:.init(x:100,y:100))
        model.preview(copy)
        XCTAssertEqual(model.result,cached); XCTAssertFalse(model.isCalculating)
        model.finishGesture(from:original); XCTAssertEqual(model.document,copy)
        model.undo(); XCTAssertEqual(model.document,original)
        model.redo(); XCTAssertEqual(model.document,copy)
        var invalid = copy; invalid.lighting?.positions[0] = .init(x:-100,y:500)
        model.preview(invalid); model.finishGesture(from:copy)
        XCTAssertEqual(model.document,copy); XCTAssertNotNil(model.saveError)
        model.saveCurrentAndClose()
        XCTAssertEqual(LayoutEditorModel(defaults:defaults).savedDocuments.first?.document,copy)
    }
    func testFreeVertexDragChangesAreaWithoutTranslatingOtherVertices() throws {
        var original = surface(width:4000,height:3000)
        original.contourIntent = .init(sketch:original.contour)
        // Reproduce an old saved gesture: it must not become an invisible lock.
        original.contourIntent?.userVertexPositions[0] = original.contour[0]
        var points = original.contour; points[2] = .init(x:5000,y:4000)
        let moved = try original.movingVertices(to:points)
        for i in points.indices {
            XCTAssertEqual(moved.contour[i].x,points[i].x,accuracy:0.001)
            XCTAssertEqual(moved.contour[i].y,points[i].y,accuracy:0.001)
        }
        XCTAssertEqual(abs(LayoutGeometry.area(moved.contour)),15_500_000,accuracy:0.01)
        XCTAssertTrue(moved.editableIntent.userVertexPositions.allSatisfy{$0 == nil})
        var second = moved.contour; second[2] = .init(x:3000,y:2000)
        let shrunk = try moved.movingVertices(to:second)
        XCTAssertEqual(abs(LayoutGeometry.area(shrunk.contour)),8_500_000,accuracy:0.01)
        let reopened = try JSONDecoder().decode(Surface2D.self,from:JSONEncoder().encode(shrunk))
        XCTAssertEqual(reopened,shrunk)
    }
    func testVertexDragHonoursVisibleLocksButNotUnlockedMeasurements() throws {
        var original = surface(width:4000,height:3000)
        original.contourIntent = .init(sketch:original.contour)
        original.contourIntent?.userMeasuredLengths[0] = 4000
        original.contourIntent?.lockedLengthIndices = [0]
        original.contourIntent?.userAnglesDegrees[0] = 90
        original.contourIntent?.userMeasuredLengths[1] = 3000 // measured, not locked
        var points = original.contour; points[2] = .init(x:5000,y:4000)
        let moved = try original.movingVertices(to:points)
        XCTAssertEqual((moved.contour[1]-moved.contour[0]).length,4000,accuracy:0.5)
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:0,in:moved.contour),90,accuracy:0.25)
        XCTAssertEqual(moved.contour[2].x,5000,accuracy:0.5)
        XCTAssertEqual(moved.contour[2].y,4000,accuracy:0.5)
        XCTAssertEqual(moved.editableIntent.userMeasuredLengths[1],3000)
        XCTAssertTrue(moved.dimensionCorrections.contains{$0.edgeIndex == 1})
        XCTAssertGreaterThan(abs(LayoutGeometry.area(moved.contour)),12_000_000)
        points[2] = .init(x:-1000,y:-1000)
        XCTAssertThrowsError(try original.movingVertices(to:points))
    }
    @MainActor func testEditorVertexGestureChangesAreaAndUndoRestoresIt() throws {
        let key = "vertex-drag-\(UUID())", defaults = UserDefaults(suiteName:key)!
        defer { defaults.removePersistentDomain(forName:key) }
        let model = LayoutEditorModel(defaults:defaults)
        let original = LayoutDocument(surface:surface(width:4000,height:3000))
        model.apply(original)
        var copy = original; copy.surface.contour[2] = .init(x:5000,y:4000)
        model.preview(copy); model.finishGesture(from:original)
        XCTAssertEqual(abs(LayoutGeometry.area(try XCTUnwrap(model.document).surface.contour)),15_500_000,accuracy:0.01)
        model.undo(); XCTAssertEqual(model.document,original)
        model.redo()
        model.saveCurrentAndClose()
        let loaded = LayoutEditorModel(defaults:defaults)
        XCTAssertEqual(abs(LayoutGeometry.area(try XCTUnwrap(loaded.savedDocuments.first).document.surface.contour)),15_500_000,accuracy:0.01)
    }
    func testExportKeepsTrueRectangleDimensionsIncludingRotatedPlans() throws {
        var doc = LayoutDocument(surface:surface(width:4000,height:2500))
        let frame = LayoutGridFrame(origin:.init(x:500,y:200),angle:0.4)
        doc.surface.contour = doc.surface.contour.map(frame.world)
        let configuration = LayoutWorkGeometry.ceiling(doc)
        XCTAssertEqual(configuration.dimensionsSpecified,true)
        XCTAssertEqual(configuration.length,4,accuracy:0.0001)
        XCTAssertEqual(configuration.width,2.5,accuracy:0.0001)
        doc.surface.openings = [.init(kind:.stairwell,contour:LayoutBounds(min:.init(x:1500,y:1500),max:.init(x:1700,y:1700)).polygon)]
        XCTAssertNil(LayoutWorkGeometry.rectangle(doc))
        XCTAssertEqual(LayoutWorkGeometry.ceiling(doc).dimensionsSpecified,false)
    }
    func testLightingDetectsOpeningMovedUnderExistingSpot() throws {
        var s = surface(width:6000,height:4000)
        let lighting = try LayoutPlanning.lighting(.init(),surface:s)
        XCTAssertTrue(LayoutPlanning.lightingFits(lighting,surface:s))
        let p = try XCTUnwrap(lighting.positions.first)
        s.openings = [.init(kind:.stairwell,contour:LayoutBounds(min:p - .init(x:100,y:100),max:p + .init(x:100,y:100)).polygon)]
        XCTAssertFalse(LayoutPlanning.lightingFits(lighting,surface:s))
    }
    func testLockedLengthsRejectContradictionAndPreserveUnlockedMeasurements() throws {
        var intent = measuredRectangle()
        intent.lockedLengthIndices = [0]
        intent.userMeasuredLengths[0] = 4100
        let result = try LayoutPolygonSolver.resolve(intent)
        XCTAssertEqual((result.contour[1]-result.contour[0]).length,4100,accuracy:0.5)
        XCTAssertEqual(intent.userMeasuredLengths[2],4000)
        intent.lockedLengthIndices = [0,2]
        XCTAssertThrowsError(try LayoutPolygonSolver.resolve(intent))
    }
    func testVertexTopologyRemapsUnaffectedLocks() throws {
        var s = surface(width:4000,height:3000)
        s.contourIntent = measuredRectangle(); s.contourIntent?.lockedLengthIndices = [0,1,2,3]
        let added = try s.changingVertex(insertAfter:0,point:.init(x:2000,y:0))
        XCTAssertEqual(added.contour.count,5)
        XCTAssertNil(added.contourIntent?.userMeasuredLengths[0])
        XCTAssertNil(added.contourIntent?.userMeasuredLengths[1])
        XCTAssertEqual(added.contourIntent?.userMeasuredLengths[2],3000)
        XCTAssertEqual(added.contourIntent?.lockedLengthIndices,[2,3,4])
        XCTAssertEqual(added.previousContourIntents.count,1)
        let removed = try added.changingVertex(remove:1)
        XCTAssertEqual(removed.contour.count,4)
        XCTAssertEqual(abs(LayoutGeometry.area(removed.contour)),12_000_000,accuracy:1)
    }
    func testOpeningWallDimensionsFollowPerpendicularFeet() {
        let s = surface(width:5000,height:4000)
        let p = LayoutPoint(x:950,y:1120)
        let values = LayoutPlanning.wallDimensions(points:[p],surface:s).map(\.distance).sorted()
        XCTAssertEqual(values,[950,1120,2880,4050])
        let frame = LayoutGridFrame(origin:.init(x:100,y:200),angle:0.3)
        var rotated = s; rotated.contour = s.contour.map(frame.world)
        let rotatedValues = LayoutPlanning.wallDimensions(points:[frame.world(p)],surface:rotated).map(\.distance).sorted()
        for (a,b) in zip(values,rotatedValues) { XCTAssertEqual(a,b,accuracy:0.001) }
    }
    func testSpacingCompatibilityAndBidirectionalAlignment() {
        var layer = LayoutLayer(); layer.orientation = .horizontal; layer.sheetLength = 2400; layer.furring = .init()
        XCTAssertEqual(LayoutPlanning.compatibleSpacings(layer),[400,600])
        layer.sheetLength = 2500
        XCTAssertEqual(LayoutPlanning.compatibleSpacings(layer),[500])
        layer.furring?.spacing = 500; layer.offset = .init(x:160,y:200)
        XCTAssertFalse(LayoutPlanning.aligned(layer))
        layer = LayoutPlanning.alignFurring(to:layer)
        XCTAssertTrue(LayoutPlanning.aligned(layer))
        layer.furring?.offset = 75; layer = LayoutPlanning.alignBoards(to:layer)
        XCTAssertTrue(LayoutPlanning.aligned(layer)); XCTAssertEqual(layer.offset.x,75)
        layer.furring?.parallelToBoards = true
        XCTAssertEqual(LayoutPlanning.compatibleSpacings(layer),[400,600])
    }
    func testOptimizationNeverWorsensCountsOrFurringMetres() throws {
        let s = surface(width:4800,height:2400)
        var layer = LayoutLayer(); layer.sheetLength = 2400; layer.orientation = .horizontal
        layer.offset = .init(x:123,y:157); layer.furring = .init()
        let original = try SheetLayoutEngine.calculate(surface:s,layer:layer)
        let boards = try LayoutPlanning.optimize(surface:s,layer:layer,furring:false)
        let boardResult = try SheetLayoutEngine.calculate(surface:s,layer:boards)
        XCTAssertLessThanOrEqual(boardResult.sheets.count,original.sheets.count)
        XCTAssertEqual(boardResult.sheets.count,4)
        XCTAssertTrue(LayoutPlanning.aligned(boards))
        let frame = try LayoutPlanning.optimize(surface:s,layer:boards,furring:true)
        let frameResult = try SheetLayoutEngine.calculate(surface:s,layer:frame)
        XCTAssertLessThanOrEqual(frameResult.furring.lines.reduce(0){$0+($1.end-$1.start).length},boardResult.furring.lines.reduce(0){$0+($1.end-$1.start).length}+0.001)
        XCTAssertTrue(LayoutPlanning.aligned(frame))
    }
    func testLightingCountSpacingAndOpenings() throws {
        var s = surface(width:6000,height:4000)
        var light = LayoutLighting(); light.count = 6
        let a = try LayoutPlanning.lighting(light,surface:s)
        XCTAssertEqual(a.positions.count,6)
        light.spread = 0.9
        let b = try LayoutPlanning.lighting(light,surface:s)
        XCTAssertGreaterThan(LayoutBounds(points:b.positions).width,LayoutBounds(points:a.positions).width)
        s.openings = [.init(kind:.stairwell,contour:LayoutBounds(min:.init(x:2200,y:1500),max:.init(x:3800,y:2500)).polygon)]
        let cutout = try LayoutPlanning.lighting(light,surface:s)
        XCTAssertEqual(cutout.positions.count,6)
        for p in cutout.positions { XCTAssertTrue(LayoutGeometry.contains(p,in:s.contour)); XCTAssertFalse(LayoutGeometry.contains(p,in:s.openings[0].contour)) }
        light.count = 65
        XCTAssertThrowsError(try LayoutPlanning.lighting(light,surface:s))
    }
    @MainActor func testDraggingDoesNotRecalculateAndCommitIsUndoable() async throws {
        let key = "drag-test-\(UUID())", defaults = UserDefaults(suiteName:key)!
        defer { defaults.removePersistentDomain(forName:key) }
        let model = LayoutEditorModel(defaults:defaults)
        let original = LayoutDocument(surface:surface())
        model.apply(original)
        for _ in 0..<200 where model.isCalculating { try await Task.sleep(nanoseconds:5_000_000) }
        let result = try XCTUnwrap(model.result)
        var copy = original; copy.layers[0].offset.x = 400
        model.preview(copy)
        XCTAssertFalse(model.isCalculating); XCTAssertEqual(model.result,result)
        model.finishGesture(from:original)
        XCTAssertTrue(model.canUndo)
        model.undo(); XCTAssertEqual(model.document,original)
    }
    @MainActor func testLinkedProjectExportRoundTripAndIndependentDuplication() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("layout-export-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let store = ProjectStore(fileURL:url)
        let id = try store.createProject(name:"Test",client:"",address:"",notes:"")
        var doc = LayoutDocument(surface:surface())
        doc.surface.kind = .ceiling
        try store.createLayoutWork(projectID:id,name:"Salon - Plafond",type:.ceilingOnFurring,payload:.ceiling(LayoutWorkGeometry.ceiling(doc)),document:doc)
        let loaded = ProjectStore(fileURL:url)
        let work = try XCTUnwrap(loaded.project(id:id)?.works.first)
        XCTAssertEqual(work.layoutDocument,doc)
        let duplicateID = try loaded.duplicateWork(projectID:id,workID:work.id)
        let copied = try XCTUnwrap(loaded.project(id:id)?.works.first{$0.id == duplicateID}?.layoutDocument)
        XCTAssertEqual(copied.surface.contour,doc.surface.contour)
        XCTAssertNotEqual(copied.surface.id,doc.surface.id)
        XCTAssertNotEqual(copied.layers[0].id,doc.layers[0].id)
        var changed = doc; changed.layers[0].offset.x = 100
        try loaded.updateLinkedLayout(projectID:id,workID:work.id,document:changed)
        XCTAssertEqual(loaded.project(id:id)?.works.first{$0.id == work.id}?.layoutNeedsRecalculation,true)
        XCTAssertEqual(loaded.project(id:id)?.works.first{$0.id == duplicateID}?.layoutDocument,copied)
    }
    func testDrawingScalePreservesShapeAnglesAndPins() throws {
        var s = surface(width:2000,height:1500)
        s.contourIntent = .init(sketch:s.contour)
        s.contourIntent?.userAnglesDegrees[0] = 90
        s.contourIntent?.userVertexPositions[1] = s.contour[1]
        let scaled = try s.scaledDrawing(by:4)
        XCTAssertEqual(scaled.bounds.width,8000,accuracy:0.001)
        XCTAssertEqual(scaled.bounds.height,6000,accuracy:0.001)
        XCTAssertEqual(scaled.contourIntent?.userVertexPositions[1],scaled.contour[1])
        XCTAssertEqual(scaled.contourIntent?.userAnglesDegrees[0],90)
        var resolved = scaled
        try resolved.resolve(scaled.editableIntent)
        XCTAssertEqual(resolved.bounds.width,8000,accuracy:0.01)
        s.contourIntent?.userMeasuredLengths[0] = 2000
        XCTAssertFalse(s.canScaleDrawing)
        XCTAssertThrowsError(try s.scaledDrawing(by:2))
    }

    func testRotatedReferenceWallPreservesCutDimensionsAndHitTesting() throws {
        let angle = 0.43
        let frame = LayoutGridFrame(origin:.init(x:725,y:-823),angle:angle)
        var s = surface(width:4800,height:2400)
        s.kind = .ceiling
        s.contour = s.contour.map(frame.world)
        var layer = LayoutLayer()
        layer.referenceEdge = 0; layer.orientation = .horizontal; layer.sheetLength = 2400
        let result = try check(s,layer,area:11_520_000,count:4)
        XCTAssertTrue(result.sheets.allSatisfy(\.isFull))
        XCTAssertEqual(result.frame.angle,angle,accuracy:1e-10)
        for sheet in result.sheets {
            XCTAssertEqual(sheet.width,2400)
            XCTAssertEqual(sheet.height,1200)
            for piece in sheet.pieces {
                let world = result.frame.world(piece.labelPoint)
                XCTAssertTrue(LayoutGeometry.contains(world,in:s.contour))
                XCTAssertTrue(piece.contains(result.frame.local(world)))
            }
        }
        let delta = result.frame.vector(frame.world(.init(x:200,y:0))-frame.origin)
        XCTAssertEqual(delta.x,200,accuracy:0.001)
        XCTAssertEqual(delta.y,0,accuracy:0.001)
    }

    func testFurringOrientationSpacingAndWallReferences() throws {
        var s = surface(width:2400,height:1200)
        s.kind = .ceiling
        var layer = LayoutLayer(); layer.orientation = .horizontal
        layer.furring = .init(parallelToBoards:false,spacing:600,offset:200)
        let r = try SheetLayoutEngine.calculate(surface:s,layer:layer)
        XCTAssertEqual(r.furring.lines.count,4)
        XCTAssertTrue(r.furring.lines.allSatisfy{abs($0.start.x-$0.end.x) < 0.001})
        XCTAssertEqual(r.furring.contacts.filter{$0.edgeIndex == 0}.map(\.distance).sorted(),[200,800,1400,2000])
        layer.furring?.parallelToBoards = true
        layer.furring?.spacing = 400
        let parallel = try SheetLayoutEngine.calculate(surface:s,layer:layer)
        XCTAssertEqual(parallel.furring.lines.count,3)
        XCTAssertTrue(parallel.furring.lines.allSatisfy{abs($0.start.y-$0.end.y) < 0.001})
        layer.orientation = .vertical
        let turned = try SheetLayoutEngine.calculate(surface:s,layer:layer)
        XCTAssertTrue(turned.furring.lines.allSatisfy{abs($0.start.x-$0.end.x) < 0.001})
    }

    func testFurringClipsHolesAndConcaveContours() throws {
        var s = surface(width:2400,height:2400)
        s.openings = [.init(kind:.roofWindow,contour:LayoutBounds(min:.init(x:100,y:700),max:.init(x:400,y:1400)).polygon)]
        var layer = LayoutLayer(); layer.orientation = .horizontal
        layer.furring = .init(parallelToBoards:false,spacing:600,offset:200)
        let result = try SheetLayoutEngine.calculate(surface:s,layer:layer)
        let first = result.furring.lines.filter{abs($0.start.x-200) < 0.001}
        XCTAssertEqual(first.count,2)
        XCTAssertEqual(first.reduce(0){$0+($1.end-$1.start).length},1700,accuracy:0.001)
        s = surface(.lShape,width:4000,height:3000,second:1000)
        let concave = try SheetLayoutEngine.calculate(surface:s,layer:layer)
        for line in concave.furring.lines {
            for fraction in [0.25,0.5,0.75] {
                let point = line.start+(line.end-line.start)*fraction
                // A member at x=2000 lies exactly on the return of this L.
                // Perimeter members are intentional, not outside fragments.
                let onBoundary = LayoutGeometry.edges(s.contour).contains { LayoutGeometry.distance(point,to:$0.a,$0.b) < 0.001 }
                XCTAssertTrue(LayoutGeometry.contains(point,in:s.contour) || onBoundary)
            }
        }
        layer.furring?.spacing = 0
        XCTAssertThrowsError(try SheetLayoutEngine.calculate(surface:s,layer:layer))
    }

    func testLayerBackwardCompatibilityAndNewSettingsRoundTrip() throws {
        let old = """
        {"id":"E17C951D-4068-4C60-9047-D3106D845DA8","sheetWidth":1200,"sheetLength":2400,"orientation":"Horizontal","offset":{"x":0,"y":0}}
        """
        var layer = try JSONDecoder().decode(LayoutLayer.self,from:Data(old.utf8))
        XCTAssertNil(layer.referenceEdge); XCTAssertNil(layer.furring)
        layer.referenceEdge = 2; layer.furring = .init(parallelToBoards:true,spacing:400,offset:120)
        XCTAssertEqual(layer,try JSONDecoder().decode(LayoutLayer.self,from:JSONEncoder().encode(layer)))
    }
    func testFurringOnPerimeterAndRotatedWallDistances() throws {
        var s = surface(width:2400,height:1200)
        s.kind = .ceiling
        let frame = LayoutGridFrame(origin:.init(x:300,y:200),angle:0.7)
        s.contour = s.contour.map(frame.world)
        var layer = LayoutLayer(); layer.referenceEdge = 0; layer.orientation = .horizontal
        layer.furring = .init(parallelToBoards:false,spacing:600,offset:0)
        let result = try SheetLayoutEngine.calculate(surface:s,layer:layer)
        XCTAssertEqual(result.furring.lines.count,5)
        let contacts = result.furring.contacts.filter{$0.edgeIndex == 0}.sorted{$0.distance < $1.distance}
        XCTAssertEqual(contacts.count,5)
        for (i,contact) in contacts.enumerated() { XCTAssertEqual(contact.distance,Double(i)*600,accuracy:0.001) }
    }
    private func surface(_ preset: LayoutPreset = .rectangle, width: Double = 3600, height: Double = 2500, second: Double = 1800) -> Surface2D {
        .init(name: "Test", kind: .wall, contour: preset.contour(width: width, height: height, secondaryHeight: second))
    }
    private func check(_ s: Surface2D, _ layer: LayoutLayer = .init(), area: Double, count: Int? = nil) throws -> SheetLayoutResult {
        let r = try SheetLayoutEngine.calculate(surface: s, layer: layer)
        XCTAssertEqual(r.netArea, area, accuracy: 0.1)
        if let count { XCTAssertEqual(r.sheets.count, count) }
        for sheet in r.sheets {
            XCTAssertLessThanOrEqual(sheet.area, sheet.width * sheet.height + 0.1)
            for p in sheet.pieces {
                XCTAssertGreaterThan(p.area, 0)
                XCTAssertNoThrow(try LayoutGeometry.validate(p.contour))
                for hole in p.holes { XCTAssertNoThrow(try LayoutGeometry.validate(hole)) }
            }
        }
        return r
    }
    func testExactRectangleAndPartialEnd() throws {
        let exact = try check(surface(), area: 9_000_000, count: 3)
        XCTAssertTrue(exact.sheets.allSatisfy(\.isFull))
        XCTAssertEqual(exact.joints.count, 2)
        let partial = try check(surface(width: 3700), area: 9_250_000, count: 4)
        XCTAssertEqual(partial.sheets.last!.pieces[0].bounds.width, 100, accuracy: 0.001)
    }
    func testOffsetsOrientationAndDeterminism() throws {
        // Ceilings allow both axes; single-height walls deliberately stay on the floor.
        var s = surface(); s.kind = .ceiling
        var layer = LayoutLayer(); layer.offset = .init(x: -200, y: 350)
        let a = try check(s, layer, area: 9_000_000, count: 8)
        XCTAssertEqual(a, try SheetLayoutEngine.calculate(surface: s, layer: layer))
        layer.offset.x += 1200; layer.offset.y += 2500
        XCTAssertEqual(a, try SheetLayoutEngine.calculate(surface: s, layer: layer))
        layer.orientation = .horizontal; layer.offset = .zero
        _ = try check(s, layer, area: 9_000_000, count: 6)
    }
    func testWindowInsideSheetAndDoorAtEdge() throws {
        var s = surface(width: 1200)
        s.openings = [.init(kind: .window, contour: LayoutBounds(min: .init(x: 200, y: 500), max: .init(x: 900, y: 1500)).polygon)]
        let r = try check(s, area: 2_300_000, count: 1)
        XCTAssertEqual(r.sheets[0].pieces[0].holes.count, 1)
        s.openings[0].contour = LayoutBounds(min: .init(x: 200, y: 0), max: .init(x: 900, y: 2000)).polygon
        let door = try check(s, area: 1_600_000, count: 1)
        XCTAssertEqual(door.sheets[0].pieces[0].holes.count, 0)
        XCTAssertEqual(door.sheets[0].pieces[0].contour.count, 8)
    }
    func testOverlappingOpeningsAndOpeningCrossingGrid() throws {
        var s = surface()
        s.openings = [
            .init(kind: .window, contour: LayoutBounds(min: .init(x: 900, y: 500), max: .init(x: 1500, y: 1500)).polygon),
            .init(kind: .window, contour: LayoutBounds(min: .init(x: 1200, y: 500), max: .init(x: 1800, y: 1500)).polygon)
        ]
        _ = try check(s, area: 8_100_000, count: 3)
    }
    func testDiagonalSlopeAndGableMeasurements() throws {
        let r = try check(surface(.slope, second: 1600), area: 7_380_000, count: 3)
        let first = r.sheets[0].pieces[0].contour
        XCTAssertTrue(first.contains { abs($0.x - 1200) < 0.001 && abs($0.y - 2200) < 0.001 })
        _ = try check(surface(.gable, height: 1800, second: 2500), area: 7_740_000, count: 3)
    }
    func testMeasuredContourClosesAndRecordsDistributedCorrections() throws {
        let sketch = [LayoutPoint.zero, .init(x: 4000, y: 0), .init(x: 3980, y: 3000), .init(x: 0, y: 2970)]
        let requested = [4000.0, 3000, 3990, 2960]
        let (closed, corrections) = try LayoutGeometry.closedMeasuredContour(sketch: sketch, lengths: requested)
        XCTAssertNoThrow(try LayoutGeometry.validate(closed))
        XCTAssertEqual(closed.count, 4)
        XCTAssertFalse(corrections.isEmpty)
        let vectors = LayoutGeometry.edges(closed).map { $0.b - $0.a }
        let closure = vectors.reduce(LayoutPoint.zero, +)
        XCTAssertEqual(closure.length, 0, accuracy: 0.001)
        XCTAssertEqual(corrections.map(\.edgeIndex), corrections.map(\.edgeIndex).sorted())
    }

    func testWallPresetsMirrorSlopeAndLWithoutChangingArea() throws {
        for preset in [LayoutPreset.slope, .lShape] {
            let normal = preset.contour(length: 4000, height: 2400, secondaryHeight: 3000)
            let mirrored = preset.contour(length: 4000, height: 2400, secondaryHeight: 3000, mirrored: true)
            XCTAssertEqual(abs(LayoutGeometry.area(normal)), abs(LayoutGeometry.area(mirrored)), accuracy: 0.001)
            XCTAssertNoThrow(try LayoutGeometry.validate(normal))
            XCTAssertNoThrow(try LayoutGeometry.validate(mirrored))
        }
        XCTAssertFalse(LayoutPreset.available(for: .wall).contains(.gable))
        XCTAssertEqual(LayoutPreset.available(for: .ceiling), [.rectangle, .freeform])
    }
    func testSlopeMirrorMovesMaximumHeightFromBCToDA() throws {
        let normal = LayoutPreset.slope.contour(length: 4000, height: 2500, secondaryHeight: 4000)
        let mirrored = LayoutPreset.slope.contour(length: 4000, height: 2500, secondaryHeight: 4000, mirrored: true)
        XCTAssertEqual((normal[2] - normal[1]).length, 4000, accuracy: 0.001)
        XCTAssertEqual((normal[0] - normal[3]).length, 2500, accuracy: 0.001)
        XCTAssertEqual((mirrored[2] - mirrored[1]).length, 2500, accuracy: 0.001)
        XCTAssertEqual((mirrored[0] - mirrored[3]).length, 4000, accuracy: 0.001)
    }

    func testLWallUsesRequestedArchitecturalSides() throws {
        let contour = LayoutPreset.lShape.contour(length: 5000, height: 2400, secondaryHeight: 3100,
                                                   lowerLength: 1800)
        XCTAssertEqual((contour[1] - contour[0]).length, 1800, accuracy: 0.001) // BA
        XCTAssertEqual((contour[3] - contour[2]).length, 3200, accuracy: 0.001) // DC
        XCTAssertEqual((contour[4] - contour[3]).length, 3100, accuracy: 0.001) // DE
        XCTAssertEqual((contour[5] - contour[4]).length, 5000, accuracy: 0.001) // EF
        XCTAssertEqual((contour[0] - contour[5]).length, 2400, accuracy: 0.001) // FA
        XCTAssertNoThrow(try LayoutGeometry.validate(contour))
    }
    func testConcaveCeilingWithStairwell() throws {
        var s = surface(.lShape, width: 4000, height: 4000); s.kind = .ceiling
        s.openings = [.init(kind: .stairwell, contour: LayoutBounds(min: .init(x: 500, y: 500), max: .init(x: 1500, y: 1500)).polygon)]
        _ = try check(s, area: 11_000_000)
    }
    func testDisconnectedPiecesAndFullyEmptyCell() throws {
        var s = surface(width: 1200)
        s.openings = [.init(kind: .passage, contour: LayoutBounds(min: .init(x: 400, y: 0), max: .init(x: 800, y: 2500)).polygon)]
        let r = try check(s, area: 2_000_000, count: 1)
        XCTAssertEqual(r.sheets[0].pieces.count, 2)
        s.openings[0].contour = s.contour
        _ = try check(s, area: 0, count: 0)
    }
    func testReversedWindingAndIrregularPolygon() throws {
        var s = surface(); s.kind = .ceiling
        s.contour = [.zero, .init(x: 4000, y: 0), .init(x: 3600, y: 1800), .init(x: 2000, y: 2700), .init(x: 0, y: 2500)]
        let area = abs(LayoutGeometry.area(s.contour))
        _ = try check(s, area: area)
        s.contour.reverse()
        _ = try check(s, area: area)
    }
    func testRejectsInvalidGeometryAndExcessiveWork() throws {
        var s = surface(); s.contour.swapAt(1, 2)
        XCTAssertThrowsError(try SheetLayoutEngine.calculate(surface: s, layer: .init()))
        var layer = LayoutLayer(); layer.sheetWidth = 0
        XCTAssertThrowsError(try SheetLayoutEngine.calculate(surface: surface(), layer: layer))
        layer.sheetWidth = 1; layer.sheetLength = 1
        XCTAssertThrowsError(try SheetLayoutEngine.calculate(surface: surface(), layer: layer))
        layer.offset.x = .infinity
        XCTAssertThrowsError(try SheetLayoutEngine.calculate(surface: surface(), layer: layer))
    }
    func testSmallRealCutsAndManyOffsetsConserveArea() throws {
        _ = try check(surface(width: 3600.1), area: 9_000_250, count: 4)
        let s = surface(.lShape, width: 3800, height: 3100)
        for step in 0..<20 {
            var layer = LayoutLayer(); layer.offset = .init(x: Double(step) * 67.3, y: Double(step) * -41.7)
            _ = try check(s, layer, area: 8_835_000)
        }
    }
    func testScanAdapterPreservesSlopeLengthsAndDocumentRoundtrip() throws {
        let frame = LayoutLocalFrame(origin: .init(x: 0, y: 0, z: 0), axisX: .init(x: 1, y: 0, z: 0), axisY: .init(x: 0, y: 0.6, z: 0.8))
        let s = try Surface2DAdapter.projected(name: "Rampant", kind: .ceiling,
            contour: [.init(x: 0, y: 0, z: 0), .init(x: 3.6, y: 0, z: 0), .init(x: 3.6, y: 1.5, z: 2), .init(x: 0, y: 1.5, z: 2)],
            openings: [], frame: frame, sourceID: "scan-1")
        _ = try check(s, area: 9_000_000, count: 3)
        let doc = LayoutDocument(surface: s)
        XCTAssertEqual(doc, try JSONDecoder().decode(LayoutDocument.self, from: JSONEncoder().encode(doc)))
    }

    func testOpeningsTouchingAtOneVertexAndClippedOutside() throws {
        var s = surface(width: 1200)
        s.openings = [
            .init(kind: .window, contour: LayoutBounds(min: .init(x: 100, y: 100), max: .init(x: 500, y: 500)).polygon),
            .init(kind: .window, contour: LayoutBounds(min: .init(x: 500, y: 500), max: .init(x: 900, y: 900)).polygon)
        ]
        _ = try check(s, area: 2_680_000, count: 1)
        s.openings = [.init(kind: .door, contour: LayoutBounds(min: .init(x: -100, y: -100), max: .init(x: 500, y: 500)).polygon)]
        _ = try check(s, area: 2_750_000, count: 1)
    }

    func testConcaveUProducesTwoPiecesAboveOpening() throws {
        var s = surface(width: 1200)
        s.contour = [.zero, .init(x: 1200, y: 0), .init(x: 1200, y: 2500), .init(x: 800, y: 2500), .init(x: 800, y: 500), .init(x: 400, y: 500), .init(x: 400, y: 2500), .init(x: 0, y: 2500)]
        s.openings = [.init(kind: .other, contour: LayoutBounds(min: .zero, max: .init(x: 1200, y: 600)).polygon)]
        let r = try check(s, area: 1_520_000, count: 1)
        XCTAssertEqual(r.pieceCount, 2)
    }

    @MainActor func testHistoryAndDraftPersistence() throws {
        let name = "layout-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let editor = LayoutEditorModel(defaults: defaults)
        let initial = LayoutDocument(surface: surface())
        editor.apply(initial)
        var changed = initial; changed.layers[0].offset.x = 200
        editor.apply(changed)
        editor.undo(); XCTAssertEqual(editor.document, initial)
        editor.redo(); XCTAssertEqual(editor.document, changed)
        var dragged = changed; dragged.surface.contour.swapAt(1, 2)
        editor.preview(dragged); editor.finishGesture(from: changed)
        XCTAssertEqual(editor.document, changed)

        editor.saveCurrentAndClose()
        XCTAssertNil(editor.document)
        XCTAssertEqual(editor.savedDocuments.count, 1)

        let reloaded = LayoutEditorModel(defaults: defaults)
        XCTAssertNil(reloaded.document)
        XCTAssertEqual(reloaded.savedDocuments.count, 1)
        reloaded.open(reloaded.savedDocuments[0])
        XCTAssertEqual(reloaded.document, changed)

        var renamed = changed
        renamed.surface.name = "Salon"
        reloaded.apply(renamed)
        reloaded.saveCurrentAndClose()
        XCTAssertEqual(reloaded.savedDocuments.count, 1)
        XCTAssertEqual(reloaded.savedDocuments[0].title, "Salon")
    }

    private func noisyStroke(_ polygon: [LayoutPoint], noise: Double = 2, finishGap: Double = 3) -> [LayoutPoint] {
        var points: [LayoutPoint] = []
        for (index, edge) in LayoutGeometry.edges(polygon).enumerated() {
            let vector = edge.b-edge.a, count = max(3,Int(vector.length/5))
            let normal = LayoutPoint(x:-vector.y,y:vector.x) * (1/max(1,vector.length))
            for step in 0..<count {
                let jitter = sin(Double(step*7+index))*noise
                points.append(edge.a + vector*(Double(step)/Double(count)) + normal*jitter)
            }
        }
        points.append(polygon[0] + .init(x:finishGap,y:0))
        return points
    }

    func testBeautificationPreservesRectangleLAndIrregularDiagonals() throws {
        let rectangle = LayoutBounds(min:.zero,max:.init(x:300,y:220)).polygon
        let l: [LayoutPoint] = [.zero,.init(x:300,y:0),.init(x:300,y:100),.init(x:150,y:100),.init(x:150,y:260),.init(x:0,y:260)]
        let pentagon: [LayoutPoint] = [.zero,.init(x:280,y:30),.init(x:320,y:180),.init(x:140,y:280),.init(x:-50,y:150)]
        for shape in [rectangle,l,pentagon] {
            let raw = noisyStroke(shape,noise:3)
            let result = try LayoutStrokeBeautifier.polygon(from:raw)
            XCTAssertEqual(result.count,shape.count)
            XCTAssertNoThrow(try LayoutGeometry.validate(result))
            XCTAssertEqual(abs(LayoutGeometry.area(result))/abs(LayoutGeometry.area(shape)),1,accuracy:0.08)
            for vertex in try LayoutStrokeBeautifier.alignedToGround(shape) {
                XCTAssertLessThan(result.map { ($0-vertex).length }.min()!,14)
            }
            XCTAssertEqual(result,try LayoutStrokeBeautifier.polygon(from:raw))
        }
    }

    func testBeautificationNoiseMicroHookAndStartInMiddleOfSide() throws {
        let rectangle = LayoutBounds(min:.zero,max:.init(x:320,y:220)).polygon
        var raw = noisyStroke(rectangle,noise:5)
        raw.insert(contentsOf:[.init(x:100,y:0),.init(x:104,y:7),.init(x:106,y:0)],at:20)
        XCTAssertEqual(try LayoutStrokeBeautifier.polygon(from:raw).count,4)
        let midStart:[LayoutPoint] = [.init(x:150,y:0),.init(x:300,y:0),.init(x:300,y:220),.init(x:0,y:220),.zero]
        XCTAssertEqual(try LayoutStrokeBeautifier.polygon(from:noisyStroke(midStart)).count,4)
    }

    func testGroundAlignmentRotatesWholePolygonAndSquaresOnlyNearRightCorners() throws {
        let almostRectangle:[LayoutPoint] = [.zero,.init(x:400,y:0),.init(x:414,y:300),.init(x:-10,y:300)]
        let angle = 6.0 * Double.pi/180
        let rotated = almostRectangle.map { p in
            LayoutPoint(x:p.x*cos(angle)-p.y*sin(angle)+37,y:p.x*sin(angle)+p.y*cos(angle)+54)
        }
        for input in [rotated,Array(rotated.reversed())] {
            let output = try LayoutStrokeBeautifier.alignedToGround(input,squareGroundCorners:true)
            XCTAssertEqual(output[0],.zero)
            XCTAssertEqual(output[1].x,400,accuracy:0.00001)
            XCTAssertEqual(output[1].y,0,accuracy:0.00001)
            XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:0,in:output),90,accuracy:0.00001)
            XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:1,in:output),90,accuracy:0.00001)
            XCTAssertNoThrow(try LayoutGeometry.validate(output))
        }
        let oblique:[LayoutPoint] = [.zero,.init(x:400,y:0),.init(x:500,y:300),.init(x:-90,y:280)]
        let tilted = oblique.map { p in LayoutPoint(x:p.x*cos(angle)-p.y*sin(angle),y:p.x*sin(angle)+p.y*cos(angle)) }
        let output = try LayoutStrokeBeautifier.alignedToGround(tilted,squareGroundCorners:true)
        for i in oblique.indices {
            XCTAssertEqual((output[i]-oblique[i]).length,0,accuracy:0.00001)
        }
        // Beautification itself (the finger-up path), not just its helper, aligns the base.
        let strokeResult = try LayoutStrokeBeautifier.polygon(from:noisyStroke(rotated,noise:1),kind:.wall)
        XCTAssertEqual(strokeResult[0].y,0,accuracy:0.00001)
        XCTAssertEqual(strokeResult[1].y,0,accuracy:0.00001)
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:0,in:strokeResult),90,accuracy:0.00001)
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:1,in:strokeResult),90,accuracy:0.00001)
    }

    func testGroundAlignmentKeepsConcaveCornersAndDoesNotSquareTriangles() throws {
        let l:[LayoutPoint] = [.zero,.init(x:400,y:0),.init(x:400,y:180),.init(x:200,y:180),.init(x:200,y:300),.init(x:0,y:300)]
        let output = try LayoutStrokeBeautifier.alignedToGround(l)
        XCTAssertEqual(output,l)
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:3,in:output),270,accuracy:0.00001)
        let triangle:[LayoutPoint] = [.zero,.init(x:400,y:0),.init(x:10,y:300)]
        XCTAssertEqual(try LayoutStrokeBeautifier.alignedToGround(triangle,squareGroundCorners:true),triangle)
    }

    func testCeilingGroundAlignmentNeverSquaresNearRightAngles() throws {
        let shape:[LayoutPoint] = [.zero,.init(x:400,y:0),.init(x:420,y:300),.init(x:-12,y:300)]
        let angle = 6.0 * Double.pi/180
        let tilted = shape.map { p in LayoutPoint(x:p.x*cos(angle)-p.y*sin(angle),y:p.x*sin(angle)+p.y*cos(angle)) }
        let aligned = try LayoutStrokeBeautifier.alignedToGround(tilted)
        for i in shape.indices {
            XCTAssertEqual((aligned[i]-shape[i]).length,0,accuracy:0.00001)
            XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:i,in:aligned),LayoutPolygonSolver.interiorAngle(at:i,in:shape),accuracy:0.00001)
        }
        let output = try LayoutStrokeBeautifier.polygon(from:noisyStroke(tilted,noise:0.3),kind:.ceiling)
        XCTAssertEqual(output[1].y-output[0].y,0,accuracy:0.00001)
        XCTAssertGreaterThan(abs(LayoutPolygonSolver.interiorAngle(at:0,in:output)-90),1)
        XCTAssertGreaterThan(abs(LayoutPolygonSolver.interiorAngle(at:1,in:output)-90),1)
    }

    func testVisibilityDefaultsAndIndependentCycles() {
        var settings = LayoutVisibilitySettings()
        XCTAssertEqual(settings.sheets,.visible)
        XCTAssertEqual(settings.framing,.visible)
        XCTAssertEqual(settings.openings,.visible)
        XCTAssertEqual(settings.electrical,.visible)
        XCTAssertFalse(settings.angles)
        settings.sheets = settings.sheets.next
        XCTAssertTrue(settings.sheets.isVisible)
        XCTAssertTrue(settings.sheets.showsDimensions)
        settings.sheets = settings.sheets.next
        XCTAssertFalse(settings.sheets.isVisible)
        XCTAssertFalse(settings.sheets.showsDimensions)
        XCTAssertEqual(settings.framing,.visible)
        settings.sheets = settings.sheets.next
        XCTAssertEqual(settings.sheets,.visible)
    }

    func testNewSupportHasVisibleCompatibleFramingForWallsAndCeilings() throws {
        for kind in [LayoutSupportKind.wall,.ceiling] {
            let support = Surface2D(name:"Test",kind:kind,contour:LayoutBounds(min:.zero,max:.init(x:4000,y:3000)).polygon)
            let document = LayoutDocument.newSupport(support)
            let layer = try XCTUnwrap(document.layers.first)
            let framing = try XCTUnwrap(layer.furring)
            XCTAssertTrue(LayoutPlanning.compatibleSpacings(layer).contains(framing.spacing))
            let lines = try LayoutFurringEngine.calculate(surface:support,layer:layer).lines
            XCTAssertFalse(lines.isEmpty)
            if kind == .wall {
                XCTAssertTrue(lines.allSatisfy { abs($0.start.x-$0.end.x) < 0.0001 })
            }
        }
    }

    @MainActor func testVisibilityIconsAndCrowdedSupportPreviewRender() throws {
        let contour:[LayoutPoint] = [.zero,.init(x:3870,y:0),.init(x:3820,y:2500),.init(x:3300,y:2870),.init(x:2530,y:3520),.init(x:1530,y:3520),.init(x:1450,y:2770),.init(x:540,y:2770),.init(x:600,y:3220),.init(x:0,y:3320)]
        let view = VStack(spacing:20) {
            LayoutMeasuredPreview(contour:contour,tones:contour.indices.map { [.blue,.orange,.purple,.green,.teal][$0%5] },corrections:[],onCorrection:{ _ in }).frame(height:440)
            ForEach([LayoutVisibilityState.visible,.dimensioned,.hidden],id:\.rawValue) { state in
                HStack {
                    LayoutVisibilityIcon(kind:.sheet,state:state)
                    LayoutVisibilityIcon(kind:.angle,state:state == .hidden ? .hidden : .visible)
                    LayoutVisibilityIcon(kind:.framing,state:state)
                    LayoutVisibilityIcon(kind:.opening,state:state)
                    LayoutVisibilityIcon(kind:.electrical,state:state)
                }.frame(height:44)
            }
        }.padding(16).frame(width:390).background(Color(.systemGroupedBackground)).environment(\.colorScheme,.dark)
        let renderer = ImageRenderer(content:view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image:image)
        attachment.name = "Contour encombré et cinq icônes — trois états"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBeautificationDoesNotLimitToTwelveCornersAndRejectsOpenOrStrangeStrokes() throws {
        let star = (0..<16).map { i -> LayoutPoint in
            let a = Double(i)*2 * .pi/16, r = i%2 == 0 ? 180.0 : 125.0
            return .init(x:200+cos(a)*r,y:200+sin(a)*r)
        }
        XCTAssertEqual(try LayoutStrokeBeautifier.polygon(from:noisyStroke(star,noise:1)).count,16)
        for raw in [[],[LayoutPoint.zero],[.zero,.zero,.zero,.zero], [.zero,.init(x:100,y:0),.init(x:200,y:0),.init(x:300,y:0)]] {
            XCTAssertThrowsError(try LayoutStrokeBeautifier.polygon(from:raw))
        }
        let crossed:[LayoutPoint] = [.zero,.init(x:200,y:200),.init(x:200,y:0),.init(x:0,y:200)]
        XCTAssertThrowsError(try LayoutStrokeBeautifier.polygon(from:noisyStroke(crossed)))
        XCTAssertThrowsError(try LayoutStrokeBeautifier.polygon(from:[.zero,.init(x:100,y:100),.init(x:.nan,y:0),.zero]))
        let rectangle = LayoutBounds(min:.zero,max:.init(x:300,y:200)).polygon
        XCTAssertEqual(try LayoutStrokeBeautifier.polygon(from:noisyStroke(rectangle,finishGap:16)).count,4)
        XCTAssertThrowsError(try LayoutStrokeBeautifier.polygon(from:Array(noisyStroke(rectangle).dropLast(30))))
    }

    private func measuredRectangle() -> LayoutContourIntent {
        var intent = LayoutContourIntent(sketch:LayoutBounds(min:.zero,max:.init(x:4000,y:3000)).polygon)
        intent.userMeasuredLengths = [4000,3000,4000,3000]
        intent.userAnglesDegrees = [90,90,90,90]
        return intent
    }

    func testSolverConsistentAndDistributedCorrectionsAtAllSeverities() throws {
        let exact = try LayoutPolygonSolver.resolve(measuredRectangle())
        XCTAssertTrue(exact.corrections.isEmpty)
        for (delta,severity) in [(16.0,LayoutCorrectionSeverity.yellow),(30.0,.yellow),(70.0,.orange),(140.0,.red)] {
            var intent = measuredRectangle(); intent.userMeasuredLengths[0] = 4000+delta
            let before = intent
            let resolved = try LayoutPolygonSolver.resolve(intent)
            XCTAssertEqual(intent,before)
            XCTAssertNoThrow(try LayoutGeometry.validate(resolved.contour))
            XCTAssertEqual(LayoutGeometry.edges(resolved.contour).reduce(LayoutPoint.zero) { $0 + $1.b-$1.a }.length,0,accuracy:0.001)
            let bottom = try XCTUnwrap(resolved.corrections.first { $0.edgeIndex == 0 })
            let top = try XCTUnwrap(resolved.corrections.first { $0.edgeIndex == 2 })
            XCTAssertEqual(bottom.correctionDelta,-delta/2,accuracy:0.2)
            XCTAssertEqual(top.correctionDelta,delta/2,accuracy:0.2)
            XCTAssertEqual(top.severity(),severity)
            XCTAssertEqual(bottom.percentage,abs(bottom.correctionDelta)/bottom.original*100,accuracy:0.000001)
        }
    }

    func testCorrectionBoundariesAndSignedDelta() {
        for (difference,severity) in [(0.0,LayoutCorrectionSeverity.none),(0.05,.none),(1,.yellow),(19.99,.yellow),(20,.orange),(50,.orange),(50.01,.red)] {
            let correction = LayoutDimensionCorrection(edgeIndex:0,original:4000,corrected:4000-difference)
            XCTAssertEqual(correction.severity(),severity)
            XCTAssertEqual(correction.correctionDelta,-difference,accuracy:0.00001)
        }
    }

    func testSolverLengthAngleReflexAndVertexEditsPreserveIntent() throws {
        let sketch:[LayoutPoint] = [.zero,.init(x:4000,y:0),.init(x:4140,y:3000),.init(x:0,y:3000)]
        var intent = LayoutContourIntent(sketch:sketch)
        intent.userMeasuredLengths = LayoutGeometry.edges(sketch).map { ($0.b-$0.a).length }
        intent.userAnglesDegrees[1] = 90
        let resolved = try LayoutPolygonSolver.resolve(intent)
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:1,in:resolved.contour),90,accuracy:0.01)
        intent.userMeasuredLengths[0] = 3850
        let edited = try LayoutPolygonSolver.resolve(intent)
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:1,in:edited.contour),90,accuracy:0.01)
        XCTAssertEqual(intent.userMeasuredLengths[0],3850)
        XCTAssertEqual(intent.sketch,sketch)
        let roundTrip = try JSONDecoder().decode(LayoutContourIntent.self,from:JSONEncoder().encode(intent))
        XCTAssertEqual(intent,roundTrip)
        var movable = LayoutContourIntent(sketch:sketch)
        movable.userVertexPositions[2] = .init(x:4300,y:3150)
        let moved = try LayoutPolygonSolver.resolve(movable)
        XCTAssertEqual(moved.contour[2].x,4300,accuracy:0.1)
        XCTAssertEqual(moved.contour[2].y,3150,accuracy:0.1)
        let l:[LayoutPoint] = [.zero,.init(x:4000,y:0),.init(x:4000,y:2000),.init(x:2000,y:2000),.init(x:2000,y:4000),.init(x:0,y:4000)]
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:3,in:l),270,accuracy:0.00001)
        var reflex = LayoutContourIntent(sketch:l); reflex.userAnglesDegrees[3] = 265
        let reflexResult = try LayoutPolygonSolver.resolve(reflex)
        XCTAssertEqual(LayoutPolygonSolver.interiorAngle(at:3,in:reflexResult.contour),265,accuracy:0.01)
        var impossible = measuredRectangle(); impossible.userAnglesDegrees = [60,60,60,60]
        XCTAssertThrowsError(try LayoutPolygonSolver.resolve(impossible))
    }

    @MainActor func testSavedLibraryPreservesPolygonConstraintsAndUpdatesWithoutDuplicates() throws {
        let name = "polygon-library-\(UUID())", defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let intent = measuredRectangle()
        var s = surface(); try s.resolve(intent)
        let model = LayoutEditorModel(defaults:defaults)
        model.apply(.init(surface:s)); model.saveCurrentAndClose()
        model.startNew(); model.apply(.init(surface:surface(.lShape))); model.saveCurrentAndClose()
        let restored = LayoutEditorModel(defaults:defaults)
        XCTAssertNil(restored.document)
        XCTAssertEqual(restored.savedDocuments.count,2)
        let saved = try XCTUnwrap(restored.savedDocuments.first { $0.document.surface.contourIntent != nil })
        restored.open(saved)
        XCTAssertEqual(restored.document?.surface.contourIntent,intent)
        restored.saveCurrentAndClose()
        XCTAssertEqual(restored.savedDocuments.count,2)
    }
}
