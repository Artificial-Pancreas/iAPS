import ActivityKit
import SwiftUI
import WidgetKit

struct LiveActivity: Widget {
    let dateFormatter: DateFormatter = {
        var f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    @ViewBuilder func changeLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if !context.state.change.isEmpty {
            if context.isStale {
                Text(context.state.change).foregroundStyle(.primary.opacity(0.5))
                    .strikethrough(pattern: .solid, color: .red.opacity(0.6))
            } else {
                Text(context.state.change)
            }
        } else {
            Text("--")
        }
    }

    func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        let text = Text("Updated: \(dateFormatter.string(from: context.state.date))")
        if context.isStale {
            return text.bold().foregroundStyle(.red)
        } else {
            return text
        }
    }

    func bgAndTrendText(context: ActivityViewContext<LiveActivityAttributes>, space: Bool) -> String {
        var str = context.state.bg
        if let direction = context.state.direction {
            // half width space
            if space {
                str += "\u{2009}"
            }
            _ = str += direction
        }
        return str
    }

    @ViewBuilder func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>, space: Bool) -> some View {
        let str = bgAndTrendText(context: context, space: space)

        if context.isStale {
            Text(str).foregroundStyle(.primary.opacity(0.5)).strikethrough(pattern: .solid, color: .red.opacity(0.6))
        } else {
            Text(str)
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            HStack(spacing: 3) {
                bgAndTrend(context: context, space: true).font(.title)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    changeLabel(context: context).font(.title3)
                    updatedLabel(context: context).font(.caption).foregroundStyle(.primary.opacity(0.7))
                }
            }
            .privacySensitive()
            .padding(.all, 15)
            // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
            // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
            // The colorScheme environment varaible that is usually used to detect dark mode does NOT work here (it reports false values)
            .foregroundStyle(Color.primary)
            .background(BackgroundStyle.background.opacity(0.4))
            .activityBackgroundTint(Color.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    bgAndTrend(context: context, space: true).font(.title).padding(.leading, 5)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    changeLabel(context: context).font(.title).padding(.trailing, 5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                    }
                    .frame(
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
                }
            } compactLeading: {
                bgAndTrend(context: context, space: true).padding(.leading, 5)
            } compactTrailing: {
                changeLabel(context: context).padding(.trailing, 5)
            } minimal: {
                bgAndTrend(context: context, space: false).fontWidth(.compressed)
            }
            .widgetURL(URL(string: "freeaps-x://"))
            .keylineTint(Color.cyan.opacity(0.5))
        }
    }
}

private extension LiveActivityAttributes {
    static var preview: LiveActivityAttributes {
        LiveActivityAttributes(startDate: Date())
    }
}

private extension LiveActivityAttributes.ContentState {
    static var test: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(bg: "000", direction: "↗︎", change: "+7", date: Date())
    }
}

#Preview("Notification", as: .content, using: LiveActivityAttributes.preview) {
    LiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.test
}
