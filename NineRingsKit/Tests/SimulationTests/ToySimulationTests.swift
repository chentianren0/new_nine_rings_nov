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
                #expect(ringIsRoundTheRodBefore(number, in: toy.pose), "state \(state), ring \(number)")
            }
            #expect(!swordGoesThroughTheBar(in: toy.pose), "state \(state)")
            deepest = max(deepest, toy.deepestOverlap)
            refused += toy.refusedSteps
            atRest += toy.isAtRest ? 1 : 0
        }
        print("SWEEP deepest overlap \(deepest) mm, refused steps \(refused), at rest after 3 s: \(atRest) of 511")
    }
}
