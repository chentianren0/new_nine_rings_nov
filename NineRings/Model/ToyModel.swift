import Observation
import Puzzle
import Simulation
import Toy

/// The app's state: which rings are on, the moves made, and the pose being drawn.
///
/// The pose is not observed by views: the 3D view reads it once a frame, after calling `advance(by:)`. The
/// pose comes from the live simulation, which lets the toy settle under its own weight. A tapped ring is moved
/// by a hand in the simulation where a hand can move it; anywhere else, and wherever a hand fails, the toy
/// glides to the stored pose of the new state and is set down there afresh.
@Observable
final class ToyModel {
    /// Why the last ring tapped could not move.
    struct Refusal: Equatable {
        var ring: Int
        var block: PuzzleState.Block

        /// The ring that stands in the way.
        var blockingRing: Int {
            switch block {
            case .earlierRingOn(let ring), .previousRingOff(let ring): ring
            }
        }
    }

    /// A ring that a hand is moving, and the state the puzzle will be in once it arrives.
    struct HandMove: Equatable {
        var ring: Int
        var target: PuzzleState
    }

    /// Which rings are on. While a hand moves a ring this is still the state before the move: the move counts
    /// once the ring has arrived, or once the toy has glided there because the hand failed.
    private(set) var state: PuzzleState
    private(set) var moveCount = 0
    private(set) var refusal: Refusal?
    /// The move a hand is making, if one is. Taps are ignored until it ends.
    private(set) var handMove: HandMove?

    @ObservationIgnored private var history: [PuzzleState] = []
    @ObservationIgnored private(set) var pose: ToyPose
    /// Goes up by one whenever `pose` changes, so a reader can skip frames where nothing moved.
    @ObservationIgnored private(set) var poseRevision = 0
    @ObservationIgnored private var blend: PoseBlend?
    @ObservationIgnored private var simulation: ToySimulation
    /// How long the toy has been left to come to rest since the hand let go of a ring that did not arrive.
    @ObservationIgnored private var waitAfterHand = 0.0

    /// A gap between two frames longer than this is not made up for: the toy just moves on this much.
    private static let longestFrame = 1.0 / 30
    /// How long a ring the hand let go of short of its place is given to settle there before the toy glides.
    private static let longestWaitAfterHand = 3.0

    init(state: PuzzleState = .allOn) {
        self.state = state
        simulation = ToySimulation(pose: RestPoses.pose(for: state))
        pose = simulation.pose
    }

    var canUndo: Bool { !history.isEmpty && handMove == nil }

    /// Whether nothing is moving: no hand, no glide, and the toy at rest.
    var isStill: Bool { handMove == nil && blend == nil && simulation.isAtRest }

    /// Moves `ring` on or off if the rule allows it; otherwise records what blocks it. Does nothing while a
    /// hand is moving a ring.
    func tap(_ ring: Int) {
        guard handMove == nil else { return }
        if let block = state.block(for: ring) {
            refusal = Refusal(ring: ring, block: block)
            return
        }
        refusal = nil
        let target = state.moving(ring)
        // The hand starts from the toy as it lies, so the toy has to read as the state the puzzle is in.
        if blend == nil, simulation.pose.ringsOnTheSword == state, simulation.move(ring: ring) {
            handMove = HandMove(ring: ring, target: target)
            waitAfterHand = 0
        } else {
            record(target)
            glide(to: target)
        }
    }

    func undo() {
        guard handMove == nil, let previous = history.popLast() else { return }
        moveCount -= 1
        refusal = nil
        state = previous
        glide(to: previous)
    }

    /// Sets the puzzle to `state` afresh, stopping any hand that is moving a ring.
    func reset(to state: PuzzleState) {
        history.removeAll()
        moveCount = 0
        handMove = nil
        refusal = nil
        self.state = state
        glide(to: state)
    }

    /// Moves the drawing on by `seconds`. Called once a frame.
    func advance(by seconds: Double) {
        if var blend {
            blend.advance(by: seconds)
            pose = blend.pose
            poseRevision += 1
            self.blend = blend.isFinished ? nil : blend
            return
        }
        if !simulation.isAtRest {
            simulation.advance(by: min(seconds, Self.longestFrame))
            pose = simulation.pose
            poseRevision += 1
        }
        if let handMove, !simulation.handIsBusy {
            finish(handMove, after: seconds)
        }
    }

    /// Ends a move once the hand has let go: the ring has arrived, or it is given a little while to settle
    /// into place, and the toy glides there if it does not.
    private func finish(_ move: HandMove, after seconds: Double) {
        let arrived = simulation.pose.ringsOnTheSword == move.target
        waitAfterHand += seconds
        guard arrived || simulation.isAtRest || waitAfterHand >= Self.longestWaitAfterHand else { return }
        handMove = nil
        record(move.target)
        if !arrived {
            glide(to: move.target)
        }
    }

    /// Makes `newState` the puzzle's state as one more move.
    private func record(_ newState: PuzzleState) {
        history.append(state)
        moveCount += 1
        state = newState
    }

    /// Glides the toy to the stored pose of `state`, where the simulation starts afresh.
    private func glide(to state: PuzzleState) {
        simulation = ToySimulation(pose: RestPoses.pose(for: state))
        blend = PoseBlend(from: pose, to: simulation.pose)
    }
}
