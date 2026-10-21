import XCTest
import SwiftUI
@testable import Plaquisto

final class ToolCalculatorTests: XCTestCase {
    @MainActor func testToolbarTextDoesNotCompressToIconWidth() throws {
        for title in ["Fermer", "Annuler", "Utiliser", "Enregistrer"] {
            let renderer = ImageRenderer(content: Button(title) {}.atlantiqueToolbarAction().atlantiqueDesign())
            renderer.proposedSize = ProposedViewSize(width: 44, height: 44)
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.width, 60, title)
            XCTAssertGreaterThanOrEqual(image.size.height, 44, title)
        }
    }

    @MainActor func testSegmentedChoicesRenderAtPhoneWidthsWithoutChangingSelection() throws {
        for width: CGFloat in [320, 390] {
            for size in [DynamicTypeSize.large, .accessibility1] {
                var selected = true
                let view = AtlantiqueSegmentedChoice(title: "Saisie", options: [(false, "Unité"), (true, "Conditionnement")],
                    selection: Binding(get: { selected }, set: { selected = $0 }))
                    .frame(width: width).atlantiqueDesign().environment(\.dynamicTypeSize, size)
                let image = try XCTUnwrap(ImageRenderer(content: view).uiImage)
                XCTAssertEqual(image.size.width, width)
                XCTAssertGreaterThanOrEqual(image.size.height, 48)
                XCTAssertTrue(selected)
            }
        }
    }

    func testAdjustableArchUsesSymmetricCentreBasedMeasurements() throws {
        let points = ArchCalculator.adjustable(width:120,rise:60,amplitude:0.5,spacing:20)
        XCTAssertEqual(points.map(\.x),[0,20,40,60,80,100,120])
        XCTAssertEqual(points.first?.y,0)
        XCTAssertEqual(points.last?.y,0)
        XCTAssertEqual(points[3].y,60,accuracy:0.0001)
        XCTAssertEqual(points[4].y,sqrt(3200),accuracy:0.0001)
        for i in points.indices { XCTAssertEqual(points[i].y,points[points.count-1-i].y,accuracy:0.0001) }
        let narrow = ArchCalculator.adjustable(width:120,rise:60,amplitude:0,spacing:20)
        let wide = ArchCalculator.adjustable(width:120,rise:60,amplitude:1,spacing:20)
        XCTAssertLessThan(narrow[4].y,points[4].y)
        XCTAssertGreaterThan(wide[4].y,points[4].y)
        let uneven = ArchCalculator.adjustable(width:125,rise:40,amplitude:0.5,spacing:20)
        XCTAssertEqual(uneven.filter { $0.x >= 62.5 }.map { $0.x-62.5 },[0,20,40,60,62.5])
    }

    func testAdjustableArchRejectsInvalidAndBoundsSampling() {
        XCTAssertTrue(ArchCalculator.adjustable(width:0,rise:50,amplitude:0.5,spacing:10).isEmpty)
        XCTAssertTrue(ArchCalculator.adjustable(width:120,rise:.nan,amplitude:0.5,spacing:10).isEmpty)
        XCTAssertTrue(ArchCalculator.adjustable(width:120,rise:50,amplitude:2,spacing:10).isEmpty)
        XCTAssertTrue(ArchCalculator.adjustable(width:120,rise:50,amplitude:0.5,spacing:0).isEmpty)
        XCTAssertLessThanOrEqual(ArchCalculator.adjustable(width:120,rise:50,amplitude:0.5,spacing:0.000001).count,2003)
    }

    func testAtlantiqueIsOptInAndPreservesStandardPresentation() {
        let environment = EnvironmentValues()
        XCTAssertFalse(environment.usesAtlantiqueDesign)
        XCTAssertEqual(environment.interfacePresentation, .standard)
    }

    @MainActor func testAtlantiqueFontsExistOnIOS() {
        for weight in Atlantique.Typography.Weight.allCases {
            XCTAssertNotNil(UIFont(name: weight.rawValue, size: 17), weight.rawValue)
            XCTAssertEqual(Atlantique.Typography.uiFont(weight: weight).fontName, weight.rawValue)
        }
    }

    @MainActor func testAtlantiquePaletteMatchesApprovedBooks() {
        func rgb(_ color: Color) -> [Int] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a))
            return [r, g, b].map { Int(($0 * 255).rounded()) }
        }
        XCTAssertEqual(rgb(Atlantique.Palette.blue), [40, 89, 130])
        XCTAssertEqual(rgb(Atlantique.Palette.orange), [255, 138, 31])
        XCTAssertEqual(rgb(Atlantique.Palette.ink), [23, 50, 74])
        XCTAssertGreaterThanOrEqual(Atlantique.Metrics.touchTarget, 44)
    }

    func testR50KeypadOrderingAndUniqueKeys() {
        XCTAssertEqual(PlaquistoNumericInput.keypadRows,
                       [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"], ["0", ",", "delete"]])
        XCTAssertEqual(Set(PlaquistoNumericInput.keypadRows.flatMap { $0 }).count, 12)
        XCTAssertNil(PlaquistoNumericInput.replacing("12", range: NSRange(location: 2, length: 0), with: ",", integer: true, signed: false))
        XCTAssertEqual(PlaquistoNumericInput.replacing("12", range: NSRange(location: 2, length: 0), with: ".5", integer: false, signed: false), "12,5")
    }

    @MainActor func testAtlantiqueNumericFieldKeepsBindingUntilUserEdits() async throws {
        var value = "12,3456"
        let host = UIHostingController(rootView: AtlantiqueNumberRow(title: "Hauteur", unit: "cm",
            text: Binding(get: { value }, set: { value = $0 })).atlantiqueDesign())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        func findField(_ view: UIView) -> UITextField? {
            if let field = view as? UITextField { return field }
            return view.subviews.compactMap { findField($0) }.first
        }
        let field = try XCTUnwrap(findField(host.view))
        XCTAssertEqual(field.font?.fontName, "AvenirNext-Regular")
        XCTAssertEqual(field.text, "12,3456")
        XCTAssertEqual(value, "12,3456")
        XCTAssertNotNil(field.inputView)
        field.text = "45,5"
        field.sendActions(for: .editingChanged)
        XCTAssertEqual(value, "45,5")
    }

    @MainActor func testAtlantiqueComponentsRenderWithAccessibilityTextSize() throws {
        let content = VStack {
            AtlantiqueCard {
                Text("Plénum supplémentaire").font(Atlantique.Typography.heading)
                AtlantiqueChoice(title: "Entraxe", options: [(40, "40 cm"), (60, "60 cm")], selection: .constant(60))
            }
            Button("Enregistrer") {}.buttonStyle(AtlantiqueButtonStyle()).disabled(true)
            HStack { ForEach(AtlantiqueIcon.allCases.prefix(6), id: \.self) { AtlantiqueSymbol(icon: $0) } }
        }.padding().frame(width: 390).atlantiqueDesign()
            .environment(\.dynamicTypeSize, .accessibility1)
        let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
        XCTAssertEqual(image.size.width, 390)
        XCTAssertGreaterThan(image.size.height, 200)
    }

    func testFormMenuPreservesZeroBasedStepNumbersAndExcludesResult() {
        let choices = FormStepNavigation.choices(titles: ["Dimensions", "Isolation", "Parements", "Résultat"])
        XCTAssertEqual(choices.map(\.step), [0, 1, 2])
        XCTAssertEqual(choices.map(\.title), ["Dimensions", "Isolation", "Parements"])
    }

    func testFormMenuPreservesOneBasedStepNumbers() {
        let choices = FormStepNavigation.choices(titles: ["Dimensions", "Parements", "Bandes", "Résultat"], firstStep: 1)
        XCTAssertEqual(choices.map(\.step), [1, 2, 3])
        XCTAssertEqual(choices.last?.title, "Bandes")
    }

    func testFormMenuHidesSuspensionStepsForSelfSupportingCeiling() {
        let titles = ["Dimensions", "Isolation", "Parements", "Ossature", "Support", "Plénum", "Suspension", "Bandes", "Résultat"]
        let choices = FormStepNavigation.choices(titles: titles, visibleSteps: [0, 1, 2, 3, 7, 8])
        XCTAssertEqual(choices.map(\.step), [0, 1, 2, 3, 7])
        XCTAssertFalse(choices.contains { ["Support", "Plénum", "Suspension", "Résultat"].contains($0.title) })
    }

    func testFormMenuDoesNotInventEntriesForEmptyOrResultOnlyForms() {
        XCTAssertTrue(FormStepNavigation.choices(titles: []).isEmpty)
        XCTAssertTrue(FormStepNavigation.choices(titles: ["Résultat"]).isEmpty)
        XCTAssertTrue(FormStepNavigation.choices(titles: ["Dimensions", "Résultat"], visibleSteps: []).isEmpty)
    }

    func testFormMenuReflectsConditionalPaintingSteps() {
        let withoutPrimer = FormStepNavigation.choices(titles: ["Traitements", "Finition", "Quantitatif"])
        let withPrimer = FormStepNavigation.choices(titles: ["Traitements", "Impression", "Finition", "Quantitatif"])
        XCTAssertEqual(withoutPrimer.map(\.title), ["Traitements", "Finition"])
        XCTAssertEqual(withPrimer.map(\.title), ["Traitements", "Impression", "Finition"])
        XCTAssertEqual(withPrimer.last?.step, 2)
    }

    func testFormMenuOffersResultOnlyWhenConfigurationIsComplete() {
        let titles = ["Dimensions", "Parements", "Résultat"]
        XCTAssertEqual(FormStepNavigation.choices(titles: titles, includeResult: false).map(\.step), [0, 1])
        XCTAssertEqual(FormStepNavigation.choices(titles: titles, includeResult: true).map(\.step), [0, 1, 2])
        XCTAssertEqual(FormStepNavigation.choices(titles: titles, firstStep: 1, includeResult: true).last?.step, 3)
    }

    func testRoofWindowProfilesAreCountedOnlyInLinearMeters() {
        let opening=OpeningInput(kind:.roofWindow,width:0.78,height:1.30)
        let result=OpeningQuantityCalculator.calculate(opening,context:.init(system:.furringCeiling,hsp:0,spacing:0.4))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.quantities.first { $0.name == "Cornière" }?.quantity ?? 0,3.8,accuracy:1e-8)
        XCTAssertEqual(result.quantities.first { $0.name == "Fourrures F45/F47" }?.quantity ?? 0,2.16,accuracy:1e-8)
        XCTAssertTrue(result.quantities.allSatisfy { $0.unit == .linearMeter })
        let studs=OpeningQuantityCalculator.calculate(opening,context:.init(system:.railStudCeiling,hsp:0,spacing:0.6,ceilingLengthInStudDirection:4.2))
        XCTAssertTrue(studs.quantities.allSatisfy { $0.unit == .linearMeter })
    }
    func testSupplyUnitAliasesConsolidateWithoutInventingBarLengths() {
        let rows=SupplyListingConsolidator.rows([
            .init(name:"Cornière",quantity:3,unit:" ml "),.init(name:"Cornières",quantity:5,unit:"m.l."),
            .init(name:"Appuis 100",quantity:2,unit:"unité(s)"),.init(name:"Appuis 100",quantity:3,unit:"unités"),
            .init(name:"Cornière inconnue",quantity:2,unit:"unité"),.init(name:"Cornière inconnue",quantity:6,unit:"ml")])
        XCTAssertEqual(rows.first { $0.name == "Cornière" }?.measurements.count,1)
        XCTAssertEqual(rows.first { $0.name == "Cornière" }?.measurements.first?.quantity,8)
        XCTAssertEqual(rows.first { $0.name == "Appuis 100" }?.measurements.first?.quantity,5)
        XCTAssertEqual(rows.first { $0.name == "Cornière inconnue" }?.measurements.count,2)
    }
    func testHatchAvailableForWallsAndCeilingsAndSurvivesEncoding() throws {
        XCTAssertTrue(LayoutOpeningKind.available(for:.wall).contains(.hatch))
        XCTAssertTrue(LayoutOpeningKind.available(for:.ceiling).contains(.hatch))
        let hatch=LayoutOpening(kind:.hatch,contour:[.init(x:0,y:0),.init(x:600,y:0),.init(x:600,y:600),.init(x:0,y:600)])
        XCTAssertEqual(try JSONDecoder().decode(LayoutOpening.self,from:JSONEncoder().encode(hatch)),hatch)
    }
    @MainActor func testDecimalFieldPreservesPrecisionUntilUserActuallyEdits() async throws {
        var value=2.537842
        let host=UIHostingController(rootView:ZeroEmptyDecimalTextField(value:Binding(get:{ value },set:{ value=$0 })))
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController=host; window.makeKeyAndVisible()
        defer { window.isHidden=true; window.rootViewController=nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for:.milliseconds(250))
        func field(in view:UIView) -> UITextField? {
            (view as? UITextField) ?? view.subviews.lazy.compactMap { field(in:$0) }.first
        }
        let input=try XCTUnwrap(field(in:host.view))
        XCTAssertEqual(input.text,"2,54")
        XCTAssertEqual(value,2.537842)
        input.delegate?.textFieldDidBeginEditing?(input)
        input.delegate?.textFieldDidEndEditing?(input)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(value,2.537842,"Opening/closing the keyboard without editing must not round the model")
        input.text="3,123456"; input.sendActions(for:.editingChanged)
        input.delegate?.textFieldDidEndEditing?(input)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(value,3.123456,"Formatting after an edit must not round its value either")
        input.text=""; input.sendActions(for:.editingChanged)
        XCTAssertEqual(value,0)
        input.text="12.5"; input.sendActions(for:.editingChanged)
        XCTAssertEqual(value,12.5)
        input.text="NaN"; input.sendActions(for:.editingChanged)
        XCTAssertEqual(value,12.5)
    }

    func testNumericKeyboardEditingGrammar() {
        func edit(_ text: String, _ range: NSRange, _ replacement: String, integer: Bool = false, signed: Bool = false) -> String? {
            PlaquistoNumericInput.replacing(text, range: range, with: replacement, integer: integer, signed: signed)
        }
        XCTAssertEqual(edit("300", NSRange(location: 0, length: 3), "200"), "200")
        XCTAssertEqual(edit("", NSRange(location: 0, length: 0), " 12.50 "), "12,50")
        XCTAssertNil(edit("12,5", NSRange(location: 4, length: 0), ","))
        XCTAssertNil(edit("", NSRange(location: 0, length: 0), "1,5", integer: true))
        XCTAssertNil(edit("", NSRange(location: 0, length: 0), "-2"))
        XCTAssertEqual(edit("", NSRange(location: 0, length: 0), "-2,5", signed: true), "-2,5")
        XCTAssertEqual(edit("1", NSRange(location: 0, length: 1), ""), "")
        XCTAssertNil(edit("", NSRange(location: 0, length: 0), "NaN"))
        XCTAssertNil(edit("", NSRange(location: 0, length: 0), String(repeating: "9", count: 400)))
        XCTAssertNil(edit("1", NSRange(location: 5, length: 1), "2"))
        XCTAssertNil(edit("", NSRange(location: 0, length: 0), "999999999999999999999", integer: true))
    }

    func testNumericKeyboardDismissGestureThresholds() {
        XCTAssertEqual(PlaquistoNumericInput.visibleKeyboardHeight(fullHeight: 320, translation: 100), 220)
        XCTAssertEqual(PlaquistoNumericInput.visibleKeyboardHeight(fullHeight: 320, translation: -10), 320)
        XCTAssertEqual(PlaquistoNumericInput.visibleKeyboardHeight(fullHeight: 320, translation: 500), 1)
        XCTAssertEqual(PlaquistoNumericInput.visibleKeyboardHeight(fullHeight: 245, translation: 0), 245)
        XCTAssertFalse(PlaquistoNumericInput.shouldDismiss(translation: -100, predicted: -200))
        XCTAssertFalse(PlaquistoNumericInput.shouldDismiss(translation: 20, predicted: 30))
        XCTAssertTrue(PlaquistoNumericInput.shouldDismiss(translation: 65, predicted: 65))
        XCTAssertTrue(PlaquistoNumericInput.shouldDismiss(translation: 20, predicted: 160))
    }

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
