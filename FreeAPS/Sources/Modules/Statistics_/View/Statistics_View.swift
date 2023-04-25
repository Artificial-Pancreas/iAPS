import Charts
import CoreData
import SwiftDate
import SwiftUI
import Swinject

struct Statistics_View: View {
    // let resolver: Resolver

    @Environment(\.managedObjectContext) var moc

    @State private var dateFilter = Calendar.current.startOfDay(for: Date()) as NSDate

    /*
     var glucoseToday: NSPredicate? { NSPredicate(format: "date >= %@", Calendar.current.startOfDay(for: Date()) as NSDate) }
     var glucoseWeek: NSPredicate? { NSPredicate(format: "date > %@", Date().addingTimeInterval(-7.days.timeInterval) as NSDate) }
     var glucoseMonth: NSPredicate? { NSPredicate(format: "date > %@", Date().addingTimeInterval(-30.days.timeInterval) as NSDate)}
     var glucose90: NSPredicate? { NSPredicate(format: "date > %@", Date().addingTimeInterval(-90.days.timeInterval) as NSDate) }
      */

    @FetchRequest(
        entity: Readings.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
            format: "date > %@",
            Date().addingTimeInterval(-90.days.timeInterval) as NSDate
        )
    ) var fetchedGlucose: FetchedResults<Readings>

    @FetchRequest(
        entity: Readings.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
            format: "date >= %@", Calendar.current.startOfDay(for: Date()) as NSDate
        )
    ) var fetchedGlucoseDay: FetchedResults<Readings>

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

    @State var paddingAmount: CGFloat? = 2
    @State var headline: Color = .secondary
    @State var selectedState: durationState
    @State var days: Double = 0
    @State var pointSize: CGFloat = 3
    @State var conversionFactor = 0.0555

    @ViewBuilder func stats() -> some View {
        timeInRange
        Divider()
        // header
        // Divider()
        loops
        Divider()
        // Spacer()
        bloodGlucose
        Divider()
        // Spacer()
        // Spacer()
        hba1c
    }

    @ViewBuilder func chart() -> some View {
        glucoseChart
    }

    var glucoseChart: some View {
        Chart {
            ForEach(fetchedGlucoseDay.filter({ $0.glucose > 145 }), id: \.date) { item in
                PointMark(
                    x: .value("Date", item.date ?? Date()),
                    y: .value("Low", Double(item.glucose) * conversionFactor)
                )
                .foregroundStyle(.orange)
                .symbolSize(pointSize)
            }
            ForEach(fetchedGlucoseDay.filter({ $0.glucose >= 70 && $0.glucose <= 145 }), id: \.date) { item in
                PointMark(
                    x: .value("Date", item.date ?? Date()),
                    y: .value("In Range", Double(item.glucose) * conversionFactor)
                )
                .foregroundStyle(.green)
                .symbolSize(pointSize)
            }
            ForEach(fetchedGlucoseDay.filter({ $0.glucose < 70 }), id: \.date) { item in
                PointMark(
                    x: .value("Date", item.date ?? Date()),
                    y: .value("High", Double(item.glucose) * conversionFactor)
                )
                .foregroundStyle(.red)
                .symbolSize(pointSize)
            }
            RuleMark(
                y: .value("Target", 100 * conversionFactor)
            )
            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [10]))
        }
    }

    var header: some View {
        Text(
            selectedState == .total ?
                (
                    numberOfDays
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " days of stored glucose"
                ) :
                ""
        ).foregroundColor(.secondary).padding([.vertical], paddingAmount)
    }

    var loops: some View {
        VStack {
            let loops_ = loopStats(fetchedLoopStats)
            HStack {
                ForEach(0 ..< loops_.count, id: \.self) { index in
                    VStack {
                        if index == 0 {
                            Text(loops_[index].string).foregroundColor(.secondary).padding([.vertical], paddingAmount)
                        } else { Text(loops_[index].string).foregroundColor(.secondary).padding([.vertical], paddingAmount) }
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
        HStack {
            let hba1cs = glucoseStats(fetchedGlucose)
            VStack {
                Text("SD").font(.subheadline).foregroundColor(.secondary).padding([.vertical], paddingAmount)
                HStack {
                    VStack {
                        Text(
                            hba1cs.sd.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                        )
                    }
                }
            }
            VStack {
                Text("HbA1C").font(.subheadline).foregroundColor(headline).padding([.vertical], paddingAmount)
                HStack {
                    VStack {
                        Text(hba1cs.ifcc.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))))
                    }
                }
            }
            VStack {
                Text("CV").font(.subheadline).foregroundColor(.secondary).padding([.vertical], paddingAmount)
                HStack {
                    VStack {
                        Text(
                            hba1cs.cv.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                        )
                    }
                }
            }
        }
    }

    var bloodGlucose: some View {
        VStack {
            HStack {
                let bgs = glucoseStats(fetchedGlucose)
                VStack {
                    HStack {
                        Text("Median").font(.subheadline).foregroundColor(.secondary).padding([.vertical], paddingAmount)
                    }
                    HStack {
                        VStack {
                            Text(
                                bgs.median
                                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                            )
                        }
                    }
                }
                VStack {
                    HStack {
                        Text("Average").font(.subheadline).foregroundColor(headline).padding([.vertical], paddingAmount)
                    }
                    HStack {
                        VStack {
                            Text(
                                bgs.average
                                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                            )
                        }
                    }
                }
                VStack {
                    HStack {
                        Text("Readings").font(.subheadline).foregroundColor(.secondary).padding([.vertical], paddingAmount)
                    }
                    HStack {
                        VStack {
                            Text(
                                bgs.readings.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))
                            )
                        }
                    }
                }
            }
        }
    }

    var timeInRange: some View {
        VStack {
            let TIRs = tir(fetchedGlucose)
            HStack {
                ForEach(0 ..< TIRs.count, id: \.self) { index in
                    VStack {
                        if index == 1 {
                            Text(TIRs[index].string).foregroundColor(.secondary)
                                .padding([.vertical], paddingAmount)
                        } else { Text(TIRs[index].string).foregroundColor(.secondary).padding([.vertical], paddingAmount) }
                        Text(
                            TIRs[index].decimal
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + " %"
                        )
                        .foregroundColor(colorOfGlucose(index))
                    }
                }
            }
        }
    }

    var numberOfDays: Double {
        let endIndex = fetchedGlucose.count - 1
        var days = 0.0

        if endIndex > 0 {
            let firstElementTime = fetchedGlucose.first?.date ?? Date()
            let lastElementTime = fetchedGlucose[endIndex].date ?? Date()
            days = (firstElementTime - lastElementTime).timeInterval / 8.64E4
        }
        return days
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                chart().padding(.horizontal, 10)
                Spacer()
                stats()
                Spacer()
                durationButton(states: durationState.allCases, selectedState: $selectedState)
            }
            .frame(maxWidth: .infinity)
            .padding([.vertical], 40)
            .navigationTitle("Statistics")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
        }
    }

    private func loopStats(_ loops: FetchedResults<LoopStatRecord>) -> [(double: Double, string: String)] {
        guard (loops.first?.start) != nil else { return [] }

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
        medianLoopTime = medianCalculationDouble(array: timeForOneLoopArray)
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
        array.append((double: successRate ?? 100, string: "%"))

        return array
    }

    private func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    private func medianCalculationDouble(array: [Double]) -> Double {
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

    private func glucoseStats(_ glucose_90: FetchedResults<Readings>)
        -> (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
    {
        var conversionFactor: Double = 1
        conversionFactor = 0.0555
        var numberOfDays: Double = 0
        let endIndex = glucose_90.count - 1

        if endIndex > 0 {
            let firstElementTime = glucose_90[0].date ?? Date()
            let lastElementTime = glucose_90[endIndex].date ?? Date()
            numberOfDays = (firstElementTime - lastElementTime).timeInterval / 8.64E4
        }
        var duration = 1
        var denominator: Double = 1

        switch selectedState {
        case .day:
            let minutesSinceMidnight = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current
                .component(.minute, from: Date())
            duration = minutesSinceMidnight
        case .week:
            duration = 7 * 1440
            if numberOfDays > 7 { denominator = 7 } else { denominator = numberOfDays }
        case .month:
            duration = 30 * 1440
            if numberOfDays > 30 { denominator = 30 } else { denominator = numberOfDays }
        case .total:
            duration = 90 * 1440
            if numberOfDays >= 90 { denominator = 90 } else { denominator = numberOfDays }
        }

        let timeAgo = Date().addingTimeInterval(-duration.minutes.timeInterval)
        let glucose = glucose_90.filter({ ($0.date ?? Date()) >= timeAgo })

        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let sumReadings = justGlucoseArray.reduce(0, +)
        let countReadings = justGlucoseArray.count

        let glucoseAverage = Double(sumReadings) / Double(countReadings)
        let medianGlucose = medianCalculation(array: justGlucoseArray)

        var NGSPa1CStatisticValue = 0.0
        var IFCCa1CStatisticValue = 0.0

        if numberOfDays > 0 {
            NGSPa1CStatisticValue = (glucoseAverage + 46.7) / 28.7 // NGSP (%)
            IFCCa1CStatisticValue = 10.929 *
                (NGSPa1CStatisticValue - 2.152) // IFCC (mmol/mol)  A1C(mmol/mol) = 10.929 * (A1C(%) - 2.15)
        }
        var sumOfSquares = 0.0

        for array in justGlucoseArray {
            sumOfSquares += pow(Double(array) - Double(glucoseAverage), 2)
        }
        var sd = 0.0
        var cv = 0.0

        // Avoid division by zero
        if glucoseAverage > 0 {
            sd = sqrt(sumOfSquares / Double(countReadings))
            cv = sd / Double(glucoseAverage) * 100
        }

        var output: (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
        output = (
            ifcc: IFCCa1CStatisticValue,
            ngsp: NGSPa1CStatisticValue,
            average: glucoseAverage * conversionFactor,
            median: medianGlucose * conversionFactor, sd: sd * conversionFactor, cv: cv,
            readings: Double(countReadings) / denominator
        )
        return output
    }

    private func tir(_ glucose_90: FetchedResults<Readings>) -> [(decimal: Decimal, string: String)] {
        var duration = 1

        switch selectedState {
        case .day:
            let minutesSinceMidnight = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current
                .component(.minute, from: Date())
            duration = minutesSinceMidnight
        case .week:
            duration = 7 * 1440
        case .month:
            duration = 30 * 1440
        case .total:
            duration = 90 * 1440
        }

        let hypoLimit = Int16(round(3.9 / 0.0555))
        let hyperLimit = Int16(round(10.0 / 0.0555))

        let timeAgo = Date().addingTimeInterval(-duration.minutes.timeInterval)
        let glucose = glucose_90.filter({ ($0.date ?? Date()) >= timeAgo })

        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let totalReadings = justGlucoseArray.count

        let hyperArray = glucose.filter({ $0.glucose >= hyperLimit })
        let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
        let hyperPercentage = Double(hyperReadings) / Double(totalReadings) * 100

        let hypoArray = glucose.filter({ $0.glucose <= hypoLimit })
        let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
        let hypoPercentage = Double(hypoReadings) / Double(totalReadings) * 100

        let tir = 100 - (hypoPercentage + hyperPercentage)

        var array: [(decimal: Decimal, string: String)] = []
        array.append((decimal: Decimal(hypoPercentage), string: "Low"))
        array.append((decimal: Decimal(tir), string: "NormaL"))
        array.append((decimal: Decimal(hyperPercentage), string: "High"))

        return array
    }

    private func colorOfGlucose(_ index: Int) -> Color {
        let whichIndex = index

        switch whichIndex {
        case 0:
            return .red
        case 1:
            return .green
        case 2:
            return .orange
        default:
            return .primary
        }
    }

    struct StatisticsView_Previews: PreviewProvider {
        static var previews: some View {
            Statistics_View(selectedState: .day)
        }
    }
}
