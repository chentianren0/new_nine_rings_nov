import simd

typealias Vector = SIMD3<Double>

/// The point, line, curve or flat region at the middle of a part of the toy.
///
/// Every solid shape in the simulation is a core swept by a radius: a ring is a circle swept by the radius of
/// its wire, a bead is a point swept by the bead's radius, the bar is a flat region swept by half its thickness.
/// Two shapes touch when their cores are as far apart as the sum of their radii, so all contact comes down to
/// the distance between cores.
protocol Core: Sendable {
    /// The point of the core nearest to `point`.
    func nearestPoint(to point: Vector) -> Vector
}

/// A core that is a curve, walked by a parameter from 0 to 1.
protocol CurveCore: Core {
    /// Whether the curve closes on itself, so that parameter 1 is parameter 0 again.
    var isClosed: Bool { get }
    func point(at parameter: Double) -> Vector
    /// The derivative of `point(at:)` by the parameter.
    func velocity(at parameter: Double) -> Vector
}

/// A single point: the middle of a bead.
struct PointCore: Core {
    var position: Vector

    func nearestPoint(to point: Vector) -> Vector { position }
}

/// A straight piece: the shaft of a rod, or a straight stretch of the sword.
struct Segment: CurveCore {
    var start: Vector
    var end: Vector

    var isClosed: Bool { false }

    func point(at parameter: Double) -> Vector {
        start + (end - start) * parameter
    }

    func velocity(at parameter: Double) -> Vector {
        end - start
    }

    func parameter(nearestTo point: Vector) -> Double {
        let direction = end - start
        let lengthSquared = simd_length_squared(direction)
        guard lengthSquared > 0 else { return 0 }
        return simd_clamp(simd_dot(point - start, direction) / lengthSquared, 0, 1)
    }

    func nearestPoint(to point: Vector) -> Vector {
        self.point(at: parameter(nearestTo: point))
    }
}

/// A circle: the centreline of a ring or of an eye.
struct Circle: CurveCore {
    var center: Vector
    /// Two unit vectors at right angles that span the circle's plane.
    var axisU: Vector
    var axisV: Vector
    var radius: Double

    var normal: Vector { simd_cross(axisU, axisV) }
    var isClosed: Bool { true }

    init(center: Vector, axisU: Vector, axisV: Vector, radius: Double) {
        self.center = center
        self.axisU = axisU
        self.axisV = axisV
        self.radius = radius
    }

    init(center: Vector, normal: Vector, radius: Double) {
        let unitNormal = simd_normalize(normal)
        // Start from the world axis the normal leans on least, so the cross product is well away from zero.
        let magnitudes = simd_abs(unitNormal)
        let helper: Vector = magnitudes.x <= magnitudes.y && magnitudes.x <= magnitudes.z
            ? Vector(1, 0, 0)
            : (magnitudes.y <= magnitudes.z ? Vector(0, 1, 0) : Vector(0, 0, 1))
        let axisU = simd_normalize(simd_cross(unitNormal, helper))
        self.init(center: center, axisU: axisU, axisV: simd_cross(unitNormal, axisU), radius: radius)
    }

    func point(at parameter: Double) -> Vector {
        let angle = 2 * Double.pi * parameter
        return center + radius * (cos(angle) * axisU + sin(angle) * axisV)
    }

    func velocity(at parameter: Double) -> Vector {
        let angle = 2 * Double.pi * parameter
        return (2 * Double.pi * radius) * (cos(angle) * axisV - sin(angle) * axisU)
    }

    func nearestPoint(to point: Vector) -> Vector {
        let offset = point - center
        let u = simd_dot(offset, axisU)
        let v = simd_dot(offset, axisV)
        let inPlane = (u * u + v * v).squareRoot()
        // On the circle's own axis every point of the circle is as near as any other.
        guard inPlane > 1e-12 else { return center + radius * axisU }
        return center + (radius / inPlane) * (u * axisU + v * axisV)
    }
}

/// A chain of straight pieces: the sword's rising, curved tip.
struct Polyline: Core {
    var points: [Vector]

    func nearestPoint(to point: Vector) -> Vector {
        var best = points[0]
        var bestDistance = Double.infinity
        for (start, end) in zip(points, points.dropFirst()) {
            let candidate = Segment(start: start, end: end).nearestPoint(to: point)
            let distance = simd_distance_squared(candidate, point)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}

/// A flat region with straight sides and half-circle ends: the bar, seen as its middle sheet.
struct Stadium: Core {
    var center: Vector
    /// Unit vector along the straight sides.
    var lengthAxis: Vector
    /// Unit vector across them, in the region's plane.
    var widthAxis: Vector
    /// Half the length of the straight sides, which is the spine the half circles are drawn around.
    var halfLength: Double
    /// Half the width, and the radius of the ends.
    var radius: Double

    var normal: Vector { simd_cross(lengthAxis, widthAxis) }

    func nearestPoint(to point: Vector) -> Vector {
        let offset = point - center
        let along = simd_dot(offset, lengthAxis)
        let across = simd_dot(offset, widthAxis)
        let spine = simd_clamp(along, -halfLength, halfLength)
        let fromSpine = SIMD2(along - spine, across)
        let distance = simd_length(fromSpine)
        let inRegion = distance <= radius ? fromSpine : fromSpine * (radius / distance)
        return center + (spine + inRegion.x) * lengthAxis + inRegion.y * widthAxis
    }
}
