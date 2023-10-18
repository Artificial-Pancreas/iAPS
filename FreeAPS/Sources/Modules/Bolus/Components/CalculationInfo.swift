import Foundation
import SwiftUI

struct CalculationInfo: View {
    let title: String
    let value: NSNumber
    let unit: String
    let comment1: String
    let calculationInfo: NSNumber
    let calcInfoUnit: String
    let comment2: String

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(
                (formatter.string(from: value as NSNumber) ?? "-") + NSLocalizedString(unit, comment: comment1)
            )
            Spacer()
            Text(
                (formatter.string(from: calculationInfo as NSNumber) ?? "-") + NSLocalizedString(calcInfoUnit, comment: comment2)
            )
        }
    }
}
