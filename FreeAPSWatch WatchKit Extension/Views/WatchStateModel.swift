import Foundation
import SwiftUI
import WatchConnectivity

class WatchStateModel: NSObject, ObservableObject {
    var session: WCSession
    @Published var result = ""

    @Published var glucose = "0"
    @Published var trend = "??"
    @Published var delta = "??"
    @Published var lastLoopDate: Date?
    @Published var bolusIncrement: Decimal?
    @Published var maxCOB: Int?
    @Published var maxBolus: Decimal?
    @Published var bolusRecommended: Decimal?
    @Published var iob: Decimal?
    @Published var cob: Decimal?

    init(session: WCSession = .default) {
        self.session = session
        super.init()

        session.delegate = self
        session.activate()
    }

    func addCarbs(_ carbs: Int) {
        session.sendMessage(["addCarbs": carbs], replyHandler: nil) { error in
            print("ASDF: " + error.localizedDescription)
        }
    }

    private func processState(_ state: WatchState) {
        glucose = state.glucose ?? "?"
        trend = state.trend ?? "?"
        delta = state.delta ?? "?"
    }
}

extension WatchStateModel: WCSessionDelegate {
    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error _: Error?) {
        print("WCSession activated: \(state == .activated)")

        session.sendMessage(["active": true], replyHandler: nil) { error in
            print("ASDF: " + error.localizedDescription)
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        if let text = message["message"] as? String {
            DispatchQueue.main.async {
                self.result = text
            }
        }
    }

    func session(_: WCSession, didReceiveMessageData messageData: Data) {
        if let state = try? JSONDecoder().decode(WatchState.self, from: messageData) {
            DispatchQueue.main.async {
                self.processState(state)
            }
        }
    }
}
