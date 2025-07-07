import HealthKit
import LoopKit
import SwiftUI

enum PatchLifecycleState {
    case noPatch
    case active
    case expired
}

class MedtrumKitSettingsViewModel: ObservableObject, PumpManagerStatusObserver {
    private let processQueue = DispatchQueue(label: "com.nightscout.medtrumkit.settingsViewModel")

    @Published var pumpBaseSN: String = ""
    @Published var pumpName: String = ""
    @Published var model: String = ""
    @Published var patchId: UInt64 = 0
    @Published var is300u: Bool = false
    @Published var usingHeartbeatMode = false
    @Published var reservoirLevel: Double = 0
    @Published var battery: Double = 0
    @Published var maxReservoirLevel: Double = 1
    @Published var patchState: PatchState = .none
    @Published var patchStateString: String = PatchState.none.description
    @Published var basalType: BasalState = .active
    @Published var basalRate: Double = 0
    @Published var insulinType: InsulinType = .novolog
    @Published var lastSync = Date.distantPast
    @Published var patchLifecycleProgress: Double = 0
    @Published var patchLifecycleState: PatchLifecycleState = .noPatch
    @Published var patchActivatedAt = Date.distantPast
    @Published var patchExpiresAt = Date.distantFuture
    @Published var isConnected: Bool = false
    @Published var isReconnecting: Bool = false
    @Published var isUpdatingPumpState = false
    @Published var isUpdatingSuspend = false
    @Published var isUpdatingTempBasal = false
    @Published var showingHeartbeatWarning = false
    @Published var showingDeleteConfirmation = false
    @Published var previousPatch: PreviousPatch? = nil
    @Published var patchSessionToken: String? = nil

    public let patchSettingsViewModel: PatchSettingsViewModel

    let reservoirVolumeFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit())
        formatter.numberFormatter.minimumFractionDigits = 0
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()

    let batteryFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .volt())
        formatter.numberFormatter.minimumFractionDigits = 2
        formatter.numberFormatter.maximumFractionDigits = 2
        return formatter
    }()

    let basalRateFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.minimumIntegerDigits = 1
        return numberFormatter
    }()

    let dateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    let dateTimeFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    let deactivatePatchAction: () -> Void
    let pumpRemovalAction: () -> Void
    let pumpActivationAction: (Bool) -> Void
    private let log = MedtrumLogger(category: "settingsViewModel")
    private let pumpManager: MedtrumPumpManager?
    init(
        _ pumpManager: MedtrumPumpManager?,
        _ deactivatePatchAction: @escaping () -> Void,
        _ pumpActivationAction: @escaping (Bool) -> Void,
        _ pumpRemovalAction: @escaping () -> Void
    ) {
        self.pumpManager = pumpManager
        patchSettingsViewModel = PatchSettingsViewModel(pumpManager, updatePatch: true, nextStep: nil)
        self.deactivatePatchAction = deactivatePatchAction
        self.pumpActivationAction = pumpActivationAction
        self.pumpRemovalAction = pumpRemovalAction

        guard let pumpManager = pumpManager else {
            return
        }

        isConnected = pumpManager.bluetooth.isConnected
        updateState(pumpManager.state)
        pumpManager.addStatusObserver(self, queue: processQueue)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    func reservoirText(for units: Double) -> String {
        let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: units)
        return reservoirVolumeFormatter.string(from: quantity, for: .internationalUnit()) ?? ""
    }

    func batteryText(for voltage: Double) -> String {
        let quantity = HKQuantity(unit: .volt(), doubleValue: voltage)
        return batteryFormatter.string(from: quantity, for: .volt()) ?? ""
    }

    var patchLifecycleDays: Int? {
        guard patchLifecycleState == .active else {
            return nil
        }

        return Int((Date.now.timeIntervalSince1970 - patchActivatedAt.timeIntervalSince1970).days.rounded(.towardZero))
    }

    var patchLifecycleHours: Int? {
        guard patchLifecycleState == .active else {
            return nil
        }

        return Int(
            (Date.now.timeIntervalSince1970 - patchActivatedAt.timeIntervalSince1970).hours
                .truncatingRemainder(dividingBy: 24).rounded(.towardZero)
        )
    }

    var patchLifecycleMinutes: Int? {
        guard patchLifecycleState == .active else {
            return nil
        }

        return Int(
            (Date.now.timeIntervalSince1970 - patchActivatedAt.timeIntervalSince1970).minutes
                .truncatingRemainder(dividingBy: 60).rounded(.towardZero)
        )
    }

    func syncData() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        isUpdatingPumpState = true
        pumpManager.syncPumpData { _ in
            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
            }
        }
    }

    func didChangeInsulinType(_ newType: InsulinType?) {
        guard let type = newType else {
            return
        }

        pumpManager?.state.insulinType = type
        pumpManager?.notifyStateDidChange()
        insulinType = type
    }

    func stopUsingMedtrum() {
        guard let pumpManager = self.pumpManager else {
            pumpRemovalAction()
            return
        }

        pumpManager.notifyDelegateOfDeactivation {
            DispatchQueue.main.async {
                self.pumpRemovalAction()
            }
        }
    }

    func getLogs() -> [URL] {
        if let pumpManager = self.pumpManager {
            log.info(pumpManager.state.debugDescription)
        }
        return log.getDebugLogs()
    }

    func toPumpActivation() {
        guard let pumpManager = self.pumpManager else {
            pumpActivationAction(false)
            return
        }

        let alreadyPrimed = pumpManager.state.pumpState.rawValue >= PatchState.primed.rawValue
        pumpActivationAction(alreadyPrimed)
    }

    func toggleHeartbeat() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        pumpManager.state.usingHeartbeatMode.toggle()
        pumpManager.notifyStateDidChange()
        checkConnection()
    }

    func suspendResumeButtonPressed() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        isUpdatingSuspend = true
        if basalType == .suspended {
            pumpManager.resumeDelivery { error in
                DispatchQueue.main.async {
                    self.isUpdatingSuspend = false
                }

                if let error = error {
                    self.log.error("Failed to resume delivery: \(error)")
                }
            }

        } else {
            pumpManager.suspendDelivery { error in
                DispatchQueue.main.async {
                    self.isUpdatingSuspend = false
                }

                if let error = error {
                    self.log.error("Failed to suspend delivery: \(error)")
                }
            }
        }
    }

    func stopTempBasal() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        isUpdatingTempBasal = true
        pumpManager.enactTempBasal(unitsPerHour: 0, for: 0) { error in
            DispatchQueue.main.async {
                self.isUpdatingTempBasal = false
            }

            if let error = error {
                self.log.error("Failed to stop temp basal: \(error)")
            }
        }
    }

    func checkConnection() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        if pumpManager.state.usingHeartbeatMode, !pumpManager.bluetooth.isConnected {
            // Reconnect to patch
            isReconnecting = true
            pumpManager.bluetooth.ensureConnected { _ in
                DispatchQueue.main.async {
                    self.isReconnecting = false
                }
            }
            return
        }

        if !pumpManager.state.usingHeartbeatMode, pumpManager.bluetooth.isConnected {
            // Disconnect from patch
            pumpManager.bluetooth.disconnect()
            return
        }
    }
}

extension MedtrumKitSettingsViewModel {
    func pumpManager(
        _ pumpManager: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = pumpManager as? MedtrumPumpManager else {
            return
        }

        DispatchQueue.main.async {
            self.isConnected = pumpManager.bluetooth.isConnected
            self.updateState(pumpManager.state)
        }
    }

    private func updateState(_ state: MedtrumPumpState) {
        model = state.model
        switch model {
        case "MD8301":
            is300u = true
            maxReservoirLevel = 300
        default:
            is300u = false
            maxReservoirLevel = 200
        }

        pumpBaseSN = state.pumpSN.hexEncodedString().uppercased()
        pumpName = state.pumpName
        patchId = state.patchId.toUInt64()
        patchSessionToken = state.sessionToken.hexEncodedString()
        usingHeartbeatMode = state.usingHeartbeatMode
        patchState = state.pumpState
        patchStateString = state.pumpState.description
        reservoirLevel = state.reservoir
        basalType = state.basalState
        basalRate = basalType == .tempBasal ? (state.tempBasalUnits ?? state.currentBaseBasalRate) : state.currentBaseBasalRate
        lastSync = state.lastSync
        patchActivatedAt = state.patchActivatedAt
        patchExpiresAt = state.patchExpiresAt ?? state.patchActivatedAt.addingTimeInterval(.hours(80))
        battery = state.battery

        if !state.patchId.isEmpty {
            patchLifecycleProgress = min(
                (Date.now.timeIntervalSince1970 - state.patchActivatedAt.timeIntervalSince1970) / TimeInterval(days: 3),
                1
            )
            patchLifecycleState = patchLifecycleProgress == 1 ? .expired : .active
        } else {
            patchLifecycleState = .noPatch
        }

        if let insulinType = state.insulinType {
            self.insulinType = insulinType
        }

        if let previewPatchState = state.previousPatch {
            previousPatch = previewPatchState
        }
    }
}
