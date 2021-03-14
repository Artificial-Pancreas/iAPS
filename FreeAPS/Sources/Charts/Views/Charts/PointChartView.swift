import SwiftUI

struct PointChartView<PointEntry: View>: View {
    let minValue: Int
    let maxValue: Int
    let maxWidth: CGFloat

    @Binding var showHours: Int
    @Binding var glucoseData: [BloodGlucose]

    let pointEntry: (_: Int?) -> PointEntry

    let hoursMultiplier: Double = 14
    let pointSize: CGFloat = ChartsConfig.glucosePointSize / 2

    public var body: some View {
        let firstEntryTime = glucoseData
            .map(\.date)
            .first ?? UInt64(Date().timeIntervalSince1970)

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
    func calculateXPosition(glucose: BloodGlucose, firstEntryTime: UInt64) -> CGFloat {
        let xPositionIndex = CGFloat(glucose.date - firstEntryTime) / CGFloat(300 * showHours)
        return (xPositionIndex * maxWidth / CGFloat(Double(showHours) * hoursMultiplier)) + pointSize
    }

    func getGlucosePoints(
        height: CGFloat,
        firstEntryTime: UInt64
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
