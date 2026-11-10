import simd

/// Where one rigid part is: its local origin in world coordinates, in millimetres, and the rotation that takes
/// its local axes to the world's.
///
/// The world frame is the sword's, and each part's local frame is described in ``Dimensions``.
public struct PartPose: Sendable, Equatable {
    public var position: SIMD3<Double>
    public var orientation: simd_quatd

    public init(position: SIMD3<Double>, orientation: simd_quatd) {
        self.position = position
        self.orientation = orientation
    }

    /// A point given in the part's local frame, in world coordinates.
    public func worldPoint(_ local: SIMD3<Double>) -> SIMD3<Double> {
        position + orientation.act(local)
    }

    /// A direction given in the part's local frame, in world coordinates.
    public func worldDirection(_ local: SIMD3<Double>) -> SIMD3<Double> {
        orientation.act(local)
    }
}

/// Where every moving part of the toy is. The sword does not move.
///
/// This is all a drawing needs, and it is what the simulation produces.
public struct ToyPose: Sendable, Equatable {
    /// Nine poses, ring 1 first.
    public var rings: [PartPose]
    /// Nine poses, the rod of ring 1 first.
    public var rods: [PartPose]
    public var bar: PartPose

    public init(rings: [PartPose], rods: [PartPose], bar: PartPose) {
        precondition(rings.count == 9 && rods.count == 9, "the toy has nine rings and nine rods")
        self.rings = rings
        self.rods = rods
        self.bar = bar
    }

    public func ring(_ number: Int) -> PartPose { rings[number - 1] }
    public func rod(_ number: Int) -> PartPose { rods[number - 1] }
}
