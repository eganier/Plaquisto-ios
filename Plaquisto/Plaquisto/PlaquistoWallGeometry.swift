import Foundation

enum PlaquistoWallGeometry {
    struct Strip {
        let x0: Double; let x1: Double; let h0: Double; let h1: Double
        let heightSource: GeometrySource
        let manuallyValidated: Bool
    }
    struct Result { let strips: [Strip]; let gross: Double; let net: Double; let openingArea: Double }
    static func contains(_ p: RoomPoint, polygon: [RoomPoint], tolerance: Double = 0.025) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i+1)%polygon.count]
            let dx = b.x-a.x, dz = b.z-a.z, l2 = dx*dx+dz*dz
            if l2 > 1e-12 {
                let t = min(1,max(0,((p.x-a.x)*dx+(p.z-a.z)*dz)/l2))
                if hypot(p.x-a.x-t*dx,p.z-a.z-t*dz) <= tolerance { return true }
            }
            if (a.z > p.z) != (b.z > p.z), p.x < (b.x-a.x)*(p.z-a.z)/(b.z-a.z)+a.x { inside.toggle() }
        }
        return inside
    }
    static func analyze(wall: PlaquistoWall, room: PlaquistoRoomModel) -> Result {
        let length = wall.length.effectiveValue
        guard length > 0 else { return .init(strips: [], gross: 0, net: 0, openingArea: 0) }
        let pans = room.slopes.filter(\.accepted)
        var breaks = [0.0, length]
        let direction = wall.direction
        func cross(_ x: Double, _ z: Double, _ u: Double, _ v: Double) -> Double { x*v-z*u }
        for pan in pans {
            for polygon in pan.boundaries {
                for i in polygon.indices {
                    let a = polygon[i], b = polygon[(i+1)%polygon.count]
                    let ex = b.x-a.x, ez = b.z-a.z
                    let denom = cross(direction.x,direction.z,ex,ez)
                    if abs(denom) < 1e-9 { continue }
                    let ax = a.x-wall.start.x, az = a.z-wall.start.z
                    let t = cross(ax,az,ex,ez)/denom, u = cross(ax,az,direction.x,direction.z)/denom
                    if t > 1e-6 && t < length-1e-6 && u >= -1e-6 && u <= 1+1e-6 { breaks.append(t) }
                }
            }
        }
        breaks = Array(Set(breaks)).sorted()
        var strips: [Strip] = []
        for i in 1..<breaks.count {
            let lo = breaks[i-1], hi = breaks[i]
            guard hi-lo > 1e-7 else { continue }
            let midpoint = wall.start + direction*((lo+hi)/2)
            let pan = pans.filter { $0.boundaries.contains { contains(midpoint, polygon: $0) } }
                .min { $0.plane.height(x: midpoint.x,z: midpoint.z) < $1.plane.height(x: midpoint.x,z: midpoint.z) }
            func height(_ distance: Double) -> Double {
                if wall.height.manualValue != nil { return wall.height.effectiveValue }
                guard let pan else { return wall.height.effectiveValue }
                let p = wall.start+direction*distance
                return max(0,pan.plane.height(x:p.x,z:p.z)-wall.start.y)
            }
            let manual = wall.height.manualValue != nil
            strips.append(.init(x0:lo,x1:hi,h0:height(lo),h1:height(hi),
                                heightSource:manual ? .manual : (pan?.provenance.source ?? wall.height.effectiveSource),
                                manuallyValidated:manual ? wall.height.manuallyValidated : (pan?.manuallyValidated ?? wall.height.manuallyValidated)))
        }
        let openings = room.openings.filter { $0.wallID == wall.id }
        var gross = 0.0, deduction = 0.0
        for strip in strips {
            let slope = (strip.h1-strip.h0)/(strip.x1-strip.x0)
            func height(_ x: Double) -> Double { strip.h0+slope*(x-strip.x0) }
            gross += (strip.x1-strip.x0)*(strip.h0+strip.h1)/2
            var xs = [strip.x0,strip.x1]
            for o in openings {
                let left = o.positionOnWall.effectiveValue, right = left+o.width.effectiveValue
                xs += [max(strip.x0,min(strip.x1,left)),max(strip.x0,min(strip.x1,right))]
                if abs(slope) > 1e-9 {
                    for y in [o.sillHeight.effectiveValue,o.sillHeight.effectiveValue+o.height.effectiveValue] {
                        let x = strip.x0+(y-strip.h0)/slope
                        if x > strip.x0 && x < strip.x1 { xs.append(x) }
                    }
                }
            }
            xs = Array(Set(xs)).sorted()
            for j in 1..<xs.count {
                let lo = xs[j-1], hi = xs[j], mid = (lo+hi)/2
                let active = openings.filter { mid >= $0.positionOnWall.effectiveValue && mid <= $0.positionOnWall.effectiveValue+$0.width.effectiveValue }
                func unionHeight(_ x: Double) -> Double {
                    let ranges = active.map { (max(0,$0.sillHeight.effectiveValue),min(height(x),$0.sillHeight.effectiveValue+$0.height.effectiveValue)) }
                        .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
                    var total = 0.0, top = 0.0
                    for r in ranges { total += max(0,r.1-max(top,r.0)); top = max(top,r.1) }
                    return total
                }
                deduction += (hi-lo)*(unionHeight(lo)+unionHeight(hi))/2
            }
        }
        return .init(strips:strips,gross:gross,net:max(0,gross-deduction),openingArea:min(gross,deduction))
    }
    static func triangles(wall: PlaquistoWall, room: PlaquistoRoomModel) -> [RoomPoint] {
        analyze(wall:wall,room:room).strips.flatMap { strip in
            let a = wall.start+wall.direction*strip.x0, b = wall.start+wall.direction*strip.x1
            let c = b+RoomPoint(x:0,y:strip.h1,z:0), d = a+RoomPoint(x:0,y:strip.h0,z:0)
            return [a,b,c,a,c,d]
        }
    }

    // Render the complement of openings, not an opaque wall with outlines.
    // Subdivide at every opening edge and roof/rectangular-edge intersection.
    static func solidTriangles(wall: PlaquistoWall, room: PlaquistoRoomModel) -> [RoomPoint] {
        let openings = room.openings.filter { $0.wallID == wall.id }
        var result: [RoomPoint] = []
        for strip in analyze(wall:wall,room:room).strips {
            let slope = (strip.h1-strip.h0)/(strip.x1-strip.x0)
            func h(_ x:Double) -> Double { strip.h0+slope*(x-strip.x0) }
            var xs = [strip.x0,strip.x1]
            for o in openings {
                for x in [o.positionOnWall.effectiveValue,o.positionOnWall.effectiveValue+o.width.effectiveValue] {
                    if x > strip.x0 && x < strip.x1 { xs.append(x) }
                }
                if abs(slope)>1e-9 {
                    for y in [o.sillHeight.effectiveValue,o.sillHeight.effectiveValue+o.height.effectiveValue] {
                        let x = strip.x0+(y-strip.h0)/slope
                        if x > strip.x0 && x < strip.x1 { xs.append(x) }
                    }
                }
            }
            xs = Array(Set(xs)).sorted()
            for i in 1..<xs.count {
                let lo=xs[i-1],hi=xs[i],mid=(lo+hi)/2
                guard hi-lo>1e-8 else { continue }
                let ranges = openings.filter {
                    mid > $0.positionOnWall.effectiveValue && mid < $0.positionOnWall.effectiveValue+$0.width.effectiveValue
                }.map { (max(0,$0.sillHeight.effectiveValue),$0.sillHeight.effectiveValue+$0.height.effectiveValue) }
                    .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
                func band(_ lower:Double,_ upper:Double) {
                    func point(_ x:Double,_ y:Double) -> RoomPoint { wall.start+wall.direction*x+RoomPoint(x:0,y:min(h(x),y),z:0) }
                    let a=point(lo,lower),b=point(hi,lower),c=point(hi,upper),d=point(lo,upper)
                    if hi-lo>1e-8 && c.y-b.y>1e-8 { result += [a,b,c] }
                    if hi-lo>1e-8 && d.y-a.y>1e-8 { result += [a,c,d] }
                }
                var bottom=0.0
                for r in ranges {
                    if r.0>bottom { band(bottom,r.0) }
                    bottom=max(bottom,r.1)
                }
                band(bottom,max(strip.h0,strip.h1))
            }
        }
        return result
    }

    // Display thickness is not a measured business dimension when absent.
    static func displayTriangles(wall:PlaquistoWall,room:PlaquistoRoomModel) -> [RoomPoint] {
        let face=solidTriangles(wall:wall,room:room)
        let thickness=max(0.02,min(0.6,wall.thickness?.effectiveValue ?? 0.10))
        let offset=RoomPoint(x:-wall.direction.z,y:0,z:wall.direction.x)*(thickness/2)
        var result:[RoomPoint]=[]
        var edges:[String:(RoomPoint,RoomPoint,Int)]=[:]
        func key(_ p:RoomPoint) -> String { "\(Int64((p.x*1e6).rounded()))/\(Int64((p.y*1e6).rounded()))/\(Int64((p.z*1e6).rounded()))" }
        for i in stride(from:0,to:face.count,by:3) {
            let a=face[i],b=face[i+1],c=face[i+2]
            result += [a+offset,b+offset,c+offset,c-offset,b-offset,a-offset]
            for (u,v) in [(a,b),(b,c),(c,a)] {
                let k=[key(u),key(v)].sorted().joined(separator:"|")
                edges[k]=(u,v,(edges[k]?.2 ?? 0)+1)
            }
        }
        for (_,edge) in edges where edge.2==1 {
            let a=edge.0+offset,b=edge.1+offset,c=edge.1-offset,d=edge.0-offset
            result += [a,d,c,a,c,b]
        }
        return result
    }
}

enum PlaquistoSurfaceGeometry {
    static func area(of pan:PlaquistoSlope) -> Double {
        let points=pan.boundaries.flatMap { loop in
            triangles(loop.map { RoomPoint(x:$0.x,y:pan.plane.height(x:$0.x,z:$0.z),z:$0.z) })
        }
        return stride(from:0,to:points.count,by:3).reduce(0) { total,i in
            let u=points[i+1]-points[i],v=points[i+2]-points[i]
            let n=RoomPoint(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
            return total+n.length/2
        }
    }
    // Ear clipping in XZ; retains concave outlines rather than filling a bounding box.
    static func triangles(_ input:[RoomPoint]) -> [RoomPoint] {
        var polygon=input
        if polygon.count>3, let first=polygon.first, let last=polygon.last, (first-last).length<1e-8 { polygon.removeLast() }
        guard polygon.count>=3 else { return [] }
        func cross(_ a:RoomPoint,_ b:RoomPoint,_ c:RoomPoint) -> Double { (b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x) }
        let area=polygon.indices.reduce(0.0) { sum,i in
            let a=polygon[i],b=polygon[(i+1)%polygon.count]; return sum+a.x*b.z-b.x*a.z
        }
        if area<0 { polygon.reverse() }
        var output:[RoomPoint]=[]
        while polygon.count>3 {
            var found=false
            for i in polygon.indices {
                let previous=(i+polygon.count-1)%polygon.count,next=(i+1)%polygon.count
                let a=polygon[previous],b=polygon[i],c=polygon[next]
                if abs(cross(a,b,c))<1e-10 { polygon.remove(at:i); found=true; break }
                guard cross(a,b,c)>0 else { continue }
                let blocked=polygon.indices.contains { j in
                    j != previous && j != i && j != next &&
                    cross(a,b,polygon[j])>=(-1e-10) && cross(b,c,polygon[j])>=(-1e-10) && cross(c,a,polygon[j])>=(-1e-10)
                }
                if !blocked { output += [a,c,b]; polygon.remove(at:i); found=true; break }
            }
            if !found { return [] } // Do not invent a surface for an invalid contour.
        }
        if polygon.count==3 { output += [polygon[0],polygon[2],polygon[1]] }
        return output
    }
}
