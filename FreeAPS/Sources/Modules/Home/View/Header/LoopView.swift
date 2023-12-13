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

    var body: some View {
        VStack {
            let textColor: Color = .secondary
            HStack {
                ZStack {
                    if !isLooping, actualSuggestion?.timestamp != nil {
                        if minutesAgo > 1440 {
                            Text("Not looping").font(.extraSmall).foregroundColor(textColor).padding(.leading, 5)
                        } /* else {
                         let timeString = "\(minutesAgo) " +
                         NSLocalizedString("min", comment: "Minutes ago since last loop")
                         Text(timeString).font(.extraSmall).foregroundColor(textColor).padding(.leading, 5)
                         } */
                    }
                    if isLooping {
                        ProgressView()
                    }
                }
                if isLooping {
                    Text("looping").font(.extraSmall).padding(.leading, 5).foregroundColor(textColor)
                } else if manualTempBasal {
                    Text("Manual").font(.extraSmall).padding(.leading, 5).foregroundColor(textColor)
                }
            } // .offset(x: 50, y: 0)
            .addButtonBackground()
            .frame(width: 60, height: 30)
            .overlay {
                let timeString = "\(minutesAgo) " +
                    NSLocalizedString("min", comment: "Minutes ago since last loop")
                Text(timeString).font(.extraSmall).foregroundColor(textColor)
            }.shadow(
                color: color.opacity(colorScheme == .dark ? 0.80 : 0.65),
                radius: colorScheme == .dark ? 5 : 5
            )
        }
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
