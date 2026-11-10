import Puzzle
import SwiftUI
import Toy

/// A placeholder that shows the app is linked to the puzzle logic and the toy's poses.
struct ContentView: View {
    private let state = PuzzleState.allOn

    var body: some View {
        VStack(spacing: 8) {
            Text("Nine rings")
                .font(.title)
            Text("State \(state.description), \(state.rank) moves from all off")
            Text("Ring 1 rests \(ringOneX, format: .number.precision(.fractionLength(1))) mm from the tip")
        }
        .padding()
    }

    private var ringOneX: Double {
        RestPoses.pose(for: state).ring(1).position.x
    }
}

#Preview {
    ContentView()
}
