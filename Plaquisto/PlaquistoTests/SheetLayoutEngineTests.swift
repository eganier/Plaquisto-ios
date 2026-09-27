import XCTest
import SwiftUI
@testable import Plaquisto

final class SheetLayoutEngineTests: XCTestCase {
    private func offcutCeiling(_ width:Double=2400,_ height:Double=3000) -> Surface2D {
        var value=surface(width:width,height:height); value.kind = .ceiling; return value
    }
    private var offcutLayer:LayoutLayer { .init(sheetLength:2400,furring:.init()) }

    func testOffcutsReducePurchasedBoardsAndNumberRelatedPieces() throws {
        let ceiling=offcutCeiling()
        let result=try SheetLayoutEngine.calculate(surface:ceiling,layer:offcutLayer)
        XCTAssertEqual(result.sheets.count,4)
        XCTAssertEqual(result.purchasedSheetCount,3)
        XCTAssertEqual(result.savedSheetCount,1)
        XCTAssertEqual(result.netArea,7_200_000,accuracy:0.01)
        XCTAssertEqual(result.wasteArea,1_440_000,accuracy:0.01)
        XCTAssertEqual(result.sheets.flatMap(\.pieces).compactMap{$0.stock?.label},["1","2","3-1","3-2"])
        XCTAssertEqual(result,try SheetLayoutEngine.calculate(surface:ceiling,layer:offcutLayer))
        try assertCutStockIsFeasible(result)
    }

    func testOffcutMinimumIsFixedAndPeripheryIsAnEligibleSecondSupport() throws {
        let atMinimum=try SheetLayoutEngine.calculate(surface:offcutCeiling(2400,2600),layer:offcutLayer)
        XCTAssertEqual(atMinimum.purchasedSheetCount,3)
        let tooSmall=try SheetLayoutEngine.calculate(surface:offcutCeiling(2400,2599),layer:offcutLayer)
        XCTAssertEqual(tooSmall.purchasedSheetCount,4)
        var noReuse=offcutLayer; noReuse.reuseOffcuts=false
        XCTAssertEqual(try SheetLayoutEngine.calculate(surface:offcutCeiling(),layer:noReuse).purchasedSheetCount,4)
        noReuse.reuseOffcuts=true; noReuse.furring=nil
        XCTAssertEqual(try SheetLayoutEngine.calculate(surface:offcutCeiling(),layer:noReuse).purchasedSheetCount,4)
    }

    func testSupportCountingRejectsCornersAndCollinearFragments() {
        let room=offcutCeiling(3000,3000)
        let piece=LayoutCutPiece(id:"p",contour:LayoutBounds(min:.init(x:500,y:500),max:.init(x:1500,y:1500)).polygon,holes:[])
        let first=LayoutJoint(start:.init(x:0,y:600),end:.init(x:3000,y:600))
        let second=LayoutJoint(start:.init(x:0,y:1200),end:.init(x:3000,y:1200))
        XCTAssertTrue(LayoutOffcutPacking.hasSupports(piece,surface:room,furring:.init(lines:[first,second])))
        XCTAssertFalse(LayoutOffcutPacking.hasSupports(piece,surface:room,furring:.init(lines:[first])))
        let split=[LayoutJoint(start:.init(x:500,y:600),end:.init(x:900,y:600)),
                   LayoutJoint(start:.init(x:1100,y:600),end:.init(x:1500,y:600))]
        XCTAssertFalse(LayoutOffcutPacking.hasSupports(piece,surface:room,furring:.init(lines:split)))
        let corner=LayoutJoint(start:.zero,end:.init(x:500,y:500))
        XCTAssertFalse(LayoutOffcutPacking.hasSupports(piece,surface:room,furring:.init(lines:[first,corner])))
        var withOpening=room
        withOpening.openings=[.init(kind:.other,contour:LayoutBounds(min:.init(x:1500,y:500),max:.init(x:2000,y:1500)).polygon)]
        XCTAssertFalse(LayoutOffcutPacking.hasSupports(piece,surface:withOpening,furring:.init(lines:[first])))
    }

    func testSupportBoundaryRecognitionIsSymmetricAndDoesNotCountOneLineTwice() {
        let room=offcutCeiling(3000,3000)
        for rect in [LayoutBounds(min:.zero,max:.init(x:1200,y:200)),
                     .init(min:.init(x:1800,y:2800),max:.init(x:3000,y:3000))] {
            let piece=LayoutCutPiece(id:"p",contour:rect.polygon,holes:[])
            let line=LayoutJoint(start:.init(x:0,y:rect.center.y),end:.init(x:3000,y:rect.center.y))
            XCTAssertTrue(LayoutOffcutPacking.hasSupports(piece,surface:room,furring:.init(lines:[line])))
        }
        let piece=LayoutCutPiece(id:"p",contour:LayoutBounds(min:.init(x:500,y:0),max:.init(x:1500,y:200)).polygon,holes:[])
        let only=LayoutJoint(start:.zero,end:.init(x:3000,y:0))
        XCTAssertFalse(LayoutOffcutPacking.hasSupports(piece,surface:room,furring:.init(lines:[only])))
    }

    func testStaggerOffsetsFollowFurringInsteadOfAssumingHalfBoard() {
        var layer=offcutLayer; layer.staggered=true
        XCTAssertEqual(LayoutBoardGrid.staggerDistance(layer),1200)
        layer.sheetLength=2500; layer.furring?.spacing=500
        XCTAssertEqual(LayoutBoardGrid.staggerDistance(layer),1000)
        layer.staggerOffset=1500
        XCTAssertEqual(LayoutBoardGrid.staggerDistance(layer),1500)
        layer.staggerOffset=1250
        XCTAssertEqual(LayoutBoardGrid.staggerDistance(layer),1000)
        layer.furring?.spacing=600
        XCTAssertEqual(LayoutBoardGrid.staggerDistance(layer),0)
    }

    func testStaggerCoversSurfaceForBothOrientationsAndNegativeOffsets() throws {
        let room=offcutCeiling(4300,3700)
        for orientation in LayoutOrientation.allCases {
            for offset in [LayoutPoint.zero,.init(x:-300,y:-500),.init(x:1450,y:2550)] {
                var layer=offcutLayer; layer.orientation=orientation; layer.staggered=true; layer.offset=offset
                let result=try SheetLayoutEngine.calculate(surface:room,layer:layer)
                XCTAssertEqual(result.netArea,4300*3700,accuracy:0.1)
                XCTAssertEqual(result.staggerDistance,1200)
                let pieces=result.sheets.flatMap(\.pieces)
                for i in pieces.indices { for j in pieces.indices where j>i {
                    let a=pieces[i].bounds,b=pieces[j].bounds
                    let overlap=max(0,min(a.max.x,b.max.x)-max(a.min.x,b.min.x))*max(0,min(a.max.y,b.max.y)-max(a.min.y,b.min.y))
                    XCTAssertLessThan(overlap,0.01)
                } }
                try assertCutStockIsFeasible(result)
            }
        }
    }

    func testStaggerShortAxisPeriodPreservesAlternateStripParity() throws {
        var layer=offcutLayer; layer.staggered=true
        let room=offcutCeiling()
        let original=try SheetLayoutEngine.calculate(surface:room,layer:layer)
        layer.offset.x=1200
        let shifted=try SheetLayoutEngine.calculate(surface:room,layer:layer)
        XCTAssertNotEqual(original.sheets.map(\.origin),shifted.sheets.map(\.origin))
        layer.offset.x=2400
        XCTAssertEqual(original,try SheetLayoutEngine.calculate(surface:room,layer:layer))
    }

    func testStaggerJointsIncludeTJunctions() throws {
        var layer=offcutLayer; layer.staggered=true
        let result=try SheetLayoutEngine.calculate(surface:offcutCeiling(2400,3600),layer:layer)
        let vertical=result.joints.filter{abs($0.start.x-1200)<0.01 && abs($0.end.x-1200)<0.01}
        XCTAssertEqual(vertical.reduce(0){$0+($1.end-$1.start).length},3600,accuracy:0.01)
        XCTAssertEqual(result.netArea,2400*3600,accuracy:0.01)
    }

    func testStaggerDoesNotIntroduceHorizontalJointIntoSingleHeightWall() throws {
        var layer=offcutLayer; layer.staggered=true
        let wall=surface(width:3600,height:2300)
        let result=try SheetLayoutEngine.calculate(surface:wall,layer:layer)
        XCTAssertEqual(result.staggerDistance,0)
        XCTAssertEqual(result.sheets.count,3)
        XCTAssertEqual(try SheetLayoutEngine.calculate(surface:surface(width:3600,height:4000),layer:layer).staggerDistance,1200)
    }

    func testPackingIsFeasibleForRotatedConcaveCeilingAndOpenings() throws {
        var room=offcutCeiling(4700,4100)
        room.contour=[.zero,.init(x:4700,y:0),.init(x:4300,y:2100),.init(x:2400,y:2100),.init(x:2400,y:4100),.init(x:0,y:4100)]
        room.openings=[.init(kind:.other,contour:LayoutBounds(min:.init(x:600,y:600),max:.init(x:1500,y:1200)).polygon)]
        let frame=LayoutGridFrame(origin:.init(x:80,y:90),angle:0.41)
        room.contour=room.contour.map(frame.world)
        room.openings[0].contour=room.openings[0].contour.map(frame.world)
        var layer=offcutLayer; layer.referenceEdge=0; layer.staggered=true
        let result=try SheetLayoutEngine.calculate(surface:room,layer:layer)
        XCTAssertEqual(result.netArea,abs(LayoutGeometry.area(room.contour))-540000,accuracy:1)
        try assertCutStockIsFeasible(result)
    }

    func testOffcutSettingsRoundTripAndLegacyLayerDecoding() throws {
        var layer=offcutLayer; layer.staggered=true; layer.staggerOffset=600; layer.reuseOffcuts=false
        let data=try JSONEncoder().encode(layer)
        XCTAssertEqual(try JSONDecoder().decode(LayoutLayer.self,from:data),layer)
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for key in ["staggered","staggerOffset","reuseOffcuts"] { legacy.removeValue(forKey:key) }
        let decoded=try JSONDecoder().decode(LayoutLayer.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(decoded.staggered); XCTAssertNil(decoded.reuseOffcuts)
        XCTAssertEqual(LayoutBoardGrid.staggerDistance(decoded),0)
    }

    func testOptimizerScoresPurchasedStockAndKeepsStaggerOnTheFrame() throws {
        let room=offcutCeiling(4300,3700)
        var layer=offcutLayer; layer.staggered=true; layer.offset = .init(x:140,y:230)
        let before=try SheetLayoutEngine.calculate(surface:room,layer:layer)
        let optimized=try LayoutPlanning.optimize(surface:room,layer:layer,furring:false)
        let after=try SheetLayoutEngine.calculate(surface:room,layer:optimized)
        XCTAssertLessThanOrEqual(after.purchasedSheetCount,before.purchasedSheetCount)
        XCTAssertTrue(LayoutPlanning.aligned(optimized))
        XCTAssertTrue(LayoutBoardGrid.staggerChoices(optimized).contains(after.staggerDistance))
        XCTAssertEqual(optimized.sheetWidth,layer.sheetWidth)
        XCTAssertEqual(optimized.sheetLength,layer.sheetLength)
        XCTAssertEqual(optimized.orientation,layer.orientation)
        XCTAssertEqual(optimized.furring?.spacing,layer.furring?.spacing)
        XCTAssertEqual(after.netArea,before.netArea,accuracy:0.1)
        try assertCutStockIsFeasible(after)
    }

    func testCutDiagramPlacesSiblingAndSpotInActualPurchasedBoardCoordinates() throws {
        let result=try SheetLayoutEngine.calculate(surface:offcutCeiling(),layer:offcutLayer)
        let sheet=try XCTUnwrap(result.sheets.last)
        let piece=try XCTUnwrap(sheet.pieces.first)
        var lighting=LayoutLighting(); lighting.positions=[piece.bounds.center]
        let selection=LayoutCutSelection.make(sheet:sheet,piece:piece,lighting:lighting,frame:result.frame,wall:false,placements:result.sheets)
        XCTAssertEqual(selection.spots,[piece.bounds.center])
        XCTAssertEqual(selection.relatedCuts.count,1)
        let origin=try XCTUnwrap(piece.stock?.origin)
        for sibling in selection.relatedCuts {
            XCTAssertEqual(sibling.stock?.origin,origin)
            let b=LayoutBounds(points:sibling.contour.map{$0-origin})
            XCTAssertGreaterThanOrEqual(b.min.x,0)
            XCTAssertGreaterThanOrEqual(b.min.y,0)
            XCTAssertLessThanOrEqual(b.max.x,sheet.width)
            XCTAssertLessThanOrEqual(b.max.y,sheet.height)
            XCTAssertEqual(sibling.stock?.label,"3-1")
        }
    }

    func testBoardGridRejectsInvalidAndExcessiveInputWithoutIntegerOverflow() {
        let enormous=LayoutBounds(min:.zero,max:.init(x:1e100,y:1e100))
        XCTAssertThrowsError(try LayoutBoardGrid.cells(bounds:enormous,layer:offcutLayer))
        var layer=offcutLayer; layer.sheetWidth=1;layer.sheetLength=1
        XCTAssertThrowsError(try LayoutBoardGrid.cells(bounds:offcutCeiling().bounds,layer:layer))
        layer.sheetLength = .infinity
        XCTAssertThrowsError(try LayoutBoardGrid.cells(bounds:offcutCeiling().bounds,layer:layer))
        layer.sheetWidth=1200; layer.sheetLength=1e100; layer.staggered=true
        XCTAssertEqual(LayoutBoardGrid.staggerDistance(layer),0)
        XCTAssertThrowsError(try LayoutBoardGrid.cells(bounds:offcutCeiling().bounds,layer:layer))
    }

    private func assertCutStockIsFeasible(_ result:SheetLayoutResult,file:StaticString=#filePath,line:UInt=#line) throws {
        var boxes:[Int:[LayoutBounds]]=[:],labels=Set<String>()
        for sheet in result.sheets { for piece in sheet.pieces {
            let stock=try XCTUnwrap(piece.stock,file:file,line:line)
            XCTAssertTrue(labels.insert(stock.label).inserted,file:file,line:line)
            let box=LayoutBounds(points:piece.contour.map{$0-stock.origin})
            XCTAssertGreaterThanOrEqual(box.min.x,-0.01,file:file,line:line)
            XCTAssertGreaterThanOrEqual(box.min.y,-0.01,file:file,line:line)
            XCTAssertLessThanOrEqual(box.max.x,sheet.width+0.01,file:file,line:line)
            XCTAssertLessThanOrEqual(box.max.y,sheet.height+0.01,file:file,line:line)
            // Test fixtures have connected pieces per grid cell. Conservative
            // envelopes assigned to different cells must never share material.
            for other in boxes[stock.number,default:[]] {
                let overlap=max(0,min(box.max.x,other.max.x)-max(box.min.x,other.min.x))*max(0,min(box.max.y,other.max.y)-max(box.min.y,other.min.y))
                XCTAssertLessThan(overlap,0.1,file:file,line:line)
            }
            boxes[stock.number,default:[]].append(box)
        } }
        XCTAssertGreaterThanOrEqual(result.wasteArea,0,file:file,line:line)
    }

    func testNewScannedCeilingBoardsArePerpendicularToLongestWall() throws {
        var ceiling = surface(width: 5000, height: 3000)
        ceiling.kind = .ceiling
        let angle = 0.37
        ceiling.contour = ceiling.contour.map { .init(x: cos(angle)*$0.x-sin(angle)*$0.y,
                                                     y: sin(angle)*$0.x+cos(angle)*$0.y) }
        let document = LayoutDocument.newSupport(ceiling)
        let layer = try XCTUnwrap(document.layers.first)
        let edge = try XCTUnwrap(layer.referenceEdge)
        let wall = ceiling.contour[(edge+1)%ceiling.contour.count]-ceiling.contour[edge]
        XCTAssertEqual(wall.length, 5000, accuracy: 0.001)
        XCTAssertEqual(layer.orientation, .vertical)
        let frame = LayoutGridFrame.make(surface: ceiling, layer: layer)
        let boardLongDirection = frame.world(.init(x:0,y:1))-frame.origin
        XCTAssertEqual(LayoutGeometry.dot(boardLongDirection,wall), 0, accuracy: 0.001)
        XCTAssertFalse(try SheetLayoutEngine.calculate(surface: ceiling, layer: layer).furring.lines.isEmpty)
        XCTAssertEqual(document.surface, ceiling)
    }

    func testReferenceWallCyclingRespectsWindingAndWraps() {
        var ceiling = surface()
        for _ in 0..<2 {
            let ccw = LayoutGeometry.area(ceiling.contour) > 0
            XCTAssertEqual(LayoutPlanning.nextReferenceEdge(ceiling,current:0,clockwise:true), ccw ? 3 : 1)
            var current: Int? = 0
            for _ in 0..<4 { current = LayoutPlanning.nextReferenceEdge(ceiling,current:current,clockwise:true) }
            XCTAssertEqual(current,0)
            let next = LayoutPlanning.nextReferenceEdge(ceiling,current:0,clockwise:true)
            XCTAssertEqual(LayoutPlanning.nextReferenceEdge(ceiling,current:next,clockwise:false),0)
            ceiling.contour.reverse()
        }
    }

    func testOuvrageLayoutKeepsSpacingAndLargestCombinedFormatAllocation() throws {
        var configuration = CeilingConfiguration()
        configuration.selectedSpacing = 0.5
        configuration.firstSkin = [
            .init(facingID:"a",dimensionID:"1200x2400",area:10),
            .init(facingID:"b",dimensionID:"1200x2500",area:8),
            .init(facingID:"c",dimensionID:"1200x2500",area:8)
        ]
        var ceiling = surface(); ceiling.kind = .ceiling
        let document = WorkLayoutDefaults.document(surface:ceiling,configuration:.ceiling(configuration))
        let layer = try XCTUnwrap(document.layers.first)
        XCTAssertEqual(layer.sheetWidth,1200)
        XCTAssertEqual(layer.sheetLength,2500)
        XCTAssertEqual(layer.furring?.spacing,500)
        XCTAssertNotNil(layer.referenceEdge)
        XCTAssertTrue(LayoutVisibilitySettings().framing.isVisible)
    }

    func testExistingComponentLayoutIsNotResetByOuvrageDefaults() throws {
        var ceiling = surface(); ceiling.kind = .ceiling
        let savedLayer = LayoutLayer(sheetWidth:900,sheetLength:3000,orientation:.horizontal,
            offset:.init(x:73,y:41),referenceEdge:1)
        var component = WorkComponentRecord(name:"Salon",surface:ceiling)
        component.framing = .init(spacing:400,offset:62)
        component.plans = [.init(sideRoomID:nil,layers:[savedLayer])]
        let initial = try XCTUnwrap(component.initialDocument(sideRoomID:nil,configuration:.ceiling(.init())))
        XCTAssertEqual(initial.layers[0].sheetLength,3000)
        XCTAssertEqual(initial.layers[0].sheetWidth,900)
        XCTAssertEqual(initial.layers[0].referenceEdge,1)
        XCTAssertEqual(initial.layers[0].offset,savedLayer.offset)
        XCTAssertEqual(initial.layers[0].furring,component.framing)
    }

    func testLayingOffsetPresentationUsesSliderDirection() throws {
        XCTAssertEqual(LayoutLayingOffset.storedMillimetres(displayedCentimetres:-5),50)
        XCTAssertEqual(LayoutLayingOffset.storedMillimetres(displayedCentimetres:5),-50)
        XCTAssertEqual(LayoutLayingOffset.displayedCentimetres(storedMillimetres:50),-5)
        XCTAssertEqual(LayoutLayingOffset.displayedCentimetres(storedMillimetres:-50),5)
        let outward = try surface(width:5000,height:5000).changingLayingOffset(edge:0,distanceMM:LayoutLayingOffset.storedMillimetres(displayedCentimetres:5))
        XCTAssertNotNil(outward.layingWarning)
        let inward = try surface(width:5000,height:5000).changingLayingOffset(edge:0,distanceMM:LayoutLayingOffset.storedMillimetres(displayedCentimetres:-5))
        XCTAssertNil(inward.layingWarning)
    }
    func testLayingOffsetsAreAbsoluteAndPreserveMeasuredContour() throws {
        let original = surface(width:5000,height:5000)
        XCTAssertEqual(try original.layingContour(),original.contour)
        let global = try original.changingLayingOffset(globalMM:30)
        XCTAssertEqual(LayoutBounds(points:try global.layingContour()).width,4940,accuracy:0.001)
        XCTAssertEqual(LayoutBounds(points:try global.layingContour()).height,4940,accuracy:0.001)
        for value in [0.0,-50,100] {
            let individual = try global.changingLayingOffset(edge:0,distanceMM:value)
            XCTAssertEqual(individual.layingDistance(at:0),value)
            XCTAssertEqual(individual.contour,original.contour)
            let result = try individual.layingContour()
            let edge = original.contour[1]-original.contour[0]
            XCTAssertEqual(LayoutGeometry.cross(edge,result[0]-original.contour[0])/edge.length,value,accuracy:0.001)
            XCTAssertEqual(individual.layingWarning != nil,value < 0)
            let reset = try individual.changingLayingOffset(reset:true)
            XCTAssertNil(reset.layingWarning)
            XCTAssertEqual(try reset.layingContour(),original.contour)
            XCTAssertTrue(reset.layingOffset.individualMM.isEmpty)
        }
    }
    func testLayingOffsetsConcaveObliqueAndBothWindings() throws {
        let polygons = [surface(.lShape,width:5000,height:5000).contour,
                        [LayoutPoint.zero,.init(x:5000,y:0),.init(x:4000,y:3500),.init(x:0,y:5000)]]
        for polygon in polygons {
            for contour in [polygon,Array(polygon.reversed())] {
                let original = Surface2D(name:"Test",kind:.ceiling,contour:contour)
                let changed = try original.changingLayingOffset(globalMM:30)
                let result = try changed.layingContour()
                let winding = LayoutGeometry.area(contour) > 0 ? 1.0 : -1.0
                for i in contour.indices {
                    let d = contour[(i+1)%contour.count]-contour[i]
                    for point in [result[i],result[(i+1)%result.count]] {
                        XCTAssertEqual(LayoutGeometry.cross(d,point-contour[i])/d.length,30*winding,accuracy:0.001)
                    }
                }
            }
        }
    }
    func testLayingInvalidOffsetsRejectAndKeepLastValidState() throws {
        let narrow = surface(width:80,height:5000)
        let valid = try narrow.changingLayingOffset(globalMM:30)
        XCTAssertThrowsError(try valid.changingLayingOffset(globalMM:50))
        XCTAssertEqual(valid.layingOffset.globalMM,30)
        let crossed = Surface2D(name:"Invalid",kind:.wall,contour:[.zero,.init(x:100,y:100),.init(x:0,y:100),.init(x:100,y:0)])
        XCTAssertThrowsError(try crossed.layingContour())
    }
    func testLayingClipsOpeningsAndChangesBoardsWithoutChangingFraming() throws {
        var original = surface(width:5000,height:5000)
        original.kind = .ceiling
        original.openings = [.init(kind:.stairwell,contour:LayoutBounds(min:.init(x:0,y:100),max:.init(x:1000,y:1100)).polygon)]
        var layer = LayoutLayer(); layer.furring = .init()
        let before = try SheetLayoutEngine.calculate(surface:original,layer:layer)
        let changed = try original.changingLayingOffset(globalMM:30)
        let after = try SheetLayoutEngine.calculate(surface:changed,layer:layer)
        XCTAssertEqual(after.netArea,4940*4940-970*1000,accuracy:0.01)
        XCTAssertEqual(after.netArea,try changed.netLayingArea(),accuracy:0.01)
        XCTAssertEqual(try changed.netMeasuredArea(),before.netArea,accuracy:0.01)
        XCTAssertEqual(after.furring,before.furring)
        XCTAssertNotEqual(after.sheets,before.sheets)
        XCTAssertEqual(original.openings,changed.openings)
    }
    func testLayingPersistenceLegacyAndStableEdgeIdentity() throws {
        let original = surface(width:5000,height:5000)
        let changed = try original.changingLayingOffset(globalMM:30).changingLayingOffset(edge:2,distanceMM:-50)
        let reopened = try JSONDecoder().decode(Surface2D.self,from:JSONEncoder().encode(changed))
        XCTAssertEqual(changed,reopened)
        XCTAssertEqual(try changed.layingContour(),try reopened.layingContour())
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        legacy.removeValue(forKey:"layingOffset"); legacy.removeValue(forKey:"edgeIDs")
        let decoded = try JSONDecoder().decode(Surface2D.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertEqual(decoded.layingOffset.globalMM,0)
        XCTAssertEqual(try decoded.layingContour(),original.contour)
        let inserted = try changed.changingVertex(insertAfter:0,point:(changed.contour[0]+changed.contour[1])*0.5)
        XCTAssertEqual(inserted.stableEdgeIDs[3],changed.stableEdgeIDs[2])
        XCTAssertEqual(inserted.layingDistance(at:3),-50)
    }
    func testLayingExpansionRecalculatesRequiredBoardCount() throws {
        let original = surface(width:2400,height:2500)
        let expanded = try original.changingLayingOffset(edge:1,distanceMM:-50)
        XCTAssertEqual(try SheetLayoutEngine.calculate(surface:original,layer:.init()).sheets.count,2)
        XCTAssertEqual(try SheetLayoutEngine.calculate(surface:expanded,layer:.init()).sheets.count,3)
    }
    func testLayingOffsetsMirrorWithPartitionSideWithoutLosingEdgeIDs() throws {
        let original = try surface(width:5000,height:5000).changingLayingOffset(globalMM:30).changingLayingOffset(edge:1,distanceMM:-50)
        let mirrored = original.mirroredComponentSide()
        XCTAssertEqual(mirrored.stableEdgeIDs,original.stableEdgeIDs)
        let expected = try original.layingContour().map { LayoutPoint(x:-$0.x,y:$0.y) }
        let actual = try mirrored.layingContour()
        for (a,b) in zip(expected,actual) {
            XCTAssertEqual(a.x,b.x,accuracy:0.001); XCTAssertEqual(a.y,b.y,accuracy:0.001)
        }
        XCTAssertEqual(try mirrored.netLayingArea(),try original.netLayingArea(),accuracy:0.01)
    }
    @MainActor func testLayingOffsetSurvivesClosingAndReopeningSavedPlan() throws {
        let name = "layout-offset-\(UUID())", defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let changed = try surface(width:5000,height:5000).changingLayingOffset(globalMM:30).changingLayingOffset(edge:1,distanceMM:-50)
        let saved = SavedLayoutDocument(document:.init(surface:changed))
        defaults.set(try JSONEncoder().encode([saved]),forKey:"plaquisto.tools.layout.library.v1")
        let editor = LayoutEditorModel(defaults:defaults)
        editor.open(editor.savedDocuments[0]); editor.saveCurrentAndClose()
        let reopened = LayoutEditorModel(defaults:defaults)
        reopened.open(reopened.savedDocuments[0])
        XCTAssertEqual(reopened.document?.surface,changed)
        XCTAssertTrue(try XCTUnwrap(reopened.document?.surface.layingWarning).contains("mur adjacent"))
        var ceiling = changed; ceiling.kind = .ceiling
        XCTAssertTrue(try XCTUnwrap(ceiling.layingWarning).contains("mur support"))
    }
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
    func testViewportRotationKeepsGeometricCenterAndRoundTripsCoordinates() {
        let bounds = LayoutBounds(min:.init(x:-500,y:-500),max:.init(x:5000,y:4000))
        let pivot = LayoutPoint(x:1750,y:1200)
        let base = LayoutViewport(bounds:bounds,size:.init(width:390,height:600),zoom:1.7,pan:.init(width:23,height:-11),pivot:pivot)
        for angle in [-2.2,0,.pi/2,4.9] {
            var rotated = base; rotated.rotation = angle
            XCTAssertEqual(rotated.screen(pivot),base.screen(pivot))
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
        let pivot = LayoutViewport.geometricCenter(points)
        let viewport = LayoutViewport(bounds:LayoutViewport.fittedBounds(points,rotation:angle,pivot:pivot),size:.init(width:390,height:400),zoom:1,pan:.zero,rotation:angle,pivot:pivot)
        for point in points {
            let p = viewport.screen(point)
            XCTAssertTrue((0...390).contains(p.x)); XCTAssertTrue((0...400).contains(p.y))
        }
    }
    func testConcaveViewportRotationUsesStablePolygonCentroid() {
        let points = [LayoutPoint.zero,.init(x:5000,y:0),.init(x:5000,y:1500),
                      .init(x:1800,y:1500),.init(x:1800,y:4200),.init(x:0,y:4200)]
        let pivot = LayoutViewport.geometricCenter(points)
        let bounds = LayoutViewport.fittedBounds(points,rotation:0,pivot:pivot)
        let base = LayoutViewport(bounds:bounds,size:.init(width:390,height:500),zoom:1.3,pan:.zero,pivot:pivot)
        let center = base.screen(pivot)
        for angle in stride(from:-Double.pi,through:Double.pi,by:0.2) {
            var viewport = base
            viewport.rotation = angle
            XCTAssertEqual(viewport.screen(pivot).x,center.x,accuracy:0.000001)
            XCTAssertEqual(viewport.screen(pivot).y,center.y,accuracy:0.000001)
        }
    }
    func testViewportPanAlwaysLeavesContourVisibleAtEveryZoomAndRotation() {
        let points = [LayoutPoint.zero,.init(x:5000,y:0),.init(x:5000,y:1500),
                      .init(x:1800,y:1500),.init(x:1800,y:4200),.init(x:0,y:4200)]
        let pivot = LayoutViewport.geometricCenter(points)
        let bounds = LayoutViewport.fittedBounds(points,rotation:0,pivot:pivot)
        for zoom in [0.4,1.0,3.0,8.0] {
            for rotation in [-2.1,0.0,1.3] {
                let viewport = LayoutViewport(bounds:bounds,size:.init(width:390,height:500),zoom:zoom,pan:.zero,rotation:rotation,pivot:pivot)
                for requested in [CGSize(width:20_000,height:20_000),CGSize(width:-20_000,height:-20_000),CGSize(width:20_000,height:-20_000)] {
                    let pan = viewport.constrainedPan(requested,contour:points)
                    var moved = viewport
                    moved = LayoutViewport(bounds:moved.bounds,size:moved.size,zoom:moved.zoom,pan:pan,rotation:moved.rotation,pivot:moved.pivot)
                    let screen = points.map(moved.screen)
                    XCTAssertGreaterThanOrEqual(screen.map(\.x).max() ?? 0,50-0.000001)
                    XCTAssertLessThanOrEqual(screen.map(\.x).min() ?? 0,340+0.000001)
                    XCTAssertGreaterThanOrEqual(screen.map(\.y).max() ?? 0,50-0.000001)
                    XCTAssertLessThanOrEqual(screen.map(\.y).min() ?? 0,450+0.000001)
                }
            }
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
        layer.furring?.offset = 75; layer = LayoutPlanning.alignBoards(to:layer,support:.wall)
        XCTAssertTrue(LayoutPlanning.aligned(layer)); XCTAssertEqual(layer.offset.x,75)
        layer.furring?.parallelToBoards = true
        XCTAssertEqual(LayoutPlanning.compatibleSpacings(layer),[400,600])
    }
    func testCeilingBoardSnapIsNearestAndPreservesLateralPlacement() {
        for orientation in [LayoutOrientation.vertical, .horizontal] {
            for spacing in [400.0, 500.0, 600.0] {
                for position in [-4301.0, -1200, -1, 0, 49, 50, 51, 2749, 2750, 2751, 4390] {
                    var layer = LayoutLayer()
                    layer.orientation = orientation
                    layer.sheetLength = spacing == 500 ? 2500 : 2400
                    layer.referenceEdge = 2
                    layer.furring = .init(spacing:spacing,offset:50)
                    let alongX = LayoutPlanning.alongX(layer)
                    layer.offset = alongX ? .init(x:1733,y:position) : .init(x:position,y:1733)
                    let result = LayoutPlanning.alignBoards(to:layer,support:.ceiling)
                    let target = alongX ? result.offset.y : result.offset.x
                    let nearest = 50 + ((position - 50)/spacing).rounded()*spacing
                    XCTAssertEqual(abs(target-position),abs(nearest-position),accuracy:0.000001)
                    XCTAssertLessThanOrEqual(abs(target-position),spacing/2+0.000001)
                    XCTAssertTrue(LayoutPlanning.aligned(result))
                    XCTAssertEqual(LayoutPlanning.alignBoards(to:result,support:.ceiling),result)
                    var expected = layer
                    if alongX { expected.offset.y = target } else { expected.offset.x = target }
                    XCTAssertEqual(result,expected, "Only the offset normal to the fourrures may change")
                }
            }
        }
    }

    func testCeilingBoardSnapOnLargeRotatedPlanKeepsFurringAndGridOrigin() throws {
        var support = surface(width:8000,height:7000)
        support.kind = .ceiling
        let world = LayoutGridFrame(origin:.init(x:800,y:400),angle:0.37)
        support.contour = support.contour.map(world.world)
        var layer = LayoutLayer()
        layer.sheetLength = 2400
        layer.referenceEdge = 0
        layer.offset = .init(x:1733,y:3590)
        layer.furring = .init(spacing:600,offset:0,orientation:.horizontal)
        let before = try SheetLayoutEngine.calculate(surface:support,layer:layer)
        let snapped = LayoutPlanning.alignBoards(to:layer,support:.ceiling)
        XCTAssertEqual(snapped.offset,.init(x:1733,y:3600))
        let after = try SheetLayoutEngine.calculate(surface:support,layer:snapped)
        XCTAssertEqual(before.furring,after.furring)
        XCTAssertEqual(before.frame.origin,after.frame.origin)
        XCTAssertEqual(before.frame.angle,after.frame.angle)
        XCTAssertTrue(after.furring.lines.contains { abs($0.start.y-3600) < 0.001 && abs($0.end.y-3600) < 0.001 })
        XCTAssertTrue(LayoutPlanning.aligned(snapped))
    }

    func testCeilingSnapDoesNotResetAlignedOrUnsupportedLayers() {
        var layer = LayoutLayer()
        layer.sheetLength = 2400
        layer.offset = .init(x:1345,y:3600)
        XCTAssertEqual(LayoutPlanning.alignBoards(to:layer,support:.ceiling),layer)
        layer.furring = .init(spacing:600,offset:0,orientation:.horizontal)
        XCTAssertEqual(LayoutPlanning.alignBoards(to:layer,support:.ceiling),layer)
        layer.furring?.spacing = 0
        XCTAssertEqual(LayoutPlanning.alignBoards(to:layer,support:.ceiling),layer)
        layer.furring?.spacing = 500
        XCTAssertEqual(LayoutPlanning.alignBoards(to:layer,support:.ceiling),layer)
        layer.furring?.spacing = 600
        let wall = LayoutPlanning.alignBoards(to:layer,support:.wall)
        XCTAssertEqual(wall.offset,.init(x:1345,y:0), "Legacy wall action is unchanged")
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

    func testPresetShapesNeverUseDrawingScale() throws {
        var wall = surface(.slope,width:4000,height:2400,second:3000)
        wall.provenance = "preset"
        wall.contourIntent = .init(sketch:wall.contour)
        XCTAssertFalse(wall.canScaleDrawing)
        XCTAssertThrowsError(try wall.scaledDrawing(by:1.5))

        var ceiling = surface(width:5000,height:3200)
        ceiling.kind = .ceiling
        ceiling.provenance = "preset"
        ceiling.contourIntent = .init(sketch:ceiling.contour)
        XCTAssertFalse(ceiling.canScaleDrawing)
        XCTAssertThrowsError(try ceiling.scaledDrawing(by:0.75))
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

    func testBoardAndFurringOrientationsRemainIndependent() throws {
        var surface = surface(width:2400,height:1200)
        surface.kind = .ceiling

        // A legacy relative value is resolved once, then preserved as an
        // absolute physical direction while board orientation changes.
        var layer = LayoutLayer()
        layer.orientation = .vertical
        layer.furring = .init(parallelToBoards:false,spacing:600,offset:0)
        layer.materializeFurringOrientation()
        XCTAssertEqual(layer.resolvedFurringOrientation, .horizontal)

        layer.orientation = .horizontal
        XCTAssertEqual(layer.resolvedFurringOrientation, .horizontal)
        var result = try SheetLayoutEngine.calculate(surface:surface,layer:layer)
        XCTAssertTrue(result.furring.lines.allSatisfy { abs($0.start.y-$0.end.y) < 0.001 })

        layer.setFurringOrientation(.vertical)
        XCTAssertEqual(layer.orientation, .horizontal)
        result = try SheetLayoutEngine.calculate(surface:surface,layer:layer)
        XCTAssertTrue(result.furring.lines.allSatisfy { abs($0.start.x-$0.end.x) < 0.001 })

        layer.orientation = .vertical
        XCTAssertEqual(layer.resolvedFurringOrientation, .vertical)
        let reopened = try JSONDecoder().decode(LayoutLayer.self, from: JSONEncoder().encode(layer))
        XCTAssertEqual(reopened.orientation, .vertical)
        XCTAssertEqual(reopened.resolvedFurringOrientation, .vertical)
    }

    func testChangingFurringOrientationNeverChangesBoardOrientation() {
        for boardOrientation in LayoutOrientation.allCases {
            var layer = LayoutLayer()
            layer.orientation = boardOrientation
            layer.furring = .init()
            layer.materializeFurringOrientation()

            for furringOrientation in LayoutOrientation.allCases {
                layer.setFurringOrientation(furringOrientation)
                XCTAssertEqual(layer.orientation, boardOrientation)
                XCTAssertEqual(layer.resolvedFurringOrientation, furringOrientation)
            }
        }
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

    func testLegacyWallPresetsMirrorSlopeAndLWithoutChangingArea() throws {
        for preset in [LayoutPreset.slope, .lShape] {
            let normal = preset.contour(length: 4000, height: 2400, secondaryHeight: 3000)
            let mirrored = preset.contour(length: 4000, height: 2400, secondaryHeight: 3000, mirrored: true)
            XCTAssertEqual(abs(LayoutGeometry.area(normal)), abs(LayoutGeometry.area(mirrored)), accuracy: 0.001)
            XCTAssertNoThrow(try LayoutGeometry.validate(normal))
            XCTAssertNoThrow(try LayoutGeometry.validate(mirrored))
        }
    }
    func testPresetSelectionExcludesLForWallsAndKeepsItForCeilings() throws {
        XCTAssertEqual(LayoutPreset.available(for: .wall), [.rectangle, .slope, .freeform])
        XCTAssertEqual(LayoutPreset.available(for: .ceiling), [.rectangle, .lShape, .freeform])
        XCTAssertFalse(LayoutPreset.lShape.isAvailable(for: .wall))
        XCTAssertTrue(LayoutPreset.lShape.isAvailable(for: .ceiling))

        // Compatibility is intentionally independent from the creation menu:
        // an L-shaped wall saved by an older version must remain valid.
        let legacyWall = LayoutPreset.lShape.contour(
            length: 5000,
            height: 2400,
            secondaryHeight: 3100,
            lowerLength: 1800
        )
        XCTAssertNoThrow(try LayoutGeometry.validate(legacyWall))
    }
    func testSlopeMirrorMovesMaximumHeightFromBCToDA() throws {
        let normal = LayoutPreset.slope.contour(length: 4000, height: 2500, secondaryHeight: 4000)
        let mirrored = LayoutPreset.slope.contour(length: 4000, height: 2500, secondaryHeight: 4000, mirrored: true)
        XCTAssertEqual((normal[2] - normal[1]).length, 4000, accuracy: 0.001)
        XCTAssertEqual((normal[0] - normal[3]).length, 2500, accuracy: 0.001)
        XCTAssertEqual((mirrored[2] - mirrored[1]).length, 2500, accuracy: 0.001)
        XCTAssertEqual((mirrored[0] - mirrored[3]).length, 4000, accuracy: 0.001)
    }

    func testLegacyLWallUsesRequestedArchitecturalSides() throws {
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
            } else {
                XCTAssertEqual(layer.sheetWidth,1200)
                XCTAssertEqual(layer.sheetLength,2400)
                XCTAssertEqual(framing.spacing,600)
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
