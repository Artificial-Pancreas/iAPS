import Foundation

enum VerticalSide {
    case above
    case below
}

struct Candidate { let p: CGPoint
    let d: CGFloat
    let rank: Int }

struct Pick { let p: CGPoint
    let d2: CGFloat
    let rank: Int }

extension Array where Element == DotInfo {
    /// Place `desired` as the globally closest collision-free rect near `desired`,
    /// ranking by weighted distance where vertical moves cost more.
    /// - Uses expanded obstacles to compute exact same-row gaps (no L/R bias).
    /// - Also tries roofline slabs (above/below) and direct-over each obstacle.
    func placeLabelCenter(
        desiredRect desired: CGRect,
        verticalSide: VerticalSide,
        maxDistance: CGFloat,
        verticalClearanceEps: CGFloat = 0.5,
        verticalWeight: CGFloat = 2.0
    ) -> CGRect? {
        // --- geometry
        let w = desired.width, h = desired.height
        let halfW = w * 0.5, halfH = h * 0.5
        let cx = desired.midX, cy = desired.midY
        let maxD2 = maxDistance * maxDistance

        @inline(__always) func euclidD2(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let dx = x - cx, dy = y - cy
            return dx * dx + dy * dy
        }
        @inline(__always) func cost(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let dx = x - cx, dy = y - cy
            let vy = verticalWeight * dy
            return dx * dx + vy * vy
        }
        @inline(__always) func rectAt(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: x - halfW, y: y - halfH, width: w, height: h)
        }

        // Obstacles as rendered (dot + optional text)
        var obstacles: [CGRect] = []
        obstacles.reserveCapacity(Swift.max(1, count * 2))
        for d in self {
            obstacles.append(d.rect)
            if let t = d.textRect { obstacles.append(t) }
        }

        @inline(__always) func intersectsAny(_ r: CGRect) -> Bool {
            for o in obstacles where o.intersects(r) { return true }
            return false
        }

        // If desired already OK, keep it.
        if !intersectsAny(desired) { return desired }

        // Prefilter obstacles to a search box around the Euclidean circle (speeds things up).
        if !obstacles.isEmpty {
            let searchBox = CGRect(
                x: cx - maxDistance - halfW,
                y: cy - maxDistance - halfH,
                width: 2 * (maxDistance + halfW),
                height: 2 * (maxDistance + halfH)
            )
            obstacles.removeAll { !searchBox.intersects($0) }
        }

        // Expanded obstacles for **centers** (Minkowski by label half-size)
        var expanded: [CGRect] = []
        expanded.reserveCapacity(obstacles.count)
        for o in obstacles {
            expanded.append(CGRect(
                x: o.minX - halfW,
                y: o.minY - halfH,
                width: o.width + w,
                height: o.height + h
            ))
        }

        // --- candidate accumulator (weighted cost, tie-break Euclidean)
        var bestRect: CGRect?
        var bestCost = CGFloat.greatestFiniteMagnitude
        var bestEuclid = CGFloat.greatestFiniteMagnitude

        @inline(__always) func considerXY(_ x: CGFloat, _ y: CGFloat) {
            let e2 = euclidD2(x, y)
            if e2 > maxD2 { return }
            let r = rectAt(x, y)
            if intersectsAny(r) { return } // should be false for center-from-expanded, but keep as guard
            let c = cost(x, y)
            if c < bestCost - 1E-6 || (Swift.abs(c - bestCost) <= 1E-6 && e2 < bestEuclid) {
                bestCost = c
                bestEuclid = e2
                bestRect = r
            }
        }

        // ---------- A) SAME ROW (y == cy) via expanded obstacles ----------
        // Blocks for center-X are simply [e.minX, e.maxX] for all expanded e that cover cy.
        func sameRowAllowedIntervals() -> [(CGFloat, CGFloat)] {
            var blocks: [(CGFloat, CGFloat)] = []
            for e in expanded where e.minY <= cy && cy <= e.maxY {
                blocks.append((e.minX, e.maxX))
            }
            if blocks.isEmpty { return [(-CGFloat.infinity, CGFloat.infinity)] }

            blocks.sort { $0.0 < $1.0 }
            var merged: [(CGFloat, CGFloat)] = []
            var cur = blocks[0]
            for i in 1 ..< blocks.count {
                let b = blocks[i]
                if b.0 <= cur.1 { cur.1 = Swift.max(cur.1, b.1) } else { merged.append(cur)
                    cur = b }
            }
            merged.append(cur)

            // Complement → allowed intervals
            var allowed: [(CGFloat, CGFloat)] = []
            var cursor = -CGFloat.infinity
            for m in merged {
                if m.0 > cursor { allowed.append((cursor, m.0)) }
                cursor = Swift.max(cursor, m.1)
            }
            if cursor < CGFloat.infinity { allowed.append((cursor, CGFloat.infinity)) }
            return allowed
        }

        // Evaluate ALL same-row gaps: nearest x in each gap (this removes any L/R bias)
        do {
            let intervals = sameRowAllowedIntervals()
            for (a, b) in intervals {
                let x = Swift.min(Swift.max(cx, a), b)
                if x.isFinite { considerXY(x, cy) }
            }
        }

        // ---------- B) ROOFLINE (above/below), evaluated by x-slabs ----------
        // Collect vertical edges of expanded obstacles within the horizontal search band.
        let xMin = cx - maxDistance, xMax = cx + maxDistance
        var breaks: [CGFloat] = [xMin, cx, xMax]
        breaks.reserveCapacity(Swift.max(3, 2 * expanded.count + 3))
        for e in expanded {
            if e.minX >= xMin - 1E-6, e.minX <= xMax + 1E-6 { breaks.append(e.minX) }
            if e.maxX >= xMin - 1E-6, e.maxX <= xMax + 1E-6 { breaks.append(e.maxX) }
        }
        breaks.sort()
        var xs: [CGFloat] = []
        xs.reserveCapacity(breaks.count)
        var lastX: CGFloat?
        for v in breaks {
            if let L = lastX, Swift.abs(v - L) < 0.25 { continue }
            xs.append(v)
            lastX = v
        }

        func roofY(in slabA: CGFloat, _ slabB: CGFloat) -> CGFloat? {
            var yVal: CGFloat?
            for e in expanded where !(e.maxX <= slabA || e.minX >= slabB) {
                switch verticalSide {
                case .above:
                    let y = e.minY - verticalClearanceEps // strictly above roof
                    yVal = (yVal == nil) ? y : Swift.min(yVal!, y)
                case .below:
                    let y = e.maxY + verticalClearanceEps // strictly below floor
                    yVal = (yVal == nil) ? y : Swift.max(yVal!, y)
                }
            }
            return yVal
        }

        if xs.count >= 2 {
            for i in 0 ..< (xs.count - 1) {
                let a = xs[i], b = xs[i + 1]
                if b <= a { continue }
                guard var y = roofY(in: a, b) else { continue }
                // respect direction relative to original row
                if verticalSide == .above { y = Swift.min(y, cy) } else { y = Swift.max(y, cy) }
                let x = Swift.min(Swift.max(cx, a), b) // nearest x in this slab
                considerXY(x, y)
            }
        }

        // ---------- C) DIRECT-OVER each expanded obstacle (good in tight clusters) ----------
        for e in expanded {
            let y = (verticalSide == .above)
                ? Swift.min(e.minY - verticalClearanceEps, cy)
                : Swift.max(e.maxY + verticalClearanceEps, cy)
            let xMid = Swift.min(Swift.max(cx, e.minX), e.maxX)
            considerXY(xMid, y)
            considerXY(e.minX, y)
            considerXY(e.maxX, y)
        }

        return bestRect
    }
}
