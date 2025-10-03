import LocalAuthentication

class DeactivatePatchViewModel: ObservableObject {
    @Published var isDeactivating = false
    @Published var deactivationError = ""
    @Published var is300u = false

    private let nextStep: () -> Void
    private let pumpManager: MedtrumPumpManager?
    init(_ pumpManager: MedtrumPumpManager?, _ nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep

        guard let pumpManager = self.pumpManager else {
            return
        }

        is300u = pumpManager.state.pumpName.contains("300U")
    }

    func deactivate() {
        #if targetEnvironment(simulator)
            authenticate { success in
                DispatchQueue.main.async {
                    guard success else {
                        self.deactivationError = LocalizedString("Authentication failure", comment: "auth failed")
                        return
                    }

                    if let pumpManager = self.pumpManager {
                        pumpManager.state.previousPatch = PreviousPatch(
                            patchId: pumpManager.state.patchId,
                            lastStateRaw: pumpManager.state.pumpState.rawValue,
                            lastSyncAt: pumpManager.state.lastSync,
                            battery: pumpManager.state.battery,
                            activatedAt: pumpManager.state.patchActivatedAt,
                            deactivatedAt: Date.now
                        )

                        pumpManager.state.patchId = Data()
                        pumpManager.state.sessionToken = Data()
                        pumpManager.state.pumpState = .none
                        pumpManager.notifyStateDidChange()
                    }

                    self.nextStep()
                }
            }
        #else
            guard let pumpManager = self.pumpManager else {
                nextStep()
                return
            }

            isDeactivating = true
            deactivationError = ""

            authenticate { success in
                guard success else {
                    DispatchQueue.main.async {
                        self.deactivationError = LocalizedString("Authentication failure", comment: "auth failed")
                    }
                    return
                }

                pumpManager.deactivatePatch { result in
                    DispatchQueue.main.async {
                        self.isDeactivating = false

                        if case let .failure(error) = result {
                            self.deactivationError = error.localizedDescription
                            return
                        }

                        self.nextStep()
                    }
                }
            }
        #endif
    }

    private func authenticate(success authSuccess: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        // check whether authentication is possible
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            // it's possible, so go ahead and use it
            let reason = "We need to unlock your data."

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                authSuccess(success)
            }
        } else {
            // no auth, automatically allow
            authSuccess(true)
        }
    }
}
