import CareKitUI
import SwiftUI

struct GlucoseChartView: UIViewRepresentable {
    @Binding var glucose: [BloodGlucose]

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
            title: "Glucose",
            color: .green
        )
        data.size = 1
        view.dataSeries = [data]
    }
}
