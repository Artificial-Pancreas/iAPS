import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBanner: View {
    let context: ActivityViewContext<LiveActivityAttributes>
    var isWatch: Bool = false

    private let eventualSymbol = "⇢"

    private let decimalString: String = NumberFormatter().decimalSeparator

    private let dateFormatter: DateFormatter = {
        var formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        if isWatch {
            watchBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        VStack(spacing: 2) {
            ZStack {
                updatedLabel
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                VStack {
                    loop(size: 22)
                    Spacer()
                }.offset(x: 0, y: 2)
                Spacer()
                VStack {
                    bgAndTrend.font(.title)
                    changeLabel
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.7))
                        .offset(x: -12, y: -5)
                }
                Spacer()
                VStack {
                    iob(context: context, size: .expanded).font(.title)
                    Spacer() // emptyText
                }
                Spacer()
                VStack {
                    cob(context: context, size: .expanded).font(.title)
                    Spacer() // emptyText
                }
            }
            HStack {
                Spacer()
                Text(NSLocalizedString("Eventual Glucose", comment: ""))
                Spacer()
                Text(context.state.eventual)
                Text(context.state.mmol ? NSLocalizedString(
                    "mmol/L",
                    comment: "The short unit display string for millimoles of glucose per liter"
                ) : NSLocalizedString(
                    "mg/dL",
                    comment: "The short unit display string for milligrams of glucose per decilter"
                )).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
        .privacySensitive()
        .padding(.vertical, 10).padding(.horizontal, 15)
        // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
        // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
        // The colorScheme environment varaible that is usually used to detect dark mode does NOT work here (it reports false values)
        .foregroundStyle(Color.primary)
        .background(BackgroundStyle.background.opacity(0.4))
        .activityBackgroundTint(Color.clear)
    }

    private var watchBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    HStack(spacing: 0.5) {
                        Text(context.state.iob)
                            .font(.system(size: 19))
                            .tracking(-0.5)
                        Text("U")
                            .font(.system(size: 19).smallCaps())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .fontWidth(.compressed)

                    if context.state.cob != "0" {
                        HStack(spacing: 0.5) {
                            Text(context.state.cob)
                                .font(.system(size: 19))
                                .tracking(-0.5)
                            Text("g")
                                .font(.system(size: 19))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .fontWidth(.compressed)
                    }
                }

                Spacer()

                glucoseDisplayWatch
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                loop(size: 9)
                    .opacity(abs(context.state.loopDate.timeIntervalSinceNow) / 60 <= 8 ? 0.7 : 0.9)
                    .padding(.trailing, 2)
                updatedLabel
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                HStack(spacing: 3) {
                    Text(eventualSymbol)
                        .font(.system(size: 13))
                        .opacity(0.7)
                    Text(context.state.eventual)
                        .font(.system(size: 13))
                        .fontWidth(.condensed)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.bottom, 7)
        }
        .privacySensitive()
        .foregroundStyle(.white)
        .background(Color.black)
        .activityBackgroundTint(Color.clear)
    }

    private var glucoseDisplayWatch: some View {
        HStack(alignment: .center, spacing: 6) {
            let string = context.state.bg
            let decimalSeparator = string.contains(decimalString) ? decimalString : "."
            let decimal = string.components(separatedBy: decimalSeparator)
            if decimal.count > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(decimal[0]).font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(decimalSeparator).font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(decimal[1]).font(.system(size: 20, weight: .semibold, design: .rounded))
                }
            } else {
                Text(string)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
            }

            if let direction = context.state.direction {
                Text(direction)
                    .font(.system(size: 16))
            }
        }
    }

    private var bgAndTrend: some View {
        let spacing: CGFloat = 3

        let stack = HStack(spacing: spacing) {
            Text(context.state.bg)

            if let direction = context.state.direction {
                Text(direction)
                    .scaleEffect(x: 0.7, y: 0.7, anchor: .center).padding(.trailing, -5)
            }
        }
        return stack
    }

    private func iob(context: ActivityViewContext<LiveActivityAttributes>, size _: LiveActivitySize) -> some View {
        HStack(spacing: 0) {
            Text(context.state.iob)
            Text(" U")
        }
        .foregroundStyle(.insulin)
    }

    private func cob(context: ActivityViewContext<LiveActivityAttributes>, size _: LiveActivitySize) -> some View {
        HStack(spacing: 0) {
            Text(context.state.cob)
            Text(" g")
        }
        .foregroundStyle(.loopYellow)
    }

    private func loop(size: CGFloat) -> some View {
        let timeAgo = abs(context.state.loopDate.timeIntervalSinceNow) / 60
        let color: Color = timeAgo > 8 ? .loopYellow : timeAgo > 12 ? .loopRed : .loopGreen
        return LoopActivity(stroke: color, compact: false).frame(width: size)
    }

    private var updatedLabel: Text {
        Text("\(dateFormatter.string(from: context.state.loopDate))")
    }

    @ViewBuilder private var changeLabel: some View {
        if !context.state.change.isEmpty {
            if !context.isStale {
                Text(context.state.change)
            } else {
                Text("old").foregroundStyle(.secondary)
            }
        } else {
            Text("--")
        }
    }
}
