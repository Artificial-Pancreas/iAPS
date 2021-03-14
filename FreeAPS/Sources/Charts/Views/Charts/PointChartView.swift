import SwiftUI

struct PointChartView<PointEntry: View>: View {
    let minValue: Int
    let maxValue: Int
    let maxWidth: CGFloat

    let showHours: Int
    @Binding var glucoseData: [BloodGlucose]

    let pointEntry: (_: Int?) -> PointEntry

    let hoursMultiplier: Double = 12
    let pointSize: CGFloat = ChartsConfig.glucosePointSize / 2

    public var body: some View {
        let firstEntryTime = glucoseData
            .map(\.dateString)
            .first ?? Date()

        var width: CGFloat = 0
        if let lastGlucose = glucoseData.last {
            width = calculateXPosition(glucose: lastGlucose, firstEntryTime: firstEntryTime)
        }

        return GeometryReader { geometry in
            ForEach(
                getGlucosePoints(
                    height: geometry.size.height, firstEntryTime: firstEntryTime
                ),
                id: \.self
            ) { point in
                pointEntry(point.value)
                    .position(x: point.xPosition, y: point.yPosition ?? 0)
            }
        }
        .frame(width: width + pointSize)
    }
}

extension PointChartView {
    func calculateXPosition(glucose: BloodGlucose, firstEntryTime: Date) -> CGFloat {
        let xPositionIndex = CGFloat(DateInterval(start: firstEntryTime, end: glucose.dateString).duration) /
            CGFloat(300)
        return (xPositionIndex * maxWidth / CGFloat(Double(showHours) * hoursMultiplier)) + pointSize
    }

    func getGlucosePoints(
        height: CGFloat,
        firstEntryTime: Date
    ) -> [GlucosePointData] {
        /// y = mx + b where m = scalingFactor, b = addendum, x = value, y = mapped value
        let scalingFactor = Double(height - pointSize * 2) / Double(maxValue - minValue)
        let addendum = scalingFactor * Double(maxValue)

        return glucoseData.map { glucose in

            let xPosition = calculateXPosition(glucose: glucose, firstEntryTime: firstEntryTime)

            guard let value = glucose.sgv else {
                return GlucosePointData(
                    value: nil,
                    xPosition: xPosition,
                    yPosition: nil
                )
            }
            return GlucosePointData(
                value: value,
                xPosition: xPosition,
                yPosition: CGFloat(-scalingFactor * Double(value) + addendum) + pointSize
            )
        }
    }
}
