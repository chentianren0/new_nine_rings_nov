import RealityKit
import Toy
import simd

/// The bar: a flat strip with rounded ends and nine round holes, in its local frame (x along its length,
/// y its normal, z across it), centred on the origin.
///
/// The strip is cut into nine cells, one around each hole, split halfway between neighbouring holes; the end
/// cells take the rounded ends. Each cell is convex, so its face is filled by joining the hole's edge to the
/// cell's edge along rays from the hole's centre.
enum BarMesh {
    static func descriptor() -> MeshDescriptor {
        var mesh = MeshBuilder()
        for ring in 1...9 {
            addCell(around: ring, to: &mesh)
        }
        addOuterWall(to: &mesh)
        return mesh.descriptor(named: "bar")
    }

    private typealias Bar = Dimensions.Bar
    private static let halfThickness = Float(Bar.thickness / 2)
    private static let halfWidth = Float(Bar.width / 2)
    private static let endCenter = Float(Bar.length / 2 - Bar.width / 2)
    private static let holeRadius = Float(Bar.holeRadius)

    /// The cell's outline in the bar's x–z plane, as (x, z) points in order around it.
    private static func outline(of ring: Int) -> [SIMD2<Float>] {
        let hole = Float(Bar.holeX(ring)), half = Float(Bar.holePitch / 2)
        let left = ring == 1 ? -endCenter : hole - half
        let right = ring == 9 ? endCenter : hole + half
        var points: [SIMD2<Float>] = [[right, -halfWidth]]
        if ring == 9 { points += arc(center: endCenter, from: -.pi / 2, to: .pi / 2) }
        points.append([right, halfWidth])
        points.append([left, halfWidth])
        if ring == 1 { points += arc(center: -endCenter, from: .pi / 2, to: 3 * .pi / 2) }
        points.append([left, -halfWidth])
        return points
    }

    private static func arc(center: Float, from start: Float, to end: Float, steps: Int = 24) -> [SIMD2<Float>] {
        (1..<steps).map { step in
            let angle = start + (end - start) * Float(step) / Float(steps)
            return [center + halfWidth * cos(angle), halfWidth * sin(angle)]
        }
    }

    private static func addCell(around ring: Int, to mesh: inout MeshBuilder) {
        let center = SIMD2<Float>(Float(Bar.holeX(ring)), 0)
        let outline = outline(of: ring)

        // Rays every few degrees, and through every corner of the outline so no corner is cut off.
        var angles = (0..<40).map { Float($0) / 40 * 2 * .pi }
        angles += outline.map { point in
            let angle = atan2(point.y - center.y, point.x - center.x)
            return angle < 0 ? angle + 2 * .pi : angle
        }
        angles.sort()
        angles = angles.enumerated().filter { index, angle in index == 0 || angle - angles[index - 1] > 1e-4 }.map(\.element)

        let directions = angles.map { SIMD2<Float>(cos($0), sin($0)) }
        let inner = directions.map { center + $0 * holeRadius }
        let outer = directions.map { center + $0 * distanceToOutline(outline, from: center, along: $0) }

        for (y, up) in [(halfThickness, SIMD3<Float>(0, 1, 0)), (-halfThickness, SIMD3<Float>(0, -1, 0))] {
            let innerIndices = inner.map { mesh.addVertex([$0.x, y, $0.y], normal: up) }
            let outerIndices = outer.map { mesh.addVertex([$0.x, y, $0.y], normal: up) }
            for index in angles.indices {
                let next = (index + 1) % angles.count
                mesh.addQuad(innerIndices[index], outerIndices[index], outerIndices[next], innerIndices[next], facing: up)
            }
        }

        // The hole's wall, facing into the hole.
        let top = zip(inner, directions).map { mesh.addVertex([$0.x, halfThickness, $0.y], normal: [-$1.x, 0, -$1.y]) }
        let bottom = zip(inner, directions).map { mesh.addVertex([$0.x, -halfThickness, $0.y], normal: [-$1.x, 0, -$1.y]) }
        for index in angles.indices {
            let next = (index + 1) % angles.count
            let facing = -SIMD3(directions[index].x + directions[next].x, 0, directions[index].y + directions[next].y)
            mesh.addQuad(top[index], top[next], bottom[next], bottom[index], facing: facing)
        }
    }

    private static func distanceToOutline(_ outline: [SIMD2<Float>], from origin: SIMD2<Float>, along direction: SIMD2<Float>) -> Float {
        var nearest = Float.infinity
        for (index, start) in outline.enumerated() {
            let edge = outline[(index + 1) % outline.count] - start
            let denominator = direction.x * edge.y - direction.y * edge.x
            guard abs(denominator) > 1e-9 else { continue }
            let offset = start - origin
            let distance = (offset.x * edge.y - offset.y * edge.x) / denominator
            let along = (offset.x * direction.y - offset.y * direction.x) / denominator
            if distance > 0, along >= -1e-5, along <= 1 + 1e-5 {
                nearest = min(nearest, distance)
            }
        }
        return nearest
    }

    /// The outside edge: two straight sides and the two rounded ends.
    private static func addOuterWall(to mesh: inout MeshBuilder) {
        var points: [SIMD2<Float>] = []
        var outward: [SIMD2<Float>] = []
        for step in 0...48 {
            let angle = -Float.pi / 2 + Float.pi * Float(step) / 48
            outward.append([cos(angle), sin(angle)])
            points.append([endCenter, 0] + outward[outward.count - 1] * halfWidth)
        }
        for step in 0...48 {
            let angle = Float.pi / 2 + Float.pi * Float(step) / 48
            outward.append([cos(angle), sin(angle)])
            points.append([-endCenter, 0] + outward[outward.count - 1] * halfWidth)
        }
        let top = zip(points, outward).map { mesh.addVertex([$0.x, halfThickness, $0.y], normal: [$1.x, 0, $1.y]) }
        let bottom = zip(points, outward).map { mesh.addVertex([$0.x, -halfThickness, $0.y], normal: [$1.x, 0, $1.y]) }
        for index in points.indices {
            let next = (index + 1) % points.count
            let facing = SIMD3(outward[index].x + outward[next].x, 0, outward[index].y + outward[next].y)
            mesh.addQuad(top[index], top[next], bottom[next], bottom[index], facing: facing)
        }
    }
}
