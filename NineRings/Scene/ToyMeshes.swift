import RealityKit
import Toy

/// The meshes of the toy, built once from `Dimensions`, each in the local frame its part documents.
///
/// All rings share one mesh and all rods another; a rod's mesh has two parts, the steel eye and shaft
/// (material 0) and the wooden bead (material 1).
@MainActor
struct ToyMeshes {
    let sword: MeshResource
    let ring: MeshResource
    let rod: MeshResource
    let bar: MeshResource

    init() async throws {
        var sword = MeshBuilder()
        sword.addTube(along: SwordPath.points(), radius: Float(Dimensions.Sword.wireRadius), sides: 20)
        self.sword = try await MeshResource(from: [sword.descriptor(named: "sword")])

        var ring = MeshBuilder()
        ring.addTorus(radius: Float(Dimensions.Ring.radius), tubeRadius: Float(Dimensions.Ring.wireRadius), segments: 120, sides: 20)
        self.ring = try await MeshResource(from: [ring.descriptor(named: "ring")])

        typealias Rod = Dimensions.Rod
        var steel = MeshBuilder()
        steel.addTorus(radius: Float(Rod.eyeRadius), tubeRadius: Float(Rod.wireRadius), segments: 48, sides: 14)
        steel.addTube(along: [[0, Float(Rod.shaftTopY), 0], [0, Float(Rod.beadCenterY), 0]], radius: Float(Rod.wireRadius), sides: 14)
        var bead = MeshBuilder()
        bead.addSphere(center: [0, Float(Rod.beadCenterY), 0], radius: Float(Rod.beadRadius), rings: 24, segments: 36)
        self.rod = try await MeshResource(from: [steel.descriptor(named: "rod", material: 0), bead.descriptor(named: "bead", material: 1)])

        self.bar = try await MeshResource(from: [BarMesh.descriptor()])
    }
}
