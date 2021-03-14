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
    case .doubleUp,
         .singleUp,
         .tripleUp:
        arrow = up
    case .fortyFiveUp:
        arrow = upForward
    case .flat:
        arrow = forward
    case .fortyFiveDown:
        arrow = downForward
    case .doubleDown,
         .singleDown,
         .tripleDown:
        arrow = down
    case .none,
         .notComputable,
         .rateOutOfRange:
        arrow = error
    }

    return Image(systemName: arrow)
}
