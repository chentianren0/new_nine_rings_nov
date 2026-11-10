import Toy
import simd

/// A box, in millimetres in the sword's frame, around the toy.
///
/// The parts hang very differently from state to state (with only ring 1 on, everything else hangs from it far
/// below the sword), so the box is measured for a given pose: the sword's box joined with every moving part.
struct ToyBounds {
    var lower: SIMD3<Float>
    var upper: SIMD3<Float>

    var center: SIMD3<Float> { (lower + upper) / 2 }
    var size: SIMD3<Float> { upper - lower }

    /// The sword alone, with the grip loops.
    static let sword: ToyBounds = {
        let points = SwordPath.points()
        let radius = Float(Dimensions.Sword.wireRadius)
        return ToyBounds(
            lower: points.reduce(SIMD3(repeating: .infinity)) { simd_min($0, $1) } - radius,
            upper: points.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) } + radius
        )
    }()

    /// The whole toy in `pose`.
    init(_ pose: ToyPose) {
        self = Self.sword
        let ringReach = Float(Dimensions.Ring.radius + Dimensions.Ring.wireRadius)
        let eyeReach = Float(Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius)
        let bead = SIMD3(0, Dimensions.Rod.beadCenterY, 0)
        for ring in pose.rings {
            include(SIMD3<Float>(ring.position), radius: ringReach)
        }
        for rod in pose.rods {
            include(SIMD3<Float>(rod.position), radius: eyeReach)
            include(SIMD3<Float>(rod.worldPoint(bead)), radius: Float(Dimensions.Rod.beadRadius))
        }
        for end in [-1.0, 1.0] {
            include(SIMD3<Float>(pose.bar.worldPoint(SIMD3(end * Dimensions.Bar.length / 2, 0, 0))), radius: Float(Dimensions.Bar.width / 2))
        }
    }

    /// A cube of side `size` around `center`.
    init(center: SIMD3<Float>, size: Float) {
        self.init(lower: center - size / 2, upper: center + size / 2)
    }

    private init(lower: SIMD3<Float>, upper: SIMD3<Float>) {
        self.lower = lower
        self.upper = upper
    }

    /// The lowest point of any part in `pose`, without building the whole box: cheap enough for every frame.
    static func lowestPoint(of pose: ToyPose) -> Float {
        let beadBottom = Dimensions.Rod.beadCenterY - Dimensions.Rod.beadRadius
        var lowest = Double(sword.lower.y)
        for ring in pose.rings {
            lowest = min(lowest, ring.position.y - Dimensions.Ring.radius - Dimensions.Ring.wireRadius)
        }
        for rod in pose.rods {
            lowest = min(lowest, rod.worldPoint(SIMD3(0, beadBottom, 0)).y)
        }
        return Float(lowest)
    }

    private mutating func include(_ point: SIMD3<Float>, radius: Float) {
        lower = simd_min(lower, point - radius)
        upper = simd_max(upper, point + radius)
    }
}
