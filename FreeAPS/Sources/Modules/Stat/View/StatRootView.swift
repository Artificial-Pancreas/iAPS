import Charts
import CoreData
import SwiftDate
import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        // @Environment(\.managedObjectContext) var moc
        @FetchRequest(
            entity: Readings.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
                format: "date >= %@", Calendar.current.startOfDay(for: Date()) as NSDate
            )
        ) var fetchedGlucoseDay: FetchedResults<Readings>

        @FetchRequest(
            entity: Readings.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "date > %@", Date().addingTimeInterval(-24.hours.timeInterval) as NSDate)
        ) var fetchedGlucoseTwentyFourHours: FetchedResults<Readings>

        @FetchRequest(
            entity: Readings.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "date > %@", Date().addingTimeInterval(-7.days.timeInterval) as NSDate)
        ) var fetchedGlucoseWeek: FetchedResults<Readings>

        @FetchRequest(
            entity: Readings.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
                format: "date > %@",
                Date().addingTimeInterval(-30.days.timeInterval) as NSDate
            )
        ) var fetchedGlucoseMonth: FetchedResults<Readings>

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

        enum Duration: String, CaseIterable, Identifiable {
            case Today
            case Day
            case Week
            case Month
            case Total
            var id: Self { self }
        }

        @State private var selectedDuration: Duration = .Today
        @State var paddingAmount: CGFloat? = 10
        @State var headline: Color = .secondary
        @State var days: Double = 0
        @State var pointSize: CGFloat = 3
        @State var conversionFactor = 0.0555

        @ViewBuilder func stats() -> some View {
            bloodGlucose
            Divider()
            tirChart
            Divider()
            hba1c
            Divider()
            loops
        }

        @ViewBuilder func chart() -> some View {
            Text("Statistics").font(.largeTitle).bold().padding(.top, 25)
            switch selectedDuration {
            case .Today:
                glucoseChart
            case .Day:
                glucoseChartTwentyFourHours
            case .Week:
                glucoseChartWeek
            case .Month:
                glucoseChartMonth
            case .Total:
                glucoseChart90
            }
        }

        var body: some View {
            ZStack {
                VStack(alignment: .center, spacing: 8) {
                    chart().padding(.horizontal, 10)
                    Divider()
                    stats()
                    Spacer()
                    Picker("Duration", selection: $selectedDuration) {
                        ForEach(Duration.allCases) { duration in
                            Text(duration.rawValue).tag(Optional(duration))
                        }
                    }.pickerStyle(.segmented)
                }
            }.onAppear(perform: configureView)
        }

        var loops: some View {
            VStack {
                let loops_ = loopStats(fetchedLoopStats)
                HStack {
                    ForEach(0 ..< loops_.count, id: \.self) { index in
                        VStack {
                            Text(loops_[index].string).font(.subheadline).foregroundColor(.secondary)
                            Text(
                                index == 0 ? loops_[index].double.formatted() : (
                                    index == 2 ? loops_[index].double
                                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(2))) :
                                        loops_[index]
                                        .double
                                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                                )
                            )
                        }.padding(.horizontal, 6)
                    }
                }
            }
        }

        var hba1c: some View {
            let useUnit: GlucoseUnits = (state.units == .mmolL && (state.overrideUnit ?? false)) ? .mgdL :
                (state.units == .mgdL && (state.overrideUnit ?? false) || state.units == .mmolL) ? .mmolL : .mgdL
            return HStack {
                let hba1cs = glucoseStats(fetchedGlucose)
                let hba1cString = (
                    useUnit == .mmolL ? hba1cs.ifcc
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) : hba1cs.ngsp
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                        + " %"
                )

                VStack {
                    Text("HbA1C").font(.subheadline).foregroundColor(headline)
                    HStack {
                        VStack {
                            Text(hba1cString)
                        }
                    }
                }.padding([.horizontal], 15)
                VStack {
                    Text("SD").font(.subheadline).foregroundColor(.secondary)
                    HStack {
                        VStack {
                            Text(
                                hba1cs.sd
                                    .formatted(
                                        .number.grouping(.never).rounded()
                                            .precision(.fractionLength(state.units == .mmolL ? 1 : 0))
                                    )
                            )
                        }
                    }
                }.padding([.horizontal], 15)
                VStack {
                    Text("CV").font(.subheadline).foregroundColor(.secondary)
                    HStack {
                        VStack {
                            Text(
                                hba1cs.cv.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))
                            )
                        }
                    }
                }.padding([.horizontal], 15)
                if selectedDuration == .Total {
                    VStack {
                        Text("Days").font(.subheadline).foregroundColor(.secondary)
                        HStack {
                            VStack {
                                Text(numberOfDays.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))))
                            }
                        }
                    }.padding([.horizontal], 15)
                }
            }
        }

        var bloodGlucose: some View {
            VStack {
                HStack {
                    let bgs = glucoseStats(fetchedGlucose)
                    VStack {
                        HStack {
                            Text("Average").font(.subheadline).foregroundColor(headline)
                        }
                        HStack {
                            VStack {
                                Text(
                                    bgs.average
                                        .formatted(
                                            .number.grouping(.never).rounded()
                                                .precision(.fractionLength(state.units == .mmolL ? 1 : 0))
                                        )
                                )
                            }
                        }
                    }
                    VStack {
                        HStack {
                            Text("Median").font(.subheadline).foregroundColor(.secondary)
                        }
                        HStack {
                            VStack {
                                Text(
                                    bgs.median
                                        .formatted(
                                            .number.grouping(.never).rounded()
                                                .precision(.fractionLength(state.units == .mmolL ? 1 : 0))
                                        )
                                )
                            }
                        }
                    }
                    VStack {
                        HStack {
                            Text(selectedDuration == .Today ? "Readings today" : "Readings / 24h").font(.subheadline)
                                .foregroundColor(.secondary)
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

        var tirChart: some View {
            let array = selectedDuration == .Today ? fetchedGlucoseDay : selectedDuration == .Day ?
                fetchedGlucoseTwentyFourHours :
                selectedDuration == .Week ? fetchedGlucoseWeek : selectedDuration == .Month ? fetchedGlucoseMonth :
                selectedDuration ==
                .Total ? fetchedGlucose : fetchedGlucoseDay
            let fetched = tir(array)
            let data: [ShapeModel] = [
                .init(type: "Low", percent: fetched[0].decimal),
                .init(type: "In Range", percent: fetched[1].decimal),
                .init(type: "High", percent: fetched[2].decimal)
            ]

            return VStack(alignment: .center) {
                Chart(data) { shape in
                    BarMark(
                        x: .value("Shape", shape.type),
                        y: .value("Percentage", shape.percent)
                    )
                    .foregroundStyle(by: .value("Group", shape.type))
                    .annotation(position: shape.percent < 5 ? .top : .overlay, alignment: .center) {
                        Text(shape.percent == 0 ? "" : "\(shape.percent, format: .number.precision(.fractionLength(0))) %")
                    }
                }
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartForegroundStyleScale(["Low": .red, "In Range": .green, "High": .orange])
            }
        }

        var glucoseChart: some View {
            let count = fetchedGlucoseDay.count
            let lowLimit = (state.lowLimit ?? 70) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            let highLimit = (state.highLimit ?? 145) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            return Chart {
                ForEach(fetchedGlucoseDay.filter({ $0.glucose > Int(state.highLimit ?? 145) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("High", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(count < 20 ? 30 : 12)
                }
                ForEach(
                    fetchedGlucoseDay
                        .filter({ $0.glucose >= Int(state.lowLimit ?? 70) && $0.glucose <= Int(state.highLimit ?? 145) }),
                    id: \.date
                ) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("In Range", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.green)
                    .symbolSize(count < 20 ? 30 : 12)
                }
                ForEach(fetchedGlucoseDay.filter({ $0.glucose < Int(state.lowLimit ?? 70) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("Low", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.red)
                    .symbolSize(count < 20 ? 30 : 12)
                }
            }
            .chartYScale(domain: [0, state.units == .mmolL ? 17 : 305])
            .chartYAxis {
                AxisMarks(
                    values: [
                        0,
                        lowLimit,
                        highLimit,
                        state.units == .mmolL ? 15 : 270
                    ]
                )
            }
        }

        var glucoseChartTwentyFourHours: some View {
            let count = fetchedGlucoseTwentyFourHours.count
            let lowLimit = (state.lowLimit ?? 70) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            let highLimit = (state.highLimit ?? 145) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            return Chart {
                ForEach(fetchedGlucoseTwentyFourHours.filter({ $0.glucose > Int(state.highLimit ?? 145) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("High", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(count < 20 ? 20 : 10)
                }
                ForEach(
                    fetchedGlucoseTwentyFourHours
                        .filter({ $0.glucose >= Int(state.lowLimit ?? 70) && $0.glucose <= Int(state.highLimit ?? 145) }),
                    id: \.date
                ) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("In Range", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.green)
                    .symbolSize(count < 20 ? 20 : 10)
                }
                ForEach(fetchedGlucoseTwentyFourHours.filter({ $0.glucose < Int(state.lowLimit ?? 70) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("Low", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.red)
                    .symbolSize(count < 20 ? 20 : 10)
                }
                RuleMark(
                    y: .value("Target", 100 * (state.units == .mmolL ? conversionFactor : 1))
                )
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [10]))
            }
            .chartYScale(domain: [0, state.units == .mmolL ? 17 : 305])
            .chartYAxis {
                AxisMarks(
                    values: [
                        0,
                        lowLimit,
                        highLimit,
                        state.units == .mmolL ? 15 : 270
                    ]
                )
            }
        }

        var glucoseChartWeek: some View {
            let lowLimit = (state.lowLimit ?? 70) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            let highLimit = (state.highLimit ?? 145) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            return Chart {
                ForEach(fetchedGlucoseWeek.filter({ $0.glucose > Int(state.highLimit ?? 145) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("Low", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(5)
                }
                ForEach(
                    fetchedGlucoseWeek
                        .filter({ $0.glucose >= Int(state.lowLimit ?? 70) && $0.glucose <= Int(state.highLimit ?? 145) }),
                    id: \.date
                ) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("In Range", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.green)
                    .symbolSize(5)
                }
                ForEach(fetchedGlucoseWeek.filter({ $0.glucose < Int(state.lowLimit ?? 70) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("High", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.red)
                    .symbolSize(5)
                }
                RuleMark(
                    y: .value("Target", 100 * (state.units == .mmolL ? conversionFactor : 1))
                )
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [10]))
            }
            .chartYScale(domain: [0, state.units == .mmolL ? 17 : 305])
            .chartYAxis {
                AxisMarks(
                    values: [
                        0,
                        lowLimit,
                        highLimit,
                        state.units == .mmolL ? 15 : 270
                    ]
                )
            }
        }

        var glucoseChartMonth: some View {
            let lowLimit = (state.lowLimit ?? 70) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            let highLimit = (state.highLimit ?? 145) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            return Chart {
                ForEach(fetchedGlucoseMonth.filter({ $0.glucose > Int(state.highLimit ?? 145) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("Low", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(2)
                }
                ForEach(
                    fetchedGlucoseMonth
                        .filter({ $0.glucose >= Int(state.lowLimit ?? 70) && $0.glucose <= Int(state.highLimit ?? 145) }),
                    id: \.date
                ) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("In Range", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.green)
                    .symbolSize(2)
                }
                ForEach(fetchedGlucoseMonth.filter({ $0.glucose < Int(state.lowLimit ?? 70) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("High", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.red)
                    .symbolSize(2)
                }
                RuleMark(
                    y: .value("Target", 100 * (state.units == .mmolL ? conversionFactor : 1))
                )
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [10]))
            }
            .chartYScale(domain: [0, state.units == .mmolL ? 17 : 305])
            .chartYAxis {
                AxisMarks(
                    values: [
                        0,
                        lowLimit,
                        highLimit,
                        state.units == .mmolL ? 15 : 270
                    ]
                )
            }
        }

        var glucoseChart90: some View {
            let lowLimit = (state.lowLimit ?? 70) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            let highLimit = (state.highLimit ?? 145) * (state.units == .mmolL ? Decimal(conversionFactor) : 1)
            return Chart {
                ForEach(fetchedGlucose.filter({ $0.glucose > Int(state.highLimit ?? 145) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("Low", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(2)
                }
                ForEach(
                    fetchedGlucose
                        .filter({ $0.glucose >= Int(state.lowLimit ?? 70) && $0.glucose <= Int(state.highLimit ?? 145) }),
                    id: \.date
                ) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("In Range", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.green)
                    .symbolSize(2)
                }
                ForEach(fetchedGlucose.filter({ $0.glucose < Int(state.lowLimit ?? 70) }), id: \.date) { item in
                    PointMark(
                        x: .value("Date", item.date ?? Date()),
                        y: .value("High", Double(item.glucose) * (state.units == .mmolL ? conversionFactor : 1))
                    )
                    .foregroundStyle(.red)
                    .symbolSize(2)
                }
                RuleMark(
                    y: .value("Target", 100 * (state.units == .mmolL ? conversionFactor : 1))
                )
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [10]))
            }
            .chartYScale(domain: [0, state.units == .mmolL ? 17 : 305])
            .chartYAxis {
                AxisMarks(
                    values: [
                        0,
                        lowLimit,
                        highLimit,
                        state.units == .mmolL ? 15 : 270
                    ]
                )
            }
        }

        private func loopStats(_ loops: FetchedResults<LoopStatRecord>) -> [(double: Double, string: String)] {
            guard (loops.first?.start) != nil else { return [] }

            var i = 0.0
            var minimumInt = 999.0
            var maximumInt = 0.0
            var timeIntervalLoops = 0.0
            var previousTimeLoop = loops.first?.end ?? Date()
            var timeIntervalLoopArray: [Double] = []

            let durationArray = loops.compactMap({ each in each.duration })
            let durationArrayCount = durationArray.count
            var durationAverage = durationArray.reduce(0, +) / Double(durationArrayCount)

            let medianDuration = medianCalculationDouble(array: durationArray)
            let successsNR = loops.compactMap({ each in each.loopStatus }).filter({ each in each!.contains("Success") }).count
            let errorNR = durationArrayCount - successsNR
            let successRate: Double? = (Double(successsNR) / Double(successsNR + errorNR)) * 100

            for each in loops {
                if let loopEnd = each.end {
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
                    previousTimeLoop = loopEnd
                }
            }

            // Average Loop Interval in minutes
            let timeOfFirstIndex = loops.first?.start ?? Date()
            let lastIndexWithTimestamp = loops.count - 1
            let timeOfLastIndex = loops[lastIndexWithTimestamp].end ?? Date()
            let averageInterval = (timeOfFirstIndex - timeOfLastIndex).timeInterval / 60 / Double(errorNR + successsNR)

            if minimumInt == 999.0 {
                minimumInt = 0.0
            }

            var array: [(double: Double, string: String)] = []

            array.append((double: Double(successsNR + errorNR), string: "Loops"))
            array.append((double: averageInterval, string: "Interval"))
            array.append((double: medianDuration, string: "Duration"))
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
            var numberOfDays: Double = 0
            let endIndex = glucose_90.count - 1

            if endIndex > 0 {
                let firstElementTime = glucose_90[0].date ?? Date()
                let lastElementTime = glucose_90[endIndex].date ?? Date()
                numberOfDays = (firstElementTime - lastElementTime).timeInterval / 8.64E4
            }
            var duration = 1
            var denominator: Double = 1

            switch selectedDuration {
            case .Today:
                let minutesSinceMidnight = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current
                    .component(.minute, from: Date())
                duration = minutesSinceMidnight
                denominator = 1
            case .Day:
                duration = 1 * 1440
                denominator = 1
            case .Week:
                duration = 7 * 1440
                if numberOfDays > 7 { denominator = 7 } else { denominator = numberOfDays }
            case .Month:
                duration = 30 * 1440
                if numberOfDays > 30 { denominator = 30 } else { denominator = numberOfDays }
            case .Total:
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
                average: glucoseAverage * (state.units == .mmolL ? conversionFactor : 1),
                median: medianGlucose * (state.units == .mmolL ? conversionFactor : 1),
                sd: sd * (state.units == .mmolL ? conversionFactor : 1), cv: cv,
                readings: Double(countReadings) / denominator
            )
            return output
        }

        private func tir(_ glucose_90: FetchedResults<Readings>) -> [(decimal: Decimal, string: String)] {
            var duration = 1

            switch selectedDuration {
            case .Today:
                let minutesSinceMidnight = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current
                    .component(.minute, from: Date())
                duration = minutesSinceMidnight
            case .Day:
                duration = 1 * 1440
            case .Week:
                duration = 7 * 1440
            case .Month:
                duration = 30 * 1440
            case .Total:
                duration = 90 * 1440
            }

            let hypoLimit = Int(state.lowLimit ?? 70)
            let hyperLimit = Int(state.highLimit ?? 145)

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
    }
}
