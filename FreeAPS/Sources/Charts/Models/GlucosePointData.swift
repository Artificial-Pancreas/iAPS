import SwiftUI

public struct GlucosePointData: PointData {
    public init(id: UUID = UUID(), value: Int? = nil, xPosition: CGFloat, yPosition: CGFloat? = nil) {
        self.id = id
        self.value = value
        self.xPosition = xPosition
        self.yPosition = yPosition
    }

    public var id = UUID()
    public let value: Int?
    public let xPosition: CGFloat
    public let yPosition: CGFloat?
}
