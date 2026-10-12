import XCTest
import SwiftUI
@testable import Plaquisto

final class SheetLayoutEngineTests: XCTestCase {
    func testPreciseProfilesAreFiftyMillimetresInEveryDirection() {
        for end:LayoutPoint in [.init(x:1000,y:0),.init(x:0,y:1000),.init(x:800,y:600)] {
            let line=LayoutJoint(start:.zero,end:end)
            let polygon=LayoutPreciseStyle.profilePolygon(line)
            XCTAssertEqual(polygon.count,4)
            XCTAssertEqual((polygon[0]-polygon[3]).length,50,accuracy:0.0001)
            XCTAssertEqual((polygon[1]-polygon[0]).length,line.end.length,accuracy:0.0001)
            XCTAssertEqual(abs(LayoutGeometry.area(polygon)),50*end.length,accuracy:0.001)
        }
        XCTAssertTrue(LayoutPreciseStyle.profilePolygon(.init(start:.zero,end:.zero)).isEmpty)
    }

    func testPreciseFramingPlacesSupportHorizontalsBehindVerticals() {
        let v=LayoutJoint(start:.zero,end:.init(x:0,y:2500))
        let h=LayoutJoint(start:.init(x:-1000,y:1200),end:.init(x:1000,y:1200))
        let lintel=LayoutJoint(start:.init(x:0,y:2100),end:.init(x:900,y:2100))
        var geometry=LayoutFurringResult(lines:[v,h,lintel])
        geometry.wallFixedProfiles=[.init(line:h,role:.supportHorizontal)]
        geometry.openingProfiles=[.init(line:lintel,role:.horizontal)]
        XCTAssertEqual(LayoutPreciseStyle.orderedLines(geometry),[h,lintel,v])
        XCTAssertEqual(geometry.lines,[v,h,lintel],"Presentation must not mutate quantities or geometry")
    }

    func testPreciseFocusInterpolatesOnlyPresentation() {
        XCTAssertEqual(LayoutPreciseStyle.transitionDuration,0.5)
        XCTAssertEqual(LayoutPreciseStyle.blur(focus:0),0.6,accuracy:0.001)
        XCTAssertEqual(LayoutPreciseStyle.blur(focus:0.5),0.3,accuracy:0.001)
        XCTAssertEqual(LayoutPreciseStyle.blur(focus:1),0)
        XCTAssertEqual(LayoutPreciseStyle.plateOpacity(focus:0),0.64,accuracy:0.001)
        XCTAssertEqual(LayoutPreciseStyle.plateOpacity(focus:1),0.16,accuracy:0.001)
    }

    func testAutomaticPartitionHasTwoMirroredFacesAndSharedFrameForEverySkin() throws {
        let surface = Surface2D(name:"Cloison",kind:.wall,contour:LayoutPreset.rectangle.contour(length:2600,height:2400,secondaryHeight:0))
        var c = CloisonDistributionConfiguration(); c.layers=2; c.geometryMode="surface"; c.enteredSurface=6.24
        c.faceAFirst=[.init(facingID:"ba13",formatID:"1200x2400",surface:6.24)]
        c.faceASecond=c.faceAFirst; c.faceBFirst=c.faceAFirst; c.faceBSecond=c.faceAFirst
        var work=WorkItem(id:UUID(),projectID:UUID(),name:"Cloison",type:.distributionPartition,payload:.distributionPartition(c),createdAt:Date(),updatedAt:Date())
        var component=WorkComponentRecord(name:"Cloison",surface:surface)
        component.surveySource = .init(surveyID:UUID(),checkpointID:UUID(),surfaceID:UUID(),boundaryIndex:0,kind:.wall,capturedAt:Date())
        work.components=[component]
        let prepared=try AutomaticSurveyLayout.prepare(work,formats:[],catalogue:nil)
        let part=prepared.components[0]
        XCTAssertEqual(part.localLayoutSideIDs?.count,2)
        XCTAssertEqual(part.plans.count,2)
        XCTAssertTrue(part.plans.allSatisfy { $0.layers.count == 2 && $0.layers.allSatisfy { $0.furring == nil } })
        let front=try XCTUnwrap(part.document(for:part.plans[0]))
        let back=try XCTUnwrap(part.document(for:part.plans[1]))
        XCTAssertEqual(back.surface,front.surface.mirroredComponentSide())
        let frontFrame=try XCTUnwrap(front.layers[0].furring)
        let backFrame=try XCTUnwrap(back.layers[0].furring)
        XCTAssertEqual(backFrame.offset, -frontFrame.offset,accuracy:0.001)
        for plan in part.plans {
            let doc=try XCTUnwrap(part.document(for:plan))
            for layer in doc.layers {
                var materialized=layer; materialized.furring=doc.layers[0].furring
                XCTAssertTrue(LayoutPlanning.aligned(materialized))
            }
        }
        XCTAssertEqual(try JSONDecoder().decode(WorkComponentRecord.self,from:JSONEncoder().encode(part)),part)
    }

    func testCutQualityAllowsNarrowAttachedTipButRejectsSeparateSmallPiece() throws {
        let contour: [LayoutPoint] = [.init(x:0,y:0),.init(x:800,y:0),.init(x:800,y:400),
            .init(x:1000,y:400),.init(x:1000,y:500),.init(x:800,y:500),.init(x:800,y:800),.init(x:0,y:800)]
        let surface = Surface2D(name:"Pointe",kind:.wall,contour:contour)
        let layer = LayoutLayer(sheetWidth:1200,sheetLength:2400)
        let result = try SheetLayoutEngine.calculate(surface:surface,layer:layer)
        XCTAssertEqual(result.pieceCount,1)
        XCTAssertTrue(LayoutCutQuality.smallPieces(result).isEmpty)
        let thin = Surface2D(name:"Chute",kind:.wall,contour:[.init(x:0,y:0),.init(x:100,y:0),.init(x:100,y:800),.init(x:0,y:800)])
        XCTAssertEqual(LayoutCutQuality.smallPieces(try SheetLayoutEngine.calculate(surface:thin,layer:layer)).count,1)
    }

    func testOptimizationAvoidsTwentyCentimetreIndependentRemainderAndAlignsFrame() throws {
        let surface = Surface2D(name:"Plafond",kind:.ceiling,contour:LayoutPreset.rectangle.contour(length:2600,height:4800,secondaryHeight:0))
        var layer = LayoutLayer(sheetWidth:1200,sheetLength:2400,furring:.init())
        layer.orientation = .vertical
        XCTAssertFalse(LayoutCutQuality.smallPieces(try SheetLayoutEngine.calculate(surface:surface,layer:layer)).isEmpty)
        let optimized = try LayoutPlanning.optimize(surface:surface,layer:layer,furring:false,alignFraming:true)
        let result = try SheetLayoutEngine.calculate(surface:surface,layer:optimized)
        XCTAssertTrue(LayoutCutQuality.smallPieces(result).isEmpty)
        XCTAssertTrue(LayoutPlanning.aligned(optimized))
        XCTAssertEqual(result.netArea,2600*4800,accuracy:0.1)
    }

    func testAutomaticSurveyPlansPreserveOpeningsAndExistingUserPlan() throws {
        let surface = Surface2D(name:"Mur",kind:.wall,contour:LayoutPreset.rectangle.contour(length:2600,height:2400,secondaryHeight:0),openings:[
            .init(kind:.window,contour:LayoutPreset.rectangle.contour(length:600,height:800,secondaryHeight:0).map { $0 + .init(x:800,y:900) })])
        var c = FurringLiningConfiguration(); c.geometryMode="surface"; c.enteredSurface=5.76
        c.firstSkin=[.init(facingID:"ba13",formatID:"1200x2400",surface:5.76)]
        c.maximumSupportSpacing=1.35; c.selectedSupportLines=1
        var work=WorkItem(id:UUID(),projectID:UUID(),name:"Doublage",type:.peripheralLiningFurrings,payload:.furringLining(c),createdAt:Date(),updatedAt:Date())
        var component=WorkComponentRecord(name:"Mur",surface:surface)
        component.surveySource = .init(surveyID:UUID(),checkpointID:UUID(),surfaceID:UUID(),boundaryIndex:0,kind:.wall,capturedAt:Date())
        work.components=[component]
        let prepared=try AutomaticSurveyLayout.prepare(work,formats:[],catalogue:nil)
        XCTAssertEqual(prepared.components[0].surface,surface)
        XCTAssertEqual(prepared.components[0].plans.count,1)
        let plan=try XCTUnwrap(prepared.components[0].plans.first)
        let document=try XCTUnwrap(prepared.components[0].document(for:plan))
        XCTAssertEqual(document.surface.openings,surface.openings)
        XCTAssertNotNil(document.layers[0].furring)
        work.components=prepared.components
        work.components[0].plans[0].layers[0].offset.x=321
        XCTAssertEqual(try AutomaticSurveyLayout.prepare(work,formats:[],catalogue:nil).components,work.components)
        component.surveySource=nil; work.components=[component]
        XCTAssertTrue(try AutomaticSurveyLayout.prepare(work,formats:[],catalogue:nil).components[0].plans.isEmpty)
    }

    func testFixedLiningEdgesAndHorizontalRowsRespectFormAndRamp() throws {
        let wall=Surface2D(name:"Rampant",kind:.wall,contour:[
            .init(x:0,y:0),.init(x:4000,y:0),.init(x:4000,y:4000),.init(x:0,y:2000)])
        var c=FurringLiningConfiguration()
        c.selectedSupportLines=2; c.maximumSupportSpacing=1.35
        c.firstSupportHeightWhenMultiple=0.6; c.includesHorizontalSupportFurring=true
        var layer=WorkLayoutDefaults.document(surface:wall,configuration:.furringLining(c)).layers[0]
        let result=try LayoutFurringEngine.calculate(surface:wall,layer:layer)
        let fixed=result.wallFixedProfiles
        let left=try XCTUnwrap(fixed.first { $0.role == .leftFurring })
        let right=try XCTUnwrap(fixed.first { $0.role == .rightAngle })
        XCTAssertEqual(left.line.start.x,120,accuracy:0.001)
        XCTAssertEqual(left.line.end.y,2060,accuracy:0.001)
        XCTAssertEqual(right.line.start.x,3880,accuracy:0.001)
        let rows=fixed.filter { $0.role == .supportHorizontal }.map(\.line)
        XCTAssertEqual(rows.count,2)
        XCTAssertEqual(rows[0].start.y,600,accuracy:0.001)
        XCTAssertEqual(rows[0].start.x,0,accuracy:0.001)
        XCTAssertEqual(rows[1].start.y,1950,accuracy:0.001)
        XCTAssertEqual(rows[1].start.x,1400,accuracy:0.001,"Extra row begins where wall exceeds 2 × 1.35 m")
        XCTAssertTrue(result.supportPoints.allSatisfy { p in rows.contains { LayoutGeometry.distance(p,to:$0.start,$0.end)<0.01 } })
        layer.furring?.offset=120
        let moved=try LayoutFurringEngine.calculate(surface:wall,layer:layer)
        XCTAssertEqual(moved.wallFixedProfiles,fixed)
        XCTAssertEqual(moved.lines.filter { abs($0.start.x-120)<0.01 && abs($0.end.x-120)<0.01 }.count,1)
        c.includesHorizontalSupportFurring=false
        layer=WorkLayoutDefaults.document(surface:wall,configuration:.furringLining(c)).layers[0]
        let without=try LayoutFurringEngine.calculate(surface:wall,layer:layer)
        XCTAssertTrue(without.wallFixedProfiles.allSatisfy { $0.role != .supportHorizontal })
        XCTAssertEqual(without.wallFixedProfiles.count,2)
        XCTAssertEqual(without.supportPoints,result.supportPoints)
        let roundTrip=try JSONDecoder().decode(FurringLiningConfiguration.self,from:JSONEncoder().encode(c))
        XCTAssertEqual(roundTrip.maximumSupportSpacing,1.35)
        XCTAssertEqual(roundTrip.includesHorizontalSupportFurring,false)
    }

    func testHorizontalSupportRowsAreCutByOpenings() throws {
        var c=FurringLiningConfiguration(); c.maximumSupportSpacing=1.35
        c.includesHorizontalSupportFurring=true
        let wall=openingWall()
        let layer=WorkLayoutDefaults.document(surface:wall,configuration:.furringLining(c)).layers[0]
        let geometry=LayoutPlanning.worldFurring(surface:wall,layer:layer)
        let rows=geometry.wallFixedProfiles.filter { $0.role == .supportHorizontal }.map(\.line)
        XCTAssertEqual(rows.count,2)
        XCTAssertEqual(rows.map { $0.start.x },[0,2000])
        XCTAssertEqual(rows.map { $0.end.x },[1000,4000])
        XCTAssertEqual(rows.map { $0.start.y },[1350,1350])
    }

    func testSplicesCountContinuousThreeMetreLengthsNotOpeningsOrAngles() {
        for (length,count) in [(0.0,0),(3000,0),(3001,1),(6000,1),(6001,2),(9000,2),(9001,3)] {
            XCTAssertEqual(LayoutFurringEngine.splices(lengthMM:length),count)
        }
        let a=LayoutJoint(start:.init(x:0,y:0),end:.init(x:0,y:2500))
        let touching=LayoutJoint(start:a.end,end:.init(x:0,y:5000))
        let separated=LayoutJoint(start:.init(x:0,y:3000),end:.init(x:0,y:5500))
        XCTAssertEqual(LayoutFurringResult(lines:[a,touching]).furringSpliceCount,1)
        XCTAssertEqual(LayoutFurringResult(lines:[a,separated]).furringSpliceCount,0)
        let angle=LayoutJoint(start:.init(x:100,y:0),end:.init(x:100,y:7000))
        let result=LayoutFurringResult(lines:[a,touching,angle],wallFixedProfiles:[.init(line:angle,role:.rightAngle)])
        XCTAssertEqual(result.furringSpliceCount,1)
    }

    func testCalageMovesTheOtherLayerAndPreservesFixedProfiles() throws {
        let wall=openingWall()
        var layer=WorkLayoutDefaults.document(surface:wall,configuration:.furringLining(.init())).layers[0]
        layer.offset.x=1320; layer.furring?.offset=50
        let fixed=LayoutPlanning.worldFurring(surface:wall,layer:layer).wallFixedProfiles
        let boards=LayoutPlanning.alignOtherLayer(layer,surface:wall,framingMode:true)
        XCTAssertEqual(boards.furring,layer.furring)
        XCTAssertNotEqual(boards.offset,layer.offset)
        let framing=LayoutPlanning.alignOtherLayer(layer,surface:wall,framingMode:false)
        XCTAssertEqual(framing.offset,layer.offset)
        XCTAssertNotEqual(framing.furring?.offset,layer.furring?.offset)
        XCTAssertEqual(LayoutPlanning.worldFurring(surface:wall,layer:framing).wallFixedProfiles,fixed)
    }

    func testRepeatedLengthLabelsChooseOneVisibleRepresentativePerDirection() {
        let lines: [LayoutJoint] = [
            .init(start:.init(x:0,y:0),end:.init(x:0,y:3000)),
            .init(start:.init(x:600,y:3000),end:.init(x:600,y:0)),
            .init(start:.init(x:1200,y:0),end:.init(x:1200,y:3000)),
            .init(start:.init(x:0,y:0),end:.init(x:3000,y:0)),
            .init(start:.init(x:1800,y:0),end:.init(x:1800,y:2500))]
        XCTAssertEqual(LayoutDimensionLabels.representatives(lines,preferred:Set(lines.indices)),[0,3,4])
        XCTAssertEqual(LayoutDimensionLabels.representatives(lines,preferred:[1,2]),[1])
        XCTAssertTrue(LayoutDimensionLabels.representatives(lines,preferred:[]).isEmpty)
    }
    private func openingWall(_ kind: LayoutOpeningKind = .window) -> Surface2D {
        Surface2D(name:"Mur",kind:.wall,
            contour:LayoutPreset.rectangle.contour(length:4000,height:2600,secondaryHeight:0),
            openings:[.init(kind:kind,contour:[.init(x:1000,y:kind == .window ? 800 : 0),.init(x:2000,y:kind == .window ? 800 : 0),.init(x:2000,y:2000),.init(x:1000,y:2000)])])
    }
    func testFixedOpeningProfilesAtFiveCentimetresAndShortFurrings() throws {
        let wall=openingWall()
        var c=FurringLiningConfiguration(); c.selectedSupportLines=2; c.furringSpacing=0.6
        var layer=WorkLayoutDefaults.document(surface:wall,configuration:.furringLining(c)).layers[0]
        let first=try LayoutFurringEngine.calculate(surface:wall,layer:layer)
        XCTAssertEqual(first.openingProfiles.count,8)
        let sides=first.openingProfiles.filter { $0.role == .side }
        XCTAssertEqual(sides.map { $0.line.start.x }.sorted(),[950,2050])
        XCTAssertEqual(first.openingProfiles.filter { $0.role == .horizontal }.map { $0.line.start.y }.sorted(),[750,2050])
        XCTAssertEqual(Set(first.openingProfiles.filter { $0.role == .shortVertical }.map { $0.line.start.x }),[1050,1950])
        XCTAssertFalse(first.supportPoints.isEmpty)
        layer.furring?.offset=123
        let moved=try LayoutFurringEngine.calculate(surface:wall,layer:layer)
        XCTAssertEqual(first.openingProfiles,moved.openingProfiles)
        XCTAssertNotEqual(first.lines,moved.lines)
        let restored=try JSONDecoder().decode(LayoutLayer.self,from:JSONEncoder().encode(layer))
        XCTAssertEqual(restored.furring?.intermediateSupportLines,2)
    }
    func testDoorHasNoSillAndStudsHaveNoExtraShortFurrings() {
        let f=LayoutOpeningFraming.profiles(surface:openingWall(.door),system:.furring)
        XCTAssertEqual(f.filter { $0.role == .horizontal }.count,1)
        XCTAssertEqual(f.filter { $0.role == .shortVertical }.count,2)
        let studs=LayoutOpeningFraming.profiles(surface:openingWall(),system:.studs)
        XCTAssertEqual(studs.count,4)
        XCTAssertTrue(studs.allSatisfy { $0.role != .shortVertical })
    }
    func testMovingFrameSnapsAndMergesIntoOpeningSide() throws {
        let wall=openingWall()
        var layer=WorkLayoutDefaults.document(surface:wall,configuration:.furringLining(.init())).layers[0]
        layer.furring?.spacing=600; layer.furring?.offset=345
        let offset=try XCTUnwrap(LayoutPlanning.snappedOpeningSupport(layer,surface:wall,tolerance:10))
        layer.furring?.offset=offset
        XCTAssertEqual(layer.furring?.offset,350)
        let result=try LayoutFurringEngine.calculate(surface:wall,layer:layer)
        let left=result.lines.filter { abs($0.start.x-950)<0.5 && abs($0.end.x-950)<0.5 }
        XCTAssertEqual(left.count,1)
        XCTAssertEqual((left[0].end-left[0].start).length,2600,accuracy:0.001)
    }
    func testPlateSnapUsesNearestRegularLineNotOpeningReinforcement() throws {
        let wall=openingWall()
        var layer=WorkLayoutDefaults.document(surface:wall,configuration:.furringLining(.init())).layers[0]
        layer.furring?.spacing=600; layer.furring?.offset=0
        layer.offset.x=949
        XCTAssertEqual(LayoutPlanning.snappedWallBoards(layer,surface:wall,tolerance:10).offset.x,949)
        layer.offset.x=1194
        XCTAssertEqual(LayoutPlanning.snappedWallBoards(layer,surface:wall,tolerance:10).offset.x,1200,accuracy:0.001)
        layer.offset.x=1320
        XCTAssertEqual(LayoutPlanning.alignBoards(to:layer,support:.wall).offset.x,1200,accuracy:0.001)
    }
    func testCeilingStartsLandscapeUsingReferenceWhenSuitable() throws {
        let frame=LayoutGridFrame(origin:.init(x:850,y:730),angle:0.63)
        let contour=LayoutPreset.rectangle.contour(length:6000,height:2500,secondaryHeight:0).map(frame.world)
        let initial=try XCTUnwrap(LayoutViewport.initialCeilingAlignment(contour,referenceEdge:0))
        XCTAssertEqual(initial.index,0)
        let bounds=LayoutBounds(points:contour.map { LayoutViewport.rotated($0,by:initial.angle) })
        XCTAssertEqual(bounds.width,6000,accuracy:0.001)
        XCTAssertEqual(bounds.height,2500,accuracy:0.001)
        let shortReference=try XCTUnwrap(LayoutViewport.initialCeilingAlignment(contour,referenceEdge:1))
        let wide=LayoutBounds(points:contour.map { LayoutViewport.rotated($0,by:shortReference.angle) })
        XCTAssertGreaterThan(wide.width,wide.height)
        // The following user-controlled step follows the contour, not the board reference.
        XCTAssertEqual(LayoutViewport.nextHorizontalEdge(contour,after:initial.index)?.index,1)
        XCTAssertNil(LayoutViewport.initialCeilingAlignment([],referenceEdge:0))
    }

    func testViewCyclesCeilingEdgesWithoutChangingScaleOrGeometry() throws {
        let contour:[LayoutPoint] = [.init(x:100,y:200),.init(x:4600,y:500),.init(x:4100,y:3200),.init(x:0,y:2800)]
        let pivot = LayoutViewport.geometricCenter(contour)
        let base = LayoutViewport(bounds:LayoutViewport.fittedBounds(contour,rotation:0,pivot:pivot),size:.init(width:390,height:600),zoom:2.4,pan:.init(width:12,height:25),pivot:pivot)
        var index:Int?
        for expected in [0,1,2,3,0] {
            let next = try XCTUnwrap(LayoutViewport.nextHorizontalEdge(contour,after:index))
            XCTAssertEqual(next.index,expected)
            index = next.index
            for mirrored in [false,true] {
                var view = base; view.rotation = next.angle; view.mirrored = mirrored
                let a = view.screen(contour[next.index]), b = view.screen(contour[(next.index+1)%contour.count])
                XCTAssertEqual(a.y,b.y,accuracy:0.000001)
                XCTAssertEqual(view.scale,base.scale)
                XCTAssertEqual(view.screen(pivot).y,base.screen(pivot).y,accuracy:0.000001)
                let back=view.world(a)
                XCTAssertEqual(back.x,contour[next.index].x,accuracy:0.000001)
                XCTAssertEqual(back.y,contour[next.index].y,accuracy:0.000001)
            }
        }
        XCTAssertNil(LayoutViewport.nextHorizontalEdge([],after:nil))
        XCTAssertEqual(LayoutViewport.nextHorizontalEdge([.init(x:0,y:0),.init(x:0,y:0),.init(x:100,y:0),.init(x:100,y:100)],after:nil)?.index,1)
        XCTAssertEqual(LayoutViewport.nextHorizontalEdge(contour,after:99)?.index,0)
    }

    func testRailStudInsulationReadsPublishedConductivity() throws {
        let json = #"{"id":"glass","kind":"insulation_series","title":"Laine de verre","summary":"","sourcePage":1,"status":"Publié","data":{"material":"Laine de verre","conductivity":"λ ≈ 0,035","values":[{"thickness_mm":100,"max_weight_kg_m2":2},{"thickness_mm":200,"max_weight_kg_m2":4}]}}"#
        var record = try JSONDecoder().decode(CeilingReferenceRecord.self,from:Data(json.utf8))
        let series = try XCTUnwrap(LabInsulationSeries.decode(record))
        XCTAssertEqual(series.lambda,0.035,accuracy:0.000001)
        XCTAssertEqual(series.thicknesses,[100,200])
        XCTAssertEqual(series.weight(for:200),4,accuracy:0.000001)
        XCTAssertEqual(series.resistance(for:100),0.1/0.035,accuracy:0.000001)
        record = try JSONDecoder().decode(CeilingReferenceRecord.self,from:Data(json.replacingOccurrences(of:"\"conductivity\":\"λ ≈ 0,035\"",with:"\"lambda_w_mk\":0.032").utf8))
        XCTAssertEqual(try XCTUnwrap(LabInsulationSeries.decode(record)).lambda,0.032)
        record = try JSONDecoder().decode(CeilingReferenceRecord.self,from:Data(json.replacingOccurrences(of:"λ ≈ 0,035",with:"non renseigné").utf8))
        XCTAssertNil(LabInsulationSeries.decode(record))
    }

    func testFirstRailStudCeilingLayoutReusesExplicitWorkDimensions() throws {
        var configuration = RailStudCeilingConfiguration()
        configuration.length = 5.3; configuration.width = 3.7
        configuration.firstSkin = [.init(productID:"board",dimensionID:"1200x2400",area:19.61)]
        let component = WorkLayoutDefaults.firstComponent(name:"Plafond A",configuration:.railStudCeiling(configuration))
        let document = try XCTUnwrap(component.initialDocument(sideRoomID:nil,configuration:.railStudCeiling(configuration)))
        XCTAssertEqual(document.surface.bounds.width,5300,accuracy:0.001)
        XCTAssertEqual(document.surface.bounds.height,3700,accuracy:0.001)
        XCTAssertEqual(document.layers[0].sheetLength,2400)
        XCTAssertEqual(document.layers[0].furring?.spacing,600)
        configuration.dimensionsSpecified = false; configuration.area = 19.61
        XCTAssertNil(WorkLayoutDefaults.firstComponent(name:"Plafond A",configuration:.railStudCeiling(configuration)).surface)
        configuration.dimensionsSpecified = true; configuration.width = .nan
        XCTAssertNil(WorkLayoutDefaults.firstComponent(name:"Plafond A",configuration:.railStudCeiling(configuration)).surface)
    }

    func testPeripheralFurringsStayAtTenCentimetresWhileGridMoves() throws {
        let surface=offcutCeiling(3600,4800)
        var layer=offcutLayer; layer.referenceEdge=0
        layer.furring?.orientation = .horizontal
        layer.furring?.peripheralInset=100
        let first=LayoutPlanning.worldFurring(surface:surface,layer:layer)
        layer.furring?.offset=170
        let moved=LayoutPlanning.worldFurring(surface:surface,layer:layer)
        XCTAssertEqual(first.peripheralLines,moved.peripheralLines)
        XCTAssertEqual(first.peripheralLines.count,2)
        XCTAssertEqual(first.peripheralLines.map{$0.start.y}.sorted(),[100,4700])
        XCTAssertNotEqual(first.lines,moved.lines)
        XCTAssertTrue(moved.peripheralLines.allSatisfy { moved.lines.contains($0) })
        layer.furring?.offset=100
        let coincident=LayoutPlanning.worldFurring(surface:surface,layer:layer)
        for fixed in coincident.peripheralLines { XCTAssertEqual(coincident.lines.filter{$0 == fixed}.count,1) }
        XCTAssertEqual(try JSONDecoder().decode(LayoutLayer.self,from:JSONEncoder().encode(layer)),layer)
    }

    func testPeripheralFurringsRotateWithTheirOwnReferenceAndStopAtOpenings() throws {
        var surface=offcutCeiling(3600,4800)
        surface.openings=[.init(kind:.stairwell,contour:LayoutBounds(min:.init(x:1500,y:50),max:.init(x:2100,y:400)).polygon)]
        var layer=offcutLayer; layer.referenceEdge=0
        layer.furring?.orientation = .horizontal; layer.furring?.peripheralInset=100
        let result=LayoutPlanning.worldFurring(surface:surface,layer:layer)
        XCTAssertEqual(result.peripheralLines.count,3)
        XCTAssertFalse(result.lines.contains { LayoutGeometry.contains(($0.start+$0.end)*0.5,in:surface.openings[0].contour) })
        layer.furring?.usesOwnReference=true; layer.furring?.referenceEdge=1
        let own=LayoutPlanning.worldFurring(surface:surface,layer:layer)
        XCTAssertEqual(own.peripheralLines.count,2)
        for line in own.peripheralLines { XCTAssertEqual(line.start.x,line.end.x,accuracy:0.001) }
    }

    func testNoPerimeterSupportFlowsFromFormEvenForExistingManualFacingPlan() {
        var c=CeilingConfiguration(); c.perimeterSupport=false
        let doc=WorkLayoutDefaults.document(surface:offcutCeiling(),configuration:.ceiling(c))
        XCTAssertEqual(doc.layers[0].furring?.peripheralInset,100)
        var manual=offcutLayer; manual.manualFacing=true
        XCTAssertEqual(WorkLayoutDefaults.resolvingFacing(manual,configuration:.ceiling(c),formats:[]).furring?.peripheralInset,100)
        c.perimeterSupport=true
        XCTAssertNil(WorkLayoutDefaults.resolvingSupport(doc.layers[0],configuration:.ceiling(c)).furring?.peripheralInset)
    }

    func testManualWallDistanceShiftsGridAndPreservesSpacingAndFixedSupports() throws {
        let surface=offcutCeiling(3600,4800)
        for orientation in [LayoutOrientation.horizontal,.vertical] {
            var layer=offcutLayer; layer.referenceEdge=0
            layer.furring?.orientation=orientation; layer.furring?.peripheralInset=100
            let before=LayoutPlanning.worldFurring(surface:surface,layer:layer)
            let line=try XCTUnwrap(before.lines.first { !before.peripheralLines.contains($0) })
            let dimension=try XCTUnwrap(LayoutPlanning.framingWallDimensions(line,surface:surface).min(by:{$0.distance<$1.distance}))
            let edited=try LayoutPlanning.settingFurringDistance(layer,surface:surface,dimension:dimension,distance:750)
            let after=LayoutPlanning.worldFurring(surface:surface,layer:edited)
            XCTAssertEqual(edited.furring?.spacing,layer.furring?.spacing)
            XCTAssertEqual(after.peripheralLines,before.peripheralLines)
            XCTAssertTrue(after.lines.flatMap{LayoutPlanning.framingWallDimensions($0,surface:surface)}.contains{abs($0.distance-750)<0.001})
            XCTAssertThrowsError(try LayoutPlanning.settingFurringDistance(layer,surface:surface,dimension:dimension,distance:-10))
        }
    }

    func testFurringSnapRespectsIndependentReference() throws {
        let surface=offcutCeiling(3600,4800)
        var layer=offcutLayer; layer.referenceEdge=0
        layer.furring?.orientation = .horizontal; layer.furring?.offset=14
        let joint=LayoutJoint(start:.init(x:0,y:1200),end:.init(x:3600,y:1200))
        XCTAssertEqual(try XCTUnwrap(LayoutPlanning.snappedFurringOffset(layer,surface:surface,joints:[joint],tolerance:20)),0,accuracy:0.001)
        XCTAssertNil(LayoutPlanning.snappedFurringOffset(layer,surface:surface,joints:[joint],tolerance:5))
        layer.furring?.usesOwnReference=true; layer.furring?.referenceEdge=1
        XCTAssertNil(LayoutPlanning.snappedFurringOffset(layer,surface:surface,joints:[joint],tolerance:20))
    }

    func testAutomaticLightingUsesFurringFrameWithExactGridAndNinetyDegreeSwitch() throws {
        var surface=offcutCeiling(6000,4800)
        let rotation=LayoutGridFrame(origin:.init(x:2000,y:-1000),angle:0.43)
        surface.contour=surface.contour.map(rotation.world)
        var layer=offcutLayer; layer.referenceEdge=0
        layer.furring?.orientation = .horizontal
        XCTAssertEqual(LayoutPlanning.automaticSpotCounts,[1,2,3,4,6,8,9,10,12])
        XCTAssertNil(LayoutPlanning.spotPattern(5))
        XCTAssertNil(LayoutPlanning.spotPattern(7))
        XCTAssertNil(LayoutPlanning.spotPattern(11))
        for count in LayoutPlanning.automaticSpotCounts {
            for perpendicular in [false,true] {
                var settings=LayoutLighting(count:count,spread:0.6)
                settings.perpendicularToFurring=perpendicular
                let result=try LayoutPlanning.lighting(settings,surface:surface,layer:layer)
                XCTAssertEqual(result.positions.count,count)
                XCTAssertTrue(LayoutPlanning.lightingFits(result,surface:surface))
                var frame=LayoutPlanning.framingFrame(surface:surface,layer:layer)
                if perpendicular { frame.angle += .pi/2 }
                let grid=try XCTUnwrap(LayoutPlanning.spotGrid(count))
                let local=result.positions.map(frame.local)
                XCTAssertEqual(Set(local.map { Int($0.x.rounded()) }).count,grid.columns)
                XCTAssertEqual(Set(local.map { Int($0.y.rounded()) }).count,grid.rows)
                XCTAssertEqual(result.diameter,68)
            }
        }
    }

    func testTwelveSpotGridsKeepTheirRowsColumnsAndEqualIntervals() throws {
        let surface=offcutCeiling(8000,6000)
        var layer=offcutLayer; layer.referenceEdge=0; layer.furring?.orientation = .horizontal
        for grid in LayoutTwelveSpotGrid.allCases {
            for perpendicular in [false,true] {
                var settings=LayoutLighting(count:12,spread:0.6)
                settings.twelveSpotGrid=grid; settings.perpendicularToFurring=perpendicular
                let lighting=try LayoutPlanning.lighting(settings,surface:surface,layer:layer)
                var frame=LayoutPlanning.framingFrame(surface:surface,layer:layer)
                if perpendicular { frame.angle += .pi/2 }
                let points=lighting.positions.map(frame.local)
                XCTAssertEqual(points.count,12)
                XCTAssertEqual(Set(points.map { Int($0.x.rounded()) }).count,grid.columns)
                XCTAssertEqual(Set(points.map { Int($0.y.rounded()) }).count,grid.rows)
                for row in 0..<grid.rows {
                    for column in 1..<grid.columns {
                        let i=row*grid.columns+column
                        XCTAssertEqual(points[i].x-points[i-1].x,points[1].x-points[0].x,accuracy:0.001)
                        XCTAssertEqual(points[i].y,points[i-1].y,accuracy:0.001)
                    }
                }
                XCTAssertTrue(LayoutPlanning.lightingFits(lighting,surface:surface))
                XCTAssertEqual(try JSONDecoder().decode(LayoutLighting.self,from:JSONEncoder().encode(lighting)),lighting)
            }
        }
    }

    func testGeneratedLightingSpreadChangesEachFramingAxisIndependently() throws {
        var surface=offcutCeiling(7000,5000)
        let rotation=LayoutGridFrame(origin:.init(x:500,y:-1000),angle:0.37)
        surface.contour=surface.contour.map(rotation.world)
        var layer=offcutLayer; layer.referenceEdge=0; layer.furring?.orientation = .horizontal
        for count in [4,6,8,9,10,12] {
            for perpendicular in [false,true] {
                var settings=LayoutLighting(count:count,spread:0.5)
                settings.perpendicularToFurring=perpendicular
                var frame=LayoutPlanning.framingFrame(surface:surface,layer:layer)
                if perpendicular { frame.angle += .pi/2 }
                let original=try LayoutPlanning.lighting(settings,surface:surface,layer:layer).positions.map(frame.local)
                settings.widthSpread=0.8
                let wider=try LayoutPlanning.lighting(settings,surface:surface,layer:layer).positions.map(frame.local)
                settings.lengthSpread=0.7
                let longer=try LayoutPlanning.lighting(settings,surface:surface,layer:layer).positions.map(frame.local)
                for i in original.indices {
                    XCTAssertEqual(wider[i].y,original[i].y,accuracy:0.001)
                    XCTAssertEqual(longer[i].x,wider[i].x,accuracy:0.001)
                }
                XCTAssertEqual(LayoutBounds(points:wider).width/LayoutBounds(points:original).width,1.6,accuracy:0.001)
                XCTAssertEqual(LayoutBounds(points:longer).height/LayoutBounds(points:wider).height,1.4,accuracy:0.001)
            }
        }
    }

    func testAxisSpacingAndQuarterTurnPreserveManualPositionsAndCenter() throws {
        let frame=LayoutGridFrame(origin:.init(x:2000,y:2000),angle:0.41)
        let positions=[LayoutPoint(x:-700,y:-600),.init(x:650,y:-500),.init(x:800,y:550),.init(x:-750,y:550)]
        var original=LayoutLighting(count:4,spread:0.5,positions:positions.map(frame.world))
        original.kinds=[.light,.socket,.light,.light]
        var settings=original; settings.widthSpread=0.75; settings.lengthSpread=0.3
        let adjusted=LayoutPlanning.adjustedLighting(original,from:original,to:settings,frame:frame)
        for i in positions.indices {
            let point=frame.local(adjusted.positions[i])
            XCTAssertEqual(point.x,positions[i].x*1.5,accuracy:0.001)
            XCTAssertEqual(point.y,positions[i].y*0.6,accuracy:0.001)
        }
        var turnedSettings=settings; turnedSettings.perpendicularToFurring=true
        let turned=LayoutPlanning.adjustedLighting(adjusted,from:settings,to:turnedSettings,frame:frame)
        let expected=LayoutPlanning.rotatedLighting(adjusted,selected:Set(positions.indices),angle:.pi/2)
        for i in positions.indices { XCTAssertEqual((turned.positions[i]-expected.positions[i]).length,0,accuracy:0.001) }
        let restored=LayoutPlanning.adjustedLighting(turned,from:turnedSettings,to:original,frame:frame)
        for i in positions.indices { XCTAssertEqual((restored.positions[i]-original.positions[i]).length,0,accuracy:0.001) }
        XCTAssertEqual(restored.kinds,original.kinds)
        XCTAssertEqual(try JSONDecoder().decode(LayoutLighting.self,from:JSONEncoder().encode(turned)),turned)
        let subset=LayoutPlanning.scaledLighting(original,selected:[0,1,2],widthFactor:1.2,lengthFactor:0.8,frame:frame)
        XCTAssertEqual(subset.positions[3],original.positions[3])
        let before=original.positions.prefix(3).reduce(LayoutPoint.zero,+)
        let after=subset.positions.prefix(3).reduce(LayoutPoint.zero,+)
        XCTAssertEqual((before-after).length,0,accuracy:0.001)
    }

    func testLegacyManualLightingLoadsWithoutRegenerationOrNewSettings() throws {
        let data=Data("{\"count\":3,\"spread\":0.65,\"diameter\":75,\"dicePattern\":true,\"positions\":[{\"x\":500,\"y\":700},{\"x\":1100,\"y\":1500},{\"x\":1900,\"y\":2100}]}".utf8)
        let saved=try JSONDecoder().decode(LayoutLighting.self,from:data)
        XCTAssertEqual(saved.resolvedWidthSpread,0.65)
        XCTAssertEqual(saved.resolvedLengthSpread,0.65)
        XCTAssertNil(saved.twelveSpotGrid)
        XCTAssertNil(saved.widthSpread)
        XCTAssertNil(saved.lengthSpread)
        XCTAssertEqual(LayoutPlanning.adjustedLighting(saved,from:saved,to:saved,frame:.init(angle:0.4)),saved)
        XCTAssertEqual(try JSONDecoder().decode(LayoutLighting.self,from:JSONEncoder().encode(saved)),saved)
        let surface=offcutCeiling(5000,4000)
        let added=try LayoutPlanning.addingSpot(to:saved,at:.init(x:3000,y:1800),surface:surface)
        XCTAssertEqual(Array(added.positions.prefix(3)),saved.positions)
        XCTAssertEqual(added.diameter,75)
        XCTAssertEqual(added.count,4)
        for count in [5,11] {
            let manual=LayoutLighting(count:count,positions:(0..<count).map { .init(x:500+Double($0)*300,y:900) })
            let decoded=try JSONDecoder().decode(LayoutLighting.self,from:JSONEncoder().encode(manual))
            XCTAssertEqual(decoded,manual)
            XCTAssertTrue(LayoutPlanning.lightingFits(decoded,surface:surface))
            XCTAssertEqual(LayoutPlanning.adjustedLighting(decoded,from:decoded,to:decoded,frame:.init()),manual)
        }
    }

    func testAutomaticLightingRejectsInvalidAxesAndUnusableSurface() throws {
        let surface=offcutCeiling(5000,4000)
        var settings=LayoutLighting()
        settings.widthSpread = .nan
        XCTAssertThrowsError(try LayoutPlanning.lighting(settings,surface:surface))
        settings.widthSpread=0.5; settings.lengthSpread=0
        XCTAssertThrowsError(try LayoutPlanning.lighting(settings,surface:surface))
        settings.lengthSpread=0.5
        XCTAssertThrowsError(try LayoutPlanning.lighting(settings,surface:offcutCeiling(50,50)))
    }

    func testLightingAlignmentUsesFurringAxesAndKeepsOtherSpotsUntouched() throws {
        let surface=offcutCeiling(6000,4800)
        let frame=LayoutGridFrame(origin:.init(x:2000,y:2000),angle:0.4)
        let lighting=LayoutLighting(count:4,positions:[.init(x:0,y:0),.init(x:500,y:100),.init(x:1300,y:-100),.init(x:1000,y:1000)].map(frame.world))
        let aligned=try LayoutPlanning.arrangedLighting(lighting,selected:[0,1,2],reference:1,action:.horizontal,surface:surface,frame:frame)
        for i in 0...2 { XCTAssertEqual(frame.local(aligned.positions[i]).y,100,accuracy:0.001) }
        XCTAssertEqual(aligned.positions[3],lighting.positions[3])
        let spaced=try LayoutPlanning.arrangedLighting(aligned,selected:[0,1,2],reference:nil,action:.distributeX,surface:surface,frame:frame)
        XCTAssertEqual(frame.local(spaced.positions[1]).x,650,accuracy:0.001)
    }

    func testDimensionDisplayRoundsOnlyTextToOneDecimal() {
        XCTAssertEqual(layoutCM(1234.56),"123,5 cm")
        XCTAssertEqual(layoutCM(1200),"120 cm")
    }

    func testBelowCeilingCameraIsInvertibleAndKeepsScale() {
        let ceiling=offcutCeiling()
        let top=LayoutViewport(bounds:ceiling.bounds,size:.init(width:390,height:700),zoom:2.3,pan:.init(width:21,height:-32))
        var bottom=top; bottom.mirrored=true
        XCTAssertEqual(top.scale,bottom.scale)
        for p in ceiling.contour + [.init(x:700,y:900)] {
            let restored=bottom.world(bottom.screen(p))
            XCTAssertEqual(restored.x,p.x,accuracy:0.00001)
            XCTAssertEqual(restored.y,p.y,accuracy:0.00001)
        }
        XCTAssertEqual(bottom.worldDelta(.init(width:42,height:0)).x,-top.worldDelta(.init(width:42,height:0)).x,accuracy:0.00001)
        let pan=bottom.constrainedPan(.init(width:100_000,height:-100_000),contour:ceiling.contour)
        let bounded=LayoutViewport(bounds:ceiling.bounds,size:bottom.size,zoom:bottom.zoom,pan:pan,mirrored:true)
        let points=ceiling.contour.map(bounded.screen)
        XCTAssertLessThanOrEqual(points.map(\.x).min()!,bottom.size.width-49)
        XCTAssertGreaterThanOrEqual(points.map(\.y).max()!,49)
    }

    func testSupportHitTestIgnoresOutsideAndOpenings() {
        var ceiling=offcutCeiling()
        ceiling.openings=[.init(kind:.other,contour:LayoutBounds(min:.init(x:500,y:500),max:.init(x:1000,y:1000)).polygon)]
        XCTAssertTrue(LayoutPlanning.hitSupport(.init(x:200,y:200),surface:ceiling))
        XCTAssertFalse(LayoutPlanning.hitSupport(.init(x:-200,y:200),surface:ceiling))
        XCTAssertFalse(LayoutPlanning.hitSupport(.init(x:700,y:700),surface:ceiling))
    }

    func testIndependentFramingDoesNotTurnWhenBoardReferenceChanges() throws {
        let ceiling=offcutCeiling(3600,4800)
        var first=offcutLayer; first.referenceEdge=0
        first.furring?.orientation = .horizontal
        first.furring?.referenceEdge=0; first.furring?.usesOwnReference=true
        first.furring?.offset=80
        var second=first; second.referenceEdge=1
        let a=try SheetLayoutEngine.calculate(surface:ceiling,layer:first)
        let b=try SheetLayoutEngine.calculate(surface:ceiling,layer:second)
        func endpoints(_ r:SheetLayoutResult) -> [LayoutPoint] {
            r.furring.lines.flatMap { [r.frame.world($0.start),r.frame.world($0.end)] }
        }
        let pointsA=endpoints(a),pointsB=endpoints(b)
        XCTAssertEqual(pointsA.count,pointsB.count)
        for p in pointsA { XCTAssertTrue(pointsB.contains { ($0-p).length<0.01 }) }
        let optimized=try LayoutPlanning.optimize(surface:ceiling,layer:second,furring:true)
        XCTAssertEqual(optimized.offset,second.offset)
        XCTAssertEqual(optimized.referenceEdge,second.referenceEdge)
        XCTAssertEqual(optimized.furring?.referenceEdge,0)
    }

    func testJunctionEmphasisAndFacingWallDimensions() {
        let room=offcutCeiling(2400,3000)
        let line=LayoutJoint(start:.init(x:0,y:1200),end:.init(x:2400,y:1200))
        XCTAssertTrue(LayoutPlanning.isJunction(line,joints:[.init(start:.init(x:500,y:1200),end:.init(x:1800,y:1200))]))
        XCTAssertFalse(LayoutPlanning.isJunction(line,joints:[.init(start:.init(x:500,y:1300),end:.init(x:1800,y:1300))]))
        let distances=LayoutPlanning.framingWallDimensions(line,surface:room).map { ($0.end-$0.start).length }.sorted()
        XCTAssertEqual(distances,[1200,1800])
    }

    private func quantityWork(peripheral:Bool=true) -> WorkItem {
        let room=offcutCeiling(2400,3600),layer=offcutLayer
        var component=WorkComponentRecord(name:"Salon",surface:room)
        component.framing=layer.furring
        component.plans=[.init(layers:[layer])]
        var c=CeilingConfiguration(length:2.4,width:3.6); c.perimeterSupport=peripheral
        var work=WorkItem(id:UUID(),projectID:UUID(),name:"Plafond",type:.ceilingOnFurring,configuration:c,createdAt:Date(),updatedAt:Date())
        work.components=[component]
        return work
    }

    func testLayoutQuantityMarginsAndPeripheralSupports() throws {
        let supported=quantityWork(),free=quantityWork(peripheral:false)
        let a=try LayoutQuantityCalculator.make(work:supported,formats:[])
        let b=try LayoutQuantityCalculator.make(work:free,formats:[])
        let document=try XCTUnwrap(supported.components[0].document(for:supported.components[0].plans[0]))
        let result=try SheetLayoutEngine.calculate(surface:document.surface,layer:document.layers[0])
        XCTAssertEqual(a.boards[0].quantity,ceil(Double(result.purchasedSheetCount)*1.1))
        XCTAssertEqual(a.area,8.64,accuracy:0.0001)
        XCTAssertEqual(a.perimeterMeters,12*1.1,accuracy:0.0001)
        XCTAssertEqual(b.perimeterMeters,0)
        XCTAssertEqual(b.hangers-a.hangers,2*result.furring.lines.count)
        XCTAssertEqual(a.framingMeters,result.furring.lines.reduce(0) { $0+($1.end-$1.start).length/1000 }*1.1,accuracy:0.0001)
        var form=CeilingConfiguration(length:4,width:3); form.perimeterSupport=false
        XCTAssertEqual(LayoutQuantityCalculator.estimatedAdditionalEndHangers(form),12)
        form.perimeterSupport=true
        XCTAssertEqual(LayoutQuantityCalculator.estimatedAdditionalEndHangers(form),0)
    }

    func testSpliceTakeoffReplacesOnlyCoveredSurfaceEstimateAndSurvivesSave() throws {
        var work=quantityWork()
        var configuration=try XCTUnwrap(work.ceilingConfiguration)
        // One planned part covers half of the ouvrage.
        configuration.enteredArea=17.28
        work.payload = .ceiling(configuration)
        let takeoff=try LayoutQuantityCalculator.make(work:work,formats:[])
        let document=try XCTUnwrap(work.components[0].document(for:work.components[0].plans[0]))
        let calculated=try SheetLayoutEngine.calculate(surface:document.surface,layer:document.layers[0])
        XCTAssertEqual(takeoff.furringSplices,calculated.furring.furringSpliceCount)
        XCTAssertEqual(takeoff.framingCoverage,0.5,accuracy:0.001)
        XCTAssertEqual(try JSONDecoder().decode(LayoutQuantityTakeoff.self,from:JSONEncoder().encode(takeoff)),takeoff)
        let item=CeilingReferenceRecord(id:"QTY-ECLISSE",kind:"quantitatif",title:"Éclisse",summary:"",sourcePage:0,status:"active",
            data:["unit":.string("unité"),"values":.object(["simple_060":.number(0.25)])])
        let catalogue=CeilingCataloguePayload(version:"test",ouvrage:nil,isolation:[],systemesFixation:[],parements:[],
            quantitatifs:[item],pareVapeur:[],regles:[])
        work.layoutQuantityTakeoff=takeoff
        let total=CombinedQuantityCalculator.calculate(works:[work],catalogue:catalogue)
        XCTAssertEqual(try XCTUnwrap(total.supplies.first { $0.name == "Éclisse" }).quantity,
            Double(takeoff.furringSplices ?? 0)+17.28*0.25*0.5,accuracy:0.001)
        var legacy=takeoff; legacy.furringSplices=nil; work.layoutQuantityTakeoff=legacy
        let old=CombinedQuantityCalculator.calculate(works:[work],catalogue:catalogue)
        XCTAssertEqual(try XCTUnwrap(old.supplies.first { $0.name == "Éclisse" }).quantity,17.28*0.25,accuracy:0.001)
    }

    func testPartialQuantityUsesSurfaceProportionAndKeepsUnplannedParts() throws {
        var work=quantityWork()
        var c=CeilingConfiguration(length:4,width:5); c.perimeterSupport=true
        work.payload = .ceiling(c)
        work.components.append(.init(name:"Cuisine — non calepinée"))
        let first=try LayoutQuantityCalculator.make(work:work,formats:[])
        XCTAssertEqual(first.area,8.64,accuracy:0.0001)
        XCTAssertEqual(first.framingCoverage,8.64/20,accuracy:0.0001)
        XCTAssertEqual(first.boardCoverage(0),8.64/20,accuracy:0.0001)
        var second=work.components[0]; second.id=UUID(); second.name="Cuisine"
        work.components[1]=second
        let both=try LayoutQuantityCalculator.make(work:work,formats:[])
        XCTAssertEqual(both.framingCoverage,17.28/20,accuracy:0.0001)
        XCTAssertEqual(both.framingMeters,first.framingMeters*2,accuracy:0.0001)
    }

    func testQuantitySnapshotRoundTripInvalidationAndIncompletePlans() throws {
        var work=quantityWork()
        work.layoutQuantityTakeoff=try LayoutQuantityCalculator.make(work:work,formats:[])
        let restored=try JSONDecoder().decode(WorkItem.self,from:JSONEncoder().encode(work))
        XCTAssertEqual(LayoutQuantityCalculator.validated(restored),work.layoutQuantityTakeoff)
        work.components[0].plans[0].layers[0].offset.x += 50
        XCTAssertNil(LayoutQuantityCalculator.validated(work))
        XCTAssertEqual(LayoutQuantityCalculator.applicable(work),try LayoutQuantityCalculator.make(work:work,formats:[]),"A changed plan recalculates without a second approval")
        XCTAssertEqual(LayoutQuantityCalculator.applicable(work)?.fingerprint,LayoutQuantityCalculator.fingerprint(work))
        work.components.append(.init(name:"Cuisine"))
        XCTAssertNoThrow(try LayoutQuantityCalculator.make(work:work,formats:[]))
        work=quantityWork(); work.components[0].geometryRevision=1
        XCTAssertThrowsError(try LayoutQuantityCalculator.make(work:work,formats:[]))
        var obsolete=try LayoutQuantityCalculator.make(work:quantityWork(),formats:[])
        obsolete.configurationFingerprint=LayoutQuantityCalculator.configurationFingerprint(work)
        work.layoutQuantityTakeoff=obsolete
        XCTAssertNil(LayoutQuantityCalculator.applicable(work),"An obsolete snapshot must not hide an unusable plan")
        work=quantityWork(); var doubleSkin=CeilingConfiguration(length:2.4,width:3.6); doubleSkin.layers=2; work.payload = .ceiling(doubleSkin)
        let partial=try LayoutQuantityCalculator.make(work:work,formats:[])
        XCTAssertEqual(partial.boardCoverage(0),1)
        XCTAssertEqual(partial.boardCoverage(1),0)
    }

    func testRailStudQuantityUsesStoredSpacingAndRejectsExcessiveSpan() throws {
        var work=quantityWork()
        var c=RailStudCeilingConfiguration()
        c.length=2.4; c.width=3.6
        c.frameMode="suspended"; c.assembly="double"; c.suspensionSpacingMeters=2
        c.suppliesPerSuspension=[.init(name:"Suspente",quantity:1,unit:"unité")]
        work.payload = .railStudCeiling(c); work.type = .ceilingOnRailsAndStuds
        let rail=try LayoutQuantityCalculator.make(work:work,formats:[])
        let furring=try LayoutQuantityCalculator.make(work:quantityWork(),formats:[])
        XCTAssertEqual(rail.framingMeters,furring.framingMeters*2,accuracy:0.0001)
        XCTAssertLessThanOrEqual(rail.hangers,furring.hangers)
        c.frameMode="selfSupporting"; c.maximumSpanMeters=1
        work.payload = .railStudCeiling(c)
        XCTAssertThrowsError(try LayoutQuantityCalculator.make(work:work,formats:[]))
    }

    func testRailCeilingFixingPairSplitsBeforeAndAfterLayoutTakeoff() throws {
        var work = quantityWork()
        var configuration = RailStudCeilingConfiguration()
        configuration.length = 2.4; configuration.width = 3.6
        configuration.frameMode = "suspended"; configuration.suspensionSpacingMeters = 1.2
        configuration.quantities = [.init(name: "Cheville et piton", quantity: 20, unit: "unité")]
        configuration.suppliesPerSuspension = [.init(name: "Cheville et piton", quantity: 1, unit: "unité")]
        work.payload = .railStudCeiling(configuration); work.type = .ceilingOnRailsAndStuds
        let catalogue = CeilingCataloguePayload(version: "test", ouvrage: nil, isolation: [], systemesFixation: [], parements: [], quantitatifs: [], pareVapeur: [], regles: [])
        let before = CombinedQuantityCalculator.calculate(works: [work], catalogue: catalogue)
        XCTAssertEqual(before.supplies.first(where: { $0.name == "Cheville crampon 8 mm" })?.quantity, 20)
        let takeoff = try LayoutQuantityCalculator.make(work: work, formats: [])
        work.layoutQuantityTakeoff = takeoff
        let after = CombinedQuantityCalculator.calculate(works: [work], catalogue: catalogue)
        for name in ["Cheville crampon 8 mm", "Piton de suspension 8 mm"] {
            XCTAssertEqual(after.supplies.first(where: { $0.name == name })?.quantity, Double(takeoff.hangers))
        }
        XCTAssertFalse(after.supplies.contains(where: { $0.name == "Cheville et piton" }))
        configuration.quantities = ["Cheville crampon 8 mm", "Piton de suspension 8 mm"].map { .init(name: $0, quantity: 20, unit: "unité") }
        configuration.suppliesPerSuspension = ["Cheville crampon 8 mm", "Piton de suspension 8 mm"].map { .init(name: $0, quantity: 1, unit: "unités") }
        work.payload = .railStudCeiling(configuration)
        // Replacing a configuration intentionally invalidates its prior takeoff.
        work.layoutQuantityTakeoff = try LayoutQuantityCalculator.make(work: work, formats: [])
        let updated = CombinedQuantityCalculator.calculate(works: [work], catalogue: catalogue)
        XCTAssertEqual(updated.supplies.map(\.name), after.supplies.map(\.name))
        XCTAssertEqual(updated.supplies.map(\.quantity), after.supplies.map(\.quantity))
    }

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
        XCTAssertEqual(result.sheets.flatMap(\.pieces).compactMap{$0.stock?.label},["1","2-1","3","2-2"])
        XCTAssertEqual(result,try SheetLayoutEngine.calculate(surface:ceiling,layer:offcutLayer))
        try assertCutStockIsFeasible(result)
    }

    func testOffcutMinimumIsFixedAndPeripheryIsAnEligibleSecondSupport() throws {
        let atMinimum=try SheetLayoutEngine.calculate(surface:offcutCeiling(2400,2600),layer:offcutLayer)
        XCTAssertEqual(atMinimum.purchasedSheetCount,3)
        let tooSmall=try SheetLayoutEngine.calculate(surface:offcutCeiling(2400,2599),layer:offcutLayer)
        XCTAssertEqual(tooSmall.purchasedSheetCount,4)
        var noReuse=offcutLayer; noReuse.reuseOffcuts=false
        XCTAssertEqual(try SheetLayoutEngine.calculate(surface:offcutCeiling(),layer:noReuse).purchasedSheetCount,3)
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

    func testFourTaperedEdgesRejectReuseWithCutEdgeAgainstAnotherBoard() throws {
        var layer=offcutLayer
        layer.fourTaperedEdges=true
        let result=try SheetLayoutEngine.calculate(surface:offcutCeiling(),layer:layer)
        XCTAssertEqual(result.purchasedSheetCount,4)
        layer.fourTaperedEdges=false
        XCTAssertEqual(try SheetLayoutEngine.calculate(surface:offcutCeiling(),layer:layer).purchasedSheetCount,3)
    }

    func testFourTaperedEdgesStillReuseOppositePeripheryCuts() throws {
        var layer=offcutLayer
        layer.fourTaperedEdges=true; layer.offset.y=600
        let result=try SheetLayoutEngine.calculate(surface:offcutCeiling(2400,3600),layer:layer)
        XCTAssertGreaterThan(result.savedSheetCount,0)
        try assertCutStockIsFeasible(result)
        assertFactoryJoints(result)
    }

    func testFourTaperedEdgesPreservedWithStaggerOpeningsAndRotatedReference() throws {
        var room=offcutCeiling(4300,3700)
        room.openings=[.init(kind:.other,contour:LayoutBounds(min:.init(x:1400,y:1100),max:.init(x:2000,y:1900)).polygon)]
        for orientation in LayoutOrientation.allCases {
            for staggered in [false,true] {
                var layer=offcutLayer
                layer.orientation=orientation; layer.fourTaperedEdges=true
                layer.staggered=staggered; layer.referenceEdge=1
                layer.offset = .init(x:-300,y:-500)
                let result=try SheetLayoutEngine.calculate(surface:room,layer:layer)
                try assertCutStockIsFeasible(result)
                assertFactoryJoints(result)
                XCTAssertEqual(result.netArea,4300*3700-600*800,accuracy:0.1)
            }
        }
    }

    private func assertFactoryJoints(_ result:SheetLayoutResult, file:StaticString=#filePath,line:UInt=#line) {
        for sheet in result.sheets {
            let contacts=LayoutOffcutPacking.sharedEdges(of:sheet,joints:result.joints)
            for piece in sheet.pieces {
                guard let stock=piece.stock else { XCTFail("Missing stock",file:file,line:line); continue }
                XCTAssertTrue(LayoutOffcutPacking.factoryEdges(contacts,origin:stock.origin,size:.init(x:sheet.width,y:sheet.height)),file:file,line:line)
            }
        }
    }

    func testBoardNumbersFollowLongAxisInBothOrientations() throws {
        for orientation in LayoutOrientation.allCases {
            var layer=offcutLayer; layer.orientation=orientation
            let result=try SheetLayoutEngine.calculate(surface:offcutCeiling(4800,4800),layer:layer)
            let a=result.sheets[0].origin,b=result.sheets[1].origin
            XCTAssertEqual(orientation == .vertical ? a.x : a.y,orientation == .vertical ? b.x : b.y)
            XCTAssertEqual(orientation == .vertical ? b.y-a.y : b.x-a.x,2400,accuracy:0.001)
            XCTAssertEqual(result.sheets[0].pieces[0].stock?.label,"1")
            XCTAssertEqual(result.sheets[1].pieces[0].stock?.label,"2")
        }
    }

    func testOffsetNumbersRemainInViewportAndAvoidExistingNumbers() {
        let viewport=CGRect(x:0,y:0,width:300,height:400)
        let occupied=[CGRect(x:145,y:180,width:35,height:22)]
        for anchor in [CGPoint(x:150,y:200),CGPoint(x:3,y:3),CGPoint(x:299,y:399)] {
            let rect=LayoutNumberCallout.rect(anchor:anchor,size:.init(width:35,height:22),viewport:viewport,occupied:occupied,displaced:true)
            XCTAssertTrue(viewport.contains(rect))
            XCTAssertFalse(occupied.contains { $0.intersects(rect) })
            XCTAssertGreaterThan(hypot(rect.midX-anchor.x,rect.midY-anchor.y),10)
        }
    }

    @MainActor func testCeilingOrientationAutomaticallyOptimizesAndKeepsLastRapidChoice() async throws {
        let model=LayoutEditorModel(persistsStandaloneLibrary:false)
        var document=LayoutDocument.newSupport(offcutCeiling())
        model.apply(document)
        XCTAssertFalse(model.isOptimizing)
        document.layers[0].orientation = .horizontal
        model.apply(document)
        XCTAssertTrue(model.isOptimizing)
        document.layers[0].referenceEdge=1
        model.apply(document)
        for _ in 0..<1000 {
            if !model.isOptimizing { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertFalse(model.isOptimizing)
        let expected=try LayoutPlanning.optimize(surface:document.surface,layer:document.layers[0],furring:false)
        XCTAssertEqual(model.document?.layers.first,expected)
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
            XCTAssertEqual(sibling.stock?.label,"2-1")
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

    func testFourTaperedEdgesFlowFromOuvrageAndSurviveSaveWithoutCatalogue() throws {
        var allocation=FacingSelection(facingID:"four",dimensionID:"1200x2400",area:20)
        allocation.fourTaperedEdges=true
        var configuration=CeilingConfiguration(); configuration.firstSkin=[allocation]
        let document=WorkLayoutDefaults.document(surface:offcutCeiling(),configuration:.ceiling(configuration))
        XCTAssertEqual(document.layers[0].fourTaperedEdges,true)
        let restored=try JSONDecoder().decode(LayoutDocument.self,from:JSONEncoder().encode(document))
        XCTAssertEqual(restored.layers[0].fourTaperedEdges,true)
        let catalog=[LayoutCatalogFormat(id:"four-1200-2400",title:"Plaque",width:1200,length:2400,productID:"four",fourTaperedEdges:true)]
        XCTAssertEqual(WorkLayoutDefaults.fourTaperedEdges(configuration:.ceiling(configuration),layer:document.layers[0],formats:catalog),true)
        var rail=RailStudCeilingConfiguration()
        rail.firstSkin=[.init(productID:"four",dimensionID:"1200x2400",area:20,fourTaperedEdges:true)]
        XCTAssertEqual(WorkLayoutDefaults.document(surface:offcutCeiling(),configuration:.railStudCeiling(rail)).layers[0].fourTaperedEdges,true)
    }

    func testCanvasControlsDoNotChangePhysicalZoomWhenViewportHeightChanges() {
        let bounds=offcutCeiling().bounds
        let size=CGSize(width:380,height:600)
        let initial=LayoutViewport(bounds:bounds,size:size,zoom:2,pan:.zero,fittingSize:size)
        let smaller=LayoutViewport(bounds:bounds,size:.init(width:380,height:470),zoom:2,pan:.init(width:0,height:65),fittingSize:size)
        XCTAssertEqual(initial.scale,smaller.scale,accuracy:0.000001)
        XCTAssertEqual(initial.screen(bounds.center),smaller.screen(bounds.center))
    }

    private var fourEdgeFormat: LayoutCatalogFormat {
        let product = "FACING-BA13-QUATRE-BORDS-AMINCIS"
        return .init(id:LayoutCatalogFormat.identifier(productID:product,width:1200,length:2400),
                     title:"BA13 quatre bords amincis",width:1200,length:2400,productID:product,fourTaperedEdges:true)
    }

    func testOuvrageImportsProductIdentityAndAppliesFactoryEdgeRuleAfterReload() throws {
        let format = fourEdgeFormat
        var allocation = FacingSelection(facingID:format.productID!,dimensionID:"1200x2400",area:20)
        allocation.fourTaperedEdges = true
        var configuration = CeilingConfiguration(); configuration.firstSkin = [allocation]
        let initial = WorkLayoutDefaults.document(surface:offcutCeiling(),configuration:.ceiling(configuration))
        XCTAssertEqual(initial.layers[0].catalogFormatID,format.id)
        let restored = try JSONDecoder().decode(LayoutDocument.self,from:JSONEncoder().encode(initial))
        let layer = WorkLayoutDefaults.resolvingFacing(restored.layers[0],configuration:nil,formats:[])
        XCTAssertEqual(layer.catalogFormatID,format.id)
        XCTAssertEqual(layer.fourTaperedEdges,true)
        // Use the bottom reference edge: the last row yields offcuts whose
        // reuse would otherwise put a cut edge against the following board.
        var bottomAligned = layer; bottomAligned.referenceEdge = 0
        let result = try SheetLayoutEngine.calculate(surface:restored.surface,layer:bottomAligned)
        XCTAssertEqual(result.purchasedSheetCount,4)
        assertFactoryJoints(result)
    }

    func testLegacyOuvrageRecoversExactFacingWhenCatalogueArrives() throws {
        var configuration = CeilingConfiguration()
        configuration.firstSkin = [.init(facingID:fourEdgeFormat.productID!,dimensionID:"1200.0x2400.0",area:20)]
        var legacy = offcutLayer
        legacy.fourTaperedEdges = false // Former form default must not override the known product.
        legacy.offset = .init(x:35,y:48); legacy.staggered = true
        let unavailable = WorkLayoutDefaults.resolvingFacing(legacy,configuration:.ceiling(configuration),formats:[])
        XCTAssertEqual(unavailable.catalogFormatID,fourEdgeFormat.id)
        let fixed = WorkLayoutDefaults.resolvingFacing(unavailable,configuration:.ceiling(configuration),formats:[fourEdgeFormat])
        XCTAssertEqual(fixed.fourTaperedEdges,true)
        XCTAssertEqual(fixed.offset,legacy.offset)
        XCTAssertEqual(fixed.staggered,true)
        XCTAssertEqual(WorkLayoutDefaults.resolvingFacing(fixed,configuration:.ceiling(configuration),formats:[fourEdgeFormat]),fixed)
    }

    func testExplicitManualFacingIsNotOverwrittenByOuvrageOrReload() throws {
        var configuration = CeilingConfiguration()
        configuration.firstSkin = [.init(facingID:fourEdgeFormat.productID!,dimensionID:"1200x2400",area:20)]
        var manual = offcutLayer; manual.manualFacing = true; manual.fourTaperedEdges = false
        let restored = try JSONDecoder().decode(LayoutLayer.self,from:JSONEncoder().encode(manual))
        XCTAssertEqual(WorkLayoutDefaults.resolvingFacing(restored,configuration:.ceiling(configuration),formats:[fourEdgeFormat]),manual)
    }

    func testExplicitCatalogueFacingWinsOverSameSizedOuvrageFacing() {
        var configuration = CeilingConfiguration()
        configuration.firstSkin = [.init(facingID:fourEdgeFormat.productID!,dimensionID:"1200x2400",area:20)]
        let standard = LayoutCatalogFormat(id:"standard",title:"BA13 standard",width:1200,length:2400,productID:"standard",fourTaperedEdges:false)
        var layer = offcutLayer; layer.catalogFormatID = standard.id; layer.fourTaperedEdges = true
        let result = WorkLayoutDefaults.resolvingFacing(layer,configuration:.ceiling(configuration),formats:[fourEdgeFormat,standard])
        XCTAssertEqual(result.catalogFormatID,standard.id)
        XCTAssertEqual(result.fourTaperedEdges,false)
    }

    func testRailCeilingFacingIdentityAndLargestAreaAreImported() {
        var configuration = RailStudCeilingConfiguration()
        configuration.firstSkin = [
            .init(productID:"standard",dimensionID:"1200x2400",area:3,fourTaperedEdges:false),
            .init(productID:fourEdgeFormat.productID!,dimensionID:"1200x2400",area:10,fourTaperedEdges:true),
            .init(productID:"long",dimensionID:"1200x3000",area:5,fourTaperedEdges:false)
        ]
        let layer = WorkLayoutDefaults.document(surface:offcutCeiling(),configuration:.railStudCeiling(configuration)).layers[0]
        XCTAssertEqual(layer.catalogFormatID,fourEdgeFormat.id)
        XCTAssertEqual(layer.fourTaperedEdges,true)
        XCTAssertEqual(layer.sheetLength,2400)
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
        layer.furring?.orientation = .vertical // Wall framing is always vertical.
        let wall = LayoutPlanning.alignBoards(to:layer,support:.wall)
        XCTAssertEqual(wall.offset,.init(x:1200,y:3600), "Wall boards use the nearest vertical support, preserving the height offset")
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
