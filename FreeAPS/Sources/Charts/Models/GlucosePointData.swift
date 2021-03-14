import SwiftUI

struct GlucosePointData: PointData {
    var id = UUID()
    let value: Int?
    let xPosition: CGFloat
    let yPosition: CGFloat?
}
