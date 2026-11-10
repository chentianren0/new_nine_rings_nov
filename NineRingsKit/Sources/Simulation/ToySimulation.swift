import Foundation
import Puzzle
import Toy
import simd

/// The toy in motion: nine rings, nine rods and the bar as rigid bodies around the fixed sword, under gravity.
///
/// It starts from a pose, moves when it is advanced, and gives back the pose it has reached.
public struct ToySimulation: Sendable {
    private var world = World()
    private let rodCenterY: Double
    /// The hand that holds the bar while no ring is on the sword.
    private var barHold: World.Hold?
    /// The hand that is moving a ring, and where it holds that ring now.
    private var hand: Hand?
    private var ringHold: World.Hold?
    /// The hand that holds the ring before that one up out of its way, where one is needed, and the hand that
    /// waits for it to have done so.
    private var helper: Hand?
    private var helperHold: World.Hold?
    private var waitingHand: Hand?
    private var calmTime = 0.0

    /// Whether every part has stayed still for a moment. A toy at rest stays as it is, and `advance` leaves it
    /// alone, until `wake` is called.
    public private(set) var isAtRest = false

    public init(pose: ToyPose) {
        let rod = RodBuild()
        rodCenterY = rod.centerY
        world.unwatchedKinds = [(Kind.shaft, Kind.bar)]

        // Bodies are numbered in this order: rings 0 to 8, rods 9 to 17, the bar 18.
        for ring in pose.rings {
            world.add(Self.ringBody(at: ring), pieces: [Self.ringPiece])
        }
        for part in pose.rods {
            world.add(rod.body(at: part), pieces: rod.pieces, kinds: [0, Kind.shaft, 0])
        }
        world.add(Self.barBody(at: pose.bar), pieces: [Self.barPiece], kinds: [Kind.bar])

        for number in 1...9 {
            world.sleeves.append(World.Sleeve(
                shaftBody: 9 + number - 1,
                shaft: rod.shaft,
                shaftRadius: Dimensions.Rod.wireRadius,
                holeBody: 18,
                hole: Vector(Dimensions.Bar.holeX(number), 0, 0),
                holeNormal: Vector(0, 1, 0),
                holeRadius: Dimensions.Bar.holeRadius,
                sheetThickness: Dimensions.Bar.thickness
            ))
        }
        for piece in Self.swordPieces {
            world.addFixed(piece)
        }
        world.relax()
    }

    /// Where every part is now.
    public var pose: ToyPose {
        let eye = Vector(0, -rodCenterY, 0)
        return ToyPose(
            rings: (0..<9).map { PartPose(position: world.bodies[$0].position, orientation: world.bodies[$0].orientation) },
            rods: (9..<18).map { PartPose(position: world.bodies[$0].worldPoint(eye), orientation: world.bodies[$0].orientation) },
            bar: PartPose(position: world.bodies[18].position, orientation: world.bodies[18].orientation)
        )
    }

    /// The speed of the fastest point of any part, in millimetres a second.
    public var fastestSpeed: Double {
        world.bodies.map(\.fastestPointSpeed).max() ?? 0
    }

    /// The deepest any two parts have been left overlapping, in millimetres, since the simulation began.
    /// While it stays a small part of a wire's radius, nothing can have passed through anything.
    public var deepestOverlap: Double { world.deepestOverlap }

    /// How many steps the simulation would not take, because parts were being forced into one another. While
    /// a hand pulls a part into a jam, the toy stands still instead of giving way.
    public var refusedSteps: Int { world.refusedSteps }

    /// Pulls on a ring with a steady force, given in grams' weight along each world axis, until it is changed.
    /// This is for trying how the toy stands up to a hand.
    mutating func pull(ring number: Int, by gramsWeight: SIMD3<Double>) {
        wake()
        world.pushes = [World.Push(body: number - 1, force: gramsWeight * 9810)]
    }

    /// Whether a hand is moving a ring just now.
    public var handIsBusy: Bool { hand != nil || helper != nil || waitingHand != nil }

    /// Has a hand move a ring: off the sword if the ring is on it, and back on if it is off. The hand takes
    /// the way a person takes, and the ring is moved by the hand and by everything it meets on that way.
    /// For any ring but the first, a second hand first lifts the ring before it off the tip and holds it up,
    /// so that the ring travels round that ring's rod, and puts it back afterwards.
    ///
    /// Gives `false`, and does nothing, where hands are not yet able to move that ring: see
    /// `aHandCanMove(ring:in:)`. A hand that has begun can still fail, and then lets its ring go; whether the
    /// ring arrived is read from `pose` once the toy is at rest.
    @discardableResult
    public mutating func move(ring number: Int) -> Bool {
        guard !handIsBusy, Self.aHandCanMove(ring: number, in: pose.ringsOnTheSword) else { return false }
        setAHand(to: number)
        return true
    }

    /// Whether hands are able to move a ring of a toy in a state, as far as is known before they try.
    ///
    /// So far they move rings 1 and 2. Ring 3 and those after it need more: with rings off in front, the rod
    /// of the last of them hangs through the ring that has to be lifted, round the outside of the tip, and
    /// the hands do not yet carry that along. And they move a ring only where the toy hangs in a way they
    /// can handle:
    ///
    /// - The bar hangs within 45 degrees of level, before and after. With few rings on, the bar hangs
    ///   steeply from one end and jams every rod in its hole; a person would steady the bar in the other hand.
    /// - Ring 1, off the sword, has its eye no more than 60 millimetres under the rails. At the end of a
    ///   chain of four or more rings that are off it hangs lower, down by the bar's end.
    /// - Ring 2 moves only while no three neighbouring rings are off. To make room for it, ring 1 is lifted
    ///   a ring's height above the sword, which raises the bar's end by its rod; a chain of three or more
    ///   rings that are off rests on the bar and holds it down.
    public static func aHandCanMove(ring number: Int, in state: PuzzleState) -> Bool {
        guard number <= 2, state.canMove(number) else { return false }
        let stateOn = state.isOn(number) ? state : state.moving(number)
        let stateOff = state.isOn(number) ? state.moving(number) : state
        let on = RestPoses.pose(for: stateOn)
        let off = RestPoses.pose(for: stateOff)
        func tilt(of pose: ToyPose) -> Double {
            abs(asin(pose.bar.worldDirection(Vector(1, 0, 0)).y))
        }
        let steepest = 45 * Double.pi / 180
        guard tilt(of: on) < steepest, tilt(of: off) < steepest else { return false }
        if number == 1 {
            return off.rod(number).position.y > -60
        }
        var longestRunOff = 0
        var run = 0
        for ring in PuzzleState.rings {
            run = stateOff.isOn(ring) ? 0 : run + 1
            longestRunOff = max(longestRunOff, run)
        }
        return longestRunOff < 3
    }

    /// Sets a hand to move a ring, whether or not it can be expected to get the ring there.
    mutating func setAHand(to number: Int) {
        wake()
        let state = pose.ringsOnTheSword
        let mover = state.isOn(number)
            ? Hand.takingOff(ring: number)
            : Hand.puttingOn(ring: number, restingAs: RestPoses.pose(for: state.moving(number)))
        // Any ring but the first travels round the rod of the ring before it, so a second hand first lifts
        // that ring off the tip and holds it up; the hand for the ring itself waits until it has.
        if number > 1, state.isOn(number - 1), state.canMove(number) {
            helper = Hand.holdingUp(ring: number - 1, restingAs: RestPoses.pose(for: state.moving(number)))
            waitingHand = mover
        } else {
            hand = mover
        }
    }

    /// Moves the toy on by `time` seconds, unless it is at rest.
    public mutating func advance(by time: Double) {
        guard !isAtRest else { return }
        moveTheHands(by: time)
        holdTheBarWhileNoRingIsOn()
        world.holds = [barHold, ringHold, helperHold].compactMap { $0 }
        world.advance(by: time)

        calmTime = (fastestSpeed < Self.restSpeed && !handIsBusy) ? calmTime + time : 0
        if calmTime >= Self.restTime {
            isAtRest = true
            world.halt()
        }
    }

    /// Moves the hands on along their ways and steers their rings toward where they now want them. A hand
    /// whose way has ended, or that has given up, lets go.
    private mutating func moveTheHands(by time: Double) {
        let now = pose
        // The helping hand works first and last: the other hand begins once the ring before is held up, and
        // the helping hand puts that ring back once the other hand has let go.
        if var helping = helper {
            if helping.isHoldingUp {
                if let waiting = waitingHand {
                    hand = waiting
                    waitingHand = nil
                } else if hand == nil {
                    helping.letDown()
                }
            }
            let loose = helping.isHoldingUp
            if let wanted = helping.advance(by: time, in: now) {
                helperHold = hold(on: helping.ring, at: wanted, force: loose ? Self.holdingUpForce : Self.handForce)
                helper = helping
            } else {
                helperHold = nil
                helper = nil
                waitingHand = nil
            }
        }
        if var busy = hand {
            if let wanted = busy.advance(by: time, in: now) {
                ringHold = hold(on: busy.ring, at: wanted, force: Self.handForce)
                hand = busy
            } else {
                ringHold = nil
                hand = nil
            }
        }
    }

    /// A hand's hold on a ring that it wants at a station.
    private func hold(on ring: Int, at wanted: Hand.Station, force: Double) -> World.Hold {
        // The hand turns the ring's axis the short way to where it wants it, and asks for no spin about that
        // axis: the ring is the same however it is spun.
        let body = world.bodies[ring - 1]
        let axis = body.orientation.act(Vector(0, 0, 1))
        let wantedAxis = simd_dot(axis, wanted.axis) < 0 ? -wanted.axis : wanted.axis
        return World.Hold(
            body: ring - 1,
            position: wanted.centre,
            orientation: simd_quatd(from: axis, to: wantedAxis) * body.orientation,
            force: force,
            torque: force * Dimensions.Ring.radius
        )
    }

    /// The hand is as strong as the weight of about eighty grams, more than all the parts that hang from the
    /// sword weigh together: enough to lift a ring with whatever hangs from it, and to draw the other rings
    /// along the rails after it.
    private static let handForce = 80 * 9810.0
    /// A ring that is only held up out of the way is held more loosely, with the weight of about thirty
    /// grams: enough to carry it with its rod and the end of the bar, and little enough for the ring that
    /// travels round its rod to push that rod aside.
    private static let holdingUpForce = 30 * 9810.0

    /// Lets a toy at rest move again. Whatever is about to disturb it calls this first.
    public mutating func wake() {
        isAtRest = false
        calmTime = 0
    }

    /// A part slower than this, in millimetres a second, for this long, in seconds, counts as still. The slow
    /// creep that the solver leaves in a loaded contact is slower, so a resting toy stops for good, as real
    /// friction would hold it.
    private static let restSpeed = 3.0
    private static let restTime = 0.25

    /// With every ring off, nothing joins the rings, the rods and the bar to the sword, and they would fall
    /// away. A person would be holding them in the other hand: so a hand takes hold of the bar where it is,
    /// and lets go when a ring is back on.
    private mutating func holdTheBarWhileNoRingIsOn() {
        // While a hand is moving a ring, the hand on the bar keeps whatever grip it has: letting the bar drop
        // the moment the first ring is over the slot would tear that ring from the other hand.
        guard !handIsBusy else { return }
        let isFree = pose.ringsOnTheSword == .allOff
        if isFree && barHold == nil {
            let bar = world.bodies[Self.barBody]
            barHold = World.Hold(
                body: Self.barBody,
                position: bar.position,
                orientation: bar.orientation,
                force: Self.holdingForce,
                torque: Self.holdingTorque
            )
        } else if !isFree {
            barHold = nil
        }
    }

    private static let barBody = 18
    /// Enough to carry all the parts, which weigh about 55 grams together, three times over.
    private static let holdingForce = 3 * 55 * 9810.0
    /// Enough to hold that weight level from an end of the bar.
    private static let holdingTorque = holdingForce * Dimensions.Bar.length / 2

    // MARK: Building the parts

    private enum Kind {
        static let shaft = 1
        static let bar = 2
    }

    /// Grams in a cubic millimetre.
    private enum Density {
        static let steel = 0.00785
        static let wood = 0.0007
    }

    private static let ringPiece = Piece(
        shape: .circle(Circle(center: .zero, axisU: Vector(1, 0, 0), axisV: Vector(0, 1, 0), radius: Dimensions.Ring.radius)),
        radius: Dimensions.Ring.wireRadius
    )

    private static func ringBody(at pose: PartPose) -> Body {
        let radius = Dimensions.Ring.radius
        let wire = Dimensions.Ring.wireRadius
        let mass = Density.steel * 2 * Double.pi * Double.pi * radius * wire * wire
        return Body(
            position: pose.position,
            orientation: pose.orientation,
            mass: mass,
            inertia: Vector(0.5, 0.5, 1) * (mass * radius * radius),
            halfSize: Vector(radius + wire, radius + wire, wire)
        )
    }

    /// A rod's mass and pieces, laid out around its centre of mass, which lies partway down the shaft.
    private struct RodBuild {
        /// The least inertia about the shaft, as a share of the inertia across it.
        static let leastInertiaShare = 0.1

        let mass: Double
        let inertia: Vector
        let centerY: Double
        let halfSize: Vector
        let shaft: Segment
        let pieces: [Piece]

        init() {
            typealias Rod = Dimensions.Rod
            let wire = Rod.wireRadius
            let shaftLength = Rod.shaftTopY - Rod.beadCenterY
            let shaftMiddleY = (Rod.shaftTopY + Rod.beadCenterY) / 2

            let eyeMass = Density.steel * 2 * Double.pi * Double.pi * Rod.eyeRadius * wire * wire
            let shaftMass = Density.steel * Double.pi * wire * wire * shaftLength
            let beadMass = Density.wood * 4 / 3 * Double.pi * pow(Rod.beadRadius, 3)
            let mass = eyeMass + shaftMass + beadMass
            let centerY = (shaftMass * shaftMiddleY + beadMass * Rod.beadCenterY) / mass

            let eyeAway = centerY * centerY
            let shaftAway = (shaftMiddleY - centerY) * (shaftMiddleY - centerY)
            let beadAway = (Rod.beadCenterY - centerY) * (Rod.beadCenterY - centerY)
            let eyeSquare = Rod.eyeRadius * Rod.eyeRadius
            let shaftAcross = shaftMass * (shaftLength * shaftLength / 12 + shaftAway)
            let beadAcross = beadMass * (0.4 * Rod.beadRadius * Rod.beadRadius + beadAway)

            self.mass = mass
            self.centerY = centerY
            // About the axis across the eye, the axis along the shaft, and the eye's own axis.
            let across = eyeMass * (0.5 * eyeSquare + eyeAway) + shaftAcross + beadAcross
            let along = eyeMass * 0.5 * eyeSquare + shaftMass * 0.5 * wire * wire + beadMass * 0.4 * Rod.beadRadius * Rod.beadRadius
            // A rod spins about its own shaft a hundred times more readily than it swings, which makes every
            // touch at its eye whirl it. It is given more inertia there than it has: nobody sees how fast a
            // rod spins about itself, and the solver stays calm.
            self.inertia = Vector(across, max(along, Self.leastInertiaShare * across), eyeMass * (eyeSquare + eyeAway) + shaftAcross + beadAcross)
            self.halfSize = Vector(
                Rod.beadRadius,
                max(-centerY + Rod.eyeRadius + wire, centerY - Rod.beadCenterY + Rod.beadRadius),
                Rod.beadRadius
            )

            let eye = Vector(0, -centerY, 0)
            let bead = Vector(0, Rod.beadCenterY - centerY, 0)
            self.shaft = Segment(start: Vector(0, Rod.shaftTopY - centerY, 0), end: bead)
            self.pieces = [
                Piece(shape: .circle(Circle(center: eye, axisU: Vector(1, 0, 0), axisV: Vector(0, 1, 0), radius: Rod.eyeRadius)), radius: wire),
                Piece(shape: .segment(shaft), radius: wire),
                Piece(shape: .point(PointCore(position: bead)), radius: Rod.beadRadius),
            ]
        }

        func body(at pose: PartPose) -> Body {
            Body(
                position: pose.worldPoint(Vector(0, centerY, 0)),
                orientation: pose.orientation,
                mass: mass,
                inertia: inertia,
                halfSize: halfSize
            )
        }
    }

    /// The bar as its middle sheet, swept by half its thickness, which rounds its edges.
    private static let barPiece: Piece = {
        typealias Bar = Dimensions.Bar
        let sweep = Bar.thickness / 2
        return Piece(
            shape: .stadium(Stadium(
                center: .zero,
                lengthAxis: Vector(1, 0, 0),
                widthAxis: Vector(0, 0, 1),
                halfLength: (Bar.length - Bar.width) / 2,
                radius: Bar.width / 2 - sweep
            )),
            radius: sweep
        )
    }()

    private static func barBody(at pose: PartPose) -> Body {
        typealias Bar = Dimensions.Bar
        let area = (Bar.length - Bar.width) * Bar.width + Double.pi * Bar.width * Bar.width / 4
        let mass = Density.steel * area * Bar.thickness
        let length = Bar.length * Bar.length
        let width = Bar.width * Bar.width
        let thickness = Bar.thickness * Bar.thickness
        return Body(
            position: pose.position,
            orientation: pose.orientation,
            mass: mass,
            inertia: Vector(width + thickness, length + width, length + thickness) * (mass / 12),
            halfSize: Vector(Bar.length, Bar.thickness, Bar.width) / 2
        )
    }

    /// The sword: the tip's half circle as one chain of short pieces, and four straight pieces on each side.
    private static let swordPieces: [Piece] = {
        let tipSegments = 24
        let near = SwordShape.centerline(side: 1, tipSegments: tipSegments)
        let far = SwordShape.centerline(side: -1, tipSegments: tipSegments)
        let wire = Dimensions.Sword.wireRadius

        var pieces = [Piece(
            shape: .polyline(Polyline(points: far[1...tipSegments].reversed() + near[0...tipSegments])),
            radius: wire
        )]
        for side in [near, far] {
            for index in tipSegments..<(side.count - 1) {
                pieces.append(Piece(shape: .segment(Segment(start: side[index], end: side[index + 1])), radius: wire))
            }
        }
        return pieces
    }()
}
