import SwiftUI

struct WallAngleToolView: View {
    var kind: WallAngleKind = .interior
    @State private var equalSide = 100.0
    @State private var oppositeSide = 0.0
    private var result: Result<WallAngleResult,Error> { Result { try WallAngleCalculator.calculate(equalSide:equalSide,oppositeSide:oppositeSide) } }
    var body: some View {
        Form {
            Section {
                WallAngleDiagram(kind:kind,angle:(try? result.get().interiorDegrees) ?? 90)
                    .frame(height:260)
                    .listRowInsets(EdgeInsets(top:12,leading:8,bottom:12,trailing:8))
            } header: { Text(kind.range) }
            footer: {
                Text(kind == .interior
                     ? "Mesurez la même distance L sur les deux murs, puis D entre les repères."
                     : "Prolongez les murs dans le vide (pointillés), puis mesurez entre les deux repères.")
            }
            Section {
                LayoutDimensionField(title:kind.equalSideTitle,millimetres:$equalSide,tint:.blue,unit:"cm",displayScale:1,showsDoneButton:false)
            } footer: {
                Text(kind == .interior
                     ? "Depuis l’angle, mesurez la même distance sur chacun des deux murs et faites vos repères."
                     : "Dans le vide, mesurez la même distance depuis le coin sur chacun des deux alignements prolongés.")
            }
            Section {
                LayoutDimensionField(title:"D · Distance entre les repères",millimetres:$oppositeSide,tint:.orange,unit:"cm",displayScale:1,showsDoneButton:false)
            } footer: {
                Text(kind == .interior
                     ? "Mesurez la ligne droite entre les deux repères, pas le long des murs."
                     : "Mesurez entre les deux repères dans la zone libre : cette ligne ne traverse aucun mur.")
            }
            Section("Résultat") {
                switch result {
                case .success(let angle):
                    VStack(spacing:6) {
                        Text(kind.title).font(.subheadline.weight(.semibold))
                        Text(WallAngleCalculator.formattedDegrees(angle.degrees(for:kind)))
                            .font(.system(size:34,weight:.bold,design:.rounded)).monospacedDigit()
                    }
                    .foregroundStyle(.teal).frame(maxWidth:.infinity).padding(.vertical,8)
                    .listRowBackground(Color.teal.opacity(0.08))
                case .failure(let error):
                    if oppositeSide == 0 && equalSide > 0 {
                        Text("Renseignez une distance D supérieure à 0 pour afficher l’angle.").foregroundStyle(.secondary)
                    } else { Label(error.localizedDescription,systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            Section {
                DisclosureGroup("Comment mesurer ?") {
                    Text(kind == .interior
                         ? "Depuis le coin, reportez la même distance L sur les deux murs, puis mesurez D entre les repères."
                         : "Alignez une règle ou une équerre sur chaque mur et prolongez sa direction au-delà du coin. Reportez la même distance L sur ces prolongements, puis mesurez D entre les repères. L’équerre sert de guide d’alignement, sans créer de perpendiculaire.")
                    Text("Gardez les deux repères à la même hauteur. Des repères plus éloignés améliorent la précision à erreur de mesure égale.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct WallAngleDiagram: View {
    let kind:WallAngleKind
    let angle:Double
    var body: some View {
        Canvas { context,size in
            let theta = angle * .pi/180
            let half = theta/2
            let isExterior = kind == .exterior
            // Fit both the real wall faces and the measurement triangle. The reference
            // face passes through O; masonry is placed exclusively on its solid side.
            let depth = 0.52
            let height = 66.0
            let length = min((size.width-76)/(2*max(sin(half),0.25)),
                             (size.height-78-height)/((isExterior ? 2 : 1)*depth*max(cos(half),0.35)),190)
            let wallRise = length*cos(half)*depth
            let low = isExterior ? -wallRise-height : -height
            let high = wallRise
            let origin = CGPoint(x:size.width/2,y:(size.height-low-high)/2)
            let leftAngle = isExterior ? -.pi/2-half : .pi/2+half
            let rightAngle = isExterior ? -.pi/2+half : .pi/2-half
            let arcRadius = min(48,length*0.38,length*cos(half)*0.7)
            func point(_ direction:Double,_ distance:Double) -> CGPoint {
                .init(x:origin.x+cos(direction)*distance,y:origin.y+sin(direction)*distance*depth)
            }
            let measuredLeft = point(isExterior ? rightAngle + .pi : leftAngle,length)
            let measuredRight = point(isExterior ? leftAngle + .pi : rightAngle,length)
            var triangle = Path()
            triangle.move(to:origin); triangle.addLine(to:measuredLeft); triangle.addLine(to:measuredRight); triangle.closeSubpath()
            context.fill(triangle,with:.color(.blue.opacity(0.045)))
            for (index,direction) in [leftAngle,rightAngle].enumerated() {
                let end = point(direction,length+9)
                let face = Path { path in
                    path.move(to:origin); path.addLine(to:end)
                    path.addLine(to:.init(x:end.x,y:end.y-height))
                    path.addLine(to:.init(x:origin.x,y:origin.y-height)); path.closeSubpath()
                }
                context.fill(face,with:.color(Color(.secondarySystemGroupedBackground)))
                context.fill(face,with:.color(.secondary.opacity(index == 0 ? 0.12 : 0.2)))
                context.drawLayer { wall in
                    wall.clip(to:face)
                    for row in 0..<3 {
                        let y = Double(row)*height/3
                        var joints = Path()
                        joints.move(to:.init(x:origin.x,y:origin.y-y))
                        joints.addLine(to:.init(x:end.x,y:end.y-y))
                        let step = 38.0/max(length,1)
                        for t in stride(from:row.isMultiple(of:2) ? step/2 : step,to:1,by:step) {
                            let x = origin.x+(end.x-origin.x)*t
                            let baseY = origin.y+(end.y-origin.y)*t-y
                            joints.move(to:.init(x:x,y:baseY)); joints.addLine(to:.init(x:x,y:baseY-height/3))
                        }
                        wall.stroke(joints,with:.color(.secondary.opacity(0.26)),lineWidth:0.7)
                    }
                }
                context.stroke(face,with:.color(.secondary.opacity(0.45)),lineWidth:0.9)
            }
            var cap = context
            cap.translateBy(x:origin.x,y:origin.y-height)
            cap.scaleBy(x:1,y:depth)
            if !isExterior { cap.rotate(by:.degrees(180)) }
            WallAngleMasonry.draw(context:&cap,origin:.zero,halfAngle:half,length:length+9,
                                  thickness:18,materialInside:isExterior)

            var measuredRays = Path()
            measuredRays.move(to:measuredLeft); measuredRays.addLine(to:origin); measuredRays.addLine(to:measuredRight)
            context.stroke(measuredRays,with:.color(.blue),style:.init(lineWidth:1.7,lineCap:.round,dash:isExterior ? [6,5] : []))
            var chord = Path(); chord.move(to:measuredLeft); chord.addLine(to:measuredRight)
            context.stroke(chord,with:.color(.orange),style:.init(lineWidth:2,lineCap:.round))
            for end in [measuredLeft,measuredRight] {
                context.fill(Path(ellipseIn:.init(x:end.x-3,y:end.y-3,width:6,height:6)),with:.color(.orange))
            }

            // Exterior: start on the REAL right face, sweep through the free lower
            // region and finish on the REAL left face (never on the extensions).
            let start = rightAngle
            let sweep = isExterior ? 2 * .pi-theta : theta
            let arc = WallAngleArc.path(center:origin,radius:arcRadius,startAngle:start,sweep:sweep,depth:depth)
            context.stroke(arc,with:.color(.teal),style:.init(lineWidth:2.5,lineCap:.round))
            func label(_ text:String,at p:CGPoint,color:Color) {
                let resolved = context.resolve(Text(text).font(.system(size:13,weight:.semibold)).foregroundStyle(color))
                let measured = resolved.measure(in:CGSize(width:size.width,height:30))
                let width = measured.width+10
                let p = CGPoint(x:max(width/2,min(size.width-width/2,p.x)),y:max(12,min(size.height-12,p.y)))
                context.fill(Path(roundedRect:.init(x:p.x-width/2,y:p.y-11,width:width,height:22),cornerRadius:5),with:.color(Color(.secondarySystemGroupedBackground).opacity(0.94)))
                context.draw(resolved,at:p)
            }
            // Values stay in the form; the drawing needs only the matching letters.
            label("L",at:midpoint(origin,measuredLeft,offset:.init(x:-25,y:0)),color:.blue)
            label("L",at:midpoint(origin,measuredRight,offset:.init(x:25,y:0)),color:.blue)
            label("D",at:.init(x:origin.x,y:measuredLeft.y+19),color:.orange)
            context.fill(Path(ellipseIn:.init(x:origin.x-2,y:origin.y-2,width:4,height:4)),with:.color(.blue))
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(kind == .interior
                            ? "Angle intérieur. Mesurez L sur chacun des deux murs, puis D entre les repères."
                            : "Angle extérieur. Prolongez l’alignement des murs dans le vide en suivant les pointillés, mesurez L sur chaque prolongement, puis D entre les deux repères.")
    }

    private func midpoint(_ a:CGPoint,_ b:CGPoint,offset:CGPoint) -> CGPoint {
        .init(x:(a.x+b.x)/2+offset.x,y:(a.y+b.y)/2+offset.y)
    }
}

/// A masonry band seen from above: mortar joints and two cavities per block.
/// The band sits behind the measured face so the accessible area remains clear.
private enum WallAngleMasonry {
    static func draw(context:inout GraphicsContext,origin:CGPoint,halfAngle:Double,length:Double,
                     thickness:Double,materialInside:Bool) {
        let thickness = min(thickness,length*sin(halfAngle)*0.38)
        guard thickness > 0 else { return }
        let side = materialInside ? 1.0 : -1.0
        let left = CGPoint(x:-sin(halfAngle),y:-cos(halfAngle))
        let right = CGPoint(x:sin(halfAngle),y:-cos(halfAngle))
        let normals = [CGPoint(x:side*cos(halfAngle),y:-side*sin(halfAngle)),
                       CGPoint(x:-side*cos(halfAngle),y:-side*sin(halfAngle))]
        func p(_ d:CGPoint,_ n:CGPoint,_ along:Double,_ across:Double) -> CGPoint {
            .init(x:origin.x+d.x*along+n.x*across,y:origin.y+d.y*along+n.y*across)
        }
        let miter = CGPoint(x:origin.x,y:origin.y-side*thickness/max(sin(halfAngle),0.000001))
        let vertices = [p(left,normals[0],length,0),origin,p(right,normals[1],length,0),
                        p(right,normals[1],length,thickness),miter,p(left,normals[0],length,thickness)]
        let wall = Path { path in
            path.move(to:vertices[0]); for point in vertices.dropFirst() { path.addLine(to:point) }; path.closeSubpath()
        }
        context.fill(wall,with:.color(.secondary.opacity(0.15)))
        context.drawLayer { layer in
            layer.clip(to:wall)
            for (index,direction) in [left,right].enumerated() {
                let normal = normals[index]
                let blockLength = max(16,thickness*1.7)
                for station in stride(from:0.0,to:length,by:blockLength) {
                    var joint = Path()
                    joint.move(to:p(direction,normal,station,0)); joint.addLine(to:p(direction,normal,station,thickness))
                    layer.stroke(joint,with:.color(.secondary.opacity(0.65)),lineWidth:0.9)
                    if thickness >= 10 {
                        for offset in [0.15,0.57] {
                            let start = station+blockLength*offset
                            let end = min(station+blockLength*(offset+0.28),length)
                            guard end > start else { continue }
                            let hole = Path { path in
                                path.move(to:p(direction,normal,start,thickness*0.28))
                                path.addLine(to:p(direction,normal,end,thickness*0.28))
                                path.addLine(to:p(direction,normal,end,thickness*0.72))
                                path.addLine(to:p(direction,normal,start,thickness*0.72)); path.closeSubpath()
                            }
                            layer.fill(hole,with:.color(.secondary.opacity(0.17)))
                            layer.stroke(hole,with:.color(.secondary.opacity(0.3)),lineWidth:0.6)
                        }
                    }
                }
            }
        }
        context.stroke(wall,with:.color(.secondary.opacity(0.85)),style:.init(lineWidth:1.1,lineJoin:.round))
    }
}

// Explicit sampling avoids clockwise/screen-coordinate ambiguity for the reflex arc.
private enum WallAngleArc {
    static func path(center:CGPoint,radius:Double,startAngle:Double,sweep:Double,depth:Double = 1) -> Path {
        return Path { path in
            for step in 0...72 {
                let a = startAngle+sweep*Double(step)/72
                let p = CGPoint(x:center.x+radius*cos(a),y:center.y+radius*sin(a)*depth)
                if step == 0 { path.move(to:p) } else { path.addLine(to:p) }
            }
        }
    }
}

struct WallAngleIcon: View {
    let kind: WallAngleKind
    var body: some View {
        Canvas { context,size in
            let unit = min(size.width,size.height)
            let origin = CGPoint(x:unit*0.50,y:unit*0.52)
            WallAngleMasonry.draw(context:&context,origin:origin,halfAngle:.pi/4,length:unit*0.43,
                                  thickness:unit*0.13,materialInside:kind == .exterior)
            if kind == .exterior {
                var extensions = Path()
                extensions.move(to:.init(x:origin.x+unit*0.22,y:origin.y+unit*0.26))
                extensions.addLine(to:origin)
                extensions.addLine(to:.init(x:origin.x-unit*0.22,y:origin.y+unit*0.26))
                context.stroke(extensions,with:.color(.blue),style:.init(lineWidth:1.5,lineCap:.round,dash:[3,2]))
            }
            let start = kind == .interior ? -.pi*0.75 : -.pi*0.25
            let sweep = kind == .interior ? .pi*0.5 : .pi*1.5
            let arc = WallAngleArc.path(center:origin,radius:unit*0.22,startAngle:start,sweep:sweep)
            context.stroke(arc,with:.color(.teal),style:.init(lineWidth:2.5,lineCap:.round))
        }
        .accessibilityHidden(true)
    }
}

struct ThermalToolView: View {
    @State private var thickness = 0.0
    @State private var lambda = 0.0
    @State private var resistance = 0.0

    private enum ValueKind: Equatable { case thickness, lambda, resistance }

    private var computedKind: ValueKind? {
        let filled = [thickness > 0, lambda > 0, resistance > 0].filter { $0 }.count
        guard filled == 2 else { return nil }
        if thickness <= 0 { return .thickness }
        if lambda <= 0 { return .lambda }
        return .resistance
    }

    private func computedValue(for kind: ValueKind) -> Double? {
        guard computedKind == kind else { return nil }
        switch kind {
        case .thickness: return ThermalCalculator.thickness(resistance: resistance, lambda: lambda)
        case .lambda: return ThermalCalculator.lambda(thicknessMM: thickness, resistance: resistance)
        case .resistance: return ThermalCalculator.resistance(thicknessMM: thickness, lambda: lambda)
        }
    }

    var body: some View {
        Form {
            Section {
                thermalRow(.thickness)
                thermalRow(.lambda)
                thermalRow(.resistance)
            } header: {
                Text("Données")
            } footer: {
                Text("Renseignez deux valeurs : la troisième est calculée automatiquement.")
            }
        }
        .navigationTitle("Résistance thermique")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Réinitialiser") { reset() } } }
    }

    private func reset() { thickness = 0; lambda = 0; resistance = 0 }

    @ViewBuilder
    private func thermalRow(_ kind: ValueKind) -> some View {
        if let value = computedValue(for: kind) {
            LabeledContent(title(for: kind), value: formatted(value, for: kind))
                .font(.headline)
                .foregroundStyle(.green)
        } else if kind == .lambda {
            Picker("Lambda λ", selection: $lambda) {
                Text("Sélectionner").tag(0.0)
                ForEach(stride(from: 0.030, through: 0.0401, by: 0.002).map { $0 }, id: \.self) { value in
                    Text(value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(3))))
                        .tag(value)
                }
            }
        } else if kind == .thickness {
            ToolNumberField(title: "Épaisseur", unit: "mm", value: $thickness)
        } else {
            ToolNumberField(title: "Résistance R", unit: "m²·K/W", value: $resistance)
        }
    }

    private func title(for kind: ValueKind) -> String {
        switch kind {
        case .thickness: "Épaisseur"
        case .lambda: "Lambda λ"
        case .resistance: "Résistance R"
        }
    }

    private func formatted(_ value: Double, for kind: ValueKind) -> String {
        switch kind {
        case .thickness:
            value.formatted(.number.precision(.fractionLength(0...1))) + " mm"
        case .lambda:
            value.formatted(.number.precision(.fractionLength(3))) + " W/(m·K)"
        case .resistance:
            value.formatted(.number.precision(.fractionLength(2))) + " m²·K/W"
        }
    }
}

struct VATToolView: View {
    @State private var direction = VATDirection.netToGross
    @State private var amount = 0.0
    @State private var rate = 20.0

    private var result: VATResult? {
        VATCalculator.calculate(amount: Decimal(amount), rate: Decimal(rate), direction: direction)
    }

    var body: some View {
        Form {
            Section {
                Picker("Sens", selection: $direction) { ForEach(VATDirection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            }
            Section("Montant") {
                ToolNumberField(title: direction == .netToGross ? "Montant HT" : "Montant TTC", unit: "€", value: $amount)
                Picker("Taux de TVA", selection: $rate) {
                    Text("5,5 %").tag(5.5); Text("10 %").tag(10.0); Text("20 %").tag(20.0)
                }
                .pickerStyle(.segmented)
            }
            if let result {
                Section("Résultat") {
                    LabeledContent("Montant HT", value: currency(result.net))
                    LabeledContent("TVA", value: currency(result.tax))
                    LabeledContent("Montant TTC", value: currency(result.gross)).font(.headline)
                }
            }
        }
        .navigationTitle("Calcul de TVA")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Réinitialiser") { amount = 0; rate = 20; direction = .netToGross } } }
    }

    private func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }
}

struct ArchTemplateToolView: View {
    @State private var kind = ArchKind.rounded
    @State private var width = 120.0
    @State private var rise = 40.0
    @State private var spacing = 10.0
    @State private var xFromCenter = false

    private var effectiveRise: Double { kind == .semicircle ? width / 2 : rise }
    private var points: [ArchPoint] { ArchCalculator.points(kind: kind, width: width, rise: rise, spacing: spacing) }

    var body: some View {
        Form {
            Section("Forme") {
                Picker("Type d’arche", selection: $kind) { ForEach(ArchKind.allCases) { Text($0.rawValue).tag($0) } }
                ToolNumberField(title: "Largeur", unit: "cm", value: $width)
                ToolNumberField(title: "Flèche", unit: "cm", value: $rise).disabled(kind == .semicircle)
                if kind == .semicircle { LabeledContent("Flèche imposée", value: format(width / 2) + " cm") }
                Picker("Pas des points", selection: $spacing) {
                    ForEach([5.0, 10, 15, 20], id: \.self) { Text("\(Int($0)) cm").tag($0) }
                }
            }
            Section("Aperçu") {
                ArchDiagram(points: points, width: width, rise: effectiveRise).frame(height: 190)
            }
            Section {
                Toggle("Abscisse depuis le centre", isOn: $xFromCenter)
            }
            Section("Table de traçage") {
                ForEach(points) { point in
                    LabeledContent("x = \(format(xFromCenter ? point.x - width / 2 : point.x)) cm", value: "y = \(format(point.y)) cm")
                }
            }
        }
        .navigationTitle("Gabarit d’arche")
    }

    private func format(_ value: Double) -> String { value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))) }
}

private struct ArchDiagram: View {
    let points: [ArchPoint]
    let width: Double
    let rise: Double

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard points.count > 1, width > 0, rise > 0 else { return }
                let pad = 18.0, usableWidth = size.width - pad * 2, usableHeight = size.height - pad * 2
                func mapped(_ point: ArchPoint) -> CGPoint {
                    CGPoint(x: pad + point.x / width * usableWidth, y: size.height - pad - point.y / rise * usableHeight)
                }
                var curve = Path(); curve.move(to: mapped(points[0]))
                points.dropFirst().forEach { curve.addLine(to: mapped($0)) }
                context.stroke(curve, with: .color(.accentColor), lineWidth: 3)
                var baseline = Path(); baseline.move(to: CGPoint(x: pad, y: size.height - pad)); baseline.addLine(to: CGPoint(x: size.width - pad, y: size.height - pad))
                context.stroke(baseline, with: .color(.secondary), style: .init(lineWidth: 1, dash: [5]))
                for point in points { context.fill(Path(ellipseIn: CGRect(x: mapped(point).x - 3, y: mapped(point).y - 3, width: 6, height: 6)), with: .color(.orange)) }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
