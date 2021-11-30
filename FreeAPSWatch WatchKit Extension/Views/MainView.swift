import SwiftDate
import SwiftUI

struct MainView: View {
    private enum Config {
        static let lag: TimeInterval = 30
    }

    @EnvironmentObject var state: WatchStateModel

    @State var isCarbsActive = false
    @State var isTargetsActive = false
    @State var isBolusActive = false
    var body: some View {
        VStack {
            header
            Spacer()
            buttons
        }
        .frame(maxHeight: .infinity)
        .padding()
    }

    var header: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(state.glucose).font(.largeTitle)
                        Text(state.trend)
                    }
                    Text(state.delta).font(.caption2)
                }
                Spacer()

                VStack(spacing: 0) {
                    HStack {
                        Circle().stroke(color, lineWidth: 6).frame(width: 30, height: 30).padding(10)
                    }

                    if state.lastLoopDate != nil {
                        Text(timeString).font(.caption2)
                    } else {
                        Text("--").font(.caption2)
                    }
                }
            }
            Spacer()
            HStack {
                Text("IOB: " + iobFormatter.string(from: (state.iob ?? 0) as NSNumber)! + " U").font(.caption2)
                Spacer()
                Text("COB: " + iobFormatter.string(from: (state.cob ?? 0) as NSNumber)! + " g").font(.caption2)
            }
            Spacer()
        }.padding()
    }

    var buttons: some View {
        HStack {
            NavigationLink {
                CarbsView()
                    .environmentObject(state)
            } label: {
                HStack {
                    Image("carbs", bundle: nil)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.loopGreen)
                }
            }

            NavigationLink {
                EmptyView()
            } label: {
                HStack {
                    Image("target", bundle: nil)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.loopYellow)
                }
            }

            NavigationLink {
                EmptyView()
            } label: {
                HStack {
                    Image("bolus", bundle: nil)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.insulin)
                }
            }
        }
    }

    private var iobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter
    }

    private var timeString: String {
        let minAgo = Int((Date().timeIntervalSince(state.lastLoopDate ?? .distantPast) - Config.lag) / 60) + 1
        if minAgo > 1440 {
            return "--"
        }
        return "\(minAgo) " + NSLocalizedString("min ago", comment: "Minutes ago since last loop")
    }

    private var color: Color {
        guard let lastLoopDate = state.lastLoopDate else {
            return .loopGray
        }
        let delta = Date().timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainView().environmentObject(WatchStateModel())
            MainView().previewDevice("Apple Watch Series 5 - 40mm").environmentObject(WatchStateModel())
        }
    }
}
