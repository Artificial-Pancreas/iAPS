import Foundation

enum VerticalSide {
    case above
    case below
    case both
}

struct Candidate {
    let p: CGPoint
    let d: CGFloat
    let rank: Int
}

struct Pick {
    let p: CGPoint
    let d2: CGFloat
    let rank: Int
}

extension Array where Element == CGRect {
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
        if isEmpty { return desired }

        // Geometry
        let w = desired.width, h = desired.height
        let halfW = w * 0.5, halfH = h * 0.5
        let cx = desired.midX, cy = desired.midY
        let maxD2 = maxDistance * maxDistance

        @inline(__always) func rectAt(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: x - halfW, y: y - halfH, width: w, height: h)
        }

        // Expand obstacles by label half-size (Minkowski sum) so we only test a point-in-rect for the center.
        var expanded: [CGRect] = map { o in
            CGRect(x: o.minX - halfW, y: o.minY - halfH, width: o.width + w, height: o.height + h)
        }

        // Optional: prefilter by search box to reduce work
        let searchBox = CGRect(
            x: cx - maxDistance - halfW,
            y: cy - maxDistance - halfH,
            width: 2 * (maxDistance + halfW),
            height: 2 * (maxDistance + halfH)
        )

        // Since original array is sorted by minX, we can binary search lower bound and slice
        var lo = 0, hi = expanded.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if expanded[mid].minX < searchBox.minX {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var filtered: [CGRect] = []
        filtered.reserveCapacity(expanded.count - lo)
        var i = lo
        while i < expanded.count {
            let e = expanded[i]
            if e.minX > searchBox.maxX { break }
            if e.maxX >= searchBox.minX, e.intersects(searchBox) {
                filtered.append(e)
            }
            i += 1
        }
        expanded = filtered

        @inline(__always) func inAny(_ x: CGFloat, _ y: CGFloat) -> Bool {
            let p = CGPoint(x: x, y: y)
            for e in expanded where e.contains(p) { return true }
            return false
        }

        // Quick accept: if desired center is not inside any expanded obstacle, we keep it.
        if !inAny(cx, cy) { return desired }

        // Scoring (vertical-weighted), tie-break Euclidean
        var bestRect: CGRect?
        var bestCost = CGFloat.greatestFiniteMagnitude
        var bestEuclid = CGFloat.greatestFiniteMagnitude

        @inline(__always) func consider(_ x: CGFloat, _ y: CGFloat) {
            let dx = x - cx, dy = y - cy
            let e2 = dx * dx + dy * dy
            if e2 > maxD2 { return }
            if inAny(x, y) { return }
            let vy = verticalWeight * dy
            let c = dx * dx + vy * vy
            if c < bestCost - 1E-6 || (Swift.abs(c - bestCost) <= 1E-6 && e2 < bestEuclid) {
                bestCost = c
                bestEuclid = e2
                bestRect = rectAt(x, y)
            }
        }

        // A) SAME-ROW: merge overlapping x-blocks for obstacles covering cy, and emit single candidate per gap
        do {
            var blocks: [(CGFloat, CGFloat)] = []
            var curMin: CGFloat = 0
            var curMax: CGFloat = 0
            var hasCur = false

            for e in expanded where e.minY <= cy && cy <= e.maxY {
                if !hasCur {
                    curMin = e.minX
                    curMax = e.maxX
                    hasCur = true
                } else if e.minX <= curMax { // overlap/adjacent
                    if e.maxX > curMax { curMax = e.maxX }
                } else {
                    blocks.append((curMin, curMax))
                    curMin = e.minX
                    curMax = e.maxX
                }
            }
            if hasCur { blocks.append((curMin, curMax)) }

            if blocks.isEmpty {
                // Whole row free in this band
                consider(cx, cy)
            } else {
                // Complement to allowed intervals, but only emit the closest x per interval
                var cursor = -CGFloat.infinity
                for (a, b) in blocks {
                    if a > cursor {
                        let left = cursor
                        let right = a
                        // Clamp desired x to [left, right]
                        let x = Swift.min(Swift.max(cx, left), right)
                        if x.isFinite { consider(x, cy) }
                    }
                    if b > cursor { cursor = b }
                }
                if cursor < CGFloat.infinity {
                    let x = Swift.max(cx, cursor)
                    if x.isFinite { consider(x, cy) }
                }
            }
        }

        // Helper to run the roofline logic for a specific vertical side (.above / .below)
        @inline(__always) func roofline(for side: VerticalSide) {
            var yRoof: CGFloat?
            for e in expanded where e.minX <= cx && cx <= e.maxX {
                switch side {
                case .above:
                    let y = e.minY - verticalClearanceEps
                    yRoof = (yRoof == nil) ? y : Swift.min(yRoof!, y)
                case .below:
                    let y = e.maxY + verticalClearanceEps
                    yRoof = (yRoof == nil) ? y : Swift.max(yRoof!, y)
                case .both:
                    // .both is handled outside by calling this helper twice
                    break
                }
            }
            if let y = yRoof {
                let yClamp: CGFloat
                switch side {
                case .above:
                    yClamp = Swift.min(y, cy)
                case .below:
                    yClamp = Swift.max(y, cy)
                case .both:
                    return
                }
                consider(cx, yClamp)
                consider(cx - halfW, yClamp)
                consider(cx + halfW, yClamp)
            }
        }

        // B) ROOFLINE: compute a roof y near cx and emit a few nearby x samples
        do {
            switch verticalSide {
            case .above:
                roofline(for: .above)
            case .below:
                roofline(for: .below)
            case .both:
                roofline(for: .above)
                roofline(for: .below)
            }
        }

        // Helper to run the direct-over logic for a specific vertical side (.above / .below)
        @inline(__always) func directOver(for side: VerticalSide) {
            let xBandMin = cx - w
            let xBandMax = cx + w
            for e in expanded where e.maxX >= xBandMin && e.minX <= xBandMax {
                let y: CGFloat
                switch side {
                case .above:
                    y = Swift.min(e.minY - verticalClearanceEps, cy)
                case .below:
                    y = Swift.max(e.maxY + verticalClearanceEps, cy)
                case .both:
                    continue // handled by outer dispatch
                }
                let xMid = Swift.min(Swift.max(cx, e.minX), e.maxX)
                consider(xMid, y)
                consider(e.minX, y)
                consider(e.maxX, y)
            }
        }

        // C) DIRECT-OVER: probe a few points above/below obstacles near cx to break tight clusters
        do {
            switch verticalSide {
            case .above:
                directOver(for: .above)
            case .below:
                directOver(for: .below)
            case .both:
                directOver(for: .above)
                directOver(for: .below)
            }
        }

        return bestRect
    }
}
