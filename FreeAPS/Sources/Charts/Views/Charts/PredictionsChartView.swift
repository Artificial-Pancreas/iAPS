import SwiftUI

public struct PredictionsChartView: View {
    let minValue: Int
    let maxValue: Int
    let maxWidth: CGFloat
    @Binding var data: [PredictionLineData]?
    @Binding var showHours: Int

    public var body: some View {
        ZStack {
            if data != nil {
                ForEach(0 ..< data!.count, id: \.self) { index in
                    HStack {
                        PointChartView(
                            minValue: minValue,
                            maxValue: maxValue,
                            maxWidth: maxWidth,
                            showHours: $showHours,
                            glucoseData: $data[index].values
                        ) { value in
                            PredictionPointView(
                                predictionType: data?[index].type ?? .cob,
                                value: value
                            )
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}
