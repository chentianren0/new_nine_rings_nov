import Toy
import simd

/// The sword's one wire as a single path, in millimetres in the sword's frame: from the end of one grip loop,
/// along one side of the neck and its rail, round the tip, back along the other side, to the end of the other
/// grip loop.
///
/// The rails, the tip and the neck are `SwordShape.centerline(side:)` exactly. Only the corners where the
/// rails turn in to the shoulder get small rounded bends, as a bent wire has, and the grip loops are added
/// beyond the end of the neck as decoration.
enum SwordPath {
    static func points() -> [SIMD3<Float>] {
        let near = SwordShape.centerline(side: 1) + gripLoop(side: 1)
        let far = SwordShape.centerline(side: -1) + gripLoop(side: -1)
        let wire = Array(far.reversed()) + near.dropFirst()
        return rounded(wire, radius: 3, sharperThan: 8 * .pi / 180).map { SIMD3<Float>($0) }
    }

    /// One grip loop: the wire runs straight on from the end of the neck, then turns outward round an oval
    /// and comes back to touch itself, as on the real toy.
    private static func gripLoop(side: Double) -> [SIMD3<Double>] {
        typealias Sword = Dimensions.Sword
        let wire = Sword.wireRadius
        // Half the oval's length and half its width, measured on the wire's centreline.
        let halfLength = (Sword.gripLoopLength - 2 * wire) / 2
        let halfWidth = (Sword.gripLoopSpan / 2 - 2 * wire) / 2
        let center = SIMD3(Sword.neckEndX + halfLength, Sword.railHeight, side * (wire + halfWidth))
        let steps = 96
        // Stop just short of closing, where the end of the wire lies against its start.
        let sweep = 2 * Double.pi - 0.3
        return (0...steps).map { step in
            let angle = -Double.pi / 2 + sweep * Double(step) / Double(steps)
            return center + SIMD3(halfLength * cos(angle), 0, side * halfWidth * sin(angle))
        }
    }

    /// Replaces each corner sharper than `threshold` with a smooth bend of about `radius`.
    private static func rounded(_ path: [SIMD3<Double>], radius: Double, sharperThan threshold: Double) -> [SIMD3<Double>] {
        guard path.count > 2 else { return path }
        var result = [path[0]]
        for index in 1..<(path.count - 1) {
            let corner = path[index]
            let incoming = corner - path[index - 1], outgoing = path[index + 1] - corner
            let turn = acos(min(max(simd_dot(simd_normalize(incoming), simd_normalize(outgoing)), -1), 1))
            guard turn > threshold else {
                result.append(corner)
                continue
            }
            let reach = min(radius * tan(turn / 2), 0.45 * simd_length(incoming), 0.45 * simd_length(outgoing))
            let start = corner - simd_normalize(incoming) * reach
            let end = corner + simd_normalize(outgoing) * reach
            let steps = max(2, Int((turn / (6 * .pi / 180)).rounded(.up)))
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                // A quadratic curve with the corner as its control point: close to a circular bend.
                result.append(start * (1 - t) * (1 - t) + corner * 2 * t * (1 - t) + end * t * t)
            }
        }
        result.append(path[path.count - 1])
        return result
    }
}
