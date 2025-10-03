import LoopKit
import SwiftUI

struct ReservoirView: View {
    let reservoirLevel: Double
    let fillColor: Color
    let maxReservoirLevel: Double

    // mask height to reservoir height ratio
    let maskHeightRatio = 1.0

    let reservoirAspectRatio = 93.0 / 127.0

    func reservoirSize(in frame: CGSize) -> CGSize {
        let frameAspectRatio = frame.width / frame.height
        if frameAspectRatio > reservoirAspectRatio {
            return CGSize(
                width: frame.height * reservoirAspectRatio,
                height: frame.height
            )
        } else {
            return CGSize(
                width: frame.width,
                height: frame.width / reservoirAspectRatio
            )
        }
    }

    var body: some View {
        let reservoirName = maxReservoirLevel == 300 ? "reservoir_300u" : "reservoir_200u"
        ZStack(alignment: Alignment(horizontal: .center, vertical: .center)) {
            GeometryReader { geometry in
                let reservoirSize = reservoirSize(in: geometry.size)
                let frameCenterX = geometry.size.width / 2
                let frameCenterY = geometry.size.height / 2
                let maskHeight = reservoirSize.height * maskHeightRatio
                let fillHeight = maskHeight * (reservoirLevel / maxReservoirLevel)
                let maskOffset = (reservoirSize.height - maskHeight) / 2

                Rectangle()
                    .fill(fillColor)
                    .mask(
                        Image(uiImage: UIImage(
                            named: "\(reservoirName)_mask",
                            in: Bundle(for: MedtrumKitHUDProvider.self),
                            compatibleWith: nil
                        )!)
                            .resizable()
                            .scaledToFit()
                            .frame(height: maskHeight)
                            .position(x: frameCenterX, y: frameCenterY + maskOffset)
                    )
                    .mask(
                        Rectangle()
                            .path(in: CGRect(
                                x: 0,
                                y: frameCenterY + maskHeight / 2 - fillHeight + maskOffset,
                                width: geometry.size.width,
                                height: fillHeight
                            ))
                    )
            }
            Image(uiImage: UIImage(named: reservoirName, in: Bundle(for: MedtrumKitHUDProvider.self), compatibleWith: nil)!)
                .resizable()
                .scaledToFit()
        }
    }
}

#Preview {
    ReservoirView(reservoirLevel: 180, fillColor: .yellow, maxReservoirLevel: 200)
}
