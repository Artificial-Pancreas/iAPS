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

    @State var tirString = ""
    @State var paddingAmount: CGFloat? = 2
    @State var headline: Color = .teal
    @State var selectedState: durationState

    @ViewBuilder func stats() -> some View {
        Spacer()
        loops
        Spacer()
        bloodGlucose
        Spacer()
        timeInRange
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
                        if index == 0 {
                            Text(loops_[index].string).foregroundColor(headline).padding([.vertical], paddingAmount)
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
                Text("HbA1C (mmol/mol)").font(.subheadline).foregroundColor(headline).padding([.vertical], paddingAmount)
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
                            Text(TIRs[index].string).foregroundColor(headline)
                                .padding([.vertical], paddingAmount)
                        } else { Text(TIRs[index].string).foregroundColor(.secondary).font(.subheadline)
                            .padding([.vertical], paddingAmount) }
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

    var body: some View {
        VStack(spacing: 8) {
            stats()
            durationButton(states: durationState.allCases, selectedState: $selectedState)
        }
        .frame(maxWidth: .infinity)
        .padding([.vertical], 40)
        .navigationTitle("Statistics")
        .navigationBarHidden(true)
        .ignoresSafeArea(.keyboard)
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
        medianLoopTime = medianCalculationDouble(array: timeForOneLoopArray)
        medianInterval = medianCalculationDouble(array: timeIntervalLoopArray)
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
        array.append((double: successRate ?? 100, string: "Success %"))

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
        -> (ifcc: Decimal, ngsp: Decimal, average: Double, median: Double, sd: Double, cv: Double, readings: Int)
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

        switch selectedState {
        case .day:
            duration = 1
        case .week:
            duration = 7
        case .month:
            duration = 30
        case .total:
            duration = 90
        }

        let timeAgo = Date().addingTimeInterval(-duration.days.timeInterval)
        let glucose = glucose_90.filter({ ($0.date ?? Date()) >= timeAgo })

        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let sumReadings = justGlucoseArray.reduce(0, +)

        var countReadings = justGlucoseArray.count

        let glucoseAverage = Double(sumReadings) / Double(countReadings)
        let medianGlucose = medianCalculation(array: justGlucoseArray)

        var NGSPa1CStatisticValue: Decimal = 0.0
        var IFCCa1CStatisticValue: Decimal = 0.0

        if numberOfDays > 0 {
            NGSPa1CStatisticValue = (Decimal(glucoseAverage) + 46.7) / 28.7 // NGSP (%)
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

        var output: (ifcc: Decimal, ngsp: Decimal, average: Double, median: Double, sd: Double, cv: Double, readings: Int)
        output = (
            ifcc: IFCCa1CStatisticValue,
            ngsp: NGSPa1CStatisticValue,
            average: glucoseAverage * conversionFactor,
            median: medianGlucose * conversionFactor, sd: sd * conversionFactor, cv: cv, readings: countReadings
        )
        return output
    }

    private func tir(_ glucose_90: FetchedResults<Readings>) -> [(decimal: Decimal, string: String)] {
        var duration = 1
        switch selectedState {
        case .day:
            duration = 1
        case .week:
            duration = 7
        case .month:
            duration = 30
        case .total:
            duration = 90
        }

        let timeAgo = Date().addingTimeInterval(-duration.days.timeInterval)
        var glucose = glucose_90.filter({ ($0.date ?? Date()) >= timeAgo })

        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let sumReadings = justGlucoseArray.reduce(0, +)
        let totalReadings = justGlucoseArray.count

        let hypoLimit = Int16(round(3.9 / 0.0555))
        let hyperLimit = Int16(round(10.0 / 0.0555))

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
