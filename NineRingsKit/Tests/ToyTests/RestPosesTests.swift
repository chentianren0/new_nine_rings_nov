import Puzzle
import Testing
import simd
@testable import Toy

private let allStates = (0..<PuzzleState.count).map { PuzzleState(bits: UInt16($0)) }

/// How many times a path of straight pieces passes through the disc spanned by a ring.
private func crossings(of path: [SIMD3<Double>], throughRing ring: PartPose) -> Int {
    let normal = ring.worldDirection(SIMD3(0, 0, 1))
    var count = 0
    for (start, end) in zip(path, path.dropFirst()) {
        let startSide = simd_dot(start - ring.position, normal)
        let endSide = simd_dot(end - ring.position, normal)
        guard (startSide < 0) != (endSide < 0) else { continue }
        let point = start + (end - start) * (startSide / (startSide - endSide))
        if simd_distance(point, ring.position) < Dimensions.Ring.radius {
            count += 1
        }
    }
    return count
}

/// These checks read the stored poses through the frames that `Dimensions` describes, so they fail if a pose,
/// a frame or the numbering of the rings is misread.
@Suite struct RestPosesTests {
    @Test func everyStateHasAPose() {
        #expect(RestPoses.all.count == PuzzleState.count)
        for state in allStates {
            let pose = RestPoses.pose(for: state)
            for part in pose.rings + pose.rods + [pose.bar] {
                #expect(abs(simd_length(part.orientation) - 1) < 1e-9)
            }
        }
    }

    @Test func aRingIsOnExactlyWhenBothRailsPassThroughIt() {
        let rails = [SwordShape.centerline(side: 1), SwordShape.centerline(side: -1)]
        for state in allStates {
            let pose = RestPoses.pose(for: state)
            for ring in PuzzleState.rings {
                let through = rails.map { crossings(of: $0, throughRing: pose.ring(ring)) }
                #expect(through == (state.isOn(ring) ? [1, 1] : [0, 0]), "state \(state), ring \(ring)")
            }
        }
    }

    @Test func everyRingAfterTheFirstEncirclesThePreviousRod() {
        let top = SIMD3(0, Dimensions.Rod.eyeRadius, 0)
        let bead = SIMD3(0, Dimensions.Rod.beadCenterY, 0)
        for state in allStates {
            let pose = RestPoses.pose(for: state)
            for ring in 2...PuzzleState.ringCount {
                let rod = pose.rod(ring - 1)
                let length = [rod.worldPoint(top), rod.worldPoint(bead)]
                #expect(crossings(of: length, throughRing: pose.ring(ring)) == 1, "state \(state), ring \(ring)")
            }
        }
    }

    @Test func everyRodRunsThroughItsHoleWithItsBeadBelowTheBar() {
        for state in allStates {
            let pose = RestPoses.pose(for: state)
            let barNormal = pose.bar.worldDirection(SIMD3(0, 1, 0))
            for ring in PuzzleState.rings {
                let rod = pose.rod(ring)
                let hole = pose.bar.worldPoint(SIMD3(Dimensions.Bar.holeX(ring), 0, 0))
                let down = rod.worldDirection(SIMD3(0, -1, 0))
                let distanceAlongShaft = simd_dot(hole - rod.position, barNormal) / simd_dot(down, barNormal)
                let point = rod.position + down * distanceAlongShaft
                #expect(simd_distance(point, hole) < Dimensions.Bar.holeRadius, "state \(state), rod \(ring)")
                #expect(distanceAlongShaft > Dimensions.Rod.eyeRadius, "state \(state), rod \(ring): eye above the bar")
                #expect(distanceAlongShaft < -Dimensions.Rod.beadCenterY, "state \(state), rod \(ring): bead below the bar")
            }
        }
    }

    @Test func everyEyeHoldsItsOwnRing() {
        for state in allStates {
            let pose = RestPoses.pose(for: state)
            for ring in PuzzleState.rings {
                let ringPose = pose.ring(ring)
                let offset = pose.rod(ring).position - ringPose.position
                let height = simd_dot(offset, ringPose.worldDirection(SIMD3(0, 0, 1)))
                let inPlane = (simd_length_squared(offset) - height * height).squareRoot()
                let distanceToWire = ((inPlane - Dimensions.Ring.radius) * (inPlane - Dimensions.Ring.radius) + height * height).squareRoot()
                #expect(distanceToWire < Dimensions.Rod.eyeRadius, "state \(state), ring \(ring)")
            }
        }
    }
}

@Suite struct SwordShapeTests {
    @Test func theTwoSidesMeetAtTheTipAndMirrorEachOther() {
        let near = SwordShape.centerline(side: 1)
        let far = SwordShape.centerline(side: -1)
        #expect(near.first == SIMD3(0, 0, 0))
        #expect(far.first == near.first)
        for (a, b) in zip(near, far) {
            #expect(a.x == b.x && a.y == b.y && a.z == -b.z)
        }
    }

    @Test func theRailsAreLevelBeyondTheRiseAndTouchAtTheShoulder() {
        let side = SwordShape.centerline(side: 1)
        #expect(abs(Dimensions.Sword.railHeight + 3.5265) < 1e-3)
        #expect(side.last == SIMD3(Dimensions.Sword.neckEndX, Dimensions.Sword.railHeight, Dimensions.Sword.wireRadius))
        #expect(side.allSatisfy { $0.y <= 0 && $0.y >= Dimensions.Sword.railHeight })
    }
}
