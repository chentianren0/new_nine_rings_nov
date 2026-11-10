import Foundation
import Puzzle
import simd

extension ToyPose {
    /// Which rings are on the sword, read from where the parts are.
    ///
    /// A ring is on in two cases. It goes round both rails with its eye up at them; or it has been lifted
    /// clear above the sword, on its way over the tip, with its rod still down through the slot.
    ///
    /// It is off otherwise, and two arrangements that look like "on" are not: a ring pushed back over the tip
    /// from below goes round the rails, but its eye hangs under the sword; and the eye of a ring that hangs
    /// below can stand up between the rails from underneath without the ring being on.
    public var ringsOnTheSword: PuzzleState {
        var bits: UInt16 = 0
        for number in PuzzleState.rings where isOn(number) {
            bits |= 1 << (number - 1)
        }
        return PuzzleState(bits: bits)
    }

    private func isOn(_ number: Int) -> Bool {
        let ring = ring(number)
        let rod = rod(number)
        if Self.swordSides.allSatisfy({ Self.passes($0, through: ring) }) {
            // Round both rails. The eye of a ring that is on sits a millimetre or more above the slot; the eye
            // of one pushed over the tip from below hangs most of a ring's width under it.
            return Self.heightAboveSlot(rod.position) > -1.5 * Dimensions.Rod.eyeRadius
        }
        return Self.heightAboveSlot(ring.position) > 0 && Self.runsThroughTheSlot(rod)
    }

    private static let swordSides = [SwordShape.centerline(side: 1), SwordShape.centerline(side: -1)]

    /// How far a point is above the surface the sword's wire runs round: level along the rails, tilted where
    /// the tip rises.
    private static func heightAboveSlot(_ point: SIMD3<Double>) -> Double {
        point.y - Dimensions.Sword.height(atX: point.x)
    }

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

    /// Whether a rod, from the middle of its eye to its bead, passes down through the slot, inside the
    /// outline of the sword's wire.
    private static func runsThroughTheSlot(_ rod: PartPose) -> Bool {
        let top = rod.position
        let bottom = rod.worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0))
        let above = heightAboveSlot(top)
        let below = heightAboveSlot(bottom)
        guard above > 0, below < 0 else { return false }
        let point = top + (bottom - top) * (above / (above - below))
        return point.x > 0 && point.x <= Dimensions.Sword.shoulderX && abs(point.z) < slotHalfWidth(atX: point.x)
    }

    /// Half the distance between the middles of the sword's two wires at `x`: round at the tip, even along the
    /// rails, and closing at the shoulder.
    private static func slotHalfWidth(atX x: Double) -> Double {
        typealias Sword = Dimensions.Sword
        let offset = Sword.railOffset
        if x < offset {
            return max(0, offset * offset - (x - offset) * (x - offset)).squareRoot()
        }
        if x <= Sword.railEndX {
            return offset
        }
        let closing = (x - Sword.railEndX) / (Sword.shoulderX - Sword.railEndX)
        return offset + (Sword.wireRadius - offset) * min(1, closing)
    }
}
