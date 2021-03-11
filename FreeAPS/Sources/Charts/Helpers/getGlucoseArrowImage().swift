import SwiftUI

func getGlucoseArrowImage(for delta: Double) -> Image {
    let arrowName: String
    switch delta {
    case ..<(-0.6):
        arrowName = "arrow.down"
    case -0.6 ... (-0.1):
        arrowName = "arrow.down.forward"
    case 0.1 ..< 0.6:
        arrowName = "arrow.up.forward"
    case 0.6...:
        arrowName = "arrow.up"
    default:
        arrowName = "arrow.forward"
    }
    return Image(systemName: arrowName)
}
