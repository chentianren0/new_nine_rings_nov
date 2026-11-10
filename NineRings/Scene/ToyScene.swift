import RealityKit
import Toy
import simd

/// The drawn toy: the fixed sword, the nineteen moving parts, the studio light and the shadow.
///
/// `root` is in RealityKit's metres. Everything of the toy hangs under one entity scaled from millimetres,
/// so poses, meshes and `Dimensions` are all used in millimetres as they are.
@MainActor
final class ToyScene {
    /// The one place where millimetres become RealityKit's metres.
    static let metresPerMillimetre: Float = 0.001

    let root = Entity()
    private let toy = Entity()
    private let rings: [ModelEntity]
    private let rods: [ModelEntity]
    private let bar: ModelEntity
    private let shadow: ModelEntity

    static func make() async throws -> ToyScene {
        let meshes = try await ToyMeshes()
        let light = try await Studio.light()
        let shadow = try await Studio.shadow()
        return ToyScene(meshes: meshes, light: light, shadow: shadow)
    }

    private init(meshes: ToyMeshes, light: Entity, shadow: ModelEntity) {
        let wire = ToyMaterials.wire
        rings = (1...9).map { number in
            let ring = ModelEntity(mesh: meshes.ring, materials: [wire])
            ring.name = "ring \(number)"
            return ring
        }
        rods = (1...9).map { number in
            let rod = ModelEntity(mesh: meshes.rod, materials: [wire, ToyMaterials.wood])
            rod.name = "rod \(number)"
            return rod
        }
        bar = ModelEntity(mesh: meshes.bar, materials: [ToyMaterials.bar])
        bar.name = "bar"
        self.shadow = shadow
        let sword = ModelEntity(mesh: meshes.sword, materials: [wire])
        sword.name = "sword"

        toy.name = "toy"
        toy.scale = SIMD3(repeating: Self.metresPerMillimetre)
        for part in [sword, bar] + rings + rods {
            part.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            toy.addChild(part)
        }
        toy.addChild(shadow)
        root.addChild(light)
        root.addChild(toy)
    }

    /// Places every moving part. This sets transforms only, so it is cheap enough to call every frame.
    func apply(_ pose: ToyPose) {
        for index in 0..<9 {
            place(rings[index], at: pose.rings[index])
            place(rods[index], at: pose.rods[index])
        }
        place(bar, at: pose.bar)
        // The shadow lies on an imagined table just under the lowest part.
        shadow.position.y = ToyBounds.lowestPoint(of: pose) - 6
    }

    private func place(_ entity: Entity, at pose: PartPose) {
        entity.transform = Transform(
            scale: .one,
            rotation: simd_quatf(vector: SIMD4<Float>(pose.orientation.vector)),
            translation: SIMD3<Float>(pose.position)
        )
    }

    /// A point given in millimetres in the sword's frame, in metres in `root`'s frame.
    static func metres(_ millimetres: SIMD3<Float>) -> SIMD3<Float> {
        millimetres * metresPerMillimetre
    }
}
