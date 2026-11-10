import RealityKit
import simd

/// Collects triangles for one mesh part, in millimetres, and turns them into a `MeshDescriptor`.
///
/// Every shape the toy needs is a tube swept along a path, a torus, a sphere or a flat face, so these few
/// primitives are all there is.
struct MeshBuilder {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var indices: [UInt32] = []

    func descriptor(named name: String, material: UInt32 = 0) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .allFaces(material)
        return descriptor
    }

    @discardableResult
    mutating func addVertex(_ position: SIMD3<Float>, normal: SIMD3<Float>) -> UInt32 {
        positions.append(position)
        normals.append(normal)
        return UInt32(positions.count - 1)
    }

    /// Adds a triangle wound so that its front faces `facing`.
    mutating func addTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32, facing: SIMD3<Float>) {
        let pa = positions[Int(a)], pb = positions[Int(b)], pc = positions[Int(c)]
        if simd_dot(simd_cross(pb - pa, pc - pa), facing) >= 0 {
            indices += [a, b, c]
        } else {
            indices += [a, c, b]
        }
    }

    /// Adds the quad `a b c d`, given in order around its edge, as two triangles facing `facing`.
    mutating func addQuad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, facing: SIMD3<Float>) {
        addTriangle(a, b, c, facing: facing)
        addTriangle(a, c, d, facing: facing)
    }

    /// A round tube of `radius` along an open path, with flat ends.
    ///
    /// The cross-section is carried along the path without twisting, so a path that bends in any direction
    /// keeps an even surface. Bends should already be smooth: the path is followed point to point.
    mutating func addTube(along path: [SIMD3<Float>], radius: Float, sides: Int) {
        precondition(path.count >= 2, "a tube needs two points")
        let tangents = path.indices.map { index -> SIMD3<Float> in
            let previous = path[max(index - 1, 0)]
            let next = path[min(index + 1, path.count - 1)]
            if index == 0 || index == path.count - 1 {
                return simd_normalize(next - previous)
            }
            return simd_normalize(simd_normalize(next - path[index]) + simd_normalize(path[index] - previous))
        }

        var normal = Self.perpendicular(to: tangents[0])
        var rings: [UInt32] = []
        for (point, tangent) in zip(path, tangents) {
            normal = simd_normalize(normal - tangent * simd_dot(normal, tangent))
            let binormal = simd_cross(tangent, normal)
            rings.append(UInt32(positions.count))
            for side in 0..<sides {
                let angle = Float(side) / Float(sides) * 2 * .pi
                let outward = normal * cos(angle) + binormal * sin(angle)
                addVertex(point + outward * radius, normal: outward)
            }
        }

        for ring in 0..<(path.count - 1) {
            for side in 0..<sides {
                let next = (side + 1) % sides
                let a = rings[ring] + UInt32(side), b = rings[ring] + UInt32(next)
                let c = rings[ring + 1] + UInt32(next), d = rings[ring + 1] + UInt32(side)
                addQuad(a, b, c, d, facing: normals[Int(a)] + normals[Int(c)])
            }
        }

        addCap(at: path[0], facing: -tangents[0], firstVertex: rings[0], sides: sides)
        addCap(at: path[path.count - 1], facing: tangents[tangents.count - 1], firstVertex: rings[rings.count - 1], sides: sides)
    }

    /// A torus in the local x–y plane, centred on the origin: `radius` to the centreline, `tubeRadius` thick.
    mutating func addTorus(radius: Float, tubeRadius: Float, segments: Int, sides: Int, center: SIMD3<Float> = .zero) {
        let first = UInt32(positions.count)
        for segment in 0..<segments {
            let around = Float(segment) / Float(segments) * 2 * .pi
            let radial = SIMD3<Float>(cos(around), sin(around), 0)
            for side in 0..<sides {
                let angle = Float(side) / Float(sides) * 2 * .pi
                let outward = radial * cos(angle) + SIMD3(0, 0, sin(angle))
                addVertex(center + radial * radius + outward * tubeRadius, normal: outward)
            }
        }
        for segment in 0..<segments {
            let nextSegment = (segment + 1) % segments
            for side in 0..<sides {
                let nextSide = (side + 1) % sides
                let a = first + UInt32(segment * sides + side)
                let b = first + UInt32(segment * sides + nextSide)
                let c = first + UInt32(nextSegment * sides + nextSide)
                let d = first + UInt32(nextSegment * sides + side)
                addQuad(a, b, c, d, facing: normals[Int(a)] + normals[Int(c)])
            }
        }
    }

    /// A sphere made of `rings` bands of latitude and `segments` of longitude.
    mutating func addSphere(center: SIMD3<Float>, radius: Float, rings: Int, segments: Int) {
        let first = UInt32(positions.count)
        for ring in 0...rings {
            let latitude = Float(ring) / Float(rings) * .pi
            for segment in 0...segments {
                let longitude = Float(segment) / Float(segments) * 2 * .pi
                let outward = SIMD3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
                addVertex(center + outward * radius, normal: outward)
            }
        }
        let row = UInt32(segments + 1)
        for ring in 0..<UInt32(rings) {
            for segment in 0..<UInt32(segments) {
                let a = first + ring * row + segment, b = a + 1
                let d = a + row, c = d + 1
                let facing = normals[Int(a)] + normals[Int(c)]
                if ring > 0 { addTriangle(a, b, c, facing: facing) }
                if ring < UInt32(rings) - 1 { addTriangle(a, c, d, facing: facing) }
            }
        }
    }

    private mutating func addCap(at center: SIMD3<Float>, facing: SIMD3<Float>, firstVertex: UInt32, sides: Int) {
        let middle = addVertex(center, normal: facing)
        let rim = (0..<sides).map { addVertex(positions[Int(firstVertex) + $0], normal: facing) }
        for side in 0..<sides {
            addTriangle(middle, rim[side], rim[(side + 1) % sides], facing: facing)
        }
    }

    private static func perpendicular(to direction: SIMD3<Float>) -> SIMD3<Float> {
        let axis: SIMD3<Float> = abs(direction.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        return simd_normalize(simd_cross(direction, axis))
    }
}
