import SwiftUI

struct PaintingBetaConfiguratorView: View {
    let readOnlyArea: Bool
    let onSave: (PaintingBetaConfiguration) -> Void
    @State private var configuration: PaintingBetaConfiguration
    @StateObject private var reference = PaintingReferenceStore()
    @StateObject private var products = PaintingProductStore()

    init(initialConfiguration: PaintingBetaConfiguration = .init(), readOnlyArea: Bool = false,
         onSave: @escaping (PaintingBetaConfiguration) -> Void) {
        self.readOnlyArea = readOnlyArea; self.onSave = onSave
        _configuration = State(initialValue: initialConfiguration)
    }
    var body: some View {
        Group {
            if let treatment = configuration.treatment {
                PaintingStepsView(area: $configuration.area,
                                  treatment: Binding(get: { configuration.treatment ?? treatment }, set: { configuration.treatment = $0 }),
                                  products: products, readOnlyArea: readOnlyArea,
                                  referenceMessage: reference.message,
                                  onSave: { onSave(configuration) })
            } else {
                ContentUnavailableView {
                    Label("Bases de calcul peinture", systemImage: "paintbrush")
                } description: {
                    Text(reference.message ?? "Chargement depuis Plaquisto Admin…")
                } actions: {
                    if reference.loading { ProgressView() }
                    else { Button("Réessayer") { Task { await load() } } }
                }
            }
        }
        .navigationTitle("Peinture et ratissages").atlantiqueFormPage("Peinture et ratissages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        if configuration.treatment == nil, let rules = reference.rules { configuration.treatment = .init(rules: rules) }
        await reference.load()
        if configuration.treatment == nil, let rules = reference.rules { configuration.treatment = .init(rules: rules) }
    }
}

private struct PaintingStepsView: View {
    @Binding var area: Double
    @Binding var treatment: PaintingTreatment
    @ObservedObject var products: PaintingProductStore
    let readOnlyArea: Bool
    let referenceMessage: String?
    let onSave: () -> Void
    @State private var step = 0
    @State private var notice: String?
    @State private var activePass = 0
    private var titles: [String] {
        ["Traitements"] + (treatment.skimEnabled ? ["Ratissage"] : []) +
        (treatment.includesPrimer ? ["Impression"] : []) +
        (treatment.paintEnabled ? ["Finition"] : []) + ["Quantitatif"]
    }
    private var currentStep: String { titles[min(step, titles.count - 1)] }
    private var configuration: PaintingBetaConfiguration { .init(area: area, treatment: treatment) }
    private var supplies: [PaintingSupply] { (try? PaintingCalculator.calculate(configuration)) ?? [] }
    private var validation: String? {
        do { _ = try PaintingCalculator.calculate(configuration); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Peinture et ratissages").font(.title2.bold())
                Text("Étape \(step + 1) sur \(titles.count) · \(currentStep)").foregroundStyle(.secondary)
                ProgressView(value: Double(step + 1), total: Double(titles.count)).tint(.accentColor)
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
            AtlantiqueForm {
                switch currentStep {
                case "Traitements": preparation
                case "Ratissage": skimStep
                case "Impression": AtlantiqueSection("Impression") { productEditor($treatment.primer) }
                case "Finition": AtlantiqueSection("Peinture de finition") {
                    Picker("Nombre de couches", selection: $treatment.finishCoats) {
                        ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                    }
                    productEditor($treatment.finish)
                }
                default: quantities
                }
            }
            HStack {
                if step > 0 {
                    Button("Retour") { step -= 1 }.buttonStyle(.bordered)
                        .formStepMenu(titles: titles, selection: $step, canShowResult: validation == nil)
                }
                Spacer()
                Button(currentStep == "Quantitatif" ? "Enregistrer" : currentStep == "Ratissage" ? "Terminer" : "Continuer") {
                    if currentStep == "Quantitatif" { onSave() } else { step += 1 }
                }.buttonStyle(.borderedProminent)
                    .disabled(step == 0 ? !area.isFinite || area <= 0 || !(treatment.skimEnabled || treatment.includesPrimer || treatment.paintEnabled) : validation != nil)
            }.padding().background(.bar)
        }
        .alert("Mes peintures", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .onAppear {
            let primer = treatment.includesPrimer
            treatment.independentTreatments = true
            treatment.primerEnabled = primer
            treatment.airless = false
            treatment.primer.yieldM2PerL = treatment.primer.yieldM2PerL.rounded()
            treatment.finish.yieldM2PerL = treatment.finish.yieldM2PerL.rounded()
            for i in treatment.passes.indices {
                let kind = PaintingPassKind.of(treatment.passes[i].compoundID)
                treatment.passes[i].thicknessMM = max(kind.rangeMM.lowerBound, min(kind.rangeMM.upperBound,
                    (treatment.passes[i].thicknessMM / kind.stepMM).rounded() * kind.stepMM))
            }
        }
    }

    @ViewBuilder private var preparation: some View {
        Section {
            Toggle("Prévoir un ratissage", isOn: $treatment.skimEnabled)
            Toggle("Prévoir une impression", isOn: $treatment.primerEnabled)
            Toggle("Prévoir une peinture de finition", isOn: $treatment.paintEnabled)
        }
        AtlantiqueSection("Surface à traiter") {
            if readOnlyArea { LabeledContent("Surface nette", value: "\(number(area)) m²") }
            else {
                HStack {
                    Text("Surface"); Spacer()
                    ZeroEmptyDecimalTextField(value: $area).multilineTextAlignment(.trailing).frame(width: 100)
                    Text("m²").foregroundStyle(.secondary)
                }
            }
            if readOnlyArea { Text("Les ouvertures sont déjà déduites. Les dimensions se modifient dans le relevé source.").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var skimStep: some View {
        if treatment.passes.count > 1 {
            AtlantiqueSection("Passes prévues") {
                ForEach(Array(treatment.passes.enumerated()), id: \.element.id) { i, pass in
                    Button {
                        activePass = i
                    } label: {
                        HStack {
                            Text("Passe \(i + 1) · \(PaintingPassKind.of(pass.compoundID).title)")
                            Spacer()
                            if i == activePass { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                }.onDelete { offsets in
                    treatment.passes.remove(atOffsets: offsets)
                    if treatment.passes.isEmpty { resizePasses(1) }
                    activePass = min(activePass, treatment.passes.count - 1)
                }
            }
        }
        if treatment.passes.indices.contains(activePass) {
            PaintingPassEditor(pass: $treatment.passes[activePass], rules: treatment.rules, index: activePass + 1)
        }
        Section {
            Button("Rajouter une autre passe", systemImage: "plus.circle") {
                resizePasses(treatment.passes.count + 1)
                activePass = treatment.passes.count - 1
            }
        }
        if let validation { Section { Text(validation).foregroundStyle(.red) } }
    }

    @ViewBuilder private func productEditor(_ product: Binding<PaintingProduct>) -> some View {
        if !products.products.isEmpty {
            Menu("Choisir dans mes peintures") {
                ForEach(products.products) { saved in
                    Button("\(saved.name) · \(number(saved.yieldM2PerL)) m²/L") {
                        product.wrappedValue.name = saved.name
                        product.wrappedValue.yieldM2PerL = saved.yieldM2PerL.rounded()
                    }.disabled(!(treatment.rules.yieldMin...treatment.rules.yieldMax).contains(saved.yieldM2PerL))
                }
            }
        }
        TextField("Nom de la peinture (facultatif)", text: product.name)
        TextField("Teinte (facultative)", text: product.tint)
        LabeledContent("Rendement", value: "\(number(product.wrappedValue.yieldM2PerL)) m²/L")
        Slider(value: product.yieldM2PerL, in: treatment.rules.yieldMin...treatment.rules.yieldMax, step: 1)
            .accessibilityLabel("Rendement de la peinture")
        Button("Enregistrer dans mes peintures", systemImage: "bookmark") {
            do { try products.save(product.wrappedValue); notice = "Peinture enregistrée. Vous pourrez la retrouver dans vos autres projets sur cet appareil." }
            catch { notice = error.localizedDescription }
        }.disabled(product.wrappedValue.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder private var quantities: some View {
        AtlantiqueSection("Quantités à prévoir") {
            ForEach(Array(supplies.enumerated()), id: \.offset) { _, item in
                LabeledContent(item.name, value: "\(number(PaintingCalculator.displayedQuantity(item.quantity))) \(item.unit)")
            }
            if let validation { Text(validation).foregroundStyle(.red) }
        }
        Section {
            Text("Réserve de \(number(treatment.rules.reservePercent)) % incluse sur tous les consommables. Les quantités affichées sont arrondies au dixième supérieur.")
            Text("Consommations indicatives : vérifiez les fiches des produits utilisés. Le ratissage partiel s’applique indépendamment à chaque passe.")
            Text(referenceMessage ?? "Bases Plaquisto Admin · \(treatment.rules.revision). Coefficients conservés avec cet ouvrage.")
        }.font(.footnote).foregroundStyle(.secondary)
    }
    private func resizePasses(_ count: Int) {
        if count < treatment.passes.count { treatment.passes = Array(treatment.passes.prefix(count)) }
        else if let compound = treatment.rules.compounds.first(where: { $0.id == "finition-poudre" }) ?? treatment.rules.compounds.first {
            while treatment.passes.count < count { treatment.passes.append(.init(compoundID: compound.id, thicknessMM: compound.thicknessDefault)) }
        }
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

private struct PaintingPassEditor: View {
    @Binding var pass: PaintingPass
    let rules: PaintingRules
    let index: Int
    private var compound: PaintingCompound? { rules.compounds.first(where: { $0.id == pass.compoundID }) }
    private var kind: PaintingPassKind { .of(pass.compoundID) }
    private var paste: Bool { pass.compoundID.hasSuffix("-pate") }
    private func select(_ kind: PaintingPassKind, paste: Bool) {
        let id = kind.rawValue + (paste ? "-pate" : "-poudre")
        guard rules.compounds.contains(where: { $0.id == id }) else { return }
        if kind != self.kind { pass.thicknessMM = kind.rangeMM.lowerBound }
        pass.compoundID = id
    }
    private func color(_ kind: PaintingPassKind) -> Color {
        switch kind { case .rebouchage: .red; case .charge: .green; case .finition: .blue }
    }
    var body: some View {
        AtlantiqueSection("Passe \(index)") {
            HStack(spacing: 8) {
                ForEach(PaintingPassKind.allCases) { choice in
                    Button { select(choice, paste: paste) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: choice == kind ? "checkmark.circle.fill" : "circle")
                            Text(choice.title).font(.caption.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1)
                        }.frame(maxWidth: .infinity).padding(.vertical, 16)
                            .foregroundStyle(color(choice))
                            .background(color(choice).opacity(choice == kind ? 0.18 : 0.07), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color(choice).opacity(choice == kind ? 1 : 0.15)))
                    }.buttonStyle(.plain).accessibilityAddTraits(choice == kind ? .isSelected : [])
                }
            }
            if let compound {
                LabeledContent("Épaisseur", value: "\((pass.thicknessMM / (kind == .rebouchage ? 10 : 1)).formatted(.number.precision(.fractionLength(0...1)))) \(kind == .rebouchage ? "cm" : "mm")")
                Slider(value: $pass.thicknessMM, in: kind.rangeMM, step: kind.stepMM)
                    .accessibilityLabel("Épaisseur passe \(index)")
                Text("\(compound.kgPerM2MM.formatted()) kg/m²/mm").font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Surface concernée", value: "\(Int(pass.surfacePercent)) %")
            Slider(value: $pass.surfacePercent, in: 1...100, step: 1).accessibilityLabel("Pourcentage passe \(index)")
            Picker("Présentation de l’enduit", selection: Binding(get: { paste }, set: { select(kind, paste: $0) })) {
                Text("En poudre").tag(false)
                Text("En pâte").tag(true)
            }.pickerStyle(.segmented)
        }
    }
}
