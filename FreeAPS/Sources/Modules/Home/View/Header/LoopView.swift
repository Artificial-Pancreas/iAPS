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

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 40, weight: .thin)).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: 0, y: 10)
        let textColor: Color = .secondary
        HStack {
            ZStack {
                if !isLooping, actualSuggestion?.timestamp != nil {
                    if minutesAgo > 1440 {
                        Text("--").font(.extraSmall).foregroundColor(textColor).padding(.leading, 5)
                    } else {
                        let timeString = "\(minutesAgo) " +
                            NSLocalizedString("min", comment: "Minutes ago since last loop")
                        Text(timeString).font(.extraSmall).foregroundColor(textColor).padding(.leading, 5)
                    }
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
        }.offset(x: 50, y: 10)
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

        if delta <= 6.minutes.timeInterval {
            guard actualSuggestion?.deliverAt != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    func mask(in rect: CGRect) -> Path {
        var path = Rectangle().path(in: rect)
        if !closedLoop || manualTempBasal {
            path.addPath(Rectangle().path(in: CGRect(x: rect.minX, y: rect.midY - 5, width: rect.width, height: 10)))
        }
        return path
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
