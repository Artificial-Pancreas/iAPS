import Foundation
import SwiftUI
import WatchConnectivity

class WatchStateModel: NSObject, ObservableObject {
    var session: WCSession
    @Published var result = ""

    @Published var glucose = "00"
    @Published var trend = "→"
    @Published var delta = "+00"
    @Published var lastLoopDate: Date?
    @Published var glucoseDate: Date?
    @Published var bolusIncrement: Decimal?
    @Published var maxCOB: Decimal?
    @Published var maxBolus: Decimal?
    @Published var bolusRecommended: Decimal?
    @Published var carbsRequired: Decimal?
    @Published var iob: Decimal?
    @Published var cob: Decimal?

    init(session: WCSession = .default) {
        self.session = session
        super.init()

        session.delegate = self
        session.activate()
    }

    func addCarbs(_ carbs: Int) {
        session.sendMessage(["addCarbs": carbs], replyHandler: { _ in
            WKInterfaceDevice.current().play(.success)
        }) { error in
            print("ASDF: " + error.localizedDescription)
        }
    }

    private func processState(_ state: WatchState) {
        glucose = state.glucose ?? "?"
        trend = state.trend ?? "?"
        delta = state.delta ?? "?"
        glucoseDate = state.glucoseDate
        lastLoopDate = state.lastLoopDate
        bolusIncrement = state.bolusIncrement
        maxCOB = state.maxCOB
        bolusRecommended = state.bolusRecommended
        carbsRequired = state.carbsRequired
        iob = state.iob
        cob = state.cob
    }
}

extension WatchStateModel: WCSessionDelegate {
    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error _: Error?) {
        print("WCSession activated: \(state == .activated)")
        session.sendMessage([WatchCommandKey.command.rawValue: WatchCommand.stateRequest.rawValue], replyHandler: nil) { error in
            print("WatchStateModel error: " + error.localizedDescription)
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        if let text = message["message"] as? String {
            DispatchQueue.main.async {
                self.result = text
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WCSession Reachability: \(session.isReachable)")
    }

    func session(_: WCSession, didReceiveMessageData messageData: Data) {
        if let state = try? JSONDecoder().decode(WatchState.self, from: messageData) {
            DispatchQueue.main.async {
//                WKInterfaceDevice.current().play(.click)
                self.processState(state)
            }
        }
    }
}
