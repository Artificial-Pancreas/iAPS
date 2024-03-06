import Charts
import Foundation
import SwiftUI

struct LoopsView: View {
    @Binding var fetchedReadings: [Readings]
    @Binding var fetchedLoops: [LoopStatRecord]

    var body: some View {
        VStack {
            // Data
            let loops = fetchedLoops.compactMap({ each in each.duration }).count
            let readings = fetchedReadings.compactMap({ each in each.glucose }).count
            let percentage = Double(loops) / Double(readings) * 100

            Text("Loops / Readings").padding(.bottom, 10).font(.previewHeadline)

            loopChart(percentage: percentage)

            HStack {
                Text("Average Interval")
                let average = -1 * (DateFilter().today.timeIntervalSinceNow / 60) /
                    Double(loops)
                Text(average.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " min")
            }.font(.loopFont)

            HStack {
                Text("Readings")
                Text("\(fetchedReadings.compactMap({ each in each.glucose }).count)")
            }.font(.loopFont)

            HStack {
                Text("Loops")
                Text("\(fetchedLoops.compactMap({ each in each.duration }).count)")
            }.font(.loopFont)
        }
        .padding(.top, 20)
        .padding(.bottom, 15)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
