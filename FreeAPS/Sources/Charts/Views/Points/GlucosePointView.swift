import SwiftUI

struct GlucosePointView: View {
    let value: Int?

    var body: some View {
        Circle()
            .foregroundColor(
                Color(.systemBlue)
            )
            .frame(width: ChartsConfig.glucosePointSize, height: ChartsConfig.glucosePointSize)
            .opacity(value != nil ? 1 : 0)
    }
}

struct GlucosePointView_Previews: PreviewProvider {
    static var previews: some View {
        GlucosePointView(value: 3)
            .preferredColorScheme(.dark)
    }
}
