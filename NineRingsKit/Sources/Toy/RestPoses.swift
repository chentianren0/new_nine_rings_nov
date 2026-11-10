import Foundation
import Puzzle
import simd

/// One settled pose of the toy for each of the 512 states.
///
/// The poses were solved without friction, so rings lie flatter across the rails than on a real toy. They hold
/// the toy's topology and no part overlaps another. They serve until the simulation settles its own.
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
        return poses
    }
}
