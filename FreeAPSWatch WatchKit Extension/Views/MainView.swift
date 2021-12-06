import HealthKit
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

    private var healthStore = HKHealthStore()
    let heartRateQuantity = HKUnit(from: "count/min")
    @State private var value = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if state.timerDate.timeIntervalSince(state.lastUpdate) > 10 {
                HStack {
                    withAnimation {
                        BlinkingView(count: 5, size: 3)
                            .frame(width: 14, height: 14)
                            .padding(2)
                    }
                    Text("Updating...").font(.caption2).foregroundColor(.secondary)
                }
            }
            VStack {
                header
                Spacer()
                buttons
            }

            if state.isConfirmationViewActive {
                ConfirmationView(success: $state.confirmationSuccess)
                    .background(Rectangle().fill(.black))
            }

            if state.isConfirmationBolusViewActive {
                BolusConfirmationView()
                    .environmentObject(state)
                    .background(Rectangle().fill(.black))
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
        .onReceive(state.timer) { date in
            state.timerDate = date
            state.requestState()
        }
        .onAppear {
            state.requestState()
        }
    }

    var header: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(state.glucose).font(.largeTitle)
                        Text(state.trend)
                    }
                    Text(state.delta).font(.caption2).foregroundColor(.gray)
                }
                Spacer()

                VStack(spacing: 0) {
                    HStack {
                        Circle().stroke(color, lineWidth: 6).frame(width: 30, height: 30).padding(10)
                    }

                    if state.lastLoopDate != nil {
                        Text(timeString).font(.caption2).foregroundColor(.gray)
                    } else {
                        Text("--").font(.caption2).foregroundColor(.gray)
                    }
                }
            }
            Spacer()
            Spacer()
            HStack {
                Text(iobFormatter.string(from: (state.cob ?? 0) as NSNumber)!).font(.caption2)
                Text("g").foregroundColor(.loopGreen)
                Spacer()
                Text(iobFormatter.string(from: (state.iob ?? 0) as NSNumber)!).font(.caption2)
                Text("U").foregroundColor(.insulin)
                Spacer()
                HStack {
                    Text("❤️").font(.system(size: 25))
                    Text("\(value)")
                        .fontWeight(.regular)
                        .font(.system(size: 20)).foregroundColor(Color.red)
                }
            }

            Spacer()
            Spacer()
//            Spacer()
        }.padding()
            .onAppear(perform: start)
    }

    var buttons: some View {
        HStack {
            NavigationLink(isActive: $state.isCarbsViewActive) {
                CarbsView()
                    .environmentObject(state)
            } label: {
                Image("carbs", bundle: nil)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.loopGreen)
            }

            NavigationLink(isActive: $state.isBolusViewActive) {
                BolusView()
                    .environmentObject(state)
            } label: {
                Image("bolus", bundle: nil)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.insulin)
            }

            NavigationLink(isActive: $state.isTempTargetViewActive) {
                TempTargetsView()
                    .environmentObject(state)
            } label: {
                VStack {
                    Image("target", bundle: nil)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.loopYellow)
                    if let until = state.tempTargets.compactMap(\.until).first, until > Date() {
                        Text(until, style: .timer).font(.system(size: 8))
                    }
                }
            }
        }
    }

    func start() {
        autorizeHealthKit()
        startHeartRateQuery(quantityTypeIdentifier: .heartRate)
    }

    func autorizeHealthKit() {
        let healthKitTypes: Set = [
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!
        ]
        healthStore.requestAuthorization(toShare: healthKitTypes, read: healthKitTypes) { _, _ in }
    }

    private func startHeartRateQuery(quantityTypeIdentifier: HKQuantityTypeIdentifier) {
        // 1
        let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
        // 2
        let updateHandler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            _, samples, _, _, _ in
            // 3
            guard let samples = samples as? [HKQuantitySample] else {
                return
            }
            self.process(samples, type: quantityTypeIdentifier)
        }
        // 4
        let query = HKAnchoredObjectQuery(
            type: HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier)!,
            predicate: devicePredicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: updateHandler
        )
        query.updateHandler = updateHandler
        // 5
        healthStore.execute(query)
    }

    private func process(_ samples: [HKQuantitySample], type: HKQuantityTypeIdentifier) {
        var lastHeartRate = 0.0
        for sample in samples {
            if type == .heartRate {
                lastHeartRate = sample.quantity.doubleValue(for: heartRateQuantity)
            }
            value = Int(lastHeartRate)
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
        return "\(minAgo) " + NSLocalizedString("min", comment: "Minutes ago since last loop")
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
