import Foundation
import SwiftUI

/// Tariffs are independent of technical coefficients and quantities. No pack
/// rounding, no second waste allowance, and no guessed commercial equivalent.
struct SupplyPriceKey: Hashable {
    var referenceId: String
    var variantKey: String
    var unit: String
}

struct SupplyPrice: Codable, Identifiable {
    var id: String
    var referenceId: String
    var variantKey: String
    var label: String
    var unit: String
    var unitPriceHT: Double
    var repUnitHT: Double
    var priceDate: String
    var validUntil: String?
    var status: String
    var updatedAt: String
    var key: SupplyPriceKey { .init(referenceId:referenceId,variantKey:variantKey,unit:unit) }
    func isUsable(on day: String) -> Bool {
        status == "validated" && unitPriceHT.isFinite && unitPriceHT > 0
            && repUnitHT.isFinite && repUnitHT >= 0
            && priceDate <= day && (validUntil.map { $0 >= day } ?? true)
    }
}

struct SupplyPriceCatalogue: Codable {
    var version: String
    var revision: String
    var currency: String
    var lowerMultiplier: Double
    var upperMultiplier: Double
    var prices: [SupplyPrice]
    var isSupported: Bool {
        version == "1.0" && currency == "EUR" && lowerMultiplier == 0.95 && upperMultiplier == 1.05
    }
}

enum SupplyCostEstimator {
    struct Line: Identifiable {
        var id: String
        var name: String
        var quantity: Double
        var unit: String
        var price: SupplyPrice?
        var amount: Double? {
            guard let price else { return nil }
            let result=quantity*(price.unitPriceHT+price.repUnitHT)
            return result.isFinite ? result : nil
        }
    }
    struct Estimate {
        var lines: [Line]
        var priced: [Line] { lines.filter { $0.amount != nil } }
        var missing: [Line] { lines.filter { $0.amount == nil } }
        /// Nil means unknown, never a misleading zero-euro estimate.
        var total: Double? {
            guard !priced.isEmpty else { return nil }
            let sum=priced.compactMap(\.amount).reduce(0,+)
            return sum.isFinite ? sum : nil
        }
        var lower: Double? { total.map { $0*0.95 } }
        var upper: Double? { total.map { $0*1.05 } }
    }

    static func estimate(_ supplies: [CombinedSupply], prices: SupplyPriceCatalogue?, catalogue: CeilingCataloguePayload, day: String) -> Estimate {
        let available = prices?.isSupported == true ? prices!.prices.filter { $0.isUsable(on:day) } : []
        let indexed=Dictionary(grouping:available,by:\.key)
        return Estimate(lines:supplies.map { supply in
            let resolved=resolve(supply,catalogue:catalogue)
            let candidates=resolved.flatMap { indexed[$0.key] } ?? []
            // Even two identical amounts are ambiguous: the user must select
            // which supplier tariff is the reference in Admin.
            let price=candidates.count == 1 && supply.quantity.isFinite && supply.quantity >= 0 ? candidates[0] : nil
            return Line(id:supply.id,name:supply.name,quantity:resolved?.quantity ?? supply.quantity,unit:resolved?.key.unit ?? supply.unit,price:price)
        })
    }

    struct Resolved { var key: SupplyPriceKey; var quantity: Double }
    static func resolve(_ supply: CombinedSupply, catalogue: CeilingCataloguePayload) -> Resolved? {
        let unit=SupplyListingConsolidator.canonicalUnit(supply.unit)
        let name=SupplyListingConsolidator.canonicalName(supply.name)
        // Transitional exact bridge for persisted quantities which currently
        // contain display labels. Never match substrings, sizes alone or fuzzy names.
        var matches:[Resolved]=[]
        for record in catalogue.parements {
            for value in record.data["dimensions"]?.array ?? [] {
                guard let d=value.object, let w=d["width_mm"]?.number, let h=d["length_mm"]?.number,
                      w.isFinite, h.isFinite, w>0, h>0, w<=100_000, h<=100_000 else { continue }
                let label="\(record.title) · \(Int(w)) × \(Int(h)) mm"
                guard name == label, unit == "plaques" || unit == "m²" else { continue }
                matches.append(.init(key:.init(referenceId:record.id,variantKey:"\(Int(w))x\(Int(h))",unit:"m²"),quantity:supply.quantity*(unit == "plaques" ? w*h/1_000_000 : 1)))
            }
        }
        if matches.count == 1 { return matches[0] }
        if !matches.isEmpty { return nil }
        let priceUnit=unit == "unités" ? "unité" : unit
        guard ["m²","ml","unité","kg"].contains(priceUnit) else { return nil }
        let quantities=catalogue.quantitatifs.filter {
            $0.id != "QTY-PLAQUE" && SupplyListingConsolidator.canonicalName($0.title) == name
                && SupplyListingConsolidator.canonicalUnit($0.data["unit"]?.string ?? "") == unit
        }
        guard quantities.count == 1, let record=quantities.first else { return nil }
        return .init(key:.init(referenceId:record.id,variantKey:record.id == "QTY-BANDE" ? "papier" : "standard",unit:priceUnit),quantity:supply.quantity)
    }
    static func day(_ date: Date = Date()) -> String {
        let f=DateFormatter(); f.locale=Locale(identifier:"en_US_POSIX"); f.timeZone=TimeZone(identifier:"Europe/Paris"); f.dateFormat="yyyy-MM-dd"
        return f.string(from:date)
    }
    static func money(_ amount:Double) -> String { amount.formatted(.currency(code:"EUR").locale(Locale(identifier:"fr_FR"))) }
}

@MainActor final class SupplyPriceStore: ObservableObject {
    @Published private(set) var catalogue:SupplyPriceCatalogue?
    @Published private(set) var isLoading=false
    @Published private(set) var offline=false
    @Published private(set) var message:String?
    private let cacheKey="plaquisto.prices.v1"
    func load() async {
        guard !isLoading else { return }
        isLoading=true; defer { isLoading=false }
        do {
            var request=URLRequest(url:URL(string:"https://plaquisto-admin.vercel.app/api/ios/prices")!)
            request.timeoutInterval=15; request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data,response)=try await URLSession.shared.data(for:request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let value=try JSONDecoder().decode(SupplyPriceCatalogue.self,from:data)
            guard value.isSupported else { throw URLError(.cannotParseResponse) }
            catalogue=value; offline=false; message=nil
            UserDefaults.standard.set(data,forKey:cacheKey)
        } catch {
            if let data=UserDefaults.standard.data(forKey:cacheKey),
               let cached=try? JSONDecoder().decode(SupplyPriceCatalogue.self,from:data),cached.isSupported {
                catalogue=cached; offline=true; message="Derniers tarifs enregistrés. Les tarifs expirés sont exclus."
            } else { catalogue=nil; message="Tarifs indisponibles. Le quantitatif reste consultable." }
        }
    }
}

struct SupplyCostSection: View {
    let estimate:SupplyCostEstimator.Estimate
    let loading:Bool
    let message:String?
    var body: some View {
        Section(estimate.missing.isEmpty ? "Fournitures · estimation HT" : "Fournitures · estimation HT partielle") {
            if loading { ProgressView("Chargement des tarifs…") }
            else if let lower=estimate.lower,let upper=estimate.upper {
                Text("\(SupplyCostEstimator.money(lower)) à \(SupplyCostEstimator.money(upper)) HT").font(.title3.bold())
                Text("Fourchette de ±5 % · éco-contribution incluse · hors main-d’œuvre et livraison.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("\(estimate.priced.count) fourniture(s) chiffrée(s)") {
                    ForEach(estimate.priced) { line in
                        if let amount=line.amount {
                            LabeledContent(line.name,value:SupplyCostEstimator.money(amount)).font(.caption)
                        }
                    }
                }
            } else { Text("Aucun tarif validé disponible pour ces fournitures.").foregroundStyle(.secondary) }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if !loading && !estimate.missing.isEmpty {
                DisclosureGroup("\(estimate.missing.count) fourniture(s) non chiffrée(s)") {
                    Text("Non incluses dans le montant. Renseignez ou validez leurs tarifs dans Plaquisto Admin.").font(.caption)
                    ForEach(estimate.missing) { Text($0.name).font(.caption) }
                }
            }
        }
    }
}
