import simd

/// One rigid part in motion. Lengths are millimetres, masses grams and times seconds.
///
/// The position is the centre of mass, and the orientation takes the body's own axes, which are the axes its
/// moments of inertia are given about, to the world's.
struct Body: Sendable {
    var position: Vector
    var orientation: simd_quatd
    var velocity = Vector.zero
    /// The turning rate about each world axis, in radians a second.
    var angularVelocity = Vector.zero

    /// One over the mass. Zero for a part that nothing can move.
    let inverseMass: Double
    /// One over the moment of inertia about each of the body's own axes.
    let inverseInertia: Vector
    /// Half the size of a box around the body, along its own axes and centred on its centre of mass.
    let halfSize: Vector
    /// The farthest any point of the body is from its centre of mass.
    var extent: Double { simd_length(halfSize) }

    /// Where the body was when the step being solved began.
    private(set) var previousPosition: Vector
    private(set) var previousOrientation: simd_quatd
    /// Where the body's own motion had carried it in this step, before anything pushed it back.
    private(set) var movedPosition: Vector
    private(set) var movedOrientation: simd_quatd

    init(position: Vector, orientation: simd_quatd, mass: Double, inertia: Vector, halfSize: Vector) {
        self.position = position
        self.orientation = orientation
        self.inverseMass = 1 / mass
        self.inverseInertia = 1 / inertia
        self.halfSize = halfSize
        self.previousPosition = position
        self.previousOrientation = orientation
        self.movedPosition = position
        self.movedOrientation = orientation
    }

    /// An upper bound on how fast any point of the body is moving.
    var speedBound: Double {
        simd_length(velocity) + simd_length(angularVelocity) * extent
    }

    /// A point given in the body's frame, in world coordinates.
    func worldPoint(_ local: Vector) -> Vector {
        position + orientation.act(local)
    }

    func localPoint(_ world: Vector) -> Vector {
        orientation.inverse.act(world - position)
    }

    /// Where a point of the body was when the step began.
    func previousWorldPoint(_ local: Vector) -> Vector {
        previousPosition + previousOrientation.act(local)
    }

    /// The velocity of the body's material at a world point.
    func velocity(at point: Vector) -> Vector {
        velocity + simd_cross(angularVelocity, point - position)
    }

    /// The speed of the fastest corner of the box around the body: no point of the body moves faster.
    var fastestPointSpeed: Double {
        var fastest = 0.0
        for x in [-1.0, 1.0] {
            for y in [-1.0, 1.0] {
                for z in [-1.0, 1.0] {
                    let corner = orientation.act(halfSize * Vector(x, y, z))
                    fastest = max(fastest, simd_length(velocity + simd_cross(angularVelocity, corner)))
                }
            }
        }
        return fastest
    }

    /// How readily the body gives way to a push along `direction` at `point`: the distance that point moves
    /// along the direction for each unit of push.
    func yield(at point: Vector, along direction: Vector) -> Double {
        let twist = orientation.inverse.act(simd_cross(point - position, direction))
        return inverseMass + simd_dot(twist * inverseInertia, twist)
    }

    /// How readily the body turns about `axis`: the angle it turns for each unit of twist.
    func turnYield(about axis: Vector) -> Double {
        let local = orientation.inverse.act(axis)
        return simd_dot(local * inverseInertia, local)
    }

    /// Turns the body about its centre of mass as a twist would, without touching its velocity.
    mutating func turn(by twist: Vector) {
        rotate(by: orientation.act(orientation.inverse.act(twist) * inverseInertia))
    }

    /// The turn a push at `point` gives, as a rotation vector in the world.
    private func turn(from push: Vector, at point: Vector) -> Vector {
        orientation.act(orientation.inverse.act(simd_cross(point - position, push)) * inverseInertia)
    }

    /// Moves and turns the body as a push at `point` would, without touching its velocity.
    mutating func displace(by push: Vector, at point: Vector) {
        let turn = turn(from: push, at: point)
        position += push * inverseMass
        rotate(by: turn)
    }

    /// Changes the body's velocity and turning rate as a push at `point` would.
    mutating func accelerate(by push: Vector, at point: Vector) {
        angularVelocity += turn(from: push, at: point)
        velocity += push * inverseMass
    }

    private mutating func rotate(by turn: Vector) {
        let change = simd_quatd(ix: turn.x, iy: turn.y, iz: turn.z, r: 0) * orientation
        orientation = simd_normalize(simd_quatd(vector: orientation.vector + 0.5 * change.vector))
    }

    /// Changes the body's speed as `acceleration` and the air's drag would over a time step.
    mutating func gainSpeed(over step: Double, acceleration: Vector, damping: Double) {
        velocity += acceleration * step
        velocity *= max(0, 1 - damping * step)
        angularVelocity *= max(0, 1 - damping * step)
    }

    /// Steers the body toward a place and a way of facing, as a hand that holds it would.
    ///
    /// The hand aims to close the gap within `settleTime` without going faster than `topSpeed`, and changes
    /// the body's motion by no more than `force` and `torque` can in the step. So it carries a body it is
    /// strong enough for, and gives way where something stronger stands against it.
    mutating func steer(
        toward position: Vector, facing orientation: simd_quatd,
        over step: Double, settleTime: Double, topSpeed: Double, force: Double, torque: Double
    ) {
        var wanted = (position - self.position) / settleTime
        let speed = simd_length(wanted)
        if speed > topSpeed {
            wanted *= topSpeed / speed
        }
        var change = wanted - velocity
        let mostChange = force * inverseMass * step
        let size = simd_length(change)
        if size > mostChange {
            change *= mostChange / size
        }
        velocity += change

        // The turn that would bring the body to face as wanted, as a rotation vector the short way round.
        let off = orientation * self.orientation.inverse
        let sine = simd_length(off.imag)
        var wantedTurn = Vector.zero
        if sine > 1e-12 {
            let angle = 2 * atan2(sine, abs(off.real))
            wantedTurn = off.imag * ((off.real >= 0 ? angle : -angle) / (sine * settleTime))
        }
        let turning = simd_length(wantedTurn) * extent
        if turning > topSpeed {
            wantedTurn *= topSpeed / turning
        }
        // The twist that change of turning rate takes, about the body's own axes, held to what the hand can give.
        var twist = self.orientation.inverse.act(wantedTurn - angularVelocity) / (inverseInertia * step)
        let strength = simd_length(twist)
        if strength > torque {
            twist *= torque / strength
        }
        angularVelocity += self.orientation.act(twist * inverseInertia * step)
    }

    /// Carries the body through a time step at the speed it has, remembering where it started.
    ///
    /// No point of the body travels farther than `reach` in the step: a body that would is slowed, moving and
    /// turning alike.
    mutating func move(over step: Double, reach: Double) {
        previousPosition = position
        previousOrientation = orientation

        let travel = speedBound * step
        if travel > reach {
            velocity *= reach / travel
            angularVelocity *= reach / travel
        }
        position += velocity * step
        rotate(by: angularVelocity * step)

        movedPosition = position
        movedOrientation = orientation
    }

    /// Holds what the solver has done to the body in this step to at most `reach` for any of its points.
    ///
    /// Whatever correction is left over is made in the steps that follow. This is what keeps a correction from
    /// carrying one wire past another.
    mutating func limitCorrection(to reach: Double) {
        let shift = position - movedPosition
        let change = orientation * movedOrientation.inverse
        let angle = 2 * atan2(simd_length(change.imag), abs(change.real))
        let travel = simd_length(shift) + angle * extent
        guard travel > reach else { return }
        let share = reach / travel
        position = movedPosition + shift * share
        orientation = simd_slerp(movedOrientation, orientation, share)
    }

    /// Stops the body where it is.
    mutating func halt() {
        velocity = .zero
        angularVelocity = .zero
    }

    /// Reads the velocity and turning rate back from how far the body has come since the step began.
    mutating func deriveVelocity(over step: Double) {
        velocity = (position - previousPosition) / step
        let change = orientation * previousOrientation.inverse
        let sign: Double = change.real >= 0 ? 1 : -1
        angularVelocity = change.imag * (2 * sign / step)
    }
}
