import SwiftUI

public struct PredictionsChartView: View {
    let minValue: Int
    let maxValue: Int
    let maxWidth: CGFloat
    var data: [PredictionLineData]?
    let showHours: Int

    public var body: some View {
        ZStack {
            if let data = data {
                ForEach(data, id: \.self) { predictionLine in
                    HStack {
                        PointChartView(
                            minValue: minValue,
                            maxValue: maxValue,
                            maxWidth: maxWidth,
                            showHours: showHours,
                            glucoseData: predictionLine.values
                        ) { value in
                            PredictionPointView(predictionType: predictionLine.type, value: value)
                        }
                        Spacer()
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
        PredictionLineData(type: .cob, values: Array(SampleData.sampleData[1 ... 21])),
        PredictionLineData(
            type: .uam,
            values: Array(SampleData.sampleData[21 ... 30])
        ),
        PredictionLineData(type: .zt, values: Array(SampleData.sampleData[31 ... 40]))
    ]

    static var previews: some View {
        ScrollView(.horizontal) {
            PredictionsChartView(minValue: 30, maxValue: 180, maxWidth: 400, data: data, showHours: 1)
        }
        .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
