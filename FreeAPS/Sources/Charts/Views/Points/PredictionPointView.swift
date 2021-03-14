import SwiftUI

struct PredictionPointView: View {
    let predictionType: PredictionType
    let value: Int?

    var body: some View {
        Circle()
            .strokeBorder(
                predictionColor,
                lineWidth: 1.5,
                antialiased: true
            )
            .frame(width: ChartsConfig.glucosePointSize, height: ChartsConfig.glucosePointSize)
    }
}

extension PredictionPointView {
    var predictionColor: Color {
        let color: Color

        switch predictionType {
        case .iob:
            color = Color(.systemTeal)
        case .cob:
            color = Color(.systemOrange)
        case .zt:
            color = Color(.systemPink)
        case .uam:
            color = Color(.systemIndigo)
        }

        return color.opacity(value != nil ? 1 : 0)
    }
}

struct PredictionPointView_Previews: PreviewProvider {
    static var previews: some View {
        PredictionPointView(predictionType: .iob, value: 3)
            .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
