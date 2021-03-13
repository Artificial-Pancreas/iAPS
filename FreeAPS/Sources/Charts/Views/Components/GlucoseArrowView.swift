import SwiftUI

public struct GlucoseArrowView: View {
    let direction: BloodGlucose.Direction

    public var body: some View {
        getGlucoseArrowImage(for: direction)
            .foregroundColor(Color(.systemBlue))
            .informationBarEntryStyle()
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
