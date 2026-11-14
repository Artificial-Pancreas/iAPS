import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBanner: View {
    let context: ActivityViewContext<LiveActivityAttributes>
    var isWatch: Bool = false
    var isFullscreen: Bool = false
    var isSupplementalMedium: Bool = false

    var body: some View {
        if isWatch {
            watchBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: isFullscreen ? 12 : 8) {
            HStack(alignment: .center, spacing: 8) {
                BannerLoopCircle(context: context, size: isFullscreen || isSupplementalMedium ? 26 : 22)
                BannerTimestampLabel(context: context)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                eventualGlucose
            }
            ViewThatFits(in: .horizontal) {
                wideMetricsRow
                compactMetricsGrid
            }
        }
        .privacySensitive()
        .padding(.vertical, isFullscreen ? 16 : 10)
        .padding(.horizontal, isFullscreen || isSupplementalMedium ? 20 : 15)
        .foregroundStyle(Color.primary)
        .background(BackgroundStyle.background.opacity(0.4))
        .activityBackgroundTint(Color.clear)
    }

    private var wideMetricsRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            glucoseDisplay
                .frame(maxWidth: .infinity, alignment: .leading)

            metricDisplay(value: context.state.iob, unit: "U", color: .insulin)
            metricDisplay(value: context.state.cob, unit: "g", color: .loopYellow)
        }
    }

    private var compactMetricsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                glucoseDisplay
                    .gridCellColumns(2)
            }
            GridRow {
                metricDisplay(value: context.state.iob, unit: "U", color: .insulin)
                metricDisplay(value: context.state.cob, unit: "g", color: .loopYellow)
            }
        }
    }

    private var glucoseDisplay: some View {
        VStack(alignment: .leading, spacing: 0) {
            bgAndTrend
                .font(isFullscreen || isSupplementalMedium ? .largeTitle : .title)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            changeLabel
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func metricDisplay(value: String, unit: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value)
                .monospacedDigit()
            Text(unit)
                .font(.callout.smallCaps())
        }
        .font(isFullscreen || isSupplementalMedium ? .title2 : .title3)
        .fontWidth(.condensed)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var eventualGlucose: some View {
        HStack(spacing: 4) {
            Text("Eventual")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(context.state.eventual)
                .monospacedDigit()
            Text(
                context.state
                    .mmol ? NSLocalizedString(
                        "mmol/L",
                        comment: "The short unit display string for millimoles of glucose per liter"
                    ) :
                    NSLocalizedString(
                        "mg/dL",
                        comment: "The short unit display string for milligrams of glucose per decilter"
                    )
            )
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fontWidth(.condensed)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
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

                if context.state.watchDelta, !context.state.change.isEmpty, !context.isStale {
                    Text(context.state.change)
                        .font(.system(size: 16))
                        .opacity(0.7)
                }

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
