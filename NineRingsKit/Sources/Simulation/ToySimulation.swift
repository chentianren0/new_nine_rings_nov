import Foundation
import Toy
import simd

/// The toy in motion: nine rings, nine rods and the bar as rigid bodies around the fixed sword, under gravity.
///
/// It starts from a pose, moves when it is advanced, and gives back the pose it has reached.
public struct ToySimulation: Sendable {
    /// How many small steps the simulation takes for each second it is advanced.
    public static let stepsPerSecond = 1200.0

    private var world = World()
    private let rodCenterY: Double

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

    /// The fastest any part is moving, in millimetres a second, counting how fast its far end swings.
    public var fastestSpeed: Double {
        world.bodies.map { simd_length($0.velocity) + simd_length($0.angularVelocity) * $0.extent }.max() ?? 0
    }

    /// The deepest any two parts have been left overlapping, in millimetres, since the simulation began.
    /// While it stays a small part of a wire's radius, nothing can have passed through anything.
    public var deepestOverlap: Double { world.deepestOverlap }

    /// Moves the toy on by `time` seconds.
    public mutating func advance(by time: Double) {
        world.advance(by: time, steps: max(1, Int((time * Self.stepsPerSecond).rounded())))
    }

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
            extent: radius + wire
        )
    }

    /// A rod's mass and pieces, laid out around its centre of mass, which lies partway down the shaft.
    private struct RodBuild {
        /// The least inertia about the shaft, as a share of the inertia across it.
        static let leastInertiaShare = 0.1

        let mass: Double
        let inertia: Vector
        let centerY: Double
        let extent: Double
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
            self.extent = max(-centerY + Rod.eyeRadius + wire, centerY - Rod.beadCenterY + Rod.beadRadius)

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
                extent: extent
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
            extent: Bar.length / 2
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
