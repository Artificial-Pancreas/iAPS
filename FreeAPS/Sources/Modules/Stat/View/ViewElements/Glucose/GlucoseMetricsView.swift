import CoreData
import SwiftUI

struct GlucoseMetricsView: View {
    let units: GlucoseUnits
    let overrideUnit: Bool
    let glucose: FetchedResults<Readings>

    private let conversionFactor = 0.0555

    var body: some View {
        let useUnit: GlucoseUnits = (units == .mmolL && overrideUnit) ? .mgdL :
            (units == .mgdL && overrideUnit || units == .mmolL) ? .mmolL : .mgdL

        let stats = calculateGlucoseStatistics()

        let earliestDate = glucose.last?.date ?? Date()
        let latestDate = glucose.first?.date ?? Date()
        let totalDays = latestDate.timeIntervalSince(earliestDate) / 86400

        let hba1cString = useUnit == .mmolL
            ? stats.ifcc.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
            : stats.ngsp.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "%"

        let sdString = units == .mgdL
            ? stats.sd.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))
            : stats.sd.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))

        let cvString = stats.cv.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "%"

        let daysString = totalDays.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))

        HStack {
            StatChartUtils.statView(title: NSLocalizedString("eA1c", comment: ""), value: hba1cString)
            Spacer()
            StatChartUtils.statView(
                title: NSLocalizedString("SD", comment: ""),
                value: sdString
            )
            Spacer()
            StatChartUtils.statView(title: NSLocalizedString("CV", comment: ""), value: cvString)
            Spacer()
            StatChartUtils.statView(
                title: NSLocalizedString("Days", comment: ""),
                value: daysString
            )
        }
    }

    private func calculateGlucoseStatistics()
        -> (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double)
    {
        let glucoseValues = glucose.compactMap { Int($0.glucose as Int16) }
        let totalReadings = glucoseValues.count

        guard totalReadings > 1 else {
            return (ifcc: 0, ngsp: 0, average: 0, median: 0, sd: 0, cv: 0)
        }

        let earliestDate = glucose.last?.date ?? Date()
        let latestDate = glucose.first?.date ?? Date()
        let totalDays = latestDate.timeIntervalSince(earliestDate) / 86400

        let sumOfReadings = glucoseValues.reduce(0, +)
        let meanGlucose = Double(sumOfReadings) / Double(totalReadings)
        let medianGlucose = StatChartUtils.medianCalculation(array: glucoseValues)

        var eA1cNGSP = 0.0
        var eA1cIFCC = 0.0

        if totalDays > 0 {
            eA1cNGSP = (meanGlucose + 46.7) / 28.7
            eA1cIFCC = 10.929 * (eA1cNGSP - 2.152)
        }

        let sumOfSquaredDifferences = glucoseValues.reduce(0.0) { sum, value in
            sum + pow(Double(value) - meanGlucose, 2)
        }
        let standardDeviation = sqrt(sumOfSquaredDifferences / Double(totalReadings - 1))
        let coefficientOfVariation = meanGlucose > 0 ? (standardDeviation / meanGlucose) * 100 : 0.0

        return (
            ifcc: eA1cIFCC,
            ngsp: eA1cNGSP,
            average: units == .mmolL ? meanGlucose * conversionFactor : meanGlucose,
            median: units == .mmolL ? medianGlucose * conversionFactor : medianGlucose,
            sd: units == .mmolL ? standardDeviation * conversionFactor : standardDeviation,
            cv: coefficientOfVariation
        )
    }
}
