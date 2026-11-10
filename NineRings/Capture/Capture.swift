#if DEBUG
import CoreImage
import Foundation
import Metal
import Puzzle
import RealityKit
import Simulation
import Toy

/// Renders the toy to PNG files without a window and quits: how an agent sees what the app draws.
///
/// Launch the debug app with, for example,
/// `-capture-states 111111111,000000000 -capture-views side,top -capture-dir scratch/captures`.
/// A view is a preset (`side`, `top`, `tip`) or a yaw and a pitch in degrees, as `30:20`.
/// Optional: `-capture-size 1600x1000` (pixels), `-capture-appearance dark`, and `-capture-focus x,y,z,size`
/// to frame a cube of `size` millimetres around a point in the sword's frame instead of the whole toy.
/// `-capture-settle 2` lets the simulation run for that many seconds from the stored pose before drawing.
/// Each image is named `<state>-<view>-<appearance>.png`, with `-settled` after the state when it was left
/// to settle. The scene, the poses and the framing are the app's own.
///
/// `-capture-moves 1,1 -capture-every 0.5` shows moves instead: the first state is left to settle, then a
/// hand moves each of those rings in turn, off the sword if it is on and back on if it is off, and waits
/// for the toy to come to rest before the next. The toy is drawn every so many seconds from when the first
/// hand began. Those images are named `<state>-moves-t<time>-<view>-<appearance>.png`.
///
/// `-capture-taps 1,1 -capture-every 0.5` does the same through the app's own model: the rings are tapped in
/// turn as a person would tap them, each when the toy has come to rest after the last, and the pose the model
/// gives is drawn. A hand moves a ring where it can, and the toy glides elsewhere, as in the app. Those
/// images are named `<state>-taps-t<time>-<view>-<appearance>.png`.
@MainActor
enum Capture {
    struct Request {
        var states: [PuzzleState]
        var views: [View]
        var focus: (center: SIMD3<Float>, size: Float)?
        /// How long the simulation runs from the stored pose before the toy is drawn; nil to draw the stored pose.
        var settle: Double?
        /// Rings for a hand in the simulation to move in turn.
        var moves: [Int]?
        /// Rings to tap in turn on the app's model.
        var taps: [Int]?
        /// How many seconds pass between drawings of a toy in motion.
        var every: Double
        var directory: URL
        var size: CGSize
        var appearance: Backdrop.Appearance
    }

    static let request: Request? = parse(ProcessInfo.processInfo.arguments)

    static func run(_ request: Request) async {
        do {
            try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
            let renderer = try await Renderer(size: request.size, appearance: request.appearance)
            if let state = request.states.first, let rings = request.moves {
                try await filmMoves(of: rings, from: state, renderer: renderer, request: request)
                exit(0)
            }
            if let state = request.states.first, let rings = request.taps {
                try await filmTaps(on: rings, from: state, renderer: renderer, request: request)
                exit(0)
            }
            for state in request.states {
                let pose = pose(for: state, settledFor: request.settle)
                for view in request.views {
                    let settled = request.settle == nil ? "" : "-settled"
                    let name = "\(state)\(settled)-\(view.name)-\(request.appearance.rawValue).png"
                    let url = request.directory.appending(path: name)
                    try await renderer.render(pose, view: view, focus: request.focus, to: url)
                    print("capture: wrote \(url.path)")
                }
            }
            exit(0)
        } catch {
            print("capture: failed: \(error)")
            exit(1)
        }
    }

    /// Has a hand in the simulation move each ring in turn, from `state` left to settle, and films the toy.
    private static func filmMoves(of rings: [Int], from state: PuzzleState, renderer: Renderer, request: Request) async throws {
        let step = 1.0 / 120
        var toy = ToySimulation(pose: RestPoses.pose(for: state))
        for _ in 0..<240 {
            toy.advance(by: step)
        }
        var film = Film(name: "\(state)-moves", renderer: renderer, request: request)
        for ring in rings {
            guard toy.move(ring: ring) else {
                print("capture: a hand cannot move ring \(ring) while the toy reads \(toy.pose.ringsOnTheSword)")
                continue
            }
            // A move that has not come to rest in half a minute is cut short, so a jam still ends.
            var steps = 0
            while !toy.isAtRest && steps < 30 * 120 {
                try await film.roll(toy.pose, by: step)
                toy.advance(by: step)
                steps += 1
            }
            print("capture: ring \(ring) moved, the toy reads \(toy.pose.ringsOnTheSword) at \(film.clock) s\(toy.isAtRest ? "" : ", not at rest")")
        }
        try await film.draw(toy.pose)
    }

    /// Taps each ring in turn as a person would, on the app's model in `state` left to settle, and films the
    /// pose the model gives, frame by frame as the app's view would.
    private static func filmTaps(on rings: [Int], from state: PuzzleState, renderer: Renderer, request: Request) async throws {
        let frame = 1.0 / 60
        let model = ToyModel(state: state)
        for _ in 0..<(5 * 60) where !model.isStill {
            model.advance(by: frame)
        }
        var film = Film(name: "\(state)-taps", renderer: renderer, request: request)
        for ring in rings {
            let before = model.state
            model.tap(ring)
            let how = model.handMove != nil ? "a hand moves it" : model.refusal != nil ? "the rule refuses" : "it glides"
            print("capture: tapped ring \(ring) in \(before) at \(film.clock) s: \(how)")
            var byHand = model.handMove != nil
            // A move that has not come to rest in half a minute is cut short, so a jam still ends.
            var frames = 0
            while !model.isStill && frames < 30 * 60 {
                try await film.roll(model.pose, by: frame)
                model.advance(by: frame)
                frames += 1
                if byHand && model.handMove == nil {
                    byHand = false
                    print("capture: the move ended at \(film.clock) s, the model reads \(model.state), the toy \(model.pose.ringsOnTheSword)")
                }
            }
            print("capture: the model reads \(model.state), the toy \(model.pose.ringsOnTheSword) at \(film.clock) s\(model.isStill ? "" : ", not still")")
        }
        try await film.draw(model.pose)
    }

    /// The stored pose of a state, or what the simulation makes of it in `seconds`.
    private static func pose(for state: PuzzleState, settledFor seconds: Double?) -> ToyPose {
        let stored = RestPoses.pose(for: state)
        guard let seconds else { return stored }
        var toy = ToySimulation(pose: stored)
        for _ in 0..<Int((seconds * 60).rounded()) {
            toy.advance(by: 1.0 / 60)
        }
        return toy.pose
    }

    private static func parse(_ arguments: [String]) -> Request? {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let statesArgument = value("-capture-states") else { return nil }
        let states = statesArgument.split(separator: ",").compactMap { PuzzleState(String($0)) }
        let views = (value("-capture-views") ?? "side,top").split(separator: ",").compactMap { View(String($0)) }
        let focusNumbers = value("-capture-focus")?.split(separator: ",").compactMap { Float($0) } ?? []
        let focus = focusNumbers.count == 4 ? (SIMD3(focusNumbers[0], focusNumbers[1], focusNumbers[2]), focusNumbers[3]) : nil
        let directory = value("-capture-dir").map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory.appending(path: "captures")
        let dimensions = (value("-capture-size") ?? "1600x1000").split(separator: "x").compactMap { Double($0) }
        let size = dimensions.count == 2 ? CGSize(width: dimensions[0], height: dimensions[1]) : CGSize(width: 1600, height: 1000)
        let appearance = value("-capture-appearance").flatMap(Backdrop.Appearance.init(rawValue:)) ?? .light
        let settle = value("-capture-settle").flatMap { Double($0) }
        let every = value("-capture-every").flatMap { Double($0) } ?? 0.5
        let rings = { (text: String) in text.split(separator: ",").compactMap { Int($0) } }
        return Request(
            states: states, views: views, focus: focus, settle: settle,
            moves: value("-capture-moves").map(rings), taps: value("-capture-taps").map(rings), every: max(every, 0.05),
            directory: directory, size: size, appearance: appearance
        )
    }

    /// Where a capture looks from.
    struct View {
        var name: String
        var yaw: Float
        var pitch: Float

        init?(_ text: String) {
            if let preset = CameraPreset(rawValue: text) {
                (name, yaw, pitch) = (text, preset.angles.yaw, preset.angles.pitch)
                return
            }
            let degrees = text.split(separator: ":").compactMap { Float($0) }
            guard degrees.count == 2 else { return nil }
            (name, yaw, pitch) = ("yaw\(Int(degrees[0]))-pitch\(Int(degrees[1]))", degrees[0] * .pi / 180, degrees[1] * .pi / 180)
        }
    }

    /// Draws a toy in motion every so often, each image named by the time it was drawn.
    private struct Film {
        let name: String
        let renderer: Renderer
        let request: Request
        private(set) var time = 0.0
        private var nextDrawing = 0.0

        init(name: String, renderer: Renderer, request: Request) {
            self.name = name
            self.renderer = renderer
            self.request = request
        }

        /// The time, as it is written in names and printed.
        var clock: String {
            time.formatted(.number.precision(.integerAndFractionLength(integerLimits: 2..., fractionLimits: 2...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        }

        /// Draws `pose` if a drawing is due, then moves the clock on by `seconds`.
        mutating func roll(_ pose: ToyPose, by seconds: Double) async throws {
            if time >= nextDrawing - 1e-9 {
                try await draw(pose)
                nextDrawing += request.every
            }
            time += seconds
        }

        func draw(_ pose: ToyPose) async throws {
            for view in request.views {
                let url = request.directory.appending(path: "\(name)-t\(clock)-\(view.name)-\(request.appearance.rawValue).png")
                try await renderer.render(pose, view: view, focus: request.focus, to: url)
                print("capture: wrote \(url.path)")
            }
        }
    }

    /// An offscreen RealityKit renderer holding the app's scene.
    private final class Renderer {
        private let scene: ToyScene
        private let renderer: RealityRenderer
        private let camera = Entity()
        private let texture: any MTLTexture
        private let output: RealityRenderer.CameraOutput
        private let size: CGSize

        init(size: CGSize, appearance: Backdrop.Appearance) async throws {
            self.size = size
            scene = try await ToyScene.make()
            renderer = try RealityRenderer()
            renderer.entities.append(scene.root)
            camera.components.set(OrbitCamera.component())
            renderer.entities.append(camera)
            renderer.activeCamera = camera
            renderer.cameraSettings.colorBackground = .color(appearance.backgroundColor)
            renderer.cameraSettings.antialiasing = .multisample4X

            guard let device = MTLCreateSystemDefaultDevice() else { throw CaptureError.noMetal }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb, width: Int(size.width), height: Int(size.height), mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw CaptureError.noTexture }
            self.texture = texture
            output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        }

        func render(_ pose: ToyPose, view: View, focus: (center: SIMD3<Float>, size: Float)?, to url: URL) async throws {
            scene.apply(pose)
            let box = focus.map { ToyBounds(center: $0.center, size: $0.size) } ?? ToyBounds(pose)
            camera.transform = OrbitCamera.framing(yaw: view.yaw, pitch: view.pitch, of: box, in: Viewport(size: size)).transform
            // The first frame after a change can still be settling resources; draw twice and keep the second.
            for _ in 0..<2 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    do {
                        try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in
                            continuation.resume()
                        })
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            // The texture is sRGB-encoded, so Metal hands Core Image linear values when it reads it.
            guard let image = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!]) else {
                throw CaptureError.noImage
            }
            // Metal's rows run top to bottom, Core Image's bottom to top.
            let upright = image.oriented(.downMirrored)
            try CIContext().writePNGRepresentation(of: upright, to: url, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
    }

    enum CaptureError: Error {
        case noMetal, noTexture, noImage
    }
}
#endif
