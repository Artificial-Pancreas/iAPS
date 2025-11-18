import Foundation

enum ExtremumType { case max, min }

enum PeakPicker {
    static func pick(
        data: [BloodGlucose],
        windowHours: Double = 1
    ) -> (maxima: [BloodGlucose], minima: [BloodGlucose]) {
        let W: TimeInterval = windowHours * 3600

        // Normalize: non-nil, oldest → latest
        let asc: [(bg: BloodGlucose, v: Double)] = data.compactMap { g in
            guard let v = g.glucose else { return nil }
            return (g, Double(v))
        }.sorted { $0.bg.dateString < $1.bg.dateString }

        let n = asc.count
        guard n > 0 else { return ([], []) }

        let times = asc.map(\.bg.dateString)
        let vals = asc.map(\.v)

        // Monotonic deques of indices (we keep only the **latest** among equals):
        var maxDQ: [Int] = [] // decreasing by value
        var minDQ: [Int] = [] // increasing by value
        var maxHead = 0
        var minHead = 0

        @inline(__always) func maxFront() -> Int? { maxHead < maxDQ.count ? maxDQ[maxHead] : nil }
        @inline(__always) func minFront() -> Int? { minHead < minDQ.count ? minDQ[minHead] : nil }

        // IMPORTANT: use >= (<=) so pushing an equal value removes the older one.
        func maxPush(_ j: Int) {
            while maxHead < maxDQ.count, vals[j] >= vals[maxDQ.last!] { _ = maxDQ.popLast() }
            maxDQ.append(j)
        }
        func minPush(_ j: Int) {
            while minHead < minDQ.count, vals[j] <= vals[minDQ.last!] { _ = minDQ.popLast() }
            minDQ.append(j)
        }
        func maxPopFrontIf(_ idx: Int) { if let f = maxFront(), f == idx { maxHead += 1 } }
        func minPopFrontIf(_ idx: Int) { if let f = minFront(), f == idx { minHead += 1 } }

        var L = 0 // left boundary of window
        var R = -1 // right boundary (inclusive)

        var maxima: [BloodGlucose] = []
        var minima: [BloodGlucose] = []

        for i in 0 ..< n {
            let ti = times[i]

            // expand right to include ti + W
            while R + 1 < n, times[R + 1].timeIntervalSince(ti) <= W {
                R += 1
                maxPush(R)
                minPush(R)
            }
            // shrink left to exclude ti - W
            while L <= R, ti.timeIntervalSince(times[L]) > W {
                maxPopFrontIf(L)
                minPopFrontIf(L)
                L += 1
            }

            // i is a peak if it's exactly the (unique-latest) extreme at the front
            if let mf = maxFront(), mf == i { maxima.append(asc[i].bg) }
            if let nf = minFront(), nf == i { minima.append(asc[i].bg) }
        }

        // Post-processing: simpler gap filling based on combined extrema timestamps.
        // 1) Combine maxima and minima timestamps.
        // 2) Find spans longer than 2 * W.
        // 3) Split spans into k equal parts where k = floor(span / W).
        // 4) For each split point, search local extreme within ±10% of W; if none, add the point itself
        //    and classify as min/max based on the slope of the span.

        guard let globalStart = times.first, let globalEnd = times.last, W > 0 else {
            return (maxima, minima)
        }

        // Helper to get value at time by nearest sample index in `asc`.
        func nearestIndex(for time: Date) -> Int? {
            // Linear search is acceptable for typical data sizes; can optimize with binary search if needed.
            var best: (idx: Int, dt: TimeInterval)?
            for (i, t) in times.enumerated() {
                let dt = abs(t.timeIntervalSince(time))
                if best == nil || dt < best!.dt { best = (i, dt) }
            }
            return best?.idx
        }

        // Helper to find local extreme around a center time within ±radius seconds.
        enum ExtremeKind { case max, min }
        func localExtreme(around center: Date, radius: TimeInterval) -> (idx: Int, kind: ExtremeKind)? {
            let start = center.addingTimeInterval(-radius)
            let end = center.addingTimeInterval(radius)
            var sIdx: Int?
            var eIdx: Int?
            for (i, t) in times.enumerated() {
                if t >= start, t <= end {
                    if sIdx == nil { sIdx = i }
                    eIdx = i
                } else if t > end { break }
            }
            guard let s = sIdx, let e = eIdx, s <= e else { return nil }
            var minI = s, maxI = s
            var minV = vals[s], maxV = vals[s]
            for j in s ... e {
                let v = vals[j]
                if v < minV { minV = v
                    minI = j }
                if v > maxV { maxV = v
                    maxI = j }
            }
            // If the range is non-trivial, pick the stronger extreme; else nil to fallback to center.
            if maxV - minV > 0 {
                let mean = (maxV + minV) * 0.5
                let devMax = abs(maxV - mean)
                let devMin = abs(minV - mean)
                if devMax >= devMin { return (maxI, .max) } else { return (minI, .min) }
            }
            return nil
        }

        // Build sorted unique list of existing extrema times.
        var selectedTimes: [Date] = (maxima.map(\.dateString) + minima.map(\.dateString))
        selectedTimes = Array(Set(selectedTimes)).sorted()

        // If no extrema yet, seed with start and end so gap logic can operate.
        if selectedTimes.isEmpty {
            selectedTimes = [globalStart, globalEnd]
        } else {
            // Ensure endpoints are present for span computation.
            if let first = selectedTimes.first, first > globalStart { selectedTimes.insert(globalStart, at: 0) }
            if let last = selectedTimes.last, last < globalEnd { selectedTimes.append(globalEnd) }
        }

        let searchRadius = 0.1 * W // ±10% of window size

        // For each adjacent pair, fill large spans.
        for i in 0 ..< (selectedTimes.count - 1) {
            let a = selectedTimes[i]
            let b = selectedTimes[i + 1]
            let span = b.timeIntervalSince(a)
            if span <= 2 * W { continue }

            // Determine how many splits: spans longer than k windows -> split into k parts.
            let k = Int(floor(span / W))
            guard k >= 2 else { continue }

            // Determine slope across the whole segment (for fallback classification)
            let ia = nearestIndex(for: a)
            let ib = nearestIndex(for: b)
            let slopeKind: ExtremeKind? = {
                if let ia, let ib, ia != ib {
                    let va = vals[ia]
                    let vb = vals[ib]
                    return (vb >= va) ? .max : .min
                }
                return nil
            }()

            // Place k-1 interior points (split into k parts -> k-1 internal marks)
            for j in 1 ..< k {
                let t = a.addingTimeInterval(span * Double(j) / Double(k))
                if let found = localExtreme(around: t, radius: searchRadius) {
                    let bg = asc[found.idx].bg
                    if found.kind == .max {
                        maxima.append(bg)
                    } else {
                        minima.append(bg)
                    }
                } else {
                    // Fallback: add the sample nearest to t and classify by slopeKind
                    if let idx = nearestIndex(for: t) {
                        let bg = asc[idx].bg
                        if let kind = slopeKind {
                            if kind == .max { maxima.append(bg) } else { minima.append(bg) }
                        } else {
                            // If slope unknown, decide by local derivative if possible
                            let prev = max(0, idx - 1)
                            let next = min(n - 1, idx + 1)
                            let dv = vals[next] - vals[prev]
                            if dv >= 0 { maxima.append(bg) } else { minima.append(bg) }
                        }
                    }
                }
            }
        }

        // Deduplicate in case added points coincide with existing peaks
        func uniqueByDate(_ arr: [BloodGlucose]) -> [BloodGlucose] {
            var seen = Set<Date>()
            var out: [BloodGlucose] = []
            for g in arr.sorted(by: { $0.dateString < $1.dateString }) {
                if !seen.contains(g.dateString) {
                    out.append(g)
                    seen.insert(g.dateString)
                }
            }
            return out
        }

        maxima = uniqueByDate(maxima)
        minima = uniqueByDate(minima)

        return (maxima, minima) // oldest → latest (with gap-filling)
    }
}
