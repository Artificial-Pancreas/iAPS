import SwiftUI

struct PredictionPointView: View {
    let predictionType: PredictionType
    let value: Int?

    var body: some View {
        Circle()
            .strokeBorder(
                getPredictionColor(for: predictionType, value: value),
                lineWidth: 1.5,
                antialiased: true
            )
            .frame(width: ChartsConfig.glucosePointSize, height: ChartsConfig.glucosePointSize)
    }
}

struct PredictionPointView_Previews: PreviewProvider {
    static var previews: some View {
        PredictionPointView(predictionType: .iob, value: 3)
            .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
