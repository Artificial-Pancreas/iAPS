import Charts
import SwiftUI

struct PreviewChart: View {
    @Binding var readings: [Readings]
    @Binding var lowLimit: Decimal
    @Binding var highLimit: Decimal

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) private var fontSize

    private var tirFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    var body: some View {
        if !readings.isEmpty {
            VStack {
                let padding: CGFloat = 40
                // Prepare the chart data
                let data = prepareData()
                HStack {
                    Text("Today")
                }.padding(.bottom, 15).font(.previewHeadline)

                HStack {
                    Chart(data) { item in
                        BarMark(
                            x: .value("TIR", item.type),
                            y: .value("Percentage", item.percentage),
                            width: .fixed(65)
                        )
                        .foregroundStyle(by: .value("Group", item.group))
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: (item.last || item.percentage == 100) ? 4 : 0,
                                bottomLeadingRadius: (item.first || item.percentage == 100) ? 4 : 0,
                                bottomTrailingRadius: (item.first || item.percentage == 100) ? 4 : 0,
                                topTrailingRadius: (item.last || item.percentage == 100) ? 4 : 0
                            )
                        )
                    }
                    .chartForegroundStyleScale([
                        NSLocalizedString(
                            "Low",
                            comment: ""
                        ): .red,
                        NSLocalizedString("In Range", comment: ""): .darkGreen,
                        NSLocalizedString(
                            "High",
                            comment: ""
                        ): .yellow,
                        NSLocalizedString(
                            "Very High",
                            comment: ""
                        ): .darkRed,
                        NSLocalizedString(
                            "Very Low",
                            comment: ""
                        ): .darkRed,
                        "Separator": colorScheme == .dark ? .black : .white
                    ])
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartLegend(.hidden)
                    .padding(.bottom, 15)
                    .padding(.leading, padding)
                    .frame(maxWidth: (UIScreen.main.bounds.width / 5) + padding)

                    sumView(data).offset(x: 0, y: -7)
                }

            }.frame(maxHeight: 180)
                .padding(.top, 20)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }

    @ViewBuilder private func sumView(_ data: [TIRinPercent]) -> some View {
        let entries = data.reversed().filter { $0.group != "Separator" }
        let padding: CGFloat = entries.count == 5 ? 4 : 35 / CGFloat(entries.count)
        Grid {
            ForEach(entries) { entry in
                if entry.group != "Separator" {
                    GridRow(alignment: .firstTextBaseline) {
                        if entry.percentage != 0 {
                            HStack {
                                Text((tirFormatter.string(for: entry.percentage) ?? "") + "%")
                                Text(entry.group)
                            }.font(
                                entry.group == NSLocalizedString("In Range", comment: "") ? .previewHeadline : .previewSmall
                            )
                            .foregroundStyle(
                                entry
                                    .group == NSLocalizedString("In Range", comment: "") ? .primary : .secondary
                            )
                            .padding(
                                .bottom,
                                (entries.count > 1 && entry.group != entries[entries.count - 1].group) ? padding : 0
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.medium)
    }

    private func previewTir() -> [(double: Double, string: String)] {
        let hypoLimit = Int(lowLimit)
        let hyperLimit = Int(highLimit)
        let glucose = readings
        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let totalReadings = justGlucoseArray.count
        let hyperArray = glucose.filter({ $0.glucose >= hyperLimit })
        let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
        var hyperPercentage = round(Double(hyperReadings) / Double(totalReadings) * 100)
        let hypoArray = glucose.filter({ $0.glucose <= hypoLimit })
        let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
        var hypoPercentage = round(Double(hypoReadings) / Double(totalReadings) * 100)
        let veryHighArray = glucose.filter({ $0.glucose > 197 })
        let veryHighReadings = veryHighArray.compactMap({ each in each.glucose as Int16 }).count
        let veryHighPercentage = round(Double(veryHighReadings) / Double(totalReadings) * 100)
        let veryLowArray = glucose.filter({ $0.glucose < 60 })
        let veryLowReadings = veryLowArray.compactMap({ each in each.glucose as Int16 }).count
        let veryLowPercentage = round(Double(veryLowReadings) / Double(totalReadings) * 100)

        hypoPercentage -= veryLowPercentage
        hyperPercentage -= veryHighPercentage

        let tir = round(100 - (hypoPercentage + hyperPercentage + veryHighPercentage + veryLowPercentage))

        var array: [(double: Double, string: String)] = []
        array.append((double: hypoPercentage, string: "Low"))
        array.append((double: tir, string: "NormaL"))
        array.append((double: hyperPercentage, string: "High"))
        array.append((double: veryHighPercentage, string: "Very High"))
        array.append((double: veryLowPercentage, string: "Very Low"))

        return array
    }

    private func prepareData() -> [TIRinPercent] {
        let fetched = previewTir()
        let separator: Double = 2
        var data: [TIRinPercent] = [
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "Very Low",
                    comment: ""
                ),
                percentage: fetched[4].double,
                id: UUID(),
                offset: -5,
                first: true,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID(),
                offset: 0,
                first: false,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "Low",
                    comment: ""
                ),
                percentage: fetched[0].double,
                id: UUID(),
                offset: -10,
                first: false,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID(),
                offset: 0,
                first: false,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString("In Range", comment: ""),
                percentage: fetched[1].double,
                id: UUID(),
                offset: 0,
                first: false,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID(),
                offset: 0,
                first: false,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "High",
                    comment: ""
                ),
                percentage: fetched[2].double,
                id: UUID(),
                offset: 10,
                first: false,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID(),
                offset: 0,
                first: false,
                last: false
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "Very High",
                    comment: ""
                ),
                percentage: fetched[3].double,
                id: UUID(),
                offset: 5,
                first: false,
                last: true
            )
        ]

        // Remove separators when needed
        for index in 0 ..< data.count - 2 {
            if index < data.count - 1 {
                if data[index].percentage == 0 {
                    if index + 1 < data.count {
                        data.remove(at: index + 1)
                    } else { data.remove(at: data.count - 1) }
                }
            }
        }

        if data.last?.group == "Separator" || (data.last?.percentage ?? 0) <= 0 {
            data = data.dropLast()
            // data.remove(at: data.count - 1)
        }

        // Remove double separators
        var c = false
        for index in 0 ..< data.count - 1 {
            if data[index].group == "Separator" {
                if c {
                    data.remove(at: index)
                }
                c = true
            } else { c = false }
        }

        data.removeAll(where: { $0.percentage <= 0 })

        // Update properties?
        if (data.last?.percentage ?? 0) > 0, data.last?.group != "Separator" {
            data[data.count - 1].last = true
        } else {
            data = data.dropLast()
            data[data.count - 1].last = true
        }

        data[0].first = true
        data[data.count - 1].last = true

        return data
    }
}

struct TIRinPercent: Identifiable {
    let type: String
    let group: String
    let percentage: Double
    let id: UUID
    let offset: CGFloat
    var first: Bool
    var last: Bool
}
