import simd

/// One solid piece of a part: a core swept by a radius.
struct Piece: Sendable {
    enum Shape: Sendable {
        case point(PointCore)
        case segment(Segment)
        case circle(Circle)
        case polyline(Polyline)
        case stadium(Stadium)
    }

    var shape: Shape
    var radius: Double

    /// The same piece carried from a body's frame into the world.
    func placed(by body: Body) -> Piece {
        let move = body.worldPoint
        let turn = body.orientation.act
        let placed: Shape = switch shape {
        case .point(let point):
            .point(PointCore(position: move(point.position)))
        case .segment(let segment):
            .segment(Segment(start: move(segment.start), end: move(segment.end)))
        case .circle(let circle):
            .circle(Circle(center: move(circle.center), axisU: turn(circle.axisU), axisV: turn(circle.axisV), radius: circle.radius))
        case .polyline(let polyline):
            .polyline(Polyline(points: polyline.points.map(move)))
        case .stadium(let stadium):
            .stadium(Stadium(
                center: move(stadium.center),
                lengthAxis: turn(stadium.lengthAxis),
                widthAxis: turn(stadium.widthAxis),
                halfLength: stadium.halfLength,
                radius: stadium.radius
            ))
        }
        return Piece(shape: placed, radius: radius)
    }

    /// A ball that holds the whole piece: its middle and its radius.
    var bounds: (center: Vector, radius: Double) {
        switch shape {
        case .point(let point):
            return (point.position, radius)
        case .segment(let segment):
            return ((segment.start + segment.end) / 2, simd_distance(segment.start, segment.end) / 2 + radius)
        case .circle(let circle):
            return (circle.center, circle.radius + radius)
        case .polyline(let polyline):
            let middle = polyline.points.reduce(Vector.zero, +) / Double(polyline.points.count)
            let farthest = polyline.points.map { simd_distance($0, middle) }.max() ?? 0
            return (middle, farthest + radius)
        case .stadium(let stadium):
            return (stadium.center, stadium.halfLength + stadium.radius + radius)
        }
    }

    /// Appends the places where the cores of two pieces come closer than `reach`, with `pointA` on `a`.
    static func approaches(_ a: Piece, _ b: Piece, within reach: Double, into approaches: inout [Approach]) {
        func direct(_ pointA: Vector, _ pointB: Vector) {
            if simd_distance(pointA, pointB) < reach {
                approaches.append(Approach(pointA: pointA, pointB: pointB))
            }
        }
        /// Searches along a curve of `b` and turns the result round, so that `pointA` stays on `a`.
        func searchFromB(_ curve: some CurveCore, _ core: some Core, samples: Int) {
            let first = approaches.count
            Approaches.find(curve, core, within: reach, samples: samples, into: &approaches)
            for index in first..<approaches.count {
                approaches[index] = Approach(pointA: approaches[index].pointB, pointB: approaches[index].pointA)
            }
        }
        func search(_ curve: some CurveCore, _ core: some Core, samples: Int) {
            Approaches.find(curve, core, within: reach, samples: samples, into: &approaches)
        }

        switch (a.shape, b.shape) {
        case (.point(let p), .point(let q)): direct(p.position, q.position)
        case (.point(let p), .segment(let core)): direct(p.position, core.nearestPoint(to: p.position))
        case (.point(let p), .circle(let core)): direct(p.position, core.nearestPoint(to: p.position))
        case (.point(let p), .polyline(let core)): direct(p.position, core.nearestPoint(to: p.position))
        case (.point(let p), .stadium(let core)): direct(p.position, core.nearestPoint(to: p.position))
        case (.segment(let core), .point(let p)): direct(core.nearestPoint(to: p.position), p.position)
        case (.circle(let core), .point(let p)): direct(core.nearestPoint(to: p.position), p.position)
        case (.polyline(let core), .point(let p)): direct(core.nearestPoint(to: p.position), p.position)
        case (.stadium(let core), .point(let p)): direct(core.nearestPoint(to: p.position), p.position)

        case (.segment(let s), .segment(let t)):
            let nearest = Approaches.nearest(s, t)
            direct(nearest.pointA, nearest.pointB)
        case (.segment(let s), .polyline(let core)): search(s, core, samples: wireSamples)
        case (.segment(let s), .stadium(let core)): search(s, core, samples: wireSamples)
        case (.polyline(let core), .segment(let s)): searchFromB(s, core, samples: wireSamples)
        case (.stadium(let core), .segment(let s)): searchFromB(s, core, samples: wireSamples)

        case (.circle(let c), .segment(let core)): search(c, core, samples: samples(for: c))
        case (.circle(let c), .polyline(let core)): search(c, core, samples: samples(for: c))
        case (.circle(let c), .stadium(let core)): search(c, core, samples: samples(for: c))
        case (.segment(let core), .circle(let c)): searchFromB(c, core, samples: samples(for: c))
        case (.polyline(let core), .circle(let c)): searchFromB(c, core, samples: samples(for: c))
        case (.stadium(let core), .circle(let c)): searchFromB(c, core, samples: samples(for: c))
        case (.circle(let c), .circle(let d)):
            // Walk the smaller circle: its samples lie closer together.
            if c.radius <= d.radius {
                search(c, d, samples: samples(for: c))
            } else {
                searchFromB(d, c, samples: samples(for: d))
            }

        // The sword's tip and the bar are too far apart on the toy to meet, and there is one of each.
        case (.polyline, .polyline), (.polyline, .stadium), (.stadium, .polyline), (.stadium, .stadium):
            break
        }
    }

    private static let wireSamples = 12

    /// A ring is walked in sixteen steps and an eye in twelve: about five and two millimetres of wire a step.
    private static func samples(for circle: Circle) -> Int {
        circle.radius > 8 ? 16 : 12
    }
}
