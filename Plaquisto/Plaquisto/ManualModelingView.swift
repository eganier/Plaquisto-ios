import SwiftUI
import UIKit

enum ModelingIcon {
    /// An open room (floor and two walls), not a closed cube.
    static let image: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 28, height: 27)).image { context in
            let path = UIBezierPath()
            func line(_ points: [CGPoint]) {
                path.move(to: points[0]); for point in points.dropFirst() { path.addLine(to: point) }
            }
            line([.init(x: 2, y: 7), .init(x: 14, y: 2), .init(x: 26, y: 7), .init(x: 26, y: 20), .init(x: 14, y: 25), .init(x: 2, y: 20), .init(x: 2, y: 7)])
            line([.init(x: 14, y: 2), .init(x: 14, y: 15), .init(x: 2, y: 20)])
            line([.init(x: 14, y: 15), .init(x: 26, y: 20)])
            UIColor.black.setStroke(); path.lineWidth = 1.8; path.lineJoinStyle = .round; path.lineCapStyle = .round; path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }()
}

struct ManualModelingView: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    let targetProjectID: UUID?
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var contour: Surface2D?
    @State private var editingContour = false
    @State private var commonHeightCM = 250.0
    @State private var differentHeights = false
    @State private var heights: [Int: Double] = [:]
    @State private var heightTarget: HeightTarget?
    @State private var heightText = ""
    @State private var askingHeight = false
    @State private var error: String?
    @State private var room: PlaquistoRoomModel?
    @State private var name = "Ma pièce"
    @State private var projectID: UUID?
    @State private var projectName = ""
    @State private var address = ""
    @State private var savedDraft: ScanCampaignDraft?
    @State private var openingWorkspace = false
    @State private var cameraReset = UUID()
    @State private var confirmingClose = false
    @State private var startedBookDrawing = false

    private struct HeightTarget {
        var indices: [Int]
        var label: String
    }
    init(targetProjectID: UUID? = nil) {
        self.targetProjectID = targetProjectID
        _projectID = State(initialValue: targetProjectID)
    }
    private var effectiveHeights: [Int: Double] { differentHeights ? heights : [:] }
    private var plane: RoomPlane? {
        guard let contour else { return nil }
        return try? ManualRoomModel.plane(contour: contour.contour, commonHeight: commonHeightCM/100, constraints: effectiveHeights)
    }
    var body: some View {
        NavigationStack {
            AtlantiqueForm(bookLayout: true) {
                if !atlantique { Section {
                    Text("Étape \(step+1) sur 3 · \(["Dessiner le sol", "Définir les hauteurs", "Enregistrer le modèle"][step])")
                        .font(.subheadline).foregroundStyle(.secondary)
                } }
                if step == 0 { floorSection }
                if step == 1 { heightSection }
                if step == 2 { saveSection }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !atlantique { Section {
                    Button(step == 2 ? "Enregistrer et ouvrir en 3D" : "Continuer") { advance() }
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        .atlantiqueActionStyle()
                        .disabled(savedDraft != nil || contour == nil || plane == nil || (step == 2 && (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (projectID == nil && projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))))
                }.listRowBackground(Color.clear) }
            }
            .navigationTitle(["Dessiner ma pièce", "Hauteurs", "Mon modèle 3D"][step])
            .navigationBarTitleDisplayMode(.inline)
            .atlantiqueFormPage(["Dessiner le sol", "Définir les hauteurs", "Enregistrer le modèle"][step])
            .safeAreaInset(edge: .top, spacing: 0) {
                if atlantique {
                    Text("\(step + 1) / 3 · \(["Contour et dimensions", "Hauteurs sous plafond", "Enregistrer le modèle"][step])")
                        .font(Atlantique.Typography.caption).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 12)
                        .background(Atlantique.Palette.blue)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if atlantique {
                    HStack(spacing: 12) {
                        Button("Retour", action: goBack).atlantiqueActionStyle(.secondary).frame(width: 112)
                        Button(step == 2 ? "Enregistrer" : "Continuer", action: advance)
                            .atlantiqueActionStyle()
                            .disabled(savedDraft != nil || contour == nil || plane == nil || (step == 2 && (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (projectID == nil && projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))))
                    }.padding(20).background(Atlantique.Palette.blue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "Fermer" : "Retour", action: goBack).atlantiqueToolbarAction()
                }.atlantiqueToolbarBackground(atlantique)
            }
            .onAppear {
                if atlantique && !startedBookDrawing && contour == nil {
                    startedBookDrawing = true; editingContour = true
                }
            }
            .interactiveDismissDisabled(contour != nil)
            .confirmationDialog("Quitter sans enregistrer ce dessin ?", isPresented: $confirmingClose, titleVisibility: .visible) {
                Button("Abandonner le dessin", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $editingContour) {
                LayoutManualContourEditor(surface: contour, kind: .ceiling, title: "Dessiner le sol", allowsLayingOffset: false) { updated in
                    // Vertex indices no longer identify the same corners after an edit.
                    if contour?.contour != updated.contour { heights = [:]; differentHeights = false }
                    contour = updated; error = nil
                    if atlantique { step = 1; heightTarget = nil }
                }
            }
            .alert(heightTarget?.label ?? "Hauteur", isPresented: $askingHeight) {
                TextField("Hauteur en cm", text: $heightText).keyboardType(.decimalPad)
                Button("Annuler", role: .cancel) {}
                Button("Appliquer") { applyHeight() }
                if let target = heightTarget, target.indices.contains(where: { heights[$0] != nil }) {
                    Button("Laisser le plafond calculer") {
                        var next = heights; target.indices.forEach { next.removeValue(forKey: $0) }; accept(next)
                    }
                }
            } message: { Text("Hauteur sous plafond en centimètres.") }
            .navigationDestination(isPresented: $openingWorkspace) {
                if let savedDraft {
                    ScannerCampaignWorkspaceView(draft: savedDraft)
                        .navigationBarBackButtonHidden()
                        .toolbar { if !atlantique { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } } }
                }
            }
        }
    }
    private func goBack() {
        if step > 0 {
            step -= 1; error = nil
            if atlantique && step == 0 { editingContour = true }
        } else if contour != nil { confirmingClose = true }
        else { dismiss() }
    }
    @ViewBuilder private var floorSection: some View {
        Section {
            if !atlantique { Text("Tracez le sol de votre pièce, puis renseignez ses dimensions. Les murs et le plafond seront créés à partir de ce contour.") }
            if let contour {
                ManualHeightPlan(contour: contour.contour, plane: nil, constraints: [:], interactive: false, onVertex: { _ in }, onEdge: { _ in })
                    .frame(height: 260)
                LabeledContent("Surface au sol", value: "\((abs(LayoutGeometry.area(contour.contour))/1_000_000).formatted(.number.precision(.fractionLength(2)))) m²")
            }
            Button { editingContour = true } label: {
                Label(contour == nil ? "Dessiner le sol" : "Modifier le contour et les dimensions", systemImage: "pencil.and.outline")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }.buttonStyle(.bordered)
            if contour == nil {
                Button("Partir d’un rectangle") {
                    contour = Surface2D(name: "Sol", kind: .ceiling,
                        contour: [.init(x: 0, y: 0), .init(x: 4000, y: 0), .init(x: 4000, y: 3000), .init(x: 0, y: 3000)], provenance: "preset")
                    editingContour = true
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
    @ViewBuilder private var heightSection: some View {
        if !differentHeights {
            Section {
                if atlantique {
                    ToolNumberField(title: "Hauteur commune", unit: "cm", value: $commonHeightCM)
                } else {
                    HStack {
                        Text("Hauteur commune")
                        Spacer()
                        TextField("250", value: $commonHeightCM, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        Text("cm").foregroundStyle(.secondary)
                    }
                }
            }
        }
        Section {
            Toggle("Hauteurs différentes", isOn: $differentHeights)
                .onChange(of: differentHeights) { _, _ in error = nil; heightTarget = nil }
        }
        if let contour {
            Section {
                ManualHeightPlan(contour: contour.contour, plane: plane, constraints: effectiveHeights, interactive: differentHeights, selectedIndices: heightTarget?.indices ?? [],
                    onVertex: { i in choose(.init(indices: [i], label: "Angle \(vertexName(i))")) },
                    onEdge: { i in choose(.init(indices: [i, (i+1)%contour.contour.count], label: "Mur \(i+1)")) })
                    .frame(height: atlantique ? 270 : 340)
                if differentHeights && !atlantique {
                    Text("Touchez un angle ou un mur. Deux hauteurs différentes créent un rampant ; les autres hauteurs suivent le même plan.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !heights.isEmpty { Button("Réinitialiser les hauteurs") { heights = [:]; error = nil } }
                }
            }
            if atlantique, differentHeights, let target = heightTarget {
                Section {
                    Text(target.label).font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                    HStack {
                        PlaquistoNumericField(text: $heightText, onEditingChanged: { editing in if !editing { applyHeight() } }, onValidate: { applyHeight() })
                            .accessibilityLabel("Hauteur de " + target.label)
                        Text("cm").font(Atlantique.Typography.caption).foregroundStyle(Atlantique.Palette.muted)
                    }.frame(minHeight: 44)
                }
            }
        }
        if plane == nil { Text("Vérifiez les hauteurs saisies (20 à 2 000 cm).").foregroundStyle(.red) }
    }
    @ViewBuilder private var saveSection: some View {
        if let room {
            Section {
                RoomDomainScene(room: room, selected: .constant(nil), ceilingMode: 1, showFloor: true, topView: false, cameraReset: cameraReset)
                    .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16))
                if !atlantique { Text("Ajoutez ensuite portes, fenêtres, cloisons et poteaux dans « Modifier le plan ». Les plafonds restent modifiables.")
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        AtlantiqueSection("Nom du relevé") { TextField("Nom", text: $name) }
        AtlantiqueSection("Projet de destination") {
            AtlantiquePicker("Projet", selection: $projectID) {
                Text("Nouveau projet").tag(UUID?.none)
                ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
            }
            if projectID == nil {
                TextField("Nom du projet", text: $projectName)
                TextField("Adresse (facultative)", text: $address)
            }
        }
    }
    private func choose(_ target: HeightTarget) {
        if atlantique && heightTarget != nil && !applyHeight() { return }
        guard let contour, let i = target.indices.first else { return }
        let p = ManualRoomModel.floorPoints(contour.contour)[i]
        heightText = ((plane?.height(x: p.x, z: p.z) ?? commonHeightCM/100)*100).formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        heightTarget = target; askingHeight = !atlantique
    }
    @discardableResult private func applyHeight() -> Bool {
        guard let target = heightTarget, let cm = Double(heightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Saisissez une hauteur en centimètres."; return false
        }
        var next = heights; target.indices.forEach { next[$0] = cm/100 }; accept(next)
        return error == nil
    }
    private func accept(_ next: [Int: Double]) {
        guard let contour else { return }
        do {
            _ = try ManualRoomModel.plane(contour: contour.contour, commonHeight: commonHeightCM/100, constraints: next)
            heights = next; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func advance() {
        guard let contour else { return }
        if atlantique && step == 1 && differentHeights && heightTarget != nil && !applyHeight() { return }
        do {
            error = nil
            if step == 0 { step = 1; return }
            if step == 1 {
                room = try ManualRoomModel.room(contour: contour.contour, commonHeight: commonHeightCM/100, constraints: effectiveHeights, name: name)
                step = 2; return
            }
            guard savedDraft == nil, var room else { return }
            room.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let draft = try ManualRoomModel.campaign(room: room)
            // Commit project + survey atomically. The existing workspace then owns
            // all subsequent edits; no duplicate scan or synthetic location is made.
            try store.saveScanCampaign(draft, projectID: projectID, newProjectName: projectName,
                surveyName: room.name!, newProjectAddress: address)
            savedDraft = draft; openingWorkspace = true
        } catch { self.error = error.localizedDescription }
    }
}

private struct ManualHeightPlan: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    let contour: [LayoutPoint]
    let plane: RoomPlane?
    let constraints: [Int: Double]
    let interactive: Bool
    var selectedIndices: [Int] = []
    let onVertex: (Int) -> Void
    let onEdge: (Int) -> Void
    var body: some View {
        GeometryReader { geometry in
            let bounds = LayoutBounds(points: contour)
            let scale = min(max(1, geometry.size.width-100)/max(1, bounds.width), max(1, geometry.size.height-100)/max(1, bounds.height))
            // Match the contour editor's Y-up drawing; changing step must not mirror the room.
            let points = contour.map { CGPoint(x: geometry.size.width/2+($0.x-bounds.center.x)*scale, y: geometry.size.height/2-($0.y-bounds.center.y)*scale) }
            ZStack {
                Path { path in
                    if let first = points.first { path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath() }
                }.fill(atlantique ? Atlantique.Palette.paper : Color.blue.opacity(0.08))
                ForEach(points.indices, id: \.self) { i in
                    let a = points[i], b = points[(i+1)%points.count]
                    let selected = selectedIndices.contains(i) && selectedIndices.contains((i + 1) % points.count)
                    Path { $0.move(to: a); $0.addLine(to: b) }.stroke(selected ? Atlantique.Palette.orange : atlantique ? Atlantique.Palette.ink : .blue, lineWidth: selected ? 3 : 1.5)
                        .contentShape(Path { $0.move(to: a); $0.addLine(to: b) }.strokedPath(.init(lineWidth: 30)))
                        .onTapGesture { if interactive { onEdge(i) } }
                    if interactive {
                        Button { onEdge(i) } label: {
                            Text("Mur \(i+1)").font(.caption.bold()).padding(8).background(.regularMaterial, in: Capsule())
                        }.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                            .position(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
                    }
                }
                ForEach(points.indices, id: \.self) { i in
                    Button { onVertex(i) } label: {
                        VStack(spacing: 2) {
                            Text(vertexName(i)).font(.caption.bold())
                            if let plane {
                                Text("\((plane.height(x: contour[i].x/1000, z: -contour[i].y/1000)*100).formatted(.number.precision(.fractionLength(0...1)))) cm")
                                    .font(.caption2.monospacedDigit())
                            }
                        }.padding(5).foregroundStyle(selectedIndices.contains(i) || constraints[i] != nil ? Atlantique.Palette.actionInk : atlantique ? Atlantique.Palette.ink : Color.primary)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!interactive).position(points[i])
                        .accessibilityLabel("Angle \(vertexName(i)), modifier la hauteur")
                }
            }
        }
    }
}
