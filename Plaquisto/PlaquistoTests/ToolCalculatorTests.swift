import XCTest
@testable import Plaquisto

final class ToolCalculatorTests: XCTestCase {
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
