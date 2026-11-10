import Foundation
import Puzzle
import Testing
import Toy
import simd
@testable import Simulation

/// A toy in a state, left to settle from its stored pose.
private func settledToy(_ state: PuzzleState) -> ToySimulation {
    var toy = ToySimulation(pose: RestPoses.pose(for: state))
    for _ in 0..<360 {
        toy.advance(by: 1.0 / 120)
    }
    return toy
}

/// Runs a toy until it is at rest, or for `limit` seconds at most.
private func runToRest(_ toy: inout ToySimulation, limit: Double = 20) {
    var time = 0.0
    while !toy.isAtRest && time < limit {
        toy.advance(by: 1.0 / 120)
        time += 1.0 / 120
    }
}

/// Expects a toy to be whole: every rod in its hole and holding its ring, and nothing gone through anything.
private func expectWhole(_ toy: ToySimulation, _ when: Comment) {
    let pose = toy.pose
    #expect(toy.deepestOverlap <= hardOverlapLimit, when)
    #expect(faults(in: pose).isEmpty, when)
    for number in PuzzleState.rings {
        #expect(eyeHoldsItsRing(number, in: pose), "eye \(number), \(when)")
        #expect(ringIsRoundTheRodBefore(number, in: pose), "ring \(number), \(when)")
    }
    #expect(!swordGoesThroughTheBar(in: pose), when)
}

/// Has hands move a ring one way and then back, and expects the toy to read as it should after each move.
private func moveThereAndBack(ring: Int, from start: PuzzleState) {
    var toy = settledToy(start)
    #expect(toy.pose.ringsOnTheSword == start, "\(start) at the start")

    let began = toy.move(ring: ring)
    #expect(began, "\(start): a hand takes the ring")
    runToRest(&toy, limit: 40)
    #expect(!toy.handIsBusy)
    #expect(toy.pose.ringsOnTheSword == start.moving(ring), "\(start) after the first move")
    expectWhole(toy, "\(start) after the first move")

    let beganAgain = toy.move(ring: ring)
    #expect(beganAgain, "\(start): a hand takes the ring again")
    runToRest(&toy, limit: 40)
    #expect(toy.pose.ringsOnTheSword == start, "\(start) after the move back")
    expectWhole(toy, "\(start) after the move back")
    #expect(toy.refusedSteps == 0, "\(start)")
}

@Suite struct HandTests {
    /// Ring 1 with ring 2 on and off, with a chain of off rings behind it, with rings off further along,
    /// and with the bar hanging at a slant: the hand has to cope with what each does to the tip.
    @Test(arguments: ["111111111", "101111111", "100111111", "101010101", "111110000"])
    func aHandTakesRingOneOffAndPutsItBack(_ name: String) throws {
        moveThereAndBack(ring: 1, from: try #require(PuzzleState(name)))
    }

    /// The same from the other side: ring 1 hanging alone, and hanging as the last of two and of three.
    @Test(arguments: ["011111111", "001111111", "000111111"])
    func aHandPutsRingOneOnAndTakesItBackOff(_ name: String) throws {
        moveThereAndBack(ring: 1, from: try #require(PuzzleState(name)))
    }

    /// Ring 2 travels round rod 1, so a second hand first lifts ring 1 off the tip and holds it up, and puts
    /// it back afterwards: with ring 3 on and off, with ring 2 starting off, and with rings off further along.
    @Test(arguments: ["111111111", "110111111", "101111111", "100111111", "110101010"])
    func twoHandsMoveRingTwoThereAndBack(_ name: String) throws {
        moveThereAndBack(ring: 2, from: try #require(PuzzleState(name)))
    }

    /// Off the sword, ring 1 does not lie wedged in the slot: all of it is under the rails, and it hangs from
    /// its eye, which the next ring's lower arc has caught not far under them.
    @Test func aRingTakenOffHangsUnderTheSwordFromItsEye() {
        var toy = settledToy(.allOn)
        toy.move(ring: 1)
        runToRest(&toy)
        let pose = toy.pose
        let ring = pose.ring(1)
        let axis = ring.worldDirection(SIMD3(0, 0, 1))
        let top = ring.position.y + Dimensions.Ring.radius * (1 - axis.y * axis.y).squareRoot() + Dimensions.Ring.wireRadius
        #expect(top < Dimensions.Sword.railHeight - Dimensions.Sword.wireRadius)
        let eye = pose.rod(1).position
        #expect(eye.y < Dimensions.Sword.railHeight - 5 && eye.y > Dimensions.Sword.railHeight - 16)
        #expect(ring.position.y < eye.y - Dimensions.Ring.radius / 2)
        #expect(toy.isAtRest)
    }

    /// A hand says beforehand what it cannot do, and then does nothing.
    @Test func aHandDeclinesWhatItCannotDoYet() throws {
        var toy = ToySimulation(pose: RestPoses.pose(for: try #require(PuzzleState("011111111"))))
        let tookRingThree = toy.move(ring: 3)
        #expect(!tookRingThree)
        #expect(!toy.handIsBusy)
        #expect(ToySimulation.aHandCanMove(ring: 1, in: .allOn))
        #expect(ToySimulation.aHandCanMove(ring: 2, in: .allOn))
        // Ring 2 with a chain of three rings off resting on the bar.
        #expect(!ToySimulation.aHandCanMove(ring: 2, in: try #require(PuzzleState("110001111"))))
        // The bar hanging steeply from the one ring that is on.
        #expect(!ToySimulation.aHandCanMove(ring: 1, in: try #require(PuzzleState("100000000"))))
        // Ring 1 hanging as the last of a chain of four, down by the end of the bar.
        #expect(!ToySimulation.aHandCanMove(ring: 1, in: try #require(PuzzleState("000010110"))))
        // One hand at a time.
        let took = toy.move(ring: 1)
        let tookAgain = toy.move(ring: 1)
        #expect(took && !tookAgain)
    }

    /// Ring 3 cannot come off while rings 1 and 2 are on: they are in its way to the tip. A hand set to it
    /// all the same does not get it there. It waits, lets go, and has forced nothing through anything.
    @Test func aHandThatCannotGetItsRingThroughLetsGo() {
        var toy = settledToy(.allOn)
        toy.setAHand(to: 3)
        runToRest(&toy)
        #expect(!toy.handIsBusy)
        #expect(toy.pose.ringsOnTheSword.isOn(3))
        expectWhole(toy, "after the hand let go")
    }

    /// Ring 1 there and back from every state where a hand says it can move it. It takes many minutes, so
    /// it runs only when asked for: set NINE_RINGS_FULL_SWEEP in the environment.
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_FULL_SWEEP"] != nil),
        arguments: (0..<PuzzleState.count).map { PuzzleState(bits: UInt16($0)) }.filter { ToySimulation.aHandCanMove(ring: 1, in: $0) }
    )
    func aHandMovesRingOneWhereverItSaysItCan(_ state: PuzzleState) {
        moveThereAndBack(ring: 1, from: state)
    }

    /// The same for ring 2, with the second hand holding ring 1 up.
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["NINE_RINGS_FULL_SWEEP"] != nil),
        arguments: (0..<PuzzleState.count).map { PuzzleState(bits: UInt16($0)) }.filter { ToySimulation.aHandCanMove(ring: 2, in: $0) }
    )
    func twoHandsMoveRingTwoWhereverTheySayTheyCan(_ state: PuzzleState) {
        moveThereAndBack(ring: 2, from: state)
    }
}
