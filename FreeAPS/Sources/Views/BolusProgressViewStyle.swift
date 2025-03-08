import SwiftUI

public struct BolusProgressViewStyle: ProgressViewStyle {
    @Environment(\.colorScheme) var colorScheme

    public func makeBody(configuration: LinearProgressViewStyle.Configuration) -> some View {
        @State var progress = CGFloat(configuration.fractionCompleted ?? 0)
        ZStack {
            ProgressView(value: progress)
                .tint(Color.insulin)
                .scaleEffect(y: 5.5)
                .frame(width: 250, height: 20)
        }
    }
}
