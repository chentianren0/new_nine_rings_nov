# Nine rings

An Apple-native app, for iPhone, iPad and Mac, that shows how a Chinese nine linked rings puzzle (also known as the Baguenaudier) works.

## Layout

- `NineRings/` and `NineRings.xcodeproj`: the app, in SwiftUI. The project file is in Xcode's JSON format, and the `NineRings/` folder is synchronized, so adding a file there does not change the project file.
- `NineRingsKit/`: a Swift package with everything that does not depend on the interface.
  - `Puzzle`: which rings are on, the rule that says which ring can move, and the one path through all 512 states.
  - `Toy`: the toy's dimensions, the pose of every part, and a settled pose for each state.
  - `Simulation`: the toy in motion. Nine rings, nine rods and the bar are rigid bodies around the fixed sword, under gravity, that touch and rub but never pass through one another.

## Building and testing

Run the package's tests. They are built with optimization, because the simulation's tests are slow without it:

```bash
swift test --package-path NineRingsKit -c release -Xswiftc -enable-testing
```

Open `NineRings.xcodeproj` in Xcode 27.2 or later and run the `NineRings` scheme on My Mac or on an iOS simulator.

To compile from the command line without signing:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

For a simulator, name one, as in `-destination 'platform=iOS Simulator,name=iPhone Duo'`. The destination "Any iOS Simulator Device" does not link, because the package is built without an Intel slice.

The app is built with pointer authentication. `NineRings.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` makes Xcode build the package the same way.
