import Foundation

enum ExtremumType { case max, min }

enum PeakPicker {
    /// This function detects glucose trend extrema in two stages.
    /// Phase 1 identifies “primary” maxima and minima using a sliding ± W time-window, ensuring that each reported peak is the most extreme (latest among equals) within its window.
    /// Phase 2 then fills large gaps between these primary peaks: it finds secondary local extrema, filters out narrow bumps (shortest arm < W/10), ranks them by width, and iteratively inserts them only where allowed by the peak-type gap rules and same-type spacing constraints.
    /// Opposite-type peaks may appear close together, while peaks of the same type remain well-spaced.
    /// The result is a robust set of meaningful turning points without noise-driven micro-peaks.
    static func pick(
        data: [BloodGlucose],
        windowHours: Double = 1
    ) -> (maxima: [BloodGlucose], minima: [BloodGlucose]) {
        let W: TimeInterval = windowHours * 3600
        let minGapSameTypeFactor = 0.85 // neighbours of SAME type at least ~0.85 * W apart
        let oppositeGapFactor: Double = 1.7 // for opposite-type gaps
        let minArmFraction: Double = 0.05 // filter phase-2 extrema with shortest arm < W * 0.05

        let minGapSameType = minGapSameTypeFactor * W
        let minArm = minArmFraction * W

        let asc: [(bg: BloodGlucose, v: Double)] = data.compactMap { g in
            guard let v = g.glucose else { return nil }
            return (g, Double(v))
        }

        let n = asc.count
        guard n > 0 else { return ([], []) }

        let times = asc.map(\.bg.dateString) // assuming this is Date
        let vals = asc.map(\.v)

        // ---------------------------------------------------------
        // PHASE 1: sliding-window extrema
        // ---------------------------------------------------------

        // Monotonic deques of indices (we keep only the **latest** among equals):
        var maxDQ: [Int] = [] // decreasing by value
        var minDQ: [Int] = [] // increasing by value
        var maxHead = 0
        var minHead = 0

        @inline(__always) func maxFront() -> Int? { maxHead < maxDQ.count ? maxDQ[maxHead] : nil }
        @inline(__always) func minFront() -> Int? { minHead < minDQ.count ? minDQ[minDQ.count > minHead ? minHead : 0] : nil }

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
        func maxPopFrontIf(_ idx: Int) { if let f = maxFront(), f == idx { maxHead += 1 } }
        func minPopFrontIf(_ idx: Int) { if let f = minFront(), f == idx { minHead += 1 } }

        var L = 0 // left boundary of window
        var R = -1 // right boundary (inclusive)

        var phase1MaxIdx: [Int] = []
        var phase1MinIdx: [Int] = []

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
            if let mf = maxFront(), mf == i {
                phase1MaxIdx.append(i)
            }
            if let nf = minFront(), nf == i {
                phase1MinIdx.append(i)
            }
        }

        // ---------------------------------------------------------
        // PHASE 2: local extrema + "shortest arm" width, with arm >= W * 0.05
        // ---------------------------------------------------------

        // 1) Detect strict local extrema by neighbour comparison
        var localMaxIdx: [Int] = []
        var localMinIdx: [Int] = []

        if n >= 3 {
            for i in 1 ..< (n - 1) {
                let prev = vals[i - 1]
                let cur = vals[i]
                let next = vals[i + 1]

                if cur > prev, cur > next {
                    localMaxIdx.append(i)
                } else if cur < prev, cur < next {
                    localMinIdx.append(i)
                }
            }
        }

        struct WideExtremum {
            let idx: Int
            let width: TimeInterval // priority = shortest of the two arms
            let type: ExtremumType
        }

        func buildWideExtrema(from indices: [Int], type: ExtremumType) -> [WideExtremum] {
            var result: [WideExtremum] = []
            result.reserveCapacity(indices.count)

            for i in indices {
                var l = i
                var r = i

                switch type {
                case .max:
                    // expand as long as we don't see a *strictly higher* neighbour
                    while l > 0, vals[l - 1] <= vals[l] { l -= 1 }
                    while r + 1 < n, vals[r + 1] <= vals[r] { r += 1 }

                case .min:
                    // expand as long as we don't see a *strictly lower* neighbour
                    while l > 0, vals[l - 1] >= vals[l] { l -= 1 }
                    while r + 1 < n, vals[r + 1] >= vals[r] { r += 1 }
                }

                let centerTime = times[i]
                let leftTime = times[l]
                let rightTime = times[r]

                let leftArm = centerTime.timeIntervalSince(leftTime)
                let rightArm = rightTime.timeIntervalSince(centerTime)
                let shortestArm = min(leftArm, rightArm)

                // filter out tiny bumps: one arm < W/10
                guard shortestArm >= minArm else { continue }

                result.append(WideExtremum(idx: i, width: shortestArm, type: type))
            }

            // widest → narrowest (for deterministic choice when several fit)
            result.sort { $0.width > $1.width }
            return result
        }

        let maxCandidates = buildWideExtrema(from: localMaxIdx, type: .max)
        let minCandidates = buildWideExtrema(from: localMinIdx, type: .min)

        if maxCandidates.isEmpty, minCandidates.isEmpty {
            // No extra candidates -> return phase1 only
            let finalMaxIdx = phase1MaxIdx.sorted { times[$0] < times[$1] }
            let finalMinIdx = phase1MinIdx.sorted { times[$0] < times[$1] }
            return (finalMaxIdx.map { asc[$0].bg }, finalMinIdx.map { asc[$0].bg })
        }

        // Type lookup for all peaks (phase1 + phase2)
        var typeByIdx: [Int: ExtremumType] = [:]
        for idx in phase1MaxIdx { typeByIdx[idx] = .max }
        for idx in phase1MinIdx { typeByIdx[idx] = .min }
        for cand in maxCandidates { typeByIdx[cand.idx] = .max }
        for cand in minCandidates { typeByIdx[cand.idx] = .min }

        // For looking up widths (only needed for comparing phase2 candidates)
        var widthByIdx: [Int: TimeInterval] = [:]
        for cand in maxCandidates { widthByIdx[cand.idx] = cand.width }
        for cand in minCandidates { widthByIdx[cand.idx] = cand.width }

        // ---------------------------------------------------------
        // Iterative gap-filling
        // ---------------------------------------------------------

        // Phase1 peaks, sorted by time
        var currentPeaks = Array(Set(phase1MaxIdx + phase1MinIdx))
        currentPeaks.sort { times[$0] < times[$1] }

        // Used candidates so we don't insert the same phase2 point twice
        var usedCandidates = Set<Int>()

        func bestCandidate(
            ofType type: ExtremumType,
            between leftIdx: Int,
            and rightIdx: Int,
            used: Set<Int>
        ) -> WideExtremum? {
            let candidates = (type == .max ? maxCandidates : minCandidates)

            let tLeft = times[leftIdx]
            let tRight = times[rightIdx]

            var best: WideExtremum?

            for cand in candidates {
                let idx = cand.idx
                if used.contains(idx) { continue }

                let t = times[idx]
                // must lie strictly inside the gap in time
                if t <= tLeft || t >= tRight { continue }

                // Enforce min distance only to same-type endpoints
                if typeByIdx[leftIdx] == type {
                    if t.timeIntervalSince(tLeft) < minGapSameType {
                        continue
                    }
                }
                if typeByIdx[rightIdx] == type {
                    if tRight.timeIntervalSince(t) < minGapSameType {
                        continue
                    }
                }

                if let cur = best {
                    if cand.width > cur.width {
                        best = cand
                    }
                } else {
                    best = cand
                }
            }

            return best
        }

        let oppositeMinGap = oppositeGapFactor * W

        while true {
            var addedThisPass: [Int] = []

            if currentPeaks.count >= 2 {
                for k in 0 ..< (currentPeaks.count - 1) {
                    let leftIdx = currentPeaks[k]
                    let rightIdx = currentPeaks[k + 1]

                    guard
                        let leftType = typeByIdx[leftIdx],
                        let rightType = typeByIdx[rightIdx]
                    else { continue }

                    let tLeft = times[leftIdx]
                    let tRight = times[rightIdx]
                    let gap = tRight.timeIntervalSince(tLeft)

                    // ---- same-type gaps ----
                    if leftType == .min && rightType == .min {
                        // min–min: always try to add one max (no same-type gap restriction here)
                        if let chosenMax = bestCandidate(
                            ofType: .max,
                            between: leftIdx,
                            and: rightIdx,
                            used: usedCandidates
                        ) {
                            let idx = chosenMax.idx
                            addedThisPass.append(idx)
                            usedCandidates.insert(idx)
                            typeByIdx[idx] = .max
                        }
                        continue
                    }

                    if leftType == .max && rightType == .max {
                        // max–max: always try to add one min
                        if let chosenMin = bestCandidate(
                            ofType: .min,
                            between: leftIdx,
                            and: rightIdx,
                            used: usedCandidates
                        ) {
                            let idx = chosenMin.idx
                            addedThisPass.append(idx)
                            usedCandidates.insert(idx)
                            typeByIdx[idx] = .min
                        }
                        continue
                    }

                    // ---- opposite-type gaps ----
                    let isOpposite =
                        (leftType == .min && rightType == .max) ||
                        (leftType == .max && rightType == .min)

                    if isOpposite, gap > oppositeMinGap {
                        // Try to get both a max and a min that respect same-type spacing
                        let maxCand = bestCandidate(
                            ofType: .max,
                            between: leftIdx,
                            and: rightIdx,
                            used: usedCandidates
                        )
                        let minCand = bestCandidate(
                            ofType: .min,
                            between: leftIdx,
                            and: rightIdx,
                            used: usedCandidates
                        )

                        if let maxC = maxCand, let minC = minCand {
                            // No restriction between them (min can be close to max)
                            addedThisPass.append(maxC.idx)
                            addedThisPass.append(minC.idx)
                            usedCandidates.insert(maxC.idx)
                            usedCandidates.insert(minC.idx)
                            typeByIdx[maxC.idx] = .max
                            typeByIdx[minC.idx] = .min
                        } else if let maxC = maxCand {
                            addedThisPass.append(maxC.idx)
                            usedCandidates.insert(maxC.idx)
                            typeByIdx[maxC.idx] = .max
                        } else if let minC = minCand {
                            addedThisPass.append(minC.idx)
                            usedCandidates.insert(minC.idx)
                            typeByIdx[minC.idx] = .min
                        }
                    }
                }
            }

            if addedThisPass.isEmpty {
                break
            }

            // Merge newly added peaks into the list and sort by time
            currentPeaks.append(contentsOf: addedThisPass)
            currentPeaks = Array(Set(currentPeaks))
            currentPeaks.sort { times[$0] < times[$1] }
        }

        // ---------------------------------------------------------
        // Final maxima / minima
        // ---------------------------------------------------------

        var finalMaxIdx: [Int] = []
        var finalMinIdx: [Int] = []

        for idx in currentPeaks {
            switch typeByIdx[idx] {
            case .max?: finalMaxIdx.append(idx)
            case .min?: finalMinIdx.append(idx)
            case nil: break
            }
        }

        finalMaxIdx.sort { times[$0] < times[$1] }
        finalMinIdx.sort { times[$0] < times[$1] }

        let maxima = finalMaxIdx.map { asc[$0].bg }
        let minima = finalMinIdx.map { asc[$0].bg }

        return (maxima, minima)
    }
}
