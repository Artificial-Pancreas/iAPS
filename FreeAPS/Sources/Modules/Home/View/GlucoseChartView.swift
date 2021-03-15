import Charts
import SwiftDate
import SwiftUI

extension DateFormatter: AxisValueFormatter {
    public func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        timeStyle = .short
        return string(from: Date(timeIntervalSince1970: value))
    }
}

extension NumberFormatter: AxisValueFormatter {
    public func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        numberStyle = .decimal
        maximumFractionDigits = 1
        return string(from: value as NSNumber)!
    }
}

struct GlucoseChartView: UIViewRepresentable {
    @Binding var glucose: [BloodGlucose]
    @Binding var suggestion: Suggestion?
    let units: GlucoseUnits

    func makeUIView(context _: Context) -> LineChartView {
        let view = LineChartView()
        makeDataPointsFor(view: view)
        view.xAxis.valueFormatter = DateFormatter()
        view.leftAxis.valueFormatter = NumberFormatter()
        view.xAxis.labelPosition = .top
        view.rightAxis.drawLabelsEnabled = false
        view.drawBordersEnabled = true
        view.setScaleEnabled(false)
        view.setVisibleXRangeMaximum(6.hours.timeInterval)
        view.xAxis.granularityEnabled = true
        view.xAxis.granularity = 1.hours.timeInterval
        return view
    }

    func updateUIView(_ view: LineChartView, context _: Context) {
        makeDataPointsFor(view: view)
        view.moveViewToX(glucose.last?.dateString.timeIntervalSince1970 ?? 0)
    }

    private func makeDataPointsFor(view: LineChartView) {
        guard !glucose.isEmpty else {
            return
        }

        let dataPoints = glucose.map {
            ChartDataEntry(
                x: $0.dateString.timeIntervalSince1970,
                y: Double($0.sgv ?? 0) * (units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)
            )
        }

        let data = MyLineChartDataSet(entries: dataPoints, label: "BG")
        data.drawCirclesEnabled = true
        data.circleRadius = 2
        data.setCircleColor(UIColor(named: "LoopGreen")!)
        data.setColor(UIColor(named: "LoopGreen")!)
        data.lineWidth = 0
        data.drawValuesEnabled = false

        var series = [data]

        let lastDate = suggestion?.deliverAt ?? Date()

        if let iob = suggestion?.predictions?.iob {
            let dataPoints = iob.enumerated().map {
                ChartDataEntry(
                    x: lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970,
                    y: Double($1) * (units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)
                )
            }
            let data = MyLineChartDataSet(entries: dataPoints, label: "IOB")
            data.drawCirclesEnabled = true
            data.circleRadius = 2
            data.setCircleColor(.blue)
            data.setColor(.blue)
            data.lineWidth = 0
            data.drawValuesEnabled = false
            series.append(data)
        }

        if let zt = suggestion?.predictions?.zt {
            let dataPoints = zt.enumerated().map {
                ChartDataEntry(
                    x: lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970,
                    y: Double($1) * (units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)
                )
            }
            let data = MyLineChartDataSet(entries: dataPoints, label: "ZT")
            data.drawCirclesEnabled = true
            data.circleRadius = 2
            data.setCircleColor(.cyan)
            data.setColor(.cyan)
            data.lineWidth = 0
            data.drawValuesEnabled = false
            series.append(data)
        }

        if let cob = suggestion?.predictions?.cob {
            let dataPoints = cob.enumerated().map {
                ChartDataEntry(
                    x: lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970,
                    y: Double($1) * (units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)
                )
            }
            let data = MyLineChartDataSet(entries: dataPoints, label: "COB")
            data.drawCirclesEnabled = true
            data.circleRadius = 2
            data.setCircleColor(.orange)
            data.setColor(.orange)
            data.lineWidth = 0
            data.drawValuesEnabled = false
            series.append(data)
        }

        if let uam = suggestion?.predictions?.uam {
            let dataPoints = uam.enumerated().map {
                ChartDataEntry(
                    x: lastDate.addingTimeInterval(Double($0 * 300)).timeIntervalSince1970,
                    y: Double($1) * (units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)
                )
            }
            let data = MyLineChartDataSet(entries: dataPoints, label: "UAM")
            data.drawCirclesEnabled = true
            data.circleRadius = 2
            data.setCircleColor(.yellow)
            data.setColor(.yellow)
            data.lineWidth = 0
            data.drawValuesEnabled = false
            series.append(data)
        }

        view.data = LineChartData(dataSets: series)
    }
}

class MyLineChartDataSet: LineChartDataSet {
    override func entryIndex(x xValue: Double, closestToY yValue: Double, rounding: ChartDataSetRounding) -> Int {
        var closest = partitioningIndex { $0.x >= xValue }
        if closest >= endIndex {
            closest = endIndex - 1
        }

        let closestXValue = self[closest].x

        switch rounding {
        case .up:
            // If rounding up, and found x-value is lower than specified x, and we can go upper...
            if closestXValue < xValue, closest < index(before: endIndex)
            {
                formIndex(after: &closest)
            }

        case .down:
            // If rounding down, and found x-value is upper than specified x, and we can go lower...
            if closestXValue > xValue, closest > startIndex
            {
                formIndex(before: &closest)
            }

        case .closest:
            break
        }

        // Search by closest to y-value
        if !yValue.isNaN
        {
            while closest > startIndex, self[index(before: closest)].x == closestXValue
            {
                formIndex(before: &closest)
            }

            var closestYValue = self[closest].y
            var closestYIndex = closest

            while closest < index(before: endIndex)
            {
                formIndex(after: &closest)
                let value = self[closest]

                if value.x != closestXValue { break }
                if abs(value.y - yValue) <= abs(closestYValue - yValue)
                {
                    closestYValue = yValue
                    closestYIndex = closest
                }
            }

            closest = closestYIndex
        }

        return closest
    }
}
