import Puzzle
import SwiftUI

/// The toy filling the window, the strip of ring markers over its bottom edge, and the commands in the toolbar.
struct ContentView: View {
    @State private var model: ToyModel
    @State private var rig: CameraRig
    @State private var stripHeight: CGFloat = 0

    init() {
        let model = ToyModel(state: LaunchOptions.startState ?? .allOn)
        self.model = model
        rig = CameraRig(framing: ToyBounds(model.pose))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // The toy is drawn under the bars, and framed in the part they and the strip leave uncovered.
                let insets = EdgeInsets(top: proxy.safeAreaInsets.top, leading: 0, bottom: proxy.safeAreaInsets.bottom + stripHeight, trailing: 0)
                ToyView(model: model, rig: rig, insets: insets)
                    .ignoresSafeArea()
            }
            .overlay(alignment: .bottom) {
                RingStrip(model: model)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { stripHeight = $0 }
            }
            .toolbar { toolbar }
                #if os(iOS)
                .toolbarTitleDisplayMode(.inline)
                #endif
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                ForEach(CameraPreset.allCases) { preset in
                    Button(preset.title) { rig.show(preset, framing: ToyBounds(model.pose)) }
                        .keyboardShortcut(preset.shortcut, modifiers: .command)
                        .help("View from the \(preset.title.lowercased())")
                }
            } label: {
                Label("View", systemImage: "cube")
            }
            Button("Undo", systemImage: "arrow.uturn.backward") {
                model.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.canUndo)
            Menu {
                Button("All rings on") { model.reset(to: .allOn) }
                Button("All rings off") { model.reset(to: .allOff) }
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
        }
    }
}

private extension CameraPreset {
    var shortcut: KeyEquivalent {
        switch self {
        case .side: "1"
        case .top: "2"
        case .tip: "3"
        }
    }
}

/// Options read from the launch arguments.
enum LaunchOptions {
    /// `-start-state 011110010` opens the app in that state, for checking a particular state by hand.
    static var startState: PuzzleState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-start-state"), index + 1 < arguments.count else { return nil }
        return PuzzleState(arguments[index + 1])
    }
}

#Preview {
    ContentView()
}
