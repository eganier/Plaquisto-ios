import Foundation

/// Portable boundary: upright RGB bytes in, normalized top-left polylines out.
/// No Vision/CoreML object is part of the model or the Android contract.
struct BeforeAfterGuideRaster {
    let width: Int
    let height: Int
    let rgba: [UInt8]
}
struct BeforeAfterGuide: Equatable {
    var lines: [[BeforeAfterPoint]]
    var isEmpty: Bool { lines.isEmpty }
}
protocol BeforeAfterGuideExtracting {
    func extract(_ raster: BeforeAfterGuideRaster) throws -> BeforeAfterGuide
}
struct BeforeAfterGuideFit: Equatable {
    let width: Int, height: Int, x: Int, y: Int
    init?(width:Int,height:Int) {
        guard width > 0, height > 0, width <= 4000, height <= 4000 else { return nil }
        let scale = 512/Double(max(width,height))
        self.width = max(1,Int((Double(width)*scale).rounded()))
        self.height = max(1,Int((Double(height)*scale).rounded()))
        x = (512-self.width)/2; y = (512-self.height)/2
    }
}
enum BeforeAfterGuideFailure: LocalizedError {
    case unavailable, invalidInput
    var errorDescription: String? { "Le guide simplifié est indisponible. Vous pouvez prendre la photo manuellement." }
}

/// Same post-processing can be applied to CoreML or ONNX probabilities.
enum BeforeAfterGuideTracing {
    static func trace(probabilities: [Float], width w: Int, height h: Int) -> BeforeAfterGuide {
        guard w >= 8, h >= 8, w <= 512, h <= 512, probabilities.count == w*h else { return .init(lines:[]) }
        var mask = probabilities.map { $0.isFinite && $0 >= 0.80 ? UInt8(1) : 0 }
        // Dense repeated patterns (slats/textiles) are not useful framing guides.
        var integral = [Int](repeating:0,count:(w+1)*(h+1))
        for y in 0..<h {
            var row = 0
            for x in 0..<w { row += Int(mask[y*w+x]); integral[(y+1)*(w+1)+x+1] = integral[y*(w+1)+x+1]+row }
        }
        var dense = [UInt8](repeating:0,count:w*h)
        for y in 0..<h { for x in 0..<w {
            let x0 = max(0,x-5), x1 = min(w,x+6), y0 = max(0,y-5), y1 = min(h,y+6)
            let n = integral[y1*(w+1)+x1]-integral[y0*(w+1)+x1]-integral[y1*(w+1)+x0]+integral[y0*(w+1)+x0]
            if Double(n)/Double((x1-x0)*(y1-y0)) > 0.55 { dense[y*w+x] = 1 }
        } }
        // Remove the border of a dense patch too; otherwise thinning turns its
        // surviving corners into spurious framing marks.
        for y in 0..<h { for x in 0..<w where dense[y*w+x] != 0 {
            for yy in max(0,y-5)...min(h-1,y+5) {
                for xx in max(0,x-5)...min(w-1,x+5) { mask[yy*w+xx] = 0 }
            }
        } }
        for y in 0..<h { for x in 0..<w {
            if x < 3 || x >= w-3 || y < 3 || y >= h-3 { mask[y*w+x] = 0 }
        } }
        // Zhang-Suen skeleton: convert probability ribbons to single centerlines.
        for _ in 0..<24 {
            var changed = false
            for phase in 0...1 {
                var remove: [Int] = []
                for y in 1..<h-1 { for x in 1..<w-1 {
                    let i = y*w+x
                    guard mask[i] != 0 else { continue }
                    let p = [mask[i-w],mask[i-w+1],mask[i+1],mask[i+w+1],mask[i+w],mask[i+w-1],mask[i-1],mask[i-w-1]]
                    let count = p.reduce(0) { $0+Int($1) }
                    guard count >= 2, count <= 6 else { continue }
                    let changes = (0..<8).filter { p[$0] == 0 && p[($0+1)%8] == 1 }.count
                    guard changes == 1 else { continue }
                    if phase == 0 ? (p[0]*p[2]*p[4] == 0 && p[2]*p[4]*p[6] == 0) : (p[0]*p[2]*p[6] == 0 && p[0]*p[4]*p[6] == 0) { remove.append(i) }
                } }
                if !remove.isEmpty { changed = true; for i in remove { mask[i] = 0 } }
            }
            if !changed { break }
        }
        func neighbors(_ i: Int) -> [Int] {
            let x = i%w, y = i/w
            var result: [Int] = []
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let xx = x+dx, yy = y+dy
                guard xx >= 0, xx < w, yy >= 0, yy < h, mask[yy*w+xx] != 0 else { continue }
                if dx != 0 && dy != 0 && (mask[y*w+xx] != 0 || mask[yy*w+x] != 0) { continue }
                result.append(yy*w+xx)
            } }
            return result
        }
        let active = mask.indices.filter { mask[$0] != 0 }
        let links = Dictionary(uniqueKeysWithValues:active.map { ($0,neighbors($0)) })
        var visited = Set<UInt64>(), paths: [[BeforeAfterPoint]] = []
        func key(_ a:Int,_ b:Int) -> UInt64 { UInt64(min(a,b))*UInt64(w*h)+UInt64(max(a,b)) }
        func walk(_ start:Int,_ next:Int) {
            guard !visited.contains(key(start,next)) else { return }
            var nodes = [start], previous = start, current = next
            visited.insert(key(start,next))
            while nodes.count <= w*h {
                nodes.append(current)
                let adjacent = (links[current] ?? []).filter { $0 != previous && !visited.contains(key(current,$0)) }
                let dx = Double(current%w-previous%w), dy = Double(current/w-previous/w)
                guard current != start, let n = adjacent.max(by: { a,b in
                    func alignment(_ n:Int) -> Double {
                        let nx = Double(n%w-current%w), ny = Double(n/w-current/w)
                        return (dx*nx+dy*ny)/max(1,hypot(nx,ny))
                    }
                    return alignment(a) < alignment(b)
                }) else { break }
                visited.insert(key(current,n)); previous = current; current = n
            }
            let points = nodes.map { BeforeAfterPoint(x:Double($0%w)+0.5,y:Double($0/w)+0.5) }
            let length = zip(points,points.dropFirst()).reduce(0.0) { $0+hypot($1.0.x-$1.1.x,$1.0.y-$1.1.y) }
            guard length >= max(12,Double(max(w,h))*0.032) else { return }
            let simplified = simplify(points,tolerance:1.1)
            paths.append(simplified.map { .init(x:$0.x/Double(w),y:$0.y/Double(h)) })
        }
        for i in active where links[i]?.count != 2 { for n in links[i] ?? [] { walk(i,n) } }
        for i in active { for n in links[i] ?? [] { walk(i,n) } }
        return .init(lines:Array(paths.prefix(300)))
    }
    static func simplify(_ points: [BeforeAfterPoint], tolerance: Double) -> [BeforeAfterPoint] {
        guard points.count > 2 else { return points }
        var keep: Set<Int> = [0,points.count-1], stack = [(0,points.count-1)]
        while let (first,last) = stack.popLast() {
            guard last > first+1 else { continue }
            let a = points[first], b = points[last], dx = b.x-a.x, dy = b.y-a.y, norm = dx*dx+dy*dy
            var farthest = first, maximum = tolerance
            for i in first+1..<last {
                let p = points[i], t = norm > 0 ? min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/norm)) : 0
                let distance = hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
                if distance > maximum { maximum = distance; farthest = i }
            }
            if farthest != first { keep.insert(farthest); stack.append((first,farthest)); stack.append((farthest,last)) }
        }
        return keep.sorted().map { points[$0] }
    }
}
