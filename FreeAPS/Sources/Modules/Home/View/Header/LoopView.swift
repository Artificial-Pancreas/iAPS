import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    private enum Config {
        static let lag: TimeInterval = 30
    }

    @Binding var suggestion: Suggestion?
    @Binding var enactedSuggestion: Suggestion?
    @Binding var closedLoop: Bool
    @Binding var timerDate: Date
    @Binding var isLooping: Bool
    @Binding var lastLoopDate: Date
    @Binding var manualTempBasal: Bool

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) private var fontSize

    var body: some View {
        VStack(spacing: 2) {
            let multiplyForLargeFonts = fontSize > .extraLarge ? 1.1 : 1

            HStack(spacing: 0) {
                Text("i").font(.system(size: 10, design: .rounded)).offset(y: 0.35)
                Text("APS").font(.system(size: 12, design: .rounded))
            }.foregroundStyle(.secondary.opacity(0.5))

            LoopEllipse(stroke: color)
                .frame(width: minutesAgo > 9 ? 60 * multiplyForLargeFonts : 60 * multiplyForLargeFonts, height: 27)
                .overlay {
                    HStack {
                        ZStack {
                            if closedLoop {
                                if !isLooping, actualSuggestion?.timestamp != nil {
                                    if minutesAgo > 999 {
                                        Text("--").font(.caption).padding(.leading, 5).foregroundColor(.secondary)
                                    } else {
                                        let timeString = NSLocalizedString("m", comment: "Minutes ago since last loop")
                                        HStack(spacing: 0) {
                                            Text("\(minutesAgo) ")
                                            Text(timeString).foregroundColor(.secondary)
                                        }.font(.caption)
                                    }
                                }
                                if isLooping {
                                    ProgressView()
                                }
                            } else if !isLooping {
                                Text("Open").font(.caption)
                            }
                        }
                    }.dynamicTypeSize(...DynamicTypeSize.xLarge)
                }
        }.offset(y: 5)
    }

    private var minutesAgo: Int {
        let minAgo = Int((timerDate.timeIntervalSince(lastLoopDate) - Config.lag) / 60) + 1
        return minAgo
    }

    private var color: Color {
        guard actualSuggestion?.timestamp != nil else {
            return .loopGray
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 8.minutes.timeInterval {
            guard actualSuggestion?.deliverAt != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 12.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    private var actualSuggestion: Suggestion? {
        if closedLoop, enactedSuggestion?.recieved == true {
            return enactedSuggestion ?? suggestion
        } else {
            return suggestion
        }
    }
}

extension View {
    func animateForever(
        using animation: Animation = Animation.easeInOut(duration: 1),
        autoreverses: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        let repeated = animation.repeatForever(autoreverses: autoreverses)

        return onAppear {
            withAnimation(repeated) {
                action()
            }
        }
    }
}
