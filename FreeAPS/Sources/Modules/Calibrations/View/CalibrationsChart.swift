import SwiftUI

struct CalibrationsChart: View {
    @EnvironmentObject var state: Calibrations.StateModel

    private let maxValue = 400.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Rectangle().fill(Color.secondary)
                    .frame(height: geo.size.width)
                Path { path in
                    let size = geo.size.width
                    path.move(
                        to:
                        CGPoint(
                            x: 0,
                            y: size - state.calibrate(0) / maxValue * geo.size.width
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: size,
                            y: size - state.calibrate(maxValue) / maxValue * geo.size.width
                        )
                    )
                }
                .stroke(.blue, lineWidth: 2)

                ForEach(state.calibrations, id: \.self) { value in
                    Circle().fill(.red)
                        .frame(width: 6, height: 6)
                        .position(
                            x: value.x / maxValue * geo.size.width,
                            y: geo.size.width - (value.y / maxValue * geo.size.width)
                        )
                }
            }
            .frame(height: geo.size.width)
            .clipped()
        }
    }
}
