import SwiftUI

public struct PredictionsChartView: View {
    var data: [PredictionLineData]?
    let width: CGFloat
    let showHours: Int

    public var body: some View {
        ZStack {
            if let data = data {
                ForEach(data, id: \.self) { predictionLine in
                    PointChartView(
                        minValue: 30,
                        maxValue: 300,
                        width: 500,
                        showHours: 1,
                        glucoseData: predictionLine.values
                    ) { value in
                        PredictionPointView(predictionType: predictionLine.type, value: value)
                    }
                }
            }
        }
    }
}

struct PredictionsChartView_Previews: PreviewProvider {
    static let data = [
        PredictionLineData(
            type: .iob,
            values: Array(SampleData.sampleData[0 ... 10])
        ),
        PredictionLineData(type: .cob, values: Array(SampleData.sampleData[1 ... 20])),
        PredictionLineData(
            type: .uam,
            values: Array(SampleData.sampleData[21 ... 30])
        ),
        PredictionLineData(type: .zt, values: Array(SampleData.sampleData[31 ... 40]))
    ]

    static var previews: some View {
        ScrollView(.horizontal) {
            PredictionsChartView(data: data, width: 400, showHours: 1)
        }
        .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
