import Foundation

/// The sword's centreline as points, for whatever needs to draw it or measure against it.
public enum SwordShape {
    /// One side of the sword, from the tip's outermost point to the end of the neck.
    ///
    /// The two sides meet at the first point. Between the points the centreline is straight, except along the
    /// tip's quarter circle, which `tipSegments` straight pieces follow.
    ///
    /// - Parameter side: `1` for the rail at positive z, `-1` for the one at negative z.
    public static func centerline(side: Double, tipSegments: Int = 24) -> [SIMD3<Double>] {
        precondition(side == 1 || side == -1, "a side is 1 or -1")
        precondition(tipSegments >= 1, "the tip needs at least one piece")
        typealias Sword = Dimensions.Sword
        let radius = Sword.railOffset

        var points: [SIMD3<Double>] = (0...tipSegments).map { step in
            let angle = Double(step) / Double(tipSegments) * .pi / 2
            let x = radius * (1 - cos(angle))
            return SIMD3(x, Sword.height(atX: x), side * radius * sin(angle))
        }
        points.append(SIMD3(Sword.tipRiseLength, Sword.railHeight, side * radius))
        points.append(SIMD3(Sword.railEndX, Sword.railHeight, side * radius))
        points.append(SIMD3(Sword.shoulderX, Sword.railHeight, side * Sword.wireRadius))
        points.append(SIMD3(Sword.neckEndX, Sword.railHeight, side * Sword.wireRadius))
        return points
    }
}
