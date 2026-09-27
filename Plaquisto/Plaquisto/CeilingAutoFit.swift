import Foundation
import simd

/// Post-scan suggestions only. Samples come from the upper wall outlines on this
/// footprint, never from another ceiling or from an adjacent room's far walls.
/// The caller owns preview, undo and explicit persistence.
struct CeilingAutoFit {
    struct Sample {
        let point: RoomPoint
        let weight: Double
    }
    struct Result {
        let settings: CeilingEstimateSettings
        let estimatedRise: Bool
        init(settings: CeilingEstimateSettings, estimatedRise: Bool) {
            var saved = settings
            saved.riseIsEstimated = estimatedRise
            self.settings = saved; self.estimatedRise = estimatedRise
        }
    }
    struct Gap: Equatable {
        let wall: RoomPoint
        let ceiling: RoomPoint
    }
    let boundary: [RoomPoint]
    let floor: Double
    let samples: [Sample]
    let coverage: Double
    private let preferredAzimuth: Double
    private let defaultHeight: Double
    private let hasSlopingProfile: Bool

    init(room: PlaquistoRoomModel, proposal: WallCeilingEstimate.Proposal) {
        boundary = proposal.boundary
        floor = proposal.floorElevation
        let reference = proposal.floorElevation
        defaultHeight = proposal.suggestedHeight
        struct Segment {
            let a: RoomPoint
            let b: RoomPoint
        }
        // Keep only the upper envelope if a native contour has several vertical intervals.
        let segments: [Segment] = room.walls.filter { abs($0.start.y-reference) < 0.20 }.flatMap { wall in
            let strips = PlaquistoWallGeometry.analyze(wall:wall,room:room).strips
            return strips.filter { s in !strips.contains { other in
                other.x0 == s.x0 && other.x1 == s.x1 && other.h0+other.h1 > s.h0+s.h1
            }}.map { s in
                Segment(a:wall.start+wall.direction*s.x0+RoomPoint(x:0,y:s.h0,z:0),
                        b:wall.start+wall.direction*s.x1+RoomPoint(x:0,y:s.h1,z:0))
            }
        }
        var points: [Sample] = []
        var perimeter = 0.0, covered = 0.0, longest = 0.0, angle = 0.0
        var sloping = false
        for i in boundary.indices {
            let a = boundary[i], b = boundary[(i+1)%boundary.count]
            let length = hypot(b.x-a.x,b.z-a.z)
            guard length > 1e-6 else { continue }
            perimeter += length
            let ux = (b.x-a.x)/length, uz = (b.z-a.z)/length
            if length > longest {
                longest = length
                angle = atan2(ux,-uz) // Ridge follows the longest edge, pitch crosses it.
            }
            struct Match {
                let lo: Double; let hi: Double
                let start: Double; let end: Double
                let y0: Double; let y1: Double
                let distance: Double
                func height(_ t: Double) -> Double { y0+(y1-y0)*(t-start)/(end-start) }
            }
            let matches = segments.compactMap { s -> Match? in
                let start = (s.a.x-a.x)*ux+(s.a.z-a.z)*uz
                let end = (s.b.x-a.x)*ux+(s.b.z-a.z)*uz
                let distance = max(abs((s.a.x-a.x)*uz-(s.a.z-a.z)*ux),
                                   abs((s.b.x-a.x)*uz-(s.b.z-a.z)*ux))
                let lo = max(0,min(start,end)), hi = min(length,max(start,end))
                guard distance <= 0.08, hi-lo > 0.01, abs(end-start) > 0.01,
                      s.a.finite, s.b.finite, min(s.a.y,s.b.y) > reference else { return nil }
                return .init(lo:lo,hi:hi,start:start,end:end,y0:s.a.y,y1:s.b.y,distance:distance)
            }
            let cuts = Array(Set(matches.flatMap { [$0.lo,$0.hi] })).sorted()
            guard cuts.count >= 2 else { continue }
            for j in 1..<cuts.count {
                let lo = cuts[j-1], hi = cuts[j], mid = (lo+hi)/2
                guard hi-lo > 1e-6, let match = matches.filter({ $0.lo <= mid && mid <= $0.hi })
                    .min(by:{ $0.distance < $1.distance }) else { continue }
                covered += hi-lo
                if abs(match.y1-match.y0)/abs(match.end-match.start) > 0.02 { sloping = true }
                // Trapezoidal length weights avoid favouring fragmented scan walls.
                let steps = max(1,min(40,Int(ceil((hi-lo)/0.4))))
                for k in 0...steps {
                    let t = lo+(hi-lo)*Double(k)/Double(steps)
                    let weight = (hi-lo)/Double(steps)*(k == 0 || k == steps ? 0.5 : 1)
                    points.append(.init(point:.init(x:a.x+t*ux,y:match.height(t),z:a.z+t*uz),weight:weight))
                }
            }
        }
        samples = points
        coverage = perimeter > 0 ? min(1,covered/perimeter) : 0
        preferredAzimuth = angle
        hasSlopingProfile = sloping
    }

    func suggest(shape: CeilingEstimateSettings.Shape, current: CeilingEstimateSettings? = nil) -> Result {
        let height = max(0.1,min(999,weightedMedianHeight() ?? defaultHeight))
        if shape == .flat {
            return .init(settings:.init(lowHeight:height,highHeight:height),estimatedRise:false)
        }
        // Four perimeter corners cannot identify an interior ridge height. In that
        // case retain a user's existing rise, or suggest an explicit 50 cm starting value.
        let rise = current.flatMap { $0.shape != .flat && $0.isValid && $0.highHeight-$0.lowHeight > 0.1
            ? $0.highHeight-$0.lowHeight : nil } ?? 0.5
        let fallback = CeilingEstimateSettings(shape:shape,lowHeight:height,
            highHeight:min(1000,height+rise),azimuth:preferredAzimuth,ridgePosition:0.5)
        guard coverage >= 0.5, samples.count >= 4,
              shape == .singleSlope || hasSlopingProfile else { return .init(settings:fallback,estimatedRise:true) }
        struct Candidate { let settings: CeilingEstimateSettings; let cost: Double }
        var best: Candidate?
        let totalWeight = samples.reduce(0) { $0+$1.weight }
        let ys = samples.map { $0.point.y-floor }
        func evaluate(angle: Double, ridge: Double) {
            var s = fallback
            s.azimuth = atan2(sin(angle),cos(angle))
            s.ridgePosition = min(0.85,max(0.15,ridge))
            s.lowHeight = 1; s.highHeight = 2
            guard let planes = try? WallCeilingEstimate.planes(boundary:boundary,floorElevation:0,settings:s) else { return }
            let fs = samples.map { sample in planes.map { $0.height(x:sample.point.x,z:sample.point.z)-1 }.min() ?? 0 }
            guard let f0 = fs.min(), let f1 = fs.max(), f1-f0 > 0.35 else { return }
            var weights = samples.map(\.weight), low = height, rise = 0.0
            for _ in 0..<4 {
                var sw = 0.0, sf = 0.0, sy = 0.0, sff = 0.0, sfy = 0.0
                for i in fs.indices {
                    let w = weights[i], f = fs[i], y = ys[i]
                    sw += w; sf += w*f; sy += w*y; sff += w*f*f; sfy += w*f*y
                }
                let determinant = sw*sff-sf*sf
                guard determinant > sw*sw*0.005 else { return }
                rise = (sw*sfy-sf*sy)/determinant
                low = (sy-rise*sf)/sw
                for i in weights.indices {
                    let residual = abs(low+rise*fs[i]-ys[i])
                    weights[i] = samples[i].weight*min(1,0.08/max(1e-9,residual))
                }
            }
            s.lowHeight = low; s.highHeight = low+rise
            guard s.isValid, rise > 0.10 else { return }
            let cost = fs.indices.reduce(0.0) { sum, i in
                sum+samples[i].weight*loss(low+rise*fs[i]-ys[i])
            }/totalWeight
            if best == nil || cost < best!.cost-1e-12 { best = .init(settings:s,cost:cost) }
        }
        let ridges = shape == .singleSlope ? [0.5] : (0...14).map { 0.15+Double($0)*0.05 }
        // Include exact boundary directions before searching and refining other orientations.
        var angles = [preferredAzimuth]
        for i in boundary.indices {
            let d = boundary[(i+1)%boundary.count]-boundary[i]
            let a = atan2(d.z,d.x)
            angles += [a,a+Double.pi/2,a+Double.pi,a-Double.pi/2]
        }
        angles += (0..<36).map { Double($0)*Double.pi/18 }
        for a in angles { for r in ridges { evaluate(angle:a,ridge:r) } }
        for (angleStep,ridgeStep) in [(Double.pi/90,0.01),(Double.pi/360,0.0025)] {
            guard let center = best?.settings else { break }
            for da in -4...4 {
                for dr in (shape == .singleSlope ? [0] : Array(-4...4)) {
                    evaluate(angle:center.azimuth+Double(da)*angleStep,ridge:center.ridgePosition+Double(dr)*ridgeStep)
                }
            }
        }
        let flatCost = samples.reduce(0.0) { $0+$1.weight*loss(height-($1.point.y-floor)) }/totalWeight
        guard let best, best.cost < flatCost*0.7 else { return .init(settings:fallback,estimatedRise:true) }
        return .init(settings:best.settings,estimatedRise:false)
    }

    /// A few largest visible mismatches, recomputed cheaply as sliders move.
    func gaps(settings: CeilingEstimateSettings, limit: Int = 4) -> [Gap] {
        guard let planes = try? WallCeilingEstimate.planes(boundary:boundary,floorElevation:floor,settings:settings) else { return [] }
        let values = samples.compactMap { sample -> Gap? in
            let y = planes.map { $0.height(x:sample.point.x,z:sample.point.z) }.min() ?? sample.point.y
            guard abs(y-sample.point.y) > 0.05 else { return nil }
            return .init(wall:sample.point,ceiling:.init(x:sample.point.x,y:y,z:sample.point.z))
        }.sorted { abs($0.wall.y-$0.ceiling.y) > abs($1.wall.y-$1.ceiling.y) }
        var result: [Gap] = []
        for gap in values where result.count < limit {
            if !result.contains(where:{ hypot($0.wall.x-gap.wall.x,$0.wall.z-gap.wall.z) < 0.6 }) { result.append(gap) }
        }
        return result
    }

    private func weightedMedianHeight() -> Double? {
        let ordered = samples.sorted { $0.point.y < $1.point.y }
        let half = samples.reduce(0) { $0+$1.weight }/2
        var weight = 0.0
        for s in ordered { weight += s.weight; if weight >= half { return s.point.y-floor } }
        return nil
    }
    private func loss(_ residual: Double) -> Double {
        let d = abs(residual)
        return d <= 0.08 ? d*d : 0.16*d-0.0064
    }
}
