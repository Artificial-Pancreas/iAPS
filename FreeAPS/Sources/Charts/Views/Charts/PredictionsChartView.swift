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
                        width: 500,
                        showHours: 1,
                        glucoseData: predictionLine.values
                    )  { value in
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
            type: .COB,
            values: Array(SampleData.sampleData[0...10])
        ),
        PredictionLineData(type: .IOB, values: Array(SampleData.sampleData[1...20])),
        PredictionLineData(
            type: .UAM,
            values: Array(SampleData.sampleData[21...30])
        ),
        PredictionLineData(type: .ZT, values: Array(SampleData.sampleData[31...40]))
    ]

    static var previews: some View {
        ScrollView(.horizontal) {
        PredictionsChartView(data: data, width: 400, showHours: 1)
        }
            .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
