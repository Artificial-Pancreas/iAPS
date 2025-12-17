import Foundation

enum ExtremumType { case max, min, none }

enum PeakPicker {
    /// Detects meaningful extrema in a CGM time series using a multi-stage
    /// sliding-window algorithm with gap-based refinement.
    ///
    /// The function operates in **three phases**:
    ///
    /// **Phase 1 — Primary extrema**
    /// A sliding window of width *W* (derived from `windowHours`) is swept across the
    /// entire dataset. A point is marked as a primary maximum or minimum if it is the
    /// most extreme value (and the most recent among equals) within its ±W window.
    /// This yields a stable set of major turning points.
    ///
    /// **Phase 2 — Gap refinement (secondary extrema)**
    /// Each gap between consecutive primary extrema is re-examined using a smaller
    /// sliding window of size `secondaryWindowFactor * W`.
    /// Local extrema inside that gap are detected, and depending on the types of the
    /// endpoints:
    ///   • a min–min gap may admit one secondary maximum,
    ///   • a max–max gap may admit one secondary minimum,
    ///   • a mixed (min–max or max–min) gap may admit one of each, but only if the
    ///     gap is wider than `oppositeGapFactor * W`.
    ///
    /// When selecting a secondary extremum for a gap:
    ///   1. **Value priority** — choose the strongest candidate
    ///      (highest for maxima, lowest for minima).
    ///   2. **Same-type spacing rule** — the chosen extremum must be sufficiently far
    ///      from all other extrema of the same type, at least
    ///      `minSameTypeGapFactor * W` apart.
    ///      This prevents unnatural clustering of same-type peaks.
    ///
    /// **Phase 3 — Neutral extrema (`.none`) in wide opposite-type gaps**
    /// After merging primary and secondary extrema, the function scans all min–max
    /// and max–min neighbours. If their separation exceeds `oppositeGapFactor * W`,
    /// it inserts exactly one “neutral” extremum (`.none`) at the interior data point
    /// whose timestamp is closest to the midpoint of the gap.
    /// These neutral markers can be used for annotations or segmentation.
    ///
    /// The function returns **all extrema of all three phases**, each annotated with
    /// its `ExtremumType` ( `.max`, `.min`, or `.none` ), sorted in ascending
    /// chronological order.
    ///
    /// - Parameters:
    ///   - data: The time-ordered glucose measurements.
    ///   - windowHours: The primary window width *W*, in hours.
    ///   - secondaryWindowFactor: Fraction of *W* used for secondary extrema.
    ///   - oppositeGapFactor: Gap-width multiplier controlling when opposite-type
    ///     gaps may receive two secondary extrema, and when neutral extrema are added.
    ///   - minSameTypeGapFactor: Minimum spacing between same-type extrema,
    ///     expressed as a multiple of *W*.
    ///
    /// - Returns: An array of `(bg: BloodGlucose, type: ExtremumType)`
    ///            sorted by timestamp ascending.
    static func pick(
        data: [BloodGlucose],
        windowHours: Double = 1,
        secondaryWindowFactor: Double = 1.0 / 3.0,
        oppositeGapFactor: Double = 1.9,
        minSameTypeGapFactor: Double = 0.8
    ) -> [(bg: BloodGlucose, type: ExtremumType)] {
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
        guard n > 0 else { return [] }

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

        // Not enough primary peaks to define gaps → return the single peak (or none)
        if primaryPeaks.count <= 1 {
            let sortedIdx = (primaryMaxIdx + primaryMinIdx).sorted { times[$0] < times[$1] }

            let result: [(bg: BloodGlucose, type: ExtremumType)] =
                sortedIdx.map { i in
                    let type: ExtremumType = primaryMaxIdx.contains(i) ? .max : .min
                    return (bg: asc[i].bg, type: type)
                }

            return result
        }

        // Same-type sets used to enforce minimal spacing for added peaks
        var maxSameType = primaryMaxIdx
        var minSameType = primaryMinIdx

        // MARK: - Phase 2: refine each gap using smaller window (secondaryW)

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

            case (_, .none),
                 (.none, _):
                break
            }
        }

        // MARK: - Merge primary + secondary

        var allPeaks = primaryPeaks
        let primaryIdxSet = Set(allPeaks.map(\.idx))

        for p in secondaryPeaks where !primaryIdxSet.contains(p.idx) {
            allPeaks.append(p)
        }

        allPeaks.sort { times[$0.idx] < times[$1.idx] }

        // MARK: - Phase 3: neutral (.none) extrema in wide opposite-type gaps

        var neutralPeaks: [Peak] = []

        if allPeaks.count >= 2 {
            for i in 0 ..< (allPeaks.count - 1) {
                let left = allPeaks[i]
                let right = allPeaks[i + 1]

                // Only min–max or max–min; ignore gaps involving `.none`.
                let isOppositePair: Bool =
                    (left.type == .min && right.type == .max) ||
                    (left.type == .max && right.type == .min)

                guard isOppositePair else { continue }

                let tLeft = times[left.idx]
                let tRight = times[right.idx]
                let gapDuration = tRight.timeIntervalSince(tLeft)

                guard gapDuration > oppositeMinGap else { continue }

                // Need at least one interior sample to host a neutral extremum
                let start = left.idx + 1
                let end = right.idx
                guard start < end else { continue }

                let midTime = tLeft.addingTimeInterval(gapDuration / 2)
                var bestIdx = start
                var bestDist = abs(times[start].timeIntervalSince(midTime))

                if start + 1 < end {
                    for j in (start + 1) ..< end {
                        let d = abs(times[j].timeIntervalSince(midTime))
                        if d < bestDist {
                            bestDist = d
                            bestIdx = j
                        }
                    }
                }

                // Avoid duplicating an existing peak at exactly the same index
                if primaryIdxSet.contains(bestIdx) ||
                    allPeaks.contains(where: { $0.idx == bestIdx })
                {
                    continue
                }

                neutralPeaks.append(Peak(idx: bestIdx, type: .none))
            }
        }

        allPeaks.append(contentsOf: neutralPeaks)
        allPeaks.sort { times[$0.idx] < times[$1.idx] }

        // Convert to final result including .none peaks
        let result: [(bg: BloodGlucose, type: ExtremumType)] =
            allPeaks.map { peak in
                (bg: asc[peak.idx].bg, type: peak.type)
            }

        return result
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
                case .none:
                    // Should never be requested for `.none` in current logic.
                    break
                }
            } else {
                bestIdx = i
                bestVal = v
                _ = bestVal // just to silence "unused" if optimised out
            }
        }

        return bestIdx
    }
}
