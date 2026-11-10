import Foundation
import Puzzle
import Testing
import Toy
import simd
@testable import Simulation

/// States that between them show every arrangement: all on, one ring off, chains of off rings of several
/// lengths, ring 9 off, and the whole assembly hanging from a single ring at either end.
private let variedStates = ["111111111", "101111111", "000111111", "011110010", "010101010", "000100000", "000000001", "100000000"]

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

/// The limit on overlap that shows nothing passed through anything: under half the thinnest wire's radius.
private let overlapLimit = 0.4

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
    /// set NINE_RINGS_FULL_SWEEP in the environment.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_FULL_SWEEP"] != nil))
    func everyStateHoldsTogether() {
        for bits in 1..<PuzzleState.count {
            let state = PuzzleState(bits: UInt16(bits))
            let toy = simulate(state, seconds: 3)
            #expect(toy.deepestOverlap < overlapLimit, "state \(state)")
            #expect(toy.pose.ringsOnTheSword == state, "state \(state)")
            #expect(faults(in: toy.pose).isEmpty, "state \(state)")
        }
    }
}
