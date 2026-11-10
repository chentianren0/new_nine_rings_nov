import simd

/// A place where two cores come near each other.
struct Approach: Sendable, Equatable {
    var pointA: Vector
    var pointB: Vector

    var distance: Double { simd_distance(pointA, pointB) }
}

/// Finds where cores come near each other. Two wires can touch in more than one place at once, so the search
/// returns every such place, not only the nearest.
enum Approaches {
    /// Appends the places where `curve` comes closer to `core` than `reach`.
    ///
    /// The distance from a point of the curve to the core is a function of the curve's parameter alone, because
    /// the nearest point of the core follows from the point. The search samples that function at `samples`
    /// parameters. Wherever its slope turns from falling to rising, it closes in on the minimum between the two
    /// samples. A sample that is itself within reach is a place too: that is how a curve running alongside the
    /// core, as a ring lying flat on the bar does, gets a spread of places instead of a single one, and how the
    /// end of an open curve is found. A minimum stands in for the samples on either side of it.
    ///
    /// Two minima closer together than one sample apart count as one. In each approach `pointA` is on the curve
    /// and `pointB` on the core.
    static func find(
        _ curve: some CurveCore,
        _ core: some Core,
        within reach: Double,
        samples: Int,
        into approaches: inout [Approach]
    ) {
        precondition(samples >= 3, "too few samples to tell a minimum from a slope")

        /// The nearest point of the core, and half the rate at which the squared distance to it grows along
        /// the curve. A rate too small to tell from rounding counts as none.
        func measure(at parameter: Double) -> (approach: Approach, slope: Double) {
            let point = curve.point(at: parameter)
            let nearest = core.nearestPoint(to: point)
            let velocity = curve.velocity(at: parameter)
            let slope = simd_dot(point - nearest, velocity)
            let noise = 1e-9 * simd_distance(point, nearest) * simd_length(velocity)
            return (Approach(pointA: point, pointB: nearest), abs(slope) < noise ? 0 : slope)
        }

        let step = 1 / Double(samples)
        let first = measure(at: 0)
        let firstIndex = approaches.count
        var firstIsKept = first.approach.distance < reach
        var previousIsKept = firstIsKept
        if firstIsKept {
            approaches.append(first.approach)
        }

        var previous = first
        for index in 1...samples {
            let parameter = Double(index) * step
            let closesTheCurve = curve.isClosed && index == samples
            let here = closesTheCurve ? first : measure(at: parameter)

            var minimumStandsIn = false
            if previous.slope < 0 && here.slope >= 0 {
                let minimum = measure(at: root(
                    of: { measure(at: $0).slope },
                    from: parameter - step, previous.slope,
                    to: parameter, here.slope
                )).approach
                if minimum.distance < reach {
                    if previousIsKept {
                        approaches.removeLast()
                        if approaches.count == firstIndex { firstIsKept = false }
                    }
                    approaches.append(minimum)
                    minimumStandsIn = true
                }
            }

            if closesTheCurve {
                if minimumStandsIn && firstIsKept {
                    approaches.remove(at: firstIndex)
                }
            } else {
                previousIsKept = !minimumStandsIn && here.approach.distance < reach
                if previousIsKept {
                    approaches.append(here.approach)
                }
            }
            previous = here
        }
    }

    /// Where a rising function crosses zero between two parameters, given its values there: negative at the
    /// first, zero or more at the second. A secant search that halves a stuck end's weight (the Illinois rule).
    private static func root(
        of function: (Double) -> Double,
        from lower: Double, _ valueAtLower: Double,
        to upper: Double, _ valueAtUpper: Double
    ) -> Double {
        var lower = lower, upper = upper
        var valueAtLower = valueAtLower, valueAtUpper = valueAtUpper
        var lastMoved = 0
        for _ in 0..<60 {
            guard valueAtUpper > 0, upper - lower > 1e-13 else { break }
            var middle = upper - valueAtUpper * (upper - lower) / (valueAtUpper - valueAtLower)
            if !(middle > lower && middle < upper) {
                middle = (lower + upper) / 2
            }
            let value = function(middle)
            if value < 0 {
                lower = middle
                valueAtLower = value
                if lastMoved == -1 { valueAtUpper /= 2 }
                lastMoved = -1
            } else {
                upper = middle
                valueAtUpper = value
                if lastMoved == 1 { valueAtLower /= 2 }
                lastMoved = 1
            }
        }
        return upper
    }

    /// The nearest points of two straight pieces. There is only ever one such place worth reporting.
    static func nearest(_ a: Segment, _ b: Segment) -> Approach {
        let directionA = a.end - a.start
        let directionB = b.end - b.start
        let between = a.start - b.start
        let lengthA = simd_length_squared(directionA)
        let lengthB = simd_length_squared(directionB)
        let f = simd_dot(directionB, between)

        var parameterA = 0.0
        var parameterB = 0.0
        if lengthA <= 1e-18 && lengthB <= 1e-18 {
            return Approach(pointA: a.start, pointB: b.start)
        } else if lengthA <= 1e-18 {
            parameterB = simd_clamp(f / lengthB, 0, 1)
        } else {
            let c = simd_dot(directionA, between)
            if lengthB <= 1e-18 {
                parameterA = simd_clamp(-c / lengthA, 0, 1)
            } else {
                let b = simd_dot(directionA, directionB)
                let denominator = lengthA * lengthB - b * b
                // Parallel pieces have no single nearest pair; any point of the first will do to start from.
                parameterA = denominator > 1e-12 * lengthA * lengthB
                    ? simd_clamp((b * f - c * lengthB) / denominator, 0, 1)
                    : 0
                parameterB = (b * parameterA + f) / lengthB
                if parameterB < 0 {
                    parameterB = 0
                    parameterA = simd_clamp(-c / lengthA, 0, 1)
                } else if parameterB > 1 {
                    parameterB = 1
                    parameterA = simd_clamp((b - c) / lengthA, 0, 1)
                }
            }
        }
        return Approach(pointA: a.point(at: parameterA), pointB: b.point(at: parameterB))
    }
}
