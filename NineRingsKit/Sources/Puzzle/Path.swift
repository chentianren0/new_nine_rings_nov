/// The 512 states lie on one path: every state has at most two legal moves, one toward each end.
/// One end is all rings off, the other is only ring 9 on, and all rings on sits 341 moves from all off.
extension PuzzleState {
    public static let count = 1 << ringCount

    /// How many moves the state is from all rings off, from 0 to 511.
    ///
    /// The states along the path are the reflected Gray code, with ring 9 as the highest bit.
    public var rank: Int {
        var binary = bits
        binary ^= binary >> 1
        binary ^= binary >> 2
        binary ^= binary >> 4
        binary ^= binary >> 8
        return Int(binary)
    }

    public init(rank: Int) {
        precondition((0..<Self.count).contains(rank), "ranks run from 0 to 511")
        let binary = UInt16(rank)
        self.init(bits: binary ^ (binary >> 1))
    }

    /// The ring to move to come one move closer to `target`, or `nil` when already there.
    public func nextRing(toward target: PuzzleState) -> Int? {
        guard self != target else { return nil }
        let next = PuzzleState(rank: rank + (target.rank > rank ? 1 : -1))
        return (bits ^ next.bits).trailingZeroBitCount + 1
    }

    /// The rings to move, in order, to reach `target`. There is only one way that never turns back.
    public func moves(to target: PuzzleState) -> [Int] {
        var moves: [Int] = []
        var state = self
        while let ring = state.nextRing(toward: target) {
            moves.append(ring)
            state = state.moving(ring)
        }
        return moves
    }
}
