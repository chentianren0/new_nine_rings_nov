import RealityKit

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

/// The toy's materials: bright polished steel for the wire, a softer satin steel for the bar, varnished wood
/// for the beads, and the shadow's veil.
@MainActor
enum ToyMaterials {
    static var wire: PhysicallyBasedMaterial {
        metal(white: 0.94, roughness: 0.16)
    }

    static var bar: PhysicallyBasedMaterial {
        metal(white: 0.76, roughness: 0.36)
    }

    static var wood: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: PlatformColor(red: 0.50, green: 0.27, blue: 0.12, alpha: 1))
        material.roughness = 0.45
        material.metallic = 0.0
        material.clearcoat = 0.6
        material.clearcoatRoughness = 0.25
        return material
    }

    /// Black, as opaque as `coverage` says, at most a light veil.
    static func shadow(coverage: TextureResource) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: PlatformColor(white: 0, alpha: 1))
        material.blending = .transparent(opacity: .init(scale: 0.22, texture: .init(coverage)))
        return material
    }

    private static func metal(white: CGFloat, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: PlatformColor(white: white, alpha: 1))
        material.metallic = 1.0
        material.roughness = .init(floatLiteral: roughness)
        return material
    }
}
