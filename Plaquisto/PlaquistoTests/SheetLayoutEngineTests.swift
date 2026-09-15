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
        let reloaded = LayoutEditorModel(defaults: defaults)
        XCTAssertEqual(reloaded.document, changed)
        var dragged = changed; dragged.surface.contour.swapAt(1, 2)
        editor.preview(dragged); editor.finishGesture(from: changed)
        XCTAssertEqual(editor.document, changed)
    }
}
