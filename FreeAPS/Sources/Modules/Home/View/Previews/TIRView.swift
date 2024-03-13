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
        let fetched = previewTir()

        struct TIRinPercent: Identifiable {
            let type: String
            let group: String
            let percentage: Decimal
            let id: UUID
        }

        let separator: Decimal = 4

        var data: [TIRinPercent] = [
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "Very Low",
                    comment: ""
                ),
                percentage: fetched[4].decimal,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "Low",
                    comment: ""
                ),
                percentage: fetched[0].decimal,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString("In Range", comment: ""),
                percentage: fetched[1].decimal,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "High",
                    comment: ""
                ),
                percentage: fetched[2].decimal,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: "Separator",
                percentage: separator,
                id: UUID()
            ),
            TIRinPercent(
                type: "TIR",
                group: NSLocalizedString(
                    "Very High",
                    comment: ""
                ),
                percentage: fetched[3].decimal,
                id: UUID()
            )
        ]

        for index in 0 ..< 3 {
            if data[index].percentage == 0 {
                data.remove(at: index + 1)
            }
        }

        return VStack {
            Text("Time In Range").padding(.bottom, 10).font(.previewHeadline)

            Chart(data) { item in
                BarMark(
                    x: .value("TIR", item.type),
                    y: .value("Percentage", item.percentage),
                    width: .fixed(60)
                )
                .foregroundStyle(by: .value("Group", item.group))
                .annotation(position: .trailing) {
                    if item.group == NSLocalizedString("In Range", comment: ""), item.percentage > 0 {
                        HStack {
                            if item.percentage < 1 {
                                Text("< 1%")
                            } else {
                                Text((tirFormatter.string(from: item.percentage as NSNumber) ?? "") + "%")
                            }
                            Text(item.group)
                        }.font(.previewNormal)
                            .padding(.leading, 10)
                    } else if item.group == NSLocalizedString(
                        "Low",
                        comment: ""
                    ), item.percentage > 0.0 {
                        HStack {
                            if item.percentage < 1 {
                                Text("< 1%")
                            } else {
                                Text((tirFormatter.string(from: item.percentage as NSNumber) ?? "") + "%")
                            }
                            Text(item.group)
                        }
                        .font(.loopFont)
                        .padding(.leading, 10)
                    } else if item.group == NSLocalizedString(
                        "High",
                        comment: ""
                    ), item.percentage > 0 {
                        HStack {
                            if item.percentage < 1 {
                                Text("< 1%")
                            } else {
                                Text((tirFormatter.string(from: item.percentage as NSNumber) ?? "") + "%")
                            }
                            Text(item.group)
                        }
                        .font(.loopFont)
                        .padding(.leading, 10)
                    } else if item.group == NSLocalizedString(
                        "Very High",
                        comment: ""
                    ), item.percentage > 0 {
                        HStack {
                            if item.percentage < 1 {
                                Text("< 1%")
                            } else {
                                Text((tirFormatter.string(from: item.percentage as NSNumber) ?? "") + "%")
                            }
                            Text(item.group)
                        }
                        .offset(x: 0, y: -5)
                        .font(.loopFont)
                        .padding(.leading, 10)
                    } else if item.group == NSLocalizedString(
                        "Very Low",
                        comment: ""
                    ), item.percentage > 0 {
                        HStack {
                            if item.percentage < 1 {
                                Text("< 1%")
                            } else {
                                Text((tirFormatter.string(from: item.percentage as NSNumber) ?? "") + "%")
                            }
                            Text(item.group)
                        }
                        .offset(x: 0, y: 5)
                        .font(.loopFont)
                        .padding(.leading, 10)
                    }
                }
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
                ): .red,
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
            .frame(maxWidth: UIScreen.main.bounds.width / 5)
            .offset(x: -UIScreen.main.bounds.width / 5, y: 0)
        }.frame(maxHeight: 200)
            .padding(.top, 20)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func previewTir() -> [(decimal: Decimal, string: String)] {
        let hypoLimit = Int(lowLimit)
        let hyperLimit = Int(highLimit)

        let glucose = readings

        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let totalReadings = justGlucoseArray.count

        let hyperArray = glucose.filter({ $0.glucose >= hyperLimit })
        let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
        var hyperPercentage = Double(hyperReadings) / Double(totalReadings) * 100

        let hypoArray = glucose.filter({ $0.glucose <= hypoLimit })
        let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
        var hypoPercentage = Double(hypoReadings) / Double(totalReadings) * 100

        let veryHighArray = glucose.filter({ $0.glucose > 197 })
        let veryHighReadings = veryHighArray.compactMap({ each in each.glucose as Int16 }).count
        let veryHighPercentage = Double(veryHighReadings) / Double(totalReadings) * 100

        let veryLowArray = glucose.filter({ $0.glucose < 60 })
        let veryLowReadings = veryLowArray.compactMap({ each in each.glucose as Int16 }).count
        let veryLowPercentage = Double(veryLowReadings) / Double(totalReadings) * 100

        hypoPercentage -= veryLowPercentage
        hyperPercentage -= veryHighPercentage

        let tir = 100 - (hypoPercentage + hyperPercentage + veryHighPercentage + veryLowPercentage)

        var array: [(decimal: Decimal, string: String)] = []
        array.append((decimal: Decimal(hypoPercentage), string: "Low"))
        array.append((decimal: Decimal(tir), string: "NormaL"))
        array.append((decimal: Decimal(hyperPercentage), string: "High"))
        array.append((decimal: Decimal(veryHighPercentage), string: "Very High"))
        array.append((decimal: Decimal(veryLowPercentage), string: "Very Low"))

        return array
    }
}
