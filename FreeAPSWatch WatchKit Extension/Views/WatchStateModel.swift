import Foundation
import SwiftUI
import WatchConnectivity

class WatchStateModel: NSObject, ObservableObject {
    var session: WCSession
    @Published var result = ""

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
}

extension WatchStateModel: WCSessionDelegate {
    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error _: Error?) {
        print("ASDF state \(state.rawValue)")
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        if let text = message["message"] as? String {
            DispatchQueue.main.async {
                self.result = text
            }
        }
    }
}
