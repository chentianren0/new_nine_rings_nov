import CoreGraphics
import Foundation
import RealityKit

/// The light around the toy, generated in code: a soft photo studio for the steel to reflect, and a soft
/// shadow on an invisible floor beneath the toy.
@MainActor
enum Studio {
    /// An entity that lights whatever receives from it. Everything that should look lit by the studio gets an
    /// `ImageBasedLightReceiverComponent` pointing here.
    static func light() async throws -> Entity {
        let environment = try await EnvironmentResource(equirectangular: environmentImage(), withName: "studio")
        let light = Entity()
        light.name = "studio light"
        light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.4))
        return light
    }

    /// A soft, elongated shadow lying flat under the toy, in the toy's frame. Its height is set with each pose.
    static func shadow() async throws -> ModelEntity {
        let texture = try await TextureResource(image: shadowImage(), withName: "shadow", options: .init(semantic: .color))
        let material = ToyMaterials.shadow(coverage: texture)
        // The floor plane covers the whole toy and a margin, so the shadow fades out before its edge.
        let size = SIMD2<Float>(360, 120)
        let plane = ModelEntity(mesh: .generatePlane(width: size.x, depth: size.y), materials: [material])
        plane.name = "shadow"
        plane.position = [shadowCenterX, 0, 0]
        return plane
    }

    /// The middle of the sword along its length, which the shadow is centred on.
    private static var shadowCenterX: Float { ToyBounds.sword.center.x }

    // MARK: Images

    /// A 2:1 latitude–longitude image of a bright studio: a broad soft box overhead, long strips to either
    /// side that draw clean lines along the wire, a softer one behind the camera, a light grey room and a
    /// darker floor. Values above 1 are brighter than white, so the highlights stay crisp.
    private static func environmentImage() -> CGImage {
        let width = 512, height = 256
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for row in 0..<height {
            // Latitude from +90° at the top row to −90° at the bottom.
            let latitude = Float.pi / 2 - (Float(row) + 0.5) / Float(height) * .pi
            for column in 0..<width {
                let longitude = (Float(column) + 0.5) / Float(width) * 2 * .pi
                let direction = SIMD3<Float>(cos(latitude) * sin(longitude), sin(latitude), cos(latitude) * cos(longitude))
                let value = studioRadiance(direction)
                let index = (row * width + column) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value * 1.02
            }
        }
        return image(from: pixels, width: width, height: height, components: 4, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
    }

    /// How bright the studio is in one direction (y is up).
    private static func studioRadiance(_ direction: SIMD3<Float>) -> Float {
        let up = direction.y
        // The room: dim grey walls, darker toward the floor, so the steel has something dark to show its shape.
        var value = up < 0 ? 0.03 + 0.12 * (1 + up) * (1 + up) : 0.12 + 0.18 * up
        // A broad soft box overhead.
        value += 4.5 * smoothBox(up, from: 0.82, softness: 0.08)
        // Two long upright strips, to the left and right of the default view, that draw lines along the wire.
        for side: Float in [-1, 1] {
            let across = abs(direction.x - side * 0.96)
            value += 4 * smoothBox(-across, from: -0.12, softness: 0.05) * smoothBox(-abs(up - 0.2), from: -0.55, softness: 0.15)
        }
        // A wide, softer panel behind the camera, and a low one opposite it that lights the undersides.
        value += 1.4 * smoothBox(direction.z, from: 0.88, softness: 0.06) * smoothBox(-abs(up - 0.1), from: -0.3, softness: 0.12)
        value += 0.8 * smoothBox(-direction.z, from: 0.9, softness: 0.06) * smoothBox(-abs(up + 0.1), from: -0.25, softness: 0.1)
        return value
    }

    /// 0 below `edge`, 1 above `edge + softness`, smooth in between.
    private static func smoothBox(_ value: Float, from edge: Float, softness: Float) -> Float {
        let t = min(max((value - edge) / softness, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The shadow's coverage as a grey image: an elongated blur, denser under the rings and rods than under the
    /// grip, white where the shadow is darkest.
    private static func shadowImage() -> CGImage {
        let width = 360, height = 120
        var pixels = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            let z = (Float(row) + 0.5) / Float(height) * 120 - 60
            for column in 0..<width {
                // x in the toy's frame, millimetres.
                let x = (Float(column) + 0.5) / Float(width) * 360 - 180 + shadowCenterX
                let body = falloff(x, from: 0, to: 150, softness: 30) * falloff(z, from: -14, to: 14, softness: 22)
                let grip = 0.35 * falloff(x, from: 150, to: 250, softness: 25) * falloff(z, from: -8, to: 8, softness: 14)
                pixels[row * width + column] = min(body + grip, 1)
            }
        }
        return image(from: pixels, width: width, height: height, components: 1, colorSpace: CGColorSpace(name: CGColorSpace.linearGray)!)
    }

    /// 1 between `start` and `end`, fading smoothly to 0 over `softness` beyond either end.
    private static func falloff(_ value: Float, from start: Float, to end: Float, softness: Float) -> Float {
        let outside = max(start - value, value - end, 0) / softness
        return exp(-outside * outside * 2.5)
    }

    private static func image(from pixels: [Float], width: Int, height: Int, components: Int, colorSpace: CGColorSpace) -> CGImage {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(pixels.count * 4)
        for pixel in pixels {
            let bits = pixel.bitPattern
            for shift in stride(from: 0, to: 32, by: 8) {
                bytes.append(UInt8(truncatingIfNeeded: bits >> shift))
            }
        }
        let data = Data(bytes)
        let alpha: CGImageAlphaInfo = components == 4 ? .noneSkipLast : .none
        let info = CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return unsafe CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 32 * components,
            bytesPerRow: width * components * 4, space: colorSpace, bitmapInfo: info,
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }
}
