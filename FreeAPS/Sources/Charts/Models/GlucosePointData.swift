import SwiftUI

public struct GlucosePointData: PointData {
    public var id = UUID()
    public let value: Int?
    public let xPosition: CGFloat
    public let yPosition: CGFloat?
}
