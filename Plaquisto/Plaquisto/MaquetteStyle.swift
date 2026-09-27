import SceneKit
import UIKit

/// Presentation only. No scan types, geometry correction or persistent styles.
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
    private struct Key: Hashable { let surface:Surface; let state:State; let translucent:Bool }
    private static var materials:[Key:SCNMaterial]=[:]
    static let background=UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.10,green:0.11,blue:0.12,alpha:1)
            : UIColor(red:0.965,green:0.957,blue:0.939,alpha:1)
    }
    static func updateBackground(_ view: SCNView, dark: Bool) {
        let color = background.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        view.backgroundColor = color
        view.scene?.background.contents = color
    }
    static func material(_ surface:Surface, state:State = .normal, translucent:Bool = false) -> SCNMaterial {
        let key=Key(surface:surface,state:state,translucent:translucent)
        if let existing=materials[key] { return existing }
        let value=SCNMaterial()
        value.lightingModel = .physicallyBased
        value.metalness.contents=0.0
        value.roughness.contents=surface == .floor ? 0.8 : 0.9
        value.isDoubleSided=true
        value.writesToDepthBuffer = !translucent
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
        view.backgroundColor=background
        view.autoenablesDefaultLighting=false
        view.rendersContinuously=false
        view.preferredFramesPerSecond=quality == .balanced ? 60 : 30
        view.antialiasingMode=quality == .balanced ? .multisampling4X : .multisampling2X
    }
    static func configure(_ camera:SCNCamera, quality:Quality) {
        camera.screenSpaceAmbientOcclusionIntensity=quality == .balanced ? 0.35 : 0
        camera.screenSpaceAmbientOcclusionRadius=0.18
        camera.wantsHDR=false
        camera.bloomIntensity=0
    }
    static func installStudio(in scene:SCNScene, quality:Quality) {
        scene.background.contents=background
        scene.rootNode.childNode(withName:"studio",recursively:false)?.removeFromParentNode()
        let studio=SCNNode(); studio.name="studio"
        let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity=350; ambient.light?.color=UIColor.white
        studio.addChildNode(ambient)
        let sun=SCNNode(); sun.name="studio.key"; sun.light=SCNLight(); sun.light?.type = .directional
        sun.light?.intensity=850; sun.light?.castsShadow=true
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
