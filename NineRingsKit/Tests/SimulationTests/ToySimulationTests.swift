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
    func theToyComesToRest(_ name: String) throws {
        let state = try #require(PuzzleState(name))
        #expect(speed(of: simulate(state, seconds: 3)) < 2)
    }

    @Test func theSameStartGivesTheSameMotion() {
        let first = simulate(.allOn, seconds: 0.5).pose
        let second = simulate(.allOn, seconds: 0.5).pose
        #expect(first == second)
    }

    /// With every ring off, nothing joins the rings, rods and bar to the sword any more: the puzzle is solved
    /// and the assembly comes away. Until the app gives it a hand or a table, it falls.
    @Test func withEveryRingOffTheAssemblyComesAwayFromTheSword() {
        let start = RestPoses.pose(for: .allOff)
        let toy = simulate(.allOff, seconds: 0.5)
        #expect(toy.pose.bar.position.y < start.bar.position.y - 50)
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
