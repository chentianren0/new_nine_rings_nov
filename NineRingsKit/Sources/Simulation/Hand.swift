import Foundation
import Toy
import simd

/// A hand moving one ring off the sword or back on, the way a person does it, or holding one ring up out of
/// the way of another.
///
/// The hand does not place the ring. It steers the ring toward where it wants it, with limited strength, so the
/// rest of the toy steers the ring too: a wire in the way turns the ring aside instead of being pushed through.
/// It does not run ahead of the ring either: while the ring is held back, the hand waits for it.
struct Hand: Sendable {
    /// A place on the way: where the ring's centre is to be, and the way the ring's axis points. A ring is
    /// the same from both sides, so either way along the axis is the same place.
    struct Station: Sendable {
        var centre: SIMD3<Double>
        var axis: SIMD3<Double>
    }

    /// A stretch of the way. Its stations are laid out when the hand comes to it, from where the toy's parts
    /// are then: what the hand does next depends on where the stretch before has left them.
    enum Leg: Sendable {
        /// Coming off: from its place on the rails to lying flat over the tip end.
        case ontoTheTip
        /// Coming off: tipped up off the tip, turned to stand along the slot, and lowered between the rails.
        case intoTheSlot
        /// Coming off: leaned under the rails and swung down to hang.
        case underTheRails
        /// Going on: swung up level under the rails, leaned, and raised through the slot to stand above it.
        case outFromUnder
        /// Going on: turned across the sword and tipped down flat over the tip end.
        case backOverTheTip
        /// Going on: slid along the rails to where it rests.
        case home(Station)
        /// Out of the way: tipped up off the tip and raised until its rod stands well up through the slot.
        case upOutOfTheWay
        /// Out of the way: held up there, loosely, until the hand is told to let it down.
        case heldUp
    }

    let ring: Int
    private var legs: [Leg]
    private var stretch: Stretch?
    /// Where the hand last wanted the ring, and for how long it has now been waiting for the ring to follow.
    private var wanted: Station?
    private var waited = 0.0
    /// Where the hand is holding its ring up out of the way, while it does.
    private var holdingAt: Station?

    /// Whether the hand has its ring up out of the way and is holding it there.
    var isHoldingUp: Bool { holdingAt != nil }

    /// Ends the hold: the hand goes on to put its ring back.
    mutating func letDown() {
        holdingAt = nil
    }

    /// A hand that takes a ring off the sword: tips it flat over the tip end, tips it up off the tip, stands
    /// it along the slot and lowers it between the rails, leans it under them and lets it swing down to hang.
    static func takingOff(ring: Int) -> Hand {
        Hand(ring: ring, legs: [.ontoTheTip, .intoTheSlot, .underTheRails])
    }

    /// A hand that puts a ring back on the sword by the same way backwards, and sets it down where it lies in
    /// `resting`, a pose of the toy at rest with that ring on.
    static func puttingOn(ring: Int, restingAs resting: ToyPose) -> Hand {
        Hand(ring: ring, legs: [.outFromUnder, .backOverTheTip, .home(station(of: resting.ring(ring)))])
    }

    /// A hand that lifts a ring off the tip and holds it up, so that its rod stands up through the slot and
    /// the next ring can travel round that rod; once told to, it puts the ring back where it lies in `resting`.
    static func holdingUp(ring: Int, restingAs resting: ToyPose) -> Hand {
        Hand(ring: ring, legs: [.ontoTheTip, .upOutOfTheWay, .heldUp, .backOverTheTip, .home(station(of: resting.ring(ring)))])
    }

    private init(ring: Int, legs: [Leg]) {
        self.ring = ring
        self.legs = legs
    }

    /// Moves the hand on by `time`, given where the toy's parts are now, and gives where it wants its ring,
    /// or `nil` once it has let go.
    mutating func advance(by time: Double, in pose: ToyPose) -> Station? {
        if let holdingAt { return holdingAt }
        let ringNow = Self.station(of: pose.ring(ring))

        // How far the ring is behind sets the hand's pace: full while the ring keeps up, none while it is
        // well behind. A ring that stays behind is stuck, and in the end the hand lets it go.
        var pace = 1.0
        if let wanted {
            let turn = acos(min(1, abs(simd_dot(ringNow.axis, wanted.axis))))
            let behind = simd_distance(ringNow.centre, wanted.centre) + turn * Dimensions.Ring.radius
            pace = max(0, min(1, 2 - behind / Self.slack))
            waited = pace < 0.5 ? waited + time : 0
            if waited > Self.patience {
                legs = []
                stretch = nil
            }
        }

        while true {
            if stretch == nil {
                guard !legs.isEmpty else {
                    wanted = nil
                    return nil
                }
                let leg = legs.removeFirst()
                let stations = Self.stations(of: leg, for: ring, in: pose)
                if case .heldUp = leg {
                    holdingAt = stations[0]
                    wanted = nil
                    return holdingAt
                }
                stretch = Stretch(from: ringNow, through: stations, holdsAtItsEnd: legs.isEmpty)
            }
            if let station = stretch?.advance(by: time * pace) {
                wanted = station
                return station
            }
            stretch = nil
        }
    }

    /// The ring may be this far behind, in millimetres, before the hand slows for it; at twice this the hand
    /// stands still. A turn counts as the distance it moves the ring's rim.
    private static let slack = 3.0
    /// How long the hand waits for a ring that does not come, in seconds, before it lets go.
    private static let patience = 2.0

    private static func station(of ring: PartPose) -> Station {
        Station(centre: ring.position, axis: ring.worldDirection(SIMD3(0, 0, 1)))
    }
}

// MARK: The way

extension Hand {
    /// The stations of one leg, for the toy as it is now.
    ///
    /// The frame is the toy's: x from the tip toward the grip, y up, the slot along z = 0, the tip's end at
    /// the origin.
    private static func stations(of leg: Leg, for number: Int, in pose: ToyPose) -> [Station] {
        typealias Sword = Dimensions.Sword
        let radius = Dimensions.Ring.radius
        let up = SIMD3<Double>(0, 1, 0)
        let along = SIMD3<Double>(0, 0, 1)

        // Flat over the tip end: level, round the tip's half circle, lying on the rails where it crosses them.
        // The tip's loop is narrower than the ring's opening, so the tip passes out of the ring as the ring is
        // tipped up from here about its grip-side point, where its eye holds it, until it stands across the
        // sword. The eye stays at that point all the way, at the ring's foot.
        let seatX = Sword.railOffset + (radius * radius - Sword.railOffset * Sword.railOffset).squareRoot()
        let flatHeight = Sword.height(atX: seatX) + Dimensions.Ring.wireRadius + Sword.wireRadius + 0.3
        let flat = Station(centre: SIMD3(Sword.railOffset, flatHeight, 0), axis: up)
        let foot = SIMD3(Sword.railOffset + radius, flatHeight, 0)
        func tipped(by angle: Double) -> Station {
            Station(centre: foot + radius * SIMD3(-cos(angle), sin(angle), 0), axis: SIMD3(sin(angle), cos(angle), 0))
        }
        // Ring 1 is tipped up until it stands. Any later ring has the rod of the ring before it standing up
        // through it, and a ring that stood upright there would have that rod in its own plane: it is tipped
        // up less far, so that it leans toward the tip and the rod goes through its middle.
        let upright = number == 1 ? Double.pi / 2 : 70 * Double.pi / 180

        // Standing along the slot, a little toward the tip from where its own eye is when it rests: there the
        // ring's lowest point comes down in front of the next ring's lower arc and pushes that arc back, not
        // forward. For ring 1 that is a little toward the tip from the foot; each later ring's place is one
        // hole further along. At the lower height the ring's widest part is just under the rails.
        func standing(overX x: Double, atHeight height: Double) -> Station {
            Station(centre: SIMD3(x, height, 0), axis: along)
        }
        let slotX = foot.x - 3.5 + Dimensions.Bar.holePitch * Double(number - 1)
        let aboveHeight = Sword.railHeight + radius + 3.5
        let throughHeight = Sword.railHeight - 2.5

        // Under the rails the ring turns about its eye. While the next ring is on the sword, that ring's
        // lower arc catches the eye not far under the rails, long before the ring itself is under them, so
        // a ring standing in the slot cannot go straight down. It leans to one side and slides under on that
        // side, its top passing down inside the other rail, until it lies level under the rails, toward the
        // tip from its eye; from there it swings down to hang from the eye.
        let centre = pose.ring(number).position
        let eye = pose.rod(number).position
        /// How far the eye's middle can be from the ring's wire, the wire being inside the eye.
        let play = Dimensions.Rod.eyeRadius - Dimensions.Rod.wireRadius - Dimensions.Ring.wireRadius
        let reach = min(max(simd_distance(centre, eye), radius - play), radius + play)
        // No further toward the tip than where a ring can still rise into the slot inside the tip's end: an
        // eye that was caught nearer the tip than that is nudged back by the ring's own wire.
        let level = Station(centre: SIMD3(max(eye.x - reach, slotX - 5), eye.y, 0), axis: up)
        // A level ring is wider than the slot, so the side that tilts up has first to be brought inside its
        // rail: the ring is slid aside by what that takes, and three millimetres more, for a ring follows
        // its hand a millimetre or two behind. The higher the eye was caught, the sooner the rising side
        // meets the rail and the further aside the ring has to be.
        let railUnderside = Sword.railHeight - Sword.wireRadius - Dimensions.Ring.wireRadius
        let slotHalfWidth = Sword.railOffset - Sword.wireRadius - Dimensions.Ring.wireRadius
        let rise = min(max((railUnderside - eye.y) / radius, 0), 1)
        let aside = SIMD3(0, 0, -(max(0, radius * (1 - rise * rise).squareRoot() - slotHalfWidth) + 3))
        let levelAside = Station(centre: level.centre + aside, axis: up)
        let leaning = Station(
            centre: level.centre + aside,
            axis: SIMD3(0, -sin(Double.pi / 3), cos(Double.pi / 3))
        )
        let hangAngle = Double.pi / 6
        let hanging = Station(
            centre: eye + reach * SIMD3(-sin(hangAngle), -cos(hangAngle), 0),
            axis: SIMD3(cos(hangAngle), -sin(hangAngle), 0)
        )

        // Held up out of the way: standing across the sword over the tip side of the slot, a ring's height
        // and a little more above the rails, so that the next ring can stand and turn under it.
        let parked = Station(centre: SIMD3(foot.x - 3, flatHeight + 3 * radius + 6, 0), axis: SIMD3(1, 0, 0))

        switch leg {
        case .upOutOfTheWay:
            return [tipped(by: upright / 2), tipped(by: upright), parked]
        case .heldUp:
            return [parked]
        case .ontoTheTip:
            return [flat]
        case .intoTheSlot:
            return [
                tipped(by: upright / 2), tipped(by: upright),
                standing(overX: slotX, atHeight: aboveHeight), standing(overX: slotX, atHeight: throughHeight),
            ]
        case .underTheRails:
            // An eye that nothing has caught is still at the ring's lowest point, coming down with it: then
            // the ring goes straight on down until it is under the rails.
            guard centre.y - eye.y < radius else {
                return [standing(overX: centre.x, atHeight: Sword.railHeight - radius - 4)]
            }
            return [leaning, levelAside, level, hanging]
        case .outFromUnder:
            let x = level.centre.x + 5
            return [level, levelAside, leaning, standing(overX: x, atHeight: throughHeight), standing(overX: x, atHeight: aboveHeight)]
        case .backOverTheTip:
            return [tipped(by: upright), tipped(by: upright / 2), flat]
        case .home(let resting):
            return [resting]
        }
    }
}

// MARK: One stretch

/// A run of stations that the hand passes at an even pace, gathering pace at the start and losing it at the end.
private struct Stretch: Sendable {
    /// The stations in order, the first being where the ring was when the stretch began.
    private let stations: [Hand.Station]
    /// How far along the stretch each station is, in seconds of travel at full pace.
    private let arrivals: [Double]
    private let hold: Double
    private var elapsed = 0.0

    init(from start: Hand.Station, through stations: [Hand.Station], holdsAtItsEnd: Bool) {
        var path = [start]
        var arrivals = [0.0]
        for station in stations {
            let last = path[path.count - 1]
            // Facing the way that takes the smaller turn from the station before.
            let axis = simd_dot(last.axis, station.axis) < 0 ? -station.axis : station.axis
            let turn = acos(min(1, simd_dot(last.axis, axis)))
            let travel = max(simd_distance(last.centre, station.centre) / Self.pace, turn / Self.turningPace, 0.01)
            path.append(Hand.Station(centre: station.centre, axis: axis))
            arrivals.append(arrivals[arrivals.count - 1] + travel)
        }
        self.stations = path
        self.arrivals = arrivals
        hold = holdsAtItsEnd ? Self.lastHold : 0
    }

    /// Moves on by `time` and gives the place reached, or `nil` once the stretch is over.
    mutating func advance(by time: Double) -> Hand.Station? {
        elapsed += time
        let length = arrivals[arrivals.count - 1]
        let run = min(Self.runUp, length)
        guard elapsed < length + run + hold else { return nil }

        let travelled: Double
        if elapsed < run {
            travelled = elapsed * elapsed / (2 * run)
        } else if elapsed < length {
            travelled = elapsed - run / 2
        } else {
            let left = max(0, length + run - elapsed)
            travelled = length - left * left / (2 * run)
        }

        let next = arrivals.firstIndex { $0 > travelled } ?? arrivals.count - 1
        let share = min(1, (travelled - arrivals[next - 1]) / (arrivals[next] - arrivals[next - 1]))
        let from = stations[next - 1], to = stations[next]
        return Hand.Station(
            centre: simd_mix(from.centre, to.centre, SIMD3(repeating: share)),
            axis: Self.turned(from.axis, toward: to.axis, by: share)
        )
    }

    /// The direction a share of the way round from one direction to another.
    private static func turned(_ from: SIMD3<Double>, toward to: SIMD3<Double>, by share: Double) -> SIMD3<Double> {
        let angle = acos(max(-1, min(1, simd_dot(from, to))))
        guard angle > 1e-9 else { return to }
        return (from * sin((1 - share) * angle) + to * sin(share * angle)) / sin(angle)
    }

    /// How fast the hand carries a ring, in millimetres a second, and how fast it turns one, in radians a second.
    private static let pace = 36.0
    private static let turningPace = 2.4
    /// How long the hand takes to gather pace, and how long it holds the ring at the last station of all
    /// before it lets go, in seconds.
    private static let runUp = 0.2
    private static let lastHold = 0.15
}
