import Testing
import simd
@testable import Simulation

/// A small repeatable generator, so a failing case can be found again.
private struct Generator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func vector(within extent: Double) -> Vector {
        Vector(.random(in: -extent...extent, using: &self), .random(in: -extent...extent, using: &self), .random(in: -extent...extent, using: &self))
    }

    mutating func direction() -> Vector {
        while true {
            let candidate = vector(within: 1)
            let length = simd_length(candidate)
            if length > 0.1 && length <= 1 { return candidate / length }
        }
    }
}

/// The smallest distance from a curve to a core, by walking the curve in small steps.
private func smallestDistanceByWalking(_ curve: some CurveCore, _ core: some Core, steps: Int = 8_000) -> Double {
    (0...steps).reduce(Double.infinity) { smallest, index in
        let point = curve.point(at: Double(index) / Double(steps))
        return min(smallest, simd_distance(point, core.nearestPoint(to: point)))
    }
}

/// The search must never miss a smaller distance than walking finds, and walking can only be worse by its own
/// step: where two cores cross, the distance falls to zero in a sharp V that the walk steps over.
private func expectAgreement(_ found: [Approach], walked: Double, walkStep: Double, _ comment: Comment) {
    let smallest = found.map(\.distance).min() ?? .infinity
    #expect(smallest <= walked + 1e-9, comment)
    #expect(walked - smallest < walkStep, comment)
}

private func approaches(_ curve: some CurveCore, _ core: some Core, samples: Int = 16) -> [Approach] {
    var found: [Approach] = []
    Approaches.find(curve, core, within: .infinity, samples: samples, into: &found)
    return found
}

/// The sizes of the toy's own wires, so the cases look like the ones the simulation meets.
private let ringRadius = 12.85
private let eyeRadius = 3.75

@Suite struct ApproachesTests {
    @Test func aRingAndAStraightWire() {
        var generator = Generator(state: 1)
        for trial in 0..<120 {
            let ring = Circle(center: generator.vector(within: 10), normal: generator.direction(), radius: ringRadius)
            let start = generator.vector(within: 30)
            let wire = Segment(start: start, end: start + generator.direction() * Double.random(in: 5...130, using: &generator))
            let found = approaches(ring, wire)
            expectAgreement(found, walked: smallestDistanceByWalking(ring, wire), walkStep: 0.02, "trial \(trial)")
        }
    }

    @Test func twoRings() {
        var generator = Generator(state: 2)
        for trial in 0..<120 {
            let first = Circle(center: generator.vector(within: 12), normal: generator.direction(), radius: ringRadius)
            let second = Circle(center: generator.vector(within: 12), normal: generator.direction(), radius: ringRadius)
            let found = approaches(first, second)
            expectAgreement(found, walked: smallestDistanceByWalking(first, second), walkStep: 0.02, "trial \(trial)")
        }
    }

    @Test func anEyeAndARing() {
        var generator = Generator(state: 3)
        for trial in 0..<120 {
            let ring = Circle(center: .zero, normal: generator.direction(), radius: ringRadius)
            // An eye threaded on the ring's wire: its middle within reach of the wire, turned any way.
            let onWire = ring.point(at: .random(in: 0...1, using: &generator))
            let eye = Circle(center: onWire + generator.vector(within: 2), normal: generator.direction(), radius: eyeRadius)
            let found = approaches(eye, ring, samples: 12)
            expectAgreement(found, walked: smallestDistanceByWalking(eye, ring), walkStep: 0.02, "trial \(trial)")
        }
    }

    @Test func aRingAndTheBar() {
        var generator = Generator(state: 4)
        for trial in 0..<120 {
            let lengthAxis = generator.direction()
            let widthAxis = simd_normalize(simd_cross(lengthAxis, generator.direction()))
            let bar = Stadium(center: .zero, lengthAxis: lengthAxis, widthAxis: widthAxis, halfLength: 68.75, radius: 5.75)
            let ring = Circle(center: generator.vector(within: 40), normal: generator.direction(), radius: ringRadius)
            let found = approaches(ring, bar)
            expectAgreement(found, walked: smallestDistanceByWalking(ring, bar), walkStep: 0.02, "trial \(trial)")
        }
    }

    @Test func aStraightWireAndACurvedTip() {
        var generator = Generator(state: 5)
        let tip = Polyline(points: (0...24).map { step in
            let angle = Double(step) / 24 * .pi
            return Vector(9.4 * (1 - sin(angle)), 0, -9.4 * cos(angle))
        })
        for trial in 0..<120 {
            let start = generator.vector(within: 20)
            let wire = Segment(start: start, end: start + generator.direction() * Double.random(in: 5...60, using: &generator))
            let found = approaches(wire, tip, samples: 24)
            expectAgreement(found, walked: smallestDistanceByWalking(wire, tip), walkStep: 0.02, "trial \(trial)")
        }
    }

    @Test func twoRingsThatNearEachOtherInTwoPlacesGiveTwoApproaches() {
        // Two rings at right angles around one middle, the second a millimetre smaller.
        let first = Circle(center: .zero, normal: Vector(0, 0, 1), radius: ringRadius)
        let second = Circle(center: .zero, normal: Vector(0, 1, 0), radius: ringRadius - 1)
        var found: [Approach] = []
        Approaches.find(first, second, within: 2, samples: 16, into: &found)
        #expect(found.count == 2)
        for approach in found {
            #expect(abs(approach.distance - 1) < 1e-9)
        }
        #expect(simd_distance(found[0].pointA, found[1].pointA) > 2 * ringRadius - 1e-9)
    }

    @Test func aRingLyingFlatOverTheBarGetsASpreadOfApproaches() {
        // The ring is wider than the bar, so it lies over it on two sides, a tenth of a millimetre above.
        let bar = Stadium(center: .zero, lengthAxis: Vector(1, 0, 0), widthAxis: Vector(0, 0, 1), halfLength: 68.75, radius: 5.75)
        let ring = Circle(center: Vector(0, 0.1, 0), axisU: Vector(1, 0, 0), axisV: Vector(0, 0, 1), radius: ringRadius)
        var found: [Approach] = []
        Approaches.find(ring, bar, within: 0.5, samples: 16, into: &found)
        #expect(found.count >= 4)
        for approach in found {
            #expect(abs(approach.distance - 0.1) < 1e-9)
        }
        #expect(found.contains { $0.pointA.x > 10 } && found.contains { $0.pointA.x < -10 })
    }

    @Test func aRingAroundALineThroughItsMiddleIsEquallyNearAllRound() {
        let ring = Circle(center: .zero, normal: Vector(1, 0, 0), radius: ringRadius)
        let rail = Segment(start: Vector(-50, 0, 0), end: Vector(50, 0, 0))
        let found = approaches(ring, rail)
        #expect(found.count == 16)
        for approach in found {
            #expect(abs(approach.distance - ringRadius) < 1e-9)
        }
    }

    @Test func theEndOfAStraightWireIsFound() {
        let ring = Circle(center: .zero, normal: Vector(0, 0, 1), radius: ringRadius)
        // A wire pointing at the ring's wire from outside and stopping half a millimetre short of it.
        let wire = Segment(start: Vector(40, 0, 0), end: Vector(ringRadius + 0.5, 0, 0))
        var found: [Approach] = []
        Approaches.find(wire, ring, within: 1, samples: 8, into: &found)
        #expect(found.count == 1)
        #expect(abs((found.first?.distance ?? 0) - 0.5) < 1e-9)
    }

    @Test func nothingBeyondReachIsReported() {
        let ring = Circle(center: .zero, normal: Vector(0, 0, 1), radius: ringRadius)
        let far = Segment(start: Vector(40, -10, 0), end: Vector(40, 10, 0))
        var found: [Approach] = []
        Approaches.find(ring, far, within: 5, samples: 16, into: &found)
        #expect(found.isEmpty)
    }
}

@Suite struct SegmentPairTests {
    @Test func agreesWithWalkingBothPieces() {
        var generator = Generator(state: 7)
        for _ in 0..<500 {
            let startA = generator.vector(within: 20)
            let startB = generator.vector(within: 20)
            let a = Segment(start: startA, end: startA + generator.direction() * Double.random(in: 0.5...60, using: &generator))
            let b = Segment(start: startB, end: startB + generator.direction() * Double.random(in: 0.5...60, using: &generator))
            let nearest = Approaches.nearest(a, b)
            #expect(abs(nearest.distance - smallestDistanceByWalking(a, b, steps: 4_000)) < 1e-3)
            #expect(abs(nearest.distance - simd_distance(nearest.pointA, b.nearestPoint(to: nearest.pointA))) < 1e-9)
            #expect(abs(nearest.distance - simd_distance(nearest.pointB, a.nearestPoint(to: nearest.pointB))) < 1e-9)
        }
    }

    @Test func parallelAndPointLikePieces() {
        let a = Segment(start: Vector(0, 0, 0), end: Vector(10, 0, 0))
        let parallel = Segment(start: Vector(3, 2, 0), end: Vector(20, 2, 0))
        #expect(abs(Approaches.nearest(a, parallel).distance - 2) < 1e-12)
        let point = Segment(start: Vector(5, 3, 4), end: Vector(5, 3, 4))
        #expect(abs(Approaches.nearest(a, point).distance - 5) < 1e-12)
        #expect(abs(Approaches.nearest(point, a).distance - 5) < 1e-12)
    }
}
