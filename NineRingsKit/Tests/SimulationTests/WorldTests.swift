import Testing
import simd
@testable import Simulation

private let ringRadius = 12.85
private let ringWire = 1.15
private let railWire = 1.1
private let railOffset = 9.4

/// A quarter turn about the vertical, which stands a ring across the rails with its normal along them.
private let acrossTheRails = simd_quatd(angle: .pi / 2, axis: Vector(0, 1, 0))

private func addRing(to world: inout World, at position: Vector) -> Int {
    let mass = 2.633
    let body = Body(
        position: position,
        orientation: acrossTheRails,
        mass: mass,
        inertia: Vector(0.5, 0.5, 1) * mass * ringRadius * ringRadius,
        halfSize: Vector(ringRadius + ringWire, ringRadius + ringWire, ringWire)
    )
    let wire = Piece(
        shape: .circle(Circle(center: .zero, axisU: Vector(1, 0, 0), axisV: Vector(0, 1, 0), radius: ringRadius)),
        radius: ringWire
    )
    return world.add(body, pieces: [wire])
}

/// Two long rails through the origin's height, climbing toward positive x at `slope`.
private func addRails(to world: inout World, slope: Double = 0) {
    let along = Vector(cos(slope), sin(slope), 0)
    for side in [-1.0, 1.0] {
        let middle = Vector(0, 0, side * railOffset)
        world.addFixed(Piece(shape: .segment(Segment(start: middle - along * 100, end: middle + along * 100)), radius: railWire))
    }
}

private func run(_ world: inout World, seconds: Double) {
    for _ in 0..<Int((seconds * 60).rounded()) {
        world.advance(by: 1.0 / 60)
    }
}

/// How far the ring's surface is from a rail's: negative when the two overlap.
private func gap(between ring: Body, andRailAt side: Double) -> Double {
    let circle = Circle(
        center: ring.position,
        axisU: ring.orientation.act(Vector(1, 0, 0)),
        axisV: ring.orientation.act(Vector(0, 1, 0)),
        radius: ringRadius
    )
    let rail = Segment(start: Vector(-100, 0, side * railOffset), end: Vector(100, 0, side * railOffset))
    var found: [Approach] = []
    Approaches.find(circle, rail, within: .infinity, samples: 16, into: &found)
    return (found.map(\.distance).min() ?? .infinity) - ringWire - railWire
}

@Suite struct WorldTests {
    @Test func aBodyWithNothingUnderItFalls() {
        var world = World()
        world.damping = 0
        let ring = addRing(to: &world, at: .zero)
        world.advance(by: 0.02)
        // Stepping adds each small step's speed before it moves, which lands a little past the exact fall.
        let exact = 0.5 * 9810 * 0.02 * 0.02
        #expect(world.bodies[ring].position.y < -exact)
        #expect(world.bodies[ring].position.y > -exact * 1.05)
        #expect(abs(world.bodies[ring].velocity.y + 9810 * 0.02) < 1e-6)
    }

    @Test func aRingDroppedOnTheRailsComesToRestHangingFromThem() {
        var world = World()
        addRails(to: &world)
        let ring = addRing(to: &world, at: Vector(0, -3, 0))
        run(&world, seconds: 1.5)

        let body = world.bodies[ring]
        // The ring hangs where its wire rests on both rails: its middle below them by this much.
        let reach = ringRadius - ringWire - railWire
        let hang = (reach * reach - railOffset * railOffset).squareRoot()
        #expect(abs(body.position.y + hang) < 0.02)
        #expect(abs(body.position.x) < 0.05 && abs(body.position.z) < 0.05)
        #expect(simd_length(body.velocity) < 1)
        #expect(simd_length(body.angularVelocity) < 0.1)
        #expect(abs(body.orientation.act(Vector(0, 0, 1)).x) > 0.999)
    }

    @Test func aRestingRingDoesNotSinkIntoTheRails() {
        var world = World()
        addRails(to: &world)
        let ring = addRing(to: &world, at: Vector(0, -3, 0))
        var deepest = 0.0
        for _ in 0..<90 {
            world.advance(by: 1.0 / 60)
            for side in [-1.0, 1.0] {
                deepest = min(deepest, gap(between: world.bodies[ring], andRailAt: side))
            }
        }
        #expect(deepest > -0.01)
    }

    /// How far a ring dropped on sloping rails travels down them between two moments.
    private func slideDown(slopeInDegrees: Double, from start: Double, to end: Double) -> Double {
        var world = World()
        addRails(to: &world, slope: slopeInDegrees * .pi / 180)
        let ring = addRing(to: &world, at: Vector(0, -3.5, 0))
        run(&world, seconds: start)
        let before = world.bodies[ring].position.x
        run(&world, seconds: end - start)
        return before - world.bodies[ring].position.x
    }

    @Test func frictionHoldsARingOnAGentleSlope() {
        // The ring still swings a little on its two contacts for a while, which moves its middle by less than this.
        #expect(abs(slideDown(slopeInDegrees: 8, from: 1, to: 2)) < 0.1)
    }

    /// A ring hangs wedged between the two rails, which press on it with about twice its weight. So it grips
    /// about twice as well as a block on a plane would: with friction of 0.3 it holds up to some 33 degrees,
    /// where a block would slide beyond 17.
    @Test func aWedgedRingHoldsOnASlopeTooSteepForABlock() {
        #expect(abs(slideDown(slopeInDegrees: 25, from: 1, to: 2)) < 0.15)
    }

    @Test func aRingSlidesDownASteepSlope() {
        #expect(slideDown(slopeInDegrees: 40, from: 0, to: 0.3) > 20)
    }
}
