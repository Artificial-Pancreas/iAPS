import CoreData
import SwiftDate
import SwiftUI

struct StatsView: View {
    @FetchRequest var fetchRequest: FetchedResults<LoopStatRecord>
    @FetchRequest var fetchRequestReadings: FetchedResults<Readings>

    @State var headline: Color = .secondary
    @State var errorReasons: Bool = false

    @Binding var highLimit: Decimal
    @Binding var lowLimit: Decimal
    @Binding var units: GlucoseUnits
    @Binding var overrideUnit: Bool

    private let conversionFactor = 0.0555

    var body: some View {
        VStack(spacing: 10) {
            loops
            Divider()
            hba1c
            Divider()
            bloodGlucose
        }
    }

    init(
        filter: NSDate,
        _ highLimit: Binding<Decimal>,
        _ lowLimit: Binding<Decimal>,
        _ units: Binding<GlucoseUnits>,
        _ overrideUnit: Binding<Bool>
    ) {
        _fetchRequest = FetchRequest<LoopStatRecord>(
            sortDescriptors: [NSSortDescriptor(key: "start", ascending: false)],
            predicate: NSPredicate(format: "start > %@", filter)
        )

        _fetchRequestReadings = FetchRequest<Readings>(
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "glucose > 0 AND date > %@", filter)
        )

        _highLimit = highLimit
        _lowLimit = lowLimit
        _units = units
        _overrideUnit = overrideUnit
    }

    var loops: some View {
        let loops = fetchRequest
        // First loop date
        let previous = (loops.last?.start ?? Date.now).addingTimeInterval(-5.minutes.timeInterval)
        // Time in days
        let days = -1 * previous.timeIntervalSinceNow / 8.64E4
        // Calculations
        let durationArray = loops.compactMap({ each in each.duration })
        let medianDuration = medianCalculationDouble(array: durationArray)
        let successsNR = loops.compactMap({ each in each.loopStatus }).filter({ each in each!.contains("Success") }).count
        let loopCount = loops.compactMap({ each in each.loopStatus }).count
        let successRate: Double? = (Double(successsNR) / max(Double(loopCount), 1)) * 100
        let intervalAverage = -1 * (previous.timeIntervalSinceNow / 60) / max(Double(loopCount), 1)

        // Round
        let loopsPerDay = round(Double(loopCount) / max(days, 1))

        return VStack(spacing: 10) {
            HStack(spacing: 35) {
                VStack(spacing: 5) {
                    Text("Loops").font(.subheadline).foregroundColor(headline)
                    Text(loopsPerDay.formatted())
                }
                VStack(spacing: 5) {
                    Text("Interval").font(.subheadline).foregroundColor(headline)
                    Text(intervalAverage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " min")
                }
                VStack(spacing: 5) {
                    Text("Duration").font(.subheadline).foregroundColor(headline)
                    Text(
                        (medianDuration * 60)
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " s"
                    )
                }
                VStack(spacing: 5) {
                    let succesPercentage = successRate ?? 100
                    HStack {
                        Text("Success").foregroundColor(headline)
                        if succesPercentage != 100 {
                            Image(systemName: "info.circle").foregroundStyle(.blue)
                        }
                    }.font(.subheadline)
                    Text(
                        (succesPercentage / 100)
                            .formatted(.percent.grouping(.never).rounded().precision(.fractionLength(1)))
                    )
                }.onTapGesture {
                    errorReasons.toggle()
                }
            }
            .overlay {
                VStack {
                    if errorReasons {
                        errors(loopCount - successsNR)
                    }
                }
            }
        }
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

    private func errors(_ nonCompleted: Int) -> some View {
        ZStack {
            if nonCompleted > 0 {
                let errors = fetchRequest.compactMap(\.error)
                if errors.isNotEmpty {
                    let mostFrequent = errors.mostFrequent()?.description ?? ""
                    let mostFrequentCount = errors.filter({ $0 == mostFrequent }).count
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray2))
                        .frame(width: 380, height: 200)
                        .shadow(radius: 5)
                        .overlay {
                            ZStack {
                                Text("Success = Started / Completed (loops)")
                                    .padding(.horizontal, 5)
                                    .padding(.top, 20)
                                    .foregroundStyle(.secondary)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                VStack {
                                    Text(
                                        NSLocalizedString("Most Frequent Error", comment: "Loop Statistics pop-up") +
                                            " (\(mostFrequentCount) " +
                                            NSLocalizedString("of", comment: "") +
                                            " \(nonCompleted)):"
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 3)
                                    .bold()
                                    Text(mostFrequent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                        }
                }
            }
        }
        .offset(y: -160)
        .onTapGesture { errorReasons.toggle() }
    }

    var hba1c: some View {
        HStack(spacing: 50) {
            let useUnit: GlucoseUnits = (units == .mmolL && overrideUnit) ? .mgdL :
                (units == .mgdL && overrideUnit || units == .mmolL) ? .mmolL : .mgdL
            let hba1cs = glucoseStats()
            let glucose = fetchRequestReadings
            // First date
            let previous = glucose.last?.date ?? Date()
            // Days
            let numberOfDays = -1 * previous.timeIntervalSinceNow / 8.64E4

            let hba1cString = (
                useUnit == .mmolL ? hba1cs.ifcc
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) : hba1cs.ngsp
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                    + " %"
            )
            VStack(spacing: 5) {
                Text("HbA1C").font(.subheadline).foregroundColor(headline)
                Text(hba1cString)
            }
            VStack(spacing: 5) {
                Text("SD").font(.subheadline).foregroundColor(.secondary)
                Text(
                    hba1cs.sd
                        .formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(units == .mmolL ? 1 : 0))
                        )
                )
            }
            VStack(spacing: 5) {
                Text("CV").font(.subheadline).foregroundColor(.secondary)
                Text(hba1cs.cv.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))))
            }
            VStack(spacing: 5) {
                Text("Days").font(.subheadline).foregroundColor(.secondary)
                Text(numberOfDays.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))))
            }
        }
    }

    var bloodGlucose: some View {
        HStack(spacing: 30) {
            let bgs = glucoseStats()

            let glucose = fetchRequestReadings
            // First date
            let previous = glucose.last?.date ?? Date()
            // Last date (recent)
            let numberOfDays = -1 * previous.timeIntervalSinceNow / 8.64E4

            VStack(spacing: 5) {
                Text(numberOfDays < 1 ? "Readings" : "Readings / 24h").font(.subheadline)
                    .foregroundColor(.secondary)
                Text(bgs.readings.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))))
            }
            VStack(spacing: 5) {
                Text("Average").font(.subheadline).foregroundColor(headline)
                Text(
                    bgs.average
                        .formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(units == .mmolL ? 1 : 0))
                        )
                )
            }
            VStack(spacing: 5) {
                Text("Median").font(.subheadline).foregroundColor(.secondary)
                Text(
                    bgs.median
                        .formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(units == .mmolL ? 1 : 0))
                        )
                )
            }
        }
    }

    private func glucoseStats()
        -> (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
    {
        let glucose = fetchRequestReadings
        // First date
        let previous = glucose.last?.date ?? Date()
        // Last date (recent)
        let current = glucose.first?.date ?? Date()
        // Total time in days
        let numberOfDays = (current - previous).timeInterval / 8.64E4

        let denominator = numberOfDays < 1 ? 1 : numberOfDays

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
            average: glucoseAverage * (units == .mmolL ? conversionFactor : 1),
            median: medianGlucose * (units == .mmolL ? conversionFactor : 1),
            sd: sd * (units == .mmolL ? conversionFactor : 1), cv: cv,
            readings: Double(countReadings) / denominator
        )
        return output
    }

    private func tir() -> [(decimal: Decimal, string: String)] {
        let glucose = fetchRequestReadings
        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let totalReadings = justGlucoseArray.count

        let hyperArray = glucose.filter({ $0.glucose >= Int(highLimit) })
        let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
        let hyperPercentage = Double(hyperReadings) / Double(totalReadings) * 100

        let hypoArray = glucose.filter({ $0.glucose <= Int(lowLimit) })
        let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
        let hypoPercentage = Double(hypoReadings) / Double(totalReadings) * 100

        let tir = 100 - (hypoPercentage + hyperPercentage)

        var array: [(decimal: Decimal, string: String)] = []
        array.append((decimal: Decimal(hypoPercentage), string: "Low"))
        array.append((decimal: Decimal(tir), string: "NormaL"))
        array.append((decimal: Decimal(hyperPercentage), string: "High"))

        return array
    }
}

extension Collection {
    /**
     Returns the most frequent element in the collection.
     */
    func mostFrequent() -> Element? where Element: Hashable {
        reduce(into: [:]) { $0[$1, default: 0] += 1 }.max(by: { $0.1 < $1.1 })?.key
    }
}
