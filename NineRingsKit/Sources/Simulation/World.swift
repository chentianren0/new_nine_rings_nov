import simd

/// Rigid bodies made of pieces, under gravity, that may touch but never pass through one another.
///
/// Time moves in small steps. In each step every body first moves freely, then the places where pieces overlap
/// are pushed apart, and the bodies' velocities are read back from where they ended up. Positions are corrected
/// directly, which keeps contact between thin wires firm without stiff springs.
///
/// Nothing passes through anything, and that holds by how a step is built, not by how well the solver does:
///
/// - No point travels farther than `freeReach` on its own in a step; a step is shortened until that is so.
/// - What the solver then does to a body moves none of its points farther than `correctionReach`.
/// - A step that would end with two surfaces overlapping by more than `overlapLimit` is not taken at all.
///
/// So two surfaces start a step overlapping by no more than the limit, and come no more than twice the two
/// reaches closer during it. While that sum stays under the thinnest pair of parts, the middles of two parts
/// can never meet, let alone cross.
struct World: Sendable {
    /// A piece and the body that carries it. A piece without a body is fixed in the world.
    struct Part: Sendable {
        var piece: Piece
        var body: Int?
        /// Pieces whose kinds are listed together in `unwatchedKinds` are never checked against each other.
        var kind = 0
    }

    /// A round shaft of one body running through a round hole in a sheet of another. This is how a rod stays
    /// in the bar.
    ///
    /// The shaft's middle line is kept as near the hole's middle as the shaft has room for, and the shaft may
    /// lean in the hole only as far as the sheet's two rims let it.
    struct Sleeve: Sendable {
        var shaftBody: Int
        /// The shaft's middle line, in the frame of the body that carries it.
        var shaft: Segment
        var shaftRadius: Double
        var holeBody: Int
        /// The middle of the hole and the direction it faces, in the frame of its body.
        var hole: Vector
        var holeNormal: Vector
        var holeRadius: Double
        var sheetThickness: Double

        /// The farthest the shaft can lean from the hole's direction: where it touches the rim of one face on
        /// one side and the rim of the other face on the other.
        var steepestLean: Double {
            let halfSheet = sheetThickness / 2
            return acos(shaftRadius / (holeRadius * holeRadius + halfSheet * halfSheet).squareRoot()) - atan(halfSheet / holeRadius)
        }

        /// How far the shaft's middle line may be from the hole's middle, for a shaft whose direction makes
        /// the cosine `upright` with the hole's. A leaning shaft cuts the sheet in a longer oval, so it has
        /// less room.
        ///
        /// This leaves out the sheet's thickness, which would take away up to 0.3 mm more and leave no room at
        /// all at the steepest lean. That is on purpose: with no room there, the hole and the limit on leaning
        /// pull against each other, and a toy hanging with all its rods at that limit never settles. The shaft
        /// stays well inside its hole either way.
        func room(upright: Double) -> Double {
            max(0, holeRadius * upright - shaftRadius)
        }
    }

    /// A hand on a body: it steers the body toward a place and a way of facing, with limited strength.
    struct Hold: Sendable {
        var body: Int
        var position: Vector
        var orientation: simd_quatd
        /// The hand aims to arrive within this many seconds, at no more than `topSpeed` millimetres a second.
        var settleTime = 0.05
        var topSpeed = 60.0
        /// The most force and the most twist the hand gives.
        var force: Double
        var torque: Double
    }

    /// A steady force on a body, through its centre of mass.
    struct Push: Sendable {
        var body: Int
        var force: Vector
    }

    var bodies: [Body] = []
    var holds: [Hold] = []
    var pushes: [Push] = []
    /// Every piece, in its body's frame, or in the world's frame when it is fixed.
    var parts: [Part] = []
    var sleeves: [Sleeve] = []
    /// Pairs of kinds of pieces that are left to something else, as a rod's shaft and the bar are left to
    /// the sleeve that holds one in the other.
    var unwatchedKinds: [(Int, Int)] = []

    /// Millimetres a second squared.
    var gravity = Vector(0, -9810, 0)
    var friction = 0.3
    /// The share of a body's speed lost each second to everything the contacts do not model: the scrape and
    /// rattle of wire on wire that stops a real ring swinging within a second or two.
    var damping = 2.5
    /// Two surfaces closer than this are watched for contact.
    var margin = 0.1

    /// The longest a step may be, in seconds. A step is shorter while something moves fast.
    var longestStep = 1.0 / 1200
    /// The farthest any point may travel on its own in one step.
    var freeReach = 0.2
    /// The farthest the solver may move any point of a body in one step.
    var correctionReach = 0.15
    /// The deepest two surfaces may overlap at the end of a step. With the two reaches it must stay under the
    /// thinnest pair of parts, an eye on the bar, 1.35 mm together: 0.5 + 2 × (0.2 + 0.15) = 1.2.
    var overlapLimit = 0.5

    /// How many times the contacts are gone over in a step, at least and at most. Contacts that share a body,
    /// as the two rails share a ring, need several passes to agree on how its load divides, and a jammed part
    /// needs many. The passes go on past the least number while any overlap is deeper than `settledOverlap`.
    var sweeps = 8
    var mostSweeps = 32
    var settledOverlap = 0.02

    /// The deepest any two surfaces have overlapped at the end of a step, since the world was made.
    private(set) var deepestOverlap = 0.0
    /// How many steps were not taken because they would have ended with too deep an overlap. A part that is
    /// pulled or pushed into a jam stops there: the world stands still for as long as the force lasts.
    private(set) var refusedSteps = 0

    private var lastOverlap = 0.0
    private var placed: [Piece] = []
    private var contacts: [Contact] = []
    private var approaches: [Approach] = []

    /// A place where two pieces touch or nearly touch, kept for one step.
    private struct Contact {
        var bodyA: Int?
        var bodyB: Int?
        /// The touching point of each surface, in its body's frame, or the world's for a fixed piece.
        var pointA: Vector
        var pointB: Vector
        /// From B toward A.
        var normal: Vector
        /// How well the two surfaces grip each other.
        var friction: Double
        /// How hard the two have been pushed apart in this step.
        var push = 0.0
        /// The pull that friction has given across the contact in this step.
        var hold = Vector.zero
    }

    @discardableResult
    mutating func add(_ body: Body, pieces: [Piece], kinds: [Int] = []) -> Int {
        bodies.append(body)
        for (index, piece) in pieces.enumerated() {
            parts.append(Part(piece: piece, body: bodies.count - 1, kind: index < kinds.count ? kinds[index] : 0))
        }
        return bodies.count - 1
    }

    mutating func addFixed(_ piece: Piece) {
        parts.append(Part(piece: piece, body: nil))
    }

    /// Stops every body where it is.
    mutating func halt() {
        for index in bodies.indices {
            bodies[index].halt()
        }
    }

    // MARK: Stepping

    /// Advances the world by `time` seconds.
    mutating func advance(by time: Double) {
        var remaining = time
        while remaining > 1e-9 {
            let step = min(remaining, stepLength)
            take(step)
            remaining -= step
        }
    }

    /// A step short enough that nothing travels farther than `freeReach` in it, down to a thirty-second of
    /// the longest step. Past that a body is slowed instead.
    private var stepLength: Double {
        let fastest = (bodies.map(\.speedBound).max() ?? 0) + simd_length(gravity) * longestStep
        guard fastest > 0 else { return longestStep }
        return max(longestStep / 32, min(longestStep, freeReach / fastest))
    }

    private mutating func take(_ step: Double) {
        let start = bodies

        for index in bodies.indices {
            bodies[index].gainSpeed(over: step, acceleration: gravity, damping: damping)
        }
        for push in pushes {
            bodies[push.body].velocity += push.force * (bodies[push.body].inverseMass * step)
        }
        for hold in holds {
            bodies[hold.body].steer(
                toward: hold.position, facing: hold.orientation,
                over: step, settleTime: hold.settleTime, topSpeed: hold.topSpeed, force: hold.force, torque: hold.torque
            )
        }
        for index in bodies.indices {
            bodies[index].move(over: step, reach: freeReach)
        }

        findContacts()
        var sweep = 0
        repeat {
            solve()
            sweep += 1
        } while sweep < sweeps || (sweep < mostSweeps && worstOverlap > settledOverlap)
        for index in bodies.indices {
            bodies[index].limitCorrection(to: correctionReach)
        }

        // An overlap left from before may stay as it is while it is being worked off, but never deepen.
        let overlap = worstOverlap
        guard overlap <= max(overlapLimit, lastOverlap) else {
            refuse(backTo: start)
            return
        }
        lastOverlap = overlap
        deepestOverlap = max(deepestOverlap, overlap)

        for index in bodies.indices {
            bodies[index].deriveVelocity(over: step)
        }
        for contact in contacts where contact.push > 0 {
            settleVelocity(at: contact)
        }
    }

    /// Puts every body back where the step began, and stops the bodies that were being driven into each
    /// other, so that they do not simply try again.
    private mutating func refuse(backTo start: [Body]) {
        var stopped = start
        for contact in contacts where overlap(at: contact) > overlapLimit {
            if let a = contact.bodyA { stopped[a].halt() }
            if let b = contact.bodyB { stopped[b].halt() }
        }
        bodies = stopped
        refusedSteps += 1
    }

    /// The deepest overlap among the places being watched, as the bodies are now.
    private var worstOverlap: Double {
        contacts.reduce(0) { max($0, overlap(at: $1)) }
    }

    // MARK: Finding contacts

    private mutating func findContacts() {
        placed.removeAll(keepingCapacity: true)
        for part in parts {
            placed.append(part.body.map { part.piece.placed(by: bodies[$0]) } ?? part.piece)
        }

        contacts.removeAll(keepingCapacity: true)
        for first in parts.indices {
            let boundsA = placed[first].bounds
            for second in (first + 1)..<parts.count {
                let bodyA = parts[first].body
                let bodyB = parts[second].body
                // Pieces of one body, and two fixed pieces, never move against each other.
                guard bodyA != bodyB else { continue }
                let kindA = parts[first].kind
                let kindB = parts[second].kind
                guard !unwatchedKinds.contains(where: { $0 == (kindA, kindB) || $0 == (kindB, kindA) }) else { continue }
                let boundsB = placed[second].bounds
                guard simd_distance(boundsA.center, boundsB.center) < boundsA.radius + boundsB.radius + margin else { continue }

                let a = placed[first]
                let b = placed[second]
                approaches.removeAll(keepingCapacity: true)
                Piece.approaches(a, b, within: a.radius + b.radius + margin, into: &approaches)
                for approach in approaches {
                    let distance = approach.distance
                    // Two middles that meet leave no direction to push in. The limits on a step keep them apart.
                    guard distance > 1e-9 else { continue }
                    let normal = (approach.pointA - approach.pointB) / distance
                    let surfaceA = approach.pointA - normal * a.radius
                    let surfaceB = approach.pointB + normal * b.radius
                    contacts.append(Contact(
                        bodyA: bodyA,
                        bodyB: bodyB,
                        pointA: bodyA.map { bodies[$0].localPoint(surfaceA) } ?? surfaceA,
                        pointB: bodyB.map { bodies[$0].localPoint(surfaceB) } ?? surfaceB,
                        normal: normal,
                        friction: friction
                    ))
                }
            }
        }

        // A sleeve acts like a contact turned inside out: it pushes the shaft back toward the hole's middle
        // once the two are farther apart than the shaft has room for, and it does not grip.
        for sleeve in sleeves {
            let shaft = Segment(
                start: bodies[sleeve.shaftBody].worldPoint(sleeve.shaft.start),
                end: bodies[sleeve.shaftBody].worldPoint(sleeve.shaft.end)
            )
            let hole = bodies[sleeve.holeBody].worldPoint(sleeve.hole)
            let facing = bodies[sleeve.holeBody].orientation.act(sleeve.holeNormal)
            let room = sleeve.room(upright: abs(simd_dot(simd_normalize(shaft.end - shaft.start), facing)))
            let nearest = shaft.nearestPoint(to: hole)
            let distance = simd_distance(nearest, hole)
            guard distance > room - margin, distance > 1e-9 else { continue }
            let towardHole = (hole - nearest) / distance
            contacts.append(Contact(
                bodyA: sleeve.shaftBody,
                bodyB: sleeve.holeBody,
                pointA: bodies[sleeve.shaftBody].localPoint(nearest),
                pointB: bodies[sleeve.holeBody].localPoint(hole - towardHole * room),
                normal: towardHole,
                friction: 0
            ))
        }
    }

    // MARK: Solving contacts

    /// Goes over every sleeve and every contact once.
    ///
    /// The contacts are always taken in the same order. Going over them backward on alternate passes was
    /// tried, to keep any one contact from always taking up what the others leave over, and made things worse:
    /// friction then held less well, and a toy that should have been still kept creeping.
    private mutating func solve() {
        // The leaning limits come first: the contacts after them put each shaft back in its hole.
        for sleeve in sleeves {
            straighten(sleeve)
        }
        for index in contacts.indices {
            var contact = contacts[index]
            separate(&contact)
            contacts[index] = contact
        }
    }

    private func worldPoint(_ point: Vector, of body: Int?) -> Vector {
        body.map { bodies[$0].worldPoint(point) } ?? point
    }

    private func previousWorldPoint(_ point: Vector, of body: Int?) -> Vector {
        body.map { bodies[$0].previousWorldPoint(point) } ?? point
    }

    /// How far the two surfaces of a contact overlap along its normal; negative while they are apart.
    private func overlap(at contact: Contact) -> Double {
        simd_dot(
            worldPoint(contact.pointB, of: contact.bodyB) - worldPoint(contact.pointA, of: contact.bodyA),
            contact.normal
        )
    }

    /// How far the touching points of a contact part along `direction` for each unit of push between them.
    private func give(at contact: Contact, along direction: Vector) -> Double {
        (contact.bodyA.map { bodies[$0].yield(at: worldPoint(contact.pointA, of: $0), along: direction) } ?? 0)
            + (contact.bodyB.map { bodies[$0].yield(at: worldPoint(contact.pointB, of: $0), along: direction) } ?? 0)
    }

    /// Moves the two bodies of a contact as a push on A, and its opposite on B, at the touching points would.
    private mutating func displace(_ contact: Contact, by push: Vector) {
        if let a = contact.bodyA { bodies[a].displace(by: push, at: bodies[a].worldPoint(contact.pointA)) }
        if let b = contact.bodyB { bodies[b].displace(by: -push, at: bodies[b].worldPoint(contact.pointB)) }
    }

    /// Moves the two surfaces of a contact apart where they overlap, and holds them from sliding as far as
    /// friction can.
    ///
    /// Both the push and the hold are kept as totals for the step and corrected on each pass, so the push can
    /// be taken back if another contact has since moved the surfaces apart, and the hold never exceeds
    /// friction's share of the push.
    private mutating func separate(_ contact: inout Contact) {
        let overlap = overlap(at: contact)
        let normalGive = give(at: contact, along: contact.normal)
        guard normalGive > 0 else { return }
        let push = max(0, contact.push + overlap / normalGive)
        displace(contact, by: contact.normal * (push - contact.push))
        contact.push = push

        // How far the touching points have slid past each other since the step began.
        let pointA = worldPoint(contact.pointA, of: contact.bodyA)
        let pointB = worldPoint(contact.pointB, of: contact.bodyB)
        let travel = (pointA - previousWorldPoint(contact.pointA, of: contact.bodyA))
            - (pointB - previousWorldPoint(contact.pointB, of: contact.bodyB))
        let slide = travel - contact.normal * simd_dot(travel, contact.normal)
        let distance = simd_length(slide)
        var hold = contact.hold
        if distance > 1e-12 {
            let direction = slide / distance
            let slideGive = give(at: contact, along: direction)
            if slideGive > 0 {
                hold -= direction * (distance / slideGive)
            }
        }
        let limit = contact.friction * contact.push
        let strength = simd_length(hold)
        if strength > limit {
            hold *= limit / strength
        }
        displace(contact, by: hold - contact.hold)
        contact.hold = hold
    }

    /// Turns a shaft and the sheet it runs through toward each other where the shaft leans in its hole more
    /// than the rims allow. The two get equal and opposite twists, each about its own centre of mass, so the
    /// correction adds no momentum; the sleeve's contact then brings the shaft back to the hole.
    private mutating func straighten(_ sleeve: Sleeve) {
        let shaft = bodies[sleeve.shaftBody]
        let sheet = bodies[sleeve.holeBody]
        let along = simd_normalize(shaft.orientation.act(sleeve.shaft.end - sleeve.shaft.start))
        var facing = sheet.orientation.act(sleeve.holeNormal)
        if simd_dot(along, facing) < 0 { facing = -facing }

        let axis = simd_cross(along, facing)
        let sine = simd_length(axis)
        guard sine > 1e-9 else { return }
        let excess = atan2(sine, simd_dot(along, facing)) - sleeve.steepestLean
        guard excess > 0 else { return }

        let hinge = axis / sine
        let give = shaft.turnYield(about: hinge) + sheet.turnYield(about: hinge)
        guard give > 0 else { return }
        let twist = hinge * (excess / give)
        bodies[sleeve.shaftBody].turn(by: twist)
        bodies[sleeve.holeBody].turn(by: -twist)
    }

    /// Takes away the speed at which the two surfaces of a contact still close or part, so that nothing bounces.
    private mutating func settleVelocity(at contact: Contact) {
        let pointA = worldPoint(contact.pointA, of: contact.bodyA)
        let pointB = worldPoint(contact.pointB, of: contact.bodyB)
        let closing = simd_dot(
            (contact.bodyA.map { bodies[$0].velocity(at: pointA) } ?? .zero)
                - (contact.bodyB.map { bodies[$0].velocity(at: pointB) } ?? .zero),
            contact.normal
        )
        let normalGive = give(at: contact, along: contact.normal)
        guard normalGive > 0 else { return }
        let push = contact.normal * (-closing / normalGive)
        if let a = contact.bodyA { bodies[a].accelerate(by: push, at: pointA) }
        if let b = contact.bodyB { bodies[b].accelerate(by: -push, at: pointB) }
    }
}
