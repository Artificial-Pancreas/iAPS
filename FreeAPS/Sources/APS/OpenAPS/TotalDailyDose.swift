import Combine
import CoreData
import Foundation

final class TotalDailyDose {
    func totalDailyDose(_ data: [PumpHistoryEvent], increment: Double) -> (bolus: Decimal, basal: Decimal, hours: Double) {
        let now = Date.now
        let hours = -1 * (data.first?.timestamp ?? .distantFuture).timeIntervalSinceNow / 36E2
        guard hours > 0 else {
            return (bolus: 0, basal: 0, hours: 0)
        }
        let tdd = (bolus: bolus(data), basal: tempBasals(data, increment: increment), hours: hours)
        // Dev testing
        print("Time for TDD: \(-1 * now.timeIntervalSinceNow) seconds")
        debug(.dynamic, "TDD: " + (tdd.basal + tdd.bolus).formatted() + " U; basal: " + tdd.basal.formatted() + " U.")
        return tdd
    }

    // MDT pumps don't have pulses, but a rate variable speed of delivery(?)
    private func secondsPerPulse(omnipod: Bool, units: Decimal) -> Double {
        var secondsPerPulse: Double = 2
        if !omnipod {
            let amount = Double(units)
            switch amount {
            case let u where u < 1.0:
                secondsPerPulse = 4
            case let u where u > 7.5:
                secondsPerPulse = 0.05 / ((amount / 5) / 60)
            default:
                secondsPerPulse = 2
            }
        }
        return secondsPerPulse
    }

    func accountForIncrements(_ insulin: Double, increment: Double) -> Double {
        // Currently uses the bolus increment setting. Change it if set too high.
        var minimalDose = increment
        if minimalDose != 0.05 {
            minimalDose = 0.1
        }

        let incrementsRaw = insulin / minimalDose
        if incrementsRaw >= 1 {
            let increments = floor(incrementsRaw)
            return increments * minimalDose
        } else { return 0 }
    }

    // All delivered boli (manual, external and SMBs)
    private func bolus(_ data: [PumpHistoryEvent]) -> Decimal {
        data.compactMap(\.amount).reduce(0, +)
    }

    // All delivered temp basals > 0 U/h
    private func tempBasals(_ data: [PumpHistoryEvent], increment: Double) -> Decimal {
        let filteredData: [PumpHistoryEvent] = data.reversed().filter({ $0.type != .tempBasalDuration && $0.type != .bolus })
            .sorted { $0.timestamp < $1.timestamp }
        // Parsing 1/2 or more of the temp basals
        let allBasals = parseBasalHistory(filteredData, data: data, increment: increment)
        // Parsing rest of the temp basals.
        let addSkippedBasals = addSkippedBasals(checkForSkippedBasals: allBasals, filteredData, data: data, increment: increment)
        // Summation
        var firstBasals = allBasals.compactMap({ each in each?.amount }).reduce(0, +)
        var addedBasals = addSkippedBasals.map(\.amount).reduce(0, +)
        // There is no temp basal insulin delivery during boluses/SMBs. Remove amount here.
        if firstBasals > 0 {
            firstBasals -= subtractPulses(filteredData: filteredData, basals: allBasals, increment: increment)
        }
        if addedBasals > 0 {
            addedBasals -= subtractPulsesSkippedBasals(filteredData: filteredData, basals: addSkippedBasals, increment: increment)
        }
        return firstBasals + addedBasals
    }

    private func parseBasalHistory(_ filteredData: [PumpHistoryEvent], data: [PumpHistoryEvent], increment: Double) -> [Basal?] {
        let allBasals = filteredData
            .chunks(ofCount: 2)
            .map { chunk -> Basal? in
                let chunk = Array(chunk)
                var timeOfNoneComputed: Date?
                var nonComputedAmount: Decimal = 0

                guard chunk[0].type == .tempBasal, (chunk[0].rate ?? 0) > 0 else {
                    // Did we skip over a temp basal? In that case save for later.
                    if chunk.count == 2, chunk[1].type == .tempBasal, (chunk[1].rate ?? 0) > 0 {
                        timeOfNoneComputed = chunk[1].timestamp
                        nonComputedAmount = chunk[1].rate ?? 0
                        return Basal(
                            amount: 0,
                            noneComputed: timeOfNoneComputed,
                            nonComputedAmount: nonComputedAmount
                        )
                    }
                    return nil
                }
                // let time = chunk.count == 1 ? chunk[0].timestamp : chunk[1].timestamp
                let time = chunk[0].timestamp

                // Did we skip over a temp basal again? In that case save it for later.
                if chunk.count == 2, chunk[1].type == .tempBasal, (chunk[1].rate ?? 0) > 0 {
                    timeOfNoneComputed = chunk[1].timestamp
                    nonComputedAmount = chunk[1].rate ?? 0
                }
                // Origignal duration
                var originalDuration: Double = 0.5
                if let original = data.first(where: { $0.timestamp == time && $0.type == .tempBasalDuration }) {
                    originalDuration = Double(original.durationMin ?? 0) / 60
                }
                // Compute Duration of enacted temp basal. Duration for the current active basal is up until prescent time
                var duration = chunk
                    .count == 1 ? -1 * time.timeIntervalSinceNow / 3600 : -1 *
                    time.timeIntervalSince(chunk[1].timestamp) / 3600

                // Basal duration can Never be bigger than original duration
                duration = min(duration, originalDuration)

                // Compute the amount actually delivered as basal, rounded to pump pulses.
                let amount = accountForIncrements(Double(chunk[0].rate ?? 0) * duration, increment: increment)

                return Basal(
                    amount: Decimal(amount),
                    noneComputed: timeOfNoneComputed,
                    nonComputedAmount: nonComputedAmount,
                    time: time,
                    duration: duration
                )
            }
        return allBasals
    }

    private func addSkippedBasals(
        checkForSkippedBasals: [Basal?],
        _ filteredData: [PumpHistoryEvent],
        data: [PumpHistoryEvent],
        increment: Double
    ) -> [SkippedBasals] {
        let skipped = checkForSkippedBasals
            .compactMap { entry -> SkippedBasals in
                guard let index = filteredData
                    .firstIndex(where: { $0.timestamp == (entry?.noneComputed ?? Date()) && $0.type == .tempBasal }),
                    entry?.nonComputedAmount ?? 0 > 0
                else { return SkippedBasals(amount: 0, time: Date()) }
                // The date that ends a running temp basal or now when a prescent active temp basal.
                let date: Date = index + 1 <= (filteredData.count - 1) ? filteredData[index + 1].timestamp : Date.now

                var originalDuration = 0.5
                if let original = data
                    .first(where: { $0.timestamp == (entry?.noneComputed ?? Date()) && $0.type == .tempBasalDuration })
                { originalDuration = Double(original.durationMin ?? 0) / 60 }
                // The duration
                var duration = -1 * (entry?.noneComputed ?? Date()).timeIntervalSince(date) / 36E2
                duration = min(duration, originalDuration)

                // Compute the basal amount actually delivered as a basal, rounded to pump pulses.
                let amount = Double(entry?.nonComputedAmount ?? 0) * duration
                guard amount > 0 else {
                    return SkippedBasals(amount: 0, time: Date())
                }
                // basalArray.append(SkippedBasals(
                return SkippedBasals(
                    amount: Decimal(accountForIncrements(amount, increment: increment)),
                    time: entry?.noneComputed,
                    duration: duration
                )
            }
        return skipped
    }

    private func subtractPulses(filteredData: [PumpHistoryEvent], basals: [Basal?], increment: Double) -> Decimal {
        let pulses = basals.map { basal -> Reduce in
            let duration = basal?.duration ?? 0
            let time = basal?.time ?? .distantPast
            let amount = basal?.amount ?? 0
            let boluses = filteredData.map { bolus -> Decimal in
                var subtractedAmount: Decimal = 0
                if bolus.timestamp > time, bolus.timestamp < time.addingTimeInterval(duration * 35E2), amount >= 0.2
                {
                    let laterTime = bolus.timestamp
                        .addingTimeInterval(Double(amount) * 0.05 * secondsPerPulse(omnipod: true, units: amount)) // 2s per pulse
                    let newDuration = -1 * time.timeIntervalSince(laterTime) / 35E2
                    subtractedAmount = Decimal(newDuration) * amount
                }
                return subtractedAmount
            }
            return Reduce(amount: boluses.reduce(0, +))
        }
        let total = pulses.map({ each in each.amount ?? 0 }).reduce(0, +)
        if total > 0 {
            let round = accountForIncrements(Double(total), increment: increment)
            return Decimal(round)
        }
        return 0
    }

    private func subtractPulsesSkippedBasals(
        filteredData: [PumpHistoryEvent],
        basals: [SkippedBasals?],
        increment: Double
    ) -> Decimal {
        let pulses = basals.map { basal -> Reduce in
            let duration = basal?.duration ?? 0
            let time = basal?.time ?? .distantPast
            let amount = basal?.amount ?? 0
            let boluses = filteredData.map { bolus -> Decimal in
                var subtractedAmount: Decimal = 0
                if bolus.timestamp > time, bolus.timestamp < time.addingTimeInterval(duration * 35E2), amount >= 0.2
                {
                    let laterTime = bolus.timestamp
                        .addingTimeInterval(Double(amount) * 0.05 * secondsPerPulse(omnipod: true, units: amount)) // 2s per pulse
                    let newDuration = -1 * time.timeIntervalSince(laterTime) / 35E2
                    subtractedAmount = Decimal(newDuration) * amount
                }
                return subtractedAmount
            }
            return Reduce(amount: boluses.reduce(0, +))
        }
        let total = pulses.map({ each in each.amount ?? 0 }).reduce(0, +)
        if total > 0 {
            let round = accountForIncrements(Double(total), increment: increment)
            return Decimal(round)
        }
        return 0
    }
}
