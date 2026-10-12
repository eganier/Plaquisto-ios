import SceneKit
import UIKit
import SwiftUI

/// A presentation preference, deliberately separate from the thermal/GPU budget.
enum MaquetteRendering: String, CaseIterable {
    case standard, elevated
    static let preferenceKey = "maquette.rendering"
    static func resolve(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .elevated }
    static var current: Self { resolve(UserDefaults.standard.string(forKey: preferenceKey)) }
    var title: String { self == .standard ? "Standard" : "Élevé" }
}

struct MaquetteRenderingSettingsSection: View {
    @AppStorage(MaquetteRendering.preferenceKey) private var rendering = MaquetteRendering.elevated.rawValue
    var body: some View {
        Section {
            Picker("Rendu des maquettes", selection: $rendering) {
                ForEach(MaquetteRendering.allCases, id: \.rawValue) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
        } header: { Text("Graphisme 3D") } footer: {
            Text("Élevé : murs bleu clair, sol gris et contours contrastés. Standard : rendu d’origine. Les dimensions restent identiques.")
        }
    }
}

/// Keep SceneKit's native orbit, translation and pinch, but reject camera roll.
/// Filtering the public gesture type also covers controls reinstalled when the
/// scene or allowsCameraControl changes. No private SceneKit recognizer names.
class UprightSurveySceneView: SCNView {
    override func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        // SceneKit re-enables its recognizers after adding them. Simply setting
        // isEnabled=false here is insufficient; do not attach the roll handler.
        if gestureRecognizer is UIRotationGestureRecognizer {
            return
        }
        super.addGestureRecognizer(gestureRecognizer)
    }
}

/// Presentation only. Never corrects or modifies the recorded scan geometry.
/// Cached materials are immutable after publication: select by swapping variants.
@MainActor enum MaquetteStyle {
    enum Surface: Hashable { case wall, ceiling, floor }
    enum State: Hashable { case normal, selected, claimed }
    enum Quality: Equatable {
        case balanced, economical
        static var current: Self {
            let info=ProcessInfo.processInfo
            return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
                ? .economical : .balanced
        }
    }
    private struct Key: Hashable { let surface:Surface; let state:State; let translucent:Bool; let rendering:MaquetteRendering }
    private static var materials:[Key:SCNMaterial]=[:]
    private static let standardBackground=UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.10,green:0.11,blue:0.12,alpha:1)
            : UIColor(red:0.965,green:0.957,blue:0.939,alpha:1)
    }
    static var background: UIColor {
        MaquetteRendering.current == .standard ? standardBackground : UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white:0.12,alpha:1)
                : UIColor(red:0.965,green:0.975,blue:0.98,alpha:1)
        }
    }
    static func updateBackground(_ view: SCNView, dark: Bool) {
        let color = background.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        view.backgroundColor = color
        view.scene?.background.contents = color
    }
    static func material(_ surface:Surface, state:State = .normal, translucent:Bool = false,
                         rendering:MaquetteRendering = .current) -> SCNMaterial {
        let key=Key(surface:surface,state:state,translucent:translucent,rendering:rendering)
        if let existing=materials[key] { return existing }
        let value=SCNMaterial()
        value.lightingModel = .physicallyBased
        value.metalness.contents=0.0
        value.roughness.contents=surface == .floor ? 0.8 : 0.9
        value.isDoubleSided=true
        value.writesToDepthBuffer = !translucent
        if rendering == .elevated {
            value.lightingModel = surface == .floor || state == .selected ? .constant : .lambert
            switch state {
            case .selected: value.diffuse.contents=UIColor(red:1,green:0.43,blue:0.08,alpha:1)
            case .claimed: value.diffuse.contents=UIColor(red:0.64,green:0.71,blue:0.75,alpha:1)
            case .normal:
                switch surface {
                case .wall: value.diffuse.contents=UIColor(red:0.72,green:0.84,blue:0.93,alpha:1)
                case .ceiling: value.diffuse.contents=UIColor(red:0.84,green:0.9,blue:0.95,alpha:1)
                case .floor: value.diffuse.contents=UIColor(red:0.89,green:0.9,blue:0.91,alpha:1)
                }
            }
            materials[key]=value
            return value
        }
        switch state {
        case .selected: value.diffuse.contents=UIColor(red:0.9,green:0.62,blue:0.32,alpha:1)
        case .claimed: value.diffuse.contents=UIColor(red:0.63,green:0.65,blue:0.62,alpha:1)
        case .normal:
            switch surface {
            case .wall: value.diffuse.contents=UIColor(red:0.91,green:0.895,blue:0.86,alpha:1)
            case .ceiling: value.diffuse.contents=UIColor(red:0.94,green:0.925,blue:0.895,alpha:1)
            case .floor: value.diffuse.contents=floorTexture
            }
        }
        value.diffuse.wrapS = .repeat; value.diffuse.wrapT = .repeat
        value.diffuse.mipFilter = .linear
        materials[key]=value
        return value
    }
    static let outlineMaterial:SCNMaterial = {
        let value=SCNMaterial(); value.lightingModel = .constant
        value.diffuse.contents=UIColor(red:0.43,green:0.42,blue:0.39,alpha:1)
        return value
    }()
    private static let inkMaterial:SCNMaterial = {
        let material=SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents=UIColor(red:0.19,green:0.29,blue:0.37,alpha:1)
        material.writesToDepthBuffer=false
        return material
    }()
    private static let orangeOutline:SCNMaterial = {
        let material=SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents=UIColor(red:0.65,green:0.22,blue:0.025,alpha:1)
        material.writesToDepthBuffer=false
        return material
    }()
    static func outline(selected:Bool) -> SCNMaterial {
        MaquetteRendering.current == .standard ? outlineMaterial : (selected ? orangeOutline : inkMaterial)
    }
    /// Only boundary/crease edges: never draw the diagonals of coplanar triangles.
    static func featureEdges(_ points:[RoomPoint]) -> [RoomPoint] {
        struct Edge { let a:RoomPoint; let b:RoomPoint; var normals:[RoomPoint] }
        var edges:[String:Edge]=[:]
        func coordinate(_ v:Double) -> Double { let rounded=(v*100000).rounded(); return rounded == 0 ? 0 : rounded }
        func key(_ p:RoomPoint) -> String { "\(coordinate(p.x))/\(coordinate(p.y))/\(coordinate(p.z))" }
        for i in stride(from:0,to:points.count-points.count%3,by:3) {
            let a=points[i], b=points[i+1], c=points[i+2]
            guard [a,b,c].allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { continue }
            let u=b-a, v=c-a
            let n=RoomPoint(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
            guard n.length > 1e-10 else { continue }
            let normal=n*(1/n.length)
            for (p,q) in [(a,b),(b,c),(c,a)] {
                let id=[key(p),key(q)].sorted().joined(separator:"|")
                if edges[id] == nil { edges[id]=Edge(a:p,b:q,normals:[]) }
                edges[id]?.normals.append(normal)
            }
        }
        return edges.keys.sorted().flatMap { id -> [RoomPoint] in
            let edge=edges[id]!, first=edge.normals[0]
            let crease=edge.normals.dropFirst().contains { abs(first.x*$0.x+first.y*$0.y+first.z*$0.z) < 0.985 }
            return edge.normals.count == 1 || crease ? [edge.a,edge.b] : []
        }
    }
    static func attachEdges(to node:SCNNode, points:[RoomPoint]) {
        let lines=featureEdges(points)
        guard !lines.isEmpty else { return }
        let mesh=edgeGeometry(lines)
        let edges=SCNNode(geometry:mesh); edges.name="maquette.edges"; edges.categoryBitMask=2
        edges.castsShadow=false; edges.renderingOrder=1
        node.addChildNode(edges); updateEdges(on:node,selected:false)
    }
    /// Thin square strokes, batched in one mesh. Unlike coplanar lines they
    /// do not flicker against wall faces. No per-edge nodes or draw calls.
    static func edgeGeometry(_ lines:[RoomPoint]) -> SCNGeometry {
        var triangles:[RoomPoint]=[]
        func cross(_ a:RoomPoint,_ b:RoomPoint) -> RoomPoint {
            .init(x:a.y*b.z-a.z*b.y,y:a.z*b.x-a.x*b.z,z:a.x*b.y-a.y*b.x)
        }
        for i in stride(from:0,to:lines.count-lines.count%2,by:2) {
            let a=lines[i], b=lines[i+1], delta=b-a
            guard delta.length > 1e-9 else { continue }
            let direction=delta*(1/delta.length)
            let perpendicular=cross(direction,abs(direction.y) < 0.9 ? .init(x:0,y:1,z:0) : .init(x:1,y:0,z:0))
            let u=perpendicular*(0.008/perpendicular.length), v=cross(direction,u)
            let offsets=[u+v,u-v,(u+v)*(-1),v-u]
            for j in 0..<4 {
                let p=a+offsets[j], q=b+offsets[j], r=b+offsets[(j+1)%4], s=a+offsets[(j+1)%4]
                triangles += [p,q,r,p,r,s]
            }
        }
        return geometry(triangles)
    }
    static func updateEdges(on node:SCNNode, selected:Bool) {
        guard let edges=node.childNode(withName:"maquette.edges",recursively:false) else { return }
        edges.isHidden=MaquetteRendering.current == .standard
        edges.geometry?.firstMaterial=outline(selected:selected)
    }
    /// Fixed pixel budget, independent of the phone's @2x/@3x screen scale.
    static let floorTexture:UIImage = {
        let format=UIGraphicsImageRendererFormat(); format.scale=1; format.opaque=true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size:CGSize(width:512,height:512),format:format).image { ctx in
            UIColor(red:0.78,green:0.73,blue:0.64,alpha:1).setFill()
            ctx.fill(CGRect(x:0,y:0,width:512,height:512))
            for row in 0..<8 {
                let shade=CGFloat([0.0,0.015,-0.01,0.008][row%4])
                UIColor(red:0.8+shade,green:0.755+shade,blue:0.68+shade,alpha:1).setFill()
                ctx.fill(CGRect(x:0,y:row*64+1,width:512,height:62))
                UIColor(red:0.43,green:0.38,blue:0.31,alpha:0.13).setStroke()
                let joint=UIBezierPath(), x=row.isMultiple(of:2) ? 128 : 384
                joint.move(to:CGPoint(x:x,y:row*64)); joint.addLine(to:CGPoint(x:x,y:row*64+64))
                joint.lineWidth=1; joint.stroke()
                // Very subtle grain, seamless at the tile boundaries.
                for line in 0..<5 {
                    UIColor(white:0.3,alpha:0.015).setStroke()
                    let grain=UIBezierPath(), y=row*64+8+line*10
                    grain.move(to:CGPoint(x:0,y:y)); grain.addLine(to:CGPoint(x:512,y:y))
                    grain.lineWidth=1; grain.stroke()
                }
            }
        }
    }()
    static func uv(_ point:RoomPoint, origin:RoomPoint = .zero,
                   axisU:RoomPoint = .init(x:1,y:0,z:0), axisV:RoomPoint = .init(x:0,y:0,z:1),
                   period:Double = 2) -> CGPoint {
        let d=point-origin, size=period.isFinite && period>0 ? period : 2
        return CGPoint(x:(d.x*axisU.x+d.y*axisU.y+d.z*axisU.z)/size,
                       y:(d.x*axisV.x+d.y*axisV.y+d.z*axisV.z)/size)
    }
    static func geometry(_ points:[RoomPoint], textureCoordinates:[CGPoint]? = nil) -> SCNGeometry {
        let vertices=Array(points.prefix(points.count-points.count%3))
        var normals:[SCNVector3]=[]
        for i in stride(from:0,to:vertices.count,by:3) {
            let u=vertices[i+1]-vertices[i],v=vertices[i+2]-vertices[i]
            let n=RoomPoint(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
            let unit=n*(1/max(n.length,1e-12))
            normals += Array(repeating:SCNVector3(unit.x,unit.y,unit.z),count:3)
        }
        var sources=[SCNGeometrySource(vertices:vertices.map { SCNVector3($0.x,$0.y,$0.z) }),SCNGeometrySource(normals:normals)]
        if let textureCoordinates, textureCoordinates.count == points.count {
            let coordinates=Array(textureCoordinates.prefix(vertices.count))
            sources.append(SCNGeometrySource(textureCoordinates:coordinates))
        }
        return SCNGeometry(sources:sources,elements:[SCNGeometryElement(indices:vertices.indices.map(Int32.init),primitiveType:.triangles)])
    }
    static func configure(_ view:SCNView, quality:Quality) {
        // SceneKit's turntable constraints operate in world-space elevation.
        // Stop just before the pole to keep the turntable's up vector unambiguous.
        // The dedicated top view uses panning instead of orbiting.
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.worldUp = SCNVector3(0, 1, 0)
        view.defaultCameraController.minimumVerticalAngle = 0
        view.defaultCameraController.maximumVerticalAngle = 89.5
        // rotationSensitivity controls orbit too on iOS. Do not zero it to
        // suppress roll: UprightSurveySceneView disables only the twist gesture.
        view.backgroundColor=background
        view.autoenablesDefaultLighting=false
        view.rendersContinuously=false
        view.preferredFramesPerSecond=quality == .balanced ? 60 : 30
        view.antialiasingMode=quality == .balanced ? .multisampling4X : .multisampling2X
    }
    static func configure(_ camera:SCNCamera, quality:Quality) {
        camera.screenSpaceAmbientOcclusionIntensity=quality == .balanced && MaquetteRendering.current == .standard ? 0.35 : 0
        camera.screenSpaceAmbientOcclusionRadius=0.18
        camera.wantsHDR=false
        camera.bloomIntensity=0
    }
    static func installStudio(in scene:SCNScene, quality:Quality) {
        scene.background.contents=background
        scene.rootNode.childNode(withName:"studio",recursively:false)?.removeFromParentNode()
        let studio=SCNNode(); studio.name="studio"
        let flat=MaquetteRendering.current == .elevated
        let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity=flat ? 500 : 350; ambient.light?.color=UIColor.white
        studio.addChildNode(ambient)
        let sun=SCNNode(); sun.name="studio.key"; sun.light=SCNLight(); sun.light?.type = .directional
        sun.light?.intensity=flat ? 450 : 850; sun.light?.castsShadow = !flat
        sun.light?.shadowColor=UIColor.black.withAlphaComponent(0.16)
        sun.light?.shadowRadius=5; sun.light?.shadowSampleCount=quality == .balanced ? 8 : 4
        let resolution=quality == .balanced ? 1024 : 512
        sun.light?.shadowMapSize=CGSize(width:resolution,height:resolution)
        sun.eulerAngles=SCNVector3(-Float.pi/3,-Float.pi/5,0)
        studio.addChildNode(sun)
        let fill=SCNNode(); fill.light=SCNLight(); fill.light?.type = .directional
        fill.light?.intensity=170; fill.light?.color=UIColor(red:0.9,green:0.94,blue:1,alpha:1)
        fill.eulerAngles=SCNVector3(-Float.pi/5,Float.pi*0.7,0)
        studio.addChildNode(fill)
        scene.rootNode.addChildNode(studio)
    }
}
