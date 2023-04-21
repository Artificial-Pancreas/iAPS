import CoreData
import SwiftDate
import SwiftUI
import Swinject

struct Statistics_View: View {
    // let resolver: Resolver

    @FetchRequest(
        entity: Readings.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
            format: "date > %@",
            Date().addingTimeInterval(-90.days.timeInterval) as NSDate
        )
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

    @ViewBuilder func stats() -> some View {
        Spacer()
        loops
        Spacer()
        hba1c
        Spacer()
    }

    var loops: some View {
        VStack {
            let loops_ = loopStats(fetchedLoopStats)
            HStack {
                ForEach(0 ..< loops_.count, id: \.self) { index in
                    VStack {
                        Text(loops_[index].string).foregroundColor(.secondary)
                        Text(
                            index == 0 ? loops_[index].double.formatted() : (
                                index == 2 ? loops_[index].double
                                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(2))) :
                                    loops_[index]
                                    .double
                                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                            )
                        )
                    }
                }
            }
        }
    }

    var hba1c: some View {
        VStack {
            let hba1cs = glucoseStats(fetchedGlucose)
            Text("HbA1C").font(.subheadline)
            HStack {
                ForEach(0 ..< hba1cs.count, id: \.self) { index in
                    VStack {
                        Text(hba1cs[index].string).foregroundColor(.secondary)
                        Text(hba1cs[index].decimal.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))))
                    }
                }
            }
        }
    }

    var body: some View {
        VStack {
            stats()
        }
        .navigationTitle("Statistics")
        .navigationBarHidden(true)
        .ignoresSafeArea(.keyboard)
    }

    private func loopStats(_ loops: FetchedResults<LoopStatRecord>) -> [(double: Double, string: String)] {
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

        var array: [(double: Double, string: String)] = []

        array.append((double: Double(successNR + errorNR), string: "Loops"))
        array.append((double: averageLoopTime, string: "Interval"))
        array.append((double: medianLoopTime, string: "Duration"))

        return array
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

    private func glucoseStats(_ glucose_90: FetchedResults<Readings>) -> [(decimal: Decimal, string: String)] {
        var firstElementTime = Date()
        var lastElementTime = Date()
        var conversionFactor: Decimal = 1
        conversionFactor = 0.0555
        var numberOfDays: Double = 0

        let endIndex = glucose_90.count - 1

        if endIndex > 0 {
            firstElementTime = glucose_90[0].date ?? Date()
            lastElementTime = glucose_90[endIndex].date ?? Date()
            numberOfDays = (firstElementTime - lastElementTime).timeInterval / 8.64E4
        }

        let oneDayAgo = Date().addingTimeInterval(-1.days.timeInterval)
        let sevenDaysAgo = Date().addingTimeInterval(-7.days.timeInterval)
        let thirtyDaysAgo = Date().addingTimeInterval(-30.days.timeInterval)

        let glucose = glucose_90.filter({ ($0.date ?? Date()) >= oneDayAgo })
        let glucose_7 = glucose_90.filter({ ($0.date ?? Date()) >= sevenDaysAgo })
        let glucose_30 = glucose_90.filter({ ($0.date ?? Date()) >= thirtyDaysAgo })

        let countReadingsOneday = glucose.compactMap({ each in Int(each.glucose as Int16) }).reduce(0, +)

        let glucoseAverageOneDay = countReadingsOneday / glucose.compactMap({ each in each.glucose as Int16 }).count

        let countReadingsSevenDays = glucose_7.compactMap({ each in Int(each.glucose as Int16) }).reduce(0, +)
        let glucoseAverageSevenDays = countReadingsSevenDays /
            glucose_7.compactMap({ each in each.glucose as Int16 }).count

        let countReadingsThirtyDays = glucose_30.compactMap({ each in Int(each.glucose as Int16) }).reduce(0, +)
        let glucoseAverageThirtyDays = countReadingsThirtyDays /
            glucose_30.compactMap({ each in each.glucose as Int16 }).count

        let countReadingsNinetyDays = glucose_90.compactMap({ each in Int(each.glucose as Int16) }).reduce(0, +)
        let glucoseAverageNinetyDays = countReadingsNinetyDays /
            glucose_90.compactMap({ each in each.glucose as Int16 }).count

        // HbA1c estimation (%, mmol/mol) 1 day
        var NGSPa1CStatisticValue: Decimal = 0.0
        var IFCCa1CStatisticValue: Decimal = 0.0
        if numberOfDays > 0 {
            NGSPa1CStatisticValue = (Decimal(glucoseAverageOneDay) + 46.7) / 28.7 // NGSP (%)
            IFCCa1CStatisticValue = 10.929 *
                (NGSPa1CStatisticValue - 2.152) // IFCC (mmol/mol)  A1C(mmol/mol) = 10.929 * (A1C(%) - 2.15)
        }
        // 7 days
        var NGSPa1CStatisticValue_7: Decimal = 0.0
        var IFCCa1CStatisticValue_7: Decimal = 0.0
        if numberOfDays > 0 {
            NGSPa1CStatisticValue_7 = (Decimal(glucoseAverageSevenDays) + 46.7) / 28.7
            IFCCa1CStatisticValue_7 = 10.929 * (NGSPa1CStatisticValue_7 - 2.152)
        }
        // 30 days
        var NGSPa1CStatisticValue_30: Decimal = 0.0
        var IFCCa1CStatisticValue_30: Decimal = 0.0
        if numberOfDays > 0 {
            NGSPa1CStatisticValue_30 = (Decimal(glucoseAverageThirtyDays) + 46.7) / 28.7
            IFCCa1CStatisticValue_30 = 10.929 * (NGSPa1CStatisticValue_30 - 2.152)
        }
        // 90 days
        var NGSPa1CStatisticValue_90: Decimal = 0.0
        var IFCCa1CStatisticValue_90: Decimal = 0.0
        if numberOfDays > 0 {
            NGSPa1CStatisticValue_90 = (Decimal(glucoseAverageNinetyDays) + 46.7) / 28.7
            IFCCa1CStatisticValue_90 = 10.929 * (NGSPa1CStatisticValue_90 - 2.152)
        }

        var array: [(decimal: Decimal, string: String)] = []

        array.append((decimal: IFCCa1CStatisticValue, string: "24 h"))
        array.append((decimal: IFCCa1CStatisticValue_7, string: "7 days"))
        array.append((decimal: IFCCa1CStatisticValue_30, string: "30 days"))
        array.append((decimal: IFCCa1CStatisticValue_90, string: "90 days"))

        return array
    }

    struct StatisticsView_Previews: PreviewProvider {
        static var previews: some View {
            StatisticsView()
            //    .environmentObject(Icons())
        }
    }
}
