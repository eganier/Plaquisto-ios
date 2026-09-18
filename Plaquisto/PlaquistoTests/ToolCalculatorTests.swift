import XCTest
@testable import Plaquisto

final class ToolCalculatorTests: XCTestCase {
    func testWallAngleSharedResultsAndReflexExamples() throws {
        for (distance,interior,exterior) in [(100.0,60.0,300.0),(141.421356,90.0,270.0),(173.205081,120.0,240.0),(193.185165,150.0,210.0)] {
            let result = try WallAngleCalculator.calculate(equalSide:100,oppositeSide:distance)
            XCTAssertEqual(result.interiorDegrees,interior,accuracy:0.00001)
            XCTAssertEqual(result.exteriorDegrees,exterior,accuracy:0.00001)
            XCTAssertEqual(result.degrees(for:.exterior),exterior,accuracy:0.00001)
        }
        for distance in stride(from:0.01,through:199.99,by:0.13) {
            let result = try WallAngleCalculator.calculate(equalSide:100,oppositeSide:distance)
            XCTAssertEqual(result.interiorDegrees+result.exteriorDegrees,360,accuracy:1e-12)
            XCTAssertTrue((0..<180).contains(result.interiorDegrees))
            XCTAssertTrue((180..<360).contains(result.exteriorDegrees))
        }
        XCTAssertEqual(WallAngleCalculator.formattedDegrees(270),"270,0°")
    }

    func testWallAngleSharedValidationAndNumericalLimits() throws {
        for length in [0.0,-100,.infinity,-.infinity,.nan] {
            XCTAssertThrowsError(try WallAngleCalculator.calculate(equalSide:length,oppositeSide:100))
        }
        for distance in [0.0,-100,200,201,.infinity,-.infinity,.nan,Double.leastNonzeroMagnitude] {
            XCTAssertThrowsError(try WallAngleCalculator.calculate(equalSide:100,oppositeSide:distance))
        }
        let huge = try WallAngleCalculator.calculate(equalSide:Double.greatestFiniteMagnitude,oppositeSide:Double.greatestFiniteMagnitude)
        XCTAssertEqual(huge.exteriorDegrees,300,accuracy:1e-10)
    }

    func testAngleCategoryAndDistinctDestinations() {
        let angles = ToolCatalog.all.filter { $0.category == .angles }
        XCTAssertEqual(angles.map(\.title),["Angle intérieur","Angle extérieur"])
        XCTAssertEqual(angles.map(\.shortDescription),["0–180°","180–360°"])
        XCTAssertEqual(angles.map(\.destination),[.wallAngle,.exteriorWallAngle])
        XCTAssertEqual(ToolCatalog.search("exterieur").map(\.destination),[.exteriorWallAngle])
        XCTAssertEqual(ToolCatalog.search("mesure d’angle").count,2)
        XCTAssertEqual(WallAngleKind.interior.equalSideTitle,"L · Distance sur chaque mur")
        XCTAssertEqual(WallAngleKind.exterior.equalSideTitle,"L · Distance sur les prolongements")
        XCTAssertTrue(WallAngleKind.exterior.measurementHelp.contains("dans le vide"))
    }
    func testWallAngleReferenceValues() throws {
        for (distance,expected) in [(100.0,60.0),(141.421356,90.0),(173.205081,120.0),(193.185165,150.0)] {
            XCTAssertEqual(try WallAngleCalculator.angle(equalSide:100,oppositeSide:distance),expected,accuracy:0.00001)
        }
        XCTAssertEqual(try WallAngleCalculator.angle(equalSide:200,oppositeSide:200),60,accuracy:0.000001)
    }
    func testWallAngleRejectsInvalidAndNonFiniteValues() {
        for length in [0.0,-1,.infinity,.nan] {
            XCTAssertThrowsError(try WallAngleCalculator.angle(equalSide:length,oppositeSide:100))
        }
        for distance in [0.0,-1,200,201,.infinity,.nan] {
            XCTAssertThrowsError(try WallAngleCalculator.angle(equalSide:100,oppositeSide:distance))
        }
    }
    func testWallAngleExtremeFiniteInputsAndFrenchFormatting() throws {
        XCTAssertEqual(try WallAngleCalculator.angle(equalSide:Double.greatestFiniteMagnitude,oppositeSide:Double.greatestFiniteMagnitude),60,accuracy:0.000001)
        XCTAssertGreaterThan(try WallAngleCalculator.angle(equalSide:100,oppositeSide:0.00001),0)
        XCTAssertLessThan(try WallAngleCalculator.angle(equalSide:100,oppositeSide:199.999999),180)
        XCTAssertEqual(WallAngleCalculator.formattedDegrees(2.31,signed:true),"+2,3°")
        XCTAssertEqual(WallAngleCalculator.formattedDegrees(-2.41,signed:true),"-2,4°")
        XCTAssertEqual(WallAngleCalculator.formattedDegrees(-0.001,signed:true),"0,0°")
        XCTAssertEqual(ToolCatalog.search("angle entre").map(\.destination),[.wallAngle])
    }
    func testThermalFormulasAndInvalidValues() {
        XCTAssertEqual(ThermalCalculator.resistance(thicknessMM: 120, lambda: 0.032) ?? 0, 3.75, accuracy: 0.0001)
        XCTAssertEqual(ThermalCalculator.thickness(resistance: 4, lambda: 0.036) ?? 0, 144, accuracy: 0.0001)
        XCTAssertEqual(ThermalCalculator.lambda(thicknessMM: 120, resistance: 3.75) ?? 0, 0.032, accuracy: 0.0001)
        XCTAssertNil(ThermalCalculator.resistance(thicknessMM: 0, lambda: 0.032))
    }

    func testVATBothDirections() {
        XCTAssertEqual(VATCalculator.calculate(amount: 100, rate: 20, direction: .netToGross), VATResult(net: 100, tax: 20, gross: 120))
        XCTAssertEqual(VATCalculator.calculate(amount: 120, rate: 20, direction: .grossToNet), VATResult(net: 100, tax: 20, gross: 120))
    }

    func testArchEndpointsCenterAndSemicircle() {
        let points = ArchCalculator.points(kind: .rounded, width: 120, rise: 40, spacing: 17)
        XCTAssertEqual(points.first?.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(points.first?.y ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(points.last?.x ?? -1, 120, accuracy: 0.0001)
        XCTAssertEqual(points.last?.y ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(points.first(where: { abs($0.x - 60) < 0.001 })?.y ?? -1, 40, accuracy: 0.0001)
        let semicircle = ArchCalculator.points(kind: .semicircle, width: 100, rise: 12, spacing: 10)
        XCTAssertEqual(semicircle.first(where: { $0.x == 50 })?.y ?? 0, 50, accuracy: 0.0001)
    }

    func testCatalogSearchAndSpacingBoundaries() {
        XCTAssertEqual(ToolCatalog.search("resistance").map(\.id), ["thermal"])
        XCTAssertTrue(ToolCatalog.search("fourrure").contains { $0.id == "furring-spacing" })
        let low = InsulationSpacingBand(minimumMass: 0, maximumMass: 6, spacing: 0.60, maximumExclusive: true)
        let medium = InsulationSpacingBand(minimumMass: 6, maximumMass: 10, spacing: 0.50, maximumExclusive: true)
        XCTAssertTrue(low.contains(5.99)); XCTAssertFalse(low.contains(6)); XCTAssertTrue(medium.contains(6))
    }
}
