// Run with swiftc alongside ScannerCeilingReconstruction.swift; no device required.
import Foundation
import simd

@main
enum ScannerCeilingReconstructionChecks {
    typealias Engine = ScannerCeilingReconstruction

    static func walls(_ polygon: [SIMD2<Double>]) -> [Engine.Wall] {
        polygon.indices.map { .init(start: polygon[$0], end: polygon[($0 + 1) % polygon.count]) }
    }
    static func mesh(slope: Double = 0, hole: Bool = true, twoLevels: Bool = false) -> [Engine.Triangle] {
        var result: [Engine.Triangle] = []
        for x in 0..<10 {
            for z in 0..<10 {
                if hole && (3...6).contains(x) && (3...6).contains(z) { continue }
                func point(_ i: Int, _ j: Int) -> SIMD3<Double> {
                    let px = Double(i) * 0.099, pz = Double(j) * 0.15
                    return SIMD3(px, 2.3 + px * slope + (twoLevels && x >= 5 ? 0.4 : 0), pz)
                }
                let a = point(x, z), b = point(x + 1, z), c = point(x + 1, z + 1), d = point(x, z + 1)
                result.append(.init(a: a, b: b, c: c))
                result.append(.init(a: a, b: c, c: d))
            }
        }
        return result
    }
    static func success(_ result: Result<Engine.Surface, Engine.Failure>) -> Engine.Surface {
        switch result {
        case .success(let surface): return surface
        case .failure(let error): fatalError("Unexpected reconstruction failure: \(error)")
        }
    }
    static func main() {
        let roofWalls = walls([.init(0, 0), .init(4, 0), .init(4, 3), .init(0, 3)])
        func roofMesh(ridge: Double = 2, leftSlope: Double = 0.5, rightSlope: Double = 0.5, hole: Bool = false) -> [Engine.Triangle] {
            var triangles: [Engine.Triangle] = []
            for x in 0..<40 {
                for z in 0..<30 {
                    if hole && (26...31).contains(x) && (10...17).contains(z) { continue }
                    func p(_ i: Int, _ j: Int) -> SIMD3<Double> {
                        let px = Double(i) * 0.1
                        return .init(px, 3 - (px <= ridge ? leftSlope * (ridge - px) : rightSlope * (px - ridge)), Double(j) * 0.1)
                    }
                    let a = p(x, z), b = p(x + 1, z), c = p(x + 1, z + 1), d = p(x, z + 1)
                    triangles += [.init(a: a, b: b, c: c), .init(a: a, b: c, c: d)]
                }
            }
            return triangles
        }
        let roof = success(Engine.reconstruct(walls: roofWalls, triangles: roofMesh()))
        precondition(roof.pans.count == 2)
        precondition(abs(roof.area - 12 * sqrt(1.25)) < 1e-7)
        precondition(roof.pans.allSatisfy { abs($0.area - 6 * sqrt(1.25)) < 1e-7 })
        let fullRoofMesh = roofMesh()
        let sampledRoof = stride(from: 0, to: fullRoofMesh.count, by: 28).map { fullRoofMesh[$0] }
        precondition(success(Engine.reconstruct(walls: roofWalls, triangles: sampledRoof, minimumSupportArea: 0.15 / 28)).pans.count == 2)
        let threePlanes = fullRoofMesh.map { triangle -> Engine.Triangle in
            func cap(_ p: SIMD3<Double>) -> SIMD3<Double> { .init(p.x, min(p.y, 2.65), p.z) }
            return .init(a: cap(triangle.a), b: cap(triangle.b), c: cap(triangle.c))
        }
        if case .success = Engine.reconstruct(walls: roofWalls, triangles: threePlanes) {
            fatalError("A substantial third plane must not be silently reconstructed as two")
        }
        let holedRoof = success(Engine.reconstruct(walls: roofWalls, triangles: roofMesh(hole: true)))
        precondition(abs(holedRoof.area - roof.area) < 1e-7, "Missing mesh is not automatically a deductible roof window")
        let asymmetric = success(Engine.reconstruct(walls: roofWalls, triangles: roofMesh(ridge: 1.6, leftSlope: 0.4, rightSlope: 0.65)))
        precondition(asymmetric.pans.count == 2)
        precondition(abs(asymmetric.area - 3 * (1.6 * sqrt(1.16) + 2.4 * sqrt(1.4225))) < 1e-7)
        let invertedTriangles = roofMesh().reversed().map { Engine.Triangle(a: $0.c, b: $0.b, c: $0.a) }
        precondition(abs(success(Engine.reconstruct(walls: roofWalls.reversed().map { .init(start: $0.end, end: $0.start) }, triangles: invertedTriangles)).area - roof.area) < 1e-7)
        let roofOffset = SIMD3<Double>(-11, 4, 8)
        let movedRoof = success(Engine.reconstruct(walls: roofWalls.map { .init(start: $0.start + SIMD2(roofOffset.x, roofOffset.z), end: $0.end + SIMD2(roofOffset.x, roofOffset.z)) }, triangles: roofMesh().map { .init(a: $0.a + roofOffset, b: $0.b + roofOffset, c: $0.c + roofOffset) }))
        precondition(abs(movedRoof.area - roof.area) < 1e-7)
        let notchedWalls = walls([.init(0, 0), .init(4, 0), .init(4, 1), .init(3, 1), .init(3, 3), .init(0, 3)])
        let notched = success(Engine.reconstruct(walls: notchedWalls, triangles: roofMesh()))
        precondition(notched.pans.count == 2 && abs(notched.area - 10 * sqrt(1.25)) < 1e-7)
        print("PASS: two opposing pans, unequal slopes, mesh hole, reversed normals/order, world translation, concave two-pan outline")
        let rectangle: [SIMD2<Double>] = [.init(0, 0), .init(0.99, 0), .init(0.99, 1.5), .init(0, 1.5)]
        let boundary = walls(rectangle)
        var diagnostic: Engine.Diagnostics?
        _ = Engine.reconstruct(walls: boundary, triangles: mesh()) { diagnostic = $0 }
        precondition(diagnostic?.stage == "success")
        precondition(diagnostic!.retainedTriangles > 12 && diagnostic!.supportRatio! >= 0.7)
        let encodedDiagnostic = try! JSONEncoder().encode(diagnostic!)
        precondition((try! JSONDecoder().decode(Engine.Diagnostics.self, from: encodedDiagnostic)).stage == "success")
        _ = Engine.reconstruct(walls: [], triangles: mesh()) { diagnostic = $0 }
        precondition(diagnostic?.stage == "contour")
        _ = Engine.reconstruct(walls: boundary, triangles: []) { diagnostic = $0 }
        precondition(diagnostic?.stage == "insufficient_samples" && diagnostic?.retainedTriangles == 0)
        _ = Engine.reconstruct(walls: boundary, triangles: mesh(hole: false, twoLevels: true)) { diagnostic = $0 }
        precondition(diagnostic?.stage == "plane_support_below_70_percent")
        precondition(diagnostic!.supportRatio! < 0.7)
        let branchData = try! Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/sloped-room-branches-20260911.json"))
        let branchJSON = try! JSONSerialization.jsonObject(with: branchData) as! [String: Any]
        let branchWalls = (branchJSON["rawWalls"] as! [[String: Any]]).map { row -> Engine.Wall in
            let a = row["start"] as! [Double], b = row["end"] as! [Double]
            return .init(start: SIMD2(a[0], a[1]), end: SIMD2(b[0], b[1]))
        }
        let branchVariants = [branchWalls, branchWalls.reversed().map { Engine.Wall(start: $0.end, end: $0.start) }]
        for variant in branchVariants {
            for position in [SIMD2<Double>.zero, SIMD2(-1, 0), SIMD2(0, 1)] {
                let proposals = Engine.closureProposals(walls: variant, keepPoint: position)
                precondition(!proposals.isEmpty, "Recorded branched room must offer its observed local loop")
                // Synthetic slope validates the pipeline, not the recorded mesh
                // (the user's diagnostic contains only wall geometry).
                let surface = success(Engine.reconstruct(walls: proposals[0], triangles: mesh(slope: 0.5)))
                precondition(abs(surface.area / sqrt(1.25) - 3.00655 * 3.56224) < 0.03,
                             "Select the main rectangle, not its adjacent narrow return")
            }
        }
        precondition(Engine.closureProposals(walls: branchWalls, keepPoint: .init(20, 20)).isEmpty)
        let recordedData = try! Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/kitchen-open-corridor-20260911.json"))
        let recordedJSON = try! JSONSerialization.jsonObject(with: recordedData) as! [String: Any]
        let recordedWalls = (recordedJSON["rawWalls"] as! [[String: Any]]).map { row -> Engine.Wall in
            let a = row["start"] as! [Double], b = row["end"] as! [Double]
            return .init(start: SIMD2(a[0], a[1]), end: SIMD2(b[0], b[1]))
        }
        let recordedZones = Engine.zoneProposals(walls: recordedWalls, keepPoint: .zero)
        precondition(!recordedZones.isEmpty, "Real failed scan must now propose a kitchen boundary")
        let recorded = recordedZones[0]
        func cross2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
        precondition(recorded.allSatisfy { cross2($0.end - $0.start, -$0.start) >= -1e-6 })
        precondition(recorded.contains { cross2($0.end - $0.start, SIMD2<Double>(3, -1.2) - $0.start) < 0 },
                     "Proposed kitchen must exclude the observed corridor")
        let recordedArea = abs(recorded.reduce(0.0) { $0 + cross2($1.start, $1.end) }) / 2
        precondition(recordedArea > 12 && recordedArea < 18, "Plausibility check, not a measured ground-truth area")
        let reversedRecorded = recordedWalls.reversed().map { Engine.Wall(start: $0.end, end: $0.start) }
        let reversedZones = Engine.zoneProposals(walls: reversedRecorded, keepPoint: .zero)
        precondition(!reversedZones.isEmpty)
        let reversedArea = abs(reversedZones[0].reduce(0.0) { $0 + cross2($1.start, $1.end) }) / 2
        precondition(abs(recordedArea - reversedArea) < 0.1)
        print("Recorded kitchen regression: \(recordedZones.count) proposals, first area \(recordedArea) m² (estimated)")
        let kitchen: [Engine.Wall] = [
            .init(start: .init(0, 0), end: .init(4, 0)),
            .init(start: .init(4, 0), end: .init(4, 4)),
            .init(start: .init(4, 4), end: .init(2.5, 4)),
            .init(start: .init(1.5, 4), end: .init(0, 4)),
            .init(start: .init(0, 4), end: .init(0, 0)),
            .init(start: .init(1.5, 4), end: .init(1.5, 7)),
            .init(start: .init(2.5, 4), end: .init(2.5, 7))]
        let kitchenZones = Engine.zoneProposals(walls: kitchen, keepPoint: .init(2, 2))
        precondition(!kitchenZones.isEmpty, "Kitchen should stop at the corridor mouth without a far wall")
        precondition(abs(success(Engine.reconstruct(walls: kitchenZones[0], triangles: mesh())).area - 16) < 1e-8)
        let clutter = kitchen + walls([.init(8, 0), .init(9, 0), .init(9, 1), .init(8, 1)])
        let localZone = Engine.zoneProposals(walls: clutter, keepPoint: .init(2, 2))
        precondition(abs(success(Engine.reconstruct(walls: localZone[0], triangles: mesh())).area - 16) < 1e-8,
                     "Detached neighboring room must not prevent kitchen reconstruction")
        let reversedKitchen = kitchen.reversed().map { Engine.Wall(start: $0.end, end: $0.start) }
        precondition(abs(success(Engine.reconstruct(walls: Engine.zoneProposals(walls: reversedKitchen, keepPoint: .init(2, 2))[0], triangles: mesh())).area - 16) < 1e-8)
        let report = Engine.contourDiagnostic(walls: boundary)!
        let json = try! JSONSerialization.jsonObject(with: Data(report.utf8)) as! [String: Any]
        precondition((json["rawWalls"] as! [[String: Any]]).count == 4)
        precondition((json["closedContour"] as! [[Double]]).count == 4)
        let openReport = Engine.contourDiagnostic(walls: Array(boundary.dropLast()))!
        let openJSON = try! JSONSerialization.jsonObject(with: Data(openReport.utf8)) as! [String: Any]
        precondition(openJSON["closedContour"] is NSNull)
        let flat = success(Engine.reconstruct(walls: boundary, triangles: mesh()))
        let virtual = Engine.Boundary(start: .init(0, 0.75), end: .init(0.99, 0.75), keepPoint: .init(0.4, 0.2))
        let clipped = Engine.boundedWalls(boundary, boundaries: [virtual])!
        precondition(abs(success(Engine.reconstruct(walls: clipped, triangles: mesh(hole: false))).area - 0.7425) < 1e-8)
        let reversedCut = Engine.Boundary(start: virtual.end, end: virtual.start, keepPoint: virtual.keepPoint)
        precondition(abs(success(Engine.reconstruct(walls: Engine.boundedWalls(boundary, boundaries: [reversedCut])!, triangles: mesh(hole: false))).area - 0.7425) < 1e-8)
        let secondCut = Engine.Boundary(start: .init(0, 0.25), end: .init(0.99, 0.25), keepPoint: .init(0.4, 0.5))
        precondition(abs(success(Engine.reconstruct(walls: Engine.boundedWalls(boundary, boundaries: [virtual, secondCut])!, triangles: mesh(hole: false))).area - 0.495) < 1e-8)
        let openEnd = [boundary[0], boundary[1], boundary[3]]
        let suggestions = Engine.closureProposals(walls: openEnd, keepPoint: .init(0.4, 0.5))
        precondition(!suggestions.isEmpty, "An open passage should offer a closure for approval")
        precondition(abs(success(Engine.reconstruct(walls: suggestions[0], triangles: mesh())).area - 1.485) < 1e-8)
        precondition(Engine.closureProposals(walls: openEnd, keepPoint: .init(20, 20)).isEmpty,
                     "A proposal must contain the user's position")
        let broadOpening = openEnd.map { Engine.Wall(start: .init($0.start.x * 5, $0.start.y), end: .init($0.end.x * 5, $0.end.y)) }
        precondition(Engine.closureProposals(walls: broadOpening, keepPoint: .init(2, 0.5)).isEmpty,
                     "Do not suggest an arbitrary closure across a large missing wall")
        precondition(abs(success(Engine.reconstruct(walls: Engine.boundedWalls(openEnd, boundaries: [virtual])!, triangles: mesh(hole: false))).area - 0.7425) < 1e-8)
        let fragmented = [Engine.Wall(start: .init(0, 0), end: .init(0.5, 0)),
                          Engine.Wall(start: .init(0.48, 0), end: .init(0.99, 0))] + Array(boundary.dropFirst()) + [boundary[1]]
        precondition(abs(success(Engine.reconstruct(walls: fragmented, triangles: mesh())).area - 1.485) < 1e-8,
                     "Overlaps, fragmented walls and duplicates should merge")
        let shortened = boundary.map { wall -> Engine.Wall in
            let direction = simd_normalize(wall.end - wall.start)
            return .init(start: wall.start + direction * 0.12, end: wall.end - direction * 0.12)
        }
        precondition(abs(success(Engine.reconstruct(walls: shortened, triangles: mesh())).area - 1.485) < 1e-8,
                     "Small corner gaps should close at supporting-line intersections")
        let opening = [Engine.Wall(start: .init(0, 0), end: .init(0.2, 0)),
                       Engine.Wall(start: .init(0.8, 0), end: .init(0.99, 0))] + Array(boundary.dropFirst())
        if case .success = Engine.reconstruct(walls: opening, triangles: mesh()) {
            fatalError("A real 60 cm opening must not be bridged")
        }
        let branch = boundary + [Engine.Wall(start: .init(0, 0), end: .init(0.4, 0.4))]
        let branchProposal = Engine.closureProposals(walls: branch, keepPoint: .init(0.5, 0.5))
        precondition(!branchProposal.isEmpty)
        precondition(abs(success(Engine.reconstruct(walls: branchProposal[0], triangles: mesh())).area - 1.485) < 1e-8)
        if case .success = Engine.reconstruct(walls: branch, triangles: mesh()) {
            fatalError("An ambiguous branch must not silently choose a contour")
        }
        precondition(abs(flat.area - 1.485) < 1e-8, "Central hole must not reduce reconstructed area")
        precondition(flat.vertices.count == 6 && flat.slopeDegrees < 1e-6)
        let slope = success(Engine.reconstruct(walls: boundary, triangles: mesh(slope: 0.5)))
        precondition(abs(slope.area - 1.485 * sqrt(1.25)) < 1e-8)
        precondition(abs(slope.slopeDegrees - atan(0.5) * 180 / .pi) < 1e-6)
        let reversed = boundary.reversed().map { Engine.Wall(start: $0.end, end: $0.start) }
        precondition(abs(success(Engine.reconstruct(walls: reversed, triangles: mesh())).area - flat.area) < 1e-8)
        let offset = SIMD3<Double>(8, -4, 7)
        let shiftedWalls = boundary.map { Engine.Wall(start: $0.start + SIMD2(offset.x, offset.z), end: $0.end + SIMD2(offset.x, offset.z)) }
        let shiftedMesh = mesh().map { Engine.Triangle(a: $0.a + offset, b: $0.b + offset, c: $0.c + offset) }
        precondition(abs(success(Engine.reconstruct(walls: shiftedWalls, triangles: shiftedMesh)).area - flat.area) < 1e-8)
        if case .success = Engine.reconstruct(walls: Array(boundary.dropLast()), triangles: mesh()) {
            fatalError("Open contour must not be filled")
        }
        if case .success = Engine.reconstruct(walls: boundary, triangles: []) {
            fatalError("Walls alone must not invent a ceiling")
        }
        if case .success = Engine.reconstruct(walls: boundary, triangles: mesh(hole: false, twoLevels: true)) {
            fatalError("Two ceiling levels must not be extrapolated as one plane")
        }
        let concave: [SIMD2<Double>] = [.init(0, 0), .init(0.99, 0), .init(0.99, 0.75), .init(0.495, 0.75), .init(0.495, 1.5), .init(0, 1.5)]
        precondition(Engine.zoneProposals(walls: walls(concave.map { $0 * 4 }), keepPoint: .init(1, 1)).isEmpty,
                     "An L shape without two opposite returns must not be split as a corridor")
        let lShape = success(Engine.reconstruct(walls: walls(concave), triangles: mesh(hole: false)))
        let branchedL = walls(concave) + [.init(start: .init(0, 0), end: .init(-0.5, -0.5))]
            + walls([.init(5, 5), .init(6, 5), .init(6, 6), .init(5, 6)])
        let localL = Engine.closureProposals(walls: branchedL, keepPoint: .init(0.2, 0.2))
        precondition(!localL.isEmpty)
        precondition(abs(success(Engine.reconstruct(walls: localL[0], triangles: mesh(hole: false))).area - 1.11375) < 1e-8,
                     "Local extraction preserves concavity and excludes a detached neighboring room")
        precondition(abs(lShape.area - 1.11375) < 1e-8, "Concave contour must not use convex hull")
        let triangleArea = stride(from: 0, to: lShape.vertices.count, by: 3).reduce(0.0) { sum, i in
            sum + Engine.Triangle(a: lShape.vertices[i], b: lShape.vertices[i + 1], c: lShape.vertices[i + 2]).area
        }
        precondition(abs(triangleArea - lShape.area) < 1e-8, "3D preview must match reported area")
        print("PASS: fragmented/duplicate walls, corner gaps, real opening, ambiguous branch, hole, inclined plane, reversed walls, translated world, open contour, absent mesh, multiple levels, concave contour and rendered area")
    }
}
