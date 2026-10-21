import XCTest
import SwiftUI
@testable import Plaquisto

@MainActor final class StockTests:XCTestCase {
    func testShoppingStockOnlyChangesPurchasesAndUsesAllAvailableAfterOverride() throws {
        let stock=StockStore(fileURL:location())
        try add(stock,rail,quantity:10)
        let encoder=JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let events=try encoder.encode(stock.events), entries=try encoder.encode(stock.entries)
        let lines=StockTakeoffLine.make([.init(name:rail.name,quantity:4,unit:rail.unit)],stock:stock,projectID:nil)
        var edits=ShoppingListEdits()
        edits.edits[rail.id] = .init(name:"Rails chantier",quantity:15,deductStock:true)
        let row=try XCTUnwrap(ShoppingSupplyRow.make(lines:lines,edits:edits,available:[rail.id:10]).first)
        XCTAssertEqual(row.quantity,5)
        XCTAssertEqual(row.originalQuantity,4)
        XCTAssertEqual(row.name,"Rails chantier")
        XCTAssertEqual(try encoder.encode(stock.events),events); XCTAssertEqual(try encoder.encode(stock.entries),entries)
        edits.edits[rail.id]?.deductStock=false
        XCTAssertEqual(ShoppingSupplyRow.make(lines:lines,edits:edits).first?.quantity,15)
        edits.reset(rail.id)
        XCTAssertEqual(ShoppingSupplyRow.make(lines:lines,edits:edits).first?.quantity,4)
    }
    func testShoppingMergeIsReversibleFromEitherSideAndRecalculatesSources() throws {
        let a=StockProduct(name:"Appuis 100",unit:"unités"),b=StockProduct(name:"Appuis 120",unit:"unités")
        func lines(_ value:Double) -> [StockTakeoffLine] { [
            .init(product:a,required:value,fromStock:0),.init(product:b,required:8,fromStock:3)] }
        var edits=ShoppingListEdits()
        edits.edits[a.id] = .init(name:"À remplacer")
        edits.edits[b.id] = .init(deductStock:true)
        edits.merge(a.id,into:b.id)
        let rows=ShoppingSupplyRow.make(lines:lines(5),edits:edits)
        XCTAssertEqual(rows.map(\.quantity),[0,10])
        XCTAssertEqual(rows[0].originalQuantity,5)
        XCTAssertTrue(rows[0].replaced)
        XCTAssertEqual(ShoppingSupplyRow.make(lines:lines(10),edits:edits)[1].quantity,15)
        for id in [a.id,b.id] {
            var reset=edits; reset.reset(id)
            XCTAssertEqual(reset,ShoppingListEdits())
            XCTAssertEqual(ShoppingSupplyRow.make(lines:lines(5),edits:reset).map(\.quantity),[5,8])
        }
        // Losing a destination must not hide the source's purchase requirement.
        XCTAssertEqual(ShoppingSupplyRow.make(lines:[lines(5)[0]],edits:edits)[0].quantity,5)
    }
    func testShoppingMergeChainFlattensAndDoesNotMixUnits() {
        var edits=ShoppingListEdits()
        edits.merge("a",into:"b"); edits.merge("b",into:"c")
        XCTAssertEqual(edits.replacements,["a":"c","b":"c"])
        edits.merge("c",into:"a")
        XCTAssertEqual(edits.replacements,["a":"c","b":"c"])
        edits.reset("b"); XCTAssertTrue(edits.replacements.isEmpty)
        let a=StockProduct(name:"Cornière",unit:"ml"),b=StockProduct(name:"Cornière 3m",unit:"unités")
        edits.merge(a.id,into:b.id)
        let rows=ShoppingSupplyRow.make(lines:[.init(product:a,required:6,fromStock:0),.init(product:b,required:2,fromStock:0)],edits:edits)
        XCTAssertEqual(rows.map(\.quantity),[6,2])
    }
    func testShoppingEditsPersistPerSelectionWithoutChangingWorks() throws {
        let url=location(),store=ProjectStore(fileURL:url)
        let project=try store.createProject(name:"Maison",client:"",address:"",notes:"")
        var edits=ShoppingListEdits()
        edits.products=[.init(name:"Produit manuel",quantity:2.5,unit:"ml")]
        edits.edits[rail.id] = .init(name:"Rails",quantity:12,deductStock:true)
        try store.saveShoppingList(projectID:project,scope:"selection",edits:edits)
        let loaded=try XCTUnwrap(ProjectStore(fileURL:url).project(id:project))
        XCTAssertEqual(loaded.shoppingLists?["selection"],edits)
        XCTAssertNil(loaded.shoppingLists?["autre"])
        XCTAssertTrue(loaded.works.isEmpty)
        var invalid=edits; invalid.products[0].quantity = .nan
        XCTAssertThrowsError(try store.saveShoppingList(projectID:project,scope:"selection",edits:invalid))
        XCTAssertEqual(store.project(id:project)?.shoppingLists?["selection"],edits)
    }
    private let rail = StockProduct(name:"Rails R48",unit:"ml",family:.frames)
    private func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("stock-tests-\(UUID())/stock.json") }
    private func add(_ stock:StockStore,_ product:StockProduct,quantity:Double) throws {
        try stock.move(.entry,product:product,quantity:quantity,packName:"boîte",packSize:1,usesPack:false)
    }
    func testLastUpdatePersistsAndFollowsRecordedOperations() throws {
        let url = location(), stock = StockStore(fileURL:url), project = UUID()
        XCTAssertNil(stock.lastUpdatedAt)
        let before = Date()
        try add(stock,rail,quantity:10)
        let enteredAt = try XCTUnwrap(stock.lastUpdatedAt)
        XCTAssertGreaterThanOrEqual(enteredAt,before)
        XCTAssertEqual(StockStore(fileURL:url).lastUpdatedAt,enteredAt)
        try stock.reserve(projectID:project,projectName:"Chantier",quantities:[rail.id:3])
        let reservedAt = try XCTUnwrap(stock.lastUpdatedAt)
        XCTAssertGreaterThanOrEqual(reservedAt,enteredAt)
        XCTAssertEqual(reservedAt,stock.events.first?.date)
        try stock.reserve(projectID:project,projectName:"Chantier",quantities:[rail.id:3])
        XCTAssertEqual(stock.lastUpdatedAt,reservedAt)
        XCTAssertThrowsError(try stock.move(.exit,product:rail,quantity:100,packName:"barre",packSize:1,usesPack:false))
        XCTAssertEqual(stock.lastUpdatedAt,reservedAt)
        try stock.cancel(XCTUnwrap(stock.reservations.first))
        let cancelledAt = try XCTUnwrap(stock.lastUpdatedAt)
        XCTAssertGreaterThanOrEqual(cancelledAt,reservedAt)
        try stock.undoLast()
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(stock.lastUpdatedAt),cancelledAt)
        XCTAssertEqual(stock.lastUpdatedAt,stock.events.first?.date)
        XCTAssertEqual(StockStore(fileURL:url).lastUpdatedAt,stock.lastUpdatedAt)
    }
    func testSelectedExportContainsOnlyProjectDetailsAndPositiveSelectedSupplies() {
        let now = Date()
        let project = ProjectItem(id: UUID(), name: "Maison", client: "Client", address: "12 rue du Test",
            notes: "Note privée", works: [], createdAt: now, updatedAt: now)
        let selected = CombinedSupply(name:"BA13",quantity:12.5,unit:"m²")
        let ignored = CombinedSupply(name:"Vis TTPC 25",quantity:100,unit:"unités")
        let zero = CombinedSupply(name:"Rails",quantity:0,unit:"ml")
        let invalid = CombinedSupply(name:"Invalide",quantity:.nan,unit:"ml")
        let text = QuantityTextExport.text(projects:[project,project], supplies:[selected,ignored,zero,invalid], selected:[selected.id,zero.id,invalid.id])
        XCTAssertEqual(text,"Projet : Maison\nClient : Client\nAdresse : 12 rue du Test\n\n• BA13 : 12,5 m²")
        XCTAssertFalse(text.contains("stock"))
        XCTAssertFalse(text.contains("€"))
        XCTAssertFalse(text.contains("Note privée"))
    }
    func testSingleSupplyReservationPreservesOthersAndExportCanDeductStock() throws {
        let stock = StockStore(fileURL:location()), project = UUID()
        let screws = StockProduct(name:"Vis TTPC 25",unit:"unités",family:.screws)
        try add(stock,rail,quantity:10)
        try add(stock,screws,quantity:100)
        try stock.reserve(projectID:project,projectName:"Maison",quantities:[screws.id:20])
        try stock.reserve(projectID:project,projectName:"Maison",quantities:[rail.id:4])
        XCTAssertEqual(stock.reserved(screws.id),20)
        XCTAssertEqual(stock.reserved(rail.id),4)
        XCTAssertEqual(stock.entry(rail.id)?.quantity,10)
        let lines = StockTakeoffLine.make([.init(name:rail.name,quantity:12,unit:rail.unit)],stock:stock,projectID:project)
        XCTAssertEqual(lines.first?.toBuy,2)
        let supplies = lines.map { CombinedSupply(name:$0.product.name,quantity:$0.toBuy,unit:$0.product.unit) }
        let text = QuantityTextExport.text(projects:[],supplies:supplies,selected:Set(supplies.map(\.id)))
        XCTAssertEqual(text,"• Rails R48 : 2 ml")
    }
    func testReservationDoesNotRemovePhysicalStockAndProtectsOtherProjects() throws {
        let stock = StockStore(fileURL:location()), a = UUID(), b = UUID()
        try add(stock,rail,quantity:10)
        try stock.reserve(projectID:a,projectName:"A",quantities:[rail.id:3])
        XCTAssertEqual(stock.entry(rail.id)?.quantity,10)
        XCTAssertEqual(stock.available(rail.id),7)
        XCTAssertEqual(stock.available(rail.id,for:a),10)
        XCTAssertEqual(stock.available(rail.id,for:b),7)
        XCTAssertThrowsError(try stock.reserve(projectID:b,projectName:"B",quantities:[rail.id:8]))
        XCTAssertThrowsError(try stock.move(.exit,product:rail,quantity:8,packName:"barre",packSize:1,usesPack:false))
        XCTAssertEqual(stock.entry(rail.id)?.quantity,10)
    }
    func testRepeatedReservationIsIdempotentAndCancelRestoresAvailability() throws {
        let stock = StockStore(fileURL:location()), project = UUID()
        try add(stock,rail,quantity:10)
        for _ in 0..<3 { try stock.reserve(projectID:project,projectName:"Chantier",quantities:[rail.id:3]) }
        XCTAssertEqual(stock.reservations.count,1)
        XCTAssertEqual(stock.reserved(rail.id),3)
        XCTAssertEqual(stock.events.count,2)
        try stock.cancel(XCTUnwrap(stock.reservations.first))
        XCTAssertEqual(stock.available(rail.id),10)
        XCTAssertEqual(stock.events.first?.title,"Réservation annulée")
    }
    func testProjectExitConsumesOnlyItsOwnReservation() throws {
        let stock = StockStore(fileURL:location()), a = UUID(), b = UUID()
        try add(stock,rail,quantity:10)
        try stock.reserve(projectID:a,projectName:"A",quantities:[rail.id:3])
        try stock.reserve(projectID:b,projectName:"B",quantities:[rail.id:4])
        try stock.move(.exit,product:rail,quantity:2,packName:"barre",packSize:1,usesPack:false,projectID:a,projectName:"A")
        XCTAssertEqual(stock.entry(rail.id)?.quantity,8)
        XCTAssertEqual(stock.reservations.first { $0.projectID == a }?.quantity,1)
        XCTAssertEqual(stock.reservations.first { $0.projectID == b }?.quantity,4)
        XCTAssertEqual(stock.available(rail.id),3)
    }
    func testInventoryShortfallPreservesReservationsAndNeverGivesNegativeAvailability() throws {
        let stock = StockStore(fileURL:location()), project = UUID()
        try add(stock,rail,quantity:10)
        try stock.reserve(projectID:project,projectName:"A",quantities:[rail.id:8])
        try stock.move(.inventory,product:rail,quantity:2,packName:"barre",packSize:1,usesPack:false)
        XCTAssertEqual(stock.entry(rail.id)?.quantity,2)
        XCTAssertEqual(stock.reserved(rail.id),8)
        XCTAssertEqual(stock.available(rail.id),0)
        XCTAssertEqual(stock.available(rail.id,for:project),2)
        try stock.cancel(XCTUnwrap(stock.reservations.first))
        XCTAssertEqual(stock.available(rail.id),2)
    }
    func testReservationBatchFailureIsAtomic() throws {
        let stock = StockStore(fileURL:location()), screws = StockProduct(name:"Vis TTPC 25",unit:"unité")
        try add(stock,rail,quantity:10); try add(stock,screws,quantity:5)
        XCTAssertThrowsError(try stock.reserve(projectID:UUID(),projectName:"A",quantities:[rail.id:2,screws.id:6]))
        XCTAssertTrue(stock.reservations.isEmpty)
        XCTAssertEqual(stock.events.count,2)
    }
    func testSavingReloadingKeepsPackReservationAndHistory() throws {
        let url = location(), stock = StockStore(fileURL:url)
        try stock.move(.entry,product:rail,quantity:7.5,packName:"barre",packSize:3,usesPack:true)
        try stock.reserve(projectID:UUID(),projectName:"A",quantities:[rail.id:1.5])
        let loaded = StockStore(fileURL:url)
        XCTAssertNil(loaded.loadError)
        XCTAssertEqual(loaded.entry(rail.id)?.quantity,7.5)
        XCTAssertEqual(loaded.entry(rail.id)?.packSize,3)
        XCTAssertEqual(loaded.reserved(rail.id),1.5)
        XCTAssertEqual(loaded.events.count,2)
    }
    func testUnreadableArchiveIsNotOverwritten() throws {
        let url = location()
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let data = Data("broken archive".utf8); try data.write(to:url)
        let stock = StockStore(fileURL:url)
        XCTAssertNotNil(stock.loadError)
        XCTAssertThrowsError(try add(stock,rail,quantity:1))
        XCTAssertEqual(try Data(contentsOf:url),data)
    }
    func testFailedSaveDoesNotPublishAnUnsavedMovement() throws {
        let directory = location().deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let stock = StockStore(fileURL:directory.appendingPathComponent("stock.json"))
        try FileManager.default.createDirectory(at:directory.appendingPathComponent("stock.json"),withIntermediateDirectories:true)
        XCTAssertThrowsError(try add(stock,rail,quantity:1))
        XCTAssertTrue(stock.entries.isEmpty)
    }
    func testUndoKeepsAuditAndRestoresPhysicalStockAndReservations() throws {
        let stock = StockStore(fileURL:location()), project = UUID()
        try add(stock,rail,quantity:10)
        try stock.reserve(projectID:project,projectName:"A",quantities:[rail.id:3])
        try stock.move(.exit,product:rail,quantity:2,packName:"barre",packSize:1,usesPack:false,projectID:project)
        try stock.undoLast()
        XCTAssertEqual(stock.entry(rail.id)?.quantity,10)
        XCTAssertEqual(stock.reserved(rail.id),3)
        XCTAssertEqual(stock.events.count,4)
        XCTAssertFalse(stock.canUndo)
    }
    func testInvalidNumbersAreRejected() throws {
        let stock = StockStore(fileURL:location())
        for q in [Double.nan,Double.infinity,-1,0] { XCTAssertThrowsError(try add(stock,rail,quantity:q)) }
        XCTAssertThrowsError(try stock.move(.entry,product:rail,quantity:1,packName:"barre",packSize:0,usesPack:true))
        XCTAssertTrue(stock.entries.isEmpty)
        XCTAssertEqual(StockQuantity.parse("2,5"),2.5)
        XCTAssertNil(StockQuantity.parse("nan"))
        XCTAssertNil(StockQuantity.parse("-1"))
    }
    func testTakeoffConsolidatesUnitsConvertsBoardsAndDoesNotMutateStock() throws {
        let stock = StockStore(fileURL:location()), board = StockProduct(name:"BA13 · 1200 × 2400 mm",unit:"m²")
        try add(stock,board,quantity:2.88)
        let supplies:[CombinedSupply] = [.init(name:board.name,quantity:2,unit:"plaques"),.init(name:board.name,quantity:1,unit:"m²")]
        let lines = StockTakeoffLine.make(supplies,stock:stock,projectID:nil)
        XCTAssertEqual(lines.count,1)
        XCTAssertEqual(lines[0].required,6.76,accuracy:0.00001)
        XCTAssertEqual(lines[0].toBuy,3.88,accuracy:0.00001)
        XCTAssertEqual(stock.entry(board.id)?.quantity,2.88)
        XCTAssertEqual(stock.events.count,1)
    }
    func testInsulationIdentityKeepsThicknessAndLambdaAndNormalizesKnownFormats() {
        let a = StockProduct(name:"Laine de verre · λ 0.032 · 120 mm",unit:"m²")
        let b = StockProduct(name:"Isolation · Laine de verre · 120 mm · λ 0,032",unit:"m²")
        XCTAssertEqual(a.id,b.id)
        XCTAssertNotEqual(a.id,StockProduct(name:"Laine de verre · λ 0.035 · 120 mm",unit:"m²").id)
    }
    func testCatalogueIncludesUnpricedNestedReferencesWithoutDuplicateNames() throws {
        let data = Data(#"{"parements":[{"id":"board","kind":"facing","title":"BA13","data":{"dimensions":[{"width_mm":1200,"length_mm":2400}]}}],"doublage":{"isolants":[{"id":"wool","kind":"insulation_series","title":"Laine de verre","data":{"lambdas":[{"lambda_w_mk":0.032,"thicknesses_mm":[120]}]}}]},"quantitatifs":[{"id":"rail","title":"Rails R48","kind":"quantity_item","data":{"unit":"ml"}}]}"#.utf8)
        let products = StockCatalogue.products(data:data)
        XCTAssertEqual(products.count,3)
        XCTAssertEqual(products.first { $0.referenceID == "board" }?.variant,"1200x2400")
        XCTAssertEqual(products.first { $0.referenceID == "wool" }?.family,.insulation)
        XCTAssertEqual(products.first { $0.referenceID == "rail" }?.family,.frames)
    }
    func testFrameTablesPopulateEveryRailWithoutCreatingPricedDuplicates() {
        let data = Data(#"{"systems":[{"frame":"R36 + M36"},{"frame":"R48 + M48/35"},{"frame":"R48 + M48/50"},{"frame":"R62 + M62"},{"frame":"R70 + M70"},{"frame":"R90 + M90"},{"frame":"R100 + M100"}],"studs":[{"width_mm":150,"suspension_allowed":false}],"quantitatifs":[{"id":"rail48","kind":"quantity_item","title":"Rails R48","data":{"unit":"ml"}}]}"#.utf8)
        let rows = StockCatalogue.products(data:data)
        XCTAssertEqual(Set(rows.filter { $0.subcategory == "Rails" }.map(\.name)),Set(["Rails R36","Rails R48","Rails R62","Rails R70","Rails R90","Rails R100","Rails R150"]))
        XCTAssertEqual(rows.filter { $0.name == "Rails R48" }.count,1)
        XCTAssertEqual(rows.first { $0.name == "Rails R48" }?.referenceID,"rail48")
        XCTAssertNil(rows.first { $0.name == "Rails R150" }?.referenceID)
        XCTAssertEqual(rows.filter { $0.name.hasPrefix("Montants M48/") }.count,2)
    }
    func testCategoryFilteringIncludesUnstockedProductsAndExcludesOtherProfiles() {
        let products = [StockProduct(name:"Fourrures F45/F47",unit:"ml"),StockProduct(name:"Rails R48",unit:"ml"),StockProduct(name:"Montants M70",unit:"ml")]
        let rows = StockCatalogue.filtered(products,family:.frames,subcategory:"Fourrures",search:"")
        XCTAssertEqual(rows.map(\.name),["Fourrures F45/F47"])
        XCTAssertEqual(StockCatalogue.filtered(products,family:.frames,subcategory:"Rails",search:"48").count,1)
        XCTAssertEqual(StockCatalogue.filtered(products,family:.frames,subcategory:"Rails",search:"70").count,0)
    }
    func testEntriesAndInventoryNeverAttributeToAProject() throws {
        let stock=StockStore(fileURL:location()), project=UUID()
        for kind in [StockMovement.entry,.inventory] {
            XCTAssertFalse(kind.allowsProjectAssignment)
            try stock.move(kind,product:rail,quantity:10,packName:"barre",packSize:1,usesPack:false,projectID:project,projectName:"Ne pas attribuer")
            XCTAssertNil(stock.events.first?.projectName)
            XCTAssertTrue(stock.reservations.isEmpty)
        }
        XCTAssertTrue(StockMovement.exit.allowsProjectAssignment)
    }
    func testLegacyPaperTapeStockMergesWithoutLosingReservationsOrRewritingOnRead() throws {
        let url=location(), project=UUID()
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        var paper=StockProduct(name:"Bande à joint",unit:"ml")
        paper.name="Bande à joint · papier" // Historical encoded name, before canonicalization.
        let plain=StockProduct(name:"Bande à joint",unit:"ml")
        let archive=StockArchive(entries:[.init(product:paper,quantity:20),.init(product:plain,quantity:30)],
            reservations:[.init(productID:"Bande à joint · papier|ml",projectID:project,projectName:"Maison",quantity:12)])
        let data=try JSONEncoder().encode(archive)
        try data.write(to:url)
        let store=StockStore(fileURL:url)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.entries.count,1)
        XCTAssertEqual(store.entry(plain.id)?.quantity,50)
        XCTAssertEqual(store.reserved(plain.id),12)
        XCTAssertEqual(try Data(contentsOf:url),data)
        try add(store,plain,quantity:5)
        let loaded=StockStore(fileURL:url)
        XCTAssertNil(loaded.loadError)
        XCTAssertEqual(loaded.entry(plain.id)?.quantity,55)
        XCTAssertEqual(loaded.reserved(plain.id),12)
    }
    func testValuationRequiresUniqueValidatedExactTariff() {
        let product = StockProduct(name:"Rails R48",unit:"ml",referenceID:"rail",variant:"standard")
        let price = SupplyPrice(id:"p",referenceId:"rail",variantKey:"standard",label:"Rails R48",unit:"ml",unitPriceHT:2,repUnitHT:0.1,priceDate:"2020-01-01",status:"validated",updatedAt:"")
        var prices = SupplyPriceCatalogue(version:"1.0",revision:"test",currency:"EUR",lowerMultiplier:0.95,upperMultiplier:1.05,prices:[price])
        XCTAssertEqual(StockValuation.unitPrice(product,prices:prices),2.1)
        prices.prices.append(price)
        XCTAssertNil(StockValuation.unitPrice(product,prices:prices))
        XCTAssertNil(StockValuation.unitPrice(product,prices:nil))
        prices.prices = [price]; prices.prices[0].status = "draft"
        XCTAssertNil(StockValuation.unitPrice(product,prices:prices))
    }
    func testThumbButtonsRemainAtLeast56PointsHigh() throws {
        for width in [290.0,366] {
            let image = try XCTUnwrap(ImageRenderer(content:StockActionLabel(title:"Confirmer la réservation",symbol:"bookmark.fill").frame(width:width)).uiImage)
            XCTAssertEqual(image.size.width,width,accuracy:1)
            XCTAssertGreaterThanOrEqual(image.size.height,56)
        }
    }
    func testExportChoiceDoesNotLeakStockWhenOmitted() {
        let line = StockTakeoffLine(product:rail,required:90,fromStock:30)
        XCTAssertEqual(line.exportLine(deduct:true,includeStock:false),"Rails R48 : 60 ml")
        XCTAssertEqual(line.exportLine(deduct:false,includeStock:false),"Rails R48 : 90 ml")
        XCTAssertTrue(line.exportLine(deduct:true,includeStock:true).contains("+30 ml disponibles en stock"))
        XCTAssertEqual(line.required,90)
    }
    func testEditableQuantityDoesNotRoundStockUpAndReservationsStayExact() throws {
        let stock = StockStore(fileURL:location())
        try add(stock,rail,quantity:0.335)
        let value = try XCTUnwrap(StockQuantity.parse(StockQuantity.input(stock.available(rail.id))))
        try stock.reserve(projectID:UUID(),projectName:"A",quantities:[rail.id:value])
        XCTAssertEqual(stock.reserved(rail.id),0.335,accuracy:0.00000001)
    }
    func testQuarterHalfAndThreeQuarterBoxesConvertToIndividualUnits() throws {
        let stock = StockStore(fileURL:location()), screws = StockProduct(name:"Vis TTPC 25",unit:"unité")
        for fraction in [0.25,0.5,0.75] {
            try stock.move(.entry,product:screws,quantity:fraction*1000,packName:"boîte",packSize:1000,usesPack:true)
        }
        XCTAssertEqual(stock.entry(screws.id)?.quantity,1500)
        XCTAssertEqual(stock.entry(screws.id)?.packSize,1000)
    }
}
