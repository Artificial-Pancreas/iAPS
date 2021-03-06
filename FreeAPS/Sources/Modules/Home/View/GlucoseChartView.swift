import CareKitUI
import SwiftUI

struct GlucoseChartView: UIViewRepresentable {
    @Binding var glucose: [BloodGlucose]
    @Binding var suggestion: Suggestion?

    func makeUIView(context _: Context) -> OCKCartesianGraphView {
        let view = OCKCartesianGraphView(type: .scatter)
        makeDataPointsFor(view: view)
        return view
    }

    func updateUIView(_ view: OCKCartesianGraphView, context _: Context) {
        makeDataPointsFor(view: view)
    }

    private func makeDataPointsFor(view: OCKCartesianGraphView) {
        let dataPoints = glucose.map {
            CGPoint(x: CGFloat($0.dateString.timeIntervalSince1970), y: CGFloat($0.sgv ?? 0))
        }
        var data = OCKDataSeries(
            dataPoints: dataPoints,
            title: "BG",
            color: .green
        )
        data.size = 1

        var series = [data]

        let lastDate = glucose.last?.dateString ?? Date()

        if let iob = suggestion?.predictions?.iob {
            let dataPoints = iob.enumerated().map {
                CGPoint(
                    x: CGFloat(lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970),
                    y: CGFloat($1)
                )
            }
            var data = OCKDataSeries(
                dataPoints: dataPoints,
                title: "IOB",
                color: .blue
            )
            data.size = 1
            series.append(data)
        }

        if let zt = suggestion?.predictions?.zt {
            let dataPoints = zt.enumerated().map {
                CGPoint(
                    x: CGFloat(lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970),
                    y: CGFloat($1)
                )
            }
            var data = OCKDataSeries(
                dataPoints: dataPoints,
                title: "ZT",
                color: .cyan
            )
            data.size = 1
            series.append(data)
        }

        if let cob = suggestion?.predictions?.cob {
            let dataPoints = cob.enumerated().map {
                CGPoint(
                    x: CGFloat(lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970),
                    y: CGFloat($1)
                )
            }
            var data = OCKDataSeries(
                dataPoints: dataPoints,
                title: "COB",
                color: .orange
            )
            data.size = 1
            series.append(data)
        }

        if let uam = suggestion?.predictions?.uam {
            let dataPoints = uam.enumerated().map {
                CGPoint(
                    x: CGFloat(lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970),
                    y: CGFloat($1)
                )
            }
            var data = OCKDataSeries(
                dataPoints: dataPoints,
                title: "UAM",
                color: .yellow
            )
            data.size = 1
            series.append(data)
        }

        view.dataSeries = series
    }
}
