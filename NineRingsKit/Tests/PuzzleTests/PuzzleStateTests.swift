import Testing
@testable import Puzzle

private let allStates = (0..<PuzzleState.count).map { PuzzleState(bits: UInt16($0)) }

@Suite struct RuleTests {
    /// The rule as the toy states it, written out separately from the code under test.
    private func canMoveByDefinition(_ state: PuzzleState, _ ring: Int) -> Bool {
        if ring == 1 { return true }
        let previousOn = state.isOn(ring - 1)
        let earlierOff = (1..<(ring - 1)).allSatisfy { !state.isOn($0) }
        return previousOn && earlierOff
    }

    @Test func ruleHoldsInEveryState() {
        for state in allStates {
            for ring in PuzzleState.rings {
                #expect(state.canMove(ring) == canMoveByDefinition(state, ring), "state \(state), ring \(ring)")
            }
        }
    }

    @Test func everyStateHasOneOrTwoMoves() {
        for state in allStates {
            let moves = state.movableRings
            let isEnd = state == .allOff || state == PuzzleState("000000001")
            #expect(moves.count == (isEnd ? 1 : 2), "state \(state)")
            #expect(moves.first == 1)
        }
    }

    @Test func blockNamesTheNearestEarlierRingFirst() {
        let state = PuzzleState("101000000")!
        #expect(state.block(for: 5) == .earlierRingOn(3))
        #expect(state.block(for: 4) == .earlierRingOn(1))
        #expect(state.block(for: 3) == .earlierRingOn(1))
        #expect(state.block(for: 2) == nil)
        #expect(state.block(for: 1) == nil)
    }

    @Test func blockNamesThePreviousRingWhenNothingEarlierIsOn() {
        #expect(PuzzleState.allOff.block(for: 2) == .previousRingOff(1))
        #expect(PuzzleState("001000000")!.block(for: 3) == .previousRingOff(2))
        #expect(PuzzleState("001000000")!.block(for: 4) == nil)
    }

    @Test func movingTogglesOnlyThatRing() {
        let state = PuzzleState.allOn.moving(2)
        #expect(state.description == "101111111")
        #expect(state.moving(2) == .allOn)
    }
}

@Suite struct PathTests {
    @Test func rankNumbersEveryStateOnce() {
        #expect(Set(allStates.map(\.rank)) == Set(0..<PuzzleState.count))
        for state in allStates {
            #expect(PuzzleState(rank: state.rank) == state)
        }
    }

    @Test func everyLegalMoveIsOneStepAlongThePath() {
        for state in allStates {
            for ring in state.movableRings {
                #expect(abs(state.moving(ring).rank - state.rank) == 1, "state \(state), ring \(ring)")
            }
        }
    }

    @Test func endsOfThePath() {
        #expect(PuzzleState.allOff.rank == 0)
        #expect(PuzzleState.allOn.rank == 341)
        #expect(PuzzleState("000000001")!.rank == 511)
    }

    @Test func solvingAllOnTakes341LegalMoves() {
        let moves = PuzzleState.allOn.moves(to: .allOff)
        #expect(moves.count == 341)
        #expect(moves.first == 1)
        var state = PuzzleState.allOn
        for ring in moves {
            #expect(state.canMove(ring))
            state = state.moving(ring)
        }
        #expect(state == .allOff)
    }

    @Test func movesToTheSameStateAreEmpty() {
        #expect(PuzzleState.allOn.moves(to: .allOn).isEmpty)
        #expect(PuzzleState.allOn.nextRing(toward: .allOn) == nil)
    }
}

@Suite struct DescriptionTests {
    @Test func stringsReadRingOneFirst() {
        let state = PuzzleState("100000000")!
        #expect(state.isOn(1))
        #expect(!state.isOn(9))
        #expect(state.bits == 1)
    }

    @Test func roundTrip() {
        for state in allStates {
            #expect(PuzzleState(state.description) == state)
        }
    }

    @Test func rejectsMalformedStrings() {
        #expect(PuzzleState("11111111") == nil)
        #expect(PuzzleState("1111111112") == nil)
        #expect(PuzzleState("11111111x") == nil)
    }
}
