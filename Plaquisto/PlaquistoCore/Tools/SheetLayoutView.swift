import SwiftUI

struct LayoutViewport {
    let bounds: LayoutBounds
    let size: CGSize
    let zoom: Double
    let pan: CGSize
    var rotation: Double = 0
    var pivot: LayoutPoint? = nil
    var fittingSize: CGSize? = nil
    var mirrored = false
    var scale: Double {
        let fit = fittingSize ?? size
        return min(max(1, fit.width - 70) / max(100, bounds.width), max(1, fit.height - 70) / max(100, bounds.height)) * zoom
    }
    var rotationPivot: LayoutPoint { pivot ?? bounds.center }
    /// Fit into an editing-sized area, even when View has more vertical space.
    /// Keeping this fit afterwards prevents the mode controls from changing zoom.
    static func initialEditingSize(_ size: CGSize) -> CGSize {
        .init(width: size.width, height: min(size.height, max(180, size.width * 0.95)))
    }
    func upperFramingPan(contour: [LayoutPoint]) -> CGSize {
        guard let top = contour.map({ screen($0).y }).min() else { return .zero }
        let topMargin = min(60, size.height * 0.15)
        return .init(width: pan.width, height: pan.height + topMargin - top)
    }
    static func rotated(_ p: LayoutPoint, by angle: Double) -> LayoutPoint {
        .init(x: p.x * cos(angle) - p.y * sin(angle), y: p.x * sin(angle) + p.y * cos(angle))
    }
    func screen(_ p: LayoutPoint) -> CGPoint {
        let r = rotationPivot + Self.rotated(p - rotationPivot, by: rotation)
        return .init(x: size.width / 2 + pan.width + (r.x - bounds.center.x) * scale * (mirrored ? -1 : 1),
                     y: size.height / 2 + pan.height - (r.y - bounds.center.y) * scale)
    }
    func world(_ p: CGPoint) -> LayoutPoint {
        let rotatedPoint = LayoutPoint(x: bounds.center.x + (p.x - size.width / 2 - pan.width) / scale * (mirrored ? -1 : 1),
                                       y: bounds.center.y - (p.y - size.height / 2 - pan.height) / scale)
        return rotationPivot + Self.rotated(rotatedPoint - rotationPivot, by: -rotation)
    }
    func worldDelta(_ translation: CGSize) -> LayoutPoint {
        Self.rotated(.init(x: translation.width / scale * (mirrored ? -1 : 1), y: -translation.height / scale), by: -rotation)
    }
    /// Keep the world point under the pinch anchor at the same screen position.
    /// Includes the existing pan and works identically in rotated/mirrored views.
    func zoomed(to nextZoom: Double, anchor: CGPoint) -> Self {
        guard nextZoom.isFinite, nextZoom > 0, zoom.isFinite, zoom > 0 else { return self }
        let ratio = nextZoom / zoom
        return .init(bounds:bounds,size:size,zoom:nextZoom,
            pan:.init(width:anchor.x-size.width/2-(anchor.x-size.width/2-pan.width)*ratio,
                      height:anchor.y-size.height/2-(anchor.y-size.height/2-pan.height)*ratio),
            rotation:rotation,pivot:pivot,fittingSize:fittingSize,mirrored:mirrored)
    }
    /// Keeps a visible part of the transformed contour inside the canvas while
    /// leaving the camera free to pan in every direction. This only constrains
    /// the view; model coordinates and snapping axes are untouched.
    func constrainedPan(_ candidate: CGSize, contour: [LayoutPoint], minimumVisible: Double = 50) -> CGSize {
        guard !contour.isEmpty, size.width > 2, size.height > 2 else { return .zero }
        let points = contour.map { point -> CGPoint in
            let rotated = rotationPivot + Self.rotated(point - rotationPivot, by: rotation)
            return .init(x: size.width / 2 + (rotated.x - bounds.center.x) * scale * (mirrored ? -1 : 1),
                         y: size.height / 2 - (rotated.y - bounds.center.y) * scale)
        }
        let visibleX = min(minimumVisible, max(1, size.width / 2 - 1))
        let visibleY = min(minimumVisible, max(1, size.height / 2 - 1))
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        return .init(
            width: min(size.width - visibleX - minX, max(visibleX - maxX, candidate.width)),
            height: min(size.height - visibleY - minY, max(visibleY - maxY, candidate.height))
        )
    }
    static func geometricCenter(_ points: [LayoutPoint]) -> LayoutPoint {
        guard points.count >= 3 else { return LayoutBounds(points: points).center }
        var doubledArea = 0.0, x = 0.0, y = 0.0
        for edge in LayoutGeometry.edges(points) {
            let cross = edge.a.x * edge.b.y - edge.b.x * edge.a.y
            doubledArea += cross
            x += (edge.a.x + edge.b.x) * cross
            y += (edge.a.y + edge.b.y) * cross
        }
        guard abs(doubledArea) > 0.000_001 else { return LayoutBounds(points: points).center }
        return .init(x: x / (3 * doubledArea), y: y / (3 * doubledArea))
    }
    static func fittedBounds(_ points: [LayoutPoint], rotation: Double, pivot: LayoutPoint? = nil) -> LayoutBounds {
        let center = pivot ?? geometricCenter(points)
        let relative = points.map { rotated($0 - center, by: rotation) }
        let halfWidth = relative.map { abs($0.x) }.max() ?? 50
        let halfHeight = relative.map { abs($0.y) }.max() ?? 50
        let margin = max(halfWidth * 2, halfHeight * 2) * 0.2
        let half = LayoutPoint(x: max(50, halfWidth + margin), y: max(50, halfHeight + margin))
        return .init(min: center - half, max: center + half)
    }
    /// View-only alignment. Geometry, measured angles and layer offsets stay intact.
    static func horizontalBaseRotation(_ contour:[LayoutPoint]) -> Double {
        guard let edge = LayoutStrokeBeautifier.groundEdge(contour) else { return 0 }
        let vector = edge.b-edge.a
        return -atan2(vector.y,vector.x)
    }
    /// Camera-only cycling: do not change the boards' or framing's reference wall.
    static func nextHorizontalEdge(_ contour:[LayoutPoint], after current:Int?) -> (index:Int, angle:Double)? {
        guard contour.count >= 3 else { return nil }
        let start = current.flatMap { contour.indices.contains($0) ? ($0+1)%contour.count : nil } ?? 0
        for offset in contour.indices {
            let index = (start+offset)%contour.count
            let vector = contour[(index+1)%contour.count]-contour[index]
            guard vector.x.isFinite, vector.y.isFinite, vector.length>0.001 else { continue }
            return (index,-atan2(vector.y,vector.x))
        }
        return nil
    }
    static func initialCeilingAlignment(_ contour:[LayoutPoint], referenceEdge:Int?) -> (index:Int, angle:Double)? {
        let candidates = contour.indices.compactMap { index -> (index:Int,angle:Double,ratio:Double)? in
            guard let edge=nextHorizontalEdge(contour,after:(index+contour.count-1)%contour.count), edge.index == index else { return nil }
            let bounds=LayoutBounds(points:contour.map { rotated($0,by:edge.angle) })
            return (index,edge.angle,bounds.width/max(0.001,bounds.height))
        }
        // Prefer the board reference when it already gives a landscape view.
        // Otherwise choose the edge that makes the ceiling widest on screen.
        if let preferred=candidates.first(where:{$0.index == referenceEdge && $0.ratio >= 1-0.000001}) {
            return (preferred.index,preferred.angle)
        }
        guard let best=candidates.max(by:{$0.ratio < $1.ratio}) else { return nil }
        return (best.index,best.angle)
    }
    /// Camera-only detent: acquire within 2.5°, release after 5° to avoid flicker.
    static func snappedRotation(_ candidate: Double, contour: [LayoutPoint], latched: Double?) -> (angle: Double, latch: Double?) {
        if let latched, abs(candidate - latched) <= 5 * .pi / 180 { return (latched, latched) }
        let targets = LayoutGeometry.edges(contour).filter { ($0.b - $0.a).length > 1 }.map { edge in
            let d = edge.b - edge.a, direction = atan2(d.y, d.x)
            return ((candidate + direction) / (.pi / 2)).rounded() * (.pi / 2) - direction
        }
        if let target = targets.min(by: { abs($0-candidate) < abs($1-candidate) }), abs(target-candidate) <= 2.5 * .pi / 180 {
            return (target, target)
        }
        return (candidate, nil)
    }
}
func layoutPath(_ loop: [LayoutPoint], transform: LayoutViewport) -> Path {
    var path = Path()
    guard let first = loop.first else { return path }
    path.move(to: transform.screen(first))
    for p in loop.dropFirst() { path.addLine(to: transform.screen(p)) }
    path.closeSubpath(); return path
}

struct LayoutVisibilityIcon: View {
    enum Kind { case sheet, angle, framing, opening, electrical }
    let kind:Kind
    let state:LayoutVisibilityState
    var modern = false
    var body:some View {
        Canvas { context,size in
            let drawingWidth = state == .dimensioned && !modern ? 56.0 : 40.0
            context.translateBy(x:(size.width-drawingWidth)/2,y:(size.height-40)/2)
            let hidden = state == .hidden
            let color = modern ? (hidden ? Color.secondary.opacity(0.55) : Color.blue) : Color.primary.opacity(hidden ? 0.32 : 0.9)
            func line(_ points:[CGPoint],closed:Bool = false,fill:Bool = false) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to:first)
                for p in points.dropFirst() { path.addLine(to:p) }
                if closed { path.closeSubpath() }
                if fill && !hidden { context.fill(path,with:.color(.secondary.opacity(0.15))) }
                context.stroke(path,with:.color(color),style:.init(lineWidth:1.7,lineCap:.round,lineJoin:.round,dash:hidden && !modern ? [2,3] : []))
            }
            switch kind {
            case .sheet:
                line([.init(x:7,y:5),.init(x:31,y:5),.init(x:31,y:33),.init(x:7,y:33)],closed:true,fill:true)
                if !hidden { line([.init(x:10,y:9),.init(x:10,y:29)]) }
            case .angle:
                line([.init(x:10,y:5),.init(x:10,y:33),.init(x:36,y:33)])
                if !hidden {
                    var arc = Path(); arc.addArc(center:.init(x:10,y:33),radius:13,startAngle:.degrees(-90),endAngle:.degrees(0),clockwise:false)
                    context.stroke(arc,with:.color(color),lineWidth:1)
                    context.draw(Text("α").font(.system(size:15,weight:.medium)).foregroundStyle(color),at:.init(x:30,y:17))
                }
            case .framing:
                for x in [10.0,20.0,30.0] {
                    line([.init(x:x,y:5),.init(x:x,y:35)])
                }
            case .opening:
                if modern {
                    line([.init(x:7,y:3),.init(x:33,y:3),.init(x:33,y:37),.init(x:7,y:37)],closed:true)
                    line([.init(x:14,y:14),.init(x:26,y:14),.init(x:26,y:26),.init(x:14,y:26)],closed:true)
                } else {
                    line([.init(x:4,y:3),.init(x:36,y:3),.init(x:36,y:36),.init(x:4,y:36)],closed:true)
                    line([.init(x:8,y:7),.init(x:32,y:7),.init(x:32,y:32),.init(x:8,y:32)],closed:true)
                }
            case .electrical:
                line([.init(x:25,y:3),.init(x:8,y:22),.init(x:19,y:22),.init(x:14,y:37),.init(x:33,y:15),.init(x:22,y:15)],closed:true,fill:true)
            }
            if state == .dimensioned && !modern {
                context.translateBy(x:7,y:0)
                line([.init(x:45,y:5),.init(x:45,y:34)])
                line([.init(x:42,y:8),.init(x:45,y:5),.init(x:48,y:8)])
                line([.init(x:42,y:31),.init(x:45,y:34),.init(x:48,y:31)])
            }
        }.accessibilityHidden(true)
    }
}

/// Unfilled, consistent outlines for the Lab visibility controls.
struct LayoutLabVisibilityIcon: View {
    enum Kind: CaseIterable { case ruler, sheet, framing, opening, electrical }
    let kind: Kind
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.translateBy(x:(size.width-40)/2,y:(size.height-40)/2)
            let stroke = StrokeStyle(lineWidth:2.4,lineCap:.round,lineJoin:.round)
            func line(_ points:[CGPoint], closed:Bool = false) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to:first)
                for point in points.dropFirst() { path.addLine(to:point) }
                if closed { path.closeSubpath() }
                context.stroke(path,with:.color(color),style:stroke)
            }
            switch kind {
            case .ruler:
                context.translateBy(x:20,y:20)
                context.rotate(by:.degrees(45))
                context.stroke(Path(roundedRect:CGRect(x:-18,y:-7,width:36,height:14),cornerRadius:2.5),with:.color(color),style:stroke)
                for (index,x) in [-10.0,-3,4,11].enumerated() {
                    line([.init(x:x,y:-7),.init(x:x,y:index.isMultiple(of:2) ? -1 : -3)])
                }
            case .sheet, .opening:
                context.stroke(Path(roundedRect:CGRect(x:10,y:3,width:20,height:34),cornerRadius:2.5),with:.color(color),style:stroke)
                if kind == .opening {
                    context.stroke(Path(roundedRect:CGRect(x:14,y:14,width:12,height:12),cornerRadius:0.8),with:.color(color),lineWidth:1.4)
                }
            case .framing:
                for x in [9.0,20,31] { line([.init(x:x,y:8),.init(x:x,y:32)]) }
            case .electrical:
                line([.init(x:27,y:3),.init(x:7,y:23),.init(x:21,y:23),.init(x:14,y:37),.init(x:34,y:16),.init(x:21,y:16)],closed:true)
            }
        }.accessibilityHidden(true)
    }
}

/// Fixed columns prevent either action moving when its label changes with the tool.
struct LayoutLabAlignmentActions: View {
    var framingMode: Bool
    var isOptimizing = false
    var optimizeDisabled = false
    var alignDisabled = false
    var showsAlignment = true
    var height: CGFloat = 44
    var optimize: () -> Void
    var align: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing:8) {
                action(width:(geometry.size.width-8)*0.34,disabled:optimizeDisabled,perform:optimize) {
                    Label(isOptimizing ? "Optimisation…" : "Optimiser",systemImage:"sparkles")
                }
                action(width:(geometry.size.width-8)*0.66,disabled:alignDisabled,perform:align) {
                    Text(framingMode ? "Caler les plaques sur l’ossature" : "Caler les ossatures sur les plaques")
                }.opacity(showsAlignment ? 1 : 0).allowsHitTesting(showsAlignment).accessibilityHidden(!showsAlignment)
            }
        }.frame(height:height)
    }

    private func action<Content:View>(width:CGFloat,disabled:Bool,perform:@escaping ()->Void,@ViewBuilder label:()->Content) -> some View {
        Button(action:perform) {
            label().font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
                .padding(.horizontal,8).frame(width:width,height:height)
                .foregroundStyle(Color.accentColor.opacity(disabled ? 0.4 : 1))
                .background(Color.accentColor.opacity(disabled ? 0.06 : 0.14),in:Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(disabled)
    }
}

/// Shared presentation only: millimetres here never change the quantity model.
enum LayoutPreciseStyle {
    static let profileWidthMM = 50.0
    static let edgeWidth = 1.6
    static let transitionDuration = 0.5
    static let ink = Color(red:0.26,green:0.34,blue:0.39)
    static let steel = Color(red:0.43,green:0.55,blue:0.63)
    static let steelFill = Color(red:0.76,green:0.84,blue:0.89)
    static func profilePolygon(_ line:LayoutJoint,width:Double = profileWidthMM) -> [LayoutPoint] {
        let d=line.end-line.start
        guard d.length.isFinite, d.length>0.001, width.isFinite, width>0 else { return [] }
        let normal=LayoutPoint(x:-d.y,y:d.x)*(width/(2*d.length))
        return [line.start+normal,line.end+normal,line.end-normal,line.start-normal]
    }
    static func orderedLines(_ geometry:LayoutFurringResult) -> [LayoutJoint] {
        let rear=geometry.wallFixedProfiles.filter { $0.role == .supportHorizontal }.map(\.line)
            + geometry.openingProfiles.filter { $0.role == .horizontal }.map(\.line)
        return geometry.lines.filter { line in rear.contains { LayoutOpeningFraming.same($0,line) } }
            + geometry.lines.filter { line in !rear.contains { LayoutOpeningFraming.same($0,line) } }
    }
    static func blur(focus:Double) -> Double { 0.6*(1-min(1,max(0,focus))) }
    static func plateOpacity(focus:Double) -> Double { 0.64-0.48*min(1,max(0,focus)) }
    static func drawProfiles(context:inout GraphicsContext,geometry:LayoutFurringResult,viewport:LayoutViewport) {
        for line in orderedLines(geometry) {
            let polygon=profilePolygon(line)
            guard !polygon.isEmpty else { continue }
            context.fill(layoutPath(polygon,transform:viewport),with:.color(steel))
            context.fill(layoutPath(profilePolygon(line,width:34),transform:viewport),with:.color(steelFill))
        }
    }
}

/// Canvas itself doesn't interpolate captured state. Animate one explicit scalar
/// so the steel becomes sharp over 0.5 s, without animating the model or viewport.
private struct LayoutPreciseCanvas: View, Animatable {
    var focus:Double
    var render:(inout GraphicsContext,CGSize,Double)->Void
    var animatableData:Double { get { focus } set { focus=newValue } }
    var body:some View { Canvas { context,size in render(&context,size,focus) } }
}

struct LayoutStaggerIcon: View {
    let staggered:Bool
    var body:some View {
        Canvas { c,s in
            let outer=CGRect(x:5,y:9,width:s.width-10,height:s.height-18)
            c.stroke(Path(outer),with:.foreground,lineWidth:1.5)
            var p=Path(); p.move(to:.init(x:outer.minX,y:outer.midY)); p.addLine(to:.init(x:outer.maxX,y:outer.midY))
            let a=outer.minX+outer.width*(staggered ? 0.35 : 0.5), b=outer.minX+outer.width*(staggered ? 0.65 : 0.5)
            p.move(to:.init(x:a,y:outer.minY)); p.addLine(to:.init(x:a,y:outer.midY))
            p.move(to:.init(x:b,y:outer.midY)); p.addLine(to:.init(x:b,y:outer.maxY))
            c.stroke(p,with:.foreground,lineWidth:1.5)
        }.frame(width:32,height:32).accessibilityHidden(true)
    }
}
struct LayoutObservationIcon: View {
    let fromBelow:Bool
    var body:some View {
        ZStack {
            Rectangle().frame(width:30,height:2)
            Image(systemName:"eye").font(.system(size:14)).offset(y:fromBelow ? 10 : -10)
        }.accessibilityHidden(true)
    }
}
struct LayoutOrientationIcon: View {
    let parallel:Bool
    var body:some View {
        Canvas { c,s in
            var p=Path(); p.move(to:.init(x:6,y:26)); p.addLine(to:.init(x:26,y:26))
            p.move(to:.init(x:parallel ? 6 : 16,y:8)); p.addLine(to:.init(x:parallel ? 26 : 16,y:parallel ? 8 : 26))
            c.stroke(p,with:.foreground,style:.init(lineWidth:2.5,lineCap:.round))
        }.frame(width:32,height:32).accessibilityHidden(true)
    }
}

enum LayoutInteraction: String, CaseIterable {
    case openings = "Ouvertures", contour = "Contour", framing = "Ossatures", grid = "Plaques", lighting = "Électricité", move = "Vue"
    static var allCases: [Self] { [.move,.grid,.framing,.openings,.lighting] }
    static func tool(for element:LayoutVisibilitySettings.Element) -> Self {
        switch element {
        case .sheets: .grid
        case .framing: .framing
        case .openings: .openings
        case .electrical: .lighting
        }
    }
    var hint: String {
        switch self {
        case .openings: return "Touchez une ouverture pour la modifier, glissez-la pour la déplacer."
        case .contour: return "Glissez un sommet, ou touchez-le pour modifier ses cotes."
        case .grid: return "Glissez pour déplacer les plaques. Choisissez leur sens et la pose en quinconce sur le plan."
        case .framing: return "Glissez pour décaler les fourrures et suivre leurs cotes. Touchez une distance au mur pour la saisir."
        case .lighting: return "Touchez les spots à sélectionner, puis glissez-en un pour déplacer la sélection. Touchez le vide pour désélectionner."
        case .move: return "Touchez une plaque pour ses cotes et découpes. Glissez pour déplacer la vue ; pincez pour zoomer."
        }
    }
}

/// One row selects what the finger moves. Visibility and dimension cycling
/// remain independent: selecting a tool never hides its content.
struct LayoutLabToolBar: View {
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    @Binding var mode: LayoutInteraction
    @Binding var visibility: LayoutVisibilitySettings

    func select(_ tool:LayoutInteraction) { mode = tool }

    var body: some View {
        HStack(spacing:12) {
            HStack(spacing:2) {
            Button { visibility.cycleDimensions() } label: {
                VStack(spacing:0) {
                    LayoutLabVisibilityIcon(kind:.ruler,color:visibility.dimensionedElement == nil ? Color.secondary.opacity(0.55) : .orange).frame(height:40)
                    Text("Cotes").font(.caption2)
                }.foregroundStyle(visibility.dimensionedElement == nil ? Color.secondary.opacity(0.55) : .orange)
                    .frame(maxWidth:.infinity).frame(height:58).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Cotes")
                .accessibilityValue(visibility.dimensionedElement?.title ?? "Masquées")
                .accessibilityIdentifier("layout.dimensions.cycle")
            ForEach(LayoutVisibilitySettings.Element.allCases,id:\.self) { element in
                let tool = LayoutInteraction.tool(for:element)
                let active = mode == tool
                let kind:LayoutLabVisibilityIcon.Kind = switch element {
                case .sheets: .sheet
                case .framing: .framing
                case .openings: .opening
                case .electrical: .electrical
                }
                Button { select(tool) } label: {
                    VStack(spacing:0) {
                        LayoutLabVisibilityIcon(kind:kind,color:active ? (atlantique ? Atlantique.Palette.actionInk : .orange) : (atlantique ? Atlantique.Palette.blue : .blue)).frame(height:40)
                        Text(element.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(active ? (atlantique ? Atlantique.Palette.actionInk : Color.orange) : (atlantique ? Atlantique.Palette.blue : .blue))
                    }.frame(maxWidth:.infinity).frame(height:58).contentShape(Rectangle())
                        .overlay(alignment:.bottom) {
                            Capsule().fill(visibility[element].showsDimensions ? Color.orange : .clear).frame(width:26,height:3).offset(y:4)
                        }
                }.buttonStyle(.plain).accessibilityLabel("Déplacer : \(element.title)")
                    .accessibilityValue(active ? "Outil actif" : "Outil inactif")
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("layout.tool.\(tool)")
            }
            }.frame(maxWidth:.infinity).padding(.horizontal, atlantique ? 5 : 0).padding(.vertical, atlantique ? 5 : 0)
                .background { if atlantique { AtlantiqueSurface(radius: 14) } }
            Button { select(.move) } label: {
                Image(systemName:"arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size:28,weight:.regular))
                    .foregroundStyle(mode == .move ? (atlantique ? Atlantique.Palette.actionInk : Color.orange) : (atlantique ? Atlantique.Palette.blue : .blue))
                    .frame(width:48,height:58)
                    .background(Color.white,in:RoundedRectangle(cornerRadius:18,style:.continuous))
                    .contentShape(RoundedRectangle(cornerRadius:18,style:.continuous))
            }.buttonStyle(.plain).accessibilityLabel("Déplacer le plan")
                .accessibilityHint("Déplace la vue sans déplacer les plaques, les ossatures, les ouvertures ou l’électricité")
                .accessibilityValue(mode == .move ? "Outil actif" : "Outil inactif")
                .accessibilityAddTraits(mode == .move ? .isSelected : [])
                .accessibilityIdentifier("layout.tool.move")
        }.padding(.horizontal,12).padding(.bottom,4)
    }
}
struct LayoutPlanActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label
            .multilineTextAlignment(.center)
            .padding(.horizontal,14).padding(.vertical,8)
            .frame(minHeight:52)
            .foregroundStyle(Color.accentColor.opacity(isEnabled ? 1 : 0.4))
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.25 : 0.14) : 0.06),in:Capsule())
            .contentShape(Capsule())
    }
}

private enum LayoutEditorSheet: Identifiable {
    case newSurface, settings, furring, lighting, lightingSpacing(Set<Int>), wallPoint(Int), opening(UUID?), vertex(Int), correction(Int), cut(LayoutCutSelection), pieces, furringDimensions, parts, framingDistance(LayoutWallDimension)
    var id: String {
        switch self {
        case .newSurface: return "new"
        case .settings: return "settings"
        case .furring: return "furring"
        case .lighting: return "lighting"
        case .lightingSpacing: return "lightingSpacing"
        case .wallPoint(let i): return "wallPoint-\(i)"
        case .opening(let id): return "opening-\(id?.uuidString ?? "new")"
        case .vertex(let i): return "vertex-\(i)"
        case .correction(let i): return "correction-\(i)"
        case .cut(let selection): return "cut-\(selection.id)"
        case .pieces: return "pieces"
        case .furringDimensions: return "furringDimensions"
        case .parts: return "parts"
        case .framingDistance: return "framingDistance"
        }
    }
}
private struct LayoutDragState {
    let document: LayoutDocument
    let viewport: LayoutViewport
    let vertex: Int?
    let opening: UUID?
    let initialPan: CGSize
    var spot: Int? = nil
    var spots: Set<Int> = []
}

/// Lightweight exact grid preview: contour and board joints only. No quantity
/// calculation when scrolling the library, and no lighting/framing annotations.
struct LayoutSavedThumbnail: View {
    let document:LayoutDocument
    var body:some View {
        Canvas { context,size in
            let surface = document.surface, bounds = surface.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = min((size.width-12)/bounds.width,(size.height-12)/bounds.height)
            func screen(_ p:LayoutPoint) -> CGPoint {
                .init(x:size.width/2+(p.x-bounds.center.x)*scale,y:size.height/2-(p.y-bounds.center.y)*scale)
            }
            func path(_ points:[LayoutPoint]) -> Path {
                var value = Path()
                guard let first = points.first else { return value }
                value.move(to:screen(first))
                for p in points.dropFirst() { value.addLine(to:screen(p)) }
                value.closeSubpath(); return value
            }
            var mask = path(surface.contour)
            for opening in surface.openings { mask.addPath(path(opening.contour)) }
            var boards = context
            boards.clip(to:mask,style:.init(eoFill:true))
            boards.fill(mask,with:.color(.teal.opacity(0.17)),style:.init(eoFill:true))
            if let layer = document.layers.first {
                let frame = LayoutGridFrame.make(surface:surface,layer:layer)
                let local = LayoutBounds(points:surface.contour.map(frame.local))
                func joints(step:Double,offset:Double,vertical:Bool) {
                    let low = vertical ? local.min.x : local.min.y, high = vertical ? local.max.x : local.max.y
                    guard step.isFinite, step > 0, offset.isFinite, (high-low)/step < 2000 else { return }
                    let remainder = offset.truncatingRemainder(dividingBy:step)
                    let first = ceil((low-remainder)/step), last = floor((high-remainder)/step)
                    guard first <= last else { return }
                    var lines = Path()
                    for index in Int(first)...Int(last) {
                        let v = remainder+Double(index)*step
                        let a = vertical ? LayoutPoint(x:v,y:local.min.y) : .init(x:local.min.x,y:v)
                        let b = vertical ? LayoutPoint(x:v,y:local.max.y) : .init(x:local.max.x,y:v)
                        lines.move(to:screen(frame.world(a))); lines.addLine(to:screen(frame.world(b)))
                    }
                    boards.stroke(lines,with:.color(.teal.opacity(0.8)),lineWidth:0.7)
                }
                joints(step:layer.cellWidth,offset:layer.offset.x,vertical:true)
                joints(step:layer.cellHeight,offset:layer.offset.y,vertical:false)
            }
            context.stroke(path(surface.contour),with:.color(.primary.opacity(0.8)),lineWidth:1.3)
        }.background(Color(.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:10)).accessibilityHidden(true)
    }
}

/// UI navigation for parts of the same work; no separate standalone documents are created.
struct LayoutWorkbookNavigation {
    struct Tab: Identifiable {
        let id: String
        let title: String
        var preview: AnyView? = nil
    }
    let tabs: [Tab]
    let selectedID: String
    let select: (String) -> Void
    let add: () -> Void
    let rename: () -> Void
    let relations: () -> Void
}

struct SheetLayoutView: View {
    var workbook: LayoutWorkbookNavigation? = nil
    @State private var afterLinkedSave: (() -> Void)?
    @State private var pendingPartAction: (() -> Void)?
    @State private var cleanDocument: LayoutDocument?
    var initialDocument: LayoutDocument? = nil
    var newDocumentConfiguration: WorkConfiguration? = nil
    var onSaveDocument: ((LayoutDocument) throws -> Void)? = nil
    var editWorkFacing: (() -> Void)? = nil
    var quantityProposal: (() throws -> LayoutQuantityTakeoff)? = nil
    var saveQuantityProposal: ((LayoutQuantityTakeoff) throws -> Void)? = nil
    @State private var quantityMessage: String?
    var requiredSupportKind: LayoutSupportKind? = nil
    var sharedPartitionFraming = false
    var reviewLinkedDocument: ((LayoutDocument) throws -> ComponentAdjacencyReview)? = nil
    var saveReviewedDocument: ((LayoutDocument, ComponentAdjacencyReview, ComponentAdjacencyDecision) throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadedInitial = false
    @StateObject private var model: LayoutEditorModel
    init(initialDocument: LayoutDocument? = nil, onSaveDocument: ((LayoutDocument) throws -> Void)? = nil, requiredSupportKind: LayoutSupportKind? = nil, sharedPartitionFraming: Bool = false,
         reviewLinkedDocument: ((LayoutDocument) throws -> ComponentAdjacencyReview)? = nil,
         saveReviewedDocument: ((LayoutDocument, ComponentAdjacencyReview, ComponentAdjacencyDecision) throws -> Void)? = nil,
         workbook: LayoutWorkbookNavigation? = nil, newDocumentConfiguration: WorkConfiguration? = nil,
         quantityProposal: (() throws -> LayoutQuantityTakeoff)? = nil,
         saveQuantityProposal: ((LayoutQuantityTakeoff) throws -> Void)? = nil,
         editWorkFacing: (() -> Void)? = nil) {
        self.editWorkFacing = editWorkFacing
        self.quantityProposal=quantityProposal; self.saveQuantityProposal=saveQuantityProposal
        self.newDocumentConfiguration = newDocumentConfiguration
        self.workbook = workbook
        self.initialDocument = initialDocument
        self.onSaveDocument = onSaveDocument
        self.requiredSupportKind = requiredSupportKind
        self.sharedPartitionFraming = sharedPartitionFraming
        self.reviewLinkedDocument = reviewLinkedDocument
        self.saveReviewedDocument = saveReviewedDocument
        _model = StateObject(wrappedValue: LayoutEditorModel(persistsStandaloneLibrary: onSaveDocument == nil))
    }
    @State private var linkedSaveError: String?
    @State private var pendingSharedFrameSave: LayoutDocument?
    private struct PendingAdjacency: Identifiable {
        let id = UUID()
        var document: LayoutDocument
        var review: ComponentAdjacencyReview
    }
    @State private var pendingAdjacency: PendingAdjacency?
    @EnvironmentObject private var catalogue: ToolTechnicalStore
    @State private var mode = LayoutInteraction.move
    @State private var sheet: LayoutEditorSheet?
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var rotation = 0.0
    @State private var viewAlignedEdge: Int?
    @State private var rotationStart: Double?
    @State private var rotationLatch: Double?
    @State private var fittedBounds: LayoutBounds?
    @State private var canvasFitSize: CGSize?
    @State private var fullscreen = false
    @State private var ceilingFromBelow = true
    @State private var recenterToken = 0
    @State private var addingSpot = false
    @State private var pendingWallPoint:LayoutPoint?
    @State private var wallDragFinger:CGPoint?
    @State private var ignoreWallTapUntil=Date.distantPast
    @State private var addingKind = LayoutElectricalKind.light
    @GestureState private var magnification = 1.0
    @State private var pinchAnchor: CGPoint?
    @State private var drag: LayoutDragState?
    @State private var selectedVertex: Int?
    @State private var polygonSelection: LayoutPolygonSelection?
    @State private var editingShape = false
    @State private var visibility = LayoutVisibilitySettings()
    @Environment(\.interfacePresentation) private var presentation
    @Environment(\.usesAtlantiqueDesign) private var atlantique
    private var simplifiedInterface: Bool { presentation == .contrastLab }
    @ScaledMetric(relativeTo:.body) private var toolPanelHeight = 64.0
    @ScaledMetric(relativeTo:.body) private var toolActionsHeight = 44.0
    @State private var dimensionEdge = 0
    @State private var pinching = false
    @State private var selectedSpots: Set<Int> = []
    @State private var referenceSpot: Int?
    @State private var spotGuides: [LayoutPoint] = []
    @State private var spotEditError: String?
    @State private var selectSpotsByBox = false
    @State private var spotSelectionBox: CGRect?
    @State private var renamingSaved: SavedLayoutDocument?
    @State private var savedName = ""
    @State private var deletingSaved: SavedLayoutDocument?
    @State private var showingQuickScan = false
    @AppStorage("layout.snapSpots") private var snapSpots = true

    private var navigationContent: some View {
        Group {
            VStack(spacing: 0) {
                if let workbook, !fullscreen {
                    Button { sheet = .parts } label: {
                        HStack {
                            Image(systemName: "square.stack")
                            Text(workbook.tabs.first { $0.id == workbook.selectedID }?.title ?? "Sous-parties")
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }.padding(.horizontal).padding(.vertical, 9)
                            .foregroundStyle(atlantique ? Color.white : Color.accentColor)
                    }.accessibilityLabel("Sous-parties du calepinage")
                }
                if let document = model.document { editor(document) }
                else { entry }
            }
        }
        .navigationTitle(onSaveDocument == nil ? "Calepinage 2D rapide" : "Calepinage 2D").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(workbook != nil || (model.document != nil && onSaveDocument == nil))
        .background(atlantique ? Atlantique.Palette.blue : Color(.systemGroupedBackground))
        .atlantiquePage(onSaveDocument == nil ? "Calepinage 2D rapide" : "Calepinage 2D", root: true)
        .toolbar {
            if workbook != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { performAfterSaving { dismiss() } } label: {
                        if atlantique { AtlantiqueToolbarGlyph(symbol: "chevron.left") }
                        else { Image(systemName: "chevron.left") }
                    }
                        .accessibilityLabel("Enregistrer et revenir à l’ouvrage")
                }.atlantiqueToolbarBackground(atlantique)
            } else if atlantique && (onSaveDocument != nil || model.document == nil) {
                ToolbarItem(placement: .topBarLeading) {
                    Button { performAfterSaving { dismiss() } } label: { AtlantiqueToolbarGlyph(symbol: "chevron.left") }
                        .accessibilityLabel("Retour")
                }.atlantiqueToolbarBackground()
            }
            if model.document != nil {
                if onSaveDocument == nil {
                    ToolbarItem(placement:.topBarLeading) {
                        Button { model.saveCurrentAndClose() } label: { Image(systemName:"chevron.left") }
                            .accessibilityLabel("Retour aux calepinages sauvegardés")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Enregistrer") {
                        afterLinkedSave = nil
                        if onSaveDocument != nil, let document = model.document {
                            if sharedPartitionFraming && initialDocument?.layers.first?.furring != document.layers.first?.furring {
                                pendingSharedFrameSave = document
                            } else { saveLinked(document) }
                        } else { model.saveCurrentAndClose(); selectedVertex = nil }
                    }.foregroundStyle(atlantique ? Color.white : Color.accentColor)
                    Menu {
                        if onSaveDocument == nil {
                            Button("Retour aux calepinages", systemImage: "list.bullet") { model.saveCurrentAndClose(); selectedVertex = nil }
                            Button("Nouveau support", systemImage: "plus") { sheet = .newSurface }
                        }
                        if !simplifiedInterface {
                            Button("Liste des découpes", systemImage: "list.number") { sheet = .pieces }.disabled(model.result == nil)
                        }
                        if !simplifiedInterface {
                            Button("Modifier le contour et l’échelle",systemImage:"pencil.and.outline") { editingShape = true }
                            Button("Recentrer le plan",systemImage:"scope") { recenterToken += 1 }
                        }
                        Divider()
                        Button { model.undo(); selectedVertex = nil } label: { Label("Annuler la modification", systemImage: "arrow.uturn.backward") }.disabled(!model.canUndo)
                        Button { model.redo(); selectedVertex = nil } label: { Label("Rétablir la modification", systemImage: "arrow.uturn.forward") }.disabled(!model.canRedo)
                    } label: {
                        if atlantique { AtlantiqueToolbarGlyph() }
                        else { Image(systemName: "ellipsis.circle") }
                    }.accessibilityLabel("Options du calepinage")
                }.atlantiqueToolbarBackground(atlantique)
            }
        }
    }
    private var dialogContent: some View {
        navigationContent
        .fullScreenCover(isPresented: $showingQuickScan, onDismiss: { model.reloadSavedLibrary() }) {
            ScannerDebugView(quickLayout: true, onOpenAccount: {})
        }
        .sheet(item: $sheet) { destination in sheetContent(destination) }
        .confirmationDialog("Enregistrer les modifications de cette sous-partie ?", isPresented: Binding(
            get: { pendingPartAction != nil }, set: { if !$0 { pendingPartAction = nil } }
        ), titleVisibility: .visible) {
            Button("Enregistrer et continuer") {
                let action = pendingPartAction; pendingPartAction = nil
                if let action { saveBeforePartAction(action) }
            }
            Button("Abandonner les modifications", role: .destructive) {
                let action = pendingPartAction; pendingPartAction = nil
                if let cleanDocument { model.apply(cleanDocument) }
                else { model.startNew() }
                action?()
            }
            Button("Rester sur cette sous-partie", role: .cancel) { pendingPartAction = nil }
        } message: {
            Text("Les modifications du contour, des plaques, de l’ossature, des ouvertures et de l’électricité doivent être enregistrées. Les réglages de vue et d’affichage ne sont pas concernés.")
        }
        .sheet(item: $pendingAdjacency) { pending in
            NavigationStack {
                Form {
                    Section {
                        Text("La correction du plafond concerne les murs reliés ci-dessous. Aucun mur n’est modifié sans votre accord.")
                    }
                    ForEach(pending.review.changes) { change in
                        Section(change.wallName) {
                            LabeledContent("Longueur actuelle", value: "\((change.oldLengthMM / 10).formatted(.number.precision(.fractionLength(1)))) cm")
                            if let length = change.proposedLengthMM {
                                LabeledContent("Longueur proposée", value: "\((length / 10).formatted(.number.precision(.fractionLength(1)))) cm")
                            }
                            if let reason = change.reason { Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        }
                    }
                    Section {
                        Button("Appliquer aux murs et enregistrer") { finishReviewedSave(pending, decision: .applyWalls) }
                            .disabled(!pending.review.canApply)
                        Button("Enregistrer le plafond uniquement") { finishReviewedSave(pending, decision: .keepWalls) }
                    } footer: {
                        Text("Conserver les murs laisse un écart à vérifier. Si vous les ajustez, leur bord droit est déplacé ; les hauteurs, ouvertures, ossatures et points électriques restent en place. Leurs calepinages seront à vérifier.")
                    }
                }
                .navigationTitle("Ajuster les murs ?").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Revenir au plan") { pendingAdjacency = nil } } }
                .interactiveDismissDisabled()
            }
        }
        .confirmationDialog("Modifier l’ossature des deux côtés ?", isPresented: Binding(get: { pendingSharedFrameSave != nil }, set: { if !$0 { pendingSharedFrameSave = nil } }), titleVisibility: .visible) {
            Button("Appliquer aux deux côtés") {
                if let document = pendingSharedFrameSave { saveLinked(document) }
                pendingSharedFrameSave = nil
            }
            Button("Revenir au plan", role: .cancel) { pendingSharedFrameSave = nil }
        } message: {
            Text("Cette cloison possède une seule ossature. Votre modification s’appliquera aussi à l’autre côté, en miroir : 5 cm vers la droite ici correspondent à 5 cm vers la gauche de l’autre côté. Les calepinages de plaques restent propres à chaque côté et peuvent nécessiter une vérification.")
        }
        .alert("Enregistrement impossible", isPresented: Binding(get: { linkedSaveError != nil }, set: { if !$0 { linkedSaveError = nil } })) {
            Button("OK") { linkedSaveError = nil }
        } message: { Text(linkedSaveError ?? "") }
        .alert("Renommer le calepinage",isPresented:Binding(get:{renamingSaved != nil},set:{if !$0 { renamingSaved = nil }})) {
            TextField("Nom du calepinage",text:$savedName)
            Button("Annuler",role:.cancel) { renamingSaved = nil }
            Button("Renommer") {
                if let saved = renamingSaved { model.rename(saved,to:savedName) }
                renamingSaved = nil
            }.disabled(savedName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }
        .alert("Supprimer ce calepinage ?",isPresented:Binding(get:{deletingSaved != nil},set:{if !$0 { deletingSaved = nil }})) {
            Button("Annuler",role:.cancel) { deletingSaved = nil }
            Button("Supprimer",role:.destructive) {
                if let saved = deletingSaved { model.delete(saved) }
                deletingSaved = nil
            }
        } message: { Text("« \(deletingSaved?.title ?? "") » sera supprimé de vos calepinages sauvegardés. Cette action ne peut pas être annulée.") }
    }
    var body: some View {
        dialogContent
        .alert("Calepinage enregistré",isPresented:Binding(get:{quantityMessage != nil},set:{if !$0 { quantityMessage=nil }})) {
            Button("OK") { quantityMessage=nil; finishLinkedNavigation() }
        } message: { Text(quantityMessage ?? "") }
        .toolbar(fullscreen ? .hidden : .visible, for:.navigationBar)
        .toolbar(fullscreen || atlantique ? .hidden : .visible, for:.tabBar)
        .preference(key: AtlantiqueTabBarHiddenKey.self, value: fullscreen)
        .statusBarHidden(fullscreen)
        .onChange(of:model.document?.lighting?.count) { _,_ in selectedSpots = []; referenceSpot = nil }
        .onChange(of:model.document?.surface.id) { _,_ in
            selectedSpots = []; referenceSpot = nil
            mode = .move; visibility = LayoutVisibilitySettings()
            pinchAnchor = nil; pinching = false
            rotation = 0; viewAlignedEdge = nil; rotationStart = nil; rotationLatch = nil; fittedBounds = nil; canvasFitSize = nil; zoom = 1; pan = .zero; fullscreen = false
            resolveBoardEdges()
            initializeCeilingView()
        }
        .onChange(of:mode) { _,_ in spotGuides = []; spotEditError = nil; addingSpot = false }
        .onAppear { if !loadedInitial { if let initialDocument { model.apply(initialDocument) }; resolveBoardEdges(); initializeCeilingView(); cleanDocument = model.document; loadedInitial = true } }
        .onChange(of: catalogue.layoutFormats) { _,_ in resolveBoardEdges() }
        .fullScreenCover(isPresented:$editingShape) {
            if let document = model.document {
                LayoutManualContourEditor(surface:document.surface,kind:document.surface.kind,title:"Modifier le contour et l’échelle") { surface in
                    var copy = document; copy.surface = surface
                    if surface.contour.count != document.surface.contour.count || surface.id != document.surface.id {
                        for i in copy.layers.indices { copy.layers[i].referenceEdge = nil }
                    }
                    model.apply(copy)
                }
            }
        }
        .sheet(item:$polygonSelection) { selection in
            if let document = model.document {
                if case .correction(let i) = selection, let correction = document.surface.dimensionCorrections.first(where:{$0.edgeIndex == i}) {
                    LayoutCorrectionDetail(correction:correction, edgeCount:document.surface.contour.count)
                } else {
                    LayoutConstraintForm(selection:selection, surface:document.surface) { surface in
                        var copy = document; copy.surface = surface; model.apply(copy)
                    }
                }
            }
        }
    }

    private func performAfterSaving(_ action: @escaping () -> Void) {
        guard let document = model.document, document != cleanDocument else { action(); return }
        pendingPartAction = action
    }

    private func saveBeforePartAction(_ action: @escaping () -> Void) {
        guard let document = model.document else { action(); return }
        afterLinkedSave = action
        if sharedPartitionFraming && initialDocument?.layers.first?.furring != document.layers.first?.furring {
            pendingSharedFrameSave = document
        } else { saveLinked(document) }
    }

    private func finishLinkedNavigation() {
        cleanDocument = model.document
        if let action = afterLinkedSave { afterLinkedSave = nil; action() }
        else { dismiss() }
    }

    private func saveLinked(_ document: LayoutDocument) {
        do {
            if let review = try reviewLinkedDocument?(document), !review.changes.isEmpty {
                pendingAdjacency = .init(document: document, review: review)
                return
            }
            try onSaveDocument?(document); updateQuantitiesAfterSaving()
        }
        catch { linkedSaveError = "Le plan n’a pas pu être enregistré dans l’ouvrage. \(error.localizedDescription)" }
    }

    private func finishReviewedSave(_ pending: PendingAdjacency, decision: ComponentAdjacencyDecision) {
        pendingAdjacency = nil
        do {
            guard let saveReviewedDocument else { return }
            try saveReviewedDocument(pending.document, pending.review, decision)
            updateQuantitiesAfterSaving()
        } catch { linkedSaveError = "Aucune modification enregistrée. \(error.localizedDescription)" }
    }

    private func updateQuantitiesAfterSaving() {
        cleanDocument=model.document
        guard let quantityProposal else { finishLinkedNavigation(); return }
        do {
            let updated=try quantityProposal()
            try saveQuantityProposal?(updated)
            finishLinkedNavigation()
        }
        catch { quantityMessage="Le plan est enregistré, mais son quantitatif détaillé n’a pas pu être recalculé. L’estimation du formulaire reste disponible. \(error.localizedDescription)" }
    }

    private var entry: some View {
        List {
            Section(onSaveDocument == nil ? "Calepinages sauvegardés" : "Contour de la sous-partie") {
                if model.savedDocuments.isEmpty {
                    ContentUnavailableView(onSaveDocument == nil ? "Aucun calepinage" : "Support à définir", systemImage: "square.grid.3x3",
                                           description: Text(onSaveDocument == nil ? "Créez votre premier mur ou plafond." : "Dessinez le contour ou choisissez une forme et renseignez ses dimensions."))
                } else {
                    ForEach(model.savedDocuments) { saved in
                        Button { model.open(saved) } label: {
                            HStack(spacing: 12) {
                                LayoutSavedThumbnail(document:saved.document).frame(width:82,height:72)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(saved.title).font(.headline).foregroundStyle(.primary)
                                    Text("\(saved.document.surface.kind.rawValue) · \(layoutArea(abs(LayoutGeometry.area(saved.document.surface.contour))))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("Créé le \(saved.createdAt.formatted(.dateTime.day().month().year().locale(Locale(identifier:"fr_FR"))))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                        .swipeActions(edge:.trailing,allowsFullSwipe:false) {
                            Button { deletingSaved = saved } label: { Label("Supprimer",systemImage:"trash") }.tint(.red)
                            Button { savedName = saved.title; renamingSaved = saved } label: { Label("Renommer",systemImage:"pencil") }.tint(.blue)
                        }
                    }
                }
            }
            Section {
                Button { sheet = .newSurface } label: { Label("Nouveau calepinage", systemImage: "plus") }
                if onSaveDocument == nil {
                    Button { showingQuickScan=true } label: { Label("Scanner un mur ou un plafond", systemImage: "viewfinder") }
                    Text("Choisissez une surface sur la maquette, puis calepinez-la sans créer de projet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.saveError { Section { Text(error).font(.footnote).foregroundStyle(.orange) } }
        }
    }

    private func visibilityButton(_ kind:LayoutVisibilityIcon.Kind,title:String,state:Binding<LayoutVisibilityState>) -> some View {
        Button { state.wrappedValue = state.wrappedValue.next } label: {
            LayoutVisibilityIcon(kind:kind,state:state.wrappedValue).frame(height:42).frame(maxWidth:.infinity)
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(state.wrappedValue == .hidden ? "Masqués" : state.wrappedValue == .dimensioned ? "Visibles avec cotes" : "Visibles sans cotes")
            .accessibilityHint("Toucher pour changer l’affichage")
    }

    private func displayPicker(_ title:String,state:Binding<LayoutVisibilityState>) -> some View {
        Picker(title,selection:state) {
            Text("Masquer").tag(LayoutVisibilityState.hidden)
            Text("Afficher").tag(LayoutVisibilityState.visible)
            Text("Afficher avec les cotes").tag(LayoutVisibilityState.dimensioned)
        }.pickerStyle(.menu)
    }

    private var labVisibilityBar: some View {
        LayoutLabToolBar(mode:$mode,visibility:$visibility)
            .disabled(drag != nil || pinching)
    }

    /// The reserved context area has the same height for every tool. Long wall
    /// electrical controls remain reachable without ever resizing the drawing.
    private func labToolDock(_ document:LayoutDocument) -> some View {
        VStack(spacing:6) {
            ScrollView {
                VStack(spacing:8) {
                    if mode == .move {
                        Button { editingShape = true } label: {
                            HStack {
                                Image(systemName:"pencil.and.outline")
                                Text("Modifier le contour et l’échelle").font(.subheadline)
                                Spacer(minLength:0)
                                Image(systemName:"chevron.right").font(.caption)
                            }.padding(.horizontal,12).frame(minHeight:44)
                                .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain).foregroundStyle(atlantique ? Atlantique.Palette.blue : Color.blue)
                            .accessibilityIdentifier("layout.plan.contour")
                            .padding(.horizontal,12)
                    } else {
                        activeModeSummary(document).padding(.horizontal,12)
                    }
                    if mode == .grid || mode == .framing { alignmentWarnings(document) }
                    if mode == .lighting { lightingControls(document) }
                    if let error=model.error { Text(error).foregroundStyle(.red) }
                    if let error=model.saveError { Text(error).foregroundStyle(.orange) }
                    if mode == .framing && sharedPartitionFraming {
                        Text("Ossature commune aux deux faces").foregroundStyle(.orange)
                    }
                    if let warning=model.lightingWarning {
                        Button(warning) { sheet = .lighting }.foregroundStyle(.orange)
                    }
                    if let warning=document.surface.layingWarning { Text(warning).foregroundStyle(.orange) }
                }.font(.caption).padding(.top,2)
            }.frame(height:toolPanelHeight)
            Group {
                if mode == .grid || mode == .framing {
                    let layer = document.layers.first
                    LayoutLabAlignmentActions(
                        framingMode:mode == .framing,
                        isOptimizing:model.isOptimizing,
                        optimizeDisabled:model.isOptimizing || model.isCalculating || drag != nil || pinching || (mode == .framing && layer?.furring == nil),
                        alignDisabled:model.isOptimizing || model.isCalculating || drag != nil || pinching || !(layer.map { LayoutPlanning.compatibleSpacings($0).contains($0.furring?.spacing ?? 0) } ?? false),
                        showsAlignment:layer?.furring != nil,
                        height:toolActionsHeight,
                        optimize:{ model.optimize(furring:mode == .framing) },
                        align:{
                            guard let layer else { return }
                            var copy = document
                            copy.layers[0] = LayoutPlanning.alignOtherLayer(layer,surface:document.surface,framingMode:mode == .framing)
                            model.apply(copy)
                        })
                } else if mode == .move {
                    HStack(spacing:8) {
                        planDisplayOption("Afficher les numéros de plaques",value:$visibility.sheetNumbers)
                        planDisplayOption("Afficher les angles",value:$visibility.angles)
                    }
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }.frame(height:toolActionsHeight).padding(.horizontal,12)
        }.padding(.top, atlantique ? 6 : 0).padding(.bottom, 6)
            .background {
                if atlantique { AtlantiqueSurface(radius: 17).padding(.horizontal, 12) }
            }
    }

    private func planDisplayOption(_ title:String,value:Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing:6) {
                Image(systemName:value.wrappedValue ? "checkmark.circle.fill" : "circle")
                Text(title).font(.caption).multilineTextAlignment(.leading)
            }.frame(maxWidth:.infinity).frame(height:toolActionsHeight)
                .foregroundStyle(value.wrappedValue ? Color.blue : .secondary)
                .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).accessibilityValue(value.wrappedValue ? "Activé" : "Désactivé")
    }

    @ViewBuilder private func alignmentWarnings(_ document:LayoutDocument) -> some View {
        if model.optimizationFailed, let message=model.optimizationMessage {
            Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal)
        }
        if let layer=document.layers.first, layer.furring != nil, !LayoutPlanning.aligned(layer) {
            Label("Joints et fourrures décalés : utilisez « Caler ».",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
    }

    private func alignmentActions(_ document:LayoutDocument) -> some View {
        VStack(spacing:6) {
            HStack(spacing:10) {
                Button { model.optimize(furring:mode == .framing) } label: {
                    Label(model.isOptimizing ? "Optimisation…" : "Optimiser",systemImage:"sparkles")
                }.disabled(model.isOptimizing || model.isCalculating || drag != nil || (mode == .framing && document.layers.first?.furring == nil))
                if let layer=document.layers.first, layer.furring != nil {
                    Button {
                        var copy=document
                        copy.layers[0]=LayoutPlanning.alignOtherLayer(layer,surface:document.surface,framingMode:mode == .framing)
                        model.apply(copy)
                    } label: {
                        Text(mode == .framing ? "Caler les plaques sur l’ossature" : "Caler les ossatures sur les plaques").frame(maxWidth:.infinity)
                    }.disabled(model.isOptimizing || drag != nil || pinching || !LayoutPlanning.compatibleSpacings(layer).contains(layer.furring?.spacing ?? 0))
                }
            }.font(.subheadline.weight(.semibold)).buttonStyle(LayoutPlanActionStyle()).padding(.horizontal)
            alignmentWarnings(document)
        }
    }

    private func editor(_ document: LayoutDocument) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workbook?.tabs.first { $0.id == workbook?.selectedID }?.title ?? document.surface.name).font(.headline).lineLimit(1)
                    Text("\(document.surface.kind.rawValue) · \(layoutCM(document.surface.bounds.width)) × \(layoutCM(document.surface.bounds.height))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isCalculating { ProgressView().accessibilityLabel("Calcul des découpes") }
                else if let result = model.result {
                    VStack(alignment: .trailing) {
                        if mode == .lighting {
                            Text("\(document.lighting?.positions.count ?? 0) \(document.surface.kind == .wall ? "points" : "spots")").font(.headline)
                            Text("\(selectedSpots.count) sélectionné(s)").font(.caption).foregroundStyle(.secondary)
                        } else if mode == .framing {
                            Text("\((result.furring.lines.reduce(0){$0+($1.end-$1.start).length}/1000).formatted(.number.precision(.fractionLength(2)))) ml").font(.headline)
                            Text("\(document.surface.kind == .wall ? "Ossature" : "Fourrures") · \(result.furring.lines.count) tronçons").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(result.purchasedSheetCount) plaques").font(.headline)
                            Text(layoutArea(result.netArea)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.horizontal, atlantique ? 12 : 16).padding(.vertical, atlantique ? 12 : 0)
                .background { if atlantique { AtlantiqueSurface().padding(.horizontal, 4) } }
                .padding(.horizontal, atlantique ? 8 : 0)
            if !simplifiedInterface {
            HStack(spacing:2) {
                ForEach(LayoutInteraction.allCases,id:\.self) { item in
                    Button { mode = item } label: {
                        Text(item == .lighting && document.surface.kind == .wall ? "Électricité" : item.rawValue).font(.system(size:12,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(minWidth:0,maxWidth:.infinity).frame(height:34)
                            .background(mode == item ? Color(.systemBackground) : .clear,in:Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(mode == item ? .isSelected : [])
                }
            }.padding(3).background(Color(.tertiarySystemFill),in:Capsule()).padding(.horizontal)
            HStack(spacing:2) {
                Menu {
                    if simplifiedInterface {
                        displayPicker("Plaques",state:$visibility.sheets)
                        displayPicker("Ossatures",state:$visibility.framing)
                        displayPicker("Ouvertures",state:$visibility.openings)
                        displayPicker("Électricité",state:$visibility.electrical)
                        Divider()
                    }
                    Toggle("Afficher les numéros de plaques",isOn:$visibility.sheetNumbers)
                    Toggle("Afficher les angles",isOn:$visibility.angles)
                    Button("Recentrer le plan") { recenterToken += 1 }
                } label: {
                    if simplifiedInterface {
                        Label("Affichage",systemImage:"eye").font(.subheadline.weight(.semibold))
                            .padding(.horizontal,12).frame(minHeight:44)
                            .background(.regularMaterial,in:Capsule())
                    } else {
                        VStack(spacing:2) {
                            Image(systemName:"eye").font(.system(size:23))
                            Text("Vue").font(.caption2)
                        }.frame(height:42).frame(maxWidth:.infinity)
                    }
                }.buttonStyle(.plain).accessibilityLabel(simplifiedInterface ? "Affichage du plan" : "Options de vue")
                    .accessibilityIdentifier("layout.display")
                if simplifiedInterface { Spacer() }
                else {
                    visibilityButton(.sheet,title:"Plaques",state:$visibility.sheets)
                    visibilityButton(.framing,title:"Ossatures",state:$visibility.framing)
                    visibilityButton(.opening,title:"Ouvertures",state:$visibility.openings)
                    visibilityButton(.electrical,title:"Électricité",state:$visibility.electrical)
                }
            }.padding(3).padding(.horizontal).disabled(drag != nil)
            } else { labVisibilityBar }
            GeometryReader { proxy in
                let contour = drag?.document.surface.contour ?? document.surface.contour
                let pivot = LayoutViewport.geometricCenter(contour)
                let baseViewport = LayoutViewport(bounds:fittedBounds ?? LayoutViewport.fittedBounds(contour, rotation:0, pivot:pivot), size:proxy.size, zoom:zoom, pan:pan, rotation:rotation, pivot:pivot, fittingSize:canvasFitSize,mirrored:document.surface.kind == .ceiling && ceilingFromBelow)
                let viewport = baseViewport.zoomed(to:min(8,max(0.4,zoom*magnification)),anchor:pinchAnchor ?? CGPoint(x:proxy.size.width/2,y:proxy.size.height/2))
                let sharpFraming = mode == .framing || (simplifiedInterface && mode == .move) || !visibility.sheets.isVisible
                LayoutPreciseCanvas(focus:sharpFraming ? 1 : 0) { context,size,focus in
                    draw(context:&context,size:size,document:document,viewport:viewport,framingFocus:focus)
                }
                    .animation(reduceMotion ? nil : .easeInOut(duration:LayoutPreciseStyle.transitionDuration),value:sharpFraming)
                    .background(Color(.secondarySystemGroupedBackground))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 7).onChanged { value in dragChanged(value, document: document, viewport: viewport) }.onEnded { _ in
                        if mode == .lighting, document.surface.kind == .wall, drag != nil { ignoreWallTapUntil=Date().addingTimeInterval(0.2) }
                        if let point=pendingWallPoint, !pinching { addWallPoint(point) }
                        else if let drag { model.finishGesture(from: drag.document) }
                        pendingWallPoint=nil; wallDragFinger=nil; drag = nil; spotGuides = []
                        if spotSelectionBox != nil { spotSelectionBox=nil; selectSpotsByBox=false }
                    })
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in tapped(value.location, document: document, viewport: viewport) })
                    .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                        .onChanged { value in
                            if !pinching {
                                pinching = true
                                pinchAnchor = CGPoint(x:value.startAnchor.x*proxy.size.width,y:value.startAnchor.y*proxy.size.height)
                                pendingWallPoint=nil; wallDragFinger=nil
                                if let original = drag { model.cancelGesture(restoring:original.document); pan = original.initialPan; drag = nil; spotGuides = [] }
                            }
                        }.onEnded { value in
                                let nextZoom = min(8, max(0.4, zoom * value.magnification))
                                let finalViewport = baseViewport.zoomed(to:nextZoom,anchor:pinchAnchor ?? CGPoint(x:proxy.size.width/2,y:proxy.size.height/2))
                                zoom = nextZoom
                                pan = finalViewport.pan
                            pinchAnchor = nil
                            pinching = false
                        })
                    .overlay { LayoutPolygonAnnotations(surface:document.surface, viewport:viewport, showAngles:visibility.angles, showDimensions:false) { polygonSelection = $0 }.allowsHitTesting(false) }
                    .overlay {
                        if let box=spotSelectionBox {
                            Rectangle().fill(Color.accentColor.opacity(0.12))
                                .overlay(Rectangle().stroke(Color.accentColor,style:.init(lineWidth:1,dash:[5,3])))
                                .frame(width:box.width,height:box.height).position(x:box.midX,y:box.midY).allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing:8) {
                            if simplifiedInterface {
                                Button { model.undo(); selectedVertex=nil } label: {
                                    Image(systemName:"arrow.uturn.backward").frame(width:44,height:44)
                                        .background(.regularMaterial,in:Circle())
                                }.accessibilityLabel("Annuler la dernière modification")
                                    .accessibilityIdentifier("layout.undo")
                                    .disabled(!model.canUndo || drag != nil || pinching || model.isCalculating || model.isOptimizing)
                            }
                            Button { fullscreen.toggle() } label: {
                                Image(systemName:fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .frame(width:44,height:44).background(.regularMaterial,in:Circle())
                            }.padding(8).accessibilityLabel(fullscreen ? "Quitter le plein écran" : "Afficher le plan en plein écran")
                                .contextMenu { Button("Recentrer le plan",systemImage:"scope") { recenterToken += 1 } }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if mode == .move, document.surface.kind == .ceiling {
                            Button {
                                guard let alignment = LayoutViewport.nextHorizontalEdge(contour,after:viewAlignedEdge) else { return }
                                var aligned = viewport
                                aligned.rotation = alignment.angle
                                rotation = alignment.angle
                                viewAlignedEdge = alignment.index
                                pan = aligned.constrainedPan(pan,contour:contour)
                            } label: {
                                Image(systemName:"arrow.clockwise")
                                    .frame(width:44,height:44).background(.regularMaterial,in:Circle())
                            }.padding(8)
                                .accessibilityLabel("Orienter la vue sur le bord suivant")
                                .accessibilityHint("Aligne successivement chaque bord du plafond à l’horizontale, sans changer le zoom ni la pose.")
                                .disabled(drag != nil || pinching || LayoutViewport.nextHorizontalEdge(contour,after:viewAlignedEdge) == nil)
                        }
                        if mode == .grid, document.surface.kind == .ceiling, let layer = document.layers.first {
                            Button {
                                var copy = document
                                copy.layers[0].staggered = layer.staggered != true
                                copy.layers[0].staggerOffset = nil
                                copy.layers[0] = LayoutPlanning.alignBoards(to:copy.layers[0],support:.ceiling)
                                model.apply(copy); model.optimize(furring:false)
                            } label: {
                                LayoutStaggerIcon(staggered:layer.staggered == true)
                                    .foregroundStyle(layer.staggered == true ? Color.accentColor : .primary)
                                    .frame(width:44,height:44).background(.regularMaterial,in:Circle())
                            }.padding(8)
                                .accessibilityLabel(layer.staggered == true ? "Désactiver la pose en quinconce" : "Activer la pose en quinconce")
                                .accessibilityValue(layer.staggered == true ? "Activée" : "Désactivée")
                                .disabled(drag != nil || pinching || model.isOptimizing || LayoutBoardGrid.staggerChoices(layer).isEmpty)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if document.surface.kind == .ceiling {
                            Button {
                                ceilingFromBelow.toggle()
                                var flipped = viewport; flipped.mirrored = ceilingFromBelow
                                pan = flipped.constrainedPan(pan,contour:document.surface.contour)
                            } label: { LayoutObservationIcon(fromBelow:ceilingFromBelow).frame(width:44,height:44).background(.regularMaterial,in:Circle()) }
                                .padding(8).accessibilityLabel(ceilingFromBelow ? "Vue du dessous — passer au-dessus" : "Vue du dessus — passer en dessous")
                                .disabled(drag != nil || pinching)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if mode == .grid || (mode == .framing && document.surface.kind == .ceiling) {
                            VStack(spacing:8) {
                                orientationButton(document)
                                if document.surface.kind == .ceiling { HStack(spacing: 8) {
                                    referenceWallButton(document, clockwise: false)
                                    referenceWallButton(document, clockwise: true)
                                } }
                            }.padding(8)
                            .disabled(drag != nil || pinching || model.isOptimizing)
                        }
                    }
                    .onAppear { if canvasFitSize == nil { fitCanvas(document, size:proxy.size, initial:true) } }
                    .onChange(of:canvasFitSize) { _,size in
                        if size == nil { fitCanvas(document, size:proxy.size, initial:true) }
                    }
                    .onChange(of:recenterToken) { _,_ in
                        fitCanvas(document, size:proxy.size, initial:false)
                    }
                    .onChange(of:proxy.size) { oldSize,newSize in
                        if canvasFitSize == nil { fitCanvas(document, size:newSize, initial:true); return }
                        let candidate = CGSize(width:pan.width+(oldSize.width-newSize.width)/2,
                                               height:pan.height+(oldSize.height-newSize.height)/2)
                        pan = viewport.constrainedPan(candidate,contour:document.surface.contour)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }.padding(.horizontal,fullscreen ? 4 : 16)
            if simplifiedInterface { labToolDock(document) }
            else {
            if !fullscreen {
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
            }
            if let saveError = model.saveError { Text(saveError).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if mode == .framing && sharedPartitionFraming {
                Label("Ossature commune : tout décalage sera appliqué en miroir sur l’autre côté à l’enregistrement.", systemImage: "arrow.left.arrow.right")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal)
            }
            if let warning = model.lightingWarning {
                Button { sheet = .lighting } label: { Label(warning,systemImage:"exclamationmark.triangle") }
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal)
            }
            if let warning = document.surface.layingWarning {
                Label(warning,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(.horizontal)
            }
            }
            // Keep the active mode's editing actions available in full screen.
            if mode == .lighting { lightingControls(document) }
            if mode == .grid || mode == .framing {
                alignmentActions(document)
            }
            if !fullscreen {
            if mode == .contour, let index = selectedVertex, document.surface.contour.indices.contains(index) {
                Button("Modifier le sommet \(index + 1) · ajouter / supprimer") { sheet = .vertex(index) }.font(.subheadline)
            }
            activeModeSummary(document).padding(.horizontal).padding(.bottom,8)
            }
            }
        }.padding(.top, 8)
    }

    private func summaryCard(_ title:String,detail:String,symbol:String,destination:LayoutEditorSheet) -> some View {
        Button {
            if case .settings = destination, let editWorkFacing {
                performAfterSaving(editWorkFacing)
            } else { sheet = destination }
        } label: {
            HStack(spacing:12) {
                if !simplifiedInterface { Image(systemName:symbol).font(.title3).foregroundStyle(LayoutPreciseStyle.steel) }
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"slider.horizontal.3").foregroundStyle(Color.accentColor)
            }.padding(.horizontal,13).padding(.vertical,simplifiedInterface ? 8 : 13).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
        }.buttonStyle(.plain).accessibilityHint("Ouvrir les réglages détaillés")
            .accessibilityIdentifier("layout.tool.settings")
    }

    @ViewBuilder private func activeModeSummary(_ document:LayoutDocument) -> some View {
        switch mode {
        case .grid:
            if let layer=document.layers.first {
                let name=catalogue.layoutFormats.first { $0.id == layer.catalogFormatID }?.title
                    ?? (layer.catalogFormatID == nil ? "Parement personnalisé" : "Parement enregistré")
                summaryCard(name,
                    detail:"\(layoutCM(layer.sheetWidth)) × \(layoutCM(layer.sheetLength)) · \(layer.fourTaperedEdges == true ? "4" : "2") bords amincis" + (simplifiedInterface ? "" : " · \(layer.staggered == true ? "Quinconce" : "Pose alignée")"),
                    symbol:"rectangle.portrait",destination:.settings)
            }
        case .framing:
            if let f=document.layers.first?.furring {
                if simplifiedInterface {
                    summaryCard("Entraxe · \(layoutCM(f.spacing))",detail:"",symbol:"line.3.horizontal",destination:.furring)
                } else {
                let length=model.result?.furring.lines.reduce(0) { $0+($1.end-$1.start).length } ?? 0
                summaryCard(f.openingSystem == .studs || f.isFurringSystem == false ? "Ossature rails et montants" : "Ossature sur fourrures",
                    detail:"Entraxe \(layoutCM(f.spacing)) · \((length/1000).formatted(.number.precision(.fractionLength(1)))) ml au total" + (f.includesHorizontalSupportFurring == true ? " · Fourrures horizontales de fixation" : ""),
                    symbol:"line.3.horizontal",destination:.furring)
                }
            } else {
                summaryCard("Aucune ossature configurée",detail:"Définir l’entraxe et le sens de pose",symbol:"line.3.horizontal",destination:.furring)
            }
        case .openings:
            VStack(spacing:6) {
                let details=document.surface.openings.prefix(2).map {
                    "\($0.kind.rawValue) · \(layoutCM($0.bounds.width)) × \(layoutCM($0.bounds.height))"
                }.joined(separator:" · ")
                summaryCard("\(document.surface.openings.count) ouverture(s)",detail:details.isEmpty ? "Ajouter une porte, une fenêtre ou une réservation" : details,symbol:"square.on.square",destination:.opening(nil))
                if !document.surface.openings.isEmpty {
                    Menu("Modifier une ouverture") {
                        ForEach(document.surface.openings) { opening in
                            Button("\(opening.kind.rawValue) · \(layoutCM(opening.bounds.width)) × \(layoutCM(opening.bounds.height))") { sheet = .opening(opening.id) }
                        }
                    }.font(.caption)
                }
            }
        case .lighting:
            let lights=document.lighting
            let count=lights?.positions.count ?? 0
            let sockets=lights.map { l in l.positions.indices.filter { l.kind(at:$0) == .socket }.count } ?? 0
            summaryCard(document.surface.kind == .wall ? "\(count-sockets) lumière(s) · \(sockets) prise(s)" : "\(count) spots",
                detail:count == 0 ? "Configurer la répartition" : "Diamètre \(layoutCM(lights?.diameter ?? 68))" + (document.surface.kind == .ceiling ? " · \(lights?.perpendicularToFurring == true ? "Perpendiculaires" : "Parallèles") aux fourrures" : ""),
                symbol:"bolt",destination:.lighting)
        case .move,.contour:
            EmptyView()
        }
    }

    @ViewBuilder private func lightingControls(_ document:LayoutDocument) -> some View {
        if document.surface.kind == .ceiling {
            Button("Répartition automatique") {
                addingSpot=false; selectSpotsByBox=false; selectedSpots=[]; referenceSpot=nil
                sheet = .lighting
            }.buttonStyle(.bordered).font(.caption).padding(.horizontal)
            if let spotEditError { Text(spotEditError).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
        } else { wallLightingControls(document) }
    }

    @ViewBuilder private func wallLightingControls(_ document:LayoutDocument) -> some View {
        HStack {
            Button(document.surface.kind == .wall ? "Ajouter des rangées" : "Répartition automatique") { sheet = .lighting }
            if document.surface.kind == .wall {
                if addingSpot { Button("Terminer l’ajout") { addingSpot = false } }
                else {
                    Menu("Ajouter à la main") {
                        Button("Prise") { addingKind = .socket; addingSpot = true }
                        Button("Lumière") { addingKind = .light; addingSpot = true }
                    }
                }
            } else { Button(addingSpot ? "Terminer l’ajout" : "Ajouter à la main") { addingKind = .light; addingSpot.toggle() } }
        }.buttonStyle(.bordered).font(.caption).padding(.horizontal)
        if let lighting = document.lighting {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    Button { selectSpotsByBox.toggle() } label: {
                        Label(selectSpotsByBox ? "Tracez un cadre" : "Sélection par cadre",systemImage:"selection.pin.in.out")
                    }.tint(selectSpotsByBox ? .orange : .accentColor)
                    ForEach(LayoutSpotArrangement.allCases,id:\.self) { action in
                        Button(spotActionTitle(action,wall:document.surface.kind == .wall)) {
                            do {
                                var copy=document
                                let frame=document.layers.first.map { LayoutPlanning.framingFrame(surface:document.surface,layer:$0) }
                                copy.lighting=try LayoutPlanning.arrangedLighting(lighting,selected:selectedSpots,reference:referenceSpot,action:action,surface:document.surface,frame:document.surface.kind == .ceiling ? frame : nil)
                                model.apply(copy); spotEditError=nil
                            } catch { spotEditError=error.localizedDescription }
                        }.disabled(selectedSpots.count<action.minimumCount)
                    }
                    Button("Centrer") { centerSpots(document,selected:selectedSpots) }.disabled(selectedSpots.isEmpty)
                    Button("Écartement") { sheet = .lightingSpacing(selectedSpots) }.disabled(selectedSpots.count<2)
                }.buttonStyle(.bordered).font(.caption).padding(.horizontal)
            }
            if !selectedSpots.isEmpty {
                Text("\(selectedSpots.count) sélectionné(s) · alignement sur le dernier spot touché").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            HStack {
                Button(selectedSpots.count == lighting.count ? "Désélectionner" : "Tout sélectionner") {
                    selectedSpots = selectedSpots.count == lighting.count ? [] : Set(lighting.positions.indices)
                    referenceSpot = selectedSpots.sorted().last
                }
                Menu {
                    Button(document.surface.kind == .wall ? "Centrer tous les points horizontalement" : "Centrer tous les spots") { centerSpots(document,selected:Set(lighting.positions.indices)) }
                    Button(document.surface.kind == .wall ? "Centrer la sélection horizontalement" : "Centrer la sélection") { centerSpots(document,selected:selectedSpots) }.disabled(selectedSpots.isEmpty)
                    Button("Rapprocher / écarter…") { sheet = .lightingSpacing(selectedSpots.isEmpty ? Set(lighting.positions.indices) : selectedSpots) }
                        .disabled((selectedSpots.isEmpty ? lighting.count : selectedSpots.count) < 2)
                    if document.surface.kind == .wall {
                        Button("Ajouter une prise sur le plan") { addingKind = .socket; addingSpot = true }
                        Button("Ajouter une lumière sur le plan") { addingKind = .light; addingSpot = true }
                        Button("Ajouter une rangée à une hauteur…") { sheet = .lighting }
                    } else { Button(addingSpot ? "Terminer l’ajout" : "Ajouter un spot sur le plan",systemImage:"plus.circle") { addingKind = .light; addingSpot.toggle() } }
                    if !selectedSpots.isEmpty {
                        Button("Supprimer la sélection",role:.destructive) {
                            var copy = document, value = lighting
                            value.kinds = lighting.positions.indices.filter { !selectedSpots.contains($0) }.map { lighting.kind(at:$0) }
                            value.positions = lighting.positions.enumerated().filter { !selectedSpots.contains($0.offset) }.map(\.element)
                            value.wallRowHeights=LayoutWallLighting.heights(lighting,surface:document.surface)
                            value.count = value.positions.count; copy.lighting = value.count == 0 && value.wallRowHeights?.isEmpty != false ? nil : value
                            model.apply(copy); selectedSpots = []; referenceSpot = nil
                        }
                    }
                    Divider()
                    Toggle("Aimantation des positions et rotations",isOn:$snapSpots)
                    if let referenceSpot { Text("Alignement sur S\(referenceSpot+1), dernier spot sélectionné") }
                    ForEach(LayoutSpotArrangement.allCases,id:\.self) { action in
                        Button(action.rawValue) {
                            do {
                                var copy = document
                                let frame=document.layers.first.map { LayoutPlanning.framingFrame(surface:document.surface,layer:$0) }
                                copy.lighting = try LayoutPlanning.arrangedLighting(lighting,selected:selectedSpots,reference:referenceSpot,action:action,surface:document.surface,frame:document.surface.kind == .ceiling ? frame : nil)
                                model.apply(copy); spotEditError = nil
                            } catch { spotEditError = error.localizedDescription }
                        }.disabled(selectedSpots.count < action.minimumCount)
                    }
                } label: { Label("Organiser",systemImage:"slider.horizontal.3") }
                Toggle(isOn:$snapSpots) { Image(systemName:"scope") }.toggleStyle(.button).accessibilityLabel("Repères et aimantation des spots")
            }.font(.caption).buttonStyle(.bordered).padding(.horizontal)
        }
        if let spotEditError { Text(spotEditError).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
    }
    private func centerSpots(_ document:LayoutDocument,selected:Set<Int>) {
        guard let lighting = document.lighting else { return }
        do {
            var copy = document
            copy.lighting = try LayoutPlanning.centeredLighting(lighting,selected:selected,surface:document.surface)
            model.apply(copy); spotEditError = nil
        } catch { spotEditError = error.localizedDescription }
    }
    private func spotActionTitle(_ action:LayoutSpotArrangement,wall:Bool) -> String {
        if wall { return action.rawValue }
        switch action {
        case .horizontal: return "Aligner ∥ fourrures"
        case .vertical: return "Aligner ⊥ fourrures"
        case .distributeX: return "Espacer ∥ fourrures"
        case .distributeY: return "Espacer ⊥ fourrures"
        }
    }
    private func initializeCeilingView() {
        guard let document=model.document, document.surface.kind == .ceiling,
              let alignment=LayoutViewport.initialCeilingAlignment(document.surface.contour,referenceEdge:document.layers.first?.referenceEdge) else { return }
        rotation=alignment.angle; viewAlignedEdge=alignment.index
        fittedBounds=LayoutViewport.fittedBounds(document.surface.contour,rotation:rotation)
    }

    private func fitCanvas(_ document:LayoutDocument, size:CGSize, initial:Bool) {
        guard size.width > 1, size.height > 1 else { return }
        if initial { initializeCeilingView() }
        let contour=document.surface.contour
        let bounds=LayoutViewport.fittedBounds(contour,rotation:rotation)
        let fit=LayoutViewport.initialEditingSize(size)
        let viewport=LayoutViewport(bounds:bounds,size:size,zoom:1,pan:.zero,rotation:rotation,
                                    pivot:LayoutViewport.geometricCenter(contour),fittingSize:fit)
        fittedBounds=bounds; canvasFitSize=fit; zoom=1
        pan=viewport.upperFramingPan(contour:contour)
    }

    private func referenceWallButton(_ document: LayoutDocument, clockwise: Bool) -> some View {
        Button {
            guard !document.layers.isEmpty else { return }
            var copy = document
            let current = mode == .framing && copy.layers[0].furring?.usesOwnReference == true ? copy.layers[0].furring?.referenceEdge : copy.layers[0].referenceEdge
            let next = LayoutPlanning.nextReferenceEdge(document.surface,current:current,clockwise:ceilingFromBelow ? !clockwise : clockwise)
            if mode == .framing {
                copy.layers[0].materializeFurringOrientation()
                copy.layers[0].furring?.usesOwnReference = true
                copy.layers[0].furring?.referenceEdge = next
                copy.layers[0].furring?.inheritedGridFrame = nil
            } else {
                if copy.layers[0].furring?.usesOwnReference != true {
                    let inheritedFrame = copy.layers[0].inheritedGridFrame
                    copy.layers[0].furring?.referenceEdge = current
                    copy.layers[0].furring?.usesOwnReference = true
                    copy.layers[0].furring?.inheritedGridFrame = inheritedFrame
                }
                copy.layers[0].referenceEdge = next
                copy.layers[0].inheritedGridFrame = nil
            }
            model.apply(copy)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
        }.accessibilityLabel(clockwise ? "Mur de référence suivant, sens horaire" : "Mur de référence précédent, sens antihoraire")
    }
    @ViewBuilder private func orientationButton(_ document:LayoutDocument) -> some View {
        if let layer = document.layers.first {
            let parallel = (mode == .framing ? layer.resolvedFurringOrientation : layer.orientation) == .horizontal
            Button {
                var copy = document
                if mode == .framing { copy.layers[0].setFurringOrientation(parallel ? .vertical : .horizontal) }
                else { copy.layers[0].materializeFurringOrientation(); copy.layers[0].orientation = parallel ? .vertical : .horizontal }
                model.apply(copy)
            } label: {
                LayoutOrientationIcon(parallel:parallel).frame(width:44,height:44).background(.regularMaterial,in:Circle())
            }.accessibilityLabel(parallel ? "Parallèle au mur — passer perpendiculaire" : "Perpendiculaire au mur — passer parallèle")
        }
    }
    private func resolveBoardEdges() {
        guard var document = model.document, let layer = document.layers.first else { return }
        let resolved = WorkLayoutDefaults.resolvingFacing(layer,configuration:newDocumentConfiguration,formats:catalogue.layoutFormats)
        guard resolved != layer else { return }
        let wasClean = document == cleanDocument
        document.layers[0] = resolved
        model.apply(document)
        if wasClean { cleanDocument = document }
    }

    private func drawSteel(context:inout GraphicsContext,document:LayoutDocument,viewport:LayoutViewport,focus:Double) {
        guard visibility.framing.isVisible, let layer=document.layers.first else { return }
        let current=LayoutPlanning.worldFurring(surface:document.surface,layer:layer)
        var mask=layoutPath(document.surface.contour,transform:viewport)
        for opening in document.surface.openings { mask.addPath(layoutPath(opening.contour,transform:viewport)) }
        context.drawLayer { steel in
            steel.clip(to:mask,style:.init(eoFill:true))
            let blur=LayoutPreciseStyle.blur(focus:focus)
            if blur>0.001 { steel.addFilter(.blur(radius:blur)) }
            // Physical rectangles preserve width under zoom, rotation and mirroring.
            LayoutPreciseStyle.drawProfiles(context:&steel,geometry:current,viewport:viewport)
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, document: LayoutDocument, viewport: LayoutViewport,framingFocus:Double) {
        let surface = document.surface
        drawSteel(context:&context,document:document,viewport:viewport,focus:framingFocus)
        var numbers: [(label:String, anchor:CGPoint, size:CGSize, fits:Bool)] = []
        // The construction axes remain part of the coordinate system used by
        // snapping and alignment; only their visual overlay is intentionally hidden.
        if let result = model.result {
            if model.resultDocument.map({ !LayoutBoardGrid.sameGeometry(document,$0) }) == true {
                drawLiveGrids(context:&context,document:document,viewport:viewport,framingFocus:framingFocus)
            } else {
            let boardEdges = visibility.sheets.showsDimensions ? result.sheets.flatMap { placement in
                placement.pieces.flatMap { piece in
                    LayoutGeometry.edges(piece.contour).map {
                        LayoutJoint(start:result.frame.world($0.a),end:result.frame.world($0.b))
                    }
                }
            } : []
            let visibleBoardEdges = Set(boardEdges.indices.filter { i in
                CGRect(origin:.zero,size:size).insetBy(dx:16,dy:16)
                    .contains(viewport.screen((boardEdges[i].start+boardEdges[i].end)*0.5))
            })
            let boardLabels = LayoutDimensionLabels.representatives(boardEdges,preferred:visibleBoardEdges)
            var boardEdgeIndex = 0
            for (placementIndex,placement) in result.sheets.enumerated() where visibility.sheets.isVisible {
                for piece in placement.pieces {
                    var path = layoutPath(piece.contour.map(result.frame.world), transform: viewport)
                    for hole in piece.holes { path.addPath(layoutPath(hole.map(result.frame.world), transform: viewport)) }
                    let color = LayoutPreciseStyle.ink
                    let tint=placementIndex.isMultiple(of:2) ? Color(red:0.98,green:0.985,blue:0.99) : Color(red:0.86,green:0.89,blue:0.91)
                    context.fill(path,with:.color(tint.opacity(LayoutPreciseStyle.plateOpacity(focus:framingFocus))),style:.init(eoFill:true))
                    context.stroke(path,with:.color(LayoutPreciseStyle.ink),lineWidth:LayoutPreciseStyle.edgeWidth)
                    if visibility.sheets.showsDimensions {
                        for edge in LayoutGeometry.edges(piece.contour) {
                            if boardLabels.contains(boardEdgeIndex) {
                                drawAlongDimension(context:&context,a:result.frame.world(edge.a),b:result.frame.world(edge.b),viewport:viewport,color:color,offset:9)
                            }
                            boardEdgeIndex += 1
                        }
                    }
                    let label = placement.label(for:piece)
                    let anchor = viewport.screen(result.frame.world(piece.labelPoint))
                    if visibility.sheetNumbers && CGRect(origin:.zero,size:size).contains(anchor) {
                        let measured = context.resolve(Text(label).font(.system(size:12,weight:.semibold)))
                            .measure(in:CGSize(width:200,height:30))
                        let labelSize = CGSize(width:measured.width+8,height:measured.height+4)
                        let corners = [CGPoint(x:anchor.x-labelSize.width/2,y:anchor.y-labelSize.height/2),
                            CGPoint(x:anchor.x+labelSize.width/2,y:anchor.y-labelSize.height/2),
                            CGPoint(x:anchor.x+labelSize.width/2,y:anchor.y+labelSize.height/2),
                            CGPoint(x:anchor.x-labelSize.width/2,y:anchor.y+labelSize.height/2)]
                        let fits = corners.allSatisfy { piece.contains(result.frame.local(viewport.world($0))) }
                        numbers.append((label,anchor,labelSize,fits))
                    }
                }
            }
            }
            if visibility.framing.isVisible, let layer=document.layers.first {
                let current=LayoutPlanning.worldFurring(surface:surface,layer:layer)
                let visibleLengths = Set(current.lines.indices.filter { i in
                    let line = current.lines[i]
                    return CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 16)
                        .contains(viewport.screen((line.start + line.end) * 0.5))
                })
                let labels = LayoutDimensionLabels.representatives(current.lines, preferred: visibleLengths)
                for (index, line) in current.lines.enumerated() {
                    if visibility.framing.showsDimensions && labels.contains(index) {
                        drawAlongDimension(context:&context,a:line.start,b:line.end,viewport:viewport,color:LayoutPreciseStyle.steel,offset:7)
                    }
                }
                // Intermediate supports remain in the takeoff, but their dots
                // are hidden to keep the lining framing drawing legible.
                if visibility.framing.showsDimensions {
                    for callout in framingCallouts(document:document,viewport:viewport) {
                        var p=Path(); p.move(to:callout.a); p.addLine(to:callout.b)
                        context.stroke(p,with:.color(LayoutPreciseStyle.steel),lineWidth:0.8)
                        var leaders=Path()
                        leaders.move(to:viewport.screen(callout.dimension.start)); leaders.addLine(to:callout.a)
                        leaders.move(to:viewport.screen(callout.dimension.end)); leaders.addLine(to:callout.b)
                        context.stroke(leaders,with:.color(LayoutPreciseStyle.steel.opacity(0.4)),style:.init(lineWidth:0.6,dash:[2,3]))
                        context.fill(Path(roundedRect:callout.rect,cornerRadius:5),with:.color(Color(.secondarySystemGroupedBackground)))
                        context.draw(Text(layoutCM(callout.dimension.distance)).font(.system(size:11,weight:.semibold)).foregroundStyle(LayoutPreciseStyle.steel),at:callout.center)
                    }
                }
            }
        }
        context.stroke(layoutPath(surface.contour, transform: viewport), with: .color(LayoutPreciseStyle.ink), lineWidth: LayoutPreciseStyle.edgeWidth)
        let layer = document.layers.first
        let referenceEdge = mode == .framing && layer?.furring?.usesOwnReference == true ? layer?.furring?.referenceEdge : layer?.referenceEdge
        if surface.kind == .ceiling, (mode == .grid || mode == .framing), let edge = referenceEdge,
           surface.contour.indices.contains(edge) {
            var reference = Path()
            reference.move(to: viewport.screen(surface.contour[edge]))
            reference.addLine(to: viewport.screen(surface.contour[(edge+1)%surface.contour.count]))
            context.stroke(reference, with: .color(.blue), lineWidth: 4)
        }
        if let laying = try? surface.layingContour(), laying != surface.contour {
            context.stroke(layoutPath(laying,transform:viewport),with:.color(.orange),lineWidth:2.5)
        }
        for opening in surface.openings where visibility.openings.isVisible {
            let p = layoutPath(opening.contour, transform: viewport)
            context.stroke(p, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            context.draw(Text(opening.kind.rawValue).font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange), at: viewport.screen(opening.bounds.center))
            if visibility.openings.showsDimensions || drag?.opening == opening.id {
                drawWallDimensions(context:&context,points:opening.contour,surface:surface,viewport:viewport,color:.orange)
            }
        }
        if mode == .lighting, surface.kind == .wall, visibility.electrical.isVisible {
            for height in LayoutWallLighting.heights(document.lighting,surface:surface) {
                for segment in LayoutWallLighting.rowSegments(height:height,surface:surface) {
                    var row=Path(); row.move(to:viewport.screen(segment.start)); row.addLine(to:viewport.screen(segment.end))
                    context.stroke(row,with:.color(.orange.opacity(0.55)),style:.init(lineWidth:1,dash:[5,5]))
                }
            }
            if let point=pendingWallPoint {
                let p=viewport.screen(point)
                let valid=(try? LayoutPlanning.addingSpot(to:document.lighting,at:point,surface:surface,kind:addingKind)) != nil
                context.fill(Path(ellipseIn:.init(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(valid ? .orange : .red))
                drawWallPointDimensions(context:&context,point:point,surface:surface,viewport:viewport)
            }
            if let finger=wallDragFinger,
               let point=pendingWallPoint ?? drag?.spot.flatMap({ document.lighting?.positions.indices.contains($0) == true ? document.lighting?.positions[$0] : nil }) {
                let p=viewport.screen(point)
                var link=Path(); link.move(to:finger); link.addLine(to:p)
                context.stroke(link,with:.color(.orange.opacity(0.5)),style:.init(lineWidth:1,dash:[3,3]))
                context.stroke(Path(ellipseIn:.init(x:p.x-10,y:p.y-10,width:20,height:20)),with:.color(.orange),lineWidth:1)
            }
        }
        if let lighting = document.lighting, visibility.electrical.isVisible {
            for (i,p) in lighting.positions.enumerated() {
                let s = viewport.screen(p), radius = max(4,lighting.diameter/2*viewport.scale)
                context.fill(Path(ellipseIn:.init(x:s.x-radius,y:s.y-radius,width:2*radius,height:2*radius)),with:.color(.yellow))
                context.stroke(Path(ellipseIn:.init(x:s.x-radius,y:s.y-radius,width:2*radius,height:2*radius)),with:.color(.orange),lineWidth:1)
                if mode == .lighting && selectedSpots.contains(i) {
                    context.stroke(Path(ellipseIn:.init(x:s.x-13,y:s.y-13,width:26,height:26)),with:.color(i == referenceSpot ? .blue : .orange),lineWidth:2)
                }
                context.draw(Text(lighting.label(at:i,wall:document.surface.kind == .wall)).font(.system(size:10,weight:.bold)).foregroundStyle(lighting.kind(at:i) == .socket ? Color.blue : .orange),at:.init(x:s.x,y:s.y-radius-8))
                if visibility.electrical.showsDimensions || (mode == .lighting && drag?.spot == i) {
                    if surface.kind == .wall { drawWallPointDimensions(context:&context,point:p,surface:surface,viewport:viewport) }
                    else { drawWallDimensions(context:&context,points:[p],surface:surface,viewport:viewport,color:.orange) }
                }
            }
            if mode == .lighting, let anchor = drag?.spot, lighting.positions.indices.contains(anchor) {
                let p = viewport.screen(lighting.positions[anchor])
                for guide in spotGuides {
                    var path = Path(); path.move(to:p); path.addLine(to:viewport.screen(guide))
                    context.stroke(path,with:.color(.orange),style:.init(lineWidth:1,dash:[4,3]))
                }
            }
        }
        for i in surface.contour.indices {
            let a = surface.contour[i]
            if mode == .contour {
                let p = viewport.screen(a), radius = selectedVertex == i ? 8.0 : 6.0
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(selectedVertex == i ? .orange : .teal))
                context.draw(Text(vertexName(i)).font(.caption.bold()), at: .init(x: p.x + 12, y: p.y - 12))
            }
        }
        var occupied:[CGRect] = []
        // Reserve in-place numbers first, then route the small-piece callouts.
        for number in numbers.filter(\.fits) + numbers.filter({ !$0.fits }) {
            let rect = LayoutNumberCallout.rect(anchor:number.anchor,size:number.size,
                viewport:CGRect(origin:.zero,size:size),occupied:occupied,displaced:!number.fits)
            occupied.append(rect)
            let center = CGPoint(x:rect.midX,y:rect.midY)
            if !number.fits {
                var leader=Path(); leader.move(to:number.anchor); leader.addLine(to:center)
                context.stroke(leader,with:.color(.primary.opacity(0.65)),lineWidth:1)
                context.fill(Path(ellipseIn:CGRect(x:number.anchor.x-2,y:number.anchor.y-2,width:4,height:4)),with:.color(.primary))
                context.fill(Path(roundedRect:rect,cornerRadius:4),with:.color(Color(.systemBackground).opacity(0.92)))
            }
            context.draw(Text(number.label).font(.system(size:12,weight:.semibold)).foregroundStyle(.primary),at:center)
        }
    }

    private func drawLiveGrids(context:inout GraphicsContext,document:LayoutDocument,viewport:LayoutViewport,framingFocus:Double) {
        guard let initialLayer = document.layers.first else { return }
        let layer=initialLayer.forSurface(document.surface)
        let frame = LayoutGridFrame.make(surface:document.surface,layer:layer)
        var local=document.surface
        local.contour=document.surface.contour.map(frame.local)
        local.openings=document.surface.openings.map { var o=$0; o.contour=o.contour.map(frame.local); return o }
        local.contour=(try? local.layingContour()) ?? local.contour
        if visibility.sheets.isVisible {
            let sheets=(try? LayoutBoardGrid.clippedSheets(surface:local,layer:layer)) ?? []
            for (i,sheet) in sheets.enumerated() {
                for piece in sheet.pieces {
                var path=layoutPath(piece.contour.map(frame.world),transform:viewport)
                for hole in piece.holes { path.addPath(layoutPath(hole.map(frame.world),transform:viewport)) }
                let tint=i.isMultiple(of:2) ? Color(red:0.98,green:0.985,blue:0.99) : Color(red:0.86,green:0.89,blue:0.91)
                context.fill(path,with:.color(tint.opacity(LayoutPreciseStyle.plateOpacity(focus:framingFocus))),style:.init(eoFill:true))
                context.stroke(path,with:.color(LayoutPreciseStyle.ink),lineWidth:LayoutPreciseStyle.edgeWidth)
                }
            }
            if visibility.sheets.showsDimensions {
                let edges=sheets.flatMap(\.pieces).flatMap { LayoutGeometry.edges($0.contour) }
                    .map { LayoutJoint(start:frame.world($0.a),end:frame.world($0.b)) }
                let visible=Set(edges.indices.filter { i in
                    CGRect(origin:.zero,size:viewport.size).insetBy(dx:16,dy:16)
                        .contains(viewport.screen((edges[i].start+edges[i].end)*0.5))
                })
                for i in LayoutDimensionLabels.representatives(edges,preferred:visible).sorted() {
                    drawAlongDimension(context:&context,a:edges[i].start,b:edges[i].end,viewport:viewport,color:LayoutPreciseStyle.ink,offset:9)
                }
            }
        }
    }

    private struct FramingCallout {
        var dimension:LayoutWallDimension
        var a:CGPoint; var b:CGPoint
        var center:CGPoint { .init(x:(a.x+b.x)/2,y:(a.y+b.y)/2) }
        var rect:CGRect { .init(x:center.x-36,y:center.y-11,width:72,height:22) }
    }
    private func framingCallouts(document:LayoutDocument,viewport:LayoutViewport) -> [FramingCallout] {
        guard document.surface.kind == .ceiling, let layer=document.layers.first,
              let settings=layer.furring, let result=model.result else { return [] }
        let geometry=LayoutPlanning.worldFurring(surface:document.surface,layer:layer)
        let joints=result.joints.map { LayoutJoint(start:result.frame.world($0.start),end:result.frame.world($0.end)) }
        var supports=LayoutPlanning.junctionSupports(lines:geometry.lines,fixed:geometry.peripheralLines,joints:joints,spacing:settings.spacing)
        if let original=drag?.document, mode == .framing, let before=original.layers.first,
           let f=before.furring {
            let previous=LayoutPlanning.worldFurring(surface:original.surface,layer:before)
            let tracking=LayoutPlanning.junctionSupports(lines:previous.lines,fixed:previous.peripheralLines,joints:joints,spacing:f.spacing)
            let frame=LayoutPlanning.framingFrame(surface:document.surface,layer:layer)
            let local=LayoutPoint(x:0,y:(settings.offset-f.offset)*(LayoutPlanning.alongX(layer) ? 1 : -1))
            let delta=frame.world(local)-frame.origin
            supports=tracking.compactMap { old in
                let target=(old.start+old.end)*0.5+delta
                return geometry.lines.filter { !geometry.peripheralLines.contains($0) }
                    .min(by:{LayoutGeometry.distance(target,to:$0.start,$0.end)<LayoutGeometry.distance(target,to:$1.start,$1.end)})
            }
        }
        var annotations:[FramingCallout]=[]
        let contour=document.surface.contour.map(viewport.screen)
        for (index,line) in supports.enumerated() {
            let start=viewport.screen(line.start), end=viewport.screen(line.end)
            let length=hypot(end.x-start.x,end.y-start.y)
            guard length>1 else { continue }
            let n=CGPoint(x:(start.x-end.x)/length,y:(start.y-end.y)/length)
            let outside=(contour.map{$0.x*n.x+$0.y*n.y}.max() ?? 0)+28+Double(index%3)*25
            func project(_ p:LayoutPoint)->CGPoint {
                let s=viewport.screen(p), shift=outside-s.x*n.x-s.y*n.y
                return .init(x:s.x+n.x*shift,y:s.y+n.y*shift)
            }
            for dimension in LayoutPlanning.framingWallDimensions(line,surface:document.surface) {
                annotations.append(.init(dimension:dimension,a:project(dimension.start),b:project(dimension.end)))
            }
        }
        return annotations
    }

    private func drawAlongDimension(context:inout GraphicsContext,a:LayoutPoint,b:LayoutPoint,viewport:LayoutViewport,color:Color,offset:Double) {
        let p = viewport.screen(a), q = viewport.screen(b)
        guard hypot(q.x-p.x,q.y-p.y) > 28 else { return }
        var angle = atan2(q.y-p.y,q.x-p.x)
        if angle > .pi/2 { angle -= .pi }; if angle < -.pi/2 { angle += .pi }
        var label = context
        label.translateBy(x:(p.x+q.x)/2+sin(angle)*offset,y:(p.y+q.y)/2-cos(angle)*offset)
        label.rotate(by:.radians(angle))
        let text = Text(layoutCM((b-a).length)).font(.system(size:10,weight:.semibold)).foregroundStyle(color)
        let resolved = label.resolve(text), size = resolved.measure(in:CGSize(width:150,height:18))
        label.fill(Path(roundedRect:CGRect(x:-size.width/2-3,y:-size.height/2-1,width:size.width+6,height:size.height+2),cornerRadius:3),with:.color(Color(.secondarySystemGroupedBackground).opacity(0.9)))
        label.draw(resolved,at:.zero)
    }

    private func drawWallPointDimensions(context:inout GraphicsContext,point:LayoutPoint,surface:Surface2D,viewport:LayoutViewport) {
        guard let span=LayoutWallLighting.span(at:point,surface:surface) else { return }
        let floor=LayoutPoint(x:point.x,y:surface.bounds.min.y)
        for (a,b) in [(span.start,point),(point,span.end),(floor,point)] {
            var line=Path(); line.move(to:viewport.screen(a)); line.addLine(to:viewport.screen(b))
            context.stroke(line,with:.color(.orange.opacity(0.65)),style:.init(lineWidth:0.8,dash:[3,3]))
            drawAlongDimension(context:&context,a:a,b:b,viewport:viewport,color:.orange,offset:15)
        }
    }

    private func wallCursor(_ finger:CGPoint,document:LayoutDocument,viewport:LayoutViewport) -> LayoutPoint {
        let point=viewport.world(.init(x:finger.x-64,y:finger.y))
        guard snapSpots else { return point }
        return LayoutWallLighting.snapped(point,lighting:document.lighting,surface:document.surface,tolerance:14/viewport.scale)
    }
    private func addWallPoint(_ point:LayoutPoint) {
        guard var copy=model.document else { return }
        do {
            copy.lighting=try LayoutPlanning.addingSpot(to:copy.lighting,at:point,surface:copy.surface,kind:addingKind)
            model.apply(copy); spotEditError=nil
        } catch { spotEditError=error.localizedDescription }
    }

    private func drawWallDimensions(context:inout GraphicsContext,points:[LayoutPoint],surface:Surface2D,viewport:LayoutViewport,color:Color) {
        var occupied: [CGRect] = []
        for dimension in LayoutPlanning.wallDimensions(points:points,surface:surface) {
            let a = viewport.screen(dimension.start), b = viewport.screen(dimension.end)
            var path = Path(); path.move(to:a); path.addLine(to:b)
            for p in [a,b] { path.move(to:.init(x:p.x-3,y:p.y+3)); path.addLine(to:.init(x:p.x+3,y:p.y-3)) }
            context.stroke(path,with:.color(color.opacity(0.8)),style:.init(lineWidth:0.8,dash:[3,3]))
            var label = CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2-8)
            for _ in 0..<6 {
                let box = CGRect(x:label.x-28,y:label.y-8,width:56,height:16)
                if !occupied.contains(where:{$0.intersects(box)}) { occupied.append(box); break }
                label.y += 16
            }
            context.draw(Text(layoutCM(dimension.distance)).font(.system(size:10,weight:.semibold)).foregroundStyle(color),at:label)
        }
    }

    private func drawFurringDimensions(context: inout GraphicsContext, surface:Surface2D, result:SheetLayoutResult, viewport:LayoutViewport) {
        guard surface.contour.indices.contains(dimensionEdge) else { return }
        let a = surface.contour[dimensionEdge], z = surface.contour[(dimensionEdge+1)%surface.contour.count]
        let winding = LayoutGeometry.area(surface.contour) >= 0 ? 1.0 : -1.0
        let start = viewport.screen(a), end = viewport.screen(z)
        let screenLength = hypot(end.x-start.x,end.y-start.y)
        let normal = CGSize(width:-winding*(end.y-start.y)/max(1,screenLength)*32,height:winding*(end.x-start.x)/max(1,screenLength)*32)
        func outward(_ p:CGPoint) -> CGPoint { .init(x:p.x+normal.width,y:p.y+normal.height) }
        var rail = Path(); rail.move(to:outward(start)); rail.addLine(to:outward(end))
        for contact in result.furring.contacts.filter({$0.edgeIndex == dimensionEdge}) {
            let p = viewport.screen(result.frame.world(contact.point)), label = outward(p)
            rail.move(to:p); rail.addLine(to:label)
            rail.move(to:.init(x:label.x-3,y:label.y+3)); rail.addLine(to:.init(x:label.x+3,y:label.y-3))
            context.draw(Text(layoutCM(contact.distance)).font(.system(size:10,weight:.semibold)).foregroundStyle(.purple),
                         at:.init(x:label.x+normal.width*0.45,y:label.y+normal.height*0.45))
        }
        context.stroke(rail,with:.color(.purple.opacity(0.8)),lineWidth:0.7)
    }

    private func nearestVertex(_ p: CGPoint, document: LayoutDocument, viewport: LayoutViewport) -> Int? {
        document.surface.contour.indices.min { a, b in
            let pa = viewport.screen(document.surface.contour[a]), pb = viewport.screen(document.surface.contour[b])
            return hypot(pa.x - p.x, pa.y - p.y) < hypot(pb.x - p.x, pb.y - p.y)
        }.flatMap { i in
            let point = viewport.screen(document.surface.contour[i])
            return hypot(point.x - p.x, point.y - p.y) < 28 ? i : nil
        }
    }
    private func tapped(_ p: CGPoint, document: LayoutDocument, viewport: LayoutViewport) {
        if mode == .lighting, document.surface.kind == .wall,
           drag != nil || Date()<ignoreWallTapUntil { return }
        if visibility.framing.showsDimensions, mode == .framing || mode == .move,
           let callout=framingCallouts(document:document,viewport:viewport).first(where:{$0.rect.insetBy(dx:-8,dy:-10).contains(p)}) {
            sheet = .framingDistance(callout.dimension); return
        }
        if mode == .lighting && addingSpot && visibility.electrical.isVisible {
            if document.surface.kind == .wall {
                addWallPoint(wallCursor(p,document:document,viewport:viewport)); return
            }
            do {
                var copy = document
                copy.lighting = try LayoutPlanning.addingSpot(to:document.lighting,at:viewport.world(p),surface:document.surface,kind:addingKind)
                model.apply(copy); spotEditError = nil
            } catch { spotEditError = error.localizedDescription }
            return
        }
        if mode == .lighting {
            guard visibility.electrical.isVisible else { return }
            if let i = nearestSpot(p,document:document,viewport:viewport) {
                if document.surface.kind == .wall, !selectSpotsByBox { sheet = .wallPoint(i); return }
                if selectedSpots.contains(i) { selectedSpots.remove(i); referenceSpot = selectedSpots.sorted().last }
                else { selectedSpots.insert(i); referenceSpot = i }
            } else { selectedSpots = []; referenceSpot = nil }
            spotEditError = nil
            return
        }
        if mode == .contour {
            selectedVertex = nearestVertex(p, document: document, viewport: viewport)
            if let selectedVertex { sheet = .vertex(selectedVertex) }
            return
        }
        guard mode == .move || mode == .openings else { return }
        let point = viewport.world(p)
        if mode == .openings, visibility.openings.isVisible {
            if let opening = document.surface.openings.last(where: { LayoutGeometry.contains(point, in:$0.contour) }) { sheet = .opening(opening.id) }
            return
        }
        guard mode == .move, visibility.sheets.isVisible else { return }
        guard !model.isCalculating, let result = model.result else { return }
        for placement in result.sheets {
            if let piece = placement.pieces.first(where: { $0.contains(result.frame.local(point)) }) {
                sheet = .cut(.make(sheet:placement,piece:piece,lighting:document.lighting,frame:result.frame,wall:document.surface.kind == .wall,placements:result.sheets)); return
            }
        }
    }
    private func dragChanged(_ value: DragGesture.Value, document: LayoutDocument, viewport: LayoutViewport) {
        guard !pinching, rotationStart == nil, !model.isOptimizing else { return }
        if mode == .lighting, addingSpot, document.surface.kind == .wall, visibility.electrical.isVisible {
            if drag == nil { drag = .init(document:document,viewport:viewport,vertex:nil,opening:nil,initialPan:pan) }
            pendingWallPoint=wallCursor(value.location,document:drag!.document,viewport:drag!.viewport)
            wallDragFinger=value.location
            return
        }
        if mode == .lighting, selectSpotsByBox, let lighting=document.lighting {
            let box=CGRect(x:min(value.startLocation.x,value.location.x),y:min(value.startLocation.y,value.location.y),
                width:abs(value.location.x-value.startLocation.x),height:abs(value.location.y-value.startLocation.y))
            spotSelectionBox=box
            selectedSpots=Set(lighting.positions.indices.filter { box.contains(viewport.screen(lighting.positions[$0])) })
            referenceSpot=selectedSpots.sorted().last
            return
        }
        if drag == nil {
            let vertex = mode == .contour ? nearestVertex(value.startLocation, document: document, viewport: viewport) : nil
            let p = viewport.world(value.startLocation)
            let opening = mode == .openings && visibility.openings.isVisible ? document.surface.openings.last(where: { LayoutGeometry.contains(p, in: $0.contour) })?.id : nil
            drag = .init(document: document, viewport: viewport, vertex: vertex, opening: opening, initialPan: pan)
            if mode == .lighting, visibility.electrical.isVisible, let i = nearestSpot(value.startLocation,document:document,viewport:viewport) {
                if document.surface.kind == .wall || !selectedSpots.contains(i) { selectedSpots = [i] }
                referenceSpot = i; drag?.spot = i; drag?.spots = selectedSpots; spotEditError = nil
            }
            if let vertex { selectedVertex = vertex }
        }
        guard let drag else { return }
        var updated = drag.document
        let delta = drag.viewport.worldDelta(value.translation)
        if mode == .lighting, let i = drag.spot, let lighting = drag.document.lighting {
            if document.surface.kind == .wall {
                let target=wallCursor(value.location,document:drag.document,viewport:drag.viewport)
                updated.lighting=LayoutPlanning.translatedLighting(lighting,indices:[i],delta:target-lighting.positions[i])
                updated.lighting?.wallRowHeights=LayoutWallLighting.heights(lighting,surface:updated.surface)
                wallDragFinger=value.location
                model.preview(updated)
                return
            }
            let snapped = snapSpots ? LayoutPlanning.snappedLightingDelta(lighting,selected:drag.spots,anchor:i,delta:delta,tolerance:8/drag.viewport.scale) : (delta:delta,guides:[])
            spotGuides = snapped.guides
            updated.lighting = LayoutPlanning.translatedLighting(lighting,indices:drag.spots,delta:snapped.delta)
        } else if mode == .grid && visibility.sheets.isVisible && LayoutPlanning.hitSupport(drag.viewport.world(value.startLocation),surface:drag.document.surface) {
            let frame = LayoutGridFrame.make(surface:drag.document.surface,layer:drag.document.layers[0])
            updated.layers[0].offset = drag.document.layers[0].offset + frame.vector(delta)
            updated.layers[0] = updated.layers[0].forSurface(updated.surface)
            if updated.surface.kind == .wall {
                updated.layers[0] = LayoutPlanning.snappedWallBoards(updated.layers[0],surface:updated.surface,tolerance:min(25,8/drag.viewport.scale))
            }
        } else if mode == .framing && visibility.framing.isVisible && LayoutPlanning.hitSupport(drag.viewport.world(value.startLocation),surface:drag.document.surface) {
            guard let f = updated.layers[0].furring else { return }
            var framingLayer=drag.document.layers[0]
            if f.usesOwnReference == true {
                framingLayer.referenceEdge=f.referenceEdge
                framingLayer.inheritedGridFrame=f.inheritedGridFrame
            }
            let frame = LayoutGridFrame.make(surface:drag.document.surface,layer:framingLayer)
            let local = frame.vector(delta)
            let acrossDelta = LayoutPlanning.alongX(updated.layers[0]) ? local.y : local.x
            updated.layers[0].furring?.offset = f.offset + acrossDelta
            if let fixed=LayoutPlanning.snappedOpeningSupport(updated.layers[0],surface:updated.surface,tolerance:min(25,8/drag.viewport.scale)) {
                updated.layers[0].furring?.offset=fixed
            } else if let result=model.result {
                let joints=result.joints.map { LayoutJoint(start:result.frame.world($0.start),end:result.frame.world($0.end)) }
                if let snapped=LayoutPlanning.snappedFurringOffset(updated.layers[0],surface:updated.surface,joints:joints,tolerance:min(25,8/drag.viewport.scale)) {
                    updated.layers[0].furring?.offset=snapped
                }
            }
        } else if mode == .contour, let i = drag.vertex {
            let p = drag.document.surface.contour[i] + delta
            updated.surface.contour[i] = .init(x: p.x.rounded(), y: p.y.rounded())
        } else if let id = drag.opening, let i = updated.surface.openings.firstIndex(where: { $0.id == id }) {
            updated.surface.openings[i].contour = drag.document.surface.openings[i].contour.map { $0 + delta }
        } else {
            let candidate = CGSize(width:drag.initialPan.width + value.translation.width,
                                   height:drag.initialPan.height + value.translation.height)
            pan = drag.viewport.constrainedPan(candidate,contour:drag.document.surface.contour)
            return
        }
        model.preview(updated)
    }

    private func nearestSpot(_ point:CGPoint, document:LayoutDocument, viewport:LayoutViewport) -> Int? {
        guard let lighting = document.lighting else { return nil }
        return lighting.positions.indices.min { a,b in
            let p = viewport.screen(lighting.positions[a]), q = viewport.screen(lighting.positions[b])
            return hypot(p.x-point.x,p.y-point.y) < hypot(q.x-point.x,q.y-point.y)
        }.flatMap { i in
            let p = viewport.screen(lighting.positions[i])
            return hypot(p.x-point.x,p.y-point.y) <= 24 ? i : nil
        }
    }

    @ViewBuilder private func sheetContent(_ destination: LayoutEditorSheet) -> some View {
        switch destination {
        case .wallPoint(let i):
            if let document=model.document, let lighting=document.lighting, lighting.positions.indices.contains(i) {
                LayoutWallPointForm(lighting:lighting,index:i,surface:document.surface) { value in
                    var copy=document; copy.lighting=value; model.apply(copy)
                }
            }
        case .framingDistance(let dimension):
            if let document=model.document, let layer=document.layers.first {
                LayoutFurringDistanceForm(value:dimension.distance) { value in
                    var copy=document
                    copy.layers[0]=try LayoutPlanning.settingFurringDistance(layer,surface:document.surface,dimension:dimension,distance:value)
                    model.apply(copy)
                }
            }
        case .parts:
            if let workbook {
                NavigationStack {
                    ScrollView {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:155))],spacing:16) {
                            ForEach(workbook.tabs) { tab in
                                Button {
                                    sheet=nil
                                    if tab.id != workbook.selectedID { performAfterSaving { workbook.select(tab.id) } }
                                } label: {
                                    VStack(alignment:.leading,spacing:8) {
                                        if let preview=tab.preview { preview.frame(height:135) }
                                        else { Image(systemName:"square.dashed").font(.largeTitle).frame(maxWidth:.infinity).frame(height:135) }
                                        HStack {
                                            Text(tab.title).font(.subheadline.weight(.semibold))
                                            if tab.id == workbook.selectedID { Image(systemName:"checkmark.circle.fill").foregroundStyle(.tint) }
                                        }.padding([.horizontal,.bottom],10)
                                    }.background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:16))
                                        .overlay(RoundedRectangle(cornerRadius:16).stroke(tab.id == workbook.selectedID ? Color.accentColor : .clear,lineWidth:2))
                                }.buttonStyle(.plain)
                            }
                        }.padding()
                        Button("Ajouter une sous-partie",systemImage:"plus") { sheet=nil; performAfterSaving(workbook.add) }
                        Button("Renommer cette sous-partie",systemImage:"pencil") { sheet=nil; performAfterSaving(workbook.rename) }
                        Button("Relations et pièces",systemImage:"link") { sheet=nil; performAfterSaving(workbook.relations) }
                    }.background(Color(.systemGroupedBackground))
                        .navigationTitle("Choisir une sous-partie").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Fermer") { sheet=nil } } }
                }
            }
        case .newSurface:
            LayoutSurfaceForm(requiredKind: requiredSupportKind) { document in
                model.startNew()
                model.apply(newDocumentConfiguration.map {
                    WorkLayoutDefaults.document(surface: document.surface, configuration: $0)
                } ?? document)
                zoom = 1; pan = .zero; selectedVertex = nil
            }
        case .settings:
            if let document = model.document, let layer = document.layers.first {
                LayoutSettingsForm(layer: layer, surface:document.surface) { value in var copy = document; copy.layers[0] = value; model.apply(copy) }.environmentObject(catalogue)
            }
        case .furring:
            if let document = model.document, let layer = document.layers.first {
                let allowsSimplifiedCeiling:Bool = {
                    guard let configuration=newDocumentConfiguration else { return true }
                    if case .ceiling = configuration { return true }
                    return false
                }()
                LayoutFurringForm(surface:document.surface,layer:layer,allowsSimplifiedCeiling:allowsSimplifiedCeiling) { value in
                    var copy = document; copy.layers[0] = value; model.apply(copy)
                }.environmentObject(catalogue)
            }
        case .lighting:
            if let document = model.document, let layer = document.layers.first {
                if document.surface.kind == .wall {
                    LayoutWallElectricalForm(surface:document.surface,layer:layer,lighting:document.lighting) { value in
                        var copy = document; copy.lighting = value; model.apply(copy)
                        mode = .lighting; selectedSpots = []; referenceSpot = nil
                    }
                } else {
                LayoutLightingForm(surface:document.surface,layer:layer,settings:document.lighting) { value in
                    var copy = document; copy.lighting = value; model.apply(copy)
                    mode = .lighting; selectedSpots = []; referenceSpot = nil
                }
                }
            }
        case .lightingSpacing(let selected):
            if let document = model.document, let layer = document.layers.first, let lighting = document.lighting {
                LayoutLightingSpacingForm(surface:document.surface,layer:layer,lighting:lighting,selected:selected) { value in
                    var copy = document; copy.lighting = value; model.apply(copy)
                }
            }
        case .opening(let id):
            if let document = model.document {
                LayoutOpeningForm(support: document.surface.kind, existing: document.surface.openings.first { $0.id == id }, surfaceContour: document.surface.contour, alignedEdge: viewAlignedEdge, displayRotation: rotation) { opening in
                    var copy = document
                    if let i = copy.surface.openings.firstIndex(where: { $0.id == opening.id }) { copy.surface.openings[i] = opening }
                    else { copy.surface.openings.append(opening) }
                    model.apply(copy)
                } onDelete: {
                    var copy = document; copy.surface.openings.removeAll { $0.id == id }; model.apply(copy)
                }
            }
        case .vertex(let index):
            if let document = model.document, document.surface.contour.indices.contains(index) {
                LayoutVertexForm(index: index, contour: document.surface.contour) { p in model.editVertices(p); selectedVertex = nil }
            }
        case .correction(let index):
            if let correction = model.document?.surface.dimensionCorrections.first(where: { $0.edgeIndex == index }) {
                LayoutCorrectionDetail(correction: correction, edgeCount: model.document?.surface.contour.count ?? 1)
            }
        case .cut(let selection): LayoutCutDetail(selection: selection)
        case .furringDimensions:
            NavigationStack {
                List {
                    if let document = model.document, let result = model.result {
                        Section {
                            Text("Distances cumulées depuis le premier angle de chaque mur, en centimètres. Les fourrures sont interrompues aux ouvertures. Repérage géométrique, sans validation de l’ossature.").font(.footnote)
                        }
                        ForEach(document.surface.contour.indices,id:\.self) { i in
                            Section("Mur \(vertexName(i))–\(vertexName((i+1)%document.surface.contour.count)) · depuis \(vertexName(i))") {
                                let contacts = result.furring.contacts.filter{$0.edgeIndex == i}.sorted{$0.distance < $1.distance}
                                if contacts.isEmpty { Text("Aucun croisement sur ce mur.").foregroundStyle(.secondary) }
                                ForEach(Array(contacts.enumerated()),id:\.offset) { index,contact in
                                    LabeledContent("Repère \(index+1)",value:layoutCM(contact.distance))
                                }
                            }
                        }
                    }
                }.navigationTitle("Repères des fourrures").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fermer") { sheet = nil } } }
            }
        case .pieces:
            NavigationStack {
                List {
                    if let result = model.result {
                        Section {
                            LabeledContent("Plaques à acheter", value: "\(result.purchasedSheetCount)")
                            LabeledContent("Plaques économisées par réemploi",value:"\(result.savedSheetCount)")
                            LabeledContent("Morceaux à poser", value: "\(result.pieceCount)")
                            LabeledContent("Surface nette", value: layoutArea(result.netArea))
                            LabeledContent("Isolant · surface de pose", value: layoutArea(result.netArea))
                            LabeledContent("Restes après découpe", value: layoutArea(result.wasteArea))
                            Text("2-1 et 2-2 sont deux morceaux d’une même plaque.").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(Array(1..<(result.purchasedSheetCount+1)),id:\.self) { number in
                            Section("Plaque \(number)") {
                              ForEach(result.sheets) { placement in
                                ForEach(placement.pieces.filter { ($0.stock?.number ?? placement.number)==number }) { piece in
                                    Button {
                                        sheet = .cut(.make(sheet:placement,piece:piece,lighting:model.document?.lighting,frame:result.frame,wall:model.document?.surface.kind == .wall,placements:result.sheets))
                                    } label: {
                                        VStack(alignment: .leading) {
                                            Text("\(placement.label(for:piece)) · \(layoutArea(piece.area))")
                                            Text("\(layoutCM(piece.bounds.width)) × \(layoutCM(piece.bounds.height))").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                              }
                            }
                        }
                    }
                }.navigationTitle("Découpes").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { sheet = nil } } }
            }
        }
    }
}
