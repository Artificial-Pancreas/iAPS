import Charts
import CoreData
import SwiftUI
import Swinject

struct PredictionView: View {
    @Binding var predictions: Predictions?
    @Binding var units: GlucoseUnits

    var body: some View {
        chart()
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
        // Chart
        return Chart(data) { item in
            // Remove 0 (empty) values
            if item.iob != 0 {
                LineMark(
                    x: .value("Time", item.date),
                    y: .value("IOB", item.iob),
                    series: .value("IOB", "A")
                )
                .foregroundStyle(Color(.insulin))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if item.uam != 0 {
                LineMark(
                    x: .value("Time", item.date),
                    y: .value("UAM", item.uam),
                    series: .value("UAM", "B")
                )
                .foregroundStyle(Color(.UAM))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if item.cob != 0 {
                LineMark(
                    x: .value("Time", item.date),
                    y: .value("COB", item.cob),
                    series: .value("COB", "C")
                )
                .foregroundStyle(Color(.loopYellow))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if item.zt != 0 {
                LineMark(
                    x: .value("Time", item.date),
                    y: .value("ZT", item.zt),
                    series: .value("ZT", "D")
                )
                .foregroundStyle(Color(.ZT))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .frame(minHeight: 150)
        .chartForegroundStyleScale([
            "IOB": Color(.insulin),
            "UAM": Color(.UAM),
            "COB": Color(.loopYellow),
            "ZT": Color(.ZT)
        ])
        .chartYAxisLabel("Glucose (" + units.rawValue + ")")
    }
}
