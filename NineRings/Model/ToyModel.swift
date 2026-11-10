import Observation
import Puzzle
import Simulation
import Toy

/// The app's state: which rings are on, the moves made, and the pose being drawn.
///
/// The pose is not observed by views: the 3D view reads it once a frame, after calling `advance(by:)`. The
/// pose comes from the live simulation, which lets the toy settle under its own weight. No hand moves a ring
/// yet, so a change of state glides to that state's stored pose, where the toy is set down afresh.
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

    private(set) var state: PuzzleState
    private(set) var moveCount = 0
    private(set) var refusal: Refusal?

    @ObservationIgnored private var history: [PuzzleState] = []
    @ObservationIgnored private(set) var pose: ToyPose
    /// Goes up by one whenever `pose` changes, so a reader can skip frames where nothing moved.
    @ObservationIgnored private(set) var poseRevision = 0
    @ObservationIgnored private var blend: PoseBlend?
    @ObservationIgnored private var simulation: ToySimulation

    /// A gap between two frames longer than this is not made up for: the toy just moves on this much.
    private static let longestFrame = 1.0 / 30

    init(state: PuzzleState = .allOn) {
        self.state = state
        simulation = ToySimulation(pose: RestPoses.pose(for: state))
        pose = simulation.pose
    }

    var canUndo: Bool { !history.isEmpty }

    /// Moves `ring` on or off if the rule allows it; otherwise records what blocks it.
    func tap(_ ring: Int) {
        if let block = state.block(for: ring) {
            refusal = Refusal(ring: ring, block: block)
            return
        }
        history.append(state)
        moveCount += 1
        show(state.moving(ring))
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        moveCount -= 1
        show(previous)
    }

    func reset(to state: PuzzleState) {
        history.removeAll()
        moveCount = 0
        show(state)
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
        guard !simulation.isAtRest else { return }
        simulation.advance(by: min(seconds, Self.longestFrame))
        pose = simulation.pose
        poseRevision += 1
    }

    private func show(_ newState: PuzzleState) {
        refusal = nil
        state = newState
        simulation = ToySimulation(pose: RestPoses.pose(for: newState))
        blend = PoseBlend(from: pose, to: simulation.pose)
    }
}
