extension PuzzleState {
    /// What stops a ring from moving.
    public enum Block: Hashable, Sendable {
        /// An earlier ring is still on, so its rod stands in the slot between the ring and the tip.
        case earlierRingOn(Int)
        /// The ring just before is off, so its rod is out of the slot and cannot guide the ring through.
        case previousRingOff(Int)
    }

    /// What stops `ring` from moving, or `nil` when it can move.
    ///
    /// Ring 1 can always move. Ring k can move only when ring k−1 is on and rings 1 to k−2 are off.
    /// When both conditions fail, the earlier ring is reported: sliding toward the tip, the ring meets that rod first.
    public func block(for ring: Int) -> Block? {
        precondition(Self.rings.contains(ring), "rings are numbered 1 to 9")
        guard ring > 1 else { return nil }
        if let earlier = (1..<(ring - 1)).last(where: isOn) {
            return .earlierRingOn(earlier)
        }
        return isOn(ring - 1) ? nil : .previousRingOff(ring - 1)
    }

    public func canMove(_ ring: Int) -> Bool {
        block(for: ring) == nil
    }

    /// The rings that can move: ring 1, and the ring after the first one that is on.
    public var movableRings: [Int] {
        Self.rings.filter(canMove)
    }

    /// The state after `ring` goes on or comes off. The move must be legal.
    public func moving(_ ring: Int) -> PuzzleState {
        precondition(canMove(ring), "ring \(ring) cannot move in state \(self)")
        return PuzzleState(bits: bits ^ Self.mask(ring))
    }
}
