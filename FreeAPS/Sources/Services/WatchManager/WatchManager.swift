import Foundation
import WatchConnectivity

protocol WatchManager {}

final class BaseWatchManager: NSObject, WatchManager {
    var session: WCSession

    init(session: WCSession = .default) {
        self.session = session
        super.init()

        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }
}

extension BaseWatchManager: WCSessionDelegate {
    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {}

    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error _: Error?) {
        print("ASDF state \(state.rawValue)")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("ASDF message \(message)")
        session.sendMessage(["message": "It works!"], replyHandler: nil) { _ in
        }
    }
}
