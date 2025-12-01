import Foundation

enum ExtremumType { case max, min }

enum PeakPicker {
    /// Detects meaningful maxima and minima in a CGM time series using a two-stage
    /// sliding-window extremum algorithm with gap-based refinement.
    ///
    /// The function operates in two phases:
    ///
    /// **Phase 1 — Primary extrema**
    /// A sliding window of width *W* (derived from `windowHours`) is swept across the
    /// entire dataset. A point is marked as a primary maximum/minimum if it is the
    /// most extreme value (and the most recent among equals) within its ±W window.
    /// This produces a coarse but structurally accurate set of major turning points.
    ///
    /// **Phase 2 — Gap refinement**
    /// Each gap between consecutive primary extrema is re-examined using a smaller
    /// sliding window of size `secondaryWindowFactor * W`.
    /// Within that gap, all secondary local maxima/minima are detected. Depending on
    /// the gap’s endpoint types:
    ///   • a min–min gap may admit a secondary maximum,
    ///   • a max–max gap may admit a secondary minimum,
    ///   • a mixed (min–max or max–min) gap may admit one of each, but only if the
    ///     time span of the gap exceeds `oppositeGapFactor * W`.
    ///
    /// For each type that a gap allows, at most one secondary extremum is selected,
    /// according to the following rules:
    ///
    /// 1. **Value priority** – among all secondary candidates of the required type,
    ///    the chosen extremum is the strongest one in its direction
    ///    (highest value for maxima, lowest value for minima).
    ///
    /// 2. **Same-type spacing constraint** – a secondary extremum is accepted only if
    ///    it is sufficiently far from all existing extrema of the same type, where
    ///    “far enough” means at least `minSameTypeGapFactor * W` apart.
    ///    This prevents excessive clustering of same-type peaks while still allowing
    ///    opposite-type peaks to be close together.
    ///
    /// The final result is the union of all primary extrema plus any secondary
    /// extrema admitted during gap refinement.
    /// This produces a stable, noise-resistant set of trend turning points that
    /// captures both the global shape and important local features of the glucose
    /// signal.
    ///
    /// - Parameters:
    ///   - data: The time-ordered glucose measurements.
    ///   - windowHours: The primary window width *W*, in hours.
    ///   - secondaryWindowFactor: Multiplier applied to *W* to obtain the finer
    ///     secondary window used inside gaps.
    ///   - oppositeGapFactor: Minimum gap width (as a multiple of *W*) required
    ///     before opposite-type extrema may both be added in a mixed gap.
    ///   - minSameTypeGapFactor: Minimum required spacing between extrema of the
    ///     same type, expressed as a multiple of *W*.
    ///
    /// - Returns: A pair `(maxima, minima)` with all detected extrema, oldest first.
    static func pick(
        data: [BloodGlucose],
        windowHours: Double = 1,
        secondaryWindowFactor: Double = 1.0 / 3.0,
        oppositeGapFactor: Double = 1.9,
        minSameTypeGapFactor: Double = 0.8
    ) -> (maxima: [BloodGlucose], minima: [BloodGlucose]) {
        let W: TimeInterval = windowHours * 3600
        let secondaryW: TimeInterval = W * secondaryWindowFactor
        let oppositeMinGap: TimeInterval = oppositeGapFactor * W
        let minSameTypeGap: TimeInterval = minSameTypeGapFactor * W

        // Normalize: non-nil, oldest → latest
        let asc: [(bg: BloodGlucose, v: Double)] = data.compactMap { g in
            guard let v = g.glucose else { return nil }
            return (g, Double(v))
        }

        let n = asc.count
        guard n > 0 else { return ([], []) }

        let times = asc.map(\.bg.dateString)
        let vals = asc.map(\.v)

        // MARK: - Phase 1: primary peaks with window W over full series

        let primary = slidingWindowExtrema(
            vals: vals,
            times: times,
            window: W,
            range: 0 ..< n
        )

        let primaryMaxIdx = primary.maxIdx
        let primaryMinIdx = primary.minIdx

        struct Peak {
            let idx: Int
            let type: ExtremumType
        }

        var primaryPeaks: [Peak] = []
        primaryPeaks += primaryMaxIdx.map { Peak(idx: $0, type: .max) }
        primaryPeaks += primaryMinIdx.map { Peak(idx: $0, type: .min) }
        primaryPeaks.sort { times[$0.idx] < times[$1.idx] }

        // Not enough primary peaks to define gaps → just return them
        if primaryPeaks.count <= 1 {
            let maxima = primaryMaxIdx.sorted { times[$0] < times[$1] }.map { asc[$0].bg }
            let minima = primaryMinIdx.sorted { times[$0] < times[$1] }.map { asc[$0].bg }
            return (maxima, minima)
        }

        // Same-type sets used to enforce minimal spacing for added peaks
        var maxSameType = primaryMaxIdx
        var minSameType = primaryMinIdx

        // MARK: - Phase 2: refine each gap using smaller window (W/3)

        var secondaryPeaks: [Peak] = []

        for k in 0 ..< (primaryPeaks.count - 1) {
            let left = primaryPeaks[k]
            let right = primaryPeaks[k + 1]

            let gapStart = left.idx + 1
            let gapEnd = right.idx // half-open [gapStart, gapEnd)

            if gapStart >= gapEnd {
                continue // no interior points
            }

            let gapRange = gapStart ..< gapEnd

            let gapExtrema = slidingWindowExtrema(
                vals: vals,
                times: times,
                window: secondaryW,
                range: gapRange
            )
            let gapMaxIdx = gapExtrema.maxIdx
            let gapMinIdx = gapExtrema.minIdx

            if gapMaxIdx.isEmpty, gapMinIdx.isEmpty {
                continue
            }

            let tLeft = times[left.idx]
            let tRight = times[right.idx]
            let gapDuration = tRight.timeIntervalSince(tLeft)

            switch (left.type, right.type) {
            case (.min, .min):
                // min–min gap: add one max (best-by-value) if far enough from other maxima
                if let idx = pickBestCandidateByValueRespectingSameTypeDistance(
                    candidates: gapMaxIdx,
                    type: .max,
                    vals: vals,
                    times: times,
                    minSameTypeGap: minSameTypeGap,
                    existingSameType: maxSameType
                ) {
                    secondaryPeaks.append(Peak(idx: idx, type: .max))
                    maxSameType.append(idx)
                }

            case (.max, .max):
                // max–max gap: add one min (best-by-value) if far enough from other minima
                if let idx = pickBestCandidateByValueRespectingSameTypeDistance(
                    candidates: gapMinIdx,
                    type: .min,
                    vals: vals,
                    times: times,
                    minSameTypeGap: minSameTypeGap,
                    existingSameType: minSameType
                ) {
                    secondaryPeaks.append(Peak(idx: idx, type: .min))
                    minSameType.append(idx)
                }

            case (.max, .min),
                 (.min, .max):
                // Opposite extrema: only if the gap is wide enough
                if gapDuration > oppositeMinGap {
                    if let idxMax = pickBestCandidateByValueRespectingSameTypeDistance(
                        candidates: gapMaxIdx,
                        type: .max,
                        vals: vals,
                        times: times,
                        minSameTypeGap: minSameTypeGap,
                        existingSameType: maxSameType
                    ) {
                        secondaryPeaks.append(Peak(idx: idxMax, type: .max))
                        maxSameType.append(idxMax)
                    }

                    if let idxMin = pickBestCandidateByValueRespectingSameTypeDistance(
                        candidates: gapMinIdx,
                        type: .min,
                        vals: vals,
                        times: times,
                        minSameTypeGap: minSameTypeGap,
                        existingSameType: minSameType
                    ) {
                        secondaryPeaks.append(Peak(idx: idxMin, type: .min))
                        minSameType.append(idxMin)
                    }
                }

            @unknown default:
                break
            }
        }

        // MARK: - Merge primary + secondary, split into maxima/minima

        var allPeaks = primaryPeaks
        let primaryIdxSet = Set(allPeaks.map(\.idx))

        for p in secondaryPeaks where !primaryIdxSet.contains(p.idx) {
            allPeaks.append(p)
        }

        allPeaks.sort { times[$0.idx] < times[$1.idx] }

        var finalMaxIdx: [Int] = []
        var finalMinIdx: [Int] = []

        for p in allPeaks {
            switch p.type {
            case .max: finalMaxIdx.append(p.idx)
            case .min: finalMinIdx.append(p.idx)
            }
        }

        finalMaxIdx.sort { times[$0] < times[$1] }
        finalMinIdx.sort { times[$0] < times[$1] }

        let maxima = finalMaxIdx.map { asc[$0].bg }
        let minima = finalMinIdx.map { asc[$0].bg }

        return (maxima, minima)
    }

    // MARK: - Private helpers

    /// Sliding-window extrema over a given `range` of indices.
    /// Returns indices of maxima and minima, using the "latest among equals" rule.
    private static func slidingWindowExtrema(
        vals: [Double],
        times: [Date],
        window: TimeInterval,
        range: Range<Int>
    ) -> (maxIdx: [Int], minIdx: [Int]) {
        guard !range.isEmpty else { return ([], []) }

        var maxDQ: [Int] = []
        var minDQ: [Int] = []
        var maxHead = 0
        var minHead = 0

        @inline(__always) func maxFront() -> Int? {
            maxHead < maxDQ.count ? maxDQ[maxHead] : nil
        }
        @inline(__always) func minFront() -> Int? {
            minHead < minDQ.count ? minDQ[minHead] : nil
        }

        func maxPush(_ j: Int) {
            while maxHead < maxDQ.count, vals[j] >= vals[maxDQ.last!] {
                _ = maxDQ.popLast()
            }
            maxDQ.append(j)
        }

        func minPush(_ j: Int) {
            while minHead < minDQ.count, vals[j] <= vals[minDQ.last!] {
                _ = minDQ.popLast()
            }
            minDQ.append(j)
        }

        func maxPopFrontIf(_ idx: Int) {
            if let f = maxFront(), f == idx { maxHead += 1 }
        }

        func minPopFrontIf(_ idx: Int) {
            if let f = minFront(), f == idx { minHead += 1 }
        }

        var L = range.lowerBound
        var R = range.lowerBound - 1

        var maxIdx: [Int] = []
        var minIdx: [Int] = []

        for i in range {
            let ti = times[i]

            // expand right to include ti + window
            while R + 1 < range.upperBound,
                  times[R + 1].timeIntervalSince(ti) <= window
            {
                R += 1
                maxPush(R)
                minPush(R)
            }

            // shrink left to exclude ti - window
            while L <= R,
                  ti.timeIntervalSince(times[L]) > window
            {
                maxPopFrontIf(L)
                minPopFrontIf(L)
                L += 1
            }

            if let mf = maxFront(), mf == i {
                maxIdx.append(i)
            }
            if let nf = minFront(), nf == i {
                minIdx.append(i)
            }
        }

        return (maxIdx, minIdx)
    }

    /// Among `candidates` (indices of extrema of given `type`), pick the one
    /// with the strongest value (highest for maxima, lowest for minima) that is
    /// at least `minSameTypeGap` away from every index in `existingSameType`.
    private static func pickBestCandidateByValueRespectingSameTypeDistance(
        candidates: [Int],
        type: ExtremumType,
        vals: [Double],
        times: [Date],
        minSameTypeGap: TimeInterval,
        existingSameType: [Int]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }

        var bestIdx: Int?
        var bestVal: Double = 0

        for i in candidates {
            let ti = times[i]

            // distance to nearest same-type peak already selected
            var nearest: TimeInterval = .infinity
            for j in existingSameType {
                let dt = abs(ti.timeIntervalSince(times[j]))
                if dt < nearest { nearest = dt }
            }

            // Enforce same-type minimal spacing
            if nearest < minSameTypeGap {
                continue
            }

            let v = vals[i]

            if let currentBestIdx = bestIdx {
                let currentBestVal = vals[currentBestIdx]
                switch type {
                case .max:
                    if v > currentBestVal { bestIdx = i }
                case .min:
                    if v < currentBestVal { bestIdx = i }
                }
            } else {
                bestIdx = i
            }
        }

        return bestIdx
    }
}
