import Foundation
import Puzzle
import simd

/// One settled pose of the toy for each of the 512 states.
///
/// The poses were solved without friction, so rings lie flatter across the rails than on a real toy. They hold
/// the toy's topology and no part overlaps another. They serve until the simulation settles its own.
///
/// The solver kept the middle of the bar at one place along the sword in every state, so with few rings on
/// it left those rings far from the tip. A person moves rings at the tip, and the rings that are on stay
/// where the bar holds them from there. So each pose is given slid along the rails until the first ring that
/// is on lies where it lies when all nine are on. The rails are straight and level there, and a pose slid
/// along them rests as well as before.
public enum RestPoses {
    public static func pose(for state: PuzzleState) -> ToyPose {
        guard let pose = all[state] else {
            preconditionFailure("no rest pose stored for state \(state)")
        }
        return pose
    }

    static let all: [PuzzleState: ToyPose] = load()

    /// The resource lists, for each state, nineteen parts in a fixed order: rings 1 to 9, rods 1 to 9, the bar.
    /// Each part is seven numbers: its position, then its orientation as a quaternion with the scalar last.
    private struct File: Decodable {
        var poses: [String: [[Double]]]
    }

    private static func load() -> [PuzzleState: ToyPose] {
        guard let url = Bundle.module.url(forResource: "RestPoses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            preconditionFailure("the rest poses resource is missing or unreadable")
        }
        var poses: [PuzzleState: ToyPose] = [:]
        for (key, parts) in file.poses {
            guard let state = PuzzleState(key), parts.count == 19, parts.allSatisfy({ $0.count == 7 }) else {
                preconditionFailure("malformed rest pose for \(key)")
            }
            let placed = parts.map { numbers in
                PartPose(
                    position: SIMD3(numbers[0], numbers[1], numbers[2]),
                    orientation: simd_normalize(simd_quatd(ix: numbers[3], iy: numbers[4], iz: numbers[5], r: numbers[6]))
                )
            }
            poses[state] = ToyPose(rings: Array(placed[0..<9]), rods: Array(placed[9..<18]), bar: placed[18])
        }

        guard let allOn = poses[.allOn] else {
            preconditionFailure("no rest pose stored for the state with every ring on")
        }
        for (state, pose) in poses {
            guard let first = (1...9).first(where: { state.isOn($0) }) else { continue }
            let slide = SIMD3(allOn.ring(first).position.x - pose.ring(first).position.x, 0, 0)
            func slid(_ part: PartPose) -> PartPose {
                PartPose(position: part.position + slide, orientation: part.orientation)
            }
            poses[state] = ToyPose(rings: pose.rings.map(slid), rods: pose.rods.map(slid), bar: slid(pose.bar))
        }
        return poses
    }
}
