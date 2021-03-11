import SwiftUI

struct PredictionPointView: View {
    let predictionType: PredictionType
    var body: some View {
        Circle()
            .strokeBorder(
                getPredictionColor(for: predictionType),
                lineWidth: 1.5,
                antialiased: true
            )
            .frame(width: ChartsConfig.glucosePointSize, height: ChartsConfig.glucosePointSize)
    }
}

struct PredictionPointView_Previews: PreviewProvider {
    static var previews: some View {
        PredictionPointView(predictionType: .COB)
            .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
