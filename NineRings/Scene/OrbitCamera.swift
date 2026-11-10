import CoreGraphics
import RealityKit
import simd

/// The three views a person can jump to.
enum CameraPreset: String, CaseIterable, Identifiable {
    /// From the side, the tip on the left.
    case side
    /// From above, the tip on the left.
    case top
    /// Looking at the tip end on.
    case tip

    var id: Self { self }

    var title: String {
        switch self {
        case .side: "Side"
        case .top: "Top"
        case .tip: "Tip"
        }
    }

    var angles: (yaw: Float, pitch: Float) {
        switch self {
        case .side: (0, 0)
        case .top: (0, .pi / 2)
        case .tip: (-.pi / 2, 0)
        }
    }
}

/// The part of a view the toy is framed in, in points: its size, and how much of its top and bottom is
/// covered by bars and controls.
struct Viewport: Equatable {
    var size: CGSize
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    var isEmpty: Bool { size.width < 1 || size.height <= topInset + bottomInset + 1 }
}

/// A camera that circles a target point: everything about it is in millimetres in the sword's frame.
///
/// Yaw turns it around the vertical, with yaw 0 looking from +z so that the tip is on the left; pitch raises it,
/// up to looking straight down.
struct OrbitCamera: Equatable {
    var target: SIMD3<Float>
    var yaw: Float
    var pitch: Float
    var distance: Float

    /// The vertical field of view. A long lens keeps the toy's proportions, as a product photo does.
    static let fieldOfView: Float = 28 * .pi / 180
    /// Clipping planes, in millimetres. The near plane is far closer than the closest a person can zoom.
    static let near: Float = 0.5
    static let far: Float = 20_000
    private static let closest: Float = 20
    private static let pitchRange: ClosedRange<Float> = (-80 * .pi / 180)...(.pi / 2)

    var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
    }

    var position: SIMD3<Float> {
        target + rotation.act([0, 0, distance])
    }

    /// The camera's transform in RealityKit's metres.
    var transform: Transform {
        Transform(scale: .one, rotation: rotation, translation: ToyScene.metres(position))
    }

    static func component() -> PerspectiveCameraComponent {
        PerspectiveCameraComponent(
            near: near * ToyScene.metresPerMillimetre,
            far: far * ToyScene.metresPerMillimetre,
            fieldOfViewInDegrees: fieldOfView * 180 / .pi
        )
    }

    // MARK: Framing

    /// The camera for `preset`, placed so that `box` fits the uncovered part of `viewport`, centred in it.
    static func framing(_ preset: CameraPreset, of box: ToyBounds, in viewport: Viewport) -> OrbitCamera {
        framing(yaw: preset.angles.yaw, pitch: preset.angles.pitch, of: box, in: viewport)
    }

    /// The camera looking from `yaw` and `pitch`, placed so that `box` fits the uncovered part of `viewport`.
    static func framing(yaw: Float, pitch: Float, of box: ToyBounds, in viewport: Viewport) -> OrbitCamera {
        var camera = OrbitCamera(target: box.center, yaw: yaw, pitch: pitch, distance: 500)
        guard !viewport.isEmpty else { return camera }
        camera.distance = camera.fittingDistance(of: box, in: viewport)
        // Move the target so the toy sits in the middle of the uncovered part.
        let shift = Float((viewport.bottomInset - viewport.topInset) / viewport.size.height) * camera.distance * tan(fieldOfView / 2)
        camera.target -= camera.rotation.act([0, 1, 0]) * shift
        return camera
    }

    /// How far away the camera must be, looking the way it looks, for `box` to fit in `viewport`.
    func fittingDistance(of box: ToyBounds, in viewport: Viewport) -> Float {
        let tangent = tan(Self.fieldOfView / 2)
        let height = Float(viewport.size.height)
        let vertical = tangent * (height - Float(viewport.topInset + viewport.bottomInset)) / height
        let horizontal = tangent * Float(viewport.size.width) / height
        let right = rotation.act([1, 0, 0]), up = rotation.act([0, 1, 0]), back = rotation.act([0, 0, 1])
        let margin: Float = 1.08
        var distance: Float = 0
        for corner in 0..<8 {
            let pick = SIMD3<Float>(Float(corner & 1), Float((corner >> 1) & 1), Float((corner >> 2) & 1))
            let offset = box.size * (pick - 0.5)
            let depth = simd_dot(offset, back)
            distance = max(distance,
                           abs(simd_dot(offset, right)) * margin / horizontal + depth,
                           abs(simd_dot(offset, up)) * margin / vertical + depth)
        }
        return distance
    }

    /// Keeps `box` the same size relative to the view when the view changes size.
    mutating func refit(_ box: ToyBounds, from old: Viewport, to new: Viewport) {
        guard !old.isEmpty, !new.isEmpty else { return }
        distance *= fittingDistance(of: box, in: new) / fittingDistance(of: box, in: old)
    }

    // MARK: Gestures

    /// Turns the camera around the target by a drag of `translation` points.
    mutating func orbit(by translation: CGSize) {
        let radiansPerPoint: Float = 0.008
        yaw -= Float(translation.width) * radiansPerPoint
        pitch = min(max(pitch + Float(translation.height) * radiansPerPoint, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
    }

    /// Slides the camera and its target so that the toy follows a drag of `translation` points.
    mutating func pan(by translation: CGSize, in viewport: Viewport) {
        guard !viewport.isEmpty else { return }
        let millimetresPerPoint = 2 * distance * tan(Self.fieldOfView / 2) / Float(viewport.size.height)
        let right = rotation.act([1, 0, 0]), up = rotation.act([0, 1, 0])
        target += (-right * Float(translation.width) + up * Float(translation.height)) * millimetresPerPoint
    }

    /// Moves the camera toward the target, by `factor` (more than 1 to come closer).
    mutating func zoom(by factor: CGFloat) {
        guard factor > 0 else { return }
        distance = min(max(distance / Float(factor), Self.closest), 5_000)
    }

    // MARK: Blending

    /// The camera a fraction `t` of the way from this one to `other`, turning the short way round.
    func blended(to other: OrbitCamera, t: Float) -> OrbitCamera {
        var turn = (other.yaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
        return OrbitCamera(
            target: simd_mix(target, other.target, SIMD3(repeating: t)),
            yaw: yaw + turn * t,
            pitch: pitch + (other.pitch - pitch) * t,
            distance: distance * pow(other.distance / distance, t)
        )
    }
}
