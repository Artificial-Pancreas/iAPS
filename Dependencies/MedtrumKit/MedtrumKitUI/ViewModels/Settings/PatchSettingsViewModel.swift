import LoopKit

class PatchSettingsViewModel: ObservableObject {
    @Published var maxHourlyInsulin: Double = 0 {
        didSet { checkDirtyState() }
    }

    @Published var maxDailyInsulin: Double = 0 {
        didSet { checkDirtyState() }
    }

    @Published var alarmSettings = Double(AlarmSettings.None.rawValue) {
        didSet { checkDirtyState() }
    }

    @Published var expirationTimer: Double = 1 {
        didSet { checkDirtyState() }
    }

    @Published var notificationAfterActivation: Double = 70 {
        didSet { checkDirtyState() }
    }

    @Published var isDirty: Bool = false
    @Published var is300u: Bool = false
    @Published var isUpdating = false
    @Published var errorMessage: String = ""

    let updatePatch: Bool
    let nextStep: (() -> Void)?

    private let processQueue = DispatchQueue(label: "com.nightscout.medtrumkit.patchSettingsViewModel")
    private let pumpManager: MedtrumPumpManager?
    init(_ pumpManager: MedtrumPumpManager?, updatePatch: Bool, nextStep: (() -> Void)?) {
        self.pumpManager = pumpManager
        self.updatePatch = updatePatch
        self.nextStep = nextStep

        guard let pumpManager = pumpManager else {
            return
        }

        updateState(pumpManager.state)
        pumpManager.addStatusObserver(self, queue: processQueue)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    var alarmOptions: [Double] {
        // Hide all options with light & vibrations
        // This feature is discontinued
        Array(6 ... 7).map({ Double($0) })
    }

    func save() {
        guard let pumpManager = pumpManager else {
            return
        }

        pumpManager.state.maxHourlyInsulin = maxHourlyInsulin
        pumpManager.state.maxDailyInsulin = maxDailyInsulin
        pumpManager.state.alarmSetting = AlarmSettings(rawValue: UInt8(alarmSettings)) ?? .None
        pumpManager.state.expirationTimer = UInt8(expirationTimer)
        pumpManager.state.notificationAfterActivation = .hours(notificationAfterActivation)
        pumpManager.notifyStateDidChange()

        NotificationManager.activatePatchExpiredNotification(after: .hours(notificationAfterActivation))

        guard updatePatch else {
            nextStep?()
            return
        }

        isUpdating = true
        pumpManager.updatePatchSettings { result in
            DispatchQueue.main.async {
                self.isUpdating = false
                switch result {
                case let .failure(error):
                    self.errorMessage = error.localizedDescription
                    return
                case .success:
                    self.nextStep?()
                    return
                }
            }
        }
    }

    func checkDirtyState() {
        guard let pumpManager = pumpManager else {
            return
        }

        DispatchQueue.main.async {
            self.isDirty = (
                pumpManager.state.maxDailyInsulin != self.maxDailyInsulin ||
                    pumpManager.state.maxHourlyInsulin != self.maxHourlyInsulin ||
                    pumpManager.state.alarmSetting.rawValue != UInt8(self.alarmSettings) ||
                    pumpManager.state.expirationTimer != UInt8(self.expirationTimer) ||
                    pumpManager.state.notificationAfterActivation.hours != self.notificationAfterActivation
            )
        }
    }
}

extension PatchSettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _ pumpManager: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = pumpManager as? MedtrumPumpManager else {
            return
        }

        updateState(pumpManager.state)
    }

    func updateState(_ state: MedtrumPumpState) {
        DispatchQueue.main.async {
            self.maxHourlyInsulin = state.maxHourlyInsulin
            self.maxDailyInsulin = state.maxDailyInsulin
            self.alarmSettings = Double(state.alarmSetting.rawValue)
            self.expirationTimer = Double(state.expirationTimer)
            self.notificationAfterActivation = state.notificationAfterActivation.hours

            if state.pumpSN.isEmpty {
                // If no serial number is available, we should show the options that are supported by both 200u & 300u
                self.is300u = false
            } else {
                self.is300u = state.pumpName.contains("300U")
            }
        }
    }
}
