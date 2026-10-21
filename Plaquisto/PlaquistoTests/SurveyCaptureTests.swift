import XCTest
import ARKit
import SceneKit
import RoomPlan
import SwiftUI
@testable import Plaquisto

final class ManualRoomModelTests: XCTestCase {
    private let rectangle: [LayoutPoint] = [.init(x: 0, y: 0), .init(x: 5000, y: 0), .init(x: 5000, y: 4000), .init(x: 0, y: 4000)]
    @MainActor func testSelectionIsImmediateAndDoubleTapRestoresOriginalSelection() {
        var events: [String] = []
        let coordinator = SurveySurfaceScene.Coordinator { events.append($0) }
        coordinator.selected = ["previous"]
        var restored: Set<String>?
        coordinator.onRestoreSelection = { restored = $0 }
        coordinator.select("wall", tapCount: 1)
        XCTAssertEqual(events, ["wall"], "No timer or double-tap failure must delay the callback")
        coordinator.selected = ["wall"] // Single-selection quick layout replaced the old wall.
        coordinator.select("wall", tapCount: 2)
        XCTAssertEqual(events, ["wall"])
        coordinator.restoreSelection()
        XCTAssertEqual(restored, ["previous"])
        coordinator.select(nil, tapCount: 1)
        XCTAssertEqual(events, ["wall"], "Empty space must not toggle the last selected wall")
    }
    func testCommonHeightBuildsClosedRoomAndSingleHorizontalCeiling() throws {
        let room = try ManualRoomModel.room(contour: rectangle, commonHeight: 2.5, constraints: [:], name: "Salon")
        XCTAssertEqual(room.walls.count, 4)
        XCTAssertEqual(room.ceilings.count, 1)
        XCTAssertEqual(room.slopes.count, 1)
        XCTAssertEqual(room.floors.count, 1)
        XCTAssertEqual(room.metadata.source, .manual)
        XCTAssertEqual(room.walls.map { $0.length.effectiveValue }, [5,4,5,4])
        XCTAssertTrue(room.walls.allSatisfy { $0.height.effectiveValue == 2.5 && $0.height.manuallyValidated })
        XCTAssertEqual(room.slopes[0].plane.slopeDegrees, 0)
        XCTAssertEqual(room.slopes[0].boundaries[0].map(\.y), [2.5,2.5,2.5,2.5])
        let document = PlaquistoRoomDocument(room: room)
        let decoded = try PlaquistoRoomDocument.decode(document.encoded())
        XCTAssertEqual(decoded.room.walls, room.walls)
        XCTAssertEqual(decoded.room.ceilings, room.ceilings)
    }
    func testSegmentHeightMakesBothEndsLevelAndWallsReachRamp() throws {
        let room = try ManualRoomModel.room(contour: rectangle, commonHeight: 2.5,
            constraints: [0:2.5, 1:2.5, 2:3.5, 3:3.5], name: "Rampant")
        XCTAssertEqual(room.slopes[0].boundaries[0].map(\.y), [2.5,2.5,3.5,3.5])
        XCTAssertEqual(room.walls[1].localOutline?.map(\.y), [0,0,3.5,2.5])
        XCTAssertEqual(room.walls[3].localOutline?.map(\.y), [0,0,2.5,3.5])
        XCTAssertEqual(room.walls[1].height.effectiveValue, 3.5)
    }
    func testTwoVerticesDefineMinimalSlopeAndUnspecifiedCornersFollowPlane() throws {
        let plane = try ManualRoomModel.plane(contour: rectangle, commonHeight: 2.5, constraints: [0:2.5,1:3])
        XCTAssertEqual(plane.a, 0.1, accuracy: 1e-9)
        XCTAssertEqual(plane.b, 0, accuracy: 1e-9)
        XCTAssertEqual(plane.height(x: 5, z: -4), 3, accuracy: 1e-9)
    }
    func testThreeNonCollinearHeightsDefineObliquePlane() throws {
        let plane = try ManualRoomModel.plane(contour: rectangle, commonHeight: 2.5, constraints: [0:2.5,1:3,3:3.5])
        XCTAssertEqual(plane.height(x: 5, z: -4), 4, accuracy: 1e-9)
    }
    func testOneConstraintIsHorizontalUntilASecondHeightIsSet() throws {
        let plane = try ManualRoomModel.plane(contour: rectangle, commonHeight: 2.5, constraints: [2:3])
        XCTAssertEqual(plane, RoomPlane(a: 0, b: 0, c: 3))
    }
    func testNonPlanarConstraintsAreRejectedRatherThanAveraged() {
        XCTAssertThrowsError(try ManualRoomModel.plane(contour: rectangle, commonHeight: 2.5, constraints: [0:2.5,1:2.5,2:3,3:2.5]))
    }
    func testInvalidAndExtrapolatedNegativeHeightsAreRejected() {
        for height in [Double.nan, .infinity, 0, -1, 21] {
            XCTAssertThrowsError(try ManualRoomModel.plane(contour: rectangle, commonHeight: height, constraints: [:]))
            XCTAssertThrowsError(try ManualRoomModel.plane(contour: rectangle, commonHeight: 2.5, constraints: [0:height]))
        }
        XCTAssertThrowsError(try ManualRoomModel.plane(contour: rectangle, commonHeight: 2.5, constraints: [4:2.5]))
        XCTAssertThrowsError(try ManualRoomModel.plane(contour: rectangle, commonHeight: 2.5, constraints: [0:4,1:1,3:1]))
    }
    func testConcaveFloorRetainsAllVerticesAndNetArea() throws {
        let contour: [LayoutPoint] = [.init(x: 0,y: 0),.init(x: 6000,y: 0),.init(x: 6000,y: 3000),.init(x: 3000,y: 3000),.init(x: 3000,y: 5000),.init(x: 0,y: 5000)]
        let room = try ManualRoomModel.room(contour: contour, commonHeight: 2.5, constraints: [:], name: "Pièce en L")
        XCTAssertEqual(room.walls.count, 6)
        let draft = try ManualRoomModel.campaign(room: room)
        XCTAssertTrue(draft.sharesWorldSpace)
        XCTAssertNil(draft.captureLocation)
        XCTAssertFalse(draft.hasUnreviewedDuplicates)
        let checkpoint = ProjectRoomScanCheckpoint(roomID: room.id, document: draft.chunks[0].document, spatialLinkState: .sharedWorldSpace, workState: .validated)
        let survey = ProjectSurveyRecord(projectID: UUID(), name: "Manuel", checkpoints: [checkpoint])
        let surfaces = SurveyWorkGeometry.surfaces(in: survey)
        XCTAssertEqual(surfaces.filter { $0.source.kind == .wall }.count, 6)
        XCTAssertEqual(SurveyWorkGeometry.totalArea(surfaces.filter { $0.source.kind == .ceiling }), 24, accuracy: 1e-6)
        XCTAssertFalse(SurveyWorkGeometry.availableWorkTypes(for: surfaces.filter { $0.source.kind == .ceiling }).isEmpty)
    }
    func testInvalidFloorIsRejected() {
        XCTAssertThrowsError(try ManualRoomModel.room(contour: Array(rectangle.prefix(2)), commonHeight: 2.5, constraints: [:], name: "Invalide"))
        XCTAssertThrowsError(try ManualRoomModel.room(contour: [rectangle[0],rectangle[2],rectangle[1],rectangle[3]], commonHeight: 2.5, constraints: [:], name: "Croisé"))
    }
    func testManualCeilingCanReopenConfigureAndSplitWithoutLosingItsHeight() throws {
        let room = try ManualRoomModel.room(contour: rectangle, commonHeight: 2.5, constraints: [0:2.5,1:2.5,2:3.2,3:3.2], name: "Rampant")
        let document = PlaquistoRoomDocument(room: room)
        let proposals = try WallCeilingEstimate.manualProposals(in: room)
        XCTAssertEqual(proposals.count, 1)
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal.ceilingID, room.ceilings[0].id)
        var settings = try XCTUnwrap(room.ceilings[0].estimateSettings)
        XCTAssertEqual(settings.shape, .singleSlope)
        XCTAssertEqual(settings.lowHeight, 2.5)
        XCTAssertEqual(settings.highHeight, 3.2)
        let unchanged = try WallCeilingEstimate.applying(to: document, proposal: proposal, settings: settings, manuallyEdited: true)
        for point in room.slopes[0].boundaries[0] {
            XCTAssertEqual(unchanged.room.slopes[0].plane.height(x: point.x, z: point.z), point.y, accuracy: 1e-8)
        }
        settings.highHeight = 3.5
        let updated = try WallCeilingEstimate.applying(to: document, proposal: proposal, settings: settings, manuallyEdited: true)
        XCTAssertEqual(updated.initialRoom, document.initialRoom)
        XCTAssertEqual(updated.room.ceilings[0].provenance.source, .manual)
        XCTAssertEqual(updated.room.slopes[0].plane.height(x: 0, z: -4), 3.5, accuracy: 1e-8)
        let split = try WallCeilingEstimate.split(updated, ceilingID: room.ceilings[0].id,
            from: .init(x: 2.5,y: 0,z: 1), to: .init(x: 2.5,y: 0,z: -5))
        XCTAssertEqual(split.room.ceilings.count, 2)
        XCTAssertEqual(try WallCeilingEstimate.manualProposals(in: split.room).count, 2)
    }
    @MainActor func testSavedManualModelsReloadInNewAndExistingProjectsWithoutDuplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ManualRoomTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        let room = try ManualRoomModel.room(contour: rectangle, commonHeight: 2.5, constraints: [:], name: "Salon")
        let first = try ManualRoomModel.campaign(room: room)
        try store.saveScanCampaign(first, projectID: nil, newProjectName: "Mes mesures", surveyName: "Salon", newProjectAddress: "Adresse saisie")
        let projectID = try XCTUnwrap(store.projects.first?.id)
        let second = try ManualRoomModel.campaign(room: ManualRoomModel.room(contour: rectangle, commonHeight: 2.5, constraints: [0:2.5,1:3], name: "Étage"))
        try store.saveScanCampaign(second, projectID: projectID, newProjectName: "", surveyName: "Étage")
        XCTAssertThrowsError(try store.saveScanCampaign(first, projectID: projectID, newProjectName: "", surveyName: "Doublon"))
        let loaded = ProjectStore(fileURL: url)
        XCTAssertEqual(loaded.projects.count, 1)
        XCTAssertEqual(loaded.surveys.count, 2)
        XCTAssertEqual(loaded.projects[0].address, "Adresse saisie")
        XCTAssertTrue(loaded.surveys.allSatisfy { $0.checkpoints[0].document.room.metadata.source == .manual })
        XCTAssertEqual(loaded.surveys[1].checkpoints[0].document.room.slopes[0].plane.a, 0.1, accuracy: 1e-9)
    }
}

final class CeilingMeshCleanupTests: XCTestCase {
    private func rectangle(_ x:Double,_ z:Double,_ width:Double,_ depth:Double) -> [SIMD3<Double>] {
        let a=SIMD3(x,2.5,z),b=SIMD3(x+width,2.5,z),c=SIMD3(x+width,2.5,z+depth),d=SIMD3(x,2.5,z+depth)
        return [a,b,c,a,c,d]
    }
    func testTJunctionTrianglesBecomeOneBoundaryWithoutMovingVertices() {
        let triangles=rectangle(0,0,1,2)+rectangle(1,0,1,1)+rectangle(1,1,1,1)
        let loops=ScannerRoomBridge.boundaries(triangles,resolvingTJunctions:true)
        XCTAssertEqual(loops.count,1)
        XCTAssertEqual(abs(SurveyPlanFinishes.area(loops.first ?? [])),4,accuracy:1e-9)
        for loop in loops { for p in loop {
            XCTAssertEqual(p.y,2.5)
            let outerEdge = p.x == 0 || p.x == 2 || p.z == 0 || p.z == 2
            XCTAssertTrue(outerEdge,"No internal triangle edge survives as a roof boundary")
        } }
        XCTAssertEqual(ScannerRoomBridge.boundaries(triangles+triangles,resolvingTJunctions:true),loops,
                       "Duplicate faces must not erase the outline")
    }
    func testOpeningInCeilingRemainsAHoleAndDisjointPartsStaySeparate() {
        let triangles=rectangle(0,0,1,3)+rectangle(2,0,1,3)+rectangle(1,0,1,1)+rectangle(1,2,1,1)
        let loops=ScannerRoomBridge.boundaries(triangles,resolvingTJunctions:true)
        XCTAssertEqual(loops.count,2)
        XCTAssertEqual(abs(loops.reduce(0) { $0+SurveyPlanFinishes.area($1) }),8,accuracy:1e-9)
        let separate=ScannerRoomBridge.boundaries(rectangle(0,0,1,1)+rectangle(2,0,1,1),resolvingTJunctions:true)
        XCTAssertEqual(separate.count,2)
    }
    func testDAEReusesVertexIndicesButRetainsRealGaps() throws {
        let points=rectangle(0,0,2,3).map { RoomPoint(x:$0.x,y:$0.y,z:$0.z) }
        let indexed=SurveyDAEExport.indexedPositions(points)
        XCTAssertEqual(indexed.points.count,4)
        XCTAssertEqual(indexed.indices.map { indexed.points[$0] },points)
        let shifted=points.map { $0+RoomPoint(x:0,y:0.0001,z:0) }
        XCTAssertEqual(SurveyDAEExport.indexedPositions(points+shifted).points.count,8)
        let xml=try SurveyDAEExport.xml(meshes:[.init(name:"Plafond",kind:"ceiling",triangles:points)],title:"Test",date:Date())
        XCTAssertTrue(XMLParser(data:Data(xml.utf8)).parse())
        XCTAssertTrue(xml.contains("id=\"mesh-0-positions-array\" count=\"12\""))
        XCTAssertTrue(xml.contains("<triangles count=\"2\""))
        XCTAssertTrue(xml.contains("<p>0 0 1 1 2 2 0 3 2 4 3 5</p>"))
    }
}

final class ScanWallSimplificationTests: XCTestCase {
    private let source = GeometryProvenance(source: .roomPlan)
    private func wall(_ x: Double, _ z: Double, _ endX: Double, _ endZ: Double, height: Double = 2.5) -> PlaquistoWall {
        .init(start: .init(x:x,y:0,z:z), end: .init(x:endX,y:0,z:endZ),
              length: .init(rawValue:hypot(endX-x,endZ-z),provenance:source),
              height: .init(rawValue:height,provenance:source),provenance:source)
    }
    private func document(_ walls: [PlaquistoWall]) -> PlaquistoRoomDocument {
        // The portable document uses ISO-8601 seconds, so use a stable date
        // without fractional seconds for exact round-trip assertions.
        .init(room:.init(walls:walls,metadata:.init(createdAt:Date(timeIntervalSince1970:1000),source:.roomPlan)))
    }
    func testStraightensFiveFragmentsPreservingOriginalAndRoundTrip() throws {
        let z=[0.0,0.03,-0.01,0.02,-0.02,0]
        let input=document((0..<5).map { wall(Double($0),z[$0],Double($0+1),z[$0+1]) })
        let result=ScanWallSimplification.process(input)
        XCTAssertEqual(result.mergedGroups,1)
        XCTAssertEqual(result.removedFragments,4)
        XCTAssertEqual(result.document.initialRoom,input.room)
        let w=try XCTUnwrap(result.document.room.walls.first)
        XCTAssertEqual(result.document.room.walls.count,1)
        XCTAssertEqual(w.length.effectiveValue,5,accuracy:1e-8)
        XCTAssertEqual(w.start.z,0,accuracy:1e-8)
        XCTAssertEqual(w.effectiveEnd.z,0,accuracy:1e-8)
        XCTAssertEqual(ScanWallSimplification.process(result.document).document,result.document)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(result.document.encoded()),result.document)
    }
    func testDoubledTolerancesAcceptFourDegreeKinkAndThreeCentimetreHeightMismatch() {
        let offset=tan(2 * Double.pi/180)
        let input=document([wall(0,0,1,offset),wall(1,offset,2,0,height:2.53)])
        XCTAssertEqual(ScanWallSimplification.process(input).document.room.walls.count,1)
    }
    func testFourCentimetreEndpointGapAcceptedButSixRejected() {
        XCTAssertEqual(ScanWallSimplification.process(document([wall(0,0,3,0),wall(3.04,0,6,0)])).mergedGroups,1)
        XCTAssertEqual(ScanWallSimplification.process(document([wall(0,0,3,0),wall(3.06,0,6,0)])).mergedGroups,0)
    }
    func testRejectsRealCornerStepAndParallelFaces() {
        for walls in [
            [wall(0,0,1,0),wall(1,0,1,2)],
            [wall(0,0,1,0),wall(1,0,2,0,height:2.55)],
            [wall(0,0,3,0),wall(3,0.1,0,0.1)],
            [wall(0,0,1,0.05),wall(1,0.05,2,0)]
        ] {
            let input=document(walls)
            XCTAssertEqual(ScanWallSimplification.process(input).document,input)
        }
    }
    func testRejectsTJunctionAndManualEdits() {
        let walls=[wall(0,0,2,0.02),wall(2,0.02,4,0),wall(2,0.02,2,2)]
        XCTAssertEqual(ScanWallSimplification.process(document(walls)).mergedGroups,0)
        var edited=document(Array(walls.prefix(2)))
        edited.room.walls[0].length.manualValue=2.1
        XCTAssertEqual(ScanWallSimplification.process(edited).document,edited)
        var manual=walls[0]; manual.provenance = .init(source:.manual)
        XCTAssertEqual(ScanWallSimplification.process(document([manual,walls[1]])).mergedGroups,0)
    }
    func testPreservesRampantPeakAndReversedFragmentOpening() throws {
        var a=wall(0,0,2,0.03,height:3), b=wall(4,0,2,0.03,height:3)
        a.id=UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
        b.id=UUID(uuidString:"00000000-0000-0000-0000-000000000002")!
        for w in [0,1] {
            let length=w == 0 ? a.length.rawValue : b.length.rawValue
            let profile=[RoomPoint(x:0,y:0,z:0),.init(x:length,y:0,z:0),.init(x:length,y:3,z:0),.init(x:0,y:2.5,z:0)]
            if w == 0 { a.localOutline=profile } else { b.localOutline=profile }
        }
        let opening=PlaquistoOpening(wallID:b.id,kind:.door,center:.init(x:3.3,y:1,z:0),
            width:.init(rawValue:0.8,provenance:source),height:.init(rawValue:2,provenance:source),
            sillHeight:.init(rawValue:0,provenance:source),positionOnWall:.init(rawValue:0.3,provenance:source),provenance:source)
        b.openingIDs=[opening.id]
        var room=document([a,b]).room; room.openings=[opening]
        let result=ScanWallSimplification.process(.init(room:room))
        XCTAssertEqual(result.mergedGroups,1)
        let merged=try XCTUnwrap(result.document.room.walls.first)
        XCTAssertTrue(merged.effectiveOutline.contains { abs($0.x-2)<1e-8 && abs($0.y-3)<1e-8 })
        let door=try XCTUnwrap(result.document.room.openings.first)
        XCTAssertEqual(door.id,opening.id)
        XCTAssertEqual(door.wallID,a.id)
        XCTAssertEqual(door.width,opening.width)
        XCTAssertEqual(door.height,opening.height)
        XCTAssertEqual(door.positionOnWall.effectiveValue,4-(0.7/b.length.rawValue*2)-0.4,accuracy:1e-8)
        XCTAssertEqual(PlaquistoWallGeometry.analyze(wall:merged,room:result.document.room).gross,11,accuracy:1e-8)
        try result.document.validate()
    }
    func testFloorBoundaryFollowsWallWithoutChangingElevation() throws {
        var room=document([wall(0,0,2,0.03),wall(2,0.03,4,0)]).room
        room.floors=[.init(boundaries:[[.zero,.init(x:2,y:0,z:0.03),.init(x:4,y:0,z:0),.init(x:4,y:0,z:3),.init(x:0,y:0,z:3)]],provenance:source)]
        let result=ScanWallSimplification.process(.init(room:room))
        XCTAssertEqual(result.mergedGroups,1)
        let point=result.document.room.floors[0].boundaries[0][1]
        XCTAssertEqual(point.x,2,accuracy:1e-8)
        XCTAssertEqual(point.y,0,accuracy:1e-8)
        XCTAssertEqual(point.z,0,accuracy:1e-8)
        XCTAssertEqual(result.document.initialRoom.floors,room.floors)
    }
    func testRejectsGradualCurveDespiteSmallPairwiseAngles() {
        let z=[0.0,0.03,0.06,0.075,0.06,0.03,0]
        let input=document((0..<6).map { wall(Double($0),z[$0],Double($0+1),z[$0+1]) })
        XCTAssertEqual(ScanWallSimplification.process(input).document,input)
    }
    func testRejectsThicknessMismatchAndPreservesUnrelatedWalls() {
        var a=wall(0,0,2,0.03),b=wall(2,0.03,4,0)
        a.thickness = .init(rawValue:0.1,provenance:source)
        b.thickness = .init(rawValue:0.2,provenance:source)
        XCTAssertEqual(ScanWallSimplification.process(document([a,b])).mergedGroups,0)
        b.thickness=a.thickness
        let other=wall(0,3,4,3)
        let result=ScanWallSimplification.process(document([a,b,other]))
        XCTAssertEqual(result.mergedGroups,1)
        XCTAssertEqual(result.document.room.walls.first { $0.id == other.id },other)
    }
}

final class SurveyCaptureTests: XCTestCase {
    func testPocketDoorAndGlazingPersistTheirOpeningGeometry() throws {
        let original = ceilingRoom()
        let wall = original.room.walls[0]
        let pocket = try SurveyPlanEditing.addingDoor(original, wallID: wall.id, width: 0.83, height: 2.04, position: 0.2,
            handing: .right, openingSide: .positive, pocket: true)
        let door = try XCTUnwrap(pocket.room.openings.first)
        XCTAssertEqual(door.kind, .door); XCTAssertEqual(door.isPocketDoor, true)
        XCTAssertNil(door.doorHanding); XCTAssertNil(door.doorOpeningSide)
        let glass = try SurveyPlanEditing.addingDoor(pocket, wallID: wall.id, width: 1.2, height: 1, position: 2,
            kind: .glazedBay, sill: 1)
        XCTAssertEqual(glass.room.openings.last?.sillHeight.effectiveValue, 1)
        XCTAssertEqual(glass.room.openings.last?.kind, .glazedBay)
        let reread = try PlaquistoRoomDocument.decode(glass.encoded())
        XCTAssertEqual(reread.room.openings, glass.room.openings)
        XCTAssertThrowsError(try SurveyPlanEditing.addingDoor(original, wallID: wall.id, width: 1, height: 2, position: 1, kind: .glazedBay, sill: 1))
    }
    func testDoorHitAreaIncludesSwingButNotOppositeSideOrPocketSwing() throws {
        let original = ceilingRoom(), wall = original.room.walls[0]
        let doc = try SurveyPlanEditing.addingDoor(original, wallID: wall.id, width: 0.9, height: 2, position: 1, handing: .right, openingSide: .positive)
        var door = try XCTUnwrap(doc.room.openings.first)
        XCTAssertNotNil(DoorPlanGeometry.hitDistance(point: .init(x: 1.3, y: 0, z: 0.4), opening: door, wall: wall, tolerance: 0.05))
        XCTAssertNil(DoorPlanGeometry.hitDistance(point: .init(x: 1.3, y: 0, z: -0.4), opening: door, wall: wall, tolerance: 0.05))
        door.isPocketDoor = true
        XCTAssertNil(DoorPlanGeometry.hitDistance(point: .init(x: 1.3, y: 0, z: 0.4), opening: door, wall: wall, tolerance: 0.05))
        XCTAssertNotNil(DoorPlanGeometry.hitDistance(point: .init(x: 1.3, y: 0, z: 0.02), opening: door, wall: wall, tolerance: 0.05))
    }
    @MainActor func testManualColumnHeightClearancesPersistenceCopyAndDAE() throws {
        let original = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom())
        let column = PlaquistoColumn(center: .init(x: 2, y: 0, z: 1.5), sideA: 0.4, sideB: 0.6, angle: 0, height: 1)
        let document = try SurveyPlanEditing.placingColumn(original, column: column)
        let saved = try XCTUnwrap(document.room.columns?.first)
        XCTAssertEqual(saved.height, 2.5, accuracy: 0.001)
        let lengths = saved.clearances(walls: document.room.walls).map(\.distance).sorted()
        XCTAssertEqual(lengths.count, 4)
        XCTAssertEqual(lengths[0], 1.2, accuracy: 0.001); XCTAssertEqual(lengths[3], 1.8, accuracy: 0.001)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(document.encoded()).room.columns, document.room.columns)
        let copy = document.remappingDomainIDs()
        XCTAssertNotEqual(copy.room.columns?.first?.id, saved.id)
        XCTAssertEqual(copy.room.columns?.first?.corners, saved.corners)
        let survey = ProjectSurveyRecord(projectID: UUID(), name: "Poteau", checkpoints: [.init(roomID: document.room.id, document: document, spatialLinkState: .sharedWorldSpace)])
        let meshes = try SurveyDAEExport.meshes(for: survey)
        XCTAssertEqual(meshes.first { $0.name.contains("Poteau 1") }?.triangles.count, 36)
        let scene = SurveySceneRenderer.make(survey: survey, surfaces: SurveyWorkGeometry.surfaces(in: survey))
        XCTAssertNotNil(scene.rootNode.childNode(withName: "column/\(saved.id)", recursively: false))
        var moved = saved; moved.center.x += 0.5; moved.angle = .pi/2
        let next = try SurveyPlanEditing.placingColumn(document, column: moved)
        XCTAssertEqual(next.room.columns?.count, 1)
        XCTAssertEqual(next.initialRoom, original.initialRoom)
        var invalid = saved; invalid.sideA = .nan
        XCTAssertThrowsError(try SurveyPlanEditing.placingColumn(document, column: invalid))
    }
    func testPlanOrientationAlignsLongWallVerticallyWithoutChangingGeometry() {
        let points = [CGPoint(x:0,y:0), CGPoint(x:8,y:0), CGPoint(x:8,y:3), CGPoint(x:0,y:3)]
        let angle = SurveyPlanOrientation.angle(points: points, edges: [[points[0],points[1]], [points[1],points[2]]])
        XCTAssertEqual(abs(sin(angle)), 1, accuracy: 1e-8)
    }
    private func evidenceFrame(depth: Float = 2, x: Float = 0, time: Double = 1) -> ScanEvidenceFrame {
        .init(timestamp: time, cameraToWorld: [1,0,0,0, 0,1,0,0, 0,0,1,0, x,0,0,1],
              imageWidth: 640, imageHeight: 480, fx: 320, fy: 320, cx: 320, cy: 240,
              depthWidth: 32, depthHeight: 24, depths: Array(repeating: depth, count: 32*24))
    }
    private var evidenceOpening: [RoomPoint] {
        let a = RoomPoint(x: -0.5, y: -0.5, z: -2), b = RoomPoint(x: 0.5, y: -0.5, z: -2)
        let c = RoomPoint(x: 0.5, y: 0.5, z: -2), d = RoomPoint(x: -0.5, y: 0.5, z: -2)
        return [a,b,c,a,c,d]
    }
    func testEvidenceIsLabOnlyRegardlessOfInterfaceTheme() {
        XCTAssertTrue(ScanEvidencePolicy.isEnabled(bundleID: "fr.plaquisto.lab"))
        XCTAssertFalse(ScanEvidencePolicy.isEnabled(bundleID: "fr.plaquisto.app"))
        XCTAssertFalse(ScanEvidencePolicy.isEnabled(bundleID: nil))
        XCTAssertFalse(ScanEvidencePolicy.isEnabled(bundleID: "com.someone.lab"))
    }
    func testEvidenceProjectionUsesCameraPoseIntrinsicsAndSensorAxes() throws {
        let frame = evidenceFrame(x: 0.25)
        let center = try XCTUnwrap(frame.project(.init(x: 0.25, y: 0, z: -2)))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.00001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.00001)
        XCTAssertEqual(center.z, 2, accuracy: 0.00001)
        let above = try XCTUnwrap(frame.project(.init(x: 0.25, y: 0.5, z: -2)))
        XCTAssertLessThan(above.y, center.y, "World Y up must project toward the top of the image")
        XCTAssertNil(frame.project(.init(x: 0, y: 0, z: 2)), "Behind the camera")
        var rotated = evidenceFrame()
        rotated.cameraToWorld = [0,0,-1,0, 0,1,0,0, 1,0,0,0, 0,0,0,1]
        XCTAssertEqual(try XCTUnwrap(rotated.project(.init(x: -2, y: 0, z: 0))).x, 0.5, accuracy: 0.00001)
    }
    func testEvidenceCannotConcludeFromRGBOrRepeatedStationaryFrames() {
        let samePose = (0..<10).map { evidenceFrame(time: Double($0)) }
        XCTAssertEqual(ScanEvidenceAnalysis.analyze(triangles: evidenceOpening, frames: samePose).finding, .unknown)
        var rgbOnly = evidenceFrame()
        rgbOnly.depths = []; rgbOnly.depthWidth = 0; rgbOnly.depthHeight = 0
        let result = ScanEvidenceAnalysis.analyze(triangles: evidenceOpening, frames: [rgbOnly])
        XCTAssertEqual(result.finding, .unknown)
        XCTAssertEqual(result.observations.count, 1, "Photo remains available for human review")
        XCTAssertEqual(result.independentViews, 0)
    }
    func testEvidencePortraitPhotoRotationDoesNotRotateDepthOrGeometry() throws {
        var frame = evidenceFrame()
        let point = RoomPoint(x: 0.5, y: 0.5, z: -2)
        let sensor = try XCTUnwrap(frame.project(point))
        frame.photoQuarterTurns = 1
        let photo = frame.photoPoint(sensor)
        XCTAssertEqual(photo.x, CGFloat(1 - sensor.y), accuracy: 0.00001)
        XCTAssertEqual(photo.y, CGFloat(sensor.x), accuracy: 0.00001)
        XCTAssertEqual(frame.project(point), sensor)
        XCTAssertEqual(frame.measuredDepth(at: sensor), 2)
    }
    func testEvidenceDistinguishesSolidSupportFromARealPassage() {
        let wall = [evidenceFrame(), evidenceFrame(x: 0.3)]
        XCTAssertEqual(ScanEvidenceAnalysis.analyze(triangles: evidenceOpening, frames: wall).finding, .surface)
        let passage = [evidenceFrame(depth: 4), evidenceFrame(depth: 4, x: 0.3)]
        XCTAssertEqual(ScanEvidenceAnalysis.analyze(triangles: evidenceOpening, frames: passage).finding, .passage)
        let inconsistent = [evidenceFrame(), evidenceFrame(depth: 4, x: 0.3)]
        XCTAssertEqual(ScanEvidenceAnalysis.analyze(triangles: evidenceOpening, frames: inconsistent).finding, .mixed)
    }
    func testEvidenceOcclusionAndMissingDepthAreNotWallEvidence() {
        for depth: Float in [0, 1, .nan, .infinity] {
            let frames = [evidenceFrame(depth: depth), evidenceFrame(depth: depth, x: 0.3)]
            XCTAssertEqual(ScanEvidenceAnalysis.analyze(triangles: evidenceOpening, frames: frames).finding, .unknown)
        }
        var broken = evidenceFrame()
        broken.cameraToWorld = Array(repeating: 0, count: 16)
        XCTAssertNil(broken.project(.zero))
        broken = evidenceFrame(); broken.fx = .nan
        XCTAssertNil(broken.project(.zero))
        XCTAssertEqual(ScanEvidenceAnalysis.analyze(triangles: [], frames: [evidenceFrame()]).finding, .unknown)
    }
    func testEvidenceSamplesOpeningInteriorRatherThanItsJambs() {
        let samples = ScanEvidenceAnalysis.samples(triangles: evidenceOpening)
        XCTAssertEqual(samples.count, 8)
        XCTAssertTrue(samples.allSatisfy { abs($0.x) < 0.5 && abs($0.y) < 0.5 })
    }
    private func evidenceBuffer(_ format: OSType, width: Int = 32, height: Int = 24) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }
    func testEvidenceCacheRoundTripsPhotosCalibrationAndConfidenceThenExpires() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EvidenceTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScanEvidenceStore(root: root), roomID = UUID()
        let image = try evidenceBuffer(kCVPixelFormatType_32BGRA)
        let depth = try evidenceBuffer(kCVPixelFormatType_DepthFloat32)
        let confidence = try evidenceBuffer(kCVPixelFormatType_OneComponent8)
        XCTAssertTrue([kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_OneComponent32Float].contains(CVPixelBufferGetPixelFormatType(depth)), "Actual depth format: \(CVPixelBufferGetPixelFormatType(depth))")
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(confidence), kCVPixelFormatType_OneComponent8)
        for buffer in [image, depth, confidence] {
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
            for y in 0..<24 {
                let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
                if buffer === depth {
                    for x in 0..<32 { row.assumingMemoryBound(to: Float.self)[x] = x == 0 ? .nan : 2 }
                } else {
                    memset(row, buffer === confidence ? 2 : 255, CVPixelBufferGetBytesPerRow(buffer))
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
        CVPixelBufferLockBaseAddress(confidence, [])
        CVPixelBufferGetBaseAddress(confidence)!.assumingMemoryBound(to: UInt8.self)[1] = 0
        CVPixelBufferUnlockBaseAddress(confidence, [])
        let source = evidenceFrame()
        let snapshot = ScanEvidenceStore.Snapshot(image: image, depth: depth, confidence: confidence, record: source)
        let write = try await store.write(snapshot, roomID: roomID)
        guard case .saved(let hasDepth) = write else { return XCTFail("Expected an archived frame") }
        XCTAssertTrue(hasDepth)
        let frames = try await store.frames(roomID: roomID)
        let restored = try XCTUnwrap(frames.first)
        XCTAssertEqual(restored.cameraToWorld, source.cameraToWorld)
        XCTAssertEqual(restored.id, source.id)
        XCTAssertEqual(restored.depths[0], 0, "Nonfinite depth is missing, not JSON NaN")
        XCTAssertEqual(restored.depths[1], 0, "Low confidence excluded")
        XCTAssertEqual(restored.depths[2], 2)
        let jpeg = await store.photo(roomID: roomID, frame: restored)
        XCTAssertNotNil(jpeg.flatMap(UIImage.init(data:)))
        let expired = try await store.frames(roomID: roomID, now: Date().addingTimeInterval(ScanEvidencePolicy.lifetime + 10))
        XCTAssertTrue(expired.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(roomID.uuidString).path))
    }
    func testEvidenceDeleteIsScopedAndMissingDepthStillKeepsThePhoto() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EvidenceTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScanEvidenceStore(root: root), first = UUID(), second = UUID()
        let image = try evidenceBuffer(kCVPixelFormatType_32BGRA)
        CVPixelBufferLockBaseAddress(image, [])
        memset(CVPixelBufferGetBaseAddress(image), 255, CVPixelBufferGetBytesPerRow(image) * 24)
        CVPixelBufferUnlockBaseAddress(image, [])
        var frame = evidenceFrame(); frame.depthWidth = 0; frame.depthHeight = 0; frame.depths = []
        let snapshot = ScanEvidenceStore.Snapshot(image: image, depth: nil, confidence: nil, record: frame)
        _ = try await store.write(snapshot, roomID: first)
        _ = try await store.write(snapshot, roomID: second)
        try await store.remove(roomID: first)
        let deleted = try await store.frames(roomID: first), kept = try await store.frames(roomID: second)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(kept.count, 1)
        XCTAssertFalse(kept[0].hasDepth)
    }
    func testEvidenceQuotaStopsImagesWithoutTouchingTheSurvey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EvidenceTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScanEvidenceStore(root: root), roomID = UUID()
        let image = try evidenceBuffer(kCVPixelFormatType_32BGRA)
        CVPixelBufferLockBaseAddress(image, [])
        memset(CVPixelBufferGetBaseAddress(image), 255, CVPixelBufferGetBytesPerRow(image) * 24)
        CVPixelBufferUnlockBaseAddress(image, [])
        for _ in 0..<ScanEvidencePolicy.maximumFrames {
            let snapshot = ScanEvidenceStore.Snapshot(image: image, depth: nil, confidence: nil, record: evidenceFrame())
            guard case .saved = try await store.write(snapshot, roomID: roomID) else { return XCTFail("Premature quota") }
        }
        let snapshot = ScanEvidenceStore.Snapshot(image: image, depth: nil, confidence: nil, record: evidenceFrame())
        guard case .full = try await store.write(snapshot, roomID: roomID) else { return XCTFail("Frame quota not enforced") }
        let frames = try await store.frames(roomID: roomID)
        XCTAssertEqual(frames.count, ScanEvidencePolicy.maximumFrames)
        XCTAssertTrue(frames.allSatisfy { !$0.hasDepth })
    }
    func testNativePostProcessingUsesAppleBeautificationFirst() async throws {
        var calls:[RoomBuilder.ConfigurationOptions]=[]
        let outcome=try await NativeRoomPostProcessing.process { options in
            calls.append(options)
            return 42
        }
        XCTAssertEqual(calls,[.beautifyObjects])
        XCTAssertEqual(outcome.value,42)
        XCTAssertTrue(outcome.beautified)
        XCTAssertNil(outcome.fallbackReason)
    }
    func testNativePostProcessingFallsBackExplicitlyWithoutInventingGeometry() async throws {
        var calls:[RoomBuilder.ConfigurationOptions]=[]
        let document=ceilingRoom()
        let outcome=try await NativeRoomPostProcessing.process { options in
            calls.append(options)
            if options.contains(.beautifyObjects) { throw CocoaError(.coderInvalidValue) }
            return document
        }
        XCTAssertEqual(calls,[.beautifyObjects,[]])
        XCTAssertEqual(outcome.value,document)
        XCTAssertFalse(outcome.beautified)
        XCTAssertNotNil(outcome.fallbackReason)
    }
    func testNativePostProcessingPropagatesFailureAndNeverRetriesCancellation() async {
        for cancelled in [false,true] {
            var calls=0
            do {
                let _:NativeRoomPostProcessing.Outcome<Int>=try await NativeRoomPostProcessing.process { _ in
                    calls += 1
                    if cancelled { throw CancellationError() }
                    throw CocoaError(.coderInvalidValue)
                }
                XCTFail("A failed build must not be presented as a completed reconstruction")
            } catch {
                XCTAssertEqual(calls,cancelled ? 1 : 2)
                XCTAssertEqual(error is CancellationError,cancelled)
            }
        }
    }
    func testNativeCaptureArchiveIsSeparateFromFinalRoomAndRoundTrips() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let id=UUID(), input=["test":"opaque native input"]
        try NativeRoomPostProcessing.archiveInput(input,directory:directory,chunkID:id)
        let url=directory.appendingPathComponent(id.uuidString+".roomplan-capture")
        XCTAssertEqual(try JSONDecoder().decode([String:String].self,from:Data(contentsOf:url)),input)
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent(id.uuidString+".roomplan").path))
    }
    private func interruptedWallRoom() -> PlaquistoRoomDocument {
        var document=ceilingRoom()
        var left=document.room.walls.removeFirst()
        var right=left; right.id=UUID()
        left.end = .init(x:1,y:0,z:0); left.length.rawValue=1; left.height.rawValue=3
        left.localOutline=[.zero,.init(x:1,y:0,z:0),.init(x:1,y:3,z:0),.init(x:0,y:2.5,z:0)]
        right.start = .init(x:2,y:0,z:0); right.length.rawValue=2
        document.room.walls += [left,right]
        return document
    }
    func testRepairProposesOnlyGapAndPreservesRampedWallsAndOriginalScan() throws {
        let document=interruptedWallRoom()
        let proposals=SurveyRepair.proposals(in:document)
        XCTAssertEqual(proposals.count,1)
        XCTAssertEqual(try SurveyRepair.applying([],to:document),document)
        let repaired=try SurveyRepair.applying(proposals,to:document)
        XCTAssertEqual(repaired.initialRoom,document.initialRoom)
        XCTAssertEqual(Array(repaired.room.walls.dropLast()),document.room.walls)
        let bridge=try XCTUnwrap(repaired.room.walls.last)
        XCTAssertEqual(bridge.length.effectiveValue,1,accuracy:1e-6)
        XCTAssertEqual(bridge.effectiveOutline.map(\.y),[0,0,2.5,3])
        XCTAssertEqual(repaired.wallWorkIntents?.last?.use,.existingWall)
        XCTAssertTrue(SurveyRepair.proposals(in:repaired).isEmpty)
        let decoded=try PlaquistoRoomDocument.decode(repaired.encoded())
        XCTAssertEqual(decoded.room.walls.last?.effectiveOutline,bridge.effectiveOutline)
        XCTAssertEqual(decoded.room.walls.map(\.id),repaired.room.walls.map(\.id))
    }
    func testRepairCanBridgeRecognizedUnattachedOpeningsAfterConfirmation() throws {
        var document=interruptedWallRoom()
        let source=GeometryProvenance(source:.roomPlan)
        for kind in [RoomOpeningKind.door,.window,.passage,.glazedBay,.frenchDoor] {
            document.room.openings=[.init(kind:kind,center:.init(x:1.5,y:1,z:0),
                width:.init(rawValue:1,provenance:source),height:.init(rawValue:2,provenance:source),
                sillHeight:.init(rawValue:0,provenance:source),positionOnWall:.init(rawValue:0,provenance:source),provenance:source)]
            let proposals=SurveyRepair.proposals(in:document)
            XCTAssertEqual(proposals.count,1,"\(kind)")
            XCTAssertEqual(try SurveyRepair.applying([],to:document),document)
            let repaired=try SurveyRepair.applying(proposals,to:document)
            XCTAssertTrue(repaired.room.openings.isEmpty)
            XCTAssertEqual(repaired.room.walls.count,document.room.walls.count+1)
            XCTAssertEqual(repaired.initialRoom,document.initialRoom)
        }
    }
    func testUnknownOpeningRepairRequiresExplicitSelection() throws {
        var document=ceilingRoom()
        let wall=document.room.walls[0], source=GeometryProvenance(source:.roomPlan)
        let opening=PlaquistoOpening(wallID:wall.id,kind:.other,center:.init(x:2,y:1,z:0),
            width:.init(rawValue:1,provenance:source),height:.init(rawValue:1,provenance:source),
            sillHeight:.init(rawValue:0.5,provenance:source),positionOnWall:.init(rawValue:1.5,provenance:source),provenance:source)
        document.room.openings=[opening]; document.room.walls[0].openingIDs=[opening.id]
        let proposals=SurveyRepair.proposals(in:document)
        XCTAssertEqual(proposals.count,1)
        XCTAssertEqual(try SurveyRepair.applying([],to:document),document)
        let repaired=try SurveyRepair.applying(proposals,to:document)
        XCTAssertTrue(repaired.room.openings.isEmpty)
        XCTAssertTrue(repaired.room.walls[0].openingIDs.isEmpty)
        XCTAssertEqual(repaired.initialRoom,document.initialRoom)
        document.room.openings[0].width.manuallyValidated=true
        XCTAssertEqual(SurveyRepair.proposals(in:document).count,1)
    }
    func testGenericScanVoidAndFloorLevelPassageCanBothBeClosed() throws {
        var document=ceilingRoom()
        let source=GeometryProvenance(source:.roomPlan), wall=document.room.walls[0]
        let opening=PlaquistoOpening(wallID:wall.id,kind:.passage,center:.init(x:2,y:1.2,z:0),
            width:.init(rawValue:1,provenance:source),height:.init(rawValue:1,provenance:source),
            sillHeight:.init(rawValue:0.7,provenance:source),positionOnWall:.init(rawValue:1.5,provenance:source),provenance:source)
        document.room.openings=[opening]; document.room.walls[0].openingIDs=[opening.id]
        let suggestions=SurveyRepair.proposals(in:document)
        XCTAssertEqual(suggestions.count,1)
        XCTAssertTrue(try SurveyRepair.applying(suggestions,to:document).room.openings.isEmpty)
        document.room.openings[0].sillHeight.rawValue=0
        XCTAssertEqual(SurveyRepair.proposals(in:document).count,1)
        XCTAssertTrue(try SurveyRepair.applying(SurveyRepair.proposals(in:document),to:document).room.openings.isEmpty)
    }
    func testAllOpeningKindsIncludingManualValidatedOnesCanBeClosed() throws {
        for kind in [RoomOpeningKind.door,.window,.glazedBay,.frenchDoor,.passage,.other] {
            var document=ceilingRoom()
            let source=GeometryProvenance(source:.manual)
            let opening=PlaquistoOpening(wallID:document.room.walls[0].id,kind:kind,center:.init(x:2,y:1,z:0),
                width:.init(rawValue:1,provenance:source,manuallyValidated:true),
                height:.init(rawValue:2,provenance:source,manuallyValidated:true),
                sillHeight:.init(rawValue:0,provenance:source),positionOnWall:.init(rawValue:1.5,provenance:source),provenance:source)
            document.room.openings=[opening]; document.room.walls[0].openingIDs=[opening.id]
            let proposals=SurveyRepair.proposals(in:document)
            XCTAssertEqual(proposals.count,1)
            XCTAssertTrue(proposals.first?.title.contains(kind.title) == true)
            let repaired=try SurveyRepair.applying(proposals,to:document)
            XCTAssertTrue(repaired.room.openings.isEmpty)
            XCTAssertTrue(repaired.room.walls[0].openingIDs.isEmpty)
            XCTAssertEqual(repaired.initialRoom,document.initialRoom)
            XCTAssertEqual(repaired.room.walls[0].effectiveOutline,document.room.walls[0].effectiveOutline)
        }
    }
    func testRepairProposesWholeMissingSideWithoutCollinearNeighbors() throws {
        var document=ceilingRoom()
        document.room.walls.removeFirst()
        let proposals=SurveyRepair.proposals(in:document)
        XCTAssertEqual(proposals.count,1)
        let repaired=try SurveyRepair.applying(proposals,to:document)
        XCTAssertEqual(repaired.room.walls.count,4)
        XCTAssertEqual(repaired.room.walls.last?.length.effectiveValue,4)
        XCTAssertTrue(SurveyRepair.proposals(in:repaired).isEmpty)
    }
    func testRepairHandlesTwoCentimetreGapAndRejectsConflictingRepairs() throws {
        var document=interruptedWallRoom()
        let i=document.room.walls.count-1
        document.room.walls[i].start.x=1.02
        document.room.walls[i].length.rawValue=2.98
        let proposals=SurveyRepair.proposals(in:document)
        XCTAssertEqual(proposals.count,1)
        let repaired=try SurveyRepair.applying(proposals,to:document)
        XCTAssertEqual(try XCTUnwrap(repaired.room.walls.last).length.effectiveValue,0.02,accuracy:1e-6)
        XCTAssertThrowsError(try SurveyRepair.applying(proposals+proposals,to:document))
        XCTAssertEqual(document.room.walls.count,5)
    }
    @MainActor func testModelDisablesNativeTwistRecognizerButKeepsOrbitAndPinch() {
        let native=SCNView()
        native.allowsCameraControl=true
        XCTAssertTrue(native.gestureRecognizers?.contains { $0 is UIRotationGestureRecognizer } == true,
            "Verify native SceneKit really installs a twist recognizer on this runtime")
        let view=UprightSurveySceneView()
        view.allowsCameraControl=true
        let rotation=view.cameraControlConfiguration.rotationSensitivity
        let pan=view.cameraControlConfiguration.panSensitivity
        let truck=view.cameraControlConfiguration.truckSensitivity
        let translation=view.cameraControlConfiguration.allowsTranslation
        MaquetteStyle.configure(view,quality:.current)
        XCTAssertEqual(view.cameraControlConfiguration.rotationSensitivity,rotation)
        XCTAssertGreaterThan(rotation,0)
        XCTAssertEqual(view.cameraControlConfiguration.panSensitivity,pan)
        XCTAssertEqual(view.cameraControlConfiguration.truckSensitivity,truck)
        XCTAssertEqual(view.cameraControlConfiguration.allowsTranslation,translation)
        XCTAssertTrue(view.allowsCameraControl)
        XCTAssertGreaterThan(pan,0)
        for _ in 0..<2 {
            let recognizers=view.gestureRecognizers ?? []
            let twists=recognizers.compactMap { $0 as? UIRotationGestureRecognizer }
            let pinches=recognizers.compactMap { $0 as? UIPinchGestureRecognizer }
            let pans=recognizers.compactMap { $0 as? UIPanGestureRecognizer }
            XCTAssertTrue(twists.isEmpty,"SceneKit roll must not receive touches")
            XCTAssertFalse(pinches.isEmpty)
            XCTAssertTrue(pinches.allSatisfy(\.isEnabled))
            XCTAssertFalse(pans.isEmpty)
            XCTAssertTrue(pans.allSatisfy(\.isEnabled))
            view.allowsCameraControl=false
            view.allowsCameraControl=true
        }
    }
    @MainActor func testModelOrbitStaysInUpperHemisphere() {
        let view=UprightSurveySceneView()
        view.allowsCameraControl=true
        MaquetteStyle.configure(view,quality:.current)
        let controller=view.defaultCameraController
        XCTAssertEqual(controller.interactionMode,.orbitTurntable)
        let camera=SCNNode(); camera.camera=SCNCamera()
        camera.position=SCNVector3(0,5,5); camera.look(at:SCNVector3Zero)
        let scene=SCNScene(); scene.rootNode.addChildNode(camera)
        view.scene=scene; view.pointOfView=camera
        controller.pointOfView=camera; controller.target=SCNVector3Zero
        // Test the actual orbit, not the angle getter (some SDK versions expose
        // radians there even though their setters are documented in degrees).
        let viewport=CGSize(width:400,height:600)
        controller.beginInteraction(CGPoint(x:200,y:300),withViewport:viewport)
        controller.continueInteraction(CGPoint(x:300,y:300),withViewport:viewport,
            sensitivity:view.cameraControlConfiguration.rotationSensitivity)
        controller.endInteraction(CGPoint(x:300,y:300),withViewport:viewport,velocity:.zero)
        XCTAssertGreaterThan(abs(camera.position.x),0.1,"One-finger horizontal orbit must remain available")
        var lowest=Float.infinity, highest = -Float.infinity
        for sign:CGFloat in [1,-1] {
            controller.beginInteraction(CGPoint(x:200,y:300),withViewport:viewport)
            for step in 1...60 {
                controller.continueInteraction(CGPoint(x:200,y:300+sign*CGFloat(step)*20),withViewport:viewport,
                    sensitivity:view.cameraControlConfiguration.rotationSensitivity)
                XCTAssertGreaterThanOrEqual(camera.position.y,-0.001)
                lowest=min(lowest,camera.position.y); highest=max(highest,camera.position.y)
            }
            controller.endInteraction(CGPoint(x:200,y:300+sign*1200),withViewport:viewport,velocity:.zero)
        }
        XCTAssertLessThan(lowest,1)
        XCTAssertGreaterThan(highest,6)
    }

    @MainActor func testTwoFingerTranslationMovesCameraAndTargetWithoutRotating() {
        let view = UprightSurveySceneView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let scene = SCNScene(), camera = SCNNode()
        camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 5
        camera.position = SCNVector3(0, 5, 5); camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera); view.scene = scene; view.pointOfView = camera
        view.allowsCameraControl = true
        view.defaultCameraController.pointOfView = camera; view.defaultCameraController.target = SCNVector3Zero
        view.layoutSubviews()
        let pans = (view.gestureRecognizers ?? []).compactMap { $0 as? UIPanGestureRecognizer }
        XCTAssertEqual(pans.filter { $0.minimumNumberOfTouches == 2 && $0.maximumNumberOfTouches == 2 }.count, 1)
        XCTAssertTrue(pans.contains { $0.maximumNumberOfTouches == 1 })
        let position = camera.simdWorldPosition, orientation = camera.simdWorldOrientation
        view.translateCamera(by: CGPoint(x: 40, y: 30))
        let movement = camera.simdWorldPosition - position, target = view.defaultCameraController.target
        XCTAssertGreaterThan(simd_length(movement), 0.01)
        XCTAssertEqual(movement.x, target.x, accuracy: 0.0001)
        XCTAssertEqual(movement.y, target.y, accuracy: 0.0001)
        XCTAssertEqual(movement.z, target.z, accuracy: 0.0001)
        XCTAssertEqual(camera.simdWorldOrientation, orientation)
        view.translateCamera(by: CGPoint(x: -40, y: -30))
        XCTAssertLessThan(simd_length(camera.simdWorldPosition - position), 0.001)
    }

    func testPartitionEdgeScrollStartsAtThirtyPercentAndRemainsProgressive() {
        let size = CGSize(width: 400, height: 600)
        XCTAssertEqual(SurveyPlanEdgeScroll.delta(at: .init(x: 200, y: 300), size: size, elapsed: 1/60), .zero)
        XCTAssertEqual(SurveyPlanEdgeScroll.delta(at: .init(x: 120, y: 180), size: size, elapsed: 1/60), .zero)
        let left = SurveyPlanEdgeScroll.delta(at: .init(x: 60, y: 300), size: size, elapsed: 1/60)
        let edge = SurveyPlanEdgeScroll.delta(at: .init(x: 0, y: 300), size: size, elapsed: 1/60)
        XCTAssertGreaterThan(left.width, 0); XCTAssertGreaterThan(edge.width, left.width)
        XCTAssertEqual(edge.height, 0)
        let right = SurveyPlanEdgeScroll.delta(at: .init(x: 400, y: 300), size: size, elapsed: 1/60)
        XCTAssertEqual(right.width, -edge.width)
        XCTAssertLessThan(SurveyPlanEdgeScroll.delta(at: .init(x: 200, y: 600), size: size, elapsed: 1/60).height, 0)
        XCTAssertGreaterThan(SurveyPlanEdgeScroll.delta(at: .init(x: 200, y: 0), size: size, elapsed: 1/60).height, 0)
        XCTAssertEqual(SurveyPlanEdgeScroll.delta(at: .zero, size: size, elapsed: 100), SurveyPlanEdgeScroll.delta(at: .zero, size: size, elapsed: 0.05))
    }
    func testAddressLinksPreserveAccentsAndQueryCharacters() throws {
        let address="27 avenue de la Chapelle, Saint-Étienne & quartier #2"
        for destination in ProjectNavigationDestination.allCases {
            let url=try XCTUnwrap(destination.url(address:address))
            let parts=try XCTUnwrap(URLComponents(url:url,resolvingAgainstBaseURL:false))
            XCTAssertTrue(parts.queryItems?.contains(where:{$0.value==address}) == true)
            XCTAssertNil(parts.fragment)
            XCTAssertNil(destination.url(address:"  "))
        }
    }
    func testCeilingContourEditsKeepWallsAndRefuseNeighborOverlap() throws {
        let original=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        var proposal=try WallCeilingEstimate.propose(in:original.room)
        proposal.boundary=proposal.boundary.map { .init(x:$0.x*0.8,y:$0.y,z:$0.z) }
        let edited=try WallCeilingEstimate.applying(to:original,proposal:proposal,
            settings:.init(shape:.flat,lowHeight:2.5,highHeight:2.5),manuallyEdited:true)
        XCTAssertEqual(edited.room.walls,original.room.walls)
        XCTAssertEqual(edited.initialRoom,original.initialRoom)
        XCTAssertEqual(edited.room.ceilings[0].id,original.room.ceilings[0].id)
        XCTAssertEqual(edited.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) },9.6,accuracy:1e-6)
        let shared=try WallCeilingEstimate.split(original,ceilingID:original.room.ceilings[0].id,
            from:.init(x:2,y:0,z:-1),to:.init(x:2,y:0,z:4))
        var half=try XCTUnwrap(WallCeilingEstimate.manualProposals(in:shared.room).first)
        half.boundary=try WallCeilingEstimate.propose(in:original.room).boundary
        XCTAssertThrowsError(try WallCeilingEstimate.applying(to:shared,proposal:half,
            settings:.init(shape:.flat,lowHeight:2.5,highHeight:2.5),manuallyEdited:true))
    }

    func testDAEDiscardsOnlyCollapsedPrimitivesAndRejectsIncompleteSurfaces() throws {
        let a=RoomPoint.zero,b=RoomPoint(x:1,y:0,z:0),c=RoomPoint(x:0,y:1,z:0)
        let valid=SurveyDAEExport.Mesh(name:"Triangle",kind:"wall",triangles:[a,b,c,a,c,a])
        let xml=try SurveyDAEExport.xml(meshes:[valid],title:"Test",date:Date())
        XCTAssertTrue(xml.contains("<triangles count=\"1\""))
        XCTAssertTrue(xml.contains("count=\"9\""))
        let invalid=SurveyDAEExport.Mesh(name:"Donnée invalide",kind:"wall",triangles:[a,b,c,a,.init(x:.nan,y:0,z:0),c])
        XCTAssertThrowsError(try SurveyDAEExport.xml(meshes:[invalid],title:"Test",date:Date()))
        // A broken wall used to be silently skipped by the surface selection
        // helper. Export must not succeed with only the three remaining walls.
        var document=ceilingRoom()
        document.room.walls[0].localOutline=[a,a,a]
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Incomplet",checkpoints:[
            .init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        XCTAssertThrowsError(try SurveyDAEExport.meshes(for:survey)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Mur 1"))
        }
    }
    func testDAEExportsTriangularCeilingAndObliqueFloorWithoutLosingArea() throws {
        var document=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom([(0,0),(4,0),(2,3)]))
        let provenance=GeometryProvenance(source:.roomPlan)
        document.room.floors=[.init(boundaries:[[.init(x:0,y:0,z:0),.init(x:4,y:0,z:0),.init(x:2,y:0,z:3)]],
            referenceElevation:0,provenance:provenance)]
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Pièce triangulaire",checkpoints:[
            .init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        let meshes=try SurveyDAEExport.meshes(for:survey)
        XCTAssertEqual(meshes.filter { $0.kind == "wall" }.count,3)
        XCTAssertEqual(meshes.filter { $0.kind == "ceiling" }.count,1)
        XCTAssertEqual(meshes.filter { $0.kind == "floor" }.count,1)
        for mesh in meshes.filter({ $0.kind != "wall" }) {
            let area=stride(from:0,to:mesh.triangles.count,by:3).reduce(0.0) { area,i in
                let a=mesh.triangles[i],b=mesh.triangles[i+1],c=mesh.triangles[i+2]
                return area+abs((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))/2
            }
            XCTAssertEqual(area,6,accuracy:1e-8)
        }
        let xml=try SurveyDAEExport.xml(meshes:meshes,title:survey.name,date:survey.scanDate)
        XCTAssertTrue(XMLParser(data:Data(xml.utf8)).parse())
        XCTAssertEqual(xml.components(separatedBy:"<geometry id=").count-1,meshes.count)
    }

    func testPartitionPreviewUsesIndependentMirroredPlansOnBothFaces() throws {
        var document=ceilingRoom([(0,0),(4,0),(4,3),(0,3)])
        document=try SurveyPlanEditing.addingDoor(document,wallID:document.room.walls[0].id,width:0.9,height:2.1,position:0.8)
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Deux faces",checkpoints:[
            .init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        let surfaces=SurveyWorkGeometry.surfaces(in:survey)
        let wall=try XCTUnwrap(surfaces.first { $0.source.surfaceID == document.room.walls[0].id })
        let a=UUID(),b=UUID()
        var component=WorkComponentRecord(name:wall.name,surface:wall.surface)
        component.referenceSideRoomID=a; component.localLayoutSideIDs=[a,b]; component.surveySource=wall.source
        component.plans=[.init(sideRoomID:a,layers:[.init(sheetWidth:1200,sheetLength:2600)]),
                         .init(sideRoomID:b,layers:[.init(sheetWidth:900,sheetLength:2600)])]
        var work=WorkItem(id:UUID(),projectID:survey.projectID,name:"Cloison",type:.distributionPartition,
                         payload:.distributionPartition(.init()),createdAt:Date(),updatedAt:Date())
        work.components=[component]
        let snapshot=work
        func mesh(_ work:WorkItem) throws -> SurveyWorkPreview.Mesh {
            try XCTUnwrap(SurveyWorkPreview.make(survey:survey,surfaces:surfaces,works:[work],showJoints:true).first)
        }
        let first=try mesh(work)
        let origin=document.room.walls[0].start
        let direction=document.room.walls[0].direction
        let normal=RoomPoint(x:-direction.z,y:0,z:direction.x)
        func distance(_ p:RoomPoint)->Double { (p.x-origin.x)*normal.x+(p.z-origin.z)*normal.z }
        let front=first.joints.filter { distance($0)>0 },rear=first.joints.filter { distance($0)<0 }
        XCTAssertFalse(front.isEmpty); XCTAssertFalse(rear.isEmpty)
        for p in rear {
            // The mirrored local x axis still maps onto the physical wall.
            let x=(p.x-origin.x)*direction.x+(p.z-origin.z)*direction.z
            XCTAssertGreaterThanOrEqual(x,-0.001); XCTAssertLessThanOrEqual(x,4.001)
            XCTAssertFalse(x>0.8 && x<1.7 && p.y>0.001 && p.y<2.099)
        }
        work.components[0].plans[1].layers[0].offset.x=200
        let changed=try mesh(work)
        XCTAssertEqual(changed.joints.filter { distance($0)>0 },front)
        XCTAssertNotEqual(changed.joints.filter { distance($0)<0 },rear)
        // wallSolid collects boundary edges in a dictionary: primitive order
        // is not stable, but changing a rear layout must preserve every face.
        func canonicalTriangles(_ points:[RoomPoint])->[String] {
            stride(from:0,to:points.count,by:3).map { index in
                points[index..<index+3].map { "\($0.x),\($0.y),\($0.z)" }.sorted().joined(separator:";")
            }.sorted()
        }
        XCTAssertEqual(canonicalTriangles(first.triangles),canonicalTriangles(changed.triangles))
        XCTAssertEqual(snapshot.components[0],component)
        XCTAssertTrue(SurveyWorkPreview.make(survey:survey,surfaces:surfaces,works:[work],showJoints:false).allSatisfy { $0.joints.isEmpty })
        work.components[0].plans.removeLast()
        XCTAssertFalse(try mesh(work).joints.filter { distance($0)<0 }.isEmpty,"Legacy front-only partitions also show a back face")
    }

    @MainActor func testWorkPreviewAddsLiningDepthCeilingDropAndSavedJointsWithoutChangingScan() throws {
        let document = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom([(0,0),(4,0),(4,3),(0,3)]))
        let survey = ProjectSurveyRecord(projectID: UUID(), name: "Atelier", checkpoints: [
            .init(roomID: document.room.id, document: document, spatialLinkState: .sharedWorldSpace)])
        let surfaces = SurveyWorkGeometry.surfaces(in: survey)
        let wall = try XCTUnwrap(surfaces.first { $0.source.kind == .wall })
        let ceiling = try XCTUnwrap(surfaces.first { $0.source.kind == .ceiling })
        func work(_ selection: SurveyWorkSurface, _ payload: WorkConfiguration, type: WorkType) -> WorkItem {
            var work = WorkItem(id: UUID(), projectID: survey.projectID, name: "Test", type: type, payload: payload, createdAt: Date(), updatedAt: Date())
            var component = WorkComponentRecord(name: selection.name, surface: selection.surface)
            component.surveySource = selection.source
            component.plans = [.init(layers: [.init(sheetWidth: 1200, sheetLength: 2400)])]
            work.components = [component]
            return work
        }
        var lining = FurringLiningConfiguration(); lining.finishedDepthMM = 140
        let works = [work(wall, .furringLining(lining), type: .peripheralLiningFurrings),
                     work(ceiling, .ceiling(.init(plenum: 20)), type: .ceilingOnFurring)]
        let before = try JSONEncoder().encode(survey)
        let meshes = SurveyWorkPreview.make(survey: survey, surfaces: surfaces, works: works, showJoints: true)
        XCTAssertEqual(meshes.count, 2)
        let top = try XCTUnwrap(meshes.first { $0.surfaceID == ceiling.id })
        XCTAssertEqual(try XCTUnwrap(top.triangles.first?.y), try XCTUnwrap(ceiling.triangles.first?.y) - 0.2, accuracy: 0.001)
        XCTAssertFalse(top.joints.isEmpty)
        let panel = try XCTUnwrap(meshes.first { $0.surfaceID == wall.id })
        XCTAssertFalse(panel.joints.isEmpty)
        let normal = RoomPoint(x: -document.room.walls[0].direction.z, y: 0, z: document.room.walls[0].direction.x)
        let origin = document.room.walls[0].start
        let distances = panel.triangles.map { p in (p.x-origin.x)*normal.x + (p.z-origin.z)*normal.z }
        XCTAssertEqual(try XCTUnwrap(distances.max()), 0.14, accuracy: 0.001)
        XCTAssertTrue(SurveyWorkPreview.make(survey: survey, surfaces: surfaces, works: works, showJoints: false).allSatisfy { $0.joints.isEmpty })
        XCTAssertEqual(try JSONDecoder().decode(ProjectSurveyRecord.self, from: before), survey)
        XCTAssertTrue(SurveyWorkPreview.make(survey: survey, surfaces: surfaces, works: [], showJoints: true).isEmpty)
        let view = UprightSurveySceneView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        var parent = SurveySurfaceScene(survey: survey, surfaces: surfaces, kind: .ceiling, selected: [], claimed: [], onTap: { _ in }, showsCeilings: true, previewWorks: works)
        let coordinator = parent.makeCoordinator()
        parent.update(view, coordinator: coordinator)
        XCTAssertEqual(view.scene?.rootNode.childNode(withName: "work-preview", recursively: false)?.childNodes.count, 2)
        let finished = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "work-preview", recursively: false)?.childNode(withName: wall.id, recursively: false))
        XCTAssertEqual(finished.opacity, 1)
        let color = try XCTUnwrap(finished.geometry?.firstMaterial?.diffuse.contents as? UIColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1, accuracy: 0.01); XCTAssertEqual(g, 0.78, accuracy: 0.01)
        XCTAssertTrue(view.scene?.rootNode.childNode(withName: ceiling.id, recursively: false)?.isHidden == true)
        let camera = try XCTUnwrap(view.pointOfView), position = camera.position
        parent.previewWorks = []; parent.update(view, coordinator: coordinator)
        XCTAssertEqual(view.scene?.rootNode.childNode(withName: wall.id, recursively: false)?.opacity, 1)
        XCTAssertTrue(view.scene?.rootNode.childNode(withName: ceiling.id, recursively: false)?.isHidden == false)
        XCTAssertEqual(camera.position.x, position.x); XCTAssertEqual(camera.position.y, position.y)
        XCTAssertEqual(coordinator.geometryBuildCount, 1)
    }

    func testDAEGeometryKeepsWorldPlacementAndDoesNotInventCeilings() throws {
        let document=ceilingRoom()
        var survey=ProjectSurveyRecord(projectID:UUID(),name:"Cuisine & salon",checkpoints:[
            .init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        let meshes=try SurveyDAEExport.meshes(for:survey)
        XCTAssertEqual(meshes.count,4)
        XCTAssertTrue(meshes.allSatisfy { $0.kind == "wall" })
        survey.checkpoints[0].transformToSurvey.values[12]=10
        survey.checkpoints[0].transformToSurvey.values[14] = -7
        let moved=try SurveyDAEExport.meshes(for:survey)
        for (a,b) in zip(meshes.flatMap(\.triangles),moved.flatMap(\.triangles)) {
            XCTAssertEqual(b.x,a.x+10,accuracy:1e-8)
            XCTAssertEqual(b.z,a.z-7,accuracy:1e-8)
            XCTAssertEqual(b.y,a.y,accuracy:1e-8)
        }
        XCTAssertEqual(survey.checkpoints[0].document,document)
        survey.checkpoints[0].transformToSurvey.values[0]=2
        XCTAssertThrowsError(try SurveyDAEExport.meshes(for:survey))
    }

    func testDAERejectsUnlinkedRoomsAndInvalidTriangles() throws {
        let document=ceilingRoom()
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Non raccordé",checkpoints:[
            .init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace),
            .init(roomID:UUID(),document:document,spatialLinkState:.needsLink)])
        XCTAssertThrowsError(try SurveyDAEExport.meshes(for:survey))
        for points in [[RoomPoint.zero],Array(repeating:.zero,count:3),[.zero,.init(x:.infinity,y:0,z:0),.init(x:0,y:1,z:0)]] {
            XCTAssertThrowsError(try SurveyDAEExport.xml(meshes:[.init(name:"Invalid",kind:"wall",triangles:points)],title:"Test",date:Date()))
        }
        XCTAssertThrowsError(try SurveyDAEExport.xml(meshes:[],title:"Vide",date:Date()))
    }

    func testDAEXMLAndFileAreSelfContainedAndPreserveEditedRoof() throws {
        let document=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Cuisine & salon <test>",checkpoints:[
            .init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        let meshes=try SurveyDAEExport.meshes(for:survey)
        XCTAssertTrue(meshes.contains { $0.kind == "ceiling" })
        let url=try SurveyDAEExport.write(survey)
        let data=try Data(contentsOf:url), xml=try XCTUnwrap(String(data:data,encoding:.utf8))
        XCTAssertEqual(url.pathExtension,"dae")
        XCTAssertTrue(XMLParser(data:data).parse())
        XCTAssertTrue(xml.contains("Cuisine &amp; salon &lt;test&gt;"))
        XCTAssertTrue(xml.contains("meter=\"1\""))
        XCTAssertTrue(xml.contains("<up_axis>Y_UP</up_axis>"))
        XCTAssertTrue(xml.contains("semantic=\"NORMAL\""))
        XCTAssertFalse(xml.contains("library_cameras"))
        XCTAssertFalse(xml.contains("library_images"))
        XCTAssertEqual(xml.components(separatedBy:"<geometry id=").count-1,meshes.count)
        // Retained in the test container for independent COLLADA importer validation.
        let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"org.khronos.collada.digital-asset-exchange")
        attachment.name="Plaquisto-DAE-validation.dae"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testDAEIncludesFloorAtRealElevationAndKeepsWindowHole() throws {
        var document=ceilingRoom()
        let p=GeometryProvenance(source:.roomPlan), wallID=document.room.walls[0].id
        document.room.openings=[.init(wallID:wallID,kind:.window,center:.init(x:1.5,y:1.5,z:0),
            width:.init(rawValue:1,provenance:p),height:.init(rawValue:1,provenance:p),
            sillHeight:.init(rawValue:1,provenance:p),positionOnWall:.init(rawValue:1,provenance:p),provenance:p)]
        document.room.walls[0].openingIDs=document.room.openings.map(\.id)
        document.room.floors=[.init(boundaries:[[.init(x:0,y:0,z:0),.init(x:4,y:0,z:0),.init(x:4,y:0,z:3),.init(x:0,y:0,z:3)]],referenceElevation:0.2,provenance:p)]
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Trou",checkpoints:[.init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        let meshes=try SurveyDAEExport.meshes(for:survey)
        let wall=try XCTUnwrap(meshes.first { $0.kind == "wall" })
        let triangles=wall.triangles
        let area=stride(from:0,to:triangles.count,by:3).reduce(0.0) { area,i in
            let a=triangles[i],b=triangles[i+1],c=triangles[i+2]
            return area+abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/2
        }
        XCTAssertEqual(area,9,accuracy:1e-8) // 4 × 2.5 minus the 1 m² window.
        let floor=try XCTUnwrap(meshes.first { $0.kind == "floor" })
        XCTAssertTrue(floor.triangles.allSatisfy { abs($0.y-0.2) < 1e-8 })
    }

    func testProjectGallerySearchIncludesCaptureAddressDatesAndAccents() throws {
        let date=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-06T12:00:00Z"))
        let project=ProjectItem(id:UUID(),name:"Rénovation",client:"Dupont",address:"12 rue Victor Hugo, Lyon 69002",notes:"",works:[],createdAt:date,updatedAt:date)
        var survey=ProjectSurveyRecord(projectID:project.id,name:"Cuisine",createdAt:date)
        survey.captureAddress="8 allée des Cèdres, Écully 69130"
        for query in ["renovation","DUPONT", "lyon 69002", "ECULLY cedres", "69130", "06/10/2026", "6 octobre 2026", "2026-10-06", ""] {
            XCTAssertTrue(ProjectGalleryIndex.matches(project,surveys:[survey],query:query),query)
        }
        XCTAssertFalse(ProjectGalleryIndex.matches(project,surveys:[survey],query:"Paris"))
        XCTAssertFalse(ProjectGalleryIndex.matches(project,surveys:[survey],query:"lyon 75001"))
        XCTAssertEqual(try JSONDecoder().decode(ProjectSurveyRecord.self,from:JSONEncoder().encode(survey)).captureAddress,survey.captureAddress)
        survey.captureAddress=nil
        XCTAssertNil(try JSONDecoder().decode(ProjectSurveyRecord.self,from:JSONEncoder().encode(survey)).captureAddress)
    }

    func testProjectGallerySummaryCountsWorkAreaNotFacingLayers() {
        let date=Date(), id=UUID()
        var ceiling=CeilingConfiguration(); ceiling.enteredArea=12; ceiling.layers=2
        let work=WorkItem(id:UUID(),projectID:id,name:"Plafond",type:.ceilingOnFurring,payload:.ceiling(ceiling),createdAt:date,updatedAt:date)
        let project=ProjectItem(id:id,name:"Test",client:"",address:"",notes:"",works:[work],createdAt:date,updatedAt:date)
        let summary=ProjectGalleryIndex.summary(project)
        XCTAssertEqual(summary.count,1)
        XCTAssertEqual(summary.first?.title,"Plafond")
        XCTAssertEqual(summary.first?.area,12)
    }

    func testPlanCameraRotationAlignsEachWallWithoutChangingGeometry() throws {
        let document=ceilingRoom(), center=RoomPoint(x:2,y:0,z:1.5)
        let before=document
        var current:UUID?
        for expected in document.room.walls {
            let wall=try XCTUnwrap(SurveyPlanCamera.nextWall(document.room.walls,after:current))
            XCTAssertEqual(wall.id,expected.id)
            current=wall.id
            let angle=SurveyPlanCamera.horizontalAngle(for:wall)
            let a=SurveyPlanCamera.rotated(wall.start,around:center,angle:angle)
            let b=SurveyPlanCamera.rotated(wall.effectiveEnd,around:center,angle:angle)
            XCTAssertEqual(a.z,b.z,accuracy:1e-9)
            XCTAssertGreaterThan(b.x,a.x)
            XCTAssertEqual((b-a).length,wall.length.effectiveValue,accuracy:1e-9)
        }
        XCTAssertEqual(SurveyPlanCamera.nextWall(document.room.walls,after:current)?.id,document.room.walls.first?.id)
        XCTAssertEqual(document,before)
        XCTAssertNil(SurveyPlanCamera.nextWall([],after:nil))
    }
    func testPlanCameraInverseKeepsEditingCoordinatesAfterObliqueRotation() {
        let center=RoomPoint(x:4,y:2,z:-3)
        for angle in [0.0,0.43,Double.pi/2,Double.pi,-Double.pi/3] {
            for point in [RoomPoint(x:-2,y:2,z:7),.init(x:6,y:2,z:1),center] {
                let rotated=SurveyPlanCamera.rotated(point,around:center,angle:angle)
                let restored=SurveyPlanCamera.rotated(rotated,around:center,angle:-angle)
                XCTAssertEqual(restored.x,point.x,accuracy:1e-9)
                XCTAssertEqual(restored.z,point.z,accuracy:1e-9)
                XCTAssertEqual(restored.y,point.y)
            }
        }
    }
    func testRemovingDesignedPartitionRemovesOnlyItsOpeningsAndIntent() throws {
        let original=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        var before=try SurveyPlanEditing.addingPartition(original,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:3),height:2.5)
        let id=try XCTUnwrap(before.room.walls.last?.id)
        before=try SurveyPlanEditing.addingDoor(before,wallID:id,width:0.83,height:2.04,position:0.8)
        before=try SurveyPlanEditing.addingDoor(before,wallID:before.room.walls[0].id,width:0.73,height:2.04,position:0.4)
        let remainingOpening=try XCTUnwrap(before.room.openings.last)
        let after=try SurveyPlanEditing.removingPartition(before,id:id)
        XCTAssertEqual(after.room.walls.map(\.id),original.room.walls.map(\.id))
        XCTAssertEqual(after.room.openings,[remainingOpening])
        XCTAssertFalse(after.wallWorkIntents?.contains { $0.wallID == id } ?? false)
        XCTAssertEqual(after.room.ceilings,before.room.ceilings)
        XCTAssertEqual(after.room.slopes,before.room.slopes)
        XCTAssertEqual(after.initialRoom,before.initialRoom)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(after.encoded()),after)
        XCTAssertThrowsError(try SurveyPlanEditing.removingPartition(after,id:id))
        XCTAssertThrowsError(try SurveyPlanEditing.removingPartition(after,id:after.room.walls[0].id))
        // The editor's undo keeps this complete pre-deletion snapshot.
        XCTAssertEqual(try PlaquistoRoomDocument.decode(before.encoded()),before)
    }
    func testRemovingDoorKeepsItsPartitionAndOtherOpenings() throws {
        var before=try SurveyPlanEditing.addingPartition(ceilingRoom(),start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:3),height:2.5)
        let wallID=try XCTUnwrap(before.room.walls.last?.id)
        before=try SurveyPlanEditing.addingDoor(before,wallID:wallID,width:0.73,height:2.04,position:0.1)
        let removed=try XCTUnwrap(before.room.openings.last?.id)
        before=try SurveyPlanEditing.addingDoor(before,wallID:wallID,width:0.83,height:2.04,position:1.5)
        let after=try SurveyPlanEditing.removingOpening(before,id:removed)
        XCTAssertEqual(after.room.walls.count,before.room.walls.count)
        XCTAssertEqual(after.room.openings.count,1)
        XCTAssertFalse(after.room.walls.flatMap(\.openingIDs).contains(removed))
        XCTAssertEqual(after.initialRoom,before.initialRoom)
        try after.validate()
    }
    func testDoorPlacementKeepsWallSnapWhileChangingReceivingRoom() throws {
        let document=try SurveyPlanEditing.addingPartition(ceilingRoom(),start:.init(x:0,y:0,z:1),end:.init(x:4,y:0,z:1),height:2.5)
        let wall=try XCTUnwrap(document.room.walls.last)
        let first=try XCTUnwrap(DoorPlanGeometry.placement(point:.init(x:2,y:0,z:1),walls:[wall],width:0.83,
            latchedWallID:nil,previous:.positive,captureDistance:0.1))
        var nearby=wall; nearby.id=UUID(); nearby.start.z += 0.3; nearby.end.z += 0.3
        let rightRoom=try XCTUnwrap(DoorPlanGeometry.placement(point:.init(x:2,y:0,z:1.3),walls:[wall,nearby],width:0.83,
            latchedWallID:first.wallID,previous:first.side,captureDistance:0.1))
        XCTAssertEqual(rightRoom.wallID,wall.id)
        XCTAssertEqual(rightRoom.position,first.position)
        XCTAssertEqual(rightRoom.center.z,1)
        XCTAssertEqual(rightRoom.side,.positive)
        let other=try XCTUnwrap(DoorPlanGeometry.placement(point:.init(x:2,y:0,z:0.7),walls:[wall],width:0.83,
            latchedWallID:wall.id,previous:rightRoom.side,captureDistance:0.1))
        XCTAssertEqual(other.side,.negative)
        XCTAssertEqual(other.position,first.position)
        XCTAssertEqual(DoorPlanGeometry.openingSide(point:.init(x:2,y:0,z:1.005),wall:wall,previous:.negative,deadZone:0.025),.negative)
        XCTAssertNil(DoorPlanGeometry.placement(point:.init(x:2,y:0,z:3),walls:[wall],width:0.83,
            latchedWallID:wall.id,previous:.positive,captureDistance:0.1))
    }
    func testDoorHandingFromPushSideAndRotationIndependentGesture() throws {
        XCTAssertTrue(DoorPlanGeometry.hingeAtStart(handing:.right,side:.positive))
        XCTAssertFalse(DoorPlanGeometry.hingeAtStart(handing:.left,side:.positive))
        XCTAssertFalse(DoorPlanGeometry.hingeAtStart(handing:.right,side:.negative))
        XCTAssertTrue(DoorPlanGeometry.hingeAtStart(handing:.left,side:.negative))
        for angle in [0.0,0.7,Double.pi,-1.4] {
            let u=RoomPoint(x:cos(angle),y:0,z:sin(angle)),n=RoomPoint(x:-sin(angle),y:0,z:cos(angle))
            let drawn=try SurveyPlanEditing.addingPartition(ceilingRoom(),start:.init(x:10,y:0,z:10),end:.init(x:10,y:0,z:10)+u*4,height:2.5)
            let wall=try XCTUnwrap(drawn.room.walls.last)
            XCTAssertEqual(DoorPlanGeometry.openingSide(point:wall.start+u*2+n*0.2,wall:wall,previous:.negative,deadZone:0.02),.positive)
            XCTAssertEqual(DoorPlanGeometry.openingSide(point:wall.start+u*2-n*0.2,wall:wall,previous:.positive,deadZone:0.02),.negative)
        }
    }
    func testDoorSideOnlyEditPersistsWithoutChangingReservation() throws {
        let original=ceilingRoom(),wall=original.room.walls[0]
        let withDoor=try SurveyPlanEditing.addingDoor(original,wallID:wall.id,width:0.83,height:2.04,position:1,handing:.right,openingSide:.positive)
        let door=try XCTUnwrap(withDoor.room.openings.last)
        let flipped=try SurveyPlanEditing.movingDoor(withDoor,id:door.id,position:1,openingSide:.negative)
        let stored=try PlaquistoRoomDocument.decode(flipped.encoded()).room.openings.last
        XCTAssertEqual(stored?.doorOpeningSide,.negative)
        XCTAssertEqual(stored?.doorHanding,.right)
        XCTAssertEqual(stored?.center,door.center)
        XCTAssertEqual(stored?.width,door.width)
        XCTAssertEqual(stored?.height,door.height)
        let handed=try SurveyPlanEditing.changingOpening(flipped,id:door.id,width:0.83,height:2.04,sill:0,position:1,handing:.left)
        XCTAssertEqual(handed.room.openings.last?.doorOpeningSide,.negative)
    }
    func testFinishedLiningDepthIsExplicitAndPersists() throws {
        var c=FurringLiningConfiguration(); c.finishedDepthMM=140
        XCTAssertEqual(SurveyPlanFinishes.depth(.furringLining(c)),0.14)
        let restored=try JSONDecoder().decode(FurringLiningConfiguration.self,from:JSONEncoder().encode(c))
        XCTAssertEqual(restored.finishedDepthMM,140)
        XCTAssertNil(SurveyPlanFinishes.depth(.furringLining(.init())))
        c.finishedDepthMM = .infinity
        XCTAssertNil(SurveyPlanFinishes.depth(.furringLining(c)))
    }
    func testFinishedPlanAreasAndClearancesIncludePartitionThickness() throws {
        let original=ceilingRoom()
        let depths=Dictionary(uniqueKeysWithValues:original.room.walls.map { ($0.id,0.1) })
        let shell=SurveyPlanFinishes.finishedWalls(in:original,depths:depths)
        XCTAssertEqual(SurveyPlanFinishes.area(shell.map(\.start)),3.8*2.8,accuracy:1e-6)
        let designed=try SurveyPlanEditing.addingPartition(original,start:.init(x:2,y:0,z:0.1),end:.init(x:2,y:0,z:2.9),height:2.5,thickness:0.098)
        let zones=SurveyPlanFinishes.zones(in:designed,depths:depths)
        XCTAssertEqual(zones.count,2)
        XCTAssertEqual(zones.reduce(0) { $0+SurveyPlanFinishes.area($1.map(\.start)) },3.8*2.8-0.098*2.8,accuracy:1e-6)
        let (left,right)=SurveyPlanFinishes.clearances(on:original.room.walls[0],at:.init(x:2,y:0,z:0),direction:.init(x:0,y:0,z:1),thickness:0.072)
        XCTAssertEqual(left,1.964,accuracy:1e-6); XCTAssertEqual(right,1.964,accuracy:1e-6)
        XCTAssertEqual(designed.room.walls.last?.thickness?.effectiveValue,0.098)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(designed.encoded()),designed)
    }
    func testPartitionCanUseCustomReservationButRejectsBadDimensions() throws {
        let original=ceilingRoom(), wall=original.room.walls[0]
        let withDoor=try SurveyPlanEditing.addingDoor(original,wallID:wall.id,width:1.1,height:2.04,position:1)
        XCTAssertEqual(withDoor.room.openings[0].width.effectiveValue,1.1)
        XCTAssertThrowsError(try SurveyPlanEditing.addingDoor(original,wallID:wall.id,width:.nan,height:2,position:1))
        XCTAssertThrowsError(try SurveyPlanEditing.addingPartition(original,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:3),height:2.5,thickness:0))
    }
    func testBentPartitionSplitsCeilingWithoutChangingRoofPlanes() throws {
        let before=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        var after=try SurveyPlanEditing.addingPartition(before,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:1.5),height:2.5)
        after=try SurveyPlanEditing.addingPartition(after,start:.init(x:2,y:0,z:1.5),end:.init(x:4,y:0,z:1.5),height:2.5)
        let split=try WallCeilingEstimate.splitForNewPartition(before:before,after:after,depths:[:])
        XCTAssertEqual(split.room.ceilings.count,2)
        XCTAssertEqual(split.room.slopes.reduce(0){$0+PlaquistoSurfaceGeometry.area(of:$1)},12,accuracy:1e-6)
        XCTAssertTrue(split.room.slopes.allSatisfy { $0.splitOrigin != nil })
        XCTAssertEqual(split.room.walls,after.room.walls)
        XCTAssertEqual(split.initialRoom,before.initialRoom)
    }
    func testPartitionEndingOnFinishedFacesStillSplitsRawCeiling() throws {
        let before=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let depths=Dictionary(uniqueKeysWithValues:before.room.walls.map { ($0.id,0.15) })
        let after=try SurveyPlanEditing.addingPartition(before,start:.init(x:2,y:0,z:0.15),end:.init(x:2,y:0,z:2.85),height:2.5)
        let split=try WallCeilingEstimate.splitForNewPartition(before:before,after:after,depths:depths)
        XCTAssertEqual(split.room.ceilings.count,2)
        XCTAssertEqual(split.room.slopes.reduce(0){$0+PlaquistoSurfaceGeometry.area(of:$1)},12,accuracy:1e-6)
        XCTAssertEqual(split.room.walls.last?.start.z,0.15)
    }
    func testOpenPartitionDoesNotOfferCeilingSplit() throws {
        let before=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let after=try SurveyPlanEditing.addingPartition(before,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:1),height:2.5)
        XCTAssertThrowsError(try WallCeilingEstimate.splitForNewPartition(before:before,after:after,depths:[:]))
    }
    func testDeletingDividerReunitesCeilingAndPreservesPansAcrossReload() throws {
        for legacy in [false,true] {
            let original=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
            let drawn=try SurveyPlanEditing.addingFittedPartition(original,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:3))
            let divider=try XCTUnwrap(drawn.room.walls.last)
            var split=try WallCeilingEstimate.splitForNewPartition(before:original,after:drawn,depths:[:])
            XCTAssertEqual(split.room.ceilings.count,2)
            if legacy {
                for i in split.room.slopes.indices { split.room.slopes[i].splitOrigin?.partitionWallIDs=nil }
            } else {
                XCTAssertTrue(split.room.slopes.allSatisfy { $0.splitOrigin?.partitionWallIDs == [divider.id] })
            }
            let reloaded=try PlaquistoRoomDocument.decode(split.encoded())
            let merged=try SurveyPlanEditing.removingPartition(reloaded,id:divider.id)
            XCTAssertEqual(merged.room.ceilings.count,1)
            XCTAssertEqual(Set(merged.room.ceilings[0].slopeIDs),Set(split.room.slopes.map(\.id)))
            XCTAssertEqual(merged.room.slopes.map(\.plane),split.room.slopes.map(\.plane))
            XCTAssertEqual(merged.room.slopes.map(\.boundaries),split.room.slopes.map(\.boundaries))
            XCTAssertEqual(merged.room.slopes.reduce(0){$0+PlaquistoSurfaceGeometry.area(of:$1)},12,accuracy:1e-6)
            XCTAssertEqual(merged.initialRoom,original.initialRoom)
            XCTAssertEqual(try PlaquistoRoomDocument.decode(merged.encoded()),merged)
        }
    }
    func testDuplicateSurveyRemapsDividerHistoryAndKeepsAutomaticCeilingReunion() throws {
        let original = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom())
        let drawn = try SurveyPlanEditing.addingFittedPartition(original, start: .init(x:2,y:0,z:0), end: .init(x:2,y:0,z:3))
        let split = try WallCeilingEstimate.splitForNewPartition(before: original, after: drawn, depths: [:])
        let copy = split.remappingDomainIDs(preservingSplitHistory: true)
        let divider = try XCTUnwrap(copy.room.walls.last)
        XCTAssertTrue(copy.room.slopes.allSatisfy { $0.splitOrigin?.partitionWallIDs == [divider.id] })
        XCTAssertNotEqual(copy.room.slopes[0].splitOrigin?.operationID, split.room.slopes[0].splitOrigin?.operationID)
        XCTAssertNotEqual(copy.room.slopes[0].splitOrigin?.sourceSlopeID, split.room.slopes[0].splitOrigin?.sourceSlopeID)
        XCTAssertEqual(copy.room.slopes.map(\.boundaries), split.room.slopes.map(\.boundaries))
        let loaded = try PlaquistoRoomDocument.decode(copy.encoded())
        let merged = try SurveyPlanEditing.removingPartition(loaded, id: divider.id)
        XCTAssertEqual(merged.room.ceilings.count, 1)
        XCTAssertEqual(split.room.ceilings.count, 2)
        XCTAssertEqual(split.remappingDomainIDs().room.slopes.compactMap(\.splitOrigin), [])
    }

    func testDeletingBentDividerReunitesOnlyItsCeiling() throws {
        let original=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        var drawn=try SurveyPlanEditing.addingPartition(original,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:1.5),height:2.5)
        let first=try XCTUnwrap(drawn.room.walls.last?.id)
        drawn=try SurveyPlanEditing.addingPartition(drawn,start:.init(x:2,y:0,z:1.5),end:.init(x:4,y:0,z:1.5),height:2.5)
        let last=try XCTUnwrap(drawn.room.walls.last?.id)
        let split=try WallCeilingEstimate.splitForNewPartition(before:original,after:drawn,depths:[:])
        let merged=try SurveyPlanEditing.removingPartition(split,id:first)
        XCTAssertEqual(merged.room.ceilings.count,1)
        XCTAssertTrue(merged.room.walls.contains { $0.id==last })
        XCTAssertEqual(try SurveyPlanEditing.removingPartition(merged,id:last).room.ceilings,merged.room.ceilings)
    }
    func testDeletingPartitionDoesNotUndoExplicitOrLaterCeilingCuts() throws {
        let original=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let drawn=try SurveyPlanEditing.addingPartition(original,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:3),height:2.5)
        let divider=try XCTUnwrap(drawn.room.walls.last?.id)
        let manual=try WallCeilingEstimate.split(drawn,ceilingID:original.room.ceilings[0].id,
            from:.init(x:2,y:0,z:0),to:.init(x:2,y:0,z:3))
        XCTAssertEqual(try SurveyPlanEditing.removingPartition(manual,id:divider).room.ceilings,manual.room.ceilings)
        let automatic=try WallCeilingEstimate.splitForNewPartition(before:original,after:drawn,depths:[:])
        let recut=try WallCeilingEstimate.split(automatic,ceilingID:automatic.room.ceilings[0].id,
            from:.init(x:0,y:0,z:1.5),to:.init(x:4,y:0,z:1.5))
        XCTAssertEqual(try SurveyPlanEditing.removingPartition(recut,id:divider).room.ceilings,recut.room.ceilings)
    }
    func testRedrawnContourPreservesOriginalAndMatchingOpening() throws {
        let original=ceilingRoom()
        let before=try SurveyPlanEditing.addingDoor(original,wallID:original.room.walls[0].id,width:0.83,height:2.04,position:1)
        let ring=try XCTUnwrap(ScanEnclosedSpaces.wallsBySpace(in:before.room).first)
        let next=try SurveyPlanEditing.replacingContour(before,walls:ring,contour:ring.map(\.start))
        XCTAssertEqual(next.room.openings,before.room.openings)
        XCTAssertEqual(next.initialRoom,before.initialRoom)
        XCTAssertEqual(Set(next.room.walls.map(\.id)),Set(before.room.walls.map(\.id)))
        XCTAssertThrowsError(try SurveyPlanEditing.replacingContour(before,walls:ring,contour:[.zero,.init(x:2,y:0,z:3),.init(x:2,y:0,z:0),.init(x:0,y:0,z:3)]))
    }
    func testAutomaticCeilingSelectsObservedShapeAndPreservesNativeGeometry() throws {
        let cases: [(PlaquistoRoomDocument,CeilingEstimateSettings.Shape)] = [
            (ceilingRoom(),.flat),
            (profiledCeilingRoom(singleSlope:true,rotation:0.6),.singleSlope),
            (profiledCeilingRoom(),.twoSlopes),
            (profiledCeilingRoom(ridge:0.3,rotation:0.37),.twoSlopes),
            (profiledCeilingRoom(ridge:0.7,rotation:-1.2),.twoSlopes)
        ]
        for (original,shape) in cases {
            let created = WallCeilingEstimate.addingAutomaticCeilings(to:original)
            let roof = try XCTUnwrap(created.room.ceilings.first)
            XCTAssertEqual(created.room.ceilings.count,1)
            XCTAssertEqual(roof.estimateSettings?.shape,shape)
            XCTAssertEqual(roof.provenance.source,.estimated)
            XCTAssertEqual(created.room.walls,original.room.walls)
            XCTAssertEqual(created.room.openings,original.room.openings)
            XCTAssertEqual(created.initialRoom,original.initialRoom)
            XCTAssertTrue(created.room.slopes.allSatisfy { $0.accepted && !$0.manuallyValidated })
            XCTAssertEqual(try PlaquistoRoomDocument.decode(created.encoded()),created)
            XCTAssertEqual(WallCeilingEstimate.addingAutomaticCeilings(to:created),created)
        }
    }

    func testAutomaticCeilingDoesNotTurnSmallHeightNoiseIntoRamp() throws {
        let original = ceilingRoom(heights:[2.49,2.52,2.48,2.51])
        let generated = WallCeilingEstimate.addingAutomaticCeilings(to:original)
        XCTAssertEqual(generated.room.ceilings.first?.estimateSettings?.shape,.flat)
        // Even a mathematically perfect but insignificant 12 cm rise stays flat.
        var smallRise = profiledCeilingRoom(singleSlope:true)
        for i in smallRise.room.walls.indices {
            smallRise.room.walls[i].localOutline = smallRise.room.walls[i].localOutline?.map {
                var p = $0; if p.y > 0 { p.y = 2.5+(p.y-2.5)*0.1 }; return p
            }
        }
        XCTAssertEqual(WallCeilingEstimate.addingAutomaticCeilings(to:smallRise)
            .room.ceilings.first?.estimateSettings?.shape,.flat)
    }

    func testAutomaticCeilingDoesNotInventGableFromRectangularWallHeights() throws {
        // Different maximum heights without observed sloping profiles do not
        // locate an interior ridge, even when two opposing walls are taller.
        let original = ceilingRoom(heights:[2.5,3.7,2.5,3.7])
        XCTAssertEqual(WallCeilingEstimate.addingAutomaticCeilings(to:original)
            .room.ceilings.first?.estimateSettings?.shape,.flat)
    }

    func testAutomaticCeilingsFillBothRoomsAndRemainIndependentlyEditable() throws {
        let original = dividedRoom()
        let created = WallCeilingEstimate.addingAutomaticCeilings(to:original)
        XCTAssertEqual(created.room.ceilings.count,2)
        let reopened = try PlaquistoRoomDocument.decode(created.encoded())
        let choices = try WallCeilingEstimate.manualProposals(in:reopened.room)
        XCTAssertEqual(choices.count,2)
        let first = try XCTUnwrap(choices.first)
        let edited = try WallCeilingEstimate.applying(to:reopened,proposal:first,
            settings:.init(shape:.singleSlope,lowHeight:2.4,highHeight:3.4),manuallyEdited:true)
        XCTAssertEqual(edited.room.ceilings[1],created.room.ceilings[1])
        XCTAssertEqual(edited.room.walls,original.room.walls)
        XCTAssertEqual(WallCeilingEstimate.addingAutomaticCeilings(to:edited),edited)
    }

    func testAutomaticCeilingsPreserveExistingUserRoofWhileFillingVacantRoom() throws {
        let original = dividedRoom()
        let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let manual = try WallCeilingEstimate.applying(to:original,proposal:proposal,
            settings:.init(shape:.twoSlopes,lowHeight:2.5,highHeight:4),manuallyEdited:true)
        let completed = WallCeilingEstimate.addingAutomaticCeilings(to:manual)
        XCTAssertEqual(completed.room.ceilings.count,2)
        XCTAssertEqual(completed.room.ceilings[0],manual.room.ceilings[0])
        for slope in manual.room.slopes { XCTAssertTrue(completed.room.slopes.contains(slope)) }
    }

    func testAutomaticCeilingDoesNotCloseMissingWalls() {
        var original = ceilingRoom()
        original.room.walls.removeLast()
        XCTAssertEqual(WallCeilingEstimate.addingAutomaticCeilings(to:original),original)
    }

    func testAutomaticCeilingIgnoresIsolatedPeakOnOtherwiseFlatRoom() {
        var original = ceilingRoom()
        let wall = original.room.walls[0]
        original.room.walls[0].height.rawValue = 3.7
        original.room.walls[0].localOutline = [
            .zero,.init(x:wall.length.rawValue,y:0,z:0),
            .init(x:wall.length.rawValue,y:2.5,z:0),
            .init(x:2.2,y:2.5,z:0),.init(x:2,y:3.7,z:0),
            .init(x:1.8,y:2.5,z:0),.init(x:0,y:2.5,z:0)
        ]
        XCTAssertEqual(WallCeilingEstimate.addingAutomaticCeilings(to:original)
            .room.ceilings.first?.estimateSettings?.shape,.flat)
    }

    func testAutomaticCeilingDoesNotReplaceObservedCeiling() throws {
        let original = ceilingRoom()
        let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        var observed = try WallCeilingEstimate.applying(to:original,proposal:proposal,
            settings:.init(lowHeight:2.6,highHeight:2.6),manuallyEdited:false)
        observed.room.ceilings[0].provenance = .init(source:.roomPlan)
        XCTAssertEqual(WallCeilingEstimate.addingAutomaticCeilings(to:observed),observed)
    }

    func testAutomaticCeilingsPersistWithCompletedScanAndOriginalCheckpoint() throws {
        let original = dividedRoom()
        let document = WallCeilingEstimate.addingAutomaticCeilings(to:original)
        var draft = ScanCampaignDraft()
        draft.append(.init(referenceGroupID:UUID(),name:"Salon / Cuisine",usages:[],
            document:document,processingPending:false))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        _ = try ScanCampaignStore.completing(draft,directory:folder)
        let loaded = try XCTUnwrap(ScanCampaignStore.load(id:draft.id,directory:folder))
        XCTAssertTrue(loaded.isComplete)
        XCTAssertEqual(loaded.chunks[0].document.room.ceilings.count,2)
        XCTAssertTrue(loaded.chunks[0].document.initialRoom.ceilings.isEmpty)
        XCTAssertEqual(loaded.chunks[0].document.room.walls,original.room.walls)
        XCTAssertEqual(try WallCeilingEstimate.manualProposals(in:loaded.chunks[0].document.room).count,2)
    }

    func testCancelledAutomaticCeilingCreationLeavesCaptureUntouched() async {
        let original = profiledCeilingRoom()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return WallCeilingEstimate.addingAutomaticCeilings(to:original)
        }
        let result = await task.value
        XCTAssertEqual(result,original)
    }

    func testCeilingFitDefaultsFlatAndDoesNotInventMeasuredRidge() throws {
        let original = ceilingRoom()
        let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let fit = CeilingAutoFit(room:original.room,proposal:proposal)
        XCTAssertEqual(fit.coverage,1,accuracy:1e-8)
        let flat = fit.suggest(shape:.flat)
        XCTAssertEqual(flat.settings.shape,.flat)
        XCTAssertEqual(flat.settings.lowHeight,2.5,accuracy:1e-8)
        for shape in [CeilingEstimateSettings.Shape.singleSlope,.twoSlopes,.fourSlopes] {
            let suggestion = fit.suggest(shape:shape)
            XCTAssertTrue(suggestion.estimatedRise,"Equal wall tops cannot measure a ridge: \(shape)")
            XCTAssertEqual(suggestion.settings.highHeight,3,accuracy:1e-8)
            let kept = fit.suggest(shape:shape,current:.init(shape:.twoSlopes,lowHeight:2.5,highHeight:4))
            XCTAssertEqual(kept.settings.highHeight,4,accuracy:1e-8)
            let result = try WallCeilingEstimate.applying(to:original,proposal:proposal,
                settings:suggestion.settings,manuallyEdited:true)
            XCTAssertEqual(result.room.walls,original.room.walls)
            XCTAssertEqual(result.initialRoom,original.initialRoom)
        }
    }

    func testCeilingFitUsesGablePeakAndHandlesRotationTranslationAndUnequalPans() throws {
        for (ridge,rotation) in [(0.5,0.0),(0.3,0.37),(0.7,-1.2)] {
            let original = profiledCeilingRoom(ridge:ridge,rotation:rotation)
            let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
            let fit = CeilingAutoFit(room:original.room,proposal:proposal)
            let suggestion = fit.suggest(shape:.twoSlopes)
            XCTAssertFalse(suggestion.estimatedRise)
            XCTAssertEqual(suggestion.settings.lowHeight,2.5,accuracy:0.02)
            XCTAssertEqual(suggestion.settings.highHeight,3.7,accuracy:0.02)
            let planes = try WallCeilingEstimate.planes(boundary:proposal.boundary,
                floorElevation:proposal.floorElevation,settings:suggestion.settings)
            for sample in fit.samples {
                let y = try XCTUnwrap(planes.map { $0.height(x:sample.point.x,z:sample.point.z) }.min())
                XCTAssertEqual(y,sample.point.y,accuracy:0.03)
            }
            XCTAssertTrue(fit.gaps(settings:suggestion.settings).isEmpty)
            let result = try WallCeilingEstimate.applying(to:original,proposal:proposal,
                settings:suggestion.settings,manuallyEdited:true)
            XCTAssertEqual(result.room.ceilings.count,1)
            XCTAssertEqual(result.room.slopes.count,2)
            XCTAssertEqual(result.room.walls,original.room.walls)
            XCTAssertEqual(result.initialRoom,original.initialRoom)
            XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()),result)
        }
    }

    func testCeilingFitOneSlopeAndReportsWrongShapeWithoutChangingWalls() throws {
        let original = profiledCeilingRoom(singleSlope:true,rotation:0.6)
        let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let fit = CeilingAutoFit(room:original.room,proposal:proposal)
        let ramp = fit.suggest(shape:.singleSlope)
        XCTAssertFalse(ramp.estimatedRise)
        XCTAssertEqual(ramp.settings.lowHeight,2.5,accuracy:0.02)
        XCTAssertEqual(ramp.settings.highHeight,3.7,accuracy:0.02)
        XCTAssertTrue(fit.gaps(settings:ramp.settings).isEmpty)
        let flat = fit.suggest(shape:.flat)
        XCTAssertFalse(fit.gaps(settings:flat.settings).isEmpty)
        let result = try WallCeilingEstimate.applying(to:original,proposal:proposal,
            settings:flat.settings,manuallyEdited:true)
        XCTAssertEqual(result.room.walls,original.room.walls)
    }

    func testCeilingFitIsUnchangedByFragmentedGableAndRetainsFallbackProvenance() throws {
        let original = profiledCeilingRoom(ridge:0.3)
        var fragmented = original
        for i in fragmented.room.walls.indices {
            guard let outline = fragmented.room.walls[i].localOutline else { continue }
            fragmented.room.walls[i].localOutline = outline.indices.flatMap { j -> [RoomPoint] in
                let a = outline[j], b = outline[(j+1)%outline.count]
                return (0..<30).map { a+(b-a)*(Double($0)/30) }
            }
        }
        let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let normal = CeilingAutoFit(room:original.room,proposal:proposal).suggest(shape:.twoSlopes)
        let subdivided = CeilingAutoFit(room:fragmented.room,proposal:proposal).suggest(shape:.twoSlopes)
        XCTAssertFalse(subdivided.estimatedRise)
        XCTAssertEqual(subdivided.settings.highHeight,normal.settings.highHeight,accuracy:0.02)
        XCTAssertEqual(subdivided.settings.lowHeight,normal.settings.lowHeight,accuracy:0.02)

        let flat = ceilingRoom()
        let choice = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:flat.room).first)
        let fallback = CeilingAutoFit(room:flat.room,proposal:choice).suggest(shape:.fourSlopes)
        let saved = try WallCeilingEstimate.applying(to:flat,proposal:choice,settings:fallback.settings,manuallyEdited:true)
        let loaded = try PlaquistoRoomDocument.decode(saved.encoded())
        XCTAssertEqual(loaded.room.ceilings.first?.estimateSettings?.riseIsEstimated,true)
    }

    func testCeilingFitIgnoresWallTopsFromAnotherFloor() throws {
        let original = profiledCeilingRoom()
        var stacked = original.room
        let upstairs = original.room.walls.map { wall -> PlaquistoWall in
            var copy = wall; copy.id = UUID(); copy.start.y += 4; copy.end.y += 4
            return copy
        }
        stacked.walls = upstairs+stacked.walls
        let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let fitted = CeilingAutoFit(room:stacked,proposal:proposal).suggest(shape:.twoSlopes)
        XCTAssertFalse(fitted.estimatedRise)
        XCTAssertEqual(fitted.settings.highHeight,3.7,accuracy:0.02)
    }

    func testOffCenterCeilingSplitReopensWithValidSettings() throws {
        let original = ceilingRoom()
        let choice = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let whole = try WallCeilingEstimate.applying(to:original,proposal:choice,
            settings:.init(shape:.twoSlopes,lowHeight:2.5,highHeight:3.7,azimuth:0,ridgePosition:0.5),manuallyEdited:true)
        let split = try WallCeilingEstimate.split(whole,ceilingID:whole.room.ceilings[0].id,
            from:.init(x:1.9,y:0,z:-1),to:.init(x:1.9,y:0,z:4))
        for ceiling in split.room.ceilings { XCTAssertTrue(try XCTUnwrap(ceiling.estimateSettings).isValid) }
        XCTAssertEqual(split.room.walls,original.room.walls)
    }

    func testCeilingFitIgnoresOtherRoomAndKeepsBothCeilingsEditableAfterReload() throws {
        var original = dividedRoom()
        // A remote high room must not influence the selected kitchen's ceiling.
        let far = ceilingRoom([(20,0),(24,0),(24,3),(20,3)],heights:[8,8,8,8])
        original.room.walls += far.room.walls
        let choices = try WallCeilingEstimate.manualProposals(in:original.room)
        let local = choices.filter { ($0.boundary.map(\.x).max() ?? 0) < 10 }
        XCTAssertEqual(local.count,2)
        var document = original
        for choice in local {
            let fit = CeilingAutoFit(room:document.room,proposal:choice)
            let suggestion = fit.suggest(shape:.flat)
            XCTAssertEqual(suggestion.settings.lowHeight,2.5,accuracy:1e-8)
            document = try WallCeilingEstimate.applying(to:document,proposal:choice,
                settings:suggestion.settings,manuallyEdited:true)
        }
        document = try PlaquistoRoomDocument.decode(document.encoded())
        let kitchen = document.room.ceilings[0], living = document.room.ceilings[1]
        let livingPans = document.room.slopes.filter { living.slopeIDs.contains($0.id) }
        let reopen = try WallCeilingEstimate.manualProposals(in:document.room)
        XCTAssertEqual(reopen.filter { $0.ceilingID != nil }.count,2)
        let kitchenChoice = try XCTUnwrap(reopen.first { $0.ceilingID == kitchen.id })
        let suggested = CeilingAutoFit(room:document.room,proposal:kitchenChoice).suggest(shape:.twoSlopes)
        let edited = try WallCeilingEstimate.applying(to:document,proposal:kitchenChoice,
            settings:suggested.settings,manuallyEdited:true)
        XCTAssertEqual(edited.room.ceilings[0].id,kitchen.id)
        XCTAssertEqual(edited.room.ceilings[1],living)
        XCTAssertEqual(edited.room.slopes.filter { living.slopeIDs.contains($0.id) },livingPans)
        let again = try WallCeilingEstimate.manualProposals(in:edited.room)
        XCTAssertNotNil(again.first { $0.ceilingID == living.id })
        XCTAssertEqual(again.filter { $0.ceilingID == nil }.count,1,"The distant third zone remains available")
    }

    func testCeilingFitSplitZoneOnlyUsesItsRemainingWallProfiles() throws {
        let original = profiledCeilingRoom(ridge:0.5)
        let choice = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let whole = try WallCeilingEstimate.applying(to:original,proposal:choice,
            settings:CeilingAutoFit(room:original.room,proposal:choice).suggest(shape:.twoSlopes).settings,manuallyEdited:true)
        // Fixture has translation (100, -70), split across the ridge at z = -67.
        let split = try WallCeilingEstimate.split(whole,ceilingID:whole.room.ceilings[0].id,
            from:.init(x:99,y:0,z:-67),to:.init(x:105,y:0,z:-67))
        let halves = try WallCeilingEstimate.manualProposals(in:split.room)
        XCTAssertEqual(halves.count,2)
        for half in halves {
            let fit = CeilingAutoFit(room:split.room,proposal:half)
            XCTAssertLessThan(fit.coverage,1,"An interior cut is not an observed wall")
            let ramp = fit.suggest(shape:.singleSlope)
            XCTAssertFalse(ramp.estimatedRise)
            XCTAssertEqual(ramp.settings.lowHeight,2.5,accuracy:0.03)
            XCTAssertEqual(ramp.settings.highHeight,3.7,accuracy:0.03)
        }
    }

    private func profiledCeilingRoom(ridge:Double = 0.5, singleSlope:Bool = false,
                                     rotation:Double = 0) -> PlaquistoRoomDocument {
        var document = ceilingRoom([(0,0),(4,0),(4,6),(0,6)])
        let source = GeometryProvenance(source:.roomPlan)
        func top(_ z:Double) -> Double {
            2.5+1.2*(singleSlope ? z/6 : min(z/(6*ridge),(6-z)/(6*(1-ridge))))
        }
        for i in document.room.walls.indices {
            var wall = document.room.walls[i]
            var xs = [0.0,wall.length.rawValue]
            if !singleSlope, abs(wall.direction.z) > 0.1 {
                let x = (6*ridge-wall.start.z)/wall.direction.z
                if x > 0 && x < wall.length.rawValue { xs.append(x) }
            }
            xs.sort()
            let upper = xs.map { RoomPoint(x:$0,y:top(wall.start.z+wall.direction.z*$0),z:0) }
            wall.localOutline = [.zero,.init(x:wall.length.rawValue,y:0,z:0)]+upper.reversed()
            wall.height = .init(rawValue:upper.map(\.y).max()!,provenance:source)
            func transform(_ p:RoomPoint) -> RoomPoint {
                .init(x:100+p.x*cos(rotation)-p.z*sin(rotation),y:1.2,
                      z:-70+p.x*sin(rotation)+p.z*cos(rotation))
            }
            wall.start = transform(wall.start); wall.end = transform(wall.end)
            document.room.walls[i] = wall
        }
        return .init(room:document.room)
    }

    func testAddingSecondCeilingPreservesFirstAndLabelsParentsNotPans() throws {
        let original=dividedRoom()
        let zones=try WallCeilingEstimate.manualProposals(in:original.room)
        XCTAssertEqual(zones.count,2)
        let first=try WallCeilingEstimate.applying(to:original,proposal:zones[0],
            settings:.init(shape:.twoSlopes,lowHeight:2.5,highHeight:3),manuallyEdited:true)
        let vacant=try XCTUnwrap(WallCeilingEstimate.manualProposals(in:first.room).first { $0.ceilingID == nil })
        let second=try WallCeilingEstimate.applying(to:first,proposal:vacant,
            settings:vacant.suggestedSettings,manuallyEdited:true)
        XCTAssertEqual(second.room.ceilings.count,2)
        XCTAssertEqual(second.room.ceilings[0],first.room.ceilings[0])
        XCTAssertEqual(Array(second.room.slopes.prefix(first.room.slopes.count)),first.room.slopes)
        let checkpoint=ProjectRoomScanCheckpoint(roomID:second.room.id,document:second,spatialLinkState:.sharedWorldSpace)
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Plafonds",checkpoints:[checkpoint])
        let names=SurveyWorkGeometry.surfaces(in:survey).filter { $0.source.kind == .ceiling }.map(\.name)
        XCTAssertTrue(names.contains("Plafond A · pan 1"))
        XCTAssertTrue(names.contains("Plafond A · pan 2"))
        XCTAssertTrue(names.contains("Plafond B"))
        XCTAssertThrowsError(try WallCeilingEstimate.applying(to:second,proposal:vacant,
            settings:vacant.suggestedSettings,manuallyEdited:true))
        XCTAssertEqual(try PlaquistoRoomDocument.decode(second.encoded()),second)
    }

    func testFreeCeilingCutsConserveAreaPlanesWallsAndAllowIndependentEditing() throws {
        for shape in CeilingEstimateSettings.Shape.allCases {
            let original=ceilingRoom()
            let proposal=try WallCeilingEstimate.propose(in:original.room)
            let whole=try WallCeilingEstimate.applying(to:original,proposal:proposal,
                settings:.init(shape:shape,lowHeight:2.5,highHeight:3.5,azimuth:0.3),manuallyEdited:true)
            let firstID=try XCTUnwrap(whole.room.ceilings.first?.id)
            let split=try WallCeilingEstimate.split(whole,ceilingID:firstID,
                from:.init(x:2,y:0,z:-1),to:.init(x:2,y:0,z:4))
            XCTAssertEqual(split.room.ceilings.count,2,"\(shape)")
            XCTAssertEqual(split.room.walls,original.room.walls)
            XCTAssertEqual(split.initialRoom,original.initialRoom)
            XCTAssertEqual(split.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) },
                whole.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) },accuracy:1e-6)
            XCTAssertTrue(split.room.slopes.allSatisfy { pan in whole.room.slopes.contains { $0.plane == pan.plane } })
            XCTAssertEqual(try PlaquistoRoomDocument.decode(split.encoded()),split)
            let choices=try WallCeilingEstimate.manualProposals(in:split.room)
            XCTAssertEqual(choices.count,2,"Do not offer the already occupied whole room")
            let selected=try XCTUnwrap(choices.first { $0.ceilingID == firstID })
            let sibling=split.room.ceilings[1]
            let changed=try WallCeilingEstimate.applying(to:split,proposal:selected,
                settings:.init(lowHeight:2.4,highHeight:2.4),manuallyEdited:true)
            XCTAssertEqual(changed.room.ceilings[1],sibling)
            XCTAssertEqual(changed.room.slopes.filter { sibling.slopeIDs.contains($0.id) },
                split.room.slopes.filter { sibling.slopeIDs.contains($0.id) })
            XCTAssertThrowsError(try WallCeilingEstimate.split(whole,ceilingID:firstID,
                from:.init(x:9,y:0,z:0),to:.init(x:9,y:0,z:4)))
        }
    }

    func testCeilingDragCutOnlyCommitsAfterExplicitAcceptance() throws {
        let base = ceilingRoom()
        let proposal = try WallCeilingEstimate.propose(in: base.room)
        let whole = try WallCeilingEstimate.applying(to: base, proposal: proposal,
            settings: .init(shape: .twoSlopes, lowHeight: 2.5, highHeight: 3.5), manuallyEdited: true)
        let id = try XCTUnwrap(whole.room.ceilings.first?.id)
        var cut = SurveyCeilingCut()
        cut.begin(at: .init(x:2,y:0,z:-1))
        cut.move(to: .init(x:2,y:0,z:1))
        XCTAssertNil(cut.preview, "Finger movement is only a dashed guide")
        cut.move(to: .init(x:2,y:0,z:4))
        let displayedStart = cut.start, displayedEnd = cut.end
        try cut.finish(document: whole, ceilingID: id, minimumLength: 0.12)
        XCTAssertEqual(cut.start, displayedStart)
        XCTAssertEqual(cut.end, displayedEnd, "Touch-up must preserve the last displayed guide")
        let preview = try XCTUnwrap(cut.preview)
        XCTAssertEqual(preview.room.ceilings.count, 2)
        XCTAssertEqual(whole.room.ceilings.count, 1, "Releasing does not mutate the original editor document")
        XCTAssertEqual(preview.initialRoom, whole.initialRoom)
        XCTAssertEqual(preview.room.walls, whole.room.walls)
        XCTAssertEqual(preview.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) },
                       whole.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) }, accuracy: 1e-6)
        cut.cancelGesture()
        XCTAssertEqual(cut.preview, preview, "Pinching/panning to inspect a preview must keep it")
        XCTAssertEqual(cut.accept(), preview)
        XCTAssertNil(cut.preview); XCTAssertNil(cut.start); XCTAssertNil(cut.end)
        XCTAssertNil(cut.accept(), "Cannot apply the same cut twice")
    }

    @MainActor
    func testCeilingCutConfirmationDoesNotResizeCanvasOnReleaseOrRedo() {
        for width in [CGFloat(240),390,750] {
            for dynamicType in [DynamicTypeSize.large,.accessibility3] {
                let drawing=UIHostingController(rootView: SurveyCeilingCutConfirmation(ready:false,redo:{},accept:{})
                    .environment(\.dynamicTypeSize,dynamicType))
                let preview=UIHostingController(rootView: SurveyCeilingCutConfirmation(ready:true,redo:{},accept:{})
                    .environment(\.dynamicTypeSize,dynamicType))
                let available=CGSize(width:width,height:1000)
                let before=drawing.sizeThatFits(in:available), after=preview.sizeThatFits(in:available)
                XCTAssertGreaterThan(before.height,0)
                XCTAssertEqual(before.height,after.height,accuracy:0.01)
                XCTAssertEqual(before.width,after.width,accuracy:0.01)
            }
        }
    }

    func testCeilingDragCutRedoAndCancellationDiscardOnlyTheDraft() throws {
        let whole = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom())
        let id = try XCTUnwrap(whole.room.ceilings.first?.id)
        var cut = SurveyCeilingCut()
        cut.begin(at: .init(x:2,y:0,z:-1)); cut.move(to: .init(x:2,y:0,z:4))
        try cut.finish(document:whole,ceilingID:id,minimumLength:0.12)
        XCTAssertNotNil(cut.preview)
        cut.reset()
        XCTAssertNil(cut.accept()); XCTAssertNil(cut.start)
        cut.begin(at: .init(x:-1,y:0,z:1)); cut.move(to: .init(x:5,y:0,z:1))
        cut.cancelGesture()
        XCTAssertNil(cut.start); XCTAssertNil(cut.end); XCTAssertNil(cut.preview)
        cut.begin(at: .init(x:-1,y:0,z:1)); cut.move(to: .init(x:5,y:0,z:1))
        try cut.finish(document:whole,ceilingID:id,minimumLength:0.12)
        XCTAssertEqual(cut.accept()?.room.ceilings.count, 2)
        XCTAssertEqual(whole.room.ceilings.count, 1)
    }

    func testCeilingDragCutRejectsTapsShortDragsAndCutsOutsideTheCeiling() throws {
        let whole = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom())
        let id = try XCTUnwrap(whole.room.ceilings.first?.id)
        for endpoints: (RoomPoint,RoomPoint) in [
            (.init(x:2,y:0,z:1), .init(x:2,y:0,z:1)),
            (.init(x:2,y:0,z:1), .init(x:2.01,y:0,z:1)),
            (.init(x:9,y:0,z:-1), .init(x:9,y:0,z:4))
        ] {
            var cut = SurveyCeilingCut()
            cut.begin(at:endpoints.0); cut.move(to:endpoints.1)
            XCTAssertThrowsError(try cut.finish(document:whole,ceilingID:id,minimumLength:0.12))
            XCTAssertNil(cut.start); XCTAssertNil(cut.end); XCTAssertNil(cut.preview)
            XCTAssertNil(cut.accept())
        }
    }

    func testCeilingMergePreservesEveryPlaneSourceAndOriginalScan() throws {
        for shape in CeilingEstimateSettings.Shape.allCases {
            let base=ceilingRoom()
            let proposal=try WallCeilingEstimate.propose(in:base.room)
            let whole=try WallCeilingEstimate.applying(to:base,proposal:proposal,
                settings:.init(shape:shape,lowHeight:2.5,highHeight:shape == .flat ? 2.5 : 3.5),manuallyEdited:true)
            let id=try XCTUnwrap(whole.room.ceilings.first?.id)
            let split=try WallCeilingEstimate.split(whole,ceilingID:id,from:.init(x:2,y:0,z:-1),to:.init(x:2,y:0,z:4))
            let merged=try CeilingZoneEditing.merge(split,first:id,second:split.room.ceilings[1].id)
            XCTAssertEqual(merged.room.ceilings.count,1)
            XCTAssertEqual(merged.room.ceilings[0].id,id)
            XCTAssertEqual(merged.room.slopes,split.room.slopes,"Keep every source ID and slope for existing calepinages")
            XCTAssertEqual(Set(merged.room.ceilings[0].slopeIDs),Set(split.room.slopes.map(\.id)))
            XCTAssertEqual(merged.room.walls,whole.room.walls)
            XCTAssertEqual(merged.initialRoom,whole.initialRoom)
            XCTAssertEqual(abs(SurveyPlanFinishes.area(try XCTUnwrap(merged.room.ceilings[0].footprint))),12,accuracy:1e-6)
            XCTAssertEqual(try PlaquistoRoomDocument.decode(merged.encoded()),merged)
        }
    }

    func testCeilingMergeRequiresSharedEdgeAndPreservesConcaveOutline() {
        func ring(_ points:[(Double,Double)]) -> [RoomPoint] { points.map { .init(x:$0.0,y:0,z:$0.1) } }
        let a=ring([(0,0),(4,0),(4,2),(0,2)])
        let b=ring([(0,2),(1,2),(2,2),(2,4),(0,4)])
        let joined=CeilingZoneEditing.joinedBoundary(a,b)
        XCTAssertNotNil(joined,"Handles extra collinear points along the shared boundary")
        XCTAssertEqual(abs(SurveyPlanFinishes.area(joined ?? [])),12,accuracy:1e-6)
        XCTAssertFalse(PlaquistoWallGeometry.contains(.init(x:3,y:0,z:3),polygon:joined ?? []),"No invented convex hull")
        XCTAssertNil(CeilingZoneEditing.joinedBoundary(a,ring([(4,2),(6,2),(6,4),(4,4)])),"Corner contact is not adjacency")
        XCTAssertNil(CeilingZoneEditing.joinedBoundary(a,ring([(0,3),(4,3),(4,5),(0,5)])),"Separate ceilings")
        XCTAssertNil(CeilingZoneEditing.joinedBoundary(a,a),"Overlapping ceilings")
    }

    func testHiddenCeilingPersistsButStillFeedsExistingWorks() throws {
        let whole=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let id=try XCTUnwrap(whole.room.ceilings.first?.id)
        let hidden=CeilingZoneEditing.togglingVisibility(whole,ceilingID:id)
        XCTAssertEqual(hidden.room.slopes,whole.room.slopes)
        XCTAssertEqual(hidden.initialRoom,whole.initialRoom)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(hidden.encoded()),hidden)
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Masqué",checkpoints:[
            .init(roomID:hidden.room.id,document:hidden,spatialLinkState:.sharedWorldSpace)])
        let canonical=SurveyWorkGeometry.surfaces(in:survey)
        XCTAssertFalse(canonical.filter { $0.source.kind == .ceiling }.isEmpty)
        XCTAssertTrue(canonical.filter { $0.source.kind == .ceiling }.allSatisfy { SurveyWorkGeometry.isHidden($0,in:survey) })
        XCTAssertTrue(canonical.filter { $0.source.kind == .wall }.allSatisfy { !SurveyWorkGeometry.isHidden($0,in:survey) })
        let visible=CeilingZoneEditing.togglingVisibility(hidden,ceilingID:id)
        XCTAssertEqual(visible.room.ceilings[0].isHidden,false)
        XCTAssertEqual(visible.room.slopes,whole.room.slopes)
        let proposal=try XCTUnwrap(WallCeilingEstimate.manualProposals(in:hidden.room).first)
        let changed=try WallCeilingEstimate.applying(to:hidden,proposal:proposal,settings:.init(lowHeight:2.7,highHeight:2.7),manuallyEdited:true)
        XCTAssertEqual(changed.room.ceilings[0].isHidden,true,"Editing must not accidentally reveal a ceiling")
    }

    func testCaptureLocationIsFreshBoundedOptionalAndNotInDiagnostics() throws {
        let now=Date()
        let fix=ScanLocationFix(latitude:45.7,longitude:4.8,horizontalAccuracy:12,capturedAt:now)
        XCTAssertTrue(fix.isUsable(at:now))
        XCTAssertFalse(fix.isUsable(at:now.addingTimeInterval(31)))
        var bad=fix; bad.horizontalAccuracy=101; XCTAssertFalse(bad.isUsable(at:now))
        bad=fix; bad.latitude = .nan; XCTAssertFalse(bad.isUsable(at:now))
        var draft=ScanCampaignDraft(); draft.captureLocation=fix
        let data=try JSONEncoder().encode(draft)
        XCTAssertEqual(try JSONDecoder().decode(ScanCampaignDraft.self,from:data).captureLocation,fix)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        json.removeValue(forKey:"captureLocation")
        XCTAssertNil(try JSONDecoder().decode(ScanCampaignDraft.self,from:JSONSerialization.data(withJSONObject:json)).captureLocation)
        let diagnostic=try ScanDiagnosticExport.data(draft:draft,survey:nil).0
        let text=String(decoding:diagnostic,as:UTF8.self)
        XCTAssertFalse(text.contains("latitude")); XCTAssertFalse(text.contains("longitude"))
    }

    func testSplitCeilingSettingsKeepLocalHeightAndVerticalReference() throws {
        var original=ceilingRoom()
        for i in original.room.walls.indices {
            original.room.walls[i].start.y=1.2; original.room.walls[i].end.y=1.2
        }
        let proposal=try WallCeilingEstimate.propose(in:original.room)
        let whole=try WallCeilingEstimate.applying(to:original,proposal:proposal,
            settings:.init(shape:.singleSlope,lowHeight:2,highHeight:4,azimuth:0),manuallyEdited:true)
        let split=try WallCeilingEstimate.split(whole,ceilingID:whole.room.ceilings[0].id,
            from:.init(x:2,y:0,z:-1),to:.init(x:2,y:0,z:4))
        for choice in try WallCeilingEstimate.manualProposals(in:split.room) {
            XCTAssertEqual(choice.floorElevation,1.2,accuracy:1e-8)
            XCTAssertEqual(choice.suggestedSettings.highHeight-choice.suggestedSettings.lowHeight,1,accuracy:1e-8)
            let rebuilt=try WallCeilingEstimate.applying(to:split,proposal:choice,
                settings:choice.suggestedSettings,manuallyEdited:true)
            let id=try XCTUnwrap(choice.ceilingID)
            let ceiling=try XCTUnwrap(rebuilt.room.ceilings.first { $0.id==id })
            for slope in rebuilt.room.slopes where ceiling.slopeIDs.contains(slope.id) {
                XCTAssertEqual(slope.plane.a,0.5,accuracy:1e-8)
                XCTAssertEqual(slope.plane.c,3.2,accuracy:1e-8)
            }
        }
    }

    func testCeilingLettersStayStableWhenEarlierCheckpointGainsCeiling() throws {
        let original=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let second=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        var survey=ProjectSurveyRecord(projectID:UUID(),name:"Repères",checkpoints:[
            .init(roomID:original.room.id,document:original,spatialLinkState:.sharedWorldSpace),
            .init(roomID:second.room.id,document:second,spatialLinkState:.sharedWorldSpace)])
        survey.ceilingPlanNumbers=CeilingPlanNaming.numbers(in:survey)
        survey.checkpoints[0].document=try WallCeilingEstimate.split(original,ceilingID:original.room.ceilings[0].id,
            from:.init(x:2,y:0,z:-1),to:.init(x:2,y:0,z:4))
        let numbers=CeilingPlanNaming.numbers(in:survey)
        XCTAssertEqual(numbers[second.room.ceilings[0].id.uuidString],2)
        XCTAssertEqual(numbers[survey.checkpoints[0].document.room.ceilings[1].id.uuidString],3)
        XCTAssertEqual(CeilingPlanNaming.title(second.room.ceilings[0],in:second.room,numbers:numbers),"Plafond B")
        XCTAssertEqual(try JSONDecoder().decode(ProjectSurveyRecord.self,from:JSONEncoder().encode(survey)),survey)
    }

    @MainActor func testArchitecturalPlanSnapshotIncludesSeparateCeilingLabels() throws {
        let document=try WallCeilingEstimate.addingIfMissing(to:dividedRoom())
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Plan d’architecte",checkpoints:[
            .init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace)])
        let surfaces=SurveyWorkGeometry.surfaces(in:survey)
        let renderer=ImageRenderer(content:SurveySurfacePlan(survey:survey,surfaces:surfaces,kind:.ceiling,
            selected:[],blocked:[],onTap:{_ in}).frame(width:420,height:560))
        renderer.scale=2
        let image=try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size,CGSize(width:420,height:560))
        let attachment=XCTAttachment(image:image); attachment.name="architectural-plan-ceilings-A-B"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testSurveyThumbnailCachesImageAndInvalidatesEditedGeometry() throws {
        let document=dividedRoom()
        let checkpoint=ProjectRoomScanCheckpoint(roomID:document.room.id,document:document,
            spatialLinkState:.sharedWorldSpace,workState:.validated)
        var survey=ProjectSurveyRecord(projectID:UUID(),name:"Vignette",checkpoints:[checkpoint])
        let original=survey
        let key=try XCTUnwrap(SurveyThumbnailRenderer.key(for:survey))
        let image=try XCTUnwrap(SurveyThumbnailRenderer.image(for:survey))
        XCTAssertEqual(image.size,CGSize(width:576,height:432))
        XCTAssertTrue(image === SurveyThumbnailRenderer.image(for:survey))
        XCTAssertEqual(survey,original)
        survey.checkpoints[0].transformToSurvey.values[12]=2
        XCTAssertNotEqual(SurveyThumbnailRenderer.key(for:survey),key)
        survey=original
        try survey.checkpoints[0].document.room.walls[0].height.correct(3)
        XCTAssertNotEqual(SurveyThumbnailRenderer.key(for:survey),key)
        let attachment=XCTAttachment(image:image); attachment.name="project-survey-thumbnail"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testElevatedRenderingDefaultsAndLightweightMaterials() throws {
        XCTAssertEqual(MaquetteRendering.resolve(nil), .elevated)
        XCTAssertEqual(MaquetteRendering.resolve("unknown"), .elevated)
        XCTAssertEqual(MaquetteRendering.resolve("standard"), .standard)
        let wall=MaquetteStyle.material(.wall,rendering:.elevated)
        XCTAssertTrue(wall === MaquetteStyle.material(.wall,rendering:.elevated))
        XCTAssertFalse(wall === MaquetteStyle.material(.wall,rendering:.standard))
        XCTAssertEqual(wall.lightingModel, .lambert)
        let blue=try XCTUnwrap(wall.diffuse.contents as? UIColor)
        var r:CGFloat=0, g:CGFloat=0, b:CGFloat=0, a:CGFloat=0
        blue.getRed(&r,green:&g,blue:&b,alpha:&a)
        XCTAssertGreaterThan(b,r)
        XCTAssertNotNil(MaquetteStyle.material(.floor,rendering:.elevated).diffuse.contents as? UIColor)
        XCTAssertNotNil(MaquetteStyle.material(.floor,rendering:.standard).diffuse.contents as? UIImage)
        let quad:[RoomPoint]=[.init(x:0,y:0,z:0),.init(x:2,y:0,z:0),.init(x:2,y:2,z:0),
                              .init(x:0,y:0,z:0),.init(x:2,y:2,z:0),.init(x:0,y:2,z:0)]
        XCTAssertEqual(MaquetteStyle.featureEdges(quad).count,8,"Four boundaries, no triangulation diagonal")
    }

    @MainActor func testRenderingSwitchPreservesGeometryCameraAndSelection() throws {
        let defaults=UserDefaults.standard, key=MaquetteRendering.preferenceKey
        let saved=defaults.object(forKey:key)
        defer { if let saved { defaults.set(saved,forKey:key) } else { defaults.removeObject(forKey:key) } }
        defaults.set("standard",forKey:key)
        let document=try WallCeilingEstimate.addingIfMissing(to:dividedRoom())
        let selected=try XCTUnwrap(document.room.ceilings.first?.id)
        let parent=RoomDomainScene(room:document.room,selected:.constant(selected),ceilingMode:2,
            showFloor:true,topView:false,cameraReset:UUID())
        let coordinator=parent.makeCoordinator(), view=SCNView()
        view.scene=SCNScene(); parent.update(view,coordinator:coordinator)
        let camera=try XCTUnwrap(view.pointOfView), wall=try XCTUnwrap(coordinator.walls.first?.geometry)
        let standardMaterial=wall.firstMaterial
        defaults.set("elevated",forKey:key)
        parent.update(view,coordinator:coordinator)
        XCTAssertTrue(camera === view.pointOfView)
        XCTAssertTrue(wall === coordinator.walls.first?.geometry)
        XCTAssertFalse(standardMaterial === wall.firstMaterial)
        XCTAssertEqual(coordinator.geometryBuildCount,1)
        XCTAssertEqual(try XCTUnwrap(coordinator.roofs.first).opacity,0.8,accuracy:0.001)
        XCTAssertFalse(try XCTUnwrap(coordinator.walls.first?.childNode(withName:"maquette.edges",recursively:false)).isHidden)
        XCTAssertEqual(parent.room,document.room)
        let checkpoint=ProjectRoomScanCheckpoint(roomID:document.room.id,document:document,
            spatialLinkState:.sharedWorldSpace,workState:.validated)
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Rendu",checkpoints:[checkpoint])
        let surfaces=SurveyWorkGeometry.surfaces(in:survey)
        let ids=Set(surfaces.filter { $0.source.kind == .ceiling }.map(\.id))
        let high=try XCTUnwrap(SurveyThumbnailRenderer.image(for:survey,selected:ids))
        let attachment=XCTAttachment(image:high); attachment.name="elevated-blue-orange"
        attachment.lifetime = .keepAlways; add(attachment)
        defaults.set("standard",forKey:key)
        XCTAssertFalse(high === SurveyThumbnailRenderer.image(for:survey,selected:ids))
        parent.update(view,coordinator:coordinator)
        XCTAssertTrue(camera === view.pointOfView)
        XCTAssertEqual(coordinator.geometryBuildCount,1)
        XCTAssertTrue(try XCTUnwrap(coordinator.walls.first?.childNode(withName:"maquette.edges",recursively:false)).isHidden)
    }

    @MainActor func testMaquetteMaterialsHaveBoundedPixelsAndIndependentVariants() throws {
        let normal=MaquetteStyle.material(.wall)
        let selected=MaquetteStyle.material(.wall,state:.selected)
        XCTAssertTrue(normal === MaquetteStyle.material(.wall))
        XCTAssertFalse(normal === selected)
        XCTAssertTrue(normal.writesToDepthBuffer)
        XCTAssertFalse(MaquetteStyle.material(.wall,translucent:true).writesToDepthBuffer)
        XCTAssertTrue(normal.writesToDepthBuffer,"Translucency must not mutate an opaque shared material")
        XCTAssertEqual(MaquetteStyle.floorTexture.cgImage?.width,512)
        XCTAssertEqual(MaquetteStyle.floorTexture.cgImage?.height,512)
        XCTAssertEqual(MaquetteStyle.uv(.init(x:4,y:8,z:2)),CGPoint(x:2,y:1))
        let view=SCNView(); MaquetteStyle.configure(view,quality:.economical)
        XCTAssertEqual(view.preferredFramesPerSecond,30)
        XCTAssertFalse(view.rendersContinuously)
        let camera=SCNCamera(); MaquetteStyle.configure(camera,quality:.economical)
        XCTAssertEqual(camera.screenSpaceAmbientOcclusionIntensity,0)
    }

    @MainActor func testMaquetteBackgroundChangesWithoutRebuildingGeometry() {
        let view = SCNView(); view.scene = SCNScene()
        let node = SCNNode(geometry:SCNBox(width:1,height:1,length:1,chamferRadius:0))
        view.scene?.rootNode.addChildNode(node)
        MaquetteStyle.updateBackground(view,dark:false)
        let light = view.backgroundColor
        MaquetteStyle.updateBackground(view,dark:true)
        XCTAssertNotEqual(view.backgroundColor,light)
        XCTAssertEqual(view.scene?.background.contents as? UIColor,view.backgroundColor)
        XCTAssertTrue(view.scene?.rootNode.childNodes.first === node)
    }

    @MainActor func testRoomPresentationChangesReuseGeometryAndCamera() throws {
        let document=try WallCeilingEstimate.addingIfMissing(to:dividedRoom())
        var parent=RoomDomainScene(room:document.room,selected:.constant(nil),ceilingMode:0,
            showFloor:true,topView:false,cameraReset:UUID())
        let coordinator=parent.makeCoordinator(), view=SCNView()
        view.scene=SCNScene(); parent.update(view,coordinator:coordinator)
        let content=try XCTUnwrap(coordinator.content), camera=try XCTUnwrap(view.pointOfView)
        let mesh=try XCTUnwrap(coordinator.walls.first?.geometry)
        let token=parent.cameraReset
        for i in 0..<20 {
            parent=RoomDomainScene(room:document.room,selected:.constant(document.room.walls[i%2].id),
                ceilingMode:i%3,showFloor:i.isMultiple(of:2),topView:false,cameraReset:token)
            parent.update(view,coordinator:coordinator)
        }
        XCTAssertEqual(coordinator.geometryBuildCount,1)
        XCTAssertTrue(coordinator.content === content)
        XCTAssertTrue(coordinator.walls.first?.geometry === mesh)
        XCTAssertTrue(view.pointOfView === camera)
        var edited=document.room; edited.walls.removeLast()
        parent=RoomDomainScene(room:edited,selected:.constant(nil),ceilingMode:0,
            showFloor:true,topView:false,cameraReset:token)
        parent.update(view,coordinator:coordinator)
        XCTAssertEqual(coordinator.geometryBuildCount,2)
        XCTAssertEqual(coordinator.walls.count,edited.walls.count)
    }

    @MainActor func testCeilingHeightPreviewReusesShellAndCamera() throws {
        let whole=try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let id=try XCTUnwrap(whole.room.ceilings.first?.id)
        let token=UUID()
        var parent=RoomDomainScene(room:whole.room,selected:.constant(id),ceilingMode:2,showFloor:true,topView:false,cameraReset:token)
        let coordinator=parent.makeCoordinator(), view=SCNView()
        view.scene=SCNScene(); parent.update(view,coordinator:coordinator)
        let wall=try XCTUnwrap(coordinator.walls.first), camera=try XCTUnwrap(view.pointOfView)
        let proposal=try XCTUnwrap(WallCeilingEstimate.manualProposals(in:whole.room).first)
        for height in [2.6,2.7,2.8] {
            let changed=try WallCeilingEstimate.applying(to:whole,proposal:proposal,settings:.init(lowHeight:height,highHeight:height),manuallyEdited:true)
            parent=RoomDomainScene(room:changed.room,selected:.constant(id),ceilingMode:2,showFloor:true,topView:false,cameraReset:token)
            parent.update(view,coordinator:coordinator)
            XCTAssertTrue(coordinator.walls.first === wall)
            XCTAssertTrue(view.pointOfView === camera)
            XCTAssertFalse(coordinator.roofs.isEmpty)
        }
        let hidden=CeilingZoneEditing.togglingVisibility(whole,ceilingID:id)
        parent=RoomDomainScene(room:hidden.room,selected:.constant(nil),ceilingMode:2,showFloor:true,topView:false,cameraReset:token)
        parent.update(view,coordinator:coordinator)
        XCTAssertTrue(coordinator.roofs.allSatisfy(\.isHidden))
        XCTAssertTrue(coordinator.outlines.allSatisfy(\.isHidden))
    }

    @MainActor func testSurveyGeometryCacheIncludesTransformsButNotSelection() throws {
        let document=dividedRoom()
        let checkpoint=ProjectRoomScanCheckpoint(roomID:document.room.id,document:document,
            spatialLinkState:.sharedWorldSpace,workState:.validated)
        var survey=ProjectSurveyRecord(projectID:UUID(),name:"Cache",checkpoints:[checkpoint])
        let surfaces=SurveyWorkGeometry.surfaces(in:survey)
        let id=try XCTUnwrap(surfaces.first?.id)
        var parent=SurveySurfaceScene(survey:survey,surfaces:surfaces,kind:.wall,selected:[],claimed:[],onTap:{ _ in })
        let coordinator=parent.makeCoordinator(),view=SCNView()
        parent.update(view,coordinator:coordinator)
        let scene=try XCTUnwrap(view.scene)
        let floor=try XCTUnwrap(scene.rootNode.childNodes.first { $0.name?.hasPrefix("floor/") == true })
        let uv=try XCTUnwrap(floor.geometry?.sources(for:.texcoord).first?.data)
        for _ in 0..<20 {
            parent=SurveySurfaceScene(survey:survey,surfaces:SurveyWorkGeometry.surfaces(in:survey),kind:.wall,
                selected:[id],claimed:[],onTap:{ _ in },showsCeilings:true,resetToken:1)
            parent.update(view,coordinator:coordinator)
        }
        XCTAssertTrue(view.scene === scene)
        XCTAssertEqual(coordinator.geometryBuildCount,1)
        XCTAssertTrue(scene.rootNode.childNode(withName:id,recursively:false)?.geometry?.firstMaterial === MaquetteStyle.material(.wall,state:.selected))
        let other=try XCTUnwrap(surfaces.first { $0.id != id })
        XCTAssertTrue(scene.rootNode.childNode(withName:other.id,recursively:false)?.geometry?.firstMaterial === MaquetteStyle.material(.wall))
        survey.checkpoints[0].transformToSurvey.values[12] += 10
        // Rotate the room 90 degrees as well: UVs must stay in its own frame.
        survey.checkpoints[0].transformToSurvey.values[0]=0
        survey.checkpoints[0].transformToSurvey.values[2] = -1
        survey.checkpoints[0].transformToSurvey.values[8]=1
        survey.checkpoints[0].transformToSurvey.values[10]=0
        parent=SurveySurfaceScene(survey:survey,surfaces:surfaces,kind:.wall,selected:[],claimed:[],onTap:{ _ in })
        parent.update(view,coordinator:coordinator)
        XCTAssertEqual(coordinator.geometryBuildCount,2)
        let moved=try XCTUnwrap(view.scene?.rootNode.childNodes.first { $0.name?.hasPrefix("floor/") == true })
        XCTAssertEqual(moved.geometry?.sources(for:.texcoord).first?.data,uv,"Survey translation must not slide the floor texture")
        XCTAssertEqual(survey.checkpoints[0].document.room,document.room)
    }

    func testRoomPlanRampantPolygonIsImportedInsteadOfBoundingRectangle() throws {
        // Five-point sloped outline found in the captured scan; anonymous pose.
        let json = #"{"polygonCorners":[[-1.2679155,2.21049,0],[-1.0856938,2.21049,0],[1.2679154,1.07163,0],[1.2679154,-2.2104897,0],[-1.2679155,-2.2104897,0]],"transform":[1,0,0,0,0,1,0,0,0,0,1,0,3,1,2,1],"parentIdentifier":null,"curve":null,"identifier":"11111111-1111-1111-1111-111111111111","dimensions":[2.5358307,4.42098,0],"story":0,"completedEdges":[],"confidence":{"high":{}},"category":{"wall":{}}}"#
        let surface=try JSONDecoder().decode(CapturedRoom.Surface.self,from:Data(json.utf8))
        let wall=RoomPlanAdapter().convertWall(surface)
        XCTAssertEqual(wall.localOutline?.count,5)
        let outline=try XCTUnwrap(wall.localOutline)
        XCTAssertEqual(outline[0].y,4.42098,accuracy:1e-5)
        XCTAssertEqual(outline[2].y,3.28212,accuracy:1e-5)
        let room=PlaquistoRoomModel(walls:[wall],metadata:.init(source:.roomPlan))
        let area=PlaquistoWallGeometry.analyze(wall:wall,room:room).gross
        let expected=2.5358307*4.42098-(2.5358307-0.1822217)*1.13886/2
        XCTAssertEqual(area,expected,accuracy:1e-5)
        let document=PlaquistoRoomDocument(room:room)
        let restored=try PlaquistoRoomDocument.decode(document.encoded())
        XCTAssertEqual(restored.room.walls,document.room.walls)
        XCTAssertEqual(restored.initialRoom.walls,document.initialRoom.walls)
    }

    func testCeilingsNeverReshapeScannedWallsAndProfileReachesLayout() throws {
        var document=chunk(group:UUID()).document
        let wallID=document.room.walls[0].id
        document.room.walls[0].height.rawValue=4
        document.room.walls[0].localOutline=[.init(x:0,y:0,z:0),.init(x:4,y:0,z:0),.init(x:4,y:2,z:0),.init(x:0,y:4,z:0)]
        document.room.slopes=[.init(plane:.init(a:0,b:0,c:1),boundaries:[[.init(x:0,y:1,z:0),.init(x:4,y:1,z:0),.init(x:4,y:1,z:3),.init(x:0,y:1,z:3)]],provenance:.init(source:.manual),accepted:true)]
        let geometry=PlaquistoWallGeometry.analyze(wall:document.room.walls[0],room:document.room)
        XCTAssertEqual(geometry.gross,12,accuracy:1e-8)
        let survey=ProjectSurveyRecord(projectID:UUID(),name:"Test",checkpoints:[.init(roomID:document.room.id,document:document,spatialLinkState:.sharedWorldSpace,workState:.validated)])
        let surface=try XCTUnwrap(SurveyWorkGeometry.surfaces(in:survey).first { $0.source.surfaceID==wallID })
        XCTAssertTrue(surface.surface.contour.contains(.init(x:4000,y:2000)))
        XCTAssertEqual(try surface.surface.netMeasuredArea()/1_000_000,12,accuracy:1e-8)
        let moved=try SurveyPlanEditing.changingWall(document,id:wallID,start:.init(x:1,y:0,z:0),end:.init(x:5,y:0,z:0),height:4)
        XCTAssertEqual(moved.room.walls[0].localOutline,document.room.walls[0].localOutline)
        XCTAssertEqual(moved.initialRoom,document.initialRoom)
        XCTAssertEqual(PlaquistoWallGeometry.analyze(wall:moved.room.walls[0],room:moved.room).gross,12,accuracy:1e-8)
    }

    func testConcaveWallAndSlopingBaseKeepExactAreaAndOpeningClipping() throws {
        var document=chunk(group:UUID()).document
        var wall=document.room.walls[0]
        wall.localOutline=[.init(x:0,y:0,z:0),.init(x:4,y:1,z:0),.init(x:4,y:3,z:0),
            .init(x:2,y:2,z:0),.init(x:0,y:3,z:0)]
        document.room.walls=[wall]
        let analysis=PlaquistoWallGeometry.analyze(wall:wall,room:document.room)
        XCTAssertEqual(analysis.gross,8,accuracy:1e-8)
        let triangles=PlaquistoWallGeometry.solidTriangles(wall:wall,room:document.room)
        let triangleArea=stride(from:0,to:triangles.count,by:3).reduce(0.0) { area,i in
            let a=triangles[i+1]-triangles[i],b=triangles[i+2]-triangles[i]
            return area+abs(a.x*b.y-a.y*b.x)/2
        }
        XCTAssertEqual(triangleArea,analysis.gross,accuracy:1e-8)
        XCTAssertThrowsError(try SurveyPlanEditing.addingDoor(document,wallID:wall.id,width:0.83,height:2,position:2))
    }

    func testMergingContiguousRampantsKeepsContourOpeningsAndOriginal() throws {
        var room=chunk(group:UUID()).document.room
        var a=room.walls[0]
        a.end = .init(x:2,y:0,z:0); a.length.rawValue=2; a.height.rawValue=3
        a.localOutline=[.init(x:0,y:0,z:0),.init(x:2,y:0,z:0),.init(x:2,y:2,z:0),.init(x:0,y:3,z:0)]
        var b=a; b.id=UUID(); b.start = .init(x:2,y:0,z:0); b.end = .init(x:4,y:0,z:0)
        b.height.rawValue=2
        b.localOutline=[.init(x:0,y:0,z:0),.init(x:2,y:0,z:0),.init(x:2,y:1,z:0),.init(x:0,y:2,z:0)]
        room.walls=[a,b]
        var document=PlaquistoRoomDocument(room:room)
        document=try SurveyPlanEditing.addingDoor(document,wallID:b.id,width:0.73,height:0.8,position:0.1)
        let result=try SurveyPlanEditing.mergingWalls(document,first:a.id,second:b.id)
        XCTAssertEqual(result.initialRoom,document.initialRoom)
        XCTAssertEqual(result.room.walls.count,1)
        let merged=try XCTUnwrap(result.room.walls.first)
        XCTAssertEqual(merged.id,a.id)
        XCTAssertEqual(PlaquistoWallGeometry.analyze(wall:merged,room:result.room).gross,8,accuracy:1e-8)
        XCTAssertEqual(result.room.openings[0].wallID,a.id)
        XCTAssertEqual(result.room.openings[0].positionOnWall.effectiveValue,2.1,accuracy:1e-8)
        let restored=try PlaquistoRoomDocument.decode(result.encoded())
        XCTAssertEqual(restored.room.walls,result.room.walls)
        XCTAssertEqual(restored.room.openings,result.room.openings)
        XCTAssertEqual(restored.initialRoom.walls,result.initialRoom.walls)
        var gap=document; gap.room.walls[1].start.x += 0.1; gap.room.walls[1].end.x += 0.1
        XCTAssertThrowsError(try SurveyPlanEditing.mergingWalls(gap,first:a.id,second:b.id))
        var corner=document; corner.room.walls[1].end = .init(x:2,y:0,z:2)
        XCTAssertThrowsError(try SurveyPlanEditing.mergingWalls(corner,first:a.id,second:b.id))
    }

    func testWindowCanBeCorrectedAndDeletedWithoutChangingOriginal() throws {
        let original=chunk(group:UUID()).document
        var document=try SurveyPlanEditing.addingDoor(original,wallID:original.room.walls[0].id,width:0.83,height:1,position:1)
        document.room.openings[0].kind = .window
        let id=document.room.openings[0].id
        let edited=try SurveyPlanEditing.changingOpening(document,id:id,width:1.2,height:1.1,sill:0.9,position:1.5)
        XCTAssertEqual(edited.room.openings[0].width.effectiveValue,1.2)
        XCTAssertEqual(edited.room.openings[0].kind,.window)
        XCTAssertEqual(edited.initialRoom,original.initialRoom)
        XCTAssertThrowsError(try SurveyPlanEditing.changingOpening(edited,id:id,width:1.2,height:3,sill:1,position:1.5))
        let deleted=try SurveyPlanEditing.removingOpening(edited,id:id)
        XCTAssertTrue(deleted.room.openings.isEmpty)
        XCTAssertTrue(deleted.room.walls[0].openingIDs.isEmpty)
        XCTAssertEqual(deleted.initialRoom,original.initialRoom)
    }

    func testCaptureDiagnosticSurvivesDraftSaveReloadAndExport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var draft = ScanCampaignDraft()
        draft.append(chunk(group: UUID()))
        draft.captureDiagnostic = "{\"meshConfigurationActive\":false,\"liveAttemptsTotal\":4}"
        try ScanCampaignStore.save(draft, directory: folder)
        let restored = try XCTUnwrap(ScanCampaignStore.load(id: draft.id, directory: folder))
        XCTAssertEqual(restored.captureDiagnostic, draft.captureDiagnostic)
        let (data, limited) = try ScanDiagnosticExport.data(draft: restored, survey: nil)
        XCTAssertFalse(limited)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let capture = try XCTUnwrap(report["capture"] as? [String: Any])
        XCTAssertEqual(capture["liveAttemptsTotal"] as? Int, 4)
        XCTAssertEqual(capture["meshConfigurationActive"] as? Bool, false)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Chambre"))
    }

    func testOldScanDiagnosticExplicitlyReportsMissingCaptureData() throws {
        var draft = ScanCampaignDraft(); draft.append(chunk(group: UUID()))
        let raw = try JSONEncoder().encode(draft)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("captureDiagnostic"))
        let restored = try JSONDecoder().decode(ScanCampaignDraft.self, from: raw)
        let (data, limited) = try ScanDiagnosticExport.data(draft: restored, survey: nil)
        XCTAssertTrue(limited)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(report["availability"] as? String, "partial")
        XCTAssertTrue(report["capture"] is NSNull)
        XCTAssertEqual((report["currentGeometry"] as? [Any])?.count, 1)
    }

    @MainActor func testProjectKeepsDiagnosticWithoutOriginalDraftFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        var draft = ScanCampaignDraft(); draft.append(chunk(group: UUID()))
        draft.captureDiagnostic = "{\"liveAttemptsTotal\":42}"
        let id = try store.saveScanCampaign(draft, projectID: nil, newProjectName: "Projet privé", surveyName: "Relevé")
        let loaded = ProjectStore(fileURL: url)
        let survey = try XCTUnwrap(loaded.surveys.first { $0.id == id })
        XCTAssertEqual(survey.captureDiagnostic, draft.captureDiagnostic)
        let (data, limited) = try ScanDiagnosticExport.data(draft: .init(id: id), survey: survey)
        XCTAssertFalse(limited)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Projet privé"))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((report["capture"] as? [String: Any])?["liveAttemptsTotal"] as? Int, 42)
    }

    @MainActor func testNativeCapturePreparationDoesNotProduceCeilingsOrMeshPreview() {
        let model=ScannerDebugModel()
        model.prepareForCapture()
        XCTAssertNil(model.meshPreview)
        XCTAssertTrue(model.campaign.chunks.isEmpty)
        XCTAssertEqual(model.liveCeilingFaceCount,0)
        XCTAssertEqual(model.lastReconstructionDiagnostic,"Plafonds : création après scan uniquement")
    }

    func testSparseObservedRampantIsExtendedThenFrozenAfterValidation() throws {
        typealias Engine = ScannerCeilingReconstruction
        let polygon: [SIMD2<Double>] = [.init(0,0),.init(4,0),.init(4,4),.init(0,4)]
        let walls = polygon.indices.map { Engine.Wall(start:polygon[$0],end:polygon[($0+1)%4]) }
        // Less than 1 m² actually observed, on the low portion of a rampant.
        // The complete 16 m² footprint is inferred from walls, not its height.
        var patches: [Engine.Triangle] = []
        for i in 0..<4 {
            for j in 0..<4 {
                func point(_ x: Int, _ z: Int) -> SIMD3<Double> {
                    let px = Double(x)*0.2
                    return .init(px,2.2+px*0.35,Double(z)*0.2)
                }
                let a = point(i,j), b = point(i+1,j), c = point(i+1,j+1), d = point(i,j+1)
                patches += [.init(a:a,b:b,c:c),.init(a:a,b:c,c:d)]
            }
        }
        XCTAssertTrue(patches.allSatisfy { Engine.isCeilingObservation($0,classifiedCeiling:true,minimumY:3.9,floorY:0) })
        XCTAssertFalse(Engine.isCeilingObservation(patches[0],classifiedCeiling:false,minimumY:3.9,floorY:0))
        let low = Engine.Triangle(a:.init(0,0,0),b:.init(1,0,0),c:.init(1,0,1))
        XCTAssertFalse(Engine.isCeilingObservation(low,classifiedCeiling:true,minimumY:3.9,floorY:0))
        let surface = try Engine.reconstruct(walls:walls,triangles:patches).get()
        XCTAssertLessThan(surface.observedSupportArea,1)
        XCTAssertEqual(surface.area,16*sqrt(1+0.35*0.35),accuracy:1e-6)
        XCTAssertEqual(surface.slopeDegrees,atan(0.35)*180 / .pi,accuracy:1e-6)
        XCTAssertTrue(surface.vertices.allSatisfy { abs($0.y-(2.2+0.35*$0.x)) < 1e-6 })
        XCTAssertThrowsError(try Engine.reconstruct(walls:walls,triangles:[]).get())
        var room = ceilingRoom().room
        ScannerRoomBridge.apply(surface,to:&room,accepted:false,manuallyValidated:false)
        var review = ScannerCeilingReview()
        XCTAssertTrue(review.propose(.init(room:room)))
        XCTAssertTrue(review.confirmed.isEmpty)
        review.accept()
        let frozen = review.applying(to:room)
        room.walls[0].height = .init(rawValue:9,provenance:.init(source:.roomPlan))
        let updated = review.applying(to:room)
        XCTAssertEqual(updated.slopes,frozen.slopes,"New wall heights must not move the accepted roof")
        XCTAssertEqual(try PlaquistoRoomDocument.decode(PlaquistoRoomDocument(room:updated).encoded()).room,updated)
    }

    func testLiveCeilingFindsLocalRoomInClosedMultiRoomScan() throws {
        typealias Engine = ScannerCeilingReconstruction
        let walls = dividedRoom().room.walls.map { Engine.Wall(start:.init($0.start.x,$0.start.z),end:.init($0.end.x,$0.end.z)) }
        for x in [2.0,6.0] {
            let local = try XCTUnwrap(Engine.localCeilingWalls(walls,keepPoint:.init(x,2)))
            let area = abs(local.reduce(0) { $0 + $1.start.x*$1.end.y - $1.end.x*$1.start.y }) / 2
            XCTAssertEqual(area,16,accuracy:1e-6)
            XCTAssertTrue(local.allSatisfy { x < 4 ? max($0.start.x,$0.end.x) <= 4 : min($0.start.x,$0.end.x) >= 4 })
        }
    }

    private func observedReviewChoices() -> [ScannerCeilingReview.Choice] {
        // Two synthetic LiDAR plane patches, adjacent at x = 4.
        (0..<2).map { index in
            let x = Double(index)*4
            let vertices: [SIMD3<Double>] = [.init(x,2.5,0),.init(x+4,2.5,0),.init(x+4,2.5,4),
                .init(x,2.5,0),.init(x+4,2.5,4),.init(x,2.5,4)]
            let surface = ScannerCeilingReconstruction.Surface(vertices:vertices,area:16,slopeDegrees:0,observedSupportArea:16,fitError:0)
            var room = dividedRoom().room
            ScannerRoomBridge.apply(surface,to:&room,accepted:false,manuallyValidated:false)
            return .init(room:room)
        }
    }

    func testCeilingReviewNeverSubstitutesWallsOrFloorForScanObservations() throws {
        let original = dividedRoom()
        var review = ScannerCeilingReview()
        XCTAssertEqual(review.applying(to:original.room),original.room)
        let estimate = try WallCeilingEstimate.addingIfMissing(to:original)
        XCTAssertFalse(review.propose(.init(room:estimate.room)))
        XCTAssertNil(review.pending)
        XCTAssertTrue(review.confirmed.isEmpty)
    }

    func testManualRoofEditorCanOpenDespiteInconsistentWallHeights() throws {
        let original = ceilingRoom(heights:[2.44,4.43,3.1,4.3])
        XCTAssertThrowsError(try WallCeilingEstimate.proposals(in:original.room))
        let choices = try WallCeilingEstimate.manualProposals(in:original.room)
        let choice = try XCTUnwrap(choices.first)
        let edited = try WallCeilingEstimate.applying(to:original,proposal:choice,
            settings:.init(shape:.singleSlope,lowHeight:2.4,highHeight:4.4),manuallyEdited:true)
        XCTAssertEqual(edited.room.ceilings.count,1)
        XCTAssertTrue(edited.room.slopes.allSatisfy(\.manuallyValidated))
        XCTAssertEqual(edited.room.walls,original.room.walls)
        XCTAssertEqual(edited.initialRoom,original.initialRoom)
    }

    func testCeilingReviewIsExplicitAndSurvivesFinalProcessing() throws {
        let original = dividedRoom()
        let choices = observedReviewChoices()
        XCTAssertEqual(choices.count,2)
        var review = ScannerCeilingReview()
        XCTAssertTrue(review.propose(choices[0]))
        XCTAssertTrue(review.confirmed.isEmpty)
        XCTAssertTrue(review.pending?.estimated == false)
        XCTAssertFalse(review.propose(choices[1]),"A visible proposal stays frozen until a decision")
        review.accept()
        XCTAssertNil(review.pending)
        XCTAssertTrue(review.confirmed[0].room.slopes.allSatisfy(\.manuallyValidated))
        XCTAssertFalse(review.propose(choices[0]),"Do not offer an already confirmed ceiling again")
        XCTAssertTrue(review.propose(choices[1]),"Neighbouring ceilings may share an edge")
        review.accept()
        let automatic = try WallCeilingEstimate.addingIfMissing(to:original)
        let final = review.applying(to:automatic.room)
        XCTAssertEqual(final.ceilings.count,2)
        XCTAssertTrue(final.slopes.allSatisfy { $0.accepted && $0.manuallyValidated && $0.provenance.source == .lidar })
        XCTAssertEqual(final.walls,original.room.walls)
        XCTAssertEqual(final.floors,original.room.floors)
        let saved = PlaquistoRoomDocument(room:final)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(saved.encoded()),saved)
    }

    func testRejectedAndPendingCeilingsAreNotSilentlyAcceptedAtFinish() throws {
        let original = dividedRoom()
        let choices = observedReviewChoices()
        var review = ScannerCeilingReview()
        XCTAssertTrue(review.propose(choices[0])); review.reject()
        XCTAssertFalse(review.propose(choices[0]))
        XCTAssertTrue(review.propose(choices[1]))
        let automatic = try WallCeilingEstimate.addingIfMissing(to:original)
        XCTAssertTrue(review.applying(to:automatic.room).ceilings.isEmpty)
        review.accept(); review.retryLast()
        XCTAssertTrue(review.confirmed.isEmpty)
        XCTAssertTrue(review.propose(choices[0]),"Revoir allows another attempt")
    }

    private func dividedRoom() -> PlaquistoRoomDocument {
        var document = ceilingRoom([(0,0),(8,0),(8,4),(0,4)])
        let p = GeometryProvenance(source: .roomPlan)
        document.room.floors = [.init(boundaries:[document.room.walls.map(\.start)],referenceElevation:0,provenance:p)]
        document.room.walls.append(.init(start:.init(x:4,y:0,z:0),end:.init(x:4,y:0,z:4),
            length:.init(rawValue:4,provenance:p),height:.init(rawValue:2.5,provenance:p),provenance:p))
        return document
    }

    func testPostScanFindsTwoClosedSpacesWithoutChangingWallsOrScan() throws {
        let original = dividedRoom()
        let result = try WallCeilingEstimate.addingIfMissing(to: original)
        XCTAssertEqual(result.room.ceilings.count, 2)
        XCTAssertEqual(result.room.slopes.count, 2)
        XCTAssertEqual(result.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) }, 32, accuracy:1e-6)
        XCTAssertEqual(result.room.walls,original.room.walls)
        XCTAssertEqual(result.initialRoom,original.initialRoom)
        XCTAssertTrue(result.room.slopes.allSatisfy { $0.provenance.source == .estimated && !$0.manuallyValidated })
        XCTAssertEqual(try WallCeilingEstimate.addingIfMissing(to:result),result)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()),result)
    }

    func testCeilingEditorChangesOnlyChosenSpace() throws {
        let document = try WallCeilingEstimate.addingIfMissing(to:dividedRoom())
        let proposals = try WallCeilingEstimate.proposals(in:document.room)
        let choice = try XCTUnwrap(proposals.first)
        let other = try XCTUnwrap(document.room.ceilings.first { $0.id != choice.ceilingID })
        let unchanged = document.room.slopes.filter { other.slopeIDs.contains($0.id) }
        let edited = try WallCeilingEstimate.applying(to:document,proposal:choice,
            settings:.init(lowHeight:2.7,highHeight:2.7),manuallyEdited:true)
        XCTAssertEqual(edited.room.ceilings.count,2)
        XCTAssertEqual(edited.room.slopes.filter { other.slopeIDs.contains($0.id) },unchanged)
        XCTAssertEqual(edited.initialRoom,document.initialRoom)
        XCTAssertEqual(edited.room.walls,document.room.walls)
    }

    func testPostScanDoesNotCloseDoorwayGapOrCreateCeilingAcrossFloorVoid() throws {
        var partial = dividedRoom()
        partial.room.walls[4].length.rawValue = 2
        partial.room.walls[4].end.z = 2
        let single = try WallCeilingEstimate.addingIfMissing(to:partial)
        XCTAssertEqual(single.room.ceilings.count,1,"A partial partition does not form two rooms")
        var open = ceilingRoom(); open.room.walls.removeFirst()
        XCTAssertThrowsError(try WallCeilingEstimate.addingIfMissing(to:open))
        var void = ceilingRoom()
        void.room.floors = [.init(boundaries:[void.room.walls.map(\.start)],referenceElevation:0,provenance:.init(source:.roomPlan))]
        void.room.floors[0].boundaries.append([.init(x:1,y:0,z:1),.init(x:2,y:0,z:1),
            .init(x:2,y:0,z:2),.init(x:1,y:0,z:2)])
        XCTAssertThrowsError(try WallCeilingEstimate.addingIfMissing(to:void))
    }

    func testPostScanRejectsIncoherentHighWallInsteadOfInventingRoof() throws {
        let room = ceilingRoom(heights:[2.5,2.5,4,2.5])
        XCTAssertThrowsError(try WallCeilingEstimate.addingIfMissing(to:room))
    }

    func testObservedFloorClosesMissingWallWithoutInventingWallGeometry() throws {
        var document = dividedRoom()
        document.room.walls.remove(at:0)
        let walls = document.room.walls
        let result = try WallCeilingEstimate.addingIfMissing(to:document)
        XCTAssertEqual(result.room.ceilings.count,2)
        XCTAssertEqual(result.room.walls,walls)
        XCTAssertEqual(result.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) },32,accuracy:1e-6)
    }

    func testShortLowerReturnDoesNotTiltCeilingOrModifyMeasuredHeight() throws {
        var document = ceilingRoom([(0,0),(0.4,0),(4,0),(4,3),(0,3)],heights:[2.1,2.5,2.5,2.5,2.5])
        document.room.floors = [.init(boundaries:[document.room.walls.map(\.start)],referenceElevation:0,provenance:.init(source:.roomPlan))]
        let result = try WallCeilingEstimate.addingIfMissing(to:document)
        XCTAssertEqual(result.room.ceilings.count,1)
        XCTAssertEqual(result.room.slopes[0].plane.slopeDegrees,0,accuracy:1e-6)
        XCTAssertEqual(result.room.walls[0].height.effectiveValue,2.1)
    }

    func testClosedCeilingContourKeepsSmallRecessesInsteadOfRematchingCorners() throws {
        // Synthetic regression: two corners only 15 cm apart used to confuse
        // the second, unordered endpoint matcher despite an already closed face.
        let outline: [(Double,Double)] = [(0,0),(6,0),(6,4),(3.15,4),(3.15,3.9),(3,3.9),(3,4),(0,4)]
        for reversed in [false,true] {
            for angle in [0.0,0.37] {
                let points = (reversed ? Array(outline.reversed()) : outline).map { x,z in
                    (x*cos(angle)-z*sin(angle)+12, x*sin(angle)+z*cos(angle)-7)
                }
                var document = ceilingRoom(points)
                document.room.floors = [.init(boundaries:[document.room.walls.map(\.start)],
                    referenceElevation:0,provenance:.init(source:.roomPlan))]
                let result = try WallCeilingEstimate.addingIfMissing(to:document)
                XCTAssertEqual(result.room.ceilings.count,1)
                XCTAssertEqual(result.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) },23.985,accuracy:1e-6)
                XCTAssertEqual(result.room.walls,document.room.walls)
                XCTAssertEqual(result.room.floors,document.room.floors)
                XCTAssertEqual(result.initialRoom,document.initialRoom)
                XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()),result)
            }
        }
    }

    func testFloorProjectionWithRecessAndPartitionKeepsSeparateCeilings() throws {
        var document = ceilingRoom([(0,0),(8,0),(8,4),(6.15,4),(6.15,3.9),(6,3.9),(6,4),(0,4)])
        let source = GeometryProvenance(source:.roomPlan)
        document.room.floors = [.init(boundaries:[document.room.walls.map(\.start)],referenceElevation:0,provenance:source)]
        document.room.walls.append(.init(start:.init(x:4,y:0,z:0),end:.init(x:4,y:0,z:4),
            length:.init(rawValue:4,provenance:source),height:.init(rawValue:2.5,provenance:source),provenance:source))
        document.room.walls.remove(at:0) // Floor supplies the missing observed boundary.
        let result = try WallCeilingEstimate.addingIfMissing(to:document)
        XCTAssertEqual(result.room.ceilings.count,2)
        XCTAssertEqual(result.room.slopes.reduce(0) { $0+PlaquistoSurfaceGeometry.area(of:$1) },31.985,accuracy:1e-6)
        XCTAssertEqual(result.room.walls,document.room.walls)
        XCTAssertEqual(try WallCeilingEstimate.addingIfMissing(to:result),result)
        XCTAssertTrue(result.room.slopes.allSatisfy { $0.provenance.source == .estimated && !$0.manuallyValidated })
    }

    @MainActor func testArchitecturalScenePreservesSelectionAndProducesPreview() throws {
        var document = try WallCeilingEstimate.addingIfMissing(to:dividedRoom())
        let dividing = document.room.walls[4].id
        document = try SurveyPlanEditing.addingDoor(document,wallID:dividing,width:0.83,height:2.04,position:1)
        document = try SurveyPlanEditing.addingDoor(document,wallID:document.room.walls[0].id,width:0.93,height:2.04,position:2)
        let checkpoint = ProjectRoomScanCheckpoint(roomID:document.room.id,document:document,
            spatialLinkState:.sharedWorldSpace,workState:.validated)
        let survey = ProjectSurveyRecord(projectID:UUID(),name:"Aperçu",checkpoints:[checkpoint])
        let surfaces = SurveyWorkGeometry.surfaces(in:survey)
        let before = SurveyWorkGeometry.totalArea(surfaces)
        let scene = SurveySceneRenderer.make(survey:survey,surfaces:surfaces)
        for surface in surfaces {
            let node = try XCTUnwrap(scene.rootNode.childNode(withName:surface.id,recursively:false))
            XCTAssertEqual(node.categoryBitMask,1)
            XCTAssertFalse(try XCTUnwrap(node.geometry).sources(for:.normal).isEmpty)
            node.isHidden = surface.source.kind == .ceiling
        }
        XCTAssertEqual(scene.rootNode.childNodes.filter { $0.name?.hasPrefix("floor/") == true }.count,1)
        let wallNode = try XCTUnwrap(scene.rootNode.childNode(withName:surfaces.first { $0.source.surfaceID == dividing }!.id,recursively:false))
        XCTAssertEqual(SurveyWorkGeometry.totalArea(SurveyWorkGeometry.surfaces(in:survey)),before)
        SurveySceneRenderer.frame(scene,aspect:0.8)
        let renderer = SCNRenderer(device:nil,options:nil)
        renderer.scene = scene; renderer.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
        let image = renderer.snapshot(atTime:1,with:CGSize(width:800,height:1000),antialiasingMode:.multisampling4X)
        let hitOptions: [String:Any] = [SCNHitTestOption.backFaceCulling.rawValue:false,SCNHitTestOption.searchMode.rawValue:SCNHitTestSearchMode.all.rawValue]
        // SceneKit prepares its hit-test acceleration structures during rendering.
        XCTAssertFalse(scene.rootNode.hitTestWithSegment(from:.init(3,1,1.4),to:.init(5,1,1.4),options:hitOptions).contains { $0.node === wallNode },"Door remains a real hole")
        XCTAssertTrue(scene.rootNode.hitTestWithSegment(from:.init(3,1,3),to:.init(5,1,3),options:hitOptions).contains { $0.node === wallNode },"Wall beside door remains selectable; bounds=\(wallNode.boundingBox)")
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count,1000)
        let attachment = XCTAttachment(image:image); attachment.name = "architectural-survey-preview"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSingleNativeResultRemainsEditableWithoutAssemblyOrCoordinateShift() throws {
        let original = ceilingRoom()
        let id = UUID(), group = UUID()
        var draft = ScanCampaignDraft()
        draft.upsert(.init(id: id, referenceGroupID: group, name: "Relevé", usages: [],
            document: original, processingPending: true))
        var document = try WallCeilingEstimate.addingIfMissing(to: original)
        document = try SurveyPlanEditing.addingPartition(document,
            start: .init(x: 1, y: 0, z: 0), end: .init(x: 1, y: 0, z: 3), height: 2.5)
        let partition = try XCTUnwrap(document.room.walls.last)
        document = try SurveyPlanEditing.addingDoor(document, wallID: partition.id,
            width: 0.83, height: 2.04, position: 1)
        draft.upsert(.init(id: id, referenceGroupID: group, name: "Relevé", usages: [],
            document: document, processingPending: false))
        XCTAssertEqual(draft.chunks.count, 1)
        XCTAssertTrue(draft.sharesWorldSpace)
        XCTAssertNotEqual(draft.assemblyVerified, true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try ScanCampaignStore.completing(draft, directory: folder)
        let restored = try XCTUnwrap(ScanCampaignStore.loadAll(directory: folder).first)
        let saved = try XCTUnwrap(restored.chunks.first?.document)
        XCTAssertTrue(restored.isComplete)
        XCTAssertEqual(saved.initialRoom, original.initialRoom)
        XCTAssertEqual(Array(saved.room.walls.prefix(4)), original.room.walls)
        XCTAssertEqual(saved.room.openings.first?.wallID, partition.id)
        XCTAssertFalse(saved.room.slopes.isEmpty)
        let plan = ScanFloorPlan(overview: ScanLiveOverview(draft: restored))
        XCTAssertEqual(plan.dimensions.count, 5)
        XCTAssertTrue(plan.segments.contains { $0.opening == .door })
        let checkpoint = ProjectRoomScanCheckpoint(roomID: saved.room.id, document: saved,
            spatialLinkState: .needsLink, workState: .validated)
        let survey = ProjectSurveyRecord(projectID: UUID(), name: "Relevé", checkpoints: [checkpoint])
        let surfaces = SurveyWorkGeometry.surfaces(in: survey)
        XCTAssertTrue(surfaces.contains { $0.source.kind == .ceiling })
        XCTAssertGreaterThan(SurveyWorkGeometry.totalArea(surfaces), 0)
    }

    func testCaptureEventsRoundTripAndOldDraftsStillDecode() throws {
        var draft = ScanCampaignDraft()
        let old = try JSONDecoder().decode(ScanCampaignDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertNil(old.captureEvents)
        draft.captureEvents = [.init(roomID: UUID(), name: "tracking_suspended", detail: "relocalizing")]
        let restored = try JSONDecoder().decode(ScanCampaignDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        XCTAssertTrue(restored.continuityReliable, "Temporary tracking events must not invalidate the entire scan")
    }

    func testPlanWallEditMovesJoinedCornersAndPreservesOriginalAndCeiling() throws {
        let original = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom())
        let wall = original.room.walls[0]
        let result = try SurveyPlanEditing.changingWall(original, id: wall.id,
            start: .init(x: 0, y: 0, z: -1), end: .init(x: 4, y: 0, z: -1), height: 2.7)
        XCTAssertEqual(result.initialRoom, original.initialRoom)
        XCTAssertEqual(result.room.slopes, original.room.slopes, "Ceiling resizing is not implicit")
        XCTAssertEqual(result.room.walls[1].start, result.room.walls[0].effectiveEnd)
        XCTAssertEqual(result.room.walls[3].effectiveEnd, result.room.walls[0].start)
        XCTAssertEqual(result.room.walls[1].length.effectiveValue, 4, accuracy: 1e-8)
        XCTAssertEqual(result.room.walls[0].height.effectiveValue, 2.7, accuracy: 1e-8)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()), result)
    }

    func testPlanStandardDoorsPersistAndFollowWallTranslation() throws {
        let original = ceilingRoom()
        let wall = original.room.walls[0]
        for width in SurveyPlanEditing.doorWidths {
            let withDoor = try SurveyPlanEditing.addingDoor(original, wallID: wall.id, width: width, height: 2.04, position: 1)
            let door = try XCTUnwrap(withDoor.room.openings.first)
            XCTAssertEqual(withDoor.room.walls[0].openingIDs, [door.id])
            let translated = try SurveyPlanEditing.changingWall(withDoor, id: wall.id,
                start: .init(x: 0, y: 0, z: -1), end: .init(x: 4, y: 0, z: -1), height: 2.5)
            XCTAssertEqual(translated.room.openings[0].center.z, -1, accuracy: 1e-8)
            XCTAssertEqual(translated.room.openings[0].center.x, 1+width/2, accuracy: 1e-8)
            XCTAssertEqual(translated.initialRoom, original.initialRoom)
            let moved = try SurveyPlanEditing.movingDoor(translated, id: door.id, position: 2)
            XCTAssertEqual(moved.room.openings[0].center.x, 2+width/2, accuracy: 1e-8)
            XCTAssertEqual(try PlaquistoRoomDocument.decode(moved.encoded()), moved)
        }
    }

    func testPlanWallEditRefusesSelfCrossingContour() throws {
        let original = ceilingRoom()
        XCTAssertThrowsError(try SurveyPlanEditing.changingWall(original, id: original.room.walls[0].id,
            start: original.room.walls[0].start, end: .init(x: -1, y: 0, z: 2), height: 2.5))
        XCTAssertEqual(original.room.walls[0].effectiveEnd, RoomPoint(x: 4, y: 0, z: 0))
    }

    func testPlanRefusesDoorsOutsideWallsOverlapsAndDestructiveShortening() throws {
        let original = ceilingRoom()
        XCTAssertThrowsError(try SurveyPlanEditing.addingDoor(original, wallID: UUID(), width: 0.83, height: 2.04, position: 1))
        let wall = original.room.walls[0]
        for values in [(0.0,2.04,1.0), (0.83,3.0,1.0), (0.83,2.04,-0.1), (0.83,2.04,3.5), (0.83,2.04,Double.nan)] {
            XCTAssertThrowsError(try SurveyPlanEditing.addingDoor(original, wallID: wall.id,
                width: values.0, height: values.1, position: values.2))
        }
        let first = try SurveyPlanEditing.addingDoor(original, wallID: wall.id, width: 0.83, height: 2.04, position: 1)
        XCTAssertThrowsError(try SurveyPlanEditing.addingDoor(first, wallID: wall.id, width: 0.73, height: 2.04, position: 1.5))
        let second = try SurveyPlanEditing.addingDoor(first, wallID: wall.id, width: 0.73, height: 2.04, position: 2.5)
        XCTAssertThrowsError(try SurveyPlanEditing.movingDoor(second, id: second.room.openings[1].id, position: 1.2))
        XCTAssertThrowsError(try SurveyPlanEditing.changingWall(second, id: wall.id,
            start: wall.start, end: .init(x: 2, y: 0, z: 0), height: 2.5))
        XCTAssertEqual(second.room.walls[0].length.effectiveValue, 4)
        XCTAssertEqual(second.initialRoom, original.initialRoom)
    }

    func testDesignedPartitionIsOneSurfaceWithSuggestedHeightAndManualProvenance() throws {
        let original = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom(heights: [2.5,3,3.5,3]))
        let start = RoomPoint(x: 1, y: 0, z: 1.5), end = RoomPoint(x: 3, y: 0, z: 1.5)
        let height = SurveyPlanEditing.suggestedHeight(in: original.room, at: start)
        XCTAssertEqual(height, 3, accuracy: 1e-8)
        let result = try SurveyPlanEditing.addingPartition(original, start: start, end: end, height: height)
        XCTAssertEqual(result.room.walls.count, 5)
        XCTAssertEqual(result.wallWorkIntents?.last?.use, .partition)
        XCTAssertEqual(result.wallWorkIntents?.last?.wallID, result.room.walls.last?.id)
        XCTAssertEqual(result.room.walls.last?.provenance.source, .manual)
        XCTAssertEqual(result.initialRoom, original.initialRoom)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()), result)
        XCTAssertThrowsError(try SurveyPlanEditing.addingPartition(original, start: start, end: start, height: height))
    }

    func testMovingDesignedPartitionDoesNotPullScannedCornerOrCeiling() throws {
        var scanned = ceilingRoom()
        scanned.room.floors = [.init(boundaries:[scanned.room.walls.map(\.start)],referenceElevation:0,
            provenance:.init(source:.roomPlan))]
        let original = try WallCeilingEstimate.addingIfMissing(to: scanned)
        var designed = try SurveyPlanEditing.addingPartition(original,
            start: .init(x: 0, y: 0, z: 0), end: .init(x: 2, y: 0, z: 1.5), height: 2.5)
        let wall = try XCTUnwrap(designed.room.walls.last)
        designed = try SurveyPlanEditing.addingDoor(designed, wallID: wall.id, width: 0.83, height: 2.04, position: 1)
        let delta = RoomPoint(x: 0.3, y: 0, z: 0.4)
        let result = try SurveyPlanEditing.changingWall(designed, id: wall.id,
            start: wall.start+delta, end: wall.effectiveEnd+delta, height: 2.5)
        XCTAssertEqual(Array(result.room.walls.prefix(4)), original.room.walls)
        XCTAssertEqual(result.room.floors, original.room.floors)
        XCTAssertEqual(result.room.slopes, original.room.slopes)
        XCTAssertEqual(result.initialRoom, original.initialRoom)
        XCTAssertEqual(result.wallWorkIntents, designed.wallWorkIntents)
        let expectedCenter = designed.room.openings[0].center+delta
        XCTAssertEqual(result.room.openings[0].center.x, expectedCenter.x, accuracy:1e-8)
        XCTAssertEqual(result.room.openings[0].center.z, expectedCenter.z, accuracy:1e-8)
        XCTAssertEqual(result.room.walls.last?.id, wall.id)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()), result)
    }

    func testPartitionNumericResizePreservesDoorWorldPositionAndRejectsTruncation() throws {
        var document = try SurveyPlanEditing.addingPartition(ceilingRoom(),
            start: .init(x: 0.5, y: 0, z: 1.5), end: .init(x: 3.5, y: 0, z: 1.5), height: 2.5)
        let wall = try XCTUnwrap(document.room.walls.last)
        document = try SurveyPlanEditing.addingDoor(document, wallID: wall.id, width: 0.83, height: 2.04, position: 1)
        let result = try SurveyPlanEditing.changingWall(document, id: wall.id,
            start: .init(x: 1, y: 0, z: 1.5), end: wall.effectiveEnd, height: 2.5, preserveOpeningLocations: true)
        XCTAssertEqual(result.room.openings[0].center, document.room.openings[0].center)
        XCTAssertEqual(result.room.openings[0].positionOnWall.effectiveValue, 0.5, accuracy: 1e-8)
        XCTAssertThrowsError(try SurveyPlanEditing.changingWall(document, id: wall.id,
            start: .init(x: 2, y: 0, z: 1.5), end: wall.effectiveEnd, height: 2.5, preserveOpeningLocations: true))
        XCTAssertEqual(document.room.walls.last?.length.effectiveValue, 3)
    }

    func testDoorAtPartitionStartCanBeResizedAndPreviewMatchesJoinedWallCommit() throws {
        let original = ceilingRoom()
        let scanned = original.room.walls[0]
        let start = RoomPoint(x:0,y:0,z:-0.5), end = RoomPoint(x:4,y:0,z:-0.5)
        let preview = SurveyPlanEditing.previewWalls(original, wall:scanned, start:start, end:end)
        let committed = try SurveyPlanEditing.changingWall(original,id:scanned.id,start:start,end:end,height:2.5)
        for (a,b) in zip(preview,committed.room.walls) {
            XCTAssertEqual(a.start,b.start)
            XCTAssertEqual(a.effectiveEnd,b.effectiveEnd)
            XCTAssertEqual(a.length.effectiveValue,b.length.effectiveValue)
        }
        var partition = try SurveyPlanEditing.addingPartition(original,
            start:.init(x:0.5,y:0,z:1.5),end:.init(x:3,y:0,z:1.5),height:2.5)
        let wall = try XCTUnwrap(partition.room.walls.last)
        partition = try SurveyPlanEditing.addingDoor(partition,wallID:wall.id,width:0.83,height:2.04,position:0)
        let expanded = try SurveyPlanEditing.changingWall(partition,id:wall.id,start:wall.start,
            end:.init(x:3.5,y:0,z:1.5),height:2.6,preserveOpeningLocations:true)
        XCTAssertEqual(expanded.room.openings[0].positionOnWall.effectiveValue,0)
        XCTAssertEqual(expanded.room.openings[0].center,partition.room.openings[0].center)
    }

    func testPartitionConflictsRejectCrossingAndOverlapButAcceptTJunction() throws {
        let base = ceilingRoom()
        let document = try SurveyPlanEditing.addingPartition(base,
            start: .init(x: 2, y: 0, z: 0), end: .init(x: 2, y: 0, z: 3), height: 2.5)
        XCTAssertThrowsError(try SurveyPlanEditing.addingPartition(document,
            start: .init(x: 1, y: 0, z: 1.5), end: .init(x: 3, y: 0, z: 1.5), height: 2.5))
        XCTAssertThrowsError(try SurveyPlanEditing.addingPartition(document,
            start: .init(x: 2, y: 0, z: 1), end: .init(x: 2, y: 0, z: 2), height: 2.5))
        XCTAssertThrowsError(try SurveyPlanEditing.addingPartition(base,
            start: .init(x: 1, y: 0, z: 0), end: .init(x: 3, y: 0, z: 0), height: 2.5))
        let joined = try SurveyPlanEditing.addingPartition(document,
            start: .init(x: 1, y: 0, z: 1.5), end: .init(x: 2, y: 0, z: 1.5), height: 2.5)
        let wall = try XCTUnwrap(joined.room.walls.last)
        XCTAssertThrowsError(try SurveyPlanEditing.changingWall(joined, id: wall.id,
            start: wall.start, end: .init(x: 3, y: 0, z: 1.5), height: 2.5))
        XCTAssertEqual(joined.room.walls.count, 6)
    }

    func testPlanSnappingUsesScannedOrientationNotWorldAxes() throws {
        let angle = 23.0 * Double.pi / 180
        func p(_ x: Double, _ z: Double) -> RoomPoint {
            .init(x: x*cos(angle)-z*sin(angle), y: 0, z: x*sin(angle)+z*cos(angle))
        }
        let document = ceilingRoom([(0,0),(4,0),(4,3),(0,3)].map { pair in
            let value = p(pair.0,pair.1); return (value.x,value.z)
        })
        let walls = document.room.walls
        let perpendicular = SurveyPlanSnapping.snap(p(1.04,2), anchor:p(1,0), walls:walls, tolerance:0.1)
        XCTAssertEqual(perpendicular.point.x, p(1,2).x, accuracy:1e-8)
        XCTAssertEqual(perpendicular.point.z, p(1,2).z, accuracy:1e-8)
        XCTAssertEqual(perpendicular.title, "90°")
        let parallel = SurveyPlanSnapping.snap(p(2,0.25), anchor:p(1,0.2), walls:walls, tolerance:0.1)
        XCTAssertEqual(parallel.point.x, p(2,0.2).x, accuracy:1e-8)
        XCTAssertEqual(parallel.point.z, p(2,0.2).z, accuracy:1e-8)
        let junction = SurveyPlanSnapping.snap(p(1.03,2.98), anchor:p(1,0), walls:walls, tolerance:0.1)
        XCTAssertEqual(junction.point.x, p(1,3).x, accuracy:1e-8)
        XCTAssertEqual(junction.point.z, p(1,3).z, accuracy:1e-8)
        XCTAssertEqual(junction.title, "90° · mur")
        XCTAssertEqual(document.room.walls, walls)
    }

    func testPlanSnapEndpointPriorityHysteresisAndFreeMovement() {
        let walls = ceilingRoom().room.walls
        let corner = SurveyPlanSnapping.snap(.init(x:0.04,y:0,z:0.04), walls:walls, tolerance:0.1)
        XCTAssertEqual(corner.point, .zero)
        XCTAssertEqual(corner.title, "Extrémité")
        let held = SurveyPlanSnapping.snap(.init(x:0.12,y:0,z:0), walls:walls, tolerance:0.1, latched:corner.key)
        XCTAssertEqual(held.point, .zero)
        let free = RoomPoint(x:1.4,y:0,z:1.5)
        XCTAssertNil(SurveyPlanSnapping.snap(free, anchor:.init(x:1,y:0,z:0), walls:walls, tolerance:0.1).key)
        XCTAssertEqual(SurveyPlanSnapping.snap(free, walls:walls, tolerance:0.1).point, free)
        let otherLevel = RoomPoint(x:0.02,y:3,z:0.02)
        XCTAssertNil(SurveyPlanSnapping.snap(otherLevel, walls:walls, tolerance:0.1).key)
    }

    func testUpdatingCheckpointInvalidatesAssembledPreview() throws {
        var draft = ScanCampaignDraft(); let group = UUID()
        draft.captureLocation = .init(latitude:45.7,longitude:4.8,horizontalAccuracy:10,capturedAt:Date())
        draft.append(chunk(group: group)); draft.append(chunk(group: group))
        // Simulate an existing saved assembly; new captures no longer assemble rooms.
        draft.assemblyVerified = true
        draft = try JSONDecoder().decode(ScanCampaignDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertTrue(draft.sharesWorldSpace)
        draft.upsert(draft.chunks[0])
        XCTAssertFalse(draft.sharesWorldSpace)
    }

    func testDrawnPartitionFollowsRampAndSplitsSupportingWalls() throws {
        var input=ceilingRoom()
        let slope=PlaquistoSlope(plane:.init(a:0,b:0.25,c:2.5),boundaries:[input.room.walls.map(\.start)],
            provenance:.init(source:.manual),accepted:true)
        input.room.slopes=[slope]
        input.room.ceilings=[.init(slopeIDs:[slope.id],provenance:.init(source:.manual))]
        let output=try SurveyPlanEditing.addingFittedPartition(input,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:3))
        let partition=try XCTUnwrap(output.room.walls.last)
        XCTAssertEqual(partition.height.effectiveValue,3.25,accuracy:1e-8)
        XCTAssertTrue(partition.effectiveOutline.contains(.init(x:0,y:2.5,z:0)))
        XCTAssertTrue(partition.effectiveOutline.contains(.init(x:3,y:3.25,z:0)))
        XCTAssertEqual(output.room.walls.count,7)
        XCTAssertEqual(output.room.walls.filter { $0.splitAncestorIDs?.contains(input.room.walls[0].id)==true }.count,2)
        XCTAssertEqual(output.initialRoom,input.initialRoom)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(output.encoded()),output)
    }
    func testDrawnPartitionWithoutCeilingUsesStartingWallHeight() throws {
        let input=ceilingRoom(heights:[3.2,2.5,2.5,2.5])
        let output=try SurveyPlanEditing.addingFittedPartition(input,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:2))
        XCTAssertEqual(output.room.walls.last?.height.effectiveValue,3.2)
    }
    func testWallJunctionKeepsDoorAndHandingOnCorrectChild() throws {
        var input=ceilingRoom()
        let wallID=input.room.walls[0].id
        input=try SurveyPlanEditing.addingDoor(input,wallID:wallID,width:0.83,height:2.04,position:2.7,handing:.left)
        let center=input.room.openings[0].center
        let output=try SurveyPlanEditing.addingFittedPartition(input,start:.init(x:2,y:0,z:0),end:.init(x:2,y:0,z:2))
        let opening=try XCTUnwrap(output.room.openings.first)
        XCTAssertNotEqual(opening.wallID,wallID)
        XCTAssertEqual(opening.positionOnWall.effectiveValue,0.7,accuracy:1e-8)
        XCTAssertEqual(opening.center,center)
        XCTAssertEqual(opening.doorHanding,.left)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(output.encoded()).room.openings[0].doorHanding,.left)
        XCTAssertThrowsError(try SurveyPlanEditing.addingFittedPartition(input,start:.init(x:3,y:0,z:0),end:.init(x:3,y:0,z:2)))
    }

    private func ceilingRoom(_ outline: [(Double, Double)] = [(0,0),(4,0),(4,3),(0,3)], heights: [Double] = []) -> PlaquistoRoomDocument {
        let source = GeometryProvenance(source: .roomPlan)
        let points = outline.map { RoomPoint(x: $0.0, y: 0, z: $0.1) }
        let walls = points.indices.map { i in
            let a = points[i], b = points[(i+1)%points.count]
            return PlaquistoWall(start: a, end: b,
                length: .init(rawValue: (b-a).length, provenance: source),
                height: .init(rawValue: heights.indices.contains(i) ? heights[i] : 2.5, provenance: source), provenance: source)
        }
        return .init(room: .init(walls: walls, metadata: .init(createdAt: Date(timeIntervalSince1970: 0), source: .roomPlan)))
    }

    func testMissingCeilingIsAutomaticallyFlatAndKeepsOriginalAndWalls() throws {
        let original = ceilingRoom()
        let result = try WallCeilingEstimate.addingIfMissing(to: original)
        XCTAssertEqual(result.initialRoom, original.initialRoom)
        XCTAssertEqual(result.room.walls, original.room.walls)
        XCTAssertEqual(result.room.slopes.count, 1)
        let pan = try XCTUnwrap(result.room.slopes.first)
        XCTAssertTrue(pan.accepted)
        XCTAssertFalse(pan.manuallyValidated)
        XCTAssertEqual(pan.provenance.source, .estimated)
        XCTAssertEqual(pan.plane.c, 2.5, accuracy: 1e-8)
        XCTAssertEqual(PlaquistoSurfaceGeometry.area(of: pan), 12, accuracy: 1e-7)
        XCTAssertEqual(try WallCeilingEstimate.addingIfMissing(to: result), result)
        XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()), result)
    }

    func testOppositeWallsInferRampButNoiseDoesNot() throws {
        let original = ceilingRoom(heights: [2.5,3,3.5,3])
        let result = try WallCeilingEstimate.addingIfMissing(to: original)
        let pan = try XCTUnwrap(result.room.slopes.first)
        XCTAssertEqual(result.room.ceilings.first?.estimateSettings?.shape, .singleSlope)
        XCTAssertEqual(pan.plane.height(x: 2, z: 0), 2.5, accuracy: 1e-8)
        XCTAssertEqual(pan.plane.height(x: 2, z: 3), 3.5, accuracy: 1e-8)
        XCTAssertEqual(PlaquistoSurfaceGeometry.area(of: pan), 4 * sqrt(10), accuracy: 1e-7)
        for wall in original.room.walls {
            XCTAssertEqual(PlaquistoWallGeometry.analyze(wall: wall, room: original.room).gross,
                           PlaquistoWallGeometry.analyze(wall: wall, room: result.room).gross)
        }
        let noisy = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom(heights: [2.5,2.54,2.56,2.51]))
        XCTAssertEqual(noisy.room.ceilings.first?.estimateSettings?.shape, .flat)
    }

    func testFourCeilingFamiliesCoverExactFootprintWithoutOverlap() throws {
        let original = ceilingRoom()
        let proposal = try WallCeilingEstimate.propose(in: original.room)
        for shape in CeilingEstimateSettings.Shape.allCases {
            let settings = CeilingEstimateSettings(shape: shape, lowHeight: 2.5, highHeight: 3.5)
            let result = try WallCeilingEstimate.applying(to: original, proposal: proposal, settings: settings, manuallyEdited: true)
            let pans = result.room.slopes
            let count = shape == .flat || shape == .singleSlope ? 1 : (shape == .twoSlopes ? 2 : 4)
            XCTAssertEqual(pans.count, count, "\(shape)")
            let footprint = pans.reduce(0.0) { total, pan in
                total + PlaquistoSurfaceGeometry.area(of: pan) / sqrt(1 + pan.plane.a*pan.plane.a + pan.plane.b*pan.plane.b)
            }
            XCTAssertEqual(footprint, 12, accuracy: 1e-6, "\(shape)")
            XCTAssertTrue(pans.allSatisfy { $0.accepted && $0.manuallyValidated })
            XCTAssertEqual(result.room.walls, original.room.walls)
            XCTAssertEqual(try PlaquistoRoomDocument.decode(result.encoded()), result)
            if shape == .twoSlopes {
                XCTAssertEqual(pans.reduce(0) { $0 + PlaquistoSurfaceGeometry.area(of: $1) }, 6 * sqrt(5), accuracy: 1e-6)
            }
        }
    }

    func testFourPansRemainEditableWithZeroToThreeSupportingWalls() throws {
        let original = try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        for wallCount in 0...3 {
            var partial = original
            partial.room.walls = Array(partial.room.walls.prefix(wallCount))
            let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:partial.room).first)
            let settings = CeilingAutoFit(room:partial.room,proposal:proposal).suggest(shape:.fourSlopes).settings
            let edited = try WallCeilingEstimate.applying(to:partial,proposal:proposal,settings:settings,manuallyEdited:true)
            XCTAssertEqual(edited.room.slopes.count,4)
            XCTAssertEqual(edited.room.walls.count,wallCount,"No missing wall is invented")
            let area = edited.room.slopes.reduce(0.0) {
                $0+PlaquistoSurfaceGeometry.area(of:$1)/sqrt(1+$1.plane.a*$1.plane.a+$1.plane.b*$1.plane.b)
            }
            XCTAssertEqual(area,12,accuracy:1e-6)
        }
    }

    func testCeilingRejectsInvertedHeightsButAllowsFlatLimit() {
        XCTAssertFalse(CeilingEstimateSettings(shape:.fourSlopes,lowHeight:3,highHeight:2).isValid)
        XCTAssertTrue(CeilingEstimateSettings(shape:.fourSlopes,lowHeight:3,highHeight:3).isValid)
    }

    func testMaximumHeightSliderStopsAtMinimumWithoutLoweringIt() {
        for shape in [CeilingEstimateSettings.Shape.singleSlope,.twoSlopes,.fourSlopes] {
            var settings = CeilingEstimateSettings(shape:shape,lowHeight:2.5,highHeight:4)
            settings.setSliderHeight(1.8,isMinimum:false)
            XCTAssertEqual(settings.lowHeight,2.5)
            XCTAssertEqual(settings.highHeight,2.5)
            XCTAssertTrue(settings.isValid)
            settings.setSliderHeight(3.12,isMinimum:false)
            XCTAssertEqual(settings.lowHeight,2.5)
            XCTAssertEqual(settings.highHeight,3.12)
        }
    }

    func testConfiguredRampExtendsWallsAndLayoutsWithoutChangingOriginalMeasurements() throws {
        let original = ceilingRoom()
        let proposal = try WallCeilingEstimate.propose(in:original.room)
        for shape in [CeilingEstimateSettings.Shape.singleSlope,.twoSlopes,.fourSlopes] {
            let settings = CeilingEstimateSettings(shape:shape,lowHeight:2.5,highHeight:4,extendsWalls:true)
            let edited = try WallCeilingEstimate.applying(to:original,proposal:proposal,settings:settings,manuallyEdited:true)
            XCTAssertEqual(edited.room.walls,original.room.walls)
            XCTAssertEqual(edited.initialRoom,original.initialRoom)
            let planes = try WallCeilingEstimate.planes(boundary:proposal.boundary,floorElevation:0,settings:settings)
            for wall in edited.room.walls {
                let polygon = PlaquistoWallGeometry.outline(wall:wall,room:edited.room)
                try LayoutGeometry.validate(polygon.map { .init(x:$0.x*1000,y:$0.y*1000) })
                let analysis = PlaquistoWallGeometry.analyze(wall:wall,room:edited.room)
                for strip in analysis.strips {
                    for (x,h) in [(strip.x0,strip.h0),(strip.x1,strip.h1)] {
                        let p = wall.start+wall.direction*x
                        let roof = try XCTUnwrap(planes.map { $0.height(x:p.x,z:p.z) }.min())
                        XCTAssertEqual(h,max(2.5,roof),accuracy:1e-6)
                    }
                }
            }
            let survey = ProjectSurveyRecord(projectID:UUID(),name:"Rampant",checkpoints:[
                .init(roomID:edited.room.id,document:edited,spatialLinkState:.sharedWorldSpace,workState:.validated)])
            let surfaces = SurveyWorkGeometry.surfaces(in:survey).filter { $0.source.kind == .wall }
            XCTAssertEqual(surfaces.count,4)
            for surface in surfaces {
                let wall = try XCTUnwrap(edited.room.walls.first { $0.id == surface.source.surfaceID })
                XCTAssertEqual(try surface.surface.netMeasuredArea()/1_000_000,
                    PlaquistoWallGeometry.analyze(wall:wall,room:edited.room).net,accuracy:1e-6)
            }
            let exportedWalls = try SurveyDAEExport.meshes(for:survey).filter { $0.kind == "wall" }
            XCTAssertEqual(exportedWalls.count,4)
            XCTAssertEqual(exportedWalls.flatMap(\.triangles).map(\.y).max(),
                surfaces.flatMap(\.triangles).map(\.y).max())
            XCTAssertEqual(try PlaquistoRoomDocument.decode(edited.encoded()),edited)
        }
    }

    func testWallExtensionStaysInsideEditedZoneAndNeverShortensWalls() throws {
        let original = ceilingRoom()
        var proposal = try WallCeilingEstimate.propose(in:original.room)
        proposal.boundary = [.init(x:0,y:0,z:0),.init(x:2,y:0,z:0),.init(x:2,y:0,z:3),.init(x:0,y:0,z:3)]
        let settings = CeilingEstimateSettings(shape:.singleSlope,lowHeight:3,highHeight:4,extendsWalls:true)
        var edited = try WallCeilingEstimate.applying(to:original,proposal:proposal,settings:settings,manuallyEdited:true)
        let wall = edited.room.walls[0]
        let analysis = PlaquistoWallGeometry.analyze(wall:wall,room:edited.room)
        XCTAssertEqual(analysis.gross,12,accuracy:1e-6) // 2 × 3.5 + 2 × 2.5
        try LayoutGeometry.validate(PlaquistoWallGeometry.outline(wall:wall,room:edited.room).map { .init(x:$0.x*1000,y:$0.y*1000) })
        var upper = wall; upper.id = UUID(); upper.start.y = 5; upper.end.y = 5
        XCTAssertEqual(PlaquistoWallGeometry.analyze(wall:upper,room:edited.room).gross,10,accuracy:1e-6)
        let editProposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:edited.room).first)
        edited = try WallCeilingEstimate.applying(to:edited,proposal:editProposal,
            settings:.init(shape:.singleSlope,lowHeight:1,highHeight:2,extendsWalls:true),manuallyEdited:true)
        XCTAssertEqual(PlaquistoWallGeometry.outline(wall:wall,room:edited.room),wall.effectiveOutline)
        XCTAssertEqual(CeilingAutoFit(room:edited.room,proposal:editProposal).suggest(shape:.flat).settings.lowHeight,2.5,accuracy:1e-8)
    }

    func testRampExtensionKeepsDoorDeduction() throws {
        let base = ceilingRoom()
        let original = try SurveyPlanEditing.addingDoor(base,wallID:base.room.walls[0].id,width:0.8,height:2,position:1)
        let proposal = try WallCeilingEstimate.propose(in:original.room)
        let edited = try WallCeilingEstimate.applying(to:original,proposal:proposal,
            settings:.init(shape:.twoSlopes,lowHeight:2.5,highHeight:4,extendsWalls:true),manuallyEdited:true)
        let analysis = PlaquistoWallGeometry.analyze(wall:edited.room.walls[0],room:edited.room)
        XCTAssertEqual(analysis.gross,13,accuracy:1e-6)
        XCTAssertEqual(analysis.openingArea,1.6,accuracy:1e-6)
        XCTAssertEqual(analysis.net,11.4,accuracy:1e-6)
        XCTAssertEqual(edited.room.openings,original.room.openings)
        XCTAssertTrue(analysis.strips.allSatisfy { $0.heightSource == .estimated })
    }

    @MainActor func testConfiguredCeilingRebuildsExtendedWallsButKeepsPreviewCamera() throws {
        let original = try WallCeilingEstimate.addingIfMissing(to:ceilingRoom())
        let proposal = try XCTUnwrap(WallCeilingEstimate.manualProposals(in:original.room).first)
        let reset = UUID()
        var scene = RoomDomainScene(room:original.room,selected:.constant(nil),ceilingMode:2,showFloor:true,topView:false,cameraReset:reset)
        let coordinator = scene.makeCoordinator(), view = SCNView()
        view.scene = SCNScene(); scene.update(view,coordinator:coordinator)
        let camera = try XCTUnwrap(view.pointOfView), wall = try XCTUnwrap(coordinator.walls.first)
        let edited = try WallCeilingEstimate.applying(to:original,proposal:proposal,
            settings:.init(shape:.singleSlope,lowHeight:2.5,highHeight:4,extendsWalls:true),manuallyEdited:true)
        scene = RoomDomainScene(room:edited.room,selected:.constant(nil),ceilingMode:2,showFloor:true,topView:false,cameraReset:reset)
        scene.update(view,coordinator:coordinator)
        XCTAssertTrue(view.pointOfView === camera)
        XCTAssertFalse(coordinator.walls.first === wall)
        XCTAssertEqual(coordinator.walls.count,4)
    }

    func testConcaveCeilingStaysConcaveForAllFamiliesAndOrientations() throws {
        let original = ceilingRoom([(0,0),(4,0),(4,1),(2,1),(2,3),(0,3)])
        let proposal = try WallCeilingEstimate.propose(in: original.room)
        for shape in CeilingEstimateSettings.Shape.allCases {
            for angle in [0.0, 0.37, Double.pi/2] {
                let settings = CeilingEstimateSettings(shape: shape, lowHeight: 2.5, highHeight: 3.7, azimuth: angle, ridgePosition: 0.35)
                let result = try WallCeilingEstimate.applying(to: original, proposal: proposal, settings: settings, manuallyEdited: true)
                let area = result.room.slopes.reduce(0.0) { total, pan in
                    total + PlaquistoSurfaceGeometry.area(of: pan) / sqrt(1 + pan.plane.a*pan.plane.a + pan.plane.b*pan.plane.b)
                }
                XCTAssertEqual(area, 8, accuracy: 1e-6, "\(shape), \(angle)")
            }
        }
    }

    func testMissingCeilingRefusesOpenWallsInvalidHeightAndObservedReplacement() throws {
        var open = ceilingRoom(); open.room.walls.removeLast()
        XCTAssertThrowsError(try WallCeilingEstimate.addingIfMissing(to: open))
        let original = ceilingRoom(), proposal = try WallCeilingEstimate.propose(in: original.room)
        for value in [0.0, -1, Double.nan, Double.infinity, 1001] {
            XCTAssertThrowsError(try WallCeilingEstimate.applying(to: original, proposal: proposal,
                settings: .init(lowHeight: value, highHeight: value), manuallyEdited: true))
        }
        var observed = try WallCeilingEstimate.addingIfMissing(to: original)
        observed.room.slopes[0].provenance.source = .lidar
        observed.room.ceilings[0].provenance.source = .lidar
        XCTAssertEqual(try WallCeilingEstimate.addingIfMissing(to: observed), observed)
        XCTAssertThrowsError(try WallCeilingEstimate.applying(to: observed, proposal: proposal,
            settings: proposal.suggestedSettings, manuallyEdited: true))
    }

    func testEstimatedCeilingEditKeepsIDsAndZeroRiseIsFlat() throws {
        let original = try WallCeilingEstimate.addingIfMissing(to: ceilingRoom())
        let proposal = try WallCeilingEstimate.propose(in: original.room)
        let edited = try WallCeilingEstimate.applying(to: original, proposal: proposal,
            settings: .init(shape: .fourSlopes, lowHeight: 3, highHeight: 3), manuallyEdited: true)
        XCTAssertEqual(edited.room.ceilings.first?.id, original.room.ceilings.first?.id)
        XCTAssertEqual(edited.room.slopes.first?.id, original.room.slopes.first?.id)
        XCTAssertEqual(edited.room.slopes.count, 1)
        XCTAssertEqual(edited.room.slopes.first?.plane.slopeDegrees, 0)
        XCTAssertEqual(edited.initialRoom, original.initialRoom)
    }

    func testGeneratedPansCanBeSelectedForDevelopedCeilingQuantities() throws {
        let original = ceilingRoom()
        let proposal = try WallCeilingEstimate.propose(in: original.room)
        for shape in CeilingEstimateSettings.Shape.allCases {
            let document = try WallCeilingEstimate.applying(to: original, proposal: proposal,
                settings: .init(shape: shape, lowHeight: 2.5, highHeight: 3.5, azimuth: 0.37), manuallyEdited: true)
            let checkpoint = ProjectRoomScanCheckpoint(roomID: document.room.id, document: document,
                spatialLinkState: .needsLink, workState: .validated)
            let survey = ProjectSurveyRecord(projectID: UUID(), name: "Plafond test", checkpoints: [checkpoint])
            let surfaces = SurveyWorkGeometry.surfaces(in: survey).filter { $0.source.kind == .ceiling }
            XCTAssertEqual(surfaces.count, document.room.slopes.count)
            XCTAssertEqual(SurveyWorkGeometry.totalArea(surfaces), document.room.slopes.reduce(0) {
                $0 + PlaquistoSurfaceGeometry.area(of: $1)
            }, accuracy: 1e-6)
            let copied = document.remappingDomainIDs()
            try copied.validate()
            XCTAssertEqual(copied.room.ceilings.first?.estimateSettings, document.room.ceilings.first?.estimateSettings)
            XCTAssertNotEqual(copied.room.ceilings.first?.id, document.room.ceilings.first?.id)
        }
    }

    func testRecoveryIsolatesCorruptDraftWithoutDeletingIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var first = ScanCampaignDraft(); first.append(chunk(group: UUID()))
        var second = ScanCampaignDraft(); second.append(chunk(group: UUID()))
        try ScanCampaignStore.save(first, directory: folder)
        try ScanCampaignStore.save(second, directory: folder)
        let corrupt = folder.appendingPathComponent("damaged.json")
        try Data("invalid json".utf8).write(to: corrupt)
        let result = try ScanCampaignStore.recover(directory: folder)
        XCTAssertEqual(Set(result.drafts.map(\.id)), [first.id, second.id])
        XCTAssertEqual(result.unreadableFiles, ["damaged.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
    }

    func testCompletionIsOnlyPublishedAfterDurableSaveAndCanBeRetried() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var draft = ScanCampaignDraft(); draft.append(chunk(group: UUID()))
        try Data("blocking file".utf8).write(to: folder)
        XCTAssertThrowsError(try ScanCampaignStore.completing(draft, directory: folder))
        XCTAssertFalse(draft.isComplete)
        try FileManager.default.removeItem(at: folder)
        draft = try ScanCampaignStore.completing(draft, directory: folder)
        XCTAssertTrue(draft.isComplete)
        XCTAssertTrue(try XCTUnwrap(ScanCampaignStore.loadAll(directory: folder).first).isComplete)
    }

    private func point(_ z: Double, x: Double = 0) -> RoomPoint { .init(x: x, y: 1.5, z: z) }

    func testSemanticLabelsDoNotInventRoomBoundaries() {
        XCTAssertEqual(ScanRoomUsage.proposedName([.kitchen, .livingRoom, .kitchen]), "Salon / Cuisine")
        XCTAssertEqual(ScanRoomUsage.proposedName([]), "Pièce à identifier")
        XCTAssertEqual(ScanRoomUsage.proposedName([.unidentified]), "Pièce à identifier")
        XCTAssertEqual(ScanRoomUsage.proposedName([.bedroom, .unidentified]), "Chambre")
    }

    func testDraftRoundTripKeepsIndependentChunksAndDisambiguatesNames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var draft = ScanCampaignDraft(); let group = UUID()
        draft.append(chunk(group: group)); draft.append(chunk(group: group))
        XCTAssertEqual(draft.chunks.map(\.name), ["Chambre", "Chambre 2"])
        XCTAssertFalse(draft.sharesWorldSpace, "Same AR session is not proof that raw room outputs are assembled")
        draft.assemblyVerified = true
        XCTAssertTrue(draft.sharesWorldSpace)
        try ScanCampaignStore.save(draft, directory: folder)
        let restored = try XCTUnwrap(ScanCampaignStore.loadAll(directory: folder).first)
        XCTAssertEqual(restored.chunks.map(\.id), draft.chunks.map(\.id))
        XCTAssertEqual(restored.chunks.map { $0.document.room.id }, draft.chunks.map { $0.document.room.id })
        XCTAssertFalse(restored.isComplete)
        draft.continuityReliable = false
        XCTAssertFalse(draft.sharesWorldSpace)
        draft.continuityReliable = true; draft.append(chunk(group: UUID()))
        XCTAssertFalse(draft.sharesWorldSpace)
    }

    @MainActor func testCampaignSaveIsAtomicIdempotencyGuardedAndDoesNotMergeRoomNames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: url)
        var draft = ScanCampaignDraft(); let group = UUID()
        draft.append(chunk(group: group)); draft.append(chunk(group: group))
        draft.assemblyVerified = true
        let id = try store.saveScanCampaign(draft, projectID: nil, newProjectName: "Maison", surveyName: "Rez-de-chaussée",
            newProjectAddress:"Adresse confirmée")
        let project = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(project.rooms.count, 2)
        XCTAssertTrue(project.works.isEmpty)
        XCTAssertEqual(project.address,"Adresse confirmée")
        XCTAssertEqual(store.surveys.first?.captureLocation,draft.captureLocation)
        XCTAssertEqual(store.surveys.first?.checkpoints.count, 2)
        XCTAssertTrue(store.surveys.first!.checkpoints.allSatisfy { $0.spatialLinkState == .sharedWorldSpace })
        XCTAssertThrowsError(try store.saveScanCampaign(draft, projectID: project.id, newProjectName: "", surveyName: "Doublon"))
        XCTAssertEqual(store.projects.first?.rooms.count, 2)
        var next = ScanCampaignDraft(); next.append(chunk(group: UUID()))
        try store.saveScanCampaign(next, projectID: project.id, newProjectName: "", surveyName: "Étage",newProjectAddress:"Ne pas écraser")
        let loaded = ProjectStore(fileURL: url)
        XCTAssertEqual(loaded.projects.first?.address,"Adresse confirmée")
        XCTAssertEqual(loaded.surveys.first(where:{$0.id==id})?.captureLocation,draft.captureLocation)
        XCTAssertEqual(loaded.surveys.first(where: { $0.id == id })?.checkpoints.count, 2)
        XCTAssertEqual(loaded.projects.first?.rooms.map(\.name), ["Chambre", "Chambre 2", "Chambre 3"])
        var invalid = ScanCampaignDraft(); invalid.append(chunk(group: UUID())); invalid.chunks[0].name = " "
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.saveScanCampaign(invalid, projectID: nil, newProjectName: "Fantôme", surveyName: "Invalide"))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    @MainActor func testCampaignDiskFailureLeavesNoProject() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appendingPathComponent("blocker")
        try Data([0]).write(to: blocker)
        let store = ProjectStore(fileURL: blocker.appendingPathComponent("projects.json"))
        var draft = ScanCampaignDraft(); draft.append(chunk(group: UUID()))
        XCTAssertThrowsError(try store.saveScanCampaign(draft, projectID: nil, newProjectName: "Maison", surveyName: "Relevé"))
        XCTAssertTrue(store.projects.isEmpty); XCTAssertTrue(store.surveys.isEmpty)
    }

    @MainActor func testPossibleRevisitIsKeptButRequiresExplicitDecisionBeforeProjectSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(fileURL: folder.appendingPathComponent("projects.json"))
        var draft = ScanCampaignDraft(); let group = UUID()
        draft.append(chunk(group: group))
        var revisit = chunk(group: group)
        revisit.possibleDuplicateOf = draft.chunks[0].id
        draft.append(revisit)
        XCTAssertEqual(draft.chunks.count, 2)
        XCTAssertTrue(draft.hasUnreviewedDuplicates)
        XCTAssertThrowsError(try store.saveScanCampaign(draft, projectID: nil, newProjectName: "Maison", surveyName: "Relevé"))
        XCTAssertTrue(store.projects.isEmpty)
        draft.chunks[1].keepAfterReview = false
        try store.saveScanCampaign(draft, projectID: nil, newProjectName: "Maison", surveyName: "Relevé")
        XCTAssertEqual(store.surveys.first?.checkpoints.count, 1)
        XCTAssertEqual(draft.chunks.count, 2, "The original capture remains recoverable in the draft")
    }

    func testFloorContainmentUsesElevationAndNotOnlyBoundingBox() {
        let p = GeometryProvenance(source: .roomPlan)
        let ring = [RoomPoint(x: 0,y: 0,z: 0), .init(x: 4,y: 0,z: 0), .init(x: 4,y: 0,z: 3), .init(x: 0,y: 0,z: 3)]
        let room = PlaquistoRoomModel(floors: [.init(boundaries: [ring], referenceElevation: 0, provenance: p)], metadata: .init(source: .roomPlan, sourceObjectCount: 0))
        XCTAssertTrue(ScanFloorContainment.contains(.init(x: 2,y: 1.5,z: 2), in: room))
        XCTAssertFalse(ScanFloorContainment.contains(.init(x: 5,y: 1.5,z: 2), in: room))
        XCTAssertFalse(ScanFloorContainment.contains(.init(x: 2,y: 4.5,z: 2), in: room))
    }

    private func chunk(group: UUID) -> ScanRoomChunk {
        let p = GeometryProvenance(source: .roomPlan)
        let wall = PlaquistoWall(start: .zero, end: .init(x: 4,y: 0,z: 0),
            length: .init(rawValue: 4, provenance: p), height: .init(rawValue: 2.5, provenance: p), provenance: p)
        let doc = PlaquistoRoomDocument(room: .init(walls: [wall], metadata: .init(source: .roomPlan, sourceObjectCount: 0)))
        return .init(referenceGroupID: group, name: "Chambre", usages: [.bedroom], document: doc)
    }

    func testNewRoomDoesNotErasePreviousLiveOverview() {
        var overview = ScanLiveOverview()
        let first = chunk(group: UUID()), second = chunk(group: UUID())
        overview.update(id: first.id, room: first.document.room)
        overview.update(id: first.id, room: first.document.room, isProcessing: true)
        overview.update(id: second.id, room: .init(metadata: .init(source: .roomPlan, sourceObjectCount: 0)))
        XCTAssertEqual(overview.entries.map(\.id), [first.id])
        overview.update(id: second.id, room: second.document.room)
        XCTAssertEqual(overview.entries.map(\.id), [first.id, second.id])
        XCTAssertEqual(overview.wallCount, 2)
        overview.update(id: first.id, room: first.document.room)
        XCTAssertEqual(overview.entries.count, 2, "An async room result must replace only that room")
    }

    func testPendingCheckpointSurvivesRelaunchAndRefinementDoesNotDuplicateIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var draft = ScanCampaignDraft()
        var first = chunk(group: UUID()); first.processingPending = true
        draft.upsert(first)
        try ScanCampaignStore.save(draft, directory: folder)
        var recovered = try XCTUnwrap(ScanCampaignStore.loadAll(directory: folder).first)
        XCTAssertEqual(recovered.chunks.count, 1)
        XCTAssertTrue(try XCTUnwrap(recovered.chunks[0].processingPending))
        recovered.chunks[0].name = "Mon espace"
        recovered.chunks[0].keepAfterReview = true
        first.document.room.walls[0].height.rawValue = 2.7
        first.processingPending = false
        recovered.upsert(first)
        XCTAssertEqual(recovered.chunks.count, 1)
        XCTAssertEqual(recovered.chunks[0].name, "Mon espace")
        XCTAssertEqual(recovered.chunks[0].document.room.walls[0].height.effectiveValue, 2.7)
        XCTAssertEqual(recovered.chunks[0].keepAfterReview, true)
        XCTAssertEqual(ScanLiveOverview(draft: recovered).wallCount, 1)
    }

    func testOlderDraftWithoutPendingFlagRemainsReadable() throws {
        var draft = ScanCampaignDraft(); draft.append(chunk(group: UUID()))
        let encoded = try JSONEncoder().encode(draft)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("processingPending"))
        let loaded = try JSONDecoder().decode(ScanCampaignDraft.self, from: encoded)
        XCTAssertNil(loaded.chunks[0].processingPending)
    }

    func testLateUsageRecognitionRenamesCheckpointWithoutCreatingAnotherRoom() {
        var draft = ScanCampaignDraft()
        var first = chunk(group: UUID())
        first.name = "Pièce à identifier"; first.usages = []
        draft.upsert(first)
        first.name = "Salon"; first.usages = [.livingRoom]
        draft.upsert(first, preserveName: false)
        XCTAssertEqual(draft.chunks.count, 1)
        XCTAssertEqual(draft.chunks[0].name, "Salon")
        first.name = "Pièce à identifier"; first.usages = []
        draft.upsert(first, preserveName: false)
        XCTAssertEqual(draft.chunks[0].name, "Salon", "Temporary loss of classification is not a new room")
    }

    func testFloorPlanProjectsSameCorrectedWallsAndKeepsOpeningGaps() throws {
        var source = chunk(group: UUID())
        var room = source.document.room
        let p = GeometryProvenance(source: .roomPlan)
        try room.walls[0].length.correct(5)
        let wallID = room.walls[0].id
        room.openings = [.init(wallID: wallID, kind: .door, center: .init(x: 1.5,y: 1,z: 0),
            width: .init(rawValue: 1, provenance: p), height: .init(rawValue: 2, provenance: p),
            sillHeight: .init(rawValue: 0, provenance: p), positionOnWall: .init(rawValue: 1, provenance: p), provenance: p)]
        room.walls[0].openingIDs = room.openings.map(\.id)
        source.document = .init(room: room)
        var overview = ScanLiveOverview(); overview.update(id: source.id, room: room)
        let plan = ScanFloorPlan(overview: overview)
        XCTAssertEqual(plan.dimensions[0].meters, 5)
        XCTAssertEqual(plan.segments.count, 3)
        XCTAssertEqual(plan.segments.filter { $0.opening == .door }.count, 1)
        XCTAssertEqual(plan.segments.last?.b.x, 5)
        XCTAssertEqual(plan.segments.filter { $0.opening == nil }.reduce(0) { $0+($1.b-$1.a).length }, 4, accuracy: 1e-6)
        XCTAssertTrue(plan.points.allSatisfy { $0.y == 0 })
        XCTAssertEqual(room.walls[0].length.rawValue, 4, "Projection must not rewrite scan measurements")
    }

    func testFloorPlanAppliesSurveyTransformAndRetainsBothRooms() {
        let a = chunk(group: UUID()), b = chunk(group: UUID())
        var overview = ScanLiveOverview()
        overview.update(id: a.id, room: a.document.room)
        overview.update(id: b.id, room: b.document.room)
        var transform = SurveyTransform3D.identity
        transform.values[12] = 6; transform.values[14] = 3
        let plan = ScanFloorPlan(overview: overview, transforms: [b.id: transform])
        XCTAssertEqual(plan.dimensions.count, 2)
        XCTAssertEqual(plan.dimensions[0].a.x, 0)
        XCTAssertEqual(plan.dimensions[1].a.x, 6)
        XCTAssertEqual(plan.dimensions[1].a.z, 3)
        XCTAssertEqual(plan.dimensions[1].b.x, 10)
    }

}
