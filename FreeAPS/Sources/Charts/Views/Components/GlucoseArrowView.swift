import SwiftUI

struct GlucoseArrowView: View {
    let direction: BloodGlucose.Direction

    var body: some View {
        arrowImage
            .foregroundColor(Color(.systemBlue))
            .informationBarEntryStyle()
    }
}

extension GlucoseArrowView {
    var arrowImage: Image {
        let arrow: String

        let up = "arrow.up"
        let upForward = "arrow.up.forward"
        let forward = "arrow.forward"
        let downForward = "arrow.down.forward"
        let down = "arrow.down"
        let error = "arrow.left.arrow.right"

        switch direction {
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
}

struct GlucoseArrowView_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseArrowView(direction: .fortyFiveDown)
            .frame(
                width: 100,
                height: 100,
                alignment: .center
            )
            .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
