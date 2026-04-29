import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBanner: View {
    let context: ActivityViewContext<LiveActivityAttributes>
    var isWatch: Bool = false

    var body: some View {
        if isWatch {
            watchBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        VStack(spacing: 2) {
            BannerTimestampLabel(context: context)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                WatchIOBCOBDisplay(context: context)

                Spacer()

                WatchGlucoseDisplay(context: context)
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
            .padding(.bottom, 6)
        }
        .privacySensitive()
        .foregroundStyle(.white)
        .background(Color.black)
        .activityBackgroundTint(Color.clear)
    }

    private var bgAndTrend: some View {
        HStack(spacing: 3) {
            Text(context.state.bg)

            if let direction = context.state.direction {
                Text(direction)
                    .scaleEffect(x: 0.7, y: 0.7, anchor: .center).padding(.trailing, -5)
            }
        }
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
