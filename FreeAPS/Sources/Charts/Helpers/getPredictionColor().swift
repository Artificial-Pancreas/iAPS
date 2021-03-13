import SwiftUI

func getPredictionColor(for type: PredictionType, value: Int?) -> Color {
    let color: Color

    switch type {
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
