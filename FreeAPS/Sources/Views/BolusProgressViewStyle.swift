import SwiftUI

public struct BolusProgressViewStyle: ProgressViewStyle {
    public func makeBody(configuration: LinearProgressViewStyle.Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 6.0)
                .opacity(0.3)
                .foregroundColor(.secondary)
                .frame(width: 16, height: 16)

            Circle()
                .trim(from: 0.0, to: CGFloat(configuration.fractionCompleted ?? 0))
                .stroke(style: StrokeStyle(lineWidth: 6.0, lineCap: .butt, lineJoin: .round))
                .foregroundColor(.insulin)
                .rotationEffect(Angle(degrees: -90))
                .frame(width: 16, height: 16)
        }.frame(width: 30, height: 30)
    }
}
