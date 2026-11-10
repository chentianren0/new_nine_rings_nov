import Observation
import Puzzle
import Toy

/// The app's state: which rings are on, the moves made, and the pose being drawn.
///
/// The pose is not observed by views: the 3D view reads it once a frame, after calling `advance(by:)`. Today
/// the pose glides between rest poses; the live simulation will take over `advance(by:)` and `pose`.
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

    init(state: PuzzleState = .allOn) {
        self.state = state
        pose = RestPoses.pose(for: state)
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
        guard var blend else { return }
        blend.advance(by: seconds)
        pose = blend.pose
        poseRevision += 1
        self.blend = blend.isFinished ? nil : blend
    }

    private func show(_ newState: PuzzleState) {
        refusal = nil
        state = newState
        blend = PoseBlend(from: pose, to: RestPoses.pose(for: newState))
    }
}
