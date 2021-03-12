import SwiftUI

func getPredictionColor(for type: PredictionType, value: Int?) -> Color {
    let color: Color
    
    switch type {
    case .IOB:
        color = Color(.systemTeal)
    case .COB:
        color = Color(.systemOrange)
    case .ZT:
        color = Color(.systemPink)
    case .UAM:
        color = Color(.systemIndigo)
    }
    
    return color.opacity(value != nil ? 1 : 0)
}
