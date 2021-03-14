import SwiftUI

struct MainChartView: View {
    let maxWidth: CGFloat
    @Binding var showHours: Int
    @Binding var glucoseData: [BloodGlucose]
    @Binding var predictionsData: [PredictionLineData]?
    var body: some View {
        let allValues = getAllValues()
        let minValue = allValues.min() ?? 40
        let maxValue = allValues.max() ?? 400

        return HStack {
            PointChartView(
                minValue: minValue,
                maxValue: maxValue,
                maxWidth: maxWidth,
                showHours: $showHours,
                glucoseData: $glucoseData
            ) { value in
                GlucosePointView(value: value)
            }
            PredictionsChartView(
                minValue: minValue,
                maxValue: maxValue,
                maxWidth: maxWidth,
                data: $predictionsData,
                showHours: $showHours
            )
        }
    }
}

extension MainChartView {
    func getAllValues() -> [Int] {
        let glucoseValues = glucoseData.compactMap(\.sgv)
        guard let predictionValues = getPredictionValues() else {
            return glucoseValues
        }
        return glucoseValues + predictionValues
    }

    func getPredictionValues() -> [Int]? {
        if let predictions = predictionsData {
            return predictions.flatMap { prediction in
                prediction.values.compactMap(\.sgv)
            }
        }
        return nil
    }
}

struct MainChartView_Previews: PreviewProvider {
    static let glucoseData = Array(SampleData.sampleData[0 ... 70])
    static let predictionsData = [
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
            MainChartView(maxWidth: 400, showHours: 1, glucoseData: glucoseData, predictionsData: predictionsData)
        }
        .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
