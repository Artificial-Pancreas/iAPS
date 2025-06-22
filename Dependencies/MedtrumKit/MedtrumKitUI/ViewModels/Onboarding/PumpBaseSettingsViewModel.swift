class PumpBaseSettingsViewModel: ObservableObject {
    @Published var is300u = false
    @Published var serialNumber: String = ""
    @Published var errorMessage: String = ""

    private let pumpManager: MedtrumPumpManager?
    private let nextStep: () -> Void
    public let pumpRemovalAction: () -> Void
    init(_ pumpManager: MedtrumPumpManager?, _ nextStep: @escaping () -> Void, _ pumpRemovalAction: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep
        self.pumpRemovalAction = pumpRemovalAction

        guard let pumpManager = pumpManager else {
            return
        }

        serialNumber = pumpManager.state.pumpSN.hexEncodedString().uppercased()
        if !pumpManager.state.pumpSN.isEmpty {
            // Only try to decrypt pumpSN if it is valid
            is300u = pumpManager.state.pumpName.contains("300U")
        }
    }

    func saveAndContinue() {
        guard serialNumber.count == 8 else {
            errorMessage = "Serial Number is too short"
            return
        }

        guard let snData = Data(hex: serialNumber), snData.count == 4 else {
            errorMessage = "Serial Number is invalid hex format"
            return
        }

        guard let pumpManager = pumpManager else {
            errorMessage = "Failed to connect to pump"
            return
        }
        pumpManager.state.pumpSN = snData
        guard pumpManager.state.model != "INVALID" else {
            errorMessage = "Incorrect serial number received"
            return
        }

        errorMessage = ""

        pumpManager.state.isOnboarded = true
        pumpManager.notifyStateDidChange()
        nextStep()
    }
}
