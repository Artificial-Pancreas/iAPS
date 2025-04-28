import Charts
import CoreData
import SwiftUI
import Swinject

struct PredictionView: View {
    @Binding var predictions: Predictions?
    @Binding var units: GlucoseUnits
    @Binding var eventualBG: Decimal
    @Binding var useEventualBG: Bool
    @Binding var target: Decimal
    @Binding var displayPredictions: Bool
    @Binding var currentGlucose: Decimal

    @Environment(\.colorScheme) var colorScheme

    private enum Config {
        static let height: CGFloat = 160
        static let lineWidth: CGFloat = 2
    }

    var body: some View {
        VStack {
            if displayPredictions {
                chart()
            }
            HStack {
                Text("Eventual Glucose")
                Spacer()
                Text(
                    Double(eventualBG)
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(units == .mmolL ? 1 : 0)))
                )
                Text(units.rawValue).foregroundStyle(.secondary)
                Divider()
            }.font(.callout)
        }
    }

    func chart() -> some View {
        // Data Source
        let iob = predictions?.iob ?? [Int]()
        let cob = predictions?.cob ?? [Int]()
        let uam = predictions?.uam ?? [Int]()
        let zt = predictions?.zt ?? [Int]()
        let count = max(iob.count, cob.count, uam.count, zt.count)
        var now = Date.now
        var startIndex = 0
        let conversion = units == .mmolL ? 0.0555 : 1
        // Organize the data needed for prediction chart.
        var data = [ChartData]()
        repeat {
            now = now.addingTimeInterval(5.minutes.timeInterval)
            if startIndex < count {
                let addedData = ChartData(
                    date: now,
                    iob: startIndex < iob.count ? Double(iob[startIndex]) * conversion : 0,
                    zt: startIndex < zt.count ? Double(zt[startIndex]) * conversion : 0,
                    cob: startIndex < cob.count ? Double(cob[startIndex]) * conversion : 0,
                    uam: startIndex < uam.count ? Double(uam[startIndex]) * conversion : 0,
                    id: UUID()
                )
                data.append(addedData)
            }
            startIndex += 1
        } while startIndex < count

        let maximum = max(
            data.map(\.cob).max() ?? 0,
            data.map(\.iob).max() ?? 0,
            data.map(\.uam).max() ?? 0,
            data.map(\.zt).max() ?? 0
        )

        let insulin = [
            GlucoseData(glucose: Double(target), type: "Target", time: Date.now),
            GlucoseData(glucose: Double(eventualBG), type: "Eventual Glucose", time: data.last?.date ?? .distantFuture)
        ]
        let notZeroInsulin = (insulin[1].glucose != insulin[0].glucose) && useEventualBG
        let requiresInsulin = (insulin[1].glucose > insulin[0].glucose) && useEventualBG

        let insulinString = requiresInsulin ? "Insulin" : notZeroInsulin ? "-Insulin" : ""
        let insulinColor: Color = requiresInsulin ? .minus : notZeroInsulin ? .red : .clear

        // Chart
        return Chart(data) {
            // Remove 0 (empty) values
            if $0.iob != 0 {
                LineMark(
                    x: .value("Time", $0.date),
                    y: .value("IOB", $0.iob),
                    series: .value("IOB", "A")
                )
                .foregroundStyle(Color(.insulin))
                .lineStyle(StrokeStyle(lineWidth: Config.lineWidth))
            }
            if $0.uam != 0 {
                LineMark(
                    x: .value("Time", $0.date),
                    y: .value("UAM", $0.uam),
                    series: .value("UAM", "B")
                )
                .foregroundStyle(Color(.UAM))
                .lineStyle(StrokeStyle(lineWidth: Config.lineWidth))
            }
            if $0.cob != 0 {
                LineMark(
                    x: .value("Time", $0.date),
                    y: .value("COB", $0.cob),
                    series: .value("COB", "C")
                )
                .foregroundStyle(Color(.loopYellow))
                .lineStyle(StrokeStyle(lineWidth: Config.lineWidth))
            }
            if $0.zt != 0 {
                LineMark(
                    x: .value("Time", $0.date),
                    y: .value("ZT", $0.zt),
                    series: .value("ZT", "D")
                )
                .foregroundStyle(Color(.ZT))
                .lineStyle(StrokeStyle(lineWidth: Config.lineWidth))
            }

            if notZeroInsulin, useEventualBG {
                ForEach(insulin) { datapoint in
                    AreaMark(
                        x: .value("Time", datapoint.time),
                        yStart: requiresInsulin ? .value("Target", insulin[0].glucose) :
                            .value("Eventual Glucose", datapoint.glucose),
                        yEnd: requiresInsulin ? .value("Eventual Glucose", datapoint.glucose) :
                            .value("Target", insulin[0].glucose)
                    )
                    .foregroundStyle(
                        requiresInsulin ? Color(.minus).opacity(colorScheme == .light ? 0.6 : 0.7) : Color(.red)
                            .opacity(colorScheme == .dark ? 0.6 : 0.75)
                    )
                }
            }
            RuleMark(y: .value("Target", target))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Color(.loopGreen))
        }
        .chartYScale(
            domain: (40 * conversion) ... max(maximum + 20 * conversion, 140 * conversion)
        )
        .frame(minHeight: Config.height)
        .chartForegroundStyleScale([
            "IOB": Color(.insulin),
            "UAM": .uam,
            "COB": Color(.loopYellow),
            "ZT": .zt,
            "Target": Color(.loopGreen),
            insulinString: insulinColor
        ])
        .chartYAxisLabel(NSLocalizedString("Predictions", comment: "") + ", " + units.rawValue, alignment: .center)
    }
}
