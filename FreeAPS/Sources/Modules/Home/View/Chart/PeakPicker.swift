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

        return (maxima, minima) // oldest → latest
    }
}
