import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBanner: View {
    let context: ActivityViewContext<LiveActivityAttributes>
    var isWatch: Bool = false

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
                BannerTimestampLabel(context: context)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                VStack {
                    BannerLoopCircle(context: context, size: 22)
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
                    iob.font(.title)
                    Spacer()
                }
                Spacer()
                VStack {
                    cob.font(.title)
                    Spacer()
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

            HStack {
                WatchLoopCircleAndTimestamp(context: context)

                Spacer()

                BannerEventualGlucose(context: context)
                    .font(.system(size: 16))
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

    private var iob: some View {
        HStack(spacing: 0) {
            Text(context.state.iob)
            Text(" U")
        }
        .foregroundStyle(.insulin)
    }

    private var cob: some View {
        HStack(spacing: 0) {
            Text(context.state.cob)
            Text(" g")
        }
        .foregroundStyle(.loopYellow)
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
