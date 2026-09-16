import XCTest
@testable import Plaquisto

final class SheetLayoutEngineTests: XCTestCase {
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
        var layer = LayoutLayer(); layer.offset = .init(x: -200, y: 350)
        let a = try check(surface(), layer, area: 9_000_000, count: 8)
        XCTAssertEqual(a, try SheetLayoutEngine.calculate(surface: surface(), layer: layer))
        layer.offset.x += 1200; layer.offset.y += 2500
        XCTAssertEqual(a, try SheetLayoutEngine.calculate(surface: surface(), layer: layer))
        layer.orientation = .horizontal; layer.offset = .zero
        _ = try check(surface(), layer, area: 9_000_000, count: 6)
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
            for vertex in shape { XCTAssertLessThan(result.map { ($0-vertex).length }.min()!,14) }
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
