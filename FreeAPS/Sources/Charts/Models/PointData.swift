import Foundation
import SwiftUI

public protocol PointData: Identifiable, Hashable {
    var id: UUID { get }
    var value: Int? { get }
    var xPosition: CGFloat { get }
    var yPosition: CGFloat? { get }
}
