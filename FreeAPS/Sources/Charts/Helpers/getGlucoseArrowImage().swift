import SwiftUI

func getGlucoseArrowImage(for delta: BloodGlucose.Direction) -> Image {
    let arrow: String
    
    let up = "arrow.up"
    let upForward = "arrow.up.forward"
    let forward = "arrow.forward"
    let downForward = "arrow.down.forward"
    let down = "arrow.down"
    let error = "arrow.left.arrow.right"
    
    switch delta {
    case .tripleUp:
        arrow = up
    case .doubleUp:
        arrow = up
    case .singleUp:
        arrow = up
    case .fortyFiveUp:
        arrow = upForward
    case .flat:
        arrow = forward
    case .fortyFiveDown:
        arrow = downForward
    case .singleDown:
        arrow = down
    case .doubleDown:
        arrow = down
    case .tripleDown:
        arrow = down
    case .none:
        arrow = error
    case .notComputable:
        arrow = error
    case .rateOutOfRange:
        arrow = error
    }
    
    return Image(systemName: arrow)
}
