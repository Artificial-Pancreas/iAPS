import CoreData
import SwiftDate
import SwiftUI
import Swinject

struct Statistics_View: View {
    // let resolver: Resolver
    
    @FetchRequest(
        entity: Readings.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
    ) var fetchedGlucose: FetchedResults<Readings>

    @FetchRequest(
        entity: TDD.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
    ) var fetchedTDD: FetchedResults<TDD>

    @FetchRequest(
        entity: LoopStatRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "start", ascending: false)], predicate: NSPredicate(
            format: "start > %@",
            Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
        )
    ) var fetchedLoopStats: FetchedResults<LoopStatRecord>

    @FetchRequest(
        entity: InsulinDistribution.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
    ) var fetchedInsulin: FetchedResults<InsulinDistribution>

    var body: some View {
        return VStack {
            let loops = loopStats(fetchedLoopStats)
            HStack {
                ForEach(0 ..< loops.count, id: \.self) { index in
                    Text(loops[index]).foregroundColor(.secondary)
                }
            }
        }
    }

    private func loopStats(_ loops: FetchedResults<LoopStatRecord>) -> [String] {
        guard let stats = loops.first?.start else { return [] }

        var i = 0.0
        var successRate: Double?
        var successNR = 0
        var errorNR = 0
        var minimumInt = 999.0
        var maximumInt = 0.0
        var minimumLoopTime = 9999.0
        var maximumLoopTime = 0.0
        var timeIntervalLoops = 0.0
        var previousTimeLoop = loops.first?.end ?? Date()
        var timeForOneLoop = 0.0
        var averageLoopTime = 0.0
        var timeForOneLoopArray: [Double] = []
        var medianLoopTime = 0.0
        var timeIntervalLoopArray: [Double] = []
        var medianInterval = 0.0
        var averageIntervalLoops = 0.0
        var averageLoopDuration = 0.0

        for each in loops {
            if let loopEnd = each.end {
                let loopDuration = each.duration

                if each.loopStatus!.contains("Success") {
                    successNR += 1
                } else {
                    errorNR += 1
                }

                i += 1
                timeIntervalLoops = (previousTimeLoop - (each.start ?? previousTimeLoop)).timeInterval / 60

                if timeIntervalLoops > 0.0, i != 1 {
                    timeIntervalLoopArray.append(timeIntervalLoops)
                }
                if timeIntervalLoops > maximumInt {
                    maximumInt = timeIntervalLoops
                }
                if timeIntervalLoops < minimumInt, i != 1 {
                    minimumInt = timeIntervalLoops
                }
                timeForOneLoop = loopDuration
                timeForOneLoopArray.append(timeForOneLoop)

                if timeForOneLoop >= maximumLoopTime, timeForOneLoop != 0.0 {
                    maximumLoopTime = timeForOneLoop
                }
                if timeForOneLoop <= minimumLoopTime, timeForOneLoop != 0.0 {
                    minimumLoopTime = timeForOneLoop
                }
                previousTimeLoop = loopEnd
            }
        }

        successRate = (Double(successNR) / Double(i)) * 100

        // Average Loop Interval in minutes
        let timeOfFirstIndex = loops.first?.start ?? Date()
        let lastIndexWithTimestamp = loops.count - 1
        let timeOfLastIndex = loops[lastIndexWithTimestamp].end ?? Date()
        averageLoopTime = (timeOfFirstIndex - timeOfLastIndex).timeInterval / 60 / Double(errorNR + successNR)

        // Median values
        medianLoopTime = medianCalculation(array: timeForOneLoopArray)
        medianInterval = medianCalculation(array: timeIntervalLoopArray)
        // Average time interval between loops
        averageIntervalLoops = timeIntervalLoopArray.reduce(0, +) / Double(timeIntervalLoopArray.count)
        // Average loop duration
        averageLoopDuration = timeForOneLoopArray.reduce(0, +) / Double(timeForOneLoopArray.count)

        if minimumInt == 999.0 {
            minimumInt = 0.0
        }
        if minimumLoopTime == 9999.0 {
            minimumLoopTime = 0.0
        }

        var string = [String]()
        string.append(NSLocalizedString("Loops", comment: "") + ": " + "\(successNR + errorNR)")
        string
            .append(
                NSLocalizedString("Interval", comment: "") + ": " +
                    "\(averageLoopTime.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))))"
            )
        string
            .append(
                NSLocalizedString("Duration", comment: "") + ": " +
                    "\(medianLoopTime.formatted(.number.grouping(.never).rounded().precision(.fractionLength(2))))"
            )

        return string
    }

    private func medianCalculation(array: [Double]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    struct StatisticsView_Previews: PreviewProvider {
        static var previews: some View {
            StatisticsView()
            //    .environmentObject(Icons())
        }
    }
}
