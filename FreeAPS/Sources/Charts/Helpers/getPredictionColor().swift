import SwiftUI

func getPredictionColor(for type: PredictionType) -> Color {
    switch type {
    case .IOB:
        return Color(.systemTeal)
    case .COB:
        return Color(.systemOrange)
    case .ZT:
        return Color(.systemPink)
    case .UAM:
        return Color(.systemIndigo)
    }
}
