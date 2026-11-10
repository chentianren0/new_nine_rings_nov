import Puzzle
import simd

extension ToyPose {
    /// Which rings are on the sword, read from where the parts are.
    ///
    /// A ring is on when both rails pass through it. The sword is one closed loop of wire and a ring is never
    /// linked with it, so the sword passes through a ring on both sides or on neither.
    public var ringsOnTheSword: PuzzleState {
        var bits: UInt16 = 0
        for number in PuzzleState.rings where Self.swordSides.allSatisfy({ Self.passes($0, through: ring(number)) }) {
            bits |= 1 << (number - 1)
        }
        return PuzzleState(bits: bits)
    }

    private static let swordSides = [SwordShape.centerline(side: 1), SwordShape.centerline(side: -1)]

    /// Whether a path of straight pieces goes through the disc that a ring spans, an odd number of times.
    private static func passes(_ path: [SIMD3<Double>], through ring: PartPose) -> Bool {
        let normal = ring.worldDirection(SIMD3(0, 0, 1))
        var through = false
        for (start, end) in zip(path, path.dropFirst()) {
            let startSide = simd_dot(start - ring.position, normal)
            let endSide = simd_dot(end - ring.position, normal)
            guard (startSide < 0) != (endSide < 0) else { continue }
            let point = start + (end - start) * (startSide / (startSide - endSide))
            if simd_distance(point, ring.position) < Dimensions.Ring.radius {
                through.toggle()
            }
        }
        return through
    }
}
