/// Which of the nine rings are on the sword.
///
/// Ring 1 is nearest the tip and ring 9 nearest the grip.
public struct PuzzleState: Hashable, Sendable {
    public static let ringCount = 9
    public static let rings = 1...ringCount

    public static let allOn = PuzzleState(bits: (1 << ringCount) - 1)
    public static let allOff = PuzzleState(bits: 0)

    /// Bit `k - 1` is set when ring `k` is on.
    public let bits: UInt16

    public init(bits: UInt16) {
        precondition(bits < 1 << Self.ringCount, "a state has nine rings")
        self.bits = bits
    }

    public func isOn(_ ring: Int) -> Bool {
        bits & Self.mask(ring) != 0
    }

    static func mask(_ ring: Int) -> UInt16 {
        precondition(rings.contains(ring), "rings are numbered 1 to 9")
        return 1 << (ring - 1)
    }
}

extension PuzzleState: LosslessStringConvertible {
    /// Nine characters, ring 1 first, `1` for on and `0` for off.
    public init?(_ description: String) {
        guard description.count == Self.ringCount else { return nil }
        var bits: UInt16 = 0
        for (index, character) in description.enumerated() {
            switch character {
            case "1": bits |= 1 << index
            case "0": break
            default: return nil
            }
        }
        self.init(bits: bits)
    }

    public var description: String {
        String(Self.rings.map { isOn($0) ? "1" : "0" })
    }
}
