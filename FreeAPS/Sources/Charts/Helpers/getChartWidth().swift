import SwiftUI

func getChartWidth(for amount: Int, width: CGFloat, showHours: Int) -> CGFloat {
    CGFloat(amount) * width / CGFloat(Double(showHours) * 12) + 2.5
}
