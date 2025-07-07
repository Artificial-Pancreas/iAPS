import Charts
import Foundation
import SwiftUI

struct LoopsView: View {
    @Binding var loopStatistics: (Int, Int, Double, String)

    var body: some View {
        VStack {
            // Data
            let loops = loopStatistics.0
            let readings = loopStatistics.1
            let percentage = loopStatistics.2

            Text(NSLocalizedString("Loops", comment: "") + " / " + NSLocalizedString("Readings", comment: ""))
                .padding(.bottom, 10).font(.previewHeadline)
                .foregroundStyle(Color.white)
            loopChart(percentage: percentage)

            HStack {
                Text("Average Interval")
                Text(loopStatistics.3)
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.white)

            HStack {
                Text("Readings")
                Text("\(readings)")
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.white)

            HStack {
                Text("Loops")
                Text("\(loops)")
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.white)
        }
        .padding(.top, 20)
        .padding(.bottom, 15)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    func loopChart(percentage: Double) -> some View {
        VStack {
            Chart {
                BarMark(
                    x: .value("LoopPercentage", percentage)
                )
                .foregroundStyle(
                    percentage >= 90 ? Color(.darkGreen) : percentage >= 75 ? .orange : .red
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 4,
                        topTrailingRadius: 4
                    )
                )
                .annotation(position: .overlay) {
                    Text(percentage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " %")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .chartXAxis(.hidden)
            .frame(maxWidth: 200, maxHeight: 30)
        }
    }
}
