import Foundation
import Puzzle
import Toy
import simd

// What the tests look for in a pose to tell whether the toy is still whole: every rod in its hole and holding
// its ring, and nothing gone through anything.

/// What is wrong with how the rods sit in the bar and hold their rings, if anything.
func faults(in pose: ToyPose) -> [String] {
    var faults: [String] = []
    let barNormal = pose.bar.worldDirection(SIMD3(0, 1, 0))
    for number in PuzzleState.rings {
        let rod = pose.rod(number)
        let hole = pose.bar.worldPoint(SIMD3(Dimensions.Bar.holeX(number), 0, 0))
        let down = rod.worldDirection(SIMD3(0, -1, 0))
        let upright = abs(simd_dot(down, barNormal))
        if acos(min(1, upright)) * 180 / Double.pi > 38.5 {
            faults.append("rod \(number) leans more in its hole than the hole allows")
        }
        let alongShaft = simd_dot(hole - rod.position, barNormal) / simd_dot(down, barNormal)
        if simd_distance(rod.position + down * alongShaft, hole) > Dimensions.Bar.holeRadius {
            faults.append("rod \(number) is out of its hole")
        }
        if alongShaft < Dimensions.Rod.eyeRadius || alongShaft > -Dimensions.Rod.beadCenterY {
            faults.append("rod \(number) has slid out of the bar")
        }
        let ring = pose.ring(number)
        let offset = rod.position - ring.position
        let height = simd_dot(offset, ring.worldDirection(SIMD3(0, 0, 1)))
        let inPlane = max(0, simd_length_squared(offset) - height * height).squareRoot()
        let toWire = ((inPlane - Dimensions.Ring.radius) * (inPlane - Dimensions.Ring.radius) + height * height).squareRoot()
        if toWire > Dimensions.Rod.eyeRadius {
            faults.append("eye \(number) has let go of its ring")
        }
    }
    return faults
}

/// Whether the eye of a rod still has its ring's wire through it: whether the two circles are linked. The
/// ring's circle passes through the plane of the eye at two points at most, and the two are linked exactly
/// when one of those points lies inside the eye.
func eyeHoldsItsRing(_ number: Int, in pose: ToyPose) -> Bool {
    let ring = pose.ring(number)
    let rod = pose.rod(number)
    let eyeNormal = rod.worldDirection(SIMD3(0, 0, 1))
    let u = ring.worldDirection(SIMD3(1, 0, 0)) * Dimensions.Ring.radius
    let v = ring.worldDirection(SIMD3(0, 1, 0)) * Dimensions.Ring.radius
    let offset = simd_dot(ring.position - rod.position, eyeNormal)
    let cosine = simd_dot(u, eyeNormal)
    let sine = simd_dot(v, eyeNormal)
    let swing = (cosine * cosine + sine * sine).squareRoot()
    guard swing > abs(offset) else { return false }
    let middle = atan2(sine, cosine)
    let spread = acos(-offset / swing)
    let inside = [middle + spread, middle - spread].filter { angle in
        simd_distance(ring.position + u * cos(angle) + v * sin(angle), rod.position) < Dimensions.Rod.eyeRadius
    }
    return inside.count == 1
}

/// Whether the sword's middle line goes through the bar's sheet anywhere.
func swordGoesThroughTheBar(in pose: ToyPose) -> Bool {
    let normal = pose.bar.worldDirection(SIMD3(0, 1, 0))
    let along = pose.bar.worldDirection(SIMD3(1, 0, 0))
    let across = pose.bar.worldDirection(SIMD3(0, 0, 1))
    let spine = (Dimensions.Bar.length - Dimensions.Bar.width) / 2
    for side in [1.0, -1.0] {
        let line = SwordShape.centerline(side: side)
        for (start, end) in zip(line, line.dropFirst()) {
            let startSide = simd_dot(start - pose.bar.position, normal)
            let endSide = simd_dot(end - pose.bar.position, normal)
            guard (startSide < 0) != (endSide < 0) else { continue }
            let point = start + (end - start) * (startSide / (startSide - endSide)) - pose.bar.position
            let x = simd_dot(point, along)
            let z = simd_dot(point, across)
            let fromSpine = SIMD2(x - simd_clamp(x, -spine, spine), z)
            if simd_length(fromSpine) < Dimensions.Bar.width / 2 { return true }
        }
    }
    return false
}

/// The deepest overlap the tests accept after an ordinary run, and the limit the simulation never exceeds.
let overlapLimit = 0.4
let hardOverlapLimit = 0.5 + 1e-9


/// Whether a ring is still round the rod of the ring before it, as every ring but the first always is.
///
/// The rod goes through the ring's opening somewhere between its bead and its eye. When the ring before is
/// off, its eye often sits in this ring's lower arc, half through the opening: that counts as through, for
/// the ring it holds cannot follow it.
func ringIsRoundTheRodBefore(_ number: Int, in pose: ToyPose) -> Bool {
    guard number > 1 else { return true }
    let ring = pose.ring(number)
    let rod = pose.rod(number - 1)
    let normal = ring.worldDirection(SIMD3(0, 0, 1))
    let eye = rod.position
    let bead = rod.worldPoint(SIMD3(0, Dimensions.Rod.beadCenterY, 0))
    let eyeSide = simd_dot(eye - ring.position, normal)
    let beadSide = simd_dot(bead - ring.position, normal)
    if abs(eyeSide) <= Dimensions.Rod.eyeRadius + Dimensions.Rod.wireRadius {
        return simd_distance(eye - normal * eyeSide, ring.position) < Dimensions.Ring.radius
    }
    guard (eyeSide < 0) != (beadSide < 0) else { return false }
    let crossing = eye + (bead - eye) * (eyeSide / (eyeSide - beadSide))
    return simd_distance(crossing, ring.position) < Dimensions.Ring.radius
}
