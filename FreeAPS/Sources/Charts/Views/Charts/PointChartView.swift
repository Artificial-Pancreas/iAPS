import SwiftUI

struct PointChartView<PointEntry: View>: View {
    let width: CGFloat
    let showHours: Int
    let glucoseData: [BloodGlucose]
    let pointEntry: (_: Int?) -> PointEntry

    public var body: some View {
        GeometryReader { geometry in
            ForEach(
                getGlucosePoints(
                    data: glucoseData,
                    height: geometry.size.height,
                    width: width,
                    showHours: showHours
                ),
                id: \.self
            ) { point in
                pointEntry(point.value)
                    .position(x: point.xPosition, y: point.yPosition ?? 0)
            }
        }
        .frame(width: 10000)
    }
}

private func getGlucosePoints(
    data: [BloodGlucose],
    height: CGFloat,
    width: CGFloat,
    showHours: Int
) -> [GlucosePointData] {
    let values = data.compactMap(\.sgv)

    let maxValue = values.max() ?? 180
    let minValue = values.min() ?? 60
    let firstEntryTime = data
        .map(\.date)
        .first ?? UInt64(Date().timeIntervalSince1970)

    let pointSize: CGFloat = ChartsConfig.glucosePointSize / 2

    /// y = mx + b where m = scalingFactor, b = addendum, x = value, y = mapped value
    let scalingFactor = Double(height - pointSize * 2) / Double(maxValue - minValue)
    let addendum = scalingFactor * Double(maxValue)
    let hoursMultiplier: Double = 14

    return data.map { glucose in
        let xPositionIndex = CGFloat(glucose.date - firstEntryTime) / CGFloat(300 * showHours)

        let xPosition = (xPositionIndex * width / CGFloat(Double(showHours) * hoursMultiplier)) + pointSize

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

struct PointChartView_Previews: PreviewProvider {
    static let sampleData = Array(SampleData.sampleData)

    static let testingData = [
        BloodGlucose(sgv: 3, direction: nil, date: 1_615_179_600, dateString: Date(), filtered: nil, noise: nil, glucose: nil),
        BloodGlucose(sgv: 4, direction: nil, date: 1_615_179_900, dateString: Date(), filtered: nil, noise: nil, glucose: nil),
        BloodGlucose(sgv: 5, direction: nil, date: 1_615_180_200, dateString: Date(), filtered: nil, noise: nil, glucose: nil),
        BloodGlucose(sgv: 6, direction: nil, date: 1_615_180_200, dateString: Date(), filtered: nil, noise: nil, glucose: nil),
        BloodGlucose(sgv: 7, direction: nil, date: 1_615_180_800, dateString: Date(), filtered: nil, noise: nil, glucose: nil),
        BloodGlucose(sgv: 8, direction: nil, date: 1_615_181_300, dateString: Date(), filtered: nil, noise: nil, glucose: nil)
    ]

    static var previews: some View {
        Group {
            ScrollView(.horizontal) {
                PointChartView(
                    width: 500,
                    showHours: 1,
                    glucoseData: testingData
                ) { value in
                    GlucosePointView(value: value)
                }
            }
            .padding(.vertical)

            .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
        }
    }
}
