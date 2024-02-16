import SwiftUI

public struct BolusProgressViewStyle: ProgressViewStyle {
    @Environment(\.colorScheme) var colorScheme

    public func makeBody(configuration: LinearProgressViewStyle.Configuration) -> some View {
        @State var progress = CGFloat(configuration.fractionCompleted ?? 0)
        ZStack {
            VStack {
                ProgressView(value: progress)
            }
        }.frame(width: 160)
    }
}
