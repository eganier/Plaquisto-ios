import SwiftUI

struct Supply: Identifiable { let id: String; let name: String; let quantity: Double; let unit: String }

struct ConfiguratorView: View {
    @StateObject private var store = ReferenceStore()
    @State private var step = 0
    @State private var length = 5.0
    @State private var width = 4.0
    @State private var plenum = 20.0
    @State private var insulation = 5.0
    @State private var supportID = ""
    @State private var boardID = ""
    @State private var suspensionID = ""
    @State private var layers = 1
    @State private var vaporBarrier = false
    @State private var parallel = false
    @State private var waterResistant = false
    @State private var fireRated = false

    private let stepNames = ["Dimensions", "Support", "Isolation", "Parement", "Options", "Résultat"]
    private var supports: [ReferenceRecord] { store.records.filter { $0.kind == "support" } }
    private var boards: [ReferenceRecord] { store.records.filter { $0.kind == "board" } }
    private var suspensions: [ReferenceRecord] { store.records.filter { $0.kind == "suspension" } }
    private var selectedSupport: ReferenceRecord? { supports.first { $0.id == supportID } }
    private var isWoodSupport: Bool { supportID == "SUP-BOIS-SOLIVAGE" }
    private var compatibleSuspensions: [ReferenceRecord] {
        guard isWoodSupport else { return [] }
        let height = plenum * 10
        return suspensions.filter { suspension in
            guard suspension.data["support"]?.string == "Bois" else { return false }
            if let minimum = suspension.data["reglage_min_mm"]?.number,
               let maximum = suspension.data["reglage_max_mm"]?.number { return height >= minimum && height <= maximum }
            if let values = suspension.data["reglages_mm"]?.array?.compactMap({ $0.string.flatMap(Double.init) }) { return values.contains { abs($0-height) < 0.1 } }
            if suspension.id == "SUSP-CAVALIER" { return height > 20 }
            return false
        }
    }
    private var area: Double { length * width }
    private var spacing: Double? {
        guard insulation <= 15 else { return nil }
        if parallel || waterResistant || insulation >= 10 { return 0.4 }
        return insulation >= 6 ? 0.5 : 0.6
    }
    private var profile: ReferenceRecord? {
        guard let spacing else { return nil }
        return store.records.first { $0.kind == "quantity" && $0.data["peaux"]?.number == Double(layers) && $0.data["entraxe_fourrures_m"]?.number == spacing }
    }
    private var supplies: [Supply] {
        guard let data = profile?.data else { return [] }
        let definitions = [("plaque_m2","Plaques de plâtre","m²"),("fourrure_f530_ml","Fourrures Stil® F 530","ml"),("rail_f530_ml","Rails Stil® F 530","ml"),("suspente_unite","Suspentes compatibles","u"),("eclisse_unite","Éclisses Stil® F 530","u"),("vis_premiere_peau_unite","Vis — première peau","u"),("vis_deuxieme_peau_unite","Vis — deuxième peau","u"),("bande_joint_ml","Bande à joint","ml"),("enduit_poudre_kg","Enduit en poudre","kg")]
        return definitions.compactMap { key,name,unit in guard let ratio=data[key]?.number else{return nil}; return Supply(id:key,name:name,quantity:ratio*area,unit:unit) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading { ProgressView("Chargement de Plaquisto Admin…") }
                else if let error = store.error { ContentUnavailableView("Référentiel indisponible", systemImage:"wifi.exclamationmark", description:Text(error)).overlay(alignment:.bottom){Button("Réessayer"){Task{await store.load()}}.buttonStyle(.borderedProminent).padding(.bottom,80)} }
                else { configurator }
            }
            .task { if store.records.isEmpty { await store.load() } }
        }
        .tint(Color(red:0.12,green:0.38,blue:0.29))
    }

    private var configurator: some View {
        VStack(spacing:0) {
            VStack(alignment:.leading,spacing:10) {
                Text("OUVRAGE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("Plafond Placostil®\nsur fourrures Stil® F 530").font(.title2.bold())
                ProgressView(value:Double(step+1),total:Double(stepNames.count))
                Text("Étape \(step+1) sur \(stepNames.count) · \(stepNames[step])").font(.caption).foregroundStyle(.secondary)
            }.padding()
            Divider()
            Form { stepContent }
            HStack {
                if step > 0 { Button("Retour") { withAnimation { step -= 1 } }.buttonStyle(.bordered) }
                Spacer()
                if step < stepNames.count-1 { Button("Continuer") { prepareDefaults(); withAnimation { step += 1 } }.buttonStyle(.borderedProminent).disabled(!canContinue) }
                else { Button("Nouvel ouvrage") { withAnimation { step=0 } }.buttonStyle(.borderedProminent) }
            }.padding().background(.bar)
        }.navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0:
            Section("Dimensions de la pièce") { MeasureField(label:"Longueur",value:$length,unit:"m"); MeasureField(label:"Largeur",value:$width,unit:"m") }
            Section { LabeledContent("Surface",value:"\(area.formatted(.number.precision(.fractionLength(2)))) m²") } footer:{Text("La surface sert de base au calcul des fournitures.")}
        case 1:
            Section("Support du plafond") { Picker("Type de support",selection:$supportID){Text("Sélectionner").tag("");ForEach(supports){Text($0.title).tag($0.id)}}.onChange(of:supportID){_,_ in suspensionID=""};MeasureField(label:"Hauteur du plénum",value:$plenum,unit:"cm");Toggle("Prévoir la pose d’un pare-vapeur",isOn:$vaporBarrier) }
            if isWoodSupport {
                Section {
                    if compatibleSuspensions.isEmpty { Label("Aucune suspente compatible avec cette hauteur.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    else { Picker("Suspente",selection:$suspensionID){Text("Sélectionner").tag("");ForEach(compatibleSuspensions){Text($0.title).tag($0.id)}};if let suspension=suspensions.first(where:{$0.id==suspensionID}){Text(suspension.summary).font(.subheadline);LabeledContent("Fixation",value:suspension.data["fixation"]?.string ?? "—");LabeledContent("Entraxe",value:"1,20 m")} }
                } header:{Text("Choix de la suspente")} footer:{Text("La liste est filtrée selon le support et la hauteur du plénum enregistrés dans Plaquisto Admin.")}
            } else if let support=selectedSupport { Section("Fixation compatible") { Text(support.summary);Label("Source : page \(support.sourcePage)",systemImage:"doc.text").font(.caption).foregroundStyle(.secondary) } }
        case 2:
            Section("Isolation") { MeasureField(label:"Poids de l’isolant",value:$insulation,unit:"kg/m²") }
            Section { if let spacing { LabeledContent("Entraxe maximal",value:"\(Int(spacing*100)) cm") } else { Label("Au-delà de 15 kg/m², cette configuration n’est pas couverte.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange) } } footer:{Text("À 6 kg/m², la règle 6 à moins de 10 s’applique. À 10 kg/m², la règle 10 à 15 s’applique.")}
        case 3:
            Section("Plaques de plâtre") { Picker("Plaque",selection:$boardID){Text("Sélectionner").tag("");ForEach(boards){Text($0.title).tag($0.id)}};Picker("Nombre de peaux",selection:$layers){Text("Simple peau").tag(1);Text("Double peau").tag(2)}.pickerStyle(.segmented) }
        case 4:
            Section("Conditions particulières") { Toggle("Plaques parallèles aux fourrures",isOn:$parallel);Toggle("Plaque hydrofugée",isOn:$waterResistant);Toggle("Exigence de résistance au feu",isOn:$fireRated) }
            Section("Règle retenue") { LabeledContent("Entraxe des fourrures",value:spacing.map{"\(Int($0*100)) cm"} ?? "Non compatible");LabeledContent("Entraxe des suspentes",value:"120 cm");if fireRated{LabeledContent("Vis",value:"Tous les 15 cm")}else{LabeledContent("Vis",value:"Tous les 30 cm")} }
        default:
            Section { VStack(alignment:.leading,spacing:8){Label("Configuration cohérente",systemImage:"checkmark.seal.fill").font(.headline).foregroundStyle(.green);Text("\(area.formatted(.number.precision(.fractionLength(2)))) m² · \(layers == 1 ? "simple" : "double") peau · entraxe \(Int((spacing ?? 0)*100)) cm").font(.subheadline).foregroundStyle(.secondary)}.padding(.vertical,5) }
            Section("Fournitures indicatives") { ForEach(supplies){item in LabeledContent(item.name,value:"\(rounded(item.quantity,item.unit)) \(item.unit)")};if fireRated,spacing == 0.6,let ratio=profile?.data["entretoise_stil_flam_unite"]?.number{LabeledContent("Entretoises Stil Flam",value:"\(Int(ceil(ratio*area))) u")} }
            Section { Label("Enduit en poudre ou prêt à l’emploi : ne pas additionner les deux quantités.",systemImage:"info.circle") } footer:{Text("Quantités indicatives issues de Plaquisto Admin, pour une base fabricant de 8 × 10 m. Les conditionnements et les prix seront ajoutés depuis l’administration.")}
        }
    }

    private var canContinue: Bool { switch step { case 0:return length>0 && width>0;case 1:return !supportID.isEmpty && plenum>0 && (!isWoodSupport || compatibleSuspensions.contains(where:{$0.id==suspensionID}));case 2:return insulation>=0 && insulation<=15;case 3:return !boardID.isEmpty;default:return true } }
    private func prepareDefaults(){if supportID.isEmpty{supportID=supports.first?.id ?? ""};if boardID.isEmpty{boardID=boards.first?.id ?? ""}}
    private func rounded(_ value:Double,_ unit:String)->String { unit=="u" ? String(Int(ceil(value))) : value.formatted(.number.precision(.fractionLength(2))) }
}

private struct MeasureField: View {
    let label:String; @Binding var value:Double; let unit:String
    var body:some View { HStack { Text(label); Spacer(); TextField("0",value:$value,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:90);Text(unit).foregroundStyle(.secondary) } }
}
