import SwiftUI

public struct GlucoseArrowView: View {
    public init(value: Double, delta: Double) {
        self.value = value
        self.delta = delta
    }

    let value: Double
    let delta: Double

    public var body: some View {
        getGlucoseArrowImage(for: delta)
            .foregroundColor(Color(.systemBlue))
            .informationBarEntryStyle()
    }
}

struct GlucoseArrowView_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseArrowView(value: 11.5, delta: 0.9)
            .frame(
                width: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/,
                height: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/,
                alignment: /*@START_MENU_TOKEN@*/ .center/*@END_MENU_TOKEN@*/
            )
            .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
