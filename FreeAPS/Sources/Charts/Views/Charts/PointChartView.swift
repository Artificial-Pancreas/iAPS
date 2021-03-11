import SwiftUI

struct PointChartView<PointEntry: View>: View {
    let width: CGFloat
    let showHours: Int
    let glucoseData: [BloodGlucose]
    let pointEntry: (_: Int?) -> PointEntry

    public init(
        width: CGFloat,
        showHours: Int,
        glucoseData: [BloodGlucose],
        point: @escaping (_: Int?) -> PointEntry
    ) {
        self.width = width
        self.showHours = showHours
        self.glucoseData = glucoseData
        pointEntry = point
    }

    public var body: some View {
        GeometryReader { geometry in
            ForEach(
                getGlucosePoints(
                    data: glucoseData,
                    height: geometry.size.height,
                    width: width,
                    showHours: showHours),
                id: \.self
            ) { point in
                pointEntry(point.value)
                    .position(x: point.xPosition, y: point.yPosition ?? 0)
            }
        }
        .frame(width: 1000)
    }
}

private func getGlucosePoints(
    data: [BloodGlucose],
    height: CGFloat,
    width: CGFloat,
    showHours: Int
) -> [GlucosePointData] {
    let values = data.compactMap { $0.sgv }
    
    let maxValue = values.max() ?? 180
    let minValue = values.min() ?? 60
    let firstEntryTime = data
        .compactMap { $0.date }
        .first ?? UInt64(Date().timeIntervalSince1970)
    
    let _ = width / CGFloat(60 * 60 * showHours)

    /// y = mx + b where m = scalingFactor, b = addendum, x = value, y = mapped value
    let scalingFactor = Double(height) / Double(maxValue - minValue)
    let addendum = scalingFactor * Double(maxValue)
    let pointSize: CGFloat = ChartsConfig.glucosePointSize / 2
    let hoursMultiplier: Double = 12

    return data.map { glucose in
        let xPosition = (CGFloat(0) * width / CGFloat(Double(showHours) * hoursMultiplier)) + pointSize
        
        guard let value = glucose.sgv else {
            return GlucosePointData(
                xPosition: xPosition
            )
        }
        return GlucosePointData(
            value: value,
            xPosition: xPosition,
            yPosition: CGFloat(-scalingFactor * Double(value) + addendum)
        )
    }
}

struct PointChartView_Previews: PreviewProvider {
    
    static let data = Array(SampleData.sampleData.prefix(10))

    static var previews: some View {
        ScrollView(.horizontal) {
            PointChartView(
                width: 500,
                showHours: 1,
                glucoseData: data
            ) { value in
                GlucosePointView(value: value)
            }
            .background(Color.gray)
        }
        .preferredColorScheme(/*@START_MENU_TOKEN@*/ .dark/*@END_MENU_TOKEN@*/)
    }
}
