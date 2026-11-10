import Toy
import simd

/// A short, eased glide from one pose to another, part by part. It stands in for real motion until the
/// simulation provides it, so parts may pass through each other on the way.
struct PoseBlend {
    let from: ToyPose
    let to: ToyPose
    var duration: Double = 0.45
    private(set) var elapsed: Double = 0

    init(from: ToyPose, to: ToyPose) {
        self.from = from
        self.to = to
    }

    var isFinished: Bool { elapsed >= duration }

    mutating func advance(by seconds: Double) {
        elapsed = min(elapsed + seconds, duration)
    }

    var pose: ToyPose {
        let linear = elapsed / duration
        let t = linear * linear * (3 - 2 * linear)
        return ToyPose(
            rings: zip(from.rings, to.rings).map { Self.mix($0, $1, t) },
            rods: zip(from.rods, to.rods).map { Self.mix($0, $1, t) },
            bar: Self.mix(from.bar, to.bar, t)
        )
    }

    private static func mix(_ a: PartPose, _ b: PartPose, _ t: Double) -> PartPose {
        PartPose(position: simd_mix(a.position, b.position, SIMD3(repeating: t)), orientation: simd_slerp(a.orientation, b.orientation, t))
    }
}
