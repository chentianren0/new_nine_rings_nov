import Foundation
import Puzzle
import Testing
import Toy
import simd
@testable import Simulation

/// States that between them show every arrangement: all on, one ring off, chains of off rings of several
/// lengths, ring 9 off, the whole assembly hanging from a single ring at either end, an off ring whose eye
/// stands up between the rails (001010000), and states where ring 1 sits at the tip under a heavy load.
private let variedStates = [
    "111111111", "101111111", "000111111", "011110010", "010101010", "000100000", "000000001", "100000000",
    "001010000", "110100000", "101101000", "111001100", "101011010", "100011111",
]

private func simulate(_ state: PuzzleState, seconds: Double) -> ToySimulation {
    var toy = ToySimulation(pose: RestPoses.pose(for: state))
    for _ in 0..<Int((seconds * 60).rounded()) {
        toy.advance(by: 1.0 / 60)
    }
    return toy
}

/// The fastest any part's own origin is moving, in millimetres a second.
private func speed(of toy: ToySimulation) -> Double {
    var later = toy
    later.advance(by: 1.0 / 60)
    let before = toy.pose
    let after = later.pose
    let pairs = zip(before.rings + before.rods + [before.bar], after.rings + after.rods + [after.bar])
    return pairs.map { simd_distance($0.position, $1.position) * 60 }.max() ?? 0
}

/// What is wrong with how the rods sit in the bar and hold their rings, if anything.
private func faults(in pose: ToyPose) -> [String] {
    var faults: [String] = []
    let barNormal = pose.bar.worldDirection(SIMD3(0, 1, 0))
    for number in PuzzleState.rings {
        let rod = pose.rod(number)
        let hole = pose.bar.worldPoint(SIMD3(Dimensions.Bar.holeX(number), 0, 0))
        let down = rod.worldDirection(SIMD3(0, -1, 0))
        let upright = abs(simd_dot(down, barNormal))
        if acos(min(1, upright)) * 180 / Double.pi > 38.5 {
            faults.append("rod \(number) leans more in its hole than the hole allows")
        }
        let alongShaft = simd_dot(hole - rod.position, barNormal) / simd_dot(down, barNormal)
        if simd_distance(rod.position + down * alongShaft, hole) > Dimensions.Bar.holeRadius {
            faults.append("rod \(number) is out of its hole")
        }
        if alongShaft < Dimensions.Rod.eyeRadius || alongShaft > -Dimensions.Rod.beadCenterY {
            faults.append("rod \(number) has slid out of the bar")
        }
        let ring = pose.ring(number)
        let offset = rod.position - ring.position
        let height = simd_dot(offset, ring.worldDirection(SIMD3(0, 0, 1)))
        let inPlane = max(0, simd_length_squared(offset) - height * height).squareRoot()
        let toWire = ((inPlane - Dimensions.Ring.radius) * (inPlane - Dimensions.Ring.radius) + height * height).squareRoot()
        if toWire > Dimensions.Rod.eyeRadius {
            faults.append("eye \(number) has let go of its ring")
        }
    }
    return faults
}

/// Whether the eye of a rod still has its ring's wire through it: whether the two circles are linked. The
/// ring's circle passes through the plane of the eye at two points at most, and the two are linked exactly
/// when one of those points lies inside the eye.
private func eyeHoldsItsRing(_ number: Int, in pose: ToyPose) -> Bool {
    let ring = pose.ring(number)
    let rod = pose.rod(number)
    let eyeNormal = rod.worldDirection(SIMD3(0, 0, 1))
    let u = ring.worldDirection(SIMD3(1, 0, 0)) * Dimensions.Ring.radius
    let v = ring.worldDirection(SIMD3(0, 1, 0)) * Dimensions.Ring.radius
    let offset = simd_dot(ring.position - rod.position, eyeNormal)
    let cosine = simd_dot(u, eyeNormal)
    let sine = simd_dot(v, eyeNormal)
    let swing = (cosine * cosine + sine * sine).squareRoot()
    guard swing > abs(offset) else { return false }
    let middle = atan2(sine, cosine)
    let spread = acos(-offset / swing)
    let inside = [middle + spread, middle - spread].filter { angle in
        simd_distance(ring.position + u * cos(angle) + v * sin(angle), rod.position) < Dimensions.Rod.eyeRadius
    }
    return inside.count == 1
}

/// Whether the sword's middle line goes through the bar's sheet anywhere.
private func swordGoesThroughTheBar(in pose: ToyPose) -> Bool {
    let normal = pose.bar.worldDirection(SIMD3(0, 1, 0))
    let along = pose.bar.worldDirection(SIMD3(1, 0, 0))
    let across = pose.bar.worldDirection(SIMD3(0, 0, 1))
    let spine = (Dimensions.Bar.length - Dimensions.Bar.width) / 2
    for side in [1.0, -1.0] {
        let line = SwordShape.centerline(side: side)
        for (start, end) in zip(line, line.dropFirst()) {
            let startSide = simd_dot(start - pose.bar.position, normal)
            let endSide = simd_dot(end - pose.bar.position, normal)
            guard (startSide < 0) != (endSide < 0) else { continue }
            let point = start + (end - start) * (startSide / (startSide - endSide)) - pose.bar.position
            let x = simd_dot(point, along)
            let z = simd_dot(point, across)
            let fromSpine = SIMD2(x - simd_clamp(x, -spine, spine), z)
            if simd_length(fromSpine) < Dimensions.Bar.width / 2 { return true }
        }
    }
    return false
}

/// The deepest overlap the tests accept after an ordinary run, and the limit the simulation never exceeds.
private let overlapLimit = 0.4
private let hardOverlapLimit = 0.5 + 1e-9

@Suite struct ToySimulationTests {
    @Test(arguments: variedStates)
    func theToyHoldsTogether(_ name: String) throws {
        let state = try #require(PuzzleState(name))
        let toy = simulate(state, seconds: 3)
        #expect(toy.deepestOverlap < overlapLimit)
        #expect(toy.pose.ringsOnTheSword == state)
        #expect(faults(in: toy.pose).isEmpty)
    }

    @Test(arguments: ["111111111", "101111111", "000111111", "010101010"])
    func theToyComesToRestAndStaysThere(_ name: String) throws {
        let state = try #require(PuzzleState(name))
        var toy = simulate(state, seconds: 6)
        #expect(toy.isAtRest)
        let resting = toy.pose
        toy.advance(by: 1)
        #expect(toy.pose == resting)
    }

    @Test func aRestingToyMovesAgainOnceWoken() throws {
        var toy = simulate(.allOn, seconds: 4)
        try #require(toy.isAtRest)
        toy.wake()
        #expect(!toy.isAtRest)
        toy.advance(by: 1.0 / 60)
        #expect(!toy.isAtRest)
    }

    /// Where the whole assembly hangs from a single ring, it keeps creeping at a few millimetres a second for
    /// a long time, where real friction would lock it: the solver gives friction a little less than its due
    /// under a heavy load. Known, and waiting for the review of the solver.
    @Test(arguments: ["100000000", "000000001"])
    func aHeavilyLoadedToyStillHoldsTogetherWhileItCreeps(_ name: String) throws {
        let state = try #require(PuzzleState(name))
        let toy = simulate(state, seconds: 8)
        #expect(toy.deepestOverlap < overlapLimit)
        #expect(toy.pose.ringsOnTheSword == state)
        #expect(toy.fastestSpeed < 30)
    }

    /// A review of the solver broke an earlier version in these two ways, with only ring 9 on.
    ///
    /// A pull of 30 grams' weight on ring 5 toward the grip jams rod 9 in the slot where it narrows at the
    /// shoulder, and eye 9 was driven through ring 9.
    @Test func aPullThatJamsARodDoesNotDriveAnEyeThroughItsRing() throws {
        let state = try #require(PuzzleState("000000001"))
        var toy = ToySimulation(pose: RestPoses.pose(for: state))
        toy.pull(ring: 5, by: SIMD3(30, 0, 0))
        for _ in 0..<120 {
            toy.advance(by: 1.0 / 60)
            for number in PuzzleState.rings {
                try #require(eyeHoldsItsRing(number, in: toy.pose), "eye \(number) let go")
            }
        }
        #expect(toy.pose.ringsOnTheSword == state)
        #expect(faults(in: toy.pose).isEmpty)
        #expect(toy.deepestOverlap <= hardOverlapLimit)
    }

    /// A pull of 100 grams' weight on ring 9 toward the tip swings the bar up to the sword's tip, which went
    /// through it, because that pair was not watched.
    @Test func aHardPullDoesNotDriveTheSwordThroughTheBar() throws {
        let state = try #require(PuzzleState("000000001"))
        var toy = ToySimulation(pose: RestPoses.pose(for: state))
        toy.pull(ring: 9, by: SIMD3(-100, 0, 0))
        for _ in 0..<120 {
            toy.advance(by: 1.0 / 60)
            try #require(!swordGoesThroughTheBar(in: toy.pose))
            for number in PuzzleState.rings {
                try #require(eyeHoldsItsRing(number, in: toy.pose), "eye \(number) let go")
            }
        }
        #expect(toy.deepestOverlap <= hardOverlapLimit)
    }

    @Test func everyEyeHoldsItsRingInEveryStoredPose() {
        for bits in 0..<PuzzleState.count {
            let pose = RestPoses.pose(for: PuzzleState(bits: UInt16(bits)))
            for number in PuzzleState.rings {
                #expect(eyeHoldsItsRing(number, in: pose))
            }
            #expect(!swordGoesThroughTheBar(in: pose))
        }
    }

    @Test func theSameStartGivesTheSameMotion() {
        let first = simulate(.allOn, seconds: 0.5).pose
        let second = simulate(.allOn, seconds: 0.5).pose
        #expect(first == second)
    }

    /// With every ring off, nothing joins the rings, the rods and the bar to the sword any more. A hand holds
    /// the bar where it is, and the rings and rods settle on it instead of falling away.
    @Test func withEveryRingOffAHandHoldsTheBar() {
        let start = RestPoses.pose(for: .allOff)
        let toy = simulate(.allOff, seconds: 3)
        let pose = toy.pose
        #expect(simd_distance(pose.bar.position, start.bar.position) < 3)
        let lowest = (pose.rings + pose.rods).map(\.position.y).min() ?? 0
        #expect(lowest > start.bar.position.y - 30)
        #expect(pose.ringsOnTheSword == .allOff)
        #expect(toy.deepestOverlap < overlapLimit)
    }

    /// Every state with a ring on, three seconds each. It takes a few minutes, so it runs only when asked for:
    /// set NINE_RINGS_FULL_SWEEP in the environment. It prints a summary line for whoever asked.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_FULL_SWEEP"] != nil))
    func everyStateHoldsTogether() {
        var deepest = 0.0
        var refused = 0
        var atRest = 0
        for bits in 1..<PuzzleState.count {
            let state = PuzzleState(bits: UInt16(bits))
            let toy = simulate(state, seconds: 3)
            #expect(toy.deepestOverlap <= hardOverlapLimit, "state \(state)")
            #expect(toy.pose.ringsOnTheSword == state, "state \(state)")
            #expect(faults(in: toy.pose).isEmpty, "state \(state)")
            for number in PuzzleState.rings {
                #expect(eyeHoldsItsRing(number, in: toy.pose), "state \(state), eye \(number)")
            }
            #expect(!swordGoesThroughTheBar(in: toy.pose), "state \(state)")
            deepest = max(deepest, toy.deepestOverlap)
            refused += toy.refusedSteps
            atRest += toy.isAtRest ? 1 : 0
        }
        print("SWEEP deepest overlap \(deepest) mm, refused steps \(refused), at rest after 3 s: \(atRest) of 511")
    }
}
