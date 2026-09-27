import XCTest
import ARKit
import SceneKit
import RoomPlan
import SwiftUI
@testable import Plaquisto

final class SurveyCaptureTests: XCTestCase {
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
        XCTAssertEqual(image.size,CGSize(width:288,height:216))
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
        for values in [(0.8,2.04,1.0), (0.83,3.0,1.0), (0.83,2.04,-0.1), (0.83,2.04,3.5), (0.83,2.04,Double.nan)] {
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
