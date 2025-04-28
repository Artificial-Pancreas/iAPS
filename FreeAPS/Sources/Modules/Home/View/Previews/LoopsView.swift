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

            Text(NSLocalizedString("Loops", comment: ""))
                .padding(.bottom, 10).font(.previewHeadline)

            loopChart(percentage: percentage)

            HStack {
                Text("Average Interval")
                Text(loopStatistics.3)
            }.font(.loopFont)

            HStack {
                Text("Readings")
                Text("\(readings)")
            }.font(.loopFont)

            HStack {
                Text("Loops")
                Text("\(loops)")
            }.font(.loopFont)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    func loopChart(percentage: Double) -> some View {
        VStack {
            Chart {
                // Background chart 100 %
                if percentage < 100 {
                    BarMark(
                        xStart: .value("LoopPercentage", percentage - 4),
                        xEnd: .value("Full Bar", 100)
                    )
                    .foregroundStyle(
                        Color(.gray).opacity(0.3)
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 4
                        )
                    )
                }

                // Loops per readings chart
                BarMark(
                    x: .value("LoopPercentage", percentage)
                )
                .foregroundStyle(
                    percentage >= 90 ? Color(.darkGreen) : percentage >= 75 ? .orange : .red
                ).opacity(1)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 4,
                        topTrailingRadius: 4
                    )
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
                        .font(.loopFont)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .chartXAxis(.hidden)
            .frame(maxWidth: 200, maxHeight: 25)
        }
    }
}
