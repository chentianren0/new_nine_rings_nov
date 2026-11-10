import CoreGraphics

/// Holds the camera the 3D view draws from: gestures move it, presets fly it, and a change of view size
/// keeps the toy framed.
///
/// The 3D view reads `camera` once a frame, after calling `advance(by:)`; nothing here is observed by SwiftUI.
@MainActor
final class CameraRig {
    private(set) var camera: OrbitCamera
    /// Goes up by one whenever `camera` changes, so a reader can skip frames where nothing moved.
    private(set) var revision = 0
    private(set) var viewport = Viewport(size: .zero)
    private var flight: (from: OrbitCamera, to: CameraPreset, elapsed: Double)?
    private var hasBeenFramed = false
    /// The box the camera was last framed on.
    private var box: ToyBounds

    init(framing box: ToyBounds) {
        self.box = box
        camera = OrbitCamera.framing(.side, of: box, in: viewport)
    }

    private static let flightDuration = 0.6

    /// Flies the camera to `preset`, framing `box`.
    func show(_ preset: CameraPreset, framing box: ToyBounds) {
        self.box = box
        flight = (camera, preset, 0)
    }

    func resize(to newViewport: Viewport) {
        guard newViewport != viewport else { return }
        let old = viewport
        viewport = newViewport
        guard !newViewport.isEmpty else { return }
        if hasBeenFramed {
            camera.refit(box, from: old, to: newViewport)
        } else {
            camera = OrbitCamera.framing(.side, of: box, in: newViewport)
            hasBeenFramed = true
        }
        revision += 1
    }

    func orbit(by translation: CGSize) {
        change { $0.orbit(by: translation) }
    }

    func pan(by translation: CGSize) {
        let viewport = viewport
        change { $0.pan(by: translation, in: viewport) }
    }

    func zoom(by factor: CGFloat) {
        change { $0.zoom(by: factor) }
    }

    func advance(by seconds: Double) {
        guard var current = flight else { return }
        current.elapsed = min(current.elapsed + seconds, Self.flightDuration)
        let linear = Float(current.elapsed / Self.flightDuration)
        let destination = OrbitCamera.framing(current.to, of: box, in: viewport)
        camera = current.from.blended(to: destination, t: linear * linear * (3 - 2 * linear))
        flight = current.elapsed < Self.flightDuration ? current : nil
        revision += 1
    }

    /// A gesture takes over from any flight in progress.
    private func change(_ edit: (inout OrbitCamera) -> Void) {
        flight = nil
        edit(&camera)
        revision += 1
    }
}
