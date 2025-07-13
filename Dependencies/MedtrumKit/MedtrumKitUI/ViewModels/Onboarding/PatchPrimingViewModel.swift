import LoopKit

class PatchPrimingViewModel: ObservableObject {
    private let processQueue = DispatchQueue(label: "com.nightscout.medtrumkit.primingView")

    @Published var isPriming = false
    @Published var primeProgress: Double = 0
    @Published var primingError = ""
    @Published var is300u = false

    private let nextStep: () -> Void
    let previousStep: () -> Void
    private let done: () -> Void
    private let pumpManager: MedtrumPumpManager?
    init(
        _ pumpManager: MedtrumPumpManager?,
        _ nextStep: @escaping () -> Void,
        _ previousStep: @escaping () -> Void,
        _ done: @escaping () -> Void
    ) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep
        self.previousStep = previousStep
        self.done = done

        guard let pumpManager = self.pumpManager else {
            return
        }

        is300u = pumpManager.state.pumpName.contains("300U")
        pumpManager.addStatusObserver(self, queue: processQueue)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    func startPrime() {
        #if targetEnvironment(simulator)
            pumpManager?.state.sessionToken = Crypto.genSessionToken()
            pumpManager?.state.pumpState = .primed
            pumpManager?.notifyStateDidChange()
            nextStep()
        #else
            guard let pumpManager = self.pumpManager else {
                nextStep()
                return
            }

            isPriming = true
            primingError = ""
            pumpManager.primePatch { result in
                if case let .failure(error) = result {
                    DispatchQueue.main.async {
                        self.primingError = error.localizedDescription
                        self.isPriming = false
                    }
                    return
                }

                if pumpManager.state.pumpState.rawValue >= PatchState.primed.rawValue {
                    self.nextStep()
                    return
                }

                // Command send succesfully, now we have to wait till primeProgress has reached PatchState.primed or PatchState.active
            }
        #endif
    }
}

extension PatchPrimingViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _ pumpManager: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        #if targetEnvironment(simulator)
            DispatchQueue.main.async {
                self.isPriming = false
            }
        #else
            guard let pumpManager = self.pumpManager else {
                return
            }

            DispatchQueue.main.async {
                self.isPriming = pumpManager.state.pumpState == .priming
                self.primeProgress = Double(pumpManager.state.primeProgress) / 240

                if pumpManager.state.pumpState.rawValue > PatchState.priming.rawValue,
                   pumpManager.state.pumpState.rawValue < PatchState.active.rawValue
                {
                    self.nextStep()
                } else if pumpManager.state.pumpState.rawValue >= PatchState.active.rawValue {
                    // Patch already activated, ready to jump to settings
                    self.done()
                }
            }
        #endif
    }
}
