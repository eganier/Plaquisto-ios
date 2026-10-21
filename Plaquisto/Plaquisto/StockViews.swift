import SwiftUI

struct StockShareDocument: Identifiable {
    var id = UUID()
    var url:URL
}
struct StockShareSheet: UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context) -> UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}

struct StockReservationView: View {
    let lines:[StockTakeoffLine]
    let projectID:UUID
    let projectName:String
    var onReserved:()->Void = {}
    @ObservedObject private var stock = StockStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var quantities:[String:String] = [:]
    @State private var error:String?
    var body:some View {
        NavigationStack {
            List {
                Section {
                    Text(projectName).font(.headline)
                    Text("Le matériel reste dans le local. Il est attribué à ce chantier et n’est plus disponible pour les autres.")
                    Text("Pour les références ci-dessous, cette validation remplace les quantités déjà réservées à ce chantier. Les autres réservations sont conservées.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(lines.filter { stock.entry($0.id) != nil }) { line in
                    Section {
                        Text(line.product.name).font(.headline)
                        HStack {
                            TextField("À réserver",text:Binding(get:{ quantities[line.id] ?? "0" },set:{ quantities[line.id] = $0 })).keyboardType(.decimalPad).font(.title2.bold())
                            Text(line.product.unit)
                        }.frame(minHeight:48)
                        Text("Besoin : \(StockQuantity.text(line.required)) · Disponible pour ce chantier : \(StockQuantity.text(stock.available(line.id,for:projectID)))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Réserver").atlantiqueFormPage("Réserver")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } } }
                .safeAreaInset(edge:.bottom) {
                    Button {
                        do {
                            var values:[String:Double] = [:]
                            for (id,text) in quantities {
                                guard let value = StockQuantity.parse(text) else { throw StockFailure.invalid }
                                values[id] = value
                            }
                            try stock.reserve(projectID:projectID,projectName:projectName,quantities:values)
                            onReserved()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    } label: { StockActionLabel(title:"Confirmer la réservation",symbol:"bookmark.fill") }.padding().background(.regularMaterial)
                }
                .onAppear { quantities = Dictionary(uniqueKeysWithValues:lines.filter { stock.entry($0.id) != nil }.map { ($0.id,StockQuantity.input($0.fromStock)) }) }
        }
    }
}

struct StockActionLabel: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    @Environment(\.isEnabled) private var isEnabled
    var title:String
    var symbol:String
    var body: some View {
        Label(title,systemImage:symbol).font(.headline)
            .frame(maxWidth:.infinity,minHeight:56)
            .foregroundStyle(atlantique ? Atlantique.Palette.ink : .white).background((atlantique ? Atlantique.Palette.orange : Color.blue).opacity(isEnabled ? 1 : 0.35),in:RoundedRectangle(cornerRadius:atlantique ? 12 : 18))
    }
}

struct StockHomeView: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    @State private var export: StockShareDocument?
    @ObservedObject private var stock = StockStore.shared
    @StateObject private var references = CeilingReferenceStore()
    @StateObject private var prices = SupplyPriceStore()
    @EnvironmentObject private var projects: ProjectStore
    @State private var section = 0
    @State private var family: StockFamily?
    @State private var subcategory = ""
    @State private var search = ""
    @State private var movement: StockMovement?
    private struct QuickMovement: Identifiable {
        let product:StockProduct
        let kind:StockMovement
        var id:String { product.id + kind.rawValue }
    }
    @State private var quickMovement:QuickMovement?
    @State private var selected: StockProduct?
    @State private var cancel: StockReservation?
    @State private var error: String?
    @State private var limit = 30
    private var catalogue:[StockProduct] {
        var products = Dictionary(StockCatalogue.products(data:UserDefaults.standard.data(forKey:"plaquisto.catalogue.v3")).map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        if let catalogue = references.catalogue {
            for project in projects.projects {
                let supplies = CombinedQuantityCalculator.calculate(works:project.visibleWorks,catalogue:catalogue).supplies
                for row in SupplyListingConsolidator.rows(supplies.map { .init(name:$0.name,quantity:$0.quantity,unit:$0.unit) }) {
                    for measurement in row.measurements {
                        let key = SupplyCostEstimator.resolve(.init(name:row.name,quantity:1,unit:measurement.unit),catalogue:catalogue)?.key
                        let product = StockProduct(name:row.name,unit:measurement.unit,referenceID:key?.referenceId,variant:key?.variantKey)
                        if products[product.id] == nil { products[product.id] = product }
                    }
                }
            }
        }
        for entry in stock.entries { products[entry.id] = entry.product }
        return products.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var filtered:[StockEntry] {
        stock.entries.filter { (family == nil || $0.product.family == family) && (subcategory.isEmpty || $0.product.subcategory == subcategory) && (search.isEmpty || $0.product.name.localizedStandardContains(search)) }
            .sorted { $0.product.name.localizedStandardCompare($1.product.name) == .orderedAscending }
    }
    private var filteredProducts:[StockProduct] {
        StockCatalogue.filtered(catalogue,family:family,subcategory:subcategory,search:search)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if atlantique {
                        stockOverview
                        AtlantiqueSearchField(prompt: "Rechercher une fourniture", text: $search)
                    } else {
                    Picker("Affichage",selection:$section) {
                        Text("Stock").tag(0); Text("Réservations").tag(1)
                    }.pickerStyle(.segmented)
                    if let date = stock.lastUpdatedAt {
                        Text("Dernière mise à jour : \(date.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier:"fr_FR"))))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if stock.loadError == nil {
                        Text("Aucun mouvement enregistré")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }
                    if let error = stock.loadError { Text(error).foregroundStyle(.red) }
                    if section == 0 {
                        if !atlantique { valuation(filtered) }
                        if family == nil && search.isEmpty {
                            if atlantique { familyList } else {
                            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                                ForEach(StockFamily.allCases) { item in
                                    let entries = stock.entries.filter { $0.product.family == item }
                                    Button { family = item; subcategory = ""; limit = 30 } label: {
                                        VStack(alignment:.leading,spacing:10) {
                                            Image(systemName:item.symbol).font(.title2).foregroundStyle(.blue)
                                            Text(item.rawValue).font(.headline).foregroundStyle(.primary)
                                            Text("\(entries.count) référence(s)").font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth:.infinity,minHeight:108,alignment:.leading).padding(14)
                                            .background(.background,in:RoundedRectangle(cornerRadius:20))
                                    }.buttonStyle(.plain)
                                }
                            }
                            }
                        } else {
                            if let family {
                                Button { self.family = nil; subcategory = "" } label: { Label(family.rawValue,systemImage:"chevron.left") }.frame(minHeight:44)
                                Picker("Sous-catégorie",selection:$subcategory) {
                                    Text("Toutes les sous-catégories").tag("")
                                    ForEach(Array(Set(catalogue.filter { $0.family == family }.map(\.subcategory))).sorted(),id:\.self) { Text($0).tag($0) }
                                }.pickerStyle(.menu).frame(minHeight:44)
                            }
                            if filteredProducts.isEmpty { Text("Aucune référence pour cette recherche.").foregroundStyle(.secondary) }
                            LazyVStack(spacing:10) {
                                ForEach(filteredProducts.prefix(limit)) { product in
                                    VStack(spacing:8) {
                                        Button { selected = product } label: { stockCard(stock.entry(product.id) ?? StockEntry(product:product)) }.buttonStyle(.plain)
                                        HStack(spacing:12) {
                                            quickButton(product,.entry)
                                            quickButton(product,.exit)
                                        }.padding(.horizontal,14).padding(.bottom,12)
                                    }.background(.background,in:RoundedRectangle(cornerRadius:18))
                                }
                                if filteredProducts.count > limit { Button("Afficher la suite") { limit += 30 }.frame(minHeight:48) }
                            }
                        }
                    } else {
                        Text("Toujours dans le local, attribué à un chantier.").font(.subheadline).foregroundStyle(.secondary)
                        if stock.reservations.isEmpty { ContentUnavailableView("Aucune réservation",systemImage:"bookmark",description:Text("Réservez vos fournitures depuis le quantitatif d’un chantier.")) }
                        ForEach(Array(Set(stock.reservations.map(\.projectID))).sorted(by:{ $0.uuidString < $1.uuidString }),id:\.self) { id in
                            let reservations = stock.reservations.filter { $0.projectID == id }
                            DisclosureGroup {
                                ForEach(reservations) { reservation in
                                    if let entry = stock.entry(reservation.productID) {
                                        VStack(alignment:.leading,spacing:8) {
                                            Text(entry.product.name).font(.headline)
                                            Text("\(StockQuantity.text(reservation.quantity)) \(entry.product.unit) réservés").foregroundStyle(.orange)
                                            if stock.reserved(entry.id) > entry.quantity { Text("Stock insuffisant après inventaire").foregroundStyle(.red) }
                                            Button("Annuler la réservation") { cancel = reservation }.frame(minHeight:48)
                                        }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,8)
                                    }
                                }
                            } label: {
                                Text(projects.project(id:id)?.name ?? reservations.first?.projectName ?? "Chantier archivé").font(.headline).frame(minHeight:52)
                            }.padding(14).background(.background,in:RoundedRectangle(cornerRadius:18))
                        }
                    }
                }.padding()
            }.background(atlantique ? Atlantique.Palette.blue : Color(uiColor:.systemGroupedBackground))
                .navigationTitle("Local").atlantiquePage(family?.rawValue ?? "Stock · Local", root: true)
                .modifier(StockLegacySearch(text: $search, enabled: !atlantique))
                .onChange(of:search) { _,value in section = 0; limit = 30; if !atlantique && !value.isEmpty { family = nil; subcategory = "" } }
                .toolbar {
                    ToolbarItem(placement:.topBarTrailing) {
                        Menu {
                            if atlantique {
                                Button("Faire un inventaire", systemImage: "checklist") { movement = .inventory }
                                Button("Exporter mon stock", systemImage: "square.and.arrow.up") {
                                    do {
                                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Plaquisto-stock-\(UUID().uuidString.prefix(8)).txt")
                                        try StockTextExport.text(stock.entries).write(to: url, atomically: true, encoding: .utf8)
                                        export = .init(url: url)
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                            Button("Actualiser les références et prix",systemImage:"arrow.clockwise") { Task { await references.load(); await prices.load() } }
                            Button("Annuler la dernière opération",systemImage:"arrow.uturn.backward") { do { try stock.undoLast() } catch { self.error = error.localizedDescription } }.disabled(!stock.canUndo)
                        } label: { if atlantique { AtlantiqueToolbarGlyph() } else { Image(systemName:"ellipsis.circle") } }.accessibilityLabel("Options du stock")
                    }
                }
                .safeAreaInset(edge:.bottom) {
                    movementActions
                }
                .sheet(item: $export) { StockShareSheet(url: $0.url) }
                .sheet(item:$movement) { kind in StockProductPicker(kind:kind,products:catalogue) }
                .sheet(item:$quickMovement) { route in StockMovementView(kind:route.kind,product:route.product) {} }
                .sheet(item:$selected) { product in StockDetailView(product:product,prices:prices.catalogue) }
                .confirmationDialog("Annuler cette réservation ? Le matériel redevient disponible, sans sortir du stock.",isPresented:Binding(get:{cancel != nil},set:{ if !$0 { cancel = nil } }),titleVisibility:.visible) {
                    Button("Annuler la réservation",role:.destructive) {
                        if let cancel { do { try stock.cancel(cancel) } catch { self.error = error.localizedDescription } }
                        cancel = nil
                    }
                }
                .alert("Stock",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                .task { await references.load(); await prices.load() }
        }
    }
    private var movementActions: some View {
        HStack(spacing: 8) {
            ForEach(StockMovement.allCases) { action in
                Button { movement = action } label: { movementLabel(action) }.buttonStyle(.plain)
            }
        }.padding(12).background(atlantique ? Atlantique.Palette.blue : Color(uiColor: .systemBackground))
            .disabled(stock.loadError != nil)
    }
    private func movementLabel(_ action: StockMovement) -> some View {
        let color: Color = atlantique ? (action == .entry ? Atlantique.Palette.success : action == .exit ? Atlantique.Palette.danger : .white) : .blue
        let ink: Color = atlantique && action == .inventory ? Atlantique.Palette.blue : .white
        let icon = atlantique ? (action == .entry ? "arrow.up" : action == .exit ? "arrow.down" : "checklist") : action.symbol
        return VStack(spacing: 5) {
            Image(systemName: icon).font(.title3.bold())
            Text(action.rawValue).font(.subheadline.bold())
        }.frame(maxWidth: .infinity, minHeight: 64).foregroundStyle(ink)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
    }
    private var stockOverview: some View {
        let entries = filtered.filter { $0.quantity > 0 }
        let values = entries.compactMap { entry in StockValuation.unitPrice(entry.product, prices: prices.catalogue).map { $0 * entry.quantity } }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Dernière mise à jour").font(Atlantique.Typography.caption)
                    Text(stock.lastUpdatedAt?.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "fr_FR"))) ?? "—")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("Valeur estimée HT").font(Atlantique.Typography.caption)
                    Text(entries.isEmpty ? "0,00 €" : values.isEmpty ? "À renseigner" : SupplyCostEstimator.money(values.reduce(0,+))).bold()
                }
            }
            if entries.count > values.count { Text("Estimation partielle · tarifs manquants").font(Atlantique.Typography.caption) }
        }.foregroundStyle(.white)
    }
    private var familyList: some View {
        AtlantiqueCard {
            VStack(spacing: 0) {
                ForEach(StockFamily.allCases) { item in
                    Button { family = item; subcategory = ""; limit = 30 } label: {
                        HStack {
                            Image(systemName: item.symbol).frame(width: 28).foregroundStyle(Atlantique.Palette.actionInk)
                            Text(item.rawValue).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").foregroundStyle(Atlantique.Palette.actionInk)
                        }.frame(minHeight: 52)
                    }.buttonStyle(.plain)
                    if item != StockFamily.allCases.last { Divider() }
                }
            }
        }
    }
    private func quickButton(_ product:StockProduct,_ kind:StockMovement) -> some View {
        Button { quickMovement = .init(product:product,kind:kind) } label: {
            Label(kind.rawValue,systemImage:atlantique ? (kind == .entry ? "arrow.up" : "arrow.down") : kind.symbol).font(.subheadline.bold())
                .frame(maxWidth:.infinity,minHeight:48)
        }.buttonStyle(.borderedProminent).tint(atlantique ? (kind == .entry ? Atlantique.Palette.success : Atlantique.Palette.danger) : .blue)
            .disabled(stock.loadError != nil || (kind == .exit && (stock.entry(product.id)?.quantity ?? 0)<=0))
    }
    private func valuation(_ entries:[StockEntry]) -> some View {
        let present = entries.filter { $0.quantity > 0 }
        let values = present.compactMap { entry in StockValuation.unitPrice(entry.product,prices:prices.catalogue).map { $0*entry.quantity } }
        return VStack(alignment:.leading,spacing:5) {
            Text("Valeur estimée HT\(family != nil ? " · catégorie" : search.isEmpty ? " du stock" : " · sélection")").font(.subheadline).foregroundStyle(.secondary)
            Text(present.isEmpty ? "0 €" : values.isEmpty ? "À renseigner" : SupplyCostEstimator.money(values.reduce(0,+))).font(.largeTitle.bold())
            if present.count > values.count { Text("Estimation partielle · \(present.count-values.count) référence(s) sans prix valide").font(.caption).foregroundStyle(.orange) }
            Text("Tarifs Admin · matériel réservé inclus").font(.caption).foregroundStyle(.secondary)
            if let message = prices.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(.background,in:RoundedRectangle(cornerRadius:22))
    }
    private func stockCard(_ entry:StockEntry) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(entry.product.name).font(.headline).foregroundStyle(.primary)
            Text(entry.usesPack ? "\(StockQuantity.text(entry.quantity/entry.packSize)) × \(entry.packName)" : "\(StockQuantity.text(entry.quantity)) \(entry.product.unit)").font(.title2.bold()).foregroundStyle(.blue)
            if entry.usesPack { Text("\(StockQuantity.text(entry.quantity)) \(entry.product.unit) · \(entry.packName) de \(StockQuantity.text(entry.packSize)) \(entry.product.unit)").font(.caption).foregroundStyle(.secondary) }
            if stock.reserved(entry.id) > 0 {
                Text("\(StockQuantity.text(stock.reserved(entry.id)/(entry.usesPack ? entry.packSize : 1))) réservés · \(StockQuantity.text(stock.available(entry.id)/(entry.usesPack ? entry.packSize : 1))) disponibles").font(.subheadline).foregroundStyle(.orange)
                if stock.reserved(entry.id) > entry.quantity { Text("Réservations supérieures au stock : à ajuster").font(.caption).foregroundStyle(.red) }
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(.background,in:RoundedRectangle(cornerRadius:18))
    }
}

private struct StockProductPicker: View {
    let kind:StockMovement
    let products:[StockProduct]
    @ObservedObject private var stock = StockStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var family:StockFamily?
    @State private var subcategory = ""
    @State private var search = ""
    @State private var custom = false
    @State private var selected:StockProduct?
    @State private var limit = 30
    private var choices:[StockProduct] {
        let source = kind == .exit ? stock.entries.map(\.product) : products
        return StockCatalogue.filtered(source,family:family,subcategory:subcategory,search:search)
    }
    var body:some View {
        NavigationStack {
            List {
                if family == nil && search.isEmpty {
                    ForEach(StockFamily.allCases) { f in Button { family = f; subcategory = "" } label: { Label(f.rawValue,systemImage:f.symbol).frame(minHeight:50) } }
                } else {
                    if let family {
                        Button("Toutes les familles") { self.family = nil; subcategory = "" }
                        Picker("Sous-catégorie",selection:$subcategory) {
                            Text("Toutes").tag("")
                            ForEach(Array(Set((kind == .exit ? stock.entries.map(\.product) : products).filter { $0.family == family }.map(\.subcategory))).sorted(),id:\.self) { Text($0).tag($0) }
                        }
                    }
                    ForEach(choices.prefix(limit)) { product in
                        Button { selected = product } label: {
                            VStack(alignment:.leading,spacing:5) { Text(product.name); Text(product.unit).font(.caption).foregroundStyle(.secondary) }.frame(minHeight:50)
                        }.foregroundStyle(.primary)
                    }
                    if choices.isEmpty { Text("Aucune référence. Essayez un autre terme.").foregroundStyle(.secondary) }
                    if choices.count > limit { Button("Afficher la suite") { limit += 30 } }
                }
                if kind == .entry { Button("Référence absente ? Ajouter un produit") { custom = true }.frame(minHeight:48) }
            }.navigationTitle(kind.rawValue).searchable(text:$search,prompt:"Nom, dimensions, modèle…")
                .onChange(of:search) { _,value in limit = 30; if !value.isEmpty { family = nil; subcategory = "" } }
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Fermer") { dismiss() } } }
                .sheet(item:$selected) { product in StockMovementView(kind:kind,product:product) { dismiss() } }
                .sheet(isPresented:$custom) { StockCustomProductView { product in custom = false; selected = product } }
        }
    }
}

private struct StockCustomProductView: View {
    var done:(StockProduct)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "unité"
    @State private var family:StockFamily = .boards
    var body:some View {
        NavigationStack {
            AtlantiqueForm {
                TextField("Nom et dimensions du produit",text:$name)
                Picker("Famille",selection:$family) { ForEach(StockFamily.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Unité",selection:$unit) { ForEach(["unité","m²","ml","kg","L"],id:\.self) { Text($0).tag($0) } }
                Text("Un produit personnel n’a pas de prix Admin tant qu’il n’est pas référencé. Utilisez une référence du catalogue quand elle existe.").font(.caption)
            }.navigationTitle("Nouveau produit").atlantiqueFormPage("Nouveau produit")
                .safeAreaInset(edge:.bottom) { Button { done(.init(name:name,unit:unit,family:family)) } label: { StockActionLabel(title:"Continuer",symbol:"arrow.right") }.padding().disabled(name.trimmingCharacters(in:.whitespaces).isEmpty) }
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } } }
        }
    }
}

private struct StockDetailView: View {
    var product:StockProduct
    var prices:SupplyPriceCatalogue?
    @ObservedObject private var stock = StockStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var movement:StockMovement?
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text(product.name).font(.title2.bold())
                    Text("\(StockQuantity.text(stock.entry(product.id)?.quantity ?? 0)) \(product.unit) en stock").font(.largeTitle.bold())
                    Text("\(StockQuantity.text(stock.reserved(product.id))) réservés · \(StockQuantity.text(stock.available(product.id))) disponibles").foregroundStyle(.orange)
                    if let price = StockValuation.unitPrice(product,prices:prices) { Text("Valeur estimée : \(SupplyCostEstimator.money(price*(stock.entry(product.id)?.quantity ?? 0))) HT") }
                    else { Text("Prix non renseigné ou non validé").foregroundStyle(.secondary) }
                    ForEach(stock.reservations.filter { $0.productID == product.id }) { r in
                        Label("\(r.projectName) · \(StockQuantity.text(r.quantity)) \(product.unit)",systemImage:"bookmark")
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding()
            }.navigationTitle("Fourniture").atlantiqueFormPage("Fourniture").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fermer") { dismiss() } } }
                .safeAreaInset(edge:.bottom) {
                    VStack(spacing:10) { ForEach(StockMovement.allCases) { action in Button { movement = action } label: { StockActionLabel(title:action.rawValue,symbol:action.symbol) } } }.padding().background(.regularMaterial)
                }
                .sheet(item:$movement) { action in StockMovementView(kind:action,product:product) {} }
        }
    }
}

private struct StockMovementView: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    @State private var partialPack = 0.0
    @State private var initializedPack = false
    let kind:StockMovement
    let product:StockProduct
    var done:()->Void
    @ObservedObject private var stock = StockStore.shared
    @EnvironmentObject private var projects:ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var usesPack = false
    @State private var packName = "boîte"
    @State private var packSize = "1"
    @State private var projectID:UUID?
    @State private var error:String?
    @State private var confirmInventory = false
    @FocusState private var focused:Bool
    init(kind:StockMovement,product:StockProduct,done:@escaping ()->Void) {
        self.kind = kind; self.product = product; self.done = done
        let entry = StockStore.shared.entry(product.id)
        let dimensions = product.variant?.split(separator:"x").compactMap { Double($0) } ?? []
        let boardArea = product.unit == "m²" && product.family == .boards && dimensions.count == 2 ? dimensions[0]*dimensions[1]/1_000_000 : nil
        _usesPack = State(initialValue:entry?.usesPack ?? (boardArea != nil))
        _packName = State(initialValue:entry?.packName ?? (boardArea != nil ? "plaque" : product.family == .frames ? "barre" : "boîte"))
        _packSize = State(initialValue:entry?.usesPack == true ? StockQuantity.input(entry!.packSize) : boardArea.map(StockQuantity.input) ?? "")
        _quantity = State(initialValue:kind == .inventory ? StockQuantity.input((entry?.quantity ?? 0)/((entry?.usesPack == true) ? (entry?.packSize ?? 1) : 1)) : "")
    }
    private var amount:Double? {
        guard let q = StockQuantity.parse(quantity) else { return nil }
        guard usesPack else { return q }
        guard let size = StockQuantity.parse(packSize), size > 0 else { return nil }
        return StockQuantity.packed(complete: q, partial: atlantique ? partialPack : 0, size: size)
    }
    var body:some View {
        NavigationStack {
            AtlantiqueForm {
                Section {
                    Text(product.name).font(.headline)
                    Text("Actuellement : \(StockQuantity.text(stock.entry(product.id)?.quantity ?? 0)) \(product.unit)").foregroundStyle(.secondary)
                }
                Section(kind == .inventory ? "Quantité réellement présente" : "Quantité à \(kind == .entry ? "ajouter" : "sortir")") {
                    Picker("Saisie",selection:$usesPack) { Text(product.unit).tag(false); Text("Conditionnement").tag(true) }.pickerStyle(.segmented)
                        .onChange(of:usesPack) { _,_ in quantity = atlantique && usesPack ? "0" : ""; partialPack = 0 }
                    HStack {
                        TextField("Quantité",text:$quantity).keyboardType(.decimalPad).font(.largeTitle.bold()).focused($focused)
                        Text(usesPack ? packName : product.unit).foregroundStyle(.secondary)
                    }.frame(minHeight:64)
                    if usesPack {
                        if atlantique {
                            HStack { Text("Contenu d’une unité de conditionnement"); TextField("Contenu", text: $packSize).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.trailing); Text(product.unit) }
                            Picker("Conditionnement", selection: $packName) { ForEach(["boîte","sac","seau","pot","rouleau","unité","plaque","paquet"], id: \.self) { Text($0).tag($0) } }
                            LabeledContent("Conditionnement entamé", value: "\(Int((partialPack * 100).rounded())) %")
                            Slider(value: $partialPack, in: 0...1, step: 0.01).accessibilityLabel("Remplissage du conditionnement entamé")
                            HStack { Text("0 % · Vide"); Spacer(); Text("100 % · Complet") }.font(.caption)
                        } else {
                        HStack(spacing:10) {
                            ForEach([0.25,0.5,0.75],id:\.self) { part in
                                Button { quantity = StockQuantity.text(floor(StockQuantity.parse(quantity) ?? 0)+part) } label: {
                                    Text(part == 0.25 ? "¼" : part == 0.5 ? "½" : "¾").font(.title2.bold()).frame(maxWidth:.infinity,minHeight:52).background(.blue.opacity(0.1),in:RoundedRectangle(cornerRadius:12))
                                }.buttonStyle(.plain)
                            }
                        }
                        Text("La fraction s’ajoute au nombre de boîtes complètes saisi.").font(.caption).foregroundStyle(.secondary)
                        Picker("Conditionnement",selection:$packName) { ForEach(["boîte","sac","seau","pot","rouleau","barre","plaque","paquet"],id:\.self) { Text($0).tag($0) } }
                        HStack { Text("Contenu d’un(e) \(packName)"); TextField("Contenu",text:$packSize).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.trailing); Text(product.unit) }
                    }
                    }
                    if let amount { Text("Soit \(StockQuantity.text(amount)) \(product.unit)").font(.headline) }
                }
                if kind.allowsProjectAssignment && !atlantique {
                    AtlantiqueSection("Chantier · facultatif") {
                        Picker("Attribuer à",selection:$projectID) {
                            Text("Sans chantier").tag(nil as UUID?)
                            ForEach(projects.projects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        if kind == .exit { Text("Une sortie pour un chantier utilise d’abord sa réservation. Les réservations des autres chantiers restent protégées.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if atlantique, let amount {
                    AtlantiqueSection("Après validation") {
                        let current = stock.entry(product.id)?.quantity ?? 0
                        Text("\(StockQuantity.text(kind == .inventory ? amount : kind == .entry ? current + amount : current - amount)) \(product.unit) en stock").font(Atlantique.Typography.heading)
                        if kind == .inventory { Text("Ce comptage remplace la quantité du stock.").font(.caption) }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(kind.rawValue).atlantiqueFormPage(kind.rawValue).navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    if atlantique && usesPack && !initializedPack, let value = StockQuantity.parse(quantity) {
                        partialPack = value - floor(value); quantity = StockQuantity.input(floor(value))
                    }
                    initializedPack = true
                }
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("Terminé") { focused = false } } }
                .safeAreaInset(edge:.bottom) {
                    Button {
                        focused = false
                        if kind == .inventory, let amount, amount < stock.reserved(product.id) { confirmInventory = true } else { save() }
                    } label: { StockActionLabel(title:kind == .inventory ? "Valider le comptage" : "Valider l’\(kind == .entry ? "entrée" : "sortie")",symbol:"checkmark") }
                        .padding().background(.regularMaterial).disabled(amount == nil || (kind != .inventory && amount == 0))
                }
                .confirmationDialog("Ce comptage est inférieur aux réservations. Elles seront conservées et signalées comme à ajuster.",isPresented:$confirmInventory,titleVisibility:.visible) { Button("Confirmer le comptage") { save() } }
        }
    }
    private func save() {
        guard let amount else { return }
        let size = usesPack ? (StockQuantity.parse(packSize) ?? 1) : max(StockQuantity.parse(packSize) ?? 1,1)
        do {
            let assignedProject = kind.allowsProjectAssignment && !atlantique ? projectID : nil
            try stock.move(kind,product:product,quantity:amount,packName:packName,packSize:size,usesPack:usesPack,projectID:assignedProject,projectName:assignedProject.flatMap { projects.project(id:$0)?.name })
            dismiss(); done()
        } catch { self.error = error.localizedDescription }
    }
}

private struct StockLegacySearch: ViewModifier {
    @Binding var text: String
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.searchable(text: $text, prompt: "Chercher une fourniture") } else { content }
    }
}

enum StockTextExport {
    static func text(_ entries: [StockEntry]) -> String {
        let lines = entries.sorted { $0.product.name.localizedStandardCompare($1.product.name) == .orderedAscending }
            .map { "• \($0.product.name) : \(StockQuantity.text($0.quantity)) \($0.product.unit)" }
        return (["Plaquisto · Stock Local"] + lines).joined(separator: "\n")
    }
}
