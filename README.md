# Nine rings

An Apple-native app, for iPhone, iPad and Mac, that shows how a Chinese nine linked rings puzzle (also known as the Baguenaudier) works.

## Layout

- `NineRings/` and `NineRings.xcodeproj`: the app, in SwiftUI and RealityKit. The project file is in Xcode's JSON format, and the `NineRings/` folder is synchronized, so adding a file there does not change the project file.
  - `Scene`: the toy drawn in 3D. Meshes are generated from `Dimensions`, and `ToyScene.apply(_:)` places the parts for any `ToyPose`.
  - `Model`: the app's state, the puzzle state and the pose being drawn.
  - `Views`: the 3D view with its camera, and the strip of ring markers.
  - `Capture`: renders the toy to image files, in debug builds only (see below).
- `NineRingsKit/`: a Swift package with everything that does not depend on the interface.
  - `Puzzle`: which rings are on, the rule that says which ring can move, and the one path through all 512 states.
  - `Toy`: the toy's dimensions, the pose of every part, and a settled pose for each state.
  - `Simulation`: the toy in motion. Nine rings, nine rods and the bar are rigid bodies around the fixed sword, under gravity, that touch and rub but never pass through one another. A hand takes a ring off the sword and puts it back on, the way a person does it, by steering the ring with limited strength and waiting when it is held back. For ring 2 a second hand first lifts ring 1 off the tip and holds it up, so that ring 2 travels round ring 1's rod. So far hands move rings 1 and 2, where the bar hangs within 45 degrees of level and no long chain of rings that are off is in the way; `ToySimulation.aHandCanMove(ring:in:)` says where.

## Building and testing

Run the package's tests. They are built with optimization, because the simulation's tests are slow without it:

```bash
swift test --package-path NineRingsKit -c release -Xswiftc -enable-testing
```

Open `NineRings.xcodeproj` in Xcode 27.2 or later and run the `NineRings` scheme on My Mac.

To compile from the command line without signing, for the Mac:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

And for iPhone and iPad:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

A simulator build has to name a simulator: the destination "Any iOS Simulator Device" does not link, because the package is built without an Intel slice.

The app is built with pointer authentication. `NineRings.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` makes Xcode build the package the same way.

## Checks on GitHub

A pull request that touches the package, the app or the project runs the package's tests and builds the app for the Mac and for iPhone and iPad (`.github/workflows/checks.yml`). One that touches the simulation or the toy's shapes also runs the long checks, which take many minutes (`.github/workflows/sweep.yml`): it simulates all 511 states with a ring on, for three seconds each, and has hands move rings 1 and 2 there and back from every state where they can. Both workflows run on the Xcode the project is developed with, and both can be started by hand from the Actions tab.

To run the long checks at home:

```bash
NINE_RINGS_FULL_SWEEP=1 swift test --package-path NineRingsKit -c release -Xswiftc -enable-testing --filter everyStateHoldsTogether
```

```bash
NINE_RINGS_FULL_SWEEP=1 swift test --package-path NineRingsKit -c release -Xswiftc -enable-testing --filter Wherever
```

## Seeing the app

A debug build of the Mac app can draw the toy to PNG files without opening a window, so an agent can look at what the app renders. It uses the app's own scene, rest poses and camera framing, rendered offscreen by RealityKit.

Build without signing into `scratch/build` (the `scratch/` folder is ignored by git), then launch the app's binary with capture arguments:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' -derivedDataPath scratch/build build CODE_SIGNING_ALLOWED=NO
```

```bash
scratch/build/Build/Products/Debug/NineRings.app/Contents/MacOS/NineRings -capture-states 111111111,000000000 -capture-views side,top -capture-dir "$PWD/scratch/captures"
```

It writes one image per state and view, named `<state>-<view>-<appearance>.png`, prints each path and quits. A state is nine characters, ring 1 first, `1` for on.

- `-capture-views`: `side`, `top` and `tip` are the app's camera presets; `yaw:pitch` in degrees, as `25:18`, looks from any other direction.
- `-capture-focus x,y,z,size`: frames a cube of `size` millimetres around a point in the sword's frame instead of the whole toy, for close checks.
- `-capture-settle 2`: lets the simulation run for that many seconds from the stored pose before drawing, and adds `-settled` to the name.
- `-capture-moves 1,1 -capture-every 0.5`: shows moves instead of states at rest. The first state is left to settle, then a hand moves each of those rings in turn and waits for the toy to come to rest, and the toy is drawn every so many seconds. The images are named `<state>-moves-t<time>-<view>-<appearance>.png`, and a line is printed after each move with the state the toy then reads.
- `-capture-size 1600x1000`: the image size in pixels.
- `-capture-appearance dark`: the dark background.

An unsigned build is not sandboxed, so it can write into the repository. A signed build is, and should be given a folder inside its container, or no `-capture-dir` for its temporary folder.

To open the app itself in a particular state, launch it with `-start-state 011110010`.
