import SwiftDate
import SwiftUI
import UIKit

// Pie Animation

var backgroundColor: Color = .clear

struct PieSliceView: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var animatableData: AnimatablePair<Double, Double> {
        get {
            AnimatablePair(startAngle.degrees, endAngle.degrees)
        }
        set {
            startAngle = Angle(degrees: newValue.first)
            endAngle = Angle(degrees: newValue.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

class PieSegmentViewModel: ObservableObject {
    @Published var progress: Double = 0.0

    func updateProgress(to newValue: CGFloat, animate: Bool) {
        if animate {
            withAnimation(.easeInOut(duration: 2.5)) { // Dauer der Animation
                self.progress = Double(newValue)
            }
        } else {
            progress = Double(newValue)
        }
    }
}

struct FillablePieSegment: View {
    @ObservedObject var pieSegmentViewModel: PieSegmentViewModel

    var fillFraction: CGFloat
    var color: Color
    var backgroundColor: Color
    var displayText: String
    var symbolSize: CGFloat
    var symbol: String
    var animateProgress: Bool
    var symbolBackgroundColor: Color = .clear
    var symbolColor: Color = .clear

    let angularGradient = AngularGradient(
        gradient: Gradient(colors: [
            Color.gray.opacity(0.3)
        ]),
        center: .center,
        startAngle: .degrees(0),
        endAngle: .degrees(360)
    )

    var body: some View {
        VStack {
            ZStack {
                PieSliceView(
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + Double(pieSegmentViewModel.progress * 360))
                )
                .fill(color)
                .frame(width: 50, height: 50)
                .opacity(0.5)

                // Symbol-Hintergrund (NEU, 40x40)
                if symbolBackgroundColor != .clear {
                    Circle()
                        .fill(symbolBackgroundColor)
                        .frame(width: 40, height: 40)
                }

                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: symbolSize, height: symbolSize)
                    .foregroundColor(symbolColor)
            }

            Text(displayText)
                .font(.system(size: 15))
                .foregroundColor(.white)
        }
        .offset(y: 10)
        .onAppear {
            pieSegmentViewModel.updateProgress(to: fillFraction, animate: animateProgress)
        }
        .onChange(of: fillFraction) { _, newValue in
            pieSegmentViewModel.updateProgress(to: newValue, animate: true)
        }
    }
}

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
    var backgroundColor: Color

    @StateObject private var pieSegmentViewModel = PieSegmentViewModel()

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack {
            var textColor: Color { // Neue Berechnung für Textfarbe
                guard actualSuggestion?.timestamp != nil else {
                    return .white
                }
                guard manualTempBasal == false else {
                    return .loopManualTemp
                }
                let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

                if delta <= 6.minutes.timeInterval {
                    guard actualSuggestion?.deliverAt != nil else {
                        return .white
                    }
                    return .white
                } else if delta <= 9.minutes.timeInterval {
                    return .yellow
                } else {
                    return .red
                }
            }

            VStack(spacing: 0) {
                ZStack {
                    FillablePieSegment(
                        pieSegmentViewModel: pieSegmentViewModel,
                        fillFraction: min(CGFloat(minutesAgo) / 5.0, 1.0),
                        color: pieColor,
                        backgroundColor: .clear,
                        displayText: "\(minutesAgo)min",
                        symbolSize: 20,
                        symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                        animateProgress: true,
                        symbolBackgroundColor: backgroundColor,
                        symbolColor: color
                    )

                    if isLooping {
                        Circle()
                            .fill(backgroundColor)
                            .frame(width: 40, height: 40)
                    }

                    if isLooping {
                        RotatingArrow(color: color)
                    }
                }
            }
        }
        .onAppear {
            pieSegmentViewModel.updateProgress(to: min(CGFloat(minutesAgo) / 5.0, 1.0), animate: true)
        }
        .onChange(of: minutesAgo) {
            pieSegmentViewModel.updateProgress(to: min(CGFloat(minutesAgo) / 5.0, 1.0), animate: true)
        }
    }

    struct RotatingArrow: View {
        var color: Color
        @State private var rotation: Double = 0

        var body: some View {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundColor(color)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(
                        Animation.linear(duration: 1.0)
                            .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360
                    }
                }
        }
    }

    /*   struct PulsatingCircle: View {
         @State private var scale: CGFloat = 1.0
         @State private var gradientOffset: Double = 0.0

         var body: some View {
             Circle()
                 .fill(
                     AngularGradient(
                         gradient: Gradient(colors: [
                             Color(red: 81 / 255, green: 81 / 255, blue: 81 / 255, opacity: 1.0),
                             Color(red: 255 / 255, green: 255 / 255, blue: 255 / 255, opacity: 1.0)
                         ]),
                         center: .center,
                         angle: .degrees(gradientOffset)
                     )
                 )
                 .frame(width: 50, height: 50)
                 .scaleEffect(scale)
                 .onAppear {
                     /* withAnimation(
                          Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)
                      ) {
                          scale = 1.2
                      }*/ // Pulsierend

                     withAnimation(
                         Animation.linear(duration: 2).repeatForever(autoreverses: false)
                     ) {
                         gradientOffset = 360
                     } // Drehen
                 }
         }
     }*/

    private var color: Color {
        guard actualSuggestion?.timestamp != nil else {
            return .white
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 6.minutes.timeInterval {
            guard actualSuggestion?.deliverAt != nil else {
                return .white
            }
            return .white
        } else if delta <= 9.minutes.timeInterval {
            return .yellow
        } else {
            return .red
        }
    }

    private var minutesAgo: Int {
        let elapsedSeconds = timerDate.timeIntervalSince(lastLoopDate) - Config.lag
        return Int(elapsedSeconds / 60) // Wechselt bei exakt 60 Sekunden auf 1 Minute
    }

    private var pieColor: Color {
        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta < 1.minutes.timeInterval {
            return .white.opacity(0.5) // unter 1 Minute
        } else if delta <= 6.minutes.timeInterval {
            return .white.opacity(0.5) // grün für 1-5 Minuten
        } else if delta < 10.minutes.timeInterval {
            return .white.opacity(0.5) // Gelb für 6-9 Minuten
        } else {
            return .white.opacity(0.5) // Rot ab Minute 10
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
