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
    /// The farthest any point of the body is from its centre of mass.
    let extent: Double

    /// Where the body was when the step being solved began.
    private(set) var previousPosition: Vector
    private(set) var previousOrientation: simd_quatd

    init(position: Vector, orientation: simd_quatd, mass: Double, inertia: Vector, extent: Double) {
        self.position = position
        self.orientation = orientation
        self.inverseMass = 1 / mass
        self.inverseInertia = 1 / inertia
        self.extent = extent
        self.previousPosition = position
        self.previousOrientation = orientation
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

    /// Turns the body as a twist about its centre of mass would, without touching its velocity.
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

    /// Carries the body through a time step under `acceleration`, remembering where it started.
    ///
    /// No point of the body travels farther than `reach` in the step, so that a thin wire cannot pass through
    /// another between two steps.
    mutating func advance(by step: Double, acceleration: Vector, damping: Double, reach: Double) {
        previousPosition = position
        previousOrientation = orientation

        velocity += acceleration * step
        velocity *= max(0, 1 - damping * step)
        angularVelocity *= max(0, 1 - damping * step)

        let fastest = reach / step
        let speed = simd_length(velocity)
        if speed > fastest {
            velocity *= fastest / speed
        }
        let spin = simd_length(angularVelocity) * extent
        if spin > fastest {
            angularVelocity *= fastest / spin
        }

        position += velocity * step
        rotate(by: angularVelocity * step)
    }

    /// Reads the velocity and turning rate back from how far the body has come since the step began.
    mutating func deriveVelocity(over step: Double) {
        velocity = (position - previousPosition) / step
        let change = orientation * previousOrientation.inverse
        let sign: Double = change.real >= 0 ? 1 : -1
        angularVelocity = change.imag * (2 * sign / step)
    }
}
